"""Compara el cuerpo de las funciones del 43 contra produccion, ignorando
los comentarios de linea completa (que es lo unico que el archivo agrega).

Uso:
    "$LOCALAPPDATA/Temp/vqsql/Scripts/python.exe" <este script>

Imprime len y huella md5 normalizada del cuerpo sin comentarios, para comparar
contra `length(p.prosrc)` y `md5(lower(regexp_replace(prosrc,'\\s','','g')))`
de pg_proc.
"""
import hashlib
import re
from pathlib import Path

RE_BODY = re.compile(
    r"CREATE\s+OR\s+REPLACE\s+FUNCTION.*?AS\s+\$(\w*)\$(.*?)\$\1\$",
    re.IGNORECASE | re.DOTALL,
)
RE_NAME = re.compile(r"FUNCTION\s+public\.(\w+)", re.IGNORECASE)

# nombre -> huella md5 normalizada en produccion, calculada sobre el cuerpo
# SIN comentarios de linea completa y sin espacios:
#   md5(lower(regexp_replace(regexp_replace(prosrc,
#         '(?m)^[ \t]*--.*$','','g'), '\s','','g')))
# Es la unica comparacion fiable: el `len` crudo difiere porque el archivo lleva
# mas comentarios que los que se aplicaron, y `\s` normaliza los saltos.
PROD = {
    "fn_catalogo_stock_meta": "c33dc2e6a4f84ccdaf4e80e2a78333fb",
    "get_productos_by_categoria_tpv_search_meta_v3": "dd8b983879789c6a2e5b7c37f24cedec",
    "get_productos_by_categoria_tpv_v2": "a642521776b3567a58fde23cb48b3ea8",
}


def main() -> int:
    raiz = Path(__file__).resolve().parent
    archivo = raiz / "43_catalogo_stock_mixto_v3.sql"
    texto = archivo.read_text(encoding="utf-8")
    fallos = 0

    for m in RE_BODY.finditer(texto):
        cabecera = texto[m.start():m.start() + 400]
        name = RE_NAME.search(cabecera)
        if not name:
            continue
        nombre = name.group(1)
        if nombre not in PROD:
            continue

        cuerpo = m.group(2)
        # quitar solo las lineas que son comentario puro
        limpio = "\n".join(
            ln for ln in cuerpo.split("\n") if not ln.strip().startswith("--")
        )
        huella = hashlib.md5(
            re.sub(r"\s", "", limpio).lower().encode("utf-8")
        ).hexdigest()

        hp = PROD[nombre]
        ok_h = huella == hp
        if not ok_h:
            fallos += 1

        print(nombre)
        print(f"   len archivo(sin comentarios)={len(limpio)}  (informativo: el "
              f"`len` en prod puede diferir por el \\n final)")
        print(f"   md5  prod   ={hp}")
        print(f"        archivo={huella}  -> {'OK cuerpo identico' if ok_h else 'DIFIERE'}")
        print()

    print("RESULTADO:", "archivo == produccion (huella normalizada)"
          if not fallos else f"{fallos} funcion(es) DIFIEREN de produccion")
    return 1 if fallos else 0


if __name__ == "__main__":
    raise SystemExit(main())