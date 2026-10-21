# Email para a Orcinus, 3.º (RASCUNHO — não enviado)

**Para:** João Oliveira <joao.oliveira@orcinus.pt>
**Cc:** Luis Silva <informatica@landeiro.pt>
**De:** Flávio Oliveira <flavio.oliveira@sigmacode.pt>
**Assunto:** Carnes Landeiro – Integração PHC → Somnia CRM: inativar contas e contactos eliminados

---

Bom dia João,

Quando uma ficha ou um contacto é eliminado no PHC, queremos que fique **Inativo** no CRM. Como depois de eliminado já não temos os dados, vamos enviar só os códigos e o estado:

```json
{"accounts":[{"code":"13444-0","status":"Inativo"}]}
{"contacts":[{"accountCode":"13444-0","contactCode":"Adm26101240747,939000002","status":"Inativo"}]}
```

Podem confirmar:

1. A API aceita estes pedidos sem os restantes campos (nome, morada, email, etc.)?
2. Os campos que não enviamos ficam como estão no CRM (sem apagar valores)?
3. O valor `Inativo` está correto, ou preferem `Inactive`?

Obrigado pela disponibilidade.

Com os melhores cumprimentos,

Flávio Oliveira
SigmaCode
flavio.oliveira@sigmacode.pt
