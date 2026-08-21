"""Compara el tamano del cuerpo de las funciones locales de pending_order_edit.sql
contra el largo_cuerpo reportado por produccion (consulta 2.2).

Sirve para decidir si el archivo local se puede usar como base para parchear esas
funciones, o si hay que exportar su definicion real primero.
"""
import re
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]
ARCHIVO = RAIZ / "ventiq_app" / "supabase" / "pending_order_edit.sql"

# largo_cuerpo devuelto por la consulta 2.2 contra el proyecto vsieeihstajlrdvpuooh
PRODUCCION = {
    "fn_actualizar_cantidad_producto_orden": 9311,
    "fn_agregar_producto_orden_pendiente": 9176,
    "fn_eliminar_producto_orden": 5586,
    "_fn_distribuir_pagos_orden": None,  # no aparece en 2.2 (no usa ingredientes)
}

PATRON = re.compile(
    r"CREATE OR REPLACE FUNCTION\s+(\w+)\s*\(.*?\)\s*RETURNS.*?AS \$\$(.*?)\$\$\s*;",
    re.S,
)


def main() -> None:
    texto = ARCHIVO.read_text(encoding="utf-8")

    print(f"{'funcion':45s} {'local(LF)':>10s} {'local(CRLF)':>12s} {'prod':>8s}  {'':s}")
    print("-" * 90)

    for match in PATRON.finditer(texto):
        nombre = match.group(1)
        cuerpo = match.group(2)

        largo_lf = len(cuerpo)
        largo_crlf = len(cuerpo.replace("\r\n", "\n").replace("\n", "\r\n"))
        prod = PRODUCCION.get(nombre)

        if prod is None:
            veredicto = "no comparado"
        elif prod in (largo_lf, largo_crlf):
            veredicto = "IGUAL -> local sirve como base"
        else:
            delta = prod - max(largo_lf, largo_crlf)
            veredicto = f"DISTINTO (prod tiene {delta:+d} chars) -> exportar antes de parchear"

        prod_txt = str(prod) if prod is not None else "-"
        print(f"{nombre:45s} {largo_lf:10d} {largo_crlf:12d} {prod_txt:>8s}  {veredicto}")


if __name__ == "__main__":
    main()
