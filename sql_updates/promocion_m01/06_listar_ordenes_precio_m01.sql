-- ============================================================================
-- PROMOCION M01 · 06 · Listado de órdenes y precio promedio de recepción (_m01)
-- ============================================================================
-- Aditivo: crea
--   fn_listar_ordenes_m01
--   fn_actualizar_precio_promedio_recepcion_v2_m01
-- Los nombres antiguos (fn_listar_ordenes, fn_actualizar_precio_promedio_recepcion_v2)
-- NO se tocan: conservan el cuerpo de main.
-- Cuerpos: newa vigente (2026-11-23).
--
-- Contrato nuevo de fn_listar_ordenes_m01: devuelve en `detalles` los campos
-- v1 (version_monetaria, client_uuid venta_v1, snapshot_* por línea, moneda y
-- monto_cup_equivalente por pago). Requiere las columnas v1 en
-- app_dat_extraccion_productos / app_dat_operacion_venta / app_dat_pago_venta.
-- ============================================================================

DO $preflight$
BEGIN
    IF to_regprocedure('public.check_user_has_access_to_any_tienda()') IS NULL THEN
        RAISE EXCEPTION 'Falta public.check_user_has_access_to_any_tienda()';
    END IF;
    IF (SELECT count(*) FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'app_dat_extraccion_productos'
          AND column_name IN ('version_monetaria', 'id_linea_cliente', 'moneda_venta',
                              'id_medio_pago_seleccionado', 'seleccion_pendiente',
                              'precio_unitario_nativo', 'descuento_manual_unitario_nativo',
                              'precio_unitario_neto_nativo', 'importe_neto_nativo',
                              'tasa_cambio_cup', 'snapshot_precio', 'snapshot_tasa',
                              'snapshot_descuentos')) < 13 THEN
        RAISE EXCEPTION 'app_dat_extraccion_productos sin las columnas v1 (version_monetaria, snapshot_*...)';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'app_dat_operacion_venta'
          AND column_name = 'version_monetaria'
    ) THEN
        RAISE EXCEPTION 'app_dat_operacion_venta sin version_monetaria';
    END IF;
    IF (SELECT count(*) FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'app_dat_pago_venta'
          AND column_name IN ('moneda', 'tasa_usd', 'monto_cup_equivalente',
                              'importe_sin_descuento', 'tipo_pago')) < 5 THEN
        RAISE EXCEPTION 'app_dat_pago_venta sin columnas multimoneda';
    END IF;
    IF to_regclass('public.paqueteria_ordenes') IS NULL
       OR to_regclass('carnavalapp."Orders"') IS NULL THEN
        RAISE EXCEPTION 'Faltan public.paqueteria_ordenes / carnavalapp."Orders" (usados por fn_listar_ordenes)';
    END IF;
END
$preflight$;

-- ---------------------------------------------------------------------------
-- 1) fn_listar_ordenes_m01
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_listar_ordenes_m01(id_tienda_param bigint DEFAULT NULL::bigint, id_tpv_param bigint DEFAULT NULL::bigint, id_usuario_param uuid DEFAULT NULL::uuid, id_estado_param smallint DEFAULT NULL::smallint, fecha_desde_param date DEFAULT NULL::date, fecha_hasta_param date DEFAULT NULL::date, id_tipo_operacion_param bigint DEFAULT NULL::bigint, con_inventario_param boolean DEFAULT false, solo_pendientes_param boolean DEFAULT false, limite_param integer DEFAULT 0, pagina_param integer DEFAULT 1)
 RETURNS TABLE(id_operacion bigint, tipo_operacion character varying, id_tienda bigint, tienda_nombre character varying, id_tpv bigint, tpv_nombre character varying, usuario_nombre text, estado smallint, estado_nombre text, fecha_operacion timestamp with time zone, total_operacion numeric, cantidad_items integer, observaciones text, detalles jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$

DECLARE
    v_fecha_inicio          TIMESTAMPTZ;
    v_fecha_fin             TIMESTAMPTZ;
    v_tiene_turno_abierto   BOOLEAN := FALSE;
    v_id_turno_abierto      BIGINT;
    v_uuid_usuario          UUID := NULL;
    v_uid                   UUID := auth.uid();
    v_id_tipo_venta         BIGINT;
    v_tiendas               BIGINT[];
BEGIN
    -- Obtener el usuario autenticado si no se pasa
    v_uuid_usuario := COALESCE(id_usuario_param, v_uid);

    -- Verificar que el usuario tenga permisos en al menos una tienda
    PERFORM check_user_has_access_to_any_tienda();

    -- (OPT 1) Resolver el id del tipo 'venta' UNA sola vez
    SELECT id INTO v_id_tipo_venta
      FROM app_nom_tipo_operacion
     WHERE LOWER(denominacion) = 'venta'
     LIMIT 1;

    -- (OPT 2) Calcular UNA vez las tiendas a las que el usuario tiene acceso.
    -- Se califica con el alias (tiendas_usuario.id_tienda) porque 'id_tienda'
    -- es también un parámetro OUT de la función (RETURNS TABLE) y colisiona.
    SELECT array_agg(DISTINCT tiendas_usuario.id_tienda) INTO v_tiendas
    FROM (
        SELECT gr.id_tienda  FROM app_dat_gerente gr     WHERE gr.uuid = v_uid
        UNION
        SELECT sup.id_tienda FROM app_dat_supervisor sup WHERE sup.uuid = v_uid
        UNION
        SELECT aud.id_tienda FROM auditor aud            WHERE aud.uuid = v_uid
        UNION
        SELECT a.id_tienda
          FROM app_dat_almacenero al
          JOIN app_dat_almacen a ON al.id_almacen = a.id
         WHERE al.uuid = v_uid
        UNION
        SELECT tpv.id_tienda
          FROM app_dat_vendedor vend2
          JOIN app_dat_tpv tpv ON vend2.id_tpv = tpv.id
         WHERE vend2.uuid = v_uid
    ) AS tiendas_usuario;

    -- Si el usuario no tiene ninguna tienda accesible, no hay nada que devolver
    IF v_tiendas IS NULL THEN
        RETURN;
    END IF;

    -- Si NO se pasan fechas, usar el turno abierto del vendedor en el TPV
    IF fecha_desde_param IS NULL AND fecha_hasta_param IS NULL
       AND id_tpv_param IS NOT NULL AND v_uuid_usuario IS NOT NULL
    THEN
        SELECT ct.id, ct.fecha_apertura
          INTO v_id_turno_abierto, v_fecha_inicio
          FROM app_dat_caja_turno ct
          JOIN app_dat_vendedor vend ON ct.id_vendedor = vend.id
         WHERE ct.id_tpv = id_tpv_param
           AND vend.uuid = v_uuid_usuario
           AND ct.estado = 1
         ORDER BY ct.fecha_apertura DESC
         LIMIT 1;

        IF NOT FOUND THEN
            RETURN;
        END IF;

        v_fecha_fin := NOW();
        v_tiene_turno_abierto := TRUE;
    ELSE
        v_fecha_inicio := fecha_desde_param;
        v_fecha_fin    := COALESCE(fecha_hasta_param, CURRENT_DATE)
                          + INTERVAL '1 day' - INTERVAL '1 second';
    END IF;

    RETURN QUERY
    WITH operaciones_filtradas AS (
        SELECT
            o.id,
            o.created_at,
            o.id_tipo_operacion,
            top.denominacion                    AS tipo_operacion_nombre,
            o.id_tienda,
            t.denominacion                      AS tienda_nombre,
            o.uuid,
            COALESCE(u.email, 'Sistema')        AS usuario_email,
            e.estado,
            desc_vendedor.descuento             AS descuento,
            COALESCE(es.denominacion::text, 'Desconocido')
                                                AS estado_nombre,
            o.observaciones::TEXT,
            -- Datos específicos de TPV (usa la variable v_id_tipo_venta cacheada)
            CASE
                WHEN o.id_tipo_operacion = v_id_tipo_venta THEN (
                    SELECT jsonb_build_object(
                        'id_tpv',            ov.id_tpv,
                        'tpv_nombre',        tp.denominacion,
                        'codigo_promocion',  ov.codigo_promocion,
                        'id_cliente',        ov.id_cliente,
                        'id_cliente_cxc',    ov.id_cliente_cxc,
                        'cliente_nombre',    COALESCE(cli_cxc.nombre_completo, cli.nombre_completo),
                        'cliente_telefono',  COALESCE(cli_cxc.telefono, cli.telefono)
                    )
                      FROM app_dat_operacion_venta ov
                      JOIN app_dat_tpv tp ON ov.id_tpv = tp.id
                      LEFT JOIN app_dat_clientes cli ON ov.id_cliente = cli.id
                      LEFT JOIN app_dat_cliente_cxc cli_cxc ON ov.id_cliente_cxc = cli_cxc.id
                     WHERE ov.id_operacion = o.id
                     LIMIT 1
                )
                ELSE NULL
            END                                 AS datos_especificos,
            -- (OPT 3) cantidad_items + total en un solo LATERAL
            ep_agg.cantidad_items,
            ep_agg.total_operacion
        FROM app_dat_operaciones o
        JOIN app_nom_tipo_operacion top ON o.id_tipo_operacion = top.id
        JOIN app_dat_tienda t           ON o.id_tienda = t.id
        LEFT JOIN auth.users u          ON o.uuid = u.id
        LEFT JOIN LATERAL (
            SELECT COUNT(*)::INTEGER                 AS cantidad_items,
                   COALESCE(SUM(ep.importe), 0)      AS total_operacion
              FROM app_dat_extraccion_productos ep
             WHERE ep.id_operacion = o.id
        ) ep_agg ON TRUE
        LEFT JOIN LATERAL (
            SELECT jsonb_build_object(
                'id',               d.id,
                'id_vendedor',      d.id_vendedor,
                'uuid_usuario',     d.uuid_usuario,
                'monto_real',       d.monto_real,
                'monto_descontado', d.monto_descontado,
                'tipo_descuento',   d.tipo_descuento,
                'valor_descuento',  d.valor_descuento,
                'created_at',       d.created_at
            ) AS descuento
              FROM app_dat_descuentos_vendedor d
             WHERE d.id_operacion = o.id
             ORDER BY d.created_at DESC
             LIMIT 1
        ) desc_vendedor ON TRUE
        LEFT JOIN LATERAL (
            SELECT er.estado
              FROM app_dat_estado_operacion er
             WHERE er.id_operacion = o.id
             ORDER BY er.id DESC
             LIMIT 1
        ) e ON TRUE
        LEFT JOIN app_nom_estado_operacion es ON e.estado = es.id
        WHERE
            -- (OPT 2) filtro de acceso por array precalculado
            o.id_tienda = ANY(v_tiendas)
            AND (id_tienda_param IS NULL OR o.id_tienda = id_tienda_param)
            AND (id_tpv_param IS NULL OR EXISTS (
                SELECT 1 FROM app_dat_operacion_venta ov
                 WHERE ov.id_operacion = o.id AND ov.id_tpv = id_tpv_param
            ))
            AND (v_uuid_usuario IS NULL OR o.uuid = v_uuid_usuario)
            AND (id_estado_param IS NULL OR e.estado = id_estado_param)
            AND (v_fecha_inicio IS NULL OR o.created_at >= v_fecha_inicio)
            AND (v_fecha_fin    IS NULL OR o.created_at <= v_fecha_fin)
            AND (id_tipo_operacion_param IS NULL OR o.id_tipo_operacion = id_tipo_operacion_param)
        ORDER BY o.created_at DESC
        LIMIT  CASE WHEN limite_param = 0 THEN NULL ELSE limite_param END
        OFFSET CASE WHEN limite_param = 0 THEN 0 ELSE (pagina_param - 1) * limite_param END
    )
    SELECT
        of.id                                                   AS id_operacion,
        of.tipo_operacion_nombre                                AS tipo_operacion,
        of.id_tienda,
        of.tienda_nombre,
        (of.datos_especificos->>'id_tpv')::BIGINT               AS id_tpv,
        (of.datos_especificos->>'tpv_nombre')::VARCHAR          AS tpv_nombre,
        COALESCE(
            (SELECT nombres || ' ' || apellidos
               FROM app_dat_trabajadores
              WHERE uuid = of.uuid
              LIMIT 1),
            of.usuario_email
        )                                                       AS usuario_nombre,
        of.estado,
        of.estado_nombre,
        of.created_at                                           AS fecha_operacion,
        of.total_operacion,
        of.cantidad_items::INTEGER,
        of.observaciones::TEXT,
        jsonb_build_object(
            'detalles_especificos', of.datos_especificos,
            'cliente', jsonb_build_object(
                'id_cliente',       of.datos_especificos->>'id_cliente',
                'nombre_completo',  of.datos_especificos->>'cliente_nombre',
                'telefono',         of.datos_especificos->>'cliente_telefono'
            ),
            -- Contrato v1 a nivel de operacion: version y clave de la
            -- huella de idempotencia (para rearmar la seleccion al
            -- reimprimir sin tocar precios vigentes).
            'version_monetaria', (
                SELECT ov.version_monetaria
                  FROM app_dat_operacion_venta ov
                 WHERE ov.id_operacion = of.id
                 LIMIT 1
            ),
            'client_uuid', (
                SELECT i.client_uuid
                  FROM app_dat_operacion_offline_idempotencia i
                 WHERE i.id_operacion = of.id
                   AND i.tipo = 'venta_v1'
                 LIMIT 1
            ),
            'items', (
                SELECT jsonb_agg(jsonb_build_object(
                    'id_extraccion',    ep.id,
                    'id_producto',      ep.id_producto,
                    'producto_nombre',  p.denominacion,
                    'sku_producto',     p.sku,
                    'descripcion',      p.descripcion,
                    'cantidad',         ep.cantidad,
                    'precio_unitario',  ep.precio_unitario,
                    'importe',          ep.importe,
                    'presentacion',     np.denominacion,
                    'id_ubicacion',     ep.id_ubicacion,
                    'nombre_ubicacion',  ubi.denominacion,
                    'sku_ubicacion',     ep.sku_ubicacion,
                    'cantidad_inicial', ip.cantidad_inicial,
                    'cantidad_final',   ip.cantidad_final,
                    'es_elaborado',     p.es_elaborado,
                    'entradas_producto', (
                        SELECT COALESCE(SUM(ip2.cantidad_final - ip2.cantidad_inicial), 0)
                          FROM app_dat_inventario_productos ip2
                         WHERE ip2.id_producto = ep.id_producto
                           AND ip2.id_recepcion IS NOT NULL
                           AND ip2.created_at >= v_fecha_inicio
                           AND ip2.created_at <= v_fecha_fin
                    ),
                    'variante', CASE
                        WHEN ep.id_variante IS NOT NULL THEN jsonb_build_object(
                            'id',       ep.id_variante,
                            'atributo', atr.denominacion,
                            'opcion',   ao.valor
                        )
                        ELSE NULL
                    END,
                    -- Contrato v1 por linea: todo lo necesario para
                    -- rearmar `seleccion` en el cliente.
                    'version_monetaria',             ep.version_monetaria,
                    'id_linea_cliente',              ep.id_linea_cliente,
                    'moneda_venta',                  ep.moneda_venta,
                    'id_medio_pago_seleccionado',    ep.id_medio_pago_seleccionado,
                    'seleccion_pendiente',           ep.seleccion_pendiente,
                    'precio_unitario_nativo',        ep.precio_unitario_nativo,
                    'descuento_manual_unitario_nativo', ep.descuento_manual_unitario_nativo,
                    'precio_unitario_neto_nativo',   ep.precio_unitario_neto_nativo,
                    'importe_neto_nativo',           ep.importe_neto_nativo,
                    'tasa_cambio_cup',               ep.tasa_cambio_cup,
                    'snapshot_precio',               ep.snapshot_precio,
                    'snapshot_tasa',                 ep.snapshot_tasa,
                    'snapshot_descuentos',           ep.snapshot_descuentos
                ))
                FROM app_dat_extraccion_productos ep
                JOIN app_dat_producto p              ON ep.id_producto = p.id
                LEFT JOIN app_dat_inventario_productos ip ON ep.id = ip.id_extraccion
                LEFT JOIN app_dat_layout_almacen ubi   ON ep.id_ubicacion = ubi.id
                LEFT JOIN app_dat_variantes var         ON ep.id_variante = var.id
                LEFT JOIN app_dat_atributos atr         ON var.id_atributo = atr.id
                LEFT JOIN app_dat_atributo_opcion ao    ON ep.id_opcion_variante = ao.id
                LEFT JOIN app_dat_producto_presentacion pp ON ep.id_presentacion = pp.id
                LEFT JOIN app_nom_presentacion np        ON pp.id_presentacion = np.id
                WHERE ep.id_operacion = of.id
            ),
            'pagos', (
                SELECT jsonb_agg(jsonb_build_object(
                    'medio_pago',              mp.denominacion,
                    'id_medio_pago',           mp.id,
                    'monto',                   pv.monto,
                    'total',                   pv.monto,
                    'total_sin_descuento',     pv.importe_sin_descuento,
                    'referencia_pago',         pv.referencia_pago,
                    'fecha_pago',              pv.fecha_pago,
                    'es_digital',              mp.es_digital,
                    'es_efectivo',             mp.es_efectivo,
                    'tipo_pago',                pv.tipo_pago,
                    'moneda',                  COALESCE(NULLIF(upper(trim(pv.moneda)), ''), 'CUP'),
                    'tasa_usd',                pv.tasa_usd,
                    'monto_cup_equivalente',   pv.monto_cup_equivalente
                ))
                FROM app_dat_pago_venta pv
                JOIN app_nom_medio_pago mp ON pv.id_medio_pago = mp.id
                WHERE pv.id_operacion_venta = of.id
                  AND mp.es_activo = TRUE
            ),
            'descuento', of.descuento,
            'paqueteria', (
                SELECT jsonb_build_object(
                    'numero_paquete', paq.numero_paquete,
                    'descripcion',    paq.descripcion,
                    'paqueteria',     ord.paqueteria,
                    'order_id',       ord.id
                )
                FROM public.paqueteria_ordenes paq
                JOIN carnavalapp."Orders" ord ON ord.id = paq.id_orden_carnaval
                WHERE paq.id_operacion = of.id
                LIMIT 1
            )
        ) AS detalles
    FROM operaciones_filtradas of;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_listar_ordenes_m01(bigint, bigint, uuid, smallint, date, date, bigint, boolean, boolean, integer, integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_listar_ordenes_m01(bigint, bigint, uuid, smallint, date, date, bigint, boolean, boolean, integer, integer)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) fn_actualizar_precio_promedio_recepcion_v2_m01
-- ---------------------------------------------------------------------------
-- Cuerpo con costos adicionales por tipo (app_dat_producto_costo /
-- app_dat_recepcion_producto_costo) y ponderación en unidades base.
DO $preflight$
DECLARE
    v_nombre text;
BEGIN
    FOREACH v_nombre IN ARRAY ARRAY[
        'fn_es_operacion_sin_actualizar_precio_costo',
        'fn_presentaciones_producto',
        'fn_stock_saldos_presentacion'
    ] LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.proname = v_nombre
        ) THEN
            RAISE EXCEPTION 'Falta public.% en este proyecto', v_nombre;
        END IF;
    END LOOP;
    IF to_regclass('public.app_dat_recepcion_producto_costo') IS NULL
       OR to_regclass('public.app_dat_producto_costo') IS NULL
       OR to_regclass('public.app_dat_consignacion_envio') IS NULL THEN
        RAISE EXCEPTION 'Faltan tablas de costos de recepción (app_dat_recepcion_producto_costo / app_dat_producto_costo)';
    END IF;
END
$preflight$;

CREATE OR REPLACE FUNCTION public.fn_actualizar_precio_promedio_recepcion_v2_m01(p_id_operacion bigint, p_productos jsonb)
 RETURNS TABLE(success boolean, mensaje text, productos_actualizados integer, tiempo_ms integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_inicio        timestamptz := clock_timestamp();
    v_actualizados  int := 0;
    v_tiempo        int;
    v_es_devolucion boolean;
    v_fila          record;
    v_linea         record;
    v_costo         record;
    v_id_producto   bigint;
    v_factor_rel    numeric;
    v_id_base       bigint;
    v_saldo_base    numeric;
    v_costo_ant     numeric;
    v_costo_nuevo   numeric;
    v_id_rp         bigint;
    v_prev_avg      numeric;
    v_nuevo_avg     numeric;
    v_adicionales   numeric;
    v_puro_dto      numeric;
    v_cant_base_ln  numeric;
    v_costos_json   jsonb;
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

    -- Por línea: auditoría de costos + costo_real efectivo + promedio por concepto.
    -- costos[] en jsonb tiene prioridad; si viene vacío se leen filas ya
    -- persistidas en app_dat_recepcion_producto_costo (alta de recepción).
    FOR v_linea IN
        SELECT
            (e->>'id_presentacion')::bigint AS id_pp,
            (e->>'precio_unitario')::numeric AS precio_unitario,
            (e->>'cantidad')::numeric        AS cantidad,
            COALESCE(e->'costos', '[]'::jsonb) AS costos_json
          FROM jsonb_array_elements(p_productos) e
         WHERE NULLIF(e->>'id_presentacion','') IS NOT NULL
           AND NULLIF(e->>'precio_unitario','') IS NOT NULL
           AND NULLIF(e->>'cantidad','')        IS NOT NULL
           AND (e->>'precio_unitario')::numeric > 0
           AND (e->>'cantidad')::numeric        > 0
    LOOP
        SELECT pp.id_producto,
               COALESCE(f.factor_rel, 1)
          INTO v_id_producto, v_factor_rel
          FROM app_dat_producto_presentacion pp
          LEFT JOIN LATERAL public.fn_presentaciones_producto(pp.id_producto) f
                 ON f.id_presentacion = pp.id
         WHERE pp.id = v_linea.id_pp;

        IF v_id_producto IS NULL THEN
            CONTINUE;
        END IF;

        v_factor_rel := COALESCE(v_factor_rel, 1);
        v_cant_base_ln := v_linea.cantidad * v_factor_rel;

        SELECT rp.id INTO v_id_rp
          FROM app_dat_recepcion_productos rp
         WHERE rp.id_operacion = p_id_operacion
           AND rp.id_presentacion = v_linea.id_pp
         ORDER BY rp.id
         LIMIT 1;

        IF v_id_rp IS NULL THEN
            SELECT rp.id INTO v_id_rp
              FROM app_dat_recepcion_productos rp
             WHERE rp.id_operacion = p_id_operacion
               AND rp.id_producto = v_id_producto
             ORDER BY rp.id
             LIMIT 1;
        END IF;

        v_costos_json := v_linea.costos_json;
        IF (v_costos_json IS NULL
            OR jsonb_typeof(v_costos_json) <> 'array'
            OR jsonb_array_length(v_costos_json) = 0)
           AND v_id_rp IS NOT NULL THEN
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                     'id_tipo_costo', rpc.id_tipo_costo,
                     'monto_usd', rpc.monto_usd
                   )), '[]'::jsonb)
              INTO v_costos_json
              FROM app_dat_recepcion_producto_costo rpc
             WHERE rpc.id_recepcion_producto = v_id_rp AND rpc.revertido_at IS NULL;
        END IF;

        IF v_costos_json IS NULL
           OR jsonb_typeof(v_costos_json) <> 'array'
           OR jsonb_array_length(v_costos_json) = 0 THEN
            CONTINUE;
        END IF;

        v_adicionales := 0;

        FOR v_costo IN
            SELECT (c->>'id_tipo_costo')::bigint AS id_tipo_costo,
                   (c->>'monto_usd')::numeric    AS monto_usd
              FROM jsonb_array_elements(v_costos_json) c
             WHERE NULLIF(c->>'id_tipo_costo','') IS NOT NULL
               AND NULLIF(c->>'monto_usd','') IS NOT NULL
        LOOP
            v_adicionales := v_adicionales + COALESCE(v_costo.monto_usd, 0);

            SELECT COALESCE(pc.monto_promedio_usd, 0) INTO v_prev_avg
              FROM app_dat_producto_costo pc
             WHERE pc.id_producto = v_id_producto
               AND pc.id_tipo_costo = v_costo.id_tipo_costo
             FOR UPDATE;

            IF NOT FOUND THEN
                v_prev_avg := 0;
            END IF;

            IF v_id_rp IS NOT NULL AND NOT EXISTS (
                SELECT 1 FROM app_dat_recepcion_producto_costo x
                 WHERE x.id_recepcion_producto = v_id_rp
                   AND x.id_tipo_costo = v_costo.id_tipo_costo AND x.revertido_at IS NULL
            ) THEN
                INSERT INTO app_dat_recepcion_producto_costo (
                    id_recepcion_producto, id_tipo_costo, monto_usd, monto_promedio_anterior
                ) VALUES (
                    v_id_rp, v_costo.id_tipo_costo, v_costo.monto_usd, v_prev_avg
                );
            END IF;

            SELECT COALESCE(SUM(s.equivalente_base), 0) INTO v_saldo_base
              FROM public.fn_stock_saldos_presentacion(v_id_producto, NULL, NULL, false) s;

            v_saldo_base := GREATEST(v_saldo_base - v_cant_base_ln, 0);

            IF (v_saldo_base + v_cant_base_ln) = 0 THEN
                v_nuevo_avg := v_costo.monto_usd;
            ELSIF v_prev_avg <= 0 OR v_saldo_base <= 0 THEN
                v_nuevo_avg := v_costo.monto_usd;
            ELSE
                v_nuevo_avg := (
                    (v_prev_avg * v_saldo_base)
                    + (v_costo.monto_usd * v_cant_base_ln)
                ) / (v_saldo_base + v_cant_base_ln);
            END IF;

            INSERT INTO app_dat_producto_costo (
                id_producto, id_tipo_costo, monto_usd, monto_promedio_usd, activo
            ) VALUES (
                v_id_producto, v_costo.id_tipo_costo,
                v_costo.monto_usd, v_nuevo_avg, true
            )
            ON CONFLICT (id_producto, id_tipo_costo) DO UPDATE
              SET monto_promedio_usd = EXCLUDED.monto_promedio_usd;
        END LOOP;

        IF v_id_rp IS NOT NULL AND v_adicionales <> 0 THEN
            SELECT
                (COALESCE(rp.precio_unitario, 0) - COALESCE(rp.descuento_monto, 0))
                - ((COALESCE(rp.precio_referencia, 0) * COALESCE(rp.descuento_porcentaje, 0)) / 100)
              INTO v_puro_dto
              FROM app_dat_recepcion_productos rp
             WHERE rp.id = v_id_rp;

            UPDATE app_dat_recepcion_productos
               SET costo_real = COALESCE(v_puro_dto, 0) + (v_adicionales * v_factor_rel)
             WHERE id = v_id_rp;
        END IF;
    END LOOP;

    -- Ponderación de precio_promedio con costo efectivo (puro + adicionales)
    FOR v_fila IN
        WITH entrada AS (
            SELECT (e->>'id_presentacion')::bigint AS id_pp,
                   (e->>'precio_unitario')::numeric AS precio_unitario,
                   (e->>'cantidad')::numeric        AS cantidad,
                   COALESCE(e->'costos', '[]'::jsonb) AS costos
              FROM jsonb_array_elements(p_productos) e
             WHERE NULLIF(e->>'id_presentacion','') IS NOT NULL
               AND NULLIF(e->>'precio_unitario','') IS NOT NULL
               AND NULLIF(e->>'cantidad','')        IS NOT NULL
               AND (e->>'precio_unitario')::numeric > 0
               AND (e->>'cantidad')::numeric        > 0
        ),
        con_factor AS (
            SELECT pp.id_producto,
                   en.cantidad * COALESCE(f.factor_rel, 1) AS cant_base,
                   (en.precio_unitario / NULLIF(COALESCE(f.factor_rel, 1), 0))
                     + COALESCE((
                         SELECT SUM(x.monto)
                           FROM (
                             SELECT (c->>'monto_usd')::numeric AS monto
                               FROM jsonb_array_elements(en.costos) c
                              WHERE jsonb_typeof(en.costos) = 'array'
                                AND jsonb_array_length(en.costos) > 0
                                AND NULLIF(c->>'id_tipo_costo','') IS NOT NULL
                                AND NULLIF(c->>'monto_usd','') IS NOT NULL
                             UNION ALL
                             SELECT rpc.monto_usd
                               FROM app_dat_recepcion_productos rp
                               JOIN app_dat_recepcion_producto_costo rpc
                                 ON rpc.id_recepcion_producto = rp.id
                              WHERE (jsonb_typeof(en.costos) <> 'array'
                                     OR jsonb_array_length(en.costos) = 0)
                                AND rp.id_operacion = p_id_operacion
                                AND rp.id_presentacion = en.id_pp
                           ) x
                       ), 0) AS costo_base
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

        UPDATE app_dat_producto_presentacion
           SET precio_promedio = v_costo_nuevo
         WHERE id = v_id_base
           AND COALESCE(precio_promedio, -1) <> v_costo_nuevo::real;

        IF FOUND THEN
            v_actualizados := v_actualizados + 1;
        END IF;

        -- Propagación: costo_presentacion = costo_base * factor_rel
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
$function$;

REVOKE ALL ON FUNCTION public.fn_actualizar_precio_promedio_recepcion_v2_m01(bigint, jsonb)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_actualizar_precio_promedio_recepcion_v2_m01(bigint, jsonb)
  TO authenticated, service_role;
