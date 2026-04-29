-- Tabla de valoraciones de viajes
CREATE TABLE muevete.valoraciones_viaje (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  viaje_id bigint NOT NULL,
  driver_id bigint NOT NULL,
  user_id uuid NOT NULL,
  rating smallint NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comentario text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT valoraciones_viaje_pkey PRIMARY KEY (id),
  CONSTRAINT valoraciones_viaje_viaje_fkey FOREIGN KEY (viaje_id) REFERENCES muevete.viajes(id),
  CONSTRAINT valoraciones_viaje_driver_fkey FOREIGN KEY (driver_id) REFERENCES muevete.drivers(id),
  CONSTRAINT valoraciones_viaje_user_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id),
  CONSTRAINT valoraciones_viaje_viaje_unique UNIQUE (viaje_id)
);
