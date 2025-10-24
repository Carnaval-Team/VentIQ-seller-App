-- Tabla para gestión de trabajadores en turnos
-- Permite registrar entrada/salida de trabajadores y calcular horas trabajadas

CREATE TABLE IF NOT EXISTS public.app_dat_turno_trabajadores (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_turno bigint NOT NULL,
  id_trabajador bigint NOT NULL,
  hora_entrada timestamp with time zone NOT NULL DEFAULT now(),
  hora_salida timestamp with time zone DEFAULT NULL,
  horas_trabajadas numeric GENERATED ALWAYS AS (
    CASE 
      WHEN hora_salida IS NOT NULL THEN 
        EXTRACT(EPOCH FROM (hora_salida - hora_entrada)) / 3600
      ELSE NULL
    END
  ) STORED,
  observaciones text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  
  CONSTRAINT app_dat_turno_trabajadores_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_turno_trabajadores_id_turno_fkey 
    FOREIGN KEY (id_turno) REFERENCES public.app_dat_caja_turno(id) ON DELETE CASCADE,
  CONSTRAINT app_dat_turno_trabajadores_id_trabajador_fkey 
    FOREIGN KEY (id_trabajador) REFERENCES public.app_dat_trabajadores(id) ON DELETE CASCADE,
  
  -- Evitar duplicados: un trabajador no puede tener múltiples entradas activas en el mismo turno
  CONSTRAINT app_dat_turno_trabajadores_unique_active 
    UNIQUE (id_turno, id_trabajador)
);

-- Índices para mejorar rendimiento
CREATE INDEX IF NOT EXISTS idx_turno_trabajadores_turno 
  ON public.app_dat_turno_trabajadores(id_turno);
  
CREATE INDEX IF NOT EXISTS idx_turno_trabajadores_trabajador 
  ON public.app_dat_turno_trabajadores(id_trabajador);
  
CREATE INDEX IF NOT EXISTS idx_turno_trabajadores_activos 
  ON public.app_dat_turno_trabajadores(id_turno, id_trabajador) 
  WHERE hora_salida IS NULL;

-- Trigger para actualizar updated_at
CREATE OR REPLACE FUNCTION update_turno_trabajadores_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_turno_trabajadores_updated_at
  BEFORE UPDATE ON public.app_dat_turno_trabajadores
  FOR EACH ROW
  EXECUTE FUNCTION update_turno_trabajadores_updated_at();

-- Comentarios para documentación
COMMENT ON TABLE public.app_dat_turno_trabajadores IS 
  'Registro de trabajadores asignados a turnos con control de entrada/salida';
COMMENT ON COLUMN public.app_dat_turno_trabajadores.id_turno IS 
  'Referencia al turno de caja';
COMMENT ON COLUMN public.app_dat_turno_trabajadores.id_trabajador IS 
  'Referencia al trabajador asignado';
COMMENT ON COLUMN public.app_dat_turno_trabajadores.hora_entrada IS 
  'Timestamp de entrada del trabajador al turno';
COMMENT ON COLUMN public.app_dat_turno_trabajadores.hora_salida IS 
  'Timestamp de salida del trabajador (NULL si aún está activo)';
COMMENT ON COLUMN public.app_dat_turno_trabajadores.horas_trabajadas IS 
  'Horas trabajadas calculadas automáticamente (diferencia entre entrada y salida)';
