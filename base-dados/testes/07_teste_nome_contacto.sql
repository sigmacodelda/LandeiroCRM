-- =============================================================================
-- Teste SQL 07: nome do contacto (campo "name" da API). SÓ NA LAND2_DEMO.
-- No PHC o nome da pessoa pode estar em "contacto" (contactos criados no ecrã, com "nome" vazio)
-- ou em "nome" (contactos importados, onde é a empresa).
-- Corre tudo dentro de uma transação e faz ROLLBACK no fim (não deixa dados).
--   sqlcmd -S ... -d LAND2_DEMO -f 65001 -b -i testes/07_teste_nome_contacto.sql
-- =============================================================================
SET NOCOUNT ON;
IF DB_NAME() <> N'LAND2_DEMO' THROW 50000, N'Este teste só pode correr na LAND2_DEMO.', 1;
IF EXISTS (SELECT 1 FROM dbo.cl WITH (NOLOCK) WHERE no BETWEEN 99999991 AND 99999999)
    THROW 50002, N'Números de cliente de teste (99999991..99999999) já em uso.', 1;

DECLARE @r TABLE (n int IDENTITY(1,1), teste varchar(160), ok bit, detalhe varchar(300));
DECLARE @c1 char(25) = 'CRMT-NM-01';
DECLARE @q int, @a varchar(200);

BEGIN TRAN;

INSERT dbo.cl (clstamp, no, estab, nome) VALUES (@c1, 99999991, 0, 'Cliente Nome');
INSERT dbo.u_clcontact (u_clcontactstamp, clstamp, nome, contacto, tlmvl) VALUES
    ('CRMT-NM-K1', @c1, '', 'Sandra Silva', '912345678'),                 -- criado no ecrã: pessoa em "contacto"
    ('CRMT-NM-K2', @c1, 'EMPRESA IMPORTADA, LDA.', '', ''),      -- importado: só "nome"
    ('CRMT-NM-K3', @c1, 'EMPRESA, LDA.', 'Vitor Silva', ''),     -- ambos: ganha a pessoa
    ('CRMT-NM-K4', @c1, 'EMPRESA, LDA.', 'geral@x.pt', ''),      -- "contacto" é um email: fica o nome
    ('CRMT-NM-K5', @c1, 'EMPRESA, LDA.', '253 823 675', ''),     -- "contacto" é um telefone: fica o nome
    ('CRMT-NM-K6', @c1, '', 'geral@x.pt', ''),                   -- só email: fica o email (melhor que "Sem nome")
    ('CRMT-NM-K7', @c1, '', '', '');                             -- nada: vazio (o serviço envia "Sem nome")

-- N1..N7: o campo name da view
SELECT @a = name FROM dbo.u_v_crm_contacto_cl WITH (NOLOCK) WHERE stamp = 'CRMT-NM-K1';
INSERT @r (teste, ok, detalhe) VALUES ('N1 nome vazio e contacto com nome: usa o contacto', CASE WHEN @a = 'Sandra Silva' THEN 1 ELSE 0 END, @a);
SELECT @a = name FROM dbo.u_v_crm_contacto_cl WITH (NOLOCK) WHERE stamp = 'CRMT-NM-K2';
INSERT @r (teste, ok, detalhe) VALUES ('N2 só nome: usa o nome', CASE WHEN @a = 'EMPRESA IMPORTADA, LDA.' THEN 1 ELSE 0 END, @a);
SELECT @a = name FROM dbo.u_v_crm_contacto_cl WITH (NOLOCK) WHERE stamp = 'CRMT-NM-K3';
INSERT @r (teste, ok, detalhe) VALUES ('N3 nome e contacto: ganha o contacto (a pessoa)', CASE WHEN @a = 'Vitor Silva' THEN 1 ELSE 0 END, @a);
SELECT @a = name FROM dbo.u_v_crm_contacto_cl WITH (NOLOCK) WHERE stamp = 'CRMT-NM-K4';
INSERT @r (teste, ok, detalhe) VALUES ('N4 contacto é um email: fica o nome', CASE WHEN @a = 'EMPRESA, LDA.' THEN 1 ELSE 0 END, @a);
SELECT @a = name FROM dbo.u_v_crm_contacto_cl WITH (NOLOCK) WHERE stamp = 'CRMT-NM-K5';
INSERT @r (teste, ok, detalhe) VALUES ('N5 contacto é um telefone: fica o nome', CASE WHEN @a = 'EMPRESA, LDA.' THEN 1 ELSE 0 END, @a);
SELECT @a = name FROM dbo.u_v_crm_contacto_cl WITH (NOLOCK) WHERE stamp = 'CRMT-NM-K6';
INSERT @r (teste, ok, detalhe) VALUES ('N6 só um email em contacto: envia esse valor', CASE WHEN @a = 'geral@x.pt' THEN 1 ELSE 0 END, @a);
SELECT @a = name FROM dbo.u_v_crm_contacto_cl WITH (NOLOCK) WHERE stamp = 'CRMT-NM-K7';
INSERT @r (teste, ok, detalhe) VALUES ('N7 tudo vazio: vazio (o serviço envia "Sem nome")', CASE WHEN @a = '' THEN 1 ELSE 0 END, '[' + @a + ']');

-- N8: alterar só o campo "contacto" gera fila (passou a ser campo integrado)
UPDATE dbo.u_crmfila SET estado = 'ENVIADO' WHERE stamporigem LIKE 'CRMT-NM-%';
UPDATE dbo.u_clcontact SET contacto = 'Sandra M. Silva' WHERE u_clcontactstamp = 'CRMT-NM-K1';
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = 'CRMT-NM-K1' AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('N8 alterar o campo contacto gera o contacto PENDENTE', CASE WHEN @q = 1 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- N9: gravar sem alterar nada continua a não gerar fila
UPDATE dbo.u_crmfila SET estado = 'ENVIADO' WHERE stamporigem = 'CRMT-NM-K1';
UPDATE dbo.u_clcontact SET nome = nome, contacto = contacto WHERE u_clcontactstamp = 'CRMT-NM-K1';
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = 'CRMT-NM-K1' AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('N9 gravar sem alterar nada NÃO gera fila', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

ROLLBACK TRAN;

SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem LIKE 'CRMT-NM%';
INSERT @r (teste, ok, detalhe) VALUES ('N10 rollback não deixa dados de teste na fila', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('restos=', @q));
SELECT @q = COUNT(*) FROM dbo.cl WITH (NOLOCK) WHERE clstamp LIKE 'CRMT-NM%';
INSERT @r (teste, ok, detalhe) VALUES ('N11 rollback não deixa fichas de teste na CL', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('restos=', @q));

SELECT n, CASE ok WHEN 1 THEN 'OK' ELSE 'FALHOU' END AS resultado, teste, detalhe FROM @r ORDER BY n;
SELECT COUNT(*) AS total, SUM(CASE WHEN ok = 1 THEN 1 ELSE 0 END) AS ok, SUM(CASE WHEN ok = 0 THEN 1 ELSE 0 END) AS falhas FROM @r;
IF EXISTS (SELECT 1 FROM @r WHERE ok = 0) THROW 50099, N'Há asserts a falhar neste teste.', 1;
