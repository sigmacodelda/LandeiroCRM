# base-dados

Tudo o que é SQL, com scripts numerados pela ordem de execução. **Todos são idempotentes** e têm rollback.

| Pasta | Conteúdo |
|---|---|
| `01_tabelas/` | Verificação da fila `u_crmfila` (criada no PHC), tipo `u_crm_evento_tt` e sequência `u_crmfila_seq`. |
| `02_views/` | `u_v_crm_conta_cl` e `u_v_crm_contacto_cl` (colunas com os nomes exatos da API). |
| `03_procedimentos/` | `up_crm_enfileirar` (único ponto de escrita), `up_crm_carga`, `up_crm_repor`, consultas. |
| `04_triggers/` | `tr_crm_cl`, `tr_crm_cl2`, `tr_crm_u_clcontact`. |
| `05_permissoes/` | Papel `crmsync_servico` (permissões mínimas do serviço). |
| `99_rollback/` | Desfaz tudo, pela ordem inversa. |
| `testes/` | Testes SQL com asserts (só LAND2_DEMO, com ROLLBACK) e `executar_testes.ps1`. |
| `instalar.sql` | Executa os scripts pela ordem certa. |

Instalar (a partir desta pasta, na base de testes):

```bash
sqlcmd -S "tcp:SERVIDOR\INSTANCIA" -d LAND2_DEMO -U <utilizador> -f 65001 -b -i instalar.sql -v BaseDados=LAND2_DEMO PermitirProducao=NAO
```

A `LAND2` (real) só aceita com `PermitirProducao=SIM`, depois de confirmação escrita. Ver [../docs/manual-instalacao.md](../docs/manual-instalacao.md).
