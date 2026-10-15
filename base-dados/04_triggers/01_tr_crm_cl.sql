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
          JOIN dbo.u_clcontact AS k ON k.clstamp = i.clstamp
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
