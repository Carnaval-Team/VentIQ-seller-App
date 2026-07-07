-- FUNCTION: public.listar_ordenes_mesa
-- Versión "mesa" del listador, con soporte para filtrar por id_mesa
-- y exponer datos de la mesa en `detalles_especificos`.
--
-- DROP FUNCTION IF EXISTS public.listar_ordenes_mesa(bigint, bigint, uuid, smallint, date, date, bigint, boolean, boolean, integer, integer, bigint);

CREATE OR REPLACE FUNCTION public.listar_ordenes_mesa(
	id_tienda_param bigint DEFAULT NULL::bigint,
	id_tpv_param bigint DEFAULT NULL::bigint,
	id_usuario_param uuid DEFAULT NULL::uuid,
	id_estado_param smallint DEFAULT NULL::smallint,
	fecha_desde_param date DEFAULT NULL::date,
	fecha_hasta_param date DEFAULT NULL::date,
	id_tipo_operacion_param bigint DEFAULT NULL::bigint,
	con_inventario_param boolean DEFAULT false,
	solo_pendientes_param boolean DEFAULT false,
	limite_param integer DEFAULT 50,
	pagina_param integer DEFAULT 1,
	id_mesa_param bigint DEFAULT NULL::bigint)
    RETURNS TABLE(id_operacion bigint, tipo_operacion character varying, id_tienda bigint, tienda_nombre character varying, id_tpv bigint, tpv_nombre character varying, usuario_nombre text, estado smallint, estado_nombre text, fecha_operacion timestamp with time zone, total_operacion numeric, cantidad_items integer, observaciones text, detalles jsonb)
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE SECURITY DEFINER PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
DECLARE
    v_fecha_inicio timestamptz;
    v_fecha_fin timestamptz;
    v_tiene_turno_abierto boolean := false;
    v_id_turno_abierto BIGINT;
    v_uuid_usuario UUID := NULL;
BEGIN
    -- Establecer contexto
    SET search_path = public;

    -- Obtener el usuario autenticado si no se pasa
    v_uuid_usuario := COALESCE(id_usuario_param, auth.uid());
    -- Verificar que el usuario tenga permisos en al menos una tienda
    PERFORM check_user_has_access_to_any_tienda();

    -- Si NO se pasan fechas, usamos el turno abierto del vendedor en el TPV
    -- EXCEPTO si estamos filtrando por mesa (en ese caso queremos todo el histórico)
    IF fecha_desde_param IS NULL AND fecha_hasta_param IS NULL
       AND id_tpv_param IS NOT NULL AND v_uuid_usuario IS NOT NULL
       AND id_mesa_param IS NULL THEN
        -- Buscar el turno abierto del vendedor en ese TPV
        SELECT ct.id, ct.fecha_apertura
        INTO v_id_turno_abierto, v_fecha_inicio
        FROM app_dat_caja_turno ct
        JOIN app_dat_vendedor v ON ct.id_vendedor = v.id
        WHERE ct.id_tpv = id_tpv_param
          AND v.uuid = v_uuid_usuario
          AND ct.estado = 1 -- Abierto
        ORDER BY ct.fecha_apertura DESC
        LIMIT 1;

        IF NOT FOUND THEN
            -- No hay turno abierto → no devolver nada
            RETURN;
        END IF;

        v_fecha_fin := NOW(); -- Hasta ahora
        v_tiene_turno_abierto := TRUE;
    ELSE
        -- Si se pasan fechas, usamos ese rango
        v_fecha_inicio := fecha_desde_param;
        v_fecha_fin := COALESCE(fecha_hasta_param, CURRENT_DATE) + INTERVAL '1 day' - INTERVAL '1 second';
    END IF;

    RETURN QUERY
    WITH operaciones_filtradas AS (
        SELECT
            o.id,
            o.created_at,
            o.id_tipo_operacion,
            top.denominacion AS tipo_operacion_nombre,
            o.id_tienda,
            t.denominacion AS tienda_nombre,
            o.uuid,
            COALESCE(u.email, 'Sistema') AS usuario_email,
            e.estado,
            desc_vendedor.descuento AS descuento,
            CASE
                WHEN e.estado = 1 THEN 'Pendiente'
                WHEN e.estado = 2 THEN 'Completada'
                WHEN e.estado = 3 THEN 'Cancelada'
                WHEN e.estado = 4 THEN 'En Proceso'
                ELSE 'Desconocido'
            END AS estado_nombre,
            o.observaciones::TEXT,
            -- Datos específicos de TPV para operaciones de venta
            CASE
                WHEN o.id_tipo_operacion = (SELECT id FROM app_nom_tipo_operacion WHERE LOWER(denominacion) = 'venta' LIMIT 1) THEN
                    (SELECT jsonb_build_object(
                        'id_tpv', ov.id_tpv,
                        'tpv_nombre', tp.denominacion,
                        'codigo_promocion', ov.codigo_promocion,
                        'id_cliente', ov.id_cliente,
                        'cliente_nombre', cli.nombre_completo,
                        'cliente_telefono', cli.telefono,
                        'id_mesa', ov.id_mesa,
                        'mesa_numero', mesa.numero,
                        'mesa_zona', mesa.zona,
                        'mesa_capacidad', mesa.capacidad
                    )
                    FROM app_dat_operacion_venta ov
                    JOIN app_dat_tpv tp ON ov.id_tpv = tp.id
                    LEFT JOIN app_dat_clientes cli ON ov.id_cliente = cli.id
                    LEFT JOIN app_dat_mesas mesa ON ov.id_mesa = mesa.id
                    WHERE ov.id_operacion = o.id
                    LIMIT 1)
                ELSE NULL
            END AS datos_especificos,
            -- Contar items en la operación
            (SELECT COUNT(*) FROM app_dat_extraccion_productos ep WHERE ep.id_operacion = o.id)::INTEGER AS cantidad_items,
            -- Calcular total de la operación
            (SELECT COALESCE(SUM(ep.importe), 0) FROM app_dat_extraccion_productos ep WHERE ep.id_operacion = o.id) AS total_operacion
        FROM
            app_dat_operaciones o
        JOIN
            app_nom_tipo_operacion top ON o.id_tipo_operacion = top.id
        JOIN
            app_dat_tienda t ON o.id_tienda = t.id
        LEFT JOIN
            auth.users u ON o.uuid = u.id
        LEFT JOIN LATERAL (
         SELECT jsonb_build_object(
        'id', d.id,
        'id_vendedor', d.id_vendedor,
        'uuid_usuario', d.uuid_usuario,
        'monto_real', d.monto_real,
        'monto_descontado', d.monto_descontado,
        'tipo_descuento', d.tipo_descuento,
        'valor_descuento', d.valor_descuento,
        'created_at', d.created_at
      ) AS descuento
       FROM app_dat_descuentos_vendedor d
       WHERE d.id_operacion = o.id
       ORDER BY d.created_at DESC
       LIMIT 1
       ) desc_vendedor ON TRUE
        LEFT JOIN
            app_dat_estado_operacion e ON e.id_operacion = o.id AND e.id = (
                SELECT MAX(id) FROM app_dat_estado_operacion er WHERE er.id_operacion = o.id
            )
        WHERE
            -- Filtros básicos
            (id_tienda_param IS NULL OR o.id_tienda = id_tienda_param)
            AND (id_tpv_param IS NULL OR EXISTS (
                SELECT 1 FROM app_dat_operacion_venta ov
                WHERE ov.id_operacion = o.id AND ov.id_tpv = id_tpv_param
            ))
            -- Filtro por mesa (nuevo)
            AND (id_mesa_param IS NULL OR EXISTS (
                SELECT 1 FROM app_dat_operacion_venta ov
                WHERE ov.id_operacion = o.id AND ov.id_mesa = id_mesa_param
            ))
            AND (v_uuid_usuario IS NULL OR o.uuid = v_uuid_usuario OR id_mesa_param IS NOT NULL)
            AND (id_estado_param IS NULL OR e.estado = id_estado_param)
            -- Filtro de fechas basado en turno o parámetros
            AND (v_fecha_inicio IS NULL OR o.created_at >= v_fecha_inicio)
            AND (v_fecha_fin IS NULL OR o.created_at <= v_fecha_fin)
            AND (id_tipo_operacion_param IS NULL OR o.id_tipo_operacion = id_tipo_operacion_param)
            -- Filtro de permisos del usuario
            AND EXISTS (
                SELECT 1 FROM (
                    SELECT gr.id_tienda FROM app_dat_gerente gr WHERE gr.uuid = auth.uid()
                    UNION
                    SELECT sup.id_tienda FROM app_dat_supervisor sup WHERE sup.uuid = auth.uid()
                    UNION
                    SELECT aud.id_tienda FROM auditor aud WHERE aud.uuid = auth.uid()
                    UNION
                    SELECT a.id_tienda FROM app_dat_almacenero al
                    JOIN app_dat_almacen a ON al.id_almacen = a.id
                    WHERE al.uuid = auth.uid()
                    UNION
                    SELECT tpv.id_tienda FROM app_dat_vendedor v
                    JOIN app_dat_tpv tpv ON v.id_tpv = tpv.id
                    WHERE v.uuid = auth.uid()
                ) AS tiendas_usuario
                WHERE tiendas_usuario.id_tienda = o.id_tienda
            )
        ORDER BY
            o.created_at DESC
        LIMIT
            CASE WHEN limite_param = 0 THEN NULL ELSE limite_param END
        OFFSET
            CASE WHEN limite_param = 0 THEN 0 ELSE (pagina_param - 1) * limite_param END
    )
    SELECT
        of.id AS id_operacion,
        of.tipo_operacion_nombre AS tipo_operacion,
        of.id_tienda,
        of.tienda_nombre,
        (of.datos_especificos->>'id_tpv')::BIGINT AS id_tpv,
        (of.datos_especificos->>'tpv_nombre')::VARCHAR AS tpv_nombre,
        COALESCE(
            (SELECT nombres || ' ' || apellidos
             FROM app_dat_trabajadores
             WHERE uuid = of.uuid
             LIMIT 1),
            of.usuario_email
        ) AS usuario_nombre,
        of.estado,
        of.estado_nombre,
        of.created_at AS fecha_operacion,
        of.total_operacion,
        of.cantidad_items::INTEGER,
        of.observaciones::TEXT,
        jsonb_build_object(
    'detalles_especificos', of.datos_especificos,
    'cliente', jsonb_build_object(
        'id_cliente', of.datos_especificos->>'id_cliente',
        'nombre_completo', of.datos_especificos->>'cliente_nombre',
        'telefono', of.datos_especificos->>'cliente_telefono'
    ),
    'mesa', CASE
        WHEN (of.datos_especificos->>'id_mesa') IS NOT NULL THEN jsonb_build_object(
            'id_mesa', (of.datos_especificos->>'id_mesa')::BIGINT,
            'numero',  of.datos_especificos->>'mesa_numero',
            'zona',    of.datos_especificos->>'mesa_zona',
            'capacidad', (of.datos_especificos->>'mesa_capacidad')::INTEGER
        )
        ELSE NULL
    END,
    'items', (
    SELECT jsonb_agg(jsonb_build_object(
        'id_extraccion', ep.id,
        'id_producto', ep.id_producto,
        'producto_nombre', p.denominacion,
        'cantidad', ep.cantidad,
        'precio_unitario', ep.precio_unitario,
        'importe', ep.importe,
        'presentacion', np.denominacion,
        'cantidad_inicial', ip.cantidad_inicial,
        'cantidad_final', ip.cantidad_final,
        'es_elaborado',p.es_elaborado,
        'entradas_producto', (
            SELECT COALESCE(SUM(ip_entradas.cantidad_final - ip_entradas.cantidad_inicial), 0)
            FROM app_dat_inventario_productos ip_entradas
            WHERE ip_entradas.id_producto = ep.id_producto
              AND ip_entradas.id_recepcion IS NOT NULL
              AND ip_entradas.created_at >= COALESCE(v_fecha_inicio, '1970-01-01'::timestamptz)
              AND ip_entradas.created_at <= COALESCE(v_fecha_fin,    NOW())
        ),
        'variante', CASE
            WHEN ep.id_variante IS NOT NULL THEN jsonb_build_object(
                'id', ep.id_variante,
                'atributo', a.denominacion,
                'opcion', ao.valor
            )
            ELSE NULL
        END
    ))
    FROM app_dat_extraccion_productos ep
    JOIN app_dat_producto p ON ep.id_producto = p.id
    LEFT JOIN app_dat_inventario_productos ip ON ep.id = ip.id_extraccion
    LEFT JOIN app_dat_variantes v ON ep.id_variante = v.id
    LEFT JOIN app_dat_atributos a ON v.id_atributo = a.id
    LEFT JOIN app_dat_atributo_opcion ao ON ep.id_opcion_variante = ao.id
    LEFT JOIN app_dat_producto_presentacion pp ON ep.id_presentacion = pp.id
    LEFT JOIN app_nom_presentacion np ON pp.id_presentacion = np.id
    WHERE ep.id_operacion = of.id
),
    'pagos', (
        SELECT jsonb_agg(jsonb_build_object(
            'medio_pago', mp.denominacion,
            'total', pv.monto,
            'total_sin_descuento',pv.importe_sin_descuento,
            'referencia_pago', pv.referencia_pago,
            'fecha_pago', pv.fecha_pago,
            'es_digital', mp.es_digital,
            'es_efectivo', mp.es_efectivo,
            'tipo_pago',pv.tipo_pago
        ))
        FROM app_dat_operacion_venta ov
        JOIN app_dat_pago_venta pv ON ov.id_operacion = pv.id_operacion_venta
        JOIN app_nom_medio_pago mp ON pv.id_medio_pago = mp.id
        WHERE ov.id_operacion = of.id
        AND mp.es_activo = true
    ),
    'descuento', of.descuento,
    'paqueteria', (
              SELECT jsonb_build_object(
                  'numero_paquete', paq.numero_paquete,
                  'descripcion', paq.descripcion,
                  'paqueteria', ord.paqueteria,
                  'order_id',ord.id
              )
              FROM public.paqueteria_ordenes paq
              JOIN carnavalapp."Orders" ord ON ord.id = paq.id_orden_carnaval
              WHERE paq.id_operacion = of.id
              LIMIT 1
          )
) AS detalles
    FROM
        operaciones_filtradas of;
END;
$BODY$;

ALTER FUNCTION public.listar_ordenes_mesa(bigint, bigint, uuid, smallint, date, date, bigint, boolean, boolean, integer, integer, bigint)
    OWNER TO postgres;

GRANT EXECUTE ON FUNCTION public.listar_ordenes_mesa(bigint, bigint, uuid, smallint, date, date, bigint, boolean, boolean, integer, integer, bigint) TO anon;
GRANT EXECUTE ON FUNCTION public.listar_ordenes_mesa(bigint, bigint, uuid, smallint, date, date, bigint, boolean, boolean, integer, integer, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.listar_ordenes_mesa(bigint, bigint, uuid, smallint, date, date, bigint, boolean, boolean, integer, integer, bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.listar_ordenes_mesa(bigint, bigint, uuid, smallint, date, date, bigint, boolean, boolean, integer, integer, bigint) TO service_role;
REVOKE ALL ON FUNCTION public.listar_ordenes_mesa(bigint, bigint, uuid, smallint, date, date, bigint, boolean, boolean, integer, integer, bigint) FROM PUBLIC;
