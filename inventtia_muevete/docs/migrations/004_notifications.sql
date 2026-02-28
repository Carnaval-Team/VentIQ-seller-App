-- Tabla de notificaciones para historial y persistencia
CREATE TABLE muevete.notificaciones (
  id BIGSERIAL PRIMARY KEY,
  user_uuid UUID NOT NULL,
  tipo TEXT NOT NULL,
  titulo TEXT NOT NULL,
  mensaje TEXT NOT NULL,
  data JSONB DEFAULT '{}',
  leida BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index para consultas por usuario
CREATE INDEX idx_notificaciones_user_uuid ON muevete.notificaciones(user_uuid);
CREATE INDEX idx_notificaciones_created_at ON muevete.notificaciones(created_at DESC);

-- Habilitar realtime
ALTER PUBLICATION supabase_realtime ADD TABLE muevete.notificaciones;

-- RLS
ALTER TABLE muevete.notificaciones ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own notifications"
  ON muevete.notificaciones FOR SELECT
  USING (auth.uid() = user_uuid);

CREATE POLICY "Authenticated users can insert notifications"
  ON muevete.notificaciones FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Users can update own notifications"
  ON muevete.notificaciones FOR UPDATE
  USING (auth.uid() = user_uuid);
