-- Rollback 5/5: remove a sequência e o tipo de tabela.
-- A tabela u_crmfila foi criada pelo PHC e NÃO é apagada aqui: se for preciso, apaga-se no PHC.
SET NOCOUNT ON;
GO
IF OBJECT_ID(N'dbo.u_crmfila_seq', N'SO') IS NOT NULL    DROP SEQUENCE dbo.u_crmfila_seq;
GO
IF TYPE_ID(N'dbo.u_crm_evento_tt') IS NOT NULL           DROP TYPE dbo.u_crm_evento_tt;
GO
