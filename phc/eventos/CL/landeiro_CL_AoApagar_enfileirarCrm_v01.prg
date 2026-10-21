**************************************************************************
* SigmaCode, Lda
* Cliente:   Landeiro
* Local:     CL - Clientes (ficha)
* Trigger:   Ao apagar (evento: corre depois de apagar)
* Objetivo:  enfileira a eliminação da conta no Somnia CRM e liberta as variáveis públicas
* Autor:     SigmaCode
* Histórico:
*   v01  21/10/2026  SC  Versão inicial
**************************************************************************

TEXT TO m_sql TEXTMERGE NOSHOW
  EXEC dbo.sc_CrmEnfileirarEvento @origem = 'CL', @stamp = '<<Alltrim(cl_clstamp)>>', @operacao = 'D',
  @no = <<Alltrim(Str(cl_no))>>, @estab = <<Alltrim(Str(cl_estab))>>
ENDTEXT
u_sqlexec(m_sql)
Release cl_clstamp, cl_no, cl_estab
