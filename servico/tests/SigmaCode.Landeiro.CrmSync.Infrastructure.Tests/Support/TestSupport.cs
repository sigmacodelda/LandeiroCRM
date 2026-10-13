using System.Text;
using Microsoft.Data.SqlClient;
using SigmaCode.Landeiro.CrmSync.Core.Abstractions;
using SigmaCode.Landeiro.CrmSync.Core.Domain;

namespace SigmaCode.Landeiro.CrmSync.Infrastructure.Tests.Support;

/// <summary>Handler HTTP falso: devolve o que o teste definir e guarda os pedidos recebidos (cabeçalhos e corpo).</summary>
public sealed class StubHandler : HttpMessageHandler
{
    public sealed record Captured(string Method, string Url, string Authorization, string ContentType, string Body);

    private readonly Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> _respond;

    public StubHandler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> respond) => _respond = respond;

    public List<Captured> Requests { get; } = new();

    public static StubHandler Returning(int status, string body) =>
        new((_, _) => Task.FromResult(new HttpResponseMessage((System.Net.HttpStatusCode)status)
        {
            Content = new StringContent(body, Encoding.UTF8, "application/json"),
        }));

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var body = request.Content is null ? string.Empty : await request.Content.ReadAsStringAsync(cancellationToken);
        Requests.Add(new Captured(
            request.Method.Method,
            request.RequestUri!.ToString(),
            request.Headers.TryGetValues("Authorization", out var auth) ? string.Join(",", auth) : string.Empty,
            request.Content?.Headers.ContentType?.ToString() ?? string.Empty,
            body));
        return await _respond(request, cancellationToken);
    }
}

public sealed class ListAuditLog : IAuditLog
{
    public List<AuditEntry> Entries { get; } = new();
    public void Write(AuditEntry entry) => Entries.Add(entry);
}

/// <summary>Os testes de base de dados só correm com CRMSYNC_TEST_CONNECTION (a LAND2_DEMO) definida.</summary>
public static class TestDb
{
    public const string EnvironmentVariable = "CRMSYNC_TEST_CONNECTION";
    public static string? ConnectionString => Environment.GetEnvironmentVariable(EnvironmentVariable);

    /// <summary>Segurança: os testes escrevem na base, por isso recusam tudo o que não seja a LAND2_DEMO.</summary>
    public static async Task AssertIsDemoAsync()
    {
        await using var connection = new SqlConnection(ConnectionString);
        await connection.OpenAsync();
        await using var cmd = new SqlCommand("SELECT DB_NAME()", connection);
        var name = (string?)await cmd.ExecuteScalarAsync();
        if (!string.Equals(name, "LAND2_DEMO", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException($"Os testes de base de dados só podem correr na LAND2_DEMO (ligado a '{name}').");
    }

    public static async Task<int> ExecAsync(string sql, params (string Name, object Value)[] parameters)
    {
        await using var connection = new SqlConnection(ConnectionString);
        await connection.OpenAsync();
        await using var cmd = new SqlCommand(sql, connection);
        foreach (var (name, value) in parameters) cmd.Parameters.AddWithValue(name, value);
        return await cmd.ExecuteNonQueryAsync();
    }

    public static async Task<T> ScalarAsync<T>(string sql, params (string Name, object Value)[] parameters)
    {
        await using var connection = new SqlConnection(ConnectionString);
        await connection.OpenAsync();
        await using var cmd = new SqlCommand(sql, connection);
        foreach (var (name, value) in parameters) cmd.Parameters.AddWithValue(name, value);
        var result = await cmd.ExecuteScalarAsync();
        return (T)Convert.ChangeType(result!, typeof(T), System.Globalization.CultureInfo.InvariantCulture);
    }
}

public sealed class DbFactAttribute : FactAttribute
{
    public DbFactAttribute()
    {
        if (TestDb.ConnectionString is null)
            Skip = $"Defina {TestDb.EnvironmentVariable} (LAND2_DEMO) para correr os testes de base de dados.";
    }
}

/// <summary>Garante a LAND2_DEMO e limpa os dados de teste (prefixo CRMIT-) antes e depois de cada teste.</summary>
public class DemoDbTestBase : IAsyncLifetime
{
    public const string Prefix = "CRMIT-";

    public async Task InitializeAsync()
    {
        if (TestDb.ConnectionString is null) return;
        await TestDb.AssertIsDemoAsync();
        await CleanAsync();
    }

    public async Task DisposeAsync()
    {
        if (TestDb.ConnectionString is null) return;
        await CleanAsync();
    }

    /// <summary>Apaga os dados de teste da origem (os triggers geram D, que também se apagam da fila no fim).</summary>
    protected static async Task CleanAsync()
    {
        await TestDb.ExecAsync("DELETE FROM dbo.u_clcontact WHERE u_clcontactstamp LIKE @p; DELETE FROM dbo.cl2 WHERE cl2stamp LIKE @p; DELETE FROM dbo.cl WHERE clstamp LIKE @p;",
            ("@p", Prefix + "%"));
        await TestDb.ExecAsync("DELETE FROM dbo.u_crmfila WHERE stamporigem LIKE @p OR u_crmfilastamp LIKE @p OR codigo LIKE @c",
            ("@p", Prefix + "%"), ("@c", "9999998%"));
    }

    protected static Task InsertClientAsync(string stamp, int no, int estab, string name, string country = "Portugal") =>
        TestDb.ExecAsync(@"INSERT dbo.cl (clstamp, no, estab, nome, morada, ncont) VALUES (@s, @no, @e, @n, ' Rua Teste ', '500000000');
                           INSERT dbo.cl2 (cl2stamp, descpais) VALUES (@s, @c);",
            ("@s", stamp), ("@no", no), ("@e", estab), ("@n", name), ("@c", country));

    protected static Task InsertContactAsync(string stamp, string clientStamp, string name) =>
        TestDb.ExecAsync("INSERT dbo.u_clcontact (u_clcontactstamp, clstamp, nome, funcao) VALUES (@s, @c, @n, 'Gerente')",
            ("@s", stamp), ("@c", clientStamp), ("@n", name));

    protected static Task<string> StatusOfAsync(string sourceStamp, string entity) =>
        TestDb.ScalarAsync<string>("SELECT TOP 1 RTRIM(estado) FROM dbo.u_crmfila WHERE stamporigem = @s AND entidade = @e ORDER BY u_crmfilastamp DESC",
            ("@s", sourceStamp), ("@e", entity));
}
