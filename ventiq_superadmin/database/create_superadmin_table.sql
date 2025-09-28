-- Crear tabla para superadministradores
CREATE TABLE IF NOT EXISTS public.app_dat_superadmin (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  uuid uuid NOT NULL UNIQUE,
  nombre character varying NOT NULL,
  apellidos character varying NOT NULL,
  email character varying NOT NULL UNIQUE,
  telefono character varying,
  activo boolean NOT NULL DEFAULT true,
  nivel_acceso smallint NOT NULL DEFAULT 1, -- 1: Full Access, 2: Read/Write, 3: Read Only
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  ultimo_acceso timestamp with time zone,
  CONSTRAINT app_dat_superadmin_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_superadmin_uuid_fkey FOREIGN KEY (uuid) REFERENCES auth.users(id) ON DELETE CASCADE
);

-- Crear índices para mejorar el rendimiento
CREATE INDEX IF NOT EXISTS idx_superadmin_uuid ON public.app_dat_superadmin(uuid);
CREATE INDEX IF NOT EXISTS idx_superadmin_email ON public.app_dat_superadmin(email);
CREATE INDEX IF NOT EXISTS idx_superadmin_activo ON public.app_dat_superadmin(activo);

-- Crear trigger para actualizar updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_app_dat_superadmin_updated_at 
  BEFORE UPDATE ON public.app_dat_superadmin 
  FOR EACH ROW 
  EXECUTE FUNCTION update_updated_at_column();

-- Insertar un superadmin de prueba (comentar en producción)
-- INSERT INTO public.app_dat_superadmin (uuid, nombre, apellidos, email)
-- SELECT id, 'Super', 'Admin', 'superadmin@ventiq.com'
-- FROM auth.users
-- WHERE email = 'superadmin@ventiq.com'
-- LIMIT 1;
