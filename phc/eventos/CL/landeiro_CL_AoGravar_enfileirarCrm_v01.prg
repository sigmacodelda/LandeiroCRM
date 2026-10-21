**************************************************************************
* SigmaCode, Lda
* Cliente:   Landeiro
* Local:     CL - Clientes (ficha, inclui CL2)
* Trigger:   Ao gravar
* Objetivo:  enfileira a conta (e contactos) para o Somnia CRM
* Autor:     SigmaCode
* Histórico:
*   v01  21/10/2026  SC  Versão inicial (substitui os triggers tr_crm_*)
**************************************************************************

If scl.adding=.t. Or scl.editing = .t.
    TEXT TO m_sql TEXTMERGE NOSHOW
        EXEC dbo.sc_CrmEnfileirarEvento @origem = 'CL', @stamp = '<<Alltrim(cl.clstamp)>>', @operacao = 'U',
             @no = <<Alltrim(Str(cl.no))>>, @estab = <<Alltrim(Str(cl.estab))>>, @inactivo = <<Iif(cl.inactivo, 1, 0)>>
    ENDTEXT
    u_sqlexec(m_sql)
Endif
