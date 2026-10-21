-- PASSO 1: instala vistas, procedimentos e permissoes na LAND2 (base REAL). NAO instala triggers.
-- Idempotente: pode repetir-se. Antes: backup e confirmar que a tabela u_crmfila existe.
USE LAND2;
GO
IF DB_NAME() <> N'LAND2' THROW 50000, N'Base errada: este ficheiro e so para a LAND2.', 1;
GO
IF OBJECT_ID(N'dbo.u_crmfila', N'U') IS NULL THROW 50001, N'A tabela u_crmfila nao existe na LAND2: criar primeiro no PHC.', 1;
GO

-- ===== 01_tabelas/01_verificar_u_crmfila.sql =====
-- =============================================================================
-- Verifica que a tabela de utilizador u_crmfila existe e tem os campos esperados.
-- A TABELA É CRIADA PELO PHC (tabelas de utilizador), NUNCA POR SQL: este script só lê e
-- pára a instalação, com a lista do que falta ou está errado, se algo não bater certo.
-- Não altera nada.
-- =============================================================================
SET NOCOUNT ON;
GO
IF OBJECT_ID(N'dbo.u_crmfila', N'U') IS NULL
    THROW 50020, N'A tabela u_crmfila não existe. Cria-a no PHC (tabelas de utilizador) antes de instalar. Campos: docs/dicionario-de-dados.md.', 1;
GO
DECLARE @esperado TABLE (campo sysname, familia varchar(10), tam int);
-- familia: S = texto (char/varchar com tamanho >= tam, ou varchar(max)); M = texto longo (text ou varchar(max)); N = numérico; D = datetime
INSERT @esperado VALUES
 ('u_crmfilastamp','S',25), ('origem','S',30), ('entidade','S',10), ('tipoconta','S',3), ('stamporigem','S',25),
 ('codigo','S',60), ('operacao','S',1), ('estado','S',15), ('tentativas','N',0), ('ultimamensagem','M',0),
 ('idcrm','S',60), ('acaocrm','S',30), ('datacriacao','D',0), ('dataenvio','D',0),
 ('ousrinis','S',30), ('ousrdata','D',0), ('ousrhora','S',8), ('usrinis','S',30), ('usrdata','D',0), ('usrhora','S',8), ('marcada','B',0);

DECLARE @problemas TABLE (problema nvarchar(300));
INSERT @problemas
SELECT CONCAT(N'Falta o campo ', e.campo)
  FROM @esperado e
 WHERE NOT EXISTS (SELECT 1 FROM sys.columns c WHERE c.object_id = OBJECT_ID(N'dbo.u_crmfila') AND c.name = e.campo);

INSERT @problemas
SELECT CONCAT(N'Campo ', e.campo, N': tipo ', t.name, N'(', c.max_length, N') não serve')
  FROM @esperado e
  JOIN sys.columns c ON c.object_id = OBJECT_ID(N'dbo.u_crmfila') AND c.name = e.campo
  JOIN sys.types t ON t.user_type_id = c.user_type_id
 WHERE NOT (
        (e.familia = 'S' AND t.name IN ('char','varchar') AND (c.max_length = -1 OR c.max_length >= e.tam))
     OR (e.familia = 'M' AND (t.name = 'text' OR (t.name = 'varchar' AND (c.max_length = -1 OR c.max_length >= 500))))
     OR (e.familia = 'N' AND t.name IN ('numeric','decimal','int','bigint'))
     OR (e.familia = 'D' AND t.name IN ('datetime','datetime2','smalldatetime'))
     OR (e.familia = 'B' AND t.name = 'bit'));

INSERT @problemas
SELECT CONCAT(N'Campo ', e.campo, N' deve ser NOT NULL')
  FROM @esperado e JOIN sys.columns c ON c.object_id = OBJECT_ID(N'dbo.u_crmfila') AND c.name = e.campo
 WHERE c.is_nullable = 1;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.u_crmfila') AND is_primary_key = 1)
    INSERT @problemas VALUES (N'Falta a chave primária em u_crmfilastamp');

IF EXISTS (SELECT 1 FROM @problemas)
BEGIN
    SELECT problema FROM @problemas;
    THROW 50021, N'A tabela u_crmfila (criada no PHC) não tem a estrutura esperada. Ver a lista acima e docs/dicionario-de-dados.md.', 1;
END
PRINT N'u_crmfila: estrutura OK.';
GO
-- Índices: o PHC não os cria em tabelas de utilizador. O serviço funciona sem eles (a fila é pequena).
-- Só se a fila crescer muito (centenas de milhares de linhas) vale a pena criar, por SQL, com autorização:
--   (estado, datacriacao)  |  (entidade, stamporigem, estado)  |  (entidade, codigo)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.u_crmfila') AND name LIKE N'in[_]u[_]crmfila[_]%')
    PRINT N'INFO: u_crmfila sem índices além da chave (esperado: o PHC não os cria).';
GO

GO

-- ===== 01_tabelas/02_tipo_evento.sql =====
-- =============================================================================
-- Tipo de tabela usado pelos triggers para entregar eventos ao procedimento
-- up_crm_enfileirar. Um evento = "este registo mudou, põe-no na fila".
-- Idempotente. Atenção: um tipo não pode ser alterado; só apagado e recriado
-- (apagar primeiro os procedimentos que o usam: ver 99_rollback).
-- =============================================================================
SET NOCOUNT ON;
GO
IF TYPE_ID(N'dbo.u_crm_evento_tt') IS NULL
    CREATE TYPE dbo.u_crm_evento_tt AS TABLE
    (
        origem      varchar(30) NOT NULL,   -- tabela de origem (CL, CL2, U_CLCONTACT, ...)
        entidade    varchar(10) NOT NULL,   -- CONTA | CONTACTO
        tipoconta   char(3)     NOT NULL,   -- CLI | FOR | COL
        stamporigem char(25)    NOT NULL,   -- stamp do registo de origem
        codigo      varchar(60) NOT NULL,   -- NO-ESTAB / contactCode
        operacao    char(1)     NOT NULL    -- U | D
    );
GO

GO

-- ===== 01_tabelas/03_sequencia.sql =====
-- =============================================================================
-- Sequência usada para gerar o stamp da fila (unicidade sem colisões). Objeto SQL, não do PHC.
-- Idempotente: só cria se ainda não existir.
-- =============================================================================
SET NOCOUNT ON;
GO
IF OBJECT_ID(N'dbo.u_crmfila_seq', N'SO') IS NULL
    CREATE SEQUENCE dbo.u_crmfila_seq AS bigint START WITH 1 INCREMENT BY 1 CACHE 50;
GO

GO

-- ===== 02_views/01_u_v_crm_conta_cl.sql =====
-- =============================================================================
-- u_v_crm_conta_cl: contas (clientes) no formato da API Somnia (ImportAccounts).
--
-- Colunas = nomes exatos da API + "stamp" (ligação à fila: u_crmfila.stamporigem).
-- Todas as colunas são de texto, já com trim. A truncagem NÃO é feita aqui:
-- é feita no serviço, com base nos limites da configuração.
--   code        = cl.no + '-' + cl.estab (sede = "13444-0", estabelecimento = "13444-1")
--   country     = cl2.descpais (LEFT JOIN: cliente sem CL2 fica com país vazio)
--   status      = "Ativo" ou "Inativo" (cl.inactivo). O CRM mantém o estado se o campo vier vazio.
--   accountType = fixo "CLI" (FL -> "FOR", PE -> "COL" nas views futuras)
-- Fora do âmbito (não enviados): obsCreation, obsExclusion, currentBalance, earliestDueDate.
-- =============================================================================
CREATE OR ALTER VIEW dbo.u_v_crm_conta_cl
AS
SELECT
    RTRIM(c.clstamp)                                              AS stamp,
    LTRIM(RTRIM(CONVERT(varchar(20), c.no))) + '-'
        + LTRIM(RTRIM(CONVERT(varchar(10), c.estab)))             AS code,
    LTRIM(RTRIM(c.nome))                                          AS name,
    LTRIM(RTRIM(c.morada))                                        AS address,
    LTRIM(RTRIM(c.codpost))                                       AS postalCode,
    LTRIM(RTRIM(c.local))                                         AS city,
    LTRIM(RTRIM(ISNULL(x.descpais, '')))                          AS country,
    LTRIM(RTRIM(c.ncont))                                         AS vatNumber,
    LTRIM(RTRIM(c.telefone))                                      AS phone,
    LTRIM(RTRIM(c.tlmvl))                                         AS mobilePhone,
    LTRIM(RTRIM(c.email))                                         AS email,
    LTRIM(RTRIM(c.fax))                                           AS fax,
    CONVERT(varchar(3), 'CLI')                                    AS accountType,
    CONVERT(varchar(7), CASE WHEN c.inactivo = 1 THEN 'Inativo' ELSE 'Ativo' END) AS status
FROM dbo.cl AS c WITH (NOLOCK)
LEFT JOIN dbo.cl2 AS x WITH (NOLOCK) ON x.cl2stamp = c.clstamp;
GO

GO

-- ===== 02_views/02_u_v_crm_contacto_cl.sql =====
-- =============================================================================
-- u_v_crm_contacto_cl: contactos dos clientes no formato da API Somnia (ImportContacts).
--
-- Colunas = nomes exatos da API + duas colunas de ligação:
--   stamp        = u_clcontactstamp (liga à fila: u_crmfila.stamporigem)
--   accountStamp = clstamp da ficha da conta (o serviço usa-o para esperar pela conta
--                  quando esta está PENDENTE ou em ERRO na fila)
--   accountCode  = code da conta, igual ao da view u_v_crm_conta_cl (NO-ESTAB da ficha
--                  ligada por clstamp; o "estab" do próprio contacto é ignorado)
--   contactCode  = u_clcontactstamp (único e nunca muda: chave do upsert no CRM)
--   status       = "Ativo"/"Inativo" da CONTA a que o contacto pertence (cl.inactivo): o contacto não tem estado próprio.
--   name         = u_clcontact.contacto se for um nome (nos contactos criados no ecrã do PHC o nome da pessoa
--                  fica em "contacto" e "nome" fica vazio); senão u_clcontact.nome (nos contactos importados é a
--                  empresa); senão o que houver em "contacto". Se tudo estiver vazio, o serviço envia "Sem nome".
-- Não enviados (a API não tem campo): fax, estab, no.
-- INNER JOIN com CL: um contacto sem ficha (órfão) não aparece na view.
-- obs: text -> varchar(max), com trim.
-- =============================================================================
CREATE OR ALTER VIEW dbo.u_v_crm_contacto_cl
AS
SELECT
    RTRIM(k.u_clcontactstamp)                                     AS stamp,
    RTRIM(c.clstamp)                                              AS accountStamp,
    LTRIM(RTRIM(CONVERT(varchar(20), c.no))) + '-'
        + LTRIM(RTRIM(CONVERT(varchar(10), c.estab)))             AS accountCode,
    RTRIM(k.u_clcontactstamp)                                     AS contactCode,
    CASE
        -- "contacto" é o nome da pessoa quando é texto (não um email nem só dígitos/telefone)
        WHEN LTRIM(RTRIM(k.contacto)) <> '' AND k.contacto NOT LIKE '%@%' AND k.contacto LIKE '%[^0-9 +().-]%'
            THEN LTRIM(RTRIM(k.contacto))
        WHEN LTRIM(RTRIM(k.nome)) <> '' THEN LTRIM(RTRIM(k.nome))
        ELSE LTRIM(RTRIM(k.contacto))
    END                                                           AS name,
    LTRIM(RTRIM(k.funcao))                                        AS title,
    LTRIM(RTRIM(k.tipo))                                          AS mattersType,
    LTRIM(RTRIM(k.telefone))                                      AS phoneOffice,
    LTRIM(RTRIM(k.tlmvl))                                         AS phoneMobile,
    LTRIM(RTRIM(CONVERT(varchar(max), k.obs)))                    AS obs,
    LTRIM(RTRIM(k.email))                                         AS email,
    LTRIM(RTRIM(k.departamento))                                  AS department,
    CONVERT(varchar(7), CASE WHEN c.inactivo = 1 THEN 'Inativo' ELSE 'Ativo' END) AS status
FROM dbo.u_clcontact AS k WITH (NOLOCK)
INNER JOIN dbo.cl AS c WITH (NOLOCK) ON c.clstamp = k.clstamp;
GO

GO

-- ===== 03_procedimentos/01_up_crm_enfileirar.sql =====
-- =============================================================================
-- up_crm_enfileirar: único ponto de escrita na fila (usado pelos triggers e pela carga).
--
-- Recebe eventos (origem, entidade, tipo de conta, stamp, código, operação) e aplica as regras:
--   * um só evento por entidade + stamp dentro do mesmo pedido (D vence U);
--   * se já existe PENDENTE para a mesma entidade + stamp, não cria outro:
--       - D substitui um U pendente;
--       - U sobre um D pendente repõe-no como U (o registo voltou a existir);
--       - U sobre U pendente só atualiza o código;
--   * só ativos: contas inativas nunca enviadas (e os contactos delas) não entram (ver 1b);
--   * contactos sem email, telefone e telemóvel nunca enviados não entram (ver 1c);
--   * caso contrário cria um novo PENDENTE, com stamp no formato PHC.
-- Stamp: 'CRM' + yymmdd + hhmmss + ',' + 8 dígitos da sequência = 24 caracteres (char 25),
-- igual ao padrão dos stamps existentes (ex.: FIL26091153534,171313351).
-- Não faz chamadas externas. Os estados diferentes de PENDENTE nunca são tocados.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.up_crm_enfileirar
    @ev        dbo.u_crm_evento_tt READONLY,
    @inseridos int = 0 OUTPUT,
    -- 0 = não aplica as regras 1b e 1c (quem chama já as aplicou com os valores do ecrã do PHC,
    -- porque o evento "Ao gravar" corre antes de a base ter os valores novos). Por defeito aplica.
    @filtrarRegras bit = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @agora datetime    = GETDATE();
    DECLARE @hora  varchar(8)  = CONVERT(varchar(8), GETDATE(), 108);
    DECLARE @data  char(6)     = CONVERT(char(6), GETDATE(), 12);                       -- yymmdd
    DECLARE @tempo char(6)     = REPLACE(CONVERT(char(8), GETDATE(), 108), ':', '');    -- hhmmss

    -- 1) Um evento por entidade + stamp (a eliminação vence a alteração)
    DECLARE @r TABLE
    (
        origem varchar(30), entidade varchar(10), tipoconta char(3),
        stamporigem char(25), codigo varchar(60), operacao char(1)
    );
    INSERT @r (origem, entidade, tipoconta, stamporigem, codigo, operacao)
    SELECT origem, entidade, tipoconta, stamporigem, codigo, operacao
    FROM (
        SELECT e.origem, e.entidade, e.tipoconta, e.stamporigem, e.codigo, e.operacao,
               ROW_NUMBER() OVER (PARTITION BY e.entidade, e.stamporigem
                                  ORDER BY CASE e.operacao WHEN 'D' THEN 0 ELSE 1 END, e.origem) AS rn
        FROM @ev AS e
    ) AS x
    WHERE x.rn = 1;

    -- 1b) Regra "só ativos": uma conta INATIVA que nunca foi enviada (sem ENVIADO na fila) não entra,
    --     nem os contactos dela. Se for ativada mais tarde, o trigger gera o evento e passa a entrar.
    --     Uma conta inativa que já foi enviada continua a entrar (para o CRM receber o estado "Inativo").
    --     As eliminações (D) não são filtradas.
    IF @filtrarRegras = 1
    BEGIN
        DELETE r
          FROM @r AS r
          JOIN dbo.cl AS c WITH (NOLOCK) ON c.clstamp = r.stamporigem
         WHERE r.entidade = 'CONTA' AND r.operacao = 'U' AND c.inactivo = 1
           AND NOT EXISTS (SELECT 1 FROM dbo.u_crmfila AS f WITH (NOLOCK)
                            WHERE f.entidade = 'CONTA' AND f.estado = 'ENVIADO' AND f.stamporigem = c.clstamp);

        DELETE r
          FROM @r AS r
          JOIN dbo.u_clcontact AS k WITH (NOLOCK) ON k.u_clcontactstamp = r.stamporigem
          JOIN dbo.cl AS c WITH (NOLOCK) ON c.clstamp = k.clstamp
         WHERE r.entidade = 'CONTACTO' AND r.operacao = 'U' AND c.inactivo = 1
           AND NOT EXISTS (SELECT 1 FROM dbo.u_crmfila AS f WITH (NOLOCK)
                            WHERE f.entidade = 'CONTA' AND f.estado = 'ENVIADO' AND f.stamporigem = c.clstamp);
    END

    -- 1c) Regra "contacto com meio de contacto": um contacto sem email, sem telefone e sem telemóvel
    --     (campos vazios ou só espaços) que nunca foi enviado não entra. Se mais tarde ganhar um destes
    --     campos, o trigger gera o evento e passa a entrar. Um contacto já enviado continua a entrar
    --     (para o CRM receber a alteração). As eliminações (D) não são filtradas.
    IF @filtrarRegras = 1
        DELETE r
          FROM @r AS r
          JOIN dbo.u_clcontact AS k WITH (NOLOCK) ON k.u_clcontactstamp = r.stamporigem
         WHERE r.entidade = 'CONTACTO' AND r.operacao = 'U'
           AND ISNULL(LTRIM(RTRIM(k.email)), '') = '' AND ISNULL(LTRIM(RTRIM(k.telefone)), '') = '' AND ISNULL(LTRIM(RTRIM(k.tlmvl)), '') = ''
           AND NOT EXISTS (SELECT 1 FROM dbo.u_crmfila AS f WITH (NOLOCK)
                            WHERE f.entidade = 'CONTACTO' AND f.estado = 'ENVIADO' AND f.stamporigem = k.u_clcontactstamp);

    -- 2) Já existe PENDENTE do mesmo registo: atualiza-o em vez de criar outro
    UPDATE f
       SET f.origem  = CASE WHEN f.operacao <> r.operacao THEN r.origem ELSE f.origem END,
           f.operacao = r.operacao,
           f.codigo   = r.codigo,
           f.usrdata  = @agora,
           f.usrhora  = @hora
      FROM dbo.u_crmfila AS f
      JOIN @r AS r ON r.entidade = f.entidade AND r.stamporigem = f.stamporigem
     WHERE f.estado = 'PENDENTE'
       AND (f.operacao <> r.operacao OR f.codigo <> r.codigo);

    -- 3) Os que já têm PENDENTE ficam tratados: só se criam os restantes
    DELETE r
      FROM @r AS r
     WHERE EXISTS (SELECT 1 FROM dbo.u_crmfila AS f WITH (NOLOCK)
                    WHERE f.estado = 'PENDENTE'
                      AND f.entidade = r.entidade
                      AND f.stamporigem = r.stamporigem);

    -- 4) Novos registos PENDENTE
    INSERT dbo.u_crmfila
        (u_crmfilastamp, origem, entidade, tipoconta, stamporigem, codigo, operacao, estado,
         datacriacao, ousrinis, ousrdata, ousrhora, usrinis, usrdata, usrhora)
    SELECT 'CRM' + @data + @tempo + ',' + RIGHT('00000000' + CONVERT(varchar(18), NEXT VALUE FOR dbo.u_crmfila_seq), 8),
           r.origem, r.entidade, r.tipoconta, r.stamporigem, r.codigo, r.operacao, 'PENDENTE',
           @agora, 'CRMSYNC', @agora, @hora, 'CRMSYNC', @agora, @hora
      FROM @r AS r;

    SET @inseridos = @@ROWCOUNT;
END
GO

GO

-- ===== 03_procedimentos/02_up_crm_carga.sql =====
-- =============================================================================
-- up_crm_carga: coloca na fila os dados já existentes no PHC.
--
--   EXEC dbo.up_crm_carga @origem = 'CL', @no = 13444;   -- um cliente (sede + estabelecimentos) e os seus contactos
--   EXEC dbo.up_crm_carga @origem = 'CL';                -- todos os clientes e contactos (importação completa)
--
-- Respeita a deduplicação (usa up_crm_enfileirar) e a ordem conta -> contactos.
-- Não envia nada: só enfileira. Contactos sem ficha (órfãos) não são enfileirados.
-- Para acrescentar uma origem nova (ex.: FL) acrescenta-se um bloco IF @origem = '...'.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.up_crm_carga
    @origem varchar(30),
    @no     numeric(10, 0) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @origem IS NULL OR @origem <> 'CL'
    BEGIN
        RAISERROR(N'up_crm_carga: origem não suportada (%s). Origens disponíveis: CL.', 16, 1, @origem);
        RETURN 1;
    END

    DECLARE @ev dbo.u_crm_evento_tt;
    DECLARE @contas int = 0, @contactos int = 0;

    -- 1.º as contas (sede e estabelecimentos do cliente)
    INSERT @ev (origem, entidade, tipoconta, stamporigem, codigo, operacao)
    SELECT 'CL', 'CONTA', 'CLI', c.clstamp,
           LTRIM(RTRIM(CONVERT(varchar(20), c.no))) + '-' + LTRIM(RTRIM(CONVERT(varchar(10), c.estab))), 'U'
      FROM dbo.cl AS c WITH (NOLOCK)
     WHERE (@no IS NULL OR c.no = @no);
    EXEC dbo.up_crm_enfileirar @ev, @contas OUTPUT;

    -- 2.º os contactos, ligados à ficha pelo clstamp
    DELETE @ev;
    INSERT @ev (origem, entidade, tipoconta, stamporigem, codigo, operacao)
    SELECT 'U_CLCONTACT', 'CONTACTO', 'CLI', k.u_clcontactstamp, RTRIM(k.u_clcontactstamp), 'U'
      FROM dbo.u_clcontact AS k WITH (NOLOCK)
      JOIN dbo.cl AS c WITH (NOLOCK) ON c.clstamp = k.clstamp
     WHERE (@no IS NULL OR c.no = @no);
    EXEC dbo.up_crm_enfileirar @ev, @contactos OUTPUT;

    SELECT @contas AS contas_enfileiradas, @contactos AS contactos_enfileirados;
    RETURN 0;
END
GO

GO

-- ===== 03_procedimentos/03_up_crm_repor.sql =====
-- =============================================================================
-- up_crm_repor: repõe a PENDENTE os registos em ERRO (reposição manual).
--
--   EXEC dbo.up_crm_repor;                                   -- todos os ERRO
--   EXEC dbo.up_crm_repor @origem = 'CL';                    -- filtrar por origem
--   EXEC dbo.up_crm_repor @entidade = 'CONTACTO';            -- filtrar por entidade
--   EXEC dbo.up_crm_repor @codigo = '13444-0';               -- filtrar por código
--   EXEC dbo.up_crm_repor @stamp = '<stamp>';                -- stamp do registo de origem ou da fila
--
-- Regras:
--   * só mexe em registos ERRO; nunca em ENVIADO / SEM_ENVIO;
--   * se o mesmo registo tiver vários ERRO, repõe só o mais recente;
--   * se já existir um PENDENTE para o mesmo registo, não repõe (evita duplicados) e conta-o como ignorado;
--   * a mensagem de erro anterior fica registada no campo ultimamensagem.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.up_crm_repor
    @origem   varchar(30) = NULL,
    @entidade varchar(10) = NULL,
    @codigo   varchar(60) = NULL,
    @stamp    varchar(25) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @agora datetime = GETDATE();
    DECLARE @hora varchar(8) = CONVERT(varchar(8), GETDATE(), 108);
    DECLARE @stampLimpo varchar(25) = LTRIM(RTRIM(@stamp));

    -- Candidatos: o ERRO mais recente de cada registo que cumpra os filtros
    DECLARE @alvo TABLE (u_crmfilastamp char(25) PRIMARY KEY, entidade varchar(10), stamporigem char(25));
    INSERT @alvo (u_crmfilastamp, entidade, stamporigem)
    SELECT u_crmfilastamp, entidade, stamporigem
    FROM (
        SELECT f.u_crmfilastamp, f.entidade, f.stamporigem,
               ROW_NUMBER() OVER (PARTITION BY f.entidade, f.stamporigem
                                  ORDER BY f.datacriacao DESC, f.u_crmfilastamp DESC) AS rn
          FROM dbo.u_crmfila AS f WITH (NOLOCK)
         WHERE f.estado = 'ERRO'
           AND (@origem   IS NULL OR f.origem   = @origem)
           AND (@entidade IS NULL OR f.entidade = @entidade)
           AND (@codigo   IS NULL OR f.codigo   = @codigo)
           AND (@stampLimpo IS NULL OR f.stamporigem = @stampLimpo OR f.u_crmfilastamp = @stampLimpo)
    ) AS x
    WHERE x.rn = 1;

    DECLARE @candidatos int = (SELECT COUNT(*) FROM @alvo);

    UPDATE f
       SET f.estado = 'PENDENTE',
           f.ultimamensagem = LEFT('Reposto manualmente. Erro anterior: ' + CONVERT(varchar(max), f.ultimamensagem), 500),
           f.usrdata = @agora,
           f.usrhora = @hora
      FROM dbo.u_crmfila AS f
      JOIN @alvo AS a ON a.u_crmfilastamp = f.u_crmfilastamp
     WHERE NOT EXISTS (SELECT 1 FROM dbo.u_crmfila AS p WITH (NOLOCK)
                        WHERE p.estado = 'PENDENTE'
                          AND p.entidade = a.entidade
                          AND p.stamporigem = a.stamporigem);

    DECLARE @repostos int = @@ROWCOUNT;
    SELECT @repostos AS repostos, @candidatos - @repostos AS ignorados_ja_pendentes;
END
GO

GO

-- ===== 03_procedimentos/04_up_crm_consultas.sql =====
-- =============================================================================
-- Consultas de acompanhamento da fila (só leitura).
-- =============================================================================

-- Totais por estado e origem
CREATE OR ALTER PROCEDURE dbo.up_crm_consulta_totais
AS
BEGIN
    SET NOCOUNT ON;
    SELECT origem, entidade, estado, COUNT(*) AS total, MIN(datacriacao) AS mais_antigo, MAX(datacriacao) AS mais_recente
      FROM dbo.u_crmfila WITH (NOLOCK)
     GROUP BY origem, entidade, estado
     ORDER BY origem, entidade, estado;
END
GO

-- Erros recentes (por defeito, dos últimos 7 dias)
CREATE OR ALTER PROCEDURE dbo.up_crm_consulta_erros
    @dias int = 7
AS
BEGIN
    SET NOCOUNT ON;
    SELECT u_crmfilastamp, origem, entidade, codigo, stamporigem, tentativas, ultimamensagem, datacriacao, dataenvio
      FROM dbo.u_crmfila WITH (NOLOCK)
     WHERE estado = 'ERRO'
       AND datacriacao >= DATEADD(DAY, -@dias, GETDATE())
     ORDER BY datacriacao DESC;
END
GO

-- Histórico de um cliente: as suas contas (sede e estabelecimentos) e os seus contactos
CREATE OR ALTER PROCEDURE dbo.up_crm_consulta_historico
    @no numeric(10, 0)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @prefixo varchar(30) = LTRIM(RTRIM(CONVERT(varchar(20), @no))) + '-%';

    SELECT f.datacriacao, f.entidade, f.origem, f.codigo, f.operacao, f.estado, f.tentativas,
           f.acaocrm, f.idcrm, f.dataenvio, f.ultimamensagem, f.u_crmfilastamp
      FROM dbo.u_crmfila AS f WITH (NOLOCK)
     WHERE (f.entidade = 'CONTA' AND f.codigo LIKE @prefixo)
        OR (f.entidade = 'CONTACTO'
            AND f.stamporigem IN (SELECT k.u_clcontactstamp
                                    FROM dbo.u_clcontact AS k WITH (NOLOCK)
                                    JOIN dbo.cl AS c WITH (NOLOCK) ON c.clstamp = k.clstamp
                                   WHERE c.no = @no))
     ORDER BY f.datacriacao, f.u_crmfilastamp;
END
GO

GO

-- ===== 03_procedimentos/05_sc_CrmEnfileirarEvento.sql =====
-- =============================================================================
-- sc_CrmEnfileirarEvento: ponto de entrada dos eventos "Ao gravar" / "Ao apagar" do PHC
-- (substitui os triggers tr_crm_cl, tr_crm_cl2 e tr_crm_u_clcontact).
--
-- O evento do PHC corre ANTES de a base ter os valores novos, por isso quem chama passa os valores
-- do ecrã (estado da ficha, se o contacto tem meio de contacto) e este procedimento aplica as
-- regras "só ativos" e "contacto com meio de contacto" com esses valores, e depois chama
-- up_crm_enfileirar sem repetir essas regras (@filtrarRegras = 0).
--
-- Parâmetros:
--   @origem     'CL' (ficha, inclui a CL2: o país vem da mesma ficha) ou 'U_CLCONTACT' (contacto)
--   @stamp      clstamp (CL) ou u_clcontactstamp (contacto)
--   @operacao   'U' (gravar) ou 'D' (apagar)
--   @no,@estab  só para CL: número e estabelecimento no ecrã (a ficha nova ainda não está na base)
--   @inactivo   só para CL: estado da ficha no ecrã (1 = inativa)
--   @clstamp    só para contactos: stamp da ficha a que pertence
--   @temMeio    só para contactos: 1 se tem email, telefone ou telemóvel preenchido no ecrã
--
-- Nunca devolve erro ao PHC: a gravação da ficha não pode falhar por causa da fila.
-- Só escreve na fila (via up_crm_enfileirar).
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.sc_CrmEnfileirarEvento
    @origem   varchar(30),
    @stamp    char(25),
    @operacao char(1),
    @no       numeric(10,0) = NULL,
    @estab    numeric(10,0) = NULL,
    @inactivo bit           = 0,
    @clstamp  char(25)      = NULL,
    @temMeio  bit           = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    BEGIN TRY
        IF @operacao NOT IN ('U', 'D') OR @stamp IS NULL OR LTRIM(RTRIM(@stamp)) = ''
            RETURN;

        DECLARE @ev dbo.u_crm_evento_tt;

        IF @origem = 'CL'
        BEGIN
            IF @no IS NULL OR @estab IS NULL
                RETURN;

            -- A conta (cada ficha, sede ou estabelecimento, gera uma conta com código NO-ESTAB)
            INSERT @ev (origem, entidade, tipoconta, stamporigem, codigo, operacao)
            VALUES ('CL', 'CONTA', 'CLI', @stamp,
                    LTRIM(RTRIM(CONVERT(varchar(20), @no))) + '-' + LTRIM(RTRIM(CONVERT(varchar(10), @estab))),
                    @operacao);

            -- Ao gravar, reenfileira também os contactos da ficha (o contacto segue o estado da conta)
            IF @operacao = 'U'
                INSERT @ev (origem, entidade, tipoconta, stamporigem, codigo, operacao)
                SELECT 'U_CLCONTACT', 'CONTACTO', 'CLI', k.u_clcontactstamp, RTRIM(k.u_clcontactstamp), 'U'
                  FROM dbo.u_clcontact AS k WITH (NOLOCK)
                 WHERE k.clstamp = @stamp
                   -- Contacto sem email, telefone nem telemóvel e nunca enviado: não entra (como no gatilho antigo)
                   AND (ISNULL(LTRIM(RTRIM(k.email)), '') <> '' OR ISNULL(LTRIM(RTRIM(k.telefone)), '') <> ''
                        OR ISNULL(LTRIM(RTRIM(k.tlmvl)), '') <> ''
                        OR EXISTS (SELECT 1 FROM dbo.u_crmfila AS f WITH (NOLOCK)
                                    WHERE f.entidade = 'CONTACTO' AND f.estado = 'ENVIADO' AND f.stamporigem = k.u_clcontactstamp));

            -- Só ativos: ficha inativa que nunca foi enviada não entra (nem os contactos dela)
            IF @operacao = 'U' AND @inactivo = 1
               AND NOT EXISTS (SELECT 1 FROM dbo.u_crmfila AS f WITH (NOLOCK)
                                WHERE f.entidade = 'CONTA' AND f.estado = 'ENVIADO' AND f.stamporigem = @stamp)
                DELETE @ev WHERE operacao = 'U';
        END
        ELSE IF @origem = 'U_CLCONTACT'
        BEGIN
            INSERT @ev (origem, entidade, tipoconta, stamporigem, codigo, operacao)
            VALUES ('U_CLCONTACT', 'CONTACTO', 'CLI', @stamp, RTRIM(@stamp), @operacao);

            IF @operacao = 'U'
            BEGIN
                -- Contacto sem ficha CL não entra
                IF @clstamp IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.cl WITH (NOLOCK) WHERE clstamp = @clstamp)
                    DELETE @ev;

                -- Sem email, telefone nem telemóvel e nunca enviado: não entra
                IF @temMeio = 0
                   AND NOT EXISTS (SELECT 1 FROM dbo.u_crmfila AS f WITH (NOLOCK)
                                    WHERE f.entidade = 'CONTACTO' AND f.estado = 'ENVIADO' AND f.stamporigem = @stamp)
                    DELETE @ev;

                -- Só ativos: ficha inativa que nunca foi enviada não entra
                IF EXISTS (SELECT 1 FROM dbo.cl AS c WITH (NOLOCK)
                            WHERE c.clstamp = @clstamp AND c.inactivo = 1
                              AND NOT EXISTS (SELECT 1 FROM dbo.u_crmfila AS f WITH (NOLOCK)
                                               WHERE f.entidade = 'CONTA' AND f.estado = 'ENVIADO' AND f.stamporigem = c.clstamp))
                    DELETE @ev;
            END
        END

        IF EXISTS (SELECT 1 FROM @ev)
            EXEC dbo.up_crm_enfileirar @ev, @filtrarRegras = 0;
    END TRY
    BEGIN CATCH
        -- Propositadamente vazio: a gravação no PHC nunca pode falhar por causa da fila.
        -- Se falhar, o registo fica por enviar até à próxima gravação ou até uma reposição.
    END CATCH
END
GO

GO

-- ===== 05_permissoes/01_role_servico.sql =====
-- =============================================================================
-- Permissões mínimas do serviço: um papel na base de dados (crmsync_servico).
--
--   * leitura das views u_v_crm_*;
--   * leitura e atualização da fila (u_crmfila);
--   * execução das consultas de acompanhamento.
-- NÃO tem acesso às tabelas do PHC (cl, cl2, u_clcontact): as views funcionam por
-- cadeia de propriedade (views e tabelas são do mesmo dono, dbo).
--
-- Este script só cria o papel. A criação do LOGIN do servidor, com a sua password, faz-se
-- à parte e nunca fica em ficheiros (ver docs/manual-instalacao.md):
--   CREATE LOGIN crmsync_svc WITH PASSWORD = '<definir>', CHECK_POLICY = ON;
--   CREATE USER  crmsync_svc FOR LOGIN crmsync_svc;
--   ALTER ROLE crmsync_servico ADD MEMBER crmsync_svc;
-- Idempotente.
-- =============================================================================
SET NOCOUNT ON;
GO
IF DATABASE_PRINCIPAL_ID(N'crmsync_servico') IS NULL
    CREATE ROLE crmsync_servico AUTHORIZATION dbo;
GO
GRANT SELECT ON dbo.u_v_crm_conta_cl             TO crmsync_servico;
GRANT SELECT ON dbo.u_v_crm_contacto_cl          TO crmsync_servico;
GRANT SELECT, UPDATE ON dbo.u_crmfila            TO crmsync_servico;
GRANT EXECUTE ON dbo.up_crm_consulta_totais      TO crmsync_servico;
GRANT EXECUTE ON dbo.up_crm_consulta_erros       TO crmsync_servico;
GRANT EXECUTE ON dbo.up_crm_consulta_historico   TO crmsync_servico;
GO

GO
PRINT N'Passo 1 concluido em ' + DB_NAME();
GO
