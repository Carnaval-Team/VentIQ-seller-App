"""Consulta el esquema `flow` real de los dos proyectos Supabase.

Usa la anon key publica que la app lleva embebida (lib/config/supabase_config.dart)
y el endpoint OpenAPI de PostgREST (`GET /rest/v1/` con `Accept-Profile: flow`),
que lista todas las funciones expuestas con el NOMBRE DE SUS PARAMETROS.

Sirve para comprobar, sin tocar datos y sin token de administracion:
  · si existe `flow.calcular_precio_con_reglas` (migracion 51)
  · con que firma estan `calcular_precio_reserva` / `calcular_precio_turno`
  · si `admin_guardar_turno_auto` ya tiene `p_id_recurso` (migracion 52)
"""

from __future__ import annotations

import json
import ssl
import urllib.error
import urllib.request

PROYECTOS = [
    ("release", "https://vsieeihstajlrdvpuooh.supabase.co",
     "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZzaWVlaWhzdGFqbHJkdnB1b29oIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQ1MzIyMDYsImV4cCI6MjA3MDEwODIwNn0.ZQmME9zoNTd77WwblxosRv5nnyMTWN8pKkDA6UMKcO4"),
    ("debug", "https://qhprswhhfasrikhawjoz.supabase.co",
     "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFocHJzd2hoZmFzcmlraGF3am96Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAzNTg0NjksImV4cCI6MjEwNTkzNDQ2OX0.2CsGM_HCmBXNmPs7I8qTmQ9_-ouNsJquamKA593R82s"),
]

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")

BUSCADAS = [
    "calcular_precio_con_reglas",
    "calcular_precio_reserva",
    "calcular_precio_turno",
    "admin_guardar_turno_auto",
    "admin_guardar_turno",
    "admin_eliminar_turno",
]


def pedir(url: str, anon: str, perfil: str) -> tuple[int, str]:
    req = urllib.request.Request(
        url,
        headers={
            "apikey": anon,
            "Authorization": f"Bearer {anon}",
            "Accept-Profile": perfil,
            "Accept": "application/openapi+json",
            "User-Agent": UA,
        },
    )
    try:
        with urllib.request.urlopen(req, context=ssl.create_default_context(), timeout=90) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")


def parametros(spec: dict, ruta: dict) -> list[str]:
    """Nombres de parametros de un RPC, vengan como body (POST) o query (GET)."""
    nombres: list[str] = []
    post = ruta.get("post") or {}
    esquema = (
        post.get("requestBody", {})
        .get("content", {})
        .get("application/json", {})
        .get("schema", {})
    )
    props = esquema.get("properties")
    if isinstance(props, dict):
        nombres = list(props.keys())
    else:
        # PostgREST puede describir el body como una lista de "args".
        for p in esquema.get("items", {}).get("properties", {}).items() if isinstance(esquema.get("items"), dict) else []:
            nombres.append(p[0])
    if not nombres:
        for f in ruta.get("post", {}).get("parameters", []) or []:
            if f.get("in") == "body" and isinstance(f.get("schema"), dict):
                nombres = list(f["schema"].get("properties", {}).keys())
    if not nombres:
        for p in ruta.get("get", {}).get("parameters", []) or []:
            if p.get("in") == "query":
                nombres.append(p.get("name", "?"))
    return nombres


for etiqueta, base, anon in PROYECTOS:
    print("=" * 78)
    print(f"PROYECTO {etiqueta}: {base}   (esquema flow)")
    print("=" * 78)
    status, cuerpo = pedir(f"{base}/rest/v1/", anon, "flow")
    if status != 200:
        print(f"  GET /rest/v1/ -> HTTP {status}: {cuerpo[:400]}")
        continue
    spec = json.loads(cuerpo)
    rutas = spec.get("paths", {})
    rpcs = {r[len("/rpc/"):]: v for r, v in rutas.items() if r.startswith("/rpc/")}
    print(f"  OpenAPI ok: {len(rutas)} rutas, {len(rpcs)} funciones expuestas al rol anon")
    print(f"  tablas/vistas visibles: {len([r for r in rutas if not r.startswith('/rpc/')])}")
    print()
    for fn in BUSCADAS:
        if fn in rpcs:
            args = parametros(spec, rpcs[fn])
            metodos = ",".join(sorted(k for k in rpcs[fn] if k in ("get", "post")))
            print(f"  [SI] {fn}")
            print(f"       parametros ({len(args)}): {', '.join(args) if args else '(sin parametros declarados)'}")
            print(f"       metodos: {metodos}")
        else:
            print(f"  [NO] {fn}  (no aparece para el rol anon)")
    print()
    # Coincidencias de precio para descartar nombres parecidos.
    parecidas = sorted(n for n in rpcs if "precio" in n or "turno" in n)
    print(f"  otras funciones de precio/turno: {', '.join(parecidas)}")
    print()