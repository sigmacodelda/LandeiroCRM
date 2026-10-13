using System.Data;
using Microsoft.Data.SqlClient;
using SigmaCode.Landeiro.CrmSync.Core.Abstractions;

namespace SigmaCode.Landeiro.CrmSync.Infrastructure.Sql;

/// <summary>
/// Uma só instância do serviço: um applock de sessão (sp_getapplock) numa ligação dedicada, mantida aberta
/// durante a vida do serviço. Se uma segunda instância arrancar, não consegue o bloqueio e não processa nada.
/// Se a ligação cair, o bloqueio perde-se: no ciclo seguinte volta a ser pedido.
/// </summary>
public sealed class SqlInstanceLock : IInstanceLock
{
    private readonly string _connectionString;
    private readonly string _resource;
    private SqlConnection? _connection;
    private bool _held;

    public SqlInstanceLock(string connectionString, string resourceName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(connectionString);
        ArgumentException.ThrowIfNullOrWhiteSpace(resourceName);
        // Sem pool: o bloqueio é da sessão e não pode ir parar a outra utilização da ligação
        _connectionString = new SqlConnectionStringBuilder(connectionString) { Pooling = false }.ConnectionString;
        _resource = resourceName;
    }

    public async Task<bool> EnsureAcquiredAsync(CancellationToken ct)
    {
        try
        {
            if (_connection is null || _connection.State != ConnectionState.Open)
            {
                await ResetAsync().ConfigureAwait(false);
                _connection = new SqlConnection(_connectionString);
                await _connection.OpenAsync(ct).ConfigureAwait(false);
                _held = false;
            }

            if (_held && await StillHeldAsync(ct).ConfigureAwait(false)) return true;

            await using var cmd = new SqlCommand(
                "DECLARE @r int; EXEC @r = sp_getapplock @Resource = @res, @LockMode = 'Exclusive', @LockOwner = 'Session', @LockTimeout = 0; SELECT @r;",
                _connection);
            cmd.Parameters.AddWithValue("@res", _resource);
            var code = Convert.ToInt32(await cmd.ExecuteScalarAsync(ct).ConfigureAwait(false), System.Globalization.CultureInfo.InvariantCulture);
            _held = code >= 0;   // 0 = obtido, 1 = obtido depois de esperar; negativo = ocupado/erro
            return _held;
        }
        catch (SqlException)
        {
            // Base de dados indisponível: não temos o bloqueio. Tenta de novo no próximo ciclo.
            await ResetAsync().ConfigureAwait(false);
            return false;
        }
    }

    private async Task<bool> StillHeldAsync(CancellationToken ct)
    {
        await using var cmd = new SqlCommand("SELECT APPLOCK_MODE('public', @res, 'Session');", _connection);
        cmd.Parameters.AddWithValue("@res", _resource);
        var mode = Convert.ToString(await cmd.ExecuteScalarAsync(ct).ConfigureAwait(false), System.Globalization.CultureInfo.InvariantCulture);
        return string.Equals(mode, "Exclusive", StringComparison.OrdinalIgnoreCase);
    }

    private async Task ResetAsync()
    {
        _held = false;
        if (_connection is not null)
        {
            await _connection.DisposeAsync().ConfigureAwait(false);   // fechar a sessão liberta o bloqueio
            _connection = null;
        }
    }

    public async ValueTask DisposeAsync() => await ResetAsync().ConfigureAwait(false);
}
