using SigmaCode.Landeiro.CrmSync.Core;
using SigmaCode.Landeiro.CrmSync.Core.Abstractions;
using SigmaCode.Landeiro.CrmSync.Core.Config;
using SigmaCode.Landeiro.CrmSync.Infrastructure.Api;
using SigmaCode.Landeiro.CrmSync.Infrastructure.Logging;
using SigmaCode.Landeiro.CrmSync.Infrastructure.Security;
using SigmaCode.Landeiro.CrmSync.Infrastructure.Sql;
using SigmaCode.Landeiro.CrmSync.Worker;

var builder = Host.CreateApplicationBuilder(args);

// Ficheiro local opcional, fora do git (appsettings.*.json está no .gitignore)
builder.Configuration.AddJsonFile("appsettings.Local.json", optional: true, reloadOnChange: false);

// Corre como Windows Service (e também na consola, para testes)
builder.Services.AddWindowsService(o => o.ServiceName = "SigmaCode.Landeiro.CrmSync");

// Configuração (sem segredos) e validação: falha logo no arranque, com mensagem clara
var options = builder.Configuration.GetSection("CrmSync").Get<SyncOptions>() ?? new SyncOptions();
var configErrors = SyncOptionsValidator.Validate(options);
if (configErrors.Count > 0)
    throw new InvalidOperationException("Configuração inválida: " + string.Join(" ", configErrors));

// Pastas e ficheiros relativos ficam junto da aplicação (um serviço Windows não arranca na pasta do exe)
string Resolve(string path) => Path.IsPathRooted(path) ? path : Path.Combine(AppContext.BaseDirectory, path);
var logDirectory = Resolve(options.LogDirectory);

// Credenciais: variáveis de ambiente ou DPAPI. Em testes locais, a connection string pode vir de
// appsettings.Local.json (ignorado pelo git; nunca no appsettings.json versionado). O token segue a mesma regra (Secrets:ApiToken).
var credentials = CredentialProvider.Load(
    string.IsNullOrWhiteSpace(options.CredentialsFile) ? null : Resolve(options.CredentialsFile),
    builder.Configuration["ConnectionStrings:Crm"],
    builder.Configuration["Secrets:ApiToken"]);

builder.Services.AddSingleton(options);
builder.Services.AddSingleton<IAuditLog>(_ => new DailyFileAuditLog(logDirectory));
builder.Services.AddSingleton<IQueueStore>(_ => new SqlQueueStore(credentials.DbConnectionString));
builder.Services.AddSingleton<ISourceReader>(_ => new SqlSourceReader(credentials.DbConnectionString));
builder.Services.AddSingleton<IInstanceLock>(_ => new SqlInstanceLock(credentials.DbConnectionString, options.InstanceLockName));
builder.Services.AddSingleton<ICrmApiClient>(_ => new SomniaApiClient(
    new HttpClient(new SocketsHttpHandler()) { Timeout = Timeout.InfiniteTimeSpan },   // o tempo limite é gerido pelo SomniaApiClient
    options.ApiBaseUrl, credentials.ApiToken, options.AuthorizationPrefix, TimeSpan.FromSeconds(options.ApiTimeoutSeconds)));
builder.Services.AddSingleton<SyncCycleRunner>();
builder.Services.AddHostedService(sp => new Worker(
    sp.GetRequiredService<SyncCycleRunner>(), sp.GetRequiredService<IInstanceLock>(), sp.GetRequiredService<IAuditLog>(),
    options, logDirectory, sp.GetRequiredService<ILogger<Worker>>()));

await builder.Build().RunAsync();
