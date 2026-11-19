CREATE OR REPLACE FUNCTION public.fn_check_update(p_app_name character varying, p_version_actual character varying, p_build_actual integer)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_latest       public.app_versiones%rowtype;
  v_hay          boolean := false;
  v_build_actual integer := coalesce(p_build_actual, 0);
begin
  -- Última versión activa de la app. `id` como desempate: si dos filas
  -- comparten build, gana la insertada después.
  select v.* into v_latest
  from public.app_versiones v
  where v.app_name = p_app_name
    and v.activa = true
  order by v.build_number desc, v.id desc
  limit 1;

  if found and coalesce(v_latest.build_number, 0) > v_build_actual then
    v_hay := true;
  end if;

  return json_build_object(
    -- ── claves originales (mismo significado) ──
    'hay_actualizacion',  v_hay,
    'version_disponible', coalesce(v_latest.version_actual, ''),
    'obligatoria',        coalesce(v_latest.actualizacion_obligatoria, false)
                          or public.fn_version_menor(p_version_actual, v_latest.version_minima),
    'version_minima',     coalesce(v_latest.version_minima, ''),
    'fecha_lanzamiento',  coalesce(v_latest.fecha_lanzamiento, now()),
    -- ── claves nuevas (72/75: null o [] cuando no hay actualización) ──
    'id_version',         case when v_hay then v_latest.id else null end,
    'build_disponible',   case when v_hay then v_latest.build_number else null end,
    'titulo',             case when v_hay then v_latest.titulo else null end,
    'novedades',          case
                            when v_hay and jsonb_typeof(v_latest.novedades) = 'array'
                              then v_latest.novedades
                            else '[]'::jsonb
                          end,
    'url_descarga',       case when v_hay then v_latest.url_descarga else null end
  );
end;
$function$

