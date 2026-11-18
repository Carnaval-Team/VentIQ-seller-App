-- ============================================================================
-- 043_taxi_consentimientos_inmutables.sql
-- Los consentimientos son un registro de AUDITORÍA: append-only.
--
-- ANEXO DE DISEÑO
--   · docs/plan-taxi-precio-fijo/08-privacidad-y-consentimiento.md
--     (auditoría del consentimiento: fecha, dispositivo, versión del texto)
--   · PLAN-IMPLEMENTACION.md §H1 criterios: "queda auditado con fecha, IP y
--     dispositivo" y "cambiar la versión de un documento obliga a re-aceptar".
--
-- POR QUÉ
--   `muevete.consentimientos` es la prueba de que un usuario aceptó una versión
--   concreta de un documento legal. Si una fila se puede modificar o borrar, la
--   prueba desaparece: un superadmin podría "limpiar" una aceptación y el
--   historial dejaría de ser fiable. Además había `UPDATE`/`DELETE` concedidos a
--   `authenticated` (heredado de la política `superadmin_all_consentimientos`
--   FOR ALL), así que un cliente con sesión podía intentarlo.
--
-- QUÉ HACE
--   1. Trigger BEFORE UPDATE OR DELETE que aborta siempre (P0060).
--   2. Revoca UPDATE/DELETE/TRUNCATE a `authenticated` y `anon`; deja
--      SELECT + INSERT (el alta va por `fn_aceptar_consentimiento`, que es
--      SECURITY DEFINER e inserta con `ON CONFLICT DO NOTHING`: NO actualiza,
--      así que este trigger no rompe la re-aceptación — crea fila nueva por
--      versión, que es justo lo que queremos auditar).
--
-- LO QUE **NO** CAMBIA
--   · `fn_aceptar_consentimiento` sigue funcionando (sólo INSERT).
--   · `fn_usuario_habilitado` sigue leyendo normalmente.
--   · Re-aceptar la misma versión es idempotente (ON CONFLICT DO NOTHING).
--
-- IDEMPOTENCIA
--   CREATE OR REPLACE FUNCTION + DROP TRIGGER IF EXISTS + REVOKE/GRANT.
--
-- NOTA (delta conocido, no bloqueante)
--   El anexo habla de guardar IP y plataforma. La tabla actual no tiene esas
--   columnas: quedan cubiertas por `user_agent`, `app_version` y `metadata`
--   (que puede llevar la IP desde la Edge Function). No se añaden columnas aquí
--   para no tocar el contrato ya aplicado.
--
-- NO EJECUTAR CONTRA SUPABASE DESDE ESTE ENTORNO (sólo se entrega el archivo).
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 0. Prerrequisitos
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('muevete.consentimientos') IS NULL THEN
    RAISE EXCEPTION 'falta la tabla muevete.consentimientos (036)';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'muevete' AND p.proname = 'fn_aceptar_consentimiento'
  ) THEN
    RAISE EXCEPTION 'falta muevete.fn_aceptar_consentimiento (036)';
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 1. Trigger de inmutabilidad (append-only)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_consentimiento_inmutable()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = muevete, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'consentimiento_inmutable: el registro de consentimientos es append-only (no se actualiza ni se borra)'
    USING ERRCODE = 'P0060';
END;
$$;

COMMENT ON FUNCTION muevete.fn_consentimiento_inmutable() IS
  'Bloquea UPDATE/DELETE en consentimientos: son prueba de auditoría. El alta va por fn_aceptar_consentimiento (INSERT).';

DROP TRIGGER IF EXISTS trg_consentimiento_inmutable ON muevete.consentimientos;
CREATE TRIGGER trg_consentimiento_inmutable
  BEFORE UPDATE OR DELETE ON muevete.consentimientos
  FOR EACH ROW EXECUTE FUNCTION muevete.fn_consentimiento_inmutable();

-- ----------------------------------------------------------------------------
-- 2. Permisos: sólo lectura y alta
--    (TRUNCATE no dispara triggers de fila: hay que quitarlo por privilegio)
-- ----------------------------------------------------------------------------
REVOKE UPDATE, DELETE, TRUNCATE ON muevete.consentimientos FROM authenticated, anon;
-- Supabase concede REFERENCES y TRIGGER por defecto; en una tabla de auditoría
-- tampoco tienen nada que hacer (TRIGGER permitiría crear triggers sobre ella).
REVOKE REFERENCES, TRIGGER ON muevete.consentimientos FROM authenticated, anon;
GRANT SELECT, INSERT ON muevete.consentimientos TO authenticated;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN (ejecutar a mano; NO forma parte de la migración)
-- ============================================================================
-- 1) Trigger y función:
--   SELECT tgname FROM pg_trigger
--    WHERE tgrelid = 'muevete.consentimientos'::regclass AND NOT tgisinternal;
--   -- debe aparecer trg_consentimiento_inmutable
--
-- 2) Privilegios (esperado: SELECT,INSERT y nada de UPDATE/DELETE/TRUNCATE):
--   SELECT string_agg(privilege_type, ',' ORDER BY privilege_type)
--     FROM information_schema.role_table_grants
--    WHERE table_schema='muevete' AND table_name='consentimientos'
--      AND grantee='authenticated';
--
-- 3) La re-aceptación sigue funcionando (INSERT, no UPDATE):
--   SELECT muevete.fn_aceptar_consentimiento('privacidad','1.1.0','app','test','test', '{}'::jsonb);
--
-- 4) Modificar o borrar debe fallar (P0060):
--   UPDATE muevete.consentimientos SET aceptado = false LIMIT 1;   -- ERROR P0060
--   DELETE FROM muevete.consentimientos WHERE id > 0;             -- ERROR P0060
--
-- ============================================================================
-- ROLLBACK
-- ============================================================================
-- DROP TRIGGER IF EXISTS trg_consentimiento_inmutable ON muevete.consentimientos;
-- DROP FUNCTION IF EXISTS muevete.fn_consentimiento_inmutable();
-- GRANT UPDATE, DELETE ON muevete.consentimientos TO authenticated;
-- ============================================================================