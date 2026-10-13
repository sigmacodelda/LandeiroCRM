using System.Text;
using SigmaCode.Landeiro.CrmSync.Core.Abstractions;
using SigmaCode.Landeiro.CrmSync.Core.Domain;

namespace SigmaCode.Landeiro.CrmSync.Infrastructure.Logging;

/// <summary>
/// Log diário em ficheiro (crmsync-AAAAMMDD.log): data/hora, nível, origem, entidade, código, stamp,
/// resultado, ação/id do CRM e mensagem. Nunca escreve o token, a connection string nem dados pessoais:
/// quem chama só lhe entrega identificadores e mensagens.
/// </summary>
public sealed class DailyFileAuditLog : IAuditLog
{
    public const string FilePrefix = "crmsync-";
    public const string FileExtension = ".log";

    private readonly string _directory;
    private readonly TimeProvider _time;
    private readonly object _gate = new();

    public DailyFileAuditLog(string directory, TimeProvider? time = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(directory);
        _directory = directory;
        _time = time ?? TimeProvider.System;
    }

    public static string FileNameFor(DateTime localDate) => $"{FilePrefix}{localDate:yyyyMMdd}{FileExtension}";

    public void Write(AuditEntry entry)
    {
        ArgumentNullException.ThrowIfNull(entry);

        var now = _time.GetLocalNow().DateTime;
        var level = entry.Level switch { AuditLevel.Info => "INFO", AuditLevel.Warning => "AVISO", _ => "ERRO" };
        var line = string.Join(" | ",
            now.ToString("yyyy-MM-dd HH:mm:ss.fff", System.Globalization.CultureInfo.InvariantCulture),
            level, Clean(entry.Origin), Clean(entry.Entity), Clean(entry.Code), Clean(entry.Stamp),
            Clean(entry.Result), Clean(entry.Detail), Clean(entry.Message));

        try
        {
            lock (_gate)
            {
                Directory.CreateDirectory(_directory);
                File.AppendAllText(Path.Combine(_directory, FileNameFor(now)), line + Environment.NewLine, Encoding.UTF8);
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Um problema de escrita do log não pode parar a sincronização
            Console.Error.WriteLine($"Não foi possível escrever o log: {ex.GetType().Name}");
        }
    }

    /// <summary>Mantém cada entrada numa só linha e sem o separador do formato.</summary>
    private static string Clean(string? text) =>
        string.IsNullOrEmpty(text) ? "-" : text.Replace('\r', ' ').Replace('\n', ' ').Replace('|', '/');
}
