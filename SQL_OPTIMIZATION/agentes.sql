-- =====================================================
-- TABLA: app_dat_agente
-- Agentes que despliegan la aplicación
-- =====================================================

CREATE TABLE public.app_dat_agente (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  nombre character varying NOT NULL,
  apellidos character varying NOT NULL,
  telefono character varying,
  email character varying,
  estado smallint NOT NULL DEFAULT 1,
  observaciones text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_agente_pkey PRIMARY KEY (id)
);

-- =====================================================
-- MODIFICAR app_suscripciones: agregar referencia al agente
-- =====================================================

ALTER TABLE public.app_suscripciones
  ADD COLUMN id_agente bigint;

ALTER TABLE public.app_suscripciones
  ADD CONSTRAINT app_suscripciones_id_agente_fkey
  FOREIGN KEY (id_agente) REFERENCES public.app_dat_agente(id);
