using System.Net;
using System.Text;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using SigmaCode.Landeiro.CrmSync.Core;
using SigmaCode.Landeiro.CrmSync.Core.Config;
using SigmaCode.Landeiro.CrmSync.Core.Domain;
using SigmaCode.Landeiro.CrmSync.Infrastructure.Api;
using SigmaCode.Landeiro.CrmSync.Infrastructure.Sql;
using SigmaCode.Landeiro.CrmSync.Infrastructure.Tests.Support;

namespace SigmaCode.Landeiro.CrmSync.Infrastructure.Tests;

[CollectionDefinition("Db", DisableParallelization = true)]
public sealed class DbCollection;

/// <summary>Fila real (LAND2_DEMO): reserva, resultados, recuperação e bloqueio de contas.</summary>
[Collection("Db")]
public class SqlQueueStoreTests : DemoDbTestBase
{
    private static SqlQueueStore Store() => new(TestDb.ConnectionString!);

    private static Task InsertRowAsync(string stamp, string estado, string entity = "CONTA", string origin = "CL",
        string type = "CLI", string source = "CRMIT-S", string code = "99999980-0", string op = "U") =>
        TestDb.ExecAsync(@"INSERT dbo.u_crmfila (u_crmfilastamp, origem, entidade, tipoconta, stamporigem, codigo, operacao, estado)
                           VALUES (@s, @o, @e, @t, @so, @c, @op, @es)",
            ("@s", stamp), ("@o", origin), ("@e", entity), ("@t", type), ("@so", source), ("@c", code), ("@op", op), ("@es", estado));

    private static async Task<(string Estado, string IdCrm, string Acao, string Msg, int Tentativas, DateTime DataEnvio)> RowAsync(string stamp)
    {
        await using var c = new SqlConnection(TestDb.ConnectionString);
        await c.OpenAsync();
        await using var cmd = new SqlCommand("SELECT RTRIM(estado), idcrm, acaocrm, ultimamensagem, tentativas, dataenvio FROM dbo.u_crmfila WHERE u_crmfilastamp = @s", c);
        cmd.Parameters.AddWithValue("@s", stamp);
        await using var r = await cmd.ExecuteReaderAsync();
        Assert.True(await r.ReadAsync());
        return (r.GetString(0), r.GetString(1), r.GetString(2), r.GetString(3), Convert.ToInt32(r.GetValue(4)), r.GetDateTime(5));
    }

    private static QueueItem Item(string stamp, string source = "CRMIT-S", string entity = "CONTA") =>
        new(stamp, "CL", entity, "CLI", source, "99999980-0", "U");

    [DbFact]
    public async Task GetPending_ReturnsOnlyPending_OfTheEntityTypeAndOrigins_InOrder()
    {
        await InsertRowAsync("CRMIT-Q-03", "PENDENTE");
        await InsertRowAsync("CRMIT-Q-01", "PENDENTE");
        await InsertRowAsync("CRMIT-Q-02", "PENDENTE", origin: "CL2");
        await InsertRowAsync("CRMIT-Q-04", "ERRO");
        await InsertRowAsync("CRMIT-Q-05", "ENVIADO");
        await InsertRowAsync("CRMIT-Q-06", "PENDENTE", entity: "CONTACTO", origin: "U_CLCONTACT");
        await InsertRowAsync("CRMIT-Q-07", "PENDENTE", type: "FOR", origin: "FL");
        await InsertRowAsync("CRMIT-Q-08", "PENDENTE", origin: "OUTRA");

        var items = await Store().GetPendingAsync("CONTA", "CLI", new[] { "CL", "CL2" }, "CRMIT-", 100, 0, CancellationToken.None);

        var mine = items.Where(i => i.QueueStamp.StartsWith("CRMIT-", StringComparison.Ordinal)).Select(i => i.QueueStamp).ToArray();
        Assert.Equal(new[] { "CRMIT-Q-01", "CRMIT-Q-02", "CRMIT-Q-03" }, mine);
        Assert.All(items.Where(i => i.QueueStamp.StartsWith("CRMIT-", StringComparison.Ordinal)), i =>
        {
            Assert.Equal("CONTA", i.Entity);
            Assert.Equal("CLI", i.AccountType);
            Assert.Equal("U", i.Operation);
            Assert.Equal(i.QueueStamp.Trim(), i.QueueStamp);   // sem espaços do char(25)
        });
    }

    [DbFact]
    public async Task GetPending_WaitsForTheMinimumAge_BeforeReturningARecord()
    {
        // Um registo novo (acabado de entrar) e outro com 2 minutos
        await InsertRowAsync("CRMIT-D-1", "PENDENTE");
        await InsertRowAsync("CRMIT-D-2", "PENDENTE");
        // (a tabela do PHC tem por defeito 1900-01-01: define-se a data de cada um)
        await TestDb.ExecAsync("UPDATE dbo.u_crmfila SET datacriacao = GETDATE() WHERE u_crmfilastamp = 'CRMIT-D-1'");
        await TestDb.ExecAsync("UPDATE dbo.u_crmfila SET datacriacao = DATEADD(MINUTE, -2, GETDATE()) WHERE u_crmfilastamp = 'CRMIT-D-2'");

        var waiting = await Store().GetPendingAsync("CONTA", "CLI", new[] { "CL" }, "CRMIT-D-", 100, 60, CancellationToken.None);
        var noDelay = await Store().GetPendingAsync("CONTA", "CLI", new[] { "CL" }, "CRMIT-D-", 100, 0, CancellationToken.None);

        Assert.Equal(new[] { "CRMIT-D-2" }, waiting.Select(i => i.QueueStamp).ToArray());
        Assert.Equal(new[] { "CRMIT-D-1", "CRMIT-D-2" }, noDelay.Select(i => i.QueueStamp).ToArray());
    }

    [DbFact]
    public async Task GetPending_PagesByQueueStamp()
    {
        for (var i = 1; i <= 5; i++) await InsertRowAsync($"CRMIT-P-{i}", "PENDENTE");

        var first = await Store().GetPendingAsync("CONTA", "CLI", new[] { "CL" }, "CRMIT-P-", 2, 0, CancellationToken.None);
        var second = await Store().GetPendingAsync("CONTA", "CLI", new[] { "CL" }, first[^1].QueueStamp, 2, 0, CancellationToken.None);

        Assert.Equal(new[] { "CRMIT-P-1", "CRMIT-P-2" }, first.Select(x => x.QueueStamp).ToArray());
        Assert.Equal(new[] { "CRMIT-P-3", "CRMIT-P-4" }, second.Select(x => x.QueueStamp).ToArray());
    }

    [DbFact]
    public async Task Claim_ReservesOnlyPendingRecords_AndCountsTheAttempt()
    {
        await InsertRowAsync("CRMIT-C-1", "PENDENTE");
        await InsertRowAsync("CRMIT-C-2", "ERRO");

        var claimed = await Store().ClaimAsync(new[] { Item("CRMIT-C-1"), Item("CRMIT-C-2") }, CancellationToken.None);

        Assert.Equal(new[] { "CRMIT-C-1" }, claimed.Select(c => c.QueueStamp).ToArray());
        var row = await RowAsync("CRMIT-C-1");
        Assert.Equal("A_PROCESSAR", row.Estado);
        Assert.Equal(1, row.Tentativas);
        Assert.Equal("ERRO", (await RowAsync("CRMIT-C-2")).Estado);
    }

    [DbFact]
    public async Task Claim_TheSameRecordTwice_OnlyTheFirstWins()
    {
        await InsertRowAsync("CRMIT-C-3", "PENDENTE");

        var first = await Store().ClaimAsync(new[] { Item("CRMIT-C-3") }, CancellationToken.None);
        var second = await Store().ClaimAsync(new[] { Item("CRMIT-C-3") }, CancellationToken.None);

        Assert.Single(first);
        Assert.Empty(second);
        Assert.Equal(1, (await RowAsync("CRMIT-C-3")).Tentativas);
    }

    [DbFact]
    public async Task SetResults_WritesStatusIdActionAndSendDate()
    {
        await InsertRowAsync("CRMIT-R-1", "PENDENTE");
        await Store().ClaimAsync(new[] { Item("CRMIT-R-1") }, CancellationToken.None);

        await Store().SetResultsAsync(new[] { new QueueResult(Item("CRMIT-R-1"), "ENVIADO", "733f67b5-d2ea", "Updated", null) }, CancellationToken.None);

        var row = await RowAsync("CRMIT-R-1");
        Assert.Equal("ENVIADO", row.Estado);
        Assert.Equal("733f67b5-d2ea", row.IdCrm);
        Assert.Equal("Updated", row.Acao);
        Assert.True(row.DataEnvio > new DateTime(2000, 1, 1));
    }

    [DbFact]
    public async Task SetResults_ErrorMessageIsLimitedTo500Characters()
    {
        await InsertRowAsync("CRMIT-R-2", "PENDENTE");
        await Store().ClaimAsync(new[] { Item("CRMIT-R-2") }, CancellationToken.None);

        await Store().SetResultsAsync(new[] { new QueueResult(Item("CRMIT-R-2"), "ERRO", null, null, new string('x', 900)) }, CancellationToken.None);

        var row = await RowAsync("CRMIT-R-2");
        Assert.Equal("ERRO", row.Estado);
        Assert.Equal(500, row.Msg.Length);
    }

    [DbFact]
    public async Task SetResults_ASuccessfulSend_KeepsThePreviousErrorMessage()
    {
        await TestDb.ExecAsync(@"INSERT dbo.u_crmfila (u_crmfilastamp, origem, entidade, tipoconta, stamporigem, codigo, operacao, estado, ultimamensagem)
                                 VALUES ('CRMIT-R-5', 'CL', 'CONTA', 'CLI', 'CRMIT-S', '99999980-0', 'U', 'PENDENTE', 'Reposto manualmente. Erro anterior: HTTP 422')");
        await Store().ClaimAsync(new[] { Item("CRMIT-R-5") }, CancellationToken.None);

        await Store().SetResultsAsync(new[] { new QueueResult(Item("CRMIT-R-5"), "ENVIADO", "id", "Updated", null) }, CancellationToken.None);

        var row = await RowAsync("CRMIT-R-5");
        Assert.Equal("ENVIADO", row.Estado);
        Assert.Equal("Reposto manualmente. Erro anterior: HTTP 422", row.Msg);
    }

    [DbFact]
    public async Task SetResults_NeverChangesRecordsThatAreNotBeingProcessed()
    {
        await InsertRowAsync("CRMIT-R-3", "ENVIADO");
        await InsertRowAsync("CRMIT-R-4", "PENDENTE");

        await Store().SetResultsAsync(new[]
        {
            new QueueResult(Item("CRMIT-R-3"), "ERRO", null, null, "x"),
            new QueueResult(Item("CRMIT-R-4"), "ERRO", null, null, "x"),
        }, CancellationToken.None);

        Assert.Equal("ENVIADO", (await RowAsync("CRMIT-R-3")).Estado);
        Assert.Equal("PENDENTE", (await RowAsync("CRMIT-R-4")).Estado);
    }

    [DbFact]
    public async Task Recover_PutsProcessingRecordsBackToPending_AndLeavesTheOthers()
    {
        await InsertRowAsync("CRMIT-V-1", "A_PROCESSAR");
        await InsertRowAsync("CRMIT-V-2", "ENVIADO");
        await InsertRowAsync("CRMIT-V-3", "ERRO");

        var n = await Store().RecoverProcessingAsync(CancellationToken.None);

        Assert.True(n >= 1);
        Assert.Equal("PENDENTE", (await RowAsync("CRMIT-V-1")).Estado);
        Assert.Equal("ENVIADO", (await RowAsync("CRMIT-V-2")).Estado);
        Assert.Equal("ERRO", (await RowAsync("CRMIT-V-3")).Estado);
    }

    [DbFact]
    public async Task Blocked_OnlyWhenTheLastRecordOfTheAccountIsPendingProcessingOrError()
    {
        // Conta A: último registo PENDENTE -> bloqueada
        await InsertRowAsync("CRMIT-B-A1", "ENVIADO", source: "CRMIT-A");
        await InsertRowAsync("CRMIT-B-A2", "PENDENTE", source: "CRMIT-A");
        // Conta B: último registo ERRO -> bloqueada
        await InsertRowAsync("CRMIT-B-B1", "ERRO", source: "CRMIT-B");
        // Conta C: um ERRO antigo já resolvido, último ENVIADO -> livre
        await InsertRowAsync("CRMIT-B-C1", "ERRO", source: "CRMIT-C");
        await InsertRowAsync("CRMIT-B-C2", "ENVIADO", source: "CRMIT-C");
        // Conta D: A_PROCESSAR -> bloqueada
        await InsertRowAsync("CRMIT-B-D1", "A_PROCESSAR", source: "CRMIT-D");
        // Conta E: nunca esteve na fila -> livre

        var blocked = await Store().GetBlockedSourceStampsAsync("CONTA", "CLI",
            new[] { "CRMIT-A", "CRMIT-B", "CRMIT-C", "CRMIT-D", "CRMIT-E" }, CancellationToken.None);

        Assert.Equal(new[] { "CRMIT-A", "CRMIT-B", "CRMIT-D" }, blocked.Order().ToArray());
    }
}

/// <summary>Leitura das views reais, e applock de instância única.</summary>
[Collection("Db")]
public class SqlSourceReaderAndLockTests : DemoDbTestBase
{
    [DbFact]
    public async Task ReadAccounts_ReturnsTheApiFieldsInOrder_Trimmed()
    {
        await InsertClientAsync("CRMIT-CL-01", 99999981, 0, "  Cliente IT  ", "Espanha");

        var rows = await new SqlSourceReader(TestDb.ConnectionString!).ReadAsync("u_v_crm_conta_cl", new[] { "CRMIT-CL-01" }, CancellationToken.None);

        var row = Assert.Single(rows).Value;
        Assert.Equal("CRMIT-CL-01", row.Stamp);
        Assert.Null(row.AccountStamp);
        Assert.Equal(
            new[] { "code", "name", "address", "postalCode", "city", "country", "vatNumber", "phone", "mobilePhone", "email", "fax", "accountType", "status" },
            row.Fields.Select(f => f.Key).ToArray());
        var values = row.Fields.ToDictionary(f => f.Key, f => f.Value);
        Assert.Equal("99999981-0", values["code"]);
        Assert.Equal("Cliente IT", values["name"]);
        Assert.Equal("Rua Teste", values["address"]);
        Assert.Equal("Espanha", values["country"]);
        Assert.Equal("CLI", values["accountType"]);
        Assert.Equal("Ativo", values["status"]);
    }

    [DbFact]
    public async Task ReadContacts_ReturnsTheAccountStampAndCode()
    {
        await InsertClientAsync("CRMIT-CL-02", 99999982, 1, "Estabelecimento");
        await InsertContactAsync("CRMIT-K-01", "CRMIT-CL-02", " Maria ");

        var rows = await new SqlSourceReader(TestDb.ConnectionString!).ReadAsync("u_v_crm_contacto_cl", new[] { "CRMIT-K-01" }, CancellationToken.None);

        var row = Assert.Single(rows).Value;
        Assert.Equal("CRMIT-CL-02", row.AccountStamp);
        var values = row.Fields.ToDictionary(f => f.Key, f => f.Value);
        Assert.Equal("99999982-1", values["accountCode"]);
        Assert.Equal("CRMIT-K-01", values["contactCode"]);
        Assert.Equal("Maria", values["name"]);
        Assert.Equal("Gerente", values["title"]);
    }

    [DbFact]
    public async Task Read_MoreThan500Stamps_WorksInChunks()
    {
        await InsertClientAsync("CRMIT-CL-03", 99999983, 0, "Cliente");
        var stamps = Enumerable.Range(0, 1200).Select(i => $"CRMIT-NAO-EXISTE-{i}").Append("CRMIT-CL-03").ToList();

        var rows = await new SqlSourceReader(TestDb.ConnectionString!).ReadAsync("u_v_crm_conta_cl", stamps, CancellationToken.None);

        Assert.Single(rows);
        Assert.True(rows.ContainsKey("CRMIT-CL-03"));
    }

    [DbFact]
    public async Task Read_ViewNameFromConfigurationIsValidated() =>
        await Assert.ThrowsAsync<ArgumentException>(() => new SqlSourceReader(TestDb.ConnectionString!)
            .ReadAsync("u_v_crm_conta_cl; DROP TABLE cl", new[] { "x" }, CancellationToken.None));

    [DbFact]
    public async Task InstanceLock_OnlyOneInstanceHoldsIt_AndItIsReleasedOnDispose()
    {
        var resource = "CrmSyncTeste-" + Guid.NewGuid().ToString("N");
        await using var first = new SqlInstanceLock(TestDb.ConnectionString!, resource);
        await using var second = new SqlInstanceLock(TestDb.ConnectionString!, resource);

        Assert.True(await first.EnsureAcquiredAsync(CancellationToken.None));
        Assert.True(await first.EnsureAcquiredAsync(CancellationToken.None));    // continua a ter
        Assert.False(await second.EnsureAcquiredAsync(CancellationToken.None));  // a segunda instância não consegue

        await first.DisposeAsync();
        Assert.True(await second.EnsureAcquiredAsync(CancellationToken.None));   // libertado
    }
}

/// <summary>Circuito completo: triggers -> fila -> serviço -> views -> API simulada -> fila + log, na LAND2_DEMO.</summary>
[Collection("Db")]
public class EndToEndWithStubbedApiTests : DemoDbTestBase
{
    private static SyncOptions Options(Dictionary<string, Dictionary<string, int?>>? limits = null) => new()
    {
        ApiBaseUrl = "http://api.teste/index.php",
        BatchSize = 100,
        SendDelaySeconds = 0,   // os testes enviam logo (o atraso de 60 s tem o seu próprio teste)
        FieldLimits = limits ?? new(),
        Sources =
        {
            new SourceOptions
            {
                Name = "CL-CONTA", Order = 1, Entity = "CONTA", AccountType = "CLI", Origins = { "CL", "CL2" },
                View = "u_v_crm_conta_cl", Endpoint = "ImportAccounts", RequestListProperty = "accounts",
                ResponseListProperty = "accounts", ResponseCodeProperty = "account",
            },
            new SourceOptions
            {
                Name = "CL-CONTACTO", Order = 2, Entity = "CONTACTO", AccountType = "CLI", Origins = { "U_CLCONTACT" },
                View = "u_v_crm_contacto_cl", Endpoint = "ImportContacts", RequestListProperty = "contacts",
                ResponseListProperty = "contacts", ResponseCodeProperty = "contact", WaitsForEntity = "CONTA",
            },
        },
    };

    /// <summary>API simulada que responde 200 a tudo o que recebe (lê os códigos do pedido).</summary>
    private static Task<HttpResponseMessage> OkResponder(HttpRequestMessage request, string body)
    {
        using var doc = JsonDocument.Parse(body);
        var list = doc.RootElement.EnumerateObject().First();
        var isAccounts = list.Name == "accounts";
        var entries = list.Value.EnumerateArray().Select((e, i) =>
            $"{{\"row\":{i},\"{(isAccounts ? "account" : "contact")}\":\"{e.GetProperty(isAccounts ? "code" : "contactCode").GetString()}\",\"action\":\"Updated\",\"id\":\"crm-{i}\"}}");
        var json = $"{{\"{list.Name}\":[{string.Join(",", entries)}]}}";
        return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(json, Encoding.UTF8, "application/json") });
    }

    private sealed record Rig(SyncCycleRunner Runner, StubHandler Handler, ListAuditLog Log, SqlQueueStore Store);

    private static Rig Build(Func<HttpRequestMessage, string, Task<HttpResponseMessage>>? responder = null, SyncOptions? options = null)
    {
        var handler = new StubHandler(async (req, ct) =>
        {
            var body = await req.Content!.ReadAsStringAsync(ct);
            return await (responder ?? OkResponder)(req, body);
        });
        var cs = TestDb.ConnectionString!;
        var opts = options ?? Options();
        var log = new ListAuditLog();
        var store = new SqlQueueStore(cs);
        var api = new SomniaApiClient(new HttpClient(handler) { Timeout = Timeout.InfiniteTimeSpan }, opts.ApiBaseUrl, "token-teste", "Bearer", TimeSpan.FromSeconds(30));
        return new Rig(new SyncCycleRunner(opts, store, new SqlSourceReader(cs), api, log), handler, log, store);
    }

    /// <summary>Estes testes processam TODA a fila: por segurança só correm com a fila sem mais nada por enviar.</summary>
    private static async Task RequireOnlyTestRowsPendingAsync()
    {
        var others = await TestDb.ScalarAsync<int>(
            "SELECT COUNT(*) FROM dbo.u_crmfila WHERE estado IN ('PENDENTE','A_PROCESSAR') AND stamporigem NOT LIKE @p", ("@p", Prefix + "%"));
        Assert.True(others == 0, $"A fila da LAND2_DEMO tem {others} registo(s) por enviar que não são de teste; processá-los ou repô-los antes de correr estes testes.");
    }

    [DbFact]
    public async Task FullCircuit_AccountsThenContacts_AreSent_AndTheQueueIsUpdated()
    {
        await RequireOnlyTestRowsPendingAsync();
        await InsertClientAsync("CRMIT-CL-10", 99999981, 0, "Sede IT");
        await InsertClientAsync("CRMIT-CL-11", 99999981, 1, "Estabelecimento IT");
        await InsertContactAsync("CRMIT-K-10", "CRMIT-CL-11", "Pessoa IT");
        var rig = Build();

        var summary = await rig.Runner.RunCycleAsync(CancellationToken.None);

        // 2 pedidos, contas primeiro; cada estabelecimento é uma conta própria
        Assert.Equal(new[] { "ImportAccounts", "ImportContacts" },
            rig.Handler.Requests.Select(r => r.Url[(r.Url.LastIndexOf('=') + 1)..]).ToArray());
        using var accounts = JsonDocument.Parse(rig.Handler.Requests[0].Body);
        Assert.Equal(new[] { "99999981-0", "99999981-1" },
            accounts.RootElement.GetProperty("accounts").EnumerateArray().Select(a => a.GetProperty("code").GetString()!).Order().ToArray());
        using var contacts = JsonDocument.Parse(rig.Handler.Requests[1].Body);
        Assert.Equal("99999981-1", contacts.RootElement.GetProperty("contacts")[0].GetProperty("accountCode").GetString());

        Assert.Equal(3, summary.Sent);
        Assert.Equal("ENVIADO", await StatusOfAsync("CRMIT-CL-10", "CONTA"));
        Assert.Equal("ENVIADO", await StatusOfAsync("CRMIT-CL-11", "CONTA"));
        Assert.Equal("ENVIADO", await StatusOfAsync("CRMIT-K-10", "CONTACTO"));
        Assert.Equal("Updated", await TestDb.ScalarAsync<string>("SELECT TOP 1 RTRIM(acaocrm) FROM dbo.u_crmfila WHERE stamporigem = 'CRMIT-CL-10'"));
        Assert.StartsWith("crm-", await TestDb.ScalarAsync<string>("SELECT TOP 1 RTRIM(idcrm) FROM dbo.u_crmfila WHERE stamporigem = 'CRMIT-CL-10'"), StringComparison.Ordinal);
    }

    [DbFact]
    public async Task AnIntegratedChange_IsSentAgain_ButANonIntegratedChange_IsNot()
    {
        await RequireOnlyTestRowsPendingAsync();
        await InsertClientAsync("CRMIT-CL-12", 99999982, 0, "Antes");
        var rig = Build();
        await rig.Runner.RunCycleAsync(CancellationToken.None);
        Assert.Single(rig.Handler.Requests);

        await TestDb.ExecAsync("UPDATE dbo.cl SET obs = 'nota interna', contacto = 'alguém' WHERE clstamp = 'CRMIT-CL-12'");
        await rig.Runner.RunCycleAsync(CancellationToken.None);
        Assert.Single(rig.Handler.Requests);   // campo não integrado: nada novo

        await TestDb.ExecAsync("UPDATE dbo.cl SET nome = 'Depois' WHERE clstamp = 'CRMIT-CL-12'");
        await rig.Runner.RunCycleAsync(CancellationToken.None);
        Assert.Equal(2, rig.Handler.Requests.Count);
        Assert.Contains("\"name\":\"Depois\"", rig.Handler.Requests[1].Body, StringComparison.Ordinal);
    }

    [DbFact]
    public async Task OnlyTheCountryChanged_StillSendsTheAccount()
    {
        await RequireOnlyTestRowsPendingAsync();
        await InsertClientAsync("CRMIT-CL-13", 99999983, 0, "Cliente", "Portugal");
        var rig = Build();
        await rig.Runner.RunCycleAsync(CancellationToken.None);

        await TestDb.ExecAsync("UPDATE dbo.cl2 SET descpais = 'França' WHERE cl2stamp = 'CRMIT-CL-13'");
        await rig.Runner.RunCycleAsync(CancellationToken.None);

        Assert.Equal(2, rig.Handler.Requests.Count);
        Assert.Contains("\"country\":\"França\"", rig.Handler.Requests[1].Body, StringComparison.Ordinal);
    }

    [DbFact]
    public async Task DeletedContact_BecomesNoSend_WithoutCallingTheApi()
    {
        await RequireOnlyTestRowsPendingAsync();
        await InsertClientAsync("CRMIT-CL-14", 99999984, 0, "Cliente");
        await InsertContactAsync("CRMIT-K-14", "CRMIT-CL-14", "Pessoa");
        var rig = Build();
        await rig.Runner.RunCycleAsync(CancellationToken.None);
        var calls = rig.Handler.Requests.Count;

        await TestDb.ExecAsync("DELETE FROM dbo.u_clcontact WHERE u_clcontactstamp = 'CRMIT-K-14'");
        await rig.Runner.RunCycleAsync(CancellationToken.None);

        Assert.Equal(calls, rig.Handler.Requests.Count);
        Assert.Equal("SEM_ENVIO", await StatusOfAsync("CRMIT-K-14", "CONTACTO"));
        Assert.Contains(rig.Log.Entries, e => e.Result == "SEM_ENVIO" && e.Code == "CRMIT-K-14");
    }

    [DbFact]
    public async Task ApiError_MarksError_ThenManualResetSendsItAgain()
    {
        await RequireOnlyTestRowsPendingAsync();
        await InsertClientAsync("CRMIT-CL-15", 99999985, 0, "Cliente");
        var failing = true;
        var rig = Build((req, body) => failing
            ? Task.FromResult(new HttpResponseMessage((HttpStatusCode)422) { Content = new StringContent("{\"error\":\"Invalid data content!\"}") })
            : OkResponder(req, body));

        await rig.Runner.RunCycleAsync(CancellationToken.None);
        Assert.Equal("ERRO", await StatusOfAsync("CRMIT-CL-15", "CONTA"));
        Assert.Contains("422", await TestDb.ScalarAsync<string>("SELECT TOP 1 ultimamensagem FROM dbo.u_crmfila WHERE stamporigem = 'CRMIT-CL-15'"), StringComparison.Ordinal);

        await rig.Runner.RunCycleAsync(CancellationToken.None);   // sem reenvio automático
        Assert.Single(rig.Handler.Requests);

        failing = false;
        await TestDb.ExecAsync("EXEC dbo.up_crm_repor @codigo = '99999985-0'");
        await rig.Runner.RunCycleAsync(CancellationToken.None);
        Assert.Equal("ENVIADO", await StatusOfAsync("CRMIT-CL-15", "CONTA"));
    }

    [DbFact]
    public async Task ContactWaits_WhileItsAccountIsInError()
    {
        await RequireOnlyTestRowsPendingAsync();
        await InsertClientAsync("CRMIT-CL-16", 99999986, 0, "Cliente");
        await InsertContactAsync("CRMIT-K-16", "CRMIT-CL-16", "Pessoa");
        var rig = Build((req, body) => req.RequestUri!.Query.Contains("ImportAccounts", StringComparison.Ordinal)
            ? Task.FromResult(new HttpResponseMessage((HttpStatusCode)422) { Content = new StringContent("{\"error\":\"x\"}") })
            : OkResponder(req, body));

        await rig.Runner.RunCycleAsync(CancellationToken.None);

        Assert.Equal("ERRO", await StatusOfAsync("CRMIT-CL-16", "CONTA"));
        Assert.Equal("PENDENTE", await StatusOfAsync("CRMIT-K-16", "CONTACTO"));
        Assert.DoesNotContain(rig.Handler.Requests, r => r.Url.Contains("ImportContacts", StringComparison.Ordinal));
    }

    [DbFact]
    public async Task ValueAboveTheLimit_IsTruncatedAndWarned()
    {
        await RequireOnlyTestRowsPendingAsync();
        await InsertClientAsync("CRMIT-CL-17", 99999987, 0, "NomeMuitoComprido");
        var rig = Build(options: Options(new() { ["CONTA"] = new() { ["name"] = 8 } }));

        await rig.Runner.RunCycleAsync(CancellationToken.None);

        Assert.Contains("\"name\":\"NomeMuit\"", rig.Handler.Requests[0].Body, StringComparison.Ordinal);
        var warning = Assert.Single(rig.Log.Entries, e => e.Result == "TRUNCADO");
        Assert.Equal("CRMIT-CL-17", warning.Stamp);
        Assert.DoesNotContain("NomeMuitoComprido", warning.Message + warning.Detail, StringComparison.Ordinal);
    }

    [DbFact]
    public async Task StoppedMidBatch_IsRecoveredOnTheNextStart()
    {
        await RequireOnlyTestRowsPendingAsync();
        await InsertClientAsync("CRMIT-CL-18", 99999988, 0, "Cliente");
        using var cts = new CancellationTokenSource();
        var rig = Build(async (_, _) =>
        {
            await cts.CancelAsync();   // o serviço pára a meio do envio
            throw new OperationCanceledException(cts.Token);
        });

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => rig.Runner.RunCycleAsync(cts.Token));
        Assert.Equal("A_PROCESSAR", await StatusOfAsync("CRMIT-CL-18", "CONTA"));

        var rig2 = Build();
        Assert.True(await rig2.Runner.RecoverAsync(CancellationToken.None) >= 1);
        await rig2.Runner.RunCycleAsync(CancellationToken.None);

        Assert.Equal("ENVIADO", await StatusOfAsync("CRMIT-CL-18", "CONTA"));
    }

    [DbFact]
    public async Task NetworkFailure_MarksTheBatchAsError()
    {
        await RequireOnlyTestRowsPendingAsync();
        await InsertClientAsync("CRMIT-CL-19", 99999989, 0, "Cliente");
        var rig = Build((_, _) => throw new HttpRequestException("sem rede"));

        await rig.Runner.RunCycleAsync(CancellationToken.None);

        Assert.Equal("ERRO", await StatusOfAsync("CRMIT-CL-19", "CONTA"));
        Assert.Contains(rig.Log.Entries, e => e.Result == "FALHA_REDE");
    }
}
