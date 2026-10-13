# Pendências e o seu estado

Atualizado em 2026-10-13. As pendências **P1 a P12** são as questões do [email para a Orcinus](email-orcinus.md)
(numeração original). **O email (por enviar) só leva P1, P2, P5, P4, P8 e P11** (renumeradas 1 a 6 no email); as restantes ficam resolvidas pela documentação ou adiadas (ver abaixo). As **S1 a S10** são internas (SigmaCode / Carnes Landeiro).

## Com a Orcinus (email por rever e enviar)

| # | Questão | Estado | Impacto | O que assumimos até haver resposta |
|---|---|---|---|---|
| **P1** | **Os endpoints `ImportAccounts` e `ImportContacts` respondem `301` → página de login (`index.php?action=Login&module=Users`) a qualquer pedido**, com o token standard, com a variante `Bearer:`, com um token inválido e sem token. Um `entryPoint` inexistente tem exatamente a mesma resposta. | **BLOQUEIA a validação com o CRM real.** Detetado em 2026-10-13. | Não foi possível autenticar nem enviar nada. O circuito está testado até à API (API simulada). | Nada: não se inventa o contrato. Nenhum dado foi enviado ao CRM. |
| P2 | Formato do "Código PHC" usado na importação inicial (`13444` ou `13444-0`). | Por enviar. | Se for só o número, enviar `13444-0` cria contas **duplicadas**. | Sem importação completa; só testes 1 a 1 com o 13444. |
| P3 (adiada: só quando houver fornecedores) | O `code` das contas é único por `accountType` ou global? | Por enviar. | Se for global, um fornecedor com o número de um cliente sobrescreve-o. | Global; não se integram fornecedores até haver resposta. |
| P4 | Existe endpoint para inativar/eliminar contas e contactos? | Por enviar. | Hoje as eliminações ficam `SEM_ENVIO` (tratamento manual). | Tratamento manual. |
| P5 | Um campo omitido no JSON mantém o valor? Um campo vazio apaga-o? | Por enviar. | Define enviar só o que mudou ou o registo completo. | Enviamos sempre o registo completo, com os campos vazios. |
| P6 (**respondida pela documentação**: `Bearer:` com dois pontos; testado na P1) | Cabeçalho: `Bearer <token>` ou `Bearer: <token>`? | Por enviar. | Afeta todos os pedidos. | Standard; variante em `AuthorizationPrefix`. (Não foi possível testar: ver P1.) |
| P7 (interna, não vai no email) | Trocar o token (foi partilhado em documento)? | Por enviar. | Segurança. | O token só existe em `anexos/` (fora do git) e no armazenamento DPAPI. |
| P8 | Tamanhos máximos, campos obrigatórios (incl. `obsCreation`, `obsExclusion`, `currentBalance`, `earliestDueDate`). | Por enviar. | Truncagem e rejeições. | Sem truncagem (limites vazios); esses 4 campos não são enviados. |
| P9 (não perguntada: enviamos como estão) | Formato esperado dos telefones. | Por enviar. | Os números do PHC têm formatos variados. | Como estão no PHC (só trim). |
| P10 (não perguntada: tratamos pela regra assumida) | Formato da resposta `206` para os registos que falham. | Por enviar. | Registo de erro por registo. | "Gravado" = vem na lista com `id` e ação que não indique falha; o resto fica em ERRO. |
| P11 | Existe ambiente de testes? | Por enviar. | Os testes com dados reais ficariam no CRM de produção. | Nenhum envio real até P1 estar resolvido. |
| P12 (não perguntada) | HTTPS (hoje o token circula em HTTP; a porta 443 não responde). | Por enviar. | Segurança. | HTTP na rede interna. |

## Internas

| # | Tema | Estado | O que fazer |
|---|---|---|---|
| S1 | O serviço usa o utilizador `sa` (decisão do responsável, "por agora"). | **Aberta — antes de produção.** | Trocar a password do `sa` e passar a `crmsync_svc` (papel `crmsync_servico`, ver [manual-instalacao.md](manual-instalacao.md)). A password foi partilhada em conversa; nunca está em ficheiros. |
| S2 | A gravação de fichas **pelo próprio PHC** (não só por SQL) não foi testada: não há cliente PHC nesta máquina. | **Por fazer por quem tenha acesso ao PHC.** | Na LAND2_DEMO: criar/alterar/apagar um cliente e um contacto pelo ecrã do PHC e confirmar que grava sem erro e que aparece na fila (ver [plano-de-testes.md](plano-de-testes.md), secção 6). Inclui lançar um documento ao cliente (saldo). |
| S3 | Triggers `tr_cl_update` e `tr_cl_delete` do PHC estão **cifrados**; não se sabe o que fazem. | Registada a limitação. | Pedir a definição a quem os criou, se for preciso garantir mais do que "coexistem sem erro nos testes". |
| S4 | Servidor PHC: tem acesso a `192.168.11.4`? | Por testar **no servidor PHC**. (Da máquina de desenvolvimento: porta 80 acessível.) | `Test-NetConnection 192.168.11.4 -Port 80`. |
| S5 | Runtime **.NET 8** no servidor PHC. | Por confirmar. | Instalar o ".NET 8 Runtime" ou publicar com `-AutoContido`. |
| S6 | `UPDATE(obs)` no trigger de contactos (limitação do SQL Server com colunas `text`). | Aceite e documentada. | Pode gerar um reenvio a mais (inofensivo). Se a coluna passar a `varchar(max)`, passa a comparar-se normalmente. |
| S7 | 61 contactos (LAND2) cujo `estab` não coincide com a ficha ligada pelo `clstamp`. | Decidido: liga-se pelo `clstamp`. | Rever com o cliente se alguns estão ligados à ficha errada (a integração envia-os para a conta da ficha). |
| S8 | A `LAND2_DEMO` não tinha `obs` e `departamento` na `u_clcontact`. | **Resolvido** na DEMO (script `00_preparar_demo_u_clcontact.sql`). | A LAND2 já os tem. Confirmar o mesmo em qualquer outra cópia. |
| S9 | Instalação na base real (LAND2) e como Windows Service no servidor do cliente. | **Não feitas** (aguardam confirmação escrita do responsável). | Seguir [manual-instalacao.md](manual-instalacao.md). |
| S10 | Contactos órfãos (1) e CL2 órfã (1) na DEMO; (1) e (1) na LAND2. | Decidido: ficam fora da fila. | Eventualmente limpar no PHC. |
