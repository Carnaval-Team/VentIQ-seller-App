create extension if not exists pg_cron with schema extensions;

create or replace function public.fn_expirar_suscripciones_catalogo()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  with expired as (
    update public.app_dat_suscripcion_catalogo s
    set vencido = true
    where (s.vencido is null or s.vencido = false)
      and s.id_tienda is not null
      and s.tiempo_suscripcion is not null
      and (now() - s.created_at) >= ((s.tiempo_suscripcion::text || ' days')::interval)
    returning s.id_tienda
  )
  update public.app_dat_tienda t
  set validada = false
  where t.id in (select distinct id_tienda from expired)
    and not exists (
      select 1
      from public.app_dat_suscripcion_catalogo s2
      where s2.id_tienda = t.id
        and (s2.vencido is null or s2.vencido = false)
    );

  update public.app_dat_tienda t
  set validada = false
  where t.validada = true
    and not exists (
      select 1
      from public.app_dat_suscripcion_catalogo s
      where s.id_tienda = t.id
        and (s.vencido is null or s.vencido = false)
    );
end;
$$;

select cron.schedule(
  'expire-catalog-subscriptions',
  '0 * * * *',
  $$select public.fn_expirar_suscripciones_catalogo();$$
);
