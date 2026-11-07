-- ============================================================================
-- 20261103120000 · fix get_categorias_by_tienda_complete_v2 (smallint)
-- ============================================================================
--
-- Bug
--   `get_categorias_by_tienda_complete_v2(223)` falla en producción con
--   `P0001: structure of query does not match function result type`.
--
-- Causa (probada contra la base viva)
--   El `RETURNS TABLE` declara `orden_home smallint`, pero en el SELECT se
--   devuelve `coalesce(ct.orden_home, 0)`: como la columna es `smallint` y el
--   literal `0` es `integer`, Postgres resuelve el `coalesce` a **integer**
--   (`pg_typeof(coalesce(ct.orden_home, 0))` = integer). El `return query`
--   exige que la expresión case exactamente con el tipo declarado.
--
-- Fix
--   Castear el resultado a `smallint` en el SELECT (y en el ORDER BY, por
--   claridad). Es un `create or replace` del cuerpo: el RETURNS TABLE no cambia,
--   así que no hace falta DROP y no hay ventana sin RPC.
--
-- Nota
--   El Home del TPV **no** usa esta función: `get_home_catalogo_tpv` ya castea
--   con `min(coalesce(ct.orden_home, 0))::smallint`. Esto afecta al admin.
-- ============================================================================

create or replace function public.get_categorias_by_tienda_complete_v2(
  p_id_tienda bigint
)
returns table (
  id                          bigint,
  denominacion                character varying,
  descripcion                 character varying,
  sku_codigo                  text,
  image                       text,
  created_at                  timestamp with time zone,
  categoria_tienda_id         bigint,
  categoria_tienda_created_at timestamp with time zone,
  especial                    boolean,
  orden_home                  smallint
)
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform set_config('search_path', 'public, pg_catalog', false);

  return query
  select c.id,
         c.denominacion,
         c.descripcion,
         c.sku_codigo,
         c.image,
         c.created_at,
         ct.id         as categoria_tienda_id,
         ct.created_at as categoria_tienda_created_at,
         coalesce(ct.especial, false)        as especial,
         coalesce(ct.orden_home, 0)::smallint as orden_home
  from public.app_dat_categoria c
  inner join public.app_dat_categoria_tienda ct on c.id = ct.id_categoria
  where ct.id_tienda = p_id_tienda
  order by coalesce(ct.especial, false) desc,
           coalesce(ct.orden_home, 0)::smallint asc,
           c.denominacion asc;

exception
  when others then
    raise exception 'Error al obtener categorías para la tienda %: %',
      p_id_tienda, sqlerrm;
end;
$function$;

grant execute on function public.get_categorias_by_tienda_complete_v2(bigint)
  to authenticated;

comment on function public.get_categorias_by_tienda_complete_v2(bigint) is
  'Igual que get_categorias_by_tienda_complete pero con especial y orden_home (cast ::smallint), y ordenada como el Home del TPV.';
