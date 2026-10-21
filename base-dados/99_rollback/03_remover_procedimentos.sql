-- Rollback 3/5: remove os procedimentos up_crm_*.
SET NOCOUNT ON;
GO
IF OBJECT_ID(N'dbo.up_crm_consulta_historico', N'P') IS NOT NULL DROP PROCEDURE dbo.up_crm_consulta_historico;
GO
IF OBJECT_ID(N'dbo.up_crm_consulta_erros', N'P') IS NOT NULL     DROP PROCEDURE dbo.up_crm_consulta_erros;
GO
IF OBJECT_ID(N'dbo.up_crm_consulta_totais', N'P') IS NOT NULL    DROP PROCEDURE dbo.up_crm_consulta_totais;
GO
IF OBJECT_ID(N'dbo.up_crm_repor', N'P') IS NOT NULL              DROP PROCEDURE dbo.up_crm_repor;
GO
IF OBJECT_ID(N'dbo.up_crm_carga', N'P') IS NOT NULL              DROP PROCEDURE dbo.up_crm_carga;
GO
IF OBJECT_ID(N'dbo.up_crm_enfileirar', N'P') IS NOT NULL         DROP PROCEDURE dbo.up_crm_enfileirar;
GO

IF OBJECT_ID(N'dbo.sc_CrmEnfileirarEvento', N'P') IS NOT NULL DROP PROCEDURE dbo.sc_CrmEnfileirarEvento;
GO
