"""Compara el CUERPO de las funciones vivas con el del repo que las recrea.

Nuestras migraciones 51 y 52 hacen `create or replace function` copiando el cuerpo
de la version anterior del repo (21, 15 y 41). Si la base tiene una version
distinta -- por ejemplo un arreglo hecho a mano en el SQL Editor, como el que ya
paso con la migracion 39 -- al aplicar las nuestras se perderia ese arreglo.
Esto lo detecta antes: compara sentencia a sentencia y muestra las que difieren.

Uso:  python .dsh\\comparar_defs.py .dsh\\live_defs.json
"""

from __future__ import annotations

import difflib
import json
import re
import sys
from pathlib import Path

RAIZ = Path(r"C:\Users\cesar\Documents\VentIQ-seller-App\inventtia_flow\docs\flow_schema")

# funcion viva -> fichero del repo con la version que deberia estar aplicada
ORIGEN = {
    "calcular_precio_con_reglas": RAIZ / "migraciones/51_precio_turno_con_reglas.sql",
    "calcular_precio_reserva": RAIZ / "migraciones/51_precio_turno_con_reglas.sql",
    "calcular_precio_turno": RAIZ / "migraciones/51_precio_turno_con_reglas.sql",
    "admin_guardar_turno_auto": RAIZ / "migraciones/52_turno_auto_en_recurso_elegido.sql",
}


def desde_repo(ruta: Path, nombre: str) -> str:
    texto = ruta.read_text(encoding="utf-8")
    marca = f"create or replace function flow.{nombre}("
    i = texto.lower().find(marca)
    if i < 0:
        raise SystemExit(f"no encuentro {nombre} en {ruta}")
    tag = re.search(r"\bas\s+(\$[A-Za-z_]*\$)", texto[i:], re.IGNORECASE)
    if not tag:
        raise SystemExit(f"no encuentro el cuerpo de {nombre} en {ruta}")
    inicio = i + tag.end()
    cierre = texto.find(tag.group(1) + ";", inicio)
    return texto[inicio:cierre if cierre > 0 else len(texto)]


def cuerpo(definicion: str) -> str:
    """Saca el texto entre los delimitadores $$ ... $$.

    `pg_get_functiondef` no termina en `;`, asi que si no aparece `$tag$;` se toma
    la ultima aparicion del delimitador (que es la de cierre).
    """
    tag = re.search(r"\bas\s+(\$[A-Za-z_]*\$)", definicion, re.IGNORECASE)
    if not tag:
        return definicion
    inicio = tag.end()
    cierre = definicion.find(tag.group(1) + ";", inicio)
    if cierre < 0:
        cierre = definicion.rfind(tag.group(1))
    return definicion[inicio:cierre] if cierre > inicio else definicion[inicio:]


def sentencias(texto: str) -> list[str]:
    """Quita comentarios, normaliza espacios y parte por `;`."""
    texto = re.sub(r"--[^\n]*", " ", texto)
    texto = re.sub(r"/\*.*?\*/", " ", texto, flags=re.DOTALL)
    texto = re.sub(r"\s+", " ", texto).strip().lower()
    return [s.strip() for s in texto.split(";") if s.strip()]


def leer_json(ruta: str) -> list:
    """Aguanta el UTF-16LE con BOM que deja la redireccion `>` de PowerShell."""
    datos = Path(ruta).read_bytes()
    if datos[:2] in (b"\xff\xfe", b"\xfe\xff"):
        texto = datos.decode("utf-16")
    elif datos[:3] == b"\xef\xbb\xbf":
        texto = datos.decode("utf-8-sig")
    else:
        texto = datos.decode("utf-8")
    return json.loads(texto)


def main() -> int:
    vivo = {f["funcion"]: f["definicion"] for f in leer_json(sys.argv[1])}
    problemas = 0
    for nombre, ruta in ORIGEN.items():
        print("=" * 76)
        print(f"{nombre}   (version del repo: {ruta.name})")
        if nombre not in vivo:
            print("  NO existe en la base (migracion pendiente) -> nada que comparar")
            continue
        repo = sentencias(cuerpo(desde_repo(ruta, nombre)))
        base = sentencias(cuerpo(vivo[nombre]))
        print(f"  sentencias: repo {len(repo)} / base {len(base)}")
        if repo == base:
            print("  IDENTICO: el cuerpo vivo coincide con el del repo (sin drift)")
            continue
        problemas += 1
        ratio = difflib.SequenceMatcher(None, repo, base).ratio()
        print(f"  DISTINTO (parecido {ratio:.2%}). Sentencias que difieren:")
        for linea in difflib.unified_diff(repo, base, fromfile="repo", tofile="base", lineterm=""):
            if linea.startswith(("---", "+++", "@@")):
                continue
            print(f"    {linea[:160]}")
    print("=" * 76)
    print(f"funciones con diferencias: {problemas}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())