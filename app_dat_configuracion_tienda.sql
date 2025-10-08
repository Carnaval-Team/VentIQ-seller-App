-- Tabla de configuraciones del sistema por tienda
-- Esta tabla almacena configuraciones específicas para cada tienda en VentIQ

CREATE TABLE public.app_dat_configuracion_tienda (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_tienda bigint NOT NULL,
  need_master_password_to_cancel boolean NOT NULL DEFAULT false,
  need_all_orders_completed_to_continue boolean NOT NULL DEFAULT false,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  
  -- Constraints
  CONSTRAINT app_dat_configuracion_tienda_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_configuracion_tienda_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id) ON DELETE CASCADE,
  
  -- Unique constraint para asegurar una sola configuración por tienda
  CONSTRAINT app_dat_configuracion_tienda_id_tienda_unique UNIQUE (id_tienda)
);

-- Índices para optimizar consultas
CREATE INDEX idx_app_dat_configuracion_tienda_id_tienda ON public.app_dat_configuracion_tienda(id_tienda);
CREATE INDEX idx_app_dat_configuracion_tienda_updated_at ON public.app_dat_configuracion_tienda(updated_at);

-- Trigger para actualizar automáticamente updated_at
CREATE OR REPLACE FUNCTION update_app_dat_configuracion_tienda_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER trigger_update_app_dat_configuracion_tienda_updated_at
    BEFORE UPDATE ON public.app_dat_configuracion_tienda
    FOR EACH ROW
    EXECUTE FUNCTION update_app_dat_configuracion_tienda_updated_at();

-- Comentarios para documentación
COMMENT ON TABLE public.app_dat_configuracion_tienda IS 'Configuraciones del sistema específicas por tienda';
COMMENT ON COLUMN public.app_dat_configuracion_tienda.id IS 'Identificador único de la configuración';
COMMENT ON COLUMN public.app_dat_configuracion_tienda.id_tienda IS 'Referencia a la tienda (FK a app_dat_tienda)';
COMMENT ON COLUMN public.app_dat_configuracion_tienda.need_master_password_to_cancel IS 'Indica si se requiere contraseña maestra para cancelar operaciones';
COMMENT ON COLUMN public.app_dat_configuracion_tienda.need_all_orders_completed_to_continue IS 'Indica si se requiere completar todas las órdenes antes de continuar';
COMMENT ON COLUMN public.app_dat_configuracion_tienda.created_at IS 'Fecha y hora de creación del registro';
COMMENT ON COLUMN public.app_dat_configuracion_tienda.updated_at IS 'Fecha y hora de última actualización del registro';

-- Insertar configuraciones por defecto para tiendas existentes (opcional)
-- INSERT INTO public.app_dat_configuracion_tienda (id_tienda, need_master_password_to_cancel, need_all_orders_completed_to_continue)
-- SELECT id, false, false FROM public.app_dat_tienda
-- WHERE id NOT IN (SELECT id_tienda FROM public.app_dat_configuracion_tienda);
