-- PASSO 4 (UMA SO VEZ): acrescenta a conta (|NO-ESTAB) ao codigo dos contactos ja enviados na fila da LAND2.
-- Altera so o campo codigo do historico (ENVIADO, operacao U) dos contactos que ainda existem. Nao envia nada ao CRM.
-- Corre dentro de uma transacao: se o numero de linhas alteradas nao for o esperado, desfaz tudo.
-- Antes: backup da LAND2 e correr a pre-visualizacao (deu 79 linhas com conta e 2 sem).
USE LAND2;
GO
IF DB_NAME() <> N'LAND2' THROW 50000, N'Base errada: este ficheiro e so para a LAND2.', 1;
GO
SET NOCOUNT ON;
DECLARE @esperado int = 79;   -- linhas com conta na pre-visualizacao

BEGIN TRAN;

UPDATE f
   SET f.codigo = RTRIM(f.codigo) + '|' + LTRIM(RTRIM(CONVERT(varchar(20), c.no))) + '-' + LTRIM(RTRIM(CONVERT(varchar(10), c.estab)))
  FROM dbo.u_crmfila AS f
  JOIN dbo.u_clcontact AS k ON k.u_clcontactstamp = f.stamporigem
  JOIN dbo.cl AS c ON c.clstamp = k.clstamp
 WHERE f.entidade = 'CONTACTO' AND f.operacao = 'U' AND f.estado = 'ENVIADO' AND f.codigo NOT LIKE '%|%';

DECLARE @feitas int = @@ROWCOUNT;

IF @feitas <> @esperado
BEGIN
    ROLLBACK TRAN;
    DECLARE @msg nvarchar(200) = CONCAT(N'Desfeito: alteradas ', @feitas, N' linhas, esperadas ', @esperado, N'.');
    THROW 50010, @msg, 1;
END

COMMIT TRAN;
SELECT @feitas AS linhas_alteradas;
SELECT COUNT(*) AS contactos_sem_conta_que_restam FROM dbo.u_crmfila WITH (NOLOCK)
 WHERE entidade = 'CONTACTO' AND operacao = 'U' AND codigo NOT LIKE '%|%';
GO
