# testes

Testes SQL com asserts (`01` a `05`), cada um dentro de uma transação com ROLLBACK, **só na LAND2_DEMO**
(recusam outra base). `executar_testes.ps1` corre-os todos e falha se algum falhar (ou se não encontrar os 5).
`00_preparar_demo_u_clcontact.sql` acrescenta `obs` e `departamento` à `u_clcontact` da DEMO (a LAND2 já os tem); só DEMO.

```powershell
$env:CRMSYNC_SQL_PASSWORD = '<password>'
.\executar_testes.ps1 -Servidor 'tcp:SERVIDOR\INSTANCIA' -Utilizador <utilizador>
```

Resultados: [../../docs/plano-de-testes.md](../../docs/plano-de-testes.md).
