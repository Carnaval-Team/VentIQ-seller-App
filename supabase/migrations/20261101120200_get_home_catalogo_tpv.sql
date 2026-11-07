-- ============================================================================
-- 20261101120200 · RPC del Home y del drawer del TPV
-- ============================================================================
--
-- Contiene 2 funciones:
--   1. get_home_catalogo_tpv(p_tienda_id, p_tpv_id)          -> una sola llamada
--      para pintar todo el Home (especiales + "Tienda") en el orden correcto.
--   2. get_subcategorias_by_categoria_tpv(p_id_categorias[], p_tienda_id, p_tpv_id)
--      -> subcategorías del grupo con total_productos REAL de la tienda/TPV.
--
-- Por qué `get_home_catalogo_tpv` COLAPSA POR NOMBRE (mitigación D7 aprobada)
--   Medido en la base viva: 1056 categorías en app_dat_categoria para solo 343
--   denominaciones distintas, y 31 pares (tienda, nombre) con más de una
--   categoría. Casos extremos: tienda 148 con 334 categorías y 11 nombres
--   ("Alimentos" x208), tienda 153 x61, tienda 160 x31.
--   Y no es solo basura: tiendas ACTIVAS y con suscripción pagando tienen
--   duplicados (173 "El Descuento Capiro", 174 "El Descuento Central",
--   177). Sin colapsar, el Home mostraría la misma tarjeta 2-6 veces.
--   El colapso es NO destructivo: no toca datos, solo agrupa al leer.
--
--   Devuelve `miembros` y `grupo_ids` para que el drawer pueda operar sobre
--   TODO el grupo y no solo sobre la categoría canónica.
--
--   Canónico = min(id) del grupo. Desempate determinista y explicable.
--
-- Por qué NO se replica el filtro de existencias del almacén del TPV
--   `get_categorias_by_tienda_tpv2` exige stock > 0 en el almacén del TPV, así
--   que una categoría desaparece del Home cuando se agota. El Home nuevo debe
--   seguir enseñando la categoría (el chip de stock se pinta en el producto).
--   Si se quiere paridad exacta con los contadores de ProductsScreen hay que
--   añadir el EXISTS de app_dat_inventario_productos — medir con EXPLAIN antes.
-- ============================================================================

-- Sin BEGIN/COMMIT explícito (convención del repo: el runner ya envuelve el archivo
-- en una transacción, y un BEGIN anidado avisa y puede confirmar la de fuera).

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Home: todas las categorías del TPV, colapsadas por nombre
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
  primera_categoria        record;
begin
  -- check_user_has_access_to_tienda resuelve tablas sin calificar y con
  -- `search_path = ''` fallaba con 42P01. Hay que restaurarlo antes de la
  -- guarda (mismo motivo y mismo patrón que get_productos_..._v3).
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
  'Home del TPV: categorías de la tienda colapsadas por denominación (mitiga la duplicación del nomenclador), con especial/orden_home/total_productos/total_subcategorias y grupo_ids para operar sobre todo el grupo.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Drawer: subcategorías del grupo, con conteo real de la tienda
-- ─────────────────────────────────────────────────────────────────────────────
-- La RPC existente `get_subcategorias_by_categoria` NO filtra por tienda ni por
-- vendibilidad, así que sus `total_productos` salen inflados. Esta los cuenta
-- bien y, además, acepta VARIAS categorías (el grupo completo del colapso) en
-- una sola llamada -> el drawer no tiene que hacer fan-out.
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
begin
  perform set_config('search_path', 'public, pg_catalog', false);
  perform public.check_user_has_access_to_tienda(p_tienda_id);

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
   group by s.id, s.denominacion, s.sku_codigo
  having count(distinct p.id) > 0
   order by s.denominacion asc;
end;
$function$;

grant execute on function public.get_subcategorias_by_categoria_tpv(bigint[], bigint, bigint)
  to authenticated;

comment on function public.get_subcategorias_by_categoria_tpv(bigint[], bigint, bigint) is
  'Subcategorías de una o varias categorías con total_productos real de la tienda (solo vendibles). Acepta el grupo completo del colapso del Home.';

-- ============================================================================
-- Notas de rendimiento
--   * El colapso usa `group by c.denominacion` sobre un join ya existente: no
--     añade escaneos, solo agrupa. Medir con EXPLAIN (ANALYZE, BUFFERS) en una
--     tienda grande (173/174) antes de dar la fase por cerrada.
--   * `count(distinct p.id)` es lo más caro del plan. Si sale mal, la
--     alternativa es un LEFT JOIN LATERAL con EXISTS por categoría.
--
-- Rollback
--   drop function if exists public.get_subcategorias_by_categoria_tpv(bigint[], bigint, bigint);
--   drop function if exists public.get_home_catalogo_tpv(bigint, bigint);
--   -- y volver a dejar el Home del TPV usando get_categorias_by_tienda_tpv
-- ============================================================================
