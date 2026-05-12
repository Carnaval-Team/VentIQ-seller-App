-- Migration 013: Create muevete.planes table
-- Run this in Supabase SQL editor (schema: muevete)

CREATE TABLE IF NOT EXISTS muevete.planes (
  id                      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo                  text UNIQUE NOT NULL,
  tipo_usuario            text NOT NULL CHECK (tipo_usuario IN ('shipper', 'carrier', 'dispatcher')),
  nombre                  text NOT NULL,
  precio_mensual          numeric NOT NULL DEFAULT 0,
  cargas_mes_max          integer,             -- NULL = ilimitado
  contactos_mes_max       integer,             -- NULL = ilimitado
  matching_auto           boolean NOT NULL DEFAULT false,
  matching_diario_max     integer,             -- NULL = ilimitado
  escrow_comision         numeric,             -- porcentaje (ej: 3.0)
  escrow_incluido         boolean NOT NULL DEFAULT false,
  verificacion_mc         boolean NOT NULL DEFAULT false,
  alertas_push            boolean NOT NULL DEFAULT false,
  ventana_exclusiva_horas integer,
  gps_basico              boolean NOT NULL DEFAULT false,
  gps_avanzado            boolean NOT NULL DEFAULT false,
  eld_integrado           boolean NOT NULL DEFAULT false,
  multi_usuarios          integer NOT NULL DEFAULT 1,
  api_acceso              boolean NOT NULL DEFAULT false,
  factoraje               boolean NOT NULL DEFAULT false,
  dashboard_nivel         text NOT NULL DEFAULT 'ninguno' CHECK (dashboard_nivel IN ('ninguno','basico','avanzado')),
  soporte_nivel           text NOT NULL DEFAULT 'email' CHECK (soporte_nivel IN ('email','chat','telefono')),
  soporte_sla_h           integer,
  activo                  boolean NOT NULL DEFAULT true,
  created_at              timestamptz NOT NULL DEFAULT now()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Seed: Planes para SHIPPER
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO muevete.planes
  (codigo, tipo_usuario, nombre, precio_mensual, cargas_mes_max, contactos_mes_max,
   matching_auto, matching_diario_max, escrow_comision, escrow_incluido,
   ventana_exclusiva_horas, multi_usuarios, dashboard_nivel, soporte_nivel)
VALUES
  ('shipper_basico',      'shipper', 'Básico',      0,   5,    10,  false, null, 3.0, false, null, 1, 'ninguno', 'email'),
  ('shipper_profesional', 'shipper', 'Profesional', 49,  30,   null, true,  5,   2.0, true,  2,    3, 'basico',  'chat'),
  ('shipper_empresarial', 'shipper', 'Empresarial', 149, null, null, true,  null,1.5, true,  6,    10,'avanzado','telefono')
ON CONFLICT (codigo) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- Seed: Planes para CARRIER
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO muevete.planes
  (codigo, tipo_usuario, nombre, precio_mensual, cargas_mes_max,
   verificacion_mc, escrow_incluido, gps_avanzado, alertas_push, dashboard_nivel, soporte_nivel)
VALUES
  ('carrier_basico',       'carrier', 'Básico',       0,  10,  false, false, false, false, 'basico',  'email'),
  ('carrier_profesional',  'carrier', 'Profesional',  39, null, true,  true,  true,  true,  'avanzado','chat')
ON CONFLICT (codigo) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- Seed: Planes para DISPATCHER
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO muevete.planes
  (codigo, tipo_usuario, nombre, precio_mensual, multi_usuarios,
   factoraje, api_acceso, gps_avanzado, eld_integrado, dashboard_nivel, soporte_nivel)
VALUES
  ('dispatcher_starter', 'dispatcher', 'Starter', 79,  5,  false, false, false, false, 'basico',  'chat'),
  ('dispatcher_pro',     'dispatcher', 'Pro',     199, 20, true,  true,  true,  true,  'avanzado','telefono')
ON CONFLICT (codigo) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- RLS: solo lectura pública (cualquier usuario autenticado puede ver los planes)
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE muevete.planes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "planes_select_authenticated"
  ON muevete.planes FOR SELECT
  TO authenticated
  USING (activo = true);
