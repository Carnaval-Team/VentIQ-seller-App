-- Roles y permisos de navegacion para superadministradores
-- Un rol contiene una lista de rutas (route names) a las que sus usuarios pueden acceder.

CREATE TABLE IF NOT EXISTS public.app_dat_superadmin_roles (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  nombre character varying NOT NULL UNIQUE,
  descripcion character varying,
  permisos jsonb NOT NULL DEFAULT '[]'::jsonb,
  activo boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_superadmin_roles_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS idx_superadmin_roles_activo ON public.app_dat_superadmin_roles(activo);

-- Enlazar superadmin con rol. Sin rol asignado mantiene el comportamiento legacy (acceso total segun nivel_acceso).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'app_dat_superadmin'
      AND column_name = 'id_rol'
  ) THEN
    ALTER TABLE public.app_dat_superadmin
      ADD COLUMN id_rol bigint REFERENCES public.app_dat_superadmin_roles(id) ON DELETE SET NULL;
  END IF;
END $$;

-- Trigger updated_at
CREATE OR REPLACE FUNCTION update_superadmin_roles_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_superadmin_roles_updated_at ON public.app_dat_superadmin_roles;
CREATE TRIGGER trg_update_superadmin_roles_updated_at
  BEFORE UPDATE ON public.app_dat_superadmin_roles
  FOR EACH ROW
  EXECUTE FUNCTION update_superadmin_roles_updated_at();

-- RLS: helper para identificar superadmins con acceso total
CREATE OR REPLACE FUNCTION public.fn_is_superadmin_full_access()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.app_dat_superadmin
    WHERE uuid = auth.uid()
      AND activo = true
      AND nivel_acceso = 1
  );
$$;

GRANT EXECUTE ON FUNCTION public.fn_is_superadmin_full_access() TO authenticated;

-- Habilitar RLS en la tabla de roles
ALTER TABLE public.app_dat_superadmin_roles ENABLE ROW LEVEL SECURITY;

-- Cualquier superadmin autenticado puede ver los roles (para asignarlos a usuarios)
DROP POLICY IF EXISTS superadmin_roles_select_authenticated ON public.app_dat_superadmin_roles;
CREATE POLICY superadmin_roles_select_authenticated
  ON public.app_dat_superadmin_roles
  FOR SELECT
  TO authenticated
  USING (true);

-- Solo superadmins con acceso total pueden crear/editar/eliminar roles
DROP POLICY IF EXISTS superadmin_roles_write_full_access ON public.app_dat_superadmin_roles;
CREATE POLICY superadmin_roles_write_full_access
  ON public.app_dat_superadmin_roles
  FOR ALL
  TO authenticated
  USING (public.fn_is_superadmin_full_access())
  WITH CHECK (public.fn_is_superadmin_full_access());

-- Habilitar RLS en superadmin para proteger la asignacion de roles
ALTER TABLE public.app_dat_superadmin ENABLE ROW LEVEL SECURITY;

-- Un superadmin puede verse a si mismo; un full-access puede ver a todos
DROP POLICY IF EXISTS superadmin_select_own_or_full ON public.app_dat_superadmin;
CREATE POLICY superadmin_select_own_or_full
  ON public.app_dat_superadmin
  FOR SELECT
  TO authenticated
  USING (
    uuid = auth.uid()
    OR public.fn_is_superadmin_full_access()
  );

-- Solo full-access puede modificar, insertar o eliminar superadmins
DROP POLICY IF EXISTS superadmin_update_full_access ON public.app_dat_superadmin;
CREATE POLICY superadmin_update_full_access
  ON public.app_dat_superadmin
  FOR UPDATE
  TO authenticated
  USING (public.fn_is_superadmin_full_access())
  WITH CHECK (public.fn_is_superadmin_full_access());

DROP POLICY IF EXISTS superadmin_insert_full_access ON public.app_dat_superadmin;
CREATE POLICY superadmin_insert_full_access
  ON public.app_dat_superadmin
  FOR INSERT
  TO authenticated
  WITH CHECK (public.fn_is_superadmin_full_access());

DROP POLICY IF EXISTS superadmin_delete_full_access ON public.app_dat_superadmin;
CREATE POLICY superadmin_delete_full_access
  ON public.app_dat_superadmin
  FOR DELETE
  TO authenticated
  USING (public.fn_is_superadmin_full_access());

-- Permisos para usuarios autenticados
GRANT SELECT, INSERT, UPDATE, DELETE ON public.app_dat_superadmin_roles TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.app_dat_superadmin_roles_id_seq TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.app_dat_superadmin TO authenticated;
