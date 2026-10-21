# Modelo de task global — SigmaCode

Versão 1.0 · 13/10/2026 · Substitui: — (ficheiro novo).

A task global é o ficheiro `docs/tasks/00-global.md` de um trabalho com várias tasks. Guarda o estado de todas, decide o que pode avançar e expõe tudo num só sítio. Este ficheiro tem as regras (secção 1), como o assistente as usa (secção 2), o modelo do `00-global.md` (secção 3) e o prompt "expor tudo" (secção 4). Os tipos de task estão em `catalogo-tasks.md`.

## 1. Regras

Estados
- PENDENTE: ainda não arrancou.
- EM_CURSO: em execução, ou reaberta.
- BLOQUEADA: parada por uma pendência ou por outra task (indica qual).
- CONCLUÍDA: fechada no gate.

Avanço
1. Por defeito as tasks são sequenciais: a task NN só arranca quando a anterior está CONCLUÍDA. Paralelo só se o Flávio o pedir, e fica registado em Decisões.
2. Uma task só fica CONCLUÍDA quando: (a) todos os critérios de conclusão estão cumpridos, cada um com evidência (ficheiro, teste ou medição); (b) não há pendência que a bloqueie; (c) o Flávio confirma. O Claude Code pede essa confirmação uma só vez, no fim da task, com a marca "GATE:". Nunca fecha a task sozinho, salvo se o prompt da task disser "gate automático".
3. Se uma task posterior encontrar um problema numa anterior, a anterior volta a EM_CURSO, com o motivo no Registo. As seguintes ficam BLOQUEADAS até a anterior voltar a fechar.
4. Decisões, pendências e riscos vivem só no `00-global.md`. Cada prompt copia as que lhe interessam e a task devolve as novas.
5. O que não está registado no `00-global.md` não aconteceu. O prompt da task seguinte parte deste ficheiro, não da memória.

Fecho de task (vai copiado para as regras de cada prompt, porque o Claude Code não vê estes ficheiros)
1. Atualiza o `00-global.md`: estado da task, saídas (caminhos), critérios (marca `[x]` só com evidência), decisões, pendências e riscos novos, e uma linha no Registo.
2. Escreve o ESTADO DA TASK no fim da resposta (formato na tag `<output_format>` de `modelo-prompt.md`).
3. Se todos os critérios estão cumpridos, escreve uma só vez "GATE: critérios cumpridos (n de n). Confirmas o fecho da task?" e pára. Depois da confirmação, marca CONCLUÍDA e indica qual é a task seguinte, sem a arrancar.
4. Se uma decisão trava o trabalho, escreve "BLOQUEIO:" com o motivo, marca a task BLOQUEADA e pára só o que depende dela.
5. Fora do GATE e do BLOQUEIO, não pede aprovações.

Quem faz o quê
- Claude Code: mantém o `00-global.md` durante as tasks.
- Projeto Claude (o assistente): escreve o `00-global.md` inicial e os prompts. Antes de escrever o prompt da task seguinte, pede o `00-global.md` atual.
- Flávio: confirma os gates, cria no PHC as tabelas e campos especificados, instala em clientes e em produção.

## 2. Como o assistente usa isto

- No arranque de um trabalho com várias tasks: faz as perguntas de ambiente e de âmbito, propõe as tasks necessárias (o mínimo que chega) como plano, e depois da minha confirmação escreve o `00-global.md` inicial (ambiente preenchido, tasks planeadas com critérios previstos, primeira task EM_CURSO) e o prompt da primeira task. Os prompts seguintes só se escrevem quando chegarem a vez.
- Para a task seguinte: pede o `00-global.md` atual (colado ou anexado). Verifica se a task anterior está CONCLUÍDA e sem pendência bloqueante. Se não estiver, diz o que falta em vez de escrever o prompt. Se estiver, escreve o prompt com as saídas da anterior como entradas e as decisões e pendências relevantes copiadas do global.
- Quando o Flávio pede "expor tudo" ou o estado: a partir do `00-global.md` que ele cole, mostra a tabela de tasks com estado e critérios, as saídas, as decisões, as pendências (dono e se bloqueiam), os riscos e o próximo passo. Se ele quiser a verificação contra o repositório, entrega o prompt "expor tudo" (secção 4) para correr no Claude Code.
- Se o `00-global.md` contradiz o que o Flávio diz, assinala a contradição e pergunta qual vale. Não decide sozinho.
- Trabalhos de uma só task não têm `00-global.md`: o prompt traz "Task global: não" e o fecho resume-se ao ESTADO DA TASK e ao GATE.

## 3. Modelo do `00-global.md`

O assistente escreve este ficheiro no arranque, com o ambiente e as tasks planeadas. A partir daí quem o mantém é o Claude Code.

````markdown
# <Iniciativa> — Task global

Cliente: <cliente> · Iniciativa: <nome> · Criado: <AAAA-MM-DD> · Última atualização: <AAAA-MM-DD HH:MM>
Repositórios: `C:\_SigmaRepos\<repositório>` · Branch: `<feature/...>` · Pasta das tasks: `docs/tasks/`

## 1. Regras (não editar)

- Estados: PENDENTE, EM_CURSO, BLOQUEADA, CONCLUÍDA.
- Sequencial: a task NN só arranca quando a anterior está CONCLUÍDA. Paralelo só se o Flávio o pedir (fica em Decisões).
- CONCLUÍDA = todos os critérios cumpridos com evidência, sem pendência que bloqueie, e confirmação do Flávio no gate. Nenhuma task se fecha sozinha, salvo "gate automático" indicado no prompt dessa task.
- Reabrir: uma task posterior que encontre um problema numa anterior reabre-a (EM_CURSO, com o motivo no Registo). As seguintes ficam BLOQUEADAS até a anterior voltar a fechar.
- Decisões, pendências e riscos vivem só aqui. O que não está aqui não aconteceu.
- Nunca se escrevem aqui credenciais, tokens nem connection strings.

## 2. Ambiente

| Facto | Valor |
|---|---|
| Edição e versão do PHC | |
| Alojamento e acesso à base de dados | |
| SQL Server (versão) e nível de compatibilidade | |
| Criar tabelas e campos no PHC: é possível? Quem cria? | |
| Base de testes (nome, instância, cópia restaurada?) | |
| Triggers existentes nas tabelas envolvidas | |
| Onde corre o código | |

## 3. Tasks

| NN | Tipo | Task | Estado | Prompt | Saídas | Critérios | Bloqueio | Atualizada |
|---|---|---|---|---|---|---|---|---|
| 01 | levantamento | <título> | EM_CURSO | `docs/tasks/01-levantamento.md` | `docs/levantamento.md` | 0 de <n> | — | <AAAA-MM-DD> |
| 02 | desenho | <título> | PENDENTE | (por escrever) | `docs/desenho.md` | 0 de <n> | task 01 | — |

### Critérios de conclusão por task

Task 01 — <título>
- [ ] <critério> — evidência: <ficheiro e secção, teste ou medição>
- [ ] <critério> — evidência:

Task 02 — <título>
- [ ] <critério> — evidência:

## 4. Decisões

| # | Decisão | Alternativas rejeitadas e porquê | Task | Data |
|---|---|---|---|---|

## 5. Pendências

| # | Pendência | Dono | Bloqueia? (que task) | Estado |
|---|---|---|---|---|

## 6. Riscos

| # | Risco | Impacto | Mitigação | Task |
|---|---|---|---|---|

## 7. Relatórios emitidos

| Data | Tipo | Destinatário | Ficheiro |
|---|---|---|---|

## 8. Registo

- <AAAA-MM-DD HH:MM> · Task NN · <arrancou, bloqueada, pronta para gate, concluída ou reaberta> · <nota>

## 9. Próximo passo

<uma frase: o que pode avançar agora e quem faz>
````

## 4. Prompt "expor tudo"

Pode ser dado ao Claude Code em qualquer momento. Verifica o estado contra o repositório, atualiza o `00-global.md` e expõe tudo. Preencher só os marcadores.

````markdown
# Task global: expor tudo
Versão 1.0 · <AAAA-MM-DD> · Iniciativa: <nome> · Cliente: <cliente>

Modo: autónomo (só pára em BLOQUEIO: ou no GATE:)

<role>
És um engenheiro de software sénior. Escreves em português de Portugal. Objetivos: segurança, confiabilidade, manutenibilidade e clareza. Aqui não desenvolves nada: verificas e expões o estado.
</role>

<context>
- Estado da iniciativa em `docs/tasks/00-global.md`. Prompts das tasks em `docs/tasks/`. Saídas em `docs/` (caminhos indicados no `00-global.md`).
- Repositório: `C:\_SigmaRepos\<repositório>`.
</context>

<task>
Objetivo: dar-me o estado completo e verificado da iniciativa e dizer o que pode avançar.

1. Lê `docs/tasks/00-global.md` e, para cada task, as suas saídas.
2. Verifica cada critério de conclusão com evidência real: o ficheiro existe, o conteúdo cumpre o critério, o teste está registado com resultado. Não voltes a correr testes nem toques em bases de dados: usa as evidências registadas. Um critério sem evidência fica por cumprir.
3. Atualiza o `00-global.md`: estados, critérios (marca `[x]` só com evidência), "Atualizada" e uma linha no Registo. Não marques nenhuma task como CONCLUÍDA: se uma task tem todos os critérios cumpridos, regista "pronta para gate" e escreve uma só vez "GATE:" a pedir a minha confirmação.
4. Procura incoerências: saída em falta ou com caminho errado; decisão contrariada pelo código ou por outra task; pendência sem dono; task a avançar com a anterior por concluir; critério marcado sem evidência; ambiente do `00-global.md` diferente do que está nos scripts (base de testes, nível de compatibilidade).
5. Diz qual é a próxima task que pode arrancar e o que falta para a desbloquear.

Fora de âmbito: alterar código ou scripts, executar scripts, tocar em bases de dados, commit ou push.
</task>

<rules>
- Só factos com evidência. Quando não consegues verificar, escreve "não verificado" e o motivo.
- Sem credenciais, tokens nem connection strings na resposta nem nos ficheiros.
- Escreve apenas em `docs/tasks/00-global.md`.
- Usa "BLOQUEIO:" apenas para o que realmente trava e "GATE:" só quando uma task estiver pronta para fechar. Fora disso, não peças aprovações.
</rules>

<output_format>
Responde por esta ordem, em português de Portugal:
1. ESTADO GLOBAL: tabela de tasks (número, tipo, estado, critérios n de n, bloqueio).
2. SAÍDAS: ficheiros por task, com "existe" ou "em falta".
3. DECISÕES: as registadas, por task.
4. PENDÊNCIAS: com dono e se bloqueiam (e que task).
5. RISCOS.
6. INCOERÊNCIAS: o que encontraste, ou "nenhuma".
7. PRÓXIMO PASSO: o que pode avançar e quem faz.
</output_format>
````
