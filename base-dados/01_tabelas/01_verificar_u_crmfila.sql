-- =============================================================================
-- Verifica que a tabela de utilizador u_crmfila existe e tem os campos esperados.
-- A TABELA É CRIADA PELO PHC (tabelas de utilizador), NUNCA POR SQL: este script só lê e
-- pára a instalação, com a lista do que falta ou está errado, se algo não bater certo.
-- Não altera nada.
-- =============================================================================
SET NOCOUNT ON;
GO
IF OBJECT_ID(N'dbo.u_crmfila', N'U') IS NULL
    THROW 50020, N'A tabela u_crmfila não existe. Cria-a no PHC (tabelas de utilizador) antes de instalar. Campos: docs/dicionario-de-dados.md.', 1;
GO
DECLARE @esperado TABLE (campo sysname, familia varchar(10), tam int);
-- familia: S = texto (char/varchar com tamanho >= tam, ou varchar(max)); M = texto longo (text ou varchar(max)); N = numérico; D = datetime
INSERT @esperado VALUES
 ('u_crmfilastamp','S',25), ('origem','S',30), ('entidade','S',10), ('tipoconta','S',3), ('stamporigem','S',25),
 ('codigo','S',60), ('operacao','S',1), ('estado','S',15), ('tentativas','N',0), ('ultimamensagem','M',0),
 ('idcrm','S',60), ('acaocrm','S',30), ('datacriacao','D',0), ('dataenvio','D',0),
 ('ousrinis','S',30), ('ousrdata','D',0), ('ousrhora','S',8), ('usrinis','S',30), ('usrdata','D',0), ('usrhora','S',8), ('marcada','B',0);

DECLARE @problemas TABLE (problema nvarchar(300));
INSERT @problemas
SELECT CONCAT(N'Falta o campo ', e.campo)
  FROM @esperado e
 WHERE NOT EXISTS (SELECT 1 FROM sys.columns c WHERE c.object_id = OBJECT_ID(N'dbo.u_crmfila') AND c.name = e.campo);

INSERT @problemas
SELECT CONCAT(N'Campo ', e.campo, N': tipo ', t.name, N'(', c.max_length, N') não serve')
  FROM @esperado e
  JOIN sys.columns c ON c.object_id = OBJECT_ID(N'dbo.u_crmfila') AND c.name = e.campo
  JOIN sys.types t ON t.user_type_id = c.user_type_id
 WHERE NOT (
        (e.familia = 'S' AND t.name IN ('char','varchar') AND (c.max_length = -1 OR c.max_length >= e.tam))
     OR (e.familia = 'M' AND (t.name = 'text' OR (t.name = 'varchar' AND (c.max_length = -1 OR c.max_length >= 500))))
     OR (e.familia = 'N' AND t.name IN ('numeric','decimal','int','bigint'))
     OR (e.familia = 'D' AND t.name IN ('datetime','datetime2','smalldatetime'))
     OR (e.familia = 'B' AND t.name = 'bit'));

INSERT @problemas
SELECT CONCAT(N'Campo ', e.campo, N' deve ser NOT NULL')
  FROM @esperado e JOIN sys.columns c ON c.object_id = OBJECT_ID(N'dbo.u_crmfila') AND c.name = e.campo
 WHERE c.is_nullable = 1;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.u_crmfila') AND is_primary_key = 1)
    INSERT @problemas VALUES (N'Falta a chave primária em u_crmfilastamp');

IF EXISTS (SELECT 1 FROM @problemas)
BEGIN
    SELECT problema FROM @problemas;
    THROW 50021, N'A tabela u_crmfila (criada no PHC) não tem a estrutura esperada. Ver a lista acima e docs/dicionario-de-dados.md.', 1;
END
PRINT N'u_crmfila: estrutura OK.';
GO
-- Índices: o PHC não os cria em tabelas de utilizador. O serviço funciona sem eles (a fila é pequena).
-- Só se a fila crescer muito (centenas de milhares de linhas) vale a pena criar, por SQL, com autorização:
--   (estado, datacriacao)  |  (entidade, stamporigem, estado)  |  (entidade, codigo)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.u_crmfila') AND name LIKE N'in[_]u[_]crmfila[_]%')
    PRINT N'INFO: u_crmfila sem índices além da chave (esperado: o PHC não os cria).';
GO
