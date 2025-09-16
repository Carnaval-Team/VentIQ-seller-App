-- Tabla para controlar egresos de efectivo procesados (aceptados/rechazados)
CREATE TABLE IF NOT EXISTS public.app_cont_egresos_procesados (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_egreso bigint NOT NULL,
  estado character varying NOT NULL CHECK (estado IN ('aceptado', 'rechazado')),
  procesado_por uuid NOT NULL,
  fecha_procesado timestamp with time zone NOT NULL DEFAULT now(),
  motivo_rechazo text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  
  CONSTRAINT app_cont_egresos_procesados_pkey PRIMARY KEY (id),
  CONSTRAINT app_cont_egresos_procesados_id_egreso_fkey 
    FOREIGN KEY (id_egreso) REFERENCES public.app_dat_entregas_parciales_caja(id),
  CONSTRAINT app_cont_egresos_procesados_procesado_por_fkey 
    FOREIGN KEY (procesado_por) REFERENCES auth.users(id),
  CONSTRAINT app_cont_egresos_procesados_unique_egreso 
    UNIQUE (id_egreso)
);

-- Índices para mejorar rendimiento
CREATE INDEX IF NOT EXISTS idx_egresos_procesados_estado 
  ON public.app_cont_egresos_procesados(estado);
CREATE INDEX IF NOT EXISTS idx_egresos_procesados_fecha 
  ON public.app_cont_egresos_procesados(fecha_procesado);

-- Comentarios para documentación
COMMENT ON TABLE public.app_cont_egresos_procesados IS 
  'Tabla de control para egresos de efectivo que han sido procesados (aceptados o rechazados como gastos)';
COMMENT ON COLUMN public.app_cont_egresos_procesados.estado IS 
  'Estado del procesamiento: aceptado o rechazado';
COMMENT ON COLUMN public.app_cont_egresos_procesados.motivo_rechazo IS 
  'Motivo del rechazo cuando el estado es rechazado';
