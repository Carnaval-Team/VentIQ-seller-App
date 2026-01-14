-- Configuración y RPCs para gestión de precios por tienda (global y por producto)
-- Incluye sincronización con carnavalapp usando porcentajes configurables.

--------------------------------------------------------------------------------
-- 1) Tabla de configuración de precios por tienda (defaults incluidos)
--------------------------------------------------------------------------------
create table if not exists public.app_dat_precio_general_tienda (
  id bigserial primary key,
  id_tienda bigint not null references app_dat_tienda(id),
  precio_regular numeric(10,4) default 0,
  precio_venta_carnaval numeric(10,4) default 5.3,
  precio_venta_carnaval_transferencia numeric(10,4) default 11.1,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique(id_tienda)
);

--------------------------------------------------------------------------------
-- 2) RPC: Obtener productos con su último precio (evita N+1)
--------------------------------------------------------------------------------
create or replace function public.rpc_get_products_last_price(p_store_id bigint)
returns table (
  id_producto bigint,
  denominacion text,
  sku text,
  id_vendedor_app bigint,
  precio_venta_cup numeric,
  created_at timestamptz
) language plpgsql as $$
begin
  return query
  select p.id,
         p.denominacion,
         p.sku,
         p.id_vendedor_app,
         pv.precio_venta_cup,
         pv.created_at
  from app_dat_producto p
  left join lateral (
    select precio_venta_cup, created_at
    from app_dat_precio_venta
    where id_producto = p.id
    order by created_at desc
    limit 1
  ) pv on true
  where p.id_tienda = p_store_id;
end;
$$;

--------------------------------------------------------------------------------
-- 3) RPC: Cambio de precio global (acepta porcentajes negativos)
--    Aplica a todos los productos de la tienda y sincroniza carnavalapp.
--------------------------------------------------------------------------------
create or replace function public.rpc_apply_global_price_change(
  p_store_id bigint,
  p_precio_regular numeric,
  p_precio_carnaval numeric,
  p_precio_carnaval_transferencia numeric
) returns void language plpgsql as $$
declare
  rec record;
  base_price numeric;
  new_price numeric;
begin
  -- Upsert de configuración global
  insert into app_dat_precio_general_tienda(
    id_tienda, precio_regular, precio_venta_carnaval, precio_venta_carnaval_transferencia
  )
  values (p_store_id, p_precio_regular, p_precio_carnaval, p_precio_carnaval_transferencia)
  on conflict (id_tienda) do update
    set precio_regular = excluded.precio_regular,
        precio_venta_carnaval = excluded.precio_venta_carnaval,
        precio_venta_carnaval_transferencia = excluded.precio_venta_carnaval_transferencia,
        updated_at = now();

  -- Recorrer productos de la tienda
  for rec in
    select p.id, p.id_vendedor_app
    from app_dat_producto p
    where p.id_tienda = p_store_id
  loop
    -- Tomar último precio o el base
    select coalesce(pv.precio_venta_cup, 0) into base_price
    from app_dat_producto p
    left join lateral (
      select precio_venta_cup
      from app_dat_precio_venta
      where id_producto = p.id
      order by created_at desc
      limit 1
    ) pv on true
    where p.id = rec.id;

    new_price := base_price + (base_price * p_precio_regular / 100);

    insert into app_dat_precio_venta (id_producto, precio_venta_cup, fecha_desde, created_at)
    values (rec.id, new_price, now(), now());

    -- Sincronizar carnavalapp si existe id_vendedor_app
    if rec.id_vendedor_app is not null then
      update carnavalapp."Productos"
      set precio_descuento = round(new_price * (1 + p_precio_carnaval / 100)),
          price = round(new_price * (1 + p_precio_carnaval_transferencia / 100)),
          updated_at = now()
      where id = rec.id_vendedor_app;
    end if;
  end loop;
end;
$$;

--------------------------------------------------------------------------------
-- 4) RPC: Cambio de precio para productos seleccionados (percent/fixed, acepta negativos)
--    Sincroniza carnavalapp cuando corresponda.
--------------------------------------------------------------------------------
create or replace function public.rpc_apply_selected_price_change(
  p_store_id bigint,
  p_product_ids int[],
  p_change_type text,          -- 'percent' o 'fixed'
  p_change_value numeric,
  p_precio_carnaval numeric,
  p_precio_carnaval_transferencia numeric
) returns void language plpgsql as $$
declare
  rec record;
  base_price numeric;
  new_price numeric;
begin
  if p_change_type not in ('percent','fixed') then
    raise exception 'p_change_type inválido';
  end if;

  for rec in
    select p.id, p.id_vendedor_app
    from app_dat_producto p
    where p.id_tienda = p_store_id
      and p.id = any(p_product_ids)
  loop
    -- Último precio o base
    select coalesce(pv.precio_venta_cup, 0) into base_price
    from app_dat_producto p
    left join lateral (
      select precio_venta_cup
      from app_dat_precio_venta
      where id_producto = p.id
      order by created_at desc
      limit 1
    ) pv on true
    where p.id = rec.id;

    if p_change_type = 'percent' then
      new_price := base_price + (base_price * p_change_value / 100);
    else
      new_price := base_price + p_change_value;
    end if;

    insert into app_dat_precio_venta (id_producto, precio_venta_cup, fecha_desde, created_at)
    values (rec.id, new_price, now(), now());

    if rec.id_vendedor_app is not null then
      update carnavalapp."Productos"
      set precio_descuento = round(new_price * (1 + p_precio_carnaval / 100)),
          price = round(new_price * (1 + p_precio_carnaval_transferencia / 100)),
          updated_at = now()
      where id = rec.id_vendedor_app;
    end if;
  end loop;
end;
$$;

--------------------------------------------------------------------------------
-- Permisos sugeridos (ajustar a tu política de seguridad)
--------------------------------------------------------------------------------
-- grant execute on function public.rpc_get_products_last_price(bigint) to <role>;
-- grant execute on function public.rpc_apply_global_price_change(bigint, numeric, numeric, numeric) to <role>;
-- grant execute on function public.rpc_apply_selected_price_change(bigint, int[], text, numeric, numeric, numeric) to <role>;
