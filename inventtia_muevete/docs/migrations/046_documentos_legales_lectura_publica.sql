-- ============================================================================
-- 046_documentos_legales_lectura_publica.sql
-- Los documentos legales deben poder leerse SIN sesión.
--
-- POR QUÉ
--   Los términos y la política de privacidad se enlazan desde el LANDING y desde
--   LOGIN/REGISTRO, es decir, antes de tener sesión. La RLS de `036` sólo daba
--   SELECT a `authenticated`:
--       documentos_legales_select_auth  FOR SELECT TO authenticated
--                                       USING (publicado OR is_superadmin())
--   y `anon` no tenía ni el privilegio de tabla. Resultado: al pulsar el enlace
--   la app no podía traer el texto (fallaba o salía vacío).
--
--   Un documento legal publicado tiene que ser público por definición: es lo que
--   el usuario debe poder leer ANTES de aceptar. Se abre la lectura para `anon`
--   limitada a lo que ya es visible: `publicado = true` y vigente.
--
-- QUÉ HACE
--   1. Política SELECT para `anon` (y `authenticated`) sobre documentos
--      publicados y vigentes. Las políticas se suman por OR: `authenticated`
--      conserva la suya (que además le deja ver borradores si es superadmin).
--   2. GRANT SELECT a `anon` (sólo lectura; nada de escritura).
--
-- LO QUE **NO** CAMBIA
--   · `consentimientos` sigue siendo privado (cada usuario ve lo suyo) y
--     append-only.
--   · Escribir o publicar documentos sigue siendo exclusivo de superadmin.
--   · Sólo se exponen documentos PUBLICADOS y VIGENTES: los borradores y las
--     versiones vencidas quedan invisibles para `anon`.
--
-- IDEMPOTENCIA
--   DROP POLICY IF EXISTS + CREATE POLICY + GRANT (idempotente).
--
-- NO EJECUTAR CONTRA SUPABASE DESDE ESTE ENTORNO (sólo se entrega el archivo).
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 0. Prerrequisitos
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('muevete.documentos_legales') IS NULL THEN
    RAISE EXCEPTION 'falta la tabla muevete.documentos_legales (036)';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname='muevete' AND tablename='documentos_legales'
       AND policyname='documentos_legales_select_auth'
  ) THEN
    RAISE EXCEPTION 'falta la política documentos_legales_select_auth (036)';
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 1. Lectura pública de lo publicado y vigente
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS documentos_legales_select_publico ON muevete.documentos_legales;
CREATE POLICY documentos_legales_select_publico ON muevete.documentos_legales
  FOR SELECT TO anon, authenticated
  USING (
    publicado
    AND (vigente_hasta IS NULL OR vigente_hasta > now())
  );

COMMENT ON POLICY documentos_legales_select_publico ON muevete.documentos_legales IS
  'El landing y el login leen los términos/privacidad sin sesión. Sólo documentos publicados y vigentes.';

-- ----------------------------------------------------------------------------
-- 2. Privilegio de tabla para `anon` (sólo lectura)
-- ----------------------------------------------------------------------------
GRANT SELECT ON muevete.documentos_legales TO anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON muevete.documentos_legales FROM anon;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN (ejecutar a mano; NO forma parte de la migración)
-- ============================================================================
-- 1) Política y privilegios:
--   SELECT policyname, cmd, roles::text
--     FROM pg_policies
--    WHERE schemaname='muevete' AND tablename='documentos_legales'
--    ORDER BY policyname;
--   -- debe aparecer documentos_legales_select_publico con {anon,authenticated}
--
--   SELECT grantee, string_agg(privilege_type, ',' ORDER BY privilege_type)
--     FROM information_schema.role_table_grants
--    WHERE table_schema='muevete' AND table_name='documentos_legales'
--      AND grantee IN ('anon','authenticated') GROUP BY grantee;
--   -- anon: SELECT (nada más)
--
-- 2) Como `anon` (sin JWT) se ven exactamente 4 documentos vigentes:
--   SET ROLE anon;
--   SELECT codigo, version, publicado, vigente_hasta IS NULL AS vigente
--     FROM muevete.documentos_legales ORDER BY codigo;
--   RESET ROLE;
--   -- esperado: contacto_emergencia, kyc, privacidad, terminos (todos 1.1.0
--   --           salvo contacto_emergencia que va en 1.0.0)
--
-- 3) Un borrador NO debe verse como anon:
--   -- (crear un borrador con publicado=false y comprobar que anon no lo lista)
--
-- ============================================================================
-- ROLLBACK
-- ============================================================================
-- DROP POLICY IF EXISTS documentos_legales_select_publico ON muevete.documentos_legales;
-- REVOKE SELECT ON muevete.documentos_legales FROM anon;
-- ============================================================================