# ferramentas

`api_simulada.py` é uma API Somnia simulada (nunca fala com o CRM real) para testes ponta a ponta do serviço.

```bash
python api_simulada.py 8099 token-simulado
curl "http://127.0.0.1:8099/__modo?modo=422&atraso=0"    # ok | 422 | 401 | 206 | 500, com atraso em segundos
curl "http://127.0.0.1:8099/__pedidos"                    # pedidos recebidos (endpoint e códigos; nunca dados pessoais)
```

Apontar o serviço para ela: `CrmSync__ApiBaseUrl=http://127.0.0.1:8099/index.php` e `CRMSYNC_API_TOKEN=token-simulado`.
