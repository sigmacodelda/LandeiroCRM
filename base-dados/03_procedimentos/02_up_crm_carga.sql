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
