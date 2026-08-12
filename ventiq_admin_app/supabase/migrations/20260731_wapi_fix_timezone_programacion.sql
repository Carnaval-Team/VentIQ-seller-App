-- ============================================================================
--  Fix: la difusión automática nunca se ejecutaba (sin error visible)
-- ============================================================================
--  La programación 11 (tienda 177 — Santa Clara, Cuba) tenía guardada
--  `timezone = 'America/Los_Angeles'`. El trigger `trg_wapi_prog_recalc`
--  interpreta `hora_envio` EN esa zona, así que 09:00 se resolvía a
--  `next_run_at = 12:00` hora de Havana. Resultado: el cron corría bien, el
--  Vault estaba bien, las credenciales estaban bien... pero la difusión
--  "de las 9" simplemente no salía. `last_run_at = NULL` confirma que nunca
--  llegó a dispararse desde su creación.
--
--  El origen del dato malo fue `TimezoneHelper.getLocalTimezone()`: detectaba
--  mal la zona del dispositivo y se guardaba en silencio. En la app ya se
--  corrigió — ahora la zona es un selector explícito y editable en
--  `wapi_schedule_config_screen.dart`.
--
--  NOTA: al cambiar `timezone` el trigger recalcula `next_run_at`. Como las
--  09:00 de hoy ya pasaron, la próxima ejecución queda para MAÑANA 09:00
--  hora de Havana. Si quieres que la difusión de hoy salga igualmente,
--  ejecuta después:  SELECT fn_wapi_force_dispatch(11);
-- ============================================================================

UPDATE public.app_wapi_programacion
   SET timezone = 'America/Havana'
 WHERE id = 11
   AND timezone = 'America/Los_Angeles';

-- Verificación (debería devolver 'America/Havana' y un next_run_at a las
-- 09:00 hora local de Cuba):
--   SELECT id, hora_envio, timezone, next_run_at,
--          (next_run_at AT TIME ZONE 'America/Havana') AS next_run_local
--     FROM public.app_wapi_programacion WHERE id = 11;
