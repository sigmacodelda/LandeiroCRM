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
-- registam sempre. Nunca impede a gravação no PHC.
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
         WHERE EXISTS (SELECT 1 FROM dbo.cl AS c WHERE c.clstamp = i.clstamp);

        -- Eliminação
        INSERT @ev (origem, entidade, tipoconta, stamporigem, codigo, operacao)
        SELECT 'U_CLCONTACT', 'CONTACTO', 'CLI', d.u_clcontactstamp, RTRIM(d.u_clcontactstamp), 'D'
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
