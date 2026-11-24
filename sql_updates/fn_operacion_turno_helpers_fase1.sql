-- ============================================================================
-- Fase 1 (aditivo): helpers de pertenencia/completado de operación
-- ============================================================================
-- Extraído de C12/C13 SIN parchear las funciones de reporte existentes.
-- Los necesita fn_caja_disponible_para_egreso / egreso _m01 (C14).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_operacion_en_turno(
    p_id_turno bigint,
    p_id_operacion bigint,
    p_created_at timestamptz
) RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case
           when t.id_operacion_apertura is not null then
             p_id_operacion > t.id_operacion_apertura
             and case
                   when t.id_operacion_cierre is not null
                     then p_id_operacion < t.id_operacion_cierre
                   else p_id_operacion < coalesce((
                          select min(n.id_operacion_apertura)
                            from public.app_dat_caja_turno n
                           where n.id_tpv = t.id_tpv
                             and n.id_vendedor = t.id_vendedor
                             and n.id_operacion_apertura > t.id_operacion_apertura
                        ), 9223372036854775807)
                 end
           else p_created_at >= t.fecha_apertura
                and p_created_at <= coalesce(t.fecha_cierre, now())
         end
  from public.app_dat_caja_turno t
  where t.id = p_id_turno;
$function$;

REVOKE ALL ON FUNCTION public.fn_operacion_en_turno(bigint, bigint, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_operacion_en_turno(bigint, bigint, timestamptz) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_operacion_completada(p_id_operacion bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.app_dat_estado_operacion eo
    where eo.id_operacion = p_id_operacion
      and eo.estado = 2
      and eo.id = (select max(eo2.id) from public.app_dat_estado_operacion eo2
                   where eo2.id_operacion = p_id_operacion)
  );
$function$;

REVOKE ALL ON FUNCTION public.fn_operacion_completada(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_operacion_completada(bigint) TO authenticated, service_role;
