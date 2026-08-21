"""Verificaciones mecanicas sobre 06_fix_edicion_orden_pendiente.sql.

Mismo criterio que _verificar_03.py: no se hace diff contra el repo porque las
copias locales estan desactualizadas. Se comprueba contra fragmentos tomados del
dump real de produccion (consulta 4.1):

  A. cada bloque de produccion que debe sobrevivir sigue presente
  B. no quedan restos del patron roto
  C. delega en los helpers correctos
  D. el criterio (es_elaborado OR es_servicio) quedo unificado en las tres
"""
import re
import sys
from pathlib import Path

AQUI = Path(__file__).resolve().parent
NUEVO = AQUI / "06_fix_edicion_orden_pendiente.sql"

DEBE_CONSERVAR = {
    "fn_actualizar_cantidad_producto_orden": [
        "'Extracción no encontrada'",
        "'Solo se pueden editar órdenes en estado Pendiente'",
        "Para eliminar usa fn_eliminar_producto_orden.",
        "'Stock insuficiente para aumentar la cantidad'",
        "PERFORM _fn_distribuir_pagos_orden(v_extraccion.op_id, v_nuevo_total)",
        "'update_quantity'",
        "INSERT INTO app_dat_log_modificacion_orden",
        "importe_real    = p_nueva_cantidad * COALESCE(v_extraccion.precio_unitario, 0)",
        "'Cantidad actualizada correctamente'",
        "3,   -- Origen: Venta / ajuste",
    ],
    "fn_agregar_producto_orden_pendiente": [
        "El producto debe incluir id_producto, cantidad, precio_unitario e id_medio_pago",
        "RETURN fn_actualizar_cantidad_producto_orden(",
        "INSERT INTO app_dat_extraccion_productos (",
        "SET monto = monto + v_importe",
        "INSERT INTO app_dat_pago_venta (id_operacion_venta, id_medio_pago, monto, created_at)",
        "'add_product'",
        "'Producto agregado correctamente'",
        "NULLIF(p_producto->>'precio_real','')::NUMERIC",
    ],
    "fn_eliminar_producto_orden": [
        "'Extracción no encontrada'",
        "'Solo se pueden editar órdenes en estado Pendiente'",
        "DELETE FROM app_dat_extraccion_productos WHERE id = p_id_extraccion",
        "IF v_nuevo_total > 0 THEN",
        "'remove_product'",
        "'Producto eliminado correctamente'",
        "-- devolver stock",
    ],
}

NO_DEBE_TENER = [
    "v_inv_ingrediente",
    "v_ingrediente       RECORD",
    "v_ingrediente      RECORD",
    "fn_obtener_ingredientes_recursivos",
]

# helper esperado por funcion
DEBE_DELEGAR = {
    "fn_actualizar_cantidad_producto_orden": [
        "fn_descontar_ingredientes_elaborado",  # sube cantidad
        "fn_devolver_ingredientes_elaborado",   # baja cantidad
        "fn_almacen_de_extraccion",
    ],
    "fn_agregar_producto_orden_pendiente": [
        "fn_descontar_ingredientes_elaborado",
        "fn_almacen_de_operacion",
    ],
    "fn_eliminar_producto_orden": [
        "fn_devolver_ingredientes_elaborado",
        "fn_almacen_de_extraccion",
    ],
}

CRITERIO = "es_elaborado or es_servicio"


def cuerpos(texto: str) -> dict[str, str]:
    patron = re.compile(
        r"CREATE OR REPLACE FUNCTION\s+(?:public\.)?(\w+)\s*\(.*?"
        r"AS \$function\$(.*?)\$function\$\s*;",
        re.S,
    )
    return {m.group(1): m.group(2) for m in patron.finditer(texto)}


def sin_comentarios(cuerpo: str) -> str:
    """Quita comentarios -- de linea, para que el chequeo B mire codigo real.

    Los comentarios del 06 explican el patron roto por su nombre, asi que
    buscarlo en el texto crudo da falsos positivos.
    """
    return "\n".join(
        re.sub(r"--.*$", "", linea) for linea in cuerpo.splitlines()
    )


def main() -> int:
    funciones = cuerpos(NUEVO.read_text(encoding="utf-8"))

    if set(funciones) != set(DEBE_CONSERVAR):
        print(f"FAIL: esperaba {sorted(DEBE_CONSERVAR)}, encontro {sorted(funciones)}")
        return 1

    fallos = 0

    for nombre, cuerpo in funciones.items():
        print("=" * 74)
        print(f"FUNCION: {nombre}  ({len(cuerpo)} chars)")
        print("=" * 74)

        faltantes = [f for f in DEBE_CONSERVAR[nombre] if f not in cuerpo]
        if faltantes:
            fallos += 1
            print(f"  [FAIL] A. faltan {len(faltantes)} bloques de produccion:")
            for f in faltantes:
                print(f"           - {f}")
        else:
            print(f"  [PASS] A. conserva los {len(DEBE_CONSERVAR[nombre])} bloques verificados")

        restos = [p for p in NO_DEBE_TENER if p in sin_comentarios(cuerpo)]
        if restos:
            fallos += 1
            print(f"  [FAIL] B. restos del patron roto: {restos}")
        else:
            print("  [PASS] B. sin restos del patron roto (ignorando comentarios)")

        sin_delegar = [h for h in DEBE_DELEGAR[nombre] if h not in cuerpo]
        if sin_delegar:
            fallos += 1
            print(f"  [FAIL] C. no delega en: {sin_delegar}")
        else:
            print(f"  [PASS] C. delega en {', '.join(DEBE_DELEGAR[nombre])}")

        if CRITERIO in cuerpo:
            print(f"  [PASS] D. usa el criterio unificado ({CRITERIO})")
        else:
            fallos += 1
            print(f"  [FAIL] D. no usa el criterio unificado ({CRITERIO})")

        print()

    # el fix del stock fantasma: eliminar ya NO debe usar es_elaborado a secas
    elim = funciones["fn_eliminar_producto_orden"]
    if re.search(r"SELECT es_elaborado INTO v_es_elaborado", elim):
        fallos += 1
        print("[FAIL] fn_eliminar_producto_orden sigue con 'SELECT es_elaborado' a secas "
              "-> seguiria creando stock fantasma en servicios")
    else:
        print("[PASS] fn_eliminar_producto_orden ya no usa es_elaborado a secas")

    print()
    print("TODO OK" if not fallos else f"{fallos} verificaciones fallaron")
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
