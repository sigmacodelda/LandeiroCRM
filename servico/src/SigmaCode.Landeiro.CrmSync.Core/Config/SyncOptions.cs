namespace SigmaCode.Landeiro.CrmSync.Core.Config;

/// <summary>
/// Configuração do serviço (secção "CrmSync" do appsettings.json). SEM segredos:
/// a connection string e o token vêm do DPAPI ou de variáveis de ambiente.
/// </summary>
public sealed class SyncOptions
{
    /// <summary>Intervalo entre ciclos, em minutos (por defeito 5).</summary>
    public double IntervalMinutes { get; set; } = 5;

    /// <summary>
    /// Espera mínima, em segundos, entre um registo entrar na fila e ser enviado (por defeito 60). Dá tempo a corrigir
    /// e voltar a gravar no PHC: as gravações seguidas juntam-se num só registo. 0 = enviar logo no ciclo seguinte.
    /// </summary>
    public int SendDelaySeconds { get; set; } = 60;

    /// <summary>Número máximo de registos por pedido à API (por defeito 100).</summary>
    public int BatchSize { get; set; } = 100;

    /// <summary>Os ficheiros de log com mais de N dias são apagados (por defeito 7). A fila nunca é limpa.</summary>
    public int LogRetentionDays { get; set; } = 7;

    /// <summary>Pasta dos logs diários.</summary>
    public string LogDirectory { get; set; } = "logs";

    /// <summary>Tempo máximo de espera por uma resposta da API.</summary>
    public int ApiTimeoutSeconds { get; set; } = 60;

    /// <summary>URL base da API, sem o entryPoint (ex.: http://host/carneslandeiro/index.php).</summary>
    public string ApiBaseUrl { get; set; } = string.Empty;

    /// <summary>Prefixo do cabeçalho Authorization. "Bearer" (standard) ou "Bearer:" (variante do PDF da Orcinus).</summary>
    public string AuthorizationPrefix { get; set; } = "Bearer";

    /// <summary>Nome do applock que garante uma só instância do serviço.</summary>
    public string InstanceLockName { get; set; } = "SigmaCode.Landeiro.CrmSync";

    /// <summary>Ficheiro com as credenciais protegidas por DPAPI (alternativa às variáveis de ambiente).</summary>
    public string CredentialsFile { get; set; } = string.Empty;

    /// <summary>Origens a processar. Acrescentar uma origem nova = acrescentar uma entrada aqui (sem alterar código).</summary>
    public List<SourceOptions> Sources { get; set; } = new();

    /// <summary>
    /// Limites de tamanho por entidade e por campo da API (ex.: CONTA → name → 255).
    /// Um limite vazio (null) ou em falta quer dizer "sem truncagem".
    /// </summary>
    public Dictionary<string, Dictionary<string, int?>> FieldLimits { get; set; } = new();
}

/// <summary>Uma origem: liga uma entidade da fila a uma view e a um endpoint da API.</summary>
public sealed class SourceOptions
{
    /// <summary>Nome livre, só para o log (ex.: "CL-CONTA").</summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>Ordem de processamento: contas (1) antes de contactos (2).</summary>
    public int Order { get; set; }

    /// <summary>Entidade da fila: CONTA ou CONTACTO.</summary>
    public string Entity { get; set; } = string.Empty;

    /// <summary>Tipo de conta da fila: CLI, FOR ou COL.</summary>
    public string AccountType { get; set; } = string.Empty;

    /// <summary>Tabelas de origem aceites na fila para esta origem (ex.: CL e CL2).</summary>
    public List<string> Origins { get; set; } = new();

    /// <summary>Nome da view com as colunas já nos nomes da API.</summary>
    public string View { get; set; } = string.Empty;

    /// <summary>Valor do entryPoint da API (ex.: ImportAccounts).</summary>
    public string Endpoint { get; set; } = string.Empty;

    /// <summary>Nome da lista no corpo do pedido (ex.: accounts / contacts).</summary>
    public string RequestListProperty { get; set; } = string.Empty;

    /// <summary>Nome da lista na resposta da API (ex.: accounts / contacts).</summary>
    public string ResponseListProperty { get; set; } = string.Empty;

    /// <summary>Nome do campo que identifica o registo na resposta (ex.: account / contact).</summary>
    public string ResponseCodeProperty { get; set; } = string.Empty;

    /// <summary>
    /// Entidade de que esta depende (contactos esperam pelas contas). Se a conta estiver PENDENTE ou em ERRO
    /// na fila, o registo espera pelo ciclo seguinte. Vazio = não depende de nenhuma.
    /// </summary>
    public string? WaitsForEntity { get; set; }
}

/// <summary>Valida a configuração no arranque, para falhar cedo e com uma mensagem clara.</summary>
public static class SyncOptionsValidator
{
    public static IReadOnlyList<string> Validate(SyncOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);
        var errors = new List<string>();

        if (options.IntervalMinutes <= 0) errors.Add("IntervalMinutes tem de ser maior que 0.");
        if (options.SendDelaySeconds < 0) errors.Add("SendDelaySeconds não pode ser negativo.");
        if (options.BatchSize is < 1 or > 1000) errors.Add("BatchSize tem de estar entre 1 e 1000.");
        if (options.LogRetentionDays < 1) errors.Add("LogRetentionDays tem de ser pelo menos 1.");
        if (options.ApiTimeoutSeconds < 1) errors.Add("ApiTimeoutSeconds tem de ser pelo menos 1.");
        if (string.IsNullOrWhiteSpace(options.ApiBaseUrl)) errors.Add("ApiBaseUrl é obrigatório.");
        if (options.Sources.Count == 0) errors.Add("É preciso configurar pelo menos uma origem em Sources.");

        foreach (var s in options.Sources)
        {
            var n = string.IsNullOrWhiteSpace(s.Name) ? "(sem nome)" : s.Name;
            if (string.IsNullOrWhiteSpace(s.Name)) errors.Add("Há uma origem sem Name.");
            if (s.Entity is not ("CONTA" or "CONTACTO")) errors.Add($"Origem {n}: Entity tem de ser CONTA ou CONTACTO.");
            if (s.AccountType is not ("CLI" or "FOR" or "COL")) errors.Add($"Origem {n}: AccountType tem de ser CLI, FOR ou COL.");
            if (s.Origins.Count == 0) errors.Add($"Origem {n}: falta a lista Origins.");
            if (string.IsNullOrWhiteSpace(s.View)) errors.Add($"Origem {n}: falta a View.");
            if (string.IsNullOrWhiteSpace(s.Endpoint)) errors.Add($"Origem {n}: falta o Endpoint.");
            if (string.IsNullOrWhiteSpace(s.RequestListProperty)) errors.Add($"Origem {n}: falta RequestListProperty.");
            if (string.IsNullOrWhiteSpace(s.ResponseListProperty)) errors.Add($"Origem {n}: falta ResponseListProperty.");
        }

        var duplicated = options.Sources
            .GroupBy(s => (s.Entity, s.AccountType))
            .Where(g => g.Count() > 1)
            .Select(g => $"{g.Key.Entity}/{g.Key.AccountType}");
        foreach (var d in duplicated) errors.Add($"Há mais do que uma origem para {d}.");

        return errors;
    }
}
