CREATE OR REPLACE FUNCTION public.fn_moneda_consolidacion(p_id_tienda bigint)
 RETURNS TABLE(moneda text, tasa_cup numeric, es_base boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
BEGIN
    PERFORM public.fn_config_tienda_exigir_lectura(p_id_tienda);
    RETURN QUERY

  with candidata as (
    select c.moneda_venta_forzada as moneda
    from public.app_dat_configuracion_tienda c
    where c.id_tienda = p_id_tienda and c.forzar_moneda_venta
      and c.moneda_venta_forzada is not null
      and exists (select 1 from public.app_dat_tienda_moneda m
                  where m.id_tienda = c.id_tienda and m.moneda = c.moneda_venta_forzada and m.activo)
    limit 1
  ),
  resuelta as (
    select cd.moneda,
           coalesce(public.fn_tasa_cambio('CUP', cd.moneda, p_id_tienda, now()),
                    1::numeric / nullif(public.fn_tasa_cambio(cd.moneda, 'CUP', p_id_tienda, now()), 0)) as tasa
    from candidata cd
  )
  select coalesce(r.moneda, 'CUP')::text, coalesce(r.tasa, 1)::numeric, (r.moneda is null)::boolean
  from (select moneda, tasa from resuelta where tasa is not null) r
  right join (select 1) uno on true;

END;
$function$

