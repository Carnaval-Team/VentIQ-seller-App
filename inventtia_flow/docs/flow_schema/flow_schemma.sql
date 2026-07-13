-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE flow.app_dat_servicios (
  id integer NOT NULL DEFAULT nextval('flow.app_dat_servicios_id_seq'::regclass),
  nombre character varying NOT NULL,
  descripcion text,
  foto text,
  created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  id_entidad integer,
  campos_adicionales jsonb NOT NULL DEFAULT '[]'::jsonb,
  permite_tercero boolean NOT NULL DEFAULT false,
  config_precio jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT app_dat_servicios_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_servicios_id_entidad_fkey FOREIGN KEY (id_entidad) REFERENCES flow.entidad(id)
);
CREATE TABLE flow.app_dat_locales (
  id integer NOT NULL DEFAULT nextval('flow.app_dat_locales_id_seq'::regclass),
  nombre character varying NOT NULL,
  descripcion text,
  horario_atencion text,
  terminos_condiciones text,
  coordenadas jsonb,
  direccion text,
  foto text,
  created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  id_entidad integer,
  pais character varying,
  provincia character varying,
  CONSTRAINT app_dat_locales_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_locales_id_entidad_fkey FOREIGN KEY (id_entidad) REFERENCES flow.entidad(id)
);
CREATE TABLE flow.perfil (
  id integer NOT NULL DEFAULT nextval('flow.perfil_id_seq'::regclass),
  uuid_usuario uuid NOT NULL UNIQUE,
  nombre character varying NOT NULL,
  apellidos character varying NOT NULL,
  ci character varying NOT NULL UNIQUE,
  telefono character varying,
  created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT perfil_pkey PRIMARY KEY (id)
);
CREATE TABLE flow.local_servicio (
  id integer NOT NULL DEFAULT nextval('flow.local_servicio_id_seq'::regclass),
  id_local integer NOT NULL,
  id_servicio integer NOT NULL,
  created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  permite_reserva_directa boolean NOT NULL DEFAULT false,
  cantidad_default integer NOT NULL DEFAULT 1,
  cantidad_max_capacidad integer NOT NULL DEFAULT 1,
  CONSTRAINT local_servicio_pkey PRIMARY KEY (id),
  CONSTRAINT local_servicio_id_servicio_fkey FOREIGN KEY (id_servicio) REFERENCES flow.app_dat_servicios(id),
  CONSTRAINT local_servicio_id_local_fkey FOREIGN KEY (id_local) REFERENCES flow.app_dat_locales(id)
);
CREATE TABLE flow.nom_estado_agenda (
  id integer NOT NULL DEFAULT nextval('flow.nom_estado_agenda_id_seq'::regclass),
  nombre character varying NOT NULL UNIQUE,
  descripcion text,
  created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT nom_estado_agenda_pkey PRIMARY KEY (id)
);
CREATE TABLE flow.agenda (
  id integer NOT NULL DEFAULT nextval('flow.agenda_id_seq'::regclass),
  uuid_usuario uuid NOT NULL,
  id_local_servicio integer NOT NULL,
  id_estado integer NOT NULL,
  fecha_hora_reserva timestamp without time zone NOT NULL,
  fecha_hora_atencion timestamp without time zone,
  created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  cantidad integer NOT NULL DEFAULT 1,
  datos_adicionales jsonb,
  reservado_por uuid,
  precio_total numeric,
  moneda varchar(8),
  CONSTRAINT agenda_pkey PRIMARY KEY (id),
  CONSTRAINT agenda_uuid_usuario_fkey FOREIGN KEY (uuid_usuario) REFERENCES flow.perfil(uuid_usuario),
  CONSTRAINT agenda_id_local_servicio_fkey FOREIGN KEY (id_local_servicio) REFERENCES flow.local_servicio(id),
  CONSTRAINT agenda_id_estado_fkey FOREIGN KEY (id_estado) REFERENCES flow.nom_estado_agenda(id)
);
CREATE TABLE flow.sala_espera (
  id integer NOT NULL DEFAULT nextval('flow.sala_espera_id_seq'::regclass),
  uuid_usuario uuid NOT NULL,
  id_local_servicio integer NOT NULL,
  fecha_regla timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  numero_cola integer NOT NULL,
  created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  datos_adicionales jsonb,
  reservado_por uuid,
  CONSTRAINT sala_espera_pkey PRIMARY KEY (id),
  CONSTRAINT sala_espera_uuid_usuario_fkey FOREIGN KEY (uuid_usuario) REFERENCES flow.perfil(uuid_usuario),
  CONSTRAINT sala_espera_id_local_servicio_fkey FOREIGN KEY (id_local_servicio) REFERENCES flow.local_servicio(id)
);
CREATE TABLE flow.ultimo_numero (
  id integer NOT NULL DEFAULT nextval('flow.ultimo_numero_id_seq'::regclass),
  id_local_servicio integer NOT NULL UNIQUE,
  ultimo_otorgado integer NOT NULL DEFAULT 0,
  updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  ultimo_en_anotarse integer,
  CONSTRAINT ultimo_numero_pkey PRIMARY KEY (id),
  CONSTRAINT ultimo_numero_id_local_servicio_fkey FOREIGN KEY (id_local_servicio) REFERENCES flow.local_servicio(id)
);
CREATE TABLE flow.plan_servicios (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  fecha timestamp with time zone DEFAULT now(),
  cantidad integer DEFAULT 0,
  id_local_servicio integer,
  agendados integer NOT NULL DEFAULT 0,
  CONSTRAINT plan_servicios_pkey PRIMARY KEY (id),
  CONSTRAINT plan_servicios_id_local_servicio_fkey FOREIGN KEY (id_local_servicio) REFERENCES flow.local_servicio(id)
);
CREATE TABLE flow.sala_espera_fraude (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  uuid_usuario uuid,
  id_local_servicio integer,
  motivo text NOT NULL,
  detalle jsonb,
  created_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT sala_espera_fraude_pkey PRIMARY KEY (id),
  CONSTRAINT sala_espera_fraude_uuid_fkey FOREIGN KEY (uuid_usuario) REFERENCES flow.perfil(uuid_usuario)
);
CREATE TABLE flow.entidad (
  id integer NOT NULL DEFAULT nextval('flow.entidad_id_seq'::regclass),
  denominacion character varying NOT NULL,
  direccion text,
  telefono character varying,
  owner_uuid uuid NOT NULL,
  created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  horas_anticipacion_cancelacion integer NOT NULL DEFAULT 0,
  CONSTRAINT entidad_pkey PRIMARY KEY (id),
  CONSTRAINT entidad_owner_uuid_fkey FOREIGN KEY (owner_uuid) REFERENCES auth.users(id)
);
CREATE TABLE flow.entidad_admin (
  id integer NOT NULL DEFAULT nextval('flow.entidad_admin_id_seq'::regclass),
  id_entidad integer NOT NULL,
  uuid_usuario uuid NOT NULL,
  asignado_por uuid NOT NULL,
  created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT entidad_admin_pkey PRIMARY KEY (id),
  CONSTRAINT entidad_admin_id_entidad_fkey FOREIGN KEY (id_entidad) REFERENCES flow.entidad(id),
  CONSTRAINT entidad_admin_uuid_usuario_fkey FOREIGN KEY (uuid_usuario) REFERENCES auth.users(id),
  CONSTRAINT entidad_admin_asignado_por_fkey FOREIGN KEY (asignado_por) REFERENCES auth.users(id)
);
CREATE TABLE flow.bot_log (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_plan bigint,
  id_local_servicio integer,
  resultado text NOT NULL,
  movidos integer NOT NULL DEFAULT 0,
  mensaje text,
  detalle jsonb,
  created_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT bot_log_pkey PRIMARY KEY (id)
);
CREATE TABLE flow.notificaciones (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  uuid_usuario uuid NOT NULL,
  tipo text NOT NULL DEFAULT 'sistema'::text,
  titulo text NOT NULL,
  mensaje text NOT NULL,
  leida boolean NOT NULL DEFAULT false,
  leida_at timestamp without time zone,
  id_local_servicio integer,
  id_referencia bigint,
  data jsonb,
  created_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT notificaciones_pkey PRIMARY KEY (id),
  CONSTRAINT notificaciones_uuid_usuario_fkey FOREIGN KEY (uuid_usuario) REFERENCES flow.perfil(uuid_usuario),
  CONSTRAINT notificaciones_id_local_servicio_fkey FOREIGN KEY (id_local_servicio) REFERENCES flow.local_servicio(id)
);
CREATE TABLE flow.plan_config (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_local_servicio integer NOT NULL UNIQUE,
  config jsonb NOT NULL,
  activo boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT plan_config_pkey PRIMARY KEY (id),
  CONSTRAINT plan_config_id_local_servicio_fkey FOREIGN KEY (id_local_servicio) REFERENCES flow.local_servicio(id)
);
CREATE TABLE flow.entidad_vendedor (
  id integer NOT NULL DEFAULT nextval('flow.entidad_vendedor_id_seq'::regclass),
  id_entidad integer NOT NULL,
  uuid_usuario uuid NOT NULL,
  asignado_por uuid NOT NULL,
  created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT entidad_vendedor_pkey PRIMARY KEY (id),
  CONSTRAINT entidad_vendedor_id_entidad_fkey FOREIGN KEY (id_entidad) REFERENCES flow.entidad(id),
  CONSTRAINT entidad_vendedor_uuid_usuario_fkey FOREIGN KEY (uuid_usuario) REFERENCES auth.users(id),
  CONSTRAINT entidad_vendedor_asignado_por_fkey FOREIGN KEY (asignado_por) REFERENCES auth.users(id)
);