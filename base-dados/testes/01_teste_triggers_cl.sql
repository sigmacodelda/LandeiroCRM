-- =============================================================================
-- Teste SQL 01: trigger tr_crm_cl (tabela CL). SÓ NA LAND2_DEMO.
-- Corre tudo dentro de uma transação e faz ROLLBACK no fim (não deixa dados).
-- Termina com THROW se algum assert falhar.
--   sqlcmd -S ... -d LAND2_DEMO -f 65001 -b -i testes/01_teste_triggers_cl.sql
-- =============================================================================
SET NOCOUNT ON;
IF DB_NAME() <> N'LAND2_DEMO' THROW 50000, N'Este teste só pode correr na LAND2_DEMO.', 1;
IF EXISTS (SELECT 1 FROM dbo.cl WHERE no BETWEEN 99999991 AND 99999999)
    THROW 50002, N'Números de cliente de teste (99999991..99999999) já em uso.', 1;

DECLARE @r TABLE (n int IDENTITY(1,1), teste varchar(160), ok bit, detalhe varchar(300));
DECLARE @s1 char(25) = 'CRMT-CL-01', @s2 char(25) = 'CRMT-CL-02', @s3 char(25) = 'CRMT-CL-03',
        @s4 char(25) = 'CRMT-CL-04', @s5 char(25) = 'CRMT-CL-05';
DECLARE @q int, @cod varchar(60), @op char(1), @org varchar(30);

BEGIN TRAN;

-- T1: criar ficha gera UMA conta PENDENTE (U), origem CL, código NO-ESTAB
INSERT dbo.cl (clstamp, no, estab, nome, morada) VALUES (@s1, 99999991, 0, 'Cliente Teste', 'Rua A');
SELECT @q = COUNT(*), @cod = MAX(codigo), @op = MAX(operacao), @org = MAX(origem)
  FROM dbo.u_crmfila WHERE stamporigem = @s1 AND entidade = 'CONTA' AND estado = 'PENDENTE' AND tipoconta = 'CLI';
INSERT @r (teste, ok, detalhe) VALUES ('T1 insert CL gera 1 CONTA PENDENTE U (CL, 99999991-0)',
    CASE WHEN @q = 1 AND @cod = '99999991-0' AND @op = 'U' AND @org = 'CL' THEN 1 ELSE 0 END,
    CONCAT('linhas=', @q, ' codigo=', @cod, ' op=', @op, ' origem=', @org));

-- T2: formato do stamp da fila = formato PHC (24 caracteres, CRM + yymmdd + hhmmss + vírgula + 8 dígitos)
INSERT @r (teste, ok, detalhe)
SELECT 'T2 stamp da fila no formato PHC (24 caracteres em char(25))',
       CASE WHEN LEN(u_crmfilastamp) = 24 AND DATALENGTH(u_crmfilastamp) = 25
             AND RTRIM(u_crmfilastamp) LIKE 'CRM[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9],[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
            THEN 1 ELSE 0 END, '[' + u_crmfilastamp + ']'
  FROM dbo.u_crmfila WHERE stamporigem = @s1;

-- T3: alterar um campo integrado (nome) depois de enviado gera novo PENDENTE
UPDATE dbo.u_crmfila SET estado = 'ENVIADO' WHERE stamporigem = @s1;
UPDATE dbo.cl SET nome = 'Cliente Teste Alterado' WHERE clstamp = @s1;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WHERE stamporigem = @s1 AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('T3 update de campo integrado (nome) gera PENDENTE', CASE WHEN @q = 1 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- T4: UPDATE de todas as colunas SEM alterações nos campos integrados NÃO gera fila (comportamento do PHC)
UPDATE dbo.u_crmfila SET estado = 'ENVIADO' WHERE stamporigem = @s1;
UPDATE dbo.cl SET nome = nome, morada = morada, codpost = codpost, local = local, ncont = ncont,
                  telefone = telefone, tlmvl = tlmvl, email = email, fax = fax, no = no, estab = estab
 WHERE clstamp = @s1;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WHERE stamporigem = @s1 AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('T4 update sem mudança nos campos integrados NÃO gera fila', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- T5: alterar campos NÃO integrados (contacto, obs, tipo) NÃO gera fila
UPDATE dbo.cl SET contacto = 'Outra pessoa', obs = 'observação interna', tipo = 'Retalho' WHERE clstamp = @s1;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WHERE stamporigem = @s1 AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('T5 update de campos não integrados NÃO gera fila', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- T6: alterar o saldo (esaldo) NÃO gera fila (processo do PHC ao lançar documentos)
UPDATE dbo.cl SET esaldo = esaldo + 123.45 WHERE clstamp = @s1;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WHERE stamporigem = @s1 AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('T6 alteração de saldo NÃO gera fila', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- T7: só espaços no fim do texto NÃO conta como alteração
UPDATE dbo.cl SET nome = RTRIM(nome) + '   ' WHERE clstamp = @s1;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WHERE stamporigem = @s1 AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('T7 espaços no fim NÃO geram fila', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- T8: mudar só maiúsculas/acentos GERA fila (comparação binária)
UPDATE dbo.cl SET nome = 'CLIENTE TESTE ALTERADO' WHERE clstamp = @s1;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WHERE stamporigem = @s1 AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('T8 mudança só de maiúsculas gera PENDENTE', CASE WHEN @q = 1 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- T9: deduplicação: várias alterações enquanto está PENDENTE não criam outro registo
UPDATE dbo.cl SET morada = 'Rua B' WHERE clstamp = @s1;
UPDATE dbo.cl SET email = 'a@b.pt' WHERE clstamp = @s1;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WHERE stamporigem = @s1 AND entidade = 'CONTA' AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('T9 deduplicação: 3 alterações = 1 PENDENTE', CASE WHEN @q = 1 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- T10: várias linhas de uma vez (INSERT de 3 fichas num só comando)
INSERT dbo.cl (clstamp, no, estab, nome)
VALUES (@s2, 99999992, 0, 'Teste 2'), (@s3, 99999993, 0, 'Teste 3'), (@s4, 99999994, 0, 'Teste 4');
SELECT @q = COUNT(*) FROM dbo.u_crmfila WHERE stamporigem IN (@s2, @s3, @s4) AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('T10 INSERT de 3 linhas gera 3 PENDENTE', CASE WHEN @q = 3 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- T11: UPDATE de várias linhas de uma vez (só 2 das 3 mudam o campo integrado)
UPDATE dbo.u_crmfila SET estado = 'ENVIADO' WHERE stamporigem IN (@s2, @s3, @s4);
UPDATE dbo.cl SET nome = CASE clstamp WHEN @s2 THEN 'Mudou 2' WHEN @s3 THEN 'Mudou 3' ELSE nome END
 WHERE clstamp IN (@s2, @s3, @s4);
SELECT @q = COUNT(*) FROM dbo.u_crmfila WHERE stamporigem IN (@s2, @s3, @s4) AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('T11 UPDATE de 3 linhas, 2 alteradas = 2 PENDENTE', CASE WHEN @q = 2 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- T12: estabelecimento (estab > 0) gera conta com código NO-ESTAB
INSERT dbo.cl (clstamp, no, estab, nome) VALUES (@s5, 99999991, 1, 'Estabelecimento 1 do 99999991');
SELECT @q = COUNT(*), @cod = MAX(codigo) FROM dbo.u_crmfila WHERE stamporigem = @s5 AND entidade = 'CONTA' AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('T12 estabelecimento gera conta 99999991-1', CASE WHEN @q = 1 AND @cod = '99999991-1' THEN 1 ELSE 0 END, CONCAT('linhas=', @q, ' codigo=', @cod));

-- T13: eliminar uma ficha sem pendente gera operação D, com o código gravado
UPDATE dbo.u_crmfila SET estado = 'ENVIADO' WHERE stamporigem = @s4;
DELETE dbo.cl WHERE clstamp = @s4;
SELECT @q = COUNT(*), @cod = MAX(codigo), @op = MAX(operacao)
  FROM dbo.u_crmfila WHERE stamporigem = @s4 AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('T13 DELETE gera D PENDENTE com código 99999994-0', CASE WHEN @q = 1 AND @cod = '99999994-0' AND @op = 'D' THEN 1 ELSE 0 END, CONCAT('linhas=', @q, ' codigo=', @cod, ' op=', @op));

-- T14: eliminar uma ficha com U pendente substitui o U (fica só um registo, D)
SELECT @q = COUNT(*) FROM dbo.u_crmfila WHERE stamporigem = @s3 AND estado = 'PENDENTE' AND operacao = 'U';
INSERT @r (teste, ok, detalhe) VALUES ('T14a pré-condição: ficha 3 tem U pendente', CASE WHEN @q = 1 THEN 1 ELSE 0 END, CONCAT('pendentes U=', @q));
DELETE dbo.cl WHERE clstamp = @s3;
SELECT @q = COUNT(*), @op = MAX(operacao) FROM dbo.u_crmfila WHERE stamporigem = @s3 AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('T14b DELETE substitui o U pendente (1 registo, D)', CASE WHEN @q = 1 AND @op = 'D' THEN 1 ELSE 0 END, CONCAT('pendentes=', @q, ' op=', @op));

-- T15: DELETE de várias linhas de uma vez
UPDATE dbo.u_crmfila SET estado = 'ENVIADO' WHERE stamporigem IN (@s1, @s2, @s5);
DELETE dbo.cl WHERE clstamp IN (@s1, @s2, @s5);
SELECT @q = COUNT(*) FROM dbo.u_crmfila WHERE stamporigem IN (@s1, @s2, @s5) AND estado = 'PENDENTE' AND operacao = 'D';
INSERT @r (teste, ok, detalhe) VALUES ('T15 DELETE de 3 linhas gera 3 D PENDENTE', CASE WHEN @q = 3 THEN 1 ELSE 0 END, CONCAT('pendentes D=', @q));

-- T16: estados diferentes de PENDENTE nunca são alterados pelo trigger
-- (o histórico ENVIADO mantém-se e nenhum ENVIADO foi transformado em eliminação)
SELECT @q = COUNT(*) FROM dbo.u_crmfila WHERE stamporigem IN (@s1, @s2, @s5) AND estado = 'ENVIADO' AND operacao = 'U';
INSERT @r (teste, ok, detalhe) VALUES ('T16a registos ENVIADO (U) mantêm-se como histórico', CASE WHEN @q >= 3 THEN 1 ELSE 0 END, CONCAT('enviados U=', @q));
SELECT @q = COUNT(*) FROM dbo.u_crmfila WHERE stamporigem IN (@s1, @s2, @s5) AND estado = 'ENVIADO' AND operacao = 'D';
INSERT @r (teste, ok, detalhe) VALUES ('T16b nenhum ENVIADO foi convertido em D', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('enviados D=', @q));

ROLLBACK TRAN;

-- Depois do rollback não pode sobrar nada
SELECT @q = COUNT(*) FROM dbo.u_crmfila WHERE stamporigem LIKE 'CRMT-%';
INSERT @r (teste, ok, detalhe) VALUES ('T17 rollback não deixa dados de teste na fila', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('restos=', @q));
SELECT @q = COUNT(*) FROM dbo.cl WHERE clstamp LIKE 'CRMT-%';
INSERT @r (teste, ok, detalhe) VALUES ('T18 rollback não deixa fichas de teste na CL', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('restos=', @q));

SELECT n, CASE ok WHEN 1 THEN 'OK' ELSE 'FALHOU' END AS resultado, teste, detalhe FROM @r ORDER BY n;
SELECT COUNT(*) AS total, SUM(CASE WHEN ok = 1 THEN 1 ELSE 0 END) AS ok, SUM(CASE WHEN ok = 0 THEN 1 ELSE 0 END) AS falhas FROM @r;
IF EXISTS (SELECT 1 FROM @r WHERE ok = 0) THROW 50099, N'Há asserts a falhar neste teste.', 1;
