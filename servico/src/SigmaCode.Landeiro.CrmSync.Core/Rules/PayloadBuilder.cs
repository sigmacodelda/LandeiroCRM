using System.Text.Encodings.Web;
using System.Text.Json;
using SigmaCode.Landeiro.CrmSync.Core.Domain;

namespace SigmaCode.Landeiro.CrmSync.Core.Rules;

/// <summary>Um campo que excedeu o limite do CRM e foi truncado. Só identifica o campo, nunca o valor.</summary>
public sealed record TruncationWarning(string SourceStamp, string Field, int Limit);

/// <summary>JSON pronto a enviar e os avisos de truncagem encontrados.</summary>
public sealed record PayloadResult(string Json, IReadOnlyList<TruncationWarning> Warnings, IReadOnlyList<FieldAdjustment> Adjustments);

/// <summary>Constrói o corpo do pedido (lista de registos) a partir das linhas das views, aplicando as regras de email e nome e a truncagem.</summary>
public static class PayloadBuilder
{
    private static readonly JsonWriterOptions WriterOptions = new()
    {
        // Mantém acentos como estão (UTF-8) em vez de é
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        Indented = false,
    };

    /// <summary>
    /// Devolve {"lista":[{campo:valor,...},...]}. Todos os valores são texto. Os campos entram pela ordem da view
    /// e só os que a view tem: o que a view não tem (ex.: saldos) nunca é enviado.
    /// </summary>
    public static PayloadResult Build(
        string listProperty,
        IReadOnlyList<SourceRow> rows,
        IReadOnlyDictionary<string, int?>? limits)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(listProperty);
        ArgumentNullException.ThrowIfNull(rows);

        var warnings = new List<TruncationWarning>();
        var adjustments = new List<FieldAdjustment>();
        var isContacts = string.Equals(listProperty, "contacts", StringComparison.Ordinal);
        var lookup = limits is null
            ? new Dictionary<string, int?>(StringComparer.OrdinalIgnoreCase)
            : new Dictionary<string, int?>(limits, StringComparer.OrdinalIgnoreCase);

        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream, WriterOptions))
        {
            writer.WriteStartObject();
            writer.WriteStartArray(listProperty);

            foreach (var row in rows)
            {
                writer.WriteStartObject();
                foreach (var (name, value) in row.Fields)
                {
                    var limit = lookup.TryGetValue(name, out var l) ? l : null;
                    // Primeiro as regras que evitam a rejeição da linha pelo CRM, depois a truncagem
                    string? rule = null;
                    var adjusted = value;
                    if (string.Equals(name, "email", StringComparison.OrdinalIgnoreCase))
                        adjusted = FieldSanitizer.NormalizeEmail(value, out rule);
                    else if (isContacts && string.Equals(name, "name", StringComparison.OrdinalIgnoreCase))
                        adjusted = FieldSanitizer.NormalizeContactName(value, out rule);
                    else if (!isContacts && string.Equals(name, "postalCode", StringComparison.OrdinalIgnoreCase))
                        adjusted = FieldSanitizer.NormalizePostalCode(value, out rule);
                    if (rule is not null) adjustments.Add(new FieldAdjustment(row.Stamp, name, rule));
                    var text = FieldTruncator.Truncate(adjusted, limit, out var truncated);
                    if (truncated) warnings.Add(new TruncationWarning(row.Stamp, name, limit!.Value));
                    writer.WriteString(name, text);
                }

                writer.WriteEndObject();
            }

            writer.WriteEndArray();
            writer.WriteEndObject();
        }

        return new PayloadResult(System.Text.Encoding.UTF8.GetString(stream.ToArray()), warnings, adjustments);
    }
}
