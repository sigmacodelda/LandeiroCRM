<context>
Integração entre o PHC CS (SQL Server) do cliente Carnes Landeiro e o Somnia CRM (implementado pela Orcinus), via API.
Cliente PHC de teste: Nº 13444.
Nesta fase só se integram CLIENTES (e os seus contactos). Mais tarde entram fornecedores e colaboradores,
por isso o circuito tem de ser genérico desde o início: acrescentar uma nova origem não pode obrigar a mudar o código do serviço.

Ficou decidido o seguinte modelo:
1. Uma tabela de utilizador no PHC serve de fila, com tudo o que falta enviar para o CRM.
2. Os triggers nas tabelas de origem registam nessa fila cada criação, alteração ou eliminação, indicando de que tabela vem.
3. Um serviço no servidor PHC corre de X em X tempo: lê a fila, envia os dados para a API do CRM
   e atualiza o estado de cada registo (enviado / erro). Também escreve um ficheiro de log diário,
   e os logs com mais de N dias (por defeito 7, configurável) são apagados.
</context>

<attachments>
Envio em anexo a documentação. Lê tudo antes de começar:
1. somnia_api_20250403_accounts_contacts.pdf: especificação oficial da API (endpoints, autenticação, token, exemplos, respostas).
   Atenção: os exemplos JSON deste PDF têm erros de sintaxe (aspas e vírgulas). Usa-os só como referência de campos.
2. Landeiro_CRM_Envio_API_Exemplo.docx: resumo da SigmaCode, com os endpoints, exemplos JSON corrigidos e as respostas da API.
   Atenção: o mapeamento de campos deste documento é anterior a este prompt (diz, por exemplo, que o país vem de cl.pais).
   Se houver conflito, PREVALECE O MAPEAMENTO DESTE PROMPT.
3. Carnes_Landeiro_ProjetoCRM_20250324.pdf: âmbito do projeto da Orcinus, responsáveis e dados da importação inicial.
4. Acesso.pdf: instruções de primeiro acesso ao interface do CRM (alteração de palavra-passe). Serve só para consultar os dados no CRM durante os testes.
</attachments>

<task>Desenhar, desenvolver, documentar e testar o circuito de integração PHC → Somnia CRM (fila + triggers + views + serviço), começando pelos clientes e os seus contactos.</task>

<role>
És um Developer Sénior de C# .NET e SQL Server e especialista em PHC CS. Conheces a estrutura das tabelas do PHC (cl, cl2, fl, pe, cc), as convenções de stamps e de tabelas de utilizador, e o comportamento do PHC ao gravar fichas.
Vais fazer esta task do princípio ao fim, com o melhor desenho possível, documentação completa e testes em tudo.
</role>

<Requirements>
    ###Business
    -Campos do Cliente (Tabela CL): clstamp (Este campo apenas serve de ligação para os contactos na importação), no, nome, morada, codpost, local, ncont, telefone, tlmvl, email, fax.
    -Campos do Cliente (Tabela CL2, extensão 1 para 1 da CL, ligação cl2.cl2stamp = cl.clstamp): descpais.
    -Campos dos Contactos (Tabela U_CLCONTACT): Contacto, Departamento, Email, estab, Fax, Func, clstamp (Ligação tabela cl), Nome, Número, observações, telefone, telemóvel, tipo
    Sendo o seguinte:
        Tabela	Coluna	Tipo	Tamanho	Precisao	Escala	AceitaNull	ValorDefeito	Posicao
        cl	clstamp	char	25	NULL	NULL	NO	('')	1
        cl	nome	varchar	55	NULL	NULL	NO	('')	2
        cl	no	numeric	NULL	10	0	NO	((0))	3
        cl	ncont	varchar	20	NULL	NULL	NO	('')	6
        cl	fax	varchar	60	NULL	NULL	NO	('')	11
        cl	telefone	varchar	60	NULL	NULL	NO	('')	12
        cl	morada	varchar	55	NULL	NULL	NO	('')	27
        cl	local	varchar	43	NULL	NULL	NO	('')	28
        cl	codpost	varchar	45	NULL	NULL	NO	('')	29
        cl	email	varchar	100	NULL	NULL	NO	('')	74
        cl	tlmvl	varchar	45	NULL	NULL	NO	('')	86
        cl2	descpais	varchar	55	NULL	NULL	NO	('')	3
        u_clcontact	u_clcontactstamp	char	25	NULL	NULL	NO	('')	1
        u_clcontact	clstamp	char	25	NULL	NULL	NO	('')	2
        u_clcontact	fax	varchar	60	NULL	NULL	NO	('')	3
        u_clcontact	funcao	varchar	15	NULL	NULL	NO	('')	4
        u_clcontact	email	varchar	60	NULL	NULL	NO	('')	5
        u_clcontact	contacto	varchar	45	NULL	NULL	NO	('')	6
        u_clcontact	telefone	varchar	60	NULL	NULL	NO	('')	7
        u_clcontact	tipo	varchar	25	NULL	NULL	NO	('')	8
        u_clcontact	tlmvl	varchar	60	NULL	NULL	NO	('')	9
        u_clcontact	no	numeric	NULL	10	0	NO	((0))	10
        u_clcontact	nome	varchar	55	NULL	NULL	NO	('')	11
        u_clcontact	ousrinis	varchar	30	NULL	NULL	NO	('')	12
        u_clcontact	ousrdata	datetime	NULL	NULL	NULL	NO	(getdate())	13
        u_clcontact	ousrhora	varchar	8	NULL	NULL	NO	('')	14
        u_clcontact	usrinis	varchar	30	NULL	NULL	NO	('')	15
        u_clcontact	usrdata	datetime	NULL	NULL	NULL	NO	(getdate())	16
        u_clcontact	usrhora	varchar	8	NULL	NULL	NO	('')	17
        u_clcontact	marcada	bit	NULL	NULL	NULL	NO	((0))	18
        u_clcontact	estab	numeric	NULL	3	0	NO	((0))	19
        u_clcontact	obs	text	2147483647	NULL	NULL	NO	('')	20
        u_clcontact	departamento	varchar	100	NULL	NULL	NO	('')	21

    ###Mapeamento PHC → API
    Contas: POST ImportAccounts (lista "accounts"). Origem: CL + CL2.
        code            ← cl.no + '-' + cl.estab, como texto sem casas decimais (ex.: sede "13444-0", estabelecimento "13444-1").
                   Todas as fichas da CL são enviadas, cada estabelecimento é uma conta própria no CRM.
        name            ← cl.nome
        address         ← cl.morada
        postalCode      ← cl.codpost
        city            ← cl.local
        country         ← cl2.descpais
        vatNumber       ← cl.ncont
        phone           ← cl.telefone
        mobilePhone     ← cl.tlmvl
        email           ← cl.email
        fax             ← cl.fax
        accountType     ← fixo, conforme a origem: CL → "CLI" (no futuro FL → "FOR", PE → "COL")
        obsCreation, obsExclusion, currentBalance, earliestDueDate ← fora do âmbito nesta fase: NÃO são enviados no JSON
            (para não apagar no CRM valores que lá existam). Se a API os exigir, envia-os vazios e regista-o na documentação.

    Contactos: POST ImportContacts (lista "contacts"). Origem: U_CLCONTACT.
        accountCode     ← cl.no + '-' + cl.estab da ficha a que o contacto pertence (join por clstamp), igual ao "code" da conta
        contactCode     ← u_clcontactstamp (trim). É único e nunca muda (é a chave do upsert no CRM)
        name            ← u_clcontact.nome
        title           ← u_clcontact.funcao
        mattersType     ← u_clcontact.tipo
        phoneOffice     ← u_clcontact.telefone
        phoneMobile     ← u_clcontact.tlmvl
        obs             ← u_clcontact.obs (text → varchar(max))
        email           ← u_clcontact.email
        department      ← u_clcontact.departamento
        Não enviados (a API não tem campo): contacto, fax, estab, no.
        O contacto fica ligado à conta da ficha (sede ou estabelecimento) indicada pelo seu clstamp.
        Confirma que u_clcontact.estab coincide com o cl.estab dessa ficha. Se houver casos diferentes, PARA e pergunta.

    Regras gerais:
        - Todos os campos de texto levam trim.
        - Telefones vão como estão no PHC (só trim). Não se faz limpeza de formato sem confirmação da Orcinus.
        - Tamanhos: se o valor no PHC for maior do que o limite do campo no CRM, é truncado ao limite do CRM.
          A truncagem é feita no serviço (não nas views), com base nos limites definidos na configuração,
          e cada truncagem fica no log como aviso (entidade, stamp e campo, sem o valor completo).
          A documentação da API não indica limites: um limite vazio na configuração quer dizer "sem truncagem".

    ###API do CRM (detalhe nos anexos 1 e 2)
        - Contas:     POST http://192.168.11.4/carneslandeiro/index.php?entryPoint=ImportAccounts
        - Contactos:  POST http://192.168.11.4/carneslandeiro/index.php?entryPoint=ImportContacts
        - Cabeçalhos: Content-Type: application/json | Authorization: Bearer <token>
        - Token: está no anexo 1. NUNCA no código, no repositório nem nos logs. O PDF escreve "Bearer:" com dois pontos.
          Usa o formato standard "Bearer <token>" e, se o servidor rejeitar, testa a variante e documenta qual funciona.
        - Os dois endpoints fazem upsert: se o "code"/"contactCode" já existir, atualizam em vez de criar.
        - Aceitam vários registos por pedido (lotes).
        - Respostas: 200 (tudo gravado) | 206 (parte falhou: lista por "row" com "action" e "id") | 422 (pedido inválido).
          Associa o resultado de cada registo pelo índice "row" (e confirma-o pelo code). Um registo que não venha
          na resposta como gravado fica em "erro". Guarda o "id" devolvido pelo CRM.
        - A API NÃO tem endpoint para eliminar nem inativar (ver Eliminações).
        - O endereço é interno (192.168.11.4) e em HTTP. O servidor PHC tem de chegar a este IP (rede do cliente ou VPN).
          Confirma a conectividade logo no início.
        - Se alguma coisa na API não estiver clara, PARA e pergunta. Não inventes contratos de API.

    ###Desenho do circuito
    PHC (gravação da ficha) → trigger → u_crmfila (fila) → serviço (de X em X minutos) → view da origem → JSON → API Somnia → atualização da fila + log

    Princípio genérico (preparado para fornecedores e colaboradores):
        - Cada origem tem uma view com as colunas JÁ com os nomes da API (contas e contactos têm o mesmo formato, venham de onde vierem).
        - O serviço não conhece as tabelas do PHC: lê a configuração de origens (origem → entidade → view → endpoint → accountType)
          e processa todas da mesma forma.
        - Para acrescentar fornecedores no futuro: uma view nova, um trigger novo e uma entrada nova na configuração. Sem alterar o código do serviço.
        - Escreve na documentação um guia passo a passo "Como adicionar uma nova origem", usando FL como exemplo.

    ###Tabela de fila (u_crmfila), a desenhar por ti. Requisitos mínimos:
        - Criada seguindo a convenção das tabelas de utilizador do PHC (prefixo u_, stamp char(25) como chave,
          campos de auditoria ousr*/usr*, colunas NOT NULL com default '' / 0), igual à U_CLCONTACT.
        - Stamp gerado no trigger de forma única, compatível com o formato PHC (char 25).
        - Campos obrigatórios:
            - origem: tabela de onde veio o registo (ex.: 'CL', 'CL2', 'U_CLCONTACT'; no futuro 'FL', ...). É OBRIGATÓRIO o insert indicar a tabela.
            - entidade: 'CONTA' ou 'CONTACTO'.
            - tipo de conta: 'CLI' / 'FOR' / 'COL'.
            - stamp do registo de origem (para CL2, o stamp do cliente: cl2stamp = clstamp).
            - código ("NO-ESTAB" da conta / contactCode), gravado no momento do insert, para continuar disponível depois de uma eliminação.
            - operação: 'U' (criação/alteração → upsert) ou 'D' (eliminação).
            - estado: 'PENDENTE' / 'A_PROCESSAR' / 'ENVIADO' / 'ERRO' / 'SEM_ENVIO'.
            - número de tentativas (informativo), última mensagem de erro, id devolvido pelo CRM, ação devolvida pelo CRM,
              identificador do lote, data de criação, data de envio.
        - Não guarda o JSON enviado nem dados pessoais do registo (RGPD). Só identificadores, estados e mensagens.
        - Sem duplicados: se já existir um registo PENDENTE para a mesma entidade + stamp, não se cria outro.
          Uma eliminação substitui uma alteração pendente do mesmo stamp.
        - Concorrência: antes de chamar a API, o serviço passa o lote a A_PROCESSAR. Assim uma alteração feita durante o envio
          cria um novo PENDENTE e não se perde. No arranque, os registos que ficaram em A_PROCESSAR (por exemplo, depois de uma
          queda do serviço) voltam a PENDENTE.
        - Índices para a leitura do serviço (estado + data) e para a deduplicação (entidade + stamp + estado).
        - A fila nunca é limpa automaticamente. Guarda o histórico completo.

    ###Triggers
        - CL e U_CLCONTACT: INSERT, UPDATE e DELETE. CL2: só INSERT e UPDATE.
        - Comportamento do PHC a ter em conta: ao gravar uma ficha, o PHC faz UPDATE de todas as colunas, e há processos que
          atualizam a CL sem a ficha ser aberta (ex.: saldos ao lançar documentos). Por isso, NÃO uses UPDATE(coluna):
          compara inserted com deleted e só regista na fila se mudou algum campo integrado.
        - O trigger da CL2 regista a entidade CONTA (stamp = cl2stamp = clstamp) com origem 'CL2'. A deduplicação evita
          o envio a dobrar quando o PHC grava a CL e a CL2 na mesma operação.
        - CL: todas as fichas (sede e estabelecimentos) geram conta, com code "NO-ESTAB".
        - Tratam várias linhas de uma vez (inserted/deleted como conjuntos, nunca variáveis escalares).
        - Leves: só escrevem na fila, sem chamadas externas nem lógica pesada. SET NOCOUNT ON.
        - Não podem impedir a gravação da ficha no PHC em casos normais. Testa a gravação pelo próprio PHC, não só por SQL.

    ###Eliminações
        - A API não permite eliminar nem inativar. O trigger de DELETE regista a operação 'D' na fila (com o código).
        - O serviço NÃO chama a API para operações 'D': marca-as como SEM_ENVIO e regista-as no log, para tratamento manual no CRM.
        - Fica preparado para quando a Orcinus disponibilizar um endpoint: basta implementar o envio da operação 'D'.

    ###Views
        - Uma view por origem e entidade (ex.: u_v_crm_conta_cl, u_v_crm_contacto_cl), com as colunas com os nomes exatos da API
          mais o stamp de ligação à fila.
        - A view de contas faz LEFT JOIN à CL2 (cl2.cl2stamp = cl.clstamp) e usa ISNULL(descpais, '').
        - Convertem obs (text) para varchar(max) e fazem trim.

    ###Serviço
        - .NET 8, Worker Service instalado como Windows Service no servidor PHC.
        - Uma só instância em execução (garantir com sp_getapplock ou equivalente).
        - Configuração em appsettings.json: intervalo de execução (por defeito 5 minutos), tamanho do lote,
          dias de retenção dos ficheiros de log (por defeito 7), limites de tamanho por campo, origens (origem/entidade/view/endpoint/accountType),
          connection string e URL base da API.
        - As credenciais da API e da base de dados NUNCA ficam em texto simples no código nem no repositório (usar DPAPI, variáveis de ambiente ou outro mecanismo justificado).
        - Ordem em cada ciclo: primeiro todas as CONTAS, depois os CONTACTOS. Um contacto cuja conta esteja PENDENTE ou em ERRO na fila espera pelo ciclo seguinte.
        - Envio em lotes (tamanho configurável). O estado é atualizado registo a registo com base na resposta (200/206/422).
        - Sem reprocessamento automático: qualquer falha passa o registo a ERRO, com a mensagem guardada.
          Só volta a ser enviado quando alguém o repõe manualmente a PENDENTE (com o script de reposição).
          Uma falha de rede ou de autenticação (o pedido nem chegou a ser processado) também deixa o lote em ERRO e fica em destaque no log.
        - Trunca os campos que excedam o limite configurado e regista um aviso no log.
        - Log diário em ficheiro: data/hora, origem, entidade, código, stamp, resultado, ação/id do CRM e mensagem de erro.
          Só os ficheiros de log com mais de N dias são apagados (a fila nunca).
        - Não regista o token, a connection string nem dados pessoais completos nos logs.
        - Queries parametrizadas e um utilizador de SQL com permissões mínimas (leitura das views; leitura e atualização da fila).
        - Qualquer dependência NuGet tem de ser justificada.

    ###Carga de dados existentes
        - A Orcinus já fez uma importação inicial de clientes com o "Código PHC". ATENÇÃO: se essa importação usou só o número (ex.: "13444") e nós enviamos "13444-0", o CRM cria uma conta NOVA (duplicado).
          Não faças a importação completa sem a Orcinus confirmar o formato do código usado na importação inicial (pendência 8).
        - Os clientes que já existem não são enviados automaticamente na instalação.
        - Procedimento de carga com dois parâmetros: origem (por agora 'CL') e número (opcional):
            - com um número, coloca na fila esse cliente (sede e todos os estabelecimentos) e os seus contactos (testes 1 a 1, a começar pelo 13444);
            - sem número, coloca todos os clientes e contactos (importação completa, mais tarde).
        - Respeita a deduplicação e a ordem conta → contactos.

    ###Operação
        - Script de reposição: repõe a PENDENTE os registos em ERRO (todos, ou filtrados por origem, entidade, código ou stamp).
        - Queries de acompanhamento: totais por estado e origem, erros recentes, histórico de um cliente.
</Requirements>

<project_structure>
Cria todo o projeto na pasta onde estás a trabalhar (a raiz do projeto). Uma pasta para o serviço e pastas separadas para o resto.
Se a pasta ainda não for um repositório git, faz git init. Não faças push para nenhum remoto.

    / (raiz)
    ├── README.md                       Visão geral, pré-requisitos, como compilar, testar e instalar, e mapa das pastas
    ├── .gitignore
    ├── .editorconfig                   Estilo de código comum (C# e SQL)
    │
    ├── servico/                        Tudo o que é .NET
    │   ├── SigmaCode.Landeiro.CrmSync.sln
    │   ├── Directory.Build.props       Definições comuns: .NET 8, Nullable, TreatWarningsAsErrors, analisadores
    │   ├── src/
    │   │   ├── SigmaCode.Landeiro.CrmSync.Core/            Domínio: estados da fila, regras (ordem, truncagem, interpretação das respostas),
    │   │   │                                               interfaces. Sem dependências de SQL, HTTP nem PHC.
    │   │   ├── SigmaCode.Landeiro.CrmSync.Infrastructure/  Implementações: acesso à fila e às views (SQL), cliente da API Somnia (HTTP),
    │   │   │                                               log em ficheiro, proteção de credenciais.
    │   │   └── SigmaCode.Landeiro.CrmSync.Worker/          Host do Windows Service: Program.cs, Worker, injeção de dependências,
    │   │                                                   appsettings.json (SEM segredos) e appsettings.Example.json.
    │   └── tests/
    │       ├── SigmaCode.Landeiro.CrmSync.Core.Tests/            Testes unitários
    │       └── SigmaCode.Landeiro.CrmSync.Infrastructure.Tests/  Testes de integração (API simulada, base de dados de teste)
    │
    ├── base-dados/                     Tudo o que é SQL, com scripts numerados pela ordem de execução
    │   ├── 01_tabelas/
    │   ├── 02_views/
    │   ├── 03_procedimentos/           Carga, reposição, consultas
    │   ├── 04_triggers/
    │   ├── 05_permissoes/              Utilizador SQL do serviço com permissões mínimas
    │   ├── 99_rollback/
    │   ├── testes/                     Scripts de teste SQL com asserts
    │   └── instalar.sql                Executa os scripts pela ordem certa
    │
    ├── deploy/                         PowerShell: publicar, instalar, desinstalar e reiniciar o Windows Service,
    │                                   e guardar as credenciais protegidas (DPAPI)
    │
    ├── docs/                           A documentação pedida nos entregáveis, um ficheiro .md por tema
    │
    └── anexos/                         A documentação que te envio em anexo. FICA FORA DO GIT (o PDF da API contém o token).

Regras da estrutura:
    - Dependências só num sentido: Worker → Infrastructure → Core. O Core não referencia nenhum outro projeto.
    - Nada específico de uma tabela PHC fica no código C#: isso vive nas views e na configuração (ver "Princípio genérico").
    - Cada pasta tem um README.md curto que explica o que contém e como se usa.
    - Nomes de pastas, scripts e ficheiros de documentação em português. Código (classes e métodos) em inglês, com comentários em português.

.gitignore: tem de excluir, pelo menos:
    - os resultados de compilação e do IDE: bin/, obj/, .vs/, .vscode/ (exceto as definições partilhadas), *.user, *.suo, publish/, TestResults/, *.trx, coverage*;
    - os logs: logs/, *.log;
    - os segredos: appsettings.*.json locais com credenciais (só o appsettings.Example.json vai para o git), *.secrets.json, *.pfx, *.key, .env;
    - a pasta anexos/.
    Antes do primeiro commit, confirma com git status que nenhum segredo, log ou anexo está a ser incluído.
</project_structure>

<decisions>
Decisões já tomadas (não voltar a perguntar):
- Âmbito: só clientes e os seus contactos nesta fase. O circuito fica genérico para fornecedores (FL) e colaboradores (PE).
- Eliminações: registadas na fila como SEM_ENVIO e no log, porque a API não as suporta.
- Carga inicial: testes 1 a 1 (cliente 13444 primeiro); a importação completa é feita mais tarde, com o mesmo procedimento.
- Retenção: só os ficheiros de log são apagados ao fim de N dias (por defeito 7). A fila guarda tudo.
- Erros: reprocessamento só manual.
- Intervalo de execução: configurável, por defeito 5 minutos.
- code da conta = "NO-ESTAB" (ex.: "13444-0"), para sede e estabelecimentos. contactCode = u_clcontactstamp. accountType = fixo pela origem.
- Campos de saldo, vencimento e observações das contas ficam fora do âmbito nesta fase.
</decisions>

<pending_orcinus>
Questões a confirmar com a Orcinus. Não bloqueiam o desenvolvimento: implementa com as decisões acima e regista na documentação o que ficar por confirmar.
1. Endpoint para inativar/eliminar contas e contactos.
2. O "code" das contas é único por accountType ou global? Se for global, um fornecedor com o mesmo número de um cliente sobrescreve-o.
   Tem de estar resolvido ANTES de integrar os fornecedores.
3. Um campo omitido no JSON mantém o valor no CRM? E um campo enviado vazio, apaga-o?
4. Tamanhos máximos de cada campo e campos obrigatórios. Formato esperado para os telefones.
5. Formato da resposta 206 para os registos que falham (como vêm identificados e com que mensagem).
6. Existe ambiente de testes? Os registos de teste ficam no CRM de produção.
7. Disponibilização em HTTPS (atualmente o token circula em HTTP na rede interna).
8. Formato do "Código PHC" usado na importação inicial das contas. A integração usa "NÚMERO-ESTABELECIMENTO" (ex.: "13444-0").
   Se a importação inicial usou só o número, é preciso converter os códigos no CRM antes da importação completa, para não haver duplicados.

Email para a Orcinus:
    Escreve o email a enviar à Orcinus com estas questões e grava-o em docs/email-orcinus.md. NÃO o envias: eu reviso e envio.
    - Para: João Oliveira <joao.oliveira@orcinus.pt> (responsável do projeto pela Orcinus).
    - Cc: Luis Silva <informatica@landeiro.pt> (responsável do projeto pela Carnes Landeiro).
    - De/assinatura: Flávio Oliveira, SigmaCode (flavio.oliveira@sigmacode.pt).
    - Português de Portugal, tom profissional, cordial e direto. Sem jargão interno da SigmaCode (fila, triggers, stamps):
      escreve do ponto de vista de quem consome a API deles.
    - Estrutura:
        1. Assunto claro, ex.: "Carnes Landeiro – Integração PHC → Somnia CRM: esclarecimentos sobre a API".
        2. Contexto em 2 ou 3 linhas: a SigmaCode está a desenvolver a integração com base na documentação "SomniaCRM API v1"
           (ImportAccounts / ImportContacts), começando pelos clientes e seus contactos, e mais tarde fornecedores e colaboradores.
        3. As questões numeradas, agrupadas por prioridade (primeiro as que bloqueiam o arranque em produção ou a entrada dos fornecedores).
           Para cada uma: a pergunta, porque é importante (o impacto, em uma frase) e, quando fizer sentido, o que vamos assumir se não houver resposta.
        4. Um pedido concreto de próximo passo: resposta por escrito e, se acharem útil, uma chamada curta.
           Indica um prazo de resposta como [data a preencher].
        5. Despedida e assinatura.
    - Não incluas o token, credenciais, IPs internos além do que já está na documentação deles, nem dados de clientes.
    - Inclui uma linha a perguntar se o token atual pode ser trocado antes do arranque em produção, dado que foi partilhado em documento.
    - Mantém o email curto: cabe num ecrã, sem repetir a documentação deles.
</pending_orcinus>

<steps>
1. Analisar os anexos e confirmar na base de dados os nomes das tabelas e campos, incluindo:
   - quantos clientes têm estabelecimentos (estab > 0) e se u_clcontact.estab coincide com o cl.estab da ficha ligada por clstamp;
   - a diferença entre u_clcontact.nome e u_clcontact.contacto (confirmar qual é o nome da pessoa, olhando para dados reais);
   - os triggers que já existem em CL, CL2 e U_CLCONTACT (não os quebrar).
   Apresentar o mapeamento final PHC → API.
   Escrever logo nesta fase o email para a Orcinus (docs/email-orcinus.md), para as respostas chegarem enquanto se desenvolve.
2. Escrever a documentação de arquitetura (circuito, fila, estados e transições) e validá-la comigo antes de implementar.
3. Criar a tabela de fila, as views e os procedimentos (carga, reposição, consultas), com testes SQL.
4. Criar os triggers nas tabelas de origem, com testes SQL.
5. Desenvolver o serviço, com testes unitários e de integração.
6. Testar a conectividade do servidor PHC até 192.168.11.4 e a autenticação na API com o cliente 13444.
7. Testar 1 a 1 com o procedimento de carga (cliente 13444 primeiro): criar, alterar um campo integrado, alterar um campo NÃO integrado
   (não pode gerar fila), mudar só o país (CL2), lançar um documento ao cliente (o saldo muda e não pode gerar fila),
   adicionar e alterar um contacto, enviar um campo acima do limite (confirmar truncagem e aviso), eliminar um contacto (SEM_ENVIO),
   simular um erro da API (confirmar ERRO e reposição manual), parar o serviço a meio de um lote (confirmar a recuperação de A_PROCESSAR).
   Confirmar cada resultado no interface do CRM.
8. Instalar como Windows Service e entregar a documentação final.
9. Só depois de validados os testes: importação completa com o procedimento de carga sem número.
</steps>

<tests>
Testes são obrigatórios em tudo, agora e em qualquer alteração futura. Nenhuma entrega sem os testes correspondentes e o resultado da execução.
- SQL (scripts com asserts, executáveis em base de dados de teste e com rollback no fim):
  trigger em insert/update/delete; update sem alterações nos campos integrados não gera fila; alteração de saldo não gera fila;
  várias linhas de uma vez; deduplicação; CL2 gera CONTA; estabelecimento gera conta com code "NO-ESTAB" e os seus contactos ligam-se a ela; views com o formato da API; carga 1 a 1 e total; reposição.
- .NET unitários (xUnit, ou o framework que já exista): mapeamento view → JSON, truncagem, interpretação das respostas 200/206/422,
  ordem conta → contacto, recuperação de A_PROCESSAR, operação 'D' → SEM_ENVIO, limpeza de logs.
- .NET integração: API simulada (HttpMessageHandler falso) com 200, 206, 422, timeout e 401, e base de dados de teste.
- Ponta a ponta: o plano do passo 7, com as evidências (estado da fila, log e o registo no CRM).
</tests>

<constraints>
- Antes de entregar qualquer documento, confirma que não contradiz a secção <decisions>
  (ex.: código NO-ESTAB para sede e estabelecimentos). Se um documento já existente contradisser, corrige-o e diz o que mudou.
- A validação da arquitetura bloqueia só a fila, as views, os triggers e o serviço. A estrutura de pastas, o git init,
  o .gitignore, o .editorconfig e a solução .NET vazia podem avançar já.
- Cada resposta termina com a secção "O que falta de ti": lista numerada, cada item com o que tens de fazer e o que trava
  se não o fizeres. Sem esta secção a resposta está incompleta.
- Segue as convenções do PHC e o código já existente. Prefere soluções simples.
- Código comentado, com explicações simples do que cada bloco faz.
- Não alteres a estrutura das tabelas nativas do PHC (CL, CL2).
- Todos os scripts SQL são idempotentes (IF NOT EXISTS / CREATE OR ALTER) e têm um script de rollback.
- Se houver ambiguidade, pergunta antes de implementar.
</constraints>

<deliverables>
Tudo dentro da estrutura definida em <project_structure>:
- Repositório git na raiz do projeto, com .gitignore, .editorconfig e README.md.
- base-dados/: tabela de fila, índices, views, triggers, procedimentos (carga, reposição, consultas), permissões, testes, rollback e instalar.sql.
- servico/: solução .NET (Core, Infrastructure, Worker) com testes unitários e de integração.
- deploy/: scripts de publicação e instalação do Windows Service e de proteção das credenciais.
- docs/:
    - Arquitetura: diagrama do circuito (Mermaid), componentes, estados da fila e transições.
    - Dicionário de dados da fila e das views.
    - Mapeamento PHC → API (campo a campo, com tamanhos e regras).
    - Manual de instalação: Windows Service, configuração, proteção das credenciais, permissões SQL, conectividade.
    - Manual de operação: consultar a fila, repor erros, fazer cargas, ler os logs, eliminações SEM_ENVIO,
      e verificação dos triggers depois de cada atualização do PHC.
    - Guia "Como adicionar uma nova origem" (exemplo FL).
    - Plano de testes e resultados.
    - Pendências com a Orcinus e o seu estado.
    - Email para a Orcinus (docs/email-orcinus.md), pronto a rever e enviar.
</deliverables>

<output_format>
Responde sempre nesta estrutura: ANÁLISE, PLANO, IMPLEMENTAÇÃO, REVISÃO, TESTES, RISCOS.
</output_format>