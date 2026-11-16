-- ============================================================================
-- 051_sms_proveedor_whatsapp.sql
-- Habilita WhatsApp como proveedor del outbox de mensajes (`configuracion_sms`).
--
-- POR QUÉ
--   En Cuba no hay proveedor SMS viable a corto plazo (Twilio no cubre Cuba;
--   ClickSend exige Alpha Tag con ~30 días de registro). En cambio ya hay un
--   gateway **OpenWA (WhatsApp)** corriendo para `ventiq_admin_app`, con la
--   sesión de la tienda 177 CONNECTED. El worker `send-sms` ya sabe usarlo
--   (`proveedor = 'whatsapp'`), sólo faltaba poder configurarlo en la BD.
--
-- QUÉ HACE
--   1. Amplía el CHECK de `configuracion_sms.proveedor` para admitir 'whatsapp'.
--   2. Añade `whatsapp_session_id`: la sesión WAPI con la que se envía.
--      (El worker también acepta el secreto `WAPI_SESSION_ID`, que tiene
--      prioridad; esta columna permite cambiarla sin redesplegar.)
--   3. Si existe `public.app_wapi_sesion` y hay UNA sesión CONNECTED, la deja
--      precargada. Si no, queda NULL y se configura a mano.
--
-- FORMATO DEL NÚMERO
--   El outbox guarda el destinatario en E.164 (`+5354590207`, lo exige su
--   CHECK). El worker lo convierte al formato de OpenWA:
--       +53 54590207  →  `5354590207@c.us`
--   (dígitos con código de país, sin «+», sin espacios, sufijo `@c.us`).
--
-- IDEMPOTENCIA
--   DROP CONSTRAINT IF EXISTS + ADD CONSTRAINT; ADD COLUMN IF NOT EXISTS.
--
-- NO EJECUTAR CONTRA SUPABASE DESDE ESTE ENTORNO (sólo se entrega el archivo).
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 0. Prerrequisitos
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('muevete.configuracion_sms') IS NULL THEN
    RAISE EXCEPTION 'falta muevete.configuracion_sms (050)';
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 1. Permitir el proveedor 'whatsapp'
-- ----------------------------------------------------------------------------
ALTER TABLE muevete.configuracion_sms
  DROP CONSTRAINT IF EXISTS configuracion_sms_proveedor_check;

ALTER TABLE muevete.configuracion_sms
  ADD CONSTRAINT configuracion_sms_proveedor_check
  CHECK (proveedor IN ('mock','whatsapp','clicksend','twilio'));

-- ----------------------------------------------------------------------------
-- 2. Sesión WAPI a usar
-- ----------------------------------------------------------------------------
ALTER TABLE muevete.configuracion_sms
  ADD COLUMN IF NOT EXISTS whatsapp_session_id text;

COMMENT ON COLUMN muevete.configuracion_sms.whatsapp_session_id IS
  'Sesión OpenWA (UUID) usada cuando proveedor = ''whatsapp''. El secreto WAPI_SESSION_ID tiene prioridad.';

-- ----------------------------------------------------------------------------
-- 3. Precargar la sesión conectada (si la tabla del panel existe aquí)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_session text;
BEGIN
  IF to_regclass('public.app_wapi_sesion') IS NOT NULL THEN
    SELECT wapi_session_id INTO v_session
      FROM public.app_wapi_sesion
     WHERE status = 'CONNECTED'
     ORDER BY last_status_at DESC NULLS LAST
     LIMIT 1;

    IF v_session IS NOT NULL THEN
      UPDATE muevete.configuracion_sms
         SET whatsapp_session_id = v_session,
             updated_at = now()
       WHERE id = 1
         AND (whatsapp_session_id IS NULL OR whatsapp_session_id <> v_session);

      RAISE NOTICE 'sesion WAPI precargada: %', v_session;
    ELSE
      RAISE NOTICE 'no hay sesion CONNECTED; configura whatsapp_session_id a mano';
    END IF;
  ELSE
    RAISE NOTICE 'public.app_wapi_sesion no existe en este proyecto; configura whatsapp_session_id a mano';
  END IF;
END $$;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN (ejecutar a mano; NO forma parte de la migración)
-- ============================================================================
-- 1) CHECK y columna:
--   SELECT pg_get_constraintdef(oid) FROM pg_constraint
--    WHERE conrelid = 'muevete.configuracion_sms'::regclass
--      AND conname = 'configuracion_sms_proveedor_check';
--   SELECT whatsapp_session_id FROM muevete.configuracion_sms WHERE id = 1;
--
-- 2) Activar el envío por WhatsApp:
--   UPDATE muevete.configuracion_sms
--      SET proveedor = 'whatsapp', activo = true, updated_at = now()
--    WHERE id = 1;
--
-- 3) Probar el flujo completo (encola un mensaje real):
--   SELECT muevete.fn_sms_encolar('+5354590207', 'Prueba de Muévete por WhatsApp',
--                                 'aviso', 'muevete');
--   -- luego invocar el worker `send-sms` (cron o a mano) y revisar:
--   SELECT id, destinatario, estado, intentos, proveedor, proveedor_msg_id, ultimo_error
--     FROM muevete.sms_mensajes ORDER BY id DESC LIMIT 5;
--
-- 4) El WhatsApp debe llegar a 5354590207 con ese texto.
--
-- ============================================================================
-- ROLLBACK
-- ============================================================================
-- UPDATE muevete.configuracion_sms SET proveedor = 'mock' WHERE proveedor = 'whatsapp';
-- ALTER TABLE muevete.configuracion_sms DROP COLUMN IF EXISTS whatsapp_session_id;
-- ALTER TABLE muevete.configuracion_sms DROP CONSTRAINT IF EXISTS configuracion_sms_proveedor_check;
-- ALTER TABLE muevete.configuracion_sms
--   ADD CONSTRAINT configuracion_sms_proveedor_check
--   CHECK (proveedor IN ('mock','clicksend','twilio'));
-- ============================================================================