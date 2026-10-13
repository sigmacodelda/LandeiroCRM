using SigmaCode.Landeiro.CrmSync.Core.Domain;
using SigmaCode.Landeiro.CrmSync.Infrastructure.Logging;
using SigmaCode.Landeiro.CrmSync.Infrastructure.Security;
using SigmaCode.Landeiro.CrmSync.Infrastructure.Sql;

namespace SigmaCode.Landeiro.CrmSync.Infrastructure.Tests;

public sealed class TempDirectory : IDisposable
{
    public string Path { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "crmsync-test-" + Guid.NewGuid().ToString("N"));

    public TempDirectory() => Directory.CreateDirectory(Path);

    public void Dispose()
    {
        try { Directory.Delete(Path, true); } catch (IOException) { /* limpeza best-effort */ }
    }
}

/// <summary>Relógio fixo para testar a retenção de logs sem esperar dias.</summary>
public sealed class FixedTime : TimeProvider
{
    private readonly DateTimeOffset _now;
    public FixedTime(DateTime localNow) => _now = new DateTimeOffset(localNow, TimeZoneInfo.Local.GetUtcOffset(localNow));
    public override DateTimeOffset GetUtcNow() => _now.ToUniversalTime();
    public override TimeZoneInfo LocalTimeZone => TimeZoneInfo.Local;
}

public class DailyFileAuditLogTests
{
    [Fact]
    public void Write_AppendsOneLinePerEntry_InTheFileOfTheDay()
    {
        using var dir = new TempDirectory();
        var log = new DailyFileAuditLog(dir.Path, new FixedTime(new DateTime(2026, 10, 13, 11, 30, 5, 123)));

        log.Write(new AuditEntry(AuditLevel.Info, "CL", "CONTA", "13444-0", "stamp1", "ENVIADO", "Updated/abc", string.Empty));
        log.Write(new AuditEntry(AuditLevel.Error, "CL", "CONTA", "13444-1", "stamp2", "ERRO", "-", "HTTP 422"));

        var lines = File.ReadAllLines(Path.Combine(dir.Path, "crmsync-20261013.log"));
        Assert.Equal(2, lines.Length);
        Assert.Equal("2026-10-13 11:30:05.123 | INFO | CL | CONTA | 13444-0 | stamp1 | ENVIADO | Updated/abc | -", lines[0]);
        Assert.Equal("2026-10-13 11:30:05.123 | ERRO | CL | CONTA | 13444-1 | stamp2 | ERRO | - | HTTP 422", lines[1]);
    }

    [Fact]
    public void Write_KeepsEachEntryOnOneLine_AndEscapesTheSeparator()
    {
        using var dir = new TempDirectory();
        var log = new DailyFileAuditLog(dir.Path, new FixedTime(new DateTime(2026, 1, 2, 3, 4, 5)));

        log.Write(new AuditEntry(AuditLevel.Warning, "CL", "CONTA", "1-0", "s", "TRUNCADO", "campo=name", "linha1\nlinha2 | outra"));

        var lines = File.ReadAllLines(Path.Combine(dir.Path, "crmsync-20260102.log"));
        Assert.Single(lines);
        Assert.Contains("AVISO", lines[0], StringComparison.Ordinal);
        Assert.Contains("linha1 linha2 / outra", lines[0], StringComparison.Ordinal);
    }

    [Fact]
    public void Write_CreatesTheDirectory_AndStartsANewFileEachDay()
    {
        using var dir = new TempDirectory();
        var sub = Path.Combine(dir.Path, "a", "b");

        new DailyFileAuditLog(sub, new FixedTime(new DateTime(2026, 5, 1, 10, 0, 0))).Write(new AuditEntry(AuditLevel.Info, "-", "-", "-", "-", "X", "", ""));
        new DailyFileAuditLog(sub, new FixedTime(new DateTime(2026, 5, 2, 10, 0, 0))).Write(new AuditEntry(AuditLevel.Info, "-", "-", "-", "-", "X", "", ""));

        Assert.True(File.Exists(Path.Combine(sub, "crmsync-20260501.log")));
        Assert.True(File.Exists(Path.Combine(sub, "crmsync-20260502.log")));
    }
}

public class LogRetentionCleanerTests
{
    private static string[] Names(string dir) => Directory.GetFiles(dir).Select(Path.GetFileName).Order().ToArray()!;

    [Fact]
    public void Clean_DeletesLogsOlderThanNDays_AndKeepsTheRest()
    {
        using var dir = new TempDirectory();
        // hoje = 2026-10-13, retenção 7: o de há 7 dias (06) fica, o de há 8 dias (05) apaga-se
        foreach (var d in new[] { "20261013", "20261007", "20261006", "20261005", "20250101" })
            File.WriteAllText(Path.Combine(dir.Path, $"crmsync-{d}.log"), "x");

        var deleted = LogRetentionCleaner.Clean(dir.Path, 7, new FixedTime(new DateTime(2026, 10, 13, 12, 0, 0)));

        Assert.Equal(2, deleted);
        Assert.Equal(new[] { "crmsync-20261006.log", "crmsync-20261007.log", "crmsync-20261013.log" }, Names(dir.Path));
    }

    [Fact]
    public void Clean_NeverTouchesFilesThatAreNotCrmSyncLogs()
    {
        using var dir = new TempDirectory();
        File.WriteAllText(Path.Combine(dir.Path, "outro.log"), "x");
        File.WriteAllText(Path.Combine(dir.Path, "crmsync-abcdefgh.log"), "x");
        File.WriteAllText(Path.Combine(dir.Path, "crmsync-20200101.txt"), "x");
        File.WriteAllText(Path.Combine(dir.Path, "notas.md"), "x");

        var deleted = LogRetentionCleaner.Clean(dir.Path, 7, new FixedTime(new DateTime(2026, 10, 13)));

        Assert.Equal(0, deleted);
        Assert.Equal(4, Names(dir.Path).Length);
    }

    [Fact]
    public void Clean_RetentionIsConfigurable()
    {
        using var dir = new TempDirectory();
        File.WriteAllText(Path.Combine(dir.Path, "crmsync-20261012.log"), "x");   // 1 dia
        File.WriteAllText(Path.Combine(dir.Path, "crmsync-20261010.log"), "x");   // 3 dias

        Assert.Equal(1, LogRetentionCleaner.Clean(dir.Path, 2, new FixedTime(new DateTime(2026, 10, 13))));
        Assert.Equal(new[] { "crmsync-20261012.log" }, Names(dir.Path));
    }

    [Fact]
    public void Clean_MissingDirectory_IsNotAnError() =>
        Assert.Equal(0, LogRetentionCleaner.Clean(Path.Combine(Path.GetTempPath(), "nao-existe-" + Guid.NewGuid().ToString("N")), 7));

    [Fact]
    public void Clean_RejectsRetentionBelowOneDay()
    {
        using var dir = new TempDirectory();
        Assert.Throws<ArgumentOutOfRangeException>(() => LogRetentionCleaner.Clean(dir.Path, 0));
    }
}

[Collection("Credenciais")]
public class CredentialProviderTests : IDisposable
{
    private readonly string? _db = Environment.GetEnvironmentVariable(CredentialProvider.DbEnvironmentVariable);
    private readonly string? _token = Environment.GetEnvironmentVariable(CredentialProvider.TokenEnvironmentVariable);

    public CredentialProviderTests()
    {
        Environment.SetEnvironmentVariable(CredentialProvider.DbEnvironmentVariable, null);
        Environment.SetEnvironmentVariable(CredentialProvider.TokenEnvironmentVariable, null);
    }

    public void Dispose()
    {
        Environment.SetEnvironmentVariable(CredentialProvider.DbEnvironmentVariable, _db);
        Environment.SetEnvironmentVariable(CredentialProvider.TokenEnvironmentVariable, _token);
    }

    [Fact]
    public void Load_ReadsEnvironmentVariables()
    {
        Environment.SetEnvironmentVariable(CredentialProvider.DbEnvironmentVariable, "Server=x;Database=y");
        Environment.SetEnvironmentVariable(CredentialProvider.TokenEnvironmentVariable, "tok");

        var c = CredentialProvider.Load(null);

        Assert.Equal("Server=x;Database=y", c.DbConnectionString);
        Assert.Equal("tok", c.ApiToken);
    }

    [Fact]
    public void Load_WithNothingConfigured_SaysWhatIsMissing_WithoutValues()
    {
        var ex = Assert.Throws<InvalidOperationException>(() => CredentialProvider.Load(null));

        Assert.Contains("connection string", ex.Message, StringComparison.Ordinal);
        Assert.Contains("token", ex.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void Credentials_ToString_NeverShowsTheSecrets()
    {
        var text = new Credentials("Server=x;Password=segredo", "TOKEN-SEGREDO").ToString();

        Assert.DoesNotContain("segredo", text, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Dpapi_RoundTrip_WritesNoPlainText_AndReadsBack()
    {
        if (!OperatingSystem.IsWindows()) return;   // DPAPI só existe no Windows
        using var dir = new TempDirectory();
        var file = Path.Combine(dir.Path, "credenciais.dpapi");

        CredentialProvider.SaveProtected(file, new Credentials("Server=s;Password=PASSWORD-SECRETA", "TOKEN-SECRETO"));

        var raw = File.ReadAllBytes(file);
        var asText = System.Text.Encoding.UTF8.GetString(raw) + System.Text.Encoding.Unicode.GetString(raw);
        Assert.DoesNotContain("PASSWORD-SECRETA", asText, StringComparison.Ordinal);
        Assert.DoesNotContain("TOKEN-SECRETO", asText, StringComparison.Ordinal);

        var back = CredentialProvider.Load(file);
        Assert.Equal("Server=s;Password=PASSWORD-SECRETA", back.DbConnectionString);
        Assert.Equal("TOKEN-SECRETO", back.ApiToken);
    }

    [Fact]
    public void Load_EnvironmentVariableWinsOverTheFile()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var dir = new TempDirectory();
        var file = Path.Combine(dir.Path, "credenciais.dpapi");
        CredentialProvider.SaveProtected(file, new Credentials("do-ficheiro", "token-do-ficheiro"));
        Environment.SetEnvironmentVariable(CredentialProvider.DbEnvironmentVariable, "do-ambiente");

        var c = CredentialProvider.Load(file);

        Assert.Equal("do-ambiente", c.DbConnectionString);
        Assert.Equal("token-do-ficheiro", c.ApiToken);
    }

    [Fact]
    public void Load_CorruptedFile_GivesAClearError_WithoutLeakingContent()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var dir = new TempDirectory();
        var file = Path.Combine(dir.Path, "credenciais.dpapi");
        File.WriteAllText(file, "isto não foi protegido pelo DPAPI");

        var ex = Assert.Throws<InvalidOperationException>(() => CredentialProvider.Load(file));

        Assert.Contains("guardar-credenciais", ex.Message, StringComparison.Ordinal);
    }
}

public class SqlSourceReaderNameTests
{
    [Theory]
    [InlineData("u_v_crm_conta_cl", "[u_v_crm_conta_cl]")]
    [InlineData("dbo.u_v_crm_conta_cl", "[dbo].[u_v_crm_conta_cl]")]
    public void QuoteViewName_AcceptsSafeNames(string name, string expected) =>
        Assert.Equal(expected, SqlSourceReader.QuoteViewName(name));

    [Theory]
    [InlineData("")]
    [InlineData("x; DROP TABLE cl")]
    [InlineData("a.b.c")]
    [InlineData("view]--")]
    [InlineData("1abc")]
    [InlineData("nome com espaços")]
    public void QuoteViewName_RejectsAnythingThatCouldBeSqlInjection(string name) =>
        Assert.Throws<ArgumentException>(() => SqlSourceReader.QuoteViewName(name));
}
