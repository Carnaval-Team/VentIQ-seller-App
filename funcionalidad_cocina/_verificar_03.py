"""Verificaciones mecanicas sobre 03_fix_descuento_bom_por_almacen.sql.

Por que no se hace un diff contra el repo:
  las copias locales (registrarventa_ok.sql, registrar_venta_mesa.sql) estan
  desactualizadas respecto a produccion (12314 vs 13997 chars en
  fn_registrar_venta), asi que un diff contra ellas no prueba nada.

Lo que si se puede comprobar de forma mecanica es que el 03:
  A. CONSERVA cada bloque que existe en el dump de produccion (consulta 2.1) y
     que no debe perderse al reemplazar la funcion.
  B. YA NO CONTIENE el patron roto de descuento de ingredientes.
  C. SI DELEGA en el helper de la Fase 0.

Los marcadores de (A) se tomaron del dump real de produccion, no del repo.
"""
import re
import sys
from pathlib import Path

AQUI = Path(__file__).resolve().parent
NUEVO = AQUI / "03_fix_descuento_bom_por_almacen.sql"

# ── (A) Fragmentos presentes en el dump de produccion que DEBEN sobrevivir ────
DEBE_CONSERVAR = {
    "fn_registrar_venta": [
        # resolucion de ubicacion por el almacen del TPV
        "AND la.id_almacen = v_id_almacen",
        "'error_code', 'NO_LOCATION_FOUND'",
        # bloque de pago con monto 0 (NO existe en ninguna copia del repo)
        "IF COALESCE(v_total_venta, 0) = 0 THEN",
        "INSERT INTO app_dat_pago_venta (",
        "'Venta mostrador - monto 0'",
        "importe_sin_descuento",
        "referencia_pago",
        # resto del flujo
        "INSERT INTO app_dat_operaciones (",
        "INSERT INTO app_dat_operacion_venta (",
        "INSERT INTO app_dat_extraccion_productos (",
        "INSERT INTO app_dat_estado_operacion (",
        "SELECT (es_elaborado or es_servicio) INTO v_es_elaborado",
        "WHERE denominacion ILIKE '%venta%' LIMIT 1",
        "'Error al registrar venta: ' || SQLERRM",
    ],
    "fn_registrar_venta_mesa": [
        "AND la.id_almacen = v_id_almacen",
        "'error_code', 'NO_LOCATION_FOUND'",
        # validaciones de mesa
        "'error_code', 'MESA_NOT_FOUND'",
        "'error_code', 'MESA_WRONG_TIENDA'",
        "FROM app_dat_mesas",
        "WHERE id = p_id_mesa AND activa = true",
        "'id_mesa', p_id_mesa",
        # resto del flujo
        "INSERT INTO app_dat_operaciones (",
        "INSERT INTO app_dat_operacion_venta (",
        "INSERT INTO app_dat_extraccion_productos (",
        "INSERT INTO app_dat_estado_operacion (",
        "SELECT (es_elaborado or es_servicio) INTO v_es_elaborado",
        "'Error al registrar venta: ' || SQLERRM",
    ],
}

# ── (B) Restos del patron roto que NO deben quedar ───────────────────────────
NO_DEBE_TENER = [
    "v_inventario_ingrediente",
    "v_ingrediente RECORD",
    "fn_obtener_ingredientes_recursivos",  # ahora lo llama el helper, no la venta
]

# ── (C) Delegacion esperada ──────────────────────────────────────────────────
DEBE_DELEGAR = "fn_descontar_ingredientes_elaborado"

# ── El bloque de pago monto 0 solo aplica a fn_registrar_venta ───────────────
SOLO_EN_VENTA = "'Venta mostrador - monto 0'"


def cuerpos(texto: str) -> dict[str, str]:
    patron = re.compile(
        r"CREATE OR REPLACE FUNCTION\s+(?:public\.)?(\w+)\s*\(.*?"
        r"AS \$function\$(.*?)\$function\$\s*;",
        re.S,
    )
    return {m.group(1): m.group(2) for m in patron.finditer(texto)}


def main() -> int:
    texto = NUEVO.read_text(encoding="utf-8")
    funciones = cuerpos(texto)

    esperadas = set(DEBE_CONSERVAR)
    if set(funciones) != esperadas:
        print(f"FAIL: se esperaban {sorted(esperadas)}, se encontro {sorted(funciones)}")
        return 1

    fallos = 0

    for nombre, cuerpo in funciones.items():
        print("=" * 74)
        print(f"FUNCION: {nombre}  ({len(cuerpo)} chars)")
        print("=" * 74)

        # A
        faltantes = [f for f in DEBE_CONSERVAR[nombre] if f not in cuerpo]
        if faltantes:
            fallos += 1
            print(f"  [FAIL] A. conserva bloques de produccion: faltan {len(faltantes)}")
            for f in faltantes:
                print(f"           - {f}")
        else:
            n = len(DEBE_CONSERVAR[nombre])
            print(f"  [PASS] A. conserva los {n} bloques de produccion verificados")

        # B
        restos = [p for p in NO_DEBE_TENER if p in cuerpo]
        if restos:
            fallos += 1
            print(f"  [FAIL] B. quedan restos del patron roto: {restos}")
        else:
            print("  [PASS] B. sin restos del patron roto (lookup global de ingrediente)")

        # C
        if DEBE_DELEGAR in cuerpo:
            print(f"  [PASS] C. delega en {DEBE_DELEGAR}")
        else:
            fallos += 1
            print(f"  [FAIL] C. no delega en {DEBE_DELEGAR}")

        # el helper debe recibir el almacen del TPV
        if "p_id_almacen            := v_id_almacen" in cuerpo:
            print("  [PASS] D. el helper recibe v_id_almacen (almacen del TPV)")
        else:
            fallos += 1
            print("  [FAIL] D. el helper no recibe v_id_almacen")

        print()

    # el bloque de pago 0 no debe filtrarse a la version de mesa
    if SOLO_EN_VENTA in funciones["fn_registrar_venta_mesa"]:
        fallos += 1
        print("[FAIL] el bloque de pago monto 0 se colo en fn_registrar_venta_mesa "
              "(produccion no lo tiene ahi)")
    else:
        print("[PASS] el bloque de pago monto 0 quedo solo en fn_registrar_venta")

    print()
    print("TODO OK" if not fallos else f"{fallos} verificaciones fallaron")
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
