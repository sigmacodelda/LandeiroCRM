# Catálogo de tasks — SigmaCode

Versão 1.0 · 13/10/2026 · Substitui: — (ficheiro novo).

Define os tipos de task que o projeto sabe escrever, o que cada uma faz e produz, e quando fica concluída. As regras de estado e de avanço entre tasks estão em `modelo-task-global.md`. `[CONFIRMAR]` quer dizer que não tenho certeza e deves validar.

## 1. Como funciona

- Um trabalho (uma iniciativa de um cliente, ou uma melhoria) pode ter mais do que um prompt. Cada prompt é uma task de um tipo: levantamento de necessidades, desenho da solução, desenvolvimento, testes e documentação, solução (entrega e instalação) ou relatórios.
- Usa-se o mínimo de tasks que chega. Uma melhoria pequena pode ser só desenvolvimento e testes e documentação. Um trabalho de uma só task não precisa de task global.
- O desenvolvimento pode dividir-se em várias tasks (por módulo ou por fase), cada uma com o seu gate.
- O prompt de cada task só se escreve quando a anterior está CONCLUÍDA, porque depende do que ela produziu. No arranque escrevem-se só a task global e o prompt da primeira task. Se o Flávio pedir os seguintes já, escrevem-se marcados como "rascunho: rever quando a task anterior fechar".
- Os relatórios não fazem parte da sequência: podem sair a qualquer momento e não bloqueiam nenhuma task.
- O gate de cada task é manual por defeito: o Flávio confirma o fecho. Só é automático se o Flávio o pedir para essa task.
- Antes de escrever o prompt de uma task, o assistente faz as perguntas indicadas no tipo (só as que ainda não têm resposta), além das perguntas de ambiente das instruções do projeto.

## 2. Nomes de ficheiros

- Prompts das tasks: `docs/tasks/NN-<tipo>.md`, com NN pela ordem na iniciativa e `<tipo>` igual a `levantamento`, `desenho`, `desenvolvimento`, `testes-documentacao` ou `solucao`. Se houver várias do mesmo tipo, acrescenta-se um sufixo (`03-desenvolvimento-api.md`).
- Estado: `docs/tasks/00-global.md`.
- Saídas de cada task: em `docs/`, com nomes estáveis e sem número (por exemplo `docs/levantamento.md`), para não mudarem se as tasks mudarem de ordem.
- Relatórios: `docs/relatorios/<tipo>-<AAAA-MM-DD>.md`.
- Se o repositório já tiver outra estrutura de documentação, segue-se essa e registam-se os caminhos no `00-global.md`.
- A pasta `docs/tasks/` é versionada com o código: é o histórico do trabalho.

## 3. O que cada tipo de task pode fazer

| Tipo | Escreve documentos | Escreve código e scripts | Base de testes |
|---|---|---|---|
| `levantamento` | Sim | Não | Só leitura, se o prompt autorizar, com confirmação |
| `desenho` | Sim | Não (só esboços dentro dos documentos) | Não |
| `desenvolvimento` | Sim | Sim (SPs, views e triggers novos; nunca tabelas) | Instala com confirmação por lote |
| `testes-documentacao` | Sim | Só testes | Corre testes, com confirmação |
| `solucao` | Sim | Só o pacote e o runbook de instalação | Instalação de teste, com confirmação |
| `relatorios` | Sim | Não | Não |
| task global | Só o `00-global.md` | Não | Não |

Em nenhuma task se executa nada em bases de clientes ou de produção, e em nenhuma se criam tabelas ou campos.

## 4. Levantamento de necessidades (`levantamento`)

- Objetivo: perceber e registar o que é preciso, sem desenhar nem programar.
- Perguntas antes de escrever o prompt: qual é o pedido numa frase; quem é o cliente e quem decide; que documentação ou anexos existem; prazos e urgência; volumes e frequência dos dados; que terceiros estão envolvidos (quem fornece a API ou os dados).
- Entradas: pedido inicial, anexos (documentação do cliente, PDFs de APIs, exemplos de dados) e o repositório existente.
- Faz: lista requisitos funcionais e não funcionais, regras de negócio, dados envolvidos (tabelas e campos, só por leitura), integrações, volumes, restrições (edição e versão do PHC, nível de compatibilidade, rede, segurança), critérios de aceitação por requisito, "Fora de âmbito" e pendências com dono. Prepara as perguntas para o cliente ou terceiros (por exemplo um email), com o impacto e a suposição por defeito em cada uma.
- Não faz: desenho, código, scripts de escrita, criação de objetos na base. Consultas de leitura na base de testes só se o prompt as autorizar, com confirmação e `SELECT DB_NAME()` antes.
- Saídas: `docs/levantamento.md` e rascunhos de perguntas (`docs/perguntas-<destinatário>.md`).
- Critérios de conclusão: requisitos numerados e sem ambiguidade; ambiente completo no `00-global.md` (edição e versão do PHC, nível de compatibilidade, se se podem criar tabelas, base de testes, triggers existentes); critérios de aceitação para cada requisito; "Fora de âmbito" fechado; pendências com dono, e as que bloqueiam o desenho resolvidas ou assumidas como suposição registada em Decisões.
- Modo por defeito: autónomo.

## 5. Desenho da solução (`desenho`)

- Objetivo: decidir a solução mais correta e mais simples e deixá-la pronta a implementar.
- Perguntas antes de escrever o prompt: há restrições de arquitetura (serviço Windows, API, só SQL); que risco é aceitável; a entrega é por fases; quem aprova o desenho.
- Entradas: `docs/levantamento.md` e o `00-global.md`.
- Faz: aplica a escada de preferência (consulta ou SP de leitura, view, SP de escrita, trigger novo, tabela nova criada no PHC, serviço externo) e justifica cada degrau; regista as alternativas rejeitadas; desenha o circuito (diagrama Mermaid) e o modelo de dados; especifica as tabelas e campos a criar no PHC em `<phc_tables>`, ou uma alternativa sem tabela se o PHC do cliente não permite; lista os objetos SQL (SPs, views, triggers) com o contrato de cada um; define contratos de API e mensagens, tratamento de erros, segurança, estratégia de testes, instalação e reversão; lista os riscos.
- Não faz: implementar (só esboços e assinaturas), criar objetos, executar nada.
- Saídas: `docs/desenho.md` e, se a solução for grande, `docs/arquitetura.md`.
- Critérios de conclusão: cada requisito do levantamento tem resposta no desenho (tabela de rastreabilidade); decisões e alternativas registadas no `00-global.md`; especificação de tabelas completa e já criada no PHC, ou registada como pendência que bloqueia só a parte que depende dela; estratégia de testes definida; aprovação do Flávio.
- Modo por defeito: autónomo.

## 6. Desenvolvimento (`desenvolvimento`)

- Objetivo: implementar o desenho aprovado.
- Perguntas antes de escrever o prompt: que parte do desenho (módulo ou fase); repositórios e branch; já existem testes; modo (Plan Mode ou autónomo); como se confirma a instalação na base de testes.
- Entradas: `docs/desenho.md`, os repositórios e o `00-global.md` (ambiente e decisões).
- Faz: código C#/.NET e scripts SQL (SPs, views e triggers novos), com comentários e testes unitários; instala na base de testes, com confirmação por lote, depois da verificação textual (`convencoes-codigo.md`, secção 8.7); revisão crítica da própria implementação.
- Não faz: criar tabelas ou campos; mexer em triggers existentes; desviar-se do desenho sem registar a decisão; commit ou push sem confirmação.
- Saídas: código e scripts no repositório (branch próprio) e `docs/desenvolvimento.md` com o que foi feito, os desvios ao desenho e como compilar e correr.
- Critérios de conclusão: compila sem erros nem avisos novos; testes unitários passam; scripts passaram a verificação textual e estão instalados e verificados na base de testes (se aplicável); sem credenciais; desvios ao desenho registados; REVISÃO feita.
- Modo por defeito: Plan Mode.

## 7. Testes e documentação (`testes-documentacao`)

- Objetivo: provar que a solução cumpre os critérios de aceitação e deixar tudo documentado.
- Perguntas antes de escrever o prompt: quais são os critérios de aceitação (se não estiverem no levantamento); que dados de teste existem e se a base de testes tem volume realista; que documentação o cliente exige.
- Entradas: levantamento (critérios de aceitação), desenho, código e scripts.
- Faz: plano de testes com cenários por requisito; executa testes unitários, de integração e ponta a ponta (e de performance, se aplicável), com evidências; documenta o dicionário de dados, o manual de instalação, o manual de operação, a arquitetura atualizada e as pendências; declara as limitações do ambiente de testes (por exemplo, nível de compatibilidade diferente do cliente).
- Não faz: corrigir código. Uma falha de código ou de desenho é registada e reabre a task de desenvolvimento (ou de desenho), onde se corrige, para o histórico ficar limpo. Pode corrigir erros dos próprios testes e da documentação.
- Saídas: `docs/plano-de-testes.md`, evidências em `docs/evidencias/`, `docs/dicionario-de-dados.md`, `docs/manual-instalacao.md` e `docs/manual-operacao.md`.
- Critérios de conclusão: cada critério de aceitação tem resultado e evidência; as falhas estão resolvidas ou aceites pelo Flávio com registo; documentação completa e coerente com o código (nomes, caminhos, versões); nada declarado como testado sem ter corrido.
- Modo por defeito: autónomo.

## 8. Solução: entrega e instalação (`solucao`)

`[CONFIRMAR]` Interpretei "task de solução" como a entrega e instalação da solução no cliente, depois dos testes. Se querias outra coisa, diz e ajusto este tipo.

- Objetivo: deixar a solução pronta a instalar no cliente e entregue.
- Perguntas antes de escrever o prompt: quem instala e em que janela; pré-requisitos do cliente (edição e versão do PHC, permissões, tabelas já criadas no PHC); plano de arranque (por exemplo, testes um a um antes da carga completa); formação e suporte.
- Entradas: todas as saídas anteriores.
- Faz: pacote de instalação (scripts por ordem, binários, configuração de exemplo sem segredos); runbook de instalação passo a passo, com quem faz o quê; verificações pós-instalação; plano de reversão; checklist de arranque e de entrega; plano de monitorização e de suporte.
- Não faz: instalar ou executar nada em bases de clientes ou de produção. Instala o Flávio. O Claude Code prepara e valida o runbook numa instalação de teste.
- Saídas: `docs/entrega.md` e o pacote em `deploy/` (ou na pasta que o repositório já usa).
- Critérios de conclusão: runbook seguido numa instalação de teste limpa (lacunas declaradas); reversão testada; pré-requisitos do cliente listados; credenciais fora do pacote; instalação real e aceitação do cliente confirmadas pelo Flávio.
- Modo por defeito: Plan Mode.

## 9. Relatórios (`relatorios`)

`[CONFIRMAR]` Interpretei "relatórios" como relatórios do próprio trabalho: de estado, de testes e de entrega. Se também queres uma task para desenvolver relatórios do PHC (listagens ou BI), isso é uma variante de `desenvolvimento`.

- Objetivo: expor em documento o estado ou o resultado, a partir de factos.
- Tipos: estado (progresso), testes, entrega ou final. Destinatário: interno ou cliente.
- Perguntas antes de escrever o prompt: tipo e destinatário; período; formato (markdown, Word ou PDF); pode incluir dados do cliente.
- Entradas: o `00-global.md` e as saídas das tasks.
- Faz: resume o que está feito, em curso e pendente, com os riscos e as pendências à vista. Cada afirmação aponta para uma evidência (ficheiro, teste, medição).
- Não faz: análise nova, promessas de datas, nem factos sem evidência. Num relatório para o cliente, nada de IPs, instâncias, credenciais nem discussões internas.
- Identidade visual: se o relatório for um documento formatado (Word, PDF ou HTML), segue a identidade SigmaCode. Cores: #5BB572 (verde), #3466AF (azul), #604696 (roxo), #1A1731 (azul-escuro) e #CAC9C9 (cinzento). Tipografia principal Exo 2 e secundária Open Sans. Só muda se o pedido disser `Cliente: <nome>, usar cores do cliente`.
- Saídas: `docs/relatorios/<tipo>-<AAAA-MM-DD>.md` (ou o formato pedido) e uma linha na secção "Relatórios emitidos" do `00-global.md`.
- Critérios de conclusão: cada afirmação tem evidência; coerente com o `00-global.md`; revisto pelo Flávio antes de sair para o cliente.
- Modo por defeito: autónomo.

## 10. Task global

Não é uma task de trabalho: é o controlo das outras. Mantém o estado de todas as tasks, só deixa avançar quando a anterior está concluída e expõe tudo. Regras, modelo do `00-global.md` e prompt "expor tudo" em `modelo-task-global.md`.
