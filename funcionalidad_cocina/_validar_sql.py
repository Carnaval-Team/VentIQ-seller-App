"""Valida los .sql de funcionalidad_cocina con pglast.

Dos niveles:
  1. parse_sql      -> sintaxis SQL de cada sentencia.
  2. parse_plpgsql  -> sintaxis del cuerpo de cada funcion plpgsql (lo que va
                       entre $$ ... $$ y que parse_sql trata como un string).

Uso:
    $LOCALAPPDATA/Temp/vqsql/Scripts/python.exe funcionalidad_cocina/_validar_sql.py

No comprueba que las tablas o columnas existan; eso lo dice el dashboard al
aplicar el archivo.

PITFALL de pglast 8.4 con funciones de trigger
----------------------------------------------
pglast.parse_plpgsql() falla con json.JSONDecodeError en funciones
RETURNS trigger. Es un bug de SERIALIZACION de pglast, no un error del SQL: al
volcar los datums implicitos NEW/OLD (PLpgSQL_rec) produce JSON malformado
('{}},{}},...'). Se comprobo que el parseo real ocurre ANTES de esa
serializacion: una funcion de trigger con un END IF faltante sigue lanzando
ParseError correctamente. Por eso JSONDecodeError se reporta como SKIP (no se
pudo inspeccionar en profundidad) y no como fallo, mientras ParseError sigue
siendo fallo.
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


def validar_sql(texto: str) -> tuple[bool, str]:
    try:
        arbol = pglast.parse_sql(texto)
    except parser.ParseError as exc:
        return False, f"ParseError SQL: {exc}"
    return True, f"{len(arbol)} sentencias"


def validar_plpgsql(texto: str) -> tuple[int, int, list[str]]:
    """Parsea el cuerpo de cada CREATE FUNCTION ... LANGUAGE plpgsql.

    Devuelve (revisadas_ok, omitidas, errores).
    """
    errores: list[str] = []
    ok = 0
    omitidas = 0

    for match in RE_CREATE_FN.finditer(texto):
        sentencia = match.group(0)
        if "plpgsql" not in sentencia.lower():
            continue

        try:
            pglast.parse_plpgsql(sentencia)
            ok += 1
        except parser.ParseError as exc:
            # Error real de sintaxis en el cuerpo.
            cabecera = sentencia.splitlines()[0][:70]
            errores.append(f"{cabecera}... -> {exc}")
        except json.JSONDecodeError:
            # Bug de serializacion de pglast con RETURNS trigger. El parseo ya
            # paso; no hay nada que reportar contra este SQL.
            omitidas += 1
        except Exception as exc:  # cualquier otra cosa si es un fallo
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
