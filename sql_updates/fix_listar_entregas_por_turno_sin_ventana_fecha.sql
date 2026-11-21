-- fn_listar_entregas_por_fechas_usuario: con p_id_turno el egreso pertenece al
-- turno por su id_turno, sin ventana de fechas.
--
-- Defecto: la función exigía siempre apertura <= fecha_entrega <= fecha_cierre.
-- Un egreso hecho offline se crea al sincronizar (fecha_entrega = hora de
-- subida), posterior al fecha_cierre fijado por el dispositivo, y el admin lo
-- mostraba como 0 (turno 21: egreso 4 de 750 CUP). Sin p_id_turno se conserva el
-- filtro por fechas.
-- Aditivo: misma firma y mismo tipo de retorno. No toca tablas ni RLS.

DO $$
BEGIN
  IF to_regprocedure('public.fn_listar_entregas_por_fechas_usuario(timestamp with time zone,timestamp with time zone,uuid,bigint)') IS NULL THEN
    RAISE EXCEPTION 'Falta fn_listar_entregas_por_fechas_usuario(timestamptz,timestamptz,uuid,bigint)';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.fn_listar_entregas_por_fechas_usuario(p_fecha_inicio timestamp with time zone, p_fecha_fin timestamp with time zone, p_uuid_usuario uuid DEFAULT NULL::uuid, p_id_turno bigint DEFAULT NULL::bigint)
 RETURNS SETOF app_dat_entregas_parciales_caja
 LANGUAGE sql
 STABLE SECURITY DEFINER
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
        -- Por turno: pertenece al turno por su id_turno. Un egreso hecho offline
        -- se crea al sincronizar (fecha_entrega posterior al cierre del
        -- dispositivo), asi que la fecha no puede decidir.
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
