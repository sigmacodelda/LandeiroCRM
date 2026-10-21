# Convenções de código — SigmaCode

Versão 2.0 · 13/10/2026 · Substitui a v1.
Estado: reconstruído a partir da conversa de 13/10/2026, sem o texto original da v1. `[CONFIRMAR]` quer dizer que não tenho certeza e deves validar contra a tua v1. `[NOVO]` quer dizer que foi acrescentado na v2 e deves aceitar ou apagar. Sem marca: regra que já existia.

## 1. Princípios

1. Correto primeiro, simples depois. Entre duas soluções corretas, a mais simples de desenvolver e de manter. Sem camadas, genéricos nem configuração para requisitos que não existem.
2. Seguir os padrões que já existem no repositório. Se o padrão existente e estas convenções divergirem, o Claude Code assinala e pergunta; não refatora por iniciativa própria.
3. Sem dependências novas sem justificação e aprovação.
4. Segurança em todas as alterações (secção 10).
5. Código legível para outros programadores. Todo o código novo vem comentado, com uma explicação simples do que faz: cada classe, cada método, cada bloco não óbvio e cada objeto SQL. Comentários em português.

## 2. API (.NET 8)

- Estrutura por módulo. Cada módulo tem Controllers finos (recebem o pedido, chamam o Service e devolvem a resposta), Services com interface (a lógica), Mappers (conversão entre modelos e DTOs) e DTOs.
- Controllers sem lógica de negócio e sem acesso a dados.
- Services registados por injeção de dependências em `Program.cs`, sempre contra a interface.
- Acesso a dados com Dapper, através de SPs (secção 8). `[CONFIRMAR]` se algum módulo usa outro padrão.
- Validação dos DTOs de entrada no limite da API, antes de chegar ao Service. `[NOVO]`
- Os endpoints existentes mantêm o contrato JSON (nomes, tipos, códigos HTTP), salvo decisão registada em `<decisions>`. `[NOVO]`

## 3. sServices e sUtils (.NET Framework 4.8)

- C# 7.3. Evitar o que só existe a partir do C# 8: declarações `using` sem chaves, switch expressions, `??=`, intervalos e índices (`[..]`, `^1`) e anotações de nulos; e `records` (C# 9). `[NOVO]`
- O .NET Framework 4.8 não tem host nem injeção de dependências por defeito. O Claude Code lê primeiro o código existente e segue o padrão que lá estiver (container ou composição manual, e o logging atual). Não introduz Microsoft.Extensions.DependencyInjection nem `ILogger<T>` sem aprovação. `[CONFIRMAR]` qual é o padrão atual de cada projeto.
- Antes de alterar qualquer pacote NuGet, faz-se um build de teste (conflitos de assemblies e binding redirects) e só depois se segue. `[NOVO]`

## 4. Biblioteca partilhada (`sigma-phc-dossiers`)

- Alvo netstandard2.0. Dapper e Microsoft.Data.SqlClient 5.x. Usa Options e Logging.Abstractions, não implementações concretas.
- A API referencia a biblioteca por ProjectReference. Por isso, uma alteração que toque na biblioteca e na API faz-se com o mesmo nome de branch nos dois repositórios (secção 11).
- Alterar a API pública da biblioteca (assinaturas, DTOs partilhados) tem impacto nos consumidores: o prompt lista quem a consome e os testes cobrem esses consumidores. `[NOVO]`

## 5. DTOs, Services e Mappers

- DTOs em todas as trocas entre camadas. Nunca expor modelos de dados (as classes que espelham tabelas do PHC).
- Mappers dedicados e simples (métodos de conversão), sem lógica de negócio.
- Nomes: `<Entidade>Dto`, `<Entidade>Service` com `I<Entidade>Service`, `<Entidade>Mapper`. `[CONFIRMAR]` nomes em uso.

## 6. Erros e logs

- try/catch com log nos pontos críticos (fronteiras: controller, acesso a dados, chamadas externas). Nunca apanhar uma exceção para a ignorar: ou se trata, ou se regista e se propaga.
- API (.NET 8) e biblioteca: `ILogger<T>`. .NET Framework 4.8: o logging que já existe no projeto (`[CONFIRMAR]` qual). Não introduzir outro sem aprovação.
- Os logs não levam passwords, tokens, connection strings nem dados pessoais desnecessários. `[NOVO]`
- Mensagens de erro para quem chama a API sem detalhes internos (sem stack trace, sem nomes de tabelas). `[NOVO]`
- Níveis: Information para o fluxo normal, Warning para o que é recuperável, Error para falhas. `[NOVO]`

## 7. Configuração

- API (.NET 8) e biblioteca: `appsettings.json` com Options pattern (classe tipada, validada no arranque). Nada fixo no código: URLs, timeouts, limites, nomes de bases.
- .NET Framework 4.8: `[CONFIRMAR]` ficheiro de configuração usado hoje (por exemplo `App.config` ou `Web.config`). Segue o que existe.
- Segredos fora do repositório: variável de ambiente, DPAPI ou o mecanismo já existente. Ficheiros com valores reais (`appsettings.*.json`) no `.gitignore`; no repositório só um `appsettings.Example.json` sem segredos. `[NOVO]`

## 8. Base de dados

### 8.1 Objetos e nomes

A regra de permissões está nas instruções do projeto (fonte única): o Claude Code cria SPs, views e triggers novos e nunca cria tabelas nem campos. Os nomes estão em `contexto-stack.md`, secção 6.

### 8.2 Stored Procedures

- Nome `sc_<Entidade><Acao>`, nunca `sp_`. Esquema `dbo`.
- Cabeçalho com comentário: o que faz, parâmetros e o que devolve.
- `SET NOCOUNT ON`.
- Listas como parâmetro em XML (`nodes()` e `value()`), sem TVP.
- Parâmetros com o mesmo tipo e tamanho das colunas, para evitar conversões implícitas que inutilizam índices. `[NOVO]`
- Sem SQL dinâmico. Se for mesmo inevitável, só com `sp_executesql` e parâmetros, justificado no prompt. `[NOVO]`
- Devolver só as colunas que o DTO usa; nada de `SELECT *`. `[NOVO]`
- Erros com `RAISERROR` até a função `THROW` estar confirmada no nível 100 (`contexto-stack.md`, secção 5).
- Reinstalável: o script pode correr duas vezes sem erro (`CREATE OR ALTER`; se falhar na base de testes, `IF OBJECT_ID(...)` + `DROP` + `CREATE`).

### 8.3 Views

- Só leitura. Nome conforme `contexto-stack.md`, secção 6.
- Colunas explícitas, com os tipos finais. Números concatenados com texto levam CAST explícito.
- Sem `ORDER BY` dentro da view.
- Evitar views que dependem de outras views: são mais difíceis de manter e de otimizar. `[NOVO]`

### 8.4 Triggers

Só se criam triggers novos. Nunca se alteram, desativam, apagam nem reordenam triggers existentes (incluindo encriptados) e nunca se usa `sp_settriggerorder`.

- Leves: no trigger só o mínimo, tipicamente um INSERT em lote. A lógica pesada fica numa SP ou no serviço.
- Seguros para várias linhas: trabalham sobre `inserted` e `deleted` como conjuntos e nunca assumem uma só linha.
- Comparam `inserted` com `deleted` para saber o que mudou, em vez de `UPDATE(coluna)`, que só diz que a coluna entrou no SET.
- Nunca bloqueiam a gravação no PHC. Num trigger, um erro não tratado desfaz a gravação do PHC e, mesmo apanhado por TRY/CATCH, pode deixar a transação inutilizável (`XACT_STATE() = -1`). Por isso o trigger faz só operações que não costumam falhar (um INSERT simples numa tabela sem restrições que possam falhar) e o TRY/CATCH é só uma segunda linha de defesa. `[CONFIRMAR]` como se regista uma falha do trigger sem bloquear (definir em cada prompt).
- `SET NOCOUNT ON`.
- Cada trigger novo tem um script de remoção (rollback) e um script de verificação de que está ativo.
- Antes de criar, ler os triggers existentes da tabela (`contexto-stack.md`, secção 4, consulta 2) para não duplicar comportamento.

### 8.5 Tabelas e campos: especificação para criar no PHC

O Claude Code nunca cria tabelas nem campos. Quando são precisos, o prompt traz a especificação em `<phc_tables>` (formato em `modelo-prompt.md`) e o Flávio cria-os no PHC.

- Primeiro verifica-se se é mesmo preciso: uma view, uma SP ou estado guardado fora do PHC resolvem? Só se justifica uma tabela nova quando as alternativas mais simples não chegam.
- Antes de especificar, confirma-se se a edição e a versão do PHC deste cliente permitem criar tabelas de utilizador (no Advanced, por indicação do Flávio, não permitem). Se não permitem, o prompt traz uma alternativa sem tabela (estado guardado no serviço, marca de água pelos campos de auditoria do PHC, ou reutilização de uma tabela de utilizador existente), com prós e contras.
- Por tabela: nome (`u_<nome>`), finalidade, quem cria e onde. Por campo: nome, tipo, tamanho ou precisão, nulo, valor por defeito e regra ou domínio. Ainda: chave e relações, e índices propostos (a aprovar).
- O PHC traz os campos standard (stamp, auditoria, marcada). A especificação lista só os campos próprios; a estrutura final confirma-se com o script de verificação.
- O script de verificação (`01_verificar_<tabela>.sql`) só lê (`INFORMATION_SCHEMA` e `sys.*`) e falha com `RAISERROR` (severidade 16) e uma mensagem clara se faltar a tabela, um campo, um tipo ou um tamanho. Se falhar, o Claude Code pára a parte que depende da tabela, escreve "BLOQUEIO:" com a lista do que falta e continua o resto.

### 8.6 Compatibilidade SQL

SQL compatível com o nível de compatibilidade da base do cliente (por defeito 100). O estado de cada função e sintaxe está em `contexto-stack.md`, secção 5. Um teste que passa numa base de nível superior (por exemplo `LAND2_DEMO`, em 150) não prova compatibilidade com o nível 100.

### 8.7 Verificação antes de instalar

Antes de pedir confirmação para instalar um lote de scripts, o Claude Code faz estas verificações. O pedido de confirmação é um por lote ou por módulo, com a lista de scripts e a base de destino; se o Flávio pedir confirmação por script, segue isso.

1. Pesquisa de texto em todos os scripts (por exemplo com `grep` ou `Select-String`). Não pode existir:
   - `CREATE TABLE`, exceto de tabelas temporárias (`#nome`);
   - `ALTER TABLE` (inclui `ENABLE TRIGGER` e `DISABLE TRIGGER`);
   - `DROP TABLE` e `TRUNCATE TABLE`;
   - `SELECT … INTO` que não seja para uma tabela temporária (`#nome`);
   - `sp_rename` sobre tabelas ou colunas, e `sp_settriggerorder`;
   - `DROP TRIGGER`, `ALTER TRIGGER` ou `CREATE OR ALTER TRIGGER` sobre triggers que não sejam novos e nossos;
   - `CREATE INDEX`, `CREATE FUNCTION`, `CREATE TYPE`, `CREATE SEQUENCE`, `CREATE ROLE` e `CREATE LOGIN`, salvo autorização explícita registada em `<decisions>`.
2. Cada script de instalação começa com uma guarda de base de dados, que impede a execução fora das bases de teste autorizadas `[NOVO]`:

```sql
-- Guarda: só deixa correr nas bases de teste autorizadas.
DECLARE @bd sysname = DB_NAME();
IF @bd NOT IN (N'DemoSigmaCode')   -- acrescentar aqui só bases de TESTE
BEGIN
    RAISERROR(N'Base de dados nao autorizada: %s', 16, 1, @bd);
    SET NOEXEC ON;   -- o resto do script nao executa
END
GO
-- ... objetos do script ...
SET NOEXEC OFF;   -- no fim, repoe a execucao normal
GO
```

3. Cada objeto novo tem script de remoção (rollback) que só apaga objetos nossos.
4. Os scripts são reinstaláveis (podem correr duas vezes sem erro).
5. Nenhum script contém passwords, tokens nem connection strings.

## 9. Testes

- Cada alteração leva testes apropriados, com os cenários listados no prompt. Se a lista faltar, o Claude Code propõe-na no PLANO antes de implementar.
- .NET: o framework de testes que o repositório já usa. `[CONFIRMAR]` qual (xUnit, NUnit ou MSTest). Se não houver testes, propõe e pede aprovação, porque é uma dependência nova.
- SQL: scripts de teste com verificações (asserts) que falham com mensagem clara, corridos só na base de testes.
- Triggers: testar uma linha, várias linhas, uma alteração que não muda nada (não deve gerar registo) e que a gravação no PHC não falha. `[NOVO]`
- Os testes não usam dados reais de clientes nem credenciais reais; usam dados fictícios.
- Medição de performance: método em `exemplo-otimizacao-acesso-dados.md`, tag `<tests>`.
- O plano de testes, as evidências e a documentação mínima (dicionário de dados, manuais de instalação e de operação) estão definidos na task `testes-documentacao`, em `catalogo-tasks.md`. `[NOVO]`
- Quando um teste não pode ser corrido (sem base de testes, sem rede), o Claude Code diz-o em TESTES e explica o que ficou por validar. Não declara como testado o que não correu. `[NOVO]`

## 10. Segurança

- Nunca incluir passwords, tokens ou connection strings em prompts, código, logs, testes ou documentação. Referenciar pela configuração (appsettings, DPAPI ou variável de ambiente).
- Credencial partilhada no chat: assinalar que deve ser trocada.
- Consultas parametrizadas. Nunca construir SQL por concatenação de texto que venha de fora.
- Utilizadores SQL e contas de serviço com o mínimo de permissões necessárias. `[NOVO]`
- Validar entradas externas (DTOs, ficheiros, respostas de APIs de terceiros). `[NOVO]`
- Nunca executar scripts contra bases de clientes ou de produção. Em bases de teste, só com confirmação e depois de confirmar o nome da base com `SELECT DB_NAME()`.
- Integração com APIs de terceiros: HTTPS sempre que possível; se só houver HTTP, registar o risco em RISCOS. `[NOVO]`

## 11. Git e branches

- Sempre num branch próprio. Sem commit nem push sem confirmação do Flávio.
- O mesmo nome de branch em todos os repositórios alterados na mesma tarefa (por exemplo `feature/logistica-transferencias`), porque a API referencia a biblioteca por ProjectReference.
- Mudanças estruturais (reorganizar, mover, renomear) e mudanças de comportamento em commits separados, de preferência em branches separados. `[NOVO]`
- Nunca fazer commit de credenciais, de ficheiros de configuração com valores reais, de `bin/` e `obj/`, de logs, nem da pasta `Claude outputs/`. O `.gitignore` cobre-os antes do primeiro commit. `[NOVO]`
- Antes de qualquer push, ver os ficheiros que vão (`git status` e `git diff`) e confirmar que o repositório de destino é privado. `[NOVO]`
- A pasta `docs/tasks/` (prompts das tasks e `00-global.md`) é versionada com o código: é o histórico do trabalho. `[NOVO]`

## 12. Revisão crítica antes de entregar

O Claude Code relê a própria implementação e responde, em REVISÃO:

1. Cumpre o que o prompt pede e nada mais (âmbito e "Fora de âmbito")?
2. É a solução mais simples que é correta? O que se podia apagar?
3. Segue os padrões que já existem?
4. Há credenciais, caminhos ou nomes de clientes no código ou nos logs?
5. O que acontece com entrada vazia, nula, muito grande ou repetida? E com falha de rede ou da base?
6. Os testes cobrem os cenários listados? Algum falharia se o código estivesse errado?
7. Riscos e impactos para RISCOS: o que pode correr mal, em que ambiente e como se desfaz.

## 13. Pontos a confirmar nesta v2

1. Padrão de injeção de dependências ou composição manual, e de logging, em sServices e sUtils.
2. Ficheiro de configuração usado no .NET Framework 4.8.
3. Framework de testes (xUnit, NUnit ou MSTest).
4. Nomes de DTOs, Services e Mappers em uso.
5. Se algum módulo da API não acede a dados por SPs.
