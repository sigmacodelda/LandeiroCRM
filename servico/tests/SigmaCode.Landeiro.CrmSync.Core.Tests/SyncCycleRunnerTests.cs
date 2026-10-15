using System.Text.Json;
using SigmaCode.Landeiro.CrmSync.Core.Config;
using SigmaCode.Landeiro.CrmSync.Core.Domain;
using SigmaCode.Landeiro.CrmSync.Core.Tests.Fakes;

namespace SigmaCode.Landeiro.CrmSync.Core.Tests;

public class SyncCycleRunnerTests
{
    private readonly FakeQueueStore _store = new();
    private readonly FakeSourceReader _reader = new();
    private readonly FakeApi _api = new();
    private readonly ListAuditLog _log = new();

    private static SyncOptions Options(int batchSize = 100) => new()
    {
        ApiBaseUrl = "http://host/index.php",
        BatchSize = batchSize,
        FieldLimits = { ["CONTA"] = new Dictionary<string, int?> { ["name"] = 10 } },
        Sources =
        {
            // Propositadamente fora de ordem: o serviço tem de ordenar por Order (contas antes de contactos)
            new SourceOptions
            {
                Name = "CL-CONTACTO", Order = 2, Entity = "CONTACTO", AccountType = "CLI", Origins = { "U_CLCONTACT" },
                View = "v_contacto", Endpoint = "ImportContacts", RequestListProperty = "contacts",
                ResponseListProperty = "contacts", ResponseCodeProperty = "contact", WaitsForEntity = "CONTA",
            },
            new SourceOptions
            {
                Name = "CL-CONTA", Order = 1, Entity = "CONTA", AccountType = "CLI", Origins = { "CL", "CL2" },
                View = "v_conta", Endpoint = "ImportAccounts", RequestListProperty = "accounts",
                ResponseListProperty = "accounts", ResponseCodeProperty = "account",
            },
        },
    };

    private SyncCycleRunner Runner(SyncOptions? options = null) => new(options ?? Options(), _store, _reader, _api, _log);

    private void Account(string stamp, string code, string name = "Cliente")
    {
        _reader.Add("v_conta", stamp, null, ("code", code), ("name", name), ("accountType", "CLI"));
        _store.Add("CONTA", stamp, code);
    }

    private void Contact(string stamp, string accountStamp, string accountCode, string name = "Pessoa")
    {
        _reader.Add("v_contacto", stamp, accountStamp, ("accountCode", accountCode), ("contactCode", stamp), ("name", name));
        _store.Add("CONTACTO", stamp, stamp);
    }

    // ---------- ordem ----------
    [Fact]
    public async Task Cycle_SendsAccountsBeforeContacts_WhateverTheConfigurationOrder()
    {
        Contact("K1", "A1", "1-0");
        Account("A1", "1-0");

        await Runner().RunCycleAsync(CancellationToken.None);

        Assert.Equal(new[] { "ImportAccounts", "ImportContacts" }, _api.Calls.Select(c => c.Endpoint).ToArray());
    }

    [Fact]
    public async Task ContactIsSentInTheSameCycle_WhenItsAccountWasJustSent()
    {
        Account("A1", "1-0");
        Contact("K1", "A1", "1-0");

        await Runner().RunCycleAsync(CancellationToken.None);

        Assert.Equal(QueueStatus.Sent, _store.Get("A1", "CONTA").Status);
        Assert.Equal(QueueStatus.Sent, _store.Get("K1", "CONTACTO").Status);
    }

    // ---------- envio e estados ----------
    [Fact]
    public async Task SuccessfulBatch_MarksSent_AndKeepsCrmIdAndAction()
    {
        Account("A1", "1-0");

        var summary = await Runner().RunCycleAsync(CancellationToken.None);

        var row = _store.Get("A1", "CONTA");
        Assert.Equal(QueueStatus.Sent, row.Status);
        Assert.Equal("id-0", row.CrmId);
        Assert.Equal("Updated", row.Action);
        Assert.Equal(1, summary.Sent);
        Assert.Equal(1, row.Attempts);
    }

    [Fact]
    public async Task RecordsAreSentInBatchesOfTheConfiguredSize()
    {
        for (var i = 0; i < 7; i++) Account($"A{i}", $"{i}-0");

        await Runner(Options(batchSize: 3)).RunCycleAsync(CancellationToken.None);

        Assert.Equal(3, _api.Calls.Count);   // 3 + 3 + 1
        Assert.All(_store.Rows, r => Assert.Equal(QueueStatus.Sent, r.Status));
    }

    [Fact]
    public async Task OnePartialResponse_UpdatesEachRecordOnItsOwn()
    {
        Account("A1", "1-0");
        Account("A2", "2-0");
        _api.Responder = (_, _) => new ApiCallResult(206,
            "{\"accounts\":[{\"row\":0,\"account\":\"1-0\",\"action\":\"Updated\",\"id\":\"X\"}],\"success\":1,\"fail\":1}", null);

        await Runner().RunCycleAsync(CancellationToken.None);

        Assert.Equal(QueueStatus.Sent, _store.Get("A1", "CONTA").Status);
        Assert.Equal(QueueStatus.Error, _store.Get("A2", "CONTA").Status);
        Assert.False(string.IsNullOrWhiteSpace(_store.Get("A2", "CONTA").Message));
    }

    [Fact]
    public async Task Status422_MarksEveryRecordOfTheBatchAsError()
    {
        Account("A1", "1-0");
        Account("A2", "2-0");
        _api.Responder = (_, _) => new ApiCallResult(422, "{\"error\":\"Invalid data content!\"}", null);

        var summary = await Runner().RunCycleAsync(CancellationToken.None);

        Assert.All(_store.Rows, r => Assert.Equal(QueueStatus.Error, r.Status));
        Assert.Equal(2, summary.Errors);
    }

    [Fact]
    public async Task NetworkFailure_MarksTheBatchAsError_AndHighlightsItInTheLog()
    {
        Account("A1", "1-0");
        _api.Responder = (_, _) => new ApiCallResult(null, null, "Ligação recusada");

        await Runner().RunCycleAsync(CancellationToken.None);

        Assert.Equal(QueueStatus.Error, _store.Get("A1", "CONTA").Status);
        Assert.Contains(_log.Entries, e => e.Result == "FALHA_REDE" && e.Level == AuditLevel.Error);
    }

    [Fact]
    public async Task AuthenticationFailure_MarksTheBatchAsError_AndHighlightsItInTheLog()
    {
        Account("A1", "1-0");
        _api.Responder = (_, _) => new ApiCallResult(401, "{\"error\":\"x\"}", null);

        await Runner().RunCycleAsync(CancellationToken.None);

        Assert.Equal(QueueStatus.Error, _store.Get("A1", "CONTA").Status);
        Assert.Contains(_log.Entries, e => e.Result == "FALHA_AUTENTICACAO" && e.Level == AuditLevel.Error);
    }

    [Fact]
    public async Task FailedRecords_AreNeverRetriedAutomatically()
    {
        Account("A1", "1-0");
        _api.Responder = (_, _) => new ApiCallResult(422, "{\"error\":\"x\"}", null);
        var runner = Runner();

        await runner.RunCycleAsync(CancellationToken.None);
        await runner.RunCycleAsync(CancellationToken.None);
        await runner.RunCycleAsync(CancellationToken.None);

        Assert.Single(_api.Calls);
        Assert.Equal(QueueStatus.Error, _store.Get("A1", "CONTA").Status);
    }

    [Fact]
    public async Task RecordMissingFromTheView_IsAnError_AndIsNotSent()
    {
        _store.Add("CONTA", "FANTASMA", "9-0");
        Account("A1", "1-0");

        await Runner().RunCycleAsync(CancellationToken.None);

        Assert.Equal(QueueStatus.Error, _store.Get("FANTASMA", "CONTA").Status);
        Assert.Contains("não encontrado", _store.Get("FANTASMA", "CONTA").Message, StringComparison.Ordinal);
        Assert.Equal(QueueStatus.Sent, _store.Get("A1", "CONTA").Status);
        Assert.DoesNotContain("FANTASMA", _api.Calls[0].Body, StringComparison.Ordinal);
    }

    // ---------- eliminações ----------
    [Fact]
    public async Task DeleteOperation_IsMarkedNoSend_WithoutCallingTheApi()
    {
        _store.Add("CONTA", "A1", "1-0", QueueOperation.Delete);
        _store.Add("CONTACTO", "K1", "K1", QueueOperation.Delete);

        var summary = await Runner().RunCycleAsync(CancellationToken.None);

        Assert.Empty(_api.Calls);
        Assert.All(_store.Rows, r => Assert.Equal(QueueStatus.NotSent, r.Status));
        Assert.Equal(2, summary.NotSent);
        Assert.Contains(_log.Entries, e => e.Result == "SEM_ENVIO" && e.Code == "1-0");
    }

    [Fact]
    public async Task DeleteAndUpsertInTheSameBatch_OnlyTheUpsertGoesToTheApi()
    {
        _store.Add("CONTA", "A0", "0-0", QueueOperation.Delete);
        Account("A1", "1-0");

        await Runner().RunCycleAsync(CancellationToken.None);

        Assert.Single(_api.Calls);
        Assert.DoesNotContain("0-0", _api.Calls[0].Body, StringComparison.Ordinal);
        Assert.Equal(QueueStatus.NotSent, _store.Get("A0", "CONTA").Status);
        Assert.Equal(QueueStatus.Sent, _store.Get("A1", "CONTA").Status);
    }

    // ---------- contactos esperam pela conta ----------
    [Fact]
    public async Task ContactWaits_WhenItsAccountIsInError()
    {
        _store.Add("CONTA", "A1", "1-0", status: QueueStatus.Error);
        _reader.Add("v_conta", "A1", null, ("code", "1-0"));
        Contact("K1", "A1", "1-0");

        var summary = await Runner().RunCycleAsync(CancellationToken.None);

        Assert.Equal(QueueStatus.Pending, _store.Get("K1", "CONTACTO").Status);
        Assert.Empty(_api.Calls);
        Assert.Equal(1, summary.WaitingForAccount);
        Assert.Contains(_log.Entries, e => e.Result == "AGUARDA_CONTA");
    }

    [Fact]
    public async Task ContactWaits_WhenItsAccountFailsInTheSameCycle_AndIsSentAfterManualReset()
    {
        Account("A1", "1-0");
        Contact("K1", "A1", "1-0");
        _api.Responder = (ep, body) => ep == "ImportAccounts"
            ? new ApiCallResult(422, "{\"error\":\"x\"}", null)
            : FakeApi.OkAll(body, ep);
        var runner = Runner();

        await runner.RunCycleAsync(CancellationToken.None);
        Assert.Equal(QueueStatus.Error, _store.Get("A1", "CONTA").Status);
        Assert.Equal(QueueStatus.Pending, _store.Get("K1", "CONTACTO").Status);

        // Reposição manual da conta e novo ciclo: agora a conta é enviada e o contacto segue
        _store.Get("A1", "CONTA").Status = QueueStatus.Pending;
        _api.Responder = null;
        await runner.RunCycleAsync(CancellationToken.None);

        Assert.Equal(QueueStatus.Sent, _store.Get("A1", "CONTA").Status);
        Assert.Equal(QueueStatus.Sent, _store.Get("K1", "CONTACTO").Status);
    }

    [Fact]
    public async Task ContactIsNotBlocked_WhenItsAccountWasNeverQueued()
    {
        _reader.Add("v_conta", "A1", null, ("code", "1-0"));   // a conta existe na view mas nunca foi enfileirada
        Contact("K1", "A1", "1-0");

        await Runner().RunCycleAsync(CancellationToken.None);

        Assert.Equal(QueueStatus.Sent, _store.Get("K1", "CONTACTO").Status);
    }

    [Fact]
    public async Task WaitingContacts_DoNotCauseAnEndlessLoop_AndTheOthersStillGo()
    {
        _store.Add("CONTA", "A1", "1-0", status: QueueStatus.Error);
        _reader.Add("v_conta", "A1", null, ("code", "1-0"));
        for (var i = 0; i < 5; i++) Contact($"KW{i}", "A1", "1-0");
        Account("A2", "2-0");
        Contact("KOK", "A2", "2-0");

        await Runner(Options(batchSize: 2)).RunCycleAsync(CancellationToken.None);

        Assert.Equal(QueueStatus.Sent, _store.Get("KOK", "CONTACTO").Status);
        for (var i = 0; i < 5; i++) Assert.Equal(QueueStatus.Pending, _store.Get($"KW{i}", "CONTACTO").Status);
    }

    // ---------- ajustes para o CRM aceitar a linha ----------
    [Fact]
    public async Task ContactWithoutName_IsSentAsSemNome_AndWarnedWithoutTheValue()
    {
        Account("A1", "1-0");
        Contact("K1", "A1", "1-0", name: "");

        await Runner().RunCycleAsync(CancellationToken.None);

        using var doc = JsonDocument.Parse(_api.Calls[1].Body);
        Assert.Equal("Sem nome", doc.RootElement.GetProperty("contacts")[0].GetProperty("name").GetString());
        var warning = Assert.Single(_log.Entries, e => e.Result == "NOME_EM_FALTA");
        Assert.Equal(AuditLevel.Warning, warning.Level);
        Assert.Equal("K1", warning.Stamp);
        Assert.Equal(QueueStatus.Sent, _store.Get("K1", "CONTACTO").Status);
    }

    // ---------- truncagem ----------
    [Fact]
    public async Task ValueAboveTheLimit_IsTruncatedInTheJson_AndWarnedWithoutTheValue()
    {
        Account("A1", "1-0", name: "NomeMuitoMuitoLongo");

        var summary = await Runner().RunCycleAsync(CancellationToken.None);

        using var doc = JsonDocument.Parse(_api.Calls[0].Body);
        Assert.Equal("NomeMuitoM", doc.RootElement.GetProperty("accounts")[0].GetProperty("name").GetString());
        Assert.Equal(1, summary.Truncations);
        var warning = Assert.Single(_log.Entries, e => e.Result == "TRUNCADO");
        Assert.Equal(AuditLevel.Warning, warning.Level);
        Assert.Equal("A1", warning.Stamp);
        Assert.Contains("name", warning.Detail, StringComparison.Ordinal);
        Assert.DoesNotContain("NomeMuitoMuitoLongo", warning.Message + warning.Detail, StringComparison.Ordinal);
    }

    // ---------- recuperação ----------
    [Fact]
    public async Task OnStartup_RecordsLeftProcessing_GoBackToPending_AndAreSentAgain()
    {
        Account("A1", "1-0");
        _store.Get("A1", "CONTA").Status = QueueStatus.Processing;   // serviço caiu a meio de um lote
        var runner = Runner();

        var recovered = await runner.RecoverAsync(CancellationToken.None);
        await runner.RunCycleAsync(CancellationToken.None);

        Assert.Equal(1, recovered);
        Assert.Equal(QueueStatus.Sent, _store.Get("A1", "CONTA").Status);
        Assert.Contains(_log.Entries, e => e.Result == "RECUPERADO");
    }

    [Fact]
    public async Task StoppingMidBatch_LeavesTheBatchProcessing_AndTheNextStartRecoversIt()
    {
        Account("A1", "1-0");
        using var cts = new CancellationTokenSource();
        _api.BeforeResponse = _ => { cts.Cancel(); return Task.CompletedTask; };   // o serviço pára durante o pedido
        var runner = Runner();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => runner.RunCycleAsync(cts.Token));
        Assert.Equal(QueueStatus.Processing, _store.Get("A1", "CONTA").Status);

        // Novo arranque
        _api.BeforeResponse = null;
        await runner.RecoverAsync(CancellationToken.None);
        await runner.RunCycleAsync(CancellationToken.None);

        Assert.Equal(QueueStatus.Sent, _store.Get("A1", "CONTA").Status);
    }

    [Fact]
    public async Task AChangeDuringTheSend_CreatesANewPending_AndIsNotLost()
    {
        Account("A1", "1-0");
        // Enquanto o lote está a ser enviado (A_PROCESSAR), o PHC grava outra alteração -> novo PENDENTE
        _api.BeforeResponse = _ => { _store.Add("CONTA", "A1", "1-0"); return Task.CompletedTask; };
        var runner = Runner();

        await runner.RunCycleAsync(CancellationToken.None);

        Assert.Equal(QueueStatus.Sent, _store.Rows[0].Status);
        Assert.Equal(QueueStatus.Pending, _store.Rows[1].Status);

        _api.BeforeResponse = null;
        await runner.RunCycleAsync(CancellationToken.None);
        Assert.All(_store.Rows, r => Assert.Equal(QueueStatus.Sent, r.Status));
    }

    // ---------- falhas inesperadas ----------
    [Fact]
    public async Task UnexpectedException_WhileSending_MarksTheClaimedRecordsAsError()
    {
        Account("A1", "1-0");
        _api.Responder = (_, _) => throw new InvalidOperationException("estoirou com dados de teste");

        await Runner().RunCycleAsync(CancellationToken.None);

        var row = _store.Get("A1", "CONTA");
        Assert.Equal(QueueStatus.Error, row.Status);
        Assert.Contains("InvalidOperationException", row.Message, StringComparison.Ordinal);
        Assert.DoesNotContain("dados de teste", row.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task ViewReadFailure_LeavesTheRecordsPending_AndPropagates()
    {
        Account("A1", "1-0");
        _reader.ThrowOnRead = new InvalidOperationException("vista indisponível");

        await Assert.ThrowsAsync<InvalidOperationException>(() => Runner().RunCycleAsync(CancellationToken.None));

        Assert.Equal(QueueStatus.Pending, _store.Get("A1", "CONTA").Status);
    }

    // ---------- genérico ----------
    [Fact]
    public async Task ANewSource_NeedsOnlyConfiguration_NotNewCode()
    {
        // Fornecedores (FOR): uma view nova + uma entrada na configuração
        var options = Options();
        options.Sources.Add(new SourceOptions
        {
            Name = "FL-CONTA", Order = 1, Entity = "CONTA", AccountType = "FOR", Origins = { "FL" },
            View = "v_conta_fl", Endpoint = "ImportAccounts", RequestListProperty = "accounts",
            ResponseListProperty = "accounts", ResponseCodeProperty = "account",
        });
        _reader.Add("v_conta_fl", "F1", null, ("code", "77-0"), ("name", "Fornecedor"), ("accountType", "FOR"));
        _store.Add("CONTA", "F1", "77-0", accountType: "FOR", origin: "FL");

        await Runner(options).RunCycleAsync(CancellationToken.None);

        Assert.Equal(QueueStatus.Sent, _store.Get("F1", "CONTA").Status);
        Assert.Contains("\"FOR\"", _api.Calls.Single().Body, StringComparison.Ordinal);
    }

    [Fact]
    public async Task RecordsFromAnOriginNotConfigured_AreLeftAlone()
    {
        _store.Add("CONTA", "X1", "5-0", origin: "FL");   // FL não está configurada para CLI

        await Runner().RunCycleAsync(CancellationToken.None);

        Assert.Equal(QueueStatus.Pending, _store.Get("X1", "CONTA").Status);
        Assert.Empty(_api.Calls);
    }

    // ---------- RGPD ----------
    [Fact]
    public async Task AuditLog_NeverContainsPersonalDataFromTheRecords()
    {
        Account("A1", "1-0", name: "NomeSecreto");
        Contact("K1", "A1", "1-0", name: "PessoaSecreta");
        _api.Responder = (ep, body) => ep == "ImportAccounts"
            ? new ApiCallResult(422, "{\"error\":\"Invalid data content!\"}", null)
            : FakeApi.OkAll(body, ep);

        await Runner().RunCycleAsync(CancellationToken.None);

        var everything = string.Join('\n', _log.Entries.Select(e => $"{e.Origin}|{e.Entity}|{e.Code}|{e.Stamp}|{e.Result}|{e.Detail}|{e.Message}"));
        Assert.DoesNotContain("NomeSecreto", everything, StringComparison.Ordinal);
        Assert.DoesNotContain("PessoaSecreta", everything, StringComparison.Ordinal);
    }

    [Fact]
    public async Task EveryLogEntry_CarriesOriginEntityCodeAndStamp()
    {
        Account("A1", "1-0");

        await Runner().RunCycleAsync(CancellationToken.None);

        var entry = Assert.Single(_log.Entries, e => e.Result == "ENVIADO");
        Assert.Equal("CL", entry.Origin);
        Assert.Equal("CONTA", entry.Entity);
        Assert.Equal("1-0", entry.Code);
        Assert.Equal("A1", entry.Stamp);
        Assert.Equal("Updated/id-0", entry.Detail);
    }
}
