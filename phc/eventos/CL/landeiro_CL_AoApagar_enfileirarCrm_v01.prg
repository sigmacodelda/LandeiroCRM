**************************************************************************
* SigmaCode, Lda
* Cliente:   Landeiro
* Local:     CL - Clientes (ficha)
* Trigger:   Ao apagar
* Objetivo:  enfileira a eliminação da conta no Somnia CRM
* Autor:     SigmaCode
* Histórico:
*   v01  21/10/2026  SC  Versão inicial (substitui os triggers tr_crm_*)
**************************************************************************

TEXT TO m_sql TEXTMERGE NOSHOW
    EXEC dbo.sc_CrmEnfileirarEvento @origem = 'CL', @stamp = '<<Alltrim(cl.clstamp)>>', @operacao = 'D',
         @no = <<Alltrim(Str(cl.no))>>, @estab = <<Alltrim(Str(cl.estab))>>
ENDTEXT
u_sqlexec(m_sql)
