-- Enable RLS on paradas_viaje if not already enabled
ALTER TABLE muevete.paradas_viaje ENABLE ROW LEVEL SECURITY;

-- Allow drivers to manage their own stops
CREATE POLICY "Drivers can manage their own stops" ON muevete.paradas_viaje
FOR ALL
TO authenticated
USING (auth.uid()::text IN (
    SELECT u.uuid FROM muevete.users u 
    INNER JOIN muevete.drivers d ON d.user_id = u.id 
    WHERE d.id = driver_id
));

-- Allow clients to read stops for their own trips
-- This policy allows a user to SELECT a stop if they are the passenger of the trip linked to that stop.
CREATE POLICY "Clients can read stops for their trips" ON muevete.paradas_viaje
FOR SELECT
TO authenticated
USING (auth.uid()::text IN (
    SELECT v."user" FROM muevete.viajes v
    WHERE v.id = id_viaje
));
