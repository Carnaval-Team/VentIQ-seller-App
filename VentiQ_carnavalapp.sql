-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE carnavalapp.Carrito (
  id bigint NOT NULL DEFAULT nextval('carnavalapp."Carrito_id_seq"'::regclass),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  user_id bigint NOT NULL,
  product_id bigint NOT NULL,
  quantity smallint DEFAULT '1'::smallint,
  uuid uuid NOT NULL,
  price_producto numeric,
  precio_descuento numeric,
  proveedor smallint DEFAULT '3'::smallint,
  es_alimento boolean NOT NULL DEFAULT false,
  CONSTRAINT Carrito_pkey PRIMARY KEY (id),
  CONSTRAINT carrito_product_id_fkey FOREIGN KEY (product_id) REFERENCES carnavalapp.Productos(id),
  CONSTRAINT carrito_proveedor_fkey FOREIGN KEY (proveedor) REFERENCES carnavalapp.proveedores(id),
  CONSTRAINT carrito_uuid_fkey FOREIGN KEY (uuid) REFERENCES auth.users(id)
);
CREATE TABLE carnavalapp.Categorias (
  id bigint NOT NULL UNIQUE,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  name text,
  icon character varying DEFAULT 'https://kvgbekelvmkbxydqvtuy.supabase.co/storage/v1/object/public/productos/imagenes/imagen_articulo_por_defecto.jpg'::character varying,
  descripcion text,
  color text,
  orden smallint,
  es_alimento boolean NOT NULL DEFAULT false,
  CONSTRAINT Categorias_pkey PRIMARY KEY (id)
);
CREATE TABLE carnavalapp.Direcciones (
  id bigint NOT NULL DEFAULT nextval('carnavalapp."Direcciones_id_seq"'::regclass),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  user_id smallint,
  address character varying,
  provincia smallint,
  municipio smallint,
  coordenadas text,
  titulo text,
  aclaraciones text,
  uuid uuid,
  pueblo text,
  CONSTRAINT Direcciones_pkey PRIMARY KEY (id),
  CONSTRAINT direcciones_uuid_fkey FOREIGN KEY (uuid) REFERENCES auth.users(id)
);
CREATE TABLE carnavalapp.OrderDetails (
  id bigint NOT NULL DEFAULT nextval('carnavalapp."OrderDetails_id_seq"'::regclass),
  created_at date DEFAULT now(),
  order_id bigint,
  product_id bigint,
  quantity smallint,
  price real,
  cajero smallint,
  precio_usd real DEFAULT '1'::real,
  proveedor smallint DEFAULT '3'::smallint,
  precio_euro real DEFAULT '1'::real,
  status_aprobacion boolean DEFAULT false,
  completada boolean DEFAULT false,
  transferencia boolean DEFAULT false,
  CONSTRAINT OrderDetails_pkey PRIMARY KEY (id),
  CONSTRAINT orderdetails_order_id_fkey FOREIGN KEY (order_id) REFERENCES carnavalapp.Orders(id),
  CONSTRAINT orderdetails_product_id_fkey FOREIGN KEY (product_id) REFERENCES carnavalapp.Productos(id)
);
CREATE TABLE carnavalapp.Orders (
  id bigint NOT NULL DEFAULT nextval('carnavalapp."Orders_id_seq"'::regclass),
  created_at date NOT NULL DEFAULT now(),
  user_id bigint NOT NULL,
  total real NOT NULL,
  status text NOT NULL DEFAULT 'Pendiente de Pago'::text,
  metodo_entrega text,
  direccion text,
  programada text,
  fecha_entrega date,
  costo_envio numeric,
  metodo_pago text,
  descrpcion text,
  notas text,
  rating numeric,
  repartidor bigint,
  cajero bigint,
  created_time time without time zone DEFAULT now(),
  proveedor_id numeric DEFAULT '3'::numeric,
  VersionApp numeric,
  totalUsd real DEFAULT '0'::real,
  envioUsd numeric DEFAULT '0'::numeric,
  totalEuro real DEFAULT '0'::real,
  EnvioEuro real DEFAULT '0'::real,
  proveedores ARRAY,
  moneda text DEFAULT 'CUP'::text,
  tax real DEFAULT '0'::real,
  direccion_recogida text,
  destinatario text,
  telefono_destinatario text,
  peso text,
  es_alimento boolean NOT NULL DEFAULT false,
  CONSTRAINT Orders_pkey PRIMARY KEY (id)
);
CREATE TABLE carnavalapp.Productos (
  id bigint NOT NULL DEFAULT nextval('carnavalapp."Productos_id_seq"'::regclass),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  name text NOT NULL DEFAULT 'Nombre'::text,
  description character varying DEFAULT 'Descripcion'::character varying,
  price real NOT NULL DEFAULT '0'::real,
  stock bigint NOT NULL DEFAULT '0'::bigint,
  category_id smallint NOT NULL,
  image text DEFAULT 'https://kvgbekelvmkbxydqvtuy.supabase.co/storage/v1/object/public/productos/imagenes/imagen_articulo_por_defecto.jpg'::text,
  precio_descuento numeric NOT NULL DEFAULT '0'::numeric,
  destacado boolean DEFAULT false,
  status boolean DEFAULT true,
  proveedor bigint DEFAULT '3'::bigint,
  localitation bigint,
  fecha_entrada timestamp with time zone DEFAULT now(),
  extras jsonb,
  tiempo_elaboracion smallint,
  calorias smallint,
  es_alimento boolean NOT NULL DEFAULT false,
  alimento boolean NOT NULL DEFAULT false,
  sub_categoria bigint,
  CONSTRAINT Productos_pkey PRIMARY KEY (id),
  CONSTRAINT productos_category_id_fkey FOREIGN KEY (category_id) REFERENCES carnavalapp.Categorias(id),
  CONSTRAINT productos_proveedor_fkey FOREIGN KEY (proveedor) REFERENCES carnavalapp.proveedores(id)
);
CREATE TABLE carnavalapp.Provincias (
  id bigint NOT NULL DEFAULT nextval('carnavalapp."Provincias_id_seq"'::regclass),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  nombre text,
  CONSTRAINT Provincias_pkey PRIMARY KEY (id)
);
CREATE TABLE carnavalapp.Reviews (
  id bigint NOT NULL DEFAULT nextval('carnavalapp."Reviews_id_seq"'::regclass),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  product_id bigint,
  user_id bigint,
  rating numeric,
  comment text,
  orden_id bigint,
  CONSTRAINT Reviews_pkey PRIMARY KEY (id),
  CONSTRAINT reviews_orden_id_fkey FOREIGN KEY (orden_id) REFERENCES carnavalapp.Orders(id)
);
CREATE TABLE carnavalapp.Usuarios (
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  email text NOT NULL,
  uuid uuid,
  name text,
  carnet_id text,
  telefono character varying,
  rol text NOT NULL DEFAULT 'Cliente'::text,
  tienda bigint,
  email_confirmacion boolean DEFAULT false,
  id bigint NOT NULL DEFAULT nextval('carnavalapp."Usuarios_id_seq"'::regclass),
  CONSTRAINT usuarios_uuid_fkey FOREIGN KEY (uuid) REFERENCES auth.users(id),
  CONSTRAINT usuarios_tienda_fkey FOREIGN KEY (tienda) REFERENCES carnavalapp.proveedores(id)
);
CREATE TABLE carnavalapp.configuraciones_admin (
  id bigint NOT NULL DEFAULT nextval('carnavalapp.configuraciones_admin_id_seq'::regclass),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  status boolean,
  versionAPPadmin smallint,
  tarjeta character varying,
  numero integer,
  numero_contacto integer,
  version_app_cliente numeric,
  banner_principal text,
  banner_secundario text,
  tarifa numeric,
  version_app_proveedores smallint,
  valor_usd real DEFAULT '0'::real,
  valor_euro real DEFAULT '0'::real,
  tax_usd real DEFAULT '0'::real,
  tax_euro real,
  numero_zelle_pagos text,
  nombre_cuenta_pagos text,
  enlace_pago_tropipay text,
  banner_principal2 text,
  banner_principal3 text,
  numero_soporte_tecnico numeric,
  enlace_whatsapp text,
  imagen_promo_cafeteria text,
  link_page_1 text,
  link_page_2 text,
  link_page_3 text,
  chat_id ARRAY,
  CONSTRAINT configuraciones_admin_pkey PRIMARY KEY (id)
);
CREATE TABLE carnavalapp.extras_productos (
  id bigint NOT NULL DEFAULT nextval('carnavalapp.extras_productos_id_seq'::regclass),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  name text,
  precio numeric,
  calorias numeric,
  peso numeric,
  CONSTRAINT extras_productos_pkey PRIMARY KEY (id)
);
CREATE TABLE carnavalapp.inventarioLogs (
  id bigint NOT NULL DEFAULT nextval('carnavalapp."inventarioLogs_id_seq"'::regclass),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  usuario smallint,
  producto smallint,
  tipo boolean,
  cantidad numeric,
  cantidadP numeric,
  CantidadDespues numeric,
  proveedor bigint,
  CONSTRAINT inventarioLogs_pkey PRIMARY KEY (id),
  CONSTRAINT inventariologs_proveedor_fkey FOREIGN KEY (proveedor) REFERENCES carnavalapp.proveedores(id)
);
CREATE TABLE carnavalapp.municipios (
  id bigint NOT NULL DEFAULT nextval('carnavalapp.municipios_id_seq'::regclass),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  municipio text,
  provincia smallint,
  precio numeric,
  distancia numeric DEFAULT '0'::numeric,
  precio_alimentos numeric NOT NULL DEFAULT '0'::numeric,
  CONSTRAINT municipios_pkey PRIMARY KEY (id),
  CONSTRAINT municipios_provincia_fkey FOREIGN KEY (provincia) REFERENCES carnavalapp.Provincias(id)
);
CREATE TABLE carnavalapp.notificaciones (
  id bigint NOT NULL DEFAULT nextval('carnavalapp.notificaciones_id_seq'::regclass),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  title text,
  content text,
  big - image text,
  CONSTRAINT notificaciones_pkey PRIMARY KEY (id)
);
CREATE TABLE carnavalapp.notificaciones_usuario (
  id bigint NOT NULL DEFAULT nextval('carnavalapp.notificaciones_usuario_id_seq'::regclass),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  titulo text,
  descripcion text,
  CONSTRAINT notificaciones_usuario_pkey PRIMARY KEY (id)
);
CREATE TABLE carnavalapp.payments (
  id bigint NOT NULL DEFAULT nextval('carnavalapp.payments_id_seq'::regclass),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  amount real,
  currency text,
  description text,
  CONSTRAINT payments_pkey PRIMARY KEY (id)
);
CREATE TABLE carnavalapp.preOrden (
  id bigint NOT NULL DEFAULT nextval('carnavalapp."preOrden_id_seq"'::regclass),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  cajero smallint,
  producto smallint,
  cantidad smallint,
  precio numeric,
  precio_descuento numeric,
  CONSTRAINT preOrden_pkey PRIMARY KEY (id),
  CONSTRAINT preorden_producto_fkey FOREIGN KEY (producto) REFERENCES carnavalapp.Productos(id)
);
CREATE TABLE carnavalapp.proveedores (
  id bigint NOT NULL UNIQUE,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  name text,
  descripcion text,
  logo character varying,
  banner character varying,
  ubicacion character varying,
  contacto numeric,
  admin bigint,
  status boolean DEFAULT true,
  direccion character varying,
  orden smallint,
  categoria text,
  es_alimento boolean NOT NULL DEFAULT false,
  chat_id text,
  CONSTRAINT proveedores_pkey PRIMARY KEY (id)
);
CREATE TABLE carnavalapp.repartidores (
  id bigint NOT NULL DEFAULT nextval('carnavalapp.repartidores_id_seq'::regclass),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  nombre text,
  telefono numeric,
  correo text,
  uuid uuid,
  status boolean,
  chat_id text,
  CONSTRAINT repartidores_pkey PRIMARY KEY (id),
  CONSTRAINT repartidores_uuid_fkey FOREIGN KEY (uuid) REFERENCES auth.users(id)
);
CREATE TABLE carnavalapp.sub_categorias (
  id bigint NOT NULL UNIQUE,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  name text,
  id_cat_padre bigint,
  CONSTRAINT sub_categorias_pkey PRIMARY KEY (id),
  CONSTRAINT sub_categorias_id_cat_padre_fkey FOREIGN KEY (id_cat_padre) REFERENCES carnavalapp.Categorias(id)
);
CREATE TABLE carnavalapp.transacciones (
  id bigint NOT NULL DEFAULT nextval('carnavalapp.transacciones_id_seq'::regclass),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  num_orden smallint,
  user_id bigint,
  metodo text,
  cliente boolean DEFAULT false,
  admin boolean DEFAULT false,
  num_admin text,
  num_cliente text,
  CONSTRAINT transacciones_pkey PRIMARY KEY (id),
  CONSTRAINT transacciones_num_orden_fkey FOREIGN KEY (num_orden) REFERENCES carnavalapp.Orders(id)
);
CREATE TABLE carnavalapp.user_tokens (
  id bigint NOT NULL DEFAULT nextval('carnavalapp.user_tokens_id_seq'::regclass),
  user_id uuid,
  fcm_token text UNIQUE,
  CONSTRAINT user_tokens_pkey PRIMARY KEY (id),
  CONSTRAINT user_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)
);