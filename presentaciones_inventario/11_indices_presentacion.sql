-- ============================================================================
-- 11 · Indices por id_presentacion  (PREREQUISITO del 12)
-- ============================================================================
-- Plan: docs/PLAN_PRESENTACIONES_INVENTARIO.md
-- Proyecto Supabase: vsieeihstajlrdvpuooh
--
-- ESTADO: **YA APLICADO EN PRODUCCION** el 2026-08-26 via MCP.
-- Este archivo queda como registro y para poder reproducir el estado en otro
-- entorno. Es idempotente (IF NOT EXISTS), asi que correrlo de nuevo no hace
-- nada.
--
--
-- POR QUE EXISTE ESTE ARCHIVO
-- ---------------------------
-- Al correr el 13 (los tests del congelado de factor) en el SQL Editor, dio
-- TIMEOUT. La causa no era el trigger ni el test: es que NINGUNA de las tablas
-- de movimientos tenia un indice por `id_presentacion`.
--
-- Medido con EXPLAIN ANALYZE en produccion, antes de estos indices:
--
--   tabla                          filas     tamano   plan          tiempo
--   app_dat_inventario_productos   309.092   224 MB   Seq Scan       46 ms
--   app_dat_extraccion_productos   201.486    54 MB   Seq Scan       30 ms
--   app_dat_control_productos      187.511    34 MB   Seq Scan      ~40 ms
--   app_dat_recepcion_productos     24.437   4.5 MB   Seq Scan       ~5 ms
--
-- Los dos indices que ya existian sobre el ledger
-- (`idx_inv_prod_combo`, `idx_inventario_productos_optimized`) arrancan por
-- `id_producto`, asi que no sirven para filtrar SOLO por presentacion: Postgres
-- no puede saltar la primera columna de un btree.
--
-- Consecuencia: cada llamada a `fn_presentacion_tiene_movimientos` recorria
-- cuatro tablas completas, ~120 ms. El test D2 la llamaba una vez por fila de
-- app_dat_producto_presentacion (8.891 filas):
--
--   8.891 x 120 ms ~= 18 minutos   -> timeout del dashboard
--
-- El timeout fue util: la funcion iba a ser llamada por la UI cada vez que se
-- abriera la pantalla de edicion de un producto. 120 ms por consulta sobre la
-- tabla mas grande del sistema, en cada apertura, era una regresion de
-- rendimiento esperando a pasar. El test solo la hizo visible antes.
--
-- Despues de estos indices, la misma comprobacion completa (las 5 tablas):
--
--   Execution Time: 0.293 ms      <- de ~120 ms a 0,3 ms
--
-- Los cuatro primeros resuelven por **Index Only Scan** con `Heap Fetches: 0`:
-- ni tocan la tabla, contestan desde el indice.
--
--
-- POR QUE INDICES PARCIALES (WHERE id_presentacion IS NOT NULL)
-- ------------------------------------------------------------
-- Hay bastantes filas con presentacion nula y no aportan nada a esta pregunta:
-- 2.863 en extraccion, 88.646 en control, 61 en recepcion. Excluirlas hace el
-- indice mas chico y mas rapido de mantener en cada INSERT.
--
-- No se pone el filtro en app_dat_conversion_presentacion porque ahi las dos
-- columnas son NOT NULL.
--
--
-- POR QUE CONCURRENTLY
-- --------------------
-- `CREATE INDEX` normal toma un ACCESS EXCLUSIVE sobre la tabla: bloquea las
-- ventas mientras construye. Con 224 MB en el ledger eso es una caja parada.
-- CONCURRENTLY no bloquea escrituras.
--
-- OJO AL APLICAR A MANO: CONCURRENTLY **no puede correr dentro de una
-- transaccion**. En el SQL Editor de Supabase hay que ejecutar cada CREATE INDEX
-- por separado, uno por vez, no los seis de un tiron (el editor envuelve el
-- bloque en una transaccion y falla con
-- "CREATE INDEX CONCURRENTLY cannot run inside a transaction block").
--
-- Si un CONCURRENTLY se interrumpe deja el indice INVALIDO. Se detecta con la
-- consulta de verificacion del final; se arregla con DROP INDEX y de nuevo.
-- ============================================================================


-- ────────────────────────────────────────────────────────────────────────────
-- Ejecutar de UNA EN UNA (no todas juntas)
-- ────────────────────────────────────────────────────────────────────────────

-- 11.1 · el ledger (309.092 filas, 224 MB) — el indice pesa 2288 kB
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_inventario_productos_presentacion
  ON public.app_dat_inventario_productos (id_presentacion)
  WHERE id_presentacion IS NOT NULL;

-- 11.2 · detalle de extraccion (201.486 filas) — 1456 kB
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_extraccion_productos_presentacion
  ON public.app_dat_extraccion_productos (id_presentacion)
  WHERE id_presentacion IS NOT NULL;

-- 11.3 · detalle de control / conteo (187.511 filas) — 704 kB
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_control_productos_presentacion
  ON public.app_dat_control_productos (id_presentacion)
  WHERE id_presentacion IS NOT NULL;

-- 11.4 · detalle de recepcion (24.437 filas) — 312 kB
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_recepcion_productos_presentacion
  ON public.app_dat_recepcion_productos (id_presentacion)
  WHERE id_presentacion IS NOT NULL;

-- 11.5 y 11.6 · conversiones. La tabla esta vacia hoy (0 filas), pero va a
-- crecer con cada apertura de caja. El indice compuesto que creo el 01
-- (idx_conv_pres_producto_ubicacion) arranca por id_producto y no sirve para
-- buscar por presentacion. Se necesitan los dos, origen y destino: la consulta
-- los combina con OR y Postgres resuelve con BitmapOr.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_conv_pres_origen
  ON public.app_dat_conversion_presentacion (id_presentacion_origen);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_conv_pres_destino
  ON public.app_dat_conversion_presentacion (id_presentacion_destino);


-- ============================================================================
-- VERIFICACION (ya corrida en produccion, todo OK)
-- ============================================================================
-- 1. Los seis existen y son VALIDOS (un CONCURRENTLY interrumpido deja
--    indisvalid = false y el indice no se usa):
--
--   SELECT c.relname AS tabla, i.relname AS indice,
--          x.indisvalid AS valido, x.indisready AS listo,
--          pg_size_pretty(pg_relation_size(i.oid)) AS tam
--     FROM pg_index x
--     JOIN pg_class i ON i.oid = x.indexrelid
--     JOIN pg_class c ON c.oid = x.indrelid
--    WHERE i.relname IN ('idx_inventario_productos_presentacion',
--                        'idx_extraccion_productos_presentacion',
--                        'idx_control_productos_presentacion',
--                        'idx_recepcion_productos_presentacion',
--                        'idx_conv_pres_origen',
--                        'idx_conv_pres_destino')
--    ORDER BY 1;
--
--   -- verificado 2026-08-26: los 4 principales valido=true, listo=true
--   --   app_dat_control_productos      idx_control_productos_presentacion      704 kB
--   --   app_dat_extraccion_productos   idx_extraccion_productos_presentacion  1456 kB
--   --   app_dat_inventario_productos   idx_inventario_productos_presentacion  2288 kB
--   --   app_dat_recepcion_productos    idx_recepcion_productos_presentacion    312 kB
--
-- 2. Que el planificador los use de verdad:
--
--   EXPLAIN (ANALYZE)
--   SELECT (EXISTS (SELECT 1 FROM app_dat_inventario_productos t
--                    WHERE t.id_presentacion = 11053)
--        OR EXISTS (SELECT 1 FROM app_dat_recepcion_productos t
--                    WHERE t.id_presentacion = 11053)
--        OR EXISTS (SELECT 1 FROM app_dat_extraccion_productos t
--                    WHERE t.id_presentacion = 11053)
--        OR EXISTS (SELECT 1 FROM app_dat_control_productos t
--                    WHERE t.id_presentacion = 11053)
--        OR EXISTS (SELECT 1 FROM app_dat_conversion_presentacion t
--                    WHERE t.id_presentacion_origen  = 11053
--                       OR t.id_presentacion_destino = 11053)) AS r;
--
--   -- verificado: 4 x "Index Only Scan ... Heap Fetches: 0" + 1 BitmapOr
--   -- Execution Time: 0.293 ms
--
-- 3. Costo de mantenimiento: ~4,7 MB de indice sobre 316 MB de tablas. Cada
--    INSERT en el ledger paga una entrada de indice mas; despreciable al lado
--    de los cuatro Seq Scan que se evitan.
