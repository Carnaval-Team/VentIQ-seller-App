-- Actualizar tabla app_cont_gastos para manejar diferentes tipos de origen
-- Agregar campos para diferenciar entre operaciones y egresos

-- Agregar campo tipo_origen para distinguir el tipo de origen del gasto
ALTER TABLE public.app_cont_gastos 
ADD COLUMN IF NOT EXISTS tipo_origen character varying;

-- Agregar campo id_referencia_origen para referenciar el ID específico del origen
ALTER TABLE public.app_cont_gastos 
ADD COLUMN IF NOT EXISTS id_referencia_origen bigint;

-- Crear índices para mejorar rendimiento en consultas
CREATE INDEX IF NOT EXISTS idx_gastos_tipo_origen 
  ON public.app_cont_gastos(tipo_origen);
CREATE INDEX IF NOT EXISTS idx_gastos_referencia_origen 
  ON public.app_cont_gastos(id_referencia_origen);
CREATE INDEX IF NOT EXISTS idx_gastos_tipo_referencia 
  ON public.app_cont_gastos(tipo_origen, id_referencia_origen);

-- Agregar comentarios para documentación
COMMENT ON COLUMN public.app_cont_gastos.tipo_origen IS 
  'Tipo de origen del gasto: operacion_recepcion, egreso_efectivo, etc.';
COMMENT ON COLUMN public.app_cont_gastos.id_referencia_origen IS 
  'ID de referencia al registro origen específico (operación, egreso, etc.)';

-- Migrar datos existentes si es necesario (opcional)
-- UPDATE public.app_cont_gastos 
-- SET tipo_origen = 'operacion_recepcion' 
-- WHERE tipo_origen IS NULL AND /* condición para identificar recepciones */;
