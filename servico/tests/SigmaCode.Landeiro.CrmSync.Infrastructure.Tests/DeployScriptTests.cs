using System.Diagnostics;
using SigmaCode.Landeiro.CrmSync.Infrastructure.Security;

namespace SigmaCode.Landeiro.CrmSync.Infrastructure.Tests;

/// <summary>Garante que o ficheiro criado pelo script PowerShell é o que o serviço sabe ler (mesmo formato e entropia).</summary>
[Collection("Credenciais")]
public class DeployScriptTests
{
    private static string? FindScript(string name)
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null)
        {
            var candidate = Path.Combine(dir.FullName, "deploy", name);
            if (File.Exists(candidate)) return candidate;
            dir = dir.Parent;
        }

        return null;
    }

    [Fact]
    public void GuardarCredenciais_CreatesAFileTheServiceCanRead_WithoutPlainText()
    {
        if (!OperatingSystem.IsWindows()) return;
        var script = FindScript("guardar-credenciais.ps1");
        Assert.NotNull(script);

        using var dir = new TempDirectory();
        var file = Path.Combine(dir.Path, "credenciais.dpapi");
        // Valores falsos: só servem para provar o formato
        var command = $"& '{script}' -Caminho '{file}' " +
                      "-ConnectionString (ConvertTo-SecureString 'Server=fake;Password=PASS-FALSA-123' -AsPlainText -Force) " +
                      "-Token (ConvertTo-SecureString 'TOKEN-FALSO-456' -AsPlainText -Force)";
        var psi = new ProcessStartInfo("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -Command \"{command}\"")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };

        using var process = Process.Start(psi)!;
        var output = process.StandardOutput.ReadToEnd() + process.StandardError.ReadToEnd();
        process.WaitForExit(60_000);

        Assert.True(process.ExitCode == 0, output);
        Assert.DoesNotContain("PASS-FALSA-123", output, StringComparison.Ordinal);   // o script não escreve segredos no ecrã
        var raw = File.ReadAllBytes(file);
        Assert.DoesNotContain("TOKEN-FALSO-456", System.Text.Encoding.UTF8.GetString(raw) + System.Text.Encoding.Unicode.GetString(raw), StringComparison.Ordinal);

        var saved = Environment.GetEnvironmentVariable(CredentialProvider.DbEnvironmentVariable);
        var savedToken = Environment.GetEnvironmentVariable(CredentialProvider.TokenEnvironmentVariable);
        Environment.SetEnvironmentVariable(CredentialProvider.DbEnvironmentVariable, null);
        Environment.SetEnvironmentVariable(CredentialProvider.TokenEnvironmentVariable, null);
        try
        {
            var credentials = CredentialProvider.Load(file);
            Assert.Equal("Server=fake;Password=PASS-FALSA-123", credentials.DbConnectionString);
            Assert.Equal("TOKEN-FALSO-456", credentials.ApiToken);
        }
        finally
        {
            Environment.SetEnvironmentVariable(CredentialProvider.DbEnvironmentVariable, saved);
            Environment.SetEnvironmentVariable(CredentialProvider.TokenEnvironmentVariable, savedToken);
        }
    }
}
