#!/usr/bin/env python3
"""
API Somnia simulada, só para testes ponta a ponta do serviço (NUNCA fala com o CRM real).

Uso:   python api_simulada.py [porta] [token]        (por defeito: 8099 e "token-simulado")
Controlo em tempo real (HTTP GET):
   /__modo?modo=ok|422|401|206|500&atraso=0     define como responde (atraso em segundos)
   /__pedidos                                   lista os pedidos recebidos (endpoint, códigos; nunca dados pessoais)
   /__limpar                                    apaga a lista de pedidos
Responde como a documentação da API: 200 (tudo gravado), 206 (parte falhou), 422 (pedido inválido), 401.
"""
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

PORTA = int(sys.argv[1]) if len(sys.argv) > 1 else 8099
TOKEN = sys.argv[2] if len(sys.argv) > 2 else "token-simulado"
ESTADO = {"modo": "ok", "atraso": 0.0, "pedidos": []}
LOCK = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    def _enviar(self, codigo, corpo):
        dados = json.dumps(corpo).encode("utf-8")
        self.send_response(codigo)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(dados)))
        self.end_headers()
        self.wfile.write(dados)

    def do_GET(self):
        url = urlparse(self.path)
        consulta = parse_qs(url.query)
        with LOCK:
            if url.path == "/__modo":
                ESTADO["modo"] = consulta.get("modo", ["ok"])[0]
                ESTADO["atraso"] = float(consulta.get("atraso", ["0"])[0])
                return self._enviar(200, {"modo": ESTADO["modo"], "atraso": ESTADO["atraso"]})
            if url.path == "/__pedidos":
                return self._enviar(200, ESTADO["pedidos"])
            if url.path == "/__limpar":
                ESTADO["pedidos"].clear()
                return self._enviar(200, {"ok": True})
        self._enviar(404, {"error": "desconhecido"})

    def do_POST(self):
        url = urlparse(self.path)
        endpoint = parse_qs(url.query).get("entryPoint", [""])[0]
        tamanho = int(self.headers.get("Content-Length", "0"))
        corpo = self.rfile.read(tamanho).decode("utf-8")
        autorizado = self.headers.get("Authorization", "") == f"Bearer {TOKEN}"

        with LOCK:
            modo, atraso = ESTADO["modo"], ESTADO["atraso"]

        try:
            dados = json.loads(corpo)
            nome_lista = next(iter(dados))
            registos = dados[nome_lista]
        except (ValueError, StopIteration, TypeError):
            return self._enviar(422, {"error": "Invalid data content!"})

        campo_codigo = "code" if endpoint == "ImportAccounts" else "contactCode"
        chave_resposta = "account" if endpoint == "ImportAccounts" else "contact"
        codigos = [r.get(campo_codigo, "?") for r in registos]
        # Guarda só o endpoint, os códigos e os nomes dos campos (nunca os valores)
        with LOCK:
            ESTADO["pedidos"].append({"endpoint": endpoint, "codigos": codigos, "campos": sorted(registos[0].keys()) if registos else [],
                                      "tamanhos": {k: len(str(v)) for k, v in (registos[0].items() if registos else [])},
                                      "autorizado": autorizado, "hora": time.strftime("%H:%M:%S")})

        if atraso > 0:
            time.sleep(atraso)
        if not autorizado or modo == "401":
            return self._enviar(401, {"error": "Unauthorized"})
        if modo == "422":
            return self._enviar(422, {"error": "Invalid data content!"})
        if modo == "500":
            return self._enviar(500, {"error": "erro interno simulado"})

        entradas = [{"row": i, chave_resposta: c, "action": "Updated", "id": f"sim-{abs(hash(c)) % 10**8:08d}"}
                    for i, c in enumerate(codigos)]
        if modo == "206" and len(entradas) > 1:
            # Só o primeiro foi gravado: o resto falhou e não vem na lista
            return self._enviar(206, {nome_lista: entradas[:1], "success": 1, "fail": len(entradas) - 1})
        self._enviar(200, {nome_lista: entradas, "success": len(entradas), "fail": 0})

    def log_message(self, *args):   # silencioso
        pass


if __name__ == "__main__":
    print(f"API simulada em http://127.0.0.1:{PORTA}/index.php (token: {TOKEN})", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORTA), Handler).serve_forever()
