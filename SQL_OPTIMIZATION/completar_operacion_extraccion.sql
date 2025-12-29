-- ============================================================================
-- SCRIPT: Completar operación de extracción
-- DESCRIPCIÓN: Cambia el estado de una operación de extracción a COMPLETADA (2)
-- USO: Ejecutar en Supabase SQL Editor para completar la extracción
-- ============================================================================

-- Reemplaza 38690 con el ID de la operación de extracción que deseas completar
INSERT INTO app_dat_estado_operacion (
  id_operacion,
  estado,
  comentario,
  created_at
) VALUES (
  38690, -- ID de la operación de extracción
  2,     -- Estado 2 = COMPLETADA
  'Operación de extracción completada manualmente para prueba',
  CURRENT_TIMESTAMP
);

-- Verificar que se creó correctamente
SELECT 
  id_operacion,
  estado,
  comentario,
  created_at
FROM app_dat_estado_operacion
WHERE id_operacion = 38690
ORDER BY created_at DESC
LIMIT 1;
