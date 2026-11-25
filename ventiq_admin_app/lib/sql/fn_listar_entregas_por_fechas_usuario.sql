-- =============================================================================
-- MAIN: egresos del turno, sin ventana de fecha cuando hay p_id_turno
-- =============================================================================
-- Con p_id_turno el egreso pertenece al turno por id_turno. Un egreso offline
-- se crea al sincronizar (fecha_entrega posterior al fecha_cierre del
-- dispositivo); filtrar por fechas lo ocultaba (turno 3599: egreso 20 USD a
-- las 11:21 con cierre 10:38).
--
-- Sin p_id_turno se conserva el filtro por fechas del turno y del rango.
-- Misma firma que ya está en main. Ejecutar en el SQL Editor de MAIN.
-- Preferir también: sql_updates/fix_listar_entregas_por_turno_sin_ventana_fecha.sql
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_listar_entregas_por_fechas_usuario(
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
    AND (
      (
        -- Por turno: pertenece por id_turno. La fecha de sync no decide.
        p_id_turno IS NOT NULL
        AND entrega.id_turno = p_id_turno
      )
      OR (
        p_id_turno IS NULL
        AND entrega.fecha_entrega >= turno.fecha_apertura
        AND entrega.fecha_entrega <= COALESCE(turno.fecha_cierre, NOW())
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
  'Egresos de caja del vendedor. Con p_id_turno solo ese turno (sin ventana de fecha). Sin él, solo egresos cuya fecha cae en el rango del turno y del período.';

NOTIFY pgrst, 'reload schema';
