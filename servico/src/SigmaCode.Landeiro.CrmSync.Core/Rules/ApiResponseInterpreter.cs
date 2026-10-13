using System.Globalization;
using System.Text.Json;
using SigmaCode.Landeiro.CrmSync.Core.Domain;

namespace SigmaCode.Landeiro.CrmSync.Core.Rules;

/// <summary>
/// Transforma a resposta da API (200 / 206 / 422 / 401 / rede) num resultado por registo.
/// Regra principal: um registo que NÃO venha na resposta como gravado fica em erro.
/// O contrato do 206 (como vêm identificados os que falham) ainda está por confirmar com a Orcinus,
/// por isso "gravado" = vem na lista, com id e ação, e a ação não indica falha.
/// </summary>
public static class ApiResponseInterpreter
{
    private const int MaxMessage = 200;

    public static BatchOutcome Interpret(
        ApiCallResult call,
        IReadOnlyList<string> sentCodes,
        string responseListProperty,
        string responseCodeProperty)
    {
        ArgumentNullException.ThrowIfNull(call);
        ArgumentNullException.ThrowIfNull(sentCodes);

        // O pedido nem chegou a ser processado (sem rede, timeout, ligação recusada)
        if (call.StatusCode is null)
            return AllFailed(sentCodes.Count, $"Sem resposta da API: {Limit(call.Error)}", BatchFailureKind.Network);

        var status = call.StatusCode.Value;
        switch (status)
        {
            case 401 or 403:
                return AllFailed(sentCodes.Count, $"HTTP {status}: autenticação rejeitada pela API", BatchFailureKind.Authentication);
            case 422:
                return AllFailed(sentCodes.Count, $"HTTP 422: pedido inválido ({ReadErrorText(call.Body)})", BatchFailureKind.InvalidRequest);
            case 200 or 206:
                return ParseList(call, sentCodes, responseListProperty, responseCodeProperty);
            case >= 500:
                return AllFailed(sentCodes.Count, $"HTTP {status}: erro no servidor do CRM", BatchFailureKind.Server);
            default:
                return AllFailed(sentCodes.Count, $"HTTP {status}: resposta inesperada da API", BatchFailureKind.InvalidRequest);
        }
    }

    private static BatchOutcome ParseList(ApiCallResult call, IReadOnlyList<string> sentCodes, string listProperty, string codeProperty)
    {
        var status = call.StatusCode;
        try
        {
            using var doc = JsonDocument.Parse(call.Body ?? string.Empty);
            if (doc.RootElement.ValueKind != JsonValueKind.Object
                || !doc.RootElement.TryGetProperty(listProperty, out var list)
                || list.ValueKind != JsonValueKind.Array)
            {
                return AllFailed(sentCodes.Count, $"HTTP {status}: resposta sem a lista '{listProperty}'", BatchFailureKind.InvalidResponse);
            }

            // Associa pelo índice "row" (se faltar, usa a posição na lista)
            var byRow = new Dictionary<int, JsonElement>();
            var position = 0;
            foreach (var entry in list.EnumerateArray())
            {
                var row = position;
                if (entry.ValueKind == JsonValueKind.Object && entry.TryGetProperty("row", out var rowElement))
                {
                    if (rowElement.ValueKind == JsonValueKind.Number && rowElement.TryGetInt32(out var n)) row = n;
                    else if (rowElement.ValueKind == JsonValueKind.String
                             && int.TryParse(rowElement.GetString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var s)) row = s;
                }

                byRow.TryAdd(row, entry);
                position++;
            }

            var items = new List<ItemOutcome>(sentCodes.Count);
            for (var i = 0; i < sentCodes.Count; i++)
            {
                items.Add(byRow.TryGetValue(i, out var element)
                    ? Evaluate(element, sentCodes[i], codeProperty)
                    : new ItemOutcome(false, null, null, $"Registo não devolvido como gravado na resposta (HTTP {status})"));
            }

            var kind = items.All(x => x.Success) ? BatchFailureKind.None : BatchFailureKind.Partial;
            return new BatchOutcome(items, kind);
        }
        catch (JsonException)
        {
            return AllFailed(sentCodes.Count, $"HTTP {status}: resposta da API não é JSON válido", BatchFailureKind.InvalidResponse);
        }
    }

    /// <summary>Um registo está gravado se vem com id e ação, a ação não indica falha, não traz erro e o código bate certo.</summary>
    private static ItemOutcome Evaluate(JsonElement entry, string sentCode, string codeProperty)
    {
        if (entry.ValueKind != JsonValueKind.Object)
            return new ItemOutcome(false, null, null, "Entrada da resposta com formato inesperado");

        var id = GetText(entry, "id");
        var action = GetText(entry, "action");
        var error = GetText(entry, "error") ?? GetText(entry, "message");

        if (!string.IsNullOrWhiteSpace(codeProperty))
        {
            var returned = GetText(entry, codeProperty);
            if (returned is not null && !string.Equals(returned.Trim(), sentCode.Trim(), StringComparison.Ordinal))
                return new ItemOutcome(false, id, action, "Código da resposta diferente do enviado");
        }

        if (!string.IsNullOrWhiteSpace(error))
            return new ItemOutcome(false, id, action, $"CRM recusou o registo: {Limit(error)}");
        if (string.IsNullOrWhiteSpace(id) || string.IsNullOrWhiteSpace(action))
            return new ItemOutcome(false, id, action, "Resposta sem id ou ação: registo não confirmado como gravado");
        if (IndicatesFailure(action))
            return new ItemOutcome(false, id, action, $"CRM não gravou o registo (ação: {Limit(action)})");

        return new ItemOutcome(true, id, action, null);
    }

    private static bool IndicatesFailure(string action) =>
        action.Contains("fail", StringComparison.OrdinalIgnoreCase)
        || action.Contains("error", StringComparison.OrdinalIgnoreCase)
        || action.Contains("invalid", StringComparison.OrdinalIgnoreCase)
        || action.Contains("reject", StringComparison.OrdinalIgnoreCase);

    private static string? GetText(JsonElement obj, string name)
    {
        if (!obj.TryGetProperty(name, out var value)) return null;
        return value.ValueKind switch
        {
            JsonValueKind.String => value.GetString(),
            JsonValueKind.Number => value.GetRawText(),
            JsonValueKind.Null or JsonValueKind.Undefined => null,
            _ => value.GetRawText(),
        };
    }

    private static string ReadErrorText(string? body)
    {
        if (string.IsNullOrWhiteSpace(body)) return "sem detalhe";
        try
        {
            using var doc = JsonDocument.Parse(body);
            if (doc.RootElement.ValueKind == JsonValueKind.Object)
            {
                var text = GetText(doc.RootElement, "error") ?? GetText(doc.RootElement, "message");
                if (!string.IsNullOrWhiteSpace(text)) return Limit(text);
            }
        }
        catch (JsonException)
        {
            // Corpo que não é JSON: não se reproduz (pode ter conteúdo arbitrário)
        }

        return "sem detalhe";
    }

    private static BatchOutcome AllFailed(int count, string message, BatchFailureKind kind) =>
        new(Enumerable.Range(0, count).Select(_ => new ItemOutcome(false, null, null, message)).ToList(), kind);

    private static string Limit(string? text)
    {
        if (string.IsNullOrEmpty(text)) return string.Empty;
        var oneLine = text.Replace('\r', ' ').Replace('\n', ' ');
        return oneLine.Length <= MaxMessage ? oneLine : oneLine[..MaxMessage];
    }
}
