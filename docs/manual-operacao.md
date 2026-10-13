# Manual de operação

Todas as consultas e procedimentos correm na base de dados onde a integração está instalada.
Trocar `LAND2_DEMO` pela base real **só** depois de confirmação do responsável.

## 1. Ver o estado da fila

```sql
EXEC dbo.up_crm_consulta_totais;                 -- totais por origem, entidade e estado
EXEC dbo.up_crm_consulta_erros @dias = 7;        -- erros dos últimos 7 dias
EXEC dbo.up_crm_consulta_historico @no = 13444;  -- tudo o que aconteceu a um cliente (contas e contactos)
```

| Estado | Significa |
|---|---|
| `PENDENTE` | Por enviar (o serviço trata no próximo ciclo). |
| `A_PROCESSAR` | O serviço reservou-o e está a enviar. Se ficar assim com o serviço parado, é recuperado no arranque. |
| `ENVIADO` | O CRM gravou-o (`idcrm` e `acaocrm` preenchidos). |
| `ERRO` | Falhou; vê `ultimamensagem`. **Não é reenviado sozinho.** |
| `SEM_ENVIO` | Eliminação (`D`): a API não tem endpoint; tratar à mão no CRM. |

Um registo `PENDENTE` de um **contacto** pode estar à espera de a sua conta (também PENDENTE ou em ERRO). Vê a conta.

## 2. Repor erros (reenviar)

Primeiro corrigir a causa (ver `ultimamensagem` e o log). Depois:

```sql
EXEC dbo.up_crm_repor;                           -- todos os ERRO
EXEC dbo.up_crm_repor @origem = 'CL';
EXEC dbo.up_crm_repor @entidade = 'CONTACTO';
EXEC dbo.up_crm_repor @codigo = '13444-0';       -- código da conta ou contactCode
EXEC dbo.up_crm_repor @stamp = '<stamp>';        -- stamp do registo de origem ou da fila
```

Devolve `repostos` e `ignorados_ja_pendentes`. Só repõe o ERRO mais recente de cada registo e nunca mexe em
`ENVIADO` / `SEM_ENVIO`. Ordem importante: repor primeiro as **contas** e só depois os contactos (os contactos esperam
pela conta de qualquer forma).

## 3. Fazer cargas

A carga **só enfileira**; o serviço envia no ciclo seguinte. Não duplica (respeita a deduplicação) e põe as contas
antes dos contactos.

```sql
EXEC dbo.up_crm_carga @origem = 'CL', @no = 13444;  -- um cliente: sede + estabelecimentos + os seus contactos (testes 1 a 1)
EXEC dbo.up_crm_carga @origem = 'CL';               -- TODOS os clientes e contactos (importação completa)
```

> **Importação completa: não fazer** antes de a Orcinus confirmar o formato do "Código PHC" usado na importação
> inicial (P2 em [pendencias.md](pendencias.md)). Se tiver usado só o número (`13444`) e nós enviarmos `13444-0`, o CRM
> cria contas novas e ficam duplicadas. E só depois de validados os testes e o endpoint (P1).

Para ver o que uma carga total vai enviar sem enviar: correr a carga, consultar os totais, e, se for preciso,
parar o serviço antes (`Stop-Service`).

## 4. Ler os logs

Ficheiros `logs\crmsync-AAAAMMDD.log` (junto ao serviço). Uma linha por evento, campos separados por ` | `:

`data/hora | nível | origem | entidade | código | stamp | resultado | detalhe (ação/id) | mensagem`

| Resultado | Nível | Significa |
|---|---|---|
| `ENVIADO` | INFO | Gravado no CRM. Detalhe = `ação/id`. |
| `ERRO` | ERRO | Falhou; a mensagem diz porquê. |
| `FALHA_REDE` | ERRO | O pedido nem chegou (rede, timeout, ligação recusada). Todo o lote em ERRO. **Em destaque.** |
| `FALHA_AUTENTICACAO` | ERRO | 401/403. Todo o lote em ERRO. **Em destaque.** |
| `TRUNCADO` | AVISO | Um campo excedeu o limite do CRM (o detalhe diz qual; nunca o valor). |
| `SEM_ENVIO` | AVISO | Eliminação por tratar à mão no CRM. |
| `AGUARDA_CONTA` | INFO | Contacto à espera da conta. |
| `RECUPERADO` | AVISO | Registos em A_PROCESSAR repostos a PENDENTE depois de uma paragem. |
| `SEM_BLOQUEIO` | AVISO | Outra instância tem o bloqueio (ou a base está indisponível). |
| `CICLO` | INFO | Resumo do ciclo. |
| `CICLO_FALHOU` | ERRO | Um ciclo falhou (ex.: base em baixo); tenta de novo no intervalo seguinte. |
| `LOGS_APAGADOS` | INFO | Logs com mais de N dias apagados. |

Os logs não têm o token, a connection string nem dados pessoais. Só os ficheiros de log são apagados (7 dias por
defeito); a fila nunca.

## 5. Eliminações (`SEM_ENVIO`)

Quando se apaga uma ficha ou um contacto no PHC, a fila regista a operação `D` com o código. O serviço **não chama
a API** (não há endpoint) e marca-o `SEM_ENVIO`, com aviso no log. **Ação manual:** apagar/inativar esse registo no CRM
(Código na coluna `codigo`; ver `up_crm_consulta_historico`). Quando a Orcinus disponibilizar o endpoint (P4), basta
implementar o envio da operação `D` no serviço.

Ver as pendentes de tratamento manual:

```sql
SELECT datacriacao, entidade, codigo, ultimamensagem FROM dbo.u_crmfila WHERE estado = 'SEM_ENVIO' ORDER BY datacriacao DESC;
```

## 6. Verificar os triggers depois de cada atualização do PHC

Uma atualização do PHC pode recriar tabelas e **perder os triggers**. Depois de cada atualização:

```sql
SELECT OBJECT_NAME(parent_id) AS tabela, name, is_disabled
  FROM sys.triggers
 WHERE name IN ('tr_crm_cl', 'tr_crm_cl2', 'tr_crm_u_clcontact');   -- devem existir os 3, is_disabled = 0
```

Se faltar algum: voltar a correr `04_triggers/*.sql` (idempotente). Depois executar `testes/executar_testes.ps1` **na
base de testes** com a nova versão do PHC. Confirmar também que a `u_clcontact` continua a ter `obs` e `departamento`
e que `tr_cl_update` / `tr_cl_delete` continuam presentes. E, **pelo próprio PHC**, gravar uma ficha de teste e confirmar
que aparece na fila.

## 7. Parar e arrancar

```powershell
Stop-Service SigmaCode.Landeiro.CrmSync       # termina o lote em curso; o resto fica PENDENTE
Start-Service SigmaCode.Landeiro.CrmSync      # ao arrancar, repõe a PENDENTE o que estava A_PROCESSAR
```

Se o serviço for morto a meio de um lote, os registos ficam `A_PROCESSAR` até ao próximo arranque (testado).
Para mudar configuração: editar `appsettings.json` e `deploy\reiniciar-servico.ps1`.

## 8. Resolução de problemas

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Muitos `ERRO` com `HTTP 401/403` | Token errado ou expirado, ou cabeçalho em formato errado | Verificar o token; tentar `AuthorizationPrefix = "Bearer:"`; ver P7 e P1. |
| `FALHA_REDE` | Servidor PHC sem acesso a `192.168.11.4` | `Test-NetConnection 192.168.11.4 -Port 80`; VPN/rede. |
| `HTTP 422` | Dados inválidos (campo obrigatório/formato) | Ver o registo; resposta da Orcinus sobre campos obrigatórios (P8). |
| Contactos sempre `PENDENTE` | A conta está em ERRO/PENDENTE | Resolver e repor a conta. |
| Nada é enviado, `SEM_BLOQUEIO` no log | Outra instância a correr, ou base indisponível | Ver `Get-Process`/serviços; não correr duas instâncias. |
| Alteração no PHC não aparece na fila | Trigger em falta/desativado; ou o campo alterado não é integrado | Secção 6. Só os campos integrados geram fila. |
| `A_PROCESSAR` parado há muito | Serviço caiu | Reiniciar o serviço (recupera sozinho). |
