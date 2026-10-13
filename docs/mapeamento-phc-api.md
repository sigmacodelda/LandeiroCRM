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
| `name` | `u_clcontact.nome` | varchar(55) | É o nome da pessoa (`contacto` está quase sempre vazio). |
| `title` | `u_clcontact.funcao` | varchar(15) | |
| `mattersType` | `u_clcontact.tipo` | varchar(25) | |
| `phoneOffice` | `u_clcontact.telefone` | varchar(60) | Só trim. |
| `phoneMobile` | `u_clcontact.tlmvl` | varchar(60) | Só trim. |
| `obs` | `u_clcontact.obs` | text → varchar(max) | |
| `email` | `u_clcontact.email` | varchar(60) | |
| `department` | `u_clcontact.departamento` | varchar(100) | |

**Não enviados (a API não tem campo):** `contacto`, `fax`, `estab`, `no`.

## Tamanhos e truncagem

A documentação da API **não indica limites** de tamanho. A truncagem é feita pelo serviço (nunca nas views), com
base em `CrmSync:FieldLimits` no `appsettings.json`:

```json
"FieldLimits": { "CONTA": { "name": 255 }, "CONTACTO": { "name": 100 } }
```

Um limite vazio (`null`) ou em falta quer dizer **sem truncagem** (estado atual: todos vazios, à espera da resposta
da Orcinus, P8). Cada truncagem fica no log como aviso (`TRUNCADO`, com origem, entidade, código, stamp e campo; **nunca
o valor completo**). Um corte nunca parte um carácter composto (par de substituição).

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
