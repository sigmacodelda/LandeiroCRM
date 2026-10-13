using System.Runtime.Versioning;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace SigmaCode.Landeiro.CrmSync.Infrastructure.Security;

/// <summary>As duas credenciais do serviço. Nunca vão para código, repositório, logs ou appsettings.</summary>
public sealed record Credentials(string DbConnectionString, string ApiToken)
{
    // Impede que um ToString acidental (log, exceção) escreva os segredos
    public override string ToString() => "Credentials(***)";
}

/// <summary>
/// Origem das credenciais, por esta ordem:
///  1) variáveis de ambiente CRMSYNC_DB_CONNECTION e CRMSYNC_API_TOKEN (testes e desenvolvimento);
///  2) ficheiro protegido por DPAPI (âmbito da máquina), criado por deploy/guardar-credenciais.ps1.
/// O DPAPI está ligado à máquina: o ficheiro copiado para outro servidor não se consegue ler.
/// </summary>
public static class CredentialProvider
{
    public const string DbEnvironmentVariable = "CRMSYNC_DB_CONNECTION";
    public const string TokenEnvironmentVariable = "CRMSYNC_API_TOKEN";

    // Entropia adicional (não é um segredo): o ficheiro só se abre com a mesma aplicação. Igual ao script PowerShell.
    internal static readonly byte[] Entropy = Encoding.UTF8.GetBytes("SigmaCode.Landeiro.CrmSync.v1");

    public static Credentials Load(string? protectedFile)
    {
        var db = Environment.GetEnvironmentVariable(DbEnvironmentVariable);
        var token = Environment.GetEnvironmentVariable(TokenEnvironmentVariable);

        // O DPAPI só existe no Windows (o serviço corre num servidor Windows)
        if (OperatingSystem.IsWindows()
            && (string.IsNullOrWhiteSpace(db) || string.IsNullOrWhiteSpace(token))
            && !string.IsNullOrWhiteSpace(protectedFile) && File.Exists(protectedFile))
        {
            var fromFile = ReadProtectedFile(protectedFile);
            if (string.IsNullOrWhiteSpace(db)) db = fromFile.DbConnectionString;
            if (string.IsNullOrWhiteSpace(token)) token = fromFile.ApiToken;
        }

        // A mensagem diz O QUE falta, nunca os valores
        var missing = new List<string>();
        if (string.IsNullOrWhiteSpace(db)) missing.Add("connection string da base de dados");
        if (string.IsNullOrWhiteSpace(token)) missing.Add("token da API");
        if (missing.Count > 0)
        {
            throw new InvalidOperationException(
                $"Faltam credenciais: {string.Join(" e ", missing)}. Usar deploy/guardar-credenciais.ps1 " +
                $"ou as variáveis de ambiente {DbEnvironmentVariable} e {TokenEnvironmentVariable}.");
        }

        return new Credentials(db!, token!);
    }

    /// <summary>Protege as credenciais com DPAPI (âmbito da máquina) e grava-as no ficheiro.</summary>
    [SupportedOSPlatform("windows")]
    public static void SaveProtected(string path, Credentials credentials)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        ArgumentNullException.ThrowIfNull(credentials);

        var json = JsonSerializer.SerializeToUtf8Bytes(new Dto(credentials.DbConnectionString, credentials.ApiToken));
        var protectedBytes = ProtectedData.Protect(json, Entropy, DataProtectionScope.LocalMachine);
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        File.WriteAllBytes(path, protectedBytes);
    }

    [SupportedOSPlatform("windows")]
    private static Credentials ReadProtectedFile(string path)
    {
        try
        {
            var plain = ProtectedData.Unprotect(File.ReadAllBytes(path), Entropy, DataProtectionScope.LocalMachine);
            var dto = JsonSerializer.Deserialize<Dto>(plain) ?? throw new InvalidOperationException("Ficheiro de credenciais vazio.");
            return new Credentials(dto.DbConnectionString ?? string.Empty, dto.ApiToken ?? string.Empty);
        }
        catch (CryptographicException)
        {
            throw new InvalidOperationException(
                "Não foi possível abrir o ficheiro de credenciais (protegido para outra máquina ou corrompido). Voltar a correr deploy/guardar-credenciais.ps1.");
        }
    }

    private sealed record Dto(string? DbConnectionString, string? ApiToken);
}
