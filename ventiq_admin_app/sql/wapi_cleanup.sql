-- ============================================================================
--  WAPI — Mantenimiento: reporte de backlog + purga del historial
--  Fecha: 2026-10-17
--
--  QUÉ HACE
--    1. `fn_wapi_backlog_report()`      → conteos de la bitácora WAPI y de las
--                                          "tareas pendientes" (lo que la app
--                                          pinta como tanda *interrumpida*).
--    2. `fn_wapi_purge_envio_log(...)`  → borra filas de `app_wapi_envio_log`
--                                          server-side, en lotes, sin abrir una
--                                          transacción gigante. Sirve para
--                                          llamarlo desde el SQL Editor, desde
--                                          un job de pg_cron (retención), o
--                                          desde `scripts/wapi_cleanup.mjs`.
--    3. `fn_wapi_purge_infra_logs(...)` → limpia `net._http_response` (pg_net) y
--                                          `cron.job_run_details`, que también
--                                          crecen sin techo y ensucian los
--                                          diagnósticos del cron WAPI.
--
--  POR QUÉ
--    La difusión encadena chunks y, cuando el worker muere a mitad (techo de
--    ~400s de las Edge Functions) o cuando la sesión OpenWA se cae, deja filas
--    `pendiente`. La UI agrupa por `created_at` y, si hay `pendiente` con más de
--    10 min sin actividad, muestra la tanda como "interrumpida" con botón
--    *Reanudar*. Con el tiempo se acumulan cientos de esas tandas fantasma:
--    ruido en el historial y una tabla que sólo crece.
--
--  IMPORTANTE
--    · `fn_wapi_purge_envio_log` con `p_estado => NULL` borra TODA la bitácora.
--      `p_dry_run => true` sólo cuenta. Empieza siempre por el dry-run.
--    · Estas funciones son SECURITY DEFINER y se conceden SÓLO a service_role:
--      no las expongas a `authenticated`/`anon`.
--    · El job de retención de pg_cron va al final, COMENTADO. Descomentar
--      requiere decisión explícita: borra historia de forma automática.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Reporte de backlog (sólo lectura)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_wapi_backlog_report(
  p_id_tienda bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH base AS (
    SELECT *
      FROM public.app_wapi_envio_log
     WHERE p_id_tienda IS NULL OR id_tienda = p_id_tienda
  )
  SELECT jsonb_build_object(
    'total',     (SELECT count(*) FROM base),
    'pendiente', (SELECT count(*) FROM base WHERE estado = 'pendiente'),
    'fallido',   (SELECT count(*) FROM base WHERE estado = 'fallido'),
    'enviado',   (SELECT count(*) FROM base WHERE estado = 'enviado'),
    'mas_antiguo', (SELECT min(created_at) FROM base),
    'mas_reciente',(SELECT max(created_at) FROM base),
    'peso',      pg_size_pretty(pg_total_relation_size('public.app_wapi_envio_log')),
    -- Tandas que la app mostrará como "interrumpida": una fila `pendiente`
    -- cuya tanda lleva >10 min sin actividad (mismo umbral que
    -- WapiEnvioTanda._umbralInactividad en Flutter).
    'tandas_interrumpidas', (
      SELECT count(*) FROM (
        SELECT id_tienda, id_sesion, id_programacion, tipo_envio,
               date_trunc('hour', created_at) AS hora
          FROM base
         WHERE estado = 'pendiente'
           AND created_at < now() - interval '10 minutes'
         GROUP BY 1,2,3,4,5
      ) t
    ),
    'pendientes_por_tienda', COALESCE((
      SELECT jsonb_agg(x ORDER BY x->>'n' DESC)
        FROM (
          SELECT jsonb_build_object(
                   'id_tienda', id_tienda,
                   'id_sesion', id_sesion,
                   'tipo_envio', tipo_envio,
                   'n', count(*),
                   'desde', min(created_at),
                   'hasta', max(created_at)
                 ) AS x
            FROM base
           WHERE estado = 'pendiente'
           GROUP BY id_tienda, id_sesion, tipo_envio
        ) q
    ), '[]'::jsonb),
    'sesiones', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id', s.id, 'id_tienda', s.id_tienda, 'nombre', s.nombre,
               'status', s.status,
               'last_status_at', s.last_status_at,
               'minutos_sin_status', round(extract(epoch FROM (now() - s.last_status_at)) / 60),
               'tiene_qr_guardado', s.last_qr_image IS NOT NULL
             ) ORDER BY s.id)
        FROM public.app_wapi_sesion s
       WHERE p_id_tienda IS NULL OR s.id_tienda = p_id_tienda
    ), '[]'::jsonb),
    'infra', jsonb_build_object(
      'pg_net_respuestas',  (SELECT count(*) FROM net._http_response),
      'pg_net_mas_antigua', (SELECT min(created) FROM net._http_response),
      'cron_runs',          (SELECT count(*) FROM cron.job_run_details)
    )
  );
$$;

COMMENT ON FUNCTION public.fn_wapi_backlog_report(bigint) IS
  'Conteos de la bitácora WAPI, tandas interrumpidas, estado de sesiones y backlog de pg_net/cron.';

-- ---------------------------------------------------------------------------
-- 2. Purga de app_wapi_envio_log (en lotes)
--    p_estado: 'pendiente' | 'fallido' | 'enviado' | NULL (todas)
--    p_older_than_days: NULL = sin corte de antigüedad
--    p_dry_run: true = sólo cuenta
--    p_max_lotes: tope de seguridad para no bloquear el SQL Editor
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_wapi_purge_envio_log(
  p_estado           text    DEFAULT 'pendiente',
  p_id_tienda        bigint  DEFAULT NULL,
  p_older_than_days  int     DEFAULT NULL,
  p_batch            int     DEFAULT 5000,
  p_max_lotes        int     DEFAULT 200,
  p_dry_run          boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_borrados_total bigint := 0;
  v_borrados_lote  bigint;
  v_lote           int := 0;
  v_corte          timestamptz;
BEGIN
  IF p_estado IS NOT NULL AND p_estado NOT IN ('pendiente','fallido','enviado') THEN
    RAISE EXCEPTION 'p_estado inválido: % (usa pendiente|fallido|enviado|NULL)', p_estado;
  END IF;
  IF p_batch < 1 THEN
    RAISE EXCEPTION 'p_batch debe ser >= 1';
  END IF;

  v_corte := CASE
    WHEN p_older_than_days IS NULL THEN NULL
    ELSE now() - make_interval(days => p_older_than_days)
  END;

  IF p_dry_run THEN
    SELECT count(*) INTO v_borrados_total
      FROM public.app_wapi_envio_log
     WHERE (p_estado IS NULL OR estado = p_estado)
       AND (p_id_tienda IS NULL OR id_tienda = p_id_tienda)
       AND (v_corte IS NULL OR created_at < v_corte);
    RETURN jsonb_build_object(
      'dry_run', true, 'fila_a_borrar', v_borrados_total,
      'estado', p_estado, 'id_tienda', p_id_tienda,
      'corte', v_corte, 'batch', p_batch
    );
  END IF;

  -- Se borra por ctid en lotes: no hace falta `DELETE ... LIMIT` y no se
  -- construye una lista de ids en memoria (que con cientos de miles de filas
  -- es lo que hace fallar al SQL Editor).
  LOOP
    v_lote := v_lote + 1;
    EXIT WHEN v_lote > p_max_lotes;

    WITH objetivo AS (
      SELECT ctid
        FROM public.app_wapi_envio_log
       WHERE (p_estado IS NULL OR estado = p_estado)
         AND (p_id_tienda IS NULL OR id_tienda = p_id_tienda)
         AND (v_corte IS NULL OR created_at < v_corte)
       LIMIT p_batch
    )
    DELETE FROM public.app_wapi_envio_log l
     USING objetivo o
     WHERE l.ctid = o.ctid;

    GET DIAGNOSTICS v_borrados_lote = ROW_COUNT;
    v_borrados_total := v_borrados_total + v_borrados_lote;
    EXIT WHEN v_borrados_lote = 0;
  END LOOP;

  RETURN jsonb_build_object(
    'dry_run', false,
    'borrados', v_borrados_total,
    'lotes', v_lote - 1,
    'estado', p_estado,
    'id_tienda', p_id_tienda,
    'corte', v_corte,
    'tope_lotes_alcanzado', (v_lote > p_max_lotes)
  );
END $$;

COMMENT ON FUNCTION public.fn_wapi_purge_envio_log(text, bigint, int, int, int, boolean) IS
  'Borra (o cuenta si p_dry_run) filas de app_wapi_envio_log en lotes. p_estado NULL = toda la tabla.';

-- ---------------------------------------------------------------------------
-- 3. Purga de logs de infraestructura (pg_net + cron)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_wapi_purge_infra_logs(
  p_keep_days int     DEFAULT 7,
  p_dry_run   boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, net, cron
AS $$
DECLARE
  v_corte      timestamptz := now() - make_interval(days => p_keep_days);
  v_net        bigint := 0;
  v_net_old    bigint := 0;
  v_runs       bigint := 0;
  v_runs_old   bigint := 0;
BEGIN
  SELECT count(*) INTO v_net FROM net._http_response;
  SELECT count(*) INTO v_runs FROM cron.job_run_details;
  v_net_old  := (SELECT count(*) FROM net._http_response WHERE created < v_corte);
  -- `cron.job_run_details` no tiene columna created: se usa start_time.
  v_runs_old := (SELECT count(*) FROM cron.job_run_details WHERE start_time < v_corte);

  IF p_dry_run THEN
    RETURN jsonb_build_object(
      'dry_run', true, 'keep_days', p_keep_days, 'corte', v_corte,
      'pg_net_total', v_net,  'pg_net_a_borrar', v_net_old,
      'cron_runs_total', v_runs, 'cron_runs_a_borrar', v_runs_old
    );
  END IF;

  DELETE FROM net._http_response  WHERE created    < v_corte;
  DELETE FROM cron.job_run_details WHERE start_time < v_corte;

  RETURN jsonb_build_object(
    'dry_run', false, 'keep_days', p_keep_days, 'corte', v_corte,
    'pg_net_borrados', v_net_old,
    'cron_runs_borrados', v_runs_old,
    'nota', 'Si el tamaño no baja, ejecuta VACUUM (no FULL) sobre las tablas: '
            || 'VACUUM net._http_response; VACUUM cron.job_run_details;'
  );
END $$;

COMMENT ON FUNCTION public.fn_wapi_purge_infra_logs(int, boolean) IS
  'Purga net._http_response y cron.job_run_details más antiguos que p_keep_days.';

-- ---------------------------------------------------------------------------
-- 4. Permisos: sólo service_role. Estas funciones borran datos.
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.fn_wapi_backlog_report(bigint)                          FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_wapi_purge_envio_log(text, bigint, int, int, int, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_wapi_purge_infra_logs(int, boolean)                  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.fn_wapi_backlog_report(bigint)                          TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_wapi_purge_envio_log(text, bigint, int, int, int, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_wapi_purge_infra_logs(int, boolean)                  TO service_role;

-- ============================================================================
--  VERIFICACIÓN RÁPIDA (copiar/pegar)
-- ============================================================================
--   -- a) ¿Cuánto backlog hay?
--   SELECT jsonb_pretty(public.fn_wapi_backlog_report());
--
--   -- b) ¿Qué borraría la limpieza de tareas pendientes? (no borra nada)
--   SELECT public.fn_wapi_purge_envio_log(p_estado => 'pendiente', p_dry_run => true);
--
--   -- c) Borrar las tareas pendientes de verdad
--   SELECT public.fn_wapi_purge_envio_log(p_estado => 'pendiente', p_dry_run => false);
--
--   -- d) Vaciar toda la bitácora (¡destructivo!)
--   SELECT public.fn_wapi_purge_envio_log(p_estado => NULL, p_dry_run => false);
--
--   -- e) Retención de infraestructura: 7 días
--   SELECT public.fn_wapi_purge_infra_logs(p_keep_days => 7, p_dry_run => true);
--
-- ============================================================================
--  RETENCIÓN AUTOMÁTICA (opcional — DESCOMENTAR CON CONCIENCIA)
--  Guarda 30 días de bitácora y 7 de logs de infraestructura, una vez al día.
-- ============================================================================
-- DO $$
-- BEGIN
--   IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'wapi_retention') THEN
--     PERFORM cron.schedule(
--       'wapi_retention',
--       '30 4 * * *',
--       $cron$SELECT public.fn_wapi_purge_envio_log(
--                    p_estado => NULL, p_older_than_days => 30, p_dry_run => false);
--              SELECT public.fn_wapi_purge_infra_logs(p_keep_days => 7, p_dry_run => false);$cron$
--     );
--   END IF;
-- END $$;
--
--   -- Para desactivarlo:
--   SELECT cron.unschedule('wapi_retention');
--
-- ============================================================================
-- FIN — WAPI mantenimiento
-- ============================================================================