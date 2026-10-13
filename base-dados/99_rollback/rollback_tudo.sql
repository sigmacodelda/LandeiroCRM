-- =============================================================================
-- Rollback completo, pela ordem inversa da instalação. Correr a partir de base-dados/ com sqlcmd:
--   sqlcmd -S <servidor> -d LAND2_DEMO -b -i 99_rollback/rollback_tudo.sql ^
--          -v BaseDados=LAND2_DEMO PermitirProducao=NAO
-- =============================================================================
:on error exit
IF DB_NAME() <> N'$(BaseDados)'
    THROW 50000, N'A base de dados ligada não é a indicada em BaseDados.', 1;
GO
IF DB_NAME() = N'LAND2' AND N'$(PermitirProducao)' <> N'SIM'
    THROW 50001, N'BLOQUEADO: LAND2 é a base real. Só com confirmação explícita (-v PermitirProducao=SIM).', 1;
GO
:r 99_rollback/01_remover_triggers.sql
:r 99_rollback/02_remover_permissoes.sql
:r 99_rollback/03_remover_procedimentos.sql
:r 99_rollback/04_remover_views.sql
:r 99_rollback/05_remover_sequencia_e_tipo.sql
