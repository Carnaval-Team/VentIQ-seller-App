-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE public.app_cont_asignacion_costos (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_tipo_costo bigint NOT NULL,
  id_producto bigint,
  id_tienda bigint,
  id_centro_costo bigint,
  porcentaje_asignacion numeric NOT NULL DEFAULT 100.00,
  metodo_asignacion smallint NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_cont_asignacion_costos_pkey PRIMARY KEY (id),
  CONSTRAINT app_cont_asignacion_costos_id_tipo_costo_fkey FOREIGN KEY (id_tipo_costo) REFERENCES public.app_cont_tipo_costo(id),
  CONSTRAINT app_cont_asignacion_costos_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_cont_asignacion_costos_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT app_cont_asignacion_costos_id_centro_costo_fkey FOREIGN KEY (id_centro_costo) REFERENCES public.app_cont_centro_costo(id)
);
CREATE TABLE public.app_cont_centro_costo (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_padre bigint,
  id_tienda bigint,
  denominacion character varying NOT NULL,
  descripcion character varying,
  codigo character varying,
  sku_codigo character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_cont_centro_costo_pkey PRIMARY KEY (id),
  CONSTRAINT app_cont_centro_costo_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id)
);
CREATE TABLE public.app_cont_egresos_procesados (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_egreso bigint NOT NULL UNIQUE,
  estado character varying NOT NULL CHECK (estado::text = ANY (ARRAY['aceptado'::character varying, 'rechazado'::character varying]::text[])),
  procesado_por uuid NOT NULL,
  fecha_procesado timestamp with time zone NOT NULL DEFAULT now(),
  motivo_rechazo text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_cont_egresos_procesados_pkey PRIMARY KEY (id),
  CONSTRAINT app_cont_egresos_procesados_id_egreso_fkey FOREIGN KEY (id_egreso) REFERENCES public.app_dat_entregas_parciales_caja(id),
  CONSTRAINT app_cont_egresos_procesados_procesado_por_fkey FOREIGN KEY (procesado_por) REFERENCES auth.users(id)
);
CREATE TABLE public.app_cont_gasto_asignacion (
  id_gasto bigint NOT NULL,
  id_asignacion bigint NOT NULL,
  monto_asignado numeric NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_cont_gasto_asignacion_pkey PRIMARY KEY (id_gasto, id_asignacion),
  CONSTRAINT app_cont_gasto_asignacion_id_gasto_fkey FOREIGN KEY (id_gasto) REFERENCES public.app_cont_gastos(id),
  CONSTRAINT app_cont_gasto_asignacion_id_asignacion_fkey FOREIGN KEY (id_asignacion) REFERENCES public.app_cont_asignacion_costos(id)
);
CREATE TABLE public.app_cont_gastos (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_subcategoria_gasto bigint,
  monto numeric NOT NULL,
  uuid uuid,
  fecha date NOT NULL,
  id_centro_costo bigint,
  id_tienda bigint,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  id_tipo_costo bigint,
  origen_operacion bigint,
  tipo_origen text,
  id_referencia_origen bigint,
  CONSTRAINT app_cont_gastos_pkey PRIMARY KEY (id),
  CONSTRAINT app_cont_gastos_id_subcategoria_gasto_fkey FOREIGN KEY (id_subcategoria_gasto) REFERENCES public.app_nom_subcategoria_gasto(id),
  CONSTRAINT app_cont_gastos_uuid_fkey FOREIGN KEY (uuid) REFERENCES auth.users(id),
  CONSTRAINT app_cont_gastos_id_centro_costo_fkey FOREIGN KEY (id_centro_costo) REFERENCES public.app_cont_centro_costo(id),
  CONSTRAINT app_cont_gastos_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT app_cont_gastos_id_tipo_costo_fkey FOREIGN KEY (id_tipo_costo) REFERENCES public.app_cont_tipo_costo(id),
  CONSTRAINT app_cont_gastos_origen_operacion_fkey FOREIGN KEY (origen_operacion) REFERENCES public.app_dat_recepcion_productos(id)
);
CREATE TABLE public.app_cont_historial_actividades (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  tipo_actividad text NOT NULL CHECK (tipo_actividad = ANY (ARRAY['gasto_registrado'::character varying::text, 'gasto_eliminado'::character varying::text, 'gasto_actualizado'::character varying::text, 'operacion_procesada'::character varying::text, 'operacion_omitida'::character varying::text, 'operacion_eliminada'::character varying::text, 'asignacion_creada'::character varying::text, 'asignacion_actualizada'::character varying::text, 'asignacion_eliminada'::character varying::text, 'categoria_creada'::character varying::text, 'categoria_actualizada'::character varying::text, 'categoria_eliminada'::character varying::text, 'centro_costo_creado'::character varying::text, 'centro_costo_actualizado'::character varying::text, 'centro_costo_eliminado'::character varying::text, 'tipo_costo_creado'::character varying::text, 'tipo_costo_actualizado'::character varying::text, 'tipo_costo_eliminado'::character varying::text, 'sistema_inicializado'::character varying::text, 'configuracion_actualizada'::character varying::text])),
  descripcion text NOT NULL,
  entidad_tipo character varying NOT NULL CHECK (entidad_tipo::text = ANY (ARRAY['gasto'::character varying, 'operacion'::character varying, 'asignacion'::character varying, 'categoria'::character varying, 'subcategoria'::character varying, 'centro_costo'::character varying, 'tipo_costo'::character varying, 'sistema'::character varying]::text[])),
  entidad_id bigint,
  monto numeric,
  usuario_id uuid NOT NULL,
  id_tienda bigint NOT NULL,
  metadata jsonb,
  fecha_actividad timestamp with time zone NOT NULL DEFAULT now(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_cont_historial_actividades_pkey PRIMARY KEY (id),
  CONSTRAINT app_cont_historial_actividades_usuario_fkey FOREIGN KEY (usuario_id) REFERENCES auth.users(id),
  CONSTRAINT app_cont_historial_actividades_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id)
);
CREATE TABLE public.app_cont_historial_asignacion_costos (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_asignacion_original bigint NOT NULL,
  id_tipo_costo bigint NOT NULL,
  id_producto bigint,
  id_tienda bigint,
  id_centro_costo bigint,
  porcentaje_asignacion numeric NOT NULL,
  metodo_asignacion smallint NOT NULL,
  fecha_modificacion timestamp with time zone NOT NULL,
  modificado_por uuid NOT NULL,
  CONSTRAINT app_cont_historial_asignacion_costos_pkey PRIMARY KEY (id),
  CONSTRAINT app_cont_historial_asignacion_costos_id_tipo_costo_fkey FOREIGN KEY (id_tipo_costo) REFERENCES public.app_cont_tipo_costo(id)
);
CREATE TABLE public.app_cont_historial_gastos (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_gasto_original bigint NOT NULL,
  id_subcategoria_gasto bigint,
  monto numeric NOT NULL,
  monto_anterior numeric,
  fecha date NOT NULL,
  id_centro_costo bigint,
  id_tienda bigint,
  id_tipo_costo bigint,
  accion text NOT NULL,
  realizado_por uuid,
  fecha_modificacion timestamp with time zone NOT NULL DEFAULT now(),
  descripcion_cambio text,
  comprobante text,
  detalles_asignacion jsonb,
  CONSTRAINT app_cont_historial_gastos_pkey PRIMARY KEY (id),
  CONSTRAINT app_cont_historial_gastos_id_subcategoria_gasto_fkey FOREIGN KEY (id_subcategoria_gasto) REFERENCES public.app_nom_subcategoria_gasto(id),
  CONSTRAINT app_cont_historial_gastos_id_centro_costo_fkey FOREIGN KEY (id_centro_costo) REFERENCES public.app_cont_centro_costo(id),
  CONSTRAINT app_cont_historial_gastos_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT app_cont_historial_gastos_id_tipo_costo_fkey FOREIGN KEY (id_tipo_costo) REFERENCES public.app_cont_tipo_costo(id),
  CONSTRAINT app_cont_historial_gastos_realizado_por_fkey FOREIGN KEY (realizado_por) REFERENCES auth.users(id)
);
CREATE TABLE public.app_cont_log_costos (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_asignacion bigint NOT NULL,
  id_historico bigint,
  accion text NOT NULL,
  cambios text,
  realizado_por uuid NOT NULL,
  fecha_operacion timestamp with time zone NOT NULL,
  CONSTRAINT app_cont_log_costos_pkey PRIMARY KEY (id),
  CONSTRAINT app_cont_log_costos_id_asignacion_fkey FOREIGN KEY (id_asignacion) REFERENCES public.app_cont_asignacion_costos(id),
  CONSTRAINT app_cont_log_costos_id_historico_fkey FOREIGN KEY (id_historico) REFERENCES public.app_cont_historial_asignacion_costos(id)
);
CREATE TABLE public.app_cont_margen_comercial (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_producto bigint NOT NULL,
  id_variante bigint,
  id_tienda bigint NOT NULL,
  margen_deseado numeric NOT NULL,
  tipo_margen smallint NOT NULL,
  fecha_desde date NOT NULL,
  fecha_hasta date,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_cont_margen_comercial_pkey PRIMARY KEY (id),
  CONSTRAINT app_cont_margen_comercial_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_cont_margen_comercial_id_variante_fkey FOREIGN KEY (id_variante) REFERENCES public.app_dat_variantes(id),
  CONSTRAINT app_cont_margen_comercial_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id)
);
CREATE TABLE public.app_cont_tipo_costo (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  denominacion character varying NOT NULL,
  descripcion text,
  naturaleza smallint NOT NULL,
  afecta_margen boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_cont_tipo_costo_pkey PRIMARY KEY (id),
  CONSTRAINT app_cont_tipo_costo_naturaleza_fkey FOREIGN KEY (naturaleza) REFERENCES public.app_nom_naturaleza_costo(id)
);
CREATE TABLE public.app_dat_actividad_usuario (
  token uuid NOT NULL,
  app text NOT NULL,
  ultimo_accesso timestamp with time zone NOT NULL DEFAULT now(),
  cantidad_de_accessos integer NOT NULL DEFAULT 1,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT app_dat_actividad_usuario_pkey PRIMARY KEY (token, app)
);
CREATE TABLE public.app_dat_ajuste_inventario (
  id bigint NOT NULL DEFAULT nextval('app_dat_ajuste_inventario_id_seq'::regclass),
  id_producto bigint NOT NULL,
  id_variante bigint,
  id_ubicacion bigint,
  cantidad_anterior numeric NOT NULL,
  cantidad_nueva numeric NOT NULL,
  id_control bigint,
  uuid_usuario uuid,
  created_at timestamp with time zone DEFAULT now(),
  diferencia numeric,
  id_operacion bigint,
  CONSTRAINT app_dat_ajuste_inventario_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_ajuste_inventario_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_dat_ajuste_inventario_id_control_fkey FOREIGN KEY (id_control) REFERENCES public.app_dat_control_productos(id),
  CONSTRAINT app_dat_ajuste_inventario_id_operacion_fkey FOREIGN KEY (id_operacion) REFERENCES public.app_dat_operaciones(id)
);
CREATE TABLE public.app_dat_almacen (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_tienda bigint,
  denominacion character varying,
  direccion character varying,
  ubicacion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  deleted_at timestamp without time zone,
  CONSTRAINT app_dat_almacen_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_almacen_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id)
);
CREATE TABLE public.app_dat_almacen_limites (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_producto bigint,
  id_almacen bigint,
  stock_min numeric,
  stock_max numeric,
  stock_ordenar numeric,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_almacen_limites_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_almacen limites_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_dat_almacen limites_id_almacen_fkey FOREIGN KEY (id_almacen) REFERENCES public.app_dat_almacen(id)
);
CREATE TABLE public.app_dat_almacenero (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  uuid uuid NOT NULL,
  id_almacen bigint NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  id_trabajador bigint,
  CONSTRAINT app_dat_almacenero_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_almacenero_uuid_fkey FOREIGN KEY (uuid) REFERENCES auth.users(id),
  CONSTRAINT app_dat_almacenero_id_almacen_fkey FOREIGN KEY (id_almacen) REFERENCES public.app_dat_almacen(id),
  CONSTRAINT app_dat_almacenero_id_trabajador_fkey FOREIGN KEY (id_trabajador) REFERENCES public.app_dat_trabajadores(id)
);
CREATE TABLE public.app_dat_application_rating (
  id bigint NOT NULL DEFAULT nextval('app_dat_application_rating_id_seq'::regclass),
  id_usuario uuid NOT NULL,
  rating numeric NOT NULL CHECK (rating >= 1.0 AND rating <= 5.0),
  comentario text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT app_dat_application_rating_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_tienda_rating_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES auth.users(id)
);
CREATE TABLE public.app_dat_atributo_opcion (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_atributo bigint NOT NULL,
  valor character varying NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  sku_codigo text NOT NULL,
  CONSTRAINT app_dat_atributo_opcion_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_atributo_opcion_id_atributo_fkey FOREIGN KEY (id_atributo) REFERENCES public.app_dat_atributos(id)
);
CREATE TABLE public.app_dat_atributos (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  denominacion character varying NOT NULL,
  label character varying NOT NULL,
  descripcion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_atributos_pkey PRIMARY KEY (id)
);
CREATE TABLE public.app_dat_caja_turno (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_operacion_apertura bigint NOT NULL UNIQUE,
  id_operacion_cierre bigint UNIQUE,
  id_tpv bigint NOT NULL,
  id_vendedor bigint NOT NULL,
  efectivo_inicial numeric NOT NULL,
  efectivo_esperado numeric DEFAULT 0,
  efectivo_real numeric,
  diferencia numeric DEFAULT (efectivo_real - efectivo_esperado),
  estado smallint NOT NULL DEFAULT 1,
  observaciones text,
  creado_por uuid NOT NULL,
  cerrado_por uuid,
  fecha_apertura timestamp with time zone NOT NULL DEFAULT now(),
  fecha_cierre timestamp with time zone,
  maneja_inventario boolean,
  CONSTRAINT app_dat_caja_turno_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_caja_turno_id_operacion_apertura_fkey FOREIGN KEY (id_operacion_apertura) REFERENCES public.app_dat_operaciones(id),
  CONSTRAINT app_dat_caja_turno_id_operacion_cierre_fkey FOREIGN KEY (id_operacion_cierre) REFERENCES public.app_dat_operaciones(id),
  CONSTRAINT app_dat_caja_turno_id_tpv_fkey FOREIGN KEY (id_tpv) REFERENCES public.app_dat_tpv(id),
  CONSTRAINT app_dat_caja_turno_id_vendedor_fkey FOREIGN KEY (id_vendedor) REFERENCES public.app_dat_vendedor(id),
  CONSTRAINT app_dat_caja_turno_creado_por_fkey FOREIGN KEY (creado_por) REFERENCES auth.users(id),
  CONSTRAINT app_dat_caja_turno_cerrado_por_fkey FOREIGN KEY (cerrado_por) REFERENCES auth.users(id),
  CONSTRAINT app_dat_caja_turno_estado_fkey FOREIGN KEY (estado) REFERENCES public.app_nom_estado_operacion(id)
);
CREATE TABLE public.app_dat_cambio_precio (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_producto bigint NOT NULL,
  id_variante bigint,
  id_tpv bigint NOT NULL,
  id_usuario uuid NOT NULL,
  precio_anterior numeric NOT NULL,
  precio_nuevo numeric NOT NULL,
  motivo text,
  fecha_cambio timestamp with time zone NOT NULL DEFAULT now(),
  monto_descontado numeric,
  CONSTRAINT app_dat_cambio_precio_pkey PRIMARY KEY (id),
  CONSTRAINT fk_producto FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT fk_variante FOREIGN KEY (id_variante) REFERENCES public.app_dat_variantes(id),
  CONSTRAINT fk_tpv FOREIGN KEY (id_tpv) REFERENCES public.app_dat_tpv(id),
  CONSTRAINT fk_usuario FOREIGN KEY (id_usuario) REFERENCES auth.users(id)
);
CREATE TABLE public.app_dat_categoria (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  denominacion character varying NOT NULL,
  descripcion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  sku_codigo text NOT NULL,
  image text,
  visible_vendedor boolean DEFAULT true,
  para_catalogo boolean DEFAULT false,
  CONSTRAINT app_dat_categoria_pkey PRIMARY KEY (id)
);
CREATE TABLE public.app_dat_categoria_tienda (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_categoria bigint,
  id_tienda bigint,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_categoria_tienda_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_categoria_tienda_id_categoria_fkey FOREIGN KEY (id_categoria) REFERENCES public.app_dat_categoria(id),
  CONSTRAINT app_dat_categoria_tienda_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id)
);
CREATE TABLE public.app_dat_clientes (
  id bigint NOT NULL DEFAULT nextval('app_dat_clientes_id_seq'::regclass),
  codigo_cliente character varying NOT NULL,
  tipo_cliente smallint NOT NULL DEFAULT 1 CHECK (tipo_cliente >= 1 AND tipo_cliente <= 3),
  nombre_completo character varying NOT NULL,
  documento_identidad character varying,
  email character varying CHECK (email::text ~* '^[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+[.][A-Za-z]+$'::text),
  telefono character varying,
  direccion jsonb,
  fecha_nacimiento date,
  genero character,
  puntos_acumulados integer DEFAULT 0,
  nivel_fidelidad smallint DEFAULT 1,
  limite_credito numeric,
  fecha_registro timestamp with time zone DEFAULT now(),
  ultima_compra timestamp with time zone,
  total_compras numeric DEFAULT 0,
  frecuencia_compra smallint,
  preferencias jsonb,
  notas text,
  activo boolean DEFAULT true,
  acepta_marketing boolean DEFAULT true,
  fecha_optin timestamp with time zone,
  fecha_optout timestamp with time zone,
  preferencias_comunicacion jsonb,
  CONSTRAINT app_dat_clientes_pkey PRIMARY KEY (id)
);
CREATE TABLE public.app_dat_codigos_barras (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_producto bigint NOT NULL,
  id_variante bigint,
  id_opcion_variante bigint,
  id_presentacion bigint,
  codigo_barras character varying NOT NULL UNIQUE,
  es_principal boolean NOT NULL DEFAULT false,
  descripcion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by uuid,
  CONSTRAINT app_dat_codigos_barras_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_codigos_barras_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id),
  CONSTRAINT app_dat_codigos_barras_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_dat_codigos_barras_variante_fkey FOREIGN KEY (id_variante) REFERENCES public.app_dat_variantes(id),
  CONSTRAINT app_dat_codigos_barras_opcion_fkey FOREIGN KEY (id_opcion_variante) REFERENCES public.app_dat_atributo_opcion(id),
  CONSTRAINT app_dat_codigos_barras_presentacion_fkey FOREIGN KEY (id_presentacion) REFERENCES public.app_dat_producto_presentacion(id)
);
CREATE TABLE public.app_dat_configuracion_tienda (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_tienda bigint NOT NULL UNIQUE,
  need_master_password_to_cancel boolean NOT NULL DEFAULT false,
  need_all_orders_completed_to_continue boolean NOT NULL DEFAULT false,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  master_password text,
  maneja_inventario boolean DEFAULT false,
  permite_vender_aun_sin_disponibilidad boolean DEFAULT false,
  no_solicitar_cliente boolean NOT NULL DEFAULT false,
  tpv_trabajador_encargado_carnaval jsonb,
  allow_discount_on_vendedor boolean NOT NULL DEFAULT false,
  permitir_imprimir_pendientes boolean,
  metodo_redondeo_precio_venta text NOT NULL DEFAULT 'NO_REDONDEAR'::text CHECK (metodo_redondeo_precio_venta = ANY (ARRAY['NO_REDONDEAR'::text, 'REDONDEAR_POR_DEFECTO'::text, 'REDONDEAR_POR_EXCESO'::text, 'REDONDEAR_A_MULT_5_POR_DEFECTO'::text, 'REDONDEAR_A_MULT_5_POR_EXCESO'::text])),
  CONSTRAINT app_dat_configuracion_tienda_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_configuracion_tienda_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id)
);
CREATE TABLE public.app_dat_consignacion_envio (
  id bigint NOT NULL DEFAULT nextval('app_dat_consignacion_envio_id_seq'::regclass),
  id_contrato_consignacion bigint NOT NULL,
  id_operacion_extraccion bigint,
  id_operacion_recepcion bigint,
  numero_envio character varying NOT NULL UNIQUE,
  descripcion text,
  id_almacen_origen bigint,
  id_almacen_destino bigint,
  estado_envio integer NOT NULL DEFAULT 1,
  fecha_propuesta timestamp with time zone DEFAULT now(),
  fecha_configuracion timestamp with time zone,
  fecha_envio timestamp with time zone,
  fecha_aceptacion timestamp with time zone,
  fecha_rechazo timestamp with time zone,
  fecha_entrega timestamp with time zone,
  motivo_rechazo text,
  cantidad_productos integer DEFAULT 0,
  cantidad_total_unidades numeric DEFAULT 0,
  valor_total_costo numeric DEFAULT 0,
  valor_total_venta numeric DEFAULT 0,
  id_usuario_creador uuid,
  id_usuario_configurador uuid,
  id_usuario_aceptador uuid,
  id_usuario_rechazador uuid,
  estado integer NOT NULL DEFAULT 1,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  tipo_envio integer DEFAULT 1,
  id_almacen_recepcion_devolucion bigint,
  CONSTRAINT app_dat_consignacion_envio_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_consignacion_envio_id_contrato_consignacion_fkey FOREIGN KEY (id_contrato_consignacion) REFERENCES public.app_dat_contrato_consignacion(id),
  CONSTRAINT app_dat_consignacion_envio_id_operacion_extraccion_fkey FOREIGN KEY (id_operacion_extraccion) REFERENCES public.app_dat_operaciones(id),
  CONSTRAINT app_dat_consignacion_envio_id_operacion_recepcion_fkey FOREIGN KEY (id_operacion_recepcion) REFERENCES public.app_dat_operaciones(id),
  CONSTRAINT app_dat_consignacion_envio_id_almacen_origen_fkey FOREIGN KEY (id_almacen_origen) REFERENCES public.app_dat_almacen(id),
  CONSTRAINT app_dat_consignacion_envio_id_almacen_destino_fkey FOREIGN KEY (id_almacen_destino) REFERENCES public.app_dat_almacen(id),
  CONSTRAINT app_dat_consignacion_envio_id_usuario_creador_fkey FOREIGN KEY (id_usuario_creador) REFERENCES auth.users(id),
  CONSTRAINT app_dat_consignacion_envio_id_usuario_configurador_fkey FOREIGN KEY (id_usuario_configurador) REFERENCES auth.users(id),
  CONSTRAINT app_dat_consignacion_envio_id_usuario_aceptador_fkey FOREIGN KEY (id_usuario_aceptador) REFERENCES auth.users(id),
  CONSTRAINT app_dat_consignacion_envio_id_usuario_rechazador_fkey FOREIGN KEY (id_usuario_rechazador) REFERENCES auth.users(id),
  CONSTRAINT app_dat_consignacion_envio_id_almacen_recepcion_devolucion_fkey FOREIGN KEY (id_almacen_recepcion_devolucion) REFERENCES public.app_dat_almacen(id)
);
CREATE TABLE public.app_dat_consignacion_envio_movimiento (
  id bigint NOT NULL DEFAULT nextval('app_dat_consignacion_envio_movimiento_id_seq'::regclass),
  id_envio bigint NOT NULL,
  id_usuario uuid NOT NULL,
  tipo_movimiento integer NOT NULL,
  estado_anterior integer,
  estado_nuevo integer NOT NULL,
  descripcion text,
  datos_adicionales jsonb,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT app_dat_consignacion_envio_movimiento_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_consignacion_envio_movimiento_id_envio_fkey FOREIGN KEY (id_envio) REFERENCES public.app_dat_consignacion_envio(id),
  CONSTRAINT app_dat_consignacion_envio_movimiento_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES auth.users(id)
);
CREATE TABLE public.app_dat_consignacion_envio_producto (
  id bigint NOT NULL DEFAULT nextval('app_dat_consignacion_envio_producto_id_seq'::regclass),
  id_envio bigint NOT NULL,
  id_producto_consignacion bigint,
  id_inventario bigint NOT NULL,
  id_producto bigint NOT NULL,
  cantidad_propuesta numeric NOT NULL,
  cantidad_aceptada numeric DEFAULT 0,
  cantidad_rechazada numeric DEFAULT 0,
  precio_costo_usd numeric,
  precio_costo_cup numeric,
  precio_venta_cup numeric,
  tasa_cambio numeric,
  estado_producto integer NOT NULL DEFAULT 1,
  fecha_configuracion_precio timestamp with time zone,
  fecha_aceptacion timestamp with time zone,
  fecha_rechazo timestamp with time zone,
  motivo_rechazo text,
  estado integer NOT NULL DEFAULT 1,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  id_presentacion_original bigint,
  id_variante_original bigint,
  id_ubicacion_original bigint,
  id_inventario_original bigint,
  CONSTRAINT app_dat_consignacion_envio_producto_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_consignacion_envio_producto_id_envio_fkey FOREIGN KEY (id_envio) REFERENCES public.app_dat_consignacion_envio(id),
  CONSTRAINT app_dat_consignacion_envio_produc_id_producto_consignacion_fkey FOREIGN KEY (id_producto_consignacion) REFERENCES public.app_dat_producto_consignacion(id),
  CONSTRAINT app_dat_consignacion_envio_producto_id_inventario_fkey FOREIGN KEY (id_inventario) REFERENCES public.app_dat_inventario_productos(id),
  CONSTRAINT app_dat_consignacion_envio_producto_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT fk_envio_producto_presentacion_original FOREIGN KEY (id_presentacion_original) REFERENCES public.app_dat_producto_presentacion(id),
  CONSTRAINT fk_envio_producto_variante_original FOREIGN KEY (id_variante_original) REFERENCES public.app_dat_variantes(id),
  CONSTRAINT fk_envio_producto_ubicacion_original FOREIGN KEY (id_ubicacion_original) REFERENCES public.app_dat_layout_almacen(id),
  CONSTRAINT fk_envio_producto_inventario_original FOREIGN KEY (id_inventario_original) REFERENCES public.app_dat_inventario_productos(id)
);
CREATE TABLE public.app_dat_consignacion_zona (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_contrato bigint NOT NULL,
  id_zona bigint NOT NULL,
  id_tienda_consignadora bigint NOT NULL,
  id_tienda_consignataria bigint NOT NULL,
  nombre_zona text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_consignacion_zona_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_consignacion_zona_contrato_fkey FOREIGN KEY (id_contrato) REFERENCES public.app_dat_contrato_consignacion(id),
  CONSTRAINT app_dat_consignacion_zona_zona_fkey FOREIGN KEY (id_zona) REFERENCES public.app_dat_layout_almacen(id),
  CONSTRAINT app_dat_consignacion_zona_tienda_consignadora_fkey FOREIGN KEY (id_tienda_consignadora) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT app_dat_consignacion_zona_tienda_consignataria_fkey FOREIGN KEY (id_tienda_consignataria) REFERENCES public.app_dat_tienda(id)
);
CREATE TABLE public.app_dat_contactos_clientes (
  id bigint NOT NULL DEFAULT nextval('app_dat_contactos_clientes_id_seq'::regclass),
  id_cliente bigint,
  nombre character varying,
  telefono character varying,
  relacion character varying,
  es_principal boolean DEFAULT false,
  CONSTRAINT app_dat_contactos_clientes_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_contactos_clientes_id_cliente_fkey FOREIGN KEY (id_cliente) REFERENCES public.app_dat_clientes(id)
);
CREATE TABLE public.app_dat_contrato_consignacion (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_tienda_consignadora bigint NOT NULL,
  id_tienda_consignataria bigint NOT NULL,
  estado smallint NOT NULL DEFAULT 1,
  fecha_inicio date NOT NULL DEFAULT CURRENT_DATE,
  fecha_fin date,
  porcentaje_comision numeric CHECK (porcentaje_comision IS NULL OR porcentaje_comision >= 0::numeric AND porcentaje_comision <= 100::numeric),
  plazo_dias integer CHECK (plazo_dias IS NULL OR plazo_dias > 0),
  condiciones text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  estado_confirmacion smallint NOT NULL DEFAULT '0'::smallint,
  fecha_confirmacion timestamp without time zone,
  motivo_cancelacion text,
  id_almacen_destino bigint,
  monto_total numeric NOT NULL DEFAULT '0'::numeric,
  id_layout_destino bigint,
  CONSTRAINT app_dat_contrato_consignacion_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_contrato_consignacion_almacen_destino_fkey FOREIGN KEY (id_almacen_destino) REFERENCES public.app_dat_almacen(id),
  CONSTRAINT app_dat_contrato_consignacion_id_tienda_consignadora_fkey FOREIGN KEY (id_tienda_consignadora) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT app_dat_contrato_consignacion_id_tienda_consignataria_fkey FOREIGN KEY (id_tienda_consignataria) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT app_dat_contrato_consignacion_id_layout_destino_fkey FOREIGN KEY (id_layout_destino) REFERENCES public.app_dat_layout_almacen(id)
);
CREATE TABLE public.app_dat_control_productos (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_operacion bigint,
  id_producto bigint,
  id_variante bigint,
  id_opcion_variante bigint,
  id_ubicacion bigint,
  id_presentacion bigint,
  cantidad numeric NOT NULL,
  sku_producto character varying,
  sku_ubicacion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_control_productos_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_control_productos_id_operacion_fkey FOREIGN KEY (id_operacion) REFERENCES public.app_dat_operaciones(id),
  CONSTRAINT app_dat_control_productos_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_dat_control_productos_id_variante_fkey FOREIGN KEY (id_variante) REFERENCES public.app_dat_variantes(id),
  CONSTRAINT app_dat_control_productos_id_opcion_variante_fkey FOREIGN KEY (id_opcion_variante) REFERENCES public.app_dat_atributo_opcion(id),
  CONSTRAINT app_dat_control_productos_id_ubicacion_fkey FOREIGN KEY (id_ubicacion) REFERENCES public.app_dat_layout_almacen(id),
  CONSTRAINT app_dat_control_productos_id_presentacion_fkey FOREIGN KEY (id_presentacion) REFERENCES public.app_dat_producto_presentacion(id)
);
CREATE TABLE public.app_dat_denominaciones_moneda (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  codigo_moneda character varying NOT NULL,
  denominacion numeric NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  active boolean NOT NULL DEFAULT true,
  CONSTRAINT app_dat_denominaciones_moneda_pkey PRIMARY KEY (id)
);
CREATE TABLE public.app_dat_descuentos_vendedor (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_vendedor bigint NOT NULL,
  uuid_usuario uuid NOT NULL,
  id_operacion bigint NOT NULL,
  monto_real numeric NOT NULL,
  monto_descontado numeric NOT NULL,
  tipo_descuento integer NOT NULL,
  valor_descuento numeric NOT NULL,
  id_cliente bigint,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  id_producto bigint,
  CONSTRAINT app_dat_descuentos_vendedor_pkey PRIMARY KEY (id)
);
CREATE TABLE public.app_dat_entregas_parciales_caja (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_turno bigint NOT NULL,
  monto_entrega numeric NOT NULL CHECK (monto_entrega > 0::numeric),
  motivo_entrega text,
  nombre_recibe character varying NOT NULL,
  nombre_autoriza character varying NOT NULL,
  fecha_entrega timestamp with time zone NOT NULL DEFAULT now(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  id_medio_pago smallint,
  uuid_vendedor uuid,
  CONSTRAINT app_dat_entregas_parciales_caja_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_entregas_parciales_caja_id_turno_fkey FOREIGN KEY (id_turno) REFERENCES public.app_dat_caja_turno(id),
  CONSTRAINT app_dat_entregas_parciales_caja_id_medio_pago_fkey FOREIGN KEY (id_medio_pago) REFERENCES public.app_nom_medio_pago(id)
);
CREATE TABLE public.app_dat_estado_operacion (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_operacion bigint NOT NULL,
  estado smallint NOT NULL DEFAULT '1'::smallint,
  uuid uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  comentario text,
  CONSTRAINT app_dat_estado_operacion_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_estado_operacion_id_operacion_fkey FOREIGN KEY (id_operacion) REFERENCES public.app_dat_operaciones(id),
  CONSTRAINT app_dat_estado_operacion_uuid_fkey FOREIGN KEY (uuid) REFERENCES auth.users(id),
  CONSTRAINT app_dat_estado_operacion_estado_fkey FOREIGN KEY (estado) REFERENCES public.app_nom_estado_operacion(id)
);
CREATE TABLE public.app_dat_extraccion_productos (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_operacion bigint,
  id_producto bigint,
  id_variante bigint,
  id_opcion_variante bigint,
  id_ubicacion bigint,
  id_presentacion bigint,
  cantidad numeric NOT NULL CHECK (cantidad > 0::numeric),
  precio_unitario numeric,
  sku_producto character varying,
  sku_ubicacion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  importe numeric,
  importe_real numeric,
  CONSTRAINT app_dat_extraccion_productos_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_extraccion_productos_id_operacion_fkey FOREIGN KEY (id_operacion) REFERENCES public.app_dat_operaciones(id),
  CONSTRAINT app_dat_extraccion_productos_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_dat_extraccion_productos_id_variante_fkey FOREIGN KEY (id_variante) REFERENCES public.app_dat_variantes(id),
  CONSTRAINT app_dat_extraccion_productos_id_opcion_variante_fkey FOREIGN KEY (id_opcion_variante) REFERENCES public.app_dat_atributo_opcion(id),
  CONSTRAINT app_dat_extraccion_productos_id_ubicacion_fkey FOREIGN KEY (id_ubicacion) REFERENCES public.app_dat_layout_almacen(id),
  CONSTRAINT app_dat_extraccion_productos_id_presentacion_fkey FOREIGN KEY (id_presentacion) REFERENCES public.app_dat_producto_presentacion(id)
);
CREATE TABLE public.app_dat_garantia_uso (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_garantia_venta bigint NOT NULL,
  id_operacion_devolucion bigint NOT NULL,
  motivo_uso text,
  resultado_garantia smallint NOT NULL,
  observaciones_tecnico text,
  fecha_uso date NOT NULL DEFAULT CURRENT_DATE,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT app_dat_garantia_uso_pkey PRIMARY KEY (id),
  CONSTRAINT fk_garantia_uso_garantia FOREIGN KEY (id_garantia_venta) REFERENCES public.app_dat_garantia_venta(id),
  CONSTRAINT fk_garantia_uso_devolucion FOREIGN KEY (id_operacion_devolucion) REFERENCES public.app_dat_operaciones(id)
);
CREATE TABLE public.app_dat_garantia_venta (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_venta_original bigint NOT NULL,
  id_producto bigint NOT NULL,
  id_variante bigint,
  id_tipo_garantia smallint NOT NULL,
  fecha_venta date NOT NULL,
  fecha_limite_garantia date NOT NULL,
  estado_garantia smallint NOT NULL DEFAULT 1,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT app_dat_garantia_venta_pkey PRIMARY KEY (id),
  CONSTRAINT fk_garantia_venta_venta FOREIGN KEY (id_venta_original) REFERENCES public.app_dat_operaciones(id),
  CONSTRAINT fk_garantia_venta_producto FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT fk_garantia_venta_tipo FOREIGN KEY (id_tipo_garantia) REFERENCES public.app_nom_tipo_garantia(id)
);
CREATE TABLE public.app_dat_gerente (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  uuid uuid NOT NULL,
  id_tienda bigint NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  id_trabajador bigint,
  CONSTRAINT app_dat_gerente_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_dueños_uuid_fkey FOREIGN KEY (uuid) REFERENCES auth.users(id),
  CONSTRAINT app_dat_dueños_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT app_dat_gerente_id_trabajador_fkey FOREIGN KEY (id_trabajador) REFERENCES public.app_dat_trabajadores(id)
);
CREATE TABLE public.app_dat_historial_pre_asignaciones (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_pre_asignacion bigint NOT NULL,
  id_operacion bigint NOT NULL,
  id_tipo_operacion bigint NOT NULL,
  cantidad_anterior numeric NOT NULL,
  cantidad_modificada numeric NOT NULL,
  cantidad_resultante numeric NOT NULL,
  tipo_cambio smallint NOT NULL,
  realizado_por uuid NOT NULL,
  fecha_cambio timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_historial_pre_asignaciones_pkey PRIMARY KEY (id),
  CONSTRAINT fk_historial_pre_asignacion FOREIGN KEY (id_pre_asignacion) REFERENCES public.app_dat_pre_asignaciones(id),
  CONSTRAINT fk_historial_operacion FOREIGN KEY (id_operacion) REFERENCES public.app_dat_operaciones(id),
  CONSTRAINT fk_historial_tipo_operacion FOREIGN KEY (id_tipo_operacion) REFERENCES public.app_nom_tipo_operacion(id),
  CONSTRAINT fk_historial_usuario FOREIGN KEY (realizado_por) REFERENCES auth.users(id)
);
CREATE TABLE public.app_dat_inventario_productos (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_producto bigint NOT NULL,
  id_variante bigint,
  id_opcion_variante bigint,
  id_ubicacion bigint,
  id_presentacion bigint NOT NULL,
  cantidad_inicial numeric NOT NULL,
  sku_producto character varying,
  sku_ubicacion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  cantidad_final numeric,
  origen_cambio smallint NOT NULL,
  id_recepcion bigint,
  id_extraccion bigint,
  id_control bigint,
  id_proveedor bigint,
  CONSTRAINT app_dat_inventario_productos_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_inventario_productos_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_dat_inventario_productos_id_variante_fkey FOREIGN KEY (id_variante) REFERENCES public.app_dat_variantes(id),
  CONSTRAINT app_dat_inventario_productos_id_opcion_variante_fkey FOREIGN KEY (id_opcion_variante) REFERENCES public.app_dat_atributo_opcion(id),
  CONSTRAINT app_dat_inventario_productos_id_presentacion_fkey FOREIGN KEY (id_presentacion) REFERENCES public.app_dat_producto_presentacion(id),
  CONSTRAINT app_dat_inventario_productos_id_control_fkey FOREIGN KEY (id_control) REFERENCES public.app_dat_control_productos(id),
  CONSTRAINT app_dat_inventario_productos_id_proveedor_fkey1 FOREIGN KEY (id_proveedor) REFERENCES carnavalapp.proveedores(id),
  CONSTRAINT app_dat_inventario_productos_id_recepcion_fkey FOREIGN KEY (id_recepcion) REFERENCES public.app_dat_recepcion_productos(id),
  CONSTRAINT app_dat_inventario_productos_id_ubicacion_fkey FOREIGN KEY (id_ubicacion) REFERENCES public.app_dat_layout_almacen(id),
  CONSTRAINT app_dat_inventario_productos_id_extraccion_fkey FOREIGN KEY (id_extraccion) REFERENCES public.app_dat_extraccion_productos(id)
);
CREATE TABLE public.app_dat_layout_abc (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_layout bigint NOT NULL,
  clasificacion_abc smallint NOT NULL DEFAULT '3'::smallint,
  fecha_desde date NOT NULL,
  fecha_hasta date,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_layout_abc_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_layout_abc_id_layout_fkey FOREIGN KEY (id_layout) REFERENCES public.app_dat_layout_almacen(id)
);
CREATE TABLE public.app_dat_layout_almacen (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_almacen bigint NOT NULL,
  id_tipo_layout bigint NOT NULL,
  id_layout_padre bigint,
  denominacion character varying NOT NULL,
  sku_codigo character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  deleted_at timestamp without time zone,
  es_consignacion boolean NOT NULL DEFAULT false,
  CONSTRAINT app_dat_layout_almacen_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_layout_almacen_id_almacen_fkey FOREIGN KEY (id_almacen) REFERENCES public.app_dat_almacen(id),
  CONSTRAINT app_dat_layout_almacen_id_tipo_layout_fkey FOREIGN KEY (id_tipo_layout) REFERENCES public.app_nom_tipo_layout_almacen(id)
);
CREATE TABLE public.app_dat_layout_condiciones (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_layout bigint,
  id_condicion bigint,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_layout_condiciones_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_layout_condiciones_id_layout_fkey FOREIGN KEY (id_layout) REFERENCES public.app_dat_layout_almacen(id),
  CONSTRAINT app_dat_layout_condiciones_id_condicion_fkey FOREIGN KEY (id_condicion) REFERENCES public.app_nom_tipo_condicion(id)
);
CREATE TABLE public.app_dat_liquidacion_consignacion (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_contrato bigint NOT NULL,
  monto_cup numeric NOT NULL CHECK (monto_cup > 0::numeric),
  monto_usd numeric NOT NULL CHECK (monto_usd > 0::numeric),
  tasa_cambio numeric NOT NULL CHECK (tasa_cambio > 0::numeric),
  estado smallint NOT NULL DEFAULT 0 CHECK (estado = ANY (ARRAY[0, 1, 2])),
  observaciones text,
  motivo_rechazo text,
  created_by uuid NOT NULL,
  confirmed_by uuid,
  fecha_liquidacion timestamp with time zone NOT NULL DEFAULT now(),
  fecha_confirmacion timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_liquidacion_consignacion_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_liquidacion_consignacion_contrato_fkey FOREIGN KEY (id_contrato) REFERENCES public.app_dat_contrato_consignacion(id),
  CONSTRAINT app_dat_liquidacion_consignacion_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id),
  CONSTRAINT app_dat_liquidacion_consignacion_confirmed_by_fkey FOREIGN KEY (confirmed_by) REFERENCES auth.users(id)
);
CREATE TABLE public.app_dat_liquidacion_consignacion_backup (
  id bigint,
  id_contrato bigint,
  fecha_inicio date,
  fecha_fin date,
  total_vendido numeric,
  total_comision numeric,
  total_a_pagar numeric,
  estado smallint,
  fecha_pago date,
  metodo_pago character varying,
  referencia_pago character varying,
  observaciones text,
  created_at timestamp with time zone,
  updated_at timestamp with time zone
);
CREATE TABLE public.app_dat_migracion_ajustes (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  total_ajustes bigint,
  ajustes_vinculados bigint,
  ajustes_sin_vincular bigint,
  fecha_migracion timestamp with time zone DEFAULT now(),
  notas text,
  CONSTRAINT app_dat_migracion_ajustes_pkey PRIMARY KEY (id)
);
CREATE TABLE public.app_dat_movimiento_consignacion (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_producto_consignacion bigint NOT NULL,
  tipo_movimiento smallint NOT NULL CHECK (tipo_movimiento = ANY (ARRAY[1, 2, 3, 4])),
  cantidad numeric NOT NULL,
  precio_unitario numeric,
  total numeric,
  id_operacion_venta bigint,
  id_usuario uuid,
  observaciones text,
  fecha_movimiento timestamp with time zone NOT NULL DEFAULT now(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_movimiento_consignacion_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_movimiento_consignacion_producto_fkey FOREIGN KEY (id_producto_consignacion) REFERENCES public.app_dat_producto_consignacion(id),
  CONSTRAINT app_dat_movimiento_consignacion_venta_fkey FOREIGN KEY (id_operacion_venta) REFERENCES public.app_dat_operacion_venta(id_operacion),
  CONSTRAINT app_dat_movimiento_consignacion_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES auth.users(id)
);
CREATE TABLE public.app_dat_notificaciones (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  user_id uuid NOT NULL,
  tipo character varying NOT NULL CHECK (tipo::text = ANY (ARRAY['alerta'::character varying, 'info'::character varying, 'warning'::character varying, 'success'::character varying, 'error'::character varying, 'promocion'::character varying, 'sistema'::character varying, 'pedido'::character varying, 'inventario'::character varying, 'venta'::character varying]::text[])),
  titulo character varying NOT NULL,
  mensaje text NOT NULL,
  data jsonb DEFAULT '{}'::jsonb,
  prioridad character varying DEFAULT 'normal'::character varying CHECK (prioridad::text = ANY (ARRAY['baja'::character varying, 'normal'::character varying, 'alta'::character varying, 'urgente'::character varying]::text[])),
  leida boolean DEFAULT false,
  archivada boolean DEFAULT false,
  accion character varying,
  icono character varying,
  color character varying CHECK (color IS NULL OR color::text ~ '^#[0-9A-Fa-f]{6}$'::text),
  fecha_expiracion timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  leida_at timestamp with time zone,
  CONSTRAINT app_dat_notificaciones_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_notificaciones_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)
);
CREATE TABLE public.app_dat_operacion_extraccion (
  id_operacion bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_motivo_operacion bigint NOT NULL,
  observaciones character varying,
  autorizado_por character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_operacion_extraccion_pkey PRIMARY KEY (id_operacion),
  CONSTRAINT app_dat_operacion_extraccion_id_operacion_fkey FOREIGN KEY (id_operacion) REFERENCES public.app_dat_operaciones(id),
  CONSTRAINT app_dat_operacion_extraccion_id_motivo_operacion_fkey FOREIGN KEY (id_motivo_operacion) REFERENCES public.app_nom_motivo_extraccion(id)
);
CREATE TABLE public.app_dat_operacion_recepcion (
  id_operacion bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  entregado_por character varying,
  recibido_por character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  monto_total numeric,
  observaciones character varying,
  motivo smallint NOT NULL DEFAULT '1'::smallint,
  numero_factura character varying,
  fecha_factura date,
  monto_factura numeric,
  moneda_factura character DEFAULT 'USD'::bpchar,
  pdf_factura text,
  observaciones_compra text,
  tasa_cambio_aplicada numeric,
  fecha_tasa_aplicada timestamp without time zone,
  CONSTRAINT app_dat_operacion_recepcion_pkey PRIMARY KEY (id_operacion),
  CONSTRAINT app_dat_operacion_recepcion_id_operacion_fkey FOREIGN KEY (id_operacion) REFERENCES public.app_dat_operaciones(id)
);
CREATE TABLE public.app_dat_operacion_transferencia (
  id_operacion bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_recepcion bigint NOT NULL,
  id_extraccion bigint NOT NULL,
  autorizado_por character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_operacion_transferencia_pkey PRIMARY KEY (id_operacion),
  CONSTRAINT app_dat_operacion_transferencia_id_operacion_fkey FOREIGN KEY (id_operacion) REFERENCES public.app_dat_operaciones(id),
  CONSTRAINT app_dat_operacion_transferencia_id_recepcion_fkey FOREIGN KEY (id_recepcion) REFERENCES public.app_dat_operaciones(id),
  CONSTRAINT app_dat_operacion_transferencia_id_extraccion_fkey FOREIGN KEY (id_extraccion) REFERENCES public.app_dat_operaciones(id)
);
CREATE TABLE public.app_dat_operacion_venta (
  id_operacion bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_tpv bigint NOT NULL,
  denominacion character varying,
  codigo_promocion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  id_promocion bigint,
  id_cliente bigint,
  importe_total numeric,
  es_pagada boolean NOT NULL DEFAULT true,
  id_turno_apertura bigint,
  precio_con_descuento_total numeric,
  CONSTRAINT app_dat_operacion_venta_pkey PRIMARY KEY (id_operacion),
  CONSTRAINT app_operacion_extraccion_id_operacion_fkey FOREIGN KEY (id_operacion) REFERENCES public.app_dat_operaciones(id),
  CONSTRAINT app_operacion_extraccion_id_tpv_fkey FOREIGN KEY (id_tpv) REFERENCES public.app_dat_tpv(id),
  CONSTRAINT app_dat_operacion_venta_id_promocion_fkey FOREIGN KEY (id_promocion) REFERENCES public.app_mkt_promociones(id),
  CONSTRAINT app_dat_operacion_venta_id_cliente_fkey FOREIGN KEY (id_cliente) REFERENCES public.app_dat_clientes(id),
  CONSTRAINT app_dat_operacion_venta_id_turno_apertura_fkey FOREIGN KEY (id_turno_apertura) REFERENCES public.app_dat_caja_turno(id)
);
CREATE TABLE public.app_dat_operaciones (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_tipo_operacion bigint NOT NULL,
  uuid uuid,
  id_tienda bigint,
  observaciones character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_operaciones_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_operaciones_id_tipo_operacion_fkey FOREIGN KEY (id_tipo_operacion) REFERENCES public.app_nom_tipo_operacion(id),
  CONSTRAINT app_dat_operaciones_uuid_fkey FOREIGN KEY (uuid) REFERENCES auth.users(id),
  CONSTRAINT app_dat_operaciones_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id)
);
CREATE TABLE public.app_dat_pago_venta (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_operacion_venta bigint NOT NULL,
  id_medio_pago smallint NOT NULL,
  monto numeric NOT NULL CHECK (monto >= 0::numeric),
  referencia_pago character varying,
  id_institucion_financiera bigint,
  fecha_pago timestamp with time zone NOT NULL DEFAULT now(),
  creado_por uuid NOT NULL,
  tipo_pago bigint,
  importe_sin_descuento numeric,
  CONSTRAINT app_dat_pago_venta_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_pago_venta_id_operacion_venta_fkey FOREIGN KEY (id_operacion_venta) REFERENCES public.app_dat_operacion_venta(id_operacion),
  CONSTRAINT app_dat_pago_venta_id_medio_pago_fkey FOREIGN KEY (id_medio_pago) REFERENCES public.app_nom_medio_pago(id),
  CONSTRAINT app_dat_pago_venta_creado_por_fkey FOREIGN KEY (creado_por) REFERENCES auth.users(id)
);
CREATE TABLE public.app_dat_pre_asignaciones (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_producto bigint NOT NULL,
  id_variante bigint,
  id_opcion_variante bigint,
  id_presentacion bigint,
  id_ubicacion_origen bigint NOT NULL,
  id_ubicacion_destino bigint,
  id_tienda_destino bigint,
  cantidad numeric NOT NULL CHECK (cantidad > 0::numeric),
  tipo_asignacion smallint NOT NULL DEFAULT 1,
  estado smallint NOT NULL DEFAULT 1,
  motivo text,
  fecha_creacion timestamp with time zone NOT NULL DEFAULT now(),
  fecha_vencimiento timestamp with time zone,
  creado_por uuid NOT NULL,
  confirmado_por uuid,
  fecha_confirmacion timestamp with time zone,
  CONSTRAINT app_dat_pre_asignaciones_pkey PRIMARY KEY (id),
  CONSTRAINT fk_pre_asignacion_producto FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT fk_pre_asignacion_variante FOREIGN KEY (id_variante) REFERENCES public.app_dat_variantes(id),
  CONSTRAINT fk_pre_asignacion_opcion FOREIGN KEY (id_opcion_variante) REFERENCES public.app_dat_atributo_opcion(id),
  CONSTRAINT fk_pre_asignacion_presentacion FOREIGN KEY (id_presentacion) REFERENCES public.app_dat_producto_presentacion(id),
  CONSTRAINT fk_pre_asignacion_ubicacion_origen FOREIGN KEY (id_ubicacion_origen) REFERENCES public.app_dat_layout_almacen(id),
  CONSTRAINT fk_pre_asignacion_ubicacion_destino FOREIGN KEY (id_ubicacion_destino) REFERENCES public.app_dat_layout_almacen(id),
  CONSTRAINT fk_pre_asignacion_tienda_destino FOREIGN KEY (id_tienda_destino) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT fk_pre_asignacion_creado_por FOREIGN KEY (creado_por) REFERENCES auth.users(id),
  CONSTRAINT fk_pre_asignacion_confirmado_por FOREIGN KEY (confirmado_por) REFERENCES auth.users(id)
);
CREATE TABLE public.app_dat_precio_general_tienda (
  id bigint NOT NULL DEFAULT nextval('app_dat_precio_general_tienda_id_seq'::regclass),
  id_tienda bigint NOT NULL,
  precio_regular numeric DEFAULT 0,
  precio_venta_carnaval numeric DEFAULT 5.3,
  precio_venta_carnaval_transferencia numeric DEFAULT 11.1,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT app_dat_precio_general_tienda_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_precio_general_tienda_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id)
);
CREATE TABLE public.app_dat_precio_tpv (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_producto bigint NOT NULL,
  id_tpv bigint NOT NULL,
  precio_venta_cup numeric NOT NULL CHECK (precio_venta_cup > 0::numeric),
  fecha_desde date NOT NULL DEFAULT CURRENT_DATE,
  fecha_hasta date,
  es_activo boolean NOT NULL DEFAULT true,
  deleted_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT app_dat_precio_tpv_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_precio_tpv_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_dat_precio_tpv_id_tpv_fkey FOREIGN KEY (id_tpv) REFERENCES public.app_dat_tpv(id)
);
CREATE TABLE public.app_dat_precio_venta (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_producto bigint NOT NULL,
  id_variante bigint,
  precio_venta_cup numeric NOT NULL DEFAULT '0'::numeric,
  fecha_desde date NOT NULL,
  fecha_hasta date,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  precio_descuento numeric,
  CONSTRAINT app_dat_precio_venta_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_precio_venta_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_dat_precio_venta_id_variante_fkey FOREIGN KEY (id_variante) REFERENCES public.app_dat_variantes(id)
);
CREATE TABLE public.app_dat_preferencias_notificaciones (
  id_usuario uuid NOT NULL,
  estado text NOT NULL CHECK (estado = ANY (ARRAY['aceptado'::text, 'denegado'::text, 'mas_tarde'::text, 'nunca'::text])),
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT app_dat_preferencias_notificaciones_pkey PRIMARY KEY (id_usuario),
  CONSTRAINT app_dat_preferencias_notificaciones_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES auth.users(id)
);
CREATE TABLE public.app_dat_presentacion_unidad_medida (
  id integer NOT NULL DEFAULT nextval('app_dat_presentacion_unidad_medida_id_seq'::regclass),
  id_producto integer NOT NULL,
  id_presentacion integer NOT NULL,
  id_unidad_medida integer NOT NULL,
  cantidad_um numeric NOT NULL DEFAULT 1.0 CHECK (cantidad_um > 0::numeric),
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT app_dat_presentacion_unidad_medida_pkey PRIMARY KEY (id),
  CONSTRAINT fk_presentacion_um_producto FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT fk_presentacion_um_presentacion FOREIGN KEY (id_presentacion) REFERENCES public.app_nom_presentacion(id),
  CONSTRAINT fk_presentacion_um_unidad_medida FOREIGN KEY (id_unidad_medida) REFERENCES public.app_nom_unidades_medida(id)
);
CREATE TABLE public.app_dat_producto (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_tienda bigint NOT NULL,
  sku character varying,
  id_categoria bigint NOT NULL,
  denominacion character varying NOT NULL,
  nombre_comercial character varying,
  denominacion_corta character varying,
  descripcion character varying,
  descripcion_corta character varying,
  um character varying,
  es_refrigerado boolean DEFAULT false,
  es_fragil boolean DEFAULT false,
  es_peligroso boolean DEFAULT false,
  es_vendible boolean DEFAULT true,
  es_comprable boolean DEFAULT true,
  es_inventariable boolean DEFAULT true,
  es_por_lotes boolean DEFAULT false,
  dias_alert_caducidad numeric,
  codigo_barras character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  imagen text,
  es_elaborado boolean DEFAULT false,
  es_servicio boolean DEFAULT false,
  deleted_at timestamp without time zone,
  id_vendedor_app bigint,
  mostrar_en_catalogo boolean DEFAULT false,
  id_proveedor integer,
  CONSTRAINT app_dat_producto_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_producto_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT app_dat_producto_id_categoria_fkey FOREIGN KEY (id_categoria) REFERENCES public.app_dat_categoria(id),
  CONSTRAINT app_dat_producto_id_proveedor_fkey FOREIGN KEY (id_proveedor) REFERENCES public.app_dat_proveedor(id)
);
CREATE TABLE public.app_dat_producto_abc (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_producto bigint NOT NULL,
  id_proveedor bigint,
  clasificacion smallint NOT NULL DEFAULT '3'::smallint,
  fecha_desde date NOT NULL,
  fecha_hasta date,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_producto_abc_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_producto_abc_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_dat_producto_abc_id_proveedor_fkey FOREIGN KEY (id_proveedor) REFERENCES public.app_dat_proveedor(id)
);
CREATE TABLE public.app_dat_producto_consignacion (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_contrato bigint NOT NULL,
  id_producto bigint NOT NULL,
  id_variante bigint,
  id_presentacion bigint,
  cantidad_enviada numeric NOT NULL DEFAULT 0,
  cantidad_vendida numeric NOT NULL DEFAULT 0,
  cantidad_devuelta numeric NOT NULL DEFAULT 0,
  precio_venta_sugerido numeric,
  estado smallint NOT NULL DEFAULT 1,
  fecha_envio date NOT NULL DEFAULT CURRENT_DATE,
  fecha_finalizacion date,
  observaciones text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  puede_modificar_precio boolean NOT NULL DEFAULT false,
  id_ubicacion_origen bigint,
  precio_venta numeric NOT NULL DEFAULT '0'::numeric,
  id_operacion_extraccion bigint,
  id_operacion_recepcion bigint,
  CONSTRAINT app_dat_producto_consignacion_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_producto_consignacion_contrato_fkey FOREIGN KEY (id_contrato) REFERENCES public.app_dat_contrato_consignacion(id),
  CONSTRAINT app_dat_producto_consignacion_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_dat_producto_consignacion_variante_fkey FOREIGN KEY (id_variante) REFERENCES public.app_dat_variantes(id),
  CONSTRAINT app_dat_producto_consignacion_presentacion_fkey FOREIGN KEY (id_presentacion) REFERENCES public.app_dat_producto_presentacion(id),
  CONSTRAINT app_dat_producto_consignacion_ubicacion_fkey FOREIGN KEY (id_ubicacion_origen) REFERENCES public.app_dat_layout_almacen(id),
  CONSTRAINT app_dat_producto_consignacion_operacion_extraccion_fkey FOREIGN KEY (id_operacion_extraccion) REFERENCES public.app_dat_operaciones(id),
  CONSTRAINT app_dat_producto_consignacion_operacion_recepcion_fkey FOREIGN KEY (id_operacion_recepcion) REFERENCES public.app_dat_operaciones(id)
);
CREATE TABLE public.app_dat_producto_consignacion_duplicado (
  id integer NOT NULL DEFAULT nextval('app_dat_producto_consignacion_duplicado_id_seq'::regclass),
  id_producto_original bigint NOT NULL,
  id_producto_duplicado bigint NOT NULL,
  id_contrato_consignacion integer NOT NULL,
  id_tienda_origen integer NOT NULL,
  id_tienda_destino integer NOT NULL,
  fecha_duplicacion timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
  duplicado_por uuid,
  id_presentacion_original bigint,
  id_presentacion_duplicada bigint,
  CONSTRAINT app_dat_producto_consignacion_duplicado_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_producto_consignacion_duplica_id_producto_original_fkey FOREIGN KEY (id_producto_original) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_dat_producto_consignacion_duplic_id_producto_duplicado_fkey FOREIGN KEY (id_producto_duplicado) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_dat_producto_consignacion_dup_id_contrato_consignacion_fkey FOREIGN KEY (id_contrato_consignacion) REFERENCES public.app_dat_contrato_consignacion(id),
  CONSTRAINT app_dat_producto_consignacion_duplicado_id_tienda_origen_fkey FOREIGN KEY (id_tienda_origen) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT app_dat_producto_consignacion_duplicado_id_tienda_destino_fkey FOREIGN KEY (id_tienda_destino) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT fk_pcd_presentacion_original FOREIGN KEY (id_presentacion_original) REFERENCES public.app_dat_producto_presentacion(id),
  CONSTRAINT fk_pcd_presentacion_duplicada FOREIGN KEY (id_presentacion_duplicada) REFERENCES public.app_dat_producto_presentacion(id)
);
CREATE TABLE public.app_dat_producto_etiquetas (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_producto bigint,
  etiqueta character varying NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_producto_etiquetas_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_producto_etiquetas_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id)
);
CREATE TABLE public.app_dat_producto_garantia (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_producto bigint NOT NULL UNIQUE,
  id_tipo_garantia smallint NOT NULL DEFAULT 1,
  condiciones_especificas text,
  es_activo boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT app_dat_producto_garantia_pkey PRIMARY KEY (id),
  CONSTRAINT fk_producto_garantia_producto FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT fk_producto_garantia_tipo FOREIGN KEY (id_tipo_garantia) REFERENCES public.app_nom_tipo_garantia(id)
);
CREATE TABLE public.app_dat_producto_ingredientes (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_producto_elaborado bigint NOT NULL,
  id_ingrediente bigint NOT NULL,
  cantidad_necesaria numeric NOT NULL,
  unidad_medida character varying DEFAULT '''g''::character varying'::character varying,
  costo_unitario numeric,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_producto_ingredientes_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_producto_ingredientes_ingrediente_fkey FOREIGN KEY (id_ingrediente) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_dat_producto_ingredientes_id_producto_elaborado_fkey FOREIGN KEY (id_producto_elaborado) REFERENCES public.app_dat_producto(id)
);
CREATE TABLE public.app_dat_producto_multimedias (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_producto bigint,
  media character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_producto_multimedias_pkey PRIMARY KEY (id),
  CONSTRAINT app_producto_multimedias_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id)
);
CREATE TABLE public.app_dat_producto_presentacion (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_producto bigint NOT NULL,
  id_presentacion bigint NOT NULL,
  cantidad numeric NOT NULL,
  es_base boolean NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  precio_promedio real DEFAULT '0'::real,
  CONSTRAINT app_dat_producto_presentacion_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_producto_presentacion_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_dat_producto_presentacion_id_presentacion_fkey FOREIGN KEY (id_presentacion) REFERENCES public.app_nom_presentacion(id)
);
CREATE TABLE public.app_dat_producto_rating (
  id bigint NOT NULL DEFAULT nextval('app_dat_producto_rating_id_seq'::regclass),
  id_producto bigint NOT NULL,
  id_usuario uuid NOT NULL,
  rating numeric NOT NULL CHECK (rating >= 1.0 AND rating <= 5.0),
  comentario text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT app_dat_producto_rating_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_producto_rating_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_dat_producto_rating_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES auth.users(id)
);
CREATE TABLE public.app_dat_producto_unidades (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_producto bigint NOT NULL,
  id_unidad_medida bigint NOT NULL,
  factor_producto numeric NOT NULL DEFAULT 1.0,
  es_unidad_compra boolean NOT NULL DEFAULT false,
  es_unidad_venta boolean NOT NULL DEFAULT false,
  es_unidad_inventario boolean NOT NULL DEFAULT false,
  observaciones text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_producto_unidades_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_producto_unidades_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_dat_producto_unidades_unidad_fkey FOREIGN KEY (id_unidad_medida) REFERENCES public.app_nom_unidades_medida(id)
);
CREATE TABLE public.app_dat_productos_subcategorias (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_producto bigint NOT NULL,
  id_sub_categoria bigint NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_productos_subcategorias_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_productos_subcategorias_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_dat_productos_subcategorias_id_sub_categoria_fkey FOREIGN KEY (id_sub_categoria) REFERENCES public.app_dat_subcategorias(id)
);
CREATE TABLE public.app_dat_proveedor (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  denominacion character varying NOT NULL,
  direccion character varying,
  ubicacion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  sku_codigo character varying NOT NULL,
  lead_time integer,
  idtienda bigint,
  CONSTRAINT app_dat_proveedor_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_proveedor_idtienda_fkey FOREIGN KEY (idtienda) REFERENCES public.app_dat_tienda(id)
);
CREATE TABLE public.app_dat_recepcion_productos (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_operacion bigint,
  id_producto bigint,
  id_variante bigint,
  id_opcion_variante bigint,
  id_proveedor bigint,
  id_ubicacion bigint,
  id_presentacion bigint,
  cantidad numeric NOT NULL,
  precio_unitario numeric,
  sku_producto character varying,
  sku_ubicacion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  precio_referencia numeric,
  descuento_porcentaje numeric DEFAULT 0,
  descuento_monto numeric DEFAULT 0,
  costo_real numeric DEFAULT ((precio_unitario - COALESCE(descuento_monto, (0)::numeric)) - ((precio_referencia * descuento_porcentaje) / (100)::numeric)),
  bonificacion_cantidad numeric DEFAULT 0,
  CONSTRAINT app_dat_recepcion_productos_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_recepcion_productos_id_operacion_fkey FOREIGN KEY (id_operacion) REFERENCES public.app_dat_operaciones(id),
  CONSTRAINT app_dat_recepcion_productos_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_dat_recepcion_productos_id_variante_fkey FOREIGN KEY (id_variante) REFERENCES public.app_dat_variantes(id),
  CONSTRAINT app_dat_recepcion_productos_id_opcion_variante_fkey FOREIGN KEY (id_opcion_variante) REFERENCES public.app_dat_atributo_opcion(id),
  CONSTRAINT app_dat_recepcion_productos_id_proveedor_fkey FOREIGN KEY (id_proveedor) REFERENCES public.app_dat_proveedor(id),
  CONSTRAINT app_dat_recepcion_productos_id_ubicacion_fkey FOREIGN KEY (id_ubicacion) REFERENCES public.app_dat_layout_almacen(id),
  CONSTRAINT app_dat_recepcion_productos_id_presentacion_fkey FOREIGN KEY (id_presentacion) REFERENCES public.app_dat_producto_presentacion(id)
);
CREATE TABLE public.app_dat_subcategorias (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  idcategoria bigint NOT NULL,
  denominacion character varying NOT NULL,
  sku_codigo character varying NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_subcategorias_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_subcategorias_idcategoria_fkey FOREIGN KEY (idcategoria) REFERENCES public.app_dat_categoria(id)
);
CREATE TABLE public.app_dat_superadmin (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  uuid uuid NOT NULL UNIQUE,
  nombre character varying NOT NULL,
  apellidos character varying NOT NULL,
  email character varying NOT NULL UNIQUE,
  telefono character varying,
  activo boolean NOT NULL DEFAULT true,
  nivel_acceso smallint NOT NULL DEFAULT 1,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  ultimo_acceso timestamp with time zone,
  CONSTRAINT app_dat_superadmin_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_superadmin_uuid_fkey FOREIGN KEY (uuid) REFERENCES auth.users(id)
);
CREATE TABLE public.app_dat_supervisor (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  uuid uuid NOT NULL,
  id_tienda bigint NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  id_trabajador bigint,
  CONSTRAINT app_dat_supervisor_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_supervisor_uuid_fkey FOREIGN KEY (uuid) REFERENCES auth.users(id),
  CONSTRAINT app_dat_supervisor_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT app_dat_supervisor_id_trabajador_fkey FOREIGN KEY (id_trabajador) REFERENCES public.app_dat_trabajadores(id)
);
CREATE TABLE public.app_dat_suscripcion_catalogo (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  id_tienda bigint,
  tiempo_suscripcion numeric,
  vencido boolean,
  CONSTRAINT app_dat_suscripcion_catalogo_pkey PRIMARY KEY (id)
);
CREATE TABLE public.app_dat_suscripcion_notificaciones_producto (
  id bigint NOT NULL DEFAULT nextval('app_dat_suscripcion_notificaciones_producto_id_seq'::regclass),
  id_usuario uuid NOT NULL,
  id_producto bigint NOT NULL,
  activo boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT app_dat_suscripcion_notificaciones_producto_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_suscripcion_notificaciones_producto_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES auth.users(id),
  CONSTRAINT app_dat_suscripcion_notificaciones_producto_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id)
);
CREATE TABLE public.app_dat_suscripcion_notificaciones_tienda (
  id bigint NOT NULL DEFAULT nextval('app_dat_suscripcion_notificaciones_tienda_id_seq'::regclass),
  id_usuario uuid NOT NULL,
  id_tienda bigint NOT NULL,
  activo boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT app_dat_suscripcion_notificaciones_tienda_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_suscripcion_notificaciones_tienda_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES auth.users(id),
  CONSTRAINT app_dat_suscripcion_notificaciones_tienda_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id)
);
CREATE TABLE public.app_dat_tienda (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  denominacion character varying NOT NULL,
  direccion character varying,
  ubicacion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  imagen_url text,
  phone text,
  admin_carnaval boolean DEFAULT false,
  id_tienda_carnaval bigint,
  pais character varying,
  estado character varying,
  nombre_pais character varying,
  nombre_estado character varying,
  latitude numeric,
  longitude numeric,
  mostrar_en_catalogo boolean DEFAULT false,
  dias_trabajo jsonb DEFAULT '["lunes", "martes", "miércoles", "jueves", "viernes"]'::jsonb,
  hora_apertura time without time zone DEFAULT '09:00:00'::time without time zone,
  hora_cierre time without time zone DEFAULT '18:00:00'::time without time zone,
  provincia character varying,
  only_catalogo boolean DEFAULT false,
  validada boolean DEFAULT false,
  layout_catalogo bigint,
  CONSTRAINT app_dat_tienda_pkey PRIMARY KEY (id),
  CONSTRAINT fk_tienda_layout_catalogo FOREIGN KEY (layout_catalogo) REFERENCES public.app_dat_layout_almacen(id)
);
CREATE TABLE public.app_dat_tienda_rating (
  id bigint NOT NULL DEFAULT nextval('app_dat_tienda_rating_id_seq'::regclass),
  id_tienda bigint NOT NULL,
  id_usuario uuid NOT NULL,
  rating numeric NOT NULL CHECK (rating >= 1.0 AND rating <= 5.0),
  comentario text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT app_dat_tienda_rating_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_tienda_rating_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT app_dat_tienda_rating_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES auth.users(id)
);
CREATE TABLE public.app_dat_tpv (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_tienda bigint NOT NULL,
  id_almacen bigint NOT NULL,
  denominacion character varying NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_tpv_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_tpv_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT app_dat_tpv_id_almacen_fkey FOREIGN KEY (id_almacen) REFERENCES public.app_dat_almacen(id)
);
CREATE TABLE public.app_dat_tpv_dispositivos (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_tpv bigint NOT NULL,
  tipo_dispositivo smallint NOT NULL,
  identificador character varying NOT NULL,
  configuracion jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_tpv_dispositivos_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_tpv_dispositivos_fkey FOREIGN KEY (id_tpv) REFERENCES public.app_dat_tpv(id)
);
CREATE TABLE public.app_dat_trabajadores (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_tienda bigint,
  id_roll bigint,
  nombres character varying,
  apellidos character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  uuid uuid,
  deleted_at timestamp with time zone,
  salario_horas numeric NOT NULL DEFAULT 0,
  maneja_apertura_control boolean DEFAULT true,
  CONSTRAINT app_dat_trabajadores_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_trabajadores_id_roll_fkey FOREIGN KEY (id_roll) REFERENCES public.seg_roll(id),
  CONSTRAINT app_dat_trabajadores_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT app_dat_trabajadores_uuid_fkey FOREIGN KEY (uuid) REFERENCES auth.users(id)
);
CREATE TABLE public.app_dat_turno_trabajadores (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_turno bigint NOT NULL,
  id_trabajador bigint NOT NULL,
  hora_entrada timestamp with time zone NOT NULL DEFAULT now(),
  hora_salida timestamp with time zone,
  observaciones text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  manual_changed uuid,
  horas_trabajadas numeric DEFAULT 
CASE
    WHEN (hora_salida IS NOT NULL) THEN round((EXTRACT(epoch FROM (hora_salida - hora_entrada)) / 3600.0), 1)
    ELSE NULL::numeric
END,
  CONSTRAINT app_dat_turno_trabajadores_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_turno_trabajadores_id_turno_fkey FOREIGN KEY (id_turno) REFERENCES public.app_dat_caja_turno(id),
  CONSTRAINT app_dat_turno_trabajadores_id_trabajador_fkey FOREIGN KEY (id_trabajador) REFERENCES public.app_dat_trabajadores(id),
  CONSTRAINT app_dat_turno_trabajadores_manual_changed_fkey FOREIGN KEY (manual_changed) REFERENCES auth.users(id)
);
CREATE TABLE public.app_dat_variantes (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_sub_categoria bigint NOT NULL,
  id_atributo bigint NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_variantes_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_variantes_id_sub_categoria_fkey FOREIGN KEY (id_sub_categoria) REFERENCES public.app_dat_subcategorias(id),
  CONSTRAINT app_dat_variantes_id_atributo_fkey FOREIGN KEY (id_atributo) REFERENCES public.app_dat_atributos(id)
);
CREATE TABLE public.app_dat_vendedor (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  uuid uuid NOT NULL,
  id_tpv bigint,
  numero_confirmacion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  id_trabajador bigint,
  permitir_customizar_precio_venta boolean DEFAULT false,
  CONSTRAINT app_dat_vendedor_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_vendedor_uuid_fkey FOREIGN KEY (uuid) REFERENCES auth.users(id),
  CONSTRAINT app_dat_vendedor_id_tpv_fkey FOREIGN KEY (id_tpv) REFERENCES public.app_dat_tpv(id),
  CONSTRAINT app_dat_vendedor_id_trabajador_fkey FOREIGN KEY (id_trabajador) REFERENCES public.app_dat_trabajadores(id)
);
CREATE TABLE public.app_mkt_campanas (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_tienda bigint NOT NULL,
  id_tipo_campana smallint NOT NULL,
  nombre character varying NOT NULL,
  descripcion text,
  fecha_inicio timestamp with time zone NOT NULL,
  fecha_fin timestamp with time zone NOT NULL,
  presupuesto numeric,
  estado smallint NOT NULL DEFAULT 1,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_mkt_campanas_pkey PRIMARY KEY (id),
  CONSTRAINT app_mkt_campanas_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT app_mkt_campanas_id_tipo_campana_fkey FOREIGN KEY (id_tipo_campana) REFERENCES public.app_mkt_tipo_campana(id)
);
CREATE TABLE public.app_mkt_cliente_promociones (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_cliente bigint NOT NULL,
  id_promocion bigint NOT NULL,
  id_operacion bigint,
  fecha_uso timestamp with time zone NOT NULL DEFAULT now(),
  descuento_aplicado numeric,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_mkt_cliente_promociones_pkey PRIMARY KEY (id),
  CONSTRAINT app_mkt_cliente_promociones_id_cliente_fkey FOREIGN KEY (id_cliente) REFERENCES public.app_dat_clientes(id),
  CONSTRAINT app_mkt_cliente_promociones_id_promocion_fkey FOREIGN KEY (id_promocion) REFERENCES public.app_mkt_promociones(id),
  CONSTRAINT app_mkt_cliente_promociones_id_operacion_fkey FOREIGN KEY (id_operacion) REFERENCES public.app_dat_operaciones(id)
);
CREATE TABLE public.app_mkt_comunicacion_clientes (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_comunicacion bigint NOT NULL,
  id_cliente bigint NOT NULL,
  fecha_envio timestamp with time zone NOT NULL,
  estado smallint NOT NULL,
  fecha_apertura timestamp with time zone,
  interacciones jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_mkt_comunicacion_clientes_pkey PRIMARY KEY (id),
  CONSTRAINT app_mkt_comunicacion_clientes_id_comunicacion_fkey FOREIGN KEY (id_comunicacion) REFERENCES public.app_mkt_comunicaciones(id),
  CONSTRAINT app_mkt_comunicacion_clientes_id_cliente_fkey FOREIGN KEY (id_cliente) REFERENCES public.app_dat_clientes(id)
);
CREATE TABLE public.app_mkt_comunicaciones (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_campana bigint,
  id_segmento bigint,
  id_tienda bigint NOT NULL,
  id_tipo_campana smallint NOT NULL,
  asunto character varying,
  contenido text NOT NULL,
  fecha_envio timestamp with time zone,
  fecha_programada timestamp with time zone,
  estado smallint NOT NULL DEFAULT 1,
  metricas jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_mkt_comunicaciones_pkey PRIMARY KEY (id),
  CONSTRAINT app_mkt_comunicaciones_id_campana_fkey FOREIGN KEY (id_campana) REFERENCES public.app_mkt_campanas(id),
  CONSTRAINT app_mkt_comunicaciones_id_segmento_fkey FOREIGN KEY (id_segmento) REFERENCES public.app_mkt_segmentos(id),
  CONSTRAINT app_mkt_comunicaciones_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT app_mkt_comunicaciones_id_tipo_campana_fkey FOREIGN KEY (id_tipo_campana) REFERENCES public.app_mkt_tipo_campana(id)
);
CREATE TABLE public.app_mkt_criterios_segmentacion (
  id smallint NOT NULL,
  denominacion character varying NOT NULL,
  campo_db character varying NOT NULL,
  tipo_dato character varying NOT NULL,
  descripcion text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_mkt_criterios_segmentacion_pkey PRIMARY KEY (id)
);
CREATE TABLE public.app_mkt_eventos_fidelizacion (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_cliente bigint NOT NULL,
  id_tienda bigint NOT NULL,
  tipo_evento smallint NOT NULL,
  puntos numeric NOT NULL,
  descripcion text,
  id_operacion bigint,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_mkt_eventos_fidelizacion_pkey PRIMARY KEY (id),
  CONSTRAINT app_mkt_eventos_fidelizacion_id_cliente_fkey FOREIGN KEY (id_cliente) REFERENCES public.app_dat_clientes(id),
  CONSTRAINT app_mkt_eventos_fidelizacion_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT app_mkt_eventos_fidelizacion_id_operacion_fkey FOREIGN KEY (id_operacion) REFERENCES public.app_dat_operaciones(id)
);
CREATE TABLE public.app_mkt_function_logs (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  function_name character varying NOT NULL,
  usuario_uuid uuid,
  id_tienda bigint,
  parametros jsonb,
  resultado character varying,
  mensaje_error text,
  tiempo_ejecucion interval,
  fecha_acceso timestamp with time zone DEFAULT now(),
  ip_address inet,
  CONSTRAINT app_mkt_function_logs_pkey PRIMARY KEY (id)
);
CREATE TABLE public.app_mkt_promocion_productos (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_promocion bigint NOT NULL,
  id_producto bigint,
  id_categoria bigint,
  id_subcategoria bigint,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_mkt_promocion_productos_pkey PRIMARY KEY (id),
  CONSTRAINT app_mkt_promocion_productos_id_promocion_fkey FOREIGN KEY (id_promocion) REFERENCES public.app_mkt_promociones(id),
  CONSTRAINT app_mkt_promocion_productos_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_mkt_promocion_productos_id_categoria_fkey FOREIGN KEY (id_categoria) REFERENCES public.app_dat_categoria(id),
  CONSTRAINT app_mkt_promocion_productos_id_subcategoria_fkey FOREIGN KEY (id_subcategoria) REFERENCES public.app_dat_subcategorias(id)
);
CREATE TABLE public.app_mkt_promocion_segmento (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_promocion bigint NOT NULL,
  id_segmento bigint NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_mkt_promocion_segmento_pkey PRIMARY KEY (id),
  CONSTRAINT app_mkt_promocion_segmento_id_promocion_fkey FOREIGN KEY (id_promocion) REFERENCES public.app_mkt_promociones(id),
  CONSTRAINT app_mkt_promocion_segmento_id_segmento_fkey FOREIGN KEY (id_segmento) REFERENCES public.app_mkt_segmentos(id)
);
CREATE TABLE public.app_mkt_promociones (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_campana bigint,
  id_tienda bigint NOT NULL,
  id_tipo_promocion smallint NOT NULL,
  codigo_promocion character varying NOT NULL,
  nombre character varying NOT NULL,
  descripcion text,
  valor_descuento numeric,
  fecha_inicio timestamp with time zone NOT NULL,
  fecha_fin timestamp with time zone,
  min_compra numeric,
  limite_usos integer,
  aplica_todo boolean DEFAULT false,
  estado boolean DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  requiere_medio_pago boolean NOT NULL DEFAULT false,
  id_medio_pago_requerido smallint,
  CONSTRAINT app_mkt_promociones_pkey PRIMARY KEY (id),
  CONSTRAINT app_mkt_promociones_id_campana_fkey FOREIGN KEY (id_campana) REFERENCES public.app_mkt_campanas(id),
  CONSTRAINT app_mkt_promociones_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT app_mkt_promociones_id_tipo_promocion_fkey FOREIGN KEY (id_tipo_promocion) REFERENCES public.app_mkt_tipo_promocion(id),
  CONSTRAINT fk_promocion_medio_pago FOREIGN KEY (id_medio_pago_requerido) REFERENCES public.app_nom_medio_pago(id)
);
CREATE TABLE public.app_mkt_promociones_audit (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_promocion bigint NOT NULL,
  accion character varying NOT NULL,
  usuario_uuid uuid,
  fecha_accion timestamp with time zone DEFAULT now(),
  datos_anteriores jsonb,
  datos_nuevos jsonb,
  ip_address inet,
  user_agent text,
  CONSTRAINT app_mkt_promociones_audit_pkey PRIMARY KEY (id)
);
CREATE TABLE public.app_mkt_segmentos (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_tienda bigint NOT NULL,
  nombre character varying NOT NULL,
  descripcion text,
  criterios jsonb NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_mkt_segmentos_pkey PRIMARY KEY (id),
  CONSTRAINT app_mkt_segmentos_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id)
);
CREATE TABLE public.app_mkt_tipo_campana (
  id smallint NOT NULL,
  denominacion character varying NOT NULL,
  descripcion text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_mkt_tipo_campana_pkey PRIMARY KEY (id)
);
CREATE TABLE public.app_mkt_tipo_promocion (
  id smallint NOT NULL,
  denominacion character varying NOT NULL,
  descripcion text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_mkt_tipo_promocion_pkey PRIMARY KEY (id)
);
CREATE TABLE public.app_nom_categoria_gasto (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  denominacion character varying NOT NULL,
  descripcion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_nom_categoria_gasto_pkey PRIMARY KEY (id)
);
CREATE TABLE public.app_nom_conversiones_unidades (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_unidad_origen bigint NOT NULL,
  id_unidad_destino bigint NOT NULL,
  factor_conversion numeric NOT NULL,
  es_aproximada boolean NOT NULL DEFAULT false,
  observaciones text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_nom_conversiones_unidades_pkey PRIMARY KEY (id),
  CONSTRAINT app_nom_conversiones_unidades_origen_fkey FOREIGN KEY (id_unidad_origen) REFERENCES public.app_nom_unidades_medida(id),
  CONSTRAINT app_nom_conversiones_unidades_destino_fkey FOREIGN KEY (id_unidad_destino) REFERENCES public.app_nom_unidades_medida(id)
);
CREATE TABLE public.app_nom_estado_operacion (
  id smallint NOT NULL,
  denominacion character varying NOT NULL UNIQUE,
  descripcion text,
  categoria smallint NOT NULL DEFAULT 1,
  es_activo boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT app_nom_estado_operacion_pkey PRIMARY KEY (id)
);
CREATE TABLE public.app_nom_medio_pago (
  id smallint NOT NULL,
  denominacion character varying NOT NULL,
  descripcion text,
  es_digital boolean NOT NULL DEFAULT false,
  es_efectivo boolean NOT NULL DEFAULT false,
  es_activo boolean NOT NULL DEFAULT true,
  CONSTRAINT app_nom_medio_pago_pkey PRIMARY KEY (id)
);
CREATE TABLE public.app_nom_motivo_extraccion (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  denominacion character varying NOT NULL,
  descripcion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_nom_motivo_extraccion_pkey PRIMARY KEY (id)
);
CREATE TABLE public.app_nom_motivo_recepcion (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  denominacion character varying NOT NULL,
  descripcion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  id_tipo_operacion bigint,
  CONSTRAINT app_nom_motivo_recepcion_pkey PRIMARY KEY (id),
  CONSTRAINT app_nom_motivo_recepcion_id_tipo_operacion_fkey FOREIGN KEY (id_tipo_operacion) REFERENCES public.app_nom_tipo_operacion(id)
);
CREATE TABLE public.app_nom_naturaleza_costo (
  id smallint NOT NULL,
  denominacion character varying NOT NULL,
  descripcion text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_nom_naturaleza_costo_pkey PRIMARY KEY (id)
);
CREATE TABLE public.app_nom_presentacion (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  denominacion character varying NOT NULL,
  descripcion character varying,
  sku_codigo character varying NOT NULL UNIQUE,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  es_fraccionable boolean DEFAULT false,
  CONSTRAINT app_nom_presentacion_pkey PRIMARY KEY (id)
);
CREATE TABLE public.app_nom_subcategoria_gasto (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_categoria_gasto bigint,
  denominacion character varying NOT NULL,
  descripcion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_nom_subcategoria_gasto_pkey PRIMARY KEY (id),
  CONSTRAINT app_nom_subcategoria_gasto_id_categoria_gasto_fkey FOREIGN KEY (id_categoria_gasto) REFERENCES public.app_nom_categoria_gasto(id)
);
CREATE TABLE public.app_nom_tipo_condicion (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  denominacion character varying NOT NULL,
  descripcion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  es_refrigerado boolean NOT NULL DEFAULT false,
  es_fragil boolean NOT NULL DEFAULT false,
  es_peligroso boolean NOT NULL DEFAULT false,
  CONSTRAINT app_nom_tipo_condicion_pkey PRIMARY KEY (id)
);
CREATE TABLE public.app_nom_tipo_garantia (
  id smallint NOT NULL,
  denominacion character varying NOT NULL UNIQUE,
  descripcion text,
  dias_validez integer NOT NULL,
  es_activo boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT app_nom_tipo_garantia_pkey PRIMARY KEY (id)
);
CREATE TABLE public.app_nom_tipo_layout_almacen (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  denominacion character varying NOT NULL UNIQUE,
  sku_codigo character varying NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_nom_tipo_layout_almacen_pkey PRIMARY KEY (id)
);
CREATE TABLE public.app_nom_tipo_operacion (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  denominacion character varying NOT NULL UNIQUE,
  descripcion character varying,
  accion text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_nom_tipo_operacion_pkey PRIMARY KEY (id)
);
CREATE TABLE public.app_nom_unidades_medida (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  denominacion character varying NOT NULL UNIQUE,
  abreviatura character varying NOT NULL UNIQUE,
  tipo_unidad smallint NOT NULL,
  es_base boolean NOT NULL DEFAULT false,
  factor_base numeric,
  descripcion text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_nom_unidades_medida_pkey PRIMARY KEY (id)
);
CREATE TABLE public.app_suscripciones (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_tienda bigint NOT NULL,
  id_plan smallint NOT NULL,
  fecha_inicio timestamp with time zone NOT NULL DEFAULT now(),
  fecha_fin timestamp with time zone,
  estado smallint NOT NULL DEFAULT 1,
  metodo_pago character varying,
  id_pago_externo character varying,
  creado_por uuid NOT NULL,
  renovacion_automatica boolean DEFAULT false,
  observaciones text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  gestionado_por text,
  CONSTRAINT app_suscripciones_pkey PRIMARY KEY (id),
  CONSTRAINT app_suscripciones_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT app_suscripciones_id_plan_fkey FOREIGN KEY (id_plan) REFERENCES public.app_suscripciones_plan(id),
  CONSTRAINT app_suscripciones_creado_por_fkey FOREIGN KEY (creado_por) REFERENCES auth.users(id)
);
CREATE TABLE public.app_suscripciones_historial (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_suscripcion bigint NOT NULL,
  id_plan_anterior smallint,
  id_plan_nuevo smallint,
  estado_anterior smallint,
  estado_nuevo smallint,
  fecha_cambio timestamp with time zone NOT NULL DEFAULT now(),
  cambiado_por uuid NOT NULL,
  motivo text,
  evidencia text,
  CONSTRAINT app_suscripciones_historial_pkey PRIMARY KEY (id),
  CONSTRAINT app_suscripciones_historial_id_suscripcion_fkey FOREIGN KEY (id_suscripcion) REFERENCES public.app_suscripciones(id),
  CONSTRAINT app_suscripciones_historial_cambiado_por_fkey FOREIGN KEY (cambiado_por) REFERENCES auth.users(id)
);
CREATE TABLE public.app_suscripciones_plan (
  id smallint GENERATED ALWAYS AS IDENTITY NOT NULL,
  denominacion character varying NOT NULL,
  descripcion text,
  precio_mensual numeric NOT NULL,
  duracion_trial_dias integer NOT NULL DEFAULT 15,
  limite_tiendas smallint DEFAULT 1,
  limite_usuarios smallint DEFAULT 5,
  funciones_habilitadas jsonb,
  es_activo boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  periodo smallint NOT NULL DEFAULT '1'::smallint,
  moneda text NOT NULL DEFAULT 'USD'::text,
  CONSTRAINT app_suscripciones_plan_pkey PRIMARY KEY (id)
);
CREATE TABLE public.app_suscripciones_renovaciones_resumen (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_mes smallint NOT NULL CHECK (id_mes >= 1 AND id_mes <= 12),
  id_anno integer NOT NULL,
  id_tienda bigint NOT NULL,
  id_plan smallint NOT NULL,
  total_pagado numeric NOT NULL DEFAULT 0,
  CONSTRAINT app_suscripciones_renovaciones_resumen_pkey PRIMARY KEY (id),
  CONSTRAINT app_suscripciones_renovaciones_resumen_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT app_suscripciones_renovaciones_resumen_id_plan_fkey FOREIGN KEY (id_plan) REFERENCES public.app_suscripciones_plan(id)
);
CREATE TABLE public.app_versiones (
  id integer NOT NULL DEFAULT nextval('app_versiones_id_seq'::regclass),
  app_name character varying NOT NULL,
  version_actual character varying NOT NULL,
  version_minima character varying NOT NULL,
  version_maxima character varying,
  build_number integer NOT NULL,
  actualizacion_obligatoria boolean DEFAULT false,
  fecha_lanzamiento timestamp without time zone DEFAULT now(),
  activa boolean DEFAULT true,
  CONSTRAINT app_versiones_pkey PRIMARY KEY (id)
);
CREATE TABLE public.auditor (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  uuid uuid NOT NULL,
  id_tienda bigint NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  id_trabajador bigint,
  CONSTRAINT auditor_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_auditor_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT app_dat_auditor_id_trabajador_fkey FOREIGN KEY (id_trabajador) REFERENCES public.app_dat_trabajadores(id),
  CONSTRAINT app_dat_auditor_uuid_fkey FOREIGN KEY (uuid) REFERENCES auth.users(id)
);
CREATE TABLE public.config_asistant_model (
  id bigint NOT NULL DEFAULT nextval('config_asistant_model_id_seq'::regclass),
  api_key text NOT NULL,
  model text NOT NULL DEFAULT 'gemini-flash-lite-latest'::text,
  url text NOT NULL DEFAULT 'https://generativelanguage.googleapis.com/v1beta/models'::text,
  param_type text NOT NULL DEFAULT 'query'::text CHECK (lower(param_type) = ANY (ARRAY['query'::text, 'body'::text, 'header'::text])),
  param_key text NOT NULL DEFAULT 'key'::text CHECK (lower(param_key) = ANY (ARRAY['key'::text, 'bearer'::text, 'basic'::text])),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT config_asistant_model_pkey PRIMARY KEY (id)
);
CREATE TABLE public.monedas (
  codigo character NOT NULL,
  nombre character varying NOT NULL,
  simbolo character varying,
  pais character varying,
  activo boolean DEFAULT true,
  creado_en timestamp without time zone DEFAULT now(),
  actualizado_en timestamp without time zone DEFAULT now(),
  CONSTRAINT monedas_pkey PRIMARY KEY (codigo)
);
CREATE TABLE public.municipios (
  id bigint NOT NULL DEFAULT nextval('municipios_id_seq'::regclass),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  municipio text,
  provincia smallint,
  precio numeric,
  distancia numeric DEFAULT '0'::numeric,
  precio_alimentos numeric NOT NULL DEFAULT '0'::numeric,
  CONSTRAINT municipios_pkey PRIMARY KEY (id),
  CONSTRAINT municipios_provincia_fkey FOREIGN KEY (provincia) REFERENCES public.provincias(id)
);
CREATE TABLE public.project_docs (
  id integer NOT NULL DEFAULT nextval('project_docs_id_seq'::regclass),
  title character varying NOT NULL,
  content text NOT NULL,
  category character varying,
  created_at timestamp without time zone DEFAULT now(),
  updated_at timestamp without time zone DEFAULT now(),
  CONSTRAINT project_docs_pkey PRIMARY KEY (id)
);
CREATE TABLE public.provincias (
  id bigint NOT NULL DEFAULT nextval('provincias_id_seq'::regclass),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  nombre text,
  CONSTRAINT provincias_pkey PRIMARY KEY (id)
);
CREATE TABLE public.relation_products_carnaval (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_producto bigint,
  id_producto_carnaval bigint,
  id_ubicacion bigint,
  extra_info_prod jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT relation_products_carnaval_pkey PRIMARY KEY (id),
  CONSTRAINT fk__products_carnaval_id_producto FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT fk__products_carnaval_id_ubicacion FOREIGN KEY (id_ubicacion) REFERENCES public.app_dat_layout_almacen(id),
  CONSTRAINT fk__products_carnaval_id_producto_carnaval FOREIGN KEY (id_producto_carnaval) REFERENCES carnavalapp.Productos(id)
);
CREATE TABLE public.seg_roll (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  denominacion character varying NOT NULL,
  descripcion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  id_tienda bigint NOT NULL,
  CONSTRAINT seg_roll_pkey PRIMARY KEY (id),
  CONSTRAINT seg_roll_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id)
);
CREATE TABLE public.tasa_cambio_extraoficial (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_moneda_origen bigint NOT NULL,
  id_moneda_destino bigint NOT NULL,
  valor_cambio numeric NOT NULL,
  usar_precio_toque boolean NOT NULL DEFAULT false,
  activo boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  id_tienda bigint NOT NULL,
  CONSTRAINT tasa_cambio_extraoficial_pkey PRIMARY KEY (id),
  CONSTRAINT tasa_cambio_extraoficial_id_moneda_origen_fkey FOREIGN KEY (id_moneda_origen) REFERENCES public.tipos_moneda(id),
  CONSTRAINT tasa_cambio_extraoficial_id_moneda_destino_fkey FOREIGN KEY (id_moneda_destino) REFERENCES public.tipos_moneda(id),
  CONSTRAINT tasa_cambio_extraoficial_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id)
);
CREATE TABLE public.tasas_conversion (
  id integer NOT NULL DEFAULT nextval('tasas_conversion_id_seq'::regclass),
  moneda_origen character NOT NULL,
  moneda_destino character NOT NULL,
  tasa numeric NOT NULL,
  fecha_actualizacion timestamp without time zone DEFAULT now(),
  CONSTRAINT tasas_conversion_pkey PRIMARY KEY (id),
  CONSTRAINT tasas_conversion_moneda_origen_fkey FOREIGN KEY (moneda_origen) REFERENCES public.monedas(codigo),
  CONSTRAINT tasas_conversion_moneda_destino_fkey FOREIGN KEY (moneda_destino) REFERENCES public.monedas(codigo)
);
CREATE TABLE public.tipos_moneda (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  denominacion text NOT NULL,
  simbolo text NOT NULL,
  nombre_corto text NOT NULL,
  pais text,
  activo boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT tipos_moneda_pkey PRIMARY KEY (id)
);