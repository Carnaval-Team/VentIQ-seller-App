-- ============================================================================
-- SUBCATEGORÍA «GENERAL» OCULTA PARA LAS CATEGORÍAS ESPECIALES
--
-- QUÉ SE PIDE: al crear (o marcar) una categoría como **especial** —es decir,
-- tarjeta destacada del Home del TPV—, que exista automáticamente una
-- subcategoría «General». Debe crearse sola y **no mostrarse** en las listas.
--
-- POR QUÉ EN LA BASE Y NO EN DART: `especial` no vive en la categoría, vive en
-- la tabla por tienda `app_dat_categoria_tienda`, y se puede activar de dos
-- formas —al crearla (`CategoryService.create`) y con el switch del detalle—
-- desde el admin **y** desde el superadmin. Un trigger cubre los dos caminos y
-- los que vengan (importaciones, scripts), y no se puede olvidar.
--
-- DETALLE IMPORTANTE: `app_dat_subcategorias` **no tiene** columna de
-- visibilidad, así que la primera pieza es añadirla. Y no tiene índice único
-- por (idcategoria, denominacion), así que la idempotencia se resuelve con un
-- `not exists` explícito.
--
-- NO ES DESTRUCTIVO: si la categoría **ya** tiene una subcategoría llamada
-- «General» (hoy hay 12 así, creadas a mano), no se toca ni se oculta — puede
-- que el usuario la esté usando. Solo se crea cuando no hay ninguna.
--
-- Idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Visibilidad
-- ---------------------------------------------------------------------------
alter table public.app_dat_subcategorias
  add column if not exists oculta boolean not null default false;

comment on column public.app_dat_subcategorias.oculta is
  'Subcategoria creada por el sistema (p.ej. la «General» de una categoria especial). No se muestra en las listas de gestion; existe para que la categoria tenga siempre una subcategoria valida.';

comment on column public.app_dat_categoria.para_catalogo is
  'Marca la categoria para el catalogo publico.';

-- ---------------------------------------------------------------------------
-- 2. Al marcar una categoría como especial, garantizar su «General» oculta
-- ---------------------------------------------------------------------------
create or replace function public.fn_subcategoria_general_especial()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_denom constant text := 'General';
  v_sku   text;
begin
  -- Solo al pasar a especial. En un UPDATE que ya era especial no se repite.
  if not new.especial or new.id_categoria is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and coalesce(old.especial, false) then
    return new;
  end if;

  -- Ya tiene una «General» (visible o no): no se toca.
  if exists (
    select 1 from public.app_dat_subcategorias s
    where s.idcategoria = new.id_categoria
      and lower(trim(s.denominacion)) = lower(v_denom)
  ) then
    return new;
  end if;

  -- `sku_codigo` es NOT NULL: se deriva del sku de la categoría.
  select upper(coalesce(nullif(trim(sku_codigo), ''), 'CAT' || id)) || '-GEN'
  into v_sku
  from public.app_dat_categoria
  where id = new.id_categoria;

  v_sku := coalesce(nullif(trim(v_sku), ''), 'CAT' || new.id_categoria || '-GEN');

  -- No hay índice único, pero repetir sku sería feo: se desambigua.
  if exists (select 1 from public.app_dat_subcategorias where sku_codigo = v_sku) then
    v_sku := v_sku || '-' || new.id_categoria;
  end if;

  insert into public.app_dat_subcategorias (idcategoria, denominacion, sku_codigo, oculta)
  values (new.id_categoria, v_denom, v_sku, true);

  return new;
end $$;

drop trigger if exists trg_subcategoria_general_especial on public.app_dat_categoria_tienda;
create trigger trg_subcategoria_general_especial
after insert or update of especial on public.app_dat_categoria_tienda
for each row execute function public.fn_subcategoria_general_especial();

-- ---------------------------------------------------------------------------
-- 3. Backfill: las categorías que YA son especiales y no tienen «General»
-- ---------------------------------------------------------------------------
insert into public.app_dat_subcategorias (idcategoria, denominacion, sku_codigo, oculta)
select distinct
       ct.id_categoria,
       'General',
       upper(coalesce(nullif(trim(c.sku_codigo), ''), 'CAT' || c.id)) || '-GEN',
       true
from public.app_dat_categoria_tienda ct
join public.app_dat_categoria c on c.id = ct.id_categoria
where ct.especial
  and not exists (
    select 1 from public.app_dat_subcategorias s
    where s.idcategoria = ct.id_categoria
      and lower(trim(s.denominacion)) = 'general'
  )
  and not exists (
    select 1 from public.app_dat_subcategorias s2
    where s2.sku_codigo = upper(coalesce(nullif(trim(c.sku_codigo), ''), 'CAT' || c.id)) || '-GEN'
  );

-- ---------------------------------------------------------------------------
-- 4. Verificación
-- ---------------------------------------------------------------------------
select count(*) as categorias_especiales,
       count(*) filter (where exists (
         select 1 from public.app_dat_subcategorias s
         where s.idcategoria = ct.id_categoria
           and lower(trim(s.denominacion)) = 'general')) as con_general
from public.app_dat_categoria_tienda ct
where ct.especial;

select count(*) as generales_ocultas
from public.app_dat_subcategorias
where lower(trim(denominacion)) = 'general' and oculta;

select count(*) as generales_visibles_respetadas
from public.app_dat_subcategorias
where lower(trim(denominacion)) = 'general' and not oculta;