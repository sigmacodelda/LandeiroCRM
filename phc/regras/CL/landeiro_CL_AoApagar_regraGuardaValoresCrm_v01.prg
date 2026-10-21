**************************************************************************
* SigmaCode, Lda
* Cliente:   Landeiro
* Local:     CL - Clientes (ficha)
* Trigger:   Personalização de ecrã (cria as variáveis públicas antes de apagar)
* Objetivo:  cria e preenche as variáveis públicas da ficha; o evento Ao apagar envia e liberta-as
* Autor:     SigmaCode
* Histórico:
*   v01  21/10/2026  SC  Versão inicial
**************************************************************************

Public cl_clstamp, cl_no, cl_estab
cl_clstamp = Alltrim(cl.clstamp)
cl_no = cl.no
cl_estab = cl.estab
Return .T.
