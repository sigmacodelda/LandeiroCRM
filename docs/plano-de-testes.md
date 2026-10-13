# Plano de testes e resultados

Execução de 2026-10-13, na **LAND2_DEMO** (SQL Server 2019, `192.168.10.79\ENT`), .NET SDK 10.0.103 com
`net8.0`/runtime 8.0.31. Nada foi executado na LAND2 (base real) nem no CRM real.

## Como correr

```powershell
# 1) Testes SQL (92 asserts, cada ficheiro faz ROLLBACK; recusam outra base que não a LAND2_DEMO)
$env:CRMSYNC_SQL_PASSWORD = '<password>'     # nunca em ficheiros
.\base-dados\testes\executar_testes.ps1 -Servidor 'tcp:192.168.10.79\ENT' -Utilizador sa

# 2) Testes .NET (unitários + integração; os de base de dados precisam desta variável e recusam outra base)
$env:CRMSYNC_TEST_CONNECTION = 'Server=tcp:192.168.10.79\ENT;Database=LAND2_DEMO;User Id=sa;Password=<...>;TrustServerCertificate=True;'
dotnet test .\servico\SigmaCode.Landeiro.CrmSync.sln
```

Sem `CRMSYNC_TEST_CONNECTION` os testes de base de dados ficam *ignorados* (aparecem como `Skipped`), e os unitários correm.
Os testes de integração por base de dados recusam correr se a fila tiver registos por enviar que não sejam de teste.

## Resumo dos resultados

| Camada | Ficheiro / projeto | Testes | Resultado |
|---|---|---|---|
| SQL | `01_teste_triggers_cl.sql` | 20 | 20 OK |
| SQL | `02_teste_triggers_cl2_contactos.sql` | 19 | 19 OK |
| SQL | `03_teste_views.sql` | 16 | 16 OK |
| SQL | `04_teste_carga_reposicao.sql` | 21 | 21 OK |
| SQL | `05_teste_permissoes_robustez.sql` | 16 | 16 OK |
| .NET | `Core.Tests` (unitários) | 67 | 67 OK |
| .NET | `Infrastructure.Tests` (API simulada, SQL, applock, logs, DPAPI, script de deploy) | 61 | 61 OK |
| Ponta a ponta | serviço real + LAND2_DEMO + API simulada (secção 5) | 13 cenários | OK |
| Scripts | rollback, guardas da instalação, `publicar.ps1`, `guardar-credenciais.ps1` | ver secção 4 | OK |

Total automatizado: **92 SQL + 128 .NET**.

## 1. Testes SQL (o que cada ficheiro prova)

| Ficheiro | Cobre |
|---|---|
| 01 CL | insert gera 1 conta PENDENTE (`99999991-0`, origem `CL`); stamp da fila no formato PHC; update de campo integrado gera fila; update de todas as colunas sem mudança **não** gera; campos não integrados (`contacto`, `obs`, `tipo`) **não** geram; alteração de **saldo** não gera; espaços no fim não geram; só maiúsculas gera; deduplicação (3 alterações = 1 PENDENTE); várias linhas de uma vez (insert, update 2 de 3, delete); estabelecimento gera `99999991-1`; delete gera `D` com código; delete substitui o `U` pendente; histórico `ENVIADO` intacto; rollback sem restos. |
| 02 CL2 e contactos | só o país (CL2) gera conta com origem `CL2`; CL2 sem mudança e campo não integrado não geram; CL + CL2 gravadas juntas = 1 PENDENTE; CL2 órfã não gera; contacto: insert, cada campo integrado (`funcao`, `tipo`, `telefone`, `tlmvl`, `email`, `departamento`) gera, `fax`/`contacto`/`estab`/`no` não, update sem mudança não, `obs` gera, mudar de ficha gera, órfão não é enfileirado, várias linhas, delete gera `D`, delete substitui `U`. |
| 03 Views | colunas = nomes da API (+`stamp`, `accountStamp`); campos fora do âmbito não existem; tudo `varchar`; trim; `code` `NO-ESTAB`; país da CL2 (vazio sem CL2); estabelecimento tem a sua conta; contacto liga à ficha do `clstamp` (ignora o `estab` do contacto); `obs` de 9000 caracteres inteira (`varchar(max)`); órfão fora da view; uma linha por ficha (sem duplicados do `LEFT JOIN`). |
| 04 Carga e reposição | carga do 13444 enfileira as suas fichas e contactos, com origem e `NO-ESTAB`; repetir não duplica; origem `FL` dá erro; histórico; **carga total** = todas as fichas e contactos com ficha (14 032 / 11 233) sem duplicar; reposição por código, entidade, stamp de origem, stamp da fila e origem; guarda a mensagem anterior; só o ERRO mais recente; ignora se já há PENDENTE; nunca toca em `ENVIADO`/`SEM_ENVIO`; consultas. |
| 05 Permissões e robustez | utilizador do PHC **sem direitos na fila** grava e os triggers escrevem na fila (cadeia de propriedade); o papel do serviço lê as views e atualiza a fila, **não** lê `cl`/`u_clcontact`, **não** insere nem apaga na fila, pede o applock e executa as consultas; **com a fila indisponível a gravação do PHC não falha**, a alteração fica gravada e a transação continua utilizável (`XACT_STATE = 1`, com `XACT_ABORT ON`). |

## 2. Testes unitários (.NET, `Core.Tests`)

Truncagem (no limite, acima, sem limite, valor nulo, par de substituição); construção do JSON (formato da API, ordem,
acentos, aspas, sem campos fora do âmbito, truncagem com aviso sem o valor, limite sem distinguir maiúsculas, texto
longo); interpretação das respostas (200, 206 por `row`, ação de falha, código diferente, sem `id`, `row` como texto,
422, 401, 403, rede, 500, estado inesperado, corpo inválido, mensagem limitada e sem eco do corpo); validação da
configuração; **ciclo**: ordem contas → contactos, contacto no mesmo ciclo da conta, lotes do tamanho configurado, 206
registo a registo, 422, falha de rede e de autenticação em destaque no log, **sem reprocessamento automático**, registo
inexistente na view, **`D` → `SEM_ENVIO` sem chamar a API**, contacto à espera de conta em ERRO (e segue depois da
reposição), sem laço infinito com contactos em espera, truncagem, **recuperação de `A_PROCESSAR`**, paragem a meio do
lote, alteração durante o envio (novo PENDENTE, não se perde), exceção inesperada, falha de leitura da view,
**origem nova só com configuração**, origem não configurada ignorada, log sem dados pessoais.

## 3. Testes de integração (.NET, `Infrastructure.Tests`)

| Área | Cobre |
|---|---|
| API simulada (`HttpMessageHandler` falso) | formato do pedido (método, URL com `entryPoint`, `Authorization: Bearer`, `Content-Type: application/json`, corpo UTF-8); variante `Bearer:`; **200, 206, 422, 401, 500**; **timeout** e **falha de rede** devolvem resultado (não exceção); cancelamento propaga-se; erros nunca contêm o token. |
| Base de dados (LAND2_DEMO) | fila: leitura por entidade/tipo/origens e ordem, paginação, reserva só de PENDENTE e contagem de tentativas, reserva dupla (só a primeira ganha), gravação de resultados, mensagem limitada a 500, nunca altera o que não está a processar, mensagem do erro anterior preservada, recuperação, **bloqueio de contas pelo último registo**; leitura das views reais (campos pela ordem da API, contactos com `accountStamp`, mais de 500 stamps em pedaços, nome de view validado contra injeção SQL); **applock de instância única**. |
| Ciclo completo (triggers → fila → serviço → views → API simulada) | contas antes de contactos; estabelecimento como conta própria; campo integrado reenviado e **não integrado não**; só o país; `D` → `SEM_ENVIO`; erro da API → ERRO → reposição → ENVIADO; contacto à espera de conta em ERRO; truncagem com aviso; **paragem a meio e recuperação**; falha de rede. |
| Logs e segurança | linhas de log (formato, uma linha por evento, separador escapado); **retenção** (apaga com mais de N dias, só `crmsync-AAAAMMDD.log`, N configurável); credenciais (variáveis de ambiente, mensagem sem valores, `ToString` mascarado, **DPAPI**: ficheiro sem texto simples, ficheiro corrompido, variável de ambiente vence o ficheiro); **o ficheiro criado por `guardar-credenciais.ps1` é lido pelo serviço**. |

## 4. Scripts

| Teste | Resultado |
|---|---|
| `instalar.sql` repetido (idempotente) | OK |
| Guarda: base ligada ≠ `BaseDados` | para com erro (testado) |
| Guarda: `LAND2` sem `PermitirProducao=SIM` | bloqueia **antes** de criar nada (testado só com as linhas de guarda) |
| `rollback_tudo.sql` (e repetido) | remove triggers, papel, procedimentos, views, sequência e tipo; a tabela `u_crmfila` (do PHC) fica; sobram só `tr_cl_update` e `tr_cl_delete`; repetir não dá erro (testado na LAND2_DEMO com a tabela já no formato PHC; reinstalar depois: OK) |
| `01_verificar_u_crmfila.sql` | na LAND2_DEMO: "estrutura OK"; na LAND2 (só leitura): "estrutura OK" + nota informativa de que não há índices |
| `executar_testes.ps1` | corre os 5 ficheiros e falha com password errada; recusa outra base |
| `publicar.ps1` | publica `Worker.exe`, `appsettings.json` e `appsettings.Example.json`; sem segredos nem `appsettings.Development.json` |
| `guardar-credenciais.ps1` | cria o ficheiro DPAPI que o serviço lê; **bug apanhado e corrigido** (nomes de contas dependem do idioma: passou a SIDs) |
| `instalar-servico.ps1`, `desinstalar-servico.ps1`, `reiniciar-servico.ps1` | sintaxe validada; a guarda de Administrador funciona; **não foram executados** (não se instalou o serviço) |

## 5. Ponta a ponta — LAND2_DEMO, cliente 13444, serviço real, **API simulada**

Serviço `Worker` real (modo consola, ciclo de 3 s) contra a LAND2_DEMO e uma API simulada local
(`servico/tests/ferramentas/api_simulada.py`). Os dados do 13444 foram repostos no fim. Evidências:
[evidencias/e2e-fila.txt](evidencias/e2e-fila.txt) e [evidencias/e2e-log.txt](evidencias/e2e-log.txt).

| # | Cenário | Resultado |
|---|---|---|
| 1 | Carga 1 a 1 do 13444 (`up_crm_carga 'CL', 13444`) | 1 conta `13444-0`, ENVIADO; pedido com exatamente os 12 campos da API, sem campos fora do âmbito. |
| 2 | Alterar campo integrado (`telefone`) | Novo registo, reenviado. |
| 3 | Alterar campo **não** integrado (`cl.obs`, `cl.contacto`) | **Nada** na fila. |
| 4 | Mudar só o país (CL2) | Novo registo com origem `CL2`, reenviado com o país novo. |
| 5 | "Lançar documento" (`esaldo` muda) | **Nada** na fila. *(Simulado por SQL; ver secção 6.)* |
| 6 | Adicionar e alterar contacto | Enviados, `accountCode = 13444-0`. |
| 7 | Valor acima do limite (`CONTACTO.name = 5`) | Campo enviado com 5 caracteres; aviso `TRUNCADO` no log (campo, stamp; **sem o valor**). |
| 8 | Eliminar contacto | `SEM_ENVIO`, **0 pedidos à API**, linha no log. |
| 9 | API simulada devolve **422** | ERRO; 2 ciclos depois continua 1 só pedido (**sem reenvio automático**); `up_crm_repor` → reenviado → ENVIADO. |
| 10 | API devolve **401** | ERRO; `FALHA_AUTENTICACAO` em destaque no log; reposição → ENVIADO. |
| 11 | API parada (rede em baixo) | ERRO; `FALHA_REDE` em destaque. |
| 12 | **Serviço morto a meio de um lote** (pedido lento de 25 s) | Registo fica `A_PROCESSAR`; ao rearrancar, linha `RECUPERADO` e envio concluído. |
| 13 | **Segunda instância** com o mesmo bloqueio | Fica em `SEM_BLOQUEIO`, não processa nada. |
| — | Retenção de logs (7 dias) com o serviço real | Apagou os 2 ficheiros com mais de 7 dias; manteve os de 6 e 7 dias e o ficheiro que não é log. |

Estado final do 13444 na DEMO: igual ao original (telefone, e-mail, observações, saldo, país); 0 contactos; fila sem
nada por enviar.

## 6. O que NÃO foi testado (e porquê)

| Item | Motivo | Quem / como |
|---|---|---|
| **Envio ao CRM real e confirmação no interface do CRM** | O endpoint responde `301` → login a qualquer pedido, com ou sem token, e também para um `entryPoint` inexistente ([pendencias.md](pendencias.md), P1). Nada foi enviado ao CRM. As variantes `Bearer` / `Bearer:` não se puderam distinguir. | Orcinus (email, questão 1). |
| **Gravação de fichas pelo próprio PHC** | Não há cliente PHC nesta máquina; os testes gravam por SQL. Os triggers cifrados do PHC (`tr_cl_update`, `tr_cl_delete`) disparam nos `UPDATE`/`DELETE` dos testes sem erro, mas **falta confirmar pelo ecrã do PHC** (criar, alterar, apagar cliente e contacto; lançar um documento ao cliente e ver o saldo mudar sem criar fila). | Quem tenha acesso ao PHC da LAND2_DEMO. |
| Conectividade **a partir do servidor PHC** | Testado só a partir da máquina de desenvolvimento (porta 80 acessível). | Correr `Test-NetConnection 192.168.11.4 -Port 80` no servidor. |
| Instalação como Windows Service | Não foi pedida nem feita (aguarda confirmação). Scripts validados só por sintaxe. | Responsável. |
| Carga completa | Não feita (aguarda P2 e P1). Só a **fila** foi exercitada: `up_crm_carga` sem número enfileira 14 032 contas e 11 233 contactos (teste 04, com rollback). | — |
| Desempenho com cargas grandes | O tempo não foi medido. A carga total na fila corre dentro do teste 04 (14 032 contas + 11 233 contactos); o envio de ~25 mil registos em lotes de 100 não foi feito contra uma API real. | Na primeira carga completa (com o serviço, a vigiar o log). |
