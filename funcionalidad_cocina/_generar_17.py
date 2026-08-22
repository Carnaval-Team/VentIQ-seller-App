"""Genera el 17: fn_registrar_venta_mesa que NO re-descuenta lo ya movido al pedir.

Parte del cuerpo YA ENRUTADO del 11 (_11_funciones_generadas.sql), no del 03:
el 11 esta aplicado en produccion y verificado (enruta=true, helper_viejo=false).

Cambios que aplica (2 por funcion, ambos con assert de 1 coincidencia):

  A. DECLARE     anadir v_ya_movido / v_id_item_cuenta / v_lineas_legado
  B. descuento   antes de descontar, comprobar si la linea de la cuenta abierta
                 ya movio el stock al pedirse (stock_movido = true). Si si,
                 saltar el descuento y contar la linea como ya servida.

Motivo de generar en vez de escribir a mano: el cuerpo tiene ~350 lineas con el
bloque de validaciones de mesa y el de pago monto 0 que no se pueden perder.
"""
import re
import sys
from pathlib import Path

AQUI = Path(__file__).resolve().parent
BASE = AQUI / "_11_funciones_generadas.sql"


def fallo(msg):
    print(f"[FALLO] {msg}")
    sys.exit(1)


def sustituir_una(texto, patron, nuevo, etiqueta, flags=re.S):
    n = len(re.findall(patron, texto, flags))
    if n != 1:
        fallo(f"{etiqueta}: se esperaba 1 coincidencia, se encontraron {n}")
    return re.sub(patron, nuevo.replace("\\", "\\\\"), texto, count=1, flags=flags)


def balance_if(texto):
    return (
        len(re.findall(r"^\s*(?:ELSIF|IF)\s", texto, re.M)),
        len(re.findall(r"^\s*END IF\s*;", texto, re.M)),
    )


# ── A · declaraciones ────────────────────────────────────────────────────────
A_PAT = r"    v_origen_venta TEXT;       -- barra \| cocina_al_pedido \| cocina_por_tanda \| servicio"
A_NEW = """    v_origen_venta TEXT;       -- barra | cocina_al_pedido | cocina_por_tanda | servicio
    -- FASE 2 · cobro que no re-descuenta lo ya movido al pedir
    v_id_cuenta_abierta BIGINT;-- cuenta abierta de la mesa, si la hay
    v_id_item_cuenta BIGINT;   -- linea de esa cuenta que corresponde a este producto
    v_ya_movido BOOLEAN;       -- true si el stock ya salio al pedirse
    v_lineas_ya_movidas INTEGER := 0;
    v_lineas_descontadas INTEGER := 0;"""

# ── B · resolver la cuenta abierta una vez, antes del loop de productos ──────
B_PAT = (
    r"    -- 3\. Procesar cada producto vendido\n"
    r"    FOR v_producto IN SELECT \* FROM jsonb_array_elements\(p_productos\)\n"
    r"    LOOP\n"
)
B_NEW = """    -- ══════════════════════════════════════════════════════════════════════
    -- FASE 2 · Localizar la cuenta abierta de esta mesa.
    --
    -- Si la venta viene de una cuenta abierta, sus lineas pueden traer el stock
    -- YA descontado (fn_pedir_item_cuenta lo movio al pedir). Cobrar tiene que
    -- respetar eso: volver a descontar duplicaria el consumo.
    --
    -- Se busca por mesa y estado abierto, que es como la localiza el resto del
    -- flujo (fn_abrir_cuenta_mesa reusa por (id_mesa, estado = 1)).
    -- ══════════════════════════════════════════════════════════════════════
    IF p_id_mesa IS NOT NULL THEN
      SELECT c.id INTO v_id_cuenta_abierta
        FROM app_dat_mesa_cuenta_abierta c
       WHERE c.id_mesa = p_id_mesa
         AND c.estado = 1
       ORDER BY c.created_at ASC
       LIMIT 1;
    END IF;

    -- 3. Procesar cada producto vendido
    FOR v_producto IN SELECT * FROM jsonb_array_elements(p_productos)
    LOOP
"""

# ── C · el descuento respeta stock_movido ────────────────────────────────────
C_PAT = (
    r"      -- ══════════════════════════════════════════════════════════════════════\n"
    r"      -- FASE 1 · Descuento enrutado\.\n"
    r".*?"
    r"      v_descuento_bom := public\.fn_descontar_venta_enrutada\(\n"
    r".*?"
    r"^      END IF;\n"
)

C_NEW = """      -- ══════════════════════════════════════════════════════════════════════
      -- FASE 2 · Descuento enrutado, SALVO que ya se movio al pedir.
      --
      -- "Pedir != cobrar": si esta linea ya salio del inventario cuando el
      -- mesero la pidio (fn_pedir_item_cuenta), cobrar es un acto puramente
      -- contable. Volver a descontar aqui duplicaria el consumo: cada plato
      -- pagaria su materia prima dos veces.
      --
      -- Se identifica la linea de la cuenta abierta por producto + variante +
      -- presentacion, tomando una que tenga stock_movido = true y no haya sido
      -- consumida ya por otra linea de esta misma venta. Las lineas creadas
      -- antes de la Fase 2 tienen stock_movido = false: se descuentan aqui como
      -- siempre, sin cambio de comportamiento.
      -- ══════════════════════════════════════════════════════════════════════
      v_ya_movido := false;
      v_id_item_cuenta := NULL;

      IF v_id_cuenta_abierta IS NOT NULL THEN
        SELECT i.id INTO v_id_item_cuenta
          FROM app_dat_mesa_cuenta_item i
         WHERE i.id_cuenta = v_id_cuenta_abierta
           AND i.id_producto = (v_producto->>'id_producto')::BIGINT
           AND COALESCE(i.id_variante, 0)
               = COALESCE(NULLIF(v_producto->>'id_variante', '')::BIGINT, 0)
           AND COALESCE(i.id_presentacion, 0)
               = COALESCE(v_producto_presentacion_id, 0)
           AND i.stock_movido = true
         ORDER BY i.id
         LIMIT 1;

        v_ya_movido := (v_id_item_cuenta IS NOT NULL);
      END IF;

      IF v_ya_movido THEN
        -- Ya salio del inventario al pedirse: no se toca nada.
        v_lineas_ya_movidas := v_lineas_ya_movidas + 1;

        -- Marcar la linea como cobrada para que no la reuse otra linea de esta
        -- venta (una venta puede repetir el mismo producto en dos entradas).
        UPDATE app_dat_mesa_cuenta_item
           SET stock_movido = false,
               updated_at = now()
         WHERE id = v_id_item_cuenta;
      ELSE
        v_descuento_bom := public.fn_descontar_venta_enrutada(
          p_id_producto       := (v_producto->>'id_producto')::BIGINT,
          p_cantidad          := (v_producto->>'cantidad')::NUMERIC,
          p_id_tpv            := p_id_tpv,
          p_id_extraccion     := v_id_extraccion,
          p_origen_cambio     := 4,
          p_ya_descontado_sku := (v_origen_venta = 'barra' AND v_es_elaborado = false)
        );

        IF (v_descuento_bom->>'status') <> 'success' THEN
          RETURN v_descuento_bom || jsonb_build_object(
            'id_producto', (v_producto->>'id_producto')::BIGINT,
            'id_almacen',  v_id_almacen_origen
          );
        END IF;

        v_lineas_descontadas := v_lineas_descontadas + 1;
      END IF;
"""

# ── D · el INSERT de inventario tampoco decrementa si ya se movio ────────────
D_PAT = (
    r"          WHEN v_es_elaborado = true OR v_origen_venta <> 'barra'\n"
    r"            THEN COALESCE\(ip\.cantidad_final, 0\)\n"
)
D_NEW = """          -- Ya movido al pedir: el INSERT solo deja rastro, no decrementa.
          WHEN v_es_elaborado = true
               OR v_origen_venta <> 'barra'
               OR v_ya_movido = true
            THEN COALESCE(ip.cantidad_final, 0)
"""

# ── E · exponer el conteo en la respuesta ────────────────────────────────────
E_PAT = r"      'total_productos', jsonb_array_length\(p_productos\),\n"
E_NEW = """      'total_productos', jsonb_array_length(p_productos),
      -- Trazabilidad de la Fase 2: cuantas lineas ya venian descontadas del
      -- momento de pedir y cuantas se descontaron en el cobro.
      'lineas_ya_movidas_al_pedir', v_lineas_ya_movidas,
      'lineas_descontadas_al_cobrar', v_lineas_descontadas,
"""


def transformar(texto):
    if_antes = balance_if(texto)

    texto = sustituir_una(texto, A_PAT, A_NEW, "A declaraciones", flags=0)
    texto = sustituir_una(texto, B_PAT, B_NEW, "B localizar cuenta abierta")
    texto = sustituir_una(texto, C_PAT, C_NEW, "C descuento condicional", flags=re.S | re.M)
    texto = sustituir_una(texto, D_PAT, D_NEW, "D insert sin decrementar", flags=0)
    texto = sustituir_una(texto, E_PAT, E_NEW, "E respuesta", flags=0)

    n_if, n_end = balance_if(texto)
    # C y B anaden IF con su END IF; el delta debe mantenerse.
    if n_if - n_end != if_antes[0] - if_antes[1]:
        fallo(
            f"desbalance IF/END IF: antes {if_antes[0]}/{if_antes[1]}, "
            f"ahora {n_if}/{n_end}"
        )

    obligatorios = [
        "MESA_NOT_FOUND",
        "MESA_WRONG_TIENDA",
        "app_dat_extraccion_productos",
        "RETURNING id INTO v_id_extraccion",
        "app_dat_estado_operacion",
        "fn_resolver_origen_venta",
        "fn_descontar_venta_enrutada",
        "v_id_almacen_origen",
        "stock_movido",
    ]
    for token in obligatorios:
        if token not in texto:
            fallo(f"se perdio '{token}'")

    if "fn_descontar_ingredientes_elaborado" in texto:
        fallo("volvio a aparecer el helper viejo")

    return texto


def main():
    src = BASE.read_text(encoding="utf-8")

    i = src.find("CREATE OR REPLACE FUNCTION public.fn_registrar_venta_mesa")
    if i == -1:
        fallo("no se encontro fn_registrar_venta_mesa en _11_funciones_generadas.sql")

    original = src[i:]
    if not original.rstrip().endswith("$function$;"):
        fallo("el cuerpo extraido no termina en $function$;")

    nuevo = transformar(original)
    print(f"[OK] fn_registrar_venta_mesa: {len(original)} -> {len(nuevo)} chars")

    destino = AQUI / "_17_funcion_generada.sql"
    destino.write_text(nuevo, encoding="utf-8")
    print(f"[OK] escrito {destino.name} ({destino.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
