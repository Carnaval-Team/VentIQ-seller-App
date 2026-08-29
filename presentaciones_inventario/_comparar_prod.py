"""Compara el cuerpo de una funcion del repo contra el largo real de produccion.

Uso:
    "$LOCALAPPDATA/Temp/vqsql/Scripts/python.exe" \
        presentaciones_inventario/_comparar_prod.py <archivo.sql> <len_prod> <lineas_prod>

El repo guarda los .sql con CRLF. Postgres devuelve prosrc con CRLF tambien si
asi se aplico, asi que la comparacion es directa: si length(prosrc) coincide con
el largo del cuerpo local, el archivo del repo ES lo que esta en produccion.

Recordatorio del contexto VentIQ: los .sql de la raiz del repo estan
DESINCRONIZADOS con produccion. Este script existe para no reemplazar a ciegas.
"""
import re
import sys
from pathlib import Path

RE_BODY = re.compile(
    r"CREATE\s+OR\s+REPLACE\s+FUNCTION.*?AS\s+\$(\w*)\$(?P<body>.*?)\$\1\$\s*;",
    re.IGNORECASE | re.DOTALL,
)


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1

    path = Path(sys.argv[1])
    if not path.exists():
        print(f"[FAIL] no existe {path}")
        return 1

    # newline="" preserva los CRLF tal cual; Path.read_text() no acepta
    # newline antes de Python 3.13, asi que se abre a mano.
    with path.open("r", encoding="utf-8", newline="") as fh:
        texto = fh.read()
    cuerpos = [m.group("body") for m in RE_BODY.finditer(texto)]

    if not cuerpos:
        print(f"[FAIL] no se encontro ningun CREATE OR REPLACE FUNCTION en {path.name}")
        return 1

    print(f"{path.name}: {len(cuerpos)} funcion(es)")
    for i, body in enumerate(cuerpos, 1):
        con_crlf = len(body)
        sin_cr = len(body.replace("\r", ""))
        lineas = body.count("\n") + 1
        print(f"  #{i}: len_con_crlf={con_crlf}  len_sin_cr={sin_cr}  lineas={lineas}")

    if len(sys.argv) >= 3:
        len_prod = int(sys.argv[2])
        print(f"\n  produccion: length(prosrc)={len_prod}")
        for i, body in enumerate(cuerpos, 1):
            con_crlf = len(body)
            sin_cr = len(body.replace("\r", ""))
            if con_crlf == len_prod:
                print(f"  -> #{i} COINCIDE exacto con CRLF: el repo es lo que hay en prod")
            elif sin_cr == len_prod:
                print(f"  -> #{i} coincide si se normaliza a LF (prod tiene LF)")
            else:
                d1 = con_crlf - len_prod
                print(f"  -> #{i} NO coincide (diferencia {d1:+d} con CRLF, "
                      f"{sin_cr - len_prod:+d} con LF)")

    if len(sys.argv) >= 4:
        lineas_prod = int(sys.argv[3])
        print(f"  produccion: lineas={lineas_prod}")
        for i, body in enumerate(cuerpos, 1):
            n = body.count("\n") + 1
            estado = "coincide" if n == lineas_prod else f"NO ({n - lineas_prod:+d})"
            print(f"  -> #{i} lineas {n}: {estado}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
