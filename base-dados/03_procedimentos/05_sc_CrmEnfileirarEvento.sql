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
