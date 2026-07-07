-- =============================================================================
-- MIGRACIÓN 019: Solicitudes de activación / cambio de plan
-- Plataforma Muevete
-- =============================================================================
-- Flujo:
--   1. Usuario selecciona plan de pago y sube comprobante de transferencia.
--   2. Se crea una fila en solicitudes_plan con estado 'pendiente'.
--   3. El administrador revisa la evidencia, introduce el código de transferencia
--      (unique: evita que dos clientes usen la misma transferencia) y
--      aprueba o rechaza con observaciones.
--   4. Al aprobar, se actualiza/crea la suscripción activa del usuario.
-- =============================================================================

CREATE TABLE IF NOT EXISTS muevete.solicitudes_plan (
  id                    BIGSERIAL PRIMARY KEY,
  usuario_uuid          UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  plan_codigo           TEXT NOT NULL REFERENCES muevete.planes(codigo),

  -- 'pendiente' | 'aprobada' | 'rechazada'
  estado                TEXT NOT NULL DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente', 'aprobada', 'rechazada')),

  -- URL pública de la foto de evidencia de pago (Supabase Storage)
  evidencia_url         TEXT NOT NULL,

  -- Código de transferencia bancaria ingresado por el admin al aprobar.
  -- UNIQUE para evitar que la misma transferencia active múltiples planes.
  codigo_transferencia  TEXT UNIQUE,

  -- Notas / motivo del administrador (requerido para rechazar)
  observaciones         TEXT,

  -- Admin que procesó la solicitud
  admin_uuid            UUID REFERENCES auth.users(id),

  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_solicitudes_plan_usuario
  ON muevete.solicitudes_plan (usuario_uuid);

CREATE INDEX IF NOT EXISTS idx_solicitudes_plan_estado
  ON muevete.solicitudes_plan (estado);

COMMENT ON TABLE muevete.solicitudes_plan IS
  'Solicitudes de activación o cambio de plan de los usuarios. '
  'Requieren revisión manual del administrador con verificación del código de transferencia.';

COMMENT ON COLUMN muevete.solicitudes_plan.codigo_transferencia IS
  'Código bancario único de la transferencia. UNIQUE para prevenir reúso fraudulento.';

-- ─────────────────────────────────────────────────────────────────────────────
-- RLS
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE muevete.solicitudes_plan ENABLE ROW LEVEL SECURITY;

-- El usuario solo ve sus propias solicitudes
CREATE POLICY "solicitudes_plan_own_select" ON muevete.solicitudes_plan
  FOR SELECT TO authenticated
  USING (usuario_uuid = auth.uid());

-- Cualquier usuario autenticado puede insertar su propia solicitud
CREATE POLICY "solicitudes_plan_own_insert" ON muevete.solicitudes_plan
  FOR INSERT TO authenticated
  WITH CHECK (usuario_uuid = auth.uid());

-- Solo service_role actualiza (el admin opera con service_role o función SECURITY DEFINER)
CREATE POLICY "solicitudes_plan_service_update" ON muevete.solicitudes_plan
  FOR UPDATE TO service_role USING (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- Función: aprobar solicitud y activar suscripción
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION muevete.fn_aprobar_solicitud_plan(
  p_solicitud_id        BIGINT,
  p_admin_uuid          UUID,
  p_codigo_transferencia TEXT,
  p_observaciones       TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_usuario_uuid UUID;
  v_plan_codigo  TEXT;
  v_inicio       DATE := CURRENT_DATE;
  v_un_mes       DATE := CURRENT_DATE + interval '1 month';
  v_vencimiento  DATE;
BEGIN
  -- Obtener datos de la solicitud
  SELECT usuario_uuid, plan_codigo
  INTO v_usuario_uuid, v_plan_codigo
  FROM muevete.solicitudes_plan
  WHERE id = p_solicitud_id AND estado = 'pendiente';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Solicitud no encontrada o no está pendiente';
  END IF;

  -- Marcar solicitud como aprobada
  UPDATE muevete.solicitudes_plan
  SET estado                = 'aprobada',
      codigo_transferencia  = p_codigo_transferencia,
      observaciones         = p_observaciones,
      admin_uuid            = p_admin_uuid,
      updated_at            = now()
  WHERE id = p_solicitud_id;

  -- Cancelar suscripciones activas previas del usuario
  UPDATE muevete.suscripciones
  SET estado     = 'cancelada',
      updated_at = now()
  WHERE usuario_uuid = v_usuario_uuid
    AND estado = 'activa';

  -- Calcular vencimiento: próximo día 2 después de 1 mes
  v_vencimiento := muevete.fn_proximo_dia_2(v_un_mes);

  -- Crear nueva suscripción activa
  INSERT INTO muevete.suscripciones
    (usuario_uuid, plan_codigo, estado, inicio, vencimiento, renovacion_auto, notas)
  VALUES
    (v_usuario_uuid, v_plan_codigo, 'activa', v_inicio, v_vencimiento, true,
     'Activado por admin · solicitud #' || p_solicitud_id);
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Función: rechazar solicitud
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION muevete.fn_rechazar_solicitud_plan(
  p_solicitud_id  BIGINT,
  p_admin_uuid    UUID,
  p_observaciones TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE muevete.solicitudes_plan
  SET estado        = 'rechazada',
      observaciones = p_observaciones,
      admin_uuid    = p_admin_uuid,
      updated_at    = now()
  WHERE id = p_solicitud_id AND estado = 'pendiente';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Solicitud no encontrada o ya fue procesada';
  END IF;
END;
$$;

COMMENT ON FUNCTION muevete.fn_aprobar_solicitud_plan IS
  'Aprueba la solicitud, registra el código de transferencia y crea la suscripción activa.';

COMMENT ON FUNCTION muevete.fn_rechazar_solicitud_plan IS
  'Rechaza la solicitud con observaciones del administrador.';
