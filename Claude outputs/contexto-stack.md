# Contexto da stack — SigmaCode

Versão 2.0 · 13/10/2026 · Substitui a v1.
Estado: reconstruído a partir da conversa de 13/10/2026, sem o texto original da v1. `[CONFIRMAR]` quer dizer que não tenho certeza e deves validar contra a tua v1. `[NOVO]` quer dizer que foi acrescentado na v2 e deves aceitar ou apagar. Sem marca: informação que já vinha da v1.

## 1. Como usar este ficheiro

- É a stack de referência da SigmaCode. Se o pedido for para outro projeto ou outra API, pergunta primeiro (frameworks, base de dados, nível de compatibilidade, dependências) e não assumas o que está aqui.
- Os factos que mudam de cliente para cliente (edição e versão do PHC, nível de compatibilidade, o que se pode criar na base) não são regra aqui: perguntam-se sempre (secção 4). O que for reutilizável fica num ficheiro por cliente, `cliente-<nome>.md`.
- A regra do que o Claude Code pode criar na base de dados está nas instruções do projeto, que são a fonte única. Aqui ficam só os factos.

## 2. Projetos e tecnologias

| Projeto | Tecnologia | Notas |
|---|---|---|
| APP | .NET MAUI | `[CONFIRMAR]` as convenções da APP não estão cobertas por estes ficheiros. |
| API | ASP.NET Core, .NET 8 | Módulos com Controllers finos, Services com interface, Mappers e DTOs. |
| sServices | .NET Framework 4.8, C# 7.3 | Repositório em `C:\_SigmaRepos\sServices`. |
| sUtils | .NET Framework 4.8, C# 7.3 | `[CONFIRMAR]` caminho, por exemplo `C:\_SigmaRepos\sUtils`. |
| sigma-phc-dossiers | Biblioteca partilhada, netstandard2.0 | Dapper, Microsoft.Data.SqlClient 5.x, Options e Logging.Abstractions. A API referencia-a por ProjectReference. `[CONFIRMAR]` caminho. |
| Base de dados | PHC sobre SQL Server 2019 | Nível de compatibilidade 100 por defeito; confirmar por cliente (secção 4). |
| Base de testes | `DemoSigmaCode` | `[CONFIRMAR]` instância e nível de compatibilidade. |

## 3. Base de dados PHC: factos gerais

- Cada tabela do PHC tem uma chave `<tabela>stamp` do tipo `char(25)`, gerada pela aplicação e não pela base de dados. O formato dos stamps lê-se de dados reais, nunca se assume. Exemplo de leitura: `SELECT TOP 10 clstamp, LEN(clstamp), DATALENGTH(clstamp) FROM CL WHERE clstamp <> ''`.
- As tabelas de utilizador começam por `u_`. No cliente Landeiro, lidas diretamente da base, trazem estes campos standard, todos NOT NULL com valor por defeito: `u_<nome>stamp` (char(25), chave), `ousrinis`, `ousrdata`, `ousrhora`, `usrinis`, `usrdata`, `usrhora` e `marcada`. `[CONFIRMAR]` noutros clientes, edições e versões.
- `CL` (clientes) tem uma extensão 1:1 em `CL2` (`cl2.cl2stamp = cl.clstamp`). `[NOVO]` Exemplo tirado da integração Landeiro.
- O PHC tem triggers próprios, por vezes encriptados (no Landeiro, `tr_cl_update` e `tr_cl_delete` em `CL`). Nunca se alteram, desativam, apagam nem reordenam.
- Campos numéricos concatenados com texto precisam de CAST explícito, por exemplo `CAST(cl.no AS varchar(10)) + '-' + CAST(cl.estab AS varchar(3))`. Sem o CAST, o SQL Server tenta converter o texto "-" para número e falha. `[NOVO]`
- `[CONFIRMAR]` O que acontece aos objetos de terceiros (triggers, views, SPs) quando o PHC do cliente é atualizado. Até haver resposta, cada prompt que instale triggers inclui um script de verificação de que continuam ativos e um script de reinstalação.

## 4. Factos por cliente (perguntar sempre)

Preencher e guardar em `cliente-<nome>.md` quando forem reutilizáveis. Nunca incluir credenciais, IPs nem tokens.

| Facto | Como confirmar |
|---|---|
| Edição do PHC (Advanced, Evolution ou outra) e versão | Perguntar ao Flávio. |
| Alojamento (servidor do cliente ou cloud) e acesso direto à base de dados | Perguntar ao Flávio. |
| Versão e edição do SQL Server | Consulta 1, abaixo. |
| Nível de compatibilidade da base | Consulta 1, abaixo. |
| É possível criar tabelas de utilizador e campos novos no PHC? Quem cria? | Perguntar ao Flávio. No Advanced, por indicação dele, não é possível criar tabelas. |
| Base de testes: nome, instância, é cópia restaurada? | Perguntar ao Flávio. `SELECT DB_NAME()` antes de qualquer escrita. |
| Triggers nas tabelas envolvidas | Consulta 2, abaixo. Definição NULL quer dizer trigger encriptado. |
| As atualizações do PHC mexem em objetos de terceiros? | Perguntar ao Flávio ou à PHC. |

Consulta 1 (só leitura): stack da base.

```sql
SELECT @@VERSION,
       SERVERPROPERTY('ProductVersion'),
       SERVERPROPERTY('Edition'),
       DB_NAME(),
       compatibility_level
FROM sys.databases
WHERE name = DB_NAME();
```

Consulta 2 (só leitura): triggers de uma tabela (exemplo com `CL`).

```sql
SELECT t.name, t.is_disabled, m.definition
FROM sys.triggers AS t
LEFT JOIN sys.sql_modules AS m ON m.object_id = t.object_id
WHERE t.parent_id = OBJECT_ID('dbo.CL');
```

## 5. Compatibilidade SQL (nível 100)

Regra mantida: o SQL dos prompts tem de funcionar com a base em nível de compatibilidade 100, que é o nível das bases PHC dos clientes SigmaCode (`[CONFIRMAR]` por cliente). Antes de escrever SQL, confirma o nível da base do cliente (secção 4, consulta 1).

Atenção: a base `LAND2_DEMO` (testes do Landeiro) está em nível 150. Testes que passam lá não provam compatibilidade com o nível 100.

Estado de cada função ou sintaxe que a v1 mandava evitar (`[CONFIRMAR]` a lista exata da v1):

| Função ou sintaxe | Estado no nível 100 | O que fazer |
|---|---|---|
| STRING_SPLIT | Bloqueada abaixo de 130 (documentação Microsoft). | Usar XML (`nodes()` e `value()`) para listas. |
| OPENJSON | Bloqueada abaixo de 130 (documentação Microsoft). | Evitar. |
| JSON_VALUE, JSON_QUERY, ISJSON, FOR JSON | A documentação indica que não dependem do nível; a confirmar. | Evitar até confirmar. |
| TRY_CONVERT, TRY_CAST, IIF, CONCAT, FORMAT | Normalmente não dependem do nível; a confirmar. | Evitar até confirmar. |
| OFFSET … FETCH | Normalmente não depende do nível; a confirmar. | Evitar até confirmar. |
| THROW | Normalmente não depende do nível; a confirmar. | Usar RAISERROR até confirmar. |
| STRING_AGG | A confirmar. | Evitar até confirmar. |
| CREATE OR ALTER, DROP … IF EXISTS | Não dependem do nível, mas exigem SQL Server 2016 SP1 ou superior; a confirmar. | Permitido. Se falhar na base de testes, usar `IF OBJECT_ID(...) IS NOT NULL DROP ...` seguido de CREATE. |
| Tipos de tabela e TVP | Proibido por convenção da SigmaCode. | Usar XML. |

Enquanto uma função estiver "a confirmar", mantém-se evitada, mas o prompt não deve justificar a proibição com "bloqueada pelo nível 100".

Como confirmar: numa base de TESTE em nível 100, correr estes blocos de leitura, um de cada vez. Um erro de sintaxe ou "Invalid object name" quer dizer que a função está bloqueada nesse nível. Depois, passar a linha da tabela de "a confirmar" para "verificado em `<data>`, base `<nome>`". Se a base de testes não estiver em nível 100, o resultado não prova nada.

```sql
SELECT compatibility_level FROM sys.databases WHERE name = DB_NAME();
GO
SELECT TRY_CONVERT(int, '1') AS r;
GO
SELECT IIF(1 = 1, 'a', 'b') AS r;
GO
SELECT CONCAT('a', 'b') AS r;
GO
SELECT FORMAT(1234, 'N0') AS r;
GO
SELECT x FROM (VALUES (1), (2)) AS t(x) ORDER BY x OFFSET 0 ROWS FETCH NEXT 1 ROWS ONLY;
GO
SELECT JSON_VALUE('{"a":1}', '$.a') AS r;
GO
SELECT ISJSON('{}') AS r;
GO
SELECT STRING_AGG(x, ',') AS r FROM (VALUES ('a'), ('b')) AS t(x);
GO
SELECT value FROM STRING_SPLIT('a,b', ',');
GO
SELECT [key], value FROM OPENJSON('{"a":1}');
GO
BEGIN TRY SELECT 1/0; END TRY BEGIN CATCH THROW; END CATCH;
GO
```

## 6. Objetos de base de dados

Fonte única da regra do que o Claude Code pode criar: instruções do projeto. Resumo: SPs, views e triggers novos, só em base de teste e com confirmação; nunca tabelas nem campos.

A regra "apenas SPs" da v1 era uma regra de processo para o agente, não uma restrição técnica da conta SQL. `[CONFIRMAR]` com que permissões liga a conta usada pelo Claude Code à base de testes; o ideal é o mínimo necessário para criar SPs, views e triggers.

Nomes:

| Objeto | Nome |
|---|---|
| Stored Procedure | `sc_<Entidade><Acao>`, nunca `sp_` |
| View | `[NOVO]` proposta: `sc_v_<Nome>` |
| Trigger | `[NOVO]` proposta: `tr_sc_<Tabela>_<Acao>` |
| Tabela de utilizador | `u_<nome>`, criada pelo Flávio no PHC |

No Landeiro os nomes são `u_v_crm_*` (views), `up_crm_*` (SPs) e `tr_crm_*` (triggers). `[CONFIRMAR]` se ficam como exceção desse cliente ou se alinham com a convenção acima.

Listas como parâmetro: XML. Sem TVP nem tipos de tabela.

## 7. Ambientes e bases de teste

- Só se escreve em bases de teste, com confirmação, depois de `SELECT DB_NAME()`. Nunca em bases de clientes nem de produção.
- Base de testes padrão: `DemoSigmaCode`. A base de demonstração de um cliente (por exemplo `LAND2_DEMO`, usada só para os testes do Landeiro) é uma base de teste desse cliente e não se usa noutros projetos.
- Validar a performance numa cópia restaurada da base do cliente, numa instância de teste. Nunca na base real. (A v1 dizia "validar na base real", o que contradizia a regra de nunca executar scripts contra clientes ou produção.)
- Dados reais em testes: só os autorizados pelo cliente e, se possível, de uma cópia restaurada. Sem dados pessoais em logs nem em prompts. `[NOVO]`

## 8. Pontos a confirmar nesta v2

1. Lista exata de funções e sintaxe que a v1 mandava evitar, e quais já foram verificadas.
2. Instância e nível de compatibilidade da `DemoSigmaCode`.
3. Caminhos dos repositórios sUtils, sigma-phc-dossiers e API.
4. Nomes de views e triggers (proposta na secção 6) e se o Landeiro fica como exceção.
5. Se a APP .NET MAUI deve ter um ficheiro de convenções próprio.
6. O que acontece aos objetos de terceiros quando o PHC é atualizado.
