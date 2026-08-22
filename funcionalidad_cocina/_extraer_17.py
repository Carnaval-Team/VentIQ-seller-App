"""Extrae la definicion de fn_registrar_venta_mesa del 17 y la imprime en JSON.

Se usa para pasarla a apply_migration por MCP sin pelear con el escapado del shell.
"""
import json
import os
from pathlib import Path

AQUI = Path(__file__).resolve().parent
SQL = AQUI / "17_cobro_sin_redescontar.sql"

t = SQL.read_text(encoding="utf-8")
ini = t.find("CREATE OR REPLACE FUNCTION public.fn_registrar_venta_mesa")
if ini == -1:
    raise SystemExit("[FALLO] no se encontro la funcion")

marca = "$function$;"
fin = t.find(marca, ini)
if fin == -1:
    raise SystemExit("[FALLO] no se encontro el cierre $function$;")

fn = t[ini : fin + len(marca)]

destino = Path(os.environ["LOCALAPPDATA"]) / "Temp" / "f17.json"
destino.write_text(json.dumps({"query": fn}), encoding="utf-8")

print(f"[OK] {len(fn)} chars -> {destino}")
print(f"[OK] contiene v_lineas_ya_movidas: {'v_lineas_ya_movidas' in fn}")
print(f"[OK] contiene stock_movido: {'stock_movido' in fn}")
print(f"[OK] contiene MESA_NOT_FOUND: {'MESA_NOT_FOUND' in fn}")
