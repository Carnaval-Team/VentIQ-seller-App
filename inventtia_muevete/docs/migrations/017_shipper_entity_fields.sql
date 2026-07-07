-- =============================================================================
-- MIGRACIÓN 017: Campos de entidad económica universal para Shippers
-- Plataforma Muevete
--
-- Diseño multi-país: los labels de id_fiscal y cod_actividad se adaptan en
-- la UI según pais_empresa (Cuba→NIF/CNAE, USA→EIN/NAICS, España→NIF/CNAE,
-- México→RFC/SCIAN).
--
-- REGLA: Solo ADD COLUMN IF NOT EXISTS. Sin modificar columnas existentes.
-- =============================================================================

ALTER TABLE muevete.users
  -- 1. Tipo de organización
  ADD COLUMN IF NOT EXISTS tipo_organizacion text,
  -- Ej: 'empresa_privada' | 'empresa_estatal' | 'autonomo' | 'cooperativa'
  --     'ong' | 'otro'

  -- 2. Nombre legal de la empresa (razón social)
  ADD COLUMN IF NOT EXISTS nombre_legal text,

  -- 3. Identificador fiscal local (NIF / EIN / RFC / CIF …)
  ADD COLUMN IF NOT EXISTS id_fiscal text,

  -- 4. Código de actividad económica (CNAE / NAICS / SCIAN / CIIU …)
  ADD COLUMN IF NOT EXISTS cod_actividad text,

  -- 5. País de la entidad (código ISO-3166-1 alpha-2, ej: 'CU', 'US', 'ES', 'MX')
  ADD COLUMN IF NOT EXISTS pais_empresa text,

  -- 6. Estado / Región / Provincia de la entidad
  ADD COLUMN IF NOT EXISTS region_empresa text,

  -- 7. Ciudad / Municipio de la entidad
  ADD COLUMN IF NOT EXISTS ciudad_empresa text,

  -- 8. Dirección completa (calle, número, reparto/colonia)
  ADD COLUMN IF NOT EXISTS direccion_empresa text,

  -- 9. Teléfono de la entidad (opcional)
  ADD COLUMN IF NOT EXISTS telefono_empresa text,

  -- 10. Correo electrónico de la entidad (opcional)
  ADD COLUMN IF NOT EXISTS email_empresa text;

-- Nota: empresa_nombre, empresa_rut, empresa_direccion ya existen (migración 001).
-- Los campos nuevos son universales; la UI adapta los labels según pais_empresa.

COMMENT ON COLUMN muevete.users.tipo_organizacion IS
  'Tipo de organización: empresa_privada | empresa_estatal | autonomo | cooperativa | ong | otro';
COMMENT ON COLUMN muevete.users.nombre_legal IS
  'Nombre legal / Razón social de la entidad';
COMMENT ON COLUMN muevete.users.id_fiscal IS
  'Identificador fiscal local según país: NIF (CU/ES), EIN (US), RFC (MX), etc.';
COMMENT ON COLUMN muevete.users.cod_actividad IS
  'Código de actividad económica según país: CNAE (CU/ES), NAICS (US), SCIAN (MX), CIIU';
COMMENT ON COLUMN muevete.users.pais_empresa IS
  'País de la entidad (ISO-3166-1 alpha-2)';
COMMENT ON COLUMN muevete.users.region_empresa IS
  'Estado / Región / Provincia de la entidad';
COMMENT ON COLUMN muevete.users.ciudad_empresa IS
  'Ciudad / Municipio de la entidad';
COMMENT ON COLUMN muevete.users.direccion_empresa IS
  'Dirección completa: calle, número, reparto/colonia';
COMMENT ON COLUMN muevete.users.telefono_empresa IS
  'Teléfono de contacto de la entidad';
COMMENT ON COLUMN muevete.users.email_empresa IS
  'Correo electrónico de contacto de la entidad';
