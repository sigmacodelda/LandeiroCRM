# Criar o repositório Claude-The-ALLKNOWING e instalar o setup global
Versão 1.0 · 13/10/2026 · Substitui: —

Iniciativa: Claude-The-ALLKNOWING · Cliente: SigmaCode (interno)
Task: 01 · Tipo: desenvolvimento
Task global: não: trabalho de uma só task
Modo: Autónomo: avança e só pára em BLOQUEIO: ou no GATE:
Entradas: o zip `Claude-The-ALLKNOWING.zip` (ver `<context>`)
Saídas: repositório privado `<organização>/Claude-The-ALLKNOWING` no GitHub, clone em `C:\_SigmaRepos\Claude-The-ALLKNOWING`, setup global instalado nesta máquina e a linha de instalação da equipa
Critérios de conclusão:
1. O zip foi descomprimido em `C:\_SigmaRepos\Claude-The-ALLKNOWING` sem sobrescrever nada que já lá estivesse.
2. A verificação de credenciais não encontrou palavras-passe, tokens, connection strings nem IPs de servidores.
3. O repositório existe no GitHub com visibilidade PRIVATE (prova: saída de `gh repo view --json visibility,url`), na branch `main`, com o primeiro commit enviado.
4. `instalar-global.ps1` correu sem erro e o teste do hook terminou com "Hook OK." (11 de 11 casos).
5. `~/.claude/CLAUDE.md` contém o bloco gerido `sigma:inicio` / `sigma:fim` e `~/.claude/agents/` contém `sc-leitor.md`, `sc-leitor-bd.md`, `sc-revisor.md` e `sc-dev.md`.
6. A linha de instalação da equipa foi impressa com o URL real do repositório.
Gate: manual: eu confirmo o fecho da task
Agentes: nenhum (tarefa curta e sequencial; os agentes `sc-*` só ficam instalados no fim)

<role>
És um engenheiro de software sénior, com experiência em Git, GitHub CLI e PowerShell. Escreves em português de Portugal. Objetivos: segurança, confiabilidade, manutenibilidade e clareza.
</role>

<context>
- Recebes este prompt com o zip `Claude-The-ALLKNOWING.zip` em `<caminho do zip>` (se eu não preencher o caminho, procura-o na pasta Transferências/Downloads do utilizador).
- Instrução que me foi dada ao entregar o zip: "É para correr o prompt PROMPT-CRIAR-REPOSITORIO.md".
- O zip tem uma única pasta de raiz, `Claude-The-ALLKNOWING/`, com:
  - `CLAUDE.md`: modelo das normas globais (traz marcadores `__RAIZ__`, que o instalador substitui pelo caminho real).
  - `README.md`: instalação, conteúdo e como alterar uma regra.
  - `instalar-global.ps1`: instala o setup global na máquina de cada programador (normas, agentes, definições e teste do hook). Opção `-Pull` para atualizar.
  - `hooks/`: `sql-so-leitura.ps1` (só deixa passar consultas de leitura ao `sqlcmd`, contra bases permitidas), `testar-hook.ps1` (11 casos), `bases-permitidas.txt` (bases de teste da equipa).
  - `agents/`: `sc-leitor.md`, `sc-leitor-bd.md`, `sc-revisor.md`, `sc-dev.md` (subagentes).
  - `normas/`: as 9 partes das normas (instruções, contexto da stack, convenções, catálogo de tasks, modelo de task global, modelo de prompt, exemplo de otimização, dicionário PHC, agentes) e `00-indice.md`.
  - `projeto/`: `projeto-sigmacode.md` (ficheiro de conhecimento único do Projeto Claude) e `instrucoes-para-colar.md` (texto das instruções do Projeto Claude).
  - `docs/phc/`: `phc-dicionario.txt`, `phc-diretorio.txt` e `gerar-dicionario.py`.
  - `tools/dividir-partes.py`: gera `normas/` a partir de `projeto/projeto-sigmacode.md`.
  - `.gitignore`.
- Objetivo: este zip serve para criar o repositório privado `Claude-The-ALLKNOWING`, que a equipa inteira usa. Quem o instala passa a ter as normas e os agentes em todas as conversas do Claude Code, desde a primeira, sem preparar nada por projeto.
- Organização GitHub: `<organização>`. Se o marcador não estiver preenchido, pergunta uma só vez e espera.
- Pasta de destino: `C:\_SigmaRepos\Claude-The-ALLKNOWING`.
Nota: este prompt não contém credenciais. Não pedir nem gravar palavras-passe ou tokens.
</context>

<task>
Executa pela ordem. Cada passo só avança se o anterior estiver verificado.

1. Verificações iniciais (só leitura): `git --version`; `gh --version`; `gh auth status`; PowerShell disponível; existência do zip; `<organização>` acessível (`gh api orgs/<organização> --jq .login`, ou, se for uma conta pessoal, `gh api users/<organização> --jq .login`). Se `gh` não estiver autenticado: BLOQUEIO: dizer-me para correr `gh auth login` e parar.
2. Pasta de destino: se `C:\_SigmaRepos\Claude-The-ALLKNOWING` já existir e não estiver vazia: BLOQUEIO: dizer o que lá está e parar. Não apagar nem sobrescrever.
3. Descomprimir o zip para `C:\_SigmaRepos` (a pasta de raiz do zip já se chama `Claude-The-ALLKNOWING`). Confirmar que existem `CLAUDE.md`, `instalar-global.ps1`, `hooks\sql-so-leitura.ps1`, `agents\sc-revisor.md` e `normas\09-agentes.md`. Confirmar que não existem `__pycache__` nem ficheiros `.bak-sigma`.
4. Verificação de credenciais no conteúdo descomprimido, excluindo `docs/phc/phc-dicionario.txt` (dicionário de campos, sem dados). Procurar, sem distinção de maiúsculas: `password=`, `pwd=`, `ghp_`, `github_pat_`, `sk-`, `AKIA`, `Bearer `, `BEGIN .* PRIVATE KEY`, `Server=` com IP, e endereços IPv4. Cada achado é mostrado em linha (ficheiro e número da linha, sem o valor). Se houver achados reais: BLOQUEIO: parar antes de qualquer commit. Falsos positivos óbvios (texto explicativo como "nunca guardar password=") são listados e dispensados com justificação.
5. Git local: `git init -b main`; `git add .`; mostrar `git status --short | wc -l` e confirmar que `hooks/bases-permitidas.local.txt` não está incluído; um único commit com a mensagem `Normas e agentes SigmaCode: versão inicial` (mais as linhas de atribuição que o ambiente exigir).
6. GitHub: `gh repo create <organização>/Claude-The-ALLKNOWING --private --source . --remote origin --push --description "Normas e agentes Claude Code da SigmaCode (uso interno)"`. Se o repositório já existir: BLOQUEIO: dizer-me, não forçar push.
7. Verificar visibilidade: `gh repo view <organização>/Claude-The-ALLKNOWING --json visibility,url`. Se não for PRIVATE: `gh repo edit --visibility private --accept-visibility-change-consequences`, voltar a verificar e, se continuar a não ser PRIVATE, BLOQUEIO: parar.
8. Instalar nesta máquina: `powershell -NoProfile -ExecutionPolicy RemoteSigned -File C:\_SigmaRepos\Claude-The-ALLKNOWING\instalar-global.ps1`. Mostrar a saída. O teste do hook tem de terminar com "Hook OK.". Se falhar: BLOQUEIO: mostrar os casos que falharam e parar, sem editar o hook para o fazer passar.
9. Verificação final (só leitura): o bloco `sigma:inicio` / `sigma:fim` em `~/.claude/CLAUDE.md`; os 4 ficheiros em `~/.claude/agents/`; `~/.claude/settings.json` com JSON válido, sem ter perdido chaves que já existissem (comparar com o `.bak-sigma`, se foi criado).
10. Imprimir, no fim, a linha de instalação da equipa com o URL real:

Clona <URL do repositório>.git para C:\_SigmaRepos\Claude-The-ALLKNOWING (se a pasta já existir, faz git pull) e corre powershell -NoProfile -ExecutionPolicy RemoteSigned -File C:\_SigmaRepos\Claude-The-ALLKNOWING\instalar-global.ps1. No fim diz-me se o teste do hook passou.

11. Lembrar-me, em RISCOS, das ações que são minhas e não tuas: convidar os colegas para a organização/repositório no GitHub; partilhar o Projeto Claude com a equipa (se o plano o permitir) e colar as instruções de `projeto/instrucoes-para-colar.md` e carregar `projeto/projeto-sigmacode.md`; cada programador definir `SQLCMDPASSWORD` no seu ambiente.
</task>

<constraints>
- Autorização explícita e limitada: criar e enviar este único repositório privado, e correr `instalar-global.ps1` nesta máquina. Nada mais fora de `C:\_SigmaRepos\Claude-The-ALLKNOWING` e de `~/.claude`.
- O repositório é sempre PRIVATE. Nunca público, nem temporariamente.
- Sem credenciais: não pedir, não gravar, não imprimir. Não ler nem alterar `~/.ssh`, nem variáveis de ambiente com segredos.
- Não executar scripts contra bases de dados. Este prompt não precisa de SQL Server. O teste do hook usa casos simulados e não liga a nenhuma base.
- Não fazer `push --force`, não apagar ficheiros nem pastas, não alterar o conteúdo dos ficheiros do zip (se encontrares um erro, regista-o e propõe a correção; não a apliques sem eu confirmar).
- Se uma ferramenta não existir (`git`, `gh`) não a instalar sem eu confirmar: BLOQUEIO: diz o que falta e como instalar.
- Se `~/.claude/CLAUDE.md` ou `~/.claude/settings.json` já existirem, o instalador preserva o que lá está. Não os reescrever à mão.
- Idioma: português de Portugal. Sem emojis.
</constraints>

<output_format>
Responde com: ANÁLISE, PLANO, IMPLEMENTAÇÃO, REVISÃO, TESTES, RISCOS e, no fim, ESTADO DA TASK (estado, critérios cumpridos com a evidência de cada um, pendências). Em IMPLEMENTAÇÃO lista os comandos executados e o resultado resumido. Em TESTES inclui a saída do teste do hook e a prova de visibilidade PRIVATE. Usa `BLOQUEIO:` quando não puderes avançar sem mim e `GATE:` uma só vez, no fim, para eu confirmar o fecho.
</output_format>
