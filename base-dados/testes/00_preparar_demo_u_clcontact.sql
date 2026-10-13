-- =============================================================================
-- Preparação da LAND2_DEMO (SÓ PARA TESTES, nunca correr na LAND2 real)
--
-- A LAND2_DEMO é uma cópia mais antiga: a tabela de utilizador U_CLCONTACT
-- não tem as colunas OBS e DEPARTAMENTO, que existem na LAND2 (posições 20 e 21).
-- Este script acrescenta-as, com o mesmo tipo e default da LAND2, para que as views
-- e os testes na DEMO usem a mesma estrutura da base real.
-- É idempotente: só acrescenta o que falta.
-- =============================================================================
SET NOCOUNT ON;
GO
IF DB_NAME() <> N'LAND2_DEMO'
    THROW 50000, N'Este script só pode correr na LAND2_DEMO.', 1;
GO
IF COL_LENGTH(N'dbo.u_clcontact', N'obs') IS NULL
    ALTER TABLE dbo.u_clcontact ADD obs text NOT NULL CONSTRAINT df_u_clcontact_obs DEFAULT ('');
GO
IF COL_LENGTH(N'dbo.u_clcontact', N'departamento') IS NULL
    ALTER TABLE dbo.u_clcontact ADD departamento varchar(100) NOT NULL CONSTRAINT df_u_clcontact_departamento DEFAULT ('');
GO
SELECT COLUMN_NAME, DATA_TYPE, ORDINAL_POSITION
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = N'u_clcontact' AND COLUMN_NAME IN (N'obs', N'departamento');
GO
