**************************************************************************
* SigmaCode, Lda
* Cliente:   Landeiro
* Local:     U_CLCONTACT - Contactos do cliente
* Trigger:   Ao apagar (regra: corre antes de apagar)
* Objetivo:  guarda os contactos apagados em variáveis públicas, para o Ao gravar os enviar
* Autor:     SigmaCode
* Histórico:
*   v01  21/10/2026  SC  Versão inicial
**************************************************************************

If Type("u_clcontact_apagados") = "U"
  Public u_clcontact_apagados, u_clcontact_clstamp
  u_clcontact_apagados = ""
Endif
u_clcontact_apagados = u_clcontact_apagados + Iif(Empty(u_clcontact_apagados), "", ",") + Alltrim(u_clcontact.u_clcontactstamp)
u_clcontact_clstamp = Alltrim(u_clcontact.clstamp)
Return .T.
