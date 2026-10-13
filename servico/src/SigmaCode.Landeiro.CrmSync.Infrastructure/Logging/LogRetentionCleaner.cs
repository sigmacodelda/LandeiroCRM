using System.Globalization;

namespace SigmaCode.Landeiro.CrmSync.Infrastructure.Logging;

/// <summary>
/// Apaga os ficheiros de log com mais de N dias (a data vem do nome do ficheiro).
/// Só mexe em ficheiros crmsync-AAAAMMDD.log: qualquer outro ficheiro da pasta fica como está.
/// A fila nunca é limpa por aqui.
/// </summary>
public static class LogRetentionCleaner
{
    public static int Clean(string directory, int retentionDays, TimeProvider? time = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(directory);
        if (retentionDays < 1) throw new ArgumentOutOfRangeException(nameof(retentionDays), "A retenção tem de ser de pelo menos 1 dia.");
        if (!Directory.Exists(directory)) return 0;

        var today = (time ?? TimeProvider.System).GetLocalNow().Date;
        var deleted = 0;

        foreach (var path in Directory.EnumerateFiles(directory, $"{DailyFileAuditLog.FilePrefix}*{DailyFileAuditLog.FileExtension}"))
        {
            var name = Path.GetFileNameWithoutExtension(path)[DailyFileAuditLog.FilePrefix.Length..];
            if (!DateTime.TryParseExact(name, "yyyyMMdd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var fileDate)) continue;

            // "Mais de N dias": com N = 7, o ficheiro de há 7 dias fica e o de há 8 apaga-se
            if ((today - fileDate.Date).TotalDays > retentionDays)
            {
                try
                {
                    File.Delete(path);
                    deleted++;
                }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
                {
                    // Ficheiro em uso: fica para a próxima limpeza
                }
            }
        }

        return deleted;
    }
}
