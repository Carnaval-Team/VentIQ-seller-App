-- ============================================================================
-- 048_kyc_obligatorio_para_clientes.sql
-- La verificación de identidad también es OBLIGATORIA para los CLIENTES.
--
-- DECISIÓN DEL USUARIO (2026-11-13)
--   "un paso importante es que el cliente y el chofer estén verificados ambos".
--   Hasta ahora `configuracion_identidad.requiere_aprobacion_kyc_cliente` estaba
--   en `false`: el cliente podía operar con `kyc_estado = 'en_revision'` y el
--   superadmin ni siquiera tenía pantalla para revisarlo (sólo veía choferes).
--
-- QUÉ HACE
--   1. Enciende `requiere_aprobacion_kyc_cliente`: `fn_usuario_habilitado`
--      devuelve `kyc_pendiente_aprobacion` y el gate bloquea publicar/tomar
--      hasta que el superadmin apruebe. El gate es de SERVIDOR, no de UI.
--   2. No toca `requiere_aprobacion_kyc_chofer` (ya estaba en true).
--
-- EFECTO
--   Todo cliente con `kyc_estado <> 'aprobado'` deja de poder publicar viajes.
--   El recorrido queda: completa perfil → `en_revision` → superadmin aprueba →
--   `aprobado`. Los rechazados ven el motivo y pueden corregir y reenviar.
--
-- ORDEN DE DESPLIEGUE (importante)
--   Aplicar DESPUÉS de publicar la pantalla de KYC con la pestaña de clientes y
--   de aprobar a los clientes que ya estén operando; si no, se quedan sin poder
--   pedir viajes. Por eso en PRUEBAS se aplica junto con la pantalla nueva.
--
-- IDEMPOTENCIA
--   UPDATE condicionado a que esté en false.
--
-- NO EJECUTAR CONTRA SUPABASE DESDE ESTE ENTORNO (sólo se entrega el archivo).
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 0. Prerrequisitos
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('muevete.configuracion_identidad') IS NULL THEN
    RAISE EXCEPTION 'falta la tabla muevete.configuracion_identidad (036)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM muevete.configuracion_identidad WHERE id = 1) THEN
    RAISE EXCEPTION 'falta la fila id=1 de configuracion_identidad';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'muevete' AND p.proname = 'fn_usuario_habilitado'
  ) THEN
    RAISE EXCEPTION 'falta muevete.fn_usuario_habilitado (036)';
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 1. Encender la aprobación de KYC para clientes
-- ----------------------------------------------------------------------------
UPDATE muevete.configuracion_identidad
   SET requiere_aprobacion_kyc_cliente = true,
       updated_at = now()
 WHERE id = 1
   AND requiere_aprobacion_kyc_cliente IS DISTINCT FROM true;

-- ----------------------------------------------------------------------------
-- 2. Guarda
-- ----------------------------------------------------------------------------
DO $$
DECLARE v_cli boolean; v_cho boolean;
BEGIN
  SELECT requiere_aprobacion_kyc_cliente, requiere_aprobacion_kyc_chofer
    INTO v_cli, v_cho
    FROM muevete.configuracion_identidad WHERE id = 1;

  IF NOT v_cli THEN
    RAISE EXCEPTION 'requiere_aprobacion_kyc_cliente quedó en false';
  END IF;
  IF NOT v_cho THEN
    RAISE NOTICE 'AVISO: requiere_aprobacion_kyc_chofer está en false; se esperaba true';
  END IF;
END $$;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN (ejecutar a mano; NO forma parte de la migración)
-- ============================================================================
-- 1) Config:
--   SELECT requiere_aprobacion_kyc_cliente, requiere_aprobacion_kyc_chofer,
--          kyc_obligatorio
--     FROM muevete.configuracion_identidad WHERE id = 1;
--   -- esperado: true | true | true
--
-- 2) Un cliente en revisión queda bloqueado por el gate:
--   SELECT muevete.fn_usuario_habilitado('<uuid-cliente-en-revision>'::uuid,'cliente');
--   -- esperado: habilitado=false, motivos con 'kyc_pendiente_aprobacion'
--
-- 3) Tras aprobarlo desde el panel (fn_kyc_revisar('cliente', uuid, 'aprobado')):
--   SELECT muevete.fn_usuario_habilitado('<uuid>'::uuid,'cliente');
--   -- esperado: habilitado=true
--
-- 4) Clientes que ya estaban operando y se quedaron sin aprobar:
--   SELECT uuid, name, email, kyc_estado
--     FROM muevete.users
--    WHERE kyc_estado IS DISTINCT FROM 'aprobado'
--    ORDER BY created_at;
--   -- revisarlos/aprobarlos ANTES de desplegar este cambio
--
-- ============================================================================
-- ROLLBACK
-- ============================================================================
-- UPDATE muevete.configuracion_identidad
--    SET requiere_aprobacion_kyc_cliente = false, updated_at = now()
--  WHERE id = 1;
-- ============================================================================