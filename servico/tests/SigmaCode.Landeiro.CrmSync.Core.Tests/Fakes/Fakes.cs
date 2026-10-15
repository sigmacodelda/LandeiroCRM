using SigmaCode.Landeiro.CrmSync.Core.Abstractions;
using SigmaCode.Landeiro.CrmSync.Core.Domain;

namespace SigmaCode.Landeiro.CrmSync.Core.Tests.Fakes;

/// <summary>Fila em memória que imita as regras da u_crmfila (estados, reserva, bloqueio de contas).</summary>
public sealed class FakeQueueStore : IQueueStore
{
    public sealed class Row
    {
        public required QueueItem Item { get; init; }
        public string Status { get; set; } = QueueStatus.Pending;
        public string? CrmId { get; set; }
        public string? Action { get; set; }
        public string? Message { get; set; }
        public int Attempts { get; set; }
    }

    private int _counter;
    public List<Row> Rows { get; } = new();

    /// <summary>Se definido, é chamado quando a fila é lida (para simular uma paragem a meio).</summary>
    public Action? OnClaim { get; set; }

    public Row Add(string entity, string sourceStamp, string code, string operation = QueueOperation.Upsert,
        string status = QueueStatus.Pending, string accountType = "CLI", string? origin = null)
    {
        origin ??= entity == "CONTA" ? "CL" : "U_CLCONTACT";
        var stamp = $"CRM{++_counter:D10}";
        var row = new Row { Item = new QueueItem(stamp, origin, entity, accountType, sourceStamp, code, operation), Status = status };
        Rows.Add(row);
        return row;
    }

    public Row Get(string sourceStamp, string entity) => Rows.Last(r => r.Item.SourceStamp == sourceStamp && r.Item.Entity == entity);

    public Task<int> RecoverProcessingAsync(CancellationToken ct)
    {
        var n = 0;
        foreach (var r in Rows.Where(r => r.Status == QueueStatus.Processing)) { r.Status = QueueStatus.Pending; n++; }
        return Task.FromResult(n);
    }

    public Task<IReadOnlyList<QueueItem>> GetPendingAsync(string entity, string accountType, IReadOnlyCollection<string> origins,
        string afterQueueStamp, int max, int minAgeSeconds, CancellationToken ct)
    {
        IReadOnlyList<QueueItem> result = Rows
            .Where(r => r.Status == QueueStatus.Pending && r.Item.Entity == entity && r.Item.AccountType == accountType
                        && origins.Contains(r.Item.Origin) && string.CompareOrdinal(r.Item.QueueStamp, afterQueueStamp) > 0)
            .OrderBy(r => r.Item.QueueStamp, StringComparer.Ordinal)
            .Take(max).Select(r => r.Item).ToList();
        return Task.FromResult(result);
    }

    public Task<IReadOnlySet<string>> GetBlockedSourceStampsAsync(string entity, string accountType,
        IReadOnlyCollection<string> sourceStamps, CancellationToken ct)
    {
        var blocked = new HashSet<string>(StringComparer.Ordinal);
        foreach (var s in sourceStamps)
        {
            var last = Rows.Where(r => r.Item.Entity == entity && r.Item.AccountType == accountType && r.Item.SourceStamp == s)
                .OrderBy(r => r.Item.QueueStamp, StringComparer.Ordinal).LastOrDefault();
            if (last is not null && last.Status is QueueStatus.Pending or QueueStatus.Processing or QueueStatus.Error) blocked.Add(s);
        }

        return Task.FromResult<IReadOnlySet<string>>(blocked);
    }

    public Task<IReadOnlyList<QueueItem>> ClaimAsync(IReadOnlyList<QueueItem> items, CancellationToken ct)
    {
        var claimed = new List<QueueItem>();
        foreach (var i in items)
        {
            var row = Rows.FirstOrDefault(r => r.Item.QueueStamp == i.QueueStamp && r.Status == QueueStatus.Pending);
            if (row is null) continue;
            row.Status = QueueStatus.Processing;
            row.Attempts++;
            claimed.Add(i);
        }

        OnClaim?.Invoke();
        return Task.FromResult<IReadOnlyList<QueueItem>>(claimed);
    }

    public Task SetResultsAsync(IReadOnlyList<QueueResult> results, CancellationToken ct)
    {
        foreach (var res in results)
        {
            var row = Rows.FirstOrDefault(r => r.Item.QueueStamp == res.Item.QueueStamp && r.Status == QueueStatus.Processing);
            if (row is null) continue;
            row.Status = res.Status;
            row.CrmId = res.CrmId;
            row.Action = res.Action;
            row.Message = res.Message;
        }

        return Task.CompletedTask;
    }
}

/// <summary>Views em memória: stamp -> linha.</summary>
public sealed class FakeSourceReader : ISourceReader
{
    public Dictionary<string, Dictionary<string, SourceRow>> Views { get; } = new();
    public Exception? ThrowOnRead { get; set; }

    public void Add(string view, string stamp, string? accountStamp, params (string Name, string Value)[] fields)
    {
        if (!Views.TryGetValue(view, out var rows)) Views[view] = rows = new Dictionary<string, SourceRow>();
        rows[stamp] = new SourceRow(stamp, accountStamp, fields.Select(f => new KeyValuePair<string, string>(f.Name, f.Value)).ToList());
    }

    public Task<IReadOnlyDictionary<string, SourceRow>> ReadAsync(string view, IReadOnlyCollection<string> stamps, CancellationToken ct)
    {
        if (ThrowOnRead is not null) throw ThrowOnRead;
        var rows = Views.TryGetValue(view, out var v) ? v : new Dictionary<string, SourceRow>();
        IReadOnlyDictionary<string, SourceRow> result = stamps.Where(rows.ContainsKey).ToDictionary(s => s, s => rows[s]);
        return Task.FromResult(result);
    }
}

/// <summary>API simulada: regista os pedidos e responde com o que o teste definir.</summary>
public sealed class FakeApi : ICrmApiClient
{
    public sealed record Call(string Endpoint, string Body);

    public List<Call> Calls { get; } = new();
    public Func<string, string, ApiCallResult>? Responder { get; set; }
    public Func<CancellationToken, Task>? BeforeResponse { get; set; }

    public async Task<ApiCallResult> PostAsync(string endpoint, string jsonBody, CancellationToken ct)
    {
        Calls.Add(new Call(endpoint, jsonBody));
        if (BeforeResponse is not null) await BeforeResponse(ct);
        ct.ThrowIfCancellationRequested();
        return Responder is not null ? Responder(endpoint, jsonBody) : OkAll(jsonBody, endpoint);
    }

    /// <summary>Responde 200 a todos os registos do pedido (usa os códigos enviados).</summary>
    public static ApiCallResult OkAll(string jsonBody, string endpoint)
    {
        using var doc = System.Text.Json.JsonDocument.Parse(jsonBody);
        var list = doc.RootElement.EnumerateObject().First();
        var key = endpoint == "ImportAccounts" ? "account" : "contact";
        var codeField = endpoint == "ImportAccounts" ? "code" : "contactCode";
        var entries = list.Value.EnumerateArray().Select((e, i) =>
            $"{{\"row\":{i},\"{key}\":\"{e.GetProperty(codeField).GetString()}\",\"action\":\"Updated\",\"id\":\"id-{i}\"}}");
        return new ApiCallResult(200, $"{{\"{list.Name}\":[{string.Join(",", entries)}],\"success\":{entries.Count()},\"fail\":0}}", null);
    }
}

public sealed class ListAuditLog : IAuditLog
{
    public List<AuditEntry> Entries { get; } = new();
    public void Write(AuditEntry entry) => Entries.Add(entry);
}
