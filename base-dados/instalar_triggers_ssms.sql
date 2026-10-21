-- Triggers tr_crm_* para colar/abrir no SSMS. So LAND2_DEMO.
USE LAND2_DEMO;
GO
IF DB_NAME() <> N'LAND2_DEMO' THROW 50000, N'Base errada: so LAND2_DEMO.', 1;
GO

-- ===== 04_triggers/01_tr_crm_cl.sql =====
-- =============================================================================
-- tr_crm_cl (tabela CL): regista na fila cada criação, alteração ou eliminação de uma ficha.
--
-- Regras:
--   * NÃO usa UPDATE(coluna): o PHC faz UPDATE de todas as colunas ao gravar e há processos
--     que alteram a CL sem abrir a ficha (ex.: saldos). Compara inserted com deleted e só
--     regista se mudou algum campo integrado (comparação binária: apanha maiúsculas e acentos).
--     O estado (cl.inactivo) conta como campo integrado: ao mudar, reenfileira também os contactos da ficha.
--   * Todas as fichas (sede e estabelecimentos) geram conta, com código NO-ESTAB.
--   * Trata vários registos de uma vez (conjuntos). Só escreve na fila.
--   * Nunca impede a gravação da ficha no PHC: qualquer erro interno é engolido.
--   * Não mexe nos triggers existentes (tr_cl_update, tr_cl_delete).
-- =============================================================================
CREATE OR ALTER TRIGGER dbo.tr_crm_cl
ON dbo.cl
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;   -- um erro aqui não pode estragar a transação do PHC

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted)
            RETURN;

        DECLARE @ev dbo.u_crm_evento_tt;

        -- Criação ou alteração: linhas novas que não existiam iguais antes (EXCEPT compara conjuntos)
        INSERT @ev (origem, entidade, tipoconta, stamporigem, codigo, operacao)
        SELECT 'CL', 'CONTA', 'CLI', n.clstamp,
               LTRIM(RTRIM(CONVERT(varchar(20), n.no))) + '-' + LTRIM(RTRIM(CONVERT(varchar(10), n.estab))), 'U'
          FROM (
                SELECT clstamp, no, estab, inactivo,
                       nome     COLLATE Latin1_General_BIN2 AS nome,
                       morada   COLLATE Latin1_General_BIN2 AS morada,
                       codpost  COLLATE Latin1_General_BIN2 AS codpost,
                       local    COLLATE Latin1_General_BIN2 AS local,
                       ncont    COLLATE Latin1_General_BIN2 AS ncont,
                       telefone COLLATE Latin1_General_BIN2 AS telefone,
                       tlmvl    COLLATE Latin1_General_BIN2 AS tlmvl,
                       email    COLLATE Latin1_General_BIN2 AS email,
                       fax      COLLATE Latin1_General_BIN2 AS fax
                  FROM inserted
                EXCEPT
                SELECT clstamp, no, estab, inactivo,
                       nome     COLLATE Latin1_General_BIN2,
                       morada   COLLATE Latin1_General_BIN2,
                       codpost  COLLATE Latin1_General_BIN2,
                       local    COLLATE Latin1_General_BIN2,
                       ncont    COLLATE Latin1_General_BIN2,
                       telefone COLLATE Latin1_General_BIN2,
                       tlmvl    COLLATE Latin1_General_BIN2,
                       email    COLLATE Latin1_General_BIN2,
                       fax      COLLATE Latin1_General_BIN2
                  FROM deleted
               ) AS n;

        -- Ativar ou inativar uma ficha muda o estado dos contactos dela (o contacto segue o estado da conta)
        INSERT @ev (origem, entidade, tipoconta, stamporigem, codigo, operacao)
        SELECT 'U_CLCONTACT', 'CONTACTO', 'CLI', k.u_clcontactstamp, RTRIM(k.u_clcontactstamp), 'U'
          FROM inserted AS i
          JOIN deleted AS d ON d.clstamp = i.clstamp
          JOIN dbo.u_clcontact AS k WITH (NOLOCK) ON k.clstamp = i.clstamp
         WHERE i.inactivo <> d.inactivo;

        -- Eliminação: fichas que estavam em deleted e já não estão em inserted
        INSERT @ev (origem, entidade, tipoconta, stamporigem, codigo, operacao)
        SELECT 'CL', 'CONTA', 'CLI', d.clstamp,
               LTRIM(RTRIM(CONVERT(varchar(20), d.no))) + '-' + LTRIM(RTRIM(CONVERT(varchar(10), d.estab))), 'D'
          FROM deleted AS d
         WHERE NOT EXISTS (SELECT 1 FROM inserted AS i WHERE i.clstamp = d.clstamp);

        IF EXISTS (SELECT 1 FROM @ev)
            EXEC dbo.up_crm_enfileirar @ev;
    END TRY
    BEGIN CATCH
        -- Propositadamente vazio: a gravação no PHC nunca pode falhar por causa da fila.
        -- Se a fila falhar, o registo fica por enviar até à próxima alteração ou até uma carga.
    END CATCH
END
GO

GO

-- ===== 04_triggers/02_tr_crm_cl2.sql =====
-- =============================================================================
-- tr_crm_cl2 (tabela CL2, extensão 1 para 1 da CL): só INSERT e UPDATE.
--
-- Regista a entidade CONTA (stamp = cl2stamp = clstamp) com origem 'CL2' quando muda o
-- campo integrado (descpais, o país). A deduplicação de up_crm_enfileirar evita o envio a
-- dobrar quando o PHC grava a CL e a CL2 na mesma operação.
-- Só enfileira se a ficha CL existir (CL2 órfã não gera nada).
-- Nunca impede a gravação no PHC. Não usa UPDATE(coluna).
-- =============================================================================
CREATE OR ALTER TRIGGER dbo.tr_crm_cl2
ON dbo.cl2
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM inserted)
            RETURN;

        DECLARE @ev dbo.u_crm_evento_tt;

        INSERT @ev (origem, entidade, tipoconta, stamporigem, codigo, operacao)
        SELECT 'CL2', 'CONTA', 'CLI', c.clstamp,
               LTRIM(RTRIM(CONVERT(varchar(20), c.no))) + '-' + LTRIM(RTRIM(CONVERT(varchar(10), c.estab))), 'U'
          FROM (
                SELECT cl2stamp, descpais COLLATE Latin1_General_BIN2 AS descpais FROM inserted
                EXCEPT
                SELECT cl2stamp, descpais COLLATE Latin1_General_BIN2 FROM deleted
               ) AS n
          JOIN dbo.cl AS c WITH (NOLOCK) ON c.clstamp = n.cl2stamp;

        IF EXISTS (SELECT 1 FROM @ev)
            EXEC dbo.up_crm_enfileirar @ev;
    END TRY
    BEGIN CATCH
        -- Propositadamente vazio: ver tr_crm_cl.
    END CATCH
END
GO

GO

-- ===== 04_triggers/03_tr_crm_u_clcontact.sql =====
-- =============================================================================
-- tr_crm_u_clcontact (tabela U_CLCONTACT): INSERT, UPDATE e DELETE.
--
-- Compara inserted com deleted e só regista se mudou um campo integrado:
--   nome, contacto, funcao, tipo, telefone, tlmvl, email, departamento e a ligação à ficha (clstamp).
-- Não são integrados (a API não tem campo): fax, estab, no.
--
-- Exceção ao "não usar UPDATE(coluna)": a coluna OBS é do tipo text e o SQL Server não
-- deixa ler colunas text em inserted/deleted num trigger AFTER, por isso não há como
-- comparar o valor antigo com o novo. Para a OBS usa-se UPDATE(obs): se a coluna foi incluída
-- no UPDATE, o contacto vai para a fila. Pode gerar um envio a mais (inofensivo: o CRM faz
-- upsert) quando o PHC regrava a linha inteira sem alterações.
--
-- Só enfileira alterações de contactos com ficha CL (órfãos ficam fora). Eliminações
-- registam sempre (o serviço envia-as ao CRM como "Inativo"). Nunca impede a gravação no PHC.
-- =============================================================================
CREATE OR ALTER TRIGGER dbo.tr_crm_u_clcontact
ON dbo.u_clcontact
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted)
            RETURN;

        DECLARE @ev dbo.u_crm_evento_tt;
        DECLARE @mudou TABLE (stamp char(25) PRIMARY KEY);

        -- Contactos novos ou com algum campo integrado alterado (sem a coluna text)
        INSERT @mudou (stamp)
        SELECT n.u_clcontactstamp
          FROM (
                SELECT u_clcontactstamp, clstamp,
                       nome         COLLATE Latin1_General_BIN2 AS nome,
                       contacto     COLLATE Latin1_General_BIN2 AS contacto,
                       funcao       COLLATE Latin1_General_BIN2 AS funcao,
                       tipo         COLLATE Latin1_General_BIN2 AS tipo,
                       telefone     COLLATE Latin1_General_BIN2 AS telefone,
                       tlmvl        COLLATE Latin1_General_BIN2 AS tlmvl,
                       email        COLLATE Latin1_General_BIN2 AS email,
                       departamento COLLATE Latin1_General_BIN2 AS departamento
                  FROM inserted
                EXCEPT
                SELECT u_clcontactstamp, clstamp,
                       nome         COLLATE Latin1_General_BIN2,
                       contacto     COLLATE Latin1_General_BIN2,
                       funcao       COLLATE Latin1_General_BIN2,
                       tipo         COLLATE Latin1_General_BIN2,
                       telefone     COLLATE Latin1_General_BIN2,
                       tlmvl        COLLATE Latin1_General_BIN2,
                       email        COLLATE Latin1_General_BIN2,
                       departamento COLLATE Latin1_General_BIN2
                  FROM deleted
               ) AS n;

        -- OBS (text) não se compara: se foi incluída no UPDATE, conta como alterada
        IF UPDATE(obs)
            INSERT @mudou (stamp)
            SELECT i.u_clcontactstamp
              FROM inserted AS i
             WHERE NOT EXISTS (SELECT 1 FROM @mudou AS m WHERE m.stamp = i.u_clcontactstamp);

        -- Criação ou alteração (só contactos com ficha CL)
        INSERT @ev (origem, entidade, tipoconta, stamporigem, codigo, operacao)
        SELECT 'U_CLCONTACT', 'CONTACTO', 'CLI', m.stamp, RTRIM(m.stamp), 'U'
          FROM @mudou AS m
          JOIN inserted AS i ON i.u_clcontactstamp = m.stamp
         WHERE EXISTS (SELECT 1 FROM dbo.cl AS c WITH (NOLOCK) WHERE c.clstamp = i.clstamp);

        -- Eliminação. O código fica "contactCode|accountCode": depois de apagado o contacto já não há como saber
        -- a conta, e o serviço precisa dela para o inativar no CRM (se a ficha já não existir, fica só o contactCode).
        INSERT @ev (origem, entidade, tipoconta, stamporigem, codigo, operacao)
        SELECT 'U_CLCONTACT', 'CONTACTO', 'CLI', d.u_clcontactstamp,
               RTRIM(d.u_clcontactstamp)
                 + ISNULL((SELECT TOP 1 '|' + LTRIM(RTRIM(CONVERT(varchar(20), c.no))) + '-' + LTRIM(RTRIM(CONVERT(varchar(10), c.estab)))
                             FROM dbo.cl AS c WITH (NOLOCK) WHERE c.clstamp = d.clstamp), ''),
               'D'
          FROM deleted AS d
         WHERE NOT EXISTS (SELECT 1 FROM inserted AS i WHERE i.u_clcontactstamp = d.u_clcontactstamp);

        IF EXISTS (SELECT 1 FROM @ev)
            EXEC dbo.up_crm_enfileirar @ev;
    END TRY
    BEGIN CATCH
        -- Propositadamente vazio: ver tr_crm_cl.
    END CATCH
END
GO

GO
