namespace SigmaCode.Landeiro.CrmSync.Core.Domain;

/// <summary>Estados de um registo da fila (coluna estado da u_crmfila).</summary>
public static class QueueStatus
{
    public const string Pending = "PENDENTE";
    public const string Processing = "A_PROCESSAR";
    public const string Sent = "ENVIADO";
    public const string Error = "ERRO";
    public const string NotSent = "SEM_ENVIO";
}

/// <summary>Operações de um registo da fila: U = criação/alteração (upsert), D = eliminação.</summary>
public static class QueueOperation
{
    public const string Upsert = "U";
    public const string Delete = "D";
}

/// <summary>Um registo da fila. Só identificadores: nunca dados pessoais.</summary>
public sealed record QueueItem(
    string QueueStamp,
    string Origin,
    string Entity,
    string AccountType,
    string SourceStamp,
    string Code,
    string Operation);

/// <summary>O que o serviço decidiu para um registo da fila depois de processado.</summary>
public sealed record QueueResult(QueueItem Item, string Status, string? CrmId, string? Action, string? Message);

/// <summary>
/// Uma linha lida de uma view: o stamp de ligação à fila, o stamp da conta (só nos contactos)
/// e os campos da API, já pela ordem e com os nomes que a view define.
/// </summary>
public sealed record SourceRow(string Stamp, string? AccountStamp, IReadOnlyList<KeyValuePair<string, string>> Fields);

/// <summary>Resultado bruto de uma chamada à API. StatusCode nulo = o pedido nem chegou a ser respondido (rede/timeout).</summary>
public sealed record ApiCallResult(int? StatusCode, string? Body, string? Error);

/// <summary>Resultado da API para um registo do lote.</summary>
public sealed record ItemOutcome(bool Success, string? CrmId, string? Action, string? Message);

/// <summary>Tipo de falha de um lote (para destacar no log o que é rede e autenticação).</summary>
public enum BatchFailureKind
{
    None,
    Partial,
    InvalidRequest,
    Authentication,
    Network,
    Server,
    InvalidResponse,
}

/// <summary>Resultado de um lote: um ItemOutcome por registo enviado, pela mesma ordem do pedido.</summary>
public sealed record BatchOutcome(IReadOnlyList<ItemOutcome> Items, BatchFailureKind Kind);

public enum AuditLevel
{
    Info,
    Warning,
    Error,
}

/// <summary>Uma linha do log diário. Sem token, sem connection string e sem dados pessoais.</summary>
public sealed record AuditEntry(
    AuditLevel Level,
    string Origin,
    string Entity,
    string Code,
    string Stamp,
    string Result,
    string Detail,
    string Message);

/// <summary>Contadores de um ciclo, para o log e para os testes.</summary>
public sealed class CycleSummary
{
    public int Batches { get; set; }
    public int Sent { get; set; }
    public int Errors { get; set; }
    public int NotSent { get; set; }
    public int WaitingForAccount { get; set; }
    public int Truncations { get; set; }
    public int Recovered { get; set; }
}
