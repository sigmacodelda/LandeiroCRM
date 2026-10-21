-- PASSO 6: apaga SO os 3 triggers nossos. Os do PHC (tr_cl_update, tr_cl_delete) nao sao tocados.
-- So fazer depois de os 4 eventos estarem no PHC e testados (passo 4).
USE LAND2;
GO
IF DB_NAME() <> N'LAND2' THROW 50000, N'Base errada: este ficheiro e so para a LAND2.', 1;
GO
IF OBJECT_ID(N'dbo.tr_crm_cl', N'TR') IS NOT NULL            DROP TRIGGER dbo.tr_crm_cl;
GO
IF OBJECT_ID(N'dbo.tr_crm_cl2', N'TR') IS NOT NULL           DROP TRIGGER dbo.tr_crm_cl2;
GO
IF OBJECT_ID(N'dbo.tr_crm_u_clcontact', N'TR') IS NOT NULL   DROP TRIGGER dbo.tr_crm_u_clcontact;
GO
SELECT name AS trigger_nosso_que_ficou FROM sys.triggers WITH (NOLOCK) WHERE name LIKE 'tr[_]crm[_]%';
GO
