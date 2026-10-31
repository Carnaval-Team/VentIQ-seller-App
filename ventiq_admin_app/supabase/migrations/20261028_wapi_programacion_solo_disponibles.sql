-- ============================================================================
--  WAPI — `solo_disponibles` por programación
--  Fecha: 2026-10-28
--
--  Contexto:
--    La difusión programada anuncia el catálogo completo, incluidos los
--    productos agotados (el caption sale con "🔴 Agotado"). Algunas tiendas
--    prefieren no anunciar lo que no tienen: esta migración añade el
--    interruptor por programación.
--
--    El envío lo aplica `wapi-send-products`: si recibe `solo_disponibles`,
--    resuelve el stock de todos los productos antes de armar el plan y filtra
--    los que tengan stock CONOCIDO <= 0. Un stock DESCONOCIDO (null: no se
--    pudo leer) NO se filtra — no se anuncia agotado lo que no se sabe—, misma
--    política que el semáforo del caption. `wapi-cron-dispatch` lee esta
--    columna y reenvía el flag (sólo cuando es true).
--
--  Aditiva e idempotente: se puede re-ejecutar sin efectos.
-- ============================================================================

ALTER TABLE public.app_wapi_programacion
  ADD COLUMN IF NOT EXISTS solo_disponibles boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.app_wapi_programacion.solo_disponibles IS
  'Si true, la difusión programada sólo anuncia productos con stock conocido > 0 '
  '(el envío lo filtra en wapi-send-products). Stock desconocido no se filtra.';

-- ----------------------------------------------------------------------------
-- Verificación manual (NO se ejecuta automáticamente):
--
--   SELECT column_name, data_type, is_nullable, column_default
--     FROM information_schema.columns
--    WHERE table_schema = 'public'
--      AND table_name   = 'app_wapi_programacion'
--      AND column_name  = 'solo_disponibles';
--
--   SELECT id, id_tienda, activa, solo_disponibles
--     FROM public.app_wapi_programacion
--    ORDER BY id;
-- ----------------------------------------------------------------------------