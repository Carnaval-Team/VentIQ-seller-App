-- ============================================================
-- Enable Supabase Realtime on muevete schema tables
-- Run this in the Supabase SQL editor (once per project)
-- ============================================================

-- 1. Add tables to the realtime publication
--    (supabase_realtime is the default Supabase publication)
ALTER PUBLICATION supabase_realtime
  ADD TABLE
    muevete.solicitudes_transporte,
    muevete.ofertas_chofer,
    muevete.viajes,
    muevete.place;

-- ============================================================
-- 2. (Optional) Enable Row Level Security on all tables
--    so that Realtime only broadcasts rows the user can read.
--    Remove or adjust policies to match your auth rules.
-- ============================================================

-- solicitudes_transporte: clients see their own, drivers see pending/active ones
ALTER TABLE muevete.solicitudes_transporte ENABLE ROW LEVEL SECURITY;

CREATE POLICY "clients_own_solicitudes" ON muevete.solicitudes_transporte
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "drivers_see_solicitudes" ON muevete.solicitudes_transporte
  FOR SELECT USING (true);   -- adjust to restrict by area/estado if needed

-- ofertas_chofer: drivers see their own offers, clients see offers for their solicitud
ALTER TABLE muevete.ofertas_chofer ENABLE ROW LEVEL SECURITY;

CREATE POLICY "drivers_own_ofertas" ON muevete.ofertas_chofer
  FOR ALL USING (
    driver_id IN (
      SELECT id FROM muevete.drivers WHERE uuid = auth.uid()
    )
  );

CREATE POLICY "clients_see_their_ofertas" ON muevete.ofertas_chofer
  FOR SELECT USING (
    solicitud_id IN (
      SELECT id FROM muevete.solicitudes_transporte WHERE user_id = auth.uid()
    )
  );

-- viajes: driver and client can see their own viaje
ALTER TABLE muevete.viajes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "driver_own_viajes" ON muevete.viajes
  FOR ALL USING (
    driver_id IN (
      SELECT id FROM muevete.drivers WHERE uuid = auth.uid()
    )
  );

CREATE POLICY "client_own_viajes" ON muevete.viajes
  FOR SELECT USING (auth.uid()::text = "user");

-- place: anyone authenticated can read driver positions
ALTER TABLE muevete.place ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated_read_place" ON muevete.place
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "drivers_upsert_own_place" ON muevete.place
  FOR ALL USING (
    driver IN (
      SELECT id FROM muevete.drivers WHERE uuid = auth.uid()
    )
  );

-- ============================================================
-- 3. Verify publication includes the tables
-- ============================================================
SELECT schemaname, tablename
FROM pg_publication_tables
WHERE pubname = 'supabase_realtime'
  AND schemaname = 'muevete';
