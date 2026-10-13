-- Rollback 1/5: remove APENAS os triggers tr_crm_*. Os triggers do PHC (tr_cl_update, tr_cl_delete) não são tocados.
SET NOCOUNT ON;
GO
IF OBJECT_ID(N'dbo.tr_crm_cl', N'TR') IS NOT NULL            DROP TRIGGER dbo.tr_crm_cl;
GO
IF OBJECT_ID(N'dbo.tr_crm_cl2', N'TR') IS NOT NULL           DROP TRIGGER dbo.tr_crm_cl2;
GO
IF OBJECT_ID(N'dbo.tr_crm_u_clcontact', N'TR') IS NOT NULL   DROP TRIGGER dbo.tr_crm_u_clcontact;
GO
