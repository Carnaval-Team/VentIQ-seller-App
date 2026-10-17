"""Sondea las funciones de `flow` que tocan las migraciones 51 y 52.

Sin token de administracion: usa la anon key publica de la app y el endpoint RPC
de PostgREST. La gracia es que PostgREST resuelve la funcion **por el nombre de
los argumentos**, asi que:

  · 404 PGRST202 "Could not find the function ... in the schema cache"
        -> esa firma NO existe (p. ej. la de 10 args = migracion 52 sin aplicar)
  · cualquier otra respuesta (200, 400, 401, 500...)
        -> la funcion existe y se ejecuto; el cuerpo dice que respondio

Incluye dos controles para saber si el rol anon ve las funciones:
  · fn_que_no_existe_xyz  -> debe dar 404
  · cliente_obtener_servicios -> existe de sobra; si da 404, anon no ve nada y
    los 404 de las funciones admin no son concluyentes.
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

CERO_UUID = "00000000-0000-0000-0000-000000000000"

# (etiqueta, funcion, argumentos, que significa si responde)
CASOS: list[tuple[str, str, dict, str]] = [
    ("control negativo", "fn_que_no_existe_xyz", {}, "debe dar 404 PGRST202"),
    ("control positivo", "cliente_obtener_servicios",
     {"p_incluir_inactivos": False}, "existe: si da 404, anon no ve funciones"),
    ("41 admin_guardar_turno_auto (9 args)", "admin_guardar_turno_auto",
     {"p_uuid_usuario": CERO_UUID, "p_id_local_servicio": 0, "p_nombre": "probe",
      "p_orden": 0, "p_activo": False, "p_precios": {}, "p_hora_inicio": None,
      "p_hora_fin": None, "p_id": None},
     "existe = migracion 41 aplicada"),
    ("52 admin_guardar_turno_auto (10 args, p_id_recurso)", "admin_guardar_turno_auto",
     {"p_uuid_usuario": CERO_UUID, "p_id_local_servicio": 0, "p_nombre": "probe",
      "p_orden": 0, "p_activo": False, "p_precios": {}, "p_hora_inicio": None,
      "p_hora_fin": None, "p_id": None, "p_id_recurso": 0},
     "existe = migracion 52 APLICADA"),
    ("51 calcular_precio_con_reglas", "calcular_precio_con_reglas",
     {"p_id_servicio": 0, "p_datos": {}, "p_moneda": "CUP", "p_cantidad": 1,
      "p_base_unit": None},
     "existe = migracion 51 APLICADA"),
    ("15/51 calcular_precio_reserva", "calcular_precio_reserva",
     {"p_id_servicio": 0, "p_datos": {}, "p_moneda": "CUP", "p_cantidad": 1},
     "existe de siempre"),
    ("21/51 calcular_precio_turno", "calcular_precio_turno",
     {"p_id_servicio": 0, "p_id_turno": 0, "p_datos": {}, "p_moneda": "CUP",
      "p_cantidad": 1},
     "existe de siempre"),
    ("41 admin_guardar_turno (10 args)", "admin_guardar_turno",
     {"p_uuid_usuario": CERO_UUID, "p_id_recurso": 0, "p_nombre": "probe",
      "p_tramos": [], "p_orden": 0, "p_activo": False, "p_id": None,
      "p_precios": {}, "p_hora_inicio": None, "p_hora_fin": None},
     "existe = migracion 41 aplicada"),
]


def rpc(base: str, anon: str, fn: str, args: dict) -> tuple[int, str]:
    datos = json.dumps(args).encode("utf-8")
    req = urllib.request.Request(
        f"{base}/rest/v1/rpc/{fn}",
        data=datos,
        method="POST",
        headers={
            "apikey": anon,
            "Authorization": f"Bearer {anon}",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Accept-Profile": "flow",
            "Content-Profile": "flow",
            "User-Agent": UA,
        },
    )
    try:
        with urllib.request.urlopen(req, context=ssl.create_default_context(), timeout=90) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")


def resumen(cuerpo: str) -> str:
    try:
        j = json.loads(cuerpo)
    except json.JSONDecodeError:
        return cuerpo[:160]
    if isinstance(j, dict):
        if "message" in j:
            return str(j["message"])[:160]
        if "error" in j:
            return f"ok={j.get('ok')} error={j['error']}"[:160]
        return json.dumps(j, ensure_ascii=False)[:160]
    return json.dumps(j, ensure_ascii=False)[:160]


for etiqueta, base, anon in PROYECTOS:
    print("=" * 78)
    print(f"PROYECTO {etiqueta}: {base}  (esquema flow, rol anon)")
    print("=" * 78)
    for nombre, fn, args, nota in CASOS:
        status, cuerpo = rpc(base, anon, fn, args)
        marca = "?" if status == 404 else "!"
        print(f"  [{marca}] {nombre}")
        print(f"      HTTP {status} | {resumen(cuerpo)}")
    print()