# Manual de instalação

Dois passos independentes: **A) base de dados** e **B) serviço Windows**. Não instalar em produção sem os testes
dos passos 3 a 6 do plano confirmados ([plano-de-testes.md](plano-de-testes.md)).

## Pré-requisitos

| Onde | O quê |
|---|---|
| Base de dados | SQL Server 2019 (testado), `sqlcmd` e um login com direitos para criar tabelas, views, procedimentos e triggers. |
| Servidor PHC | Windows com **runtime .NET 8** (`Microsoft.NETCore.App` 8.x) ou publicar com `-AutoContido`. PowerShell 5.1 e consola de Administrador. |
| Rede | O servidor PHC tem de chegar ao SQL Server e a `192.168.11.4` (porta 80, rede do cliente ou VPN). |
| Credenciais | Connection string da base de dados e token da API (nunca em ficheiros de texto). |

## A) Base de dados

1. **Faz backup** da base de dados (os triggers ficam em tabelas do PHC).
2. A partir da pasta `base-dados/`, em modo SQLCMD, **na base de testes primeiro**:

```bash
sqlcmd -S "tcp:SERVIDOR\INSTANCIA" -d LAND2_DEMO -U <utilizador> -f 65001 -b -i instalar.sql -v BaseDados=LAND2_DEMO PermitirProducao=NAO
```

   - `BaseDados` tem de coincidir com a base ligada, senão para.
   - A `LAND2` (real) só aceita com `PermitirProducao=SIM`, depois de confirmação escrita do responsável.
   - Os scripts são idempotentes: repetir não estraga nada.
   - Usar `tcp:` no nome do servidor (com named pipes a ligação por IP falha).
3. Só na **DEMO**: `testes/00_preparar_demo_u_clcontact.sql` (acrescenta `obs` e `departamento` à `u_clcontact`, que
   a LAND2 já tem). Nunca correr na LAND2.
4. Correr os testes SQL: `testes/executar_testes.ps1` (ver [plano-de-testes.md](plano-de-testes.md)).
5. **Rollback** (se for preciso desfazer): `99_rollback/rollback_tudo.sql`. Remove os triggers `tr_crm_*`, o papel, os
   procedimentos, as views, a sequência e o tipo. A tabela `u_crmfila` é do PHC e **não é apagada** (apaga-se no PHC, se for preciso). Os triggers do PHC
   (`tr_cl_update`, `tr_cl_delete`) nunca são tocados.

### Permissões SQL do serviço (mínimas)

O script `05_permissoes/01_role_servico.sql` cria o papel `crmsync_servico` (leitura das views, leitura e atualização
da fila, execução das consultas; sem acesso às tabelas do PHC). Para criar o login do serviço, **fora de ficheiros**
(a password não fica em nenhum script):

```sql
CREATE LOGIN crmsync_svc WITH PASSWORD = '<definir na consola>', CHECK_POLICY = ON;
USE <base>; CREATE USER crmsync_svc FOR LOGIN crmsync_svc;
ALTER ROLE crmsync_servico ADD MEMBER crmsync_svc;
```

> **Estado atual (decisão do responsável):** por agora o serviço usa o utilizador `sa`. **Tem de ser trocado pelo
> `crmsync_svc` e a password do `sa` mudada antes de produção** (pendência S1 em [pendencias.md](pendencias.md)).

Os utilizadores do PHC **não precisam** de direitos na fila: os triggers escrevem nela por cadeia de propriedade
(testado com um utilizador sem direitos em `u_crmfila`).

## B) Serviço Windows

### 1. Publicar (na máquina de desenvolvimento)

```powershell
.\deploy\publicar.ps1                 # corre os testes unitários e publica em deploy\publish
.\deploy\publicar.ps1 -AutoContido    # leva o runtime .NET junto
```

### 2. Copiar para o servidor e guardar as credenciais (consola de Administrador)

```powershell
.\deploy\guardar-credenciais.ps1                         # pede a connection string e o token sem os mostrar
.\deploy\guardar-credenciais.ps1 -ContaServico 'DOMINIO\svc_crmsync'   # se o serviço correr com outra conta
```

O ficheiro (`C:\ProgramData\SigmaCode\CrmSync\credenciais.dpapi`) é protegido por **DPAPI** (âmbito da máquina):
só abre neste servidor. As permissões ficam restritas a SYSTEM, Administradores e ao utilizador que correu o script.
Alternativa para testes: variáveis de ambiente `CRMSYNC_DB_CONNECTION` e `CRMSYNC_API_TOKEN`.

Exemplo de connection string (os valores reais nunca se escrevem em ficheiros do projeto):
`Server=tcp:SERVIDOR\INSTANCIA;Database=<BASE>;User Id=<utilizador>;Password=<...>;TrustServerCertificate=True;`

### 3. Configurar

Editar `appsettings.json` na pasta de instalação (não contém segredos). Os valores por defeito servem:

| Chave (`CrmSync:`) | Defeito | Para quê |
|---|---|---|
| `IntervalMinutes` | 5 | Intervalo entre ciclos. |
| `BatchSize` | 100 | Registos por pedido (1 a 1000). |
| `LogRetentionDays` | 7 | Logs com mais de N dias são apagados. |
| `LogDirectory` | `logs` | Relativa à pasta do serviço. |
| `ApiTimeoutSeconds` | 60 | Tempo limite por pedido. |
| `ApiBaseUrl` | `http://192.168.11.4/carneslandeiro/index.php` | |
| `AuthorizationPrefix` | `Bearer` | Trocar para `Bearer:` só se o servidor rejeitar a forma standard. |
| `FieldLimits` | todos vazios | Limites de tamanho por campo (ver [mapeamento-phc-api.md](mapeamento-phc-api.md)). |
| `Sources` | CL-CONTA, CL-CONTACTO | Origens (ver [como-adicionar-nova-origem.md](como-adicionar-nova-origem.md)). |

Qualquer chave pode ser substituída por variável de ambiente (`CrmSync__IntervalMinutes=1`).

### 4. Instalar e arrancar

```powershell
.\deploy\instalar-servico.ps1 -Origem .\publish -Destino C:\SigmaCode\CrmSync     # instala (parado)
Start-Service SigmaCode.Landeiro.CrmSync
```

O script confirma o runtime .NET 8, copia os ficheiros, cria o serviço (arranque automático; reinicia sozinho se
falhar, 3 vezes com 1 minuto de intervalo). Para atualizar uma versão: `desinstalar-servico.ps1`, copiar os ficheiros
novos, `instalar-servico.ps1`. A fila, as credenciais e os logs mantêm-se.

Reiniciar: `deploy\reiniciar-servico.ps1`. Desinstalar: `deploy\desinstalar-servico.ps1`.

### 5. Verificar

1. `Get-Service SigmaCode.Landeiro.CrmSync` está `Running`.
2. O ficheiro `logs\crmsync-AAAAMMDD.log` tem a linha `ARRANQUE`.
3. Linha `SEM_BLOQUEIO` repetida = há outra instância a correr (ou a base está indisponível).
4. Carga de teste do cliente 13444 e confirmação no CRM (ver [manual-operacao.md](manual-operacao.md)).

## Conectividade

A partir do **servidor PHC** (não da máquina do programador):

```powershell
Test-NetConnection 192.168.11.4 -Port 80      # TcpTestSucceeded : True
```

Resultado do teste feito a partir da máquina de desenvolvimento: ligação TCP à porta 80 **OK**, mas o endpoint devolve
`301` para a página de login (ver [pendencias.md](pendencias.md), P1). O HTTPS (porta 443) não responde.

## Segurança

- Nada de segredos em código, `appsettings.json`, logs ou repositório. `appsettings.Example.json` é o único modelo no git.
- A pasta `anexos/` (o PDF da API tem o token) está fora do git.
- Antes de produção: trocar a password do `sa` e o token da API (partilhado em documento).
