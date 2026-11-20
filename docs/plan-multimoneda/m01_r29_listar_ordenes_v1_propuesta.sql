BEGIN;

-- BORRADOR MC-055. NO EJECUTAR en main.
-- El listado de ordenes no emitia el contrato v1: las lineas llegaban sin
-- version_monetaria ni campos nativos, la app caia al camino legacy y el
-- ticket imprimia precio_unitario (NULL en lineas USD) como 0. Se agregan
-- a detalles.items las columnas v1 de app_dat_extraccion_productos y a
-- detalles la version y el client_uuid de la huella de idempotencia, para
-- que la reimpresion reconstruya la seleccion sin consultar precios
-- vigentes. No cambia filtros, totales ni pagos.

SET LOCAL app.m01_r29_listar_ordenes_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r29_listar_ordenes_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador MC-055: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    -- Solo reemplaza el cuerpo vigente (items sin campos v1) o una corrida
    -- previa de esta enmienda; cualquier otro cuerpo aborta.
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE oid = to_regprocedure('public.fn_listar_ordenes(bigint,bigint,uuid,smallint,date,date,bigint,boolean,boolean,integer,integer)')
          AND prosecdef AND proowner = 'postgres'::regrole
          AND (position('''entradas_producto''' in prosrc) > 0)
          AND (position('''id_linea_cliente''' in prosrc) = 0
               OR position('''id_linea_cliente''' in prosrc) > 0)
    ) THEN
        RAISE EXCEPTION 'fn_listar_ordenes difiere del cuerpo vigente en newa; revisar sin reemplazar avances';
    END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.fn_listar_ordenes(
    id_tienda_param bigint DEFAULT NULL::bigint,
    id_tpv_param bigint DEFAULT NULL::bigint,
    id_usuario_param uuid DEFAULT NULL::uuid,
    id_estado_param smallint DEFAULT NULL::smallint,
    fecha_desde_param date DEFAULT NULL::date,
    fecha_hasta_param date DEFAULT NULL::date,
    id_tipo_operacion_param bigint DEFAULT NULL::bigint,
    con_inventario_param boolean DEFAULT false,
    solo_pendientes_param boolean DEFAULT false,
    limite_param integer DEFAULT 0,
    pagina_param integer DEFAULT 1
)
RETURNS TABLE(
    id_operacion bigint, tipo_operacion character varying, id_tienda bigint,
    tienda_nombre character varying, id_tpv bigint, tpv_nombre character varying,
    usuario_nombre text, estado smallint, estado_nombre text,
    fecha_operacion timestamp with time zone, total_operacion numeric,
    cantidad_items integer, observaciones text, detalles jsonb
)
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

COMMIT;
