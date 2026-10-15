-- =============================================================================
-- Teste SQL 04: carga (1 a 1 e total), reposição e consultas. SÓ NA LAND2_DEMO.
-- Tudo numa transação com ROLLBACK no fim. Termina com THROW se algum assert falhar.
-- =============================================================================
SET NOCOUNT ON;
IF DB_NAME() <> N'LAND2_DEMO' THROW 50000, N'Este teste só pode correr na LAND2_DEMO.', 1;

DECLARE @r TABLE (n int IDENTITY(1,1), teste varchar(160), ok bit, detalhe varchar(400));
DECLARE @res TABLE (a int, b int);
DECLARE @rep TABLE (repostos int, ignorados int);
DECLARE @q int, @a int, @b int, @txt varchar(300), @expC int, @expK int;

BEGIN TRAN;

-- Começa com a fila limpa de pendentes (dentro da transação, para os totais serem determinísticos)
UPDATE dbo.u_crmfila SET estado = 'ENVIADO' WHERE estado = 'PENDENTE';

-- ===== CARGA 1 A 1 (cliente 13444) =====
-- O histórico do 13444 pode já ter registos de testes anteriores: guarda quantos há antes da carga
DECLARE @h TABLE (datacriacao datetime, entidade varchar(10), origem varchar(30), codigo varchar(60), operacao char(1), estado varchar(15),
                  tentativas int, acaocrm varchar(30), idcrm varchar(60), dataenvio datetime, ultimamensagem varchar(500), u_crmfilastamp char(25));
DECLARE @histAntes int;
INSERT @h EXEC dbo.up_crm_consulta_historico @no = 13444;
SELECT @histAntes = COUNT(*) FROM @h;
DELETE @h;
SELECT @expC = COUNT(*) FROM dbo.cl AS c WHERE c.no = 13444 AND (c.inactivo = 0 OR EXISTS (SELECT 1 FROM dbo.u_crmfila AS f WHERE f.entidade = 'CONTA' AND f.estado = 'ENVIADO' AND f.stamporigem = c.clstamp));
SELECT @expK = COUNT(*) FROM dbo.u_clcontact k JOIN dbo.cl c ON c.clstamp = k.clstamp WHERE c.no = 13444 AND (c.inactivo = 0 OR EXISTS (SELECT 1 FROM dbo.u_crmfila AS f WHERE f.entidade = 'CONTA' AND f.estado = 'ENVIADO' AND f.stamporigem = c.clstamp));
INSERT @res EXEC dbo.up_crm_carga @origem = 'CL', @no = 13444;
SELECT @a = a, @b = b FROM @res;
INSERT @r (teste, ok, detalhe) VALUES ('L1 carga do cliente 13444 enfileira todas as suas fichas e contactos',
    CASE WHEN @a = @expC AND @b = @expK AND @expC >= 1 THEN 1 ELSE 0 END, CONCAT('contas=', @a, '/', @expC, ' contactos=', @b, '/', @expK));

SELECT @q = COUNT(*) FROM dbo.u_crmfila WHERE estado = 'PENDENTE' AND entidade = 'CONTA' AND codigo LIKE '13444-%';
INSERT @r (teste, ok, detalhe) VALUES ('L2 as contas do 13444 têm código NO-ESTAB (13444-0, ...)', CASE WHEN @q = @expC THEN 1 ELSE 0 END, CONCAT('contas=', @q));

SELECT @q = COUNT(*) FROM dbo.u_crmfila WHERE estado = 'PENDENTE' AND (entidade = 'CONTA' AND origem <> 'CL' OR entidade = 'CONTACTO' AND origem <> 'U_CLCONTACT');
INSERT @r (teste, ok, detalhe) VALUES ('L3 a carga indica a tabela de origem em todos os registos', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('sem origem correta=', @q));

-- L4: repetir a carga não duplica
DELETE @res;
INSERT @res EXEC dbo.up_crm_carga @origem = 'CL', @no = 13444;
SELECT @a = a, @b = b FROM @res;
INSERT @r (teste, ok, detalhe) VALUES ('L4 repetir a carga não duplica (deduplicação)', CASE WHEN @a = 0 AND @b = 0 THEN 1 ELSE 0 END, CONCAT('contas=', @a, ' contactos=', @b));

-- L5: origem não suportada dá erro
BEGIN TRY
    INSERT @res EXEC dbo.up_crm_carga @origem = 'FL';
    SET @txt = 'sem erro';
END TRY
BEGIN CATCH
    SET @txt = ERROR_MESSAGE();
END CATCH
INSERT @r (teste, ok, detalhe) VALUES ('L5 origem não suportada (FL) devolve erro', CASE WHEN @txt LIKE '%origem não suportada%' THEN 1 ELSE 0 END, @txt);

-- L6: o histórico do cliente passa a ter mais as contas e os contactos enfileirados
INSERT @h EXEC dbo.up_crm_consulta_historico @no = 13444;
SELECT @q = COUNT(*) FROM @h;
INSERT @r (teste, ok, detalhe) VALUES ('L6 histórico do 13444 devolve as contas + contactos acabados de enfileirar',
    CASE WHEN @q = @histAntes + @expC + @expK THEN 1 ELSE 0 END, CONCAT('linhas=', @q, ' esperado=', @histAntes + @expC + @expK));

-- ===== CARGA TOTAL =====
UPDATE dbo.u_crmfila SET estado = 'ENVIADO' WHERE estado = 'PENDENTE';
SELECT @expC = COUNT(*) FROM dbo.cl AS c WHERE (c.inactivo = 0 OR EXISTS (SELECT 1 FROM dbo.u_crmfila AS f WHERE f.entidade = 'CONTA' AND f.estado = 'ENVIADO' AND f.stamporigem = c.clstamp));
SELECT @expK = COUNT(*) FROM dbo.u_clcontact k JOIN dbo.cl c ON c.clstamp = k.clstamp WHERE (c.inactivo = 0 OR EXISTS (SELECT 1 FROM dbo.u_crmfila AS f WHERE f.entidade = 'CONTA' AND f.estado = 'ENVIADO' AND f.stamporigem = c.clstamp));
DELETE @res;
INSERT @res EXEC dbo.up_crm_carga @origem = 'CL';
SELECT @a = a, @b = b FROM @res;
INSERT @r (teste, ok, detalhe) VALUES ('L7 carga total: fichas ativas (ou já enviadas) e os seus contactos (sem órfãos)',
    CASE WHEN @a = @expC AND @b = @expK THEN 1 ELSE 0 END, CONCAT('contas=', @a, '/', @expC, ' contactos=', @b, '/', @expK));
DELETE @res;
INSERT @res EXEC dbo.up_crm_carga @origem = 'CL';
SELECT @a = a, @b = b FROM @res;
INSERT @r (teste, ok, detalhe) VALUES ('L8 repetir a carga total não duplica', CASE WHEN @a = 0 AND @b = 0 THEN 1 ELSE 0 END, CONCAT('contas=', @a, ' contactos=', @b));

-- ===== REPOSIÇÃO =====
-- Limpa tudo e monta uma fila de teste à mão
DELETE dbo.u_crmfila;
INSERT dbo.u_crmfila (u_crmfilastamp, origem, entidade, tipoconta, stamporigem, codigo, operacao, estado, ultimamensagem, datacriacao)
VALUES ('CRMT-Q-01', 'CL',          'CONTA',    'CLI', 'CRMT-A', '1-0',       'U', 'ERRO',      'falha 1', '2026-01-01 10:00'),
       ('CRMT-Q-02', 'U_CLCONTACT', 'CONTACTO', 'CLI', 'CRMT-B', 'CRMT-B',    'U', 'ERRO',      'falha 2', '2026-01-01 10:00'),
       ('CRMT-Q-03', 'CL',          'CONTA',    'CLI', 'CRMT-C', '3-0',       'U', 'ERRO',      'falha 3', '2026-01-01 10:00'),
       ('CRMT-Q-04', 'CL',          'CONTA',    'CLI', 'CRMT-D', '4-0',       'U', 'ERRO',      'falha 4', '2026-01-01 10:00'),
       ('CRMT-Q-05', 'CL',          'CONTA',    'CLI', 'CRMT-D', '4-0',       'U', 'PENDENTE',  '',        '2026-01-02 10:00'),
       ('CRMT-Q-06', 'CL',          'CONTA',    'CLI', 'CRMT-E', '5-0',       'U', 'ENVIADO',   '',        '2026-01-01 10:00'),
       ('CRMT-Q-07', 'CL',          'CONTA',    'CLI', 'CRMT-F', '6-0',       'D', 'SEM_ENVIO', '',        '2026-01-01 10:00'),
       ('CRMT-Q-08', 'CL',          'CONTA',    'CLI', 'CRMT-G', '7-0',       'U', 'ERRO',      'falha 8', '2026-01-01 10:00'),
       ('CRMT-Q-09', 'CL2',         'CONTA',    'CLI', 'CRMT-H', '8-0',       'U', 'ERRO',      'falha 9', '2026-01-01 10:00'),
       ('CRMT-Q-10', 'CL',          'CONTA',    'CLI', 'CRMT-I', '9-0',       'U', 'ERRO',      'falha antiga', '2026-01-01 10:00'),
       ('CRMT-Q-11', 'CL',          'CONTA',    'CLI', 'CRMT-I', '9-0',       'U', 'ERRO',      'falha recente', '2026-02-01 10:00');

-- R1: filtrar por código repõe só esse registo
INSERT @rep EXEC dbo.up_crm_repor @codigo = '1-0';
SELECT @a = repostos FROM @rep;
SELECT @q = COUNT(*) FROM dbo.u_crmfila WHERE u_crmfilastamp = 'CRMT-Q-01' AND estado = 'PENDENTE';
SELECT @b = COUNT(*) FROM dbo.u_crmfila WHERE u_crmfilastamp IN ('CRMT-Q-02', 'CRMT-Q-03') AND estado = 'ERRO';
INSERT @r (teste, ok, detalhe) VALUES ('R1 filtrar por código repõe só esse registo', CASE WHEN @a = 1 AND @q = 1 AND @b = 2 THEN 1 ELSE 0 END, CONCAT('repostos=', @a));

-- R2: a mensagem de erro anterior fica guardada
SELECT @txt = ultimamensagem FROM dbo.u_crmfila WHERE u_crmfilastamp = 'CRMT-Q-01';
INSERT @r (teste, ok, detalhe) VALUES ('R2 a mensagem do erro anterior fica registada', CASE WHEN @txt = 'Reposto manualmente. Erro anterior: falha 1' THEN 1 ELSE 0 END, @txt);

-- R3: filtrar por entidade
DELETE @rep;
INSERT @rep EXEC dbo.up_crm_repor @entidade = 'CONTACTO';
SELECT @q = COUNT(*) FROM dbo.u_crmfila WHERE u_crmfilastamp = 'CRMT-Q-02' AND estado = 'PENDENTE';
SELECT @b = COUNT(*) FROM dbo.u_crmfila WHERE u_crmfilastamp = 'CRMT-Q-03' AND estado = 'ERRO';
INSERT @r (teste, ok, detalhe) VALUES ('R3 filtrar por entidade CONTACTO', CASE WHEN @q = 1 AND @b = 1 THEN 1 ELSE 0 END, CONCAT('pendente=', @q, ' erro=', @b));

-- R4: filtrar pelo stamp de origem e pelo stamp da fila
DELETE @rep;
INSERT @rep EXEC dbo.up_crm_repor @stamp = 'CRMT-C';
SELECT @q = COUNT(*) FROM dbo.u_crmfila WHERE u_crmfilastamp = 'CRMT-Q-03' AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('R4a filtrar pelo stamp de origem', CASE WHEN @q = 1 THEN 1 ELSE 0 END, CONCAT('pendente=', @q));
DELETE @rep;
INSERT @rep EXEC dbo.up_crm_repor @stamp = 'CRMT-Q-08';
SELECT @q = COUNT(*) FROM dbo.u_crmfila WHERE u_crmfilastamp = 'CRMT-Q-08' AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('R4b filtrar pelo stamp da fila', CASE WHEN @q = 1 THEN 1 ELSE 0 END, CONCAT('pendente=', @q));

-- R5: filtrar por origem
DELETE @rep;
INSERT @rep EXEC dbo.up_crm_repor @origem = 'CL2';
SELECT @q = COUNT(*) FROM dbo.u_crmfila WHERE u_crmfilastamp = 'CRMT-Q-09' AND estado = 'PENDENTE';
INSERT @r (teste, ok, detalhe) VALUES ('R5 filtrar por origem CL2', CASE WHEN @q = 1 THEN 1 ELSE 0 END, CONCAT('pendente=', @q));

-- R6: sem filtros: não repõe quem já tem PENDENTE do mesmo registo (CRMT-D) e repõe só o ERRO mais recente (CRMT-I)
DELETE @rep;
INSERT @rep EXEC dbo.up_crm_repor;
SELECT @a = repostos, @b = ignorados FROM @rep;
INSERT @r (teste, ok, detalhe) VALUES ('R6a sem filtros: repõe só o que falta (CRMT-I) e ignora o que já tem pendente (CRMT-D)',
    CASE WHEN @a = 1 AND @b = 1 THEN 1 ELSE 0 END, CONCAT('repostos=', @a, ' ignorados=', @b));
SELECT @q = COUNT(*) FROM dbo.u_crmfila WHERE u_crmfilastamp = 'CRMT-Q-11' AND estado = 'PENDENTE';
SELECT @b = COUNT(*) FROM dbo.u_crmfila WHERE u_crmfilastamp = 'CRMT-Q-10' AND estado = 'ERRO';
INSERT @r (teste, ok, detalhe) VALUES ('R6b com dois ERRO do mesmo registo repõe só o mais recente', CASE WHEN @q = 1 AND @b = 1 THEN 1 ELSE 0 END, CONCAT('recente pendente=', @q, ' antigo erro=', @b));
SELECT @q = COUNT(*) FROM dbo.u_crmfila WHERE u_crmfilastamp = 'CRMT-Q-04' AND estado = 'ERRO';
INSERT @r (teste, ok, detalhe) VALUES ('R6c o ERRO com pendente irmão fica em ERRO', CASE WHEN @q = 1 THEN 1 ELSE 0 END, CONCAT('erro=', @q));

-- R7: ENVIADO e SEM_ENVIO nunca são tocados
SELECT @q = COUNT(*) FROM dbo.u_crmfila WHERE (u_crmfilastamp = 'CRMT-Q-06' AND estado = 'ENVIADO') OR (u_crmfilastamp = 'CRMT-Q-07' AND estado = 'SEM_ENVIO');
INSERT @r (teste, ok, detalhe) VALUES ('R7 ENVIADO e SEM_ENVIO nunca são repostos', CASE WHEN @q = 2 THEN 1 ELSE 0 END, CONCAT('intactos=', @q));

-- ===== CONSULTAS =====
DECLARE @t TABLE (origem varchar(30), entidade varchar(10), estado varchar(15), total int, mais_antigo datetime, mais_recente datetime);
INSERT @t EXEC dbo.up_crm_consulta_totais;
SELECT @q = SUM(total) FROM @t;
SELECT @b = COUNT(*) FROM dbo.u_crmfila;
INSERT @r (teste, ok, detalhe) VALUES ('Q1 totais por estado e origem somam todos os registos', CASE WHEN @q = @b THEN 1 ELSE 0 END, CONCAT('soma=', @q, ' fila=', @b));

DECLARE @e TABLE (u_crmfilastamp char(25), origem varchar(30), entidade varchar(10), codigo varchar(60), stamporigem char(25),
                  tentativas int, ultimamensagem varchar(500), datacriacao datetime, dataenvio datetime);
INSERT @e EXEC dbo.up_crm_consulta_erros @dias = 36500;
SELECT @q = COUNT(*) FROM @e;
SELECT @b = COUNT(*) FROM dbo.u_crmfila WHERE estado = 'ERRO';
INSERT @r (teste, ok, detalhe) VALUES ('Q2 consulta de erros devolve os registos em ERRO', CASE WHEN @q = @b AND @q > 0 THEN 1 ELSE 0 END, CONCAT('devolvidos=', @q, ' erros=', @b));

ROLLBACK TRAN;

SELECT @q = COUNT(*) FROM dbo.u_crmfila WHERE u_crmfilastamp LIKE 'CRMT-%';
INSERT @r (teste, ok, detalhe) VALUES ('Q3 rollback repõe a fila como estava (sem restos de teste)', CASE WHEN @q = 0 THEN 1 ELSE 0 END, CONCAT('restos=', @q));

SELECT n, CASE ok WHEN 1 THEN 'OK' ELSE 'FALHOU' END AS resultado, teste, detalhe FROM @r ORDER BY n;
SELECT COUNT(*) AS total, SUM(CASE WHEN ok = 1 THEN 1 ELSE 0 END) AS ok, SUM(CASE WHEN ok = 0 THEN 1 ELSE 0 END) AS falhas FROM @r;
IF EXISTS (SELECT 1 FROM @r WHERE ok = 0) THROW 50099, N'Há asserts a falhar neste teste.', 1;
