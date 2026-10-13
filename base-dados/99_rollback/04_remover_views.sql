-- Rollback 4/5: remove as views u_v_crm_*.
SET NOCOUNT ON;
GO
IF OBJECT_ID(N'dbo.u_v_crm_contacto_cl', N'V') IS NOT NULL DROP VIEW dbo.u_v_crm_contacto_cl;
GO
IF OBJECT_ID(N'dbo.u_v_crm_conta_cl', N'V') IS NOT NULL    DROP VIEW dbo.u_v_crm_conta_cl;
GO
