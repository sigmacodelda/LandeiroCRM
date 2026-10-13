using System.Net;
using SigmaCode.Landeiro.CrmSync.Core.Rules;
using SigmaCode.Landeiro.CrmSync.Infrastructure.Api;
using SigmaCode.Landeiro.CrmSync.Infrastructure.Tests.Support;

namespace SigmaCode.Landeiro.CrmSync.Infrastructure.Tests;

/// <summary>Integração com a API simulada (HttpMessageHandler falso): 200, 206, 422, 401, timeout e falha de rede.</summary>
public class SomniaApiClientTests
{
    private const string Token = "TOKEN-DE-TESTE-NAO-REAL";
    private const string Base = "http://api.teste/carneslandeiro/index.php";

    private static SomniaApiClient Client(StubHandler handler, string prefix = "Bearer", double timeoutSeconds = 30) =>
        new(new HttpClient(handler) { Timeout = Timeout.InfiniteTimeSpan }, Base, Token, prefix, TimeSpan.FromSeconds(timeoutSeconds));

    [Fact]
    public async Task Post_SendsTheRequestInTheFormatTheApiExpects()
    {
        var handler = StubHandler.Returning(200, "{}");

        await Client(handler).PostAsync("ImportAccounts", "{\"accounts\":[]}", CancellationToken.None);

        var request = Assert.Single(handler.Requests);
        Assert.Equal("POST", request.Method);
        Assert.Equal($"{Base}?entryPoint=ImportAccounts", request.Url);
        Assert.Equal($"Bearer {Token}", request.Authorization);
        Assert.Equal("application/json", request.ContentType);
        Assert.Equal("{\"accounts\":[]}", request.Body);
    }

    [Fact]
    public async Task Post_UsesTheContactsEndpoint()
    {
        var handler = StubHandler.Returning(200, "{}");

        await Client(handler).PostAsync("ImportContacts", "{}", CancellationToken.None);

        Assert.EndsWith("?entryPoint=ImportContacts", handler.Requests[0].Url, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Post_CanUseTheColonVariantOfTheAuthorizationHeader()
    {
        var handler = StubHandler.Returning(200, "{}");

        await Client(handler, prefix: "Bearer:").PostAsync("ImportAccounts", "{}", CancellationToken.None);

        Assert.Equal($"Bearer: {Token}", handler.Requests[0].Authorization);
    }

    [Fact]
    public async Task Post_SendsUtf8WithoutEscapingAccents()
    {
        var handler = StubHandler.Returning(200, "{}");
        var body = PayloadBuilder.Build("accounts",
            new[] { new Core.Domain.SourceRow("S", null, new[] { new KeyValuePair<string, string>("name", "Conceição & Filhos, Lda") }) }, null).Json;

        await Client(handler).PostAsync("ImportAccounts", body, CancellationToken.None);

        Assert.Contains("Conceição & Filhos, Lda", handler.Requests[0].Body, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData(200)]
    [InlineData(206)]
    [InlineData(422)]
    [InlineData(401)]
    [InlineData(500)]
    public async Task Post_ReturnsTheStatusAndBody(int status)
    {
        var result = await Client(StubHandler.Returning(status, "{\"x\":1}")).PostAsync("ImportAccounts", "{}", CancellationToken.None);

        Assert.Equal(status, result.StatusCode);
        Assert.Equal("{\"x\":1}", result.Body);
        Assert.Null(result.Error);
    }

    [Fact]
    public async Task Post_Timeout_ComesBackAsAFailureNotAnException()
    {
        var handler = new StubHandler(async (_, ct) =>
        {
            await Task.Delay(TimeSpan.FromSeconds(10), ct);   // a API nunca responde
            return new HttpResponseMessage(HttpStatusCode.OK);
        });

        var result = await Client(handler, timeoutSeconds: 0.3).PostAsync("ImportAccounts", "{}", CancellationToken.None);

        Assert.Null(result.StatusCode);
        Assert.Contains("Timeout", result.Error, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Post_NetworkFailure_ComesBackAsAFailureNotAnException()
    {
        var handler = new StubHandler((_, _) => throw new HttpRequestException("Ligação recusada"));

        var result = await Client(handler).PostAsync("ImportAccounts", "{}", CancellationToken.None);

        Assert.Null(result.StatusCode);
        Assert.Contains("Falha de rede", result.Error, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Post_ServiceStopping_PropagatesTheCancellation()
    {
        using var cts = new CancellationTokenSource();
        var handler = new StubHandler(async (_, ct) =>
        {
            await cts.CancelAsync();
            ct.ThrowIfCancellationRequested();
            return new HttpResponseMessage(HttpStatusCode.OK);
        });

        await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => Client(handler).PostAsync("ImportAccounts", "{}", cts.Token));
    }

    [Fact]
    public async Task Errors_NeverContainTheToken()
    {
        var handler = new StubHandler((_, _) => throw new HttpRequestException("falhou"));

        var result = await Client(handler).PostAsync("ImportAccounts", "{}", CancellationToken.None);

        Assert.DoesNotContain(Token, result.Error, StringComparison.Ordinal);
    }

    [Fact]
    public async Task EndToEnd_PartialResponse206_IsInterpretedPerRecord()
    {
        var response = "{\"accounts\":[{\"row\":0,\"account\":\"1-0\",\"action\":\"Updated\",\"id\":\"A\"}],\"success\":1,\"fail\":1}";
        var call = await Client(StubHandler.Returning(206, response)).PostAsync("ImportAccounts", "{}", CancellationToken.None);

        var outcome = ApiResponseInterpreter.Interpret(call, new[] { "1-0", "2-0" }, "accounts", "account");

        Assert.True(outcome.Items[0].Success);
        Assert.False(outcome.Items[1].Success);
    }
}
