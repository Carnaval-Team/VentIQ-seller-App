-- =====================================================================
-- fn_listar_turnos_admin
-- Listado auditable y paginado de turnos de caja (app_dat_caja_turno)
-- para el tab "Turnos Tpv" de ventiq_admin_app.
--
-- Objetivos de diseño:
--   * UN SOLO viaje al servidor: nada de N+1 / N*N desde Flutter.
--   * PAGINAR PRIMERO, AGREGAR DESPUES: el CTE "pagina" recorta a
--     p_limite filas usando idx_caja_turno_filtros, y los agregados
--     (ventas, pagos, egresos, unidades) se calculan con LEFT JOIN
--     LATERAL solo sobre esas filas visibles.
--   * Cada agregado en su PROPIO LATERAL. Si se unieran en uno solo,
--     el producto cartesiano entre ventas y extraccion_productos
--     multiplicaria los SUM() (bug presente en fn_resumen_turno_por_id).
--   * El total global sale de COUNT(*) OVER () -> sin query extra de conteo.
--   * Scope de tienda OBLIGATORIO via app_dat_tpv.id_tienda.
--
-- Nota de conciliacion:
--   app_dat_caja_turno.diferencia es una columna generada
--   (efectivo_real - efectivo_esperado), pero efectivo_esperado suele
--   venir en 0 desde el TPV, lo que hace que la diferencia almacenada
--   sea engañosa. Por eso se devuelven AMBAS versiones:
--     - efectivo_esperado_registrado / diferencia_registrada  (lo grabado)
--     - efectivo_esperado_calculado  / diferencia_calculada   (recalculado:
--       fondo inicial + efectivo cobrado - egresos parciales)
--   La UI usa la calculada para semaforizar y muestra la registrada al lado.
--
-- Aplicar con: psql / SQL Editor de Supabase.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.fn_listar_turnos_admin(
    p_id_tienda           bigint,
    p_id_tpv              bigint      DEFAULT NULL,
    p_id_vendedor         bigint      DEFAULT NULL,
    p_estado              smallint    DEFAULT NULL,
    p_fecha_desde         timestamptz DEFAULT NULL,
    p_fecha_hasta         timestamptz DEFAULT NULL,
    p_solo_discrepancias  boolean     DEFAULT false,
    p_busqueda            text        DEFAULT NULL,
    p_limite              integer     DEFAULT 20,
    p_pagina              integer     DEFAULT 1
)
RETURNS TABLE (
    turno_id                     bigint,
    id_tpv                       bigint,
    tpv_denominacion             text,
    id_vendedor                  bigint,
    vendedor_nombre              text,
    vendedor_uuid                uuid,
    id_trabajador                bigint,
    estado                       smallint,
    estado_denominacion          text,
    fecha_apertura               timestamptz,
    fecha_cierre                 timestamptz,
    duracion_minutos             numeric,
    maneja_inventario            boolean,
    id_operacion_apertura        bigint,
    id_operacion_cierre          bigint,
    efectivo_inicial             numeric,
    efectivo_esperado_registrado numeric,
    efectivo_esperado_calculado  numeric,
    efectivo_real                numeric,
    diferencia_registrada        numeric,
    diferencia_calculada         numeric,
    conciliacion_estado          text,
    ventas_totales               numeric,
    operaciones_venta            bigint,
    ventas_pagadas               bigint,
    ticket_promedio              numeric,
    productos_vendidos           numeric,
    total_pagos                  numeric,
    total_efectivo               numeric,
    total_digital                numeric,
    porcentaje_efectivo          numeric,
    desglose_pagos               jsonb,
    total_egresos                numeric,
    egresos_cantidad             bigint,
    observaciones                text,
    obs_faltantes_cant           integer,
    obs_excesos_cant             integer,
    cerrado_por_nombre           text,
    total_registros              bigint
)
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    v_limite     integer  := LEAST(GREATEST(COALESCE(p_limite, 20), 1), 200);
    v_pagina     integer  := GREATEST(COALESCE(p_pagina, 1), 1);
    v_offset     integer;
    v_busqueda   text     := NULLIF(BTRIM(COALESCE(p_busqueda, '')), '');
    v_tipo_venta smallint;
BEGIN
    v_offset := (v_pagina - 1) * v_limite;

    -- Se resuelve una sola vez para no repetir el subselect dentro de cada LATERAL
    SELECT t.id INTO v_tipo_venta
    FROM app_nom_tipo_operacion t
    WHERE LOWER(t.denominacion) = 'venta'
    LIMIT 1;

    RETURN QUERY
    WITH pagina AS (
        SELECT
            ct.id,
            ct.id_tpv,
            tpv.denominacion::text AS tpv_denominacion,
            ct.id_vendedor,
            NULLIF(BTRIM(COALESCE(trab.nombres, '') || ' ' || COALESCE(trab.apellidos, '')), '')::text AS vendedor_nombre,
            ven.uuid  AS vendedor_uuid,
            trab.id   AS id_trabajador,
            ct.estado,
            eo.denominacion::text AS estado_denominacion,
            ct.fecha_apertura,
            ct.fecha_cierre,
            ct.maneja_inventario,
            ct.id_operacion_apertura,
            ct.id_operacion_cierre,
            ct.efectivo_inicial,
            ct.efectivo_esperado,
            ct.efectivo_real,
            ct.diferencia,
            ct.observaciones,
            ct.cerrado_por,
            COUNT(*) OVER () AS total_registros
        FROM app_dat_caja_turno ct
        JOIN      app_dat_tpv               tpv  ON tpv.id  = ct.id_tpv
        LEFT JOIN app_dat_vendedor          ven  ON ven.id  = ct.id_vendedor
        LEFT JOIN app_dat_trabajadores      trab ON trab.id = ven.id_trabajador
        LEFT JOIN app_nom_estado_operacion  eo   ON eo.id   = ct.estado
        WHERE tpv.id_tienda = p_id_tienda
          AND (p_id_tpv      IS NULL OR ct.id_tpv         = p_id_tpv)
          AND (p_id_vendedor IS NULL OR ct.id_vendedor    = p_id_vendedor)
          AND (p_estado      IS NULL OR ct.estado         = p_estado)
          AND (p_fecha_desde IS NULL OR ct.fecha_apertura >= p_fecha_desde)
          AND (p_fecha_hasta IS NULL OR ct.fecha_apertura <= p_fecha_hasta)
          AND (COALESCE(p_solo_discrepancias, false) = false
               OR BTRIM(COALESCE(ct.observaciones, '')) <> '')
          AND (v_busqueda IS NULL
               OR tpv.denominacion            ILIKE '%' || v_busqueda || '%'
               OR COALESCE(trab.nombres, '')   ILIKE '%' || v_busqueda || '%'
               OR COALESCE(trab.apellidos, '') ILIKE '%' || v_busqueda || '%'
               OR COALESCE(ct.observaciones, '') ILIKE '%' || v_busqueda || '%'
               OR ct.id::text = v_busqueda)
        ORDER BY ct.fecha_apertura DESC, ct.id DESC
        LIMIT v_limite OFFSET v_offset
    )
    SELECT
        f.id AS turno_id,
        f.id_tpv,
        f.tpv_denominacion,
        f.id_vendedor,
        f.vendedor_nombre,
        f.vendedor_uuid,
        f.id_trabajador,
        f.estado,
        f.estado_denominacion,
        f.fecha_apertura,
        f.fecha_cierre,
        ROUND(EXTRACT(EPOCH FROM (COALESCE(f.fecha_cierre, now()) - f.fecha_apertura)) / 60.0, 1) AS duracion_minutos,
        f.maneja_inventario,
        f.id_operacion_apertura,
        f.id_operacion_cierre,
        f.efectivo_inicial,
        f.efectivo_esperado AS efectivo_esperado_registrado,
        (COALESCE(f.efectivo_inicial, 0) + COALESCE(pg.total_efectivo, 0) - COALESCE(eg.total_egresos, 0)) AS efectivo_esperado_calculado,
        f.efectivo_real,
        f.diferencia AS diferencia_registrada,
        CASE
            WHEN f.efectivo_real IS NULL THEN NULL
            ELSE f.efectivo_real - (COALESCE(f.efectivo_inicial, 0) + COALESCE(pg.total_efectivo, 0) - COALESCE(eg.total_egresos, 0))
        END AS diferencia_calculada,
        CASE
            WHEN f.estado = 1 OR f.fecha_cierre IS NULL THEN 'Abierto'
            WHEN f.efectivo_real IS NULL                THEN 'Sin conteo'
            WHEN ABS(f.efectivo_real - (COALESCE(f.efectivo_inicial, 0) + COALESCE(pg.total_efectivo, 0) - COALESCE(eg.total_egresos, 0))) < 0.005 THEN 'Conciliado'
            WHEN ABS(f.efectivo_real - (COALESCE(f.efectivo_inicial, 0) + COALESCE(pg.total_efectivo, 0) - COALESCE(eg.total_egresos, 0))) <= 1.00 THEN 'Casi exacto'
            WHEN     (f.efectivo_real - (COALESCE(f.efectivo_inicial, 0) + COALESCE(pg.total_efectivo, 0) - COALESCE(eg.total_egresos, 0))) > 0    THEN 'Sobrante'
            ELSE 'Faltante'
        END::text AS conciliacion_estado,
        COALESCE(v.ventas_totales, 0)    AS ventas_totales,
        COALESCE(v.operaciones_venta, 0) AS operaciones_venta,
        COALESCE(v.ventas_pagadas, 0)    AS ventas_pagadas,
        CASE WHEN COALESCE(v.operaciones_venta, 0) > 0
             THEN ROUND(v.ventas_totales / v.operaciones_venta, 2)
             ELSE 0 END AS ticket_promedio,
        COALESCE(pr.productos_vendidos, 0) AS productos_vendidos,
        COALESCE(pg.total_pagos, 0)        AS total_pagos,
        COALESCE(pg.total_efectivo, 0)     AS total_efectivo,
        COALESCE(pg.total_digital, 0)      AS total_digital,
        CASE WHEN COALESCE(pg.total_pagos, 0) > 0
             THEN ROUND(COALESCE(pg.total_efectivo, 0) * 100.0 / pg.total_pagos, 1)
             ELSE 0 END AS porcentaje_efectivo,
        COALESCE(pg.desglose_pagos, '[]'::jsonb) AS desglose_pagos,
        COALESCE(eg.total_egresos, 0)      AS total_egresos,
        COALESCE(eg.egresos_cantidad, 0)   AS egresos_cantidad,
        f.observaciones,
        COALESCE((SELECT count(*)::integer FROM regexp_matches(COALESCE(f.observaciones, ''), 'Faltan[[:space:]]', 'g')), 0) AS obs_faltantes_cant,
        COALESCE((SELECT count(*)::integer FROM regexp_matches(COALESCE(f.observaciones, ''), 'Sobran[[:space:]]', 'g')), 0) AS obs_excesos_cant,
        cerr.nombre_completo AS cerrado_por_nombre,
        f.total_registros
    FROM pagina f

    -- Ventas del TPV dentro de la ventana del turno.
    -- Se filtra o.id_tienda para que el planificador use el indice de fecha
    -- de app_dat_operaciones (probado: mas rapido que arrancar por id_tpv).
    LEFT JOIN LATERAL (
        SELECT
            COUNT(*)                             AS operaciones_venta,
            COALESCE(SUM(ov.importe_total), 0)   AS ventas_totales,
            COUNT(*) FILTER (WHERE ov.es_pagada) AS ventas_pagadas
        FROM app_dat_operacion_venta ov
        JOIN app_dat_operaciones o ON o.id = ov.id_operacion
        WHERE ov.id_tpv = f.id_tpv
          AND o.id_tienda = p_id_tienda
          AND o.id_tipo_operacion = v_tipo_venta
          AND o.created_at >= f.fecha_apertura
          AND o.created_at <= COALESCE(f.fecha_cierre, now())
    ) v ON true

    -- Unidades extraidas. En LATERAL aparte a proposito: unido al de ventas
    -- el fan-out 1:N multiplicaria SUM(importe_total).
    LEFT JOIN LATERAL (
        SELECT COALESCE(SUM(ep.cantidad), 0) AS productos_vendidos
        FROM app_dat_extraccion_productos ep
        JOIN app_dat_operaciones o ON o.id = ep.id_operacion
        WHERE o.id_tienda = p_id_tienda
          AND o.id_tipo_operacion = v_tipo_venta
          AND o.created_at >= f.fecha_apertura
          AND o.created_at <= COALESCE(f.fecha_cierre, now())
          AND EXISTS (
              SELECT 1 FROM app_dat_operacion_venta ov2
              WHERE ov2.id_operacion = o.id AND ov2.id_tpv = f.id_tpv
          )
    ) pr ON true

    -- Cobros por medio de pago: efectivo vs digital + desglose para auditar.
    LEFT JOIN LATERAL (
        SELECT
            COALESCE(SUM(d.monto), 0)                                  AS total_pagos,
            COALESCE(SUM(d.monto) FILTER (WHERE d.es_efectivo), 0)     AS total_efectivo,
            COALESCE(SUM(d.monto) FILTER (WHERE NOT d.es_efectivo), 0) AS total_digital,
            COALESCE(jsonb_agg(jsonb_build_object(
                'medio',       d.medio,
                'monto',       d.monto,
                'es_efectivo', d.es_efectivo,
                'cantidad',    d.cantidad
            ) ORDER BY d.monto DESC), '[]'::jsonb)                     AS desglose_pagos
        FROM (
            SELECT
                mp.denominacion::text           AS medio,
                COALESCE(mp.es_efectivo, false) AS es_efectivo,
                SUM(pv.monto)                   AS monto,
                COUNT(*)                        AS cantidad
            FROM app_dat_pago_venta pv
            JOIN app_nom_medio_pago mp      ON mp.id = pv.id_medio_pago
            -- OJO: pago_venta.id_operacion_venta referencia operacion_venta.id_operacion
            JOIN app_dat_operacion_venta ov ON ov.id_operacion = pv.id_operacion_venta
            JOIN app_dat_operaciones o      ON o.id = ov.id_operacion
            WHERE ov.id_tpv = f.id_tpv
              AND o.id_tienda = p_id_tienda
              AND o.created_at >= f.fecha_apertura
              AND o.created_at <= COALESCE(f.fecha_cierre, now())
            GROUP BY mp.denominacion, mp.es_efectivo
        ) d
    ) pg ON true

    -- Entregas parciales de caja (egresos) del turno.
    LEFT JOIN LATERAL (
        SELECT
            COUNT(*)                            AS egresos_cantidad,
            COALESCE(SUM(epc.monto_entrega), 0) AS total_egresos
        FROM app_dat_entregas_parciales_caja epc
        WHERE epc.id_turno = f.id
    ) eg ON true

    -- Quien cerro el turno, resuelto desde trabajadores (no se toca auth.users).
    LEFT JOIN LATERAL (
        SELECT NULLIF(BTRIM(COALESCE(t2.nombres, '') || ' ' || COALESCE(t2.apellidos, '')), '')::text AS nombre_completo
        FROM app_dat_trabajadores t2
        WHERE f.cerrado_por IS NOT NULL
          AND t2.uuid = f.cerrado_por
          AND t2.id_tienda = p_id_tienda
        LIMIT 1
    ) cerr ON true

    ORDER BY f.fecha_apertura DESC, f.id DESC;
END;
$function$;

COMMENT ON FUNCTION public.fn_listar_turnos_admin IS
'Listado auditable y paginado de turnos de caja por tienda. Filtra por TPV, vendedor, estado, rango de fechas, discrepancias y texto libre. Devuelve KPIs de ventas, desglose de cobros por medio de pago, egresos parciales, conciliacion de efectivo (registrada y recalculada) y observaciones de cierre, resolviendo todo en un unico viaje al servidor (paginar-luego-agregar con LEFT JOIN LATERAL, sin N+1).';

GRANT EXECUTE ON FUNCTION public.fn_listar_turnos_admin(
    bigint, bigint, bigint, smallint, timestamptz, timestamptz, boolean, text, integer, integer
) TO authenticated;

-- Indice recomendado: los egresos por turno hoy caen en Seq Scan sobre
-- app_dat_entregas_parciales_caja (1.9k filas, ~0.2 ms por turno). Con el
-- indice el LATERAL de egresos pasa a index scan.
CREATE INDEX IF NOT EXISTS idx_entregas_parciales_turno
    ON public.app_dat_entregas_parciales_caja USING btree (id_turno);

-- =====================================================================
-- Verificacion rapida (ajustar id_tienda):
--   SELECT turno_id, tpv_denominacion, vendedor_nombre, conciliacion_estado,
--          efectivo_esperado_calculado, efectivo_real, diferencia_calculada,
--          ventas_totales, total_efectivo, total_egresos,
--          obs_faltantes_cant, obs_excesos_cant, total_registros
--   FROM fn_listar_turnos_admin(49, NULL, NULL, NULL, NULL, NULL, false, NULL, 20, 1);
-- =====================================================================
