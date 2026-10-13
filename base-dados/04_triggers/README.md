# 04_triggers

Triggers `tr_crm_*`. Comparam `inserted` com `deleted` (não `UPDATE(coluna)`), tratam conjuntos de linhas, só escrevem
na fila e **nunca bloqueiam a gravação do PHC**. Não tocam nos triggers do PHC (`tr_cl_update`, `tr_cl_delete`, cifrados).
Depois de cada atualização do PHC, confirmar que continuam instalados: [../../docs/manual-operacao.md](../../docs/manual-operacao.md), secção 6.
