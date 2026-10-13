using System.Net.Http.Headers;
using System.Text;
using SigmaCode.Landeiro.CrmSync.Core.Abstractions;
using SigmaCode.Landeiro.CrmSync.Core.Domain;

namespace SigmaCode.Landeiro.CrmSync.Infrastructure.Api;

/// <summary>
/// Cliente HTTP da API Somnia CRM (POST com JSON). Cabeçalhos: Content-Type: application/json e
/// Authorization: Bearer &lt;token&gt;. O token nunca é escrito em logs nem em mensagens de erro.
/// Falhas de rede e timeouts voltam como resultado (StatusCode nulo), não como exceção:
/// só o cancelamento do serviço lança OperationCanceledException.
/// </summary>
public sealed class SomniaApiClient : ICrmApiClient
{
    private const int MaxErrorLength = 200;

    private readonly HttpClient _http;
    private readonly string _baseUrl;
    private readonly string _authorizationValue;
    private readonly TimeSpan _timeout;

    public SomniaApiClient(HttpClient http, string baseUrl, string token, string authorizationPrefix, TimeSpan timeout)
    {
        _http = http ?? throw new ArgumentNullException(nameof(http));
        ArgumentException.ThrowIfNullOrWhiteSpace(baseUrl);
        ArgumentException.ThrowIfNullOrWhiteSpace(token);
        _baseUrl = baseUrl.TrimEnd('?', '&');
        _authorizationValue = $"{(string.IsNullOrWhiteSpace(authorizationPrefix) ? "Bearer" : authorizationPrefix.Trim())} {token}";
        _timeout = timeout;
    }

    public async Task<ApiCallResult> PostAsync(string endpoint, string jsonBody, CancellationToken ct)
    {
        var url = $"{_baseUrl}?entryPoint={Uri.EscapeDataString(endpoint)}";

        using var request = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = new StringContent(jsonBody, Encoding.UTF8),
        };
        // Content-Type exatamente "application/json" (sem charset), como na documentação da API
        request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        // TryAddWithoutValidation: aceita também a variante "Bearer:" do PDF da Orcinus
        request.Headers.TryAddWithoutValidation("Authorization", _authorizationValue);

        // O tempo limite é nosso (e não do HttpClient) para distinguir "timeout" de "serviço a parar"
        using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeoutSource.CancelAfter(_timeout);

        try
        {
            using var response = await _http.SendAsync(request, timeoutSource.Token).ConfigureAwait(false);
            var body = await response.Content.ReadAsStringAsync(timeoutSource.Token).ConfigureAwait(false);
            return new ApiCallResult((int)response.StatusCode, body, null);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;   // o serviço está a parar: não é uma falha da API
        }
        catch (OperationCanceledException)
        {
            return new ApiCallResult(null, null, $"Timeout após {_timeout.TotalSeconds:0}s");
        }
        catch (HttpRequestException ex)
        {
            return new ApiCallResult(null, null, $"Falha de rede: {Limit(ex.Message)}");
        }
    }

    private static string Limit(string text)
    {
        var oneLine = text.Replace('\r', ' ').Replace('\n', ' ');
        return oneLine.Length <= MaxErrorLength ? oneLine : oneLine[..MaxErrorLength];
    }
}
