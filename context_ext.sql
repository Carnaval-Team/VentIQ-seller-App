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
  CONSTRAINT app_cont_gastos_pkey PRIMARY KEY (id),
  CONSTRAINT app_cont_gastos_id_centro_costo_fkey FOREIGN KEY (id_centro_costo) REFERENCES public.app_cont_centro_costo(id),
  CONSTRAINT app_cont_gastos_id_tipo_costo_fkey FOREIGN KEY (id_tipo_costo) REFERENCES public.app_cont_tipo_costo(id),
  CONSTRAINT app_cont_gastos_id_subcategoria_gasto_fkey FOREIGN KEY (id_subcategoria_gasto) REFERENCES public.app_nom_subcategoria_gasto(id),
  CONSTRAINT app_cont_gastos_uuid_fkey FOREIGN KEY (uuid) REFERENCES auth.users(id),
  CONSTRAINT app_cont_gastos_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id)
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
  CONSTRAINT app_cont_historial_gastos_realizado_por_fkey FOREIGN KEY (realizado_por) REFERENCES auth.users(id),
  CONSTRAINT app_cont_historial_gastos_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT app_cont_historial_gastos_id_centro_costo_fkey FOREIGN KEY (id_centro_costo) REFERENCES public.app_cont_centro_costo(id),
  CONSTRAINT app_cont_historial_gastos_id_subcategoria_gasto_fkey FOREIGN KEY (id_subcategoria_gasto) REFERENCES public.app_nom_subcategoria_gasto(id),
  CONSTRAINT app_cont_historial_gastos_id_tipo_costo_fkey FOREIGN KEY (id_tipo_costo) REFERENCES public.app_cont_tipo_costo(id)
);
CREATE TABLE public.app_cont_log_costos (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_asignacion bigint NOT NULL,
  id_historico bigint,
  accion character varying NOT NULL,
  cambios text,
  realizado_por uuid NOT NULL,
  fecha_operacion timestamp with time zone NOT NULL,
  CONSTRAINT app_cont_log_costos_pkey PRIMARY KEY (id),
  CONSTRAINT app_cont_log_costos_id_historico_fkey FOREIGN KEY (id_historico) REFERENCES public.app_cont_historial_asignacion_costos(id),
  CONSTRAINT app_cont_log_costos_id_asignacion_fkey FOREIGN KEY (id_asignacion) REFERENCES public.app_cont_asignacion_costos(id)
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
  CONSTRAINT app_cont_margen_comercial_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT app_cont_margen_comercial_id_variante_fkey FOREIGN KEY (id_variante) REFERENCES public.app_dat_variantes(id),
  CONSTRAINT app_cont_margen_comercial_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id)
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
CREATE TABLE public.app_dat_ajuste_inventario (
  id bigint NOT NULL DEFAULT nextval('app_dat_ajuste_inventario_id_seq'::regclass),
  id_producto bigint NOT NULL,
  id_variante bigint,
  id_ubicacion bigint,
  cantidad_anterior numeric NOT NULL,
  cantidad_nueva numeric NOT NULL,
  diferencia numeric DEFAULT (cantidad_nueva - cantidad_anterior),
  id_control bigint,
  uuid_usuario uuid,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT app_dat_ajuste_inventario_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_ajuste_inventario_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_dat_ajuste_inventario_id_control_fkey FOREIGN KEY (id_control) REFERENCES public.app_dat_control_productos(id)
);
CREATE TABLE public.app_dat_almacen (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_tienda bigint,
  denominacion character varying,
  direccion character varying,
  ubicacion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
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
  CONSTRAINT app_dat_almacenero_id_trabajador_fkey FOREIGN KEY (id_trabajador) REFERENCES public.app_dat_trabajadores(id),
  CONSTRAINT app_dat_almacenero_id_almacen_fkey FOREIGN KEY (id_almacen) REFERENCES public.app_dat_almacen(id),
  CONSTRAINT app_dat_almacenero_uuid_fkey FOREIGN KEY (uuid) REFERENCES auth.users(id)
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
CREATE TABLE public.app_dat_categoria (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  denominacion character varying NOT NULL UNIQUE,
  descripcion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  sku_codigo text NOT NULL UNIQUE,
  image text,
  CONSTRAINT app_dat_categoria_pkey PRIMARY KEY (id)
);
CREATE TABLE public.app_dat_categoria_tienda (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_categoria bigint,
  id_tienda bigint,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_categoria_tienda_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_categoria_tienda_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT app_dat_categoria_tienda_id_categoria_fkey FOREIGN KEY (id_categoria) REFERENCES public.app_dat_categoria(id)
);
CREATE TABLE public.app_dat_clientes (
  id bigint NOT NULL DEFAULT nextval('app_dat_clientes_id_seq'::regclass),
  codigo_cliente character varying NOT NULL UNIQUE,
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
  CONSTRAINT app_dat_codigos_barras_opcion_fkey FOREIGN KEY (id_opcion_variante) REFERENCES public.app_dat_atributo_opcion(id),
  CONSTRAINT app_dat_codigos_barras_variante_fkey FOREIGN KEY (id_variante) REFERENCES public.app_dat_variantes(id),
  CONSTRAINT app_dat_codigos_barras_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_dat_codigos_barras_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id),
  CONSTRAINT app_dat_codigos_barras_presentacion_fkey FOREIGN KEY (id_presentacion) REFERENCES public.app_dat_producto_presentacion(id)
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
  CONSTRAINT app_dat_control_productos_id_presentacion_fkey FOREIGN KEY (id_presentacion) REFERENCES public.app_dat_producto_presentacion(id),
  CONSTRAINT app_dat_control_productos_id_ubicacion_fkey FOREIGN KEY (id_ubicacion) REFERENCES public.app_dat_layout_almacen(id),
  CONSTRAINT app_dat_control_productos_id_opcion_variante_fkey FOREIGN KEY (id_opcion_variante) REFERENCES public.app_dat_atributo_opcion(id),
  CONSTRAINT app_dat_control_productos_id_variante_fkey FOREIGN KEY (id_variante) REFERENCES public.app_dat_variantes(id),
  CONSTRAINT app_dat_control_productos_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_dat_control_productos_id_operacion_fkey FOREIGN KEY (id_operacion) REFERENCES public.app_dat_operaciones(id)
);
CREATE TABLE public.app_dat_estado_operacion (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_operacion bigint NOT NULL,
  estado smallint NOT NULL DEFAULT '1'::smallint,
  uuid uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_estado_operacion_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_estado_operacion_id_operacion_fkey FOREIGN KEY (id_operacion) REFERENCES public.app_dat_operaciones(id),
  CONSTRAINT app_dat_estado_operacion_uuid_fkey FOREIGN KEY (uuid) REFERENCES auth.users(id)
);
CREATE TABLE public.app_dat_extraccion_productos (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_operacion bigint,
  id_producto bigint,
  id_variante bigint,
  id_opcion_variante bigint,
  id_ubicacion bigint,
  id_presentacion bigint,
  cantidad numeric NOT NULL,
  precio_unitario numeric,
  sku_producto character varying,
  sku_ubicacion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  importe numeric,
  importe_real numeric,
  CONSTRAINT app_dat_extraccion_productos_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_extraccion_productos_id_variante_fkey FOREIGN KEY (id_variante) REFERENCES public.app_dat_variantes(id),
  CONSTRAINT app_dat_extraccion_productos_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_dat_extraccion_productos_id_operacion_fkey FOREIGN KEY (id_operacion) REFERENCES public.app_dat_operaciones(id),
  CONSTRAINT app_dat_extraccion_productos_id_presentacion_fkey FOREIGN KEY (id_presentacion) REFERENCES public.app_dat_producto_presentacion(id),
  CONSTRAINT app_dat_extraccion_productos_id_opcion_variante_fkey FOREIGN KEY (id_opcion_variante) REFERENCES public.app_dat_atributo_opcion(id),
  CONSTRAINT app_dat_extraccion_productos_id_ubicacion_fkey FOREIGN KEY (id_ubicacion) REFERENCES public.app_dat_layout_almacen(id)
);
CREATE TABLE public.app_dat_gerente (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  uuid uuid NOT NULL,
  id_tienda bigint NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  id_trabajador bigint,
  CONSTRAINT app_dat_gerente_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_gerente_id_trabajador_fkey FOREIGN KEY (id_trabajador) REFERENCES public.app_dat_trabajadores(id),
  CONSTRAINT app_dat_dueños_uuid_fkey FOREIGN KEY (uuid) REFERENCES auth.users(id),
  CONSTRAINT app_dat_dueños_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id)
);
CREATE TABLE public.app_dat_inventario_productos (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_producto bigint NOT NULL,
  id_variante bigint,
  id_opcion_variante bigint,
  id_ubicacion bigint,
  id_presentacion bigint,
  cantidad_inicial numeric NOT NULL,
  sku_producto character varying,
  sku_ubicacion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  cantidad_final numeric,
  origen_cambio smallint NOT NULL,
  id_recepcion bigint,
  id_extraccion bigint,
  id_control bigint,
  CONSTRAINT app_dat_inventario_productos_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_inventario_productos_id_control_fkey FOREIGN KEY (id_control) REFERENCES public.app_dat_control_productos(id),
  CONSTRAINT app_dat_inventario_productos_id_extraccion_fkey FOREIGN KEY (id_extraccion) REFERENCES public.app_dat_extraccion_productos(id),
  CONSTRAINT app_dat_inventario_productos_id_recepcion_fkey FOREIGN KEY (id_recepcion) REFERENCES public.app_dat_recepcion_productos(id),
  CONSTRAINT app_dat_inventario_productos_id_presentacion_fkey FOREIGN KEY (id_presentacion) REFERENCES public.app_dat_producto_presentacion(id),
  CONSTRAINT app_dat_inventario_productos_id_ubicacion_fkey FOREIGN KEY (id_ubicacion) REFERENCES public.app_dat_layout_almacen(id),
  CONSTRAINT app_dat_inventario_productos_id_opcion_variante_fkey FOREIGN KEY (id_opcion_variante) REFERENCES public.app_dat_atributo_opcion(id),
  CONSTRAINT app_dat_inventario_productos_id_variante_fkey FOREIGN KEY (id_variante) REFERENCES public.app_dat_variantes(id),
  CONSTRAINT app_dat_inventario_productos_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id)
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
  id_layout_padre bigint NOT NULL,
  denominacion character varying NOT NULL,
  sku_codigo character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_layout_almacen_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_layout_almacen_id_tipo_layout_fkey FOREIGN KEY (id_tipo_layout) REFERENCES public.app_nom_tipo_layout_almacen(id),
  CONSTRAINT app_dat_layout_almacen_id_almacen_fkey FOREIGN KEY (id_almacen) REFERENCES public.app_dat_almacen(id)
);
CREATE TABLE public.app_dat_layout_condiciones (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_layout bigint,
  id_condicion bigint,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_layout_condiciones_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_layout_condiciones_id_condicion_fkey FOREIGN KEY (id_condicion) REFERENCES public.app_nom_tipo_condicion(id),
  CONSTRAINT app_dat_layout_condiciones_id_layout_fkey FOREIGN KEY (id_layout) REFERENCES public.app_dat_layout_almacen(id)
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
  CONSTRAINT app_dat_operacion_transferencia_id_extraccion_fkey FOREIGN KEY (id_extraccion) REFERENCES public.app_dat_operaciones(id),
  CONSTRAINT app_dat_operacion_transferencia_id_recepcion_fkey FOREIGN KEY (id_recepcion) REFERENCES public.app_dat_operaciones(id)
);
CREATE TABLE public.app_dat_operacion_venta (
  id_operacion bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_tpv bigint NOT NULL,
  denominacion character varying,
  codigo_promocion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  id_promocion bigint,
  id_cliente bigint,
  CONSTRAINT app_dat_operacion_venta_pkey PRIMARY KEY (id_operacion),
  CONSTRAINT app_operacion_extraccion_id_tpv_fkey FOREIGN KEY (id_tpv) REFERENCES public.app_dat_tpv(id),
  CONSTRAINT app_dat_operacion_venta_id_cliente_fkey FOREIGN KEY (id_cliente) REFERENCES public.app_dat_clientes(id),
  CONSTRAINT app_dat_operacion_venta_id_promocion_fkey FOREIGN KEY (id_promocion) REFERENCES public.app_mkt_promociones(id),
  CONSTRAINT app_operacion_extraccion_id_operacion_fkey FOREIGN KEY (id_operacion) REFERENCES public.app_dat_operaciones(id)
);
CREATE TABLE public.app_dat_operaciones (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_tipo_operacion bigint NOT NULL,
  uuid uuid,
  id_tienda bigint,
  observaciones character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_operaciones_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_operaciones_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT app_dat_operaciones_uuid_fkey FOREIGN KEY (uuid) REFERENCES auth.users(id),
  CONSTRAINT app_dat_operaciones_id_tipo_operacion_fkey FOREIGN KEY (id_tipo_operacion) REFERENCES public.app_nom_tipo_operacion(id)
);
CREATE TABLE public.app_dat_precio_venta (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_producto bigint NOT NULL,
  id_variante bigint,
  precio_venta_cup numeric NOT NULL DEFAULT '0'::numeric,
  fecha_desde date NOT NULL,
  fecha_hasta date,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_precio_venta_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_precio_venta_id_variante_fkey FOREIGN KEY (id_variante) REFERENCES public.app_dat_variantes(id),
  CONSTRAINT app_dat_precio_venta_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id)
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
  CONSTRAINT app_dat_producto_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_producto_id_categoria_fkey FOREIGN KEY (id_categoria) REFERENCES public.app_dat_categoria(id),
  CONSTRAINT app_dat_producto_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id)
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
CREATE TABLE public.app_dat_producto_etiquetas (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_producto bigint,
  etiqueta character varying NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_producto_etiquetas_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_producto_etiquetas_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id)
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
  CONSTRAINT app_dat_producto_presentacion_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_producto_presentacion_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_dat_producto_presentacion_id_presentacion_fkey FOREIGN KEY (id_presentacion) REFERENCES public.app_nom_presentacion(id)
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
  CONSTRAINT app_dat_proveedor_pkey PRIMARY KEY (id)
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
  CONSTRAINT app_dat_recepcion_productos_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_recepcion_productos_id_presentacion_fkey FOREIGN KEY (id_presentacion) REFERENCES public.app_dat_producto_presentacion(id),
  CONSTRAINT app_dat_recepcion_productos_id_operacion_fkey FOREIGN KEY (id_operacion) REFERENCES public.app_dat_operaciones(id),
  CONSTRAINT app_dat_recepcion_productos_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_dat_recepcion_productos_id_variante_fkey FOREIGN KEY (id_variante) REFERENCES public.app_dat_variantes(id),
  CONSTRAINT app_dat_recepcion_productos_id_opcion_variante_fkey FOREIGN KEY (id_opcion_variante) REFERENCES public.app_dat_atributo_opcion(id),
  CONSTRAINT app_dat_recepcion_productos_id_proveedor_fkey FOREIGN KEY (id_proveedor) REFERENCES public.app_dat_proveedor(id),
  CONSTRAINT app_dat_recepcion_productos_id_ubicacion_fkey FOREIGN KEY (id_ubicacion) REFERENCES public.app_dat_layout_almacen(id)
);
CREATE TABLE public.app_dat_subcategorias (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  idcategoria bigint NOT NULL,
  denominacion character varying NOT NULL UNIQUE,
  sku_codigo character varying NOT NULL UNIQUE,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_subcategorias_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_subcategorias_idcategoria_fkey FOREIGN KEY (idcategoria) REFERENCES public.app_dat_categoria(id)
);
CREATE TABLE public.app_dat_supervisor (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  uuid uuid NOT NULL,
  id_tienda bigint NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  id_trabajador bigint,
  CONSTRAINT app_dat_supervisor_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_supervisor_id_trabajador_fkey FOREIGN KEY (id_trabajador) REFERENCES public.app_dat_trabajadores(id),
  CONSTRAINT app_dat_supervisor_uuid_fkey FOREIGN KEY (uuid) REFERENCES auth.users(id),
  CONSTRAINT app_dat_supervisor_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id)
);
CREATE TABLE public.app_dat_tienda (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  denominacion character varying NOT NULL,
  direccion character varying,
  ubicacion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_tienda_pkey PRIMARY KEY (id)
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
  CONSTRAINT app_dat_trabajadores_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_trabajadores_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT app_dat_trabajadores_id_roll_fkey FOREIGN KEY (id_roll) REFERENCES public.seg_roll(id)
);
CREATE TABLE public.app_dat_variantes (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_sub_categoria bigint NOT NULL,
  id_atributo bigint NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_variantes_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_variantes_id_atributo_fkey FOREIGN KEY (id_atributo) REFERENCES public.app_dat_atributos(id),
  CONSTRAINT app_dat_variantes_id_sub_categoria_fkey FOREIGN KEY (id_sub_categoria) REFERENCES public.app_dat_subcategorias(id)
);
CREATE TABLE public.app_dat_vendedor (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  uuid uuid NOT NULL,
  id_tpv bigint,
  numero_confirmacion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  id_trabajador bigint,
  CONSTRAINT app_dat_vendedor_pkey PRIMARY KEY (id),
  CONSTRAINT app_dat_vendedor_id_tpv_fkey FOREIGN KEY (id_tpv) REFERENCES public.app_dat_tpv(id),
  CONSTRAINT app_dat_vendedor_uuid_fkey FOREIGN KEY (uuid) REFERENCES auth.users(id),
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
  CONSTRAINT app_mkt_eventos_fidelizacion_id_operacion_fkey FOREIGN KEY (id_operacion) REFERENCES public.app_dat_operaciones(id),
  CONSTRAINT app_mkt_eventos_fidelizacion_id_cliente_fkey FOREIGN KEY (id_cliente) REFERENCES public.app_dat_clientes(id),
  CONSTRAINT app_mkt_eventos_fidelizacion_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id)
);
CREATE TABLE public.app_mkt_promocion_productos (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_promocion bigint NOT NULL,
  id_producto bigint,
  id_categoria bigint,
  id_subcategoria bigint,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_mkt_promocion_productos_pkey PRIMARY KEY (id),
  CONSTRAINT app_mkt_promocion_productos_id_subcategoria_fkey FOREIGN KEY (id_subcategoria) REFERENCES public.app_dat_subcategorias(id),
  CONSTRAINT app_mkt_promocion_productos_id_categoria_fkey FOREIGN KEY (id_categoria) REFERENCES public.app_dat_categoria(id),
  CONSTRAINT app_mkt_promocion_productos_id_producto_fkey FOREIGN KEY (id_producto) REFERENCES public.app_dat_producto(id),
  CONSTRAINT app_mkt_promocion_productos_id_promocion_fkey FOREIGN KEY (id_promocion) REFERENCES public.app_mkt_promociones(id)
);
CREATE TABLE public.app_mkt_promocion_segmento (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_promocion bigint NOT NULL,
  id_segmento bigint NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_mkt_promocion_segmento_pkey PRIMARY KEY (id),
  CONSTRAINT app_mkt_promocion_segmento_id_segmento_fkey FOREIGN KEY (id_segmento) REFERENCES public.app_mkt_segmentos(id),
  CONSTRAINT app_mkt_promocion_segmento_id_promocion_fkey FOREIGN KEY (id_promocion) REFERENCES public.app_mkt_promociones(id)
);
CREATE TABLE public.app_mkt_promociones (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_campana bigint,
  id_tienda bigint NOT NULL,
  id_tipo_promocion smallint NOT NULL,
  codigo_promocion character varying NOT NULL UNIQUE,
  nombre character varying NOT NULL,
  descripcion text,
  valor_descuento numeric,
  fecha_inicio timestamp with time zone NOT NULL,
  fecha_fin timestamp with time zone NOT NULL,
  min_compra numeric,
  limite_usos integer,
  aplica_todo boolean DEFAULT false,
  estado boolean DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_mkt_promociones_pkey PRIMARY KEY (id),
  CONSTRAINT app_mkt_promociones_id_campana_fkey FOREIGN KEY (id_campana) REFERENCES public.app_mkt_campanas(id),
  CONSTRAINT app_mkt_promociones_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id),
  CONSTRAINT app_mkt_promociones_id_tipo_promocion_fkey FOREIGN KEY (id_tipo_promocion) REFERENCES public.app_mkt_tipo_promocion(id)
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
CREATE TABLE public.app_nom_motivo_extraccion (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  denominacion character varying NOT NULL,
  descripcion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_nom_motivo_extraccion_pkey PRIMARY KEY (id)
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
CREATE TABLE public.seg_roll (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  denominacion character varying NOT NULL,
  descripcion character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  id_tienda bigint NOT NULL,
  CONSTRAINT seg_roll_pkey PRIMARY KEY (id),
  CONSTRAINT seg_roll_id_tienda_fkey FOREIGN KEY (id_tienda) REFERENCES public.app_dat_tienda(id)
);