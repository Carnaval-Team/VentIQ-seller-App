-- =============================================================================
-- Reset del módulo de costos (datos de prueba / seed basura)
--
-- Qué BORRA:
--   · Gastos, asignaciones, logs e historiales de costos
--   · Tipos de costo (nomenclador contaminado por createStandardCostTypes)
--   · Costos adicionales de producto / recepción (si existen)
--   · Actividades del historial financiero
--
-- Qué CONSERVA:
--   · app_cont_margen_comercial  (márgenes de precio en uso)
--   · app_cont_egresos_procesados (caja / egresos)
--   · app_cont_centro_costo
--   · app_nom_categoria_gasto / app_nom_subcategoria_gasto
--
-- Qué RESIEMBRA:
--   · app_nom_naturaleza_costo → Gasto (1), Ingreso (2)
--   · UNIQUE(denominacion) en app_cont_tipo_costo
--
-- Aplicar en Main y Newa. Tipos de costo quedan vacíos: se cargan desde
-- superadmin (Nomencladores de costo) según a costos adicionales.
-- =============================================================================

BEGIN;

-- 1) Hojas / logs
TRUNCATE TABLE public.app_cont_log_costos RESTART IDENTITY CASCADE;
TRUNCATE TABLE public.app_cont_gasto_asignacion CASCADE;

-- 2) Historiales
TRUNCATE TABLE public.app_cont_historial_gastos RESTART IDENTITY CASCADE;
TRUNCATE TABLE public.app_cont_historial_asignacion_costos RESTART IDENTITY CASCADE;
TRUNCATE TABLE public.app_cont_historial_actividades RESTART IDENTITY CASCADE;

-- 3) Transaccional
TRUNCATE TABLE public.app_cont_gastos RESTART IDENTITY CASCADE;
TRUNCATE TABLE public.app_cont_asignacion_costos RESTART IDENTITY CASCADE;

-- 4) Costos adicionales por producto (si ya se desplegó el feature)
DO $$
BEGIN
  IF to_regclass('public.app_dat_recepcion_producto_costo') IS NOT NULL THEN
    EXECUTE 'TRUNCATE TABLE public.app_dat_recepcion_producto_costo RESTART IDENTITY CASCADE';
  END IF;
  IF to_regclass('public.app_dat_producto_costo') IS NOT NULL THEN
    EXECUTE 'TRUNCATE TABLE public.app_dat_producto_costo RESTART IDENTITY CASCADE';
  END IF;
END $$;

-- 5) Nomenclador de tipos (el que estaba duplicado)
TRUNCATE TABLE public.app_cont_tipo_costo RESTART IDENTITY CASCADE;

-- 6) Naturalezas: dejar solo Gasto / Ingreso
DELETE FROM public.app_nom_naturaleza_costo;
INSERT INTO public.app_nom_naturaleza_costo (id, denominacion, descripcion)
VALUES
  (1, 'Gasto',   'Erogaciones que afectan negativamente el resultado'),
  (2, 'Ingreso', 'Entradas que afectan positivamente el resultado')
ON CONFLICT (id) DO UPDATE
  SET denominacion = EXCLUDED.denominacion,
      descripcion  = EXCLUDED.descripcion;

-- 7) Evitar que el seed de admin vuelva a duplicar
CREATE UNIQUE INDEX IF NOT EXISTS uq_app_cont_tipo_costo_denominacion
  ON public.app_cont_tipo_costo (denominacion);

-- 8) Verificación
SELECT 'tipo_costo' AS tabla, COUNT(*) AS filas FROM public.app_cont_tipo_costo
UNION ALL SELECT 'gastos', COUNT(*) FROM public.app_cont_gastos
UNION ALL SELECT 'asignaciones', COUNT(*) FROM public.app_cont_asignacion_costos
UNION ALL SELECT 'naturalezas', COUNT(*) FROM public.app_nom_naturaleza_costo
UNION ALL SELECT 'margen_comercial (conservado)', COUNT(*) FROM public.app_cont_margen_comercial
ORDER BY 1;

COMMIT;
