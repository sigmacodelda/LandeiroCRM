# Mapeamento PHC → API Somnia CRM

Prevalece o mapeamento do prompt sobre o do DOCX de apoio (que dizia, por exemplo, `country ← cl.pais`; aqui é
`cl2.descpais`). Todos os campos de texto levam trim. Telefones vão como estão no PHC (só trim).

## Contas — `POST ImportAccounts` (lista `accounts`)

Origem: `CL` + `CL2` → view `u_v_crm_conta_cl`.

| Campo da API | Origem no PHC | Tipo / tamanho no PHC | Regra |
|---|---|---|---|
| `code` | `cl.no` + `-` + `cl.estab` | numeric(10,0) + numeric(3,0) | Texto sem casas decimais. Sede `13444-0`, estabelecimento `13444-1`. Todas as fichas da CL são enviadas; cada estabelecimento é uma conta própria. |
| `name` | `cl.nome` | varchar(55) | |
| `address` | `cl.morada` | varchar(55) | |
| `postalCode` | `cl.codpost` | varchar(45) | |
| `city` | `cl.local` | varchar(43) | |
| `country` | `cl2.descpais` | varchar(55) | `LEFT JOIN`; vazio se não houver CL2. |
| `vatNumber` | `cl.ncont` | varchar(20) | |
| `phone` | `cl.telefone` | varchar(60) | Só trim. |
| `mobilePhone` | `cl.tlmvl` | varchar(45) | Só trim. |
| `email` | `cl.email` | varchar(100) | |
| `fax` | `cl.fax` | varchar(60) | |
| `accountType` | fixo pela origem | — | CL → `CLI` (futuro: FL → `FOR`, PE → `COL`). |
| `status` | `cl.inactivo` | bit | `Ativo` (0) ou `Inativo` (1). A API também aceita `Active`/`Inactive`, `true`/`false`, `1`/`0`; se vier vazio ou em falta, o CRM mantém o estado. |

**Fora do âmbito, não enviados no JSON:** `obsCreation`, `obsExclusion`, `currentBalance`, `earliestDueDate`
(para não apagar no CRM valores que lá existam). Se a API os exigir, serão enviados vazios (por confirmar, ver
[pendencias.md](pendencias.md), P8).

`cl.clstamp` serve só de ligação (à fila e aos contactos); não é enviado.

## Contactos — `POST ImportContacts` (lista `contacts`)

Origem: `U_CLCONTACT` → view `u_v_crm_contacto_cl`.

| Campo da API | Origem no PHC | Tipo / tamanho no PHC | Regra |
|---|---|---|---|
| `accountCode` | `cl.no` + `-` + `cl.estab` da ficha ligada por `clstamp` | — | Igual ao `code` da conta. O `estab` do contacto é ignorado. |
| `contactCode` | `u_clcontact.u_clcontactstamp` | char(25) | Trim. Único e nunca muda: chave do upsert. |
| `name` | `u_clcontact.contacto`, senão `nome` | varchar(55) | **No PHC real o nome da pessoa fica em `contacto`** (contactos criados no ecrã: `nome` vazio); nos contactos importados `nome` é a empresa. Usa `contacto` se for um nome (não um email nem só dígitos); senão `nome`; senão o que houver em `contacto`. Tudo vazio: o serviço envia "Sem nome". |
| `title` | `u_clcontact.funcao` | varchar(15) | |
| `mattersType` | `u_clcontact.tipo` | varchar(25) | |
| `phoneOffice` | `u_clcontact.telefone` | varchar(60) | Só trim. |
| `phoneMobile` | `u_clcontact.tlmvl` | varchar(60) | Só trim. |
| `obs` | `u_clcontact.obs` | text → varchar(max) | |
| `email` | `u_clcontact.email` | varchar(60) | |
| `department` | `u_clcontact.departamento` | varchar(100) | |
| `status` | `cl.inactivo` da conta ligada | bit | O contacto não tem estado próprio: segue o da conta (`Ativo`/`Inativo`). Ao ativar ou inativar uma ficha, o trigger reenfileira os contactos dela. |

**Não enviados (a API não tem campo):** `fax`, `estab`, `no`. (`contacto` é usado no `name`.)

## Tamanhos e truncagem

Os limites vêm da Orcinus (resposta de 2026-10-14) e estão em `CrmSync:FieldLimits` no `appsettings.json`. A truncagem
é feita pelo serviço (nunca nas views):

| Conta | Limite | Contacto | Limite |
|---|---|---|---|
| `code` | 100 | `contactCode`, `accountCode` | 100 |
| `name`, `address` | 150 | `name` | 100 (primeiro nome) + 100 (apelido) |
| `postalCode` | 20 | `title`, `phoneOffice`, `phoneMobile` | 100 |
| `city`, `phone`, `mobilePhone`, `fax` | 100 | `mattersType`, `email`, `department` | 255 |
| `country`, `email` | 255 | `obs` | 65000 |
| `vatNumber` | 32 | | |

Obrigatórios: `code` (sempre); `name` só na criação; contactos: `contactCode` e `accountCode` (conta já existente).
Um limite vazio (`null`) ou em falta quer dizer **sem truncagem**. Cada truncagem fica no log como aviso (`TRUNCADO`, com
origem, entidade, código, stamp e campo; **nunca o valor completo**). Um corte nunca parte um carácter composto (par de substituição).

## Respostas da API (por registo, pelo índice `row`)

| Resposta | O que o serviço faz |
|---|---|
| `200` | Cada registo tem de vir na lista com `id` e `action`. Quem não vier fica em ERRO. Guarda `id` e `action`. |
| `206` | Igual: só os registos que vêm gravados passam a ENVIADO; os que não vêm ficam em ERRO. (O formato dos que falham está por confirmar, P10.) |
| `422` | Todo o lote em ERRO, com a mensagem `error` da API. |
| `401` / `403` | Todo o lote em ERRO; `FALHA_AUTENTICACAO` em destaque no log. |
| Rede / timeout | Todo o lote em ERRO; `FALHA_REDE` em destaque no log. |
| `5xx`, outros, corpo inválido | Todo o lote em ERRO com a mensagem correspondente. |

Um registo cujo `account`/`contact` na resposta não coincida com o código enviado também fica em ERRO.

## Cabeçalhos

`Content-Type: application/json` e `Authorization: Bearer <token>` (formato standard). O PDF da Orcinus escreve
`Bearer:` com dois pontos; a configuração `CrmSync:AuthorizationPrefix` permite mudar para essa variante se o
servidor rejeitar a standard. **Nenhuma das duas pôde ser testada**: ver [pendencias.md](pendencias.md), P1.

## Só clientes ativos (decisão de 2026-10-15)

No PHC 84% dos clientes estão inativos (11 737 de 14 042). Só se enviam os **ativos**. A regra está no `up_crm_enfileirar`
(único ponto de escrita na fila):

- Cliente inativo **nunca enviado** (sem registo `ENVIADO` na fila): não entra na fila, nem os contactos dele. Vale para
  os triggers e para a carga.
- Passa a ativo no PHC: o trigger gera a conta e os contactos, e passam a ser enviados com `status = Ativo`.
- Cliente **já enviado** que fique inativo: continua a entrar, para o CRM receber `status = Inativo` (e os contactos também).
- Limitação: depende do histórico `ENVIADO` da fila (que nunca é limpa). Se esse histórico for apagado, um cliente já
  enviado passa a ser tratado como "nunca enviado". Se um cliente for inativado enquanto o envio anterior ainda está
  `PENDENTE`, a conta pode ser criada já como `Inativo` (caso raro).

## Regras para o CRM aceitar a linha

A API trata cada linha à parte e **rejeita a linha inteira** se um campo for inválido. Por isso, antes de enviar:

| Regra | O que faz | Aviso no log |
|---|---|---|
| Email com vários valores ou texto (ex.: `a@x.pt; b@y.pt`) | Envia o **primeiro email válido**. | `EMAIL_AJUSTADO` |
| Email sem nenhum válido (ex.: "Não Têm") | Envia o campo **vazio** (o CRM mantém o valor que tiver). | `EMAIL_INVALIDO` |
| Contacto sem nome no PHC | Envia `name` = "Sem nome" (obrigatório na criação). | `NOME_EM_FALTA` |
| Código postal com a localidade a seguir (ex.: `4410-387 ARCOZELO VNG`) | Envia só o `NNNN-NNN` (só nas contas). | `CODPOSTAL_AJUSTADO` |

Os avisos dizem o campo e a regra, nunca o valor. Na LAND2_DEMO: 215 de 1 905 contas com email e 369 contactos sem nome.

**Campos vazios:** um campo omitido, nulo ou vazio **mantém** o valor do CRM (não há forma de o limpar pela API). Se um
valor for apagado no PHC, o CRM continua com o antigo.
