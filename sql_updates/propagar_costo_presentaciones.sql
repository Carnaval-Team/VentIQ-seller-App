-- ============================================================================
-- Costo de presentaciones: fuente única en base + derivación por factor
-- ============================================================================
--
-- Problema (medido en Newa): al dar entrada a un producto, el costo promedio
-- solo queda en la fila de la presentación base (o en la recibida, según la
-- ruta). El resto de presentaciones quedan con precio_promedio NULL/0 aunque
-- su costo es derivable: costo_presentacion = costo_base * factor_rel.
--
-- Estado verificado en Newa (solo lectura, 2026-10-24):
--   · fn_actualizar_precio_promedio_recepcion_v2 YA es la versión corregida
--     (pondera en unidades base y escribe solo en es_base — ver
--     presentaciones_inventario/20_costo_promedio_en_base.sql).
--   · configurar_precios_recepcion_consignacion_v2 ya no toca precio_promedio;
--     la v2 es el único escritor vivo de costo por recepción.
--   · 5 productos multipresentación tienen 6 filas sin costo que son
--     derivables: Agua/Caja, Arroz/Kg, Frijoles/Kg, Enalapril/Caja,
--     Agua/Galón y Agua/Lata.
--   · El producto Arroz no tiene es_base marcado; fn_presentaciones_producto
--     lo resuelve por cascada (menor factor) igual, así que usamos su
--     es_base/factor_rel calculados, no la columna cruda.
--
-- Qué hace este script (en una transacción):
--   1. Reemplaza fn_actualizar_precio_promedio_recepcion_v2 añadiendo la
--      propagación: tras ponderar el costo en la fila base, escribe el costo
--      derivado (costo_base * factor_rel) en TODAS las presentaciones del
--      producto, con guarda de precisión real para no inflar el historial
--      (trg_registrar_precio_costo) cuando el valor no cambia.
--   2. Backfill: igual UPDATE derivado sobre todas las filas existentes,
--      solo donde difiera del valor derivado.
--   3. Verificación al final.
--
-- Decisiones de diseño:
--   · La fila base sigue siendo la fuente de verdad; las demás son caché
--     desnormalizado para lectores que consultan precio_promedio por fila
--     (detalle de venta, consignación, valoración). Se recalculan todas en
--     una sola sentencia → snapshot consistente, sin deriva parcial.
--   · Cada UPDATE dispara trg_registrar_precio_costo → una fila de historial
--     por presentación cuyo valor realmente cambie. Es auditoría correcta:
--     el costo de esa presentación sí cambió.
--
-- No toca: trg_registrar_precio_costo, configurar_precios_recepcion_consignacion*,
-- fn_inicializar_precio_promedio_desde_primera_recepcion (no la llama la app;
-- queda como deuda conocida: inicializa el mismo costo crudo por presentación).
-- ============================================================================

BEGIN;

-- ────────────────────────────────────────────────────────────────────────────
-- 1. v2 + propagación del costo derivado a todas las presentaciones
-- ────────────────────────────────────────────────────────────────────────────
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
    SELECT EXISTS (
        SELECT 1 FROM app_dat_consignacion_envio
         WHERE id_operacion_recepcion = p_id_operacion
           AND tipo_envio = 2
    ) INTO v_es_devolucion;

    IF v_es_devolucion THEN
        v_tiempo := (EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)) * 1000)::int;
        RETURN QUERY SELECT TRUE,
            'Operacion de devolucion - precio promedio no actualizado'::text, 0, v_tiempo;
        RETURN;
    END IF;

    IF public.fn_es_operacion_sin_actualizar_precio_costo(p_id_operacion) THEN
        v_tiempo := (EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)) * 1000)::int;
        RETURN QUERY SELECT TRUE,
            'La operacion es una transferencia, devolucion u operacion interna; no modifica el costo promedio'::text,
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
        con_factor AS (
            SELECT pp.id_producto,
                   en.cantidad * COALESCE(f.factor_rel, 1)        AS cant_base,
                   en.precio_unitario / NULLIF(COALESCE(f.factor_rel, 1), 0) AS costo_base
              FROM entrada en
              JOIN app_dat_producto_presentacion pp ON pp.id = en.id_pp
              LEFT JOIN LATERAL public.fn_presentaciones_producto(pp.id_producto) f
                     ON f.id_presentacion = pp.id
        )
        SELECT id_producto,
               SUM(cant_base)              AS cant_base,
               SUM(cant_base * costo_base) AS importe_base
          FROM con_factor
         WHERE cant_base > 0 AND costo_base IS NOT NULL
         GROUP BY id_producto
    LOOP
        SELECT c.id_presentacion INTO v_id_base
          FROM public.fn_presentaciones_producto(v_fila.id_producto) c
         WHERE c.es_base
         LIMIT 1;

        IF v_id_base IS NULL THEN
            CONTINUE;
        END IF;

        SELECT COALESCE(pp.precio_promedio, 0) INTO v_costo_ant
          FROM app_dat_producto_presentacion pp
         WHERE pp.id = v_id_base
           FOR UPDATE;

        SELECT COALESCE(SUM(s.equivalente_base), 0) INTO v_saldo_base
          FROM public.fn_stock_saldos_presentacion(v_fila.id_producto, NULL, NULL, false) s;

        v_saldo_base := GREATEST(v_saldo_base - v_fila.cant_base, 0);

        IF v_costo_ant <= 0 OR v_saldo_base <= 0 THEN
            v_costo_nuevo := v_fila.importe_base / v_fila.cant_base;
        ELSE
            v_costo_nuevo := ((v_costo_ant * v_saldo_base) + v_fila.importe_base)
                             / (v_saldo_base + v_fila.cant_base);
        END IF;

        -- precio_promedio es `real` (float4): la guarda compara en la
        -- precision de destino para no meter filas falsas al historial.
        UPDATE app_dat_producto_presentacion
           SET precio_promedio = v_costo_nuevo
         WHERE id = v_id_base
           AND COALESCE(precio_promedio, -1) <> v_costo_nuevo::real;

        IF FOUND THEN
            v_actualizados := v_actualizados + 1;
        END IF;

        -- Propagación: costo_presentacion = costo_base_nuevo * factor_rel en
        -- TODAS las filas del producto (incluida la base, que la guarda filtra).
        -- La base es la fuente de verdad; las demás son caché desnormalizado
        -- para lectores que consultan precio_promedio por fila.
        UPDATE app_dat_producto_presentacion pp
           SET precio_promedio = v_costo_nuevo * f.factor_rel
          FROM public.fn_presentaciones_producto(v_fila.id_producto) f
         WHERE f.id_presentacion = pp.id
           AND pp.id_producto = v_fila.id_producto
           AND COALESCE(pp.precio_promedio, -1)
               <> (v_costo_nuevo * f.factor_rel)::real;
    END LOOP;

    v_tiempo := (EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)) * 1000)::int;

    RETURN QUERY SELECT TRUE,
        format('Se actualizaron %s costos promedio (ponderados en unidades base)', v_actualizados)::text,
        v_actualizados, v_tiempo;

EXCEPTION WHEN OTHERS THEN
    v_tiempo := (EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)) * 1000)::int;
    RETURN QUERY SELECT FALSE,
        format('Error en fn_actualizar_precio_promedio_recepcion_v2 [%s]: %s', SQLSTATE, SQLERRM)::text,
        0, v_tiempo;
END;
$$;

-- ────────────────────────────────────────────────────────────────────────────
-- 2. Backfill: derivar el costo de TODAS las presentaciones existentes
--    a partir del costo de la fila base (resuelta por la cascada de
--    fn_presentaciones_producto, que cubre productos sin es_base marcado).
-- ────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_filas int;
BEGIN
    UPDATE app_dat_producto_presentacion pp
       SET precio_promedio = d.derivado
      FROM (
        SELECT pp2.id AS fila,
               cb.costo_base * f.factor_rel AS derivado
          FROM app_dat_producto_presentacion pp2
          JOIN LATERAL public.fn_presentaciones_producto(pp2.id_producto) f
            ON f.id_presentacion = pp2.id
          JOIN LATERAL (
            SELECT b.precio_promedio AS costo_base
              FROM app_dat_producto_presentacion b
              JOIN LATERAL public.fn_presentaciones_producto(b.id_producto) bf
                ON bf.id_presentacion = b.id AND bf.es_base
             WHERE b.id_producto = pp2.id_producto
             LIMIT 1
          ) cb ON true
         WHERE cb.costo_base > 0
      ) d
     WHERE pp.id = d.fila
       AND COALESCE(pp.precio_promedio, -1) <> d.derivado::real;

    GET DIAGNOSTICS v_filas = ROW_COUNT;
    RAISE NOTICE 'Backfill: % filas de presentacion actualizadas con costo derivado', v_filas;
END;
$$;

COMMIT;

-- ────────────────────────────────────────────────────────────────────────────
-- 3. Verificación: no debe quedar ninguna fila desviada del costo derivado.
--    Esperado: 0 filas.
-- ────────────────────────────────────────────────────────────────────────────
SELECT pp.id AS fila,
       pp.id_producto,
       f.factor_rel,
       f.es_base,
       pp.precio_promedio AS actual,
       cb.costo_base * f.factor_rel AS esperado
  FROM app_dat_producto_presentacion pp
  JOIN LATERAL public.fn_presentaciones_producto(pp.id_producto) f
    ON f.id_presentacion = pp.id
  JOIN LATERAL (
    SELECT b.precio_promedio AS costo_base
      FROM app_dat_producto_presentacion b
      JOIN LATERAL public.fn_presentaciones_producto(b.id_producto) bf
        ON bf.id_presentacion = b.id AND bf.es_base
     WHERE b.id_producto = pp.id_producto
     LIMIT 1
  ) cb ON true
 WHERE cb.costo_base > 0
   AND COALESCE(pp.precio_promedio, -1)
       <> (cb.costo_base * f.factor_rel)::real;
