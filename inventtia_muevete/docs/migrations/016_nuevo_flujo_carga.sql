-- ============================================================
-- Migración 016: Flujo simplificado de carga sin escrow
-- ============================================================
-- Nuevo flujo:
--   publicada → tomada (shipper asigna carrier) →
--   completada_carrier (carrier confirma) →
--   completada (shipper confirma)
--
-- También se eliminan los estados relacionados con escrow
-- del catálogo (marcándolos inactivos).
-- ============================================================

-- ── 1. Agregar nuevos estados al nomenclador ──────────────────
INSERT INTO muevete.app_nom_estado (codigo, nombre, descripcion, orden) VALUES
  ('tomada',             'Tomada',             'Shipper asignó un carrier; oculta para otros carriers', 4),
  ('completada_carrier', 'Completada (Carrier)', 'Carrier confirmó que la entrega fue realizada',        6)
ON CONFLICT (codigo) DO UPDATE
  SET nombre      = EXCLUDED.nombre,
      descripcion = EXCLUDED.descripcion,
      orden       = EXCLUDED.orden,
      activo      = true;

-- ── 2. Ajustar orden de estados existentes ────────────────────
-- Nuevo orden del flujo:
--   1 publicada → 4 tomada → 5 en_transito → 6 completada_carrier → 7 completada
--   (en_matching y ofertada quedan disponibles pero son opcionales en el nuevo flujo)
UPDATE muevete.app_nom_estado SET orden = 5  WHERE codigo = 'en_transito';
UPDATE muevete.app_nom_estado SET orden = 7  WHERE codigo = 'entregada';
UPDATE muevete.app_nom_estado SET orden = 8  WHERE codigo = 'completada';
UPDATE muevete.app_nom_estado SET orden = 9  WHERE codigo = 'cancelada';
UPDATE muevete.app_nom_estado SET orden = 10 WHERE codigo = 'disputa';

-- ── 3. Marcar estados de escrow/disputa como inactivos ────────
-- (disputa dependía del escrow; lo dejamos inactivo)
UPDATE muevete.app_nom_estado SET activo = false WHERE codigo = 'disputa';

-- ── 4. Agregar columna carrier_uuid a cargas para vínculo rápido ──
-- El shipper puede marcar la carga como tomada enlazando al UUID
-- del driver (carrier) sin necesidad de que éste haya hecho oferta.
ALTER TABLE muevete.cargas
  ADD COLUMN IF NOT EXISTS carrier_uuid uuid REFERENCES auth.users(id);

-- ── 5. Función RPC marcar_carga_tomada ───────────────────────
-- El shipper llama a esta función para:
--   a) asignar el carrier (driver_id + uuid)
--   b) cambiar estado a 'tomada' (oculta de getCargasDisponibles)
CREATE OR REPLACE FUNCTION muevete.fn_marcar_carga_tomada(
  p_carga_id      bigint,
  p_carrier_driver_id bigint,
  p_carrier_uuid  uuid,
  p_usuario_uuid  uuid DEFAULT NULL,
  p_motivo        text DEFAULT 'Carga tomada por shipper'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Actualizar carrier asignado en cargas
  UPDATE muevete.cargas
  SET carrier_driver_id = p_carrier_driver_id,
      carrier_uuid      = p_carrier_uuid,
      estado            = 'tomada',
      updated_at        = now()
  WHERE id = p_carga_id;

  -- Registrar en bitácora
  INSERT INTO muevete.app_dat_estado_carga
    (carga_id, estado_codigo, usuario_uuid, driver_id, motivo)
  VALUES
    (p_carga_id, 'tomada', p_usuario_uuid, p_carrier_driver_id, p_motivo);
END;
$$;

-- ── 6. Actualizar getCargasDisponibles: excluir 'tomada' ──────
-- La consulta de cargas disponibles ya filtra por estado IN ('publicada','en_matching','ofertada').
-- 'tomada' no está en esa lista, así que queda automáticamente oculta.
-- No se requiere cambio en código Dart (getCargasDisponibles ya tiene el filtro correcto).

-- ── 7. Actualizar RLS de app_dat_estado_carga para carrier_uuid ──
-- Añadir política alternativa: el carrier puede ver la bitácora por carrier_uuid
DROP POLICY IF EXISTS "dat_estado_select_participantes" ON muevete.app_dat_estado_carga;

CREATE POLICY "dat_estado_select_participantes" ON muevete.app_dat_estado_carga
  FOR SELECT TO authenticated
  USING (
    -- El shipper de la carga
    EXISTS (
      SELECT 1 FROM muevete.cargas c
      WHERE c.id = carga_id
        AND c.shipper_id = auth.uid()
    )
    OR
    -- El carrier asignado por driver_id
    EXISTS (
      SELECT 1 FROM muevete.cargas c
      JOIN  muevete.drivers d ON d.id = c.carrier_driver_id
      WHERE c.id = carga_id
        AND d.uuid = auth.uid()
    )
    OR
    -- El carrier asignado por carrier_uuid directo
    EXISTS (
      SELECT 1 FROM muevete.cargas c
      WHERE c.id = carga_id
        AND c.carrier_uuid = auth.uid()
    )
  );
