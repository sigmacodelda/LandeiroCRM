using System.Data;
using Microsoft.Data.SqlClient;
using SigmaCode.Landeiro.CrmSync.Core.Abstractions;
using SigmaCode.Landeiro.CrmSync.Core.Domain;

namespace SigmaCode.Landeiro.CrmSync.Infrastructure.Sql;

/// <summary>
/// Fila u_crmfila em SQL Server. Todas as queries são parametrizadas.
/// O serviço só lê e atualiza a fila (não insere nem apaga): quem insere são os triggers.
/// </summary>
public sealed class SqlQueueStore : IQueueStore
{
    private const int MaxMessage = 500;
    private readonly string _connectionString;

    public SqlQueueStore(string connectionString)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(connectionString);
        _connectionString = connectionString;
    }

    private async Task<SqlConnection> OpenAsync(CancellationToken ct)
    {
        var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(ct).ConfigureAwait(false);
        return connection;
    }

    public async Task<int> RecoverProcessingAsync(CancellationToken ct)
    {
        const string sql = @"
UPDATE dbo.u_crmfila
   SET estado = @pendente, ultimamensagem = @msg,
       usrdata = GETDATE(), usrhora = CONVERT(varchar(8), GETDATE(), 108)
 WHERE estado = @processar";

        await using var connection = await OpenAsync(ct).ConfigureAwait(false);
        await using var cmd = new SqlCommand(sql, connection);
        cmd.Parameters.AddWithValue("@pendente", QueueStatus.Pending);
        cmd.Parameters.AddWithValue("@processar", QueueStatus.Processing);
        cmd.Parameters.AddWithValue("@msg", "Recuperado de A_PROCESSAR depois de uma paragem do serviço");
        return await cmd.ExecuteNonQueryAsync(ct).ConfigureAwait(false);
    }

    public async Task<IReadOnlyList<QueueItem>> GetPendingAsync(
        string entity, string accountType, IReadOnlyCollection<string> origins,
        string afterQueueStamp, int max, int minAgeSeconds, CancellationToken ct)
    {
        if (origins.Count == 0) return Array.Empty<QueueItem>();

        await using var connection = await OpenAsync(ct).ConfigureAwait(false);
        await using var cmd = new SqlCommand { Connection = connection };
        var originParams = AddList(cmd, "o", origins);
        cmd.CommandText = $@"
SELECT TOP (@max)
       RTRIM(u_crmfilastamp), RTRIM(origem), RTRIM(entidade), RTRIM(tipoconta),
       RTRIM(stamporigem), RTRIM(codigo), RTRIM(operacao)
  FROM dbo.u_crmfila WITH (NOLOCK)
 WHERE estado = @pendente AND entidade = @entidade AND tipoconta = @tipoconta
   AND origem IN ({originParams}) AND u_crmfilastamp > @depois
   AND datacriacao <= DATEADD(SECOND, -@atraso, GETDATE())
 ORDER BY u_crmfilastamp";
        cmd.Parameters.AddWithValue("@max", max);
        cmd.Parameters.AddWithValue("@pendente", QueueStatus.Pending);
        cmd.Parameters.AddWithValue("@entidade", entity);
        cmd.Parameters.AddWithValue("@tipoconta", accountType);
        cmd.Parameters.AddWithValue("@depois", afterQueueStamp);
        cmd.Parameters.AddWithValue("@atraso", minAgeSeconds);

        var items = new List<QueueItem>();
        await using var reader = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
        while (await reader.ReadAsync(ct).ConfigureAwait(false))
        {
            items.Add(new QueueItem(reader.GetString(0), reader.GetString(1), reader.GetString(2), reader.GetString(3),
                reader.GetString(4), reader.GetString(5), reader.GetString(6)));
        }

        return items;
    }

    public async Task<IReadOnlySet<string>> GetBlockedSourceStampsAsync(
        string entity, string accountType, IReadOnlyCollection<string> sourceStamps, CancellationToken ct)
    {
        var blocked = new HashSet<string>(StringComparer.Ordinal);
        if (sourceStamps.Count == 0) return blocked;

        await using var connection = await OpenAsync(ct).ConfigureAwait(false);
        await using var cmd = new SqlCommand { Connection = connection };
        var stampParams = AddList(cmd, "s", sourceStamps);
        // Só conta o ÚLTIMO registo da fila de cada conta: um ERRO antigo já resolvido não bloqueia
        cmd.CommandText = $@"
SELECT DISTINCT RTRIM(f.stamporigem)
  FROM dbo.u_crmfila AS f WITH (NOLOCK)
 WHERE f.entidade = @entidade AND f.tipoconta = @tipoconta AND f.stamporigem IN ({stampParams})
   AND f.estado IN (@pendente, @processar, @erro)
   AND f.u_crmfilastamp = (SELECT MAX(x.u_crmfilastamp) FROM dbo.u_crmfila AS x WITH (NOLOCK)
                            WHERE x.entidade = f.entidade AND x.tipoconta = f.tipoconta AND x.stamporigem = f.stamporigem)";
        cmd.Parameters.AddWithValue("@entidade", entity);
        cmd.Parameters.AddWithValue("@tipoconta", accountType);
        cmd.Parameters.AddWithValue("@pendente", QueueStatus.Pending);
        cmd.Parameters.AddWithValue("@processar", QueueStatus.Processing);
        cmd.Parameters.AddWithValue("@erro", QueueStatus.Error);

        await using var reader = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
        while (await reader.ReadAsync(ct).ConfigureAwait(false)) blocked.Add(reader.GetString(0));
        return blocked;
    }

    public async Task<IReadOnlySet<string>> GetEverSentSourceStampsAsync(
        string entity, string accountType, IReadOnlyCollection<string> sourceStamps, CancellationToken ct)
    {
        var sent = new HashSet<string>(StringComparer.Ordinal);
        if (sourceStamps.Count == 0) return sent;

        await using var connection = await OpenAsync(ct).ConfigureAwait(false);
        await using var cmd = new SqlCommand { Connection = connection };
        var stampParams = AddList(cmd, "s", sourceStamps);
        // Já enviado = existe um registo ENVIADO de criação/alteração (U) desta entidade e stamp
        cmd.CommandText = $@"
SELECT DISTINCT RTRIM(f.stamporigem)
  FROM dbo.u_crmfila AS f WITH (NOLOCK)
 WHERE f.entidade = @entidade AND f.tipoconta = @tipoconta AND f.stamporigem IN ({stampParams})
   AND f.estado = @enviado AND f.operacao = 'U'";
        cmd.Parameters.AddWithValue("@entidade", entity);
        cmd.Parameters.AddWithValue("@tipoconta", accountType);
        cmd.Parameters.AddWithValue("@enviado", QueueStatus.Sent);

        await using var reader = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
        while (await reader.ReadAsync(ct).ConfigureAwait(false)) sent.Add(reader.GetString(0));
        return sent;
    }

    public async Task<IReadOnlyList<QueueItem>> ClaimAsync(IReadOnlyList<QueueItem> items, CancellationToken ct)
    {
        if (items.Count == 0) return Array.Empty<QueueItem>();

        await using var connection = await OpenAsync(ct).ConfigureAwait(false);
        await using var cmd = new SqlCommand { Connection = connection };
        var stampParams = AddList(cmd, "q", items.Select(i => i.QueueStamp).ToList());
        // Só passa a A_PROCESSAR o que ainda está PENDENTE (outra coisa já o tocou? então não o reserva)
        cmd.CommandText = $@"
UPDATE dbo.u_crmfila
   SET estado = @processar, tentativas = tentativas + 1,
       usrdata = GETDATE(), usrhora = CONVERT(varchar(8), GETDATE(), 108)
OUTPUT RTRIM(inserted.u_crmfilastamp)
 WHERE estado = @pendente AND u_crmfilastamp IN ({stampParams})";
        cmd.Parameters.AddWithValue("@processar", QueueStatus.Processing);
        cmd.Parameters.AddWithValue("@pendente", QueueStatus.Pending);

        var claimedStamps = new HashSet<string>(StringComparer.Ordinal);
        await using (var reader = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false))
        {
            while (await reader.ReadAsync(ct).ConfigureAwait(false)) claimedStamps.Add(reader.GetString(0));
        }

        return items.Where(i => claimedStamps.Contains(i.QueueStamp)).ToList();
    }

    public async Task SetResultsAsync(IReadOnlyList<QueueResult> results, CancellationToken ct)
    {
        if (results.Count == 0) return;

        const string sql = @"
UPDATE dbo.u_crmfila
   SET estado = @estado, idcrm = @idcrm, acaocrm = @acao,
       -- um envio com sucesso (mensagem vazia) mantém a mensagem do erro anterior: fica o histórico da reposição
       ultimamensagem = CASE WHEN @msg = '' THEN ultimamensagem ELSE @msg END,
       dataenvio = CASE WHEN @estado IN (@enviado, @erro) THEN GETDATE() ELSE dataenvio END,
       usrdata = GETDATE(), usrhora = CONVERT(varchar(8), GETDATE(), 108)
 WHERE u_crmfilastamp = @stamp AND estado = @processar";

        await using var connection = await OpenAsync(ct).ConfigureAwait(false);
        // Uma transação para o lote todo: ou ficam todos gravados, ou nenhum (e recupera no arranque)
        await using var tx = (SqlTransaction)await connection.BeginTransactionAsync(ct).ConfigureAwait(false);
        foreach (var r in results)
        {
            await using var cmd = new SqlCommand(sql, connection, tx);
            cmd.Parameters.AddWithValue("@estado", r.Status);
            cmd.Parameters.AddWithValue("@idcrm", Truncate(r.CrmId, 60));
            cmd.Parameters.AddWithValue("@acao", Truncate(r.Action, 30));
            cmd.Parameters.AddWithValue("@msg", Truncate(r.Message, MaxMessage));
            cmd.Parameters.AddWithValue("@stamp", r.Item.QueueStamp);
            cmd.Parameters.AddWithValue("@enviado", QueueStatus.Sent);
            cmd.Parameters.AddWithValue("@erro", QueueStatus.Error);
            cmd.Parameters.AddWithValue("@processar", QueueStatus.Processing);
            await cmd.ExecuteNonQueryAsync(ct).ConfigureAwait(false);
        }

        await tx.CommitAsync(ct).ConfigureAwait(false);
    }

    /// <summary>Acrescenta parâmetros @prefixo0, @prefixo1... e devolve o texto "@prefixo0,@prefixo1,...".</summary>
    internal static string AddList(SqlCommand cmd, string prefix, IEnumerable<string> values)
    {
        var names = new List<string>();
        var i = 0;
        foreach (var v in values)
        {
            var name = $"@{prefix}{i++}";
            cmd.Parameters.Add(new SqlParameter(name, SqlDbType.VarChar, 100) { Value = v });
            names.Add(name);
        }

        return string.Join(",", names);
    }

    private static string Truncate(string? text, int max)
    {
        if (string.IsNullOrEmpty(text)) return string.Empty;
        return text.Length <= max ? text : text[..max];
    }
}
