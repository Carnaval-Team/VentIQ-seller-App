-- Migration 002: Saved addresses for quick destinations + photo column on users
-- Run this against Supabase after 001_new_tables.sql

-- 1. Add photo_url column to muevete.users if not already present
--    (the 'image' column already exists; this adds a dedicated profile_photo column
--     so the image field can keep being the legacy one without breaking anything)
ALTER TABLE muevete.users
  ADD COLUMN IF NOT EXISTS photo_url text;

-- 2. Saved quick-access addresses (direcciones de acceso rápido)
CREATE TABLE IF NOT EXISTS muevete.direcciones_rapidas (
  id         bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  user_id    uuid NOT NULL,
  label      text NOT NULL,              -- e.g. "Casa", "Trabajo", "Gym"
  icon       text NOT NULL DEFAULT 'place', -- icon name hint for the app
  direccion  text NOT NULL,              -- human-readable address
  latitud    double precision NOT NULL,
  longitud   double precision NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT direcciones_rapidas_pkey PRIMARY KEY (id),
  CONSTRAINT direcciones_rapidas_user_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);

-- Index for fast per-user lookups
CREATE INDEX IF NOT EXISTS idx_direcciones_rapidas_user
  ON muevete.direcciones_rapidas (user_id);

-- RLS
ALTER TABLE muevete.direcciones_rapidas ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own addresses"
  ON muevete.direcciones_rapidas
  FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Grant to authenticated / service_role
GRANT ALL ON muevete.direcciones_rapidas TO authenticated, service_role;
GRANT USAGE, SELECT ON SEQUENCE muevete.direcciones_rapidas_id_seq TO authenticated, service_role;
