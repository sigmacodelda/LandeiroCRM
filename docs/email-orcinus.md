# Email para a Orcinus (RASCUNHO — não enviado)

**Para:** João Oliveira <joao.oliveira@orcinus.pt>
**Cc:** Luis Silva <informatica@landeiro.pt>
**De:** Flávio Oliveira <flavio.oliveira@sigmacode.pt>
**Assunto:** Carnes Landeiro – Integração PHC → Somnia CRM: esclarecimentos sobre a API

---

Bom dia João,

A SigmaCode está a desenvolver a integração do PHC da Carnes Landeiro com o Somnia CRM, com base na documentação "SomniaCRM API v1" (ImportAccounts e ImportContacts). Começamos pelos clientes e respetivos contactos e, mais tarde, incluiremos fornecedores e colaboradores.

Antes de avançarmos para produção, precisamos de esclarecer as questões abaixo. Para cada uma indicamos o impacto e, quando aplicável, o que vamos assumir se não houver resposta até à data limite.

**Prioridade alta (bloqueiam a entrada em produção ou a entrada dos fornecedores)**

1. **Unicidade do "code".** O "code" das contas é único por `accountType` ou é global? Se for global, um fornecedor com o mesmo número de um cliente sobrescreve o cliente.
   *Impacto:* é necessário resolver antes de integrarmos fornecedores.
   *Se não houver resposta:* assumimos que é global e não enviamos fornecedores até confirmação.

2. **Eliminação e inativação.** Existe um endpoint para inativar ou eliminar contas e contactos?
   *Impacto:* hoje as eliminações feitas no PHC não chegam ao CRM.
   *Se não houver resposta:* registamos as eliminações para tratamento manual no CRM.

3. **Campos omitidos e campos vazios.** Um campo omitido no JSON mantém o valor atual no CRM? E um campo enviado vazio apaga o valor existente?
   *Impacto:* define se podemos enviar apenas os campos que mudaram ou se temos de enviar sempre o registo completo.
   *Se não houver resposta:* enviamos sempre o registo completo, incluindo os campos vazios.

4. **Cabeçalho de autorização.** O cabeçalho deve ser `Authorization: Bearer <token>` (sem dois pontos) ou o formato da documentação, com dois pontos, é o correto?
   *Impacto:* afeta todos os pedidos.
   *Se não houver resposta:* usamos o formato standard e testamos a variante se o servidor rejeitar.

5. **Token.** Pode o token atual ser trocado antes do arranque em produção, dado que foi partilhado em documento?

**Prioridade média (afetam a qualidade dos dados e o tratamento de erros)**

6. **Limites e obrigatoriedade dos campos.** Quais são os tamanhos máximos de cada campo e quais são obrigatórios? Os campos `obsCreation`, `obsExclusion`, `currentBalance` e `earliestDueDate` são obrigatórios para clientes?
   *Impacto:* definimos a truncagem dos valores longos e evitamos rejeições.
   *Se não houver resposta:* não truncamos nada e enviamos esses campos vazios.

7. **Formato dos telefones.** Qual o formato esperado para `phone`, `mobilePhone`, `phoneOffice` e `phoneMobile` (apenas dígitos, com indicativo, com espaços)?
   *Impacto:* os números no PHC têm formatos variados.
   *Se não houver resposta:* enviamos os números como estão no PHC, apenas sem espaços no início e no fim.

8. **Resposta 206.** Como vêm identificados os registos que falham e com que mensagem?
   *Impacto:* precisamos disto para registar os erros por registo.

**Prioridade normal**

9. **Ambiente de testes.** Existe um ambiente de testes? Neste momento, os registos de teste ficariam no CRM de produção.
   *Impacto:* os testes com dados reais ficam gravados e, como não há eliminação, não se apagam.

10. **HTTPS.** Está prevista a disponibilização da API em HTTPS? Atualmente o token circula em HTTP na rede interna.

Pedimos uma resposta por escrito até [data a preencher] e, se achar útil, podemos fazer uma chamada curta para rever estes pontos em conjunto.

Obrigado pela atenção e disponibilidade.

Com os melhores cumprimentos,

Flávio Oliveira
SigmaCode
flavio.oliveira@sigmacode.pt
