namespace SigmaCode.Landeiro.CrmSync.Core.Rules;

/// <summary>Trunca valores de texto ao limite de tamanho do campo no CRM.</summary>
public static class FieldTruncator
{
    /// <summary>
    /// Se o valor for maior do que o limite, corta-o ao limite. Limite nulo (ou zero/negativo) = sem truncagem.
    /// Nunca corta um par de substituição (emoji) ao meio.
    /// </summary>
    public static string Truncate(string? value, int? limit, out bool truncated)
    {
        truncated = false;
        if (value is null) return string.Empty;
        if (limit is null or <= 0 || value.Length <= limit.Value) return value;

        var length = limit.Value;
        // Se o corte cair entre as duas metades de um carácter composto, recua um carácter
        if (char.IsHighSurrogate(value[length - 1])) length--;

        truncated = true;
        return value[..length];
    }
}
