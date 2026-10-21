# Exemplo de prompt: otimização do acesso a dados de um módulo da API

Versão 2.0 · 13/10/2026 · Substitui a v1.
Estado: reconstruído a partir da conversa de 13/10/2026, sem o texto original da v1. Onde estava o caso concreto (módulo, tabelas, endpoints) estão marcadores `<...>`. Compara com a tua v1 antes de a substituir. Serve de referência de estrutura e de nível de detalhe, não para executar tal e qual. `[CONFIRMAR]` quer dizer que não tenho certeza.

É um exemplo de uma task de desenvolvimento num trabalho de uma só task (sem task global). O formato geral está em `modelo-prompt.md` e os tipos de task em `catalogo-tasks.md`.

O que este exemplo mostra:
- Cabeçalho com versão, task, entradas, saídas, critérios de conclusão e gate.
- `<environment>` com a base de testes, a verificação do nome da base e o que o Claude Code pode e não pode criar.
- `<decisions>` com alternativas rejeitadas e `<open_points>` com dono e se bloqueia.
- "Fora de âmbito" explícito.
- Duas fases, uma estrutural e outra de comportamento, em commits separados.
- `<tests>` com cenários e método de medição.
- Uma confirmação por módulo para instalar na base de testes.

## Prompt

````markdown
# Otimizar o acesso a dados do módulo <Módulo> da API
Versão 1.0 · <DD/MM/AAAA> · Substitui: —

Iniciativa: Otimização do módulo <Módulo> · Cliente: SigmaCode (interno)
Task: 01 · Tipo: desenvolvimento
Task global: não (trabalho de uma só task)
Modo: Plan Mode (para no PLANO e espera a minha confirmação antes de alterar ficheiros)
Entradas: o módulo atual no repositório e <anexos, se houver>
Saídas: código e scripts no branch `feature/<nome>`; `docs/otimizacao-<modulo>.md` com as medições antes e depois
Critérios de conclusão:
1. O JSON de resposta de cada endpoint do módulo é igual antes e depois (mesmos pedidos).
2. O número de idas à base de dados por pedido baixou, com a medição antes e depois registada.
3. Compila sem erros nem avisos novos e os testes passam.
4. As SPs passaram a verificação textual e estão instaladas e verificadas na base de testes.
5. Sem credenciais em código, logs ou documentação.
Gate: manual (eu confirmo o fecho da task)

<role>
És um engenheiro de software sénior, especialista em .NET 8, Dapper e SQL Server (bases PHC). Escreves em português de Portugal. Objetivos: segurança, confiabilidade, manutenibilidade e clareza.
</role>

<context>
- Projeto: API ASP.NET Core (.NET 8) da SigmaCode. Módulo a otimizar: <Módulo> (por exemplo logística e transferências).
- Repositórios: `C:\_SigmaRepos\<API>` e `C:\_SigmaRepos\sigma-phc-dossiers` (a API referencia a biblioteca por ProjectReference).
- Problema: <descrição; por exemplo demasiadas idas à base de dados por pedido, consultas repetidas num ciclo (N+1), lógica de dados no C# que devia estar na base>.
- Anexos: <lista, ou "nenhum">.
</context>

<environment>
- PHC: edição <Advanced, Evolution ou outra>, versão <...>.
- SQL Server <versão>; base do cliente em nível de compatibilidade <100>.
- Base de testes: `DemoSigmaCode`, a única onde se pode escrever. Antes de qualquer escrita: `SELECT DB_NAME();` e confirmar que é `DemoSigmaCode`.
- Bases proibidas: bases de clientes e de produção. Não executar nada nelas.
- O Claude Code pode criar SPs, views e triggers novos, só na base de testes e com confirmação. Nunca cria tabelas nem campos. Neste prompt só são precisas SPs.
- Não é precisa nenhuma tabela nova. Se a otimização exigir um índice, uma tabela ou um campo, o Claude Code não os cria: propõe-os em RISCOS e, se bloquearem, escreve "BLOQUEIO:".
</environment>

<task>
Objetivo: reduzir o número de idas à base de dados por pedido, e o tempo de resposta, dos endpoints do módulo <Módulo>, sem alterar o contrato JSON.

Âmbito:
- Endpoints do módulo <Módulo>: <lista>.
- Fase 1, estrutural, sem mudar comportamento: reorganizar o módulo (Controllers finos, Services com interface, Mappers, DTOs).
- Fase 2, de comportamento: mover o acesso a dados para SPs `sc_<Entidade><Acao>`, chamadas com Dapper, com listas em XML.
- As fases 1 e 2 vão em commits separados (de preferência em branches separados), para se poder reverter uma sem a outra.

Fora de âmbito:
- Outros módulos, a APP, os sServices e os sUtils.
- Alterar o contrato JSON, os códigos HTTP ou a autenticação.
- Criar tabelas, campos, índices, triggers ou views.
- Mudar de biblioteca de acesso a dados.

Solução escolhida e porquê: SPs chamadas com Dapper, por ser o padrão da casa e resolver as idas repetidas numa só chamada por ação. `[CONFIRMAR]` motivo da v1.
</task>

<decisions>
- A lógica de acesso a dados passa para SPs `sc_<Entidade><Acao>`. Alternativa rejeitada: otimizar só as queries em C#, porque não elimina as idas repetidas. `[CONFIRMAR]` motivo da v1.
- Listas como parâmetro em XML. Alternativas rejeitadas: STRING_SPLIT (exige nível 130) e tipos de tabela (proibidos por convenção).
- O contrato JSON dos endpoints não muda.
- Branch `feature/<nome>`, o mesmo nome em todos os repositórios alterados.
</decisions>

<open_points>

| # | Pendência | Dono | Bloqueia? |
|---|---|---|---|
| 1 | Confirmar o nível de compatibilidade da base onde isto vai correr | Flávio | Sim, a instalação das SPs; não, a fase 1 |
| 2 | <...> | <...> | <...> |
</open_points>

<rules>
- Segue os padrões que já existem no repositório. Prefere a solução mais simples que seja correta. Não introduzas dependências sem justificação.
- DTOs em todas as trocas entre camadas; nunca expor modelos de dados. Estrutura por módulo, com Controllers finos, Services com interface e Mappers.
- try/catch com log nos pontos críticos, sem apanhar exceções para as ignorar.
- Configuração no appsettings com Options pattern. Nada fixo no código.
- Compatibilidade: C# 7.3 na biblioteca partilhada (netstandard2.0). SQL compatível com o nível <100>. Evitar: STRING_SPLIT, OPENJSON, JSON_VALUE, JSON_QUERY, ISJSON, FOR JSON, TRY_CONVERT, TRY_CAST, IIF, CONCAT, FORMAT, OFFSET … FETCH, STRING_AGG, THROW (usar RAISERROR), tipos de tabela e TVP (usar XML). `[CONFIRMAR]` lista atual em `contexto-stack.md`, secção 5.
- Código sempre comentado, com uma explicação simples do que faz, em português.
- Segurança: sem credenciais em código, logs ou documentação; consultas parametrizadas.
- Base de dados: instalar SPs só em `DemoSigmaCode`, com uma confirmação por módulo (lista de scripts e base de destino), depois de confirmar `DB_NAME()`. Antes de pedir a confirmação, faz a verificação textual: nenhum script pode ter CREATE TABLE (exceto temporárias), ALTER TABLE, DROP TABLE, TRUNCATE, SELECT INTO para tabela permanente nem sp_settriggerorder. Cada script começa com a guarda de base de dados.
- Git: o mesmo nome de branch em todos os repositórios alterados. Sem commit nem push sem confirmação.
- Revisão crítica da tua implementação antes de entregar.
- Fecho da task:
  1. Escreve o ESTADO DA TASK no fim da resposta.
  2. Se todos os critérios estão cumpridos, escreve uma só vez "GATE: critérios cumpridos (n de n). Confirmas o fecho da task?" e pára.
  3. Usa "BLOQUEIO:" só quando uma decisão realmente trava o trabalho, e continua o que não depende dela. Fora do GATE e do BLOQUEIO, não peças aprovações.
</rules>

<tests>
Cenários:
1. Para cada endpoint, a resposta JSON depois da otimização é igual à de antes (mesmos pedidos, comparação campo a campo), incluindo lista vazia e um só elemento.
2. Cada SP: com lista vazia, com um elemento, com muitos elementos e com valores inexistentes.
3. Falha da base de dados: o endpoint devolve o erro esperado e regista log.

Método de medição (antes e depois, nos mesmos pedidos):
- Contador de idas à base de dados por pedido, no executor de acesso a dados.
- `Stopwatch` por ação (endpoint).
- `SET STATISTICS IO, TIME ON` nas SPs, na base de testes.
- Comparação do JSON de resposta antes e depois.

Se a base de testes não tiver volume realista, declara-o em TESTES e propõe como validar numa cópia restaurada da base do cliente, numa instância de teste. Nunca na base real.
</tests>

<output_format>
Responde por esta ordem, em português de Portugal: ANÁLISE, PLANO, IMPLEMENTAÇÃO, REVISÃO, TESTES, RISCOS e, no fim, ESTADO DA TASK.
- ANÁLISE: o que encontraste (idas à base de dados por endpoint, antes).
- PLANO: passos, ficheiros a alterar e SPs a criar. Para aqui e espera a minha confirmação (Plan Mode).
- IMPLEMENTAÇÃO: o que foi alterado, por fase.
- REVISÃO: crítica da tua própria implementação.
- TESTES: o que correu, os resultados e as medições antes e depois; o que não correu e porquê.
- RISCOS: riscos e impactos, e o que fica pendente.
- ESTADO DA TASK: (1) estado (EM_CURSO, BLOQUEADA ou pronta para gate); (2) critérios cumpridos (n de n) e os que faltam; (3) pendências novas, com dono e se bloqueiam.
Usa "BLOQUEIO:" só para uma decisão que realmente trava o trabalho.
</output_format>

<examples>
Exemplo ilustrativo de SP com lista em XML. O Claude Code segue o padrão que já existir no repositório.

```sql
-- Guarda: só deixa correr nas bases de teste autorizadas.
DECLARE @bd sysname = DB_NAME();
IF @bd NOT IN (N'DemoSigmaCode')
BEGIN
    RAISERROR(N'Base de dados nao autorizada: %s', 16, 1, @bd);
    SET NOEXEC ON;
END
GO

-- sc_DossierLinhasListar: devolve as linhas (BI) dos dossiers cujos stamps vêm numa lista XML.
-- Parâmetro @bostamps: <l><s>stamp1</s><s>stamp2</s></l>
CREATE OR ALTER PROCEDURE dbo.sc_DossierLinhasListar
    @bostamps xml
AS
BEGIN
    SET NOCOUNT ON;

    -- Converte a lista XML numa tabela temporária (permitido: não é uma tabela permanente).
    SELECT x.s.value('.', 'char(25)') AS bostamp
    INTO #stamps
    FROM @bostamps.nodes('/l/s') AS x(s);

    SELECT bi.bostamp, bi.ref, bi.qtt
    FROM dbo.bi AS bi
    INNER JOIN #stamps AS st ON st.bostamp = bi.bostamp;
END
GO

SET NOEXEC OFF;
GO
```

Exemplo ilustrativo da chamada com Dapper (C# 7.3).

```csharp
// Chama a SP e devolve as linhas já como DTO.
public async Task<IReadOnlyList<LinhaDto>> ListarLinhasAsync(IEnumerable<string> stamps)
{
    // A lista vai para a SP em XML: <l><s>stamp1</s><s>stamp2</s></l>
    var xml = new XElement("l", stamps.Select(s => new XElement("s", s))).ToString();

    using (var ligacao = new SqlConnection(_opcoes.ConnectionString))
    {
        var linhas = await ligacao.QueryAsync<LinhaDto>(
            "dbo.sc_DossierLinhasListar",
            new { bostamps = xml },
            commandType: CommandType.StoredProcedure);

        return linhas.AsList();
    }
}
```
</examples>
````
