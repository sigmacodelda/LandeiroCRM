**************************************************************************
* SigmaCode, Lda
* Cliente:   Landeiro
* Local:     U_CLCONTACT - Contactos do cliente
* Trigger:   Ao apagar
* Objetivo:  enfileira a eliminação do contacto no Somnia CRM
* Autor:     SigmaCode
* Histórico:
*   v01  21/10/2026  SC  Versão inicial (substitui os triggers tr_crm_*)
**************************************************************************

TEXT TO m_sql TEXTMERGE NOSHOW
    EXEC dbo.sc_CrmEnfileirarEvento @origem = 'U_CLCONTACT', @stamp = '<<Alltrim(u_clcontact.u_clcontactstamp)>>', @operacao = 'D'
ENDTEXT
u_sqlexec(m_sql)
