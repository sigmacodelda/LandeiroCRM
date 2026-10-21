-- =============================================================================
-- Instalação do circuito PHC -> Somnia CRM na base de dados. Executa os scripts pela ordem certa.
-- Correr a partir da pasta base-dados/ com sqlcmd (modo SQLCMD), em UTF-8:
--   sqlcmd -S "tcp:<servidor>\<instancia>" -d LAND2_DEMO -f 65001 -b -i instalar.sql ^
--          -v BaseDados=LAND2_DEMO PermitirProducao=NAO
-- Todos os scripts são idempotentes: podem repetir-se sem estragar nada.
-- Segurança: recusa correr se a base ligada não for a indicada, e recusa a LAND2 (base real)
-- sem confirmação explícita (-v PermitirProducao=SIM).
-- =============================================================================
:on error exit
SET NOCOUNT ON;
IF DB_NAME() <> N'$(BaseDados)'
    THROW 50000, N'A base de dados ligada não é a indicada em BaseDados.', 1;
GO
IF DB_NAME() = N'LAND2' AND N'$(PermitirProducao)' <> N'SIM'
    THROW 50001, N'BLOQUEADO: LAND2 é a base real. Só com confirmação explícita (-v PermitirProducao=SIM).', 1;
GO
:r 01_tabelas/01_verificar_u_crmfila.sql
:r 01_tabelas/02_tipo_evento.sql
:r 01_tabelas/03_sequencia.sql
:r 02_views/01_u_v_crm_conta_cl.sql
:r 02_views/02_u_v_crm_contacto_cl.sql
:r 03_procedimentos/01_up_crm_enfileirar.sql
:r 03_procedimentos/02_up_crm_carga.sql
:r 03_procedimentos/03_up_crm_repor.sql
:r 03_procedimentos/04_up_crm_consultas.sql
:r 03_procedimentos/05_sc_CrmEnfileirarEvento.sql
-- Os triggers (04_triggers) foram substituídos pelos eventos do PHC (phc/eventos) e já não se instalam.
-- Para remover os que já existam na base: 99_rollback/01_remover_triggers.sql
:r 05_permissoes/01_role_servico.sql
PRINT N'Instalação concluída em ' + DB_NAME();
GO
