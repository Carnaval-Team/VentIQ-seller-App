-- ============================================================================
-- 20261103130000 · RPCs nuevas del Home: «Más vendidos» y «Ofertas»
-- ============================================================================
--
-- Contexto
--   El Home del TPV quiere dos rieles nuevos:
--    1. «Más vendidos»: ranking de la propia caja en los últimos N días.
--    2. «Ofertas»: productos con descuento vigente que ESTA caja puede vender.
--
--   Se apoyan en el camino de ventas ya usado por
--   `fn_productos_vendidos_por_turno_v2` (operaciones tipo 'venta' →
--   `app_dat_operacion_venta` → `app_dat_extraccion_productos`) y en el filtro
--   de inventario por almacén del TPV que usan las RPC del Home
--   (`app_dat_inventario_productos` + `app_dat_layout_almacen`).
--
--   `fn_get_productos_mas_vendidos` es del marketplace (ranking global sin
--   filtro de tienda), por eso NO se reutiliza aquí.
--
-- Notas
--   * Funciones NUEVAS: no se toca ningún `RETURNS TABLE` existente.
--   * `security definer` + `search_path` fijo, igual que el resto del Home.
--   * Sin BEGIN/COMMIT (convención del repo).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) fn_top_productos_tpv: lo más vendido de un TPV en una ventana de días.
-- ----------------------------------------------------------------------------
create or replace function public.fn_top_productos_tpv(
  p_id_tpv bigint,
  p_dias integer default 30,
  p_limit integer default 12
)
returns table (
  id_producto       bigint,
  denominacion      character varying,
  imagen            text,
  precio_venta      numeric,
  precio_descuento  numeric,
  unidades_vendidas numeric,
  operaciones       bigint,
  total_vendido     numeric
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_almacen bigint;
  v_desde   timestamp with time zone;
  v_limite  integer;
begin
  perform set_config('search_path', 'public, pg_catalog', false);
  perform public.check_user_has_access_to_any_tienda();

  select t.id_almacen into v_almacen
    from public.app_dat_tpv t
   where t.id = p_id_tpv;

  v_desde := now() - make_interval(days => greatest(coalesce(p_dias, 30), 1));
  v_limite := least(greatest(coalesce(p_limit, 12), 1), 50);

  return query
  with lineas as (
    select ep.id_producto,
           ep.cantidad,
           ep.importe,
           o.id as id_operacion
      from public.app_dat_operaciones o
      join public.app_dat_operacion_venta ov on ov.id_operacion = o.id
      join public.app_dat_extraccion_productos ep on ep.id_operacion = o.id
     where ov.id_tpv = p_id_tpv
       and o.id_tipo_operacion = (
             select id from public.app_nom_tipo_operacion
              where lower(denominacion) = 'venta' limit 1)
       and o.created_at >= v_desde
  ),
  agg as (
    select l.id_producto,
           sum(l.cantidad)                  as unidades,
           count(distinct l.id_operacion)   as operaciones,
           sum(l.importe)                   as total
      from lineas l
     group by l.id_producto
  )
  select a.id_producto,
         p.denominacion::varchar                                as denominacion,
         p.imagen                                                as imagen,
         pr.precio_venta_cup                                      as precio_venta,
         case
           when pr.precio_descuento is not null
            and pr.precio_descuento > 0
            and (pr.fecha_desde is null or pr.fecha_desde <= current_date)
            and (pr.fecha_hasta is null or pr.fecha_hasta >= current_date)
           then pr.precio_descuento
         end                                                     as precio_descuento,
         a.unidades                                              as unidades_vendidas,
         a.operaciones                                           as operaciones,
         a.total                                                 as total_vendido
    from agg a
    join public.app_dat_producto p on p.id = a.id_producto
    left join lateral (
      select pv.precio_venta_cup, pv.precio_descuento,
             pv.fecha_desde, pv.fecha_hasta
        from public.app_dat_precio_venta pv
       where pv.id_producto = a.id_producto
       order by pv.id desc
       limit 1
    ) pr on true
   where p.deleted_at is null
     and p.es_vendible
     -- Si la caja tiene almacén, el producto debe existir en él (mismo
     -- criterio que el listado y los contadores del Home).
     and (
       v_almacen is null
       or exists (
         select 1
           from public.app_dat_inventario_productos ip
           join public.app_dat_layout_almacen la on la.id = ip.id_ubicacion
          where ip.id_producto = a.id_producto
            and la.id_almacen = v_almacen
       )
     )
   order by a.total desc nulls last
   limit v_limite;
end;
$function$;

grant execute on function public.fn_top_productos_tpv(bigint, integer, integer)
  to authenticated;

comment on function public.fn_top_productos_tpv(bigint, integer, integer) is
  'Más vendidos de un TPV en los últimos p_dias (ventas propias, filtrado al almacén del TPV).';

-- ----------------------------------------------------------------------------
-- 2) fn_ofertas_tpv: productos con descuento vigente vendibles en ese TPV.
-- ----------------------------------------------------------------------------
create or replace function public.fn_ofertas_tpv(
  p_id_tpv bigint,
  p_limit integer default 12
)
returns table (
  id_producto        bigint,
  denominacion       character varying,
  imagen             text,
  precio_venta       numeric,
  precio_descuento   numeric,
  porcentaje         numeric,
  categoria_nombre   character varying,
  subcategoria_nombre character varying
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_almacen bigint;
  v_limite  integer;
begin
  perform set_config('search_path', 'public, pg_catalog', false);
  perform public.check_user_has_access_to_any_tienda();

  select t.id_almacen into v_almacen
    from public.app_dat_tpv t
   where t.id = p_id_tpv;

  v_limite := least(greatest(coalesce(p_limit, 12), 1), 50);

  return query
  select p.id                                                   as id_producto,
         p.denominacion::varchar                                as denominacion,
         p.imagen                                               as imagen,
         pr.precio_venta_cup                                     as precio_venta,
         pr.precio_descuento                                     as precio_descuento,
         round((1 - (pr.precio_descuento / nullif(pr.precio_venta_cup, 0))) * 100)::numeric
                                                                 as porcentaje,
         c.denominacion::varchar                                 as categoria_nombre,
         (select s.denominacion::varchar
            from public.app_dat_productos_subcategorias psc
            join public.app_dat_subcategorias s on s.id = psc.id_sub_categoria
           where psc.id_producto = p.id
           order by s.denominacion
           limit 1)                                              as subcategoria_nombre
    from public.app_dat_producto p
    join public.app_dat_precio_venta pr on pr.id = (
      select pv.id
        from public.app_dat_precio_venta pv
       where pv.id_producto = p.id
       order by pv.id desc
       limit 1)
    left join public.app_dat_categoria c on c.id = p.id_categoria
   where p.deleted_at is null
     and p.es_vendible
     and pr.precio_descuento is not null
     and pr.precio_descuento > 0
     and pr.precio_venta_cup is not null
     and pr.precio_descuento < pr.precio_venta_cup
     and (pr.fecha_desde is null or pr.fecha_desde <= current_date)
     and (pr.fecha_hasta is null or pr.fecha_hasta >= current_date)
     and (
       v_almacen is null
       or exists (
         select 1
           from public.app_dat_inventario_productos ip
           join public.app_dat_layout_almacen la on la.id = ip.id_ubicacion
          where ip.id_producto = p.id
            and la.id_almacen = v_almacen
       )
     )
   order by porcentaje desc nulls last, p.denominacion
   limit v_limite;
end;
$function$;

grant execute on function public.fn_ofertas_tpv(bigint, integer)
  to authenticated;

comment on function public.fn_ofertas_tpv(bigint, integer) is
  'Productos con descuento vigente (app_dat_precio_venta) vendibles en el almacén de un TPV.';