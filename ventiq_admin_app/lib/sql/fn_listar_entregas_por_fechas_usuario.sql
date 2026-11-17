-- =============================================================================
-- MAIN: egresos del turno, no de cualquier turno que se cruce con el rango
-- =============================================================================
-- Problema (tienda 177, vendedor 748b2bc7…, 2026-11-17):
--   fn_listar_entregas_por_fechas_usuario devolvía los egresos del turno 3533
--   y también los del 3504 (14 de noviembre). El 3504 sigue abierto
--   (fecha_cierre NULL), así que COALESCE(fecha_cierre, NOW()) lo hacía
--   cruzar cualquier consulta posterior y la función devolvía TODOS sus
--   egresos, no solo los del rango.
--   El mismo día además hay turnos distintos (3524 y 3533). No se pueden
--   sumar juntos.
--
-- Además el parámetro era timestamp without time zone. El cliente manda
-- '2026-11-17T20:16:06Z' y ese cast tira la Z y se queda con las 20:16, que
-- luego se comparan como hora de Cuba. El rango real (07:57–15:16) se leía
-- como 12:57–20:16 y entraba el turno de las 16:07.
--
-- Contrato:
--   * p_id_turno informado → solo los egresos de ESE turno (aunque el egreso
--     sea posterior a la última venta). Los otros turnos del día no entran.
--   * p_id_turno NULL (widget o app vieja, total del período) → solo egresos
--     cuya fecha_entrega cae en el rango. Un turno abierto de otro día no
--     aporta sus egresos viejos.
--   Los tres primeros parámetros siguen teniendo default en el cuarto, así
--   las llamadas actuales (sin p_id_turno) no cambian de firma lógica.
--
-- Junto con este script hay que aplicar
--   ventiq_admin_app/lib/sql/migracion_main_reporte_por_turno.sql
-- para que el tab TPVs reciba una fila por turno (id_turno, apertura y
-- cierre). Sin eso la app no puede decir de qué turno son los egresos.
--
-- Ejecutar en el SQL Editor de Supabase del proyecto MAIN.
-- =============================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.fn_listar_entregas_por_fechas_usuario(
  timestamp without time zone,
  timestamp without time zone,
  uuid
);

CREATE FUNCTION public.fn_listar_entregas_por_fechas_usuario(
  p_fecha_inicio timestamptz,
  p_fecha_fin timestamptz,
  p_uuid_usuario uuid DEFAULT NULL,
  p_id_turno bigint DEFAULT NULL
)
RETURNS SETOF public.app_dat_entregas_parciales_caja
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT entrega.*
  FROM public.app_dat_entregas_parciales_caja entrega
  INNER JOIN public.app_dat_caja_turno turno
    ON turno.id = entrega.id_turno
  INNER JOIN public.app_dat_vendedor vendedor
    ON vendedor.id = turno.id_vendedor
  WHERE (p_uuid_usuario IS NULL OR vendedor.uuid = p_uuid_usuario)
    AND entrega.fecha_entrega >= turno.fecha_apertura
    AND entrega.fecha_entrega <= COALESCE(turno.fecha_cierre, NOW())
    AND (
      (
        p_id_turno IS NOT NULL
        AND entrega.id_turno = p_id_turno
      )
      OR (
        p_id_turno IS NULL
        AND entrega.fecha_entrega >= p_fecha_inicio
        AND entrega.fecha_entrega <= p_fecha_fin
      )
    )
  ORDER BY entrega.fecha_entrega DESC, entrega.id DESC;
$function$;

REVOKE ALL ON FUNCTION public.fn_listar_entregas_por_fechas_usuario(
  timestamptz, timestamptz, uuid, bigint
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_listar_entregas_por_fechas_usuario(
  timestamptz, timestamptz, uuid, bigint
) TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.fn_listar_entregas_por_fechas_usuario(
  timestamptz, timestamptz, uuid, bigint
) IS
  'Egresos de caja del vendedor. Con p_id_turno devuelve solo ese turno. Sin él, solo los egresos cuya fecha cae en el rango: no arrastra un turno abierto de otro día ni mezcla turnos del mismo día.';

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ── Verificación (no forma parte de la transacción) ─────────────────────────
-- Turno 3533: solo sus tres egresos del 17, no los del 3504 (día 14).
-- SELECT id, id_turno, monto_entrega, fecha_entrega
--   FROM public.fn_listar_entregas_por_fechas_usuario(
--     '2026-11-17T12:57:27.272564Z',
--     '2026-11-17T20:16:06.188390Z',
--     '748b2bc7-dadb-4c76-b327-251c047657fe',
--     3533);
--
-- Mismo rango sin turno: no debe salir el 3504 (egresos del 14) ni el 3533
-- (16:08, después de las 15:16). El 3533 se pide con su id, arriba.
-- SELECT id, id_turno, fecha_entrega
--   FROM public.fn_listar_entregas_por_fechas_usuario(
--     '2026-11-17T12:57:27.272564Z',
--     '2026-11-17T20:16:06.188390Z',
--     '748b2bc7-dadb-4c76-b327-251c047657fe',
--     NULL);
