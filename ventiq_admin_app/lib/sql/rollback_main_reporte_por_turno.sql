-- =============================================================================
-- ROLLBACK en MAIN: revertir migracion_main_reporte_por_turno.sql
-- =============================================================================
-- Restaura las definiciones que vivían en main ANTES de la migración:
--   1. DROP v2 (depende de la v1).
--   2. DROP v1 por-turno.
--   3. CREATE v1 original: wrapper que delega en
--      fn_reporte_ventas_por_turno_vendedor (13 columnas, por vendedor).
--      NOTA: _vendedor no se tocó en la migración; sigue viva.
--   4. Recrea la _v2 con el bloque dinámico de fase5b: al no encontrar
--      `id_turno` arma el desglose con fn_desglose_monedas_usuario — la
--      definición exacta que main tenía antes.
-- =============================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.fn_reporte_ventas_por_turno_v2(uuid, date, date, bigint);
DROP FUNCTION IF EXISTS public.fn_reporte_ventas_por_turno(uuid, date, date, bigint);

-- ── v1 original de main: delega en _vendedor (por vendedor) ──────────────────
CREATE OR REPLACE FUNCTION public.fn_reporte_ventas_por_turno(
  p_uuid_usuario uuid DEFAULT NULL::uuid,
  p_fecha_desde date DEFAULT NULL::date,
  p_fecha_hasta date DEFAULT NULL::date,
  p_id_tienda bigint DEFAULT NULL::bigint
)
RETURNS TABLE(
  uuid_usuario uuid,
  nombres character varying,
  apellidos character varying,
  nombre_completo character varying,
  total_ventas bigint,
  total_productos_vendidos numeric,
  total_dinero_efectivo numeric,
  total_dinero_transferencia numeric,
  total_dinero_general numeric,
  total_importe_ventas numeric,
  productos_diferentes_vendidos bigint,
  primera_venta timestamp with time zone,
  ultima_venta timestamp with time zone
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT * FROM public.fn_reporte_ventas_por_turno_vendedor(
        p_uuid_usuario,
        p_fecha_desde,
        p_fecha_hasta,
        p_id_tienda
    );
$function$;

GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_por_turno(uuid, date, date, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_por_turno(uuid, date, date, bigint) TO service_role;

-- ── Recrear la _v2 (bloque dinámico de fase5b: sin id_turno usa
--       fn_desglose_monedas_usuario, como estaba antes en main) ───────────────
DO $$
DECLARE
  v_cols     text;
  v_es_turno boolean;
  v_expr     text;
BEGIN
  SELECT substring(pg_get_function_result(p.oid) FROM 'TABLE\((.*)\)$')
    INTO v_cols
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'fn_reporte_ventas_por_turno';

  IF v_cols IS NULL THEN
    RAISE EXCEPTION 'no pude leer las columnas de fn_reporte_ventas_por_turno';
  END IF;

  v_es_turno := position('id_turno' IN v_cols) > 0;

  v_expr := CASE WHEN v_es_turno
    THEN 'public.fn_desglose_monedas_turno(b.id_turno, false)'
    ELSE 'public.fn_desglose_monedas_usuario(b.uuid_usuario, p_fecha_desde, p_fecha_hasta, p_id_tienda)'
  END;

  EXECUTE format($f$
    CREATE OR REPLACE FUNCTION public.fn_reporte_ventas_por_turno_v2(
      p_uuid_usuario uuid DEFAULT NULL,
      p_fecha_desde  date DEFAULT NULL,
      p_fecha_hasta  date DEFAULT NULL,
      p_id_tienda    bigint DEFAULT NULL
    ) RETURNS TABLE(%s, desglose_monedas jsonb, total_base numeric)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path TO 'public'
    AS $body$
      WITH base AS (
        SELECT * FROM public.fn_reporte_ventas_por_turno(
          p_uuid_usuario, p_fecha_desde, p_fecha_hasta, p_id_tienda)
      )
      SELECT b.*, d.desglose_monedas, d.total_base
      FROM base b
      CROSS JOIN LATERAL %s d;
    $body$;
  $f$, v_cols, v_expr);

  RAISE NOTICE '_v2 recreada con criterio %',
    CASE WHEN v_es_turno THEN 'por turno' ELSE 'por vendedor' END;
END $$;

GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_por_turno_v2(uuid, date, date, bigint)
  TO authenticated, service_role;

COMMIT;

-- ── Verificación ─────────────────────────────────────────────────────────────
-- v1 debe volver a 13 columnas por vendedor (uuid_usuario primero, sin id_turno):
SELECT pg_get_function_result('public.fn_reporte_ventas_por_turno(uuid,date,date,bigint)'::regprocedure) AS v1_result;
SELECT pg_get_function_result('public.fn_reporte_ventas_por_turno_v2(uuid,date,date,bigint)'::regprocedure) AS v2_result;
