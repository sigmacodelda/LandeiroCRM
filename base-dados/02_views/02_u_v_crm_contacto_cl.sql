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
--   status       = "Ativo"/"Inativo" da CONTA a que o contacto pertence (cl.inactivo): o contacto não tem estado próprio.
--   name         = u_clcontact.contacto se for um nome (nos contactos criados no ecrã do PHC o nome da pessoa
--                  fica em "contacto" e "nome" fica vazio); senão u_clcontact.nome (nos contactos importados é a
--                  empresa); senão o que houver em "contacto". Se tudo estiver vazio, o serviço envia "Sem nome".
-- Não enviados (a API não tem campo): fax, estab, no.
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
    CASE
        -- "contacto" é o nome da pessoa quando é texto (não um email nem só dígitos/telefone)
        WHEN LTRIM(RTRIM(k.contacto)) <> '' AND k.contacto NOT LIKE '%@%' AND k.contacto LIKE '%[^0-9 +().-]%'
            THEN LTRIM(RTRIM(k.contacto))
        WHEN LTRIM(RTRIM(k.nome)) <> '' THEN LTRIM(RTRIM(k.nome))
        ELSE LTRIM(RTRIM(k.contacto))
    END                                                           AS name,
    LTRIM(RTRIM(k.funcao))                                        AS title,
    LTRIM(RTRIM(k.tipo))                                          AS mattersType,
    LTRIM(RTRIM(k.telefone))                                      AS phoneOffice,
    LTRIM(RTRIM(k.tlmvl))                                         AS phoneMobile,
    LTRIM(RTRIM(CONVERT(varchar(max), k.obs)))                    AS obs,
    LTRIM(RTRIM(k.email))                                         AS email,
    LTRIM(RTRIM(k.departamento))                                  AS department,
    CONVERT(varchar(7), CASE WHEN c.inactivo = 1 THEN 'Inativo' ELSE 'Ativo' END) AS status
FROM dbo.u_clcontact AS k WITH (NOLOCK)
INNER JOIN dbo.cl AS c WITH (NOLOCK) ON c.clstamp = k.clstamp;
GO
