using SigmaCode.Landeiro.CrmSync.Core.Domain;

namespace SigmaCode.Landeiro.CrmSync.Core.Abstractions;

/// <summary>Acesso à fila (u_crmfila). O Core não sabe como é implementada.</summary>
public interface IQueueStore
{
    /// <summary>No arranque: os registos que ficaram em A_PROCESSAR (queda do serviço) voltam a PENDENTE. Devolve quantos.</summary>
    Task<int> RecoverProcessingAsync(CancellationToken ct);

    /// <summary>
    /// Registos PENDENTE de uma entidade e tipo de conta, só das origens indicadas, por ordem de criação,
    /// com o stamp da fila maior que <paramref name="afterQueueStamp"/> (paginação).
    /// </summary>
    Task<IReadOnlyList<QueueItem>> GetPendingAsync(
        string entity, string accountType, IReadOnlyCollection<string> origins,
        string afterQueueStamp, int max, int minAgeSeconds, CancellationToken ct);

    /// <summary>
    /// Dos stamps de conta indicados, devolve os que estão "bloqueados": o último registo da fila dessa conta
    /// está PENDENTE, A_PROCESSAR ou em ERRO. Os contactos dessas contas esperam.
    /// </summary>
    Task<IReadOnlySet<string>> GetBlockedSourceStampsAsync(
        string entity, string accountType, IReadOnlyCollection<string> sourceStamps, CancellationToken ct);

    /// <summary>
    /// Dos stamps indicados, devolve os que já foram enviados ao CRM alguma vez (têm um registo ENVIADO de alteração).
    /// Serve para decidir se uma eliminação precisa de inativar algo no CRM.
    /// </summary>
    Task<IReadOnlySet<string>> GetEverSentSourceStampsAsync(
        string entity, string accountType, IReadOnlyCollection<string> sourceStamps, CancellationToken ct);

    /// <summary>Passa os registos de PENDENTE a A_PROCESSAR. Devolve só os que foram mesmo reservados.</summary>
    Task<IReadOnlyList<QueueItem>> ClaimAsync(IReadOnlyList<QueueItem> items, CancellationToken ct);

    /// <summary>Grava o estado final de cada registo (só os que estão em A_PROCESSAR).</summary>
    Task SetResultsAsync(IReadOnlyList<QueueResult> results, CancellationToken ct);
}

/// <summary>Leitura das views das origens. Devolve as linhas já pelos nomes da API.</summary>
public interface ISourceReader
{
    /// <summary>Lê da view as linhas cujo stamp está na lista. Chave do resultado = stamp de ligação à fila.</summary>
    Task<IReadOnlyDictionary<string, SourceRow>> ReadAsync(string view, IReadOnlyCollection<string> stamps, CancellationToken ct);
}

/// <summary>Cliente da API Somnia CRM.</summary>
public interface ICrmApiClient
{
    /// <summary>
    /// Faz o POST ao endpoint. Falhas de rede e timeouts NÃO lançam exceção: voltam com StatusCode nulo.
    /// Só o cancelamento do serviço lança OperationCanceledException.
    /// </summary>
    Task<ApiCallResult> PostAsync(string endpoint, string jsonBody, CancellationToken ct);
}

/// <summary>Log diário em ficheiro.</summary>
public interface IAuditLog
{
    void Write(AuditEntry entry);
}

/// <summary>Garante uma só instância do serviço (applock da base de dados).</summary>
public interface IInstanceLock : IAsyncDisposable
{
    /// <summary>Devolve true se esta instância detém o bloqueio (adquire-o se ainda não o tem).</summary>
    Task<bool> EnsureAcquiredAsync(CancellationToken ct);
}
