"""Cliente minimo del MCP de Supabase por HTTP (streamable-http).

El servidor MCP que usa DSH aparece "disconnected", pero el endpoint y el token
viven en el perfil (~/.dsh/profiles/desktop/cordis.patch.yml). Este script habla
el protocolo directamente para poder consultar la base en modo lectura:

    python mcp_supabase.py tools
    python mcp_supabase.py sql consulta.sql

El token NO se imprime nunca.
"""

from __future__ import annotations

import json
import os
import re
import ssl
import sys
import urllib.error
import urllib.request
from pathlib import Path

CFG = Path(r"C:\Users\cesar\.dsh\profiles\desktop\cordis.patch.yml")

_cfg = CFG.read_text(encoding="utf-8")
# El token se puede probar sin tocar el perfil:
#   $env:SUPABASE_MCP_TOKEN = 'sbp_...'   (y SUPABASE_MCP_PROJECT para otro proyecto)
_token = (
    os.environ.get("SUPABASE_MCP_TOKEN", "").strip()
    or re.search(r"Bearer (sbp_[A-Za-z0-9]+)", _cfg).group(1)
)
_url = re.search(r"url: '(https://mcp\.supabase\.com/mcp[^']*)'", _cfg).group(1)
_proyecto = os.environ.get("SUPABASE_MCP_PROJECT", "").strip()
if _proyecto:
    _url = re.sub(r"project_ref=[^&]*", f"project_ref={_proyecto}", _url)

_ctx = ssl.create_default_context()
_sesion: dict[str, str] = {}


def _post(cuerpo: dict | list) -> tuple[int, str]:
    datos = json.dumps(cuerpo).encode("utf-8")
    cabeceras = {
        "Authorization": f"Bearer {_token}",
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
        # Cloudflare (Error 1010) bloquea el user-agent por defecto de urllib.
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
        ),
    }
    if "sid" in _sesion:
        cabeceras["mcp-session-id"] = _sesion["sid"]
    if "proto" in _sesion:
        cabeceras["MCP-Protocol-Version"] = _sesion["proto"]

    req = urllib.request.Request(_url, data=datos, headers=cabeceras, method="POST")
    try:
        with urllib.request.urlopen(req, context=_ctx, timeout=90) as r:
            sid = r.headers.get("mcp-session-id")
            if sid:
                _sesion["sid"] = sid
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        cuerpo = e.read().decode("utf-8", "replace")
        return e.code, cuerpo


def _mensajes(crudo: str) -> list[dict]:
    """Acepta respuesta JSON o SSE (event: message / data: {...})."""
    textos: list[str] = []
    for linea in crudo.splitlines():
        linea = linea.strip()
        if linea.startswith("data:"):
            textos.append(linea[5:].strip())
    if not textos:
        crudo = crudo.strip()
        textos = [crudo] if crudo else []
    salida: list[dict] = []
    for t in textos:
        if not t or t == "[DONE]":
            continue
        try:
            salida.append(json.loads(t))
        except json.JSONDecodeError:
            print(f"[aviso] respuesta no JSON: {t[:300]}")
    return salida


def _log(msg: str) -> None:
    """Diagnostico a stderr, para que `rows` pueda volcar JSON limpio a stdout."""
    print(msg, file=sys.stderr)


def _filas(texto: str) -> object:
    """Extrae el JSON de datos del envoltorio de execute_sql.

    El servidor mete las filas ya serializadas dentro del texto de la respuesta y,
    segun el caso, con un nivel de escapado de mas: `[{\\"a\\":1}]`. Se prueba tal
    cual y, si falla, deshaciendo ese nivel.
    """
    for abre, cierra in (("[", "]"), ("{", "}")):
        i, j = texto.find(abre), texto.rfind(cierra)
        if not (0 <= i < j):
            continue
        crudo = texto[i : j + 1]
        try:
            return json.loads(crudo)
        except json.JSONDecodeError:
            pass
        try:
            return json.loads(json.loads('"' + crudo + '"'))
        except json.JSONDecodeError:
            continue
    raise SystemExit("no se pudo extraer el JSON de la respuesta")


def inicializar() -> bool:
    _log(f"URL: {_url}")
    _log(f"Token: presente (longitud {len(_token)})")
    status, crudo = _post(
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {"name": "dsh-sql-check", "version": "1.0"},
            },
        }
    )
    _log(f"initialize -> HTTP {status}")
    if status != 200:
        _log(crudo[:800])
        return False
    for m in _mensajes(crudo):
        res = m.get("result")
        if res:
            info = res.get("serverInfo") or {}
            _sesion["proto"] = res.get("protocolVersion", "2025-06-18")
            _log(
                f"servidor: {info.get('name')} {info.get('version')} "
                f"| protocolo: {_sesion['proto']} | sesion: {'si' if 'sid' in _sesion else 'no'}"
            )
        elif "error" in m:
            _log(f"error initialize: {m['error']}")
            return False
    # Notificacion obligatoria tras initialize (sin id, no espera respuesta).
    _post({"jsonrpc": "2.0", "method": "notifications/initialized"})
    return True


def herramientas() -> int:
    if not inicializar():
        return 1
    status, crudo = _post({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
    _log(f"tools/list -> HTTP {status}")
    for m in _mensajes(crudo):
        res = m.get("result")
        if not res:
            _log(f"sin result: {m}")
            continue
        for t in res.get("tools", []):
            print(f"  - {t['name']}")
    return 0


def consultar(consulta: str) -> tuple[int, str]:
    """Ejecuta SQL de lectura y devuelve (codigo, texto del servidor)."""
    if not inicializar():
        return 1, ""
    status, crudo = _post(
        {
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {"name": "execute_sql", "arguments": {"query": consulta}},
        }
    )
    _log(f"tools/call execute_sql -> HTTP {status}")
    salida: list[str] = []
    for m in _mensajes(crudo):
        if "error" in m:
            _log(f"ERROR: {json.dumps(m['error'], ensure_ascii=False)[:1500]}")
            return 1, ""
        res = m.get("result") or {}
        for c in res.get("content", []):
            salida.append(c.get("text", ""))
        if res.get("isError"):
            _log("(el servidor marco la llamada como error)")
    return 0, "\n".join(salida)


def sql(consulta: str) -> int:
    codigo, texto = consultar(consulta)
    if texto:
        print(texto)
    return codigo


def rows(consulta: str) -> int:
    codigo, texto = consultar(consulta)
    if codigo != 0:
        return codigo
    datos = _filas(texto)
    print(json.dumps(datos, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    modo = sys.argv[1] if len(sys.argv) > 1 else "tools"
    if modo == "tools":
        raise SystemExit(herramientas())
    if modo == "sql":
        texto = Path(sys.argv[2]).read_text(encoding="utf-8")
        raise SystemExit(sql(texto))
    if modo == "rows":
        texto = Path(sys.argv[2]).read_text(encoding="utf-8")
        raise SystemExit(rows(texto))
    if modo == "init":
        raise SystemExit(0 if inicializar() else 1)
    raise SystemExit(f"modo desconocido: {modo}")