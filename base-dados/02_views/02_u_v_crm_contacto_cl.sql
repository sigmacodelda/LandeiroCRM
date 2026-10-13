-- =============================================================================
-- u_v_crm_contacto_cl: contactos dos clientes no formato da API Somnia (ImportContacts).
--
-- Colunas = nomes exatos da API + duas colunas de ligação:
--   stamp        = u_clcontactstamp (liga à fila: u_crmfila.stamporigem)
--   accountStamp = clstamp da ficha da conta (o serviço usa-o para esperar pela conta
--                  quando esta está PENDENTE ou em ERRO na fila)
--   accountCode  = code da conta, igual ao da view u_v_crm_conta_cl (NO-ESTAB da ficha
--                  ligada por clstamp; o "estab" do próprio contacto é ignorado)
--   contactCode  = u_clcontactstamp (único e nunca muda: chave do upsert no CRM)
-- Não enviados (a API não tem campo): contacto, fax, estab, no.
-- INNER JOIN com CL: um contacto sem ficha (órfão) não aparece na view.
-- obs: text -> varchar(max), com trim.
-- =============================================================================
CREATE OR ALTER VIEW dbo.u_v_crm_contacto_cl
AS
SELECT
    RTRIM(k.u_clcontactstamp)                                     AS stamp,
    RTRIM(c.clstamp)                                              AS accountStamp,
    LTRIM(RTRIM(CONVERT(varchar(20), c.no))) + '-'
        + LTRIM(RTRIM(CONVERT(varchar(10), c.estab)))             AS accountCode,
    RTRIM(k.u_clcontactstamp)                                     AS contactCode,
    LTRIM(RTRIM(k.nome))                                          AS name,
    LTRIM(RTRIM(k.funcao))                                        AS title,
    LTRIM(RTRIM(k.tipo))                                          AS mattersType,
    LTRIM(RTRIM(k.telefone))                                      AS phoneOffice,
    LTRIM(RTRIM(k.tlmvl))                                         AS phoneMobile,
    LTRIM(RTRIM(CONVERT(varchar(max), k.obs)))                    AS obs,
    LTRIM(RTRIM(k.email))                                         AS email,
    LTRIM(RTRIM(k.departamento))                                  AS department
FROM dbo.u_clcontact AS k
INNER JOIN dbo.cl AS c ON c.clstamp = k.clstamp;
GO
