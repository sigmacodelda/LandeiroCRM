# Dicionário de dados

## 1. Tabela `u_crmfila`

Fila de envio e histórico completo. **Tabela de utilizador criada no PHC, nunca por SQL** (convenção da `U_CLCONTACT`).
Todas as colunas são `NOT NULL` com default. O `instalar.sql` só a **verifica** (`base-dados/01_tabelas/01_verificar_u_crmfila.sql`)
e pára com a lista do que falta. Tipos aceites: `char`/`varchar` com o tamanho indicado (ou maior), `ultimamensagem` como `text`
(PHC) ou `varchar`, `tentativas` numérico. Sem `CHECK`: quem garante os valores válidos é `up_crm_enfileirar` (única porta de escrita).

| Coluna | Tipo | Default | Descrição |
|---|---|---|---|
| `u_crmfilastamp` | char(25) | `''` | **Chave primária** (clustered). Formato PHC: `CRM` + `yymmdd` + `hhmmss` + `,` + 8 dígitos (sequência `u_crmfila_seq`). |
| `origem` | varchar(30) | `''` | Tabela de onde veio o registo: `CL`, `CL2`, `U_CLCONTACT` (futuro: `FL`, `PE`). **Obrigatória** (`CHECK` rejeita vazio). |
| `entidade` | varchar(10) | `''` | `CONTA` ou `CONTACTO` (`CHECK`). |
| `tipoconta` | char(3) | `''` | `CLI`, `FOR` ou `COL` (`CHECK`). Nos contactos guarda o tipo da conta a que pertencem. |
| `stamporigem` | char(25) | `''` | Stamp do registo de origem (`clstamp`; na CL2 é o `cl2stamp` = `clstamp`; nos contactos o `u_clcontactstamp`). |
| `codigo` | varchar(60) | `''` | Código da conta (`NO-ESTAB`, ex.: `13444-0`) ou `contactCode`. Gravado no insert: sobrevive a uma eliminação. |
| `operacao` | char(1) | `'U'` | `U` = criação/alteração (upsert); `D` = eliminação (`CHECK`). |
| `estado` | varchar(15) | `'PENDENTE'` | `PENDENTE`, `A_PROCESSAR`, `ENVIADO`, `ERRO`, `SEM_ENVIO` (`CHECK`). |
| `tentativas` | int | `0` | Informativo: sobe 1 de cada vez que o serviço reserva o registo. |
| `ultimamensagem` | varchar(500) | `''` | Última mensagem de erro (ou nota de reposição/recuperação). Sem dados pessoais. |
| `idcrm` | varchar(60) | `''` | `id` devolvido pelo CRM. |
| `acaocrm` | varchar(30) | `''` | `action` devolvida pelo CRM (ex.: `Updated`). |
| `datacriacao` | datetime | `GETDATE()` | Quando entrou na fila. |
| `dataenvio` | datetime | `'19000101'` | Data da última tentativa (ENVIADO ou ERRO). |
| `ousrinis`, `ousrdata`, `ousrhora`, `usrinis`, `usrdata`, `usrhora`, `marcada` | — | — | Auditoria e marca, convenção PHC. Os triggers e o serviço usam `CRMSYNC` nas iniciais. |

**Índices** (opcionais: o PHC não os cria em tabelas de utilizador e o serviço funciona sem eles; só valem a pena se a fila crescer muito, e então por SQL, com autorização)

| Índice | Colunas | Para quê |
|---|---|---|
| `pk_u_crmfila` (clustered) | `u_crmfilastamp` | Chave. Como o stamp começa pela data/hora, a ordem física é a ordem de criação. |
| `in_u_crmfila_leitura` | `estado, datacriacao` (+ `entidade, tipoconta, origem`) | Leitura do serviço. |
| `in_u_crmfila_dedup` | `entidade, stamporigem, estado` | Deduplicação e bloqueio de contas. |
| `in_u_crmfila_codigo` | `entidade, codigo` | Histórico de um cliente. |

**Outros objetos (SQL)**: sequência `u_crmfila_seq` (bigint); tipo de tabela `u_crm_evento_tt`
(`origem, entidade, tipoconta, stamporigem, codigo, operacao`), usado pelos triggers para entregar eventos a
`up_crm_enfileirar`.

**Não contém**: o JSON enviado, nomes, moradas, e-mails, telefones ou observações (RGPD).

## 2. Views

Contrato de uma view de origem: colunas com os **nomes exatos da API** (todas `varchar`, com trim) e
`stamp` (ligação à fila). A truncagem NÃO é feita nas views.

### `u_v_crm_conta_cl` (contas de clientes)

| Coluna | Origem | Notas |
|---|---|---|
| `stamp` | `cl.clstamp` | Ligação à fila (`u_crmfila.stamporigem`). Não é enviada. |
| `code` | `cl.no` + `'-'` + `cl.estab` | `13444-0` (sede), `13444-1` (estabelecimento). |
| `name` | `cl.nome` | |
| `address` | `cl.morada` | |
| `postalCode` | `cl.codpost` | |
| `city` | `cl.local` | |
| `country` | `cl2.descpais` | `LEFT JOIN`; vazio se não houver CL2. |
| `vatNumber` | `cl.ncont` | |
| `phone` | `cl.telefone` | |
| `mobilePhone` | `cl.tlmvl` | |
| `email` | `cl.email` | |
| `fax` | `cl.fax` | |
| `accountType` | fixo `CLI` | |

### `u_v_crm_contacto_cl` (contactos de clientes)

| Coluna | Origem | Notas |
|---|---|---|
| `stamp` | `u_clcontact.u_clcontactstamp` | Ligação à fila. Não é enviada. |
| `accountStamp` | `cl.clstamp` | Ligação à conta (regra de espera). Não é enviada. |
| `accountCode` | `cl.no` + `'-'` + `cl.estab` **da ficha ligada por `clstamp`** | O `estab` do contacto é ignorado. |
| `contactCode` | `u_clcontactstamp` | Chave do upsert no CRM. Nunca muda. |
| `name` | `u_clcontact.nome` | |
| `title` | `funcao` | |
| `mattersType` | `tipo` | |
| `phoneOffice` | `telefone` | |
| `phoneMobile` | `tlmvl` | |
| `obs` | `obs` (`text` → `varchar(max)`) | |
| `email` | `email` | |
| `department` | `departamento` | |

`INNER JOIN` com a CL: contactos sem ficha (órfãos) não aparecem.

## 3. Procedimentos

| Procedimento | Parâmetros | O que faz |
|---|---|---|
| `up_crm_enfileirar` | `@ev u_crm_evento_tt READONLY`, `@inseridos int OUTPUT` | Único ponto de escrita na fila: deduplicação, `D` substitui `U` pendente, cria os novos PENDENTE. |
| `up_crm_carga` | `@origem`, `@no` (opcional) | Enfileira contas e depois contactos de um cliente (`@no`) ou de todos. Devolve `contas_enfileiradas`, `contactos_enfileirados`. |
| `up_crm_repor` | `@origem`, `@entidade`, `@codigo`, `@stamp` (todos opcionais) | Repõe ERRO → PENDENTE (só o ERRO mais recente de cada registo; ignora se já há PENDENTE). Devolve `repostos`, `ignorados_ja_pendentes`. |
| `up_crm_consulta_totais` | — | Totais por origem, entidade e estado. |
| `up_crm_consulta_erros` | `@dias` (7) | Erros recentes. |
| `up_crm_consulta_historico` | `@no` | Histórico de um cliente (contas e contactos). |

## 4. Triggers

`tr_crm_cl` (CL), `tr_crm_cl2` (CL2), `tr_crm_u_clcontact` (U_CLCONTACT). Ver [arquitetura.md](arquitetura.md), secção 5.

## 5. Papel de base de dados `crmsync_servico`

`SELECT` nas duas views; `SELECT, UPDATE` em `u_crmfila`; `EXECUTE` nas três consultas. Sem acesso às tabelas do PHC.
