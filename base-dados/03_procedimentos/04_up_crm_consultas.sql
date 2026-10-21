-- =============================================================================
-- Consultas de acompanhamento da fila (só leitura).
-- =============================================================================

-- Totais por estado e origem
CREATE OR ALTER PROCEDURE dbo.up_crm_consulta_totais
AS
BEGIN
    SET NOCOUNT ON;
    SELECT origem, entidade, estado, COUNT(*) AS total, MIN(datacriacao) AS mais_antigo, MAX(datacriacao) AS mais_recente
      FROM dbo.u_crmfila WITH (NOLOCK)
     GROUP BY origem, entidade, estado
     ORDER BY origem, entidade, estado;
END
GO

-- Erros recentes (por defeito, dos últimos 7 dias)
CREATE OR ALTER PROCEDURE dbo.up_crm_consulta_erros
    @dias int = 7
AS
BEGIN
    SET NOCOUNT ON;
    SELECT u_crmfilastamp, origem, entidade, codigo, stamporigem, tentativas, ultimamensagem, datacriacao, dataenvio
      FROM dbo.u_crmfila WITH (NOLOCK)
     WHERE estado = 'ERRO'
       AND datacriacao >= DATEADD(DAY, -@dias, GETDATE())
     ORDER BY datacriacao DESC;
END
GO

-- Histórico de um cliente: as suas contas (sede e estabelecimentos) e os seus contactos
CREATE OR ALTER PROCEDURE dbo.up_crm_consulta_historico
    @no numeric(10, 0)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @prefixo varchar(30) = LTRIM(RTRIM(CONVERT(varchar(20), @no))) + '-%';

    SELECT f.datacriacao, f.entidade, f.origem, f.codigo, f.operacao, f.estado, f.tentativas,
           f.acaocrm, f.idcrm, f.dataenvio, f.ultimamensagem, f.u_crmfilastamp
      FROM dbo.u_crmfila AS f WITH (NOLOCK)
     WHERE (f.entidade = 'CONTA' AND f.codigo LIKE @prefixo)
        OR (f.entidade = 'CONTACTO'
            AND f.stamporigem IN (SELECT k.u_clcontactstamp
                                    FROM dbo.u_clcontact AS k WITH (NOLOCK)
                                    JOIN dbo.cl AS c WITH (NOLOCK) ON c.clstamp = k.clstamp
                                   WHERE c.no = @no))
     ORDER BY f.datacriacao, f.u_crmfilastamp;
END
GO
