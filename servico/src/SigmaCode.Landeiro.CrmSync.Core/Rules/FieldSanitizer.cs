using System.Text.RegularExpressions;

namespace SigmaCode.Landeiro.CrmSync.Core.Rules;

/// <summary>Ajuste feito a um valor para o CRM o aceitar. Só identifica o campo e a regra, nunca o valor.</summary>
public sealed record FieldAdjustment(string SourceStamp, string Field, string Rule);

/// <summary>
/// Regras que evitam que o CRM rejeite a linha toda por um campo inválido (a API trata cada linha à parte):
/// um email que não seja válido faz falhar a conta ou o contacto inteiro, e o nome é obrigatório na criação.
/// </summary>
public static class FieldSanitizer
{
    /// <summary>Nome enviado quando o contacto não tem nome no PHC (o nome é obrigatório na criação).</summary>
    public const string MissingName = "Sem nome";

    public const string EmailAdjusted = "EMAIL_AJUSTADO";
    public const string EmailInvalid = "EMAIL_INVALIDO";
    public const string NameMissing = "NOME_EM_FALTA";
    public const string PostalCodeAdjusted = "CODPOSTAL_AJUSTADO";

    // Email ASCII simples (o que a validação PHP do CRM aceita): sem espaços, sem < > ( ) " :, domínio sem hífen nas pontas
    private static readonly Regex ValidEmail = new(
        @"^[A-Za-z0-9._%+'-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*\.[A-Za-z]{2,}$",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

    // Separadores entre emails (inclui o espaço sem quebra e o espaço de largura zero, que vêm de copiar/colar)
    private static readonly char[] Separators =
        { ';', ',', '/', '|', ' ', '\t', '\r', '\n', '\u00A0', '\u200B', '\uFEFF' };

    private static readonly char[] Edges = { '<', '>', '(', ')', '.', ',', ';', ':', '"', '\'', '[', ']' };

    private static bool IsValid(string candidate) =>
        ValidEmail.IsMatch(candidate)
        && !candidate.Contains("..", StringComparison.Ordinal)
        && !candidate.StartsWith('.')
        && !candidate.Contains(".@", StringComparison.Ordinal);

    /// <summary>
    /// Se o campo tem vários emails (ou lixo à volta), devolve o primeiro válido; se não houver nenhum válido devolve
    /// vazio (o CRM mantém o valor que lá tiver). Um email que já é válido fica como está.
    /// </summary>
    public static string NormalizeEmail(string? value, out string? rule)
    {
        rule = null;
        var text = (value ?? string.Empty).Trim();
        if (text.Length == 0) return string.Empty;
        if (IsValid(text)) return text;

        foreach (var token in text.Split(Separators, StringSplitOptions.RemoveEmptyEntries))
        {
            var candidate = token.Trim(Edges);
            if (candidate.StartsWith("mailto:", StringComparison.OrdinalIgnoreCase)) candidate = candidate[7..];
            if (IsValid(candidate))
            {
                rule = EmailAdjusted;
                return candidate;
            }
        }

        rule = EmailInvalid;
        return string.Empty;
    }

    // Código postal português (NNNN-NNN) seguido de texto, ex.: "4410-387 ARCOZELO VNG" (a localidade vem no mesmo campo)
    private static readonly Regex PostalWithText = new(
        @"^(?<cp>\d{4}-\d{3})(?!\d)\s*(?<resto>\S.*)$", RegexOptions.Compiled | RegexOptions.CultureInvariant);

    /// <summary>Se o código postal tem texto a seguir ao NNNN-NNN (a localidade), envia só o NNNN-NNN.</summary>
    public static string NormalizePostalCode(string? value, out string? rule)
    {
        rule = null;
        var text = (value ?? string.Empty).Trim();
        var m = PostalWithText.Match(text);
        if (!m.Success) return text;
        rule = PostalCodeAdjusted;
        return m.Groups["cp"].Value;
    }

    /// <summary>Contacto sem nome: envia "Sem nome" para o CRM não rejeitar a criação.</summary>
    public static string NormalizeContactName(string? value, out string? rule)
    {
        rule = null;
        var text = (value ?? string.Empty).Trim();
        if (text.Length > 0) return text;
        rule = NameMissing;
        return MissingName;
    }
}
