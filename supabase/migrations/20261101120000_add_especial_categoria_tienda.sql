-- ============================================================================
-- 20261101120000 · Categorías "especiales" POR TIENDA para el Home del TPV
-- ============================================================================
--
-- Contexto
--   El Home del TPV (ventiq_app) pasa a un diseño tipo "cliente": muestra las
--   categorías marcadas como especiales como tarjetas destacadas y agrupa TODAS
--   las no especiales bajo una categoría virtual "Tienda".
--
-- Por qué en `app_dat_categoria_tienda` y NO en `app_dat_categoria`
--   `app_dat_categoria` es un NOMENCLADOR GLOBAL compartido entre tiendas (no
--   tiene `id_tienda`). El vínculo multi-tenant vive en la puente
--   `app_dat_categoria_tienda`, que ya guarda config por tienda (`id_cocina`).
--   Poner el flag en la tabla global haría que marcar "Combustibles" como
--   especial en un servicentro la marcara también en cualquier otra tienda que
--   comparta esa categoría. Verificado en vivo: 98 categorías están compartidas
--   entre más de una tienda.
--
-- Alcance / seguridad
--   * Solo ADD COLUMN, 2 índices y COMMENT. No altera columnas existentes.
--   * No cambia el RETURNS TABLE de ninguna RPC en uso -> ninguna app se rompe.
--   * Las 3 apps que tocan estas tablas son admin, app y marketplace. El
--     marketplace hace .select() con lista explícita -> tolera columnas nuevas.
--   * RLS: ya existe policy ALL/public/true en esta tabla y `authenticated`
--     tiene UPDATE (verificado con has_table_privilege). No hay que crear
--     policies.
--
-- Verificado antes de escribir
--   * app_dat_categoria_tienda NO tenía UNIQUE (id_categoria, id_tienda).
--   * 0 pares duplicados en los 1154 vínculos -> el índice único es seguro.
-- ============================================================================

-- Se omite BEGIN/COMMIT a propósito: `supabase db push` / `migration up` ya envuelve
-- el archivo en una transacción, y un BEGIN anidado avisa y puede confirmar la de fuera.
-- Convención del repo (ver 20260927120000_...): sin transacción explícita.

-- 1. Flags por tienda ---------------------------------------------------------
alter table public.app_dat_categoria_tienda
  add column if not exists especial   boolean  not null default false,
  add column if not exists orden_home smallint not null default 0;

comment on column public.app_dat_categoria_tienda.especial is
  'Home del TPV: true = tarjeta destacada; las no especiales se agrupan bajo la categoría virtual "Tienda".';

comment on column public.app_dat_categoria_tienda.orden_home is
  'Orden de las tarjetas especiales en el Home del TPV (menor primero). 0 = desempata por denominación.';

-- 2. Índice parcial: el Home solo pregunta por las especiales de una tienda ----
create index if not exists idx_app_dat_categoria_tienda_especial
  on public.app_dat_categoria_tienda (id_tienda)
  where especial;

-- 3. Red de seguridad: un vínculo por (tienda, categoría) ---------------------
--    Evita que un import vuelva a duplicar el nomenclador de una tienda.
create unique index if not exists uq_app_dat_categoria_tienda_cat_tienda
  on public.app_dat_categoria_tienda (id_tienda, id_categoria);

-- ============================================================================
-- Rollback
--   drop index if exists public.uq_app_dat_categoria_tienda_cat_tienda;
--   drop index if exists public.idx_app_dat_categoria_tienda_especial;
--   alter table public.app_dat_categoria_tienda
--     drop column if exists especial,
--     drop column if exists orden_home;
-- ============================================================================
