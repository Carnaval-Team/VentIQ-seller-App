-- Trigger: sincroniza carnavalapp.configuraciones_admin.valor_usd
-- a partir de la tasa USD(2) -> CUP(1) de la tienda 177 en tasa_cambio_extraoficial.
--
-- Reglas:
--   - Solo actua si id_moneda_origen = 2, id_moneda_destino = 1, id_tienda = 177 y activo = true.
--   - usar_precio_toque = false -> valor_usd = valor_cambio - 30.
--   - usar_precio_toque = true  -> toma la tasa USD->CUP de tasas_conversion
--                                  y valor_usd = tasa - 30.
--   - configuraciones_admin tiene una sola fila (UPDATE sin WHERE).

create or replace function public.fn_sync_valor_usd_carnaval()
returns trigger
language plpgsql
as $$
declare
  v_tasa   numeric;
  v_valor  numeric;
begin
  -- Solo USD(2) -> CUP(1), tienda 177 y tasa activa
  if new.id_moneda_origen = 2
     and new.id_moneda_destino = 1
     and new.id_tienda = 177
     and new.activo = true then

    if new.usar_precio_toque = false then
      -- Usamos el valor_cambio de la fila
      v_valor := new.valor_cambio - 30;
    else
      -- Usamos la tasa oficial USD -> CUP de tasas_conversion
      select tc.tasa
        into v_tasa
        from public.tasas_conversion tc
       where tc.moneda_origen = 'USD'
         and tc.moneda_destino = 'CUP'
       limit 1;

      -- Si no hay tasa configurada, no tocamos la config
      if v_tasa is null then
        return new;
      end if;

      v_valor := v_tasa - 30;
    end if;

    -- configuraciones_admin tiene una sola fila
    update carnavalapp.configuraciones_admin
       set valor_usd = v_valor;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_sync_valor_usd_carnaval on public.tasa_cambio_extraoficial;

create trigger trg_sync_valor_usd_carnaval
after insert or update of valor_cambio, usar_precio_toque, activo
on public.tasa_cambio_extraoficial
for each row
execute function public.fn_sync_valor_usd_carnaval();
