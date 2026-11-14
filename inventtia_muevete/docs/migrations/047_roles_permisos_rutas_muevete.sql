-- ============================================================================
-- 047_roles_permisos_rutas_muevete.sql
-- Añade las rutas nuevas del módulo Muévete a los roles del panel que ya tienen
-- acceso a Muévete.
--
-- POR QUÉ
--   El menú del superadmin se filtra por `app_dat_superadmin_roles.permisos`
--   (jsonb con la lista de rutas). El rol "full" (id = 1) se creó antes de que
--   existieran las pantallas de zonas, tarifas, vehículos, documentos legales e
--   incidentes, así que **aunque el usuario sea superadmin** esas opciones no
--   aparecían en el menú.
--
--   Con esto, un superadmin con rol "full" ve:
--     /muevete/zonas       · Zonas y Polígonos
--     /muevete/tarifas     · Tarifas y Zonas
--     /muevete/vehiculos   · Catálogo de Vehículos
--     /muevete/documentos  · Documentos y Consentimientos
--     /muevete/incidentes  · Incidentes y Bloqueos
--
-- CRITERIO DE APLICACIÓN
--   Sólo a roles que YA tienen `/muevete/dashboard` en sus permisos. Un rol de
--   otra área (p. ej. solo Carnaval) no recibe accesos que no pidió.
--
-- QUIÉN LO NECESITA
--   Producción: aplicar en el cutover, junto con `041`. En el proyecto de
--   pruebas ya está aplicado.
--
-- NOTA OPERATIVA
--   El panel guarda `permisos_rutas` en las preferencias del dispositivo al
--   iniciar sesión, así que tras aplicar esto cada administrador debe **cerrar
--   sesión y volver a entrar** para ver las rutas nuevas.
--
-- IDEMPOTENCIA
--   UPDATE condicionado a que falte alguna de las rutas. Re-ejecutar no duplica
--   ni reordena (dedupe con `jsonb_agg(DISTINCT ... ORDER BY ...)`).
--
-- NO EJECUTAR CONTRA SUPABASE DESDE ESTE ENTORNO (sólo se entrega el archivo).
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 0. Prerrequisitos
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('public.app_dat_superadmin_roles') IS NULL THEN
    RAISE EXCEPTION 'falta la tabla public.app_dat_superadmin_roles';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='app_dat_superadmin_roles'
       AND column_name='permisos' AND udt_name='jsonb'
  ) THEN
    RAISE EXCEPTION 'app_dat_superadmin_roles.permisos debe ser jsonb';
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 1. Añadir las rutas nuevas a los roles que ya tienen Muévete
-- ----------------------------------------------------------------------------
UPDATE public.app_dat_superadmin_roles r
   SET permisos = (
         SELECT jsonb_agg(DISTINCT elem ORDER BY elem)
           FROM jsonb_array_elements_text(
                  r.permisos
                  || '["/muevete/zonas","/muevete/tarifas","/muevete/vehiculos","/muevete/documentos","/muevete/incidentes"]'::jsonb
                ) AS t(elem)
       ),
       updated_at = now()
 WHERE r.permisos @> '"/muevete/dashboard"'::jsonb
   AND NOT (
     r.permisos @> '["/muevete/zonas","/muevete/tarifas","/muevete/vehiculos","/muevete/documentos","/muevete/incidentes"]'::jsonb
   );

-- ----------------------------------------------------------------------------
-- 2. Guarda: todo rol con Muévete debe tener las 5 rutas
-- ----------------------------------------------------------------------------
DO $$
DECLARE v_faltan integer;
BEGIN
  SELECT count(*) INTO v_faltan
    FROM public.app_dat_superadmin_roles r
   WHERE r.permisos @> '"/muevete/dashboard"'::jsonb
     AND NOT (
       r.permisos @> '["/muevete/zonas","/muevete/tarifas","/muevete/vehiculos","/muevete/documentos","/muevete/incidentes"]'::jsonb
     );

  IF v_faltan > 0 THEN
    RAISE EXCEPTION 'quedaron % roles con acceso a Muévete sin las rutas nuevas', v_faltan;
  END IF;
END $$;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN (ejecutar a mano; NO forma parte de la migración)
-- ============================================================================
-- 1) Rol "full" con las rutas nuevas:
--   SELECT id, nombre, jsonb_array_length(permisos) AS total,
--          permisos @> '["/muevete/zonas","/muevete/tarifas"]'::jsonb AS tiene
--     FROM public.app_dat_superadmin_roles ORDER BY id;
--
-- 2) Lista completa de rutas de Muévete del rol:
--   SELECT jsonb_array_elements_text(permisos) AS ruta
--     FROM public.app_dat_superadmin_roles WHERE id = 1
--    ORDER BY 1;
--   -- deben aparecer las 5 nuevas
--
-- 3) Un usuario es superadmin (necesario para escribir zonas/tarifas):
--   SELECT EXISTS (
--     SELECT 1 FROM public.app_dat_superadmin
--      WHERE uuid = auth.uid() AND activo
--   );
--
-- ============================================================================
-- ROLLBACK
-- ============================================================================
-- UPDATE public.app_dat_superadmin_roles r
--    SET permisos = (
--          SELECT jsonb_agg(elem)
--            FROM jsonb_array_elements_text(r.permisos) AS t(elem)
--           WHERE elem NOT IN ('/muevete/zonas','/muevete/tarifas',
--                              '/muevete/vehiculos','/muevete/documentos',
--                              '/muevete/incidentes')
--        )
--  WHERE r.permisos @> '"/muevete/dashboard"'::jsonb;
-- ============================================================================