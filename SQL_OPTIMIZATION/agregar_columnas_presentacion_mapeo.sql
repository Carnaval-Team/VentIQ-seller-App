-- ============================================================================
-- AGREGAR COLUMNAS DE MAPEO DE PRESENTACIONES
-- ============================================================================
-- Este script agrega las columnas id_presentacion_original e id_presentacion_duplicada
-- a la tabla app_dat_producto_consignacion_duplicado para guardar el mapeo de presentaciones

-- 1. Agregar columnas si no existen
ALTER TABLE app_dat_producto_consignacion_duplicado
ADD COLUMN IF NOT EXISTS id_presentacion_original BIGINT,
ADD COLUMN IF NOT EXISTS id_presentacion_duplicada BIGINT;

-- 2. Agregar foreign keys si no existen
DO $$ 
BEGIN
  -- FK para id_presentacion_original
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'fk_pcd_presentacion_original' 
    AND table_name = 'app_dat_producto_consignacion_duplicado'
  ) THEN
    ALTER TABLE app_dat_producto_consignacion_duplicado
    ADD CONSTRAINT fk_pcd_presentacion_original 
    FOREIGN KEY (id_presentacion_original) 
    REFERENCES app_dat_producto_presentacion(id) 
    ON DELETE SET NULL;
  END IF;

  -- FK para id_presentacion_duplicada
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE constraint_name = 'fk_pcd_presentacion_duplicada' 
    AND table_name = 'app_dat_producto_consignacion_duplicado'
  ) THEN
    ALTER TABLE app_dat_producto_consignacion_duplicado
    ADD CONSTRAINT fk_pcd_presentacion_duplicada 
    FOREIGN KEY (id_presentacion_duplicada) 
    REFERENCES app_dat_producto_presentacion(id) 
    ON DELETE SET NULL;
  END IF;
END $$;

-- 3. Crear índices para mejorar el rendimiento de las consultas
CREATE INDEX IF NOT EXISTS idx_pcd_presentacion_original 
ON app_dat_producto_consignacion_duplicado(id_presentacion_original);

CREATE INDEX IF NOT EXISTS idx_pcd_presentacion_duplicada 
ON app_dat_producto_consignacion_duplicado(id_presentacion_duplicada);

-- Verificar que las columnas se agregaron correctamente
SELECT 
  column_name, 
  data_type, 
  is_nullable
FROM information_schema.columns
WHERE table_name = 'app_dat_producto_consignacion_duplicado'
  AND column_name IN ('id_presentacion_original', 'id_presentacion_duplicada');
