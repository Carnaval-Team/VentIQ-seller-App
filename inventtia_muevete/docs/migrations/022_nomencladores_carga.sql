-- ============================================================
-- MIGRACIÓN 022 — Nomencladores de tipo de carga y tipo de equipo
-- ============================================================
-- Cambios:
--  1. Crear app_nom_tipo_carga  (FTL, LTL, etc.)
--  2. Crear app_nom_tipo_equipo (compartido cargas ↔ vehiculos)
--  3. cargas.tipo        : text CHECK → bigint FK a app_nom_tipo_carga
--  4. cargas.tipo_equipo : text libre → bigint FK a app_nom_tipo_equipo
--  5. cargas.id_tipo_vehiculo : FK muevete.vehiculos → muevete.vehicle_type
--  6. cargas.estado      : eliminar columna (gestionado por app_dat_estado_carga)
--  7. vehiculos.tipo_carroceria : text libre → bigint FK a app_nom_tipo_equipo
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. NOMENCLADOR: TIPO DE CARGA (FTL, LTL, etc.)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS muevete.app_nom_tipo_carga (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre      text NOT NULL,
  descripcion text,
  abreviacion text NOT NULL UNIQUE,
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- Seed inicial
INSERT INTO muevete.app_nom_tipo_carga (nombre, descripcion, abreviacion) VALUES
  ('Full Truckload',    'Carga completa que ocupa todo el camión',          'FTL'),
  ('Less Than Truckload', 'Carga parcial que comparte camión con otros envíos', 'LTL')
ON CONFLICT (abreviacion) DO NOTHING;

-- RLS
ALTER TABLE muevete.app_nom_tipo_carga ENABLE ROW LEVEL SECURITY;
CREATE POLICY "nomenclador_tipo_carga_lectura_todos"
  ON muevete.app_nom_tipo_carga FOR SELECT
  USING (activo = true);

-- ─────────────────────────────────────────────────────────────
-- 2. NOMENCLADOR: TIPO DE EQUIPO (compartido cargas + vehiculos)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS muevete.app_nom_tipo_equipo (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre      text NOT NULL,
  descripcion text,
  abreviacion text NOT NULL UNIQUE,
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- Seed inicial
INSERT INTO muevete.app_nom_tipo_equipo (nombre, descripcion, abreviacion) VALUES
  ('Furgón Seco',        'Caja cerrada para carga general seca',                   'DRY_VAN'),
  ('Flatbed',            'Plataforma abierta para carga sobredimensionada',         'FLATBED'),
  ('Refrigerado (Reefer)', 'Caja con control de temperatura para carga perecedera', 'REEFER'),
  ('Tanque',             'Cisterna para líquidos o gases',                          'TANKER'),
  ('Cortinas (Curtainsider)', 'Plataforma con lonas laterales, carga lateral',     'CURTAIN'),
  ('Volcadora (Tipper)', 'Caja basculante para graneles y escombros',               'TIPPER'),
  ('Cama Baja (Lowboy)', 'Semirremolque de bajo perfil para maquinaria pesada',    'LOWBOY'),
  ('Porta Vehículos',    'Transportador de automóviles en varios niveles',          'AUTOTRANSPORTER')
ON CONFLICT (abreviacion) DO NOTHING;

-- RLS
ALTER TABLE muevete.app_nom_tipo_equipo ENABLE ROW LEVEL SECURITY;
CREATE POLICY "nomenclador_tipo_equipo_lectura_todos"
  ON muevete.app_nom_tipo_equipo FOR SELECT
  USING (activo = true);

-- ─────────────────────────────────────────────────────────────
-- 3. TABLA cargas — migrar tipo: text → FK bigint
-- ─────────────────────────────────────────────────────────────

-- 3a. Agregar nueva columna FK
ALTER TABLE muevete.cargas
  ADD COLUMN IF NOT EXISTS tipo_carga_id bigint
    REFERENCES muevete.app_nom_tipo_carga(id);

-- 3b. Poblar tipo_carga_id a partir del valor text existente
UPDATE muevete.cargas c
SET tipo_carga_id = t.id
FROM muevete.app_nom_tipo_carga t
WHERE UPPER(c.tipo) = t.abreviacion;

-- 3c. Poner NOT NULL (todos los registros deben tener valor)
--     Si algún registro tiene tipo inesperado, asignar FTL por defecto
UPDATE muevete.cargas
SET tipo_carga_id = (SELECT id FROM muevete.app_nom_tipo_carga WHERE abreviacion = 'FTL')
WHERE tipo_carga_id IS NULL;

ALTER TABLE muevete.cargas
  ALTER COLUMN tipo_carga_id SET NOT NULL;

-- 3d. Eliminar columna text anterior y su CHECK constraint
ALTER TABLE muevete.cargas DROP COLUMN tipo;

-- ─────────────────────────────────────────────────────────────
-- 4. TABLA cargas — migrar tipo_equipo: text → FK bigint
-- ─────────────────────────────────────────────────────────────

-- 4a. Agregar nueva columna FK
ALTER TABLE muevete.cargas
  ADD COLUMN IF NOT EXISTS tipo_equipo_id bigint
    REFERENCES muevete.app_nom_tipo_equipo(id);

-- 4b. Poblar tipo_equipo_id a partir del texto existente (best effort)
UPDATE muevete.cargas c
SET tipo_equipo_id = t.id
FROM muevete.app_nom_tipo_equipo t
WHERE LOWER(c.tipo_equipo) = LOWER(t.abreviacion)
   OR LOWER(c.tipo_equipo) = LOWER(t.nombre);

-- 4c. Eliminar columna text anterior
ALTER TABLE muevete.cargas DROP COLUMN tipo_equipo;

-- ─────────────────────────────────────────────────────────────
-- 5. TABLA cargas — corregir FK id_tipo_vehiculo
--    Antes apuntaba a muevete.vehiculos(id) (incorrecto).
--    Ahora debe apuntar a muevete.vehicle_type(id),
--    igual que vehiculos.id_tipo_vehiculo.
-- ─────────────────────────────────────────────────────────────

-- 5a. Eliminar constraint incorrecto
ALTER TABLE muevete.cargas
  DROP CONSTRAINT IF EXISTS cargas_id_tipo_vehiculo_fkey;

-- 5b. Limpiar valores que no existan en vehicle_type
UPDATE muevete.cargas
SET id_tipo_vehiculo = NULL
WHERE id_tipo_vehiculo IS NOT NULL
  AND id_tipo_vehiculo NOT IN (SELECT id FROM muevete.vehicle_type);

-- 5c. Crear nuevo constraint correcto
ALTER TABLE muevete.cargas
  ADD CONSTRAINT cargas_id_tipo_vehiculo_fkey
    FOREIGN KEY (id_tipo_vehiculo)
    REFERENCES muevete.vehicle_type(id);

-- ─────────────────────────────────────────────────────────────
-- 6. TABLA cargas — eliminar columna estado
--    El estado se gestiona exclusivamente por app_dat_estado_carga
--    y se lee mediante la vista v_cargas_estado_actual.
-- ─────────────────────────────────────────────────────────────

-- NOTA: La función fn_cambiar_estado_carga y fn_marcar_carga_tomada
-- actualizan la columna estado en cargas como campo de cache rápido.
-- Si se elimina, esas funciones deben actualizarse para NO escribir
-- en cargas.estado. La vista v_cargas_estado_actual ya es la fuente
-- autoritativa del estado.
-- Por seguridad dejamos la columna pero la marcamos como deprecated
-- con un comentario. Para eliminarla ejecutar el bloque comentado
-- después de actualizar las RPCs.

COMMENT ON COLUMN muevete.cargas.estado IS
  'DEPRECATED: campo de cache. Fuente autoritativa: app_dat_estado_carga / v_cargas_estado_actual. '
  'Eliminar después de actualizar fn_cambiar_estado_carga y fn_marcar_carga_tomada para no escribir aquí.';

-- Para eliminar definitivamente (ejecutar DESPUÉS de actualizar las RPCs):
-- ALTER TABLE muevete.cargas DROP COLUMN estado;

-- ─────────────────────────────────────────────────────────────
-- 7. TABLA vehiculos — migrar tipo_carroceria: text → FK bigint
-- ─────────────────────────────────────────────────────────────

-- 7a. Agregar nueva columna FK
ALTER TABLE muevete.vehiculos
  ADD COLUMN IF NOT EXISTS tipo_equipo_id bigint
    REFERENCES muevete.app_nom_tipo_equipo(id);

-- 7b. Poblar tipo_equipo_id a partir del texto existente (best effort)
UPDATE muevete.vehiculos v
SET tipo_equipo_id = t.id
FROM muevete.app_nom_tipo_equipo t
WHERE LOWER(v.tipo_carroceria) = LOWER(t.abreviacion)
   OR LOWER(v.tipo_carroceria) = LOWER(t.nombre);

-- 7c. Mantener tipo_carroceria como campo legacy (no eliminar aún
--     para no romper código existente). Marcar deprecated.
COMMENT ON COLUMN muevete.vehiculos.tipo_carroceria IS
  'DEPRECATED: reemplazado por tipo_equipo_id (FK a app_nom_tipo_equipo). '
  'Eliminar después de migrar todos los reads/writes al nuevo campo.';

-- ─────────────────────────────────────────────────────────────
-- 8. ACTUALIZAR función fn_cambiar_estado_carga
--    Agregar soporte para leer tipo_carga_id en lugar de tipo
-- ─────────────────────────────────────────────────────────────
-- (No se modifica el cuerpo de fn_cambiar_estado_carga aquí
--  porque sólo escribe en estado + app_dat_estado_carga.
--  Al eliminar la columna estado en el futuro, habrá que
--  quitar la línea UPDATE cargas SET estado = ... de esa función.)

-- ─────────────────────────────────────────────────────────────
-- 9. VISTA v_cargas_con_nomencladores (nueva)
--    JOIN útil para leer cargas con los nombres de nomencladores
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW muevete.v_cargas_con_nomencladores AS
SELECT
  c.*,
  ntc.nombre         AS tipo_carga_nombre,
  ntc.abreviacion    AS tipo_carga_abreviacion,
  nte.nombre         AS tipo_equipo_nombre,
  nte.abreviacion    AS tipo_equipo_abreviacion,
  vt.tipo            AS vehicle_type_nombre,
  eca.estado_codigo  AS estado_actual
FROM muevete.cargas c
LEFT JOIN muevete.app_nom_tipo_carga  ntc ON ntc.id = c.tipo_carga_id
LEFT JOIN muevete.app_nom_tipo_equipo nte ON nte.id = c.tipo_equipo_id
LEFT JOIN muevete.vehicle_type        vt  ON vt.id  = c.id_tipo_vehiculo
LEFT JOIN LATERAL (
  SELECT estado_codigo
  FROM muevete.app_dat_estado_carga
  WHERE carga_id = c.id
  ORDER BY created_at DESC
  LIMIT 1
) eca ON true;
