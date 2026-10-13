-- =============================================================================
-- Permissões mínimas do serviço: um papel na base de dados (crmsync_servico).
--
--   * leitura das views u_v_crm_*;
--   * leitura e atualização da fila (u_crmfila);
--   * execução das consultas de acompanhamento.
-- NÃO tem acesso às tabelas do PHC (cl, cl2, u_clcontact): as views funcionam por
-- cadeia de propriedade (views e tabelas são do mesmo dono, dbo).
--
-- Este script só cria o papel. A criação do LOGIN do servidor, com a sua password, faz-se
-- à parte e nunca fica em ficheiros (ver docs/manual-instalacao.md):
--   CREATE LOGIN crmsync_svc WITH PASSWORD = '<definir>', CHECK_POLICY = ON;
--   CREATE USER  crmsync_svc FOR LOGIN crmsync_svc;
--   ALTER ROLE crmsync_servico ADD MEMBER crmsync_svc;
-- Idempotente.
-- =============================================================================
SET NOCOUNT ON;
GO
IF DATABASE_PRINCIPAL_ID(N'crmsync_servico') IS NULL
    CREATE ROLE crmsync_servico AUTHORIZATION dbo;
GO
GRANT SELECT ON dbo.u_v_crm_conta_cl             TO crmsync_servico;
GRANT SELECT ON dbo.u_v_crm_contacto_cl          TO crmsync_servico;
GRANT SELECT, UPDATE ON dbo.u_crmfila            TO crmsync_servico;
GRANT EXECUTE ON dbo.up_crm_consulta_totais      TO crmsync_servico;
GRANT EXECUTE ON dbo.up_crm_consulta_erros       TO crmsync_servico;
GRANT EXECUTE ON dbo.up_crm_consulta_historico   TO crmsync_servico;
GO
