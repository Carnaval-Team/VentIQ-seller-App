-- ============================================================================
-- Fase 0 — Diagnóstico de esquema multimoneda (SOLO LECTURA)
-- ============================================================================
-- Objetivo: cerrar los huecos que no se pueden resolver leyendo el repo.
-- Todo son SELECT. NO modifica nada. Seguro de ejecutar en producción.
--
-- Dónde ejecutarlo : Supabase → SQL Editor (proyecto VentiQ)
-- Qué hacer después: pegar la salida completa para ajustar el plan.md
--
-- Motivo: el volcado `VentiQ.sql` del repo es parcial y desactualizado.
-- Faltan el DDL de `tasa_cambio_extraoficial`, `tipos_moneda` y
-- `app_dat_denominaciones_moneda`, y `monedas.codigo` aparece como
-- `character` (= bpchar(1)), donde no cabría 'USD'.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1) ¿Cuál es el tipo REAL de monedas.codigo?  [BLOQUEANTE]
--    Si es bpchar(1), la migración falla al insertar 'USD' y hay que hacer
--    ALTER COLUMN antes de cualquier otra cosa.
-- ----------------------------------------------------------------------------
SELECT table_name, column_name, data_type,
       character_maximum_length,
       is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('monedas', 'tipos_moneda', 'tasas_conversion',
                     'tasa_cambio_extraoficial', 'app_dat_denominaciones_moneda')
ORDER BY table_name, ordinal_position;


-- ----------------------------------------------------------------------------
-- 2) Contenido actual de los catálogos
-- ----------------------------------------------------------------------------
SELECT * FROM public.monedas ORDER BY codigo;

SELECT * FROM public.tipos_moneda ORDER BY id;

SELECT * FROM public.app_dat_denominaciones_moneda
ORDER BY codigo_moneda, denominacion
LIMIT 500;

SELECT id, moneda_origen, moneda_destino, tasa, fecha_actualizacion
FROM public.tasas_conversion
ORDER BY moneda_origen, moneda_destino, fecha_actualizacion DESC;


-- ----------------------------------------------------------------------------
-- 3) Constraints reales de app_dat_pago_venta
--    Interesa: ¿existe app_dat_pago_venta_moneda_check con IN ('CUP','USD')?
--    ¿Y las columnas moneda / tasa_usd / monto_cup_equivalente?
-- ----------------------------------------------------------------------------
SELECT conname, contype, pg_get_constraintdef(oid) AS definicion
FROM pg_constraint
WHERE conrelid = 'public.app_dat_pago_venta'::regclass
ORDER BY contype, conname;

SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'app_dat_pago_venta'
ORDER BY ordinal_position;


-- ----------------------------------------------------------------------------
-- 4) Volumen y estado real de los pagos por moneda
--    (el doc del repo afirma 121.877 CUP + 7 USD con tasa 550: verificar)
-- ----------------------------------------------------------------------------
SELECT moneda,
       count(*)                                            AS pagos,
       count(DISTINCT id_operacion_venta)                  AS operaciones,
       sum(monto)                                          AS importe_nativo,
       sum(monto_cup_equivalente)                          AS importe_base,
       min(tasa_usd)                                       AS tasa_usd_min,
       max(tasa_usd)                                       AS tasa_usd_max,
       count(*) FILTER (WHERE monto_cup_equivalente IS NULL) AS sin_equivalente
FROM public.app_dat_pago_venta
GROUP BY moneda
ORDER BY pagos DESC;


-- ----------------------------------------------------------------------------
-- 5) Turnos / caja: ¿existen ya las columnas *_usd y hay datos?
-- ----------------------------------------------------------------------------
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'app_dat_caja_turno'
ORDER BY ordinal_position;

SELECT count(*)                                        AS turnos,
       count(*) FILTER (WHERE COALESCE(efectivo_inicial_usd, 0) <> 0) AS con_inicial_usd,
       count(*) FILTER (WHERE efectivo_real_usd IS NOT NULL)          AS con_cierre_usd
FROM public.app_dat_caja_turno;


-- ----------------------------------------------------------------------------
-- 6) RLS real: ¿quién puede escribir los catálogos?
--    En el repo NO hay ninguna política para estas tablas (hueco de seguridad).
-- ----------------------------------------------------------------------------
SELECT c.relname AS tabla,
       c.relrowsecurity AS rls_habilitado,
       c.relforcerowsecurity AS rls_forzado
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('monedas', 'tipos_moneda', 'tasas_conversion',
                    'tasa_cambio_extraoficial', 'app_dat_denominaciones_moneda',
                    'app_dat_tienda_moneda')
ORDER BY c.relname;

SELECT tablename, policyname, cmd, roles, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('monedas', 'tipos_moneda', 'tasas_conversion',
                    'tasa_cambio_extraoficial', 'app_dat_denominaciones_moneda')
ORDER BY tablename, policyname;


-- ----------------------------------------------------------------------------
-- 7) Funciones vigentes: ¿qué versión de las RPC está desplegada?
--    Necesario para decidir sobrecargas _v3/_v4 sin romper la app instalada.
-- ----------------------------------------------------------------------------
SELECT p.proname,
       pg_get_function_identity_arguments(p.oid) AS argumentos,
       pg_get_function_result(p.oid)             AS retorna
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND (p.proname LIKE 'fn_registrar_pago_venta%'
       OR p.proname LIKE 'fn_registrar_venta%'
       OR p.proname LIKE 'fn_resumen_diario_cierre%'
       OR p.proname LIKE 'fn_cerrar_turno%'
       OR p.proname LIKE 'registrar_apertura_turno%'
       OR p.proname LIKE 'fn_reporte_ventas%'
       OR p.proname LIKE 'fn_listar_turnos%'
       OR p.proname LIKE 'fn_profit_and_loss%'
       OR p.proname LIKE 'fn_sales_metrics%')
ORDER BY p.proname, argumentos;


-- ----------------------------------------------------------------------------
-- 8) ¿Existe el helper de superadmin que usaremos en las políticas RLS?
-- ----------------------------------------------------------------------------
SELECT p.proname,
       pg_get_function_identity_arguments(p.oid) AS argumentos
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('fn_is_superadmin_full_access', 'fn_user_can_access_tienda')
ORDER BY p.proname;


-- ----------------------------------------------------------------------------
-- 9) Independencia de id: ¿tipos_moneda.id 1 y 2 son CUP y USD?
--    Crítico porque tasa_cambio_extraoficial usa esos ids y NO se migrará.
-- ----------------------------------------------------------------------------
SELECT tm.id, tm.denominacion, tm.simbolo, tm.nombre_corto, tm.pais, tm.activo,
       (SELECT count(*) FROM public.tasa_cambio_extraoficial t
        WHERE t.id_moneda_origen = tm.id)  AS tasas_como_origen,
       (SELECT count(*) FROM public.tasa_cambio_extraoficial t
        WHERE t.id_moneda_destino = tm.id) AS tasas_como_destino
FROM public.tipos_moneda tm
ORDER BY tm.id;


-- ----------------------------------------------------------------------------
-- 10) Tamaño de las tablas que se van a tocar (para planificar ventanas)
-- ----------------------------------------------------------------------------
SELECT relname AS tabla,
       n_live_tup AS filas_aprox
FROM pg_stat_user_tables
WHERE schemaname = 'public'
  AND relname IN ('app_dat_pago_venta', 'app_dat_caja_turno',
                  'app_dat_tienda', 'monedas', 'tipos_moneda',
                  'tasas_conversion', 'tasa_cambio_extraoficial',
                  'app_dat_denominaciones_moneda')
ORDER BY n_live_tup DESC;

-- ============================================================================
-- Fin del diagnóstico. Guardar la salida en:
--   docs/plan-multimoneda/diagnostico-resultado.md
-- ============================================================================