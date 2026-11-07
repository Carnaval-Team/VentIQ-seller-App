-- ============================================================================
-- 20261101120100 · get_categorias_by_tienda_complete_v2
-- ============================================================================
--
-- Para qué
--   Es la RPC que alimenta la pantalla de gestión de categorías del admin
--   (ventiq_admin_app). Necesita devolver `especial` y `orden_home` para que el
--   gerente vea y edite el estado del switch.
--
-- Por qué una función NUEVA y no CREATE OR REPLACE de la existente
--   Postgres no permite cambiar el RETURNS TABLE con CREATE OR REPLACE: habría
--   que DROP + CREATE, y durante esa ventana el admin desplegado se queda sin
--   RPC. Con `_v2` el despliegue es sin corte: se aplica esto, luego se cambia
--   el Dart, y la v1 se puede borrar más adelante en una migración aparte.
--
-- Cambios respecto de la v1
--   * + `especial`, + `orden_home` (AL FINAL, para que fromJson por nombre del
--     admin siga funcionando sin tocar el orden).
--   * ORDER BY por especial desc, orden_home asc, denominación asc (antes solo
--     denominación): así el listado del admin ya sale en el orden del Home.
--   * Se conserva SECURITY DEFINER y el bloque EXCEPTION de la v1.
-- ============================================================================

-- Sin BEGIN/COMMIT explícito (convención del repo: el runner ya envuelve el archivo
-- en una transacción, y un BEGIN anidado avisa y puede confirmar la de fuera).

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
  -- `check`/lecturas resuelven tablas: se fija el search_path explícitamente
  -- (mismo patrón que el resto de RPC del proyecto con search_path = '').
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
         coalesce(ct.especial, false) as especial,
         coalesce(ct.orden_home, 0)   as orden_home
  from public.app_dat_categoria c
  inner join public.app_dat_categoria_tienda ct on c.id = ct.id_categoria
  where ct.id_tienda = p_id_tienda
  order by coalesce(ct.especial, false) desc,
           coalesce(ct.orden_home, 0) asc,
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
  'Igual que get_categorias_by_tienda_complete pero con especial y orden_home, y ordenada como el Home del TPV. Sustituye a la v1, que se conserva por compatibilidad.';

-- ============================================================================
-- Después de desplegar y de adaptar ventiq_admin_app:
--
--   drop function if exists public.get_categorias_by_tienda_complete(bigint);
--
-- (No hacerlo en esta migración para no romper un admin que aún no se actualizó.)
-- ============================================================================
