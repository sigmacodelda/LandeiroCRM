# 01_tabelas

- `01_verificar_u_crmfila.sql`: **só verifica** a tabela `u_crmfila`, que é criada **no PHC** (tabelas de utilizador), nunca por SQL. Pára a instalação com a lista do que falta.
- `02_tipo_evento.sql`: tipo de tabela `u_crm_evento_tt` (os triggers entregam eventos a `up_crm_enfileirar`).
- `03_sequencia.sql`: sequência `u_crmfila_seq` (stamp da fila).

Não alteram as tabelas do PHC (CL, CL2). Dicionário: [../../docs/dicionario-de-dados.md](../../docs/dicionario-de-dados.md).
