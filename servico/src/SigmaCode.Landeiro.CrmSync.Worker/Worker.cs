using SigmaCode.Landeiro.CrmSync.Core;
using SigmaCode.Landeiro.CrmSync.Core.Abstractions;
using SigmaCode.Landeiro.CrmSync.Core.Config;
using SigmaCode.Landeiro.CrmSync.Core.Domain;
using SigmaCode.Landeiro.CrmSync.Infrastructure.Logging;

namespace SigmaCode.Landeiro.CrmSync.Worker;

/// <summary>
/// Ciclo do serviço: de X em X tempo garante a instância única, recupera o que ficou a meio, corre um ciclo
/// de sincronização e limpa os logs antigos. Qualquer falha de um ciclo é registada e o serviço continua.
/// </summary>
public sealed class Worker : BackgroundService
{
    private readonly SyncCycleRunner _runner;
    private readonly IInstanceLock _instanceLock;
    private readonly IAuditLog _audit;
    private readonly SyncOptions _options;
    private readonly string _logDirectory;
    private readonly ILogger<Worker> _logger;

    public Worker(SyncCycleRunner runner, IInstanceLock instanceLock, IAuditLog audit, SyncOptions options,
        string logDirectory, ILogger<Worker> logger)
    {
        _runner = runner;
        _instanceLock = instanceLock;
        _audit = audit;
        _options = options;
        _logDirectory = logDirectory;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var interval = TimeSpan.FromMinutes(_options.IntervalMinutes);
        var hadLock = false;
        _audit.Write(new AuditEntry(AuditLevel.Info, "-", "-", "-", "-", "ARRANQUE", $"intervalo={interval.TotalMinutes:0.##}min", "Serviço iniciado"));

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                if (!await _instanceLock.EnsureAcquiredAsync(stoppingToken).ConfigureAwait(false))
                {
                    hadLock = false;
                    _audit.Write(new AuditEntry(AuditLevel.Warning, "-", "-", "-", "-", "SEM_BLOQUEIO", string.Empty,
                        "Outra instância está a correr ou a base de dados está indisponível; este ciclo não processa nada"));
                }
                else
                {
                    // Sempre que se (re)obtém o bloqueio, o que está A_PROCESSAR é de uma execução que caiu
                    if (!hadLock)
                    {
                        await _runner.RecoverAsync(stoppingToken).ConfigureAwait(false);
                        hadLock = true;
                    }

                    var summary = await _runner.RunCycleAsync(stoppingToken).ConfigureAwait(false);
                    if (summary.Batches > 0 || summary.NotSent > 0 || summary.WaitingForAccount > 0)
                    {
                        _audit.Write(new AuditEntry(AuditLevel.Info, "-", "-", "-", "-", "CICLO",
                            $"lotes={summary.Batches} enviados={summary.Sent} erros={summary.Errors} sem_envio={summary.NotSent} a_aguardar={summary.WaitingForAccount} truncados={summary.Truncations}",
                            "Ciclo concluído"));
                    }

                    var deleted = LogRetentionCleaner.Clean(_logDirectory, _options.LogRetentionDays);
                    if (deleted > 0)
                        _audit.Write(new AuditEntry(AuditLevel.Info, "-", "-", "-", "-", "LOGS_APAGADOS", $"{deleted} ficheiro(s)", $"Logs com mais de {_options.LogRetentionDays} dias apagados"));
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                // Um ciclo falhou (ex.: base de dados em baixo): regista e tenta no próximo
                _audit.Write(new AuditEntry(AuditLevel.Error, "-", "-", "-", "-", "CICLO_FALHOU", ex.GetType().Name, "O ciclo falhou; nova tentativa no próximo intervalo"));
                _logger.LogError(ex, "O ciclo de sincronização falhou");
            }

            try
            {
                await Task.Delay(interval, stoppingToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }

        _audit.Write(new AuditEntry(AuditLevel.Info, "-", "-", "-", "-", "PARAGEM", string.Empty, "Serviço parado"));
    }

    public override async Task StopAsync(CancellationToken cancellationToken)
    {
        await base.StopAsync(cancellationToken).ConfigureAwait(false);
        await _instanceLock.DisposeAsync().ConfigureAwait(false);   // liberta o applock
    }
}
