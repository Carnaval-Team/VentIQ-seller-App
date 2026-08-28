"""Valida los .sql de presentaciones_inventario con pglast.

Dos niveles:
  1. parse_sql      -> sintaxis SQL de cada sentencia.
  2. parse_plpgsql  -> sintaxis del cuerpo de cada funcion plpgsql.

Uso:
    "$LOCALAPPDATA/Temp/vqsql/Scripts/python.exe" presentaciones_inventario/_validar_sql.py

No comprueba que tablas o columnas existan; eso lo dice el dashboard (o el
ensayo con BEGIN/ROLLBACK via MCP) al aplicar el archivo.

PITFALL de pglast 8.4 con funciones de trigger: parse_plpgsql() lanza
json.JSONDecodeError al serializar los datums NEW/OLD. Es un bug de
SERIALIZACION, no un error del SQL, asi que se reporta como SKIP.
"""
import json
import re
import sys
from pathlib import Path

import pglast
from pglast import parser

AQUI = Path(__file__).resolve().parent

RE_CREATE_FN = re.compile(
    r"CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION.*?\$(\w*)\$.*?\$\1\$\s*;",
    re.IGNORECASE | re.DOTALL,
)


def _cegar_comentarios(texto: str) -> str:
    """Reemplaza los comentarios `--` por espacios, FUERA de dollar-quoting.

    Devuelve un texto de la MISMA longitud, asi los spans de re.finditer sirven
    para cortar el texto original (que si conserva sus comentarios y por tanto
    sigue siendo SQL valido).

    Por que hace falta: RE_CREATE_FN no sabe de comentarios. Un archivo que
    mencione "CREATE OR REPLACE FUNCTION" dentro de un comentario de cabecera
    hacia que el regex empezara a extraer ahi, y parse_plpgsql recibia un trozo
    que arranca a mitad de frase -> ParseError inventado. Paso de verdad con
    23_compatibilidad_es_base.sql.

    Los comentarios DENTRO de un cuerpo de funcion se dejan intactos: alli no
    hay marcadores de frontera que confundir, y tocarlos seria mas riesgo que
    beneficio.
    """
    salida = list(texto)
    i = 0
    n = len(texto)
    etiqueta = None  # etiqueta del dollar-quote abierto, p.ej. "$fn$"

    while i < n:
        if etiqueta is None:
            if texto.startswith("--", i):
                # Cegar hasta el fin de linea (el \n se conserva).
                j = texto.find("\n", i)
                if j == -1:
                    j = n
                for k in range(i, j):
                    salida[k] = " "
                i = j
                continue
            m = re.match(r"\$(\w*)\$", texto[i:])
            if m:
                etiqueta = m.group(0)
                i += len(etiqueta)
                continue
        else:
            if texto.startswith(etiqueta, i):
                i += len(etiqueta)
                etiqueta = None
                continue
        i += 1

    return "".join(salida)


def validar_sql(texto: str) -> tuple[bool, str]:
    try:
        arbol = pglast.parse_sql(texto)
    except parser.ParseError as exc:
        return False, f"ParseError SQL: {exc}"
    return True, f"{len(arbol)} sentencias"


def validar_plpgsql(texto: str) -> tuple[int, int, list[str]]:
    errores: list[str] = []
    ok = 0
    omitidas = 0

    # Se busca sobre el texto con los comentarios cegados, pero se EXTRAE del
    # original: asi el regex no ancla en un "CREATE OR REPLACE FUNCTION" que solo
    # aparece dentro de un comentario de la cabecera.
    mapa = _cegar_comentarios(texto)

    for match in RE_CREATE_FN.finditer(mapa):
        sentencia = texto[match.start():match.end()]
        if "plpgsql" not in sentencia.lower():
            continue
        try:
            pglast.parse_plpgsql(sentencia)
            ok += 1
        except parser.ParseError as exc:
            cabecera = sentencia.splitlines()[0][:70]
            errores.append(f"{cabecera}... -> {exc}")
        except json.JSONDecodeError:
            omitidas += 1
        except Exception as exc:
            cabecera = sentencia.splitlines()[0][:70]
            errores.append(f"{cabecera}... -> {type(exc).__name__}: {exc}")

    return ok, omitidas, errores


def main() -> int:
    archivos = sorted(p for p in AQUI.glob("*.sql") if not p.name.startswith("_"))
    if not archivos:
        print("No hay .sql en", AQUI)
        return 1

    fallos = 0
    for path in archivos:
        texto = path.read_text(encoding="utf-8")

        ok_sql, detalle_sql = validar_sql(texto)
        if not ok_sql:
            print(f"[FAIL] {path.name}: {detalle_sql}")
            fallos += 1
            continue

        n_ok, n_skip, errores_fn = validar_plpgsql(texto)
        if errores_fn:
            print(f"[FAIL] {path.name}: {detalle_sql}")
            for err in errores_fn:
                print(f"         {err}")
            fallos += 1
            continue

        extra = ""
        if n_ok:
            extra += f", {n_ok} cuerpos plpgsql OK"
        if n_skip:
            extra += f", {n_skip} triggers no inspeccionables (bug pglast)"
        print(f"[PASS] {path.name}: {detalle_sql}{extra}")

    print()
    print(f"{len(archivos) - fallos}/{len(archivos)} archivos validos")
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
