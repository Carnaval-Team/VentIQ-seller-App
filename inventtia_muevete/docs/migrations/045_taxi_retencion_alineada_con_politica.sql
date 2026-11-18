-- ============================================================================
-- 045_taxi_retencion_alineada_con_politica.sql
-- Alinea la retención de datos configurada con la Política de Privacidad v1.1.0.
--
-- DECISIÓN DEL USUARIO (2026-11-13)
--   "retención de ubicaciones: hasta 90" y "retención de incidentes: hasta 5 años".
--   La política publicada en `042` (documento `privacidad` v1.1.0) promete esos
--   plazos, pero `configuracion_seguridad` tenía valores MENORES:
--       dias_retencion_ubicaciones : 30   → debe ser 90
--       meses_retencion_incidentes : 24   → debe ser 60  (5 años)
--   Con los valores viejos la purga borraba antes de lo prometido (legalmente no
--   es infracción, pero el texto y la configuración deben decir lo mismo).
--
-- QUIÉN USA ESTOS VALORES
--   `muevete.fn_purgar_seguridad()` los lee para decidir qué histórico de
--   posiciones e incidentes elimina. Cambiarlos aquí cambia la purga.
--
-- IDEMPOTENCIA
--   UPDATE ... WHERE id = 1 AND (valores distintos). Re-ejecutar no falla y no
--   toca `actualizado_at` si ya estaban alineados.
--
-- NO EJECUTAR CONTRA SUPABASE DESDE ESTE ENTORNO (sólo se entrega el archivo).
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 0. Prerrequisitos
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('muevete.configuracion_seguridad') IS NULL THEN
    RAISE EXCEPTION 'falta la tabla muevete.configuracion_seguridad (037)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM muevete.configuracion_seguridad WHERE id = 1) THEN
    RAISE EXCEPTION 'falta la fila id=1 de configuracion_seguridad';
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 1. Alinear los dos plazos con la política publicada
-- ----------------------------------------------------------------------------
UPDATE muevete.configuracion_seguridad
   SET dias_retencion_ubicaciones = 90,   -- "hasta 90 días" (política, §7)
       meses_retencion_incidentes = 60,   -- "hasta 5 años"  (política, fila 14)
       actualizado_at             = now()
 WHERE id = 1
   AND (dias_retencion_ubicaciones IS DISTINCT FROM 90
     OR meses_retencion_incidentes IS DISTINCT FROM 60);

-- ----------------------------------------------------------------------------
-- 2. Guarda: los valores deben quedar alineados
-- ----------------------------------------------------------------------------
DO $$
DECLARE v_dias integer; v_meses integer;
BEGIN
  SELECT dias_retencion_ubicaciones, meses_retencion_incidentes
    INTO v_dias, v_meses
    FROM muevete.configuracion_seguridad WHERE id = 1;

  IF v_dias <> 90 THEN
    RAISE EXCEPTION 'dias_retencion_ubicaciones quedó en % (esperado 90)', v_dias;
  END IF;
  IF v_meses <> 60 THEN
    RAISE EXCEPTION 'meses_retencion_incidentes quedó en % (esperado 60)', v_meses;
  END IF;
END $$;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN (ejecutar a mano; NO forma parte de la migración)
-- ============================================================================
-- 1) Config alineada:
--   SELECT dias_retencion_ubicaciones, meses_retencion_incidentes, actualizado_at
--     FROM muevete.configuracion_seguridad WHERE id = 1;
--   -- esperado: 90 | 60
--
-- 2) Coherencia con el texto publicado (la política menciona 90 días y 5 años):
--   SELECT codigo, version,
--          position('90' in contenido_md)   > 0 AS menciona_90,
--          position('5 años' in contenido_md) > 0 AS menciona_5_anios
--     FROM muevete.documentos_legales
--    WHERE codigo = 'privacidad' AND vigente_hasta IS NULL;
--   -- esperado: true | true
--
-- 3) La purga usa estos valores (no la ejecutes en producción sin querer):
--   SELECT proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname = 'muevete' AND proname = 'fn_purgar_seguridad';
--
-- ============================================================================
-- ROLLBACK
-- ============================================================================
-- UPDATE muevete.configuracion_seguridad
--    SET dias_retencion_ubicaciones = 30, meses_retencion_incidentes = 24,
--        actualizado_at = now()
--  WHERE id = 1;
-- ============================================================================