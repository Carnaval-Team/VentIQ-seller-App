-- ============================================================================
-- 30 · Resumen de cierre del vendedor: _v2 de las dos RPC (Fase 3)
-- ============================================================================
-- Cierra el punto 2 de «Lo que queda» de docs/PLAN_PRESENTACIONES_INVENTARIO.md
-- («Resumen de cierre vendedor»).
--
-- ----------------------------------------------------------------------------
-- FUNCIONES NUEVAS, las originales NO SE TOCAN
-- ----------------------------------------------------------------------------
-- Se sigue el patron acordado con el usuario: sufijo `_v2` y el Dart se migra
-- aparte, en un cambio reversible. `fn_resumen_diario_cierre` la llaman **6
-- sitios del vendedor** (sales_monitor_fab, auto_sync_service, turno_service,
-- venta_total_screen, settings_screen, cierre_screen) y las apps sin actualizar
-- seguiran usandola.
--
-- ----------------------------------------------------------------------------
-- TRES bugs, y solo uno es de presentaciones
-- ----------------------------------------------------------------------------
--
-- **(1) `SUM(ep.cantidad)::INTEGER` REDONDEA, no trunca.** `productos_vendidos`
-- esta declarado `integer` en el RETURNS TABLE, asi que las ventas fraccionadas
-- se deforman. Verificado en Postgres:
--
--     (0.5)::integer = 1     (0.4)::integer = 0     (2.5)::integer = 3
--     tres lineas de 0,5 kg -> SUM = 1,5 -> ::integer = **2**
--
-- El vendedor cierra el turno viendo una cantidad de productos que no vendio.
-- Medido: **133 lineas fraccionadas en 30 dias** en 2 tiendas, 45 de ellas por
-- debajo de 1 unidad. Arreglarlo exige cambiar el tipo de la columna, que es
-- exactamente el caso en que hace falta una funcion nueva.
--
-- **(2) FAN-OUT por medio de pago en `fn_productos_vendidos_por_turno`** — el
-- peor de los tres, porque infla cantidades Y dinero. El
-- `LEFT JOIN app_dat_pago_venta` multiplica cada linea de producto por cada
-- pago de la operacion. Caso real en produccion:
--
--     operacion 154626, turno 2948, producto 5683
--       cantidad real en el ledger .... 1,0
--       cantidad que reporta la RPC ... 2,0    (x2 exacto, 2 pagos)
--
-- Si el cliente paga mitad efectivo y mitad transferencia, el cierre reporta el
-- doble de productos y el doble de importe. Con 3 pagos, el triple.
-- Medido: **93 operaciones en 30 dias** (0,84 %), hasta 3 pagos en una.
--
-- **(3) JOIN de presentacion por la columna equivocada** — la trampa
-- `pp.id <> pp.id_presentacion`:
--
--     LEFT JOIN app_nom_presentacion np ON rp.v_id_presentacion = np.id
--
-- `v_id_presentacion` es `app_dat_producto_presentacion.id` (la FILA), no el id
-- del nomenclador. Con pp.id = 337 (Bulto del producto 217):
--
--     id del nomenclador correcto ..... 7
--     JOIN actual (np.id = 337) ....... NULL -> cae al COALESCE 'Unidad'
--     nombre correcto ................. "Bulto"
--
-- Y **0 presentaciones no-base tienen colision de ids**, asi que NINGUNA se
-- etiqueta bien: vender 4 Bultos sale en el cierre como «4 Unidad». Es el mismo
-- error que el `19` arreglo en la valoracion.
--
-- **(4) Sin factor de presentacion** (el unico que es de presentaciones y el
-- unico que NO esta expuesto todavia): `SUM(cantidad)` mezcla cajas con
-- unidades. De **77 turnos abiertos, 0** tienen ventas con factor <> 1. Es
-- preventivo.
--
-- ----------------------------------------------------------------------------
-- Que cambia en cada _v2
-- ----------------------------------------------------------------------------
-- `fn_resumen_diario_cierre_v2`:
--   · `productos_vendidos` pasa de **integer a numeric** (fin del redondeo).
--   · se agrega `productos_vendidos_base numeric`: el equivalente en unidades
--     base, que es el numero comparable entre turnos.
--   · se agrega `productos_vendidos_desglose text`: "2 Cajas + 5 Unidades".
--   · las 17 columnas originales conservan nombre, orden y tipo — salvo
--     `productos_vendidos`, que es el arreglo.
--
-- `fn_productos_vendidos_por_turno_v2`:
--   · el pago se agrega **antes** del join (CTE `pagos_op`), sin fan-out.
--   · la presentacion se resuelve por `fn_presentaciones_producto`, que ya
--     devuelve `nombre` y `factor_rel` correctos, en vez del JOIN roto.
--   · se agrega `factor_rel` y `cantidad_base` a la salida.
--   · `cantidad_formateada` con `fn_plural_presentacion`.
--   · el `id_presentacion` nulo se resuelve a la BASE, no se trata como
--     dimension aparte (leccion de los archivos 26 y 29).
--
-- Seguridad: las dos llevan `check_user_has_access_to_any_tienda()` +
-- `SET search_path = public` en la cabecera (la original lo hacia con un
-- `SET search_path` dentro del cuerpo, que es menos robusto).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1/2 · fn_resumen_diario_cierre_v2
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_resumen_diario_cierre_v2(
    id_tpv_param     bigint DEFAULT NULL::bigint,
    id_usuario_param uuid   DEFAULT NULL::uuid
)
RETURNS TABLE (
    -- === las 17 columnas de la original, mismo nombre y orden ===
    ventas_totales                numeric,
    efectivo_inicial              numeric,
    efectivo_real                 numeric,
    efectivo_esperado             numeric,
    productos_vendidos            numeric,   -- era integer: REDONDEABA
    ticket_promedio               numeric,
    porcentaje_efectivo           numeric,
    porcentaje_otros              numeric,
    operaciones_totales           integer,
    operaciones_por_hora          numeric,
    promedio_operaciones_por_hora numeric,
    conciliacion_estado           text,
    efectivo_real_ajustado        numeric,
    diferencia_ajustada           numeric,
    turno_id                      bigint,
    fecha_apertura                timestamp with time zone,
    horas_transcurridas           numeric,
    -- === nuevas ===
    productos_vendidos_base       numeric,
    productos_vendidos_desglose   text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_uuid_usuario   uuid;
    v_turno          RECORD;
    v_ventas         numeric := 0;
    v_efec_inicial   numeric := 0;
    v_efec_real      numeric := 0;
    v_efec_esperado  numeric := 0;
    v_prod_vendidos  numeric := 0;
    v_prod_base      numeric := 0;
    v_prod_desglose  text    := NULL;
    v_ticket         numeric := 0;
    v_pct_efectivo   numeric := 0;
    v_pct_otros      numeric := 0;
    v_ops            integer := 0;
    v_ops_hora       numeric := 0;
    v_conciliacion   text    := 'Sin turno abierto';
    v_dif_ajustada   numeric := 0;
    v_horas          numeric := 0;
    v_tot_efectivo   numeric := 0;
    v_tot_otros      numeric := 0;
BEGIN
    v_uuid_usuario := COALESCE(id_usuario_param, auth.uid());

    PERFORM public.check_user_has_access_to_any_tienda();

    SELECT
        ct.id,
        ct.fecha_apertura,
        ct.efectivo_inicial,
        ct.efectivo_esperado,
        ct.efectivo_real,
        ct.estado,
        ct.diferencia,
        EXTRACT(EPOCH FROM (NOW() - ct.fecha_apertura)) / 3600 AS horas
    INTO v_turno
    FROM app_dat_caja_turno ct
    JOIN app_dat_vendedor v ON ct.id_vendedor = v.id
    WHERE ct.id_tpv = id_tpv_param
      AND v.uuid = v_uuid_usuario
      AND ct.estado = 1
    ORDER BY ct.fecha_apertura DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            0::numeric, 0::numeric, 0::numeric, 0::numeric, 0::numeric,
            0::numeric, 0::numeric, 0::numeric, 0::integer, 0::numeric,
            0::numeric, 'Sin turno abierto'::text, 0::numeric, 0::numeric,
            NULL::bigint, NULL::timestamptz, 0::numeric,
            0::numeric, NULL::text;
        RETURN;
    END IF;

    v_efec_inicial := COALESCE(v_turno.efectivo_inicial, 0);
    v_horas        := COALESCE(v_turno.horas, 0);

    -- ------------------------------------------------------------------
    -- Productos vendidos y operaciones.
    --
    -- Tres cosas cambian respecto de la original:
    --   1. NO se castea a integer: `SUM(...)::INTEGER` redondeaba (tres lineas
    --      de 0,5 kg daban 2). Se devuelve numeric.
    --   2. Se calcula tambien el equivalente en unidades base con factor_rel.
    --   3. El desglose por presentacion sale del mismo barrido.
    --
    -- Las operaciones se cuentan aparte para no depender del agregado de
    -- lineas (una operacion sin lineas seguiria contando).
    -- ------------------------------------------------------------------
    WITH lineas AS (
        SELECT
            ep.id_producto,
            -- El nulo es la presentacion BASE, no "ninguna" (leccion del 26/29).
            COALESCE(
                ep.id_presentacion,
                (SELECT c.id_presentacion
                   FROM public.fn_presentaciones_producto(ep.id_producto) c
                  WHERE c.es_base LIMIT 1)
            ) AS id_presentacion,
            ep.cantidad,
            o.id AS id_operacion
        FROM app_dat_operaciones o
        JOIN app_dat_operacion_venta ov ON o.id = ov.id_operacion
        JOIN app_dat_extraccion_productos ep ON o.id = ep.id_operacion
        WHERE ov.id_tpv = id_tpv_param
          AND o.uuid = v_uuid_usuario
          AND o.created_at >= v_turno.fecha_apertura
          AND EXISTS (
              SELECT 1 FROM app_dat_estado_operacion eo
               WHERE eo.id_operacion = o.id
                 AND eo.estado = 2
                 AND eo.id = (SELECT MAX(eo2.id)
                                FROM app_dat_estado_operacion eo2
                               WHERE eo2.id_operacion = o.id)
          )
    ),
    con_factor AS (
        SELECT
            l.cantidad,
            l.id_operacion,
            COALESCE(f.factor_rel, 1) AS factor_rel,
            f.nombre                  AS pres_nombre
        FROM lineas l
        LEFT JOIN LATERAL public.fn_presentaciones_producto(l.id_producto) f
               ON f.id_presentacion = l.id_presentacion
    ),
    por_pres AS (
        SELECT
            cf.pres_nombre,
            MAX(cf.factor_rel) AS factor_rel,
            SUM(cf.cantidad)   AS cantidad
        FROM con_factor cf
        GROUP BY cf.pres_nombre
    )
    SELECT
        COALESCE((SELECT SUM(cf.cantidad) FROM con_factor cf), 0),
        COALESCE((SELECT SUM(cf.cantidad * cf.factor_rel) FROM con_factor cf), 0),
        COALESCE((SELECT COUNT(DISTINCT cf.id_operacion)::integer FROM con_factor cf), 0),
        (SELECT string_agg(
                    public.fn_fmt_cantidad(pp.cantidad)
                        || CASE WHEN pp.pres_nombre IS NOT NULL
                                THEN ' ' || public.fn_plural_presentacion(
                                                pp.pres_nombre, pp.cantidad)
                                ELSE '' END,
                    ' + ' ORDER BY pp.factor_rel DESC, pp.pres_nombre)
           FROM por_pres pp)
    INTO v_prod_vendidos, v_prod_base, v_ops, v_prod_desglose;

    -- ------------------------------------------------------------------
    -- Totales por medio de pago (identico a la original).
    -- ------------------------------------------------------------------
    SELECT
        COALESCE(SUM(CASE WHEN mp.es_efectivo THEN pv.monto ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN NOT mp.es_efectivo THEN pv.monto ELSE 0 END), 0)
    INTO v_tot_efectivo, v_tot_otros
    FROM app_dat_operaciones o
    JOIN app_dat_operacion_venta ov ON o.id = ov.id_operacion
    JOIN app_dat_pago_venta pv ON ov.id_operacion = pv.id_operacion_venta
    JOIN app_nom_medio_pago mp ON pv.id_medio_pago = mp.id
    WHERE ov.id_tpv = id_tpv_param
      AND o.uuid = v_uuid_usuario
      AND o.created_at >= v_turno.fecha_apertura
      AND mp.es_activo = true
      AND EXISTS (
          SELECT 1 FROM app_dat_estado_operacion eo
           WHERE eo.id_operacion = o.id
             AND eo.estado = 2
             AND eo.id = (SELECT MAX(eo2.id)
                            FROM app_dat_estado_operacion eo2
                           WHERE eo2.id_operacion = o.id)
      );

    v_ventas        := v_tot_efectivo + v_tot_otros;
    v_efec_real     := v_tot_efectivo;
    v_efec_esperado := v_efec_inicial + v_tot_efectivo;

    IF v_ventas > 0 THEN
        v_pct_efectivo := ROUND((v_tot_efectivo / v_ventas) * 100, 2);
        v_pct_otros    := ROUND((v_tot_otros    / v_ventas) * 100, 2);
    END IF;

    IF v_ops > 0 THEN
        v_ticket := ROUND(v_ventas / v_ops, 2);
    END IF;

    IF v_horas > 0 THEN
        v_ops_hora := ROUND(v_ops / v_horas, 2);
    END IF;

    CASE
        WHEN v_turno.estado = 1 THEN v_conciliacion := 'Abierto';
        WHEN v_turno.diferencia IS NULL OR v_turno.diferencia = 0 THEN v_conciliacion := 'Conciliado';
        WHEN ABS(COALESCE(v_turno.diferencia, 0)) <= 1.00 THEN v_conciliacion := 'Casi exacto (≤ $1)';
        WHEN COALESCE(v_turno.diferencia, 0) > 0 THEN v_conciliacion := 'Sobrante';
        ELSE v_conciliacion := 'Falta';
    END CASE;

    v_dif_ajustada := v_efec_real - v_efec_esperado;

    RETURN QUERY SELECT
        v_ventas,
        v_efec_inicial,
        v_efec_real,
        v_efec_esperado,
        v_prod_vendidos,
        v_ticket,
        v_pct_efectivo,
        v_pct_otros,
        v_ops,
        v_ops_hora,
        v_ops_hora,               -- promedio_operaciones_por_hora (igual que la original)
        v_conciliacion,
        v_efec_real,              -- efectivo_real_ajustado (igual que la original)
        v_dif_ajustada,
        v_turno.id,
        v_turno.fecha_apertura,
        v_horas,
        v_prod_base,
        v_prod_desglose;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error en fn_resumen_diario_cierre_v2: %', SQLERRM;
END;
$function$;

COMMENT ON FUNCTION public.fn_resumen_diario_cierre_v2(bigint, uuid) IS
'Resumen del turno abierto para el cierre del vendedor. v2 de '
'fn_resumen_diario_cierre (que NO se modifica: la llaman 6 sitios del vendedor). '
'Arregla que productos_vendidos era integer y REDONDEABA las ventas fraccionadas '
'(tres lineas de 0,5 kg daban 2) y agrega productos_vendidos_base (equivalente '
'en unidades base, el numero comparable) y productos_vendidos_desglose '
'("2 Cajas + 5 Unidades"). Fase 3 presentaciones, archivo 30.';

GRANT EXECUTE ON FUNCTION public.fn_resumen_diario_cierre_v2(bigint, uuid)
    TO anon, authenticated, service_role;


-- ---------------------------------------------------------------------------
-- 2/2 · fn_productos_vendidos_por_turno_v2
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_productos_vendidos_por_turno_v2(
    p_id_turno bigint
)
RETURNS TABLE (
    -- === las 10 columnas de la original ===
    id_producto               bigint,
    producto_nombre           character varying,
    id_variante               bigint,
    variante_valor            character varying,
    id_presentacion           bigint,
    presentacion_denominacion character varying,
    cantidad_total            numeric,
    precio_unitario_promedio  numeric,
    total_general             numeric,
    detalle_por_medio_pago    jsonb,
    -- === nuevas ===
    factor_rel                numeric,
    cantidad_base             numeric,
    cantidad_formateada       text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
    PERFORM public.check_user_has_access_to_any_tienda();

    RETURN QUERY
    WITH turno_info AS (
        SELECT ct.id_tpv,
               ct.fecha_apertura,
               COALESCE(ct.fecha_cierre, NOW()) AS fecha_cierre
          FROM app_dat_caja_turno ct
         WHERE ct.id = p_id_turno
    ),

    -- Lineas de venta del turno. **SIN** el LEFT JOIN a pago_venta: ese join
    -- multiplicaba cada linea por cada pago de la operacion (medido: operacion
    -- 154626 reportaba 2,0 donde el ledger tiene 1,0). El medio de pago se
    -- agrega aparte, en `pagos_op`.
    lineas AS (
        SELECT
            ep.id_operacion,
            ep.id_producto,
            ep.id_variante,
            -- El nulo es la presentacion BASE (leccion del 26/29).
            COALESCE(
                ep.id_presentacion,
                (SELECT c.id_presentacion
                   FROM public.fn_presentaciones_producto(ep.id_producto) c
                  WHERE c.es_base LIMIT 1)
            ) AS id_presentacion,
            ep.cantidad,
            ep.precio_unitario,
            ep.importe
        FROM app_dat_operaciones o
        JOIN app_dat_operacion_venta ov ON o.id = ov.id_operacion
        JOIN app_dat_extraccion_productos ep ON o.id = ep.id_operacion
        CROSS JOIN turno_info ti
        WHERE o.id_tipo_operacion = (
                  SELECT id FROM app_nom_tipo_operacion
                   WHERE LOWER(denominacion) = 'venta' LIMIT 1)
          AND ov.id_tpv = ti.id_tpv
          AND o.created_at >= ti.fecha_apertura
          AND o.created_at <= ti.fecha_cierre
    ),

    -- Un medio de pago por operacion. Si la operacion se pago con varios, se
    -- listan separados por " + " en vez de duplicar las lineas.
    pagos_op AS (
        SELECT
            pv.id_operacion_venta AS id_operacion,
            -- Sin ORDER BY: con DISTINCT dentro de string_agg, Postgres exige
            -- que el ORDER BY sea por la misma expresion, y el DISTINCT ya
            -- deja el orden estable. Asi esta aplicado en produccion.
            string_agg(DISTINCT mp.denominacion, ' + ') AS medio_pago
        FROM app_dat_pago_venta pv
        JOIN app_nom_medio_pago mp ON pv.id_medio_pago = mp.id
        GROUP BY pv.id_operacion_venta
    ),

    -- La presentacion se resuelve por la CADENA, no por
    -- `app_nom_presentacion.id = pp.id`: esa era la trampa
    -- `pp.id <> pp.id_presentacion`, que dejaba el JOIN en NULL y etiquetaba
    -- TODO como 'Unidad' (0 presentaciones no-base tienen colision de ids, asi
    -- que ninguna salia bien).
    lineas_pres AS (
        SELECT
            l.*,
            COALESCE(f.factor_rel, 1) AS factor_rel,
            f.nombre                  AS pres_nombre
        FROM lineas l
        LEFT JOIN LATERAL public.fn_presentaciones_producto(l.id_producto) f
               ON f.id_presentacion = l.id_presentacion
    ),

    resumen AS (
        SELECT
            lp.id_producto,
            lp.id_variante,
            lp.id_presentacion,
            MAX(lp.factor_rel)      AS factor_rel,
            MAX(lp.pres_nombre)     AS pres_nombre,
            SUM(lp.cantidad)        AS cantidad_total,
            AVG(lp.precio_unitario) AS precio_unitario_promedio,
            SUM(lp.importe)         AS total_general
        FROM lineas_pres lp
        GROUP BY lp.id_producto, lp.id_variante, lp.id_presentacion
    ),

    detalle_medios AS (
        SELECT
            lp.id_producto,
            lp.id_variante,
            lp.id_presentacion,
            COALESCE(po.medio_pago, 'Sin pago') AS medio_pago,
            SUM(lp.cantidad) AS cantidad_por_medio,
            SUM(lp.importe)  AS monto_por_medio
        FROM lineas_pres lp
        LEFT JOIN pagos_op po ON po.id_operacion = lp.id_operacion
        GROUP BY lp.id_producto, lp.id_variante, lp.id_presentacion,
                 COALESCE(po.medio_pago, 'Sin pago')
    )

    SELECT
        r.id_producto,
        p.denominacion::varchar                       AS producto_nombre,
        r.id_variante,
        COALESCE(ao.valor, 'N/A')::varchar            AS variante_valor,
        r.id_presentacion,
        COALESCE(r.pres_nombre, 'Unidad')::varchar    AS presentacion_denominacion,
        r.cantidad_total,
        ROUND(r.precio_unitario_promedio, 2)          AS precio_unitario_promedio,
        r.total_general,
        (
            SELECT jsonb_agg(
                       jsonb_build_object(
                           'medio_pago', dm.medio_pago,
                           'cantidad',   dm.cantidad_por_medio,
                           'monto',      dm.monto_por_medio
                       ) ORDER BY dm.medio_pago
                   )
              FROM detalle_medios dm
             WHERE dm.id_producto = r.id_producto
               AND COALESCE(dm.id_variante, 0)     = COALESCE(r.id_variante, 0)
               AND COALESCE(dm.id_presentacion, 0) = COALESCE(r.id_presentacion, 0)
        )                                             AS detalle_por_medio_pago,
        r.factor_rel,
        r.cantidad_total * r.factor_rel               AS cantidad_base,
        public.fn_fmt_cantidad(r.cantidad_total)
            || CASE WHEN r.pres_nombre IS NOT NULL
                    THEN ' ' || public.fn_plural_presentacion(
                                    r.pres_nombre, r.cantidad_total)
                    ELSE '' END                       AS cantidad_formateada
    FROM resumen r
    JOIN app_dat_producto p ON r.id_producto = p.id
    LEFT JOIN app_dat_atributo_opcion ao ON r.id_variante = ao.id
    ORDER BY r.total_general DESC;
END;
$function$;

COMMENT ON FUNCTION public.fn_productos_vendidos_por_turno_v2(bigint) IS
'Detalle de productos vendidos en un turno. v2 de '
'fn_productos_vendidos_por_turno (que NO se modifica). Arregla DOS bugs graves: '
'(a) el LEFT JOIN a app_dat_pago_venta multiplicaba cada linea por cada pago de '
'la operacion, inflando cantidades e importes (93 ops en 30 dias, hasta x3); '
'(b) el JOIN a app_nom_presentacion casaba pp.id contra np.id y etiquetaba TODO '
'como "Unidad". Agrega factor_rel, cantidad_base y cantidad_formateada. '
'Fase 3 presentaciones, archivo 30.';

GRANT EXECUTE ON FUNCTION public.fn_productos_vendidos_por_turno_v2(bigint)
    TO anon, authenticated, service_role;

-- ============================================================================
-- VERIFICACION
-- ============================================================================

-- V1 · Las originales intactas y las v2 creadas, sin sobrecargas duplicadas.
--      VERIFICADO 2026-08-29: orig_cierre_cols 17 | v2_cierre_cols 19 |
--      orig_turno_cols 10 | v2_turno_cols 13 | 1 sobrecarga cada una |
--      orig_cierre_len 6.345 y orig_turno_len 3.274 SIN CAMBIOS.
-- SELECT
--   array_length(string_to_array(pg_get_function_result(
--     'public.fn_resumen_diario_cierre(bigint,uuid)'::regprocedure), ','), 1)    AS orig_cierre_cols,
--   array_length(string_to_array(pg_get_function_result(
--     'public.fn_resumen_diario_cierre_v2(bigint,uuid)'::regprocedure), ','), 1) AS v2_cierre_cols,
--   array_length(string_to_array(pg_get_function_result(
--     'public.fn_productos_vendidos_por_turno(bigint)'::regprocedure), ','), 1)    AS orig_turno_cols,
--   array_length(string_to_array(pg_get_function_result(
--     'public.fn_productos_vendidos_por_turno_v2(bigint)'::regprocedure), ','), 1) AS v2_turno_cols;

-- V2 · FAN-OUT arreglado: la operacion 154626 (2 pagos) ya no duplica.
--      VERIFICADO 2026-08-29 (turno 2948, JWT del vendedor
--      38ee6cf3-f357-4432-8765-e425f24266ff):
--
--         producto   ledger            ORIGINAL          V2
--         5683       1,0 / 24.480,00   2,0 / 48.960,00   1,0 / 24.480,00  OK
--         5709       1,0 / 20.400,00   2,0 / 40.800,00   1,0 / 20.400,00  OK
--         TOTAL      2,0 / 44.880,00   4,0 / 89.760,00   2,0 / 44.880,00
--
--      La original reportaba **el doble de cantidad y el doble de importe** en
--      todo el turno. La v2 cuadra EXACTO con app_dat_extraccion_productos.
--      El detalle de medios pasa de 2 filas duplicadas a una sola:
--         "Pago oferta(Efectivo) + Pago regular(Transferencia)".
-- SELECT f.id_producto, f.cantidad_total, f.cantidad_formateada,
--        f.detalle_por_medio_pago
--   FROM public.fn_productos_vendidos_por_turno_v2(2948) f
--  WHERE f.id_producto = 5683;

-- V3 · Comparar original vs v2 en un turno con pagos multiples: la v2 debe dar
--      cantidades MENORES o iguales, nunca mayores.
-- SELECT COALESCE(o.id_producto, v.id_producto) AS id_producto,
--        o.cantidad_total AS cant_original,
--        v.cantidad_total AS cant_v2,
--        o.total_general  AS total_original,
--        v.total_general  AS total_v2
--   FROM public.fn_productos_vendidos_por_turno(2948) o
--   FULL JOIN public.fn_productos_vendidos_por_turno_v2(2948) v
--     ON v.id_producto = o.id_producto
--    AND COALESCE(v.id_presentacion,0) = COALESCE(o.id_presentacion,0)
--  WHERE o.cantidad_total IS DISTINCT FROM v.cantidad_total
--  ORDER BY 1;

-- V4 · La presentacion ya NO sale siempre como 'Unidad'.
--      Buscar un turno con ventas de presentacion no-base.
-- SELECT f.id_producto, f.id_presentacion, f.presentacion_denominacion,
--        f.factor_rel, f.cantidad_total, f.cantidad_base, f.cantidad_formateada
--   FROM public.fn_productos_vendidos_por_turno_v2(2948) f
--  WHERE f.factor_rel <> 1
--  LIMIT 10;

-- V5 · productos_vendidos ya no redondea.
--      VERIFICADO 2026-08-29 (turno 1225, TPV 54, 248 lineas fraccionadas,
--      JWT 65f430ac-d0ff-4f2c-a349-dac9521c7e18):
--
--                           ORIGINAL     V2
--         prod. vendidos ... 55512        55511.89   <- el redondeo
--         ventas totales ... identicas    identicas  <- no se toca el dinero
--         operaciones ...... 1218         1218       <- igual
--         equiv. base ...... -            55511.89
--         desglose ......... -            "55511.89 Unidades"
--
--      Solo cambia la cantidad de productos, que es lo que se venia a arreglar.
-- SELECT o.productos_vendidos AS orig_redondeado,
--        v.productos_vendidos AS v2_exacto,
--        v.productos_vendidos_base,
--        v.productos_vendidos_desglose
--   FROM public.fn_resumen_diario_cierre(<id_tpv>, '<uuid>') o,
--        public.fn_resumen_diario_cierre_v2(<id_tpv>, '<uuid>') v;

-- V6 · Sin turno abierto la v2 devuelve la fila de ceros con 19 columnas.
-- SELECT * FROM public.fn_resumen_diario_cierre_v2(999999999, NULL);
