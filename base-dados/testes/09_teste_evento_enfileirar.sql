-- =============================================================================
-- Teste SQL 09: sc_CrmEnfileirarEvento (o que os eventos do PHC chamam). SÓ NA LAND2_DEMO.
-- Substitui os testes de triggers (01, 02, 06, 07) depois de os tr_crm_* serem removidos.
-- Tudo numa transação com ROLLBACK no fim. Termina com THROW se algum assert falhar.
-- =============================================================================
SET NOCOUNT ON;
IF DB_NAME() <> N'LAND2_DEMO' THROW 50000, N'Este teste só pode correr na LAND2_DEMO.', 1;
IF EXISTS (SELECT 1 FROM sys.triggers WITH (NOLOCK) WHERE name LIKE 'tr[_]crm[_]%')
    THROW 50003, N'Ainda existem triggers tr_crm_* na base: remover primeiro (senão contam em dobro neste teste).', 1;
IF EXISTS (SELECT 1 FROM dbo.cl WITH (NOLOCK) WHERE no BETWEEN 99999991 AND 99999999)
    THROW 50002, N'Números de cliente de teste (99999991..99999999) já em uso.', 1;

DECLARE @r TABLE (n int IDENTITY(1,1), teste varchar(160), ok bit, detalhe varchar(300));
DECLARE @c1 char(25) = 'CRMT-EV-C1', @c2 char(25) = 'CRMT-EV-C2', @k1 char(25) = 'CRMT-EV-K1', @k2 char(25) = 'CRMT-EV-K2',
        @k3 char(25) = 'CRMT-EV-K3', @korf char(25) = 'CRMT-EV-KO';
DECLARE @q int, @t varchar(200);

BEGIN TRAN;

INSERT dbo.cl (clstamp, no, estab, nome, inactivo) VALUES (@c1, 99999991, 0, 'Cliente Ativo', 0), (@c2, 99999992, 0, 'Cliente Inativo', 1);
INSERT dbo.u_clcontact (u_clcontactstamp, clstamp, nome, email) VALUES (@k1, @c1, 'Pessoa 1', 'p1@teste.pt'), (@k2, @c1, 'Pessoa 2', 'p2@teste.pt');
INSERT dbo.u_clcontact (u_clcontactstamp, clstamp, nome, email, telefone, tlmvl) VALUES (@k3, @c1, 'Sem meio', '', '', '');
INSERT dbo.u_clcontact (u_clcontactstamp, clstamp, nome, email) VALUES (@korf, 'CRMT-EV-NAOEXISTE', 'Orfao', 'o@teste.pt');
DELETE dbo.u_crmfila WHERE stamporigem LIKE 'CRMT-EV-%';

-- E1: gravar ficha ativa -> CONTA PENDENTE (99999991-0) + os 2 contactos com meio (o sem meio não entra)
EXEC dbo.sc_CrmEnfileirarEvento @origem = 'CL', @stamp = @c1, @operacao = 'U', @no = 99999991, @estab = 0, @inactivo = 0;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = @c1 AND entidade = 'CONTA' AND estado = 'PENDENTE' AND operacao = 'U' AND RTRIM(codigo) = '99999991-0';
INSERT @r (teste, ok, detalhe) VALUES ('E1a gravar ficha ativa gera a CONTA PENDENTE com código NO-ESTAB', CASE WHEN @q = 1 THEN 1 ELSE 0 END, CONCAT('contas=', @q));
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem IN (@k1, @k2) AND entidade = 'CONTACTO' AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('E1b gravar a ficha reenfileira os contactos dela', CASE WHEN @q = 2 THEN 1 ELSE 0 END, CONCAT('contactos=', @q));

-- E2: gravar outra vez não duplica
EXEC dbo.sc_CrmEnfileirarEvento @origem = 'CL', @stamp = @c1, @operacao = 'U', @no = 99999991, @estab = 0, @inactivo = 0;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = @c1 AND entidade = 'CONTA' AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('E2 gravar duas vezes = 1 só PENDENTE (deduplicação)', CASE WHEN @q = 1 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- E3: ficha inativa nunca enviada não entra; inativa já enviada entra
EXEC dbo.sc_CrmEnfileirarEvento @origem = 'CL', @stamp = @c2, @operacao = 'U', @no = 99999992, @estab = 0, @inactivo = 1;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = @c2;
INSERT @r (teste, ok, detalhe) VALUES ('E3a ficha inativa nunca enviada NÃO entra', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('linhas=', @q));
INSERT dbo.u_crmfila (u_crmfilastamp, origem, entidade, tipoconta, stamporigem, codigo, operacao, estado, datacriacao)
VALUES ('CRMT-EV-Q1', 'CL', 'CONTA', 'CLI', @c2, '99999992-0', 'U', 'ENVIADO', GETDATE());
EXEC dbo.sc_CrmEnfileirarEvento @origem = 'CL', @stamp = @c2, @operacao = 'U', @no = 99999992, @estab = 0, @inactivo = 1;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = @c2 AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('E3b ficha inativa JÁ enviada entra (o CRM recebe "Inativo")', CASE WHEN @q = 1 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- E4: contacto sem meio nunca enviado não entra; com meio entra
EXEC dbo.sc_CrmEnfileirarEvento @origem = 'U_CLCONTACT', @stamp = @k3, @operacao = 'U', @clstamp = @c1, @temMeio = 0;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = @k3;
INSERT @r (teste, ok, detalhe) VALUES ('E4a contacto sem email/telefone/telemóvel nunca enviado NÃO entra', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('linhas=', @q));
EXEC dbo.sc_CrmEnfileirarEvento @origem = 'U_CLCONTACT', @stamp = @k3, @operacao = 'U', @clstamp = @c1, @temMeio = 1;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = @k3 AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('E4b contacto com meio de contacto entra', CASE WHEN @q = 1 THEN 1 ELSE 0 END, CONCAT('pendentes=', @q));

-- E5: contacto órfão (sem ficha CL) não entra
EXEC dbo.sc_CrmEnfileirarEvento @origem = 'U_CLCONTACT', @stamp = @korf, @operacao = 'U', @clstamp = 'CRMT-EV-NAOEXISTE', @temMeio = 1;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = @korf;
INSERT @r (teste, ok, detalhe) VALUES ('E5 contacto órfão NÃO entra', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('linhas=', @q));

-- E6: apagar contacto -> D PENDENTE (substitui o U pendente)
EXEC dbo.sc_CrmEnfileirarEvento @origem = 'U_CLCONTACT', @stamp = @k1, @operacao = 'D';
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = @k1 AND estado = 'PENDENTE' AND operacao = 'D';
INSERT @r (teste, ok, detalhe) VALUES ('E6 apagar contacto gera D PENDENTE', CASE WHEN @q = 1 THEN 1 ELSE 0 END, CONCAT('pendentes D=', @q));

-- E7: apagar ficha -> D PENDENTE (substitui o U pendente)
EXEC dbo.sc_CrmEnfileirarEvento @origem = 'CL', @stamp = @c1, @operacao = 'D', @no = 99999991, @estab = 0;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem = @c1 AND entidade = 'CONTA' AND estado = 'PENDENTE' AND operacao = 'D';
INSERT @r (teste, ok, detalhe) VALUES ('E7 apagar ficha gera D PENDENTE', CASE WHEN @q = 1 THEN 1 ELSE 0 END, CONCAT('pendentes D=', @q));

-- E8: nunca dá erro ao PHC (operação inválida, parâmetros em falta)
BEGIN TRY
    EXEC dbo.sc_CrmEnfileirarEvento @origem = 'CL', @stamp = @c1, @operacao = 'X';
    EXEC dbo.sc_CrmEnfileirarEvento @origem = 'CL', @stamp = @c1, @operacao = 'U';
    EXEC dbo.sc_CrmEnfileirarEvento @origem = 'ZZ', @stamp = @c1, @operacao = 'U';
    SET @t = 'sem erro';
END TRY
BEGIN CATCH
    SET @t = ERROR_MESSAGE();
END CATCH
INSERT @r (teste, ok, detalhe) VALUES ('E8 chamadas inválidas não devolvem erro ao PHC', CASE WHEN @t = 'sem erro' THEN 1 ELSE 0 END, @t);

ROLLBACK TRAN;

SELECT @q = COUNT(*) FROM dbo.u_crmfila WITH (NOLOCK) WHERE stamporigem LIKE 'CRMT-EV-%' OR u_crmfilastamp LIKE 'CRMT-EV-%';
INSERT @r (teste, ok, detalhe) VALUES ('E9 rollback não deixa restos na fila', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('restos=', @q));
SELECT @q = COUNT(*) FROM dbo.cl WITH (NOLOCK) WHERE clstamp LIKE 'CRMT-EV-%';
INSERT @r (teste, ok, detalhe) VALUES ('E10 rollback não deixa fichas de teste na CL', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('restos=', @q));

SELECT n, CASE ok WHEN 1 THEN 'OK' ELSE 'FALHOU' END AS resultado, teste, detalhe FROM @r ORDER BY n;
IF EXISTS (SELECT 1 FROM @r WHERE ok = 0) THROW 50099, N'Há asserts a falhar neste teste.', 1;
