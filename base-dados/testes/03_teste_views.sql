-- =============================================================================
-- Teste SQL 03: views u_v_crm_conta_cl e u_v_crm_contacto_cl no formato da API. SÓ NA LAND2_DEMO.
-- Tudo numa transação com ROLLBACK no fim. Termina com THROW se algum assert falhar.
-- =============================================================================
SET NOCOUNT ON;
IF DB_NAME() <> N'LAND2_DEMO' THROW 50000, N'Este teste só pode correr na LAND2_DEMO.', 1;
IF EXISTS (SELECT 1 FROM dbo.cl WHERE no BETWEEN 99999991 AND 99999999)
    THROW 50002, N'Números de cliente de teste (99999991..99999999) já em uso.', 1;

DECLARE @r TABLE (n int IDENTITY(1,1), teste varchar(160), ok bit, detalhe varchar(400));
DECLARE @q int, @txt varchar(400), @a varchar(300), @b varchar(300), @c varchar(300);

-- Contagens de referência antes de qualquer alteração (fichas e contactos já existentes)
DECLARE @nCl int = (SELECT COUNT(*) FROM dbo.cl);
DECLARE @nContComFicha int = (SELECT COUNT(*) FROM dbo.u_clcontact k JOIN dbo.cl c ON c.clstamp = k.clstamp);

-- V1/V2: as colunas têm exatamente os nomes da API (e a ordem esperada)
SELECT @txt = STRING_AGG(COLUMN_NAME, ',') WITHIN GROUP (ORDER BY ORDINAL_POSITION)
  FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'u_v_crm_conta_cl';
INSERT @r (teste, ok, detalhe) VALUES ('V1 colunas da view de contas = nomes da API + stamp',
    CASE WHEN @txt = 'stamp,code,name,address,postalCode,city,country,vatNumber,phone,mobilePhone,email,fax,accountType' THEN 1 ELSE 0 END, @txt);
SELECT @txt = STRING_AGG(COLUMN_NAME, ',') WITHIN GROUP (ORDER BY ORDINAL_POSITION)
  FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'u_v_crm_contacto_cl';
INSERT @r (teste, ok, detalhe) VALUES ('V2 colunas da view de contactos = nomes da API + stamp/accountStamp',
    CASE WHEN @txt = 'stamp,accountStamp,accountCode,contactCode,name,title,mattersType,phoneOffice,phoneMobile,obs,email,department' THEN 1 ELSE 0 END, @txt);

-- V3: os campos fora do âmbito NÃO existem nas views
SELECT @q = COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
 WHERE TABLE_NAME = 'u_v_crm_conta_cl' AND COLUMN_NAME IN ('obsCreation', 'obsExclusion', 'currentBalance', 'earliestDueDate');
INSERT @r (teste, ok, detalhe) VALUES ('V3 obsCreation/obsExclusion/currentBalance/earliestDueDate não existem na view', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('colunas=', @q));

-- V4: todas as colunas são texto (varchar)
SELECT @q = COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
 WHERE TABLE_NAME IN ('u_v_crm_conta_cl', 'u_v_crm_contacto_cl') AND DATA_TYPE <> 'varchar';
INSERT @r (teste, ok, detalhe) VALUES ('V4 todas as colunas das views são varchar', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('não-varchar=', @q));

BEGIN TRAN;

INSERT dbo.cl (clstamp, no, estab, nome, morada, codpost, local, ncont, telefone, tlmvl, email, fax)
VALUES ('CRMT-CL-01', 99999991, 0, '  Cliente Teste  ', ' Rua A, 1 ', ' 4000-001 ', ' Porto ', ' 500000000 ', ' 220000000 ', ' 910000000 ', ' a@b.pt ', ' 220000001 '),
       ('CRMT-CL-02', 99999991, 1, 'Estabelecimento 1', '', '', '', '', '', '', '', ''),
       ('CRMT-CL-03', 99999993, 0, 'Sem CL2', '', '', '', '', '', '', '', '');
INSERT dbo.cl2 (cl2stamp, descpais) VALUES ('CRMT-CL-01', ' Portugal '), ('CRMT-CL-02', 'Espanha');

-- V5: valores da conta: trim, código NO-ESTAB, país da CL2, tipo fixo CLI
SELECT @a = CONCAT_WS('|', stamp, code, name, address, postalCode, city, country, vatNumber, phone, mobilePhone, email, fax, accountType)
  FROM dbo.u_v_crm_conta_cl WHERE stamp = 'CRMT-CL-01';
INSERT @r (teste, ok, detalhe) VALUES ('V5 conta: trim em todos os campos, code 99999991-0, país da CL2, accountType CLI',
    CASE WHEN @a = 'CRMT-CL-01|99999991-0|Cliente Teste|Rua A, 1|4000-001|Porto|Portugal|500000000|220000000|910000000|a@b.pt|220000001|CLI' THEN 1 ELSE 0 END, @a);

-- V6: estabelecimento tem o seu próprio código e a sua própria conta
SELECT @a = code, @b = country FROM dbo.u_v_crm_conta_cl WHERE stamp = 'CRMT-CL-02';
INSERT @r (teste, ok, detalhe) VALUES ('V6 estabelecimento: code 99999991-1 e país próprio', CASE WHEN @a = '99999991-1' AND @b = 'Espanha' THEN 1 ELSE 0 END, CONCAT(@a, '|', @b));

-- V7: cliente sem CL2 aparece com país vazio (LEFT JOIN + ISNULL)
SELECT @q = COUNT(*), @a = MAX(country) FROM dbo.u_v_crm_conta_cl WHERE stamp = 'CRMT-CL-03';
INSERT @r (teste, ok, detalhe) VALUES ('V7 cliente sem CL2: 1 linha com país vazio', CASE WHEN @q = 1 AND @a = '' THEN 1 ELSE 0 END, CONCAT('linhas=', @q, ' país=[', @a, ']'));

-- Contactos
INSERT dbo.u_clcontact (u_clcontactstamp, clstamp, nome, funcao, tipo, telefone, tlmvl, email, departamento, obs, contacto, fax, estab, no)
VALUES ('CRMT-K-01', 'CRMT-CL-01', ' Maria Teste ', ' Gerente ', ' Financeiro ', ' 220111111 ', ' 910111111 ', ' m@t.pt ', ' Contabilidade ', ' obs curta ', 'Campo contacto', '220999999', 0, 99999991),
       ('CRMT-K-02', 'CRMT-CL-01', 'Contacto com estab diferente', '', '', '', '', '', '', '', '', '', 5, 99999991),
       ('CRMT-K-03', 'CRMT-CL-02', 'Contacto do estabelecimento', '', '', '', '', '', '', '', '', '', 0, 99999991),
       ('CRMT-K-ORF', 'CRMT-SEM-FICHA', 'Orfão', '', '', '', '', '', '', '', '', '', 0, 0);
-- obs longa (text -> varchar(max))
UPDATE dbo.u_clcontact SET obs = REPLICATE(CONVERT(varchar(max), 'x'), 9000) WHERE u_clcontactstamp = 'CRMT-K-02';

-- V8: valores do contacto: ligação, trim, mapeamento de campos
SELECT @a = CONCAT_WS('|', stamp, accountStamp, accountCode, contactCode, name, title, mattersType, phoneOffice, phoneMobile, obs, email, department)
  FROM dbo.u_v_crm_contacto_cl WHERE stamp = 'CRMT-K-01';
INSERT @r (teste, ok, detalhe) VALUES ('V8 contacto: mapeamento e trim (nome, funcao->title, tipo->mattersType, telefone, tlmvl, obs, email, departamento)',
    CASE WHEN @a = 'CRMT-K-01|CRMT-CL-01|99999991-0|CRMT-K-01|Maria Teste|Gerente|Financeiro|220111111|910111111|obs curta|m@t.pt|Contabilidade' THEN 1 ELSE 0 END, @a);

-- V9: o estab do contacto é ignorado: liga à conta da ficha (clstamp)
SELECT @a = accountCode FROM dbo.u_v_crm_contacto_cl WHERE stamp = 'CRMT-K-02';
SELECT @b = accountCode FROM dbo.u_v_crm_contacto_cl WHERE stamp = 'CRMT-K-03';
INSERT @r (teste, ok, detalhe) VALUES ('V9 contacto com estab diferente liga à ficha do clstamp (99999991-0); contacto do estabelecimento liga a 99999991-1',
    CASE WHEN @a = '99999991-0' AND @b = '99999991-1' THEN 1 ELSE 0 END, CONCAT(@a, '|', @b));

-- V10: obs longa passa inteira (varchar(max))
SELECT @q = LEN(obs) FROM dbo.u_v_crm_contacto_cl WHERE stamp = 'CRMT-K-02';
INSERT @r (teste, ok, detalhe) VALUES ('V10 obs de 9000 caracteres passa inteira (varchar(max))', CASE WHEN @q = 9000 THEN 1 ELSE 0 END, CONCAT('LEN(obs)=', @q));
SELECT @q = CHARACTER_MAXIMUM_LENGTH FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'u_v_crm_contacto_cl' AND COLUMN_NAME = 'obs';
INSERT @r (teste, ok, detalhe) VALUES ('V10b coluna obs da view é varchar(max)', CASE WHEN @q = -1 THEN 1 ELSE 0 END, CONCAT('max_length=', @q));

-- V11: contacto órfão não aparece na view
SELECT @q = COUNT(*) FROM dbo.u_v_crm_contacto_cl WHERE stamp = 'CRMT-K-ORF';
INSERT @r (teste, ok, detalhe) VALUES ('V11 contacto órfão não aparece na view', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('linhas=', @q));

-- V12: a view de contas tem uma linha por ficha da CL (sem duplicar por causa do LEFT JOIN)
SELECT @q = COUNT(*) FROM dbo.u_v_crm_conta_cl;
INSERT @r (teste, ok, detalhe) VALUES ('V12 view de contas: uma linha por ficha CL (sem duplicados)', CASE WHEN @q = @nCl + 3 THEN 1 ELSE 0 END, CONCAT('view=', @q, ' esperado=', @nCl + 3));
SELECT @q = COUNT(*) FROM dbo.u_v_crm_contacto_cl;
INSERT @r (teste, ok, detalhe) VALUES ('V13 view de contactos: só contactos com ficha', CASE WHEN @q = @nContComFicha + 3 THEN 1 ELSE 0 END, CONCAT('view=', @q, ' esperado=', @nContComFicha + 3));

-- V14: o stamp da view liga à fila (mesmo valor que stamporigem)
SELECT @q = COUNT(*) FROM dbo.u_v_crm_conta_cl AS v JOIN dbo.u_crmfila AS f ON f.stamporigem = v.stamp AND f.entidade = 'CONTA' WHERE v.stamp = 'CRMT-CL-01';
INSERT @r (teste, ok, detalhe) VALUES ('V14 stamp da view liga à fila (stamporigem)', CASE WHEN @q >= 1 THEN 1 ELSE 0 END, CONCAT('ligações=', @q));

ROLLBACK TRAN;

SELECT @q = COUNT(*) FROM dbo.cl WHERE clstamp LIKE 'CRMT-%';
INSERT @r (teste, ok, detalhe) VALUES ('V15 rollback não deixa dados de teste', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('restos=', @q));

SELECT n, CASE ok WHEN 1 THEN 'OK' ELSE 'FALHOU' END AS resultado, teste, detalhe FROM @r ORDER BY n;
SELECT COUNT(*) AS total, SUM(CASE WHEN ok = 1 THEN 1 ELSE 0 END) AS ok, SUM(CASE WHEN ok = 0 THEN 1 ELSE 0 END) AS falhas FROM @r;
IF EXISTS (SELECT 1 FROM @r WHERE ok = 0) THROW 50099, N'Há asserts a falhar neste teste.', 1;
