# 99_rollback

Scripts de rollback; `rollback_tudo.sql` corre-os pela ordem inversa da instalação. Os triggers do PHC nunca são tocados.
A tabela `u_crmfila` é do PHC e não é apagada (apaga-se no PHC, se for preciso). Recusa a `LAND2` sem `-v PermitirProducao=SIM`.

```bash
sqlcmd -S "tcp:SERVIDOR\INSTANCIA" -d LAND2_DEMO -U <utilizador> -f 65001 -b -i 99_rollback/rollback_tudo.sql -v BaseDados=LAND2_DEMO PermitirProducao=NAO
```
