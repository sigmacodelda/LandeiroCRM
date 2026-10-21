-- =============================================================================
-- up_crm_enfileirar: único ponto de escrita na fila (usado pelos triggers e pela carga).
--
-- Recebe eventos (origem, entidade, tipo de conta, stamp, código, operação) e aplica as regras:
--   * um só evento por entidade + stamp dentro do mesmo pedido (D vence U);
--   * se já existe PENDENTE para a mesma entidade + stamp, não cria outro:
--       - D substitui um U pendente;
--       - U sobre um D pendente repõe-no como U (o registo voltou a existir);
--       - U sobre U pendente só atualiza o código;
--   * só ativos: contas inativas nunca enviadas (e os contactos delas) não entram (ver 1b);
--   * contactos sem email, telefone e telemóvel nunca enviados não entram (ver 1c);
--   * caso contrário cria um novo PENDENTE, com stamp no formato PHC.
-- Stamp: 'CRM' + yymmdd + hhmmss + ',' + 8 dígitos da sequência = 24 caracteres (char 25),
-- igual ao padrão dos stamps existentes (ex.: FIL26091153534,171313351).
-- Não faz chamadas externas. Os estados diferentes de PENDENTE nunca são tocados.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.up_crm_enfileirar
    @ev        dbo.u_crm_evento_tt READONLY,
    @inseridos int = 0 OUTPUT,
    -- 0 = não aplica as regras 1b e 1c (quem chama já as aplicou com os valores do ecrã do PHC,
    -- porque o evento "Ao gravar" corre antes de a base ter os valores novos). Por defeito aplica.
    @filtrarRegras bit = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @agora datetime    = GETDATE();
    DECLARE @hora  varchar(8)  = CONVERT(varchar(8), GETDATE(), 108);
    DECLARE @data  char(6)     = CONVERT(char(6), GETDATE(), 12);                       -- yymmdd
    DECLARE @tempo char(6)     = REPLACE(CONVERT(char(8), GETDATE(), 108), ':', '');    -- hhmmss

    -- 1) Um evento por entidade + stamp (a eliminação vence a alteração)
    DECLARE @r TABLE
    (
        origem varchar(30), entidade varchar(10), tipoconta char(3),
        stamporigem char(25), codigo varchar(60), operacao char(1)
    );
    INSERT @r (origem, entidade, tipoconta, stamporigem, codigo, operacao)
    SELECT origem, entidade, tipoconta, stamporigem, codigo, operacao
    FROM (
        SELECT e.origem, e.entidade, e.tipoconta, e.stamporigem, e.codigo, e.operacao,
               ROW_NUMBER() OVER (PARTITION BY e.entidade, e.stamporigem
                                  ORDER BY CASE e.operacao WHEN 'D' THEN 0 ELSE 1 END, e.origem) AS rn
        FROM @ev AS e
    ) AS x
    WHERE x.rn = 1;

    -- 1b) Regra "só ativos": uma conta INATIVA que nunca foi enviada (sem ENVIADO na fila) não entra,
    --     nem os contactos dela. Se for ativada mais tarde, o trigger gera o evento e passa a entrar.
    --     Uma conta inativa que já foi enviada continua a entrar (para o CRM receber o estado "Inativo").
    --     As eliminações (D) não são filtradas.
    IF @filtrarRegras = 1
    BEGIN
        DELETE r
          FROM @r AS r
          JOIN dbo.cl AS c WITH (NOLOCK) ON c.clstamp = r.stamporigem
         WHERE r.entidade = 'CONTA' AND r.operacao = 'U' AND c.inactivo = 1
           AND NOT EXISTS (SELECT 1 FROM dbo.u_crmfila AS f WITH (NOLOCK)
                            WHERE f.entidade = 'CONTA' AND f.estado = 'ENVIADO' AND f.stamporigem = c.clstamp);

        DELETE r
          FROM @r AS r
          JOIN dbo.u_clcontact AS k WITH (NOLOCK) ON k.u_clcontactstamp = r.stamporigem
          JOIN dbo.cl AS c WITH (NOLOCK) ON c.clstamp = k.clstamp
         WHERE r.entidade = 'CONTACTO' AND r.operacao = 'U' AND c.inactivo = 1
           AND NOT EXISTS (SELECT 1 FROM dbo.u_crmfila AS f WITH (NOLOCK)
                            WHERE f.entidade = 'CONTA' AND f.estado = 'ENVIADO' AND f.stamporigem = c.clstamp);
    END

    -- 1c) Regra "contacto com meio de contacto": um contacto sem email, sem telefone e sem telemóvel
    --     (campos vazios ou só espaços) que nunca foi enviado não entra. Se mais tarde ganhar um destes
    --     campos, o trigger gera o evento e passa a entrar. Um contacto já enviado continua a entrar
    --     (para o CRM receber a alteração). As eliminações (D) não são filtradas.
    IF @filtrarRegras = 1
        DELETE r
          FROM @r AS r
          JOIN dbo.u_clcontact AS k WITH (NOLOCK) ON k.u_clcontactstamp = r.stamporigem
         WHERE r.entidade = 'CONTACTO' AND r.operacao = 'U'
           AND ISNULL(LTRIM(RTRIM(k.email)), '') = '' AND ISNULL(LTRIM(RTRIM(k.telefone)), '') = '' AND ISNULL(LTRIM(RTRIM(k.tlmvl)), '') = ''
           AND NOT EXISTS (SELECT 1 FROM dbo.u_crmfila AS f WITH (NOLOCK)
                            WHERE f.entidade = 'CONTACTO' AND f.estado = 'ENVIADO' AND f.stamporigem = k.u_clcontactstamp);

    -- 2) Já existe PENDENTE do mesmo registo: atualiza-o em vez de criar outro
    UPDATE f
       SET f.origem  = CASE WHEN f.operacao <> r.operacao THEN r.origem ELSE f.origem END,
           f.operacao = r.operacao,
           f.codigo   = r.codigo,
           f.usrdata  = @agora,
           f.usrhora  = @hora
      FROM dbo.u_crmfila AS f
      JOIN @r AS r ON r.entidade = f.entidade AND r.stamporigem = f.stamporigem
     WHERE f.estado = 'PENDENTE'
       AND (f.operacao <> r.operacao OR f.codigo <> r.codigo);

    -- 3) Os que já têm PENDENTE ficam tratados: só se criam os restantes
    DELETE r
      FROM @r AS r
     WHERE EXISTS (SELECT 1 FROM dbo.u_crmfila AS f WITH (NOLOCK)
                    WHERE f.estado = 'PENDENTE'
                      AND f.entidade = r.entidade
                      AND f.stamporigem = r.stamporigem);

    -- 4) Novos registos PENDENTE
    INSERT dbo.u_crmfila
        (u_crmfilastamp, origem, entidade, tipoconta, stamporigem, codigo, operacao, estado,
         datacriacao, ousrinis, ousrdata, ousrhora, usrinis, usrdata, usrhora)
    SELECT 'CRM' + @data + @tempo + ',' + RIGHT('00000000' + CONVERT(varchar(18), NEXT VALUE FOR dbo.u_crmfila_seq), 8),
           r.origem, r.entidade, r.tipoconta, r.stamporigem, r.codigo, r.operacao, 'PENDENTE',
           @agora, 'CRMSYNC', @agora, @hora, 'CRMSYNC', @agora, @hora
      FROM @r AS r;

    SET @inseridos = @@ROWCOUNT;
END
GO
