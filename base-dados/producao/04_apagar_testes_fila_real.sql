-- APAGAR (UMA SO VEZ) os registos PENDENTE e SEM_ENVIO da fila da LAND2 (eram testes).
-- Nao toca nos ENVIADO (historico do que ja foi para o CRM) nem nos ERRO.
-- Fazer backup da LAND2 antes. Corre dentro de uma transacao: se o numero de linhas a apagar
-- nao for o esperado, desfaz tudo e da erro.
--
-- COMO USAR:
--   1) Executar so o SELECT da PARTE 1 e ver as linhas (sao mesmo os testes?).
--   2) Acertar @esperado na PARTE 2 para o numero de linhas que a PARTE 1 mostrou.
--   3) Executar a PARTE 2.
USE LAND2;
GO
IF DB_NAME() <> N'LAND2' THROW 50000, N'Base errada: este ficheiro e so para a LAND2.', 1;
GO

-- PARTE 1: pre-visualizacao (so leitura)
SELECT datacriacao, origem, entidade, codigo, operacao, estado
FROM dbo.u_crmfila WITH (NOLOCK)
WHERE estado IN ('PENDENTE', 'SEM_ENVIO')
ORDER BY datacriacao;
GO

-- PARTE 2: apagar
SET NOCOUNT ON;
DECLARE @esperado int = 5;   -- acertar ao numero de linhas da PARTE 1

BEGIN TRAN;

DELETE FROM dbo.u_crmfila WHERE estado IN ('PENDENTE', 'SEM_ENVIO');

DECLARE @feitas int = @@ROWCOUNT;

IF @feitas <> @esperado
BEGIN
    ROLLBACK TRAN;
    DECLARE @msg nvarchar(200) = CONCAT(N'Desfeito: apagaria ', @feitas, N' linhas, esperadas ', @esperado, N'.');
    THROW 50011, @msg, 1;
END

COMMIT TRAN;
SELECT @feitas AS linhas_apagadas;
SELECT estado, COUNT(*) AS total FROM dbo.u_crmfila WITH (NOLOCK) GROUP BY estado;
GO
