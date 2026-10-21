using System.Text.Json;
using SigmaCode.Landeiro.CrmSync.Core.Config;
using SigmaCode.Landeiro.CrmSync.Core.Domain;
using SigmaCode.Landeiro.CrmSync.Core.Rules;

namespace SigmaCode.Landeiro.CrmSync.Core.Tests;

public class FieldTruncatorTests
{
    [Fact]
    public void ValueWithinLimit_IsUnchanged()
    {
        Assert.Equal("abc", FieldTruncator.Truncate("abc", 5, out var truncated));
        Assert.False(truncated);
    }

    [Fact]
    public void ValueExactlyAtLimit_IsUnchanged()
    {
        Assert.Equal("abcde", FieldTruncator.Truncate("abcde", 5, out var truncated));
        Assert.False(truncated);
    }

    [Fact]
    public void ValueAboveLimit_IsCut()
    {
        Assert.Equal("abcde", FieldTruncator.Truncate("abcdefgh", 5, out var truncated));
        Assert.True(truncated);
    }

    [Theory]
    [InlineData(null)]
    [InlineData(0)]
    [InlineData(-1)]
    public void EmptyLimit_MeansNoTruncation(int? limit)
    {
        Assert.Equal("abcdefgh", FieldTruncator.Truncate("abcdefgh", limit, out var truncated));
        Assert.False(truncated);
    }

    [Fact]
    public void NullValue_BecomesEmptyText()
    {
        Assert.Equal(string.Empty, FieldTruncator.Truncate(null, 5, out var truncated));
        Assert.False(truncated);
    }

    [Fact]
    public void Cut_NeverSplitsASurrogatePair()
    {
        // "ab" + emoji (2 chars): limite 3 cairia a meio do emoji
        var result = FieldTruncator.Truncate("ab\U0001F600cd", 3, out var truncated);
        Assert.Equal("ab", result);
        Assert.True(truncated);
    }
}

public class PayloadBuilderTests
{
    private static SourceRow Row(string stamp, params (string Name, string Value)[] fields) =>
        new(stamp, null, fields.Select(f => new KeyValuePair<string, string>(f.Name, f.Value)).ToList());

    [Fact]
    public void Build_ProducesTheApiShape_WithFieldsInViewOrder()
    {
        var rows = new[]
        {
            Row("S1", ("code", "13444-0"), ("name", "Sigma"), ("accountType", "CLI")),
            Row("S2", ("code", "13444-1"), ("name", "Sigma Loja"), ("accountType", "CLI")),
        };

        var payload = PayloadBuilder.Build("accounts", rows, null);

        Assert.Equal(
            "{\"accounts\":[{\"code\":\"13444-0\",\"name\":\"Sigma\",\"accountType\":\"CLI\"},{\"code\":\"13444-1\",\"name\":\"Sigma Loja\",\"accountType\":\"CLI\"}]}",
            payload.Json);
        Assert.Empty(payload.Warnings);
    }

    [Fact]
    public void Build_DoesNotInventFieldsTheViewDoesNotHave()
    {
        var payload = PayloadBuilder.Build("accounts", new[] { Row("S1", ("code", "1-0")) }, null);

        using var doc = JsonDocument.Parse(payload.Json);
        var account = doc.RootElement.GetProperty("accounts")[0];
        foreach (var forbidden in new[] { "obsCreation", "obsExclusion", "currentBalance", "earliestDueDate" })
            Assert.False(account.TryGetProperty(forbidden, out _), forbidden);
    }

    [Fact]
    public void Build_KeepsAccentsAndEscapesQuotes()
    {
        var payload = PayloadBuilder.Build("contacts", new[] { Row("S1", ("name", "João \"Zé\" Conceição")) }, null);

        Assert.Contains("João", payload.Json, StringComparison.Ordinal);
        using var doc = JsonDocument.Parse(payload.Json);
        Assert.Equal("João \"Zé\" Conceição", doc.RootElement.GetProperty("contacts")[0].GetProperty("name").GetString());
    }

    [Fact]
    public void Build_TruncatesFieldsAboveTheLimit_AndWarnsWithoutTheValue()
    {
        var limits = new Dictionary<string, int?> { ["name"] = 5, ["email"] = null };
        var rows = new[] { Row("S1", ("name", "ValorMuitoLongo"), ("email", "um.email.muito.longo@exemplo.pt")) };

        var payload = PayloadBuilder.Build("accounts", rows, limits);

        using var doc = JsonDocument.Parse(payload.Json);
        var account = doc.RootElement.GetProperty("accounts")[0];
        Assert.Equal("Valor", account.GetProperty("name").GetString());
        Assert.Equal("um.email.muito.longo@exemplo.pt", account.GetProperty("email").GetString());

        var warning = Assert.Single(payload.Warnings);
        Assert.Equal("S1", warning.SourceStamp);
        Assert.Equal("name", warning.Field);
        Assert.Equal(5, warning.Limit);
        Assert.DoesNotContain("ValorMuitoLongo", warning.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public void Build_LimitLookupIsCaseInsensitive()
    {
        var payload = PayloadBuilder.Build("accounts", new[] { Row("S1", ("city", "PORTO-EXTRA")) },
            new Dictionary<string, int?> { ["CITY"] = 5 });

        Assert.Single(payload.Warnings);
        Assert.Contains("\"city\":\"PORTO\"", payload.Json, StringComparison.Ordinal);
    }

    [Fact]
    public void Build_LongText_IsSentWhenThereIsNoLimit()
    {
        var obs = new string('x', 20000);
        var payload = PayloadBuilder.Build("contacts", new[] { Row("S1", ("obs", obs)) }, new Dictionary<string, int?>());

        using var doc = JsonDocument.Parse(payload.Json);
        Assert.Equal(20000, doc.RootElement.GetProperty("contacts")[0].GetProperty("obs").GetString()!.Length);
    }
}

public class ApiResponseInterpreterTests
{
    private static BatchOutcome Run(int? status, string? body, string? error = null, params string[] codes) =>
        ApiResponseInterpreter.Interpret(new ApiCallResult(status, body, error), codes, "accounts", "account");

    [Fact]
    public void Status200_AllRecordsAreSaved_WithIdAndAction()
    {
        var body = "{\"accounts\":[{\"row\":0,\"account\":\"1-0\",\"action\":\"Updated\",\"id\":\"A\"},{\"row\":1,\"account\":\"2-0\",\"action\":\"Created\",\"id\":\"B\"}],\"success\":2,\"fail\":0}";

        var outcome = Run(200, body, null, "1-0", "2-0");

        Assert.Equal(BatchFailureKind.None, outcome.Kind);
        Assert.All(outcome.Items, i => Assert.True(i.Success));
        Assert.Equal("A", outcome.Items[0].CrmId);
        Assert.Equal("Updated", outcome.Items[0].Action);
        Assert.Equal("B", outcome.Items[1].CrmId);
    }

    [Fact]
    public void Status200_RecordMissingFromResponse_IsAnError()
    {
        var body = "{\"accounts\":[{\"row\":0,\"account\":\"1-0\",\"action\":\"Updated\",\"id\":\"A\"}]}";

        var outcome = Run(200, body, null, "1-0", "2-0");

        Assert.True(outcome.Items[0].Success);
        Assert.False(outcome.Items[1].Success);
        Assert.Equal(BatchFailureKind.Partial, outcome.Kind);
    }

    [Fact]
    public void Status206_MatchesResultsByRow_NotByOrder()
    {
        // O registo da linha 1 vem primeiro na lista e o da linha 0 falhou (não vem)
        var body = "{\"accounts\":[{\"row\":1,\"account\":\"2-0\",\"action\":\"Updated\",\"id\":\"B\"}],\"success\":1,\"fail\":1}";

        var outcome = Run(206, body, null, "1-0", "2-0");

        Assert.False(outcome.Items[0].Success);
        Assert.True(outcome.Items[1].Success);
        Assert.Equal("B", outcome.Items[1].CrmId);
        Assert.Equal(BatchFailureKind.Partial, outcome.Kind);
    }

    [Fact]
    public void Status206_EntryWithFailedActionOrError_IsAnError()
    {
        var body = "{\"accounts\":[{\"row\":0,\"account\":\"1-0\",\"action\":\"Failed\",\"id\":\"\"},{\"row\":1,\"account\":\"2-0\",\"action\":\"Updated\",\"id\":\"B\",\"error\":\"campo inválido\"}]}";

        var outcome = Run(206, body, null, "1-0", "2-0");

        Assert.False(outcome.Items[0].Success);
        Assert.False(outcome.Items[1].Success);
        Assert.Contains("campo inválido", outcome.Items[1].Message, StringComparison.Ordinal);
    }

    [Fact]
    public void ResponseCode_DifferentFromSentCode_IsAnError()
    {
        var body = "{\"accounts\":[{\"row\":0,\"account\":\"OUTRO\",\"action\":\"Updated\",\"id\":\"A\"}]}";

        var outcome = Run(200, body, null, "1-0");

        Assert.False(outcome.Items[0].Success);
        Assert.Contains("diferente", outcome.Items[0].Message, StringComparison.Ordinal);
    }

    [Fact]
    public void EntryWithoutIdOrAction_IsNotConfirmedAsSaved()
    {
        var body = "{\"accounts\":[{\"row\":0,\"account\":\"1-0\"}]}";

        Assert.False(Run(200, body, null, "1-0").Items[0].Success);
    }

    [Fact]
    public void RowAsText_IsAccepted_AndMissingRowFallsBackToPosition()
    {
        var textRow = "{\"accounts\":[{\"row\":\"0\",\"account\":\"1-0\",\"action\":\"Updated\",\"id\":\"A\"}]}";
        var noRow = "{\"accounts\":[{\"account\":\"1-0\",\"action\":\"Updated\",\"id\":\"A\"}]}";

        Assert.True(Run(200, textRow, null, "1-0").Items[0].Success);
        Assert.True(Run(200, noRow, null, "1-0").Items[0].Success);
    }

    [Fact]
    public void Status422_AllRecordsFail_WithTheApiErrorText()
    {
        var outcome = Run(422, "{\"error\":\"Invalid data content!\"}", null, "1-0", "2-0");

        Assert.Equal(BatchFailureKind.InvalidRequest, outcome.Kind);
        Assert.All(outcome.Items, i =>
        {
            Assert.False(i.Success);
            Assert.Contains("Invalid data content!", i.Message, StringComparison.Ordinal);
        });
    }

    [Theory]
    [InlineData(401)]
    [InlineData(403)]
    public void Status401And403_AreAuthenticationFailures(int status)
    {
        var outcome = Run(status, "{\"error\":\"Unauthorized\"}", null, "1-0");

        Assert.Equal(BatchFailureKind.Authentication, outcome.Kind);
        Assert.False(outcome.Items[0].Success);
    }

    [Fact]
    public void NoStatus_IsANetworkFailure_ForTheWholeBatch()
    {
        var outcome = Run(null, null, "Timeout após 60s", "1-0", "2-0");

        Assert.Equal(BatchFailureKind.Network, outcome.Kind);
        Assert.Equal(2, outcome.Items.Count);
        Assert.All(outcome.Items, i => Assert.False(i.Success));
        Assert.Contains("Timeout", outcome.Items[0].Message, StringComparison.Ordinal);
    }

    [Fact]
    public void Status500_IsAServerFailure()
    {
        Assert.Equal(BatchFailureKind.Server, Run(500, "erro", null, "1-0").Kind);
    }

    [Fact]
    public void UnexpectedStatus_IsAnError()
    {
        var outcome = Run(404, "x", null, "1-0");

        Assert.False(outcome.Items[0].Success);
        Assert.Equal(BatchFailureKind.InvalidRequest, outcome.Kind);
    }

    [Theory]
    [InlineData("isto não é json")]
    [InlineData("")]
    [InlineData("{\"outra\":[]}")]
    [InlineData("[1,2,3]")]
    public void Status200_WithInvalidBody_FailsEveryRecord(string body)
    {
        var outcome = Run(200, body, null, "1-0");

        Assert.Equal(BatchFailureKind.InvalidResponse, outcome.Kind);
        Assert.False(outcome.Items[0].Success);
    }

    [Fact]
    public void ErrorMessage_IsLimitedAndSingleLine()
    {
        var outcome = Run(422, "{\"error\":\"" + new string('x', 5000) + "\"}", null, "1-0");

        Assert.True(outcome.Items[0].Message!.Length < 300);
        Assert.DoesNotContain("\n", outcome.Items[0].Message!, StringComparison.Ordinal);
    }

    [Fact]
    public void Status422_WithNonJsonBody_DoesNotEchoTheBody()
    {
        var outcome = Run(422, "<html>conteúdo arbitrário com dados</html>", null, "1-0");

        Assert.DoesNotContain("conteúdo arbitrário", outcome.Items[0].Message, StringComparison.Ordinal);
    }
}

public class SyncOptionsValidatorTests
{
    private static SyncOptions Valid() => new()
    {
        ApiBaseUrl = "http://host/index.php",
        Sources =
        {
            new SourceOptions
            {
                Name = "CL-CONTA", Order = 1, Entity = "CONTA", AccountType = "CLI", Origins = { "CL", "CL2" },
                View = "u_v_crm_conta_cl", Endpoint = "ImportAccounts", RequestListProperty = "accounts",
                ResponseListProperty = "accounts", ResponseCodeProperty = "account",
            },
        },
    };

    [Fact]
    public void ValidConfiguration_HasNoErrors() => Assert.Empty(SyncOptionsValidator.Validate(Valid()));

    [Fact]
    public void Defaults_AreFiveMinutes_AndSevenDaysOfLogs()
    {
        var o = new SyncOptions();
        Assert.Equal(5, o.IntervalMinutes);
        Assert.Equal(7, o.LogRetentionDays);
    }

    [Fact]
    public void SendDelay_DefaultsToOneMinute_AndCannotBeNegative()
    {
        var o = Valid();
        Assert.Equal(60, o.SendDelaySeconds);

        o.SendDelaySeconds = -1;
        Assert.Contains(SyncOptionsValidator.Validate(o), e => e.Contains("SendDelaySeconds", StringComparison.Ordinal));
    }

    [Theory]
    [InlineData(0)]
    [InlineData(1001)]
    public void BatchSize_OutOfRange_IsRejected(int size)
    {
        var o = Valid();
        o.BatchSize = size;
        Assert.Contains(SyncOptionsValidator.Validate(o), e => e.Contains("BatchSize", StringComparison.Ordinal));
    }

    [Fact]
    public void MissingApiUrl_IsRejected()
    {
        var o = Valid();
        o.ApiBaseUrl = "";
        Assert.Contains(SyncOptionsValidator.Validate(o), e => e.Contains("ApiBaseUrl", StringComparison.Ordinal));
    }

    [Fact]
    public void TwoSourcesForTheSameEntityAndType_AreRejected()
    {
        var o = Valid();
        o.Sources.Add(o.Sources[0]);
        Assert.Contains(SyncOptionsValidator.Validate(o), e => e.Contains("mais do que uma origem", StringComparison.Ordinal));
    }

    [Fact]
    public void InvalidEntityOrAccountType_AreRejected()
    {
        var o = Valid();
        o.Sources[0].Entity = "XPTO";
        o.Sources[0].AccountType = "ZZZ";
        var errors = SyncOptionsValidator.Validate(o);
        Assert.Contains(errors, e => e.Contains("Entity", StringComparison.Ordinal));
        Assert.Contains(errors, e => e.Contains("AccountType", StringComparison.Ordinal));
    }

    [Fact]
    public void NoSources_IsRejected()
    {
        var o = Valid();
        o.Sources.Clear();
        Assert.Contains(SyncOptionsValidator.Validate(o), e => e.Contains("Sources", StringComparison.Ordinal));
    }
}

public class FieldSanitizerTests
{
    [Theory]
    [InlineData("geral@sigmacode.pt", "geral@sigmacode.pt", null)]
    [InlineData("  geral@sigmacode.pt  ", "geral@sigmacode.pt", null)]
    [InlineData("a@x.pt; b@y.pt", "a@x.pt", FieldSanitizer.EmailAdjusted)]
    [InlineData("correio@realsabor.pt; raquel@realsabor.pt - luis@realsabor.pt", "correio@realsabor.pt", FieldSanitizer.EmailAdjusted)]
    [InlineData("a@x.pt , b@y.pt", "a@x.pt", FieldSanitizer.EmailAdjusted)]
    [InlineData("Não Têm", "", FieldSanitizer.EmailInvalid)]
    [InlineData("sem arroba.pt", "", FieldSanitizer.EmailInvalid)]
    [InlineData("a@b", "", FieldSanitizer.EmailInvalid)]
    [InlineData("", "", null)]
    [InlineData("   ", "", null)]
    [InlineData("<a@x.pt>", "a@x.pt", FieldSanitizer.EmailAdjusted)]
    [InlineData("(a@x.pt)", "a@x.pt", FieldSanitizer.EmailAdjusted)]
    [InlineData("Rui Silva <a@x.pt>", "a@x.pt", FieldSanitizer.EmailAdjusted)]
    [InlineData("mailto:a@x.pt", "a@x.pt", FieldSanitizer.EmailAdjusted)]
    [InlineData("a@x.pt.", "a@x.pt", FieldSanitizer.EmailAdjusted)]
    [InlineData("a@x.pt/b@y.pt", "a@x.pt", FieldSanitizer.EmailAdjusted)]
    [InlineData("a@x.pt b@y.pt", "a@x.pt", FieldSanitizer.EmailAdjusted)]
    [InlineData("a@x.pt​b@y.pt", "a@x.pt", FieldSanitizer.EmailAdjusted)]
    [InlineData("Joao.Silva+loja@Loja-Norte.Exemplo.PT", "Joao.Silva+loja@Loja-Norte.Exemplo.PT", null)]
    [InlineData("joão@x.pt", "", FieldSanitizer.EmailInvalid)]
    [InlineData("a..b@x.pt", "", FieldSanitizer.EmailInvalid)]
    [InlineData("a@-x.pt", "", FieldSanitizer.EmailInvalid)]
    public void NormalizeEmail_KeepsAValidOne_TakesTheFirstValid_OrSendsEmpty(string input, string expected, string? expectedRule)
    {
        var result = FieldSanitizer.NormalizeEmail(input, out var rule);

        Assert.Equal(expected, result);
        Assert.Equal(expectedRule, rule);
    }

    [Fact]
    public void NormalizeContactName_ReplacesAnEmptyNameOnly()
    {
        Assert.Equal("Sem nome", FieldSanitizer.NormalizeContactName("  ", out var rule));
        Assert.Equal(FieldSanitizer.NameMissing, rule);
        Assert.Equal("Ana", FieldSanitizer.NormalizeContactName(" Ana ", out var none));
        Assert.Null(none);
    }

    [Fact]
    public void Build_AdjustsEmailAndContactName_AndReportsWithoutTheValue()
    {
        var rows = new[]
        {
            new SourceRow("S1", null, new List<KeyValuePair<string, string>> { new("name", ""), new("email", "Não Têm") }),
            new SourceRow("S2", null, new List<KeyValuePair<string, string>> { new("name", "Rui"), new("email", "a@x.pt; b@y.pt") }),
        };

        var payload = PayloadBuilder.Build("contacts", rows, null);

        using var doc = JsonDocument.Parse(payload.Json);
        var list = doc.RootElement.GetProperty("contacts");
        Assert.Equal("Sem nome", list[0].GetProperty("name").GetString());
        Assert.Equal(string.Empty, list[0].GetProperty("email").GetString());
        Assert.Equal("a@x.pt", list[1].GetProperty("email").GetString());
        Assert.Equal(
            new[] { "S1:name:NOME_EM_FALTA", "S1:email:EMAIL_INVALIDO", "S2:email:EMAIL_AJUSTADO" },
            payload.Adjustments.Select(a => $"{a.SourceStamp}:{a.Field}:{a.Rule}").ToArray());
    }

    [Fact]
    public void Build_DoesNotReplaceAnEmptyNameOnAccounts()
    {
        var payload = PayloadBuilder.Build("accounts",
            new[] { new SourceRow("S1", null, new List<KeyValuePair<string, string>> { new("name", "") }) }, null);

        Assert.Contains("\"name\":\"\"", payload.Json, StringComparison.Ordinal);
        Assert.Empty(payload.Adjustments);
    }
}

public class PostalCodeTests
{
    [Theory]
    [InlineData("4410-387 ARCOZELO VNG", "4410-387", FieldSanitizer.PostalCodeAdjusted)]
    [InlineData("4410-387  Vila Nova de Gaia", "4410-387", FieldSanitizer.PostalCodeAdjusted)]
    [InlineData("4410-387", "4410-387", null)]
    [InlineData("  4410-387  ", "4410-387", null)]
    [InlineData("4410-3871 X", "4410-3871 X", null)]
    [InlineData("1000", "1000", null)]
    [InlineData("SW1A 1AA", "SW1A 1AA", null)]
    [InlineData("", "", null)]
    public void NormalizePostalCode_KeepsOnlyNnnnNnn_WhenTextFollows(string input, string expected, string? expectedRule)
    {
        Assert.Equal(expected, FieldSanitizer.NormalizePostalCode(input, out var rule));
        Assert.Equal(expectedRule, rule);
    }

    [Fact]
    public void Build_AdjustsThePostalCodeOnAccountsOnly()
    {
        var accounts = PayloadBuilder.Build("accounts",
            new[] { new SourceRow("S1", null, new List<KeyValuePair<string, string>> { new("postalCode", "4410-387 ARCOZELO VNG") }) }, null);
        var contacts = PayloadBuilder.Build("contacts",
            new[] { new SourceRow("S1", null, new List<KeyValuePair<string, string>> { new("postalCode", "4410-387 ARCOZELO VNG") }) }, null);

        Assert.Contains("\"postalCode\":\"4410-387\"", accounts.Json, StringComparison.Ordinal);
        Assert.Equal("postalCode", Assert.Single(accounts.Adjustments).Field);
        Assert.Contains("ARCOZELO", contacts.Json, StringComparison.Ordinal);
    }
}
