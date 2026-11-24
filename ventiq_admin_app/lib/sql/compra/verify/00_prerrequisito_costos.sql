-- Prerrequisito del pase: `sql_updates/costos_adicionales_producto.sql` completo.
--
-- No se copia aquí para no duplicar la fuente de verdad. Este archivo solo sirve
-- de recordatorio y de comprobación previa: si las cuatro piezas no están, 06c
-- aborta con «no se pudo parchear _v2 … anclas encontradas: 0» y, peor, la
-- reversa del costo fallaría al escribir en `costo_real`, que en main sigue
-- siendo GENERATED.
--
-- Aplícalo ANTES de 06a y antes de 06c. Es idempotente (IF NOT EXISTS,
-- CREATE OR REPLACE y DROP EXPRESSION condicional).

-- Comprobación: las cuatro piezas del prerrequisito.
SELECT jsonb_pretty(jsonb_build_object(
  'producto_costo', (SELECT count(*) FROM information_schema.tables
                      WHERE table_schema='public' AND table_name='app_dat_producto_costo'),
  'recepcion_costo', (SELECT count(*) FROM information_schema.tables
                       WHERE table_schema='public' AND table_name='app_dat_recepcion_producto_costo'),
  'costo_real_normal', (SELECT (is_generated = 'NEVER')::text FROM information_schema.columns
                         WHERE table_schema='public' AND table_name='app_dat_recepcion_productos'
                           AND column_name='costo_real'),
  'trigger_costo_real', (SELECT count(*) FROM pg_trigger
                          WHERE tgname='trg_recepcion_productos_costo_real' AND NOT tgisinternal),
  'v2_lee_costos', (SELECT (p.prosrc LIKE '%app_dat_recepcion_producto_costo%')::text
                      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                     WHERE n.nspname='public' AND p.proname='fn_actualizar_precio_promedio_recepcion_v2')
)) AS prerrequisito;