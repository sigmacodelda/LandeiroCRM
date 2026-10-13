using System.Globalization;
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;
using SigmaCode.Landeiro.CrmSync.Core.Abstractions;
using SigmaCode.Landeiro.CrmSync.Core.Domain;

namespace SigmaCode.Landeiro.CrmSync.Infrastructure.Sql;

/// <summary>
/// Lê as views das origens. Não conhece tabelas do PHC: lê o que a view devolver.
/// Convenção das views: coluna "stamp" (ligação à fila) e, nos contactos, "accountStamp".
/// Todas as outras colunas são campos da API e seguem pela ordem da view.
/// </summary>
public sealed partial class SqlSourceReader : ISourceReader
{
    public const string StampColumn = "stamp";
    public const string AccountStampColumn = "accountStamp";

    private readonly string _connectionString;

    public SqlSourceReader(string connectionString)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(connectionString);
        _connectionString = connectionString;
    }

    // Nome de view seguro: [schema.]nome, só letras, números e sublinhado (o nome vem da configuração)
    [GeneratedRegex(@"^([A-Za-z_][A-Za-z0-9_]*\.)?[A-Za-z_][A-Za-z0-9_]*$")]
    private static partial Regex SafeViewName();

    public async Task<IReadOnlyDictionary<string, SourceRow>> ReadAsync(
        string view, IReadOnlyCollection<string> stamps, CancellationToken ct)
    {
        var quoted = QuoteViewName(view);
        var result = new Dictionary<string, SourceRow>(StringComparer.Ordinal);
        if (stamps.Count == 0) return result;

        await using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(ct).ConfigureAwait(false);

        // Em pedaços de 500 stamps (limite de parâmetros do SQL Server)
        foreach (var chunk in stamps.Chunk(500))
        {
            await using var cmd = new SqlCommand { Connection = connection };
            var stampParams = SqlQueueStore.AddList(cmd, "s", chunk);
            cmd.CommandText = $"SELECT * FROM {quoted} WHERE [{StampColumn}] IN ({stampParams})";

            await using var reader = await cmd.ExecuteReaderAsync(ct).ConfigureAwait(false);
            var stampOrdinal = FindColumn(reader, StampColumn)
                ?? throw new InvalidOperationException($"A view {view} não tem a coluna '{StampColumn}'.");
            var accountOrdinal = FindColumn(reader, AccountStampColumn);

            while (await reader.ReadAsync(ct).ConfigureAwait(false))
            {
                var stamp = Text(reader, stampOrdinal);
                var accountStamp = accountOrdinal is { } a ? Text(reader, a) : null;
                var fields = new List<KeyValuePair<string, string>>();
                for (var i = 0; i < reader.FieldCount; i++)
                {
                    if (i == stampOrdinal || i == accountOrdinal) continue;
                    fields.Add(new KeyValuePair<string, string>(reader.GetName(i), Text(reader, i)));
                }

                result[stamp] = new SourceRow(stamp, accountStamp, fields);
            }
        }

        return result;
    }

    /// <summary>Valida o nome da view e devolve-o entre parênteses retos.</summary>
    internal static string QuoteViewName(string view)
    {
        if (string.IsNullOrWhiteSpace(view) || !SafeViewName().IsMatch(view))
            throw new ArgumentException("Nome de view inválido na configuração.", nameof(view));
        return string.Join(".", view.Split('.').Select(p => $"[{p}]"));
    }

    private static int? FindColumn(SqlDataReader reader, string name)
    {
        for (var i = 0; i < reader.FieldCount; i++)
            if (string.Equals(reader.GetName(i), name, StringComparison.OrdinalIgnoreCase)) return i;
        return null;
    }

    private static string Text(SqlDataReader reader, int ordinal) =>
        reader.IsDBNull(ordinal) ? string.Empty : Convert.ToString(reader.GetValue(ordinal), CultureInfo.InvariantCulture) ?? string.Empty;
}
