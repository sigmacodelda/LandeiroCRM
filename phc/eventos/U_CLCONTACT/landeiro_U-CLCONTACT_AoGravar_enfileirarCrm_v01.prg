**************************************************************************
* SigmaCode, Lda
* Cliente:   Landeiro
* Local:     U_CLCONTACT - Contactos do cliente
* Trigger:   Ao gravar
* Objetivo:  enfileira o contacto para o Somnia CRM
* Autor:     SigmaCode
* Histórico:
*   v01  21/10/2026  SC  Versão inicial (substitui os triggers tr_crm_*)
**************************************************************************

If m_introduzir = 1 Or m_editar = 1
    TEXT TO m_sql TEXTMERGE NOSHOW
        EXEC dbo.sc_CrmEnfileirarEvento @origem = 'U_CLCONTACT', @stamp = '<<Alltrim(u_clcontact.u_clcontactstamp)>>',
             @operacao = 'U', @clstamp = '<<Alltrim(u_clcontact.clstamp)>>',
             @temMeio = <<Iif(Empty(Alltrim(u_clcontact.email)) And Empty(Alltrim(u_clcontact.telefone)) And Empty(Alltrim(u_clcontact.tlmvl)), 0, 1)>>
    ENDTEXT
    u_sqlexec(m_sql)
Endif
