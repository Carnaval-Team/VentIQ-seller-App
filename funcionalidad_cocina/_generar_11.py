"""Genera las secciones 11.3 y 11.4 a partir de las funciones de venta del 03.

Motivo de generarlas con script en vez de escribirlas a mano: son ~350 lineas
cada una y solo cambian TRES bloques. Copiarlas a mano invita a perder algo por
el camino (el bloque de pago monto 0, las validaciones de mesa, etc.).

El script aplica las tres intervenciones y ASSERTA que cada una encontro
exactamente una coincidencia. Si el 03 cambia y un anclaje deja de existir, el
script falla en vez de generar SQL silenciosamente incompleto.

Las tres intervenciones por funcion:

  A. DECLARE            anadir v_ruta / v_id_almacen_origen / v_origen_venta
  B. resolucion ubicacion  buscar en el almacen que resuelva el enrutamiento,
                           con fallback a un layout de la cocina (un plato
                           al_pedido no tiene fila de inventario propia)
  C. descuento          delegar en fn_descontar_venta_enrutada, y NO decrementar
                        el SKU en el INSERT de la venta cuando el origen es
                        cocina (lo hace el helper, evita doble descuento)
"""
import re
import sys
from pathlib import Path

AQUI = Path(__file__).resolve().parent
BASE = AQUI / "03_fix_descuento_bom_por_almacen.sql"

# Rangos verificados del 03 (1-indexed, inclusive/exclusive como en el slice).
RANGOS = {
    "fn_registrar_venta": (57, 404),
    "fn_registrar_venta_mesa": (415, 759),
}


def fallo(msg):
    print(f"[FALLO] {msg}")
    sys.exit(1)


def sustituir_una(texto, patron, nuevo, etiqueta, flags=re.S):
    """Sustituye exigiendo exactamente una coincidencia."""
    n = len(re.findall(patron, texto, flags))
    if n != 1:
        fallo(f"{etiqueta}: se esperaba 1 coincidencia, se encontraron {n}")
    return re.sub(patron, nuevo.replace("\\", "\\\\"), texto, count=1, flags=flags)


def balance_if(texto):
    """(n_if, n_end_if) contando solo sentencias, no la palabra dentro de strings."""
    n_if = len(re.findall(r"^\s*(?:ELSIF|IF)\s", texto, re.M))
    n_end = len(re.findall(r"^\s*END IF\s*;", texto, re.M))
    return n_if, n_end


# ── A · declaraciones ────────────────────────────────────────────────────────
A_PAT = r"    v_descuento_bom JSONB;   -- resultado de fn_descontar_ingredientes_elaborado"
A_NEW = """    v_descuento_bom JSONB;   -- resultado de fn_descontar_venta_enrutada
    -- FASE 1 · enrutamiento a cocina
    v_ruta JSONB;              -- resultado de fn_resolver_origen_venta
    v_id_almacen_origen BIGINT;-- almacen del que realmente sale la linea
    v_origen_venta TEXT;       -- barra | cocina_al_pedido | cocina_por_tanda | servicio"""

# ── B · resolucion de ubicacion ──────────────────────────────────────────────
B_PAT = (
    r"      -- Resolver id_ubicacion: si no viene, buscar la zona del almacen del TPV con mayor stock para el producto\n"
    r"      v_id_ubicacion_resuelto := NULLIF\(v_producto->>'id_ubicacion', ''\)::BIGINT;\n"
    r".*?"
    r"          'id_almacen', v_id_almacen\n"
    r"          \);\n"
    r"        END IF;\n"
    r"      END IF;\n"
)

B_NEW = """      -- ══════════════════════════════════════════════════════════════════════
      -- FASE 1 · Resolver DE DONDE sale esta linea antes de tocar nada.
      --
      -- Sin esto, un plato de cocina moria aqui con NO_LOCATION_FOUND: no tiene
      -- inventario en el almacen de la barra, asi que la busqueda de ubicacion
      -- no encontraba nada y la venta se cortaba ANTES del descuento.
      --
      -- fn_resolver_origen_venta tambien valida el enrutamiento (COCINA_NO_LIGADA,
      -- COCINA_INACTIVA), asi que un TPV no puede vender platos de una cocina a
      -- la que no esta ligado.
      -- ══════════════════════════════════════════════════════════════════════
      v_ruta := public.fn_resolver_origen_venta(
        (v_producto->>'id_producto')::BIGINT,
        p_id_tpv
      );

      IF (v_ruta->>'status') <> 'success' THEN
        RETURN v_ruta;
      END IF;

      v_origen_venta      := v_ruta->>'origen';
      v_id_almacen_origen := (v_ruta->>'id_almacen')::BIGINT;

      -- Resolver id_ubicacion dentro del almacen de ORIGEN (barra o cocina)
      v_id_ubicacion_resuelto := NULLIF(v_producto->>'id_ubicacion', '')::BIGINT;

      IF v_id_ubicacion_resuelto IS NULL THEN
        SELECT ip.id_ubicacion
        INTO v_id_ubicacion_resuelto
        FROM app_dat_inventario_productos ip
        INNER JOIN app_dat_layout_almacen la ON la.id = ip.id_ubicacion
        WHERE ip.id_producto = (v_producto->>'id_producto')::BIGINT
          AND la.id_almacen = v_id_almacen_origen
          AND la.deleted_at IS NULL
          AND COALESCE(ip.id_variante, 0) = COALESCE(NULLIF(v_producto->>'id_variante', '')::BIGINT, 0)
        ORDER BY ip.cantidad_final DESC NULLS LAST, ip.id DESC
        LIMIT 1;

        -- Un plato al_pedido no tiene fila de inventario propia: se fabrica a
        -- partir de ingredientes. La linea de extraccion necesita apuntar a
        -- ALGUNA ubicacion, asi que se usa un layout de la cocina. Solo se
        -- aplica a origenes de cocina: en barra se conserva el comportamiento
        -- previo (y su error) tal cual.
        IF v_id_ubicacion_resuelto IS NULL AND v_origen_venta <> 'barra' THEN
          SELECT la.id
          INTO v_id_ubicacion_resuelto
          FROM app_dat_layout_almacen la
          WHERE la.id_almacen = v_id_almacen_origen
            AND la.deleted_at IS NULL
          ORDER BY la.id
          LIMIT 1;
        END IF;

        IF v_id_ubicacion_resuelto IS NULL THEN
          RETURN jsonb_build_object(
            'status', 'error',
            'message', CASE
                WHEN v_origen_venta = 'barra'
                  THEN 'No se encontró ubicación con stock para el producto en el almacén del TPV'
                ELSE 'La cocina "' || COALESCE(v_ruta->>'cocina', '?')
                     || '" no tiene ubicaciones donde registrar la salida'
              END,
            'error_code', 'NO_LOCATION_FOUND',
            'id_producto', (v_producto->>'id_producto')::BIGINT,
            'id_almacen', v_id_almacen_origen,
            'origen',     v_origen_venta,
            'id_cocina',  v_ruta->'id_cocina',
            'cocina',     v_ruta->'cocina'
          );
        END IF;
      END IF;
"""

# ── C1 · no decrementar el SKU en el INSERT de la venta si es de cocina ──────
C1_PAT = (
    r"        CASE\n"
    r"          WHEN v_es_elaborado = true THEN COALESCE\(ip\.cantidad_final, 0\)\n"
    r"          ELSE COALESCE\(ip\.cantidad_final, 0\) - \(v_producto->>'cantidad'\)::NUMERIC\n"
    r"        END,"
)
C1_NEW = """        CASE
          -- Elaborado/servicio: la venta no decrementa el SKU (lo hace el BOM).
          -- Origen cocina: tampoco, lo descuenta fn_descontar_venta_enrutada
          -- del almacen de la cocina. Sin esta segunda condicion, un producto
          -- por_tanda NO elaborado se descontaria dos veces.
          WHEN v_es_elaborado = true OR v_origen_venta <> 'barra'
            THEN COALESCE(ip.cantidad_final, 0)
          ELSE COALESCE(ip.cantidad_final, 0) - (v_producto->>'cantidad')::NUMERIC
        END,"""

# ── C2 · descuento delegado ──────────────────────────────────────────────────
# El anclaje de cierre va con ^ + MULTILINE: sin anclar, "      END IF;\n" (6
# espacios) tambien casa dentro de "        END IF;\n" (8 espacios) del IF
# interno, cortando la sustitucion antes de tiempo y dejando un END IF huerfano.
C2_PAT = (
    r"      -- ══════════════════════════════════════════════════════════════════════\n"
    r"      -- FASE 0 · Descuento de materia prima acotado al almacen del TPV\.\n"
    r".*?"
    r"      IF v_es_elaborado = true THEN\n"
    r".*?"
    r"^      END IF;\n"
)

C2_NEW = """      -- ══════════════════════════════════════════════════════════════════════
      -- FASE 1 · Descuento enrutado.
      --
      -- Una sola llamada cubre las cuatro rutas:
      --   barra normal      ya descontado arriba -> aqui solo valida
      --   barra elaborado   descuenta receta del almacen del TPV (como Fase 0)
      --   cocina al_pedido  descuenta receta del almacen de la COCINA
      --   cocina por_tanda  descuenta la PORCION hecha del almacen de la cocina
      --                     (sin tocar la receta: la MP se consumio al producir)
      --
      -- p_ya_descontado_sku evita el doble descuento: es true solo cuando el
      -- INSERT de arriba ya decremento el SKU, o sea barra no elaborada.
      -- ══════════════════════════════════════════════════════════════════════
      v_descuento_bom := public.fn_descontar_venta_enrutada(
        p_id_producto       := (v_producto->>'id_producto')::BIGINT,
        p_cantidad          := (v_producto->>'cantidad')::NUMERIC,
        p_id_tpv            := p_id_tpv,
        p_id_extraccion     := v_id_extraccion,
        p_origen_cambio     := 4,
        p_ya_descontado_sku := (v_origen_venta = 'barra' AND v_es_elaborado = false)
      );

      IF (v_descuento_bom->>'status') <> 'success' THEN
        -- El helper ya devuelve error_code + los campos que espera el cliente
        -- (INSUFFICIENT_STOCK_INGREDIENT, INSUFFICIENT_PORTIONS, COCINA_*).
        RETURN v_descuento_bom || jsonb_build_object(
          'id_producto', (v_producto->>'id_producto')::BIGINT,
          'id_almacen',  v_id_almacen_origen
        );
      END IF;
"""


def transformar(nombre, texto):
    # Balance de IF/END IF ANTES, para comparar despues. Las sustituciones no
    # deben alterarlo: si lo hacen, un anclaje comio un END IF de mas.
    if_antes = balance_if(texto)

    texto = sustituir_una(texto, re.escape(A_PAT), A_NEW, f"{nombre} · A declaraciones", flags=0)
    texto = sustituir_una(texto, B_PAT, B_NEW, f"{nombre} · B ubicacion")
    texto = sustituir_una(texto, C1_PAT, C1_NEW, f"{nombre} · C1 insert sin doble descuento")
    texto = sustituir_una(
        texto, C2_PAT, C2_NEW, f"{nombre} · C2 descuento delegado", flags=re.S | re.M
    )

    # B introduce 4 IF nuevos (2 con END IF propio, ver B_NEW) y C1/C2 uno cada
    # bloque; lo que importa es que IF y END IF sigan CUADRANDO entre si.
    n_if, n_end = balance_if(texto)
    if n_if - n_end != if_antes[0] - if_antes[1]:
        fallo(
            f"{nombre}: desbalance IF/END IF. antes {if_antes[0]}/{if_antes[1]}, "
            f"ahora {n_if}/{n_end}. Un anclaje consumio un END IF de mas."
        )

    # Comprobaciones de que no se perdio nada critico.
    obligatorios = [
        "app_dat_extraccion_productos",
        "RETURNING id INTO v_id_extraccion",
        "app_dat_estado_operacion",
        "fn_descontar_venta_enrutada",
        "fn_resolver_origen_venta",
    ]
    if nombre == "fn_registrar_venta":
        obligatorios.append("Venta mostrador - monto 0")
    else:
        obligatorios += ["MESA_NOT_FOUND", "MESA_WRONG_TIENDA"]

    for token in obligatorios:
        if token not in texto:
            fallo(f"{nombre}: se perdio '{token}' en la transformacion")

    if "fn_descontar_ingredientes_elaborado" in texto:
        fallo(f"{nombre}: aun llama al helper viejo directamente")
    if "AND la.id_almacen = v_id_almacen\n" in texto:
        fallo(f"{nombre}: quedo una busqueda de ubicacion atada al almacen del TPV")

    return texto


def main():
    lineas = BASE.read_text(encoding="utf-8").split("\n")
    salida = []

    for nombre, (ini, fin) in RANGOS.items():
        original = "\n".join(lineas[ini - 1 : fin])
        if not original.lstrip().startswith(f"CREATE OR REPLACE FUNCTION public.{nombre}"):
            fallo(f"{nombre}: el rango {ini}..{fin} no empieza donde se esperaba")

        nuevo = transformar(nombre, original)
        salida.append(nuevo)
        print(f"[OK] {nombre}: {len(original)} -> {len(nuevo)} chars")

    destino = AQUI / "_11_funciones_generadas.sql"
    destino.write_text("\n\n\n".join(salida) + "\n", encoding="utf-8")
    print(f"[OK] escrito {destino.name} ({destino.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
