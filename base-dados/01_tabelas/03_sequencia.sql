-- =============================================================================
-- Sequência usada para gerar o stamp da fila (unicidade sem colisões). Objeto SQL, não do PHC.
-- Idempotente: só cria se ainda não existir.
-- =============================================================================
SET NOCOUNT ON;
GO
IF OBJECT_ID(N'dbo.u_crmfila_seq', N'SO') IS NULL
    CREATE SEQUENCE dbo.u_crmfila_seq AS bigint START WITH 1 INCREMENT BY 1 CACHE 50;
GO
