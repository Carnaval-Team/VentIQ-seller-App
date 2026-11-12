-- ============================================================================
-- 035_taxi_vehiculos_catalogo.sql
-- Catálogo de vehículos ordenado + capacidad de pasajeros.
--
-- ANEXO DE DISEÑO: docs/plan-taxi-precio-fijo/09-identidad-y-vehiculos.md §3
--
-- PRERREQUISITOS
--   · 030_baseline_sync_produccion.sql  (NO se redefine nada suyo)
--   · 031_taxi_zonas_tarifas.sql        (zonas, config de tarifas, solicitudes)
--   · 032/033/034                       (funciones de zona, seed, RLS de tarifas)
--
-- QUÉ HACE
--   1. vehicle_type: orden, pasajeros_max, nombre_ui (etiqueta visible).
--   2. Catálogo visible: Auto, Minivan, Microbús, Moto, Triciclo Eléctrico.
--   3. Oculta bicicleta y camioneta (status=false). NO borra filas.
--   4. Capacidad efectiva por vehículo: fn_capacidad_vehiculo().
--   5. solicitudes_transporte.pasajeros (+ check).
--   6. Vista v_catalogo_vehiculos para la app.
--
-- D-2 (corrección del Lead)
--   El seed de orden/nombre/capacidad se aplica SÓLO donde `orden IS NULL`.
--   Si el superadmin ya reordenó y este archivo se re-ejecuta, NO se pisa nada.
--   `orden` se añade NULLABLE, se siembra, se rellena lo que quede NULL y sólo
--   al final se pone NOT NULL + DEFAULT.
--
-- IDEMPOTENCIA
--   CREATE TABLE/INDEX/VIEW .... IF NOT EXISTS / OR REPLACE
--   ALTER TABLE ADD COLUMN ...... IF NOT EXISTS
--   ADD CONSTRAINT .............. guardado con pg_constraint
--   Seed ........................ UPDATE ... WHERE orden IS NULL
--   Re-ejecutar dos veces no debe fallar ni alterar el orden configurado.
--
-- NO EJECUTAR CONTRA SUPABASE DESDE ESTE ENTORNO (sólo se entrega el archivo).
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. vehicle_type: columnas del catálogo
--    `tipo` es la CLAVE funcional (solicitudes.tipo_vehiculo, reglas de tarifa,
--    vehicle_type_service). NO se renombra: sólo cambia la ETIQUETA visible.
-- ----------------------------------------------------------------------------
ALTER TABLE muevete.vehicle_type
  ADD COLUMN IF NOT EXISTS orden         smallint,               -- nullable de momento (D-2)
  ADD COLUMN IF NOT EXISTS pasajeros_max smallint NOT NULL DEFAULT 4,
  ADD COLUMN IF NOT EXISTS nombre_ui     text;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'vehicle_type_orden_chk'
                    AND conrelid = 'muevete.vehicle_type'::regclass) THEN
    ALTER TABLE muevete.vehicle_type
      ADD CONSTRAINT vehicle_type_orden_chk
      CHECK (orden IS NULL OR orden BETWEEN 0 AND 9999) NOT VALID;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'vehicle_type_pasajeros_chk'
                    AND conrelid = 'muevete.vehicle_type'::regclass) THEN
    ALTER TABLE muevete.vehicle_type
      ADD CONSTRAINT vehicle_type_pasajeros_chk
      CHECK (pasajeros_max BETWEEN 1 AND 20) NOT VALID;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS vehicle_type_catalogo_idx
  ON muevete.vehicle_type (orden, id)
  WHERE coalesce(status, true);

COMMENT ON COLUMN muevete.vehicle_type.orden IS
  'orden del catálogo en la app del cliente. MENOR = primero. Configurable en superadmin. 10,20,30,40,50 (equivale a 1º..5º con holgura para reordenar).';
COMMENT ON COLUMN muevete.vehicle_type.pasajeros_max IS
  'Máximo de pasajeros que este TIPO admite. El cliente filtra por pasajeros_max >= pasajeros elegidos.';
COMMENT ON COLUMN muevete.vehicle_type.nombre_ui IS
  'Etiqueta visible. Permite renombrar (tuktuk -> "Triciclo Eléctrico") sin tocar la clave tipo.';

-- ----------------------------------------------------------------------------
-- 2. Seed del catálogo — SÓLO donde orden IS NULL (D-2)
--    Si el admin ya configuró el orden, este UPDATE no toca su fila.
-- ----------------------------------------------------------------------------
UPDATE muevete.vehicle_type AS vt SET
  nombre_ui     = v.nombre_ui,
  orden         = v.orden,
  pasajeros_max = v.pasajeros_max,
  status        = v.status
FROM (VALUES
  -- tipo        nombre_ui               orden  pasajeros_max  status
  ('auto',      'Auto',                    10,   4,             true),
  ('minivan',   'Minivan',                 20,   7,             true),
  ('microbus',  'Microbús',                30,  15,             true),
  ('moto',      'Moto',                    40,   1,             true),
  ('tuktuk',    'Triciclo Eléctrico',      50,   2,             true),
  -- Ocultos, NO borrados: hay históricos y FKs
  ('camioneta', 'Camioneta',              900,   5,             false),
  ('bicicleta', 'Bicicleta',              910,   1,             false)
) AS v(tipo, nombre_ui, orden, pasajeros_max, status)
WHERE lower(vt.tipo) = v.tipo
  AND vt.orden IS NULL;          -- ← D-2: no pisar lo que el admin ya ordenó

-- Tipos no listados (presentes en prod y no contemplados arriba):
-- se les da etiqueta legible y una posición al final, sin tocar los sembrados.
UPDATE muevete.vehicle_type
   SET nombre_ui     = coalesce(nombre_ui, initcap(tipo)),
       orden         = 500,
       pasajeros_max = coalesce(pasajeros_max, 4)
 WHERE orden IS NULL
   AND tipo IS NOT NULL;

-- Cierre: garantizar que ninguna fila queda sin orden y fijar el contrato
UPDATE muevete.vehicle_type SET orden = 500 WHERE orden IS NULL;

ALTER TABLE muevete.vehicle_type ALTER COLUMN orden SET DEFAULT 100;
ALTER TABLE muevete.vehicle_type ALTER COLUMN orden SET NOT NULL;

-- ----------------------------------------------------------------------------
-- 3. Capacidad efectiva de un vehículo registrado
--    Prioridad: capacidad_int > capacidad (texto numérico) > pasajeros_max del tipo.
--    INTERNA: no se expone a authenticated (la usan las RPC de toma/disponibles).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION muevete.fn_capacidad_vehiculo(p_vehiculo_id bigint)
RETURNS smallint
LANGUAGE sql STABLE
SET search_path = muevete, pg_temp
AS $$
  SELECT least(20, greatest(1, coalesce(
      veh.capacidad_int,
      CASE WHEN veh.capacidad ~ '^[0-9]{1,2}$' THEN veh.capacidad::integer END,
      vt.pasajeros_max,
      1
  )))::smallint
  FROM muevete.vehiculos veh
  LEFT JOIN muevete.vehicle_type vt ON vt.id = veh.id_tipo_vehiculo
  WHERE veh.id = p_vehiculo_id;
$$;

REVOKE ALL ON FUNCTION muevete.fn_capacidad_vehiculo(bigint)
  FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION muevete.fn_capacidad_vehiculo(bigint) IS
  'INTERNA. Capacidad efectiva de un vehículo (capacidad_int > capacidad parseada > pasajeros_max del tipo).';

-- Backfill de capacidad_int desde el texto libre donde sea inequívoco
UPDATE muevete.vehiculos
   SET capacidad_int = capacidad::integer
 WHERE capacidad_int IS NULL
   AND capacidad ~ '^[0-9]{1,2}$'
   AND capacidad::integer BETWEEN 1 AND 20;

-- ----------------------------------------------------------------------------
-- 4. solicitudes_transporte.pasajeros
-- ----------------------------------------------------------------------------
ALTER TABLE muevete.solicitudes_transporte
  ADD COLUMN IF NOT EXISTS pasajeros smallint NOT NULL DEFAULT 1;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'solicitudes_pasajeros_chk'
                    AND conrelid = 'muevete.solicitudes_transporte'::regclass) THEN
    ALTER TABLE muevete.solicitudes_transporte
      ADD CONSTRAINT solicitudes_pasajeros_chk
      CHECK (pasajeros BETWEEN 1 AND 20) NOT VALID;
  END IF;
END $$;

COMMENT ON COLUMN muevete.solicitudes_transporte.pasajeros IS
  'Cantidad de pasajeros declarada por el cliente. Snapshot; validada contra pasajeros_max del tipo y contra la capacidad del vehículo del chofer.';

CREATE INDEX IF NOT EXISTS solicitudes_pasajeros_idx
  ON muevete.solicitudes_transporte (pasajeros)
  WHERE estado = 'pendiente';

-- ----------------------------------------------------------------------------
-- 5. Vista de catálogo para la app (fuente única de orden / etiqueta / filtro)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW muevete.v_catalogo_vehiculos AS
SELECT
  vt.id,
  lower(vt.tipo)                            AS tipo,
  coalesce(vt.nombre_ui, initcap(vt.tipo))  AS nombre,
  vt.orden,
  vt.pasajeros_max,
  vt.categoria,
  true                                      AS activo
FROM muevete.vehicle_type vt
WHERE coalesce(vt.status, true);

COMMENT ON VIEW muevete.v_catalogo_vehiculos IS
  'Catálogo visible en la app del cliente: ya ordenado y con etiqueta UI. Sólo tipos con status=true.';

REVOKE ALL ON muevete.v_catalogo_vehiculos FROM anon;
GRANT SELECT ON muevete.v_catalogo_vehiculos TO authenticated;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN (ejecutar a mano; NO forma parte de la migración)
-- ============================================================================
-- 1) Catálogo visible (esperado: 5 filas en el orden Auto → Triciclo):
--   SELECT orden, tipo, nombre, pasajeros_max
--     FROM muevete.v_catalogo_vehiculos
--    ORDER BY orden;
--      -- 10 auto Auto 4 | 20 minivan Minivan 7 | 30 microbus Microbús 15
--      -- 40 moto Moto 1 | 50 tuktuk Triciclo Eléctrico 2
--
-- 2) Ocultos pero presentes (esperado: 2 filas con status=false):
--   SELECT tipo, status, orden FROM muevete.vehicle_type
--    WHERE lower(tipo) IN ('bicicleta','camioneta');
--
-- 3) Orden configurable por el admin: cambiar el orden de Moto a 5 y
--    re-ejecutar 035; el valor debe seguir siendo 5 (D-2):
--   UPDATE muevete.vehicle_type SET orden = 5 WHERE lower(tipo) = 'moto';
--   -- (re-ejecutar este archivo)
--   SELECT orden FROM muevete.vehicle_type WHERE lower(tipo) = 'moto';  -- 5
--
-- 4) Capacidad efectiva:
--   SELECT muevete.fn_capacidad_vehiculo(<vehiculo_id>);
--   -- 4 si capacidad_int=4; 6 si capacidad='6'; si no, pasajeros_max del tipo
--
-- 5) Helpers no expuestos:
--   SELECT has_function_privilege('authenticated',
--     'muevete.fn_capacidad_vehiculo(bigint)', 'EXECUTE');   -- false
--
-- 6) solicitudes.pasajeros:
--   SELECT column_name, data_type, column_default
--     FROM information_schema.columns
--    WHERE table_schema='muevete' AND table_name='solicitudes_transporte'
--      AND column_name='pasajeros';                            -- smallint, 1
--
-- 7) Idempotencia: re-ejecutar 035 completo no falla y no reordena nada.
-- ============================================================================

-- ============================================================================
-- DOWN (documentado; NO ejecutar en despliegue normal)
-- ============================================================================
-- BEGIN;
-- REVOKE ALL ON muevete.v_catalogo_vehiculos FROM authenticated;
-- DROP VIEW IF EXISTS muevete.v_catalogo_vehiculos;
-- DROP FUNCTION IF EXISTS muevete.fn_capacidad_vehiculo(bigint);
-- DROP INDEX IF EXISTS muevete.solicitudes_pasajeros_idx;
-- ALTER TABLE muevete.solicitudes_transporte
--   DROP CONSTRAINT IF EXISTS solicitudes_pasajeros_chk,
--   DROP COLUMN IF EXISTS pasajeros;
-- DROP INDEX IF EXISTS muevete.vehicle_type_catalogo_idx;
-- ALTER TABLE muevete.vehicle_type
--   DROP CONSTRAINT IF EXISTS vehicle_type_orden_chk,
--   DROP CONSTRAINT IF EXISTS vehicle_type_pasajeros_chk,
--   DROP COLUMN IF EXISTS nombre_ui,
--   DROP COLUMN IF EXISTS pasajeros_max,
--   DROP COLUMN IF EXISTS orden;
-- -- Los valores de status que se ocultaron NO se revierten automáticamente:
-- -- volver a mostrarlos es una decisión de negocio (UPDATE ... SET status=true).
-- COMMIT;
-- ============================================================================