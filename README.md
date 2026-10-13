# Integração PHC → Somnia CRM (Carnes Landeiro)

Envia clientes (e os seus contactos) do PHC CS para o Somnia CRM, via API. Desenvolvido pela SigmaCode.

```
PHC (grava a ficha) → trigger tr_crm_* → u_crmfila (fila) → serviço (de 5 em 5 min) → view → JSON → API Somnia → fila + log
```

- Uma **fila** (`u_crmfila`) regista cada criação, alteração ou eliminação; **triggers** escrevem nela.
- Um **serviço Windows** (.NET 8) lê a fila, envia em lotes e atualiza o estado de cada registo (`ENVIADO` / `ERRO` / `SEM_ENVIO`).
- O circuito é **genérico**: acrescentar fornecedores ou colaboradores é uma view, um trigger e uma entrada de configuração (sem alterar o serviço).

> **Estado (2026-10-13):** implementado e testado na `LAND2_DEMO` (92 testes SQL + 128 .NET + ponta a ponta com API
> simulada). **Ainda não validado com o CRM real**: o endpoint responde `301` → login (ver [docs/pendencias.md](docs/pendencias.md), P1).
> Nada foi instalado na `LAND2` (base real) nem no servidor do cliente.

## Mapa das pastas

| Pasta | Conteúdo |
|---|---|
| [`base-dados/`](base-dados/README.md) | Tudo o que é SQL: tabela de fila, views, procedimentos, triggers, permissões, testes, rollback e `instalar.sql`. |
| [`servico/`](servico/README.md) | Solução .NET 8: `Core` (regras), `Infrastructure` (SQL, HTTP, logs, DPAPI), `Worker` (Windows Service) e testes. |
| [`deploy/`](deploy/README.md) | PowerShell: publicar, guardar credenciais (DPAPI), instalar, desinstalar e reiniciar o serviço. |
| [`docs/`](docs/README.md) | Arquitetura, dicionário de dados, mapeamento, manuais, plano de testes, pendências, email para a Orcinus. |
| `anexos/` | A documentação da Orcinus (o PDF da API tem o **token**). **Fora do git.** |

## Pré-requisitos

- Para desenvolver: .NET SDK 8 ou superior (compila `net8.0`), PowerShell 5.1, `sqlcmd`, Python 3 (só para a API simulada dos testes E2E).
- No servidor PHC: runtime **.NET 8** (`Microsoft.NETCore.App` 8.x) ou publicar com `-AutoContido`; acesso ao SQL Server e a `192.168.11.4:80`.

## Compilar e testar

```powershell
cd servico
dotnet build
dotnet test                                   # unitários; os de base de dados ficam "Skipped" sem a variável abaixo
$env:CRMSYNC_TEST_CONNECTION = '<connection string da LAND2_DEMO>'    # nunca em ficheiros
dotnet test                                   # + integração na LAND2_DEMO (recusa outra base)

.\base-dados\testes\executar_testes.ps1 -Servidor 'tcp:SERVIDOR\INSTANCIA' -Utilizador <utilizador>   # testes SQL
```

Resultados e o que ficou por testar: [docs/plano-de-testes.md](docs/plano-de-testes.md).

## Instalar

[docs/manual-instalacao.md](docs/manual-instalacao.md) (base de dados e Windows Service) e
[docs/manual-operacao.md](docs/manual-operacao.md) (fila, reposição de erros, cargas, logs, eliminações).

## Regras do projeto

- **Nunca escrever na `LAND2` (base real)** sem confirmação escrita. Os testes e os scripts recusam-na.
- **Segredos** (connection string, token, passwords): nunca em código, `appsettings.json`, logs ou git. DPAPI ou variáveis de ambiente.
- Triggers existentes do PHC (`tr_cl_update`, `tr_cl_delete`) **não se tocam**; os novos têm o prefixo `tr_crm_`.
- Código (classes e métodos) em inglês, com comentários em português; pastas, scripts e documentação em português.
