# Pacote claude-setup (SigmaCode)

Pacote partilhado da equipa para trabalhar com o Projeto Claude "SigmaCode – Prompts para Claude Code" e com os agentes do Claude Code. Guardar num repositório git privado da equipa (sem credenciais, IPs nem tokens). Caminho recomendado em cada máquina: `C:\_SigmaRepos\claude-setup`.

## Conteúdo

- `projeto/`: o que se carrega no Projeto Claude (`instrucoes-para-colar.md` e `projeto-sigmacode.md`). É a versão de referência.
- `.claude/`: os agentes `sc-leitor`, `sc-leitor-bd`, `sc-revisor` e `sc-dev`, o hook de SQL só-leitura, o teste do hook e o `settings.json`.
- `docs/phc/`: dicionário do PHC (`phc-dicionario.txt`, `phc-diretorio.txt`) e `gerar-dicionario.py`.
- `instalar.ps1`: copia `.claude/` e `docs/phc/` para um repositório de trabalho.

## Como a equipa o usa

1. Uma só pessoa cria o Projeto Claude (instruções de `projeto/instrucoes-para-colar.md` e ficheiro de conhecimento `projeto/projeto-sigmacode.md`) e partilha-o com a equipa, se o plano o permitir. Todos usam o mesmo.
2. Cada programador faz clone deste repositório uma vez, em `C:\_SigmaRepos\claude-setup`.
3. Em cada repositório de trabalho, a primeira conversa no Projeto produz sozinha o prompt de preparação (task 00). Colar esse prompt no Claude Code instala o pacote e testa o hook. Não há passos manuais.
4. A palavra-passe da base de testes de cada pessoa fica na variável de ambiente `SQLCMDPASSWORD` da sua máquina, nunca no repositório.

## Como se atualiza

1. Alterar a regra num só sítio: nos ficheiros deste pacote (e na Parte correspondente do `projeto-sigmacode.md`).
2. Subir a versão no topo do ficheiro alterado e fazer commit.
3. Quem mantém o Projeto Claude volta a carregar `projeto/projeto-sigmacode.md` e atualiza as instruções.
4. Cada programador faz `git pull` neste repositório e, em cada repositório de trabalho, corre `instalar.ps1 -Destino <repositório> -Atualizar` (ou pede ao Projeto o prompt de preparação outra vez).
5. Para um livro de PHC novo: `python docs/phc/gerar-dicionario.py livro.xlsx docs/phc` (precisa de `pip install openpyxl`) e commit.
