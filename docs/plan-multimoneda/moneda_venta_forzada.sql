-- ============================================================================
-- MONEDA DE VENTA FORZADA POR LA TIENDA
--
--   1. Dos columnas nuevas en `app_dat_configuracion_tienda`.
--   2. Un trigger que impide dejar la configuración incoherente.
--
-- QUÉ RESUELVE: hasta ahora la moneda de venta era una preferencia **del
-- teléfono** (`MonedaVentaService`), y el vendedor podía cambiarla cuando
-- quisiera. Con esto, la tienda puede decir «aquí se vende solo en X»: el chip
-- del vendedor queda bloqueado y el checkout no ofrece otras divisas.
--
-- POR QUÉ UN TRIGGER Y NO UN CHECK:
--   Un `CHECK` no puede consultar otra tabla, y la regla de negocio es que la
--   moneda forzada tiene que ser una de las que la tienda **acepta**
--   (`app_dat_tienda_moneda`). Además hay que limpiar la moneda al apagar el
--   switch: si se queda guardada, la tienda bloquea sin querer el día que
--   alguien encienda el flag sin mirar.
--
-- Idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Columnas
-- ---------------------------------------------------------------------------
alter table public.app_dat_configuracion_tienda
  add column if not exists forzar_moneda_venta boolean not null default false;

alter table public.app_dat_configuracion_tienda
  add column if not exists moneda_venta_forzada character(3);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'app_dat_configuracion_tienda_moneda_forzada_fkey'
      and conrelid = 'public.app_dat_configuracion_tienda'::regclass
  ) then
    alter table public.app_dat_configuracion_tienda
      add constraint app_dat_configuracion_tienda_moneda_forzada_fkey
      foreign key (moneda_venta_forzada) references public.monedas(codigo);
  end if;
end $$;

comment on column public.app_dat_configuracion_tienda.forzar_moneda_venta is
  'Si esta activo, la tienda vende SOLO en `moneda_venta_forzada`: el vendedor no puede elegir otra divisa.';
comment on column public.app_dat_configuracion_tienda.moneda_venta_forzada is
  'Divisa forzada. NULL cuando el flag esta apagado.';

-- ---------------------------------------------------------------------------
-- 2. Coherencia: forzada != NULL y aceptada por la tienda; al apagar, se limpia
-- ---------------------------------------------------------------------------
create or replace function public.fn_validar_moneda_forzada()
returns trigger
language plpgsql
set search_path to 'public'
as $$
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
end $$;

drop trigger if exists trg_validar_moneda_forzada on public.app_dat_configuracion_tienda;
create trigger trg_validar_moneda_forzada
before insert or update on public.app_dat_configuracion_tienda
for each row execute function public.fn_validar_moneda_forzada();

-- ---------------------------------------------------------------------------
-- 3. Verificación
-- ---------------------------------------------------------------------------
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'app_dat_configuracion_tienda'
  and column_name in ('forzar_moneda_venta', 'moneda_venta_forzada')
order by column_name;

select count(*) as tiendas_con_forzado, count(*) filter (where moneda_venta_forzada is not null) as con_moneda
from public.app_dat_configuracion_tienda
where forzar_moneda_venta;