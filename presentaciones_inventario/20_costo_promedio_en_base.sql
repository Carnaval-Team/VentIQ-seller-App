-- ============================================================================
-- 20 · Costo promedio ponderado en unidades base (Fase 3)
-- ============================================================================
-- FASE 3 de docs/PLAN_PRESENTACIONES_INVENTARIO.md (§ "Costos").
--
-- Objetivo del plan: «ponderar en unidades base; actualizar solo `es_base`».
--
-- ----------------------------------------------------------------------------
-- Hallazgo previo: la v2 está ROTA, no solo mal ponderada
-- ----------------------------------------------------------------------------
-- `fn_actualizar_precio_promedio_recepcion_v2` es la que llama la app
-- (`inventory_service.dart:3721`). Ejecutada contra producción **falla siempre**
-- que le llegue al menos un producto válido:
--
--   SELECT * FROM public.fn_actualizar_precio_promedio_recepcion_v2(
--     999999999, jsonb_build_array(jsonb_build_object(
--       'id_presentacion',336,'precio_unitario',10,'cantidad',5)));
--
--   success = false
--   mensaje = 'Error en fn_actualizar_precio_promedio_recepcion_v2:
--              column reference "cantidad" is ambiguous'
--
-- Probado con 1 fila, 2 filas y con una presentación inexistente: **los tres
-- casos dan el mismo error**. Solo devuelve `true` con lista vacía ("No hay
-- productos para procesar") y con devoluciones (sale por el guard antes de
-- tocar SQL).
--
-- La causa: los subselects correlacionados
--
--     (SELECT cantidad FROM app_dat_inventario_productos
--       WHERE id_presentacion = pe.id_presentacion
--       ORDER BY created_at DESC LIMIT 1)
--
-- referencian una columna `cantidad` que **no existe** en
-- `app_dat_inventario_productos` (sus columnas son `cantidad_inicial` y
-- `cantidad_final`). Postgres entonces la resuelve contra el CTE externo
-- `productos_entrada`, que sí tiene `cantidad`... y también la tiene
-- `app_dat_producto_presentacion` del LEFT JOIN → ambigüedad. Ese subselect
-- aparece **8 veces** en el cuerpo.
--
-- Es un error de resolución de nombres, así que salta en tiempo de ejecución, no
-- al crear la función. Y como el `EXCEPTION WHEN OTHERS` de la v2 lo convierte en
-- `success=false` + mensaje, la app lo trata como un aviso: `updateAveragePrice-
-- AfterReception` devuelve `status: 'error'` y sigue. **Ninguna recepción ha
-- actualizado el costo promedio por esta vía**; los costos que hay vienen de
-- otras rutas (`bulk_update_precios_costo`,
-- `configurar_precios_recepcion_consignacion`,
-- `fn_inicializar_precio_promedio_desde_primera_recepcion`,
-- `fn_admin_caja_actualizar_precios_offline`, `bulk_import_productos_excel`).
--
-- Existe una `v3` (más corta, sin el bug de nombres: usa `cantidad_inicial` y
-- filtra por `id_recepcion = p_id_operacion`) pero **nadie la llama**: 0
-- referencias en Dart y 0 dentro de otras funciones de Postgres.
--
-- ----------------------------------------------------------------------------
-- El bug de ponderación (el que pide el plan)
-- ----------------------------------------------------------------------------
-- Incluso arreglando el nombre de columna, la fórmula pondera **cantidades de
-- presentaciones distintas como si fueran la misma unidad**:
--
--     precio_nuevo = (precio_ant * cant_ant + precio_unit * cant_recibida)
--                    / (cant_ant + cant_recibida)
--
-- Con 10 Bolsas a 1 USD en stock y una recepción de 2 Bultos (de 10 Bolsas) a
-- 9,50 USD, eso da (10 + 19) / 12 = 2,42 — un número que no es el costo de nada.
-- El promedio ponderado solo tiene sentido en una unidad común: la base.
--
-- Y el destino también estaba mal: escribía el promedio en la fila de la
-- presentación recibida. El costo del producto debe vivir en **una sola**
-- presentación (la base) y derivarse por factor; si cada presentación guarda su
-- propio promedio, se contradicen. Medido hoy: de 40 productos
-- multipresentación con costo, **21 tienen costos inconsistentes** entre sus
-- presentaciones y **11 con desvío > 2×**. Ejemplo (producto 6841):
--
--     Bulto  factor 10  precio_promedio   9,80  → 0,98 por Bolsa
--     Bolsa  factor  1  precio_promedio 186,64  → 186,64 por Bolsa   (190× más)
--
-- ----------------------------------------------------------------------------
-- Qué hace este archivo
-- ----------------------------------------------------------------------------
-- Reemplaza la v2 (misma firma, la app no cambia) con una implementación que:
--
--   1. Convierte a base:  cant_base = cantidad * factor_rel
--                         costo_base = precio_unitario / factor_rel
--   2. Pondera en base contra el saldo REAL en base del producto en toda la
--      tienda (`fn_stock_saldos_presentacion`), no contra `cantidad_inicial` de
--      una fila del ledger elegida por `created_at DESC`.
--   3. Escribe **solo en la fila base** del producto.
--   4. Agrupa varias líneas del mismo producto en una sola ponderación (una
--      recepción mixta trae Cajas y Unidades del mismo producto: procesarlas en
--      serie hacía que la segunda ponderara contra un promedio que la primera
--      acababa de mover).
--   5. Sale con `success=false` y mensaje claro cuando la presentación no existe
--      o no pertenece al producto, en vez de saltar la fila en silencio.
--
-- Guardas que se conservan de la v2: devoluciones (`app_dat_consignacion_envio`
-- tipo 2) y `fn_es_operacion_sin_actualizar_precio_costo` (transferencias /
-- operaciones internas) — el `19` demostró lo caro que sale tocar costos sin
-- entender el caso.
--
-- ⚠️ `trg_registrar_precio_costo` dispara AFTER UPDATE OF precio_promedio e
-- inserta en `app_dat_precio_costo` (la FK que produce el 23503 documentado en el
-- README). No se toca: el historial de costo debe seguir registrándose.
--
-- Idempotente: `CREATE OR REPLACE`. No borra la v3 (queda como referencia).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_actualizar_precio_promedio_recepcion_v2(
    p_id_operacion bigint,
    p_productos    jsonb
)
RETURNS TABLE(success boolean, mensaje text, productos_actualizados integer, tiempo_ms integer)
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_inicio        timestamptz := clock_timestamp();
    v_actualizados  int := 0;
    v_tiempo        int;
    v_es_devolucion boolean;
    v_fila          record;
    v_id_base       bigint;
    v_saldo_base    numeric;
    v_costo_ant     numeric;
    v_costo_nuevo   numeric;
BEGIN
    -- ── Guardas heredadas de la v2 ──────────────────────────────────────────
    SELECT EXISTS (
        SELECT 1 FROM app_dat_consignacion_envio
         WHERE id_operacion_recepcion = p_id_operacion
           AND tipo_envio = 2
    ) INTO v_es_devolucion;

    IF v_es_devolucion THEN
        v_tiempo := (EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)) * 1000)::int;
        RETURN QUERY SELECT TRUE,
            'Operación de devolución - precio promedio no actualizado'::text, 0, v_tiempo;
        RETURN;
    END IF;

    IF public.fn_es_operacion_sin_actualizar_precio_costo(p_id_operacion) THEN
        v_tiempo := (EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)) * 1000)::int;
        RETURN QUERY SELECT TRUE,
            'La operación es una transferencia, devolución u operación interna; no modifica el costo promedio'::text,
            0, v_tiempo;
        RETURN;
    END IF;

    IF p_productos IS NULL
       OR jsonb_typeof(p_productos) <> 'array'
       OR jsonb_array_length(p_productos) = 0 THEN
        v_tiempo := (EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)) * 1000)::int;
        RETURN QUERY SELECT TRUE, 'No hay productos para procesar'::text, 0, v_tiempo;
        RETURN;
    END IF;

    -- ── Validación temprana: presentación inexistente o de otro producto ────
    --
    -- La v2 hacía CONTINUE en silencio. Con el hallazgo del `19` (6 filas de
    -- inventario apuntando a presentaciones de otro producto) un id equivocado
    -- aquí escribiría el costo en la base de un producto ajeno.
    FOR v_fila IN
        SELECT (e->>'id_presentacion')::bigint AS id_pp
          FROM jsonb_array_elements(p_productos) e
         WHERE NULLIF(e->>'id_presentacion','') IS NOT NULL
    LOOP
        IF NOT EXISTS (SELECT 1 FROM app_dat_producto_presentacion pp
                        WHERE pp.id = v_fila.id_pp) THEN
            v_tiempo := (EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)) * 1000)::int;
            RETURN QUERY SELECT FALSE,
                format('La presentacion %s no existe', v_fila.id_pp)::text, 0, v_tiempo;
            RETURN;
        END IF;
    END LOOP;

    -- ── Ponderación en unidades base, agrupada por producto ─────────────────
    FOR v_fila IN
        WITH entrada AS (
            SELECT (e->>'id_presentacion')::bigint AS id_pp,
                   (e->>'precio_unitario')::numeric AS precio_unitario,
                   (e->>'cantidad')::numeric        AS cantidad
              FROM jsonb_array_elements(p_productos) e
             WHERE NULLIF(e->>'id_presentacion','') IS NOT NULL
               AND NULLIF(e->>'precio_unitario','') IS NOT NULL
               AND NULLIF(e->>'cantidad','')        IS NOT NULL
               AND (e->>'precio_unitario')::numeric > 0
               AND (e->>'cantidad')::numeric        > 0
        ),
        -- factor_rel de CADA linea (no el de la base: ver el bug del `18`)
        con_factor AS (
            SELECT pp.id_producto,
                   en.cantidad * COALESCE(f.factor_rel, 1)        AS cant_base,
                   en.precio_unitario / NULLIF(COALESCE(f.factor_rel, 1), 0) AS costo_base
              FROM entrada en
              JOIN app_dat_producto_presentacion pp ON pp.id = en.id_pp
              LEFT JOIN LATERAL public.fn_presentaciones_producto(pp.id_producto) f
                     ON f.id_presentacion = pp.id
        )
        -- Una sola ponderación por producto: si la recepción trae Cajas y
        -- Unidades del mismo producto, procesarlas en serie haría que la segunda
        -- pondere contra un promedio que la primera acaba de mover.
        SELECT id_producto,
               SUM(cant_base)              AS cant_base,
               SUM(cant_base * costo_base) AS importe_base
          FROM con_factor
         WHERE cant_base > 0 AND costo_base IS NOT NULL
         GROUP BY id_producto
    LOOP
        -- La fila base del producto: unico lugar donde vive el costo.
        SELECT c.id_presentacion INTO v_id_base
          FROM public.fn_presentaciones_producto(v_fila.id_producto) c
         WHERE c.es_base
         LIMIT 1;

        IF v_id_base IS NULL THEN
            CONTINUE;  -- producto sin presentaciones: nada donde escribir
        END IF;

        SELECT COALESCE(pp.precio_promedio, 0) INTO v_costo_ant
          FROM app_dat_producto_presentacion pp
         WHERE pp.id = v_id_base
           FOR UPDATE;

        -- Saldo real en unidades base ANTES de esta recepcion.
        --
        -- La v2 usaba `cantidad_inicial` de una fila del ledger elegida por
        -- created_at DESC, que es el saldo de UNA ubicacion en un instante
        -- arbitrario. El costo promedio es del producto, asi que el peso tiene
        -- que ser todo lo que hay de ese producto.
        SELECT COALESCE(SUM(s.equivalente_base), 0) INTO v_saldo_base
          FROM public.fn_stock_saldos_presentacion(v_fila.id_producto, NULL, NULL, false) s;

        -- El saldo leido YA incluye esta recepcion si el ledger se escribio
        -- antes de llamar aqui, asi que se descuenta para no contarla dos veces.
        v_saldo_base := GREATEST(v_saldo_base - v_fila.cant_base, 0);

        IF v_costo_ant <= 0 OR v_saldo_base <= 0 THEN
            -- Sin costo previo o sin saldo previo: el costo es el de la compra.
            v_costo_nuevo := v_fila.importe_base / v_fila.cant_base;
        ELSE
            v_costo_nuevo := ((v_costo_ant * v_saldo_base) + v_fila.importe_base)
                             / (v_saldo_base + v_fila.cant_base);
        END IF;

        -- `.neq()` implícito: Postgres dispara triggers por fila AFECTADA, no
        -- por fila que cambia de valor (lección del README). Reescribir el mismo
        -- valor metería una fila espuria en app_dat_precio_costo vía
        -- trg_registrar_precio_costo.
        --
        -- El `::real` NO es decorativo: `precio_promedio` es `real` (float4) y
        -- comparar el valor guardado contra el numeric de precisión completa da
        -- SIEMPRE distinto (61.8971 <> 61.89710000000000001), así que sin el
        -- cast la guarda no filtra nada. Verificado en producción: sin `::real`,
        -- dos llamadas idénticas metían dos filas en el historial de costo.
        UPDATE app_dat_producto_presentacion
           SET precio_promedio = v_costo_nuevo
         WHERE id = v_id_base
           AND COALESCE(precio_promedio, -1) <> v_costo_nuevo::real;

        IF FOUND THEN
            v_actualizados := v_actualizados + 1;
        END IF;
    END LOOP;

    v_tiempo := (EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)) * 1000)::int;

    RETURN QUERY SELECT TRUE,
        format('Se actualizaron %s costos promedio (ponderados en unidades base)', v_actualizados)::text,
        v_actualizados, v_tiempo;

EXCEPTION WHEN OTHERS THEN
    -- Se conserva el patrón de la v2 (la app espera success/mensaje, no una
    -- excepción) pero el mensaje ahora incluye SQLSTATE para no volver a tener
    -- un fallo permanente disfrazado de aviso.
    v_tiempo := (EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)) * 1000)::int;
    RETURN QUERY SELECT FALSE,
        format('Error en fn_actualizar_precio_promedio_recepcion_v2 [%s]: %s', SQLSTATE, SQLERRM)::text,
        0, v_tiempo;
END;
$$;

COMMENT ON FUNCTION public.fn_actualizar_precio_promedio_recepcion_v2(bigint, jsonb) IS
    'Costo promedio ponderado EN UNIDADES BASE, escrito solo en la presentacion base del producto. Reemplaza la version que ponderaba cantidades de presentaciones distintas como si fueran la misma unidad (y que ademas fallaba siempre con "column reference cantidad is ambiguous"). Agrupa varias lineas del mismo producto en una sola ponderacion. Ver presentaciones_inventario/20.';

GRANT EXECUTE ON FUNCTION public.fn_actualizar_precio_promedio_recepcion_v2(bigint, jsonb)
    TO anon, authenticated, service_role;


-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================

-- V1 · ⭐ La v2 vieja fallaba siempre. Antes de aplicar este archivo:
--
--   SELECT success, mensaje FROM public.fn_actualizar_precio_promedio_recepcion_v2(
--     999999999, jsonb_build_array(jsonb_build_object(
--       'id_presentacion',336,'precio_unitario',10,'cantidad',5)));
--   -- medido ANTES: false, 'column reference "cantidad" is ambiguous'
--   -- espera DESPUES: true, 'Se actualizaron 1 costos promedio...'

-- V2 · Ponderación en base. Ensayo con ROLLBACK sobre el producto 6841
--      (Bolsa base id 6946 costo 186,64 / Bulto id 6947 factor 10):
--
--   BEGIN;
--     SELECT public.fn_stock_saldos_presentacion(6841, NULL, NULL, false);  -- saldo previo
--     SELECT * FROM public.fn_actualizar_precio_promedio_recepcion_v2(
--       999999999,
--       jsonb_build_array(jsonb_build_object(
--         'id_presentacion', 6947,      -- 2 Bultos = 20 Bolsas
--         'precio_unitario', 100,       -- 100 por Bulto = 10 por Bolsa
--         'cantidad', 2)));
--     SELECT id, precio_promedio FROM app_dat_producto_presentacion
--      WHERE id_producto = 6841 ORDER BY id;
--   ROLLBACK;
--
--   Esperado: el costo se escribe en 6946 (la BASE), no en 6947, y ponderado
--   en Bolsas: con 14 Bolsas previas a 186,64 y 20 Bolsas nuevas a 10 →
--   (14*186,64 + 20*10) / 34 ≈ 82,7. Con la fórmula vieja habría salido
--   (14*186,64 + 2*100) / 16 ≈ 175,8, un número sin unidad.

-- V3 · Presentación inexistente: rechazo explícito, no salto en silencio.
--
--   SELECT success, mensaje FROM public.fn_actualizar_precio_promedio_recepcion_v2(
--     999999999, jsonb_build_array(jsonb_build_object(
--       'id_presentacion',99999999,'precio_unitario',10,'cantidad',5)));
--   -- espera: false, 'La presentacion 99999999 no existe'

-- V4 · Las guardas siguen vivas (transferencias y devoluciones).
--
--   SELECT success, mensaje FROM public.fn_actualizar_precio_promedio_recepcion_v2(
--     <id_operacion_de_transferencia>, jsonb_build_array(...));
--   -- espera: true, 'La operación es una transferencia...', 0 actualizados

-- V5 · No mete filas espurias en el historial de costo.
--
--   Verificado en producción con ROLLBACK:
--
--   a) Comprar al MISMO costo que ya tiene (el ponderado no se mueve):
--        costo previo 186,64, se recibe a 186,64
--        → n_actualizados = 0, delta en app_dat_precio_costo = 0  ✅
--
--   b) Dos llamadas idénticas seguidas (la segunda no cambia el valor):
--        1ª → n=1, historial +1
--        2ª → n=0, historial +0                                    ✅
--
--   ⚠️ Esto solo funciona por el `::real` del UPDATE. `precio_promedio` es
--   `real` (float4, 24 bits) y `v_costo_nuevo` es `numeric`. Sin el cast,
--   `61.8971 <> 61.89710000000000001` es TRUE siempre y la guarda no filtra
--   nada. Medido antes de añadirlo: las dos llamadas idénticas daban n=1 y
--   +1 fila de historial cada una.

-- V6 · ⚠️ PENDIENTE DE DATO: costos ya inconsistentes entre presentaciones.
--
--   Este archivo evita que se sigan generando, pero no corrige el pasado.
--
--   WITH c AS (
--     SELECT pp.id_producto, pp.id, np.denominacion, pp.cantidad AS factor,
--            pp.es_base, pp.precio_promedio, f.factor_rel,
--            pp.precio_promedio / NULLIF(f.factor_rel,0) AS costo_por_unidad_base
--       FROM app_dat_producto_presentacion pp
--       JOIN app_nom_presentacion np ON np.id = pp.id_presentacion
--       JOIN LATERAL public.fn_presentaciones_producto(pp.id_producto) f
--            ON f.id_presentacion = pp.id
--      WHERE pp.precio_promedio IS NOT NULL AND pp.precio_promedio > 0),
--   agg AS (SELECT id_producto, min(costo_por_unidad_base) mn,
--                  max(costo_por_unidad_base) mx
--             FROM c GROUP BY 1 HAVING count(*) > 1)
--   SELECT count(*) AS productos_multipresentacion_con_costo,
--          count(*) FILTER (WHERE mx > mn * 1.01) AS inconsistentes,
--          count(*) FILTER (WHERE mx > mn * 2)    AS desvio_grave
--     FROM agg;
--   -- medido: 40 productos, 21 inconsistentes, 11 con desvío > 2×
--
--   Caso más claro (producto 6841): Bulto 9,80 → 0,98/Bolsa vs Bolsa 186,64.
--   Un factor 190×. Hay que decidir cuál es el bueno producto por producto; no
--   se puede automatizar sin saber qué compra fue la real.
