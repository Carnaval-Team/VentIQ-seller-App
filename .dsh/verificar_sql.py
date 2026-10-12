"""Verificacion estructural de los .sql de suscripciones.

No es un parser de PostgreSQL: comprueba lo que mas se rompe al escribir SQL
largo a mano y que un `flutter analyze` no puede ver:

  · bloques dollar-quoted ($tag$ ... $tag$) sin cerrar
  · parentesis desbalanceados fuera de literales y comentarios
  · comillas simples sin cerrar (incluidas las escapadas '')
  · comentarios de bloque /* */ sin cerrar
  · etiquetas de dollar-quote que no coinciden con la de apertura

Uso: python verificar_sql.py <archivo.sql> [<archivo.sql> ...]
"""

import re
import sys

DOLLAR_TAG = re.compile(r"\$([A-Za-z_][A-Za-z0-9_]*)?\$")


def revisar(path: str) -> list[str]:
    texto = open(path, encoding="utf-8").read()
    errores: list[str] = []
    linea = 1

    i = 0
    n = len(texto)
    profundidad = 0
    dollar_abierto: str | None = None
    en_comilla = False
    en_comilla_doble = False
    en_bloque = False

    while i < n:
        c = texto[i]

        if c == "\n":
            linea += 1
            i += 1
            continue

        if en_bloque:
            if texto.startswith("*/", i):
                en_bloque = False
                i += 2
                continue
            i += 1
            continue

        if dollar_abierto is not None:
            if texto.startswith(dollar_abierto, i):
                i += len(dollar_abierto)
                dollar_abierto = None
                continue
            i += 1
            continue

        if en_comilla:
            if c == "'":
                if i + 1 < n and texto[i + 1] == "'":
                    i += 2
                    continue
                en_comilla = False
            i += 1
            continue

        if en_comilla_doble:
            if c == '"':
                en_comilla_doble = False
            i += 1
            continue

        # estado normal
        if texto.startswith("--", i):
            while i < n and texto[i] != "\n":
                i += 1
            continue

        if texto.startswith("/*", i):
            en_bloque = True
            i += 2
            continue

        if c == "'":
            en_comilla = True
            i += 1
            continue

        if c == '"':
            en_comilla_doble = True
            i += 1
            continue

        if c == "$":
            m = DOLLAR_TAG.match(texto, i)
            if m:
                dollar_abierto = m.group(0)
                i = m.end()
                continue

        if c == "(":
            profundidad += 1
        elif c == ")":
            profundidad -= 1
            if profundidad < 0:
                errores.append(f"[{path}:{linea}] parentesis de cierre sin apertura")
                profundidad = 0

        i += 1

    if dollar_abierto is not None:
        errores.append(f"[{path}] bloque dollar-quoted sin cerrar: {dollar_abierto}")
    if profundidad != 0:
        errores.append(f"[{path}] parentesis desbalanceados: profundidad final {profundidad}")
    if en_comilla:
        errores.append(f"[{path}] comilla simple sin cerrar")
    if en_comilla_doble:
        errores.append(f"[{path}] comilla doble sin cerrar")
    if en_bloque:
        errores.append(f"[{path}] comentario /* sin cerrar")

    # Conteo de funciones declaradas, para saber que el archivo no quedo vacio.
    n_fn = len(re.findall(r"create or replace function", texto, re.IGNORECASE))
    print(f"{path}: {n_fn} funcion(es), {linea} lineas, "
          f"{'OK' if not errores else str(len(errores)) + ' error(es)'}")
    return errores


def main() -> int:
    todos: list[str] = []
    for path in sys.argv[1:]:
        todos.extend(revisar(path))
    if todos:
        print("\nERRORES:")
        for e in todos:
            print(" ", e)
        return 1
    print("\nSin errores estructurales.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
