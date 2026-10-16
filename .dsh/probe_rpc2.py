"""Segunda ronda: distingue "la funcion no existe" de "anon no ve nada".

Prueba firmas ANTIGUAS (anteriores a las migraciones 41 y 42). Si responden 200,
el rol anon si ve funciones en ese proyecto y, por tanto, los 404 de las firmas
nuevas significan de verdad "esa migracion no esta aplicada".
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

CASOS = [
    ("cliente_obtener_servicios v7 (pre-42, sin p_incluir_inactivos)",
     "cliente_obtener_servicios",
     {"p_id_local": None, "p_id_servicio": None, "p_id_entidad": None,
      "p_nombre_local": None, "p_nombre_servicio": None, "p_pais": None,
      "p_provincia": None}),
    ("admin_guardar_turno v8 (pre-41, sin horas)",
     "admin_guardar_turno",
     {"p_uuid_usuario": CERO_UUID, "p_id_recurso": 0, "p_nombre": "probe",
      "p_tramos": [], "p_orden": 0, "p_activo": False, "p_id": None,
      "p_precios": {}}),
    ("admin_guardar_turno_auto v9 (41) - repetido como control",
     "admin_guardar_turno_auto",
     {"p_uuid_usuario": CERO_UUID, "p_id_local_servicio": 0, "p_nombre": "probe",
      "p_orden": 0, "p_activo": False, "p_precios": {}, "p_hora_inicio": None,
      "p_hora_fin": None, "p_id": None}),
]


def rpc(base, anon, fn, args):
    datos = json.dumps(args).encode("utf-8")
    req = urllib.request.Request(
        f"{base}/rest/v1/rpc/{fn}", data=datos, method="POST",
        headers={
            "apikey": anon, "Authorization": f"Bearer {anon}",
            "Content-Type": "application/json", "Accept": "application/json",
            "Accept-Profile": "flow", "Content-Profile": "flow",
            "User-Agent": UA,
        },
    )
    try:
        with urllib.request.urlopen(req, context=ssl.create_default_context(), timeout=90) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")


for etiqueta, base, anon in PROYECTOS:
    print("=" * 78)
    print(f"PROYECTO {etiqueta}: {base}")
    print("=" * 78)
    for nombre, fn, args in CASOS:
        status, cuerpo = rpc(base, anon, fn, args)
        try:
            j = json.loads(cuerpo)
            txt = j.get("message") if isinstance(j, dict) and "message" in j else json.dumps(j, ensure_ascii=False)
        except json.JSONDecodeError:
            txt = cuerpo
        print(f"  HTTP {status}  {nombre}")
        print(f"        {str(txt)[:150]}")
    print()