# Email para a Orcinus (RASCUNHO — não enviado)

**Para:** João Oliveira <joao.oliveira@orcinus.pt>
**Cc:** Luis Silva <informatica@landeiro.pt>
**De:** Flávio Oliveira <flavio.oliveira@sigmacode.pt>
**Assunto:** Carnes Landeiro – Integração PHC → Somnia CRM: esclarecimentos sobre a API

---

Bom dia João,

Estamos a preparar a integração do PHC da Carnes Landeiro com o Somnia CRM, com base na documentação "SomniaCRM API v1" que nos enviaram. Precisamos apenas de esclarecer os pontos indicados abaixo.

**1. Não conseguimos aceder à API (urgente).**
Seguimos a documentação: `POST` para `http://192.168.11.4/carneslandeiro/index.php?entryPoint=ImportAccounts`, com `Content-Type: application/json` e `Authorization: Bearer: <token>`. Em vez de uma resposta JSON, o CRM devolve a página de login. Os pontos de entrada `ImportAccounts` e `ImportContacts` estão ativos nesta instância e o token é válido? Nada foi gravado no vosso CRM.

**2. Código das contas já existentes.** Na importação inicial dos clientes, o "Código PHC" usado foi só o número do cliente (ex.: "13444") ou o número com o estabelecimento (ex.: "13444-0")? Nós vamos enviar "13444-0" para a sede e "13444-1" para o estabelecimento 1. Se o formato for diferente, o CRM cria contas duplicadas em vez de atualizar as existentes.

**3. Campos vazios.** Se enviarmos um campo vazio, o CRM apaga o valor que lá estiver? Queremos evitar apagar dados introduzidos diretamente no CRM.

**4. Eliminar ou inativar.** Existe forma de eliminar ou inativar contas e contactos pela API?

**5. Campos obrigatórios e tamanhos.** Quais campos são obrigatórios e quais os tamanhos máximos?

**6. Ambiente de testes.** Existe um ambiente de testes? Se não, vamos testar com poucos registos no CRM de produção, e precisamos de saber como os eliminar depois.

Agradecemos uma resposta por escrito até [data a preencher].

Obrigado pela disponibilidade.

Com os melhores cumprimentos,

Flávio Oliveira
SigmaCode
flavio.oliveira@sigmacode.pt
