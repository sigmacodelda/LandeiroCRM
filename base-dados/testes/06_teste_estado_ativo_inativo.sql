-- =============================================================================
-- Teste SQL 06: estado Ativo/Inativo (campo "status" da API). SÓ NA LAND2_DEMO.
-- Corre tudo dentro de uma transação e faz ROLLBACK no fim (não deixa dados).
--   sqlcmd -S ... -d LAND2_DEMO -f 65001 -b -i testes/06_teste_estado_ativo_inativo.sql
-- =============================================================================
SET NOCOUNT ON;
IF DB_NAME() <> N'LAND2_DEMO' THROW 50000, N'Este teste só pode correr na LAND2_DEMO.', 1;
IF EXISTS (SELECT 1 FROM dbo.cl WITH (NOLOCK) WHERE no BETWEEN 99999991 AND 99999999)
    THROW 50002, N'Números de cliente de teste (99999991..99999999) já em uso.', 1;

DECLARE @r TABLE (n int IDENTITY(1,1), teste varchar(160), ok bit, detalhe varchar(300));
DECLARE @c1 char(25) = 'CRMT-ST-01', @k1 char(25) = 'CRMT-ST-K1', @k2 char(25) = 'CRMT-ST-K2';
DECLARE @q int, @a varchar(20), @b varchar(20);
DECLARE @res TABLE (a int, b int);

BEGIN TRAN;

INSERT dbo.cl (clstamp, no, estab, nome, inactivo) VALUES (@c1, 99999991, 0, 'Cliente Estado', 0);
INSERT dbo.u_clcontact (u_clcontactstamp, clstamp, nome, email) VALUES (@k1, @c1, 'Pessoa 1', 'p1@teste.pt'), (@k2, @c1, 'Pessoa 2', 'p2@teste.pt');

-- S1: ficha ativa -> "Ativo" na conta e nos contactos
SELECT @a = status FROM dbo.u_v_crm_conta_cl WITH (NOLOCK) WHERE stamp = @c1;
SELECT @b = MAX(status) FROM dbo.u_v_crm_contacto_cl WITH (NOLOCK) WHERE accountStamp = @c1;
INSERT @r (teste, ok, detalhe) VALUES ('S1 ficha ativa: status Ativo na conta e nos contactos',
    CASE WHEN @a = 'Ativo' AND @b = 'Ativo' THEN 1 ELSE 0 END, CONCAT('conta=', @a, ' contacto=', @b));

-- S2: inativar a ficha gera a conta PENDENTE e os 2 contactos PENDENTES
UPDATE dbo.u_crmfila SET estado = 'ENVIADO' WHERE stamporigem IN (@c1, @k1, @k2);
UPDATE dbo.cl SET inactivo = 1 WHERE clstamp = @c1;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = @c1 AND entidade = 'CONTA' AND estado = 'PENDENTE' AND operacao = 'U';
INSERT @r (teste, ok, detalhe) VALUES ('S2a inativar a ficha gera a conta PENDENTE', CASE WHEN @q = 1 THEN 1 ELSE 0 END, CONCAT('contas=', @q));
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem IN (@k1, @k2) AND entidade = 'CONTACTO' AND estado = 'PENDENTE' AND operacao = 'U';
INSERT @r (teste, ok, detalhe) VALUES ('S2b inativar a ficha gera os 2 contactos PENDENTES', CASE WHEN @q = 2 THEN 1 ELSE 0 END, CONCAT('contactos=', @q));

-- S3: ficha inativa -> "Inativo" na conta e nos contactos
SELECT @a = status FROM dbo.u_v_crm_conta_cl WITH (NOLOCK) WHERE stamp = @c1;
SELECT @b = MAX(status) FROM dbo.u_v_crm_contacto_cl WITH (NOLOCK) WHERE accountStamp = @c1;
INSERT @r (teste, ok, detalhe) VALUES ('S3 ficha inativa: status Inativo na conta e nos contactos',
    CASE WHEN @a = 'Inativo' AND @b = 'Inativo' THEN 1 ELSE 0 END, CONCAT('conta=', @a, ' contacto=', @b));

-- S4: gravar a ficha sem mudar o estado não reenfileira nada
UPDATE dbo.u_crmfila SET estado = 'ENVIADO' WHERE stamporigem IN (@c1, @k1, @k2);
UPDATE dbo.cl SET inactivo = inactivo, nome = nome WHERE clstamp = @c1;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem IN (@c1, @k1, @k2) AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('S4 gravar sem mudar o estado NÃO gera fila', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- S5: reativar a ficha gera de novo a conta e os contactos
UPDATE dbo.cl SET inactivo = 0 WHERE clstamp = @c1;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem IN (@c1, @k1, @k2) AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('S5 reativar gera a conta e os 2 contactos PENDENTES', CASE WHEN @q = 3 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- S6: alterar o estado de uma ficha SEM contactos só gera a conta
INSERT dbo.cl (clstamp, no, estab, nome, inactivo) VALUES ('CRMT-ST-02', 99999992, 0, 'Sem contactos', 0);
UPDATE dbo.u_crmfila SET estado = 'ENVIADO' WHERE stamporigem = 'CRMT-ST-02';
UPDATE dbo.cl SET inactivo = 1 WHERE clstamp = 'CRMT-ST-02';
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = 'CRMT-ST-02' AND estado = 'PENDENTE' AND entidade = 'CONTA';
INSERT @r (teste, ok, detalhe) VALUES ('S6 ficha sem contactos: só gera a conta', CASE WHEN @q = 1 THEN 1 ELSE 0 END, CONCAT('contas=', @q));

-- S9: cliente INATIVO nunca enviado (e o seu contacto) não entra na fila
INSERT dbo.cl (clstamp, no, estab, nome, inactivo) VALUES ('CRMT-ST-03', 99999993, 0, 'Inativo nunca enviado', 1);
INSERT dbo.u_clcontact (u_clcontactstamp, clstamp, nome, email) VALUES ('CRMT-ST-K3', 'CRMT-ST-03', 'Pessoa inativa', 'p3@teste.pt');
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem IN ('CRMT-ST-03', 'CRMT-ST-K3');
INSERT @r (teste, ok, detalhe) VALUES ('S9 inativo nunca enviado: conta e contacto não entram', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('linhas=', @q));

-- S10: a carga também não os enfileira
INSERT @res EXEC dbo.up_crm_carga @origem = 'CL', @no = 99999993;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem IN ('CRMT-ST-03', 'CRMT-ST-K3');
INSERT @r (teste, ok, detalhe) VALUES ('S10 a carga não enfileira o inativo nunca enviado', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('linhas=', @q));

-- S11: se for ativado no PHC passa a entrar (conta e contacto)
UPDATE dbo.cl SET inactivo = 0 WHERE clstamp = 'CRMT-ST-03';
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem IN ('CRMT-ST-03', 'CRMT-ST-K3') AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('S11 ativar o cliente faz entrar a conta e o contacto', CASE WHEN @q = 2 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- S12: inativo que já foi enviado continua a entrar (para o CRM receber "Inativo")
UPDATE dbo.u_crmfila SET estado = 'ENVIADO' WHERE stamporigem IN ('CRMT-ST-03', 'CRMT-ST-K3');
UPDATE dbo.cl SET inactivo = 1 WHERE clstamp = 'CRMT-ST-03';
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem IN ('CRMT-ST-03', 'CRMT-ST-K3') AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('S12 inativar um cliente já enviado gera conta e contacto', CASE WHEN @q = 2 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

ROLLBACK TRAN;

SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem LIKE 'CRMT-ST%';
INSERT @r (teste, ok, detalhe) VALUES ('S7 rollback não deixa dados de teste na fila', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('restos=', @q));
SELECT @q = COUNT(*) FROM dbo.cl WITH (NOLOCK) WHERE clstamp LIKE 'CRMT-ST%';
INSERT @r (teste, ok, detalhe) VALUES ('S8 rollback não deixa fichas de teste na CL', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('restos=', @q));

SELECT n, CASE ok WHEN 1 THEN 'OK' ELSE 'FALHOU' END AS resultado, teste, detalhe FROM @r ORDER BY n;
SELECT COUNT(*) AS total, SUM(CASE WHEN ok = 1 THEN 1 ELSE 0 END) AS ok, SUM(CASE WHEN ok = 0 THEN 1 ELSE 0 END) AS falhas FROM @r;
IF EXISTS (SELECT 1 FROM @r WHERE ok = 0) THROW 50099, N'Há asserts a falhar neste teste.', 1;
