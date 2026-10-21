-- =============================================================================
-- Teste SQL 08: regra "contacto só entra se tiver email, telefone ou telemóvel". SÓ NA LAND2_DEMO.
-- Corre tudo dentro de uma transação e faz ROLLBACK no fim (não deixa dados).
--   sqlcmd -S ... -d LAND2_DEMO -f 65001 -b -i testes/08_teste_contacto_com_meio.sql
-- =============================================================================
SET NOCOUNT ON;
IF DB_NAME() <> N'LAND2_DEMO' THROW 50000, N'Este teste só pode correr na LAND2_DEMO.', 1;
IF EXISTS (SELECT 1 FROM dbo.cl WITH (NOLOCK) WHERE no BETWEEN 99999991 AND 99999999)
    THROW 50002, N'Números de cliente de teste (99999991..99999999) já em uso.', 1;

DECLARE @r TABLE (n int IDENTITY(1,1), teste varchar(160), ok bit, detalhe varchar(300));
DECLARE @c1 char(25) = 'CRMT-MC-01';
DECLARE @q int;
DECLARE @res TABLE (a int, b int);

BEGIN TRAN;

INSERT dbo.cl (clstamp, no, estab, nome, inactivo) VALUES (@c1, 99999991, 0, 'Cliente Meio', 0);

-- M1: contacto sem email, telefone nem telemóvel (vazios ou só espaços) não entra na fila
INSERT dbo.u_clcontact (u_clcontactstamp, clstamp, nome, email, telefone, tlmvl)
VALUES ('CRMT-MC-K1', @c1, 'Sem nada', '', '', ''), ('CRMT-MC-K2', @c1, 'So espacos', '   ', ' ', '  ');
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE entidade = 'CONTACTO' AND stamporigem IN ('CRMT-MC-K1', 'CRMT-MC-K2');
INSERT @r (teste, ok, detalhe) VALUES ('M1 contacto sem meio de contacto não entra', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('linhas=', @q));

-- M2: cada um dos três campos chega para o contacto entrar
INSERT dbo.u_clcontact (u_clcontactstamp, clstamp, nome, email) VALUES ('CRMT-MC-K3', @c1, 'So email', 'a@teste.pt');
INSERT dbo.u_clcontact (u_clcontactstamp, clstamp, nome, telefone) VALUES ('CRMT-MC-K4', @c1, 'So telefone', '253000000');
INSERT dbo.u_clcontact (u_clcontactstamp, clstamp, nome, tlmvl) VALUES ('CRMT-MC-K5', @c1, 'So telemovel', '912345678');
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE entidade = 'CONTACTO' AND estado = 'PENDENTE' AND stamporigem IN ('CRMT-MC-K3', 'CRMT-MC-K4', 'CRMT-MC-K5');
INSERT @r (teste, ok, detalhe) VALUES ('M2 email, telefone ou telemóvel: o contacto entra', CASE WHEN @q = 3 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- M3: o contacto sem meio passa a entrar quando ganha um email
UPDATE dbo.u_clcontact SET email = 'novo@teste.pt' WHERE u_clcontactstamp = 'CRMT-MC-K1';
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE entidade = 'CONTACTO' AND estado = 'PENDENTE' AND stamporigem = 'CRMT-MC-K1';
INSERT @r (teste, ok, detalhe) VALUES ('M3 ao ganhar um email, o contacto entra', CASE WHEN @q = 1 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- M4: contacto já enviado que perde o email continua a entrar (o CRM recebe a alteração)
UPDATE dbo.u_crmfila SET estado = 'ENVIADO' WHERE stamporigem = 'CRMT-MC-K3';
UPDATE dbo.u_clcontact SET email = '' WHERE u_clcontactstamp = 'CRMT-MC-K3';
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE entidade = 'CONTACTO' AND estado = 'PENDENTE' AND stamporigem = 'CRMT-MC-K3';
INSERT @r (teste, ok, detalhe) VALUES ('M4 contacto já enviado sem meio continua a entrar', CASE WHEN @q = 1 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- M5: a carga também respeita a regra (K2 e K3 estão sem meio; K1, K4 e K5 têm)
DELETE dbo.u_crmfila WHERE stamporigem LIKE 'CRMT-MC-%';
INSERT @res EXEC dbo.up_crm_carga @origem = 'CL', @no = 99999991;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE entidade = 'CONTACTO' AND stamporigem LIKE 'CRMT-MC-K%';
INSERT @r (teste, ok, detalhe) VALUES ('M5 a carga enfileira 3 dos 5 contactos (K2 e K3 sem meio ficam de fora)', CASE WHEN @q = 3 THEN 1 ELSE 0 END, CONCAT('contactos=', @q));

-- M6: eliminar um contacto sem meio gera D (as eliminações não são filtradas)
DELETE dbo.u_crmfila WHERE stamporigem = 'CRMT-MC-K2';
DELETE dbo.u_clcontact WHERE u_clcontactstamp = 'CRMT-MC-K2';
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = 'CRMT-MC-K2' AND operacao = 'D' AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('M6 eliminar contacto sem meio gera D', CASE WHEN @q = 1 THEN 1 ELSE 0 END, CONCAT('linhas=', @q));

ROLLBACK TRAN;

SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem LIKE 'CRMT-MC%';
INSERT @r (teste, ok, detalhe) VALUES ('M7 rollback não deixa dados de teste na fila', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('restos=', @q));

SELECT n, CASE ok WHEN 1 THEN 'OK' ELSE 'FALHOU' END AS resultado, teste, detalhe FROM @r ORDER BY n;
SELECT COUNT(*) AS total, SUM(CASE WHEN ok = 1 THEN 1 ELSE 0 END) AS ok, SUM(CASE WHEN ok = 0 THEN 1 ELSE 0 END) AS falhas FROM @r;
IF EXISTS (SELECT 1 FROM @r WHERE ok = 0) THROW 50099, N'Há asserts a falhar neste teste.', 1;
