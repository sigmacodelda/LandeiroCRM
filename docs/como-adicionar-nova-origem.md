# Como adicionar uma nova origem (exemplo: fornecedores, FL)

Para acrescentar fornecedores **não se altera o código do serviço**: uma view nova, um trigger novo, uma ramificação
na carga e uma entrada nova na configuração. Colaboradores (PE) seguem os mesmos passos com `COL`.

> **Antes de começar com fornecedores:** a Orcinus tem de confirmar se o `code` das contas é único por `accountType`
> ou global (P3 em [pendencias.md](pendencias.md)). Se for global, um fornecedor com o mesmo número de um cliente
> sobrescreve-o. Resolver isto **antes** de integrar fornecedores.

Os nomes das colunas da `fl` têm de ser confirmados na base de dados (a documentação diz que são iguais às da `cl`;
não se assume). Fazer primeiro a verificação do esquema, como em [arquitetura.md](arquitetura.md), secção 8.1.

## Passo 1 — View `base-dados/02_views/03_u_v_crm_conta_fl.sql`

Mesmo formato da view de clientes: nomes exatos da API, `stamp` e todas as colunas de texto com trim.

```sql
CREATE OR ALTER VIEW dbo.u_v_crm_conta_fl
AS
SELECT
    RTRIM(f.flstamp)                                              AS stamp,
    LTRIM(RTRIM(CONVERT(varchar(20), f.no))) + '-'
        + LTRIM(RTRIM(CONVERT(varchar(10), f.estab)))             AS code,
    LTRIM(RTRIM(f.nome))                                          AS name,
    -- ... address, postalCode, city, country, vatNumber, phone, mobilePhone, email, fax (confirmar os nomes na fl) ...
    CONVERT(varchar(3), 'FOR')                                    AS accountType
FROM dbo.fl AS f;
```

Para contactos de fornecedores, uma `u_v_crm_contacto_fl` com `stamp` e `accountStamp` (ver `u_v_crm_contacto_cl`).

## Passo 2 — Trigger `base-dados/04_triggers/04_tr_crm_fl.sql`

Copiar `tr_crm_cl` e trocar: tabela `fl`, colunas integradas, `'FL'` como origem e `'FOR'` como tipo de conta.
Manter as regras: `EXCEPT` sobre `inserted`/`deleted` (não `UPDATE(coluna)`), `TRY…CATCH` vazio, `SET XACT_ABORT OFF`,
só `EXEC dbo.up_crm_enfileirar @ev`. Tipo de evento: `('FL', 'CONTA', 'FOR', <flstamp>, <NO-ESTAB>, 'U'|'D')`.

Não alterar nem desativar triggers existentes na `fl`. Listá-los antes (`sys.triggers`).

## Passo 3 — Carga `up_crm_carga`

Acrescentar um bloco `IF @origem = 'FL' BEGIN ... END` que enfileira as fichas da `fl` (e os contactos) por
`up_crm_enfileirar`, como o bloco da `CL`. Atualizar a condição inicial que hoje só aceita `'CL'`.

## Passo 4 — Permissões `05_permissoes/01_role_servico.sql`

`GRANT SELECT` nas views novas ao papel `crmsync_servico`.

## Passo 5 — Configuração `appsettings.json` (secção `CrmSync:Sources`)

```json
{
  "Name": "FL-CONTA",
  "Order": 1,
  "Entity": "CONTA",
  "AccountType": "FOR",
  "Origins": [ "FL" ],
  "View": "u_v_crm_conta_fl",
  "Endpoint": "ImportAccounts",
  "RequestListProperty": "accounts",
  "ResponseListProperty": "accounts",
  "ResponseCodeProperty": "account"
}
```

Há uma origem por combinação `Entity` + `AccountType` (o arranque recusa duplicados). Os limites de tamanho dos campos
partilham-se por entidade (`FieldLimits:CONTA`). Para os contactos: `Entity = CONTACTO`, `AccountType = FOR`,
`WaitsForEntity = CONTA`, `Order = 2`.

## Passo 6 — Rollback e documentação

Acrescentar o trigger e a view aos scripts de `99_rollback`, ao `instalar.sql`, e as entradas ao
[dicionario-de-dados.md](dicionario-de-dados.md) e ao [mapeamento-phc-api.md](mapeamento-phc-api.md).

## Passo 7 — Testes (obrigatórios)

- SQL: copiar os asserts de `01_teste_triggers_cl.sql` e `03_teste_views.sql` para a `fl` (insert, update com e sem
  mudança, não integrado, vários registos, delete, deduplicação, formato da view).
- .NET: o teste `ANewSource_NeedsOnlyConfiguration_NotNewCode` (em `SyncCycleRunnerTests`) já prova que uma origem
  nova só precisa de configuração; acrescentar um teste de integração com a view real.
- Carga 1 a 1 com um fornecedor de teste na `LAND2_DEMO`, antes de qualquer carga total.

## Passo 8 — Validar

Instalar na `LAND2_DEMO`, correr os testes, enviar um fornecedor de teste (com a API simulada ou, quando houver
endpoint, o CRM) e só então pedir confirmação para a base real.
