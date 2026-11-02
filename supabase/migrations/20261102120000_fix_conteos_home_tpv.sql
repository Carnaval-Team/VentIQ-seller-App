-- ============================================================================
-- 20261102120000 · Los contadores del Home coinciden con lo que lista el drawer
-- ============================================================================
--
-- PROBLEMA (reportado desde el TPV, tienda 223):
--   La tarjeta «elaboracion» decía 6 productos y el listado enseñaba 4;
--   «Alimentos» decía 13 y el listado 4. El vendedor ve un número que no puede
--   cuadrar de ninguna manera.
--
-- CAUSA:
--   `get_home_catalogo_tpv` contaba productos vendibles de la tienda, pero
--   `get_productos_by_categoria_tpv_search_meta_v3` (la RPC que alimenta el
--   listado y el drawer) exige además que el producto tenga al menos una fila
--   de inventario en el **almacén del TPV** (`app_dat_inventario_productos` +
--   `app_dat_layout_almacen` con `la.id_almacen = app_dat_tpv.id_almacen`).
--   Un producto vendible que no está en ese almacén no aparece en el listado,
--   pero sí sumaba en la tarjeta.
--
-- DECISIÓN:
--   El contador del Home debe ser **exactamente** el número de filas que el
--   vendedor va a ver al abrir la categoría/subcategoría. Se añade el mismo
--   `EXISTS` de inventario por almacén del TPV a las dos RPC.
--
--   ⚠️ Esto corrige §5.3 del plan, donde se decidió NO filtrar por inventario
--   para que una categoría no desapareciera al agotarse. El matiz importa: el
--   `EXISTS` no exige stock > 0, solo que el producto exista en el almacén del
--   TPV (aunque sea con cantidad 0 = agotado). Un producto agotado sigue
--   apareciendo y su categoría sigue en el Home; lo que deja de contarse es lo
--   que esa caja no puede vender porque no lo tiene cargado. Sin esto, los
--   números no cuadran nunca.
--
-- Idempotente: CREATE OR REPLACE con la misma firma y mismo RETURNS TABLE.
-- No se toca ninguna RPC existente del TPV (`get_categorias_by_tienda_tpv`,
-- `get_productos_by_categoria_tpv_*` ni `sync_bundle`).
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Home: una sola llamada para pintar todas las tarjetas
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_home_catalogo_tpv(
  p_tienda_id bigint,
  p_tpv_id    bigint
)
returns table (
  id                  bigint,
  nombre              text,
  descripcion         text,
  imagen              text,
  especial            boolean,
  orden_home          smallint,
  total_productos     bigint,
  total_subcategorias bigint,
  miembros            integer,
  grupo_ids           bigint[]
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  tiene_suscripcion_activa boolean := false;
  v_id_almacen             bigint;
  primera_categoria        record;
begin
  -- check_user_has_access_to_tienda resuelve tablas sin calificar y con
  -- `search_path = ''` fallaba con 42P01. Hay que restaurarlo antes de la
  -- guarda (mismo patrón que get_productos_..._v3).
  perform set_config('search_path', 'public, pg_catalog', false);

  perform public.check_user_has_access_to_tienda(p_tienda_id);

  select exists(
    select 1
      from public.app_suscripciones
     where id_tienda = p_tienda_id
       and estado = 1
       and (fecha_fin is null or fecha_fin > now())
  ) into tiene_suscripcion_activa;

  -- Sin suscripción activa: fila de contacto, igual que get_categorias_by_tienda_tpv2.
  if not tiene_suscripcion_activa then
    select c.id, c.denominacion, c.descripcion, c.image
      into primera_categoria
      from public.app_dat_categoria c
      join public.app_dat_categoria_tienda ct on c.id = ct.id_categoria
     where ct.id_tienda = p_tienda_id
     order by c.id
     limit 1;

    if primera_categoria is null then
      primera_categoria.id           := 999999;
      primera_categoria.denominacion := 'Administración';
      primera_categoria.descripcion  := 'Contactar administración';
      primera_categoria.image        := '';
    end if;

    return query
    select primera_categoria.id::bigint,
           'CONTACTAR ADMIN'::text,
           'escribir a supportinventtia@gmail.com o via whatsapp al 53765120'::text,
           coalesce(primera_categoria.image, '')::text,
           false,
           0::smallint,
           1::bigint,
           0::bigint,
           1,
           array[primera_categoria.id]::bigint[];

    return;
  end if;

  -- Almacén del TPV: es el filtro que usa la RPC del listado. Sin él, los
  -- contadores no cuadran con lo que el vendedor ve al abrir la categoría.
  select t.id_almacen
    into v_id_almacen
    from public.app_dat_tpv t
   where t.id = p_tpv_id
     and t.id_tienda = p_tienda_id;

  if v_id_almacen is null then
    return;
  end if;

  return query
  select min(c.id)::bigint,
         c.denominacion::text,
         (array_agg(c.descripcion order by c.id)
            filter (where c.descripcion is not null and c.descripcion <> ''))[1]::text,
         (array_agg(c.image order by c.id)
            filter (where c.image is not null and c.image <> ''))[1]::text,
         bool_or(coalesce(ct.especial, false)),
         min(coalesce(ct.orden_home, 0))::smallint,
         count(distinct p.id)::bigint,
         count(distinct sc.id)::bigint,
         count(distinct c.id)::integer,
         array_agg(distinct c.id)::bigint[]
    from public.app_dat_categoria c
    join public.app_dat_categoria_tienda ct on ct.id_categoria = c.id
    left join public.app_dat_subcategorias sc on sc.idcategoria = c.id
    left join public.app_dat_productos_subcategorias ps on ps.id_sub_categoria = sc.id
    left join public.app_dat_producto p
           on p.id = ps.id_producto
          and p.id_tienda = p_tienda_id
          and p.es_vendible = true
   where ct.id_tienda = p_tienda_id
     and coalesce(c.visible_vendedor, true) = true
     -- Mismo filtro que get_productos_by_categoria_tpv_search_meta_v3:
     -- el producto tiene que estar en el almacén de ESTE TPV (aunque sea a 0).
     and exists (
       select 1
         from public.app_dat_inventario_productos ip
         join public.app_dat_layout_almacen la on la.id = ip.id_ubicacion
        where ip.id_producto = p.id
          and la.id_almacen = v_id_almacen
     )
   group by c.denominacion
  having count(distinct p.id) > 0
   order by bool_or(coalesce(ct.especial, false)) desc,
            min(coalesce(ct.orden_home, 0)) asc,
            c.denominacion asc;
end;
$function$;

grant execute on function public.get_home_catalogo_tpv(bigint, bigint)
  to authenticated;

comment on function public.get_home_catalogo_tpv(bigint, bigint) is
  'Home del TPV: categorías de la tienda colapsadas por denominación, con contadores EXACTOS a lo que lista el drawer (mismo filtro de almacén del TPV).';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Drawer: subcategorías del grupo, con el mismo conteo que el listado
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_subcategorias_by_categoria_tpv(
  p_id_categorias bigint[],
  p_tienda_id     bigint,
  p_tpv_id        bigint
)
returns table (
  id              bigint,
  denominacion    character varying,
  sku_codigo      character varying,
  total_productos bigint
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_id_almacen bigint;
begin
  perform set_config('search_path', 'public, pg_catalog', false);
  perform public.check_user_has_access_to_tienda(p_tienda_id);

  select t.id_almacen
    into v_id_almacen
    from public.app_dat_tpv t
   where t.id = p_tpv_id
     and t.id_tienda = p_tienda_id;

  if v_id_almacen is null then
    return;
  end if;

  return query
  select s.id,
         s.denominacion,
         s.sku_codigo,
         count(distinct p.id)::bigint as total_productos
    from public.app_dat_subcategorias s
    left join public.app_dat_productos_subcategorias ps on ps.id_sub_categoria = s.id
    left join public.app_dat_producto p
           on p.id = ps.id_producto
          and p.id_tienda = p_tienda_id
          and p.es_vendible = true
   where s.idcategoria = any(p_id_categorias)
     and exists (
       select 1
         from public.app_dat_inventario_productos ip
         join public.app_dat_layout_almacen la on la.id = ip.id_ubicacion
        where ip.id_producto = p.id
          and la.id_almacen = v_id_almacen
     )
   group by s.id, s.denominacion, s.sku_codigo
  having count(distinct p.id) > 0
   order by s.denominacion asc;
end;
$function$;

grant execute on function public.get_subcategorias_by_categoria_tpv(bigint[], bigint, bigint)
  to authenticated;

comment on function public.get_subcategorias_by_categoria_tpv(bigint[], bigint, bigint) is
  'Subcategorías de una o varias categorías con total_productos EXACTO al listado del TPV (mismo filtro de almacén).';

-- ============================================================================
-- Cómo comprobarlo (tienda 223, tpv 224 → almacén 331):
--   select c.denominacion,
--          count(distinct p.id) filter (where exists (
--            select 1 from public.app_dat_inventario_productos ip
--              join public.app_dat_layout_almacen la on la.id = ip.id_ubicacion
--             where ip.id_producto = p.id and la.id_almacen = 331)) as como_lista
--     from ...;
--   Debe coincidir con la tarjeta del Home para cada categoría.
--
-- Rollback
--   Volver a ejecutar la versión anterior de este archivo en
--   20261101120200_get_home_catalogo_tpv.sql (sin el EXISTS de almacén).
-- ============================================================================