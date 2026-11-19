-- Solo lectura. Ejecutar despues del script 56 (R33).
SELECT
    to_regprocedure('public.fn_turno_alinear_fecha_apertura(bigint,timestamptz)') IS NOT NULL AS alinear_interna,
    NOT has_function_privilege('authenticated',
        'public.fn_turno_alinear_fecha_apertura(bigint,timestamptz)', 'EXECUTE') AS interna_cerrada,
    has_function_privilege('authenticated',
        'public.fn_alinear_apertura_turno_offline(bigint,timestamptz)', 'EXECUTE')
      AND NOT has_function_privilege('anon',
        'public.fn_alinear_apertura_turno_offline(bigint,timestamptz)', 'EXECUTE') AS rpc_solo_authenticated,
    (SELECT prosrc LIKE '%apertura_turno:%s:%s%'
            AND prosrc LIKE '%fn_turno_alinear_fecha_apertura(v_open%'
            AND prosrc LIKE '%fn_turno_alinear_fecha_apertura(v_new_id%'
     FROM pg_proc
     WHERE oid = to_regprocedure('public.fn_apertura_turno_offline(uuid,numeric,bigint,bigint,uuid,boolean,jsonb,text,timestamptz)')) AS apertura_r33,
    (SELECT prosrc LIKE '%LEAST(p_fecha_cierre, now())%'
     FROM pg_proc
     WHERE oid = to_regprocedure('public.fn_cerrar_turno_offline(uuid,bigint,numeric,uuid,jsonb,text,timestamptz)')) AS cierre_acotado,
    (SELECT prosrc LIKE '%LEAST(p_fecha_creacion, now())%'
     FROM pg_proc
     WHERE oid = to_regprocedure('public.fn_registrar_venta_offline_v4(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint,timestamptz,jsonb)')) AS venta_acotada,
    (SELECT count(*) FROM public.app_dat_operaciones
      WHERE created_at > now() + interval '1 minute') AS operaciones_futuras,
    (SELECT count(*) FROM public.app_dat_caja_turno
      WHERE fecha_cierre > now() + interval '1 minute') AS cierres_futuros;

-- Ventas offline de los ultimos 2 dias fuera de todo turno de su vendedor/TPV.
-- Debe dar 0 filas.
WITH ventas AS (
    SELECT o.id, o.created_at, o.uuid, ov.id_tpv
    FROM public.app_dat_operaciones o
    JOIN public.app_dat_operacion_venta ov ON ov.id_operacion = o.id
    JOIN public.app_dat_operacion_offline_idempotencia i ON i.id_operacion = o.id
    WHERE i.tipo LIKE 'venta%'
      AND o.created_at >= now() - interval '2 days'
)
SELECT v.id_tpv, count(*) AS ventas_huerfanas, min(v.created_at), max(v.created_at)
FROM ventas v
WHERE NOT EXISTS (
    SELECT 1
    FROM public.app_dat_caja_turno ct
    JOIN public.app_dat_vendedor vd ON vd.id = ct.id_vendedor
    WHERE ct.id_tpv = v.id_tpv AND vd.uuid = v.uuid
      AND v.created_at >= ct.fecha_apertura
      AND v.created_at <= COALESCE(ct.fecha_cierre, now())
)
GROUP BY v.id_tpv;
