-- =============================================================================
-- Tipo de tabela usado pelos triggers para entregar eventos ao procedimento
-- up_crm_enfileirar. Um evento = "este registo mudou, põe-no na fila".
-- Idempotente. Atenção: um tipo não pode ser alterado; só apagado e recriado
-- (apagar primeiro os procedimentos que o usam: ver 99_rollback).
-- =============================================================================
SET NOCOUNT ON;
GO
IF TYPE_ID(N'dbo.u_crm_evento_tt') IS NULL
    CREATE TYPE dbo.u_crm_evento_tt AS TABLE
    (
        origem      varchar(30) NOT NULL,   -- tabela de origem (CL, CL2, U_CLCONTACT, ...)
        entidade    varchar(10) NOT NULL,   -- CONTA | CONTACTO
        tipoconta   char(3)     NOT NULL,   -- CLI | FOR | COL
        stamporigem char(25)    NOT NULL,   -- stamp do registo de origem
        codigo      varchar(60) NOT NULL,   -- NO-ESTAB / contactCode
        operacao    char(1)     NOT NULL    -- U | D
    );
GO
