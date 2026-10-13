using SigmaCode.Landeiro.CrmSync.Core.Abstractions;
using SigmaCode.Landeiro.CrmSync.Core.Config;
using SigmaCode.Landeiro.CrmSync.Core.Domain;
using SigmaCode.Landeiro.CrmSync.Core.Rules;

namespace SigmaCode.Landeiro.CrmSync.Core;

/// <summary>
/// Um ciclo de sincronização: percorre as origens configuradas (contas antes de contactos), lê a fila,
/// lê a view da origem, envia à API em lotes e atualiza a fila registo a registo.
/// Não conhece tabelas do PHC: tudo vem da configuração e das views.
/// </summary>
public sealed class SyncCycleRunner
{
    private const int MaxMessage = 500;

    private readonly SyncOptions _options;
    private readonly IQueueStore _store;
    private readonly ISourceReader _reader;
    private readonly ICrmApiClient _api;
    private readonly IAuditLog _log;

    public SyncCycleRunner(SyncOptions options, IQueueStore store, ISourceReader reader, ICrmApiClient api, IAuditLog log)
    {
        _options = options ?? throw new ArgumentNullException(nameof(options));
        _store = store ?? throw new ArgumentNullException(nameof(store));
        _reader = reader ?? throw new ArgumentNullException(nameof(reader));
        _api = api ?? throw new ArgumentNullException(nameof(api));
        _log = log ?? throw new ArgumentNullException(nameof(log));
    }

    /// <summary>No arranque: os registos que ficaram em A_PROCESSAR (queda do serviço) voltam a PENDENTE.</summary>
    public async Task<int> RecoverAsync(CancellationToken ct)
    {
        var recovered = await _store.RecoverProcessingAsync(ct).ConfigureAwait(false);
        if (recovered > 0)
        {
            _log.Write(new AuditEntry(AuditLevel.Warning, "-", "-", "-", "-", "RECUPERADO",
                $"{recovered} registo(s)", "Registos em A_PROCESSAR voltaram a PENDENTE depois de uma paragem do serviço"));
        }

        return recovered;
    }

    /// <summary>Um ciclo completo: todas as origens, pela ordem configurada (contas primeiro, depois contactos).</summary>
    public async Task<CycleSummary> RunCycleAsync(CancellationToken ct)
    {
        var summary = new CycleSummary();
        foreach (var source in _options.Sources.OrderBy(s => s.Order).ThenBy(s => s.Name, StringComparer.Ordinal))
        {
            ct.ThrowIfCancellationRequested();
            await ProcessSourceAsync(source, summary, ct).ConfigureAwait(false);
        }

        return summary;
    }

    private async Task ProcessSourceAsync(SourceOptions source, CycleSummary summary, CancellationToken ct)
    {
        // Paginação pelo stamp da fila: um registo que fica a esperar não é lido outra vez neste ciclo
        var after = string.Empty;
        while (true)
        {
            ct.ThrowIfCancellationRequested();
            var items = await _store
                .GetPendingAsync(source.Entity, source.AccountType, source.Origins, after, _options.BatchSize, ct)
                .ConfigureAwait(false);
            if (items.Count == 0) break;

            after = items[^1].QueueStamp;
            await ProcessBatchAsync(source, items, summary, ct).ConfigureAwait(false);

            if (items.Count < _options.BatchSize) break;
        }
    }

    private async Task ProcessBatchAsync(SourceOptions source, IReadOnlyList<QueueItem> items, CycleSummary summary, CancellationToken ct)
    {
        var batchId = Guid.NewGuid().ToString("D");
        var deletes = items.Where(i => i.Operation == QueueOperation.Delete).ToList();
        var upserts = items.Where(i => i.Operation != QueueOperation.Delete).ToList();

        // 1) Lê as linhas das views (só para quem vai ser enviado)
        IReadOnlyDictionary<string, SourceRow> rows = upserts.Count == 0
            ? new Dictionary<string, SourceRow>()
            : await _reader.ReadAsync(source.View, upserts.Select(i => i.SourceStamp).Distinct().ToList(), ct).ConfigureAwait(false);

        // 2) Contactos esperam pela conta quando esta está PENDENTE ou em ERRO na fila
        var ready = await FilterWaitingAsync(source, upserts, rows, summary, ct).ConfigureAwait(false);

        // 3) Reserva o lote (PENDENTE -> A_PROCESSAR): uma alteração feita agora cria novo PENDENTE e não se perde
        var claimed = await _store.ClaimAsync(deletes.Concat(ready).ToList(), ct).ConfigureAwait(false);
        if (claimed.Count == 0) return;
        summary.Batches++;

        var claimedStamps = claimed.Select(c => c.QueueStamp).ToHashSet(StringComparer.Ordinal);
        var results = new List<QueueResult>();

        try
        {
            // 4) Eliminações: a API não tem endpoint, por isso não se chama (SEM_ENVIO + log, para tratamento manual)
            foreach (var d in deletes.Where(x => claimedStamps.Contains(x.QueueStamp)))
            {
                results.Add(new QueueResult(d, QueueStatus.NotSent, null, null,
                    "Eliminação: a API não tem endpoint; tratar manualmente no CRM"));
                summary.NotSent++;
                _log.Write(new AuditEntry(AuditLevel.Warning, d.Origin, d.Entity, d.Code, d.SourceStamp, "SEM_ENVIO", string.Empty,
                    "Eliminação por tratar manualmente no CRM (a API não tem endpoint)"));
            }

            // 5) Registos que já não existem na view (apagados entretanto) ficam em ERRO
            var toSend = new List<(QueueItem Item, SourceRow Row)>();
            foreach (var u in ready.Where(x => claimedStamps.Contains(x.QueueStamp)))
            {
                if (rows.TryGetValue(u.SourceStamp, out var row)) toSend.Add((u, row));
                else
                {
                    results.Add(new QueueResult(u, QueueStatus.Error, null, null, "Registo não encontrado na view (removido entretanto?)"));
                    summary.Errors++;
                    _log.Write(new AuditEntry(AuditLevel.Error, u.Origin, u.Entity, u.Code, u.SourceStamp, "ERRO", string.Empty,
                        "Registo não encontrado na view"));
                }
            }

            // 6) Envia o lote à API e interpreta a resposta registo a registo
            if (toSend.Count > 0) await SendAsync(source, toSend, batchId, results, summary, ct).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            // O serviço está a parar a meio do lote: os registos ficam A_PROCESSAR e são recuperados no próximo arranque
            throw;
        }
        catch (Exception ex)
        {
            // Qualquer falha inesperada: o que ainda não tem resultado passa a ERRO (sem reprocessamento automático)
            var message = $"Erro inesperado no serviço: {ex.GetType().Name}";
            foreach (var c in claimed.Where(c => results.All(r => r.Item.QueueStamp != c.QueueStamp)))
            {
                results.Add(new QueueResult(c, QueueStatus.Error, null, null, message));
                summary.Errors++;
                _log.Write(new AuditEntry(AuditLevel.Error, c.Origin, c.Entity, c.Code, c.SourceStamp, "ERRO", string.Empty, message));
            }
        }

        await _store.SetResultsAsync(results, ct).ConfigureAwait(false);
    }

    /// <summary>Tira do lote os registos que dependem de uma conta ainda PENDENTE ou em ERRO (ficam PENDENTE para o ciclo seguinte).</summary>
    private async Task<IReadOnlyList<QueueItem>> FilterWaitingAsync(
        SourceOptions source, List<QueueItem> upserts, IReadOnlyDictionary<string, SourceRow> rows, CycleSummary summary, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(source.WaitsForEntity) || upserts.Count == 0) return upserts;

        var accountStamps = rows.Values
            .Select(r => r.AccountStamp)
            .Where(s => !string.IsNullOrWhiteSpace(s))
            .Select(s => s!)
            .Distinct()
            .ToList();
        if (accountStamps.Count == 0) return upserts;

        var blocked = await _store
            .GetBlockedSourceStampsAsync(source.WaitsForEntity, source.AccountType, accountStamps, ct)
            .ConfigureAwait(false);
        if (blocked.Count == 0) return upserts;

        var ready = new List<QueueItem>();
        foreach (var item in upserts)
        {
            if (rows.TryGetValue(item.SourceStamp, out var row) && row.AccountStamp is not null && blocked.Contains(row.AccountStamp))
            {
                summary.WaitingForAccount++;
                _log.Write(new AuditEntry(AuditLevel.Info, item.Origin, item.Entity, item.Code, item.SourceStamp, "AGUARDA_CONTA", string.Empty,
                    "A conta deste registo está PENDENTE ou em ERRO; fica para o ciclo seguinte"));
            }
            else
            {
                ready.Add(item);
            }
        }

        return ready;
    }

    private async Task SendAsync(
        SourceOptions source, List<(QueueItem Item, SourceRow Row)> toSend, string batchId,
        List<QueueResult> results, CycleSummary summary, CancellationToken ct)
    {
        var limits = _options.FieldLimits.TryGetValue(source.Entity, out var l) ? l : null;
        var payload = PayloadBuilder.Build(source.RequestListProperty, toSend.Select(x => x.Row).ToList(), limits);

        foreach (var w in payload.Warnings)
        {
            summary.Truncations++;
            var owner = toSend.First(x => x.Row.Stamp == w.SourceStamp).Item;
            _log.Write(new AuditEntry(AuditLevel.Warning, owner.Origin, owner.Entity, owner.Code, owner.SourceStamp, "TRUNCADO",
                $"campo={w.Field}", $"Valor acima do limite do CRM ({w.Limit}) truncado"));
        }

        var call = await _api.PostAsync(source.Endpoint, payload.Json, ct).ConfigureAwait(false);
        var outcome = ApiResponseInterpreter.Interpret(
            call, toSend.Select(x => x.Item.Code).ToList(), source.ResponseListProperty, source.ResponseCodeProperty);

        // Falhas de rede e de autenticação ficam em destaque no log (o pedido nem chegou a ser processado)
        if (outcome.Kind is BatchFailureKind.Network or BatchFailureKind.Authentication)
        {
            _log.Write(new AuditEntry(AuditLevel.Error, source.Name, source.Entity, "*", batchId,
                outcome.Kind == BatchFailureKind.Network ? "FALHA_REDE" : "FALHA_AUTENTICACAO",
                $"registos={toSend.Count}", outcome.Items[0].Message ?? string.Empty));
        }

        for (var i = 0; i < toSend.Count; i++)
        {
            var (item, _) = toSend[i];
            var o = outcome.Items[i];
            if (o.Success)
            {
                results.Add(new QueueResult(item, QueueStatus.Sent, o.CrmId, o.Action, null));
                summary.Sent++;
                _log.Write(new AuditEntry(AuditLevel.Info, item.Origin, item.Entity, item.Code, item.SourceStamp, "ENVIADO",
                    $"{o.Action}/{o.CrmId}", string.Empty));
            }
            else
            {
                var message = Limit(o.Message);
                results.Add(new QueueResult(item, QueueStatus.Error, o.CrmId, o.Action, message));
                summary.Errors++;
                _log.Write(new AuditEntry(AuditLevel.Error, item.Origin, item.Entity, item.Code, item.SourceStamp, "ERRO",
                    $"{o.Action}/{o.CrmId}", message));
            }
        }
    }

    private static string Limit(string? text)
    {
        if (string.IsNullOrEmpty(text)) return string.Empty;
        return text.Length <= MaxMessage ? text : text[..MaxMessage];
    }
}
