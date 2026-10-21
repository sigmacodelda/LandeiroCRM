-- =============================================================================
-- u_v_crm_conta_cl: contas (clientes) no formato da API Somnia (ImportAccounts).
--
-- Colunas = nomes exatos da API + "stamp" (ligação à fila: u_crmfila.stamporigem).
-- Todas as colunas são de texto, já com trim. A truncagem NÃO é feita aqui:
-- é feita no serviço, com base nos limites da configuração.
--   code        = cl.no + '-' + cl.estab (sede = "13444-0", estabelecimento = "13444-1")
--   country     = cl2.descpais (LEFT JOIN: cliente sem CL2 fica com país vazio)
--   status      = "Ativo" ou "Inativo" (cl.inactivo). O CRM mantém o estado se o campo vier vazio.
--   accountType = fixo "CLI" (FL -> "FOR", PE -> "COL" nas views futuras)
-- Fora do âmbito (não enviados): obsCreation, obsExclusion, currentBalance, earliestDueDate.
-- =============================================================================
CREATE OR ALTER VIEW dbo.u_v_crm_conta_cl
AS
SELECT
    RTRIM(c.clstamp)                                              AS stamp,
    LTRIM(RTRIM(CONVERT(varchar(20), c.no))) + '-'
        + LTRIM(RTRIM(CONVERT(varchar(10), c.estab)))             AS code,
    LTRIM(RTRIM(c.nome))                                          AS name,
    LTRIM(RTRIM(c.morada))                                        AS address,
    LTRIM(RTRIM(c.codpost))                                       AS postalCode,
    LTRIM(RTRIM(c.local))                                         AS city,
    LTRIM(RTRIM(ISNULL(x.descpais, '')))                          AS country,
    LTRIM(RTRIM(c.ncont))                                         AS vatNumber,
    LTRIM(RTRIM(c.telefone))                                      AS phone,
    LTRIM(RTRIM(c.tlmvl))                                         AS mobilePhone,
    LTRIM(RTRIM(c.email))                                         AS email,
    LTRIM(RTRIM(c.fax))                                           AS fax,
    CONVERT(varchar(3), 'CLI')                                    AS accountType,
    CONVERT(varchar(7), CASE WHEN c.inactivo = 1 THEN 'Inativo' ELSE 'Ativo' END) AS status
FROM dbo.cl AS c WITH (NOLOCK)
LEFT JOIN dbo.cl2 AS x WITH (NOLOCK) ON x.cl2stamp = c.clstamp;
GO
