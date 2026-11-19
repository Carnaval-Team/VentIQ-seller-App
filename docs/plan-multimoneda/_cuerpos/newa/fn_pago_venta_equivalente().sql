CREATE OR REPLACE FUNCTION public.fn_pago_venta_equivalente()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_moneda text; v_tasa numeric;
begin
  v_moneda := upper(trim(coalesce(new.moneda, 'CUP')));
  v_tasa := case when v_moneda = 'CUP' then 1
                 else coalesce(new.tasa_cambio, new.tasa_usd) end;
  if v_tasa is null or v_tasa <= 0 then
    return new;
  end if;
  new.monto_cup_equivalente := new.monto * v_tasa;
  if new.tasa_cambio is null then new.tasa_cambio := v_tasa; end if;
  if v_moneda = 'USD' and new.tasa_usd is null then new.tasa_usd := v_tasa; end if;
  return new;
end $function$

