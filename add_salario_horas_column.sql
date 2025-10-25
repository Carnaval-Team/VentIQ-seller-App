-- Script para agregar la columna salario_horas a la tabla app_dat_trabajadores
-- Fecha: 2025-10-25
-- Descripción: Agrega columna para almacenar el salario por hora de cada trabajador

-- Agregar columna salario_horas con valor por defecto 0
ALTER TABLE public.app_dat_trabajadores
ADD COLUMN IF NOT EXISTS salario_horas numeric NOT NULL DEFAULT 0;

-- Agregar comentario a la columna
COMMENT ON COLUMN public.app_dat_trabajadores.salario_horas IS 'Salario por hora del trabajador en la moneda local';

-- Verificar que la columna se agregó correctamente
SELECT column_name, data_type, column_default, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'app_dat_trabajadores'
  AND column_name = 'salario_horas';
