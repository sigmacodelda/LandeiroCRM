# servico

Solução .NET 8 `SigmaCode.Landeiro.CrmSync.sln`. Dependências só num sentido: **Worker → Infrastructure → Core**.

| Projeto | Responsabilidade |
|---|---|
| `src/…Core` | Domínio: estados da fila, truncagem, JSON, interpretação de 200/206/422, ordem conta → contacto, ciclo (`SyncCycleRunner`). **Sem** SQL, HTTP nem PHC. |
| `src/…Infrastructure` | Fila e views (SQL Server), cliente HTTP da API, log diário em ficheiro (+ retenção), applock (instância única), DPAPI. |
| `src/…Worker` | Host do Windows Service: `Program.cs`, `Worker`, `appsettings.json` (SEM segredos) e `appsettings.Example.json`. |
| `tests/…Core.Tests` | Testes unitários (67). |
| `tests/…Infrastructure.Tests` | Integração: API simulada, SQL real (LAND2_DEMO), logs, DPAPI, script de deploy (61). |
| `tests/ferramentas/` | `api_simulada.py`: API Somnia simulada para testes ponta a ponta. |

Nada específico de uma tabela do PHC está no código: vive nas views e na configuração (`CrmSync:Sources`).

```powershell
dotnet build
dotnet test            # os testes de base de dados precisam de CRMSYNC_TEST_CONNECTION (e recusam outra base que não a LAND2_DEMO)
```

Correr o serviço em modo consola (para testes), com credenciais por variáveis de ambiente:

```powershell
$env:CRMSYNC_DB_CONNECTION = '<connection string>'; $env:CRMSYNC_API_TOKEN = '<token>'
dotnet run --project src/SigmaCode.Landeiro.CrmSync.Worker
```

Pacotes NuGet (justificados em [../docs/arquitetura.md](../docs/arquitetura.md), secção 7): `Microsoft.Data.SqlClient`,
`System.Security.Cryptography.ProtectedData`, `Microsoft.Extensions.Hosting.WindowsServices`.
