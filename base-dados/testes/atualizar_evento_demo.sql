-- Atualiza os procedimentos alterados (carga e evento). SO LAND2_DEMO.
USE LAND2_DEMO;
GO
IF DB_NAME() <> N'LAND2_DEMO' THROW 50000, N'Base errada: so LAND2_DEMO.', 1;
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
    SELECT 'U_CLCONTACT', 'CONTACTO', 'CLI', k.u_clcontactstamp,
           RTRIM(k.u_clcontactstamp) + '|' + LTRIM(RTRIM(CONVERT(varchar(20), c.no))) + '-' + LTRIM(RTRIM(CONVERT(varchar(10), c.estab))), 'U'
      FROM dbo.u_clcontact AS k WITH (NOLOCK)
      JOIN dbo.cl AS c WITH (NOLOCK) ON c.clstamp = k.clstamp
     WHERE (@no IS NULL OR c.no = @no);
    EXEC dbo.up_crm_enfileirar @ev, @contactos OUTPUT;

    SELECT @contas AS contas_enfileiradas, @contactos AS contactos_enfileirados;
    RETURN 0;
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
    @stamp    char(25)      = NULL,
    @operacao char(1),
    @no       numeric(10,0) = NULL,
    @estab    numeric(10,0) = NULL,
    @inactivo bit           = 0,
    @clstamp  char(25)      = NULL,
    @temMeio  bit           = 1,
    @contactos varchar(max) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    BEGIN TRY
        IF @operacao NOT IN ('U', 'D') OR (ISNULL(LTRIM(RTRIM(@stamp)), '') = '' AND ISNULL(@contactos, '') = '')
            RETURN;

        DECLARE @ev dbo.u_crm_evento_tt;
        DECLARE @contaCod varchar(40) = NULL;   -- código NO-ESTAB da conta indicada pelo PHC

        -- Lista de contactos a eliminar (stamps separados por vírgula), guardada pelo PHC antes de apagar
        DECLARE @lista TABLE (stamp char(25) PRIMARY KEY);
        IF ISNULL(@contactos, '') <> ''
        BEGIN
            DECLARE @x xml = CAST('<i>' + REPLACE(REPLACE(REPLACE(REPLACE(@contactos, '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), ',', '</i><i>') + '</i>' AS xml);
            INSERT @lista (stamp)
            SELECT DISTINCT LTRIM(RTRIM(t.n.value('.', 'varchar(25)'))) FROM @x.nodes('/i') AS t(n)
             WHERE LTRIM(RTRIM(t.n.value('.', 'varchar(25)'))) <> '';
        END

        IF @origem = 'CL'
        BEGIN
            IF @no IS NULL OR @estab IS NULL OR ISNULL(LTRIM(RTRIM(@stamp)), '') = ''
                RETURN;

            SET @contaCod = LTRIM(RTRIM(CONVERT(varchar(20), @no))) + '-' + LTRIM(RTRIM(CONVERT(varchar(10), @estab)));

            -- A conta (cada ficha, sede ou estabelecimento, gera uma conta com código NO-ESTAB)
            INSERT @ev (origem, entidade, tipoconta, stamporigem, codigo, operacao)
            VALUES ('CL', 'CONTA', 'CLI', @stamp,
                    LTRIM(RTRIM(CONVERT(varchar(20), @no))) + '-' + LTRIM(RTRIM(CONVERT(varchar(10), @estab))),
                    @operacao);

            -- Ao apagar a ficha, apagam-se também os contactos dela (lista guardada antes de apagar)
            IF @operacao = 'D'
                INSERT @ev (origem, entidade, tipoconta, stamporigem, codigo, operacao)
                SELECT 'U_CLCONTACT', 'CONTACTO', 'CLI', l.stamp,
                       RTRIM(l.stamp) + '|' + LTRIM(RTRIM(CONVERT(varchar(20), @no))) + '-' + LTRIM(RTRIM(CONVERT(varchar(10), @estab))), 'D'
                  FROM @lista AS l;

            -- Ao apagar a ficha, apaga também todos os contactos dela que já foram enviados ao CRM (vistos na fila)
            IF @operacao = 'D'
                INSERT @ev (origem, entidade, tipoconta, stamporigem, codigo, operacao)
                SELECT 'U_CLCONTACT', 'CONTACTO', 'CLI', f.stamporigem, RTRIM(f.codigo), 'D'
                  FROM dbo.u_crmfila AS f WITH (NOLOCK)
                 WHERE f.entidade = 'CONTACTO' AND f.operacao = 'U' AND RTRIM(f.codigo) LIKE '%|' + @contaCod
                   AND f.u_crmfilastamp = (SELECT MAX(x.u_crmfilastamp) FROM dbo.u_crmfila AS x WITH (NOLOCK)
                                            WHERE x.entidade = 'CONTACTO' AND x.stamporigem = f.stamporigem);

            -- Ao gravar, reenfileira também os contactos da ficha (o contacto segue o estado da conta)
            IF @operacao = 'U'
                INSERT @ev (origem, entidade, tipoconta, stamporigem, codigo, operacao)
                SELECT 'U_CLCONTACT', 'CONTACTO', 'CLI', k.u_clcontactstamp,
                       RTRIM(k.u_clcontactstamp) + '|' + LTRIM(RTRIM(CONVERT(varchar(20), @no))) + '-' + LTRIM(RTRIM(CONVERT(varchar(10), @estab))), 'U'
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
            IF ISNULL(LTRIM(RTRIM(@stamp)), '') <> ''
            INSERT @ev (origem, entidade, tipoconta, stamporigem, codigo, operacao)
            VALUES ('U_CLCONTACT', 'CONTACTO', 'CLI', @stamp,
                    -- Na eliminação o código leva a conta ("contactCode|NO-ESTAB"): o serviço precisa dela para inativar o contacto
                    RTRIM(@stamp) + ISNULL(
                        (SELECT TOP 1 '|' + LTRIM(RTRIM(CONVERT(varchar(20), c.no))) + '-' + LTRIM(RTRIM(CONVERT(varchar(10), c.estab)))
                           FROM dbo.cl AS c WITH (NOLOCK) WHERE c.clstamp = @clstamp), ''),
                    @operacao);

            -- Contactos apagados (lista guardada antes de apagar): código "contactCode|NO-ESTAB" da ficha
            IF @operacao = 'D'
                INSERT @ev (origem, entidade, tipoconta, stamporigem, codigo, operacao)
                SELECT 'U_CLCONTACT', 'CONTACTO', 'CLI', l.stamp,
                       RTRIM(l.stamp) + ISNULL((SELECT TOP 1 '|' + LTRIM(RTRIM(CONVERT(varchar(20), c.no))) + '-' + LTRIM(RTRIM(CONVERT(varchar(10), c.estab)))
                                                  FROM dbo.cl AS c WITH (NOLOCK) WHERE c.clstamp = @clstamp), ''), 'D'
                  FROM @lista AS l;

            -- A conta do contacto (a ficha indicada pelo PHC)
            SET @contaCod = (SELECT TOP 1 LTRIM(RTRIM(CONVERT(varchar(20), c.no))) + '-' + LTRIM(RTRIM(CONVERT(varchar(10), c.estab)))
                               FROM dbo.cl AS c WITH (NOLOCK) WHERE c.clstamp = @clstamp);

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

        -- Ao gravar: contactos desta conta com pedido na fila que entretanto já não existem (apagados) geram D.
        -- Se nunca foram enviados, o D substitui o U pendente e o serviço fecha-o como SEM_ENVIO (sem erro).
        -- O código da fila de cada contacto leva a conta ("contactCode|NO-ESTAB"), que é o que liga o contacto apagado à conta.
        IF @operacao = 'U' AND @contaCod IS NOT NULL
            INSERT @ev (origem, entidade, tipoconta, stamporigem, codigo, operacao)
            SELECT 'U_CLCONTACT', 'CONTACTO', 'CLI', f.stamporigem, RTRIM(f.codigo), 'D'
              FROM dbo.u_crmfila AS f WITH (NOLOCK)
             WHERE f.entidade = 'CONTACTO' AND f.operacao = 'U' AND RTRIM(f.codigo) LIKE '%|' + @contaCod
               -- o último registo deste contacto na fila é um U (não há já um D a seguir)
               AND f.u_crmfilastamp = (SELECT MAX(x.u_crmfilastamp) FROM dbo.u_crmfila AS x WITH (NOLOCK)
                                        WHERE x.entidade = 'CONTACTO' AND x.stamporigem = f.stamporigem)
               -- e já não existe na u_clcontact
               AND NOT EXISTS (SELECT 1 FROM dbo.u_clcontact AS k WITH (NOLOCK) WHERE k.u_clcontactstamp = f.stamporigem);

        -- Contacto que entra numa conta que nunca foi enfileirada: cria também a conta (o CRM precisa dela primeiro)
        IF @origem = 'U_CLCONTACT' AND @operacao = 'U' AND @contaCod IS NOT NULL
           AND EXISTS (SELECT 1 FROM @ev WHERE entidade = 'CONTACTO' AND operacao = 'U')
           AND NOT EXISTS (SELECT 1 FROM dbo.u_crmfila AS f WITH (NOLOCK) WHERE f.entidade = 'CONTA' AND f.stamporigem = @clstamp)
            INSERT @ev (origem, entidade, tipoconta, stamporigem, codigo, operacao)
            VALUES ('CL', 'CONTA', 'CLI', @clstamp, @contaCod, 'U');

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
