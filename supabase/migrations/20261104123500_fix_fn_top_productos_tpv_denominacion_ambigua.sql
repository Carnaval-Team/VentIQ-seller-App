-- ============================================================================
-- 20261104123500 · Fix 42702 en fn_top_productos_tpv: «denominacion» ambigua
-- ============================================================================
--
-- Síntoma
--   POST /rest/v1/rpc/fn_top_productos_tpv devolvía:
--     {
--       "code": "42702",
--       "message": "column reference \"denominacion\" is ambiguous",
--       "details": "It could refer to either a PL/pgSQL variable or a table column."
--     }
--
-- Causa
--   La función es `returns table (... denominacion character varying ...)`, así
--   que `denominacion` es un parámetro OUT y, por tanto, una variable PL/pgSQL
--   visible en todo el cuerpo. La subconsulta que resuelve el id del tipo de
--   operación 'venta' usaba la columna sin calificar:
--
--     select id from public.app_nom_tipo_operacion
--      where lower(denominacion) = 'venta' limit 1
--
--   `app_nom_tipo_operacion` también tiene una columna `denominacion`, así que
--   Postgres no puede decidir a cuál de las dos se refiere y aborta.
--
-- Arreglo
--   Calificar la referencia con el alias de la tabla (`nto.denominacion`).
--   NO se renombra el parámetro OUT: eso cambiaría el nombre de la clave JSON
--   que ya consume la app (`denominacion`) y rompería el mapeo del Home.
--
-- Alcance
--   Es la única función del esquema `public` con este patrón. El resto de
--   RPCs que usan `lower(denominacion)` lo hacen sobre tablas cuyo
--   `denominacion` no es además un parámetro OUT, así que no sufren 42702.
--   `fn_ofertas_tpv` (misma migración origen) ya califica todas sus
--   referencias (`p.denominacion`, `c.denominacion`, `s.denominacion`).
--
-- Notas
--   * Solo cambia esa referencia: el cuerpo es idéntico al de
--     20261103130000_fn_top_productos_y_ofertas_tpv.sql.
--   * Se re-afirman `grant execute` y el `comment` para que la migración sea
--     autosuficiente si se aplica aislada.
--   * Sin BEGIN/COMMIT (convención del repo).
-- ============================================================================

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
             -- nto.denominacion calificado a propósito: `denominacion` también
             -- es parámetro OUT de esta función y sin calificar Postgres lanza
             -- 42702 «column reference is ambiguous».
             select nto.id from public.app_nom_tipo_operacion nto
              where lower(nto.denominacion) = 'venta' limit 1)
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
