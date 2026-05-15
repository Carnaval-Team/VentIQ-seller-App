-- =============================================================================
-- MIGRACIÓN 018: Prioridad en cargas + Planes gratis + Tabla suscripciones
-- Plataforma Muevete
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Campo prioridad en muevete.cargas
--    Valores: 'normal' | 'alta' | 'urgente'
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE muevete.cargas
  ADD COLUMN IF NOT EXISTS prioridad text NOT NULL DEFAULT 'normal'
    CHECK (prioridad IN ('normal', 'alta', 'urgente'));

COMMENT ON COLUMN muevete.cargas.prioridad IS
  'Prioridad asignada por el shipper al crear la carga: normal | alta | urgente';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Corregir/reemplazar planes con los precios definitivos
--    Carrier  : gratis (0) + Básico (20) + PRO (40)
--    Dispatcher: gratis (0) + Dispatcher (150)
--    Shipper  : gratis (0) + Shipper (50)
--    cliente_pasajero: sin planes de carga (no aplica aquí)
-- ─────────────────────────────────────────────────────────────────────────────

-- Desactivar planes anteriores que serán reemplazados
UPDATE muevete.planes
  SET activo = false
WHERE codigo IN (
  'shipper_basico','shipper_profesional','shipper_empresarial',
  'carrier_basico','carrier_profesional',
  'dispatcher_basico','dispatcher_profesional'
);

-- Planes GRATIS (primer mes) — uno por tipo
INSERT INTO muevete.planes
  (codigo, tipo_usuario, nombre, precio_mensual,
   cargas_mes_max, contactos_mes_max,
   matching_auto, matching_diario_max,
   escrow_comision, escrow_incluido,
   ventana_exclusiva_horas, multi_usuarios,
   dashboard_nivel, soporte_nivel, activo)
VALUES
  ('carrier_gratis',    'carrier',    'Gratis',      0,   5, 5,  false, null, null, false, null, 1, 'ninguno', 'email', true),
  ('dispatcher_gratis', 'dispatcher', 'Gratis',      0,  10, 5,  false, null, null, false, null, 1, 'ninguno', 'email', true),
  ('shipper_gratis',    'shipper',    'Gratis',      0,   5, 5,  false, null, null, false, null, 1, 'ninguno', 'email', true)
ON CONFLICT (codigo) DO UPDATE
  SET activo = true,
      precio_mensual = EXCLUDED.precio_mensual,
      nombre = EXCLUDED.nombre;

-- Plan carrier_basico: 20 USD/mes
INSERT INTO muevete.planes
  (codigo, tipo_usuario, nombre, precio_mensual,
   cargas_mes_max, contactos_mes_max,
   matching_auto, matching_diario_max,
   escrow_comision, escrow_incluido,
   ventana_exclusiva_horas, multi_usuarios,
   dashboard_nivel, soporte_nivel, activo)
VALUES
  ('carrier_basico_v2', 'carrier', 'Básico', 20,
   50, 30, false, null, null, false, null, 1, 'basico', 'email', true)
ON CONFLICT (codigo) DO UPDATE
  SET activo = true, precio_mensual = EXCLUDED.precio_mensual;

-- Plan carrier_pro: 40 USD/mes
INSERT INTO muevete.planes
  (codigo, tipo_usuario, nombre, precio_mensual,
   cargas_mes_max, contactos_mes_max,
   matching_auto, matching_diario_max,
   escrow_comision, escrow_incluido,
   ventana_exclusiva_horas, multi_usuarios,
   dashboard_nivel, soporte_nivel, activo)
VALUES
  ('carrier_pro', 'carrier', 'PRO', 40,
   null, null, true, 20, null, false, 2, 3, 'avanzado', 'chat', true)
ON CONFLICT (codigo) DO UPDATE
  SET activo = true, precio_mensual = EXCLUDED.precio_mensual;

-- Plan dispatcher: 150 USD/mes
INSERT INTO muevete.planes
  (codigo, tipo_usuario, nombre, precio_mensual,
   cargas_mes_max, contactos_mes_max,
   matching_auto, matching_diario_max,
   escrow_comision, escrow_incluido,
   ventana_exclusiva_horas, multi_usuarios,
   dashboard_nivel, soporte_nivel, activo)
VALUES
  ('dispatcher_plan', 'dispatcher', 'Dispatcher', 150,
   null, null, true, null, null, false, null, 10, 'avanzado', 'chat', true)
ON CONFLICT (codigo) DO UPDATE
  SET activo = true, precio_mensual = EXCLUDED.precio_mensual;

-- Plan shipper: 50 USD/mes
INSERT INTO muevete.planes
  (codigo, tipo_usuario, nombre, precio_mensual,
   cargas_mes_max, contactos_mes_max,
   matching_auto, matching_diario_max,
   escrow_comision, escrow_incluido,
   ventana_exclusiva_horas, multi_usuarios,
   dashboard_nivel, soporte_nivel, activo)
VALUES
  ('shipper_plan', 'shipper', 'Shipper', 50,
   null, null, true, null, null, false, null, 3, 'avanzado', 'chat', true)
ON CONFLICT (codigo) DO UPDATE
  SET activo = true, precio_mensual = EXCLUDED.precio_mensual;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Tabla muevete.suscripciones
--    Ciclo de facturación: cierra el día 2 de cada mes.
--    Al registrarse, el usuario inicia en plan "gratis" con duración mínima
--    de 1 mes; si ese mes no termina en día 2, se extiende hasta el próximo día 2.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS muevete.suscripciones (
  id                  BIGSERIAL PRIMARY KEY,
  usuario_uuid        UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  plan_codigo         TEXT NOT NULL REFERENCES muevete.planes(codigo),
  -- 'activa' | 'vencida' | 'cancelada' | 'pendiente_pago'
  estado              TEXT NOT NULL DEFAULT 'activa'
    CHECK (estado IN ('activa', 'vencida', 'cancelada', 'pendiente_pago')),
  inicio              DATE NOT NULL,
  vencimiento         DATE NOT NULL,
  renovacion_auto     BOOLEAN NOT NULL DEFAULT true,
  notas               TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_suscripciones_usuario
  ON muevete.suscripciones (usuario_uuid);
CREATE INDEX IF NOT EXISTS idx_suscripciones_estado
  ON muevete.suscripciones (estado);

-- RLS
ALTER TABLE muevete.suscripciones ENABLE ROW LEVEL SECURITY;

-- El usuario solo ve su propia suscripción
CREATE POLICY "suscripcion_own_select" ON muevete.suscripciones
  FOR SELECT TO authenticated
  USING (usuario_uuid = auth.uid());

-- Solo backend (service_role) puede insertar / actualizar
CREATE POLICY "suscripcion_service_insert" ON muevete.suscripciones
  FOR INSERT TO service_role WITH CHECK (true);

CREATE POLICY "suscripcion_service_update" ON muevete.suscripciones
  FOR UPDATE TO service_role USING (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Función helper: próximo día 2 desde una fecha dada
--    Si hoy es antes del día 2 del mes actual → day 2 del mes actual
--    Si hoy es el día 2 o después            → day 2 del mes siguiente
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION muevete.fn_proximo_dia_2(desde DATE)
RETURNS DATE
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  dia2_este_mes DATE;
  dia2_siguiente DATE;
BEGIN
  dia2_este_mes  := date_trunc('month', desde)::date + interval '1 day'; -- día 2
  dia2_siguiente := date_trunc('month', desde + interval '1 month')::date + interval '1 day';
  IF desde < dia2_este_mes THEN
    RETURN dia2_este_mes;
  ELSE
    RETURN dia2_siguiente;
  END IF;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Función: crear suscripción gratis al registrarse
--    Llamar después de crear el perfil del usuario.
--    La duración mínima es 1 mes; el vencimiento se ajusta al próximo día 2
--    que sea al menos 1 mes después del inicio.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION muevete.fn_crear_suscripcion_gratis(
  p_usuario_uuid UUID,
  p_tipo_usuario TEXT   -- 'shipper' | 'carrier' | 'dispatcher'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_inicio       DATE := CURRENT_DATE;
  v_un_mes       DATE := v_inicio + interval '1 month';
  v_vencimiento  DATE;
  v_plan_codigo  TEXT;
BEGIN
  -- Determinar código del plan gratis según tipo
  v_plan_codigo := p_tipo_usuario || '_gratis';

  -- El vencimiento es el próximo día 2 que sea >= (inicio + 1 mes)
  v_vencimiento := muevete.fn_proximo_dia_2(v_un_mes);

  -- Insertar solo si no existe ya una suscripción activa
  INSERT INTO muevete.suscripciones
    (usuario_uuid, plan_codigo, estado, inicio, vencimiento, renovacion_auto)
  VALUES
    (p_usuario_uuid, v_plan_codigo, 'activa', v_inicio, v_vencimiento, false)
  ON CONFLICT DO NOTHING;
END;
$$;

COMMENT ON FUNCTION muevete.fn_crear_suscripcion_gratis IS
  'Crea la suscripción gratuita inicial al registrarse. Vence el próximo día 2 después de cumplir 1 mes.';
