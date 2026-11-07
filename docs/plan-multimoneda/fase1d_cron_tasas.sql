-- ============================================================================
-- PRODUCCIÓN — Refresco programado de la tasa automática («el toque»)
-- ============================================================================
-- Destino: proyecto de PRODUCCIÓN.
--
-- ⚠️ ORDEN OBLIGATORIO. Este fichero NO funciona por sí solo: su verificación
--    (apartado 3.3) usa `public.fn_tasa_automatica`, que crea el fichero 1b.
--    Si se ejecuta antes, falla con:
--      ERROR 42883: function public.fn_tasa_automatica(unknown, unknown) does not exist
--
--    Orden correcto en producción:
--      1. ✅ fase1_catalogo_monedas.sql     (ya aplicado 2026-11-04)
--      2. ⬜ fase1b_tasa_automatica.sql     <-- crea las funciones que este usa
--      3. ⬜ ESTE fichero (fase1d_cron_tasas.sql)
--
--    Nota: el cron en sí solo invoca `flow.*` (que ya existe en producción), así
--    que la PROGRAMACIÓN funcionaría sin el paso 2; lo que no funcionaría es la
--    verificación 3.3. Aun así, respeta el orden: sin el paso 2, la pantalla
--    Monedas del superadmin no puede consultar ni refrescar la tasa.
--
-- ⚠️ NO APLICADO EN PRODUCCIÓN (comprobado 2026-11-04: 0 jobs `flow-tasas*`).
--    En newa sí está aplicado y verificado.
--
-- Qué hace
-- --------
-- Sin esto, la caché `flow.tasa_cambio` solo se actualiza cuando alguien pulsa
-- «Actualizar» en la pantalla Monedas del superadmin. Con esto se mantiene
-- fresca sola, y `fn_tasa_cambio` puede usarla como respaldo automático.
--
-- Por qué llama a `flow.*` y no a los wrappers de `public`
-- -------------------------------------------------------
-- Un job de pg_cron NO tiene sesión de usuario (no hay `auth.uid()`), así que
-- `public.fn_tasas_refrescar` / `public.fn_tasas_ingerir` fallarían en su
-- comprobación de superadmin. Se llama directamente a las funciones del
-- esquema `flow`, que no dependen de JWT.
--
-- Estado del proyecto de producción ANTES de aplicar (verificado 2026-11-04)
-- -------------------------------------------------------------------------
--   * pg_cron instalado. 9 jobs, ninguno de tasas. Entre ellos:
--       - update_daily_prices_00_00 [0 0 * * *] -> public.fn_update_daily_prices_carnaval()
--         Es de **Carnaval**, NO del TPV: no hay dependencia de orden con esto.
--       - flow-suscripciones-expirar [*/15 * * * *]
--   * Esquema `flow` presente: `flow.tasa_cambio` con 2 filas, última 2026-10-28.
--   * `public.tasas_conversion` tiene USD->CUP = 900 (tasa MANUAL).
--
-- ⚠️ Consecuencia importante para las expectativas
-- ------------------------------------------------
-- La tasa MANUAL siempre tiene prioridad sobre la automática. En producción,
-- USD->CUP ya tiene manual (900), así que ese par NO usará el toque.
-- La automática entra en los pares SIN tasa manual: hoy EUR->CUP y MLC->CUP.
-- Cobertura del proveedor: solo USD, EUR y MLC (CAD/GBP devuelven NULL).
--
-- Cadencia
-- --------
--   * refresco : cada hora al minuto 15.
--                `flow.tasas_refrescar(false)` tiene atajo: si la caché ya es
--                de hoy (hora de La Habana) no hace ninguna petición; si hay
--                una petición pendiente reutiliza su request_id.
--   * ingesta  : cada 10 minutos. Recoge las respuestas HTTP que ya llegaron.
--                Idempotente: no duplica filas.
--
-- Nota horaria: pg_cron usa la zona del servidor (UTC en Supabase). La cadencia
-- es horaria, así que la zona no afecta a la frescura; solo al minuto exacto.
-- ============================================================================


-- ============================================================================
-- 1) Idempotencia: quitar los jobs si ya existían
-- ============================================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'flow-tasas-refresco') THEN
    PERFORM cron.unschedule('flow-tasas-refresco');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'flow-tasas-ingesta') THEN
    PERFORM cron.unschedule('flow-tasas-ingesta');
  END IF;
END $$;


-- ============================================================================
-- 2) Programar
-- ============================================================================
SELECT cron.schedule(
  'flow-tasas-refresco',
  '15 * * * *',
  $$ select flow.tasas_refrescar(false); $$
);

SELECT cron.schedule(
  'flow-tasas-ingesta',
  '*/10 * * * *',
  $$ select flow.tasas_ingest(request_id)
       from flow.tasa_cambio_sondeo
      where not ingerido
        and creado_at <= now() - interval '2 minutes'
      limit 5; $$
);


-- ============================================================================
-- 3) Verificación
-- ============================================================================

-- 3.1 Los dos jobs existen y están activos
SELECT jobid, jobname, schedule, active
FROM cron.job
WHERE jobname IN ('flow-tasas-refresco', 'flow-tasas-ingesta')
ORDER BY jobname;

-- 3.2 Primera ejecución (esperar ~15 min y volver a lanzar esta consulta)
SELECT d.jobid, j.jobname, d.status,
       left(coalesce(d.return_message, ''), 200) AS mensaje,
       d.start_time, d.end_time
FROM cron.job_run_details d
LEFT JOIN cron.job j ON j.jobid = d.jobid
WHERE j.jobname IN ('flow-tasas-refresco', 'flow-tasas-ingesta')
ORDER BY d.start_time DESC
LIMIT 10;

-- 3.3 La caché se movió y el respaldo automático resuelve
SELECT (SELECT max(fecha)::text FROM flow.tasa_cambio)          AS ultima_fecha,
       (SELECT count(*)          FROM flow.tasa_cambio)        AS filas_cache,
       (SELECT count(*) FROM flow.tasa_cambio_sondeo
         WHERE NOT ingerido)                                   AS sondeos_pendientes,
       public.fn_tasa_automatica('EUR','CUP')                  AS auto_eur_cup,
       public.fn_tasa_automatica('MLC','CUP')                  AS auto_mlc_cup,
       public.fn_tasa_cambio('EUR','CUP')                      AS resolver_eur_cup;


-- ============================================================================
-- 4) Reversión (si hiciera falta)
-- ============================================================================
-- SELECT cron.unschedule('flow-tasas-refresco');
-- SELECT cron.unschedule('flow-tasas-ingesta');
--
-- Quitar los jobs NO rompe nada: `fn_tasa_cambio` seguiría usando la última
-- caché disponible hasta que se refresque a mano desde la pantalla Monedas.


-- ============================================================================
-- 5) Opcional: cadencia diaria en vez de horaria
-- ============================================================================
-- Si se prefiere una sola ejecución al día (menos peticiones al proveedor),
-- sustituir el schedule de 'flow-tasas-refresco' por:
--
--   '30 7 * * *'   -- 07:30 UTC. El proveedor publica a las 07:00 UTC.
--
-- Consecuencia: si el proveedor publica tarde o falla un día, la caché puede
-- quedarse 24 h desfasada. La cadencia horaria es más robusta y con el atajo
-- de "ya es de hoy" no genera peticiones extra.