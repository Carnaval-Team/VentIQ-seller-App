-- RPC: Lista paginada de proveedores de Carnaval para eliminación
-- Devuelve: id, name, total_productos, ultimo_acceso
create or replace function fn_get_carnaval_providers_for_deletion(
  p_page integer default 0,
  p_page_size integer default 25
) returns table (
  id bigint,
  name text,
  total_productos integer,
  ultimo_acceso timestamptz
) language sql security definer as $$
  with base as (
    select
      prov.id,
      prov.name,
      prov.admin,
      coalesce(prod.count_prod, 0) as total_productos,
      au.last_sign_in_at as ultimo_acceso,
      row_number() over (order by prov.id) as rn
    from carnavalapp.proveedores prov
    left join lateral (
      select count(*)::int as count_prod
      from carnavalapp."Productos" p
      where p.proveedor = prov.id
    ) prod on true
    left join carnavalapp."Usuarios" u on u.id = prov.admin
    left join auth.users au on au.id = u.uuid
  )
  select id, name, total_productos, ultimo_acceso
  from base
  where rn > (p_page * p_page_size)
    and rn <= (p_page * p_page_size) + p_page_size
  order by id;
$$;

comment on function fn_get_carnaval_providers_for_deletion is
  'Lista paginada de proveedores (Carnaval) con total_productos y ultimo_acceso (auth.users.last_sign_in_at del admin).';

-- RPC: Lista paginada de tiendas de Inventtia para eliminación
-- Devuelve: id, name, total_productos, total_almacenes, ultimo_acceso_supervisor
create or replace function fn_get_inventtia_stores_for_deletion(
  p_page integer default 0,
  p_page_size integer default 25
) returns table (
  id bigint,
  name text,
  total_productos integer,
  total_almacenes integer,
  ultimo_acceso_supervisor timestamptz
) language sql security definer as $$
  with base as (
    select
      t.id,
      t.denominacion as name,
      coalesce(prod.count_prod, 0) as total_productos,
      coalesce(alm.count_alm, 0) as total_almacenes,
      sup.last_sign_in_at as ultimo_acceso_supervisor,
      row_number() over (order by t.id) as rn
    from public.app_dat_tienda t
    left join lateral (
      select count(*)::int as count_prod
      from public.app_dat_producto p
      where p.id_tienda = t.id
    ) prod on true
    left join lateral (
      select count(*)::int as count_alm
      from public.app_dat_almacen a
      where a.id_tienda = t.id
    ) alm on true
    left join lateral (
      select max(au.last_sign_in_at) as last_sign_in_at
      from public.app_dat_supervisor s
      join auth.users au on au.id = s.uuid
      where s.id_tienda = t.id
    ) sup on true
  )
  select id, name, total_productos, total_almacenes, ultimo_acceso_supervisor
  from base
  where rn > (p_page * p_page_size)
    and rn <= (p_page * p_page_size) + p_page_size
  order by id;
$$;

comment on function fn_get_inventtia_stores_for_deletion is
  'Lista paginada de tiendas con total_productos, total_almacenes y ultimo_acceso_supervisor (auth.users.last_sign_in_at del supervisor más reciente).';
