-- =============================================================================
-- up_crm_repor: repõe a PENDENTE os registos em ERRO (reposição manual).
--
--   EXEC dbo.up_crm_repor;                                   -- todos os ERRO
--   EXEC dbo.up_crm_repor @origem = 'CL';                    -- filtrar por origem
--   EXEC dbo.up_crm_repor @entidade = 'CONTACTO';            -- filtrar por entidade
--   EXEC dbo.up_crm_repor @codigo = '13444-0';               -- filtrar por código
--   EXEC dbo.up_crm_repor @stamp = '<stamp>';                -- stamp do registo de origem ou da fila
--
-- Regras:
--   * só mexe em registos ERRO; nunca em ENVIADO / SEM_ENVIO;
--   * se o mesmo registo tiver vários ERRO, repõe só o mais recente;
--   * se já existir um PENDENTE para o mesmo registo, não repõe (evita duplicados) e conta-o como ignorado;
--   * a mensagem de erro anterior fica registada no campo ultimamensagem.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.up_crm_repor
    @origem   varchar(30) = NULL,
    @entidade varchar(10) = NULL,
    @codigo   varchar(60) = NULL,
    @stamp    varchar(25) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @agora datetime = GETDATE();
    DECLARE @hora varchar(8) = CONVERT(varchar(8), GETDATE(), 108);
    DECLARE @stampLimpo varchar(25) = LTRIM(RTRIM(@stamp));

    -- Candidatos: o ERRO mais recente de cada registo que cumpra os filtros
    DECLARE @alvo TABLE (u_crmfilastamp char(25) PRIMARY KEY, entidade varchar(10), stamporigem char(25));
    INSERT @alvo (u_crmfilastamp, entidade, stamporigem)
    SELECT u_crmfilastamp, entidade, stamporigem
    FROM (
        SELECT f.u_crmfilastamp, f.entidade, f.stamporigem,
               ROW_NUMBER() OVER (PARTITION BY f.entidade, f.stamporigem
                                  ORDER BY f.datacriacao DESC, f.u_crmfilastamp DESC) AS rn
          FROM dbo.u_crmfila AS f WITH (NOLOCK)
         WHERE f.estado = 'ERRO'
           AND (@origem   IS NULL OR f.origem   = @origem)
           AND (@entidade IS NULL OR f.entidade = @entidade)
           AND (@codigo   IS NULL OR f.codigo   = @codigo)
           AND (@stampLimpo IS NULL OR f.stamporigem = @stampLimpo OR f.u_crmfilastamp = @stampLimpo)
    ) AS x
    WHERE x.rn = 1;

    DECLARE @candidatos int = (SELECT COUNT(*) FROM @alvo);

    UPDATE f
       SET f.estado = 'PENDENTE',
           f.ultimamensagem = LEFT('Reposto manualmente. Erro anterior: ' + CONVERT(varchar(max), f.ultimamensagem), 500),
           f.usrdata = @agora,
           f.usrhora = @hora
      FROM dbo.u_crmfila AS f
      JOIN @alvo AS a ON a.u_crmfilastamp = f.u_crmfilastamp
     WHERE NOT EXISTS (SELECT 1 FROM dbo.u_crmfila AS p WITH (NOLOCK)
                        WHERE p.estado = 'PENDENTE'
                          AND p.entidade = a.entidade
                          AND p.stamporigem = a.stamporigem);

    DECLARE @repostos int = @@ROWCOUNT;
    SELECT @repostos AS repostos, @candidatos - @repostos AS ignorados_ja_pendentes;
END
GO
