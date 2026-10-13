-- =============================================================================
-- tr_crm_cl2 (tabela CL2, extensão 1 para 1 da CL): só INSERT e UPDATE.
--
-- Regista a entidade CONTA (stamp = cl2stamp = clstamp) com origem 'CL2' quando muda o
-- campo integrado (descpais, o país). A deduplicação de up_crm_enfileirar evita o envio a
-- dobrar quando o PHC grava a CL e a CL2 na mesma operação.
-- Só enfileira se a ficha CL existir (CL2 órfã não gera nada).
-- Nunca impede a gravação no PHC. Não usa UPDATE(coluna).
-- =============================================================================
CREATE OR ALTER TRIGGER dbo.tr_crm_cl2
ON dbo.cl2
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM inserted)
            RETURN;

        DECLARE @ev dbo.u_crm_evento_tt;

        INSERT @ev (origem, entidade, tipoconta, stamporigem, codigo, operacao)
        SELECT 'CL2', 'CONTA', 'CLI', c.clstamp,
               LTRIM(RTRIM(CONVERT(varchar(20), c.no))) + '-' + LTRIM(RTRIM(CONVERT(varchar(10), c.estab))), 'U'
          FROM (
                SELECT cl2stamp, descpais COLLATE Latin1_General_BIN2 AS descpais FROM inserted
                EXCEPT
                SELECT cl2stamp, descpais COLLATE Latin1_General_BIN2 FROM deleted
               ) AS n
          JOIN dbo.cl AS c ON c.clstamp = n.cl2stamp;

        IF EXISTS (SELECT 1 FROM @ev)
            EXEC dbo.up_crm_enfileirar @ev;
    END TRY
    BEGIN CATCH
        -- Propositadamente vazio: ver tr_crm_cl.
    END CATCH
END
GO
