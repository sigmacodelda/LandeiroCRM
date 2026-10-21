-- =============================================================================
-- Teste SQL 02: triggers tr_crm_cl2 (CL2) e tr_crm_u_clcontact (U_CLCONTACT). SÓ NA LAND2_DEMO.
-- Tudo numa transação com ROLLBACK no fim. Termina com THROW se algum assert falhar.
-- =============================================================================
SET NOCOUNT ON;
IF DB_NAME() <> N'LAND2_DEMO' THROW 50000, N'Este teste só pode correr na LAND2_DEMO.', 1;
IF EXISTS (SELECT 1 FROM dbo.cl WITH (NOLOCK) WHERE no BETWEEN 99999991 AND 99999999)
    THROW 50002, N'Números de cliente de teste (99999991..99999999) já em uso.', 1;

DECLARE @r TABLE (n int IDENTITY(1,1), teste varchar(160), ok bit, detalhe varchar(300));
DECLARE @c1 char(25) = 'CRMT-CL-01', @c2 char(25) = 'CRMT-CL-02', @c3 char(25) = 'CRMT-CL-03';
DECLARE @k1 char(25) = 'CRMT-K-01', @k2 char(25) = 'CRMT-K-02', @k3 char(25) = 'CRMT-K-03', @k4 char(25) = 'CRMT-K-04',
        @korf char(25) = 'CRMT-K-ORF', @orf2 char(25) = 'CRMT-CL2-ORF';
DECLARE @q int, @cod varchar(60), @op char(1), @org varchar(30), @ent varchar(10);

BEGIN TRAN;

-- Fichas base: s1 com CL2 (país Portugal), c2 sem CL2
INSERT dbo.cl (clstamp, no, estab, nome) VALUES (@c1, 99999991, 0, 'Cliente 1'), (@c2, 99999992, 0, 'Cliente 2'), (@c3, 99999993, 1, 'Estab 1');
INSERT dbo.cl2 (cl2stamp, descpais) VALUES (@c1, 'Portugal');
UPDATE dbo.u_crmfila SET estado = 'ENVIADO' WHERE stamporigem IN (@c1, @c2, @c3);

-- ===== CL2 =====
-- C1: mudar só o país (CL2) gera CONTA com origem CL2
UPDATE dbo.cl2 SET descpais = 'Espanha' WHERE cl2stamp = @c1;
SELECT @q = COUNT(*), @org = MAX(origem), @cod = MAX(codigo), @ent = MAX(entidade)
  FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = @c1 AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('C1 mudar só o país (CL2) gera CONTA com origem CL2 (código 99999991-0)',
    CASE WHEN @q = 1 AND @org = 'CL2' AND @cod = '99999991-0' AND @ent = 'CONTA' THEN 1 ELSE 0 END, CONCAT('linhas=', @q, ' origem=', @org, ' codigo=', @cod));

-- C2: UPDATE da CL2 sem mudar o país não gera fila
UPDATE dbo.u_crmfila SET estado = 'ENVIADO' WHERE stamporigem = @c1;
UPDATE dbo.cl2 SET descpais = descpais WHERE cl2stamp = @c1;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = @c1 AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('C2 UPDATE da CL2 sem mudança NÃO gera fila', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- C3: campo da CL2 não integrado (ousrinis) não gera fila
UPDATE dbo.cl2 SET ousrinis = 'xx' WHERE cl2stamp = @c1;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = @c1 AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('C3 campo não integrado da CL2 NÃO gera fila', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- C4: o PHC grava CL e CL2 na mesma operação: a deduplicação deixa só 1 PENDENTE
INSERT dbo.cl (clstamp, no, estab, nome) VALUES ('CRMT-CL-09', 99999999, 0, 'Novo cliente');
INSERT dbo.cl2 (cl2stamp, descpais) VALUES ('CRMT-CL-09', 'França');
SELECT @q = COUNT(*), @org = MAX(origem) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = 'CRMT-CL-09' AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('C4 CL + CL2 gravadas juntas = 1 só PENDENTE (sem envio a dobrar)', CASE WHEN @q = 1 AND @org = 'CL' THEN 1 ELSE 0 END, CONCAT('linhas=', @q, ' origem=', @org));

-- C5: CL2 órfã (sem CL) não gera nada
INSERT dbo.cl2 (cl2stamp, descpais) VALUES (@orf2, 'Orfã');
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = @orf2;
INSERT @r (teste, ok, detalhe) VALUES ('C5 CL2 órfã (sem CL) NÃO gera fila', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('linhas=', @q));

-- C6: várias CL2 de uma vez
UPDATE dbo.u_crmfila SET estado = 'ENVIADO' WHERE stamporigem IN (@c1, @c2, 'CRMT-CL-09');
INSERT dbo.cl2 (cl2stamp, descpais) VALUES (@c2, 'Itália');
UPDATE dbo.cl2 SET descpais = 'Alemanha' WHERE cl2stamp IN (@c1, @c2, 'CRMT-CL-09');
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem IN (@c1, @c2, 'CRMT-CL-09') AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('C6 UPDATE de 3 linhas da CL2 gera 3 PENDENTE', CASE WHEN @q = 3 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- ===== U_CLCONTACT =====
UPDATE dbo.u_crmfila SET estado = 'ENVIADO' WHERE estado = 'PENDENTE' AND stamporigem LIKE 'CRMT-%';

-- K1: criar contacto gera CONTACTO PENDENTE, código = stamp
INSERT dbo.u_clcontact (u_clcontactstamp, clstamp, nome, funcao, email) VALUES (@k1, @c1, 'Pessoa 1', 'Gerente', 'p1@teste.pt');
SELECT @q = COUNT(*), @cod = MAX(codigo), @org = MAX(origem), @op = MAX(operacao)
  FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = @k1 AND entidade = 'CONTACTO' AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('K1 insert de contacto gera CONTACTO PENDENTE (código = stamp)',
    CASE WHEN @q = 1 AND @cod = 'CRMT-K-01' AND @org = 'U_CLCONTACT' AND @op = 'U' THEN 1 ELSE 0 END, CONCAT('linhas=', @q, ' codigo=', @cod, ' origem=', @org));

-- K2: alterar campo integrado (nome)
UPDATE dbo.u_crmfila SET estado = 'ENVIADO' WHERE stamporigem = @k1;
UPDATE dbo.u_clcontact SET nome = 'Pessoa 1 Alterada' WHERE u_clcontactstamp = @k1;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = @k1 AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('K2 alterar nome do contacto gera PENDENTE', CASE WHEN @q = 1 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- K3: cada campo integrado gera fila: funcao, tipo, telefone, tlmvl, email, departamento
DECLARE @i int = 0, @falhou varchar(200) = '';
DECLARE @cols TABLE (n int IDENTITY(1,1), col varchar(30));
INSERT @cols (col) VALUES ('funcao'), ('tipo'), ('telefone'), ('tlmvl'), ('email'), ('departamento');
DECLARE @col varchar(30), @sql nvarchar(400);
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT col FROM @cols ORDER BY n;
OPEN cur; FETCH NEXT FROM cur INTO @col;
WHILE @@FETCH_STATUS = 0
BEGIN
    UPDATE dbo.u_crmfila SET estado = 'ENVIADO' WHERE stamporigem = @k1;
    SET @sql = N'UPDATE dbo.u_clcontact SET ' + QUOTENAME(@col) + N' = ''novo valor'' WHERE u_clcontactstamp = @s';
    EXEC sp_executesql @sql, N'@s char(25)', @s = @k1;
    SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = @k1 AND estado = 'PENDENTE';
    IF @q <> 1 SET @falhou += @col + ' ';
    FETCH NEXT FROM cur INTO @col;
END
CLOSE cur; DEALLOCATE cur;
INSERT @r (teste, ok, detalhe) VALUES ('K3 cada campo integrado (funcao, tipo, telefone, tlmvl, email, departamento) gera PENDENTE',
    CASE WHEN @falhou = '' THEN 1 ELSE 0 END, CONCAT('campos que falharam: ', NULLIF(@falhou, '')));

-- K4: campos NÃO integrados (fax, estab, no) não geram fila (o campo contacto passou a ser integrado: ver teste 07)
UPDATE dbo.u_crmfila SET estado = 'ENVIADO' WHERE stamporigem = @k1;
UPDATE dbo.u_clcontact SET fax = '999', estab = 7, no = 12345 WHERE u_clcontactstamp = @k1;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = @k1 AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('K4 alterar fax/estab/no NÃO gera fila', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- K5: UPDATE sem mudanças nos campos integrados (e sem tocar na obs) não gera fila
UPDATE dbo.u_clcontact SET nome = nome, funcao = funcao, tipo = tipo, telefone = telefone, tlmvl = tlmvl,
                           email = email, departamento = departamento, clstamp = clstamp, contacto = contacto
 WHERE u_clcontactstamp = @k1;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = @k1 AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('K5 UPDATE sem mudanças NÃO gera fila', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- K6: alterar a observação (text) gera fila (via UPDATE(obs), ver comentário no trigger)
UPDATE dbo.u_clcontact SET obs = 'Nova observação' WHERE u_clcontactstamp = @k1;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = @k1 AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('K6 alterar a observação (text) gera PENDENTE', CASE WHEN @q = 1 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- K7: mudar o contacto para outra ficha (clstamp) gera fila
UPDATE dbo.u_crmfila SET estado = 'ENVIADO' WHERE stamporigem = @k1;
UPDATE dbo.u_clcontact SET clstamp = @c2 WHERE u_clcontactstamp = @k1;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = @k1 AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('K7 mudar a ficha (clstamp) do contacto gera PENDENTE', CASE WHEN @q = 1 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- K8: contacto órfão (clstamp sem ficha) não é enfileirado
INSERT dbo.u_clcontact (u_clcontactstamp, clstamp, nome) VALUES (@korf, 'CRMT-SEM-FICHA', 'Órfão');
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = @korf;
INSERT @r (teste, ok, detalhe) VALUES ('K8 contacto órfão NÃO é enfileirado', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('linhas=', @q));

-- K9: várias linhas de uma vez (insert de 3 contactos; update de 3)
INSERT dbo.u_clcontact (u_clcontactstamp, clstamp, nome, email)
VALUES (@k2, @c1, 'P2', 'p2@teste.pt'), (@k3, @c1, 'P3', 'p3@teste.pt'), (@k4, @c3, 'P4', 'p4@teste.pt');
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem IN (@k2, @k3, @k4) AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('K9a INSERT de 3 contactos gera 3 PENDENTE', CASE WHEN @q = 3 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));
UPDATE dbo.u_crmfila SET estado = 'ENVIADO' WHERE stamporigem IN (@k2, @k3, @k4);
UPDATE dbo.u_clcontact SET nome = nome + ' (alt)' WHERE u_clcontactstamp IN (@k2, @k3, @k4);
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem IN (@k2, @k3, @k4) AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('K9b UPDATE de 3 contactos gera 3 PENDENTE', CASE WHEN @q = 3 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- K10: eliminar contacto gera D com o código; eliminar com U pendente substitui-o
UPDATE dbo.u_crmfila SET estado = 'ENVIADO' WHERE stamporigem = @k2;
DELETE dbo.u_clcontact WHERE u_clcontactstamp = @k2;
SELECT @q = COUNT(*), @cod = MAX(codigo), @op = MAX(operacao) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = @k2 AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('K10a DELETE de contacto gera D PENDENTE com contactCode|accountCode', CASE WHEN @q = 1 AND @op = 'D' AND @cod = 'CRMT-K-02|99999991-0' THEN 1 ELSE 0 END, CONCAT('linhas=', @q, ' op=', @op, ' codigo=', @cod));
DELETE dbo.u_clcontact WHERE u_clcontactstamp = @k3;     -- @k3 tinha um U pendente
SELECT @q = COUNT(*), @op = MAX(operacao) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = @k3 AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('K10b DELETE substitui o U pendente do contacto (1 registo, D)', CASE WHEN @q = 1 AND @op = 'D' THEN 1 ELSE 0 END, CONCAT('linhas=', @q, ' op=', @op));

ROLLBACK TRAN;

SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem LIKE 'CRMT-%';
INSERT @r (teste, ok, detalhe) VALUES ('K11 rollback não deixa dados de teste na fila', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('restos=', @q));

SELECT n, CASE ok WHEN 1 THEN 'OK' ELSE 'FALHOU' END AS resultado, teste, detalhe FROM @r ORDER BY n;
SELECT COUNT(*) AS total, SUM(CASE WHEN ok = 1 THEN 1 ELSE 0 END) AS ok, SUM(CASE WHEN ok = 0 THEN 1 ELSE 0 END) AS falhas FROM @r;
IF EXISTS (SELECT 1 FROM @r WHERE ok = 0) THROW 50099, N'Há asserts a falhar neste teste.', 1;
