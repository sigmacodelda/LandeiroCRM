-- =============================================================================
-- Teste SQL 05: permissões mínimas do serviço e robustez dos triggers. SÓ NA LAND2_DEMO.
-- Usa utilizadores SEM LOGIN (só existem dentro da base de dados e desaparecem no ROLLBACK).
-- Tudo numa transação com ROLLBACK no fim. Termina com THROW se algum assert falhar.
-- =============================================================================
SET NOCOUNT ON;
IF DB_NAME() <> N'LAND2_DEMO' THROW 50000, N'Este teste só pode correr na LAND2_DEMO.', 1;
IF DATABASE_PRINCIPAL_ID(N'crmsync_servico') IS NULL THROW 50003, N'Falta o papel crmsync_servico (05_permissoes).', 1;
IF EXISTS (SELECT 1 FROM dbo.cl WHERE no BETWEEN 99999991 AND 99999999)
    THROW 50002, N'Números de cliente de teste (99999991..99999999) já em uso.', 1;

DECLARE @r TABLE (n int IDENTITY(1,1), teste varchar(160), ok bit, detalhe varchar(400));
DECLARE @q int, @err varchar(300), @nome varchar(55);

BEGIN TRAN;

-- ===== P1: um utilizador do PHC SEM direitos sobre a fila consegue gravar (os triggers escrevem na fila) =====
CREATE USER crmt_phc WITHOUT LOGIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.cl          TO crmt_phc;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.cl2         TO crmt_phc;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.u_clcontact TO crmt_phc;

SET @err = '';
EXECUTE AS USER = 'crmt_phc';
BEGIN TRY
    INSERT dbo.cl (clstamp, no, estab, nome) VALUES ('CRMT-CL-01', 99999991, 0, 'Perm');
    INSERT dbo.cl2 (cl2stamp, descpais) VALUES ('CRMT-CL-01', 'Portugal');
    INSERT dbo.u_clcontact (u_clcontactstamp, clstamp, nome) VALUES ('CRMT-K-01', 'CRMT-CL-01', 'Pessoa');
    UPDATE dbo.u_clcontact SET nome = 'Pessoa 2' WHERE u_clcontactstamp = 'CRMT-K-01';
    UPDATE dbo.cl2 SET descpais = 'Espanha' WHERE cl2stamp = 'CRMT-CL-01';
END TRY
BEGIN CATCH
    SET @err = ERROR_MESSAGE();
END CATCH
REVERT;
INSERT @r (teste, ok, detalhe) VALUES ('P1a utilizador PHC sem direitos na fila grava CL, CL2 e contactos sem erro', CASE WHEN @err = '' THEN 1 ELSE 0 END, @err);
SELECT @q = COUNT(*) FROM dbo.u_crmfila WHERE stamporigem IN ('CRMT-CL-01', 'CRMT-K-01') AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('P1b os triggers conseguiram escrever na fila (cadeia de propriedade: conta + contacto)', CASE WHEN @q = 2 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- ===== P2: o papel do serviço tem só o mínimo =====
CREATE USER crmt_svc WITHOUT LOGIN;
ALTER ROLE crmsync_servico ADD MEMBER crmt_svc;

DECLARE @okViews bit = 0, @okFila bit = 0, @negaCl bit = 0, @negaContactos bit = 0, @negaInsert bit = 0, @negaDelete bit = 0, @okLock bit = 0, @okConsulta bit = 0;
EXECUTE AS USER = 'crmt_svc';
BEGIN TRY SELECT TOP 1 @q = 1 FROM dbo.u_v_crm_conta_cl;    SELECT TOP 1 @q = 1 FROM dbo.u_v_crm_contacto_cl; SET @okViews = 1; END TRY BEGIN CATCH END CATCH
BEGIN TRY UPDATE dbo.u_crmfila SET estado = 'A_PROCESSAR' WHERE stamporigem = 'CRMT-CL-01'; SELECT TOP 1 @q = 1 FROM dbo.u_crmfila; SET @okFila = 1; END TRY BEGIN CATCH END CATCH
BEGIN TRY SELECT TOP 1 @q = 1 FROM dbo.cl; END TRY BEGIN CATCH SET @negaCl = 1; END CATCH
BEGIN TRY SELECT TOP 1 @q = 1 FROM dbo.u_clcontact; END TRY BEGIN CATCH SET @negaContactos = 1; END CATCH
BEGIN TRY
    INSERT dbo.u_crmfila (u_crmfilastamp, origem, entidade, tipoconta) VALUES ('CRMT-X-01', 'CL', 'CONTA', 'CLI');
END TRY BEGIN CATCH SET @negaInsert = 1; END CATCH
BEGIN TRY DELETE dbo.u_crmfila WHERE stamporigem = 'CRMT-CL-01'; END TRY BEGIN CATCH SET @negaDelete = 1; END CATCH
BEGIN TRY
    DECLARE @lock int;
    EXEC @lock = sp_getapplock @Resource = 'CrmSyncTeste', @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 0;
    IF @lock >= 0 SET @okLock = 1;
END TRY BEGIN CATCH END CATCH
BEGIN TRY EXEC dbo.up_crm_consulta_totais; SET @okConsulta = 1; END TRY BEGIN CATCH END CATCH
REVERT;

INSERT @r (teste, ok, detalhe) VALUES ('P2a o serviço lê as duas views', @okViews, ''),
    ('P2b o serviço lê e atualiza a fila', @okFila, ''),
    ('P2c o serviço NÃO lê a tabela CL', @negaCl, ''),
    ('P2d o serviço NÃO lê a tabela U_CLCONTACT', @negaContactos, ''),
    ('P2e o serviço NÃO insere na fila', @negaInsert, ''),
    ('P2f o serviço NÃO apaga da fila', @negaDelete, ''),
    ('P2g o serviço consegue pedir o applock (instância única)', @okLock, ''),
    ('P2h o serviço executa as consultas de acompanhamento', @okConsulta, '');

-- ===== P3: robustez: se a fila falhar, a gravação do PHC não falha nem fica com a transação inutilizada =====
SET XACT_ABORT ON;   -- pior caso: o PHC pode ter XACT_ABORT ligado
EXEC sp_rename 'dbo.u_crmfila', 'u_crmfila_indisponivel';   -- simula a fila indisponível
SET @err = '';
BEGIN TRY
    UPDATE dbo.cl SET nome = 'Gravou apesar da fila' WHERE clstamp = 'CRMT-CL-01';
    INSERT dbo.u_clcontact (u_clcontactstamp, clstamp, nome) VALUES ('CRMT-K-02', 'CRMT-CL-01', 'Outra');
    DELETE dbo.u_clcontact WHERE u_clcontactstamp = 'CRMT-K-02';
END TRY
BEGIN CATCH
    SET @err = ERROR_MESSAGE();
END CATCH
SELECT @nome = nome FROM dbo.cl WHERE clstamp = 'CRMT-CL-01';
INSERT @r (teste, ok, detalhe) VALUES ('P3a com a fila indisponível a gravação na CL/contactos NÃO falha', CASE WHEN @err = '' THEN 1 ELSE 0 END, @err);
INSERT @r (teste, ok, detalhe) VALUES ('P3b a alteração do PHC ficou gravada', CASE WHEN @nome = 'Gravou apesar da fila' THEN 1 ELSE 0 END, @nome);
INSERT @r (teste, ok, detalhe) VALUES ('P3c a transação do PHC continua utilizável (XACT_STATE = 1)', CASE WHEN XACT_STATE() = 1 THEN 1 ELSE 0 END, CONCAT('XACT_STATE=', XACT_STATE()));
EXEC sp_rename 'dbo.u_crmfila_indisponivel', 'u_crmfila';
SET XACT_ABORT OFF;

ROLLBACK TRAN;

SELECT @q = COUNT(*) FROM dbo.u_crmfila WHERE stamporigem LIKE 'CRMT-%' OR u_crmfilastamp LIKE 'CRMT-%';
INSERT @r (teste, ok, detalhe) VALUES ('P4 rollback não deixa dados de teste', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('restos=', @q));
SELECT @q = COUNT(*) FROM sys.database_principals WHERE name IN ('crmt_phc', 'crmt_svc');
INSERT @r (teste, ok, detalhe) VALUES ('P5 rollback remove os utilizadores de teste', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('utilizadores=', @q));
INSERT @r (teste, ok, detalhe) VALUES ('P6 a tabela da fila voltou ao nome certo', CASE WHEN OBJECT_ID('dbo.u_crmfila', 'U') IS NOT NULL THEN 1 ELSE 0 END, '');

SELECT n, CASE ok WHEN 1 THEN 'OK' ELSE 'FALHOU' END AS resultado, teste, detalhe FROM @r ORDER BY n;
SELECT COUNT(*) AS total, SUM(CASE WHEN ok = 1 THEN 1 ELSE 0 END) AS ok, SUM(CASE WHEN ok = 0 THEN 1 ELSE 0 END) AS falhas FROM @r;
IF EXISTS (SELECT 1 FROM @r WHERE ok = 0) THROW 50099, N'Há asserts a falhar neste teste.', 1;
