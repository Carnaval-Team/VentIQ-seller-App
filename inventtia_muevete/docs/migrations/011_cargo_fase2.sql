-- ============================================================
-- Migration 011 – Cargo Fase 2: weight unit + loading hours
-- Schema: muevete  |  Table: muevete.cargas
-- Run in Supabase SQL editor or psql
-- ============================================================

ALTER TABLE muevete.cargas
  ADD COLUMN IF NOT EXISTS unidad_peso    TEXT    DEFAULT 'kg'
    CHECK (unidad_peso IN ('kg', 'tonelada')),
  ADD COLUMN IF NOT EXISTS horas_carga    NUMERIC(4,1),
  ADD COLUMN IF NOT EXISTS horas_descarga NUMERIC(4,1);

-- Optional index to support filtering by unit
CREATE INDEX IF NOT EXISTS idx_cargas_unidad_peso ON muevete.cargas (unidad_peso);
