"""Con que user-agent Cloudflare deja pasar la peticion al MCP de Supabase.

Respuesta esperada si el UA pasa: HTTP 401 "Invalid access token" (el token esta
mal, pero la peticion llega). Si el UA esta vetado: HTTP 403 Error 1010
"browser_signature_banned" y el token ni se mira.
"""

from __future__ import annotations

import json
import re
import ssl
import urllib.error
import urllib.request
from pathlib import Path

cfg = Path(r"C:\Users\cesar\.dsh\profiles\desktop\cordis.patch.yml").read_text(encoding="utf-8")
token = re.search(r"Bearer (sbp_[A-Za-z0-9]+)", cfg).group(1)
url = re.search(r"url: '(https://mcp\.supabase\.com/mcp[^']*)'", cfg).group(1)

UAS = [
    ("(por defecto de urllib, sin cabecera)", None),
    ("undici", "undici"),
    ("node", "node"),
    ("node-fetch", "node-fetch/1.0 (+https://github.com/bitinn/node-fetch)"),
    ("curl/8.21.0", "curl/8.21.0"),
    ("dsh-mcp-client/1.0", "dsh-mcp-client/1.0"),
    ("navegador (Chrome)", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"),
]

cuerpo = json.dumps({
    "jsonrpc": "2.0", "id": 1, "method": "initialize",
    "params": {"protocolVersion": "2025-06-18", "capabilities": {},
               "clientInfo": {"name": "ua-check", "version": "1.0"}},
}).encode("utf-8")

for etiqueta, ua in UAS:
    cabeceras = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
    }
    if ua:
        cabeceras["User-Agent"] = ua
    req = urllib.request.Request(url, data=cuerpo, headers=cabeceras, method="POST")
    try:
        with urllib.request.urlopen(req, context=ssl.create_default_context(), timeout=60) as r:
            print(f"  HTTP {r.status}  {etiqueta}")
    except urllib.error.HTTPError as e:
        detalle = e.read().decode("utf-8", "replace")
        try:
            j = json.loads(detalle)
            msg = j.get("error_name") or j.get("message") or ""
        except json.JSONDecodeError:
            msg = detalle[:80]
        print(f"  HTTP {e.code}  {etiqueta:38s} -> {msg}")
    except Exception as e:  # noqa: BLE001
        print(f"  ERROR     {etiqueta:38s} -> {type(e).__name__}: {e}")