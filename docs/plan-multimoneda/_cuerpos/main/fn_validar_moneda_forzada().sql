CREATE OR REPLACE FUNCTION public.fn_validar_moneda_forzada()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if new.forzar_moneda_venta then
    if new.moneda_venta_forzada is null then
      raise exception 'Si se fuerza la moneda de venta hay que indicar cual';
    end if;
    if not exists (
      select 1 from public.app_dat_tienda_moneda m
      where m.id_tienda = new.id_tienda
        and m.moneda = new.moneda_venta_forzada
        and m.activo
    ) then
      raise exception 'La tienda % no acepta la moneda %',
        new.id_tienda, new.moneda_venta_forzada;
    end if;
  else
    -- Apagar el interruptor limpia la divisa: nunca dejar una forzada huerfana.
    new.moneda_venta_forzada := null;
  end if;
  return new;
end $function$

