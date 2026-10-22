-- ==============================================================================
-- Sincronizacion del esquema flow: MAIN (vsieeihstajlrdvpuooh) -> NEWA (qhprswhhfasrikhawjoz)
-- Generado comparando ambos catalogos via MCP el 2026-10-21.
--
-- Ejecutar COMPLETO en el SQL Editor de NEWA. Es una sola transaccion: si algo
-- falla, no se aplica nada. Es re-ejecutable (IF NOT EXISTS / DROP IF EXISTS).
--
-- Diferencias que cubre:
--   * 19 tablas nuevas (suscripciones, fidelidad, promociones, campanas,
--     colecciones, resenas, favoritos, beneficio de bienvenida, ...)
--   * 10 columnas nuevas (app_dat_locales.activo/horario_detalle,
--     app_dat_servicios.activo, local_servicio.activo/solo_turnos/sin_tramos,
--     nom_tipo_actividad_servicio.id_padre/orden, turno.hora_inicio/hora_fin)
--   * 89 funciones nuevas + 19 actualizadas; 4 overloads obsoletos eliminados
--   * constraints, indices, triggers, RLS, 54 politicas y permisos
--   * datos semilla, politicas de storage de flow-imagenes y realtime
-- ==============================================================================
BEGIN;
SET LOCAL check_function_bodies = off;
-- ============================================================
-- 1. Secuencias (tablas nuevas con id serial)
-- ============================================================
CREATE SEQUENCE IF NOT EXISTS flow.beneficio_bienvenida_id_seq;
CREATE SEQUENCE IF NOT EXISTS flow.beneficio_canje_id_seq;
CREATE SEQUENCE IF NOT EXISTS flow.coleccion_id_seq;
CREATE SEQUENCE IF NOT EXISTS flow.puntos_movimiento_id_seq;
CREATE SEQUENCE IF NOT EXISTS flow.regla_fidelidad_id_seq;

-- ============================================================
-- 2. Columnas nuevas en tablas existentes
-- ============================================================
ALTER TABLE flow.app_dat_locales ADD COLUMN IF NOT EXISTS activo boolean DEFAULT true NOT NULL;
ALTER TABLE flow.app_dat_locales ADD COLUMN IF NOT EXISTS horario_detalle jsonb;
ALTER TABLE flow.app_dat_servicios ADD COLUMN IF NOT EXISTS activo boolean DEFAULT true NOT NULL;
ALTER TABLE flow.local_servicio ADD COLUMN IF NOT EXISTS activo boolean DEFAULT true NOT NULL;
ALTER TABLE flow.local_servicio ADD COLUMN IF NOT EXISTS sin_tramos boolean DEFAULT false NOT NULL;
ALTER TABLE flow.local_servicio ADD COLUMN IF NOT EXISTS solo_turnos boolean DEFAULT false NOT NULL;
ALTER TABLE flow.nom_tipo_actividad_servicio ADD COLUMN IF NOT EXISTS id_padre integer;
ALTER TABLE flow.nom_tipo_actividad_servicio ADD COLUMN IF NOT EXISTS orden integer DEFAULT 0 NOT NULL;
ALTER TABLE flow.turno ADD COLUMN IF NOT EXISTS hora_fin time without time zone;
ALTER TABLE flow.turno ADD COLUMN IF NOT EXISTS hora_inicio time without time zone;

-- ============================================================
-- 3. Tablas nuevas
-- ============================================================
CREATE TABLE IF NOT EXISTS flow.beneficio_bienvenida (
  id integer DEFAULT nextval('flow.beneficio_bienvenida_id_seq'::regclass) NOT NULL,
  titulo character varying(120) NOT NULL,
  descripcion text,
  tipo character varying(20) DEFAULT 'porcentaje'::character varying NOT NULL,
  valor numeric(12,2) NOT NULL,
  moneda character varying(3),
  id_entidad integer,
  monto_minimo numeric(12,2),
  activo boolean DEFAULT true NOT NULL,
  desde timestamp with time zone,
  hasta timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS flow.beneficio_canje (
  id bigint DEFAULT nextval('flow.beneficio_canje_id_seq'::regclass) NOT NULL,
  uuid_usuario uuid NOT NULL,
  id_beneficio integer NOT NULL,
  id_agenda integer,
  id_entidad integer,
  moneda character varying(3),
  monto_descontado numeric(12,2),
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS flow.campana (
  id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  titulo character varying(120) NOT NULL,
  subtitulo character varying(160),
  descripcion text,
  id_local_servicio integer,
  id_entidad integer,
  color_inicio character varying(9),
  color_fin character varying(9),
  icono character varying(48),
  image_url text,
  desde timestamp with time zone,
  hasta timestamp with time zone,
  prioridad integer DEFAULT 0 NOT NULL,
  activo boolean DEFAULT true NOT NULL,
  created_by uuid,
  created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS flow.coleccion (
  id integer DEFAULT nextval('flow.coleccion_id_seq'::regclass) NOT NULL,
  titulo character varying(120) NOT NULL,
  subtitulo text,
  icono text,
  color_inicio text,
  color_fin text,
  orden integer DEFAULT 0 NOT NULL,
  activo boolean DEFAULT true NOT NULL,
  desde timestamp with time zone,
  hasta timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS flow.coleccion_servicio (
  id_coleccion integer NOT NULL,
  id_local_servicio integer NOT NULL,
  orden integer DEFAULT 0 NOT NULL
);

CREATE TABLE IF NOT EXISTS flow.entidad_categoria_oculta (
  id_entidad integer NOT NULL,
  id_tipo_actividad integer NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS flow.favorito (
  uuid_usuario uuid NOT NULL,
  id_local_servicio integer NOT NULL,
  created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS flow.fidelidad_config (
  id integer DEFAULT 1 NOT NULL,
  activa boolean DEFAULT true NOT NULL,
  updated_by uuid,
  updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS flow.promocion (
  id integer GENERATED ALWAYS AS IDENTITY NOT NULL,
  titulo character varying(120) NOT NULL,
  descripcion text,
  tipo character varying(16) NOT NULL,
  valor numeric(12,2) NOT NULL,
  moneda character varying(8),
  id_local_servicio integer,
  id_entidad integer,
  desde timestamp with time zone,
  hasta timestamp with time zone,
  cupo_total integer,
  cupo_usado integer DEFAULT 0 NOT NULL,
  activo boolean DEFAULT true NOT NULL,
  created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS flow.puntos_movimiento (
  id bigint DEFAULT nextval('flow.puntos_movimiento_id_seq'::regclass) NOT NULL,
  uuid_usuario uuid NOT NULL,
  puntos integer NOT NULL,
  tipo character varying(20) NOT NULL,
  motivo text,
  id_agenda integer,
  id_entidad integer,
  id_regla integer,
  moneda character varying(3),
  monto numeric(12,2),
  vence_en timestamp with time zone,
  liquidado boolean DEFAULT false NOT NULL,
  created_by uuid,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS flow.regla_fidelidad (
  id integer DEFAULT nextval('flow.regla_fidelidad_id_seq'::regclass) NOT NULL,
  nombre character varying(120) NOT NULL,
  id_entidad integer,
  moneda character varying(3),
  puntos_por_monto numeric(12,2) DEFAULT 1 NOT NULL,
  monto_base numeric(12,2) DEFAULT 10 NOT NULL,
  vigencia_dias integer,
  activo boolean DEFAULT true NOT NULL,
  desde timestamp with time zone,
  hasta timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS flow.resena (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_agenda integer NOT NULL,
  id_local_servicio integer NOT NULL,
  uuid_usuario uuid NOT NULL,
  puntuacion smallint NOT NULL,
  comentario text,
  created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS flow.suscripcion (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_entidad integer NOT NULL,
  id_plan bigint,
  estado text DEFAULT 'activa'::text NOT NULL,
  fecha_inicio timestamp with time zone DEFAULT now() NOT NULL,
  fecha_vencimiento timestamp with time zone NOT NULL,
  fecha_gracia_fin timestamp with time zone,
  origen text DEFAULT 'trial'::text NOT NULL,
  aviso_previo_at timestamp with time zone,
  notas text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS flow.suscripcion_config (
  id smallint DEFAULT 1 NOT NULL,
  trial_meses_default integer DEFAULT 1 NOT NULL,
  trial_auto boolean DEFAULT true NOT NULL,
  trial_por_usuario boolean DEFAULT true NOT NULL,
  dias_gracia integer DEFAULT 7 NOT NULL,
  dias_aviso_previo integer DEFAULT 7 NOT NULL,
  soporte_whatsapp text DEFAULT '5354590207'::text NOT NULL,
  whatsapp_notif_activa boolean DEFAULT false NOT NULL,
  whatsapp_bot_activo boolean DEFAULT false NOT NULL,
  transfermovil_numero_proveedor text DEFAULT '4055432'::text NOT NULL,
  transfermovil_titulo text DEFAULT 'Carnaval Alimentos'::text NOT NULL,
  transfermovil_intent_template text DEFAULT 'transfermovil://tm_compra_en_linea/action?id_transaccion=$id_transaccion&importe=$importe&moneda=$moneda&numero_proveedor=$numero_proveedor&version=1.0.0&titulo=$titulo&set_title=$titulo'::text NOT NULL,
  transfermovil_url_template text DEFAULT 'https://transfermovil.app/action?id_transaccion=$id_transaccion&importe=$importe&moneda=$moneda&numero_proveedor=$numero_proveedor&version=5&titulo=$titulo&set_title=$titulo'::text NOT NULL,
  moneda_default text DEFAULT 'CUP'::text NOT NULL,
  intent_horas_vigencia integer DEFAULT 24 NOT NULL,
  modo_prueba boolean DEFAULT false NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_by uuid
);

CREATE TABLE IF NOT EXISTS flow.suscripcion_intent (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_entidad integer NOT NULL,
  id_plan bigint NOT NULL,
  uuid_usuario uuid NOT NULL,
  monto numeric(12,2) NOT NULL,
  moneda text DEFAULT 'CUP'::text NOT NULL,
  id_transaccion text NOT NULL,
  numero_proveedor text NOT NULL,
  url_intent text NOT NULL,
  url_http text NOT NULL,
  estado text DEFAULT 'creado'::text NOT NULL,
  expira_at timestamp with time zone NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS flow.suscripcion_movimiento (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_entidad integer NOT NULL,
  id_suscripcion bigint,
  id_transaccion bigint,
  tipo text NOT NULL,
  dias integer DEFAULT 0 NOT NULL,
  fecha_desde timestamp with time zone,
  fecha_hasta timestamp with time zone,
  motivo text,
  admin_uuid uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS flow.suscripcion_notificacion (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_entidad integer NOT NULL,
  uuid_destino uuid,
  canal text NOT NULL,
  destino text,
  asunto text,
  mensaje text NOT NULL,
  estado text DEFAULT 'pendiente'::text NOT NULL,
  intentos integer DEFAULT 0 NOT NULL,
  error text,
  enviada_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE IF NOT EXISTS flow.suscripcion_plan (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  codigo text NOT NULL,
  nombre text NOT NULL,
  descripcion text,
  duracion_dias integer NOT NULL,
  precio numeric(12,2) DEFAULT 0 NOT NULL,
  moneda text DEFAULT 'CUP'::text NOT NULL,
  limites jsonb DEFAULT '{}'::jsonb NOT NULL,
  orden integer DEFAULT 0 NOT NULL,
  activo boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_by uuid
);

CREATE TABLE IF NOT EXISTS flow.suscripcion_transaccion (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  id_intent bigint NOT NULL,
  id_entidad integer NOT NULL,
  codigo_confirmacion text NOT NULL,
  monto numeric(12,2) NOT NULL,
  moneda text DEFAULT 'CUP'::text NOT NULL,
  metodo text DEFAULT 'transfermovil'::text NOT NULL,
  comprobante_url text,
  estado text DEFAULT 'reportado'::text NOT NULL,
  reportado_por uuid NOT NULL,
  reportado_at timestamp with time zone DEFAULT now() NOT NULL,
  verificado_por uuid,
  verificado_at timestamp with time zone,
  observaciones text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);


-- ============================================================
-- 4. Propiedad de secuencias
-- ============================================================
ALTER SEQUENCE flow.beneficio_bienvenida_id_seq OWNED BY flow.beneficio_bienvenida.id;
ALTER SEQUENCE flow.beneficio_canje_id_seq OWNED BY flow.beneficio_canje.id;
ALTER SEQUENCE flow.coleccion_id_seq OWNED BY flow.coleccion.id;
ALTER SEQUENCE flow.puntos_movimiento_id_seq OWNED BY flow.puntos_movimiento.id;
ALTER SEQUENCE flow.regla_fidelidad_id_seq OWNED BY flow.regla_fidelidad.id;


-- ============================================================
-- 5. Claves primarias y unicas
-- ============================================================
ALTER TABLE flow.beneficio_bienvenida DROP CONSTRAINT IF EXISTS beneficio_bienvenida_pkey;
ALTER TABLE flow.beneficio_bienvenida ADD CONSTRAINT beneficio_bienvenida_pkey PRIMARY KEY (id);
ALTER TABLE flow.beneficio_canje DROP CONSTRAINT IF EXISTS beneficio_canje_pkey;
ALTER TABLE flow.beneficio_canje ADD CONSTRAINT beneficio_canje_pkey PRIMARY KEY (id);
ALTER TABLE flow.beneficio_canje DROP CONSTRAINT IF EXISTS beneficio_canje_usuario_uidx;
ALTER TABLE flow.beneficio_canje ADD CONSTRAINT beneficio_canje_usuario_uidx UNIQUE (uuid_usuario);
ALTER TABLE flow.campana DROP CONSTRAINT IF EXISTS campana_pkey;
ALTER TABLE flow.campana ADD CONSTRAINT campana_pkey PRIMARY KEY (id);
ALTER TABLE flow.coleccion DROP CONSTRAINT IF EXISTS coleccion_pkey;
ALTER TABLE flow.coleccion ADD CONSTRAINT coleccion_pkey PRIMARY KEY (id);
ALTER TABLE flow.coleccion_servicio DROP CONSTRAINT IF EXISTS coleccion_servicio_pkey;
ALTER TABLE flow.coleccion_servicio ADD CONSTRAINT coleccion_servicio_pkey PRIMARY KEY (id_coleccion, id_local_servicio);
ALTER TABLE flow.entidad_categoria_oculta DROP CONSTRAINT IF EXISTS entidad_categoria_oculta_pkey;
ALTER TABLE flow.entidad_categoria_oculta ADD CONSTRAINT entidad_categoria_oculta_pkey PRIMARY KEY (id_entidad, id_tipo_actividad);
ALTER TABLE flow.favorito DROP CONSTRAINT IF EXISTS favorito_pkey;
ALTER TABLE flow.favorito ADD CONSTRAINT favorito_pkey PRIMARY KEY (uuid_usuario, id_local_servicio);
ALTER TABLE flow.fidelidad_config DROP CONSTRAINT IF EXISTS fidelidad_config_pkey;
ALTER TABLE flow.fidelidad_config ADD CONSTRAINT fidelidad_config_pkey PRIMARY KEY (id);
ALTER TABLE flow.promocion DROP CONSTRAINT IF EXISTS promocion_pkey;
ALTER TABLE flow.promocion ADD CONSTRAINT promocion_pkey PRIMARY KEY (id);
ALTER TABLE flow.puntos_movimiento DROP CONSTRAINT IF EXISTS puntos_movimiento_pkey;
ALTER TABLE flow.puntos_movimiento ADD CONSTRAINT puntos_movimiento_pkey PRIMARY KEY (id);
ALTER TABLE flow.regla_fidelidad DROP CONSTRAINT IF EXISTS regla_fidelidad_pkey;
ALTER TABLE flow.regla_fidelidad ADD CONSTRAINT regla_fidelidad_pkey PRIMARY KEY (id);
ALTER TABLE flow.resena DROP CONSTRAINT IF EXISTS resena_id_agenda_key;
ALTER TABLE flow.resena ADD CONSTRAINT resena_id_agenda_key UNIQUE (id_agenda);
ALTER TABLE flow.resena DROP CONSTRAINT IF EXISTS resena_pkey;
ALTER TABLE flow.resena ADD CONSTRAINT resena_pkey PRIMARY KEY (id);
ALTER TABLE flow.suscripcion DROP CONSTRAINT IF EXISTS suscripcion_pkey;
ALTER TABLE flow.suscripcion ADD CONSTRAINT suscripcion_pkey PRIMARY KEY (id);
ALTER TABLE flow.suscripcion_config DROP CONSTRAINT IF EXISTS suscripcion_config_pkey;
ALTER TABLE flow.suscripcion_config ADD CONSTRAINT suscripcion_config_pkey PRIMARY KEY (id);
ALTER TABLE flow.suscripcion_intent DROP CONSTRAINT IF EXISTS suscripcion_intent_id_transaccion_key;
ALTER TABLE flow.suscripcion_intent ADD CONSTRAINT suscripcion_intent_id_transaccion_key UNIQUE (id_transaccion);
ALTER TABLE flow.suscripcion_intent DROP CONSTRAINT IF EXISTS suscripcion_intent_pkey;
ALTER TABLE flow.suscripcion_intent ADD CONSTRAINT suscripcion_intent_pkey PRIMARY KEY (id);
ALTER TABLE flow.suscripcion_movimiento DROP CONSTRAINT IF EXISTS suscripcion_movimiento_pkey;
ALTER TABLE flow.suscripcion_movimiento ADD CONSTRAINT suscripcion_movimiento_pkey PRIMARY KEY (id);
ALTER TABLE flow.suscripcion_notificacion DROP CONSTRAINT IF EXISTS suscripcion_notificacion_pkey;
ALTER TABLE flow.suscripcion_notificacion ADD CONSTRAINT suscripcion_notificacion_pkey PRIMARY KEY (id);
ALTER TABLE flow.suscripcion_plan DROP CONSTRAINT IF EXISTS suscripcion_plan_codigo_key;
ALTER TABLE flow.suscripcion_plan ADD CONSTRAINT suscripcion_plan_codigo_key UNIQUE (codigo);
ALTER TABLE flow.suscripcion_plan DROP CONSTRAINT IF EXISTS suscripcion_plan_pkey;
ALTER TABLE flow.suscripcion_plan ADD CONSTRAINT suscripcion_plan_pkey PRIMARY KEY (id);
ALTER TABLE flow.suscripcion_transaccion DROP CONSTRAINT IF EXISTS suscripcion_transaccion_codigo_confirmacion_key;
ALTER TABLE flow.suscripcion_transaccion ADD CONSTRAINT suscripcion_transaccion_codigo_confirmacion_key UNIQUE (codigo_confirmacion);
ALTER TABLE flow.suscripcion_transaccion DROP CONSTRAINT IF EXISTS suscripcion_transaccion_id_intent_key;
ALTER TABLE flow.suscripcion_transaccion ADD CONSTRAINT suscripcion_transaccion_id_intent_key UNIQUE (id_intent);
ALTER TABLE flow.suscripcion_transaccion DROP CONSTRAINT IF EXISTS suscripcion_transaccion_pkey;
ALTER TABLE flow.suscripcion_transaccion ADD CONSTRAINT suscripcion_transaccion_pkey PRIMARY KEY (id);

-- ============================================================
-- 6. Overloads viejos que main ya no tiene (si se quedan, PostgREST no sabe cual llamar)
-- ============================================================
DROP FUNCTION IF EXISTS flow.admin_guardar_turno(p_uuid_usuario uuid, p_id_recurso integer, p_nombre text, p_tramos jsonb, p_orden integer, p_activo boolean, p_id integer, p_precios jsonb);
DROP FUNCTION IF EXISTS flow.cliente_entrar_sala_espera(p_uuid_usuario uuid, p_id_local_servicio integer, p_fecha_regla timestamp without time zone, p_datos_adicionales jsonb, p_para_tercero boolean, p_t_nombre text, p_t_apellidos text, p_t_ci text, p_t_telefono text);
DROP FUNCTION IF EXISTS flow.cliente_entrar_sala_espera(p_uuid_usuario uuid, p_id_local_servicio integer, p_fecha_regla timestamp without time zone, p_datos_adicionales jsonb, p_para_tercero boolean, p_t_nombre text, p_t_apellidos text, p_t_ci text, p_t_telefono text, p_id_turno integer);
DROP FUNCTION IF EXISTS flow.cliente_obtener_servicios(p_id_local integer, p_id_servicio integer, p_id_entidad integer, p_nombre_local text, p_nombre_servicio text, p_pais text, p_provincia text);

-- ============================================================
-- 7. Funciones (nuevas y actualizadas)
-- ============================================================
CREATE OR REPLACE FUNCTION flow._acreditar_puntos_agenda(p_id_agenda integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_id_agenda integer;
  v_uuid      uuid;
  v_precio    numeric;
  v_moneda    varchar;
  v_entidad   integer;
  v_regla     record;
  v_puntos    integer;
  v_vence     timestamptz;
  v_filas     integer;
begin
  -- Interruptor global. Apagar PAUSA, no borra: el libro se conserva y al
  -- reactivar se sigue acumulando desde ese momento.
  if not coalesce(
    (select c.activa from flow.fidelidad_config c where c.id = 1), true
  ) then
    return jsonb_build_object('ok', true, 'ya_acreditado', false, 'puntos', 0,
                              'motivo', 'La fidelidad esta desactivada');
  end if;

  -- Escalares y no un `record`: asi "no hay fila" es NULL y nunca dispara
  -- "record is not assigned yet".
  select a.id, a.uuid_usuario, a.precio_total, a.moneda, l.id_entidad
    into v_id_agenda, v_uuid, v_precio, v_moneda, v_entidad
  from flow.agenda a
  join flow.local_servicio ls on ls.id = a.id_local_servicio
  join flow.app_dat_locales l on l.id = ls.id_local
  where a.id = p_id_agenda;

  if v_id_agenda is null then
    return jsonb_build_object('ok', false, 'error', 'La reserva no existe');
  end if;

  if exists (
    select 1 from flow.puntos_movimiento m
    where m.id_agenda = p_id_agenda and m.tipo = 'acumulacion'
  ) then
    return jsonb_build_object('ok', true, 'ya_acreditado', true, 'puntos', 0);
  end if;

  if coalesce(v_precio, 0) <= 0 then
    return jsonb_build_object('ok', true, 'ya_acreditado', false, 'puntos', 0,
                              'motivo', 'La reserva no tiene importe');
  end if;

  select * into v_regla
  from flow._resolver_regla_fidelidad(v_entidad, v_moneda);

  if v_regla.id_regla is null then
    return jsonb_build_object('ok', true, 'ya_acreditado', false, 'puntos', 0,
                              'motivo', 'No hay regla de fidelidad vigente');
  end if;

  v_puntos := floor(v_precio / v_regla.monto_base * v_regla.puntos_por_monto)::integer;

  if v_puntos <= 0 then
    return jsonb_build_object('ok', true, 'ya_acreditado', false, 'puntos', 0,
                              'motivo', 'El importe no alcanza el minimo de la regla');
  end if;

  v_vence := case
    when v_regla.vigencia_dias is null then null
    else current_timestamp + make_interval(days => v_regla.vigencia_dias)
  end;

  insert into flow.puntos_movimiento
    (uuid_usuario, puntos, tipo, motivo, id_agenda, id_entidad, id_regla,
     moneda, monto, vence_en)
  values
    (v_uuid, v_puntos, 'acumulacion', 'Reserva completada #' || p_id_agenda,
     p_id_agenda, v_entidad, v_regla.id_regla, v_moneda, v_precio, v_vence)
  on conflict do nothing;

  get diagnostics v_filas = row_count;

  return jsonb_build_object(
    'ok', true,
    'ya_acreditado', v_filas = 0,
    'puntos', case when v_filas = 0 then 0 else v_puntos end,
    'saldo', flow.fn_saldo_puntos(v_uuid),
    'vence_en', v_vence
  );
exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm, 'sqlstate', sqlstate);
end;
$function$
;

CREATE OR REPLACE FUNCTION flow._aplicar_promocion(p_id_local_servicio integer, p_id_servicio integer, p_precio_lista numeric, p_moneda character varying, p_precio_unit numeric, p_consumir_cupo boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_lista        numeric := coalesce(p_precio_lista, 0);
  v_descuento    numeric := 0;
  v_promo_id     integer;
  v_promo_titulo varchar;
  v_filas        integer;
begin
  -- Sin precio de lista no hay nada que descontar (config_precio = '{}').
  if v_lista > 0 then
    -- Escalares, no `record`: sin promo aplicable no hay fila y leer un campo
    -- de un record sin asignar lanzaria "record is not assigned yet".
    select pr.id_promocion, pr.descuento, pr.titulo
      into v_promo_id, v_descuento, v_promo_titulo
    from flow._resolver_promocion(p_id_local_servicio, p_id_servicio, v_lista) pr;

    if v_promo_id is not null then
      if p_consumir_cupo then
        -- Reserva el cupo de forma atomica. Si no actualiza, la promo se agoto
        -- entre la cotizacion y la confirmacion.
        update flow.promocion pr
           set cupo_usado = pr.cupo_usado + 1,
               updated_at = current_timestamp
         where pr.id = v_promo_id
           and (pr.cupo_total is null or pr.cupo_usado < pr.cupo_total);

        get diagnostics v_filas = row_count;
        if v_filas = 0 then
          return jsonb_build_object(
            'ok', false,
            'error', 'La promocion se agoto mientras reservabas',
            'codigo', 'promo_agotada'
          );
        end if;
      end if;

      v_descuento := coalesce(v_descuento, 0);
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'precio_lista', v_lista,
    'precio_total', greatest(v_lista - v_descuento, 0),
    'descuento',    v_descuento,
    'moneda',       coalesce(p_moneda, 'USD'),
    'precio_unit',  coalesce(p_precio_unit, 0),
    'id_promocion', v_promo_id,
    'promo_titulo', v_promo_titulo
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION flow._beneficio_bienvenida_aplicable(p_uuid_usuario uuid, p_id_entidad integer, p_moneda character varying, p_subtotal numeric)
 RETURNS TABLE(id_beneficio integer, titulo character varying, tipo character varying, valor numeric, descuento numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
  with cfg as (
    select coalesce(
      (select c.activa from flow.fidelidad_config c where c.id = 1), true
    ) as activa
  ),
  b as (
    select * from flow._resolver_beneficio_bienvenida(
      p_uuid_usuario, p_id_entidad, p_moneda
    )
  )
  select b.id_beneficio, b.titulo, b.tipo, b.valor,
         round(
           case
             when b.tipo = 'porcentaje'
               then floor(coalesce(p_subtotal, 0) * b.valor / 100)
             else least(b.valor, coalesce(p_subtotal, 0))
           end,
           2
         ) as descuento
  from b, cfg
  where cfg.activa
    and p_uuid_usuario is not null
    and b.id_beneficio is not null
    and coalesce(p_subtotal, 0) > 0
    and (b.monto_minimo is null or coalesce(p_subtotal, 0) >= b.monto_minimo);
$function$
;

CREATE OR REPLACE FUNCTION flow._bloquear_reserva_si_no_disponible()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'flow', 'public'
AS $function$
begin
  -- Sin sesion (bots, service_role, migraciones) no se bloquea nada.
  if auth.uid() is null then
    return new;
  end if;

  -- El admin de la entidad sigue pudiendo reservar/encolar desde el mostrador.
  if flow._caller_es_admin_de_ls(new.id_local_servicio) then
    return new;
  end if;

  if not coalesce(flow._ls_disponible(new.id_local_servicio), false) then
    raise exception using
      errcode = 'P0001',
      message = 'LS_NO_DISPONIBLE',
      detail  = 'local_servicio=' || new.id_local_servicio,
      hint    = 'Este servicio no esta disponible para reservar en este momento.';
  end if;

  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION flow._caller_es_admin_de_ls(p_id_local_servicio integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
  select exists (
    select 1
    from flow.local_servicio ls
    join flow.app_dat_locales l on l.id = ls.id_local
    where ls.id = p_id_local_servicio
      and flow.is_entidad_admin(l.id_entidad)
  );
$function$
;

CREATE OR REPLACE FUNCTION flow._ls_disponible(p_id_local_servicio integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
  select coalesce(l.activo, false)
     and coalesce(s.activo, false)
     and coalesce(ls.activo, false)
     -- Lo nuevo: la entidad dueña del local debe estar al dia. `entidad_activa`
     -- es `security definer` a proposito: un cliente no puede leer
     -- `flow.suscripcion` por RLS, y sin definer veria "sin fila" en todas.
     and flow.entidad_activa(l.id_entidad)
  from flow.local_servicio ls
  join flow.app_dat_locales   l on l.id = ls.id_local
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  where ls.id = p_id_local_servicio;
$function$
;

CREATE OR REPLACE FUNCTION flow._precio_con_promocion(p_id_servicio integer, p_id_local_servicio integer, p_datos jsonb, p_moneda text, p_cantidad integer, p_consumir_cupo boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_lista numeric;
  v_moneda varchar;
  v_unit  numeric;
begin
  select cp.precio_total, cp.moneda, cp.precio_unit
    into v_lista, v_moneda, v_unit
  from flow.calcular_precio_reserva(
    p_id_servicio, coalesce(p_datos, '{}'::jsonb), p_moneda, p_cantidad
  ) cp;

  return flow._aplicar_promocion(
    p_id_local_servicio, p_id_servicio, v_lista, v_moneda, v_unit, p_consumir_cupo
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION flow._resolver_beneficio_bienvenida(p_uuid_usuario uuid, p_id_entidad integer DEFAULT NULL::integer, p_moneda character varying DEFAULT NULL::character varying)
 RETURNS TABLE(id_beneficio integer, titulo character varying, descripcion text, tipo character varying, valor numeric, moneda character varying, monto_minimo numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
  select b.id, b.titulo, b.descripcion, b.tipo, b.valor, b.moneda, b.monto_minimo
  from flow.beneficio_bienvenida b
  where b.activo
    and (b.desde is null or b.desde <= current_timestamp)
    and (b.hasta is null or current_timestamp < b.hasta)
    and (b.id_entidad is null or b.id_entidad = p_id_entidad)
    and (b.moneda is null or p_moneda is null or b.moneda = p_moneda)
    and not exists (
      select 1 from flow.beneficio_canje c where c.uuid_usuario = p_uuid_usuario
    )
  order by
    (b.id_entidad is not null) desc,
    (b.moneda is not null) desc,
    b.id
  limit 1;
$function$
;

CREATE OR REPLACE FUNCTION flow._resolver_promocion(p_id_local_servicio integer, p_id_servicio integer, p_monto numeric)
 RETURNS TABLE(id_promocion integer, descuento numeric, titulo character varying)
 LANGUAGE sql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
  with objetivo as (
    -- Entidad del servicio consultado. Se resuelve UNA vez y se usa para las
    -- promos de entidad. (El error facil aqui es leer `l.id_entidad` del propio
    -- registro de la promo: en una promo de entidad `id_local_servicio` es null,
    -- asi que ese join no encuentra local y la promo nunca aplicaria.)
    select ls.id as id_local_servicio, l.id_entidad
    from flow.local_servicio ls
    join flow.app_dat_locales l on l.id = ls.id_local
    where ls.id = p_id_local_servicio
  ),
  candidatas as (
    select
      pr.id,
      pr.titulo,
      pr.tipo,
      pr.valor,
      pr.moneda,
      -- Descuento efectivo sobre este monto concreto.
      case
        when pr.tipo = 'porcentaje' then round(p_monto * pr.valor / 100.0, 2)
        else least(pr.valor, p_monto)
      end as desc_calc
    from flow.promocion pr
    cross join objetivo o
    where pr.activo
      and (pr.desde is null or (now() at time zone 'America/Havana') >= pr.desde)
      and (pr.hasta is null or (now() at time zone 'America/Havana') <  pr.hasta)
      and (pr.cupo_total is null or pr.cupo_usado < pr.cupo_total)
      -- Del servicio concreto, o de toda su entidad.
      and (
        pr.id_local_servicio = o.id_local_servicio
        or (pr.id_entidad is not null and pr.id_entidad = o.id_entidad)
      )
  )
  select c.id, greatest(c.desc_calc, 0), c.titulo
  from candidatas c
  -- Gana el descuento mas alto. A igualdad, el mas antiguo (mas predecible).
  order by c.desc_calc desc, c.id asc
  limit 1;
$function$
;

CREATE OR REPLACE FUNCTION flow._resolver_regla_fidelidad(p_id_entidad integer, p_moneda character varying DEFAULT NULL::character varying)
 RETURNS TABLE(id_regla integer, puntos_por_monto numeric, monto_base numeric, vigencia_dias integer, moneda character varying)
 LANGUAGE sql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
  select r.id, r.puntos_por_monto, r.monto_base, r.vigencia_dias, r.moneda
  from flow.regla_fidelidad r
  where r.activo
    and (r.desde is null or r.desde <= current_timestamp)
    and (r.hasta is null or current_timestamp < r.hasta)
    and (r.id_entidad is null or r.id_entidad = p_id_entidad)
    and (r.moneda is null or p_moneda is null or r.moneda = p_moneda)
  order by
    (r.id_entidad is not null) desc,
    (r.moneda is not null) desc,
    r.id
  limit 1;
$function$
;

CREATE OR REPLACE FUNCTION flow._susc_acreditar_dias(p_id_entidad integer, p_id_plan bigint, p_dias integer, p_origen text, p_notas text, p_admin uuid, p_id_transaccion bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  -- Escalar y no `%rowtype`: si faltara la fila de config, queda NULL y el
  -- `coalesce` de abajo aplica el default de 7 dias (ver aviso de la migracion 33).
  v_dias_gracia integer;
  v_base   timestamptz;
  v_venc   timestamptz;
  v_gracia timestamptz;
  v_susc   bigint;
begin
  if p_dias is null or p_dias <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Los dias a acreditar deben ser mayores que cero');
  end if;

  select c.dias_gracia into v_dias_gracia from flow.suscripcion_config c where c.id = 1;

  -- SUMAR (decision del usuario): desde lo que le quede vigente, o desde ahora.
  -- `greatest(..., now())` evita acreditar hacia atras y evita regalar menos si
  -- la entidad ya estaba vencida.
  select greatest(
           coalesce(max(coalesce(s.fecha_gracia_fin, s.fecha_vencimiento)), now()),
           now())
    into v_base
  from flow.suscripcion s
  where s.id_entidad = p_id_entidad
    and s.estado in ('trial','activa','en_gracia','sin_plan','suspendida');

  v_base   := coalesce(v_base, now());
  v_venc   := v_base + make_interval(days => p_dias);
  v_gracia := v_venc + make_interval(days => coalesce(v_dias_gracia, 7));

  update flow.suscripcion s
     set estado            = 'activa',
         id_plan           = coalesce(p_id_plan, s.id_plan),
         fecha_vencimiento = v_venc,
         fecha_gracia_fin  = v_gracia,
         origen            = p_origen,
         aviso_previo_at   = null,
         notas             = p_notas
   where s.id_entidad = p_id_entidad
     and s.estado in ('trial','activa','en_gracia','sin_plan','suspendida')
  returning s.id into v_susc;

  if v_susc is null then
    insert into flow.suscripcion
      (id_entidad, id_plan, estado, fecha_inicio, fecha_vencimiento,
       fecha_gracia_fin, origen, notas, created_by)
    values
      (p_id_entidad, p_id_plan, 'activa', now(), v_venc, v_gracia, p_origen, p_notas, p_admin)
    returning id into v_susc;
  end if;

  insert into flow.suscripcion_movimiento
    (id_entidad, id_suscripcion, id_transaccion, tipo, dias,
     fecha_desde, fecha_hasta, motivo, admin_uuid)
  values
    (p_id_entidad, v_susc, p_id_transaccion,
     case when p_origen = 'compra' then 'acreditacion' else 'ajuste' end,
     p_dias, v_base, v_venc, p_notas, p_admin);

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id_suscripcion',    v_susc,
      'dias_acreditados',  p_dias,
      'fecha_desde',       v_base,
      'fecha_vencimiento', v_venc,
      'fecha_gracia_fin',  v_gracia
    )
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION flow._susc_caller_ve_entidad(p_id_entidad integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
  select exists (
           select 1
           from flow.entidad e
           where e.id = p_id_entidad
             and e.owner_uuid = auth.uid()
         )
      or exists (
           select 1
           from flow.admin_entidades_de_usuario(auth.uid()) a
           where a.id_entidad = p_id_entidad
         );
$function$
;

CREATE OR REPLACE FUNCTION flow._susc_notificar_inapp(p_id_entidad integer, p_uuid uuid, p_titulo text, p_mensaje text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
begin
  if p_uuid is null then
    return;
  end if;

  -- Outbox: deja traza de que el aviso existio, aunque el destinatario ya no
  -- tenga perfil (y por tanto no se pueda escribir en flow.notificaciones).
  insert into flow.suscripcion_notificacion
    (id_entidad, uuid_destino, canal, asunto, mensaje, estado, enviada_at)
  values
    (p_id_entidad, p_uuid, 'in_app', p_titulo, p_mensaje, 'enviada', now());

  -- La campana de la app lee de `flow.notificaciones`. Su FK exige una fila en
  -- `flow.perfil`: si el usuario no la tiene, el aviso igual quedo en el outbox.
  if exists (select 1 from flow.perfil pf where pf.uuid_usuario = p_uuid) then
    insert into flow.notificaciones
      (uuid_usuario, tipo, titulo, mensaje, data)
    values
      (p_uuid, 'suscripcion', p_titulo, p_mensaje,
       jsonb_build_object('id_entidad', p_id_entidad));
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION flow._susc_notificar_whatsapp(p_id_entidad integer, p_telefono text, p_mensaje text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_cfg flow.suscripcion_config%rowtype;
begin
  if p_telefono is null or btrim(p_telefono) = '' then
    return;
  end if;

  select c.* into v_cfg from flow.suscripcion_config c where c.id = 1;
  if not found then
    return;
  end if;

  -- Comprobacion SEPARADA a proposito: en PL/pgSQL el `or` de un `if` es una
  -- expresion SQL y no garantiza cortocircuito, asi que mezclar "no hay fila" y
  -- "leer un campo de la variable sin fila" en el mismo `if` es arriesgarse a un
  -- "record is not assigned yet".
  if not coalesce(v_cfg.whatsapp_notif_activa, false) then
    return;
  end if;

  insert into flow.suscripcion_notificacion
    (id_entidad, canal, destino, asunto, mensaje, estado)
  values
    (p_id_entidad, 'whatsapp', btrim(p_telefono), 'Suscripcion Flow', p_mensaje,
     -- 'pendiente' solo si hay bot que vaya a vaciar la cola; si no, 'omitida'
     -- (queda la traza pero no se acumula trabajo que nadie hara).
     case when coalesce(v_cfg.whatsapp_bot_activo, false) then 'pendiente' else 'omitida' end);
end;
$function$
;

CREATE OR REPLACE FUNCTION flow._susc_touch()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at := now();
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION flow._suscripcion_trial_entidad()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  -- `%rowtype` y no `record`: con `record` anonimo, un SELECT INTO sin filas
  -- deja la variable SIN ASIGNAR y cualquier lectura revienta con "record is not
  -- assigned yet". Con `%rowtype` los campos quedan NULL y `not found` es fiable.
  v_cfg        flow.suscripcion_config%rowtype;
  v_ya_trial   boolean := false;
  v_dias       integer;
  v_venc       timestamptz;
  v_gracia     timestamptz;
  v_susc_id    bigint;
begin
  select c.* into v_cfg
  from flow.suscripcion_config c
  where c.id = 1;

  -- Sin configuracion no se inventa nada: la entidad queda sin fila (activa por
  -- grandfathering) y el superadmin decide.
  if not found then
    return new;
  end if;

  -- El otorgamiento automatico esta apagado: no se bloquea a nadie.
  if not coalesce(v_cfg.trial_auto, false)
     or coalesce(v_cfg.trial_meses_default, 0) <= 0 then
    return new;
  end if;

  if coalesce(v_cfg.trial_por_usuario, false) then
    select exists (
      select 1
      from flow.suscripcion s
      join flow.entidad e on e.id = s.id_entidad
      where e.owner_uuid = new.owner_uuid
        and s.origen = 'trial'
    ) into v_ya_trial;
  end if;

  if v_ya_trial then
    -- Anti-abuso: esta entidad no recibe meses gratis. Nace bloqueada hasta que
    -- pague; el superadmin puede acreditarla a mano si el caso lo justifica.
    insert into flow.suscripcion
      (id_entidad, id_plan, estado, fecha_inicio, fecha_vencimiento,
       fecha_gracia_fin, origen, notas)
    values
      (new.id, null, 'sin_plan', now(), now(), now(), 'trial',
       'Sin trial: el owner ya recibio meses gratis en otra entidad')
    returning id into v_susc_id;

    insert into flow.suscripcion_movimiento
      (id_entidad, id_suscripcion, tipo, dias, fecha_desde, fecha_hasta, motivo)
    values
      (new.id, v_susc_id, 'ajuste', 0, now(), now(),
       'Entidad creada sin trial por anti-abuso (1 trial por usuario)');

    return new;
  end if;

  v_dias   := v_cfg.trial_meses_default * 30;
  v_venc   := now() + make_interval(days => v_dias);
  v_gracia := v_venc + make_interval(days => coalesce(v_cfg.dias_gracia, 7));

  insert into flow.suscripcion
    (id_entidad, id_plan, estado, fecha_inicio, fecha_vencimiento,
     fecha_gracia_fin, origen, notas)
  values
    (new.id, null, 'trial', now(), v_venc, v_gracia, 'trial',
     'Trial automatico: ' || v_dias || ' dias')
  returning id into v_susc_id;

  insert into flow.suscripcion_movimiento
    (id_entidad, id_suscripcion, tipo, dias, fecha_desde, fecha_hasta, motivo)
  values
    (new.id, v_susc_id, 'trial', v_dias, now(), v_venc,
     'Trial automatico al crear la entidad');

  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_ajustar_puntos_usuario(p_uuid_usuario uuid, p_uuid_destino uuid, p_puntos integer, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_saldo_actual integer;
  v_saldo_nuevo  integer;
  v_id           bigint;
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false,
      'error', 'Solo un superadmin con acceso total puede ajustar puntos');
  end if;

  if p_uuid_destino is null then
    return jsonb_build_object('ok', false, 'error', 'Falta el usuario destino');
  end if;

  if p_puntos is null or p_puntos = 0 then
    return jsonb_build_object('ok', false, 'error', 'El ajuste no puede ser cero');
  end if;

  if coalesce(btrim(p_motivo), '') = '' then
    return jsonb_build_object('ok', false,
      'error', 'El motivo es obligatorio: un ajuste sin explicacion no es auditable');
  end if;

  v_saldo_actual := flow.fn_saldo_puntos(p_uuid_destino);
  v_saldo_nuevo  := v_saldo_actual + p_puntos;

  if v_saldo_nuevo < 0 then
    return jsonb_build_object('ok', false,
      'error', 'El ajuste dejaria el saldo en negativo (' || v_saldo_nuevo
               || '). Saldo actual: ' || v_saldo_actual || '.');
  end if;

  insert into flow.puntos_movimiento
    (uuid_usuario, puntos, tipo, motivo, created_by)
  values
    (p_uuid_destino, p_puntos, 'ajuste',
     'Ajuste manual: ' || btrim(p_motivo), auth.uid())
  returning id into v_id;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'id', v_id,
    'saldo_anterior', v_saldo_actual,
    'saldo_nuevo', v_saldo_nuevo
  ));
exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm, 'sqlstate', sqlstate);
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_alternar_campana(p_uuid_usuario uuid, p_id integer, p_activo boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'flow', 'public'
AS $function$
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error', 'Solo el superadmin puede gestionar campanas');
  end if;

  update flow.campana
     set activo = coalesce(p_activo, true),
         updated_at = current_timestamp
   where id = p_id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Campana inexistente');
  end if;

  return jsonb_build_object('ok', true);
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_alternar_coleccion(p_uuid_usuario uuid, p_id integer, p_activo boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_id integer;
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error',
      'Solo el superadmin puede gestionar colecciones');
  end if;

  update flow.coleccion
     set activo = coalesce(p_activo, true),
         updated_at = current_timestamp
   where id = p_id
   returning id into v_id;

  if v_id is null then
    return jsonb_build_object('ok', false, 'error', 'Coleccion inexistente');
  end if;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'id', v_id, 'activo', coalesce(p_activo, true)));
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_alternar_tipo_actividad(p_id integer, p_activo boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_hijas integer;
begin
  if auth.uid() is null
     or (
       not exists (select 1 from flow.admin_entidades_de_usuario(auth.uid()))
       and not public.fn_is_superadmin_full_access()
     )
  then
    return jsonb_build_object('ok', false, 'error', 'No administras ninguna entidad');
  end if;

  update flow.nom_tipo_actividad_servicio
     set activo = coalesce(p_activo, true)
   where id = p_id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Categoria inexistente');
  end if;

  -- Apagar una categoria apaga sus subcategorias: dejarlas activas las sacaria
  -- en el riel de un padre que ya no se muestra.
  if coalesce(p_activo, true) = false then
    update flow.nom_tipo_actividad_servicio
       set activo = false
     where id_padre = p_id;
  end if;

  select count(*) into v_hijas
  from flow.nom_tipo_actividad_servicio where id_padre = p_id;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object('id', p_id, 'activo', coalesce(p_activo, true), 'subcategorias', v_hijas)
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_config_guardar(p_config jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
begin
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error', 'Solo el superadmin puede cambiar la configuracion');
  end if;

  if p_config is null or jsonb_typeof(p_config) <> 'object' then
    return jsonb_build_object('ok', false, 'error', 'Se espera un objeto JSON de configuracion');
  end if;

  -- Se actualizan SOLO las claves presentes: asi el panel puede mandar un cambio
  -- puntual sin reenviar (ni pisar) el resto.
  update flow.suscripcion_config c
     set trial_meses_default  = coalesce((p_config ->> 'trial_meses_default')::integer, c.trial_meses_default),
         trial_auto           = coalesce((p_config ->> 'trial_auto')::boolean, c.trial_auto),
         trial_por_usuario    = coalesce((p_config ->> 'trial_por_usuario')::boolean, c.trial_por_usuario),
         dias_gracia          = coalesce((p_config ->> 'dias_gracia')::integer, c.dias_gracia),
         dias_aviso_previo    = coalesce((p_config ->> 'dias_aviso_previo')::integer, c.dias_aviso_previo),
         soporte_whatsapp     = coalesce(nullif(btrim(coalesce(p_config ->> 'soporte_whatsapp', '')), ''), c.soporte_whatsapp),
         whatsapp_notif_activa= coalesce((p_config ->> 'whatsapp_notif_activa')::boolean, c.whatsapp_notif_activa),
         whatsapp_bot_activo  = coalesce((p_config ->> 'whatsapp_bot_activo')::boolean, c.whatsapp_bot_activo),
         transfermovil_numero_proveedor = coalesce(nullif(btrim(coalesce(p_config ->> 'transfermovil_numero_proveedor', '')), ''), c.transfermovil_numero_proveedor),
         transfermovil_titulo           = coalesce(nullif(btrim(coalesce(p_config ->> 'transfermovil_titulo', '')), ''), c.transfermovil_titulo),
         transfermovil_intent_template  = coalesce(nullif(coalesce(p_config ->> 'transfermovil_intent_template', ''), ''), c.transfermovil_intent_template),
         transfermovil_url_template     = coalesce(nullif(coalesce(p_config ->> 'transfermovil_url_template', ''), ''), c.transfermovil_url_template),
         moneda_default       = coalesce(nullif(btrim(coalesce(p_config ->> 'moneda_default', '')), ''), c.moneda_default),
         intent_horas_vigencia= coalesce((p_config ->> 'intent_horas_vigencia')::integer, c.intent_horas_vigencia),
         modo_prueba          = coalesce((p_config ->> 'modo_prueba')::boolean, c.modo_prueba),
         updated_by           = v_uid
   where c.id = 1;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Falta flow.suscripcion_config');
  end if;

  return flow.admin_config_obtener();
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_config_modo_gestion(p_uuid_usuario uuid, p_id_local_servicio integer, p_solo_turnos boolean, p_sin_tramos boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_solo          boolean := coalesce(p_solo_turnos, false);
  -- `solo_turnos` implica `sin_tramos` (el CHECK de la 40 lo exige igualmente).
  v_sin           boolean := coalesce(p_sin_tramos, false) or coalesce(p_solo_turnos, false);
  v_recursos      integer;
  v_recurso       integer;
  v_tramo         integer;
  v_creados_tramo integer := 0;
  v_creado_rec    boolean := false;
  v_turno         record;
begin
  if not flow._admin_puede_local_servicio(p_uuid_usuario, p_id_local_servicio) then
    return jsonb_build_object('ok', false, 'error', 'local_servicio inexistente o sin permiso');
  end if;

  select count(*) into v_recursos
  from flow.recurso r
  where r.id_local_servicio = p_id_local_servicio;

  -- Con varios recursos no se puede simplificar a "solo turnos" sin romper
  -- `turno_tramo`. El modo correcto para ese caso es "No uso tramos".
  if v_solo and v_recursos > 1 then
    return jsonb_build_object(
      'ok', false,
      'error', 'Este servicio tiene ' || v_recursos || ' recursos. '
               'Mantén "No uso tramos" o deja un único recurso para usar '
               '"Solo configurar turnos".'
    );
  end if;

  update flow.local_servicio
     set solo_turnos = v_solo,
         sin_tramos  = v_sin
   where id = p_id_local_servicio;

  -- En "solo turnos" siempre tiene que existir UN recurso que agrupe los turnos.
  if v_solo and v_recursos = 0 then
    insert into flow.recurso (id_local_servicio, nombre, capacidad, orden, activo)
    select p_id_local_servicio,
           'Cupo',
           greatest(coalesce(ls.cantidad_max_capacidad, 1), 1),
           0,
           true
    from flow.local_servicio ls
    where ls.id = p_id_local_servicio
    returning id into v_recurso;
    v_creado_rec := true;
  end if;

  -- Un tramo oculto por cada turno sin tramo (todo el local_servicio).
  -- Es idempotente: la segunda pasada no encuentra turnos sin tramo.
  if v_sin then
    for v_turno in
      select t.id, t.nombre, t.orden, t.id_recurso
      from flow.turno t
      join flow.recurso r on r.id = t.id_recurso
      where r.id_local_servicio = p_id_local_servicio
        and not exists (
          select 1 from flow.turno_tramo tt where tt.id_turno = t.id
        )
      order by t.orden, t.id
    loop
      insert into flow.tramo (id_recurso, nombre, capacidad, orden, activo)
      values (
        v_turno.id_recurso,
        coalesce(nullif(btrim(v_turno.nombre), ''), 'Cupo'),
        null,               -- null = hereda la capacidad del recurso
        coalesce(v_turno.orden, 0),
        true
      )
      returning id into v_tramo;

      insert into flow.turno_tramo (id_turno, id_tramo)
      values (v_turno.id, v_tramo)
      on conflict do nothing;

      v_creados_tramo := v_creados_tramo + 1;
    end loop;
  end if;

  return jsonb_build_object(
    'ok', true,
    'solo_turnos', v_solo,
    'sin_tramos', v_sin,
    'recurso_creado', v_creado_rec,
    'tramos_creados', v_creados_tramo
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_config_obtener()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_cfg flow.suscripcion_config%rowtype;
begin
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error', 'Solo el superadmin puede ver la configuracion');
  end if;

  select c.* into v_cfg from flow.suscripcion_config c where c.id = 1;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Falta flow.suscripcion_config');
  end if;

  return jsonb_build_object('ok', true, 'data', to_jsonb(v_cfg));
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_crear_reserva_directa(p_id_local_servicio integer, p_fecha date, p_cantidad integer DEFAULT NULL::integer, p_datos_adicionales jsonb DEFAULT NULL::jsonb, p_uuid_admin uuid DEFAULT NULL::uuid, p_id_turno integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_cantidad_default integer;
  v_cantidad_max     integer;
  v_plan_id          bigint;
  v_disponibles      integer;
  v_estado           integer;
  v_id_agenda        integer;
  v_fecha_ts         timestamp without time zone;
  v_cant             integer;
  v_uuid_admin       uuid;
  v_es_admin         boolean;
  v_id_servicio      integer;
  v_precio_total     numeric;
  v_moneda           varchar;
  v_desc             jsonb;
  v_cotizacion       jsonb;
begin
  v_uuid_admin := coalesce(p_uuid_admin, auth.uid());

  if v_uuid_admin is null or p_id_local_servicio is null or p_fecha is null then
    return jsonb_build_object('ok', false, 'error', 'parametros obligatorios faltantes');
  end if;

  select exists (
    select 1
    from flow.local_servicio ls
    join flow.app_dat_locales l on l.id = ls.id_local
    join flow.entidad e on e.id = l.id_entidad
    where ls.id = p_id_local_servicio
      and (
        e.owner_uuid = v_uuid_admin
        or exists (
          select 1 from flow.entidad_admin ea
          where ea.id_entidad = e.id and ea.uuid_usuario = v_uuid_admin
        )
      )
  ) into v_es_admin;

  if not v_es_admin then
    return jsonb_build_object('ok', false, 'error', 'No tienes permisos de administrador sobre este servicio');
  end if;

  perform pg_advisory_xact_lock(hashtext('flow.sala_espera'), p_id_local_servicio);

  select ls.cantidad_default, ls.cantidad_max_capacidad, ls.id_servicio
    into v_cantidad_default, v_cantidad_max, v_id_servicio
  from flow.local_servicio ls
  where ls.id = p_id_local_servicio;

  if v_cantidad_default is null then
    return jsonb_build_object('ok', false, 'error', 'El servicio no existe');
  end if;

  if p_id_turno is not null then
    if not exists (
      select 1 from flow.turno t
      join flow.recurso r on r.id = t.id_recurso and r.activo
      where t.id = p_id_turno and t.activo and r.id_local_servicio = p_id_local_servicio
    ) then
      return jsonb_build_object('ok', false, 'error', 'Turno invalido para este servicio');
    end if;
  end if;

  v_cant := coalesce(p_cantidad, v_cantidad_default, 1);
  if v_cant < 1 then
    return jsonb_build_object('ok', false, 'error', 'La cantidad debe ser al menos 1');
  end if;
  if v_cant > v_cantidad_max then
    return jsonb_build_object('ok', false, 'error',
      'La cantidad maxima por reserva es ' || v_cantidad_max);
  end if;

  select id into v_estado from flow.nom_estado_agenda where nombre = 'Reservado' limit 1;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'error', 'falta el estado Reservado (correr migracion 03)');
  end if;

  v_fecha_ts := (make_timestamp(extract(year from p_fecha)::int,
                                extract(month from p_fecha)::int,
                                extract(day from p_fecha)::int, 12, 0, 0));

  if p_id_turno is not null then
    v_desc := flow._descontar_tramos_turno(p_id_turno, p_fecha, v_cant);
    if (v_desc ->> 'ok') <> 'true' then
      return jsonb_build_object('ok', false, 'error', v_desc ->> 'error');
    end if;
    select flow._aplicar_promocion(
             p_id_local_servicio, v_id_servicio,
             cp.precio_total, cp.moneda, cp.precio_unit, true
           )
      into v_cotizacion
    from flow.calcular_precio_turno(
      v_id_servicio, p_id_turno, coalesce(p_datos_adicionales, '{}'::jsonb), null, v_cant
    ) cp;
  else
    select ps.id, (ps.cantidad - ps.agendados) into v_plan_id, v_disponibles
    from flow.plan_servicios ps
    where ps.id_local_servicio = p_id_local_servicio
      and ps.cantidad is not null
      and ps.agendados < ps.cantidad
      and (ps.fecha at time zone 'America/Havana')::date = p_fecha
    order by ps.id
    limit 1
    for update;

    if v_plan_id is null then
      return jsonb_build_object('ok', false, 'error', 'No hay turnos disponibles para esa fecha');
    end if;
    if v_cant > v_disponibles then
      return jsonb_build_object('ok', false,
        'error', 'No hay suficientes turnos (quedan ' || v_disponibles || ')');
    end if;

    v_cotizacion := flow._precio_con_promocion(
      v_id_servicio, p_id_local_servicio, p_datos_adicionales, null, v_cant, true
    );
  end if;

  if (v_cotizacion ->> 'ok') = 'false' then
    return jsonb_build_object('ok', false,
      'error', v_cotizacion ->> 'error',
      'codigo', v_cotizacion ->> 'codigo');
  end if;

  v_precio_total := (v_cotizacion ->> 'precio_total')::numeric;
  v_moneda       := (v_cotizacion ->> 'moneda')::varchar;

  insert into flow.agenda
    (uuid_usuario, id_local_servicio, id_estado, fecha_hora_reserva,
     cantidad, datos_adicionales, reservado_por, precio_total, moneda, id_turno)
  values
    (v_uuid_admin, p_id_local_servicio, v_estado, v_fecha_ts,
     v_cant, p_datos_adicionales, v_uuid_admin, v_precio_total, v_moneda, p_id_turno)
  returning id into v_id_agenda;

  if p_id_turno is null then
    update flow.plan_servicios set agendados = agendados + v_cant where id = v_plan_id;
  end if;

  return jsonb_build_object('ok', true,
    'data', jsonb_build_object(
      'id_agenda', v_id_agenda,
      'fecha',     to_char(v_fecha_ts, 'YYYY-MM-DD'),
      'cantidad',  v_cant,
      'id_turno',  p_id_turno,
      'precio_total', v_precio_total,
      'moneda',       v_moneda
    ));
exception
  when others then
    return jsonb_build_object('ok', false, 'error', sqlerrm, 'sqlstate', sqlstate);
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_create_user(p_email text, p_password text, p_nombre text, p_apellidos text, p_ci text, p_telefono text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'extensions', 'public', 'auth'
AS $function$
declare
  v_email text := lower(trim(p_email));
  v_uuid uuid := gen_random_uuid();
begin
  -- ── Quién puede crear usuarios ──────────────────────────────────────────
  if auth.uid() is null then
    raise exception 'Sesión no válida';
  end if;

  if not (
    public.fn_is_superadmin_full_access()
    or exists (select 1 from flow.entidad e where e.owner_uuid = auth.uid())
    or exists (select 1 from flow.entidad_admin a where a.uuid_usuario = auth.uid())
  ) then
    raise exception 'Solo un administrador de entidad puede crear usuarios';
  end if;

  -- ── Datos ───────────────────────────────────────────────────────────────
  if v_email is null or v_email = '' then
    raise exception 'El correo es obligatorio';
  end if;
  if coalesce(p_password, '') = '' then
    raise exception 'La contraseña es obligatoria';
  end if;

  if exists (select 1 from auth.users where email = v_email) then
    raise exception 'Ya existe un usuario con el correo %', v_email;
  end if;

  -- `flow.perfil.ci` tiene índice único (`perfil_ci_key`): sin esta comprobación
  -- el insert fallaría con un error de Postgres en vez de decir qué pasa.
  if exists (select 1 from flow.perfil where ci = trim(p_ci)) then
    raise exception 'Ya existe un perfil con ese carné de identidad';
  end if;

  -- ── Usuario de auth COMPLETO (misma forma que un registro de GoTrue) ────
  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    created_at,
    updated_at,
    raw_app_meta_data,
    raw_user_meta_data,
    confirmation_token,
    recovery_token,
    email_change,
    email_change_token_new,
    phone_change,
    phone_change_token,
    email_change_token_current,
    reauthentication_token,
    is_sso_user,
    is_anonymous,
    email_change_confirm_status
  ) values (
    '00000000-0000-0000-0000-000000000000',
    v_uuid,
    'authenticated',
    'authenticated',
    v_email,
    crypt(p_password, gen_salt('bf')),
    now(),
    now(),
    now(),
    jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
    -- `nombre`/`apellidos` se conservan porque la app los lee de aquí.
    jsonb_build_object(
      'sub', v_uuid::text,
      'email', v_email,
      'nombre', p_nombre,
      'apellidos', p_apellidos,
      'email_verified', true,
      'phone_verified', false
    ),
    '', '', '', '', '', '', '', '',
    false,
    false,
    0
  );

  -- ── Identidad de email: es lo que hace posible el login ────────────────
  -- `email` NO se escribe: en `auth.identities` es GENERATED ALWAYS a partir de
  -- `identity_data ->> 'email'`.
  insert into auth.identities (
    id,
    provider_id,
    user_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_uuid,
    v_uuid,
    jsonb_build_object(
      'sub', v_uuid::text,
      'email', v_email,
      'email_verified', true,
      'phone_verified', false
    ),
    'email',
    now(),
    now(),
    now()
  );

  -- ── Perfil de la app ────────────────────────────────────────────────────
  insert into flow.perfil (uuid_usuario, nombre, apellidos, ci, telefono)
  values (v_uuid, p_nombre, p_apellidos, p_ci, p_telefono)
  on conflict (uuid_usuario) do update set
    nombre = excluded.nombre,
    apellidos = excluded.apellidos,
    ci = excluded.ci,
    telefono = excluded.telefono;

  return v_uuid;
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_dashboard_entidad(p_uuid_usuario uuid, p_id_entidad integer, p_dias integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_dias       integer := least(greatest(coalesce(p_dias, 30), 1), 180);
  v_desde      date;
  v_locales_t  integer; v_locales_a  integer;
  v_serv_t     integer; v_serv_a     integer;
  v_ls_t       integer; v_ls_a       integer;
  v_res_t      integer; v_res_res    integer; v_res_com integer; v_res_can integer;
  v_por_dia    jsonb;
  v_top        jsonb;
begin
  if not exists (
    select 1 from flow.admin_entidades_de_usuario(p_uuid_usuario) e
    where e.id_entidad = p_id_entidad
  ) then
    return jsonb_build_object('ok', false, 'error', 'entidad inexistente o sin permiso');
  end if;

  v_desde := current_date - (v_dias - 1);

  select count(*), count(*) filter (where coalesce(l.activo, false))
    into v_locales_t, v_locales_a
  from flow.app_dat_locales l
  where l.id_entidad = p_id_entidad;

  select count(*), count(*) filter (where coalesce(s.activo, false))
    into v_serv_t, v_serv_a
  from flow.app_dat_servicios s
  where s.id_entidad = p_id_entidad;

  select count(*), count(*) filter (where flow._ls_disponible(ls.id))
    into v_ls_t, v_ls_a
  from flow.local_servicio ls
  join flow.app_dat_locales l on l.id = ls.id_local
  where l.id_entidad = p_id_entidad;

  select count(*),
         count(*) filter (where a.id_estado = 1),
         count(*) filter (where a.id_estado = 3),
         count(*) filter (where a.id_estado = 2)
    into v_res_t, v_res_res, v_res_com, v_res_can
  from flow.agenda a
  join flow.local_servicio ls on ls.id = a.id_local_servicio
  join flow.app_dat_locales l  on l.id = ls.id_local
  where l.id_entidad = p_id_entidad;

  select coalesce(jsonb_agg(jsonb_build_object(
           'fecha',      to_char(d.dia, 'YYYY-MM-DD'),
           'total',      coalesce(c.total, 0),
           'reservadas', coalesce(c.reservadas, 0),
           'completadas', coalesce(c.completadas, 0),
           'canceladas', coalesce(c.canceladas, 0)
         ) order by d.dia), '[]'::jsonb)
    into v_por_dia
  from generate_series(v_desde, current_date, interval '1 day') as d(dia)
  left join (
    select (a.fecha_hora_reserva at time zone 'America/Havana')::date as dia,
           count(*)::integer                                         as total,
           count(*) filter (where a.id_estado = 1)::integer           as reservadas,
           count(*) filter (where a.id_estado = 3)::integer           as completadas,
           count(*) filter (where a.id_estado = 2)::integer           as canceladas
    from flow.agenda a
    join flow.local_servicio ls on ls.id = a.id_local_servicio
    join flow.app_dat_locales l  on l.id = ls.id_local
    where l.id_entidad = p_id_entidad
      and (a.fecha_hora_reserva at time zone 'America/Havana')::date between v_desde and current_date
    group by 1
  ) c on c.dia = d.dia;

  select coalesce(jsonb_agg(q.t order by q.orden), '[]'::jsonb)
    into v_top
  from (
    select
      jsonb_build_object(
        'id_local_servicio', a.id_local_servicio,
        'servicio',          s.nombre,
        'local',             l.nombre,
        'total',             count(*)::integer,
        'reservadas',        count(*) filter (where a.id_estado = 1)::integer,
        'canceladas',        count(*) filter (where a.id_estado = 2)::integer
      ) as t,
      row_number() over (order by count(*) desc, s.nombre, l.nombre) as orden
    from flow.agenda a
    join flow.local_servicio ls   on ls.id = a.id_local_servicio
    join flow.app_dat_locales l   on l.id = ls.id_local
    join flow.app_dat_servicios s on s.id = ls.id_servicio
    where l.id_entidad = p_id_entidad
    group by a.id_local_servicio, s.nombre, l.nombre
    order by count(*) desc, s.nombre, l.nombre
    limit 5
  ) q;

  return jsonb_build_object(
    'ok', true,
    'dias', v_dias,
    'locales', jsonb_build_object(
      'total', v_locales_t, 'activos', v_locales_a,
      'inactivos', v_locales_t - v_locales_a
    ),
    'servicios', jsonb_build_object(
      'total', v_serv_t, 'activos', v_serv_a,
      'inactivos', v_serv_t - v_serv_a
    ),
    'local_servicios', jsonb_build_object(
      'total', v_ls_t, 'activos', v_ls_a,
      'inactivos', v_ls_t - v_ls_a
    ),
    'reservas', jsonb_build_object(
      'total', v_res_t, 'reservado', v_res_res,
      'completado', v_res_com, 'cancelado', v_res_can
    ),
    'reservas_por_dia', v_por_dia,
    'top_servicios', v_top
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_eliminar_beneficio_bienvenida(p_uuid_usuario uuid, p_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_canjes integer;
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false,
      'error', 'Solo un superadmin con acceso total puede editar los beneficios');
  end if;

  -- Si alguien ya lo canjeo, borrarlo liberaria su "una sola vez" (la FK es
  -- `on delete restrict`, asi que ademas fallaria). Se desactiva.
  select count(*) into v_canjes
  from flow.beneficio_canje c
  where c.id_beneficio = p_id;

  if v_canjes > 0 then
    return jsonb_build_object('ok', false,
      'error', 'Este beneficio ya lo usaron ' || v_canjes
               || ' usuario(s). Borrarlo les devolveria el derecho a canjear. Desactivalo en vez de borrarlo.');
  end if;

  delete from flow.beneficio_bienvenida where id = p_id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'El beneficio no existe');
  end if;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id));
exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm, 'sqlstate', sqlstate);
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_eliminar_campana(p_uuid_usuario uuid, p_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'flow', 'public'
AS $function$
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error', 'Solo el superadmin puede gestionar campanas');
  end if;

  delete from flow.campana where id = p_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Campana inexistente');
  end if;

  return jsonb_build_object('ok', true);
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_eliminar_coleccion(p_uuid_usuario uuid, p_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_id integer;
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error',
      'Solo el superadmin puede gestionar colecciones');
  end if;

  delete from flow.coleccion_servicio where id_coleccion = p_id;
  delete from flow.coleccion where id = p_id returning id into v_id;

  if v_id is null then
    return jsonb_build_object('ok', false, 'error', 'Coleccion inexistente');
  end if;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_eliminar_promocion(p_uuid_usuario uuid, p_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_id_entidad integer;
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  select coalesce(l.id_entidad, pr.id_entidad) into v_id_entidad
  from flow.promocion pr
  left join flow.local_servicio ls on ls.id = pr.id_local_servicio
  left join flow.app_dat_locales l on l.id = ls.id_local
  where pr.id = p_id;

  if v_id_entidad is null then
    return jsonb_build_object('ok', false, 'error', 'Promocion inexistente');
  end if;

  if not exists (
    select 1 from flow.admin_entidades_de_usuario(auth.uid()) mine
    where mine.id_entidad = v_id_entidad
  ) then
    return jsonb_build_object('ok', false, 'error', 'No administras esta entidad');
  end if;

  delete from flow.promocion where id = p_id;
  return jsonb_build_object('ok', true);
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_eliminar_regla_fidelidad(p_uuid_usuario uuid, p_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'flow', 'public'
AS $function$
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false,
      'error', 'Solo un superadmin con acceso total puede editar la fidelidad');
  end if;

  -- Borrar la ultima regla global dejaria a los clientes sin programa y sin
  -- explicacion en el Home. Mejor impedirlo que dejar el banner vacio.
  if exists (
    select 1 from flow.regla_fidelidad
    where id = p_id and id_entidad is null
  ) and (
    select count(*) from flow.regla_fidelidad where id_entidad is null
  ) <= 1 then
    return jsonb_build_object('ok', false,
      'error', 'No se puede borrar la unica regla global: los clientes se quedarian sin programa. Desactivala o crea otra antes.');
  end if;

  delete from flow.regla_fidelidad where id = p_id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'La regla no existe');
  end if;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id));
exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm, 'sqlstate', sqlstate);
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_eliminar_tipo_actividad(p_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_servicios integer;
  v_hijas integer;
begin
  if auth.uid() is null
     or (
       not exists (select 1 from flow.admin_entidades_de_usuario(auth.uid()))
       and not public.fn_is_superadmin_full_access()
     )
  then
    return jsonb_build_object('ok', false, 'error', 'No administras ninguna entidad');
  end if;

  select count(*) into v_servicios
  from flow.app_dat_servicios
  where id_tipo_actividad = p_id;

  if v_servicios > 0 then
    return jsonb_build_object(
      'ok', false,
      'error', format(
        'No se puede eliminar: %s servicio(s) usan esta categoria. Desactivala en su lugar.',
        v_servicios
      )
    );
  end if;

  select count(*) into v_hijas
  from flow.nom_tipo_actividad_servicio
  where id_padre = p_id;

  if v_hijas > 0 then
    return jsonb_build_object(
      'ok', false,
      'error', format(
        'No se puede eliminar: tiene %s subcategoria(s). Eliminalas o desactivala.',
        v_hijas
      )
    );
  end if;

  delete from flow.nom_tipo_actividad_servicio where id = p_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Categoria inexistente');
  end if;

  return jsonb_build_object('ok', true);
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_guardar_beneficio_bienvenida(p_uuid_usuario uuid, p_titulo text, p_descripcion text, p_tipo text, p_valor numeric, p_moneda text, p_id_entidad integer, p_monto_minimo numeric, p_activo boolean, p_desde timestamp with time zone, p_hasta timestamp with time zone, p_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_id integer;
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false,
      'error', 'Solo un superadmin con acceso total puede editar los beneficios');
  end if;

  if coalesce(btrim(p_titulo), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'El titulo es obligatorio');
  end if;

  if p_tipo not in ('porcentaje','monto') then
    return jsonb_build_object('ok', false,
      'error', 'El tipo debe ser "porcentaje" o "monto"');
  end if;

  if p_valor is null or p_valor <= 0 then
    return jsonb_build_object('ok', false, 'error', 'El valor debe ser mayor que cero');
  end if;

  -- Un porcentaje mayor que 100 regalaria dinero. El tope es de negocio, no de tipo.
  if p_tipo = 'porcentaje' and p_valor > 100 then
    return jsonb_build_object('ok', false,
      'error', 'Un porcentaje no puede superar el 100%');
  end if;

  if p_monto_minimo is not null and p_monto_minimo < 0 then
    return jsonb_build_object('ok', false, 'error', 'El monto minimo no puede ser negativo');
  end if;

  if p_desde is not null and p_hasta is not null and p_desde >= p_hasta then
    return jsonb_build_object('ok', false,
      'error', 'La fecha de fin debe ser posterior a la de inicio');
  end if;

  if p_id is null then
    insert into flow.beneficio_bienvenida
      (titulo, descripcion, tipo, valor, moneda, id_entidad, monto_minimo,
       activo, desde, hasta, created_by)
    values
      (btrim(p_titulo), nullif(btrim(coalesce(p_descripcion, '')), ''), p_tipo,
       p_valor, nullif(btrim(coalesce(p_moneda, '')), ''), p_id_entidad,
       p_monto_minimo, coalesce(p_activo, true), p_desde, p_hasta, auth.uid())
    returning id into v_id;

    return jsonb_build_object('ok', true,
      'data', jsonb_build_object('id', v_id, 'creado', true));
  end if;

  update flow.beneficio_bienvenida
     set titulo       = btrim(p_titulo),
         descripcion  = nullif(btrim(coalesce(p_descripcion, '')), ''),
         tipo         = p_tipo,
         valor        = p_valor,
         moneda       = nullif(btrim(coalesce(p_moneda, '')), ''),
         id_entidad   = p_id_entidad,
         monto_minimo = p_monto_minimo,
         activo       = coalesce(p_activo, true),
         desde        = p_desde,
         hasta        = p_hasta,
         updated_at   = current_timestamp
   where id = p_id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'El beneficio no existe');
  end if;

  return jsonb_build_object('ok', true,
    'data', jsonb_build_object('id', p_id, 'creado', false));
exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm, 'sqlstate', sqlstate);
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_guardar_campana(p_uuid_usuario uuid, p_titulo text, p_id_local_servicio integer DEFAULT NULL::integer, p_id_entidad integer DEFAULT NULL::integer, p_subtitulo text DEFAULT NULL::text, p_descripcion text DEFAULT NULL::text, p_color_inicio text DEFAULT NULL::text, p_color_fin text DEFAULT NULL::text, p_icono text DEFAULT NULL::text, p_image_url text DEFAULT NULL::text, p_desde timestamp with time zone DEFAULT NULL::timestamp with time zone, p_hasta timestamp with time zone DEFAULT NULL::timestamp with time zone, p_prioridad integer DEFAULT 0, p_activo boolean DEFAULT true, p_id integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_id integer;
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error', 'Solo el superadmin puede gestionar campanas');
  end if;

  if btrim(coalesce(p_titulo, '')) = '' then
    return jsonb_build_object('ok', false, 'error', 'El titulo es obligatorio');
  end if;
  if p_id_local_servicio is null and p_id_entidad is null then
    return jsonb_build_object('ok', false, 'error', 'Elige un servicio o una entidad');
  end if;
  if p_id_local_servicio is not null and p_id_entidad is not null then
    return jsonb_build_object('ok', false, 'error', 'Elige servicio O entidad, no ambos');
  end if;
  if p_desde is not null and p_hasta is not null and p_desde >= p_hasta then
    return jsonb_build_object('ok', false, 'error', 'La fecha de fin debe ser posterior al inicio');
  end if;

  if p_id_local_servicio is not null
     and not exists (select 1 from flow.local_servicio where id = p_id_local_servicio) then
    return jsonb_build_object('ok', false, 'error', 'El servicio no existe');
  end if;
  if p_id_entidad is not null
     and not exists (select 1 from flow.entidad where id = p_id_entidad) then
    return jsonb_build_object('ok', false, 'error', 'La entidad no existe');
  end if;

  if p_id is null then
    insert into flow.campana (
      titulo, subtitulo, descripcion,
      id_local_servicio, id_entidad,
      color_inicio, color_fin, icono, image_url,
      desde, hasta, prioridad, activo, created_by
    )
    values (
      btrim(p_titulo),
      nullif(btrim(coalesce(p_subtitulo, '')), ''),
      nullif(btrim(coalesce(p_descripcion, '')), ''),
      p_id_local_servicio, p_id_entidad,
      nullif(btrim(coalesce(p_color_inicio, '')), ''),
      nullif(btrim(coalesce(p_color_fin, '')), ''),
      nullif(btrim(coalesce(p_icono, '')), ''),
      nullif(btrim(coalesce(p_image_url, '')), ''),
      p_desde, p_hasta, coalesce(p_prioridad, 0), coalesce(p_activo, true),
      auth.uid()
    )
    returning id into v_id;
  else
    update flow.campana
       set titulo = btrim(p_titulo),
           subtitulo = nullif(btrim(coalesce(p_subtitulo, '')), ''),
           descripcion = nullif(btrim(coalesce(p_descripcion, '')), ''),
           id_local_servicio = p_id_local_servicio,
           id_entidad = p_id_entidad,
           color_inicio = nullif(btrim(coalesce(p_color_inicio, '')), ''),
           color_fin = nullif(btrim(coalesce(p_color_fin, '')), ''),
           icono = nullif(btrim(coalesce(p_icono, '')), ''),
           image_url = nullif(btrim(coalesce(p_image_url, '')), ''),
           desde = p_desde,
           hasta = p_hasta,
           prioridad = coalesce(p_prioridad, 0),
           activo = coalesce(p_activo, true),
           updated_at = current_timestamp
     where id = p_id
     returning id into v_id;

    if v_id is null then
      return jsonb_build_object('ok', false, 'error', 'Campana inexistente');
    end if;
  end if;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_guardar_coleccion(p_uuid_usuario uuid, p_titulo text, p_subtitulo text DEFAULT NULL::text, p_icono text DEFAULT NULL::text, p_color_inicio text DEFAULT NULL::text, p_color_fin text DEFAULT NULL::text, p_orden integer DEFAULT 0, p_activo boolean DEFAULT true, p_desde timestamp with time zone DEFAULT NULL::timestamp with time zone, p_hasta timestamp with time zone DEFAULT NULL::timestamp with time zone, p_servicios jsonb DEFAULT '[]'::jsonb, p_id integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_id    integer;
  v_idls  integer;
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error',
      'Solo el superadmin puede gestionar colecciones');
  end if;

  if btrim(coalesce(p_titulo, '')) = '' then
    return jsonb_build_object('ok', false, 'error', 'El titulo es obligatorio');
  end if;
  if p_desde is not null and p_hasta is not null and p_desde >= p_hasta then
    return jsonb_build_object('ok', false, 'error',
      'La fecha de fin debe ser posterior al inicio');
  end if;
  if jsonb_typeof(coalesce(p_servicios, '[]'::jsonb)) <> 'array' then
    return jsonb_build_object('ok', false, 'error',
      'p_servicios debe ser un array de id_local_servicio');
  end if;

  -- Validar TODOS los servicios antes de escribir nada.
  for v_idls in
    select (e.v)::int
      from jsonb_array_elements_text(coalesce(p_servicios, '[]'::jsonb)) as e(v)
  loop
    if not exists (select 1 from flow.local_servicio where id = v_idls) then
      return jsonb_build_object('ok', false, 'error',
        'El servicio ' || v_idls || ' no existe');
    end if;
  end loop;

  if p_id is null then
    insert into flow.coleccion
      (titulo, subtitulo, icono, color_inicio, color_fin,
       orden, activo, desde, hasta, created_by)
    values
      (btrim(p_titulo),
       nullif(btrim(coalesce(p_subtitulo, '')), ''),
       nullif(btrim(coalesce(p_icono, '')), ''),
       nullif(btrim(coalesce(p_color_inicio, '')), ''),
       nullif(btrim(coalesce(p_color_fin, '')), ''),
       coalesce(p_orden, 0), coalesce(p_activo, true),
       p_desde, p_hasta, auth.uid())
    returning id into v_id;
  else
    update flow.coleccion
       set titulo       = btrim(p_titulo),
           subtitulo    = nullif(btrim(coalesce(p_subtitulo, '')), ''),
           icono        = nullif(btrim(coalesce(p_icono, '')), ''),
           color_inicio = nullif(btrim(coalesce(p_color_inicio, '')), ''),
           color_fin    = nullif(btrim(coalesce(p_color_fin, '')), ''),
           orden        = coalesce(p_orden, 0),
           activo       = coalesce(p_activo, true),
           desde        = p_desde,
           hasta        = p_hasta,
           updated_at   = current_timestamp
     where id = p_id
     returning id into v_id;

    if v_id is null then
      return jsonb_build_object('ok', false, 'error', 'Coleccion inexistente');
    end if;

    delete from flow.coleccion_servicio where id_coleccion = v_id;
  end if;

  -- `distinct on` porque el mismo id repetido en el array chocaría dos veces
  -- contra la PK en un único INSERT ... ON CONFLICT ("cannot affect row a
  -- second time"). Gana la primera aparición, que es la que fija el orden.
  insert into flow.coleccion_servicio (id_coleccion, id_local_servicio, orden)
  select v_id, d.id_ls, (row_number() over (order by d.pos)) - 1
  from (
    select distinct on ((e.v)::int)
           (e.v)::int as id_ls, e.pos
      from jsonb_array_elements_text(coalesce(p_servicios, '[]'::jsonb))
           with ordinality as e(v, pos)
     order by (e.v)::int, e.pos
  ) d;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'id', v_id,
    'servicios', (select count(*)
                    from flow.coleccion_servicio
                   where id_coleccion = v_id)
  ));
exception
  when others then
    return jsonb_build_object('ok', false, 'error', sqlerrm, 'sqlstate', sqlstate);
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_guardar_fidelidad_config(p_uuid_usuario uuid, p_activa boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'flow', 'public'
AS $function$
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false,
      'error', 'Solo un superadmin con acceso total puede cambiar la fidelidad');
  end if;

  if p_activa is null then
    return jsonb_build_object('ok', false, 'error', 'Falta indicar si se activa o no');
  end if;

  insert into flow.fidelidad_config (id, activa, updated_by, updated_at)
  values (1, p_activa, auth.uid(), current_timestamp)
  on conflict (id) do update
    set activa     = excluded.activa,
        updated_by = excluded.updated_by,
        updated_at = excluded.updated_at;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'activa', p_activa,
    'aviso', case
      when p_activa then 'Fidelidad activada para todos los clientes.'
      else 'Fidelidad desactivada. Los puntos ya ganados se conservan y el Home deja de mostrar la seccion.'
    end
  ));
exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm, 'sqlstate', sqlstate);
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_guardar_promocion(p_uuid_usuario uuid, p_id_local_servicio integer, p_titulo text, p_tipo text, p_valor numeric, p_moneda text DEFAULT NULL::text, p_desde timestamp with time zone DEFAULT NULL::timestamp with time zone, p_hasta timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cupo_total integer DEFAULT NULL::integer, p_activo boolean DEFAULT true, p_id integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_id_entidad integer;
  v_id         integer;
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  -- El local_servicio debe pertenecer a una entidad que el usuario administra.
  select l.id_entidad into v_id_entidad
  from flow.local_servicio ls
  join flow.app_dat_locales l on l.id = ls.id_local
  where ls.id = p_id_local_servicio;

  if v_id_entidad is null then
    return jsonb_build_object('ok', false, 'error', 'El servicio no existe');
  end if;

  if not exists (
    select 1 from flow.admin_entidades_de_usuario(auth.uid()) mine
    where mine.id_entidad = v_id_entidad
  ) then
    return jsonb_build_object('ok', false, 'error', 'No administras esta entidad');
  end if;

  if btrim(coalesce(p_titulo, '')) = '' then
    return jsonb_build_object('ok', false, 'error', 'El titulo es obligatorio');
  end if;
  if p_tipo not in ('porcentaje', 'monto') then
    return jsonb_build_object('ok', false, 'error', 'Tipo invalido');
  end if;
  if p_valor is null or p_valor <= 0 then
    return jsonb_build_object('ok', false, 'error', 'El valor debe ser mayor que 0');
  end if;
  if p_tipo = 'porcentaje' and p_valor > 100 then
    return jsonb_build_object('ok', false, 'error', 'Un porcentaje no puede pasar de 100');
  end if;
  if p_tipo = 'monto' and btrim(coalesce(p_moneda, '')) = '' then
    return jsonb_build_object('ok', false, 'error', 'Un descuento de monto necesita moneda');
  end if;
  if p_desde is not null and p_hasta is not null and p_desde >= p_hasta then
    return jsonb_build_object('ok', false, 'error', 'La fecha de fin debe ser posterior al inicio');
  end if;
  if p_cupo_total is not null and p_cupo_total <= 0 then
    return jsonb_build_object('ok', false, 'error', 'El cupo debe ser mayor que 0');
  end if;

  if p_id is null then
    insert into flow.promocion (
      titulo, tipo, valor, moneda, id_local_servicio,
      desde, hasta, cupo_total, activo
    )
    values (
      btrim(p_titulo), p_tipo, p_valor, nullif(btrim(coalesce(p_moneda, '')), ''),
      p_id_local_servicio, p_desde, p_hasta, p_cupo_total, coalesce(p_activo, true)
    )
    returning id into v_id;
  else
    -- No se toca `cupo_usado`: es contabilidad de reservas ya hechas. Bajar el
    -- cupo_total por debajo de lo ya usado lo rechaza el CHECK.
    update flow.promocion pr
       set titulo = btrim(p_titulo),
           tipo = p_tipo,
           valor = p_valor,
           moneda = nullif(btrim(coalesce(p_moneda, '')), ''),
           desde = p_desde,
           hasta = p_hasta,
           cupo_total = p_cupo_total,
           activo = coalesce(p_activo, true),
           updated_at = current_timestamp
     where pr.id = p_id
       and (pr.id_local_servicio = p_id_local_servicio or pr.id_local_servicio is null)
       and exists (
         select 1 from flow.local_servicio ls2
         join flow.app_dat_locales l2 on l2.id = ls2.id_local
         join flow.admin_entidades_de_usuario(auth.uid()) mine2
           on mine2.id_entidad = l2.id_entidad
         where ls2.id = p_id_local_servicio
           and (pr.id_local_servicio = ls2.id or pr.id_entidad = l2.id_entidad)
       )
     returning pr.id into v_id;

    if v_id is null then
      return jsonb_build_object('ok', false, 'error', 'Promocion inexistente o sin permiso');
    end if;
  end if;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id));
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_guardar_regla_fidelidad(p_uuid_usuario uuid, p_nombre text, p_id_entidad integer, p_moneda text, p_puntos_por_monto numeric, p_monto_base numeric, p_vigencia_dias integer, p_activo boolean, p_desde timestamp with time zone, p_hasta timestamp with time zone, p_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_id     integer;
  v_moneda varchar(3);
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false,
      'error', 'Solo un superadmin con acceso total puede editar la fidelidad');
  end if;

  if coalesce(btrim(p_nombre), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'El nombre es obligatorio');
  end if;

  if p_monto_base is null or p_monto_base <= 0 then
    return jsonb_build_object('ok', false,
      'error', 'El monto base debe ser mayor que cero');
  end if;

  if p_puntos_por_monto is null or p_puntos_por_monto < 0 then
    return jsonb_build_object('ok', false,
      'error', 'Los puntos por monto no pueden ser negativos');
  end if;

  if p_vigencia_dias is not null and p_vigencia_dias <= 0 then
    return jsonb_build_object('ok', false,
      'error', 'La vigencia debe ser de al menos un dia (o vacia para que no caduquen)');
  end if;

  if p_desde is not null and p_hasta is not null and p_desde >= p_hasta then
    return jsonb_build_object('ok', false,
      'error', 'La fecha de fin debe ser posterior a la de inicio');
  end if;

  v_moneda := nullif(btrim(coalesce(p_moneda, '')), '');

  if p_id is null then
    insert into flow.regla_fidelidad
      (nombre, id_entidad, moneda, puntos_por_monto, monto_base,
       vigencia_dias, activo, desde, hasta, created_by)
    values
      (btrim(p_nombre), p_id_entidad, v_moneda, p_puntos_por_monto, p_monto_base,
       p_vigencia_dias, coalesce(p_activo, true), p_desde, p_hasta, auth.uid())
    returning id into v_id;

    return jsonb_build_object('ok', true,
      'data', jsonb_build_object('id', v_id, 'creado', true));
  end if;

  update flow.regla_fidelidad
     set nombre           = btrim(p_nombre),
         id_entidad       = p_id_entidad,
         moneda           = v_moneda,
         puntos_por_monto = p_puntos_por_monto,
         monto_base       = p_monto_base,
         vigencia_dias    = p_vigencia_dias,
         activo           = coalesce(p_activo, true),
         desde            = p_desde,
         hasta            = p_hasta,
         updated_at       = current_timestamp
   where id = p_id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'La regla no existe');
  end if;

  return jsonb_build_object('ok', true,
    'data', jsonb_build_object('id', p_id, 'creado', false));
exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm, 'sqlstate', sqlstate);
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_guardar_tipo_actividad(p_codigo text, p_nombre text, p_activo boolean DEFAULT true, p_id integer DEFAULT NULL::integer, p_id_padre integer DEFAULT NULL::integer, p_orden integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_codigo text;
  v_id integer;
begin
  if auth.uid() is null
     or (
       not exists (select 1 from flow.admin_entidades_de_usuario(auth.uid()))
       and not public.fn_is_superadmin_full_access()
     )
  then
    return jsonb_build_object('ok', false, 'error', 'No administras ninguna entidad');
  end if;

  -- Misma normalizacion que `TipoActividad.codigoDesdeNombre` en la app.
  v_codigo := lower(trim(coalesce(p_codigo, '')));
  v_codigo := translate(v_codigo, 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN');
  v_codigo := regexp_replace(v_codigo, '[^a-z0-9]+', '_', 'g');
  v_codigo := trim(both '_' from v_codigo);

  if trim(coalesce(p_nombre, '')) = '' then
    return jsonb_build_object('ok', false, 'error', 'El nombre es obligatorio');
  end if;
  if v_codigo !~ '^[a-z0-9_]{3,64}$' then
    return jsonb_build_object(
      'ok', false,
      'error', 'El codigo debe tener 3-64 caracteres: minusculas, numeros o guion bajo'
    );
  end if;

  if p_id_padre is not null then
    if not exists (
      select 1 from flow.nom_tipo_actividad_servicio p
      where p.id = p_id_padre and p.id_padre is null
    ) then
      return jsonb_build_object(
        'ok', false,
        'error', 'La categoria padre no existe o es a su vez una subcategoria'
      );
    end if;
  end if;

  if p_id is null then
    if exists (
      select 1 from flow.nom_tipo_actividad_servicio where codigo = v_codigo
    ) then
      return jsonb_build_object('ok', false, 'error', 'Ya existe una categoria con ese codigo');
    end if;
    insert into flow.nom_tipo_actividad_servicio
      (codigo, nombre, activo, id_padre, orden)
    values
      (v_codigo, trim(p_nombre), coalesce(p_activo, true), p_id_padre, coalesce(p_orden, 0))
    returning id into v_id;
  else
    -- El codigo es la clave estable que ya viaja dentro de
    -- `cliente_obtener_servicios` y de `cliente_home_feed`, y que usan los
    -- detectores de transporte: al editar NO se modifica.
    update flow.nom_tipo_actividad_servicio
       set nombre = trim(p_nombre),
           activo = coalesce(p_activo, true),
           id_padre = p_id_padre,
           orden = coalesce(p_orden, orden)
     where id = p_id
     returning id, codigo into v_id, v_codigo;

    if v_id is null then
      return jsonb_build_object('ok', false, 'error', 'Categoria inexistente');
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id', v_id, 'codigo', v_codigo, 'id_padre', p_id_padre
    )
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_guardar_turno(p_uuid_usuario uuid, p_id_recurso integer, p_nombre text, p_tramos jsonb DEFAULT '[]'::jsonb, p_orden integer DEFAULT 0, p_activo boolean DEFAULT true, p_id integer DEFAULT NULL::integer, p_precios jsonb DEFAULT '{}'::jsonb, p_hora_inicio time without time zone DEFAULT NULL::time without time zone, p_hora_fin time without time zone DEFAULT NULL::time without time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_id       integer;
  v_recurso  integer;
  v_bad      integer;
begin
  if coalesce(btrim(p_nombre), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'el nombre del turno es obligatorio');
  end if;

  if p_id is null then
    if not flow._admin_puede_recurso(p_uuid_usuario, p_id_recurso) then
      return jsonb_build_object('ok', false, 'error', 'recurso inexistente o sin permiso');
    end if;
    v_recurso := p_id_recurso;
    insert into flow.turno (id_recurso, nombre, orden, activo, precios, hora_inicio, hora_fin)
    values (p_id_recurso, btrim(p_nombre), coalesce(p_orden,0), coalesce(p_activo,true),
            coalesce(p_precios, '{}'::jsonb), p_hora_inicio, p_hora_fin)
    returning id into v_id;
  else
    select t.id_recurso into v_recurso
    from flow.turno t
    where t.id = p_id and flow._admin_puede_recurso(p_uuid_usuario, t.id_recurso);
    if v_recurso is null then
      return jsonb_build_object('ok', false, 'error', 'turno inexistente o sin permiso');
    end if;
    update flow.turno
       set nombre      = btrim(p_nombre),
           orden       = coalesce(p_orden, orden),
           activo      = coalesce(p_activo, activo),
           precios     = coalesce(p_precios, '{}'::jsonb),
           hora_inicio = p_hora_inicio,
           hora_fin    = p_hora_fin,
           updated_at  = now()
     where id = p_id
    returning id into v_id;
  end if;

  -- Validar que todos los tramos pedidos pertenezcan al recurso del turno.
  if p_tramos is not null and jsonb_array_length(p_tramos) > 0 then
    select count(*) into v_bad
    from jsonb_array_elements_text(p_tramos) e(tid)
    left join flow.tramo tr on tr.id = e.tid::int
    where tr.id is null or tr.id_recurso <> v_recurso;
    if v_bad > 0 then
      return jsonb_build_object('ok', false, 'error', 'algun tramo no pertenece al recurso del turno');
    end if;
  end if;

  -- Reemplazar el set de tramos del turno.
  delete from flow.turno_tramo where id_turno = v_id;
  if p_tramos is not null and jsonb_array_length(p_tramos) > 0 then
    insert into flow.turno_tramo (id_turno, id_tramo)
    select v_id, e.tid::int
    from jsonb_array_elements_text(p_tramos) e(tid)
    on conflict do nothing;
  end if;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_guardar_turno_auto(p_uuid_usuario uuid, p_id_local_servicio integer, p_nombre text, p_orden integer DEFAULT 0, p_activo boolean DEFAULT true, p_precios jsonb DEFAULT '{}'::jsonb, p_hora_inicio time without time zone DEFAULT NULL::time without time zone, p_hora_fin time without time zone DEFAULT NULL::time without time zone, p_id integer DEFAULT NULL::integer, p_id_recurso integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_recurso integer;
  v_turno   integer;
  v_tramo   integer;
begin
  if not flow._admin_puede_local_servicio(p_uuid_usuario, p_id_local_servicio) then
    return jsonb_build_object('ok', false, 'error', 'local_servicio inexistente o sin permiso');
  end if;

  if coalesce(btrim(p_nombre), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'el nombre del turno es obligatorio');
  end if;

  if p_id is null then
    if p_id_recurso is not null then
      -- Recurso elegido por el admin: tiene que ser de este local_servicio y
      -- estar bajo su permiso. Si no, se falla en vez de colocar el turno en
      -- otro recurso por sorpresa.
      select r.id into v_recurso
      from flow.recurso r
      where r.id = p_id_recurso
        and r.id_local_servicio = p_id_local_servicio
        and flow._admin_puede_recurso(p_uuid_usuario, r.id);

      if v_recurso is null then
        return jsonb_build_object('ok', false, 'error', 'recurso inexistente o sin permiso');
      end if;
    else
      -- Sin recurso indicado: el único del local_servicio; si no hay, uno oculto.
      select r.id into v_recurso
      from flow.recurso r
      where r.id_local_servicio = p_id_local_servicio
      order by r.orden, r.id
      limit 1;

      if v_recurso is null then
        insert into flow.recurso (id_local_servicio, nombre, capacidad, orden, activo)
        select p_id_local_servicio,
               'Cupo',
               greatest(coalesce(ls.cantidad_max_capacidad, 1), 1),
               0,
               true
        from flow.local_servicio ls
        where ls.id = p_id_local_servicio
        returning id into v_recurso;
      end if;
    end if;

    insert into flow.turno (id_recurso, nombre, orden, activo, precios, hora_inicio, hora_fin)
    values (
      v_recurso, btrim(p_nombre), coalesce(p_orden, 0), coalesce(p_activo, true),
      coalesce(p_precios, '{}'::jsonb), p_hora_inicio, p_hora_fin
    )
    returning id into v_turno;
  else
    -- Edición: el recurso es el del propio turno; p_id_recurso se ignora.
    select t.id_recurso into v_recurso
    from flow.turno t
    where t.id = p_id
      and flow._admin_puede_recurso(p_uuid_usuario, t.id_recurso);

    if v_recurso is null then
      return jsonb_build_object('ok', false, 'error', 'turno inexistente o sin permiso');
    end if;

    update flow.turno
       set nombre      = btrim(p_nombre),
           orden       = coalesce(p_orden, orden),
           activo      = coalesce(p_activo, activo),
           precios     = coalesce(p_precios, '{}'::jsonb),
           hora_inicio = p_hora_inicio,
           hora_fin    = p_hora_fin,
           updated_at  = now()
     where id = p_id
    returning id into v_turno;
  end if;

  -- Tramo propio del turno, sólo si aún no tiene ninguno.
  insert into flow.tramo (id_recurso, nombre, capacidad, orden, activo)
  select v_recurso, btrim(p_nombre), null, coalesce(p_orden, 0), true
  where not exists (
    select 1 from flow.turno_tramo tt where tt.id_turno = v_turno
  )
  returning id into v_tramo;

  if v_tramo is not null then
    insert into flow.turno_tramo (id_turno, id_tramo)
    values (v_turno, v_tramo)
    on conflict do nothing;
  end if;

  -- En modo simplificado los tramos son invisibles: se renombran con el turno
  -- para que la BD se lea sola si alguien la inspecciona a mano.
  if exists (
    select 1
    from flow.local_servicio ls
    join flow.recurso r      on r.id_local_servicio = ls.id
    join flow.turno_tramo tt on tt.id_turno = v_turno
    join flow.tramo tr       on tr.id = tt.id_tramo
    where ls.id = p_id_local_servicio and ls.sin_tramos
  ) then
    update flow.tramo tr
       set nombre = btrim(p_nombre), updated_at = now()
     where tr.id in (
       select tt.id_tramo from flow.turno_tramo tt where tt.id_turno = v_turno
     );
  end if;

  return jsonb_build_object(
    'ok', true,
    'id', v_turno,
    'id_recurso', v_recurso,
    'id_tramo', v_tramo
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_listar_admins(p_id_entidad integer)
 RETURNS TABLE(id integer, id_entidad integer, uuid_usuario uuid, asignado_por uuid, created_at timestamp without time zone, email text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'flow', 'auth'
AS $function$
  select ea.id, ea.id_entidad, ea.uuid_usuario, ea.asignado_por,
         ea.created_at, u.email::text
  from flow.entidad_admin ea
  join auth.users u on u.id = ea.uuid_usuario
  where ea.id_entidad = p_id_entidad
    -- Sin esta comprobacion, cualquier autenticado (o anonimo, por el grant a
    -- PUBLIC) podia listar los uuid y emails de los admins de cualquier entidad.
    and exists (
      select 1 from flow.admin_entidades_de_usuario(auth.uid()) mine
      where mine.id_entidad = p_id_entidad
    )
  order by ea.created_at;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_listar_agendas(p_uuid_usuario uuid, p_id_entidad integer DEFAULT NULL::integer, p_id_local integer DEFAULT NULL::integer, p_id_local_servicio integer DEFAULT NULL::integer, p_id_estado integer DEFAULT NULL::integer, p_desde timestamp without time zone DEFAULT NULL::timestamp without time zone, p_hasta timestamp without time zone DEFAULT NULL::timestamp without time zone)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',                  a.id,
        'uuid_usuario',        a.uuid_usuario,
        'id_estado',           a.id_estado,
        'fecha_hora_reserva',  a.fecha_hora_reserva,
        'fecha_hora_atencion', a.fecha_hora_atencion,
        'created_at',          a.created_at,
        'updated_at',          a.updated_at,
        'cantidad',            a.cantidad,
        'datos_adicionales',   a.datos_adicionales,
        'reservado_por',       a.reservado_por,
        'precio_total',        a.precio_total,
        'moneda',              a.moneda,
        'id_turno',            a.id_turno,
        'id_viaje',            a.id_viaje,
        'tipo_trayecto',       a.tipo_trayecto,
        'turno', case when t.id is null then null else jsonb_build_object(
          'id',     t.id,
          'nombre', t.nombre,
          'recurso', jsonb_build_object('id', r.id, 'nombre', r.nombre)
        ) end,
        'estado', jsonb_build_object(
          'id',          es.id,
          'nombre',      es.nombre,
          'descripcion', es.descripcion
        ),
        'id_local_servicio', ls.id,
        'servicio', jsonb_build_object(
          'id',                 s.id,
          'nombre',             s.nombre,
          'descripcion',        s.descripcion,
          'foto',               s.foto,
          'campos_adicionales', s.campos_adicionales,
          'config_precio',      s.config_precio
        ),
        'local', jsonb_build_object(
          'id',               l.id,
          'nombre',           l.nombre,
          'direccion',        l.direccion,
          'pais',             l.pais,
          'provincia',        l.provincia,
          'horario_atencion', l.horario_atencion,
          'coordenadas',      l.coordenadas,
          'foto',             l.foto
        ),
        'entidad', jsonb_build_object(
          'id',           en.id,
          'denominacion', en.denominacion,
          'direccion',    en.direccion,
          'telefono',     en.telefono
        ),
        'cliente', case when p.id is null then null else jsonb_build_object(
          'id',           p.id,
          'uuid_usuario', p.uuid_usuario,
          'nombre',       p.nombre,
          'apellidos',    p.apellidos,
          'ci',           p.ci,
          'telefono',     p.telefono,
          'created_at',   p.created_at,
          'updated_at',   p.updated_at
        ) end
      )
      order by a.fecha_hora_reserva desc
    ),
    '[]'::jsonb
  )
  from flow.agenda a
  join flow.local_servicio    ls on ls.id = a.id_local_servicio
  join flow.app_dat_locales   l  on l.id  = ls.id_local
  join flow.app_dat_servicios s  on s.id  = ls.id_servicio
  join flow.entidad           en on en.id = l.id_entidad
  join flow.nom_estado_agenda es on es.id = a.id_estado
  left join flow.perfil       p  on p.uuid_usuario = a.uuid_usuario
  left join flow.turno        t  on t.id = a.id_turno
  left join flow.recurso      r  on r.id = t.id_recurso
  join flow.admin_entidades_de_usuario(auth.uid()) mine on mine.id_entidad = l.id_entidad
  where (p_id_entidad        is null or l.id_entidad         = p_id_entidad)
    and (p_id_local          is null or ls.id_local          = p_id_local)
    and (p_id_local_servicio is null or a.id_local_servicio  = p_id_local_servicio)
    and (p_id_estado         is null or a.id_estado          = p_id_estado)
    and (p_desde             is null or a.fecha_hora_reserva::date >= p_desde::date)
    and (p_hasta             is null or a.fecha_hora_reserva::date <= p_hasta::date);
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_listar_agendas_por_estado(p_uuid_usuario uuid, p_id_entidad integer DEFAULT NULL::integer, p_id_local integer DEFAULT NULL::integer, p_id_local_servicio integer DEFAULT NULL::integer, p_id_estado integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',                  a.id,
        'uuid_usuario',        a.uuid_usuario,
        'id_estado',           a.id_estado,
        'fecha_hora_reserva',  a.fecha_hora_reserva,
        'fecha_hora_atencion', a.fecha_hora_atencion,
        'created_at',          a.created_at,
        'updated_at',          a.updated_at,
        'cantidad',            a.cantidad,
        'datos_adicionales',   a.datos_adicionales,
        'reservado_por',       a.reservado_por,
        'precio_total',        a.precio_total,
        'moneda',              a.moneda,
        'id_turno',            a.id_turno,
        'id_viaje',            a.id_viaje,
        'tipo_trayecto',       a.tipo_trayecto,
        'turno', case when t.id is null then null else jsonb_build_object(
          'id',     t.id,
          'nombre', t.nombre,
          'recurso', jsonb_build_object('id', r.id, 'nombre', r.nombre)
        ) end,
        'estado', jsonb_build_object(
          'id',          es.id,
          'nombre',      es.nombre,
          'descripcion', es.descripcion
        ),
        'id_local_servicio', ls.id,
        'servicio', jsonb_build_object(
          'id',                 s.id,
          'nombre',             s.nombre,
          'descripcion',        s.descripcion,
          'foto',               s.foto,
          'campos_adicionales', s.campos_adicionales,
          'config_precio',      s.config_precio
        ),
        'local', jsonb_build_object(
          'id',               l.id,
          'nombre',           l.nombre,
          'direccion',        l.direccion,
          'pais',             l.pais,
          'provincia',        l.provincia,
          'horario_atencion', l.horario_atencion,
          'coordenadas',      l.coordenadas,
          'foto',             l.foto
        ),
        'entidad', jsonb_build_object(
          'id',           en.id,
          'denominacion', en.denominacion,
          'direccion',    en.direccion,
          'telefono',     en.telefono
        ),
        'cliente', case when p.id is null then null else jsonb_build_object(
          'id',           p.id,
          'uuid_usuario', p.uuid_usuario,
          'nombre',       p.nombre,
          'apellidos',    p.apellidos,
          'ci',           p.ci,
          'telefono',     p.telefono,
          'created_at',   p.created_at,
          'updated_at',   p.updated_at
        ) end
      )
      order by a.fecha_hora_reserva desc
    ),
    '[]'::jsonb
  )
  from flow.agenda a
  join flow.local_servicio    ls on ls.id = a.id_local_servicio
  join flow.app_dat_locales   l  on l.id  = ls.id_local
  join flow.app_dat_servicios s  on s.id  = ls.id_servicio
  join flow.entidad           en on en.id = l.id_entidad
  join flow.nom_estado_agenda es on es.id = a.id_estado
  left join flow.perfil       p  on p.uuid_usuario = a.uuid_usuario
  left join flow.turno        t  on t.id = a.id_turno
  left join flow.recurso      r  on r.id = t.id_recurso
  join flow.admin_entidades_de_usuario(auth.uid()) mine
    on mine.id_entidad = l.id_entidad
  where (p_id_entidad        is null or l.id_entidad         = p_id_entidad)
    and (p_id_local          is null or ls.id_local          = p_id_local)
    and (p_id_local_servicio is null or a.id_local_servicio  = p_id_local_servicio)
    and (p_id_estado         is null or a.id_estado          = p_id_estado)
    and a.fecha_hora_reserva::date >= (timezone('America/Havana', now()))::date;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_listar_beneficios_bienvenida(p_uuid_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false,
      'error', 'Solo un superadmin con acceso total puede ver los beneficios');
  end if;

  return jsonb_build_object('ok', true, 'data', coalesce((
    select jsonb_agg(x order by x.id)
    from (
      select b.id,
             b.titulo,
             b.descripcion,
             b.tipo,
             b.valor,
             b.moneda,
             b.id_entidad,
             e.denominacion as entidad,
             b.monto_minimo,
             b.activo,
             b.desde,
             b.hasta,
             b.created_at,
             b.updated_at,
             -- Cuantos usuarios ya lo canjearon. Es el dato que decide si se puede
             -- borrar o si hay que desactivarlo.
             (select count(*) from flow.beneficio_canje c
               where c.id_beneficio = b.id) as canjes
      from flow.beneficio_bienvenida b
      left join flow.entidad e on e.id = b.id_entidad
      order by b.id
    ) x
  ), '[]'::jsonb));
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_listar_campanas(p_uuid_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_result jsonb;
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error', 'Solo el superadmin puede gestionar campanas');
  end if;

  select coalesce(jsonb_agg(to_jsonb(t) order by t.prioridad desc, t.id desc), '[]'::jsonb)
    into v_result
  from (
    select
      c.*,
      l.nombre as local,
      s.nombre as servicio,
      en.denominacion as entidad
    from flow.campana c
    left join flow.local_servicio   ls on ls.id = c.id_local_servicio
    left join flow.app_dat_locales  l  on l.id  = ls.id_local
    left join flow.app_dat_servicios s on s.id  = ls.id_servicio
    left join flow.entidad          en on en.id = coalesce(l.id_entidad, c.id_entidad)
  ) t;

  return jsonb_build_object('ok', true, 'data', v_result);
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_listar_colecciones(p_uuid_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error',
      'Solo el superadmin puede gestionar colecciones');
  end if;

  return jsonb_build_object('ok', true, 'data', (
    select coalesce(
      jsonb_agg(to_jsonb(t) order by t.orden asc, t.id asc),
      '[]'::jsonb
    )
    from (
      select
        c.id, c.titulo, c.subtitulo, c.icono,
        c.color_inicio, c.color_fin, c.orden, c.activo,
        c.desde, c.hasta, c.created_at, c.updated_at,
        (select count(*)
           from flow.coleccion_servicio cs
          where cs.id_coleccion = c.id) as total_servicios,
        (select coalesce(
                  jsonb_agg(cs.id_local_servicio
                            order by cs.orden asc, cs.id_local_servicio asc),
                  '[]'::jsonb)
           from flow.coleccion_servicio cs
          where cs.id_coleccion = c.id) as servicios
      from flow.coleccion c
    ) t
  ));
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_listar_movimientos_puntos(p_uuid_usuario uuid, p_uuid_destino uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false,
      'error', 'Solo un superadmin con acceso total puede auditar puntos');
  end if;

  if p_uuid_destino is null then
    return jsonb_build_object('ok', false, 'error', 'Falta el usuario a auditar');
  end if;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'uuid_usuario', p_uuid_destino,
      'saldo', flow.fn_saldo_puntos(p_uuid_destino),
      'ya_canjeo', exists (
        select 1 from flow.beneficio_canje c where c.uuid_usuario = p_uuid_destino
      ),
      'movimientos', coalesce((
        select jsonb_agg(x order by x.created_at desc)
        from (
          select m.id, m.puntos, m.tipo, m.motivo, m.moneda, m.monto,
                 m.vence_en, m.liquidado, m.created_at,
                 m.id_agenda, m.id_entidad,
                 r.nombre as regla,
                 (m.tipo = 'acumulacion'
                  and m.liquidado = false
                  and m.vence_en is not null
                  and m.vence_en <= current_timestamp) as vencido
          from flow.puntos_movimiento m
          left join flow.regla_fidelidad r on r.id = m.id_regla
          where m.uuid_usuario = p_uuid_destino
          order by m.created_at desc
          limit 200
        ) x
      ), '[]'::jsonb)
    )
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_listar_promociones(p_uuid_usuario uuid, p_id_local_servicio integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_result jsonb;
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  select coalesce(jsonb_agg(to_jsonb(t) order by t.id desc), '[]'::jsonb)
    into v_result
  from (
    select
      pr.id, pr.titulo, pr.descripcion, pr.tipo, pr.valor, pr.moneda,
      pr.id_local_servicio, pr.id_entidad,
      pr.desde, pr.hasta, pr.cupo_total, pr.cupo_usado, pr.activo,
      pr.created_at, pr.updated_at,
      s.nombre as servicio,
      l.nombre as local
    from flow.promocion pr
    left join flow.local_servicio ls on ls.id = pr.id_local_servicio
    left join flow.app_dat_servicios s on s.id = ls.id_servicio
    left join flow.app_dat_locales l on l.id = ls.id_local
    where exists (
      select 1 from flow.admin_entidades_de_usuario(auth.uid()) mine
      where mine.id_entidad = coalesce(l.id_entidad, pr.id_entidad)
    )
      and (p_id_local_servicio is null or pr.id_local_servicio = p_id_local_servicio)
  ) t;

  return jsonb_build_object('ok', true, 'data', v_result);
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_listar_recursos(p_uuid_usuario uuid, p_id_local_servicio integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_data jsonb;
begin
  if not flow._admin_puede_local_servicio(p_uuid_usuario, p_id_local_servicio) then
    return jsonb_build_object('ok', false, 'error', 'local_servicio inexistente o sin permiso');
  end if;

  select coalesce(jsonb_agg(rec order by rec_orden, rec_id), '[]'::jsonb)
    into v_data
  from (
    select
      r.orden as rec_orden,
      r.id    as rec_id,
      jsonb_build_object(
        'id',        r.id,
        'nombre',    r.nombre,
        'capacidad', r.capacidad,
        'orden',     r.orden,
        'activo',    r.activo,
        'tramos', (
          select coalesce(jsonb_agg(jsonb_build_object(
                    'id',        tr.id,
                    'nombre',    tr.nombre,
                    'capacidad', tr.capacidad,
                    'tipo_trayecto', tr.tipo_trayecto,
                    'orden',     tr.orden,
                    'activo',    tr.activo
                  ) order by tr.orden, tr.id), '[]'::jsonb)
          from flow.tramo tr where tr.id_recurso = r.id
        ),
        'turnos', (
          select coalesce(jsonb_agg(jsonb_build_object(
                    'id',      t.id,
                    'nombre',  t.nombre,
                    'orden',   t.orden,
                    'activo',  t.activo,
                    'precios', t.precios,
                    -- Horas opcionales del turno (punto 7). `to_char` con
                    -- 'HH24:MI' para que viajen como "09:00" y no como
                    -- "09:00:00", que es lo que espera el selector de hora.
                    'hora_inicio', case when t.hora_inicio is null then null
                                        else to_char(t.hora_inicio, 'HH24:MI') end,
                    'hora_fin',    case when t.hora_fin is null then null
                                        else to_char(t.hora_fin, 'HH24:MI') end,
                    'tramos', (
                      select coalesce(jsonb_agg(tt.id_tramo order by tt.id_tramo), '[]'::jsonb)
                      from flow.turno_tramo tt where tt.id_turno = t.id
                    )
                  ) order by t.orden, t.id), '[]'::jsonb)
          from flow.turno t where t.id_recurso = r.id
        )
      ) as rec
    from flow.recurso r
    where r.id_local_servicio = p_id_local_servicio
  ) s;

  return jsonb_build_object('ok', true, 'data', v_data);
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_listar_reglas_fidelidad(p_uuid_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false,
      'error', 'Solo un superadmin con acceso total puede ver el programa de fidelidad');
  end if;

  return jsonb_build_object('ok', true, 'data', coalesce((
    select jsonb_agg(x order by x.id)
    from (
      select r.id,
             r.nombre,
             r.id_entidad,
             e.denominacion as entidad,
             r.moneda,
             r.puntos_por_monto,
             r.monto_base,
             r.vigencia_dias,
             r.activo,
             r.desde,
             r.hasta,
             r.created_at,
             r.updated_at
      from flow.regla_fidelidad r
      left join flow.entidad e on e.id = r.id_entidad
      order by r.id
    ) x
  ), '[]'::jsonb));
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_listar_salas_espera(p_uuid_usuario uuid, p_id_entidad integer DEFAULT NULL::integer, p_id_local integer DEFAULT NULL::integer, p_id_local_servicio integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',          se.id,
        'numero_cola', se.numero_cola,
        'fecha_regla', se.fecha_regla,
        'created_at',  se.created_at,
        'id_local_servicio', ls.id,
        'id_turno',    se.id_turno,
        'turno',       t.nombre,
        'servicio', jsonb_build_object('id', s.id, 'nombre', s.nombre),
        'local',    jsonb_build_object('id', l.id, 'nombre', l.nombre),
        'entidad',  jsonb_build_object('id', en.id, 'denominacion', en.denominacion),
        'cliente', case when p.id is null then null else jsonb_build_object(
          'uuid_usuario', p.uuid_usuario,
          'nombre',       p.nombre,
          'apellidos',    p.apellidos,
          'ci',           p.ci,
          'telefono',     p.telefono
        ) end
      )
      order by l.nombre, s.nombre, se.numero_cola
    ),
    '[]'::jsonb
  )
  from flow.sala_espera se
  join flow.local_servicio    ls on ls.id = se.id_local_servicio
  join flow.app_dat_locales   l  on l.id  = ls.id_local
  join flow.app_dat_servicios s  on s.id  = ls.id_servicio
  join flow.entidad           en on en.id = l.id_entidad
  left join flow.turno        t  on t.id  = se.id_turno
  left join flow.perfil       p  on p.uuid_usuario = se.uuid_usuario
  join flow.admin_entidades_de_usuario(p_uuid_usuario) mine on mine.id_entidad = l.id_entidad
  where (p_id_entidad        is null or l.id_entidad        = p_id_entidad)
    and (p_id_local          is null or ls.id_local         = p_id_local)
    and (p_id_local_servicio is null or se.id_local_servicio = p_id_local_servicio);
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_listar_vendedores(p_id_entidad integer)
 RETURNS TABLE(id integer, id_entidad integer, uuid_usuario uuid, asignado_por uuid, created_at timestamp without time zone, email text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'flow', 'auth'
AS $function$
  select ev.id, ev.id_entidad, ev.uuid_usuario, ev.asignado_por,
         ev.created_at, u.email::text
  from flow.entidad_vendedor ev
  join auth.users u on u.id = ev.uuid_usuario
  where ev.id_entidad = p_id_entidad
    and exists (
      select 1 from flow.admin_entidades_de_usuario(auth.uid()) mine
      where mine.id_entidad = p_id_entidad
    )
  order by ev.created_at;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_notificacion_marcar(p_id bigint, p_estado text, p_error text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
begin
  if not (public.fn_is_superadmin_full_access() or auth.role() = 'service_role') then
    return jsonb_build_object('ok', false, 'error', 'Solo el superadmin o service_role');
  end if;

  if p_estado not in ('enviada','fallida','omitida') then
    return jsonb_build_object('ok', false, 'error', 'Estado no valido');
  end if;

  update flow.suscripcion_notificacion n
     set estado     = p_estado,
         error      = p_error,
         intentos   = n.intentos + 1,
         enviada_at = case when p_estado = 'enviada' then now() else n.enviada_at end
   where n.id = p_id;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'La notificacion no existe');
  end if;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id, 'estado', p_estado));
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_notificaciones_pendientes(p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
begin
  if not (public.fn_is_superadmin_full_access() or auth.role() = 'service_role') then
    return jsonb_build_object('ok', false, 'error', 'Solo el superadmin o service_role');
  end if;

  return jsonb_build_object('ok', true, 'data', coalesce((
    select jsonb_agg(jsonb_build_object(
             'id',         n.id,
             'id_entidad', n.id_entidad,
             'destino',    n.destino,
             'mensaje',    n.mensaje,
             'intentos',   n.intentos,
             'created_at', n.created_at)
           order by n.created_at)
    from (
      select * from flow.suscripcion_notificacion
      where estado = 'pendiente' and canal = 'whatsapp'
      order by created_at
      limit greatest(1, least(coalesce(p_limit, 50), 500))
    ) n), '[]'::jsonb));
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_obtener_fidelidad_config(p_uuid_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false,
      'error', 'Solo un superadmin con acceso total puede ver la configuracion de fidelidad');
  end if;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'activa', coalesce(
      (select c.activa from flow.fidelidad_config c where c.id = 1), true
    ),
    'updated_at', (select c.updated_at from flow.fidelidad_config c where c.id = 1),
    'updated_by', (select c.updated_by from flow.fidelidad_config c where c.id = 1)
  ));
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_ocultar_categoria_entidad(p_id_entidad integer, p_id_tipo_actividad integer, p_oculto boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_oculto boolean := coalesce(p_oculto, false);
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  if not (
    public.fn_is_superadmin_full_access()
    or flow.is_entidad_admin(p_id_entidad)
  ) then
    return jsonb_build_object('ok', false, 'error', 'No administras esa entidad');
  end if;

  if not exists (select 1 from flow.entidad e where e.id = p_id_entidad) then
    return jsonb_build_object('ok', false, 'error', 'Entidad inexistente');
  end if;

  if not exists (
    select 1 from flow.nom_tipo_actividad_servicio t
    where t.id = p_id_tipo_actividad
  ) then
    return jsonb_build_object('ok', false, 'error', 'Categoria inexistente');
  end if;

  if v_oculto then
    if not exists (
      select 1 from flow.entidad_categoria_oculta o
      where o.id_entidad = p_id_entidad
        and o.id_tipo_actividad = p_id_tipo_actividad
    ) then
      insert into flow.entidad_categoria_oculta (id_entidad, id_tipo_actividad)
      values (p_id_entidad, p_id_tipo_actividad);
    end if;
  else
    delete from flow.entidad_categoria_oculta o
    where o.id_entidad = p_id_entidad
      and o.id_tipo_actividad = p_id_tipo_actividad;
  end if;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id_entidad', p_id_entidad,
      'id_tipo_actividad', p_id_tipo_actividad,
      'oculta', v_oculto
    )
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_plan_eliminar(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_usos integer;
begin
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error', 'Solo el superadmin puede gestionar planes');
  end if;

  -- Borrar un plan con historia romperia el libro. Se apaga.
  select (select count(*) from flow.suscripcion s where s.id_plan = p_id)
       + (select count(*) from flow.suscripcion_intent i where i.id_plan = p_id)
    into v_usos;

  if v_usos > 0 then
    update flow.suscripcion_plan set activo = false where id = p_id;
    return jsonb_build_object('ok', true,
      'data', jsonb_build_object('id', p_id, 'eliminado', false, 'desactivado', true,
                                 'motivo', 'El plan tiene ' || v_usos || ' uso(s): se desactivo en vez de borrarse'));
  end if;

  delete from flow.suscripcion_plan where id = p_id;
  return jsonb_build_object('ok', true, 'data', jsonb_build_object('id', p_id, 'eliminado', true));
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_plan_guardar(p_id bigint DEFAULT NULL::bigint, p_codigo text DEFAULT NULL::text, p_nombre text DEFAULT NULL::text, p_descripcion text DEFAULT NULL::text, p_duracion_dias integer DEFAULT NULL::integer, p_precio numeric DEFAULT NULL::numeric, p_moneda text DEFAULT NULL::text, p_limites jsonb DEFAULT NULL::jsonb, p_orden integer DEFAULT NULL::integer, p_activo boolean DEFAULT NULL::boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_id  bigint := p_id;
  v_plan flow.suscripcion_plan%rowtype;
begin
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error', 'Solo el superadmin puede gestionar planes');
  end if;

  if v_id is null then
    if p_codigo is null or btrim(p_codigo) = ''
       or p_nombre is null or btrim(p_nombre) = ''
       or p_duracion_dias is null or p_duracion_dias <= 0 then
      return jsonb_build_object('ok', false,
        'error', 'Para crear un plan hacen falta codigo, nombre y duracion en dias');
    end if;

    insert into flow.suscripcion_plan
      (codigo, nombre, descripcion, duracion_dias, precio, moneda, limites, orden, activo, updated_by)
    values
      (btrim(p_codigo), btrim(p_nombre), p_descripcion, p_duracion_dias,
       coalesce(p_precio, 0), coalesce(nullif(btrim(coalesce(p_moneda, '')), ''), 'CUP'),
       coalesce(p_limites, '{}'::jsonb), coalesce(p_orden, 0),
       coalesce(p_activo, false), v_uid)
    returning id into v_id;

    return jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id, 'creado', true));
  end if;

  select p.* into v_plan from flow.suscripcion_plan p where p.id = v_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'El plan no existe');
  end if;

  if p_codigo is not null and btrim(p_codigo) <> v_plan.codigo
     and exists (select 1 from flow.suscripcion_plan p2
                  where p2.codigo = btrim(p_codigo) and p2.id <> v_id) then
    return jsonb_build_object('ok', false, 'error', 'Ya existe un plan con ese codigo');
  end if;

  update flow.suscripcion_plan p
     set codigo        = coalesce(nullif(btrim(coalesce(p_codigo, '')), ''), p.codigo),
         nombre        = coalesce(nullif(btrim(coalesce(p_nombre, '')), ''), p.nombre),
         descripcion   = coalesce(p_descripcion, p.descripcion),
         duracion_dias = coalesce(p_duracion_dias, p.duracion_dias),
         precio        = coalesce(p_precio, p.precio),
         moneda        = coalesce(nullif(btrim(coalesce(p_moneda, '')), ''), p.moneda),
         limites       = coalesce(p_limites, p.limites),
         orden         = coalesce(p_orden, p.orden),
         activo        = coalesce(p_activo, p.activo),
         updated_by    = v_uid
   where p.id = v_id;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_id, 'creado', false));
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_planes_listar()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
begin
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error', 'Solo el superadmin puede ver los planes');
  end if;

  return jsonb_build_object('ok', true, 'data', coalesce((
    select jsonb_agg(jsonb_build_object(
             'id',            p.id,
             'codigo',        p.codigo,
             'nombre',        p.nombre,
             'descripcion',   p.descripcion,
             'duracion_dias', p.duracion_dias,
             'precio',        p.precio,
             'moneda',        p.moneda,
             'limites',       p.limites,
             'orden',         p.orden,
             'activo',        p.activo,
             'created_at',    p.created_at,
             'updated_at',    p.updated_at)
           order by p.orden, p.precio, p.id)
    from flow.suscripcion_plan p), '[]'::jsonb));
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_suscripcion_acreditar(p_id_entidad integer, p_dias integer, p_id_plan bigint DEFAULT NULL::bigint, p_motivo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_uid   uuid := auth.uid();
  v_owner uuid;
  v_res   jsonb;
  v_dias  integer := p_dias;
  v_plan  flow.suscripcion_plan%rowtype;
begin
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error', 'Solo el superadmin puede acreditar planes');
  end if;

  if to_regclass('flow.entidad') is not null
     and not exists (select 1 from flow.entidad e where e.id = p_id_entidad) then
    return jsonb_build_object('ok', false, 'error', 'La entidad no existe');
  end if;

  -- Si dan plan y no dias, se usan los del plan.
  if p_id_plan is not null then
    select p.* into v_plan from flow.suscripcion_plan p where p.id = p_id_plan;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'El plan no existe');
    end if;
    if v_dias is null then
      v_dias := v_plan.duracion_dias;
    end if;
  end if;

  if p_motivo is null or btrim(p_motivo) = '' then
    return jsonb_build_object('ok', false,
      'error', 'La acreditacion manual exige un motivo (queda en el libro de movimientos)');
  end if;

  if v_dias is null or v_dias <= 0 then
    return jsonb_build_object('ok', false, 'error', 'Indica los dias o el plan a acreditar');
  end if;

  v_res := flow._susc_acreditar_dias(
             p_id_entidad, p_id_plan, v_dias, 'acreditacion_admin',
             btrim(p_motivo), v_uid, null);

  if not coalesce((v_res ->> 'ok')::boolean, false) then
    return v_res;
  end if;

  select e.owner_uuid into v_owner from flow.entidad e where e.id = p_id_entidad;

  perform flow._susc_notificar_inapp(
    p_id_entidad, v_owner,
    'Suscripcion acreditada',
    'El administrador acredito ' || v_dias || ' dia(s) de suscripcion. '
      || 'Activa hasta el '
      || to_char((v_res -> 'data' ->> 'fecha_vencimiento')::timestamptz, 'DD/MM/YYYY') || '.');

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id_entidad', p_id_entidad,
      'acreditacion', v_res -> 'data'
    )
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_suscripcion_aprobar_pago(p_id_transaccion bigint, p_observaciones text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_uid   uuid := auth.uid();
  v_trx   flow.suscripcion_transaccion%rowtype;
  v_int   flow.suscripcion_intent%rowtype;
  v_plan  flow.suscripcion_plan%rowtype;
  v_owner uuid;
  v_res   jsonb;
begin
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error', 'Solo el superadmin puede verificar pagos');
  end if;

  select t.* into v_trx from flow.suscripcion_transaccion t where t.id = p_id_transaccion;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'El pago no existe');
  end if;

  if v_trx.estado <> 'reportado' then
    return jsonb_build_object('ok', false,
      'error', 'Ese pago ya fue procesado (estado: ' || v_trx.estado || ')');
  end if;

  select i.* into v_int from flow.suscripcion_intent i where i.id = v_trx.id_intent;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'El intento de pago asociado no existe');
  end if;

  select p.* into v_plan from flow.suscripcion_plan p where p.id = v_int.id_plan;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'El plan del intento ya no existe');
  end if;

  -- Acreditar: suma los dias del plan a lo que le quede vigente.
  v_res := flow._susc_acreditar_dias(
             v_trx.id_entidad,
             v_plan.id,
             v_plan.duracion_dias,
             'compra',
             coalesce(p_observaciones, 'Pago verificado #' || v_trx.id),
             v_uid,
             v_trx.id);

  if not coalesce((v_res ->> 'ok')::boolean, false) then
    return v_res;
  end if;

  update flow.suscripcion_transaccion t
     set estado         = 'verificado',
         verificado_por = v_uid,
         verificado_at  = now(),
         observaciones  = coalesce(p_observaciones, t.observaciones)
   where t.id = v_trx.id;

  update flow.suscripcion_intent
     set estado = 'verificado'
   where id = v_int.id;

  select e.owner_uuid into v_owner from flow.entidad e where e.id = v_trx.id_entidad;

  perform flow._susc_notificar_inapp(
    v_trx.id_entidad, v_owner,
    'Suscripcion acreditada',
    'Verificamos tu pago y acreditamos el plan ' || v_plan.nombre || ' ('
      || v_plan.duracion_dias || ' dias). La entidad queda activa hasta el '
      || to_char((v_res -> 'data' ->> 'fecha_vencimiento')::timestamptz, 'DD/MM/YYYY') || '.');

  perform flow._susc_notificar_whatsapp(
    v_trx.id_entidad,
    (select pf.telefono from flow.perfil pf where pf.uuid_usuario = v_owner),
    'Tu plan ' || v_plan.nombre || ' fue acreditado. Entidad activa hasta el '
      || to_char((v_res -> 'data' ->> 'fecha_vencimiento')::timestamptz, 'DD/MM/YYYY') || '.');

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id_transaccion',    v_trx.id,
      'estado',            'verificado',
      'id_entidad',        v_trx.id_entidad,
      'acreditacion',      v_res -> 'data'
    )
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_suscripcion_detalle(p_id_entidad integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
begin
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error', 'Solo el superadmin puede ver este detalle');
  end if;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'entidad', (
        select jsonb_build_object(
                 'id',          e.id,
                 'denominacion', e.denominacion,
                 'owner_uuid',  e.owner_uuid,
                 'telefono',    e.telefono,
                 'created_at',  e.created_at,
                 'activa',      flow.entidad_activa(e.id))
        from flow.entidad e where e.id = p_id_entidad),

      'estado', flow.cliente_estado_suscripcion(p_id_entidad) -> 'data',

      'suscripciones', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id',                s.id,
                 'estado',            s.estado,
                 'origen',            s.origen,
                 'plan_nombre',       p.nombre,
                 'fecha_inicio',      s.fecha_inicio,
                 'fecha_vencimiento', s.fecha_vencimiento,
                 'fecha_gracia_fin',  s.fecha_gracia_fin,
                 'notas',             s.notas,
                 'updated_at',        s.updated_at) order by s.updated_at desc)
        from flow.suscripcion s
        left join flow.suscripcion_plan p on p.id = s.id_plan
        where s.id_entidad = p_id_entidad), '[]'::jsonb),

      'pagos', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id',                  t.id,
                 'codigo_confirmacion', t.codigo_confirmacion,
                 'monto',               t.monto,
                 'moneda',              t.moneda,
                 'metodo',              t.metodo,
                 'comprobante_url',     t.comprobante_url,
                 'estado',              t.estado,
                 'reportado_por',       t.reportado_por,
                 'reportado_at',        t.reportado_at,
                 'verificado_por',      t.verificado_por,
                 'verificado_at',       t.verificado_at,
                 'observaciones',       t.observaciones,
                 'id_transaccion',      i.id_transaccion,
                 'plan_nombre',         p.nombre
               ) order by t.reportado_at desc)
        from flow.suscripcion_transaccion t
        join flow.suscripcion_intent i on i.id = t.id_intent
        left join flow.suscripcion_plan p on p.id = i.id_plan
        where t.id_entidad = p_id_entidad), '[]'::jsonb),

      'movimientos', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'tipo',        m.tipo,
                 'dias',        m.dias,
                 'fecha_desde', m.fecha_desde,
                 'fecha_hasta', m.fecha_hasta,
                 'motivo',      m.motivo,
                 'admin_uuid',  m.admin_uuid,
                 'created_at',  m.created_at) order by m.created_at desc)
        from flow.suscripcion_movimiento m
        where m.id_entidad = p_id_entidad), '[]'::jsonb),

      'notificaciones', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'canal',      n.canal,
                 'destino',    n.destino,
                 'asunto',     n.asunto,
                 'mensaje',    n.mensaje,
                 'estado',     n.estado,
                 'error',      n.error,
                 'created_at', n.created_at) order by n.created_at desc)
        from flow.suscripcion_notificacion n
        where n.id_entidad = p_id_entidad), '[]'::jsonb)
    )
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_suscripcion_inicializar(p_dias integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_uid    uuid := auth.uid();
  v_cfg    flow.suscripcion_config%rowtype;
  v_dias   integer;
  v_r      record;
  v_n      integer := 0;
begin
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error', 'Solo el superadmin puede inicializar suscripciones');
  end if;

  select c.* into v_cfg from flow.suscripcion_config c where c.id = 1;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Falta flow.suscripcion_config');
  end if;

  v_dias := coalesce(p_dias, v_cfg.trial_meses_default * 30);

  for v_r in
    select e.id
    from flow.entidad e
    where not exists (select 1 from flow.suscripcion s where s.id_entidad = e.id)
  loop
    if v_dias > 0 then
      perform flow._susc_acreditar_dias(
        v_r.id, null, v_dias, 'trial',
        'Inicializacion manual del superadmin', v_uid, null);
    else
      insert into flow.suscripcion
        (id_entidad, id_plan, estado, fecha_inicio, fecha_vencimiento,
         fecha_gracia_fin, origen, notas, created_by)
      values
        (v_r.id, null, 'sin_plan', now(), now(), now(), 'trial',
         'Inicializado en sin_plan por el superadmin', v_uid);

      insert into flow.suscripcion_movimiento
        (id_entidad, tipo, dias, motivo, admin_uuid)
      values
        (v_r.id, 'inicializacion', 0, 'Inicializado en sin_plan por el superadmin', v_uid);
    end if;

    v_n := v_n + 1;
  end loop;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('entidades_inicializadas', v_n));
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_suscripcion_listar(p_filtro text DEFAULT 'todas'::text, p_buscar text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_cfg flow.suscripcion_config%rowtype;
begin
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error', 'Solo el superadmin puede ver las suscripciones');
  end if;

  select c.* into v_cfg from flow.suscripcion_config c where c.id = 1;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Falta flow.suscripcion_config');
  end if;

  return jsonb_build_object(
    'ok', true,
    'data', coalesce((
      with base as (
        select
          e.id                as id_entidad,
          e.denominacion,
          e.owner_uuid,
          s.id                as id_suscripcion,
          s.estado            as estado_guardado,
          s.fecha_inicio,
          s.fecha_vencimiento,
          s.fecha_gracia_fin,
          s.origen,
          s.notas,
          p.codigo            as plan_codigo,
          p.nombre            as plan_nombre,
          p.precio            as plan_precio,
          p.moneda            as plan_moneda,
          flow.entidad_activa(e.id) as activa,
          coalesce(s.fecha_gracia_fin, s.fecha_vencimiento) as vigente_hasta,
          (select count(*) from flow.suscripcion_transaccion t
            where t.id_entidad = e.id and t.estado = 'reportado') as pagos_reportados,
          (select count(*) from flow.suscripcion_transaccion t
            where t.id_entidad = e.id and t.estado = 'verificado') as pagos_verificados
        from flow.entidad e
        left join lateral (
          select s2.*
          from flow.suscripcion s2
          where s2.id_entidad = e.id
          order by
            (s2.estado in ('trial','activa','en_gracia','sin_plan','suspendida')) desc,
            s2.updated_at desc,
            s2.id desc
          limit 1
        ) s on true
        left join flow.suscripcion_plan p on p.id = s.id_plan
      ),
      calc as (
        select b.*,
          case
            when b.id_suscripcion is null then 'sin_suscripcion'
            when b.estado_guardado = 'suspendida' then 'suspendida'
            when b.estado_guardado = 'sin_plan'   then 'sin_plan'
            when not b.activa then 'vencida'
            when b.fecha_vencimiento <= now()
                 and b.vigente_hasta > now() then 'en_gracia'
            when b.fecha_vencimiento <= now()
                 + make_interval(days => coalesce(v_cfg.dias_aviso_previo, 7))
              then 'por_vencer'
            else 'activa'
          end as estado_visible,
          case when b.fecha_vencimiento is null then null
               else ceil(extract(epoch from (b.fecha_vencimiento - now())) / 86400.0)::integer
          end as dias_restantes,
          case when b.vigente_hasta is null then null
               else ceil(extract(epoch from (b.vigente_hasta - now())) / 86400.0)::integer
          end as dias_gracia
        from base b
      ),
      filtrado as (
        select c.*
        from calc c
        where (p_buscar is null
               or btrim(p_buscar) = ''
               or c.denominacion ilike '%' || btrim(p_buscar) || '%')
          and case coalesce(nullif(btrim(p_filtro), ''), 'todas')
                when 'activas'        then c.estado_visible in ('activa','por_vencer','en_gracia')
                when 'por_vencer'     then c.estado_visible = 'por_vencer'
                when 'en_gracia'      then c.estado_visible = 'en_gracia'
                when 'vencidas'       then c.estado_visible = 'vencida'
                when 'sin_plan'       then c.estado_visible in ('sin_plan','sin_suscripcion')
                when 'suspendidas'    then c.estado_visible = 'suspendida'
                when 'pagos_pendientes' then c.pagos_reportados > 0
                else true
              end
      )
      select jsonb_agg(jsonb_build_object(
               'id_entidad',        f.id_entidad,
               'denominacion',      f.denominacion,
               'owner_uuid',        f.owner_uuid,
               'id_suscripcion',    f.id_suscripcion,
               'estado',            f.estado_visible,
               'estado_guardado',   f.estado_guardado,
               'activa',            f.activa,
               'origen',            f.origen,
               'plan_codigo',       f.plan_codigo,
               'plan_nombre',       f.plan_nombre,
               'plan_precio',       f.plan_precio,
               'plan_moneda',       f.plan_moneda,
               'fecha_inicio',      f.fecha_inicio,
               'fecha_vencimiento', f.fecha_vencimiento,
               'fecha_gracia_fin',  f.fecha_gracia_fin,
               'dias_restantes',    f.dias_restantes,
               'dias_gracia',       f.dias_gracia,
               'pagos_reportados',  f.pagos_reportados,
               'pagos_verificados', f.pagos_verificados,
               'notas',             f.notas
             )
             order by
               -- Primero lo que exige accion: pagos sin verificar, luego lo vencido,
               -- luego lo que vence antes.
               f.pagos_reportados desc,
               (f.estado_visible = 'vencida') desc,
               f.fecha_vencimiento asc nulls last,
               f.denominacion asc)
      from filtrado f
    ), '[]'::jsonb)
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_suscripcion_reactivar(p_id_entidad integer, p_motivo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_uid   uuid := auth.uid();
  v_s     flow.suscripcion%rowtype;
  v_gracia timestamptz;
  v_activa boolean;
begin
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error', 'Solo el superadmin puede reactivar entidades');
  end if;

  select s.* into v_s
  from flow.suscripcion s
  where s.id_entidad = p_id_entidad
    and s.estado in ('trial','activa','en_gracia','sin_plan','suspendida')
  limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'La entidad no tiene una suscripcion viva que reactivar');
  end if;

  -- Reactivar devuelve el estado segun las FECHAS: si ya vencio, no se puede
  -- "reactivar" sin acreditar tiempo. Se dice claro en vez de mentir con el estado.
  if coalesce(v_s.fecha_gracia_fin, v_s.fecha_vencimiento) <= now() then
    return jsonb_build_object('ok', false,
      'error', 'La suscripcion ya vencio: acredita dias o un plan en vez de reactivar');
  end if;

  v_activa := now() < v_s.fecha_vencimiento;

  update flow.suscripcion s
     set estado = case when v_activa then 'activa' else 'en_gracia' end,
         notas  = coalesce(nullif(btrim(coalesce(p_motivo, '')), ''), s.notas)
   where s.id = v_s.id;

  insert into flow.suscripcion_movimiento
    (id_entidad, id_suscripcion, tipo, dias, motivo, admin_uuid)
  values
    (p_id_entidad, v_s.id, 'reactivacion', 0,
     coalesce(nullif(btrim(coalesce(p_motivo, '')), ''), 'Reactivada por el superadmin'), v_uid);

  return jsonb_build_object('ok', true, 'data', jsonb_build_object(
    'id_entidad', p_id_entidad,
    'estado', case when v_activa then 'activa' else 'en_gracia' end
  ));
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_suscripcion_rechazar_pago(p_id_transaccion bigint, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_uid   uuid := auth.uid();
  v_trx   flow.suscripcion_transaccion%rowtype;
  v_owner uuid;
begin
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error', 'Solo el superadmin puede rechazar pagos');
  end if;

  if p_motivo is null or btrim(p_motivo) = '' then
    return jsonb_build_object('ok', false, 'error', 'Indica el motivo del rechazo');
  end if;

  select t.* into v_trx from flow.suscripcion_transaccion t where t.id = p_id_transaccion;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'El pago no existe');
  end if;

  if v_trx.estado <> 'reportado' then
    return jsonb_build_object('ok', false,
      'error', 'Ese pago ya fue procesado (estado: ' || v_trx.estado || ')');
  end if;

  update flow.suscripcion_transaccion t
     set estado         = 'rechazado',
         verificado_por = v_uid,
         verificado_at  = now(),
         observaciones  = btrim(p_motivo)
   where t.id = v_trx.id;

  -- El intent vuelve a 'rechazado': el cliente puede generar uno nuevo.
  update flow.suscripcion_intent set estado = 'rechazado' where id = v_trx.id_intent;

  select e.owner_uuid into v_owner from flow.entidad e where e.id = v_trx.id_entidad;

  perform flow._susc_notificar_inapp(
    v_trx.id_entidad, v_owner,
    'Pago rechazado',
    'No pudimos verificar tu pago: ' || btrim(p_motivo) || '. Puedes generar un nuevo intento de pago.');

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object('id_transaccion', v_trx.id, 'estado', 'rechazado')
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.admin_suscripcion_suspender(p_id_entidad integer, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_id  bigint;
begin
  if not public.fn_is_superadmin_full_access() then
    return jsonb_build_object('ok', false, 'error', 'Solo el superadmin puede suspender entidades');
  end if;

  if p_motivo is null or btrim(p_motivo) = '' then
    return jsonb_build_object('ok', false, 'error', 'Indica el motivo de la suspension');
  end if;

  update flow.suscripcion s
     set estado = 'suspendida',
         notas  = btrim(p_motivo)
   where s.id_entidad = p_id_entidad
     and s.estado in ('trial','activa','en_gracia','sin_plan')
  returning s.id into v_id;

  if v_id is null then
    return jsonb_build_object('ok', false, 'error', 'La entidad no tiene una suscripcion viva que suspender');
  end if;

  insert into flow.suscripcion_movimiento
    (id_entidad, id_suscripcion, tipo, dias, motivo, admin_uuid)
  values
    (p_id_entidad, v_id, 'suspension', 0, btrim(p_motivo), v_uid);

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('id_entidad', p_id_entidad, 'estado', 'suspendida'));
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.bot_procesar_plan(p_id_plan bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_ls       integer;
  v_fecha    timestamp with time zone;
  v_cupo     integer;
  v_estado   integer;
  v_movidos  integer := 0;
  v_nombre_servicio text;
  v_nombre_local    text;
  v_saludo          text;
  v_id_servicio     integer;
begin
  -- Lee el plan y BLOQUEA esa fila (evita doble procesamiento del mismo plan)
  select ps.id_local_servicio, ps.fecha, (ps.cantidad - ps.agendados)
    into v_ls, v_fecha, v_cupo
  from flow.plan_servicios ps
  where ps.id = p_id_plan
  for update;

  if not found then
    insert into flow.bot_log (id_plan, resultado, movidos, mensaje)
    values (p_id_plan, 'error', 0, 'plan no encontrado');
    return jsonb_build_object('ok', false, 'error', 'plan no encontrado');
  end if;

  -- Sin cupo o sin servicio asignado -> nada que hacer
  if v_ls is null or v_cupo is null or v_cupo <= 0 then
    insert into flow.bot_log (id_plan, id_local_servicio, resultado, movidos, mensaje, detalle)
    values (p_id_plan, v_ls, 'sin_cupo', 0, 'sin cupo',
            jsonb_build_object('cupo', v_cupo));
    return jsonb_build_object('ok', true, 'movidos', 0, 'motivo', 'sin cupo');
  end if;

  -- Serializa con entrar/salir de ESTE servicio (mismo advisory lock)
  perform pg_advisory_xact_lock(hashtext('flow.sala_espera'), v_ls);

  -- Estado destino para las agendas creadas
  select id into v_estado from flow.nom_estado_agenda where nombre = 'Reservado' limit 1;
  if v_estado is null then
    insert into flow.bot_log (id_plan, id_local_servicio, resultado, movidos, mensaje)
    values (p_id_plan, v_ls, 'error', 0, 'falta el estado Reservado (correr migracion 03)');
    return jsonb_build_object('ok', false, 'error', 'falta el estado Reservado (correr migracion 03)');
  end if;

  -- Datos para las notificaciones de "reservacion confirmada":
  -- nombres legibles del servicio/local y saludo segun la hora del servidor.
  select s.nombre, l.nombre, ls.id_servicio
    into v_nombre_servicio, v_nombre_local, v_id_servicio
  from flow.local_servicio ls
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  join flow.app_dat_locales   l on l.id = ls.id_local
  where ls.id = v_ls;

  v_saludo := case
    when extract(hour from current_timestamp) between 5 and 11 then 'Buenos días'
    when extract(hour from current_timestamp) between 12 and 18 then 'Buenas tardes'
    else 'Buenas noches'
  end;

  -- Reparto en un solo paso (set-based). ORDEN IMPORTANTE para no sacar a nadie
  -- de la cola sin darle reserva:
  --   1) candidatos: hasta v_cupo elegibles, FIFO, bloqueados (skip locked).
  --   2) insertados: se CREA la agenda primero (una por candidato).
  --   3) borrados:   se elimina de sala_espera SOLO a quienes quedaron en
  --                  'insertados' (los que de verdad recibieron agenda).
  -- Como 'borrados' depende del RETURNING de 'insertados', Postgres garantiza
  -- que nunca se borra a un candidato que no haya sido reservado. Si en el
  -- futuro la insercion se vuelve condicional, los no reservados permanecen en
  -- la cola y podran recibir reserva en una corrida posterior.
  -- El CTE 'notificados' crea una notificacion por cada reserva confirmada;
  -- como es data-modifying, Postgres lo ejecuta siempre aunque no se lea.
  with candidatos as (
    select se.id, se.uuid_usuario, se.datos_adicionales, se.reservado_por
    from flow.sala_espera se
    where se.id_local_servicio = v_ls
      -- Compara por DIA en hora local (America/Havana). Antes era
      -- 'se.fecha_regla <= v_fecha', que casteaba el timestamp naive de
      -- fecha_regla usando la tz de la conexion (cron/service_role suele ser
      -- UTC, sesion interactiva America/Havana): el limite de dia se desplazaba
      -- y se barrian candidatos del dia equivocado, borrandolos de la cola.
      -- Solo califican los cuya fecha pedida (dia) sea <= al dia del plan.
      and se.fecha_regla::date <= (v_fecha at time zone 'America/Havana')::date
    order by se.numero_cola
    limit v_cupo
    for update skip locked
  ),
  insertados as (
    insert into flow.agenda
      (uuid_usuario, id_local_servicio, id_estado, fecha_hora_reserva,
       cantidad, datos_adicionales, reservado_por, precio_total, moneda)
    select c.uuid_usuario, v_ls, v_estado, v_fecha,
           1, c.datos_adicionales, c.reservado_por,
           case when cp.precio_total is null then null
                when (pr ->> 'ok') = 'true' then (pr ->> 'precio_total')::numeric
                else cp.precio_total end,
           case when cp.precio_total is null then cp.moneda
                when (pr ->> 'ok') = 'true' then (pr ->> 'moneda')::varchar
                else cp.moneda end
    from candidatos c
    cross join lateral flow.calcular_precio_reserva(
      v_id_servicio,
      coalesce(c.datos_adicionales, '{}'::jsonb),
      null,
      1
    ) cp
    cross join lateral flow._aplicar_promocion(
      v_ls, v_id_servicio, cp.precio_total, cp.moneda, cp.precio_unit, true
    ) pr
    returning uuid_usuario, id, fecha_hora_reserva
  ),
  borrados as (
    delete from flow.sala_espera se
    using candidatos c
    where se.id = c.id
      and se.uuid_usuario in (select uuid_usuario from insertados)
    returning se.id
  ),
  notificados as (
    insert into flow.notificaciones
      (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
    select
      i.uuid_usuario,
      'reserva',
      'Reservación confirmada',
      v_saludo || ', '
        || coalesce(nullif(trim(p.nombre || ' ' || p.apellidos), ''), 'estimado cliente')
        || ', se ha realizado satisfactoriamente su reservación para el local "'
        || coalesce(v_nombre_local, 'local') || '" el servicio "'
        || coalesce(v_nombre_servicio, 'servicio') || '" para la fecha '
        || to_char(i.fecha_hora_reserva, 'DD/MM/YYYY') || '.',
      v_ls,
      i.id,
      jsonb_build_object(
        'fecha',    i.fecha_hora_reserva,
        'servicio', v_nombre_servicio,
        'local',    v_nombre_local
      )
    from insertados i
    left join flow.perfil p on p.uuid_usuario = i.uuid_usuario
    returning 1
  )
  select count(*) into v_movidos from insertados;

  if v_movidos > 0 then
    -- Actualiza el contador del plan
    update flow.plan_servicios
       set agendados = agendados + v_movidos
     where id = p_id_plan;

    -- Registra "por donde se quedo repartiendo" en flow.ultimo_numero.
    -- Como la cola es compacta (se renumera 1..N tras agendar), ultimo_otorgado
    -- se lleva como contador ACUMULADO del total repartido en este servicio:
    -- crece de forma monotonica corrida tras corrida.
    -- UPSERT por id_local_servicio (columna UNIQUE): suma si ya existe, inserta si no.
    insert into flow.ultimo_numero (id_local_servicio, ultimo_otorgado, updated_at)
    values (v_ls, v_movidos, current_timestamp)
    on conflict (id_local_servicio) do update
      set ultimo_otorgado = flow.ultimo_numero.ultimo_otorgado + excluded.ultimo_otorgado,
          updated_at      = current_timestamp;

    -- Recompacta la cola del servicio: renumera 1..N por orden de llegada,
    -- asi no quedan huecos tras sacar a los del frente.
    with reord as (
      select se.id, row_number() over (order by se.numero_cola) as rn
      from flow.sala_espera se
      where se.id_local_servicio = v_ls
    )
    update flow.sala_espera se
       set numero_cola = r.rn
      from reord r
     where se.id = r.id
       and se.numero_cola <> r.rn;   -- solo toca filas que realmente cambian

    -- Si la cola quedo VACIA tras despachar a todos, reinicia los contadores
    -- de flow.ultimo_numero: es una cola "nueva" porque ya no queda nadie
    -- esperando. ultimo_otorgado y ultimo_en_anotarse vuelven a 0 para que
    -- la proxima persona que se anote empiece a numerar desde cero otra vez.
    if not exists (
      select 1 from flow.sala_espera se where se.id_local_servicio = v_ls
    ) then
      update flow.ultimo_numero
         set ultimo_otorgado    = 0,
             ultimo_en_anotarse = 0,
             updated_at         = current_timestamp
       where id_local_servicio = v_ls;
    end if;
  end if;

  -- Log de la corrida: 'ok' si repartio, 'sin_movimiento' si no habia candidatos.
  insert into flow.bot_log (id_plan, id_local_servicio, resultado, movidos, mensaje, detalle)
  values (
    p_id_plan, v_ls,
    case when v_movidos > 0 then 'ok' else 'sin_movimiento' end,
    v_movidos,
    case when v_movidos > 0
         then 'repartio ' || v_movidos || ' agenda(s)'
         else 'sin candidatos en cola' end,
    jsonb_build_object('cupo', v_cupo, 'fecha_plan', v_fecha)
  );

  return jsonb_build_object(
    'ok', true,
    'id_plan', p_id_plan,
    'id_local_servicio', v_ls,
    'movidos', v_movidos
  );

exception
  when others then
    -- Cualquier fallo inesperado: el rollback al savepoint implicito de este
    -- bloque revierte el reparto, pero este INSERT (posterior) si persiste.
    insert into flow.bot_log (id_plan, id_local_servicio, resultado, movidos, mensaje, detalle)
    values (p_id_plan, v_ls, 'error', 0, sqlerrm,
            jsonb_build_object('sqlstate', sqlstate));
    return jsonb_build_object(
      'ok', false,
      'id_plan', p_id_plan,
      'error', sqlerrm,
      'sqlstate', sqlstate
    );
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.bot_procesar_recurso_dia(p_id_turno integer, p_fecha date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_ls              integer;
  v_id_servicio     integer;
  v_estado          integer;
  v_cupo            integer;
  v_n_tramos        integer;
  v_n_plan          integer;
  v_movidos         integer := 0;
  v_fecha_ts        timestamp without time zone;
  v_nombre_servicio text;
  v_nombre_local    text;
  v_saludo          text;
begin
  -- Recurso/LS del turno.
  select r.id_local_servicio into v_ls
  from flow.turno t
  join flow.recurso r on r.id = t.id_recurso and r.activo
  where t.id = p_id_turno and t.activo;

  if v_ls is null then
    return jsonb_build_object('ok', true, 'movidos', 0, 'motivo', 'turno inactivo');
  end if;

  perform pg_advisory_xact_lock(hashtext('flow.sala_espera'), v_ls);

  select id into v_estado from flow.nom_estado_agenda where nombre = 'Reservado' limit 1;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'error', 'falta el estado Reservado');
  end if;

  -- Cuantos tramos consume el turno.
  select count(*) into v_n_tramos from flow.turno_tramo tt where tt.id_turno = p_id_turno;
  if coalesce(v_n_tramos, 0) = 0 then
    return jsonb_build_object('ok', true, 'movidos', 0, 'motivo', 'turno sin tramos');
  end if;

  -- Cupo del turno ese dia = min(disponible) sobre sus tramos; bloquea plan_tramo.
  create temporary table if not exists _tmp_bot_pt (id bigint) on commit drop;
  delete from _tmp_bot_pt where id is not null;

  insert into _tmp_bot_pt (id)
  select pt.id
  from flow.turno_tramo tt
  join flow.tramo tr      on tr.id = tt.id_tramo and tr.activo
  join flow.plan_tramo pt on pt.id_tramo = tr.id
  where tt.id_turno = p_id_turno
    and (pt.fecha at time zone 'America/Havana')::date = p_fecha
  for update of pt;

  select count(*), coalesce(min(pt.cantidad - pt.agendados), 0)
    into v_n_plan, v_cupo
  from flow.plan_tramo pt
  join _tmp_bot_pt tmp on tmp.id = pt.id;

  -- Todos los tramos del turno deben tener plan ese dia y quedar cupo.
  if coalesce(v_n_plan, 0) < v_n_tramos or v_cupo <= 0 then
    return jsonb_build_object('ok', true, 'movidos', 0, 'motivo', 'sin cupo');
  end if;

  v_fecha_ts := (make_timestamp(extract(year from p_fecha)::int,
                                extract(month from p_fecha)::int,
                                extract(day from p_fecha)::int, 12, 0, 0));

  select s.nombre, l.nombre, ls.id_servicio
    into v_nombre_servicio, v_nombre_local, v_id_servicio
  from flow.local_servicio ls
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  join flow.app_dat_locales   l on l.id = ls.id_local
  where ls.id = v_ls;

  v_saludo := case
    when extract(hour from current_timestamp) between 5 and 11 then 'Buenos dias'
    when extract(hour from current_timestamp) between 12 and 18 then 'Buenas tardes'
    else 'Buenas noches'
  end;

  -- Reparto set-based: N candidatos FIFO de la cola de ESTE turno (N=cupo).
  -- Cada turno consume 1 plaza de cada tramo, por eso caben exactamente v_cupo.
  with candidatos as (
    select se.id, se.uuid_usuario, se.datos_adicionales, se.reservado_por
    from flow.sala_espera se
    where se.id_local_servicio = v_ls
      and (
        se.id_turno = p_id_turno
        or (
          se.id_turno is null
          and not exists (
            select 1
            from flow.turno t0
            join flow.recurso r0 on r0.id = t0.id_recurso and r0.activo
            join flow.turno_tramo tt0 on tt0.id_turno = t0.id
            join flow.tramo tr0 on tr0.id = tt0.id_tramo and tr0.activo
            join flow.plan_tramo pt0 on pt0.id_tramo = tr0.id
            where t0.activo
              and r0.id_local_servicio = v_ls
              and (t0.orden, t0.id) < (
                select t1.orden, t1.id
                from flow.turno t1
                where t1.id = p_id_turno
              )
              and (pt0.fecha at time zone 'America/Havana')::date = p_fecha
            group by t0.id
            having count(pt0.id) = (
              select count(*)
              from flow.turno_tramo tt2
              where tt2.id_turno = t0.id
            )
              and min(pt0.cantidad - pt0.agendados) > 0
          )
        )
      )
      and se.fecha_regla::date <= p_fecha
    order by se.numero_cola
    limit v_cupo
    for update skip locked
  ),
  insertados as (
    insert into flow.agenda
      (uuid_usuario, id_local_servicio, id_estado, fecha_hora_reserva,
       cantidad, datos_adicionales, reservado_por, precio_total, moneda, id_turno)
    select c.uuid_usuario, v_ls, v_estado, v_fecha_ts,
           1, c.datos_adicionales, c.reservado_por,
           case when cp.precio_total is null then null
                when (pr ->> 'ok') = 'true' then (pr ->> 'precio_total')::numeric
                else cp.precio_total end,
           case when cp.precio_total is null then cp.moneda
                when (pr ->> 'ok') = 'true' then (pr ->> 'moneda')::varchar
                else cp.moneda end,
           p_id_turno
    from candidatos c
    cross join lateral flow.calcular_precio_turno(
      v_id_servicio, p_id_turno, coalesce(c.datos_adicionales, '{}'::jsonb), null, 1) cp
    cross join lateral flow._aplicar_promocion(
      v_ls, v_id_servicio, cp.precio_total, cp.moneda, cp.precio_unit, true) pr
    returning uuid_usuario, id, fecha_hora_reserva
  ),
  borrados as (
    delete from flow.sala_espera se
    using candidatos c
    where se.id = c.id
      and se.uuid_usuario in (select uuid_usuario from insertados)
    returning se.id
  ),
  notificados as (
    insert into flow.notificaciones
      (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
    select
      i.uuid_usuario, 'reserva', 'Reservacion confirmada',
      v_saludo || ', '
        || coalesce(nullif(trim(p.nombre || ' ' || p.apellidos), ''), 'estimado cliente')
        || ', se ha realizado satisfactoriamente su reservacion para el local "'
        || coalesce(v_nombre_local, 'local') || '" el servicio "'
        || coalesce(v_nombre_servicio, 'servicio') || '" para la fecha '
        || to_char(i.fecha_hora_reserva, 'DD/MM/YYYY') || '.',
      v_ls, i.id,
      jsonb_build_object('fecha', i.fecha_hora_reserva, 'servicio', v_nombre_servicio,
        'local', v_nombre_local, 'id_turno', p_id_turno)
    from insertados i
    left join flow.perfil p on p.uuid_usuario = i.uuid_usuario
    returning 1
  )
  select count(*) into v_movidos from insertados;

  if v_movidos > 0 then
    -- Descontar el cupo en cada tramo del turno.
    update flow.plan_tramo pt
       set agendados = pt.agendados + v_movidos
    from _tmp_bot_pt tmp
    where pt.id = tmp.id;

    -- Recompactar la cola del LS (numeracion global 1..N por orden de llegada).
    with reord as (
      select se.id, row_number() over (order by se.numero_cola) as rn
      from flow.sala_espera se
      where se.id_local_servicio = v_ls
    )
    update flow.sala_espera se
       set numero_cola = r.rn
      from reord r
     where se.id = r.id and se.numero_cola <> r.rn;
  end if;

  insert into flow.bot_log (id_plan, id_local_servicio, resultado, movidos, mensaje, detalle)
  values (null, v_ls,
    case when v_movidos > 0 then 'ok' else 'sin_movimiento' end,
    v_movidos,
    case when v_movidos > 0 then 'repartio ' || v_movidos || ' agenda(s) turno'
         else 'sin candidatos en cola de turno' end,
    jsonb_build_object('id_turno', p_id_turno, 'fecha', p_fecha, 'cupo', v_cupo));

  return jsonb_build_object('ok', true, 'id_turno', p_id_turno,
    'id_local_servicio', v_ls, 'movidos', v_movidos);
exception
  when others then
    insert into flow.bot_log (id_plan, id_local_servicio, resultado, movidos, mensaje, detalle)
    values (null, v_ls, 'error', 0, sqlerrm,
            jsonb_build_object('id_turno', p_id_turno, 'sqlstate', sqlstate));
    return jsonb_build_object('ok', false, 'id_turno', p_id_turno,
      'error', sqlerrm, 'sqlstate', sqlstate);
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.calcular_precio_con_reglas(p_id_servicio integer, p_datos jsonb, p_moneda text DEFAULT NULL::text, p_cantidad integer DEFAULT 1, p_base_unit numeric DEFAULT NULL::numeric)
 RETURNS TABLE(precio_total numeric, moneda character varying, precio_unit numeric, origen text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_cfg         jsonb;
  v_moneda      text;
  v_monedas     text[];
  v_default     text;
  v_unit        numeric;
  v_regla       jsonb;
  v_clave       text;
  v_valor       text;
  v_precios     jsonb;
  v_precios_opc jsonb;
  v_cant        integer;
begin
  v_cant := greatest(coalesce(p_cantidad, 1), 1);

  select coalesce(s.config_precio, '{}'::jsonb)
    into v_cfg
  from flow.app_dat_servicios s
  where s.id = p_id_servicio;

  -- Sin configuracion en el servicio y sin base del turno: 0, igual que antes
  -- (`config_precio = '{}'` es el caso real de los servicios sin precio).
  if p_base_unit is null and (v_cfg is null or v_cfg = '{}'::jsonb) then
    return query
    select 0::numeric,
           coalesce(nullif(trim(p_moneda), ''), 'USD')::varchar,
           0::numeric,
           'sin_config'::text;
    return;
  end if;

  v_cfg := coalesce(v_cfg, '{}'::jsonb);
  v_default := coalesce(v_cfg->>'moneda_default', 'USD');
  select coalesce(array_agg(x::text), array[v_default])
    into v_monedas
  from jsonb_array_elements_text(
    coalesce(v_cfg->'monedas', jsonb_build_array(v_default))) x;

  v_moneda := coalesce(nullif(trim(p_moneda), ''), v_default);
  if not (v_moneda = any (v_monedas)) then
    v_moneda := v_default;
  end if;

  -- Reglas en orden: gana la primera coincidente CON precio resoluble.
  for v_regla in
    select * from jsonb_array_elements(coalesce(v_cfg->'reglas', '[]'::jsonb))
  loop
    v_clave := v_regla->>'si_clave';
    if v_clave is null or v_clave = '' then
      continue;
    end if;
    v_valor := coalesce(p_datos->>v_clave, '');
    if v_valor = '' then
      continue;
    end if;

    v_precios_opc := coalesce(v_regla->'precios_opcion', '{}'::jsonb);

    -- Formato anterior (opciones + precios compartidos): migracion en lectura.
    if v_precios_opc = '{}'::jsonb
       and v_regla ? 'opciones'
       and jsonb_typeof(v_regla->'opciones') = 'array'
       and exists (
         select 1 from jsonb_array_elements_text(v_regla->'opciones') o
         where o = v_valor
       ) then
      v_precios := coalesce(v_regla->'precios', '{}'::jsonb);
    else
      v_precios := v_precios_opc->v_valor;
    end if;

    if v_precios is null
       or v_precios = 'null'::jsonb
       or v_precios = '{}'::jsonb then
      continue;
    end if;

    -- Sin precio para la moneda elegida ni para la moneda por defecto: la
    -- regla se IGNORA y se sigue buscando (nunca 0 por este motivo).
    v_unit := coalesce(
      nullif(v_precios->>v_moneda, '')::numeric,
      nullif(v_precios->>v_default, '')::numeric
    );
    if v_unit is null then
      continue;
    end if;

    return query
    select (v_unit * v_cant)::numeric, v_moneda::varchar, v_unit::numeric, 'regla'::text;
    return;
  end loop;

  -- Base: precio propio del turno si vino.
  if p_base_unit is not null then
    return query
    select (p_base_unit * v_cant)::numeric,
           v_moneda::varchar,
           p_base_unit::numeric,
           'turno'::text;
    return;
  end if;

  -- Base: precios_base del servicio (moneda elegida y respaldo al default).
  v_precios := coalesce(v_cfg->'precios_base', '{}'::jsonb);
  v_unit := coalesce(
    nullif(v_precios->>v_moneda, '')::numeric,
    nullif(v_precios->>v_default, '')::numeric
  );

  if v_unit is null then
    return query
    select 0::numeric, v_moneda::varchar, 0::numeric, 'sin_config'::text;
    return;
  end if;

  return query
  select (v_unit * v_cant)::numeric, v_moneda::varchar, v_unit::numeric, 'base'::text;
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.calcular_precio_reserva(p_id_servicio integer, p_datos jsonb, p_moneda text DEFAULT NULL::text, p_cantidad integer DEFAULT 1)
 RETURNS TABLE(precio_total numeric, moneda character varying, precio_unit numeric)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
begin
  return query
  select h.precio_total, h.moneda, h.precio_unit
  from flow.calcular_precio_con_reglas(
    p_id_servicio,
    p_datos,
    p_moneda,
    greatest(coalesce(p_cantidad, 1), 1),
    null::numeric
  ) h;
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.calcular_precio_turno(p_id_servicio integer, p_id_turno integer, p_datos jsonb, p_moneda text DEFAULT NULL::text, p_cantidad integer DEFAULT 1)
 RETURNS TABLE(precio_total numeric, moneda character varying, precio_unit numeric)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_precios jsonb;
  v_moneda  text;
  v_default text;
  v_unit    numeric;
  v_cant    integer := greatest(coalesce(p_cantidad, 1), 1);
begin
  select t.precios,
         coalesce(s.config_precio->>'moneda_default', 'USD')
    into v_precios, v_default
  from flow.turno t
  join flow.recurso r on r.id = t.id_recurso
  join flow.local_servicio ls on ls.id = r.id_local_servicio
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  where t.id = p_id_turno and s.id = p_id_servicio;

  v_default := coalesce(v_default, 'USD');
  v_moneda := coalesce(nullif(trim(p_moneda), ''), v_default);

  -- Precio unitario del turno, con respaldo a la moneda por defecto. Si no hay
  -- precio propio (`precios = '{}'`), `v_unit` queda NULL y la base la pone el
  -- `precios_base` del servicio dentro del helper.
  if coalesce(v_precios, '{}'::jsonb) <> '{}'::jsonb then
    v_unit := coalesce(
      nullif(v_precios->>v_moneda, '')::numeric,
      nullif(v_precios->>v_default, '')::numeric
    );
  end if;

  -- El helper evalua las reglas por dato adicional sobre esa base.
  return query
  select h.precio_total, h.moneda, h.precio_unit
  from flow.calcular_precio_con_reglas(
    p_id_servicio, p_datos, v_moneda, v_cant, v_unit
  ) h;
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.campanas_activas()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
  select coalesce(
    jsonb_agg(to_jsonb(t) order by t.prioridad desc, t.id asc),
    '[]'::jsonb
  )
  from (
    select
      c.id,
      c.titulo,
      c.subtitulo,
      c.descripcion,
      c.id_local_servicio,
      c.id_entidad,
      c.color_inicio,
      c.color_fin,
      c.icono,
      c.image_url,
      c.prioridad,
      c.hasta,
      -- Nombres resueltos para pintar el badge sin otra consulta.
      l.nombre      as local,
      ls.id         as id_local_servicio_real,
      s.nombre      as servicio,
      en.denominacion as entidad,
      -- [49] Datos del establecimiento para la tarjeta y la vista de marketing.
      l.id              as id_local,
      l.foto            as local_foto,
      l.descripcion     as local_descripcion,
      l.direccion       as local_direccion,
      l.provincia       as local_provincia,
      l.pais            as local_pais,
      l.horario_atencion as local_horario_atencion,
      l.horario_detalle  as local_horario_detalle,
      l.coordenadas      as local_coordenadas,
      l.activo           as local_activo,
      -- La campana puede ser de entidad: entonces no hay local.
      coalesce(l.id_entidad, c.id_entidad) as id_entidad_real,
      en.telefono       as entidad_telefono,
      en.direccion      as entidad_direccion
    from flow.campana c
    left join flow.local_servicio   ls on ls.id = c.id_local_servicio
    left join flow.app_dat_locales  l  on l.id  = ls.id_local
    left join flow.app_dat_servicios s on s.id  = ls.id_servicio
    -- [56] Hace falta la hoja del servicio para poder compararla con lo oculto.
    left join flow.nom_tipo_actividad_servicio ta on ta.id = s.id_tipo_actividad
    left join flow.entidad          en on en.id = coalesce(l.id_entidad, c.id_entidad)
    where c.activo
      and (c.desde is null or (now() at time zone 'America/Havana') >= c.desde)
      and (c.hasta is null or (now() at time zone 'America/Havana') <  c.hasta)
      -- [56] Una campana es una forma mas de enseñar un servicio: si la entidad
      -- oculto su categoria (o su categoria padre), la campana tampoco sale.
      and not exists (
        select 1
        from flow.entidad_categoria_oculta o
        where o.id_entidad = l.id_entidad
          and (
            o.id_tipo_actividad = ta.id
            or o.id_tipo_actividad = ta.id_padre
          )
      )
  ) t;
$function$
;

CREATE OR REPLACE FUNCTION flow.cliente_crear_intent_suscripcion(p_id_entidad integer, p_id_plan bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_uid    uuid := auth.uid();
  v_cfg    flow.suscripcion_config%rowtype;
  v_plan   flow.suscripcion_plan%rowtype;
  v_monto  numeric(12,2);
  v_moneda text;
  v_importe_txt text;
  v_id_trx text;
  v_url_intent text;
  v_url_http   text;
  v_expira timestamptz;
  v_id     bigint;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Sesion requerida');
  end if;

  if not flow._susc_caller_ve_entidad(p_id_entidad) then
    return jsonb_build_object('ok', false,
      'error', 'Solo el dueno o un administrador de la entidad puede pagar su suscripcion');
  end if;

  select c.* into v_cfg from flow.suscripcion_config c where c.id = 1;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Falta la configuracion de suscripciones');
  end if;

  select p.* into v_plan
  from flow.suscripcion_plan p
  where p.id = p_id_plan and p.activo;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'El plan no existe o esta inactivo');
  end if;

  v_monto  := v_plan.precio;
  v_moneda := coalesce(nullif(btrim(v_plan.moneda), ''), v_cfg.moneda_default, 'CUP');

  -- Transfermovil espera 1500, no 1500.00. Si el precio tiene centavos se envian.
  v_importe_txt := case
                     when v_monto = trunc(v_monto) then trunc(v_monto)::bigint::text
                     else to_char(v_monto, 'FM9999999990.00')
                   end;

  -- Referencia interna UNICA por intent. NO viaja en el link: es un bug de la
  -- app de Transfermovil, que trata el id_transaccion como estatico
  -- ("ESTATICO") aunque se mande uno unico (en carnavalAPP se genero un txId
  -- por pago y se acabo comentando: validacionform_widget.dart:530). El link
  -- lleva el literal ESTATICO; esta referencia queda para que SOPORTE ubique
  -- el intento en el panel y para auditar.
  v_id_trx := 'FLW-' || p_id_entidad || '-' || to_char(now(), 'YYYYMMDDHH24MISS') || '-'
              || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));

  v_expira := now() + make_interval(hours => coalesce(v_cfg.intent_horas_vigencia, 24));

  v_url_intent := replace(replace(replace(replace(replace(
                    v_cfg.transfermovil_intent_template,
                    '$id_transaccion',   'ESTATICO'),
                    '$importe',          v_importe_txt),
                    '$moneda',           v_moneda),
                    '$numero_proveedor', v_cfg.transfermovil_numero_proveedor),
                    '$titulo',           v_cfg.transfermovil_titulo);

  v_url_http := replace(replace(replace(replace(replace(
                    v_cfg.transfermovil_url_template,
                    '$id_transaccion',   'ESTATICO'),
                    '$importe',          v_importe_txt),
                    '$moneda',           v_moneda),
                    '$numero_proveedor', v_cfg.transfermovil_numero_proveedor),
                    '$titulo',           v_cfg.transfermovil_titulo);

  insert into flow.suscripcion_intent
    (id_entidad, id_plan, uuid_usuario, monto, moneda, id_transaccion,
     numero_proveedor, url_intent, url_http, estado, expira_at)
  values
    (p_id_entidad, v_plan.id, v_uid, v_monto, v_moneda, v_id_trx,
     v_cfg.transfermovil_numero_proveedor, v_url_intent, v_url_http, 'creado', v_expira)
  returning id into v_id;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id',                v_id,
      'id_entidad',        p_id_entidad,
      'id_plan',           v_plan.id,
      'plan_nombre',       v_plan.nombre,
      'duracion_dias',     v_plan.duracion_dias,
      'monto',             v_monto,
      'moneda',            v_moneda,
      'importe',           v_importe_txt,
      'id_transaccion',    v_id_trx,
      'numero_proveedor',  v_cfg.transfermovil_numero_proveedor,
      'titulo',            v_cfg.transfermovil_titulo,
      'url_intent',        v_url_intent,
      'url_http',          v_url_http,
      'expira_at',         v_expira,
      'soporte_whatsapp',  v_cfg.soporte_whatsapp,
      'modo_prueba',       coalesce(v_cfg.modo_prueba, false)
    )
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.cliente_entrar_sala_espera_cola(p_uuid_usuario uuid, p_id_local_servicio integer, p_fecha_regla timestamp without time zone DEFAULT NULL::timestamp without time zone, p_datos_adicionales jsonb DEFAULT NULL::jsonb, p_para_tercero boolean DEFAULT false, p_t_nombre text DEFAULT NULL::text, p_t_apellidos text DEFAULT NULL::text, p_t_ci text DEFAULT NULL::text, p_t_telefono text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_numero  integer;
  v_id      integer;
  v_fecha   timestamp without time zone;
  v_created timestamp without time zone;
  v_recientes integer;
  v_nombre_servicio text;
  v_nombre_local    text;
  v_titular uuid;   -- a nombre de quien queda la entrada en cola
  -- Antifraude: no mas de N entradas (a cualquier cola) por ventana de tiempo
  c_flood_ventana constant interval := interval '1 minute';
  c_flood_max     constant integer  := 5;
begin
  -- Validacion de obligatorios
  if p_uuid_usuario is null or p_id_local_servicio is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'uuid_usuario e id_local_servicio son obligatorios'
    );
  end if;

  -- Serializa solo las operaciones de ESTE servicio (se libera al commit/rollback)
  perform pg_advisory_xact_lock(hashtext('flow.sala_espera'), p_id_local_servicio);

  -- Validar que el local_servicio existe (evita error feo de FK)
  if not exists (select 1 from flow.local_servicio ls where ls.id = p_id_local_servicio) then
    insert into flow.sala_espera_fraude (uuid_usuario, id_local_servicio, motivo, detalle)
    values (p_uuid_usuario, p_id_local_servicio, 'local_servicio_inexistente', null);
    return jsonb_build_object('ok', false, 'error', 'El id_local_servicio no existe');
  end if;

  -- Resolver el titular de la entrada: uno mismo o un tercero.
  if coalesce(p_para_tercero, false) then
    if not exists (
      select 1 from flow.local_servicio ls
      join flow.app_dat_servicios s on s.id = ls.id_servicio
      where ls.id = p_id_local_servicio and s.permite_tercero = true
    ) then
      return jsonb_build_object('ok', false, 'error', 'Este servicio no permite reservar para terceros');
    end if;
    v_titular := flow._resolver_perfil_tercero(p_t_nombre, p_t_apellidos, p_t_ci, p_t_telefono);
  else
    v_titular := p_uuid_usuario;
  end if;

  -- ANTIFRAUDE 1: el titular no entra dos veces a la misma cola
  if exists (
    select 1 from flow.sala_espera se
    where se.id_local_servicio = p_id_local_servicio
      and se.uuid_usuario = v_titular
  ) then
    insert into flow.sala_espera_fraude (uuid_usuario, id_local_servicio, motivo, detalle)
    values (p_uuid_usuario, p_id_local_servicio, 'duplicado', null);
    return jsonb_build_object('ok', false, 'error',
      case when v_titular = p_uuid_usuario
           then 'El usuario ya esta en esta cola'
           else 'Esa persona ya esta en esta cola' end);
  end if;

  -- ANTIFRAUDE 2: flood / bots. Demasiadas entradas en poco tiempo.
  -- Cuenta los intentos recientes registrados como entradas exitosas + fraudes.
  select count(*) into v_recientes
  from flow.sala_espera_fraude f
  where f.uuid_usuario = p_uuid_usuario
    and f.created_at >= current_timestamp - c_flood_ventana;

  if v_recientes >= c_flood_max then
    insert into flow.sala_espera_fraude (uuid_usuario, id_local_servicio, motivo, detalle)
    values (p_uuid_usuario, p_id_local_servicio, 'flood',
            jsonb_build_object('intentos_ventana', v_recientes, 'ventana', c_flood_ventana::text));
    return jsonb_build_object('ok', false, 'error', 'Demasiados intentos, espera un momento');
  end if;

  -- Ultimo numero otorgado en este servicio (0 si la cola esta vacia)
  select coalesce(max(se.numero_cola), 0)
    into v_numero
  from flow.sala_espera se
  where se.id_local_servicio = p_id_local_servicio;

  v_numero := v_numero + 1;
  v_fecha  := coalesce(p_fecha_regla, current_timestamp);

  insert into flow.sala_espera
    (uuid_usuario, id_local_servicio, fecha_regla, numero_cola,
     datos_adicionales, reservado_por)
  values
    (v_titular, p_id_local_servicio, v_fecha, v_numero,
     p_datos_adicionales, p_uuid_usuario)
  returning id, created_at into v_id, v_created;

  -- Actualizar ultimo_en_anotarse en ultimo_numero (upsert atomico bajo el mismo advisory lock)
  insert into flow.ultimo_numero (id_local_servicio, ultimo_otorgado, ultimo_en_anotarse, updated_at)
  values (p_id_local_servicio, 0, v_numero, current_timestamp)
  on conflict (id_local_servicio) do update
    set ultimo_en_anotarse = v_numero,
        updated_at         = current_timestamp;

  -- Notificacion al usuario: "entro satisfactoriamente en la cola".
  -- Nombres del servicio y del local para un mensaje legible.
  select s.nombre, l.nombre
    into v_nombre_servicio, v_nombre_local
  from flow.local_servicio ls
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  join flow.app_dat_locales   l on l.id = ls.id_local
  where ls.id = p_id_local_servicio;

  insert into flow.notificaciones
    (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
  values (
    p_uuid_usuario,
    'sala_espera',
    'Entraste en la cola',
    'Has entrado satisfactoriamente en la cola para el servicio "'
      || coalesce(v_nombre_servicio, 'servicio')
      || '" en el local "' || coalesce(v_nombre_local, 'local')
      || '" para reserva a partir del '
      || to_char(v_fecha, 'DD/MM/YYYY') || '.',
    p_id_local_servicio,
    v_id,
    jsonb_build_object(
      'numero_cola', v_numero,
      'fecha_regla', v_fecha,
      'servicio',    v_nombre_servicio,
      'local',       v_nombre_local
    )
  );

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id',                  v_id,
      'uuid_usuario',        p_uuid_usuario,
      'id_local_servicio',   p_id_local_servicio,
      'fecha_regla',         v_fecha,
      'numero_cola',         v_numero,
      'ultimo_en_anotarse',  v_numero,
      'created_at',          v_created
    )
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.cliente_entrar_sala_espera_reserva(p_uuid_usuario uuid, p_id_local_servicio integer, p_fecha_regla timestamp without time zone DEFAULT NULL::timestamp without time zone, p_datos_adicionales jsonb DEFAULT NULL::jsonb, p_para_tercero boolean DEFAULT false, p_t_nombre text DEFAULT NULL::text, p_t_apellidos text DEFAULT NULL::text, p_t_ci text DEFAULT NULL::text, p_t_telefono text DEFAULT NULL::text, p_id_turno integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_numero  integer;
  v_id      integer;
  v_fecha   timestamp without time zone;
  v_created timestamp without time zone;
  v_recientes integer;
  v_nombre_servicio text;
  v_nombre_local    text;
  v_titular uuid;
  c_flood_ventana constant interval := interval '1 minute';
  c_flood_max     constant integer  := 5;
begin
  if p_uuid_usuario is null or p_id_local_servicio is null then
    return jsonb_build_object('ok', false,
      'error', 'uuid_usuario e id_local_servicio son obligatorios');
  end if;

  perform pg_advisory_xact_lock(hashtext('flow.sala_espera'), p_id_local_servicio);

  if not exists (select 1 from flow.local_servicio ls where ls.id = p_id_local_servicio) then
    insert into flow.sala_espera_fraude (uuid_usuario, id_local_servicio, motivo, detalle)
    values (p_uuid_usuario, p_id_local_servicio, 'local_servicio_inexistente', null);
    return jsonb_build_object('ok', false, 'error', 'El id_local_servicio no existe');
  end if;

  -- Validar turno si se pide.
  if p_id_turno is not null then
    if not exists (
      select 1 from flow.turno t
      join flow.recurso r on r.id = t.id_recurso and r.activo
      where t.id = p_id_turno and t.activo and r.id_local_servicio = p_id_local_servicio
    ) then
      return jsonb_build_object('ok', false, 'error', 'Turno invalido para este servicio');
    end if;
  end if;

  -- Titular: uno mismo o un tercero.
  if coalesce(p_para_tercero, false) then
    if not exists (
      select 1 from flow.local_servicio ls
      join flow.app_dat_servicios s on s.id = ls.id_servicio
      where ls.id = p_id_local_servicio and s.permite_tercero = true
    ) then
      return jsonb_build_object('ok', false, 'error', 'Este servicio no permite reservar para terceros');
    end if;
    v_titular := flow._resolver_perfil_tercero(p_t_nombre, p_t_apellidos, p_t_ci, p_t_telefono);
  else
    v_titular := p_uuid_usuario;
  end if;

  -- ANTIFRAUDE 1: el titular no entra dos veces a la cola del MISMO servicio.
  -- Es la restriccion que impone `unique_usuario_servicio_activo`, asi que el
  -- mensaje sale de aqui en vez de un 23505 sin capturar. El turno elegido no
  -- participa: la cola es una sola por servicio-local (ver nota de arriba).
  if exists (
    select 1 from flow.sala_espera se
    where se.id_local_servicio = p_id_local_servicio
      and se.uuid_usuario = v_titular
  ) then
    insert into flow.sala_espera_fraude (uuid_usuario, id_local_servicio, motivo, detalle)
    values (p_uuid_usuario, p_id_local_servicio, 'duplicado', 
            jsonb_build_object('id_turno_intentado', p_id_turno));
    return jsonb_build_object('ok', false, 'error',
      case when v_titular = p_uuid_usuario
           then 'Ya estas en la cola de este servicio: sal de ella para cambiar de turno'
           else 'Esa persona ya esta en la cola de este servicio' end);
  end if;

  -- ANTIFRAUDE 2: flood / bots.
  select count(*) into v_recientes
  from flow.sala_espera_fraude f
  where f.uuid_usuario = p_uuid_usuario
    and f.created_at >= current_timestamp - c_flood_ventana;

  if v_recientes >= c_flood_max then
    insert into flow.sala_espera_fraude (uuid_usuario, id_local_servicio, motivo, detalle)
    values (p_uuid_usuario, p_id_local_servicio, 'flood',
            jsonb_build_object('intentos_ventana', v_recientes, 'ventana', c_flood_ventana::text));
    return jsonb_build_object('ok', false, 'error', 'Demasiados intentos, espera un momento');
  end if;

  -- Numeracion global por LS (independiente del turno).
  select coalesce(max(se.numero_cola), 0) into v_numero
  from flow.sala_espera se
  where se.id_local_servicio = p_id_local_servicio;

  v_numero := v_numero + 1;
  v_fecha  := coalesce(p_fecha_regla, current_timestamp);

  insert into flow.sala_espera
    (uuid_usuario, id_local_servicio, fecha_regla, numero_cola,
     datos_adicionales, reservado_por, id_turno)
  values
    (v_titular, p_id_local_servicio, v_fecha, v_numero,
     p_datos_adicionales, p_uuid_usuario, p_id_turno)
  returning id, created_at into v_id, v_created;

  insert into flow.ultimo_numero (id_local_servicio, ultimo_otorgado, ultimo_en_anotarse, updated_at)
  values (p_id_local_servicio, 0, v_numero, current_timestamp)
  on conflict (id_local_servicio) do update
    set ultimo_en_anotarse = v_numero, updated_at = current_timestamp;

  select s.nombre, l.nombre into v_nombre_servicio, v_nombre_local
  from flow.local_servicio ls
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  join flow.app_dat_locales   l on l.id = ls.id_local
  where ls.id = p_id_local_servicio;

  insert into flow.notificaciones
    (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
  values (
    p_uuid_usuario, 'sala_espera', 'Entraste en la cola',
    'Has entrado satisfactoriamente en la cola para el servicio "'
      || coalesce(v_nombre_servicio, 'servicio')
      || '" en el local "' || coalesce(v_nombre_local, 'local')
      || '" para reserva a partir del '
      || to_char(v_fecha, 'DD/MM/YYYY')
      || case when p_id_turno is null then '.'
              else ' en el turno "' || coalesce((select t.nombre from flow.turno t where t.id = p_id_turno), 'turno') || '".'
         end,
    p_id_local_servicio, v_id,
    jsonb_build_object('numero_cola', v_numero, 'fecha_regla', v_fecha,
      'servicio', v_nombre_servicio, 'local', v_nombre_local, 'id_turno', p_id_turno)
  );

  return jsonb_build_object('ok', true,
    'data', jsonb_build_object(
      'id', v_id, 'uuid_usuario', p_uuid_usuario,
      'id_local_servicio', p_id_local_servicio, 'fecha_regla', v_fecha,
      'numero_cola', v_numero, 'ultimo_en_anotarse', v_numero,
      'created_at', v_created, 'id_turno', p_id_turno));
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.cliente_estado_suscripcion(p_id_entidad integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  -- Escalares y no un `record`: con un record anonimo, un SELECT INTO sin filas
  -- deja la variable sin asignar y leerla revienta con "record is not assigned
  -- yet". Con escalares, "no hay fila" es NULL y se comprueba sin drama.
  v_id         bigint;
  v_estado_g   text;
  v_inicio     timestamptz;
  v_venc       timestamptz;
  v_gracia_fin timestamptz;
  v_origen     text;
  v_plan_cod   text;
  v_plan_nom   text;
  v_dur_dias   integer;
  v_precio     numeric;
  v_moneda     text;
  v_activa     boolean;
  v_gracia     timestamptz;
  v_dias_rest  integer;
  v_dias_grac  integer;
  v_estado     text;
  v_mensaje    text;
begin
  if not (flow._susc_caller_ve_entidad(p_id_entidad)
          or public.fn_is_superadmin_full_access()) then
    return jsonb_build_object('ok', false, 'error', 'No tiene acceso a esta entidad');
  end if;

  v_activa := flow.entidad_activa(p_id_entidad);

  select s.id, s.estado, s.fecha_inicio, s.fecha_vencimiento, s.fecha_gracia_fin,
         s.origen,
         p.codigo, p.nombre, p.duracion_dias, p.precio, p.moneda
    into v_id, v_estado_g, v_inicio, v_venc, v_gracia_fin,
         v_origen,
         v_plan_cod, v_plan_nom, v_dur_dias, v_precio, v_moneda
  from flow.suscripcion s
  left join flow.suscripcion_plan p on p.id = s.id_plan
  where s.id_entidad = p_id_entidad
  order by
    (s.estado in ('trial','activa','en_gracia','sin_plan','suspendida')) desc,
    s.updated_at desc,
    s.id desc
  limit 1;

  -- Sin fila: grandfathering. Se reporta activa y sin vencimiento conocido.
  if v_id is null then
    return jsonb_build_object(
      'ok', true,
      'data', jsonb_build_object(
        'id_entidad',        p_id_entidad,
        'estado',            'sin_suscripcion',
        'activa',            true,
        'es_trial',          false,
        'en_gracia',         false,
        'plan_codigo',       null,
        'plan_nombre',       null,
        'duracion_dias',     null,
        'precio',            null,
        'moneda',            null,
        'fecha_inicio',      null,
        'fecha_vencimiento', null,
        'fecha_gracia_fin',  null,
        'dias_restantes',    null,
        'dias_gracia',       null,
        'mensaje',           'Esta entidad todavia no tiene suscripcion registrada.'
      )
    );
  end if;

  v_estado    := v_estado_g;
  v_gracia    := coalesce(v_gracia_fin, v_venc);
  v_dias_rest := case when v_venc is null then null
                      else ceil(extract(epoch from (v_venc - now())) / 86400.0)::integer
                 end;
  v_dias_grac := case when v_gracia is null then null
                      else ceil(extract(epoch from (v_gracia - now())) / 86400.0)::integer
                 end;

  -- El estado que pinta la UI se deriva de las fechas, no del texto guardado:
  -- el cron puede ir con retraso y el aviso tiene que ser exacto igual.
  if not v_activa then
    v_estado := case
                  when v_estado_g = 'suspendida' then 'suspendida'
                  when v_estado_g = 'sin_plan'   then 'sin_plan'
                  else 'vencida'
                end;
    v_mensaje := case
                   when v_estado_g = 'suspendida'
                     then 'La suscripcion de esta entidad esta suspendida por el administrador.'
                   when v_estado_g = 'sin_plan'
                     then 'Esta entidad no tiene un plan activo. Compra un plan para publicarla.'
                   else 'La suscripcion vencio y se agoto el margen de gracia. Esta entidad no se muestra ni admite reservas.'
                 end;
  elsif v_gracia is not null and v_gracia > now() and v_venc <= now() then
    v_estado  := 'en_gracia';
    v_mensaje := 'La suscripcion vencio. Tiene ' || coalesce(v_dias_grac, 0)
              || ' dia(s) de margen antes de que la entidad se desactive.';
  elsif v_estado_g = 'trial' then
    v_mensaje := 'Periodo de prueba: quedan ' || coalesce(v_dias_rest, 0) || ' dia(s).';
  else
    v_mensaje := 'Suscripcion activa: quedan ' || coalesce(v_dias_rest, 0) || ' dia(s).';
  end if;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id_entidad',        p_id_entidad,
      'estado',            v_estado,
      'estado_guardado',   v_estado_g,
      'activa',            v_activa,
      'es_trial',          v_estado_g = 'trial',
      'en_gracia',         v_estado = 'en_gracia',
      'plan_codigo',       v_plan_cod,
      'plan_nombre',       v_plan_nom,
      'duracion_dias',     v_dur_dias,
      'precio',            v_precio,
      'moneda',            v_moneda,
      'fecha_inicio',      v_inicio,
      'fecha_vencimiento', v_venc,
      'fecha_gracia_fin',  v_gracia_fin,
      'dias_restantes',    v_dias_rest,
      'dias_gracia',       v_dias_grac,
      'mensaje',           v_mensaje
    )
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.cliente_home_feed(p_query text DEFAULT NULL::text, p_id_categoria integer DEFAULT NULL::integer, p_provincia text DEFAULT NULL::text, p_id_coleccion integer DEFAULT NULL::integer, p_mejor_valorados boolean DEFAULT false, p_id_subcategoria integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
with busqueda as (
  -- El termino se normaliza UNA vez. Mismo criterio que la app: minusculas y
  -- sin acentos, en los dos lados de la comparacion.
  select nullif(btrim(unaccent(lower(coalesce(p_query, '')))), '') as q
),
base as (
  select
    ls.id                          as id_local_servicio,
    ls.created_at                  as created_at,
    ls.permite_reserva_directa,
    ls.cantidad_default,
    ls.cantidad_max_capacidad,
    -- [42] estado del par y modo de gestion
    ls.activo                      as ls_activo,
    ls.solo_turnos,
    ls.sin_tramos,
    s.id                           as id_servicio,
    s.nombre                       as servicio,
    s.descripcion                  as descripcion,
    s.foto                         as foto_servicio,
    -- [42]
    s.activo                       as servicio_activo,
    s.campos_adicionales,
    s.permite_tercero,
    s.config_precio,
    s.id_tipo_actividad,
    -- [47] La fila a la que apunta el servicio es la HOJA: o una subcategoria
    -- (con padre) o una categoria raiz. Se traen las dos cosas para poder emitir
    -- categoria y subcategoria por separado.
    ta.codigo                      as actividad_codigo,
    ta.nombre                      as actividad_nombre,
    ta.id_padre                    as actividad_id_padre,
    ta.activo                      as actividad_activa,
    tp.codigo                      as padre_codigo,
    tp.nombre                      as padre_nombre,
    tp.activo                      as padre_activo,
    l.id                           as id_local,
    l.nombre                       as local,
    l.descripcion                  as local_descripcion,
    l.horario_atencion,
    -- [42] horario estructurado (punto 10)
    l.horario_detalle,
    -- [42]
    l.activo                       as local_activo,
    l.coordenadas,
    l.direccion,
    l.pais,
    l.provincia,
    l.foto                         as foto_local,
    en.id                          as id_entidad,
    en.denominacion                as entidad,
    en.direccion                   as entidad_direccion,
    en.telefono                    as entidad_telefono,
    en.horas_anticipacion_cancelacion,
    coalesce(rv.total, 0)::integer as total_resenas,
    rv.promedio                    as rating,
    pr.id                          as id_promocion,
    pr.titulo                      as promo_titulo,
    pr.tipo                        as promo_tipo,
    pr.valor                       as promo_valor,
    pr.moneda                      as promo_moneda,
    pr.hasta                       as promo_hasta,
    pr.cupos_restantes,
    cs.orden                       as orden_coleccion
  from flow.local_servicio ls
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  join flow.app_dat_locales   l on l.id = ls.id_local
  left join flow.nom_tipo_actividad_servicio ta on ta.id = s.id_tipo_actividad
  -- [47] El padre. Solo existe cuando el servicio esta en una subcategoria.
  left join flow.nom_tipo_actividad_servicio tp on tp.id = ta.id_padre
  left join flow.entidad                     en on en.id = l.id_entidad
  -- Composicion, no copia: la regla de prioridad de la promo y el promedio de
  -- resenas siguen viviendo en un unico sitio.
  left join flow.resenas_por_servicio()     rv on rv.id_local_servicio = ls.id
  left join flow.promociones_por_servicio() pr on pr.id_local_servicio = ls.id
  -- Con `p_id_coleccion` nulo la condicion no casa y `orden_coleccion` queda
  -- nulo, que es justo lo que hace que no filtre nada.
  left join flow.coleccion_servicio cs
         on cs.id_local_servicio = ls.id
        and cs.id_coleccion = p_id_coleccion
  cross join busqueda b
  where
    -- [47] Filtrar por categoria incluye sus subcategorias.
    (
      p_id_categoria is null
      or s.id_tipo_actividad = p_id_categoria
      or ta.id_padre = p_id_categoria
    )
    -- [47] La subcategoria manda sobre la categoria: si llegan las dos, el
    -- resultado son los servicios de esa subcategoria concreta.
    and (p_id_subcategoria is null or s.id_tipo_actividad = p_id_subcategoria)
    and (p_id_coleccion is null or cs.id_coleccion is not null)
    -- [42] EL filtro del punto 3/4/8: lo que no esta publicado no existe para
    -- el cliente. Se evalua antes que el resto para descartar temprano.
    and flow._ls_disponible(ls.id)
    -- [55] Lo que la ENTIDAD oculto para si misma. Se compara contra la HOJA y
    -- contra su PADRE: ocultar una categoria raiz esconde tambien los servicios
    -- de sus subcategorias. `l.id_entidad` nulo (dato viejo) nunca casa, asi que
    -- no oculta nada por accidente.
    and not exists (
      select 1
      from flow.entidad_categoria_oculta o
      where o.id_entidad = l.id_entidad
        and (
          o.id_tipo_actividad = ta.id
          or o.id_tipo_actividad = ta.id_padre
        )
    )
    -- Provincia: comparacion exacta sin acentos, igual que hoy en la app.
    -- No se usa unaccent aqui a proposito: la app tampoco lo hace.
    and (
      p_provincia is null
      or btrim(p_provincia) = ''
      or lower(btrim(l.provincia)) = lower(btrim(p_provincia))
    )
    -- `strpos` en vez de `like`: un `%` escrito por el usuario es un caracter
    -- literal, no un comodin. Asi el comportamiento es identico al `contains`
    -- de Dart. [47] Se busca tambien en la categoria padre.
    and (
      b.q is null
      or strpos(
           unaccent(lower(
             coalesce(s.nombre, '') || ' ' ||
             coalesce(l.nombre, '') || ' ' ||
             coalesce(nullif(btrim(ta.nombre), ''),
                      replace(coalesce(ta.codigo, ''), '_', ' '),
                      'General') || ' ' ||
             coalesce(nullif(btrim(tp.nombre), ''), '')
           )),
           b.q
         ) > 0
    )
),
ordenado as (
  select b.*,
         row_number() over (
           order by
             -- Con coleccion elegida manda el orden curado por el superadmin.
             case when p_id_coleccion is not null then b.orden_coleccion end asc nulls last,
             -- "Mejor valorados": los que no tienen valoracion van al final; no se
             -- les supone una. La condicion es EXACTAMENTE la del getter
             -- `HomeCatalogItem.tieneValoracion` del cliente
             -- (`totalResenas > 0 and rating > 0`), para que el orden del
             -- servidor y el "pinto estrellas?" del cliente no se contradigan.
             case when p_mejor_valorados
                   and not (b.total_resenas > 0 and coalesce(b.rating, 0) > 0)
                  then 1 else 0 end asc,
             case when p_mejor_valorados then b.rating end desc nulls last,
             case when p_mejor_valorados then b.total_resenas end desc,
             -- Orden por defecto: el mismo que `cliente_obtener_servicios`.
             b.local asc,
             b.servicio asc
         ) as rn
  from base b
),
pagina as (
  select
    coalesce(jsonb_agg(
      -- Cada item reusa EXACTAMENTE la forma anidada que ya devuelve
      -- `cliente_obtener_servicios` (`servicio` / `local` / `entidad`), y le
      -- anade los extras. Asi el modelo Dart (`LocalServicio.fromJson`,
      -- `Servicio.fromJson`) sigue funcionando sin cambios y la navegacion al
      -- detalle no se rompe: si el feed devolviera filas planas, el cliente
      -- tendria que adaptarlas y volveriamos a tener dos formas del mismo dato.
      jsonb_build_object(
        'id_local_servicio',       o.id_local_servicio,
        'created_at',              o.created_at,
        'permite_reserva_directa', o.permite_reserva_directa,
        'cantidad_default',        o.cantidad_default,
        'cantidad_max_capacidad',  o.cantidad_max_capacidad,
        -- [42] mismo estado que `cliente_obtener_servicios`, para que el modelo
        -- Dart lo lea igual venga del feed o del catalogo.
        'activo',                  o.ls_activo,
        'solo_turnos',             o.solo_turnos,
        'sin_tramos',              o.sin_tramos,

        -- Extras del feed (no venian en `cliente_obtener_servicios`).
        'rating',         o.rating,
        'total_resenas',  o.total_resenas,
        -- [47] Categoria = padre cuando existe; si la hoja es raiz, ella misma.
        'categoria_codigo', coalesce(o.padre_codigo, o.actividad_codigo),
        -- Se emite la categoria SOLO si esta activa. Con la categoria apagada
        -- queda NULL y el cliente cae a su respaldo (el codigo legible), que es
        -- lo que hacia antes: el nomenclador activo no la conocia.
        'categoria_nombre', case
                              when coalesce(o.padre_activo, o.actividad_activa)
                                then nullif(btrim(coalesce(o.padre_nombre, o.actividad_nombre)), '')
                              else null
                            end,
        -- [47] Subcategoria: solo si la hoja cuelga de una categoria. Se exige
        -- que la hoja este activa: una subcategoria desactivada deja de existir
        -- para el cliente aunque su categoria siga encendida.
        'subcategoria_codigo', case
                                 when o.actividad_id_padre is null then null
                                 when o.actividad_activa then o.actividad_codigo
                                 else null
                               end,
        'subcategoria_nombre', case
                                 when o.actividad_id_padre is null then null
                                 when o.actividad_activa
                                   then nullif(btrim(o.actividad_nombre), '')
                                 else null
                               end,
        'promocion', case when o.id_promocion is null then null else
                       jsonb_build_object(
                         'id',              o.id_promocion,
                         'titulo',          o.promo_titulo,
                         'tipo',            o.promo_tipo,
                         'valor',           o.promo_valor,
                         'moneda',          o.promo_moneda,
                         'hasta',           o.promo_hasta,
                         'cupos_restantes', o.cupos_restantes
                       )
                     end,

        'servicio', jsonb_build_object(
          'id',                 o.id_servicio,
          'nombre',             o.servicio,
          'descripcion',        o.descripcion,
          'foto',               o.foto_servicio,
          'campos_adicionales', o.campos_adicionales,
          'permite_tercero',    o.permite_tercero,
          'config_precio',      o.config_precio,
          'id_tipo_actividad',  o.id_tipo_actividad,
          -- [42]
          'activo',             o.servicio_activo,
          -- [47] OJO: `codigo` es el de la HOJA (puede ser una subcategoria).
          -- `LocalServicio.esTransporteOmnibus` depende de que 'transporte_omnibus'
          -- siga llegando aqui. `id_padre` viaja para que el cliente pueda
          -- resolver la categoria sin otra consulta.
          'tipo_actividad', jsonb_build_object(
            'id',       o.id_tipo_actividad,
            'codigo',   o.actividad_codigo,
            'nombre',   o.actividad_nombre,
            'id_padre', o.actividad_id_padre
          )
        ),

        'local', jsonb_build_object(
          'id',               o.id_local,
          'nombre',           o.local,
          'descripcion',      o.local_descripcion,
          'horario_atencion', o.horario_atencion,
          -- [42]
          'horario_detalle',  o.horario_detalle,
          'coordenadas',      o.coordenadas,
          'direccion',        o.direccion,
          'pais',             o.pais,
          'provincia',        o.provincia,
          'foto',             o.foto_local,
          -- [42]
          'activo',           o.local_activo
        ),

        'entidad', jsonb_build_object(
          'id',                             o.id_entidad,
          'denominacion',                   o.entidad,
          'direccion',                      o.entidad_direccion,
          'telefono',                       o.entidad_telefono,
          'horas_anticipacion_cancelacion', o.horas_anticipacion_cancelacion
        )
      )
      order by o.rn
    ), '[]'::jsonb) as items,
    count(*)::integer as total
  from ordenado o
),
nomenclador as (
  -- [47] Solo raices activas. Cada una lleva sus subcategorias activas
  -- anidadas: el Home pinta el riel y, al tocar una categoria, los chips de
  -- debajo sin pedir nada mas.
  -- [55] NO se filtra por `entidad_categoria_oculta`: la categoria oculta sigue
  -- en el riel. Ocultar esconde servicios, no filtros.
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id',     ta.id,
             'codigo', ta.codigo,
             'nombre', ta.nombre,
             'id_padre', null,
             'subcategorias', coalesce((
               select jsonb_agg(
                        jsonb_build_object(
                          'id',       h.id,
                          'codigo',   h.codigo,
                          'nombre',   h.nombre,
                          'id_padre', h.id_padre
                        )
                        order by h.orden, lower(h.nombre)
                      )
               from flow.nom_tipo_actividad_servicio h
               where h.id_padre = ta.id
                 and h.activo
                 and btrim(h.nombre) <> ''
             ), '[]'::jsonb)
           )
           order by ta.orden, lower(ta.nombre)
         ), '[]'::jsonb) as categorias
  from flow.nom_tipo_actividad_servicio ta
  where ta.activo
    and ta.id_padre is null
    and btrim(ta.nombre) <> ''
)
select jsonb_build_object(
  'items',       p.items,
  'total',       p.total,
  -- Contrato de paginacion completo aunque hoy no se use (ver cabecera).
  'has_more',    false,
  'next_cursor', null,
  'metadata',    jsonb_build_object('categorias', n.categorias),
  'colecciones',  flow.colecciones_activas(),
  'patrocinados', flow.campanas_activas(),
  'contadores',  jsonb_build_object(
    'notificaciones', (
      select count(*)::integer
      from flow.notificaciones no
      where no.uuid_usuario = auth.uid()
        and not no.leida
    ),
    'reservas', (
      -- Mismo WHERE que `cliente_obtener_agendas` + el filtro del provider:
      -- el OR importa, porque reservar para un tercero crea una fila que debe
      -- contar para quien la hizo.
      select count(*)::integer
      from flow.agenda a
      where (a.uuid_usuario = auth.uid() or a.reservado_por = auth.uid())
        and a.id_estado = 1
    )
  )
)
from pagina p, nomenclador n;
$function$
;

CREATE OR REPLACE FUNCTION flow.cliente_marcar_intent_abierto(p_id_intent bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_int flow.suscripcion_intent%rowtype;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Sesion requerida');
  end if;

  select i.* into v_int from flow.suscripcion_intent i where i.id = p_id_intent;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'El intento de pago no existe');
  end if;

  if not (v_int.uuid_usuario = v_uid
          or flow._susc_caller_ve_entidad(v_int.id_entidad)) then
    return jsonb_build_object('ok', false, 'error', 'No tiene acceso a este intento de pago');
  end if;

  if v_int.estado = 'creado' then
    update flow.suscripcion_intent set estado = 'abierto' where id = v_int.id;
  end if;

  return jsonb_build_object('ok', true, 'data', jsonb_build_object('id', v_int.id, 'estado', 'abierto'));
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.cliente_mi_fidelidad()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
  with yo as (select auth.uid() as u),
  cfg as (
    select coalesce(
      (select c.activa from flow.fidelidad_config c where c.id = 1), true
    ) as activa
  )
  select jsonb_build_object(
    'con_sesion', (select u from yo) is not null,
    -- Interruptor global: si es false, el Home no pinta la seccion.
    'activa', (select activa from cfg),
    'saldo', flow.fn_saldo_puntos((select u from yo)),
    'regla', (
      select jsonb_build_object(
               'puntos_por_monto', r.puntos_por_monto,
               'monto_base',       r.monto_base,
               'vigencia_dias',    r.vigencia_dias,
               'moneda',           r.moneda
             )
      from flow.regla_fidelidad r
      where r.activo
        and r.id_entidad is null
        and (r.desde is null or r.desde <= current_timestamp)
        and (r.hasta is null or current_timestamp < r.hasta)
      order by r.id
      limit 1
    ),
    'beneficio', (
      select jsonb_build_object(
               'id',           b.id,
               'titulo',       b.titulo,
               'descripcion',  b.descripcion,
               'tipo',         b.tipo,
               'valor',        b.valor,
               'moneda',       b.moneda,
               'monto_minimo', b.monto_minimo
             )
      from flow.beneficio_bienvenida b
      where b.activo
        and b.id_entidad is null
        and (b.desde is null or b.desde <= current_timestamp)
        and (b.hasta is null or current_timestamp < b.hasta)
        and not exists (
          select 1 from flow.beneficio_canje c
          where c.uuid_usuario = (select u from yo)
        )
      order by b.id
      limit 1
    ),
    'ya_canjeo', exists (
      select 1 from flow.beneficio_canje c where c.uuid_usuario = (select u from yo)
    ),
    'movimientos', coalesce((
      select jsonb_agg(x order by x.created_at desc)
      from (
        select m.id, m.puntos, m.tipo, m.motivo, m.moneda, m.monto,
               m.vence_en, m.created_at,
               (m.tipo = 'acumulacion'
                and m.liquidado = false
                and m.vence_en is not null
                and m.vence_en <= current_timestamp) as vencido
        from flow.puntos_movimiento m
        where m.uuid_usuario = (select u from yo)
        order by m.created_at desc
        limit 50
      ) x
    ), '[]'::jsonb)
  );
$function$
;

CREATE OR REPLACE FUNCTION flow.cliente_mis_pagos_suscripcion(p_id_entidad integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
begin
  if not (flow._susc_caller_ve_entidad(p_id_entidad)
          or public.fn_is_superadmin_full_access()) then
    return jsonb_build_object('ok', false, 'error', 'No tiene acceso a esta entidad');
  end if;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      -- OJO: el `limit` va en una subconsulta, NO en el SELECT del agregado. Con
      -- `select jsonb_agg(...) ... limit 20` el LIMIT recorta el unico resultado
      -- del agregado (no hace nada) y devolveria TODAS las filas.
      'intents', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id',             x.id,
                 'id_plan',        x.id_plan,
                 'plan_nombre',    x.plan_nombre,
                 'monto',          x.monto,
                 'moneda',         x.moneda,
                 'id_transaccion', x.id_transaccion,
                 'url_intent',     x.url_intent,
                 'url_http',       x.url_http,
                 'estado',         x.estado,
                 'expira_at',      x.expira_at,
                 'created_at',     x.created_at
               ) order by x.created_at desc)
        from (
          select i.*, p.nombre as plan_nombre
          from flow.suscripcion_intent i
          left join flow.suscripcion_plan p on p.id = i.id_plan
          where i.id_entidad = p_id_entidad
          order by i.created_at desc
          limit 20
        ) x), '[]'::jsonb),

      'pagos', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id',                  x.id,
                 'id_intent',           x.id_intent,
                 'codigo_confirmacion', x.codigo_confirmacion,
                 'monto',               x.monto,
                 'moneda',              x.moneda,
                 'metodo',              x.metodo,
                 'comprobante_url',     x.comprobante_url,
                 'estado',              x.estado,
                 'observaciones',       x.observaciones,
                 'reportado_at',        x.reportado_at,
                 'verificado_at',       x.verificado_at
               ) order by x.reportado_at desc)
        from (
          select t.*
          from flow.suscripcion_transaccion t
          where t.id_entidad = p_id_entidad
          order by t.reportado_at desc
          limit 20
        ) x), '[]'::jsonb),

      'movimientos', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'tipo',        x.tipo,
                 'dias',        x.dias,
                 'fecha_desde', x.fecha_desde,
                 'fecha_hasta', x.fecha_hasta,
                 'motivo',      x.motivo,
                 'created_at',  x.created_at
               ) order by x.created_at desc)
        from (
          select m.*
          from flow.suscripcion_movimiento m
          where m.id_entidad = p_id_entidad
          order by m.created_at desc
          limit 30
        ) x), '[]'::jsonb)
    )
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.cliente_obtener_disponibilidad(p_id_local_servicio integer, p_desde date DEFAULT NULL::date, p_hasta date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_desde date;
  v_hasta date;
  v_data  jsonb;
begin
  -- [42] Si no esta publicado, no hay nada que ofrecer al cliente.
  if not coalesce(flow._ls_disponible(p_id_local_servicio), false)
     and not flow._caller_es_admin_de_ls(p_id_local_servicio) then
    return '[]'::jsonb;
  end if;

  v_desde := coalesce(p_desde, (current_timestamp at time zone 'America/Havana')::date);
  v_hasta := coalesce(p_hasta, (current_timestamp at time zone 'America/Havana')::date + 90);

  if not flow._ls_tiene_recursos(p_id_local_servicio) then
    -- ── Camino legacy: cupo por dia desde plan_servicios (formato original) ──
    with por_dia as (
      select (ps.fecha at time zone 'America/Havana')::date as dia,
             sum(ps.cantidad)  as cantidad,
             sum(ps.agendados) as agendados
      from flow.plan_servicios ps
      where ps.id_local_servicio = p_id_local_servicio
        and ps.cantidad is not null
        and (ps.fecha at time zone 'America/Havana')::date between v_desde and v_hasta
      group by (ps.fecha at time zone 'America/Havana')::date
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'fecha',       to_char(pd.dia, 'YYYY-MM-DD'),
             'cantidad',    pd.cantidad,
             'agendados',   pd.agendados,
             'disponibles', pd.cantidad - pd.agendados
           ) order by pd.dia), '[]'::jsonb)
      into v_data
    from por_dia pd
    where pd.cantidad - pd.agendados > 0;

    return v_data;
  end if;

  -- ── Camino recursos: disponibilidad por turno y por dia ──
  with turnos_dia as (
    select
      (pt.fecha at time zone 'America/Havana')::date as dia,
      r.id     as id_recurso,
      r.nombre as recurso,
      r.orden  as r_orden,
      t.id     as id_turno,
      t.nombre as turno,
      t.orden  as t_orden,
      -- [42] horas opcionales del turno (punto 7)
      t.hora_inicio,
      t.hora_fin,
      min(pt.cantidad - pt.agendados)                    as disp,
      count(*)                                           as n_plan,
      (select count(*) from flow.turno_tramo tt2
         where tt2.id_turno = t.id)                      as n_turno
    from flow.turno t
    join flow.recurso r      on r.id = t.id_recurso and r.activo
    join flow.turno_tramo tt on tt.id_turno = t.id
    join flow.tramo tr       on tr.id = tt.id_tramo and tr.activo
    join flow.plan_tramo pt  on pt.id_tramo = tr.id
    where r.id_local_servicio = p_id_local_servicio
      and t.activo
      and (pt.fecha at time zone 'America/Havana')::date between v_desde and v_hasta
    group by dia, r.id, r.nombre, r.orden, t.id, t.nombre, t.orden, t.hora_inicio, t.hora_fin
  ),
  turnos_ok as (
    -- El turno solo cuenta si TODOS sus tramos tienen cupo ese dia y disp > 0.
    select * from turnos_dia
    where n_plan = n_turno and disp > 0
  ),
  por_dia as (
    select
      dia,
      sum(disp) as disponibles,
      jsonb_agg(jsonb_build_object(
        'id_recurso',  id_recurso,
        'recurso',     recurso,
        'id_turno',    id_turno,
        'turno',       turno,
        'disponibles', disp,
        -- [42] "09:00" / "11:00" o null. `to_char` para no mandar "09:00:00".
        'hora_inicio', case when hora_inicio is null then null
                            else to_char(hora_inicio, 'HH24:MI') end,
        'hora_fin',    case when hora_fin is null then null
                            else to_char(hora_fin, 'HH24:MI') end
      ) order by r_orden, id_recurso, t_orden, id_turno) as turnos
    from turnos_ok
    group by dia
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'fecha',       to_char(pd.dia, 'YYYY-MM-DD'),
           'cantidad',    pd.disponibles,   -- agregado (no hay un unico "total")
           'agendados',   0,
           'disponibles', pd.disponibles,
           'turnos',      pd.turnos
         ) order by pd.dia), '[]'::jsonb)
    into v_data
  from por_dia pd
  where pd.disponibles > 0;

  return v_data;
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.cliente_obtener_disponibilidad_transporte(p_id_local_servicio integer, p_fecha date, p_tipo_trayecto character varying DEFAULT NULL::character varying)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
  select case
    when not coalesce(flow._ls_disponible(p_id_local_servicio), false)
         and not flow._caller_es_admin_de_ls(p_id_local_servicio)
    then jsonb_build_object(
           'ok', false,
           'fecha', to_char(p_fecha, 'YYYY-MM-DD'),
           'turnos', '[]'::jsonb
         )
    else (
  with actividad as (
    select 1
    from flow.local_servicio ls
    join flow.app_dat_servicios s on s.id = ls.id_servicio
    join flow.nom_tipo_actividad_servicio ta on ta.id = s.id_tipo_actividad
    where ls.id = p_id_local_servicio
      and ta.codigo = 'transporte_omnibus'
  ), por_turno as (
    select
      t.id as id_turno,
      r.id as id_recurso,
      r.nombre as recurso,
      t.nombre as turno,
      t.precios,
      tr.tipo_trayecto,
      min(pt.cantidad) as cantidad,
      min(pt.agendados) as agendados,
      min(pt.cantidad - pt.agendados) as disponibles,
      (
        select count(*)::int
        from flow.turno_tramo tt_c
        join flow.tramo tr_c on tr_c.id = tt_c.id_tramo and tr_c.activo
        where tt_c.id_turno = t.id
      ) as num_tramos,
      exists (
        select 1
        from flow.turno_tramo tt_i
        join flow.tramo tr_i on tr_i.id = tt_i.id_tramo and tr_i.activo
        where tt_i.id_turno = t.id and tr_i.tipo_trayecto = 'ida'
      ) and exists (
        select 1
        from flow.turno_tramo tt_v
        join flow.tramo tr_v on tr_v.id = tt_v.id_tramo and tr_v.activo
        where tt_v.id_turno = t.id and tr_v.tipo_trayecto = 'vuelta'
      ) as es_combinado
    from flow.turno t
    join flow.recurso r on r.id = t.id_recurso and r.activo
    join flow.turno_tramo tt on tt.id_turno = t.id
    join flow.tramo tr on tr.id = tt.id_tramo and tr.activo
    join flow.plan_tramo pt on pt.id_tramo = tr.id
    where r.id_local_servicio = p_id_local_servicio
      and t.activo
      and (pt.fecha at time zone 'America/Havana')::date = p_fecha
      and (p_tipo_trayecto is null or tr.tipo_trayecto = p_tipo_trayecto)
    group by t.id, r.id, r.nombre, t.nombre, t.precios, tr.tipo_trayecto
    having count(*) = 1
  )
  select jsonb_build_object(
    'ok', exists(select 1 from actividad),
    'fecha', to_char(p_fecha, 'YYYY-MM-DD'),
    'turnos', coalesce(jsonb_agg(jsonb_build_object(
      'id_turno', id_turno,
      'id_recurso', id_recurso,
      'recurso', recurso,
      'turno', turno,
      'precios', precios,
      'tipo_trayecto', tipo_trayecto,
      'cantidad', cantidad,
      'agendados', agendados,
      'disponibles', disponibles,
      'num_tramos', num_tramos,
      'es_combinado', es_combinado or num_tramos > 1
    ) order by recurso, turno), '[]'::jsonb)
  )
  from por_turno
    )
  end;
$function$
;

CREATE OR REPLACE FUNCTION flow.cliente_obtener_fechas_disponibles_transporte(p_id_local_servicio integer, p_tipo_trayecto character varying)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
  select case
    when not coalesce(flow._ls_disponible(p_id_local_servicio), false)
         and not flow._caller_es_admin_de_ls(p_id_local_servicio)
    then '[]'::jsonb
    else (
      select coalesce(jsonb_agg(fecha order by fecha), '[]'::jsonb)
      from (
        select distinct (pt.fecha at time zone 'America/Havana')::date as fecha
        from flow.plan_tramo pt
        join flow.tramo tr on tr.id = pt.id_tramo and tr.activo
        join flow.recurso r on r.id = tr.id_recurso and r.activo
        join flow.turno_tramo tt on tt.id_tramo = tr.id
        join flow.turno t on t.id = tt.id_turno and t.activo
        where r.id_local_servicio = p_id_local_servicio
          and tr.tipo_trayecto = p_tipo_trayecto
          and pt.cantidad > pt.agendados
          and (pt.fecha at time zone 'America/Havana')::date >= current_date
      ) fechas
    )
  end;
$function$
;

CREATE OR REPLACE FUNCTION flow.cliente_obtener_salas_espera(p_uuid_usuario uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',                se.id,
        'fecha_regla',       se.fecha_regla,
        'created_at',        se.created_at,
        'numero_cola',       se.numero_cola,           -- numero del usuario
        'ultimo_otorgado',   coalesce(un.ultimo_otorgado, 0), -- ultimo numero en el servicio
        -- cuantos numeros faltan para llegar al del usuario (0 = ya es su turno o paso)
        'personas_delante',  greatest(se.numero_cola - coalesce(un.ultimo_otorgado, 0), 0),
        'es_su_turno',       (coalesce(un.ultimo_otorgado, 0) >= se.numero_cola),
        'id_local_servicio', ls.id,
        -- Turno elegido al anotarse (null en las entradas anteriores a esta
        -- migracion y en los servicios que no trabajan por turnos).
        'id_turno',          se.id_turno,
        'turno',             t.nombre,
        'servicio', jsonb_build_object(
          'id',          s.id,
          'nombre',      s.nombre,
          'descripcion', s.descripcion,
          'foto',        s.foto
        ),
        'local', jsonb_build_object(
          'id',               l.id,
          'nombre',           l.nombre,
          'direccion',        l.direccion,
          'pais',             l.pais,
          'provincia',        l.provincia,
          'horario_atencion', l.horario_atencion,
          'coordenadas',      l.coordenadas,
          'foto',             l.foto
        )
      )
      order by se.fecha_regla
    ),
    '[]'::jsonb
  )
  from flow.sala_espera se
  join flow.local_servicio    ls on ls.id = se.id_local_servicio
  join flow.app_dat_locales   l  on l.id  = ls.id_local
  join flow.app_dat_servicios s  on s.id  = ls.id_servicio
  left join flow.turno        t  on t.id  = se.id_turno
  left join flow.ultimo_numero un on un.id_local_servicio = ls.id
  where se.uuid_usuario = p_uuid_usuario;
$function$
;

CREATE OR REPLACE FUNCTION flow.cliente_obtener_servicios(p_id_local integer DEFAULT NULL::integer, p_id_servicio integer DEFAULT NULL::integer, p_id_entidad integer DEFAULT NULL::integer, p_nombre_local text DEFAULT NULL::text, p_nombre_servicio text DEFAULT NULL::text, p_pais text DEFAULT NULL::text, p_provincia text DEFAULT NULL::text, p_incluir_inactivos boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id_local_servicio',       ls.id,
        'created_at',              ls.created_at,
        'permite_reserva_directa', ls.permite_reserva_directa,
        'cantidad_default',        ls.cantidad_default,
        'cantidad_max_capacidad',  ls.cantidad_max_capacidad,
        -- [42] Estado y modo del par, para pintar chips y atenuar en el admin.
        'activo',                  ls.activo,
        'solo_turnos',             ls.solo_turnos,
        'sin_tramos',              ls.sin_tramos,
        'servicio', jsonb_build_object(
          'id',                 s.id,
          'nombre',             s.nombre,
          'descripcion',        s.descripcion,
          'foto',               s.foto,
          'campos_adicionales', s.campos_adicionales,
          'permite_tercero',    s.permite_tercero,
          'config_precio',      s.config_precio,
          'id_tipo_actividad', s.id_tipo_actividad,
          -- [42]
          'activo',             s.activo,
          -- [47] `id_padre` y `nombre`: la app resuelve con ellos si el codigo
          -- es una categoria (padre null) o una subcategoria.
          'tipo_actividad', case when ta.id is null then null else jsonb_build_object(
            'id',       ta.id,
            'codigo',   ta.codigo,
            'nombre',   ta.nombre,
            'id_padre', ta.id_padre
          ) end
        ),
        'local', jsonb_build_object(
          'id',               l.id,
          'nombre',           l.nombre,
          'descripcion',      l.descripcion,
          'horario_atencion', l.horario_atencion,
          -- [42] Horario estructurado del punto 10.
          'horario_detalle',  l.horario_detalle,
          'coordenadas',      l.coordenadas,
          'direccion',        l.direccion,
          'pais',             l.pais,
          'provincia',        l.provincia,
          'foto',             l.foto,
          -- [42]
          'activo',           l.activo
        ),
        'entidad', case when en.id is null then null else jsonb_build_object(
          'id',                           en.id,
          'denominacion',                 en.denominacion,
          'direccion',                    en.direccion,
          'telefono',                     en.telefono,
          'horas_anticipacion_cancelacion', en.horas_anticipacion_cancelacion
        ) end
      )
      order by l.nombre, s.nombre
    ),
    '[]'::jsonb
  )
  from flow.local_servicio ls
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  left join flow.nom_tipo_actividad_servicio ta on ta.id = s.id_tipo_actividad
  join flow.app_dat_locales   l on l.id = ls.id_local
  left join flow.entidad     en on en.id = l.id_entidad
  where (p_id_local        is null or ls.id_local    = p_id_local)
    and (p_id_servicio     is null or ls.id_servicio = p_id_servicio)
    and (p_id_entidad      is null or l.id_entidad   = p_id_entidad)
    and (p_nombre_local    is null or l.nombre    ilike '%' || p_nombre_local    || '%')
    and (p_nombre_servicio is null or s.nombre    ilike '%' || p_nombre_servicio || '%')
    and (p_pais            is null or l.pais      ilike '%' || p_pais            || '%')
    and (p_provincia       is null or l.provincia ilike '%' || p_provincia       || '%')
    -- [42] La única regla de visibilidad. `p_incluir_inactivos` la salta para el
    -- admin; el resto del mundo ve exactamente lo reservable.
    and (p_incluir_inactivos or flow._ls_disponible(ls.id))
    -- [55] La ocultacion por entidad. El admin (`p_incluir_inactivos = true`) la
    -- salta: tiene que poder ver y reactivar SUS servicios ocultos.
    and (
      p_incluir_inactivos
      or not exists (
        select 1
        from flow.entidad_categoria_oculta o
        where o.id_entidad = l.id_entidad
          and (
            o.id_tipo_actividad = ta.id
            or o.id_tipo_actividad = ta.id_padre
          )
      )
    );
$function$
;

CREATE OR REPLACE FUNCTION flow.cliente_planes_suscripcion()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
  select jsonb_build_object(
    'ok', true,
    'data', coalesce(
      (select jsonb_agg(
                jsonb_build_object(
                  'id',            p.id,
                  'codigo',        p.codigo,
                  'nombre',        p.nombre,
                  'descripcion',   p.descripcion,
                  'duracion_dias', p.duracion_dias,
                  'precio',        p.precio,
                  'moneda',        p.moneda,
                  'limites',       p.limites,
                  'orden',         p.orden
                ) order by p.orden, p.precio, p.id)
         from flow.suscripcion_plan p
        where p.activo),
      '[]'::jsonb
    )
  );
$function$
;

CREATE OR REPLACE FUNCTION flow.cliente_ranking_semanal(p_limite integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
  with ventana as (
    select
      a.id_local_servicio,
      -- `greatest(..., 1)`: una reserva con cantidad 0 o nula sigue siendo una
      -- reserva; contarla como 0 la haria desaparecer del ranking.
      sum(greatest(coalesce(a.cantidad, 1), 1))::integer as lugares,
      count(*)::integer                                   as reservas
    from flow.agenda a
    where a.id_estado in (1, 3)
      and a.created_at is not null
      and a.created_at >= date_trunc('week', now())
    group by a.id_local_servicio
  ),
  puntaje as (
    select
      v.id_local_servicio,
      v.lugares,
      v.reservas,
      row_number() over (
        order by v.lugares desc, v.reservas desc, v.id_local_servicio asc
      ) as rn
    from ventana v
  ),
  con_item as (
    select
      jsonb_set(it.value, '{lugares_semana}', to_jsonb(p.lugares)) as item,
      p.rn
    from puntaje p
      join jsonb_array_elements(flow.cliente_home_feed() -> 'items') as it(value)
        on (it.value ->> 'id_local_servicio')::integer = p.id_local_servicio
  )
  select coalesce(jsonb_agg(c.item order by c.rn), '[]'::jsonb)
  from con_item c
  where c.rn <= greatest(p_limite, 1);
$function$
;

CREATE OR REPLACE FUNCTION flow.cliente_reportar_pago_suscripcion(p_id_intent bigint, p_codigo_confirmacion text, p_comprobante_url text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_uid   uuid := auth.uid();
  v_int   flow.suscripcion_intent%rowtype;
  -- Nombre del plan como ESCALAR, no como `%rowtype`: asi "no hay fila" es NULL y
  -- el `coalesce` de los mensajes lo resuelve. Ver el aviso de la migracion 33.
  v_plan_nombre text;
  v_cfg   flow.suscripcion_config%rowtype;
  v_cod   text;
  v_trx   bigint;
  v_owner uuid;
  v_entidad text;
  v_persona text;
  v_mensaje text;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Sesion requerida');
  end if;

  select i.* into v_int from flow.suscripcion_intent i where i.id = p_id_intent;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'El intento de pago no existe');
  end if;

  if not (v_int.uuid_usuario = v_uid
          or flow._susc_caller_ve_entidad(v_int.id_entidad)
          or public.fn_is_superadmin_full_access()) then
    return jsonb_build_object('ok', false, 'error', 'No tiene acceso a este intento de pago');
  end if;

  if exists (select 1 from flow.suscripcion_transaccion t where t.id_intent = v_int.id) then
    return jsonb_build_object('ok', false,
      'error', 'Este intento de pago ya tiene un pago reportado. Espera la verificacion.');
  end if;

  if v_int.estado in ('verificado','rechazado','expirado','cancelado') then
    return jsonb_build_object('ok', false,
      'error', 'Este intento de pago ya no esta vigente (estado: ' || v_int.estado || ')');
  end if;

  if v_int.expira_at <= now() then
    update flow.suscripcion_intent set estado = 'expirado' where id = v_int.id;
    return jsonb_build_object('ok', false,
      'error', 'El intento de pago expiro. Genera uno nuevo.');
  end if;

  v_cod := btrim(coalesce(p_codigo_confirmacion, ''));
  if length(v_cod) < 4 then
    return jsonb_build_object('ok', false,
      'error', 'Escribe el numero de confirmacion que muestra Transfermovil');
  end if;

  -- El UNIQUE de codigo_confirmacion se traduce a un mensaje legible: si no, el
  -- usuario ve un error crudo de Postgres y no entiende que ese pago ya se uso.
  begin
    insert into flow.suscripcion_transaccion
      (id_intent, id_entidad, codigo_confirmacion, monto, moneda, metodo,
       comprobante_url, estado, reportado_por)
    values
      (v_int.id, v_int.id_entidad, v_cod, v_int.monto, v_int.moneda, 'transfermovil',
       nullif(btrim(coalesce(p_comprobante_url, '')), ''), 'reportado', v_uid)
    returning id into v_trx;
  exception
    when unique_violation then
      return jsonb_build_object('ok', false,
        'error', 'Ese numero de confirmacion ya fue usado en otro pago');
  end;

  update flow.suscripcion_intent
     set estado = 'reportado'
   where id = v_int.id and estado in ('creado','abierto');

  select p.nombre into v_plan_nombre from flow.suscripcion_plan p where p.id = v_int.id_plan;

  select c.* into v_cfg from flow.suscripcion_config c where c.id = 1;
  if not found then
    return jsonb_build_object('ok', false,
      'error', 'Falta la configuracion de suscripciones');
  end if;

  select e.owner_uuid, e.denominacion into v_owner, v_entidad
    from flow.entidad e where e.id = v_int.id_entidad;
  select coalesce(pf.nombre || ' ' || pf.apellidos, 'Un administrador')
    into v_persona
    from flow.perfil pf where pf.uuid_usuario = v_uid;
  v_persona := coalesce(v_persona, 'Un administrador');

  -- Aviso in-app a quien reporta y al dueno (si reporto un admin, el dueno igual
  -- tiene que enterarse).
  perform flow._susc_notificar_inapp(
    v_int.id_entidad, v_uid,
    'Pago reportado',
    'Reportamos tu pago del plan ' || coalesce(v_plan_nombre, '') || '. Un administrador lo verificara y acreditara el tiempo.');

  if v_owner is not null and v_owner <> v_uid then
    perform flow._susc_notificar_inapp(
      v_int.id_entidad, v_owner,
      'Pago reportado por un administrador',
      'Se reporto el pago del plan ' || coalesce(v_plan_nombre, '') || ' para la entidad '
        || coalesce(v_entidad, '') || '. Esta pendiente de verificacion.');
  end if;

  -- Mensaje y destinatario del aviso a SOPORTE. Se devuelve tambien a la app para
  -- que el cliente pueda abrir el deep link `wa.me` (Q33: sin bot todavia).
  v_mensaje := 'Yo ' || v_persona || ' he pagado el plan ' || coalesce(v_plan_nombre, '')
            || ' para la entidad ' || coalesce(v_entidad, '')
            || ' por ' || trim(to_char(v_int.monto, 'FM9999999990.00')) || ' ' || v_int.moneda
            || '. Referencia de soporte: ' || v_int.id_transaccion
            || '. Codigo de confirmacion: ' || v_cod
            || '. Espero por la acreditacion del plan. Gracias.';

  perform flow._susc_notificar_whatsapp(
    v_int.id_entidad,
    coalesce(v_cfg.soporte_whatsapp, '5354590207'),
    v_mensaje);

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id_transaccion_pago', v_trx,
      'estado',              'reportado',
      'monto',               v_int.monto,
      'moneda',              v_int.moneda,
      'id_transaccion',      v_int.id_transaccion,
      'codigo_confirmacion', v_cod,
      'soporte_whatsapp',    coalesce(v_cfg.soporte_whatsapp, '5354590207'),
      'mensaje_soporte',     v_mensaje
    )
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.cliente_reservar_directo(p_uuid_usuario uuid, p_id_local_servicio integer, p_fecha date, p_cantidad integer DEFAULT NULL::integer, p_datos_adicionales jsonb DEFAULT NULL::jsonb, p_para_tercero boolean DEFAULT false, p_t_nombre text DEFAULT NULL::text, p_t_apellidos text DEFAULT NULL::text, p_t_ci text DEFAULT NULL::text, p_t_telefono text DEFAULT NULL::text, p_moneda text DEFAULT NULL::text, p_id_turno integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_permite          boolean;
  v_cantidad_default integer;
  v_cantidad_max     integer;
  v_plan_id          bigint;
  v_disponibles      integer;
  v_estado           integer;
  v_id_agenda        integer;
  v_fecha_ts         timestamp without time zone;
  v_titular          uuid;
  v_nombre_servicio  text;
  v_nombre_local     text;
  v_saludo           text;
  v_cant             integer;
  v_id_servicio      integer;
  v_id_entidad       integer;
  v_precio_total     numeric;
  v_moneda           varchar;
  v_desc             jsonb;
  v_cotizacion       jsonb;
  -- BENEFICIO
  v_id_beneficio     integer;
  v_ben_titulo       varchar;
  v_ben_descuento    numeric;
  v_canje_filas      integer;
begin
  if p_uuid_usuario is null or p_id_local_servicio is null or p_fecha is null then
    return jsonb_build_object('ok', false, 'error', 'parametros obligatorios faltantes');
  end if;

  perform pg_advisory_xact_lock(hashtext('flow.sala_espera'), p_id_local_servicio);

  -- BENEFICIO: se anade `l.id_entidad` con left join.
  select ls.permite_reserva_directa, ls.cantidad_default,
         ls.cantidad_max_capacidad, ls.id_servicio, l.id_entidad
    into v_permite, v_cantidad_default, v_cantidad_max, v_id_servicio, v_id_entidad
  from flow.local_servicio ls
  left join flow.app_dat_locales l on l.id = ls.id_local
  where ls.id = p_id_local_servicio;

  if v_permite is null then
    return jsonb_build_object('ok', false, 'error', 'El servicio no existe');
  end if;
  if v_permite is not true then
    return jsonb_build_object('ok', false, 'error', 'Reserva directa no habilitada para este servicio');
  end if;

  if p_id_turno is not null then
    if not exists (
      select 1 from flow.turno t
      join flow.recurso r on r.id = t.id_recurso and r.activo
      where t.id = p_id_turno and t.activo and r.id_local_servicio = p_id_local_servicio
    ) then
      return jsonb_build_object('ok', false, 'error', 'Turno invalido para este servicio');
    end if;
  end if;

  if coalesce(p_para_tercero, false) then
    if not exists (
      select 1 from flow.local_servicio ls
      join flow.app_dat_servicios s on s.id = ls.id_servicio
      where ls.id = p_id_local_servicio and s.permite_tercero = true
    ) then
      return jsonb_build_object('ok', false, 'error', 'Este servicio no permite reservar para terceros');
    end if;
    v_titular := flow._resolver_perfil_tercero(p_t_nombre, p_t_apellidos, p_t_ci, p_t_telefono);
  else
    v_titular := p_uuid_usuario;
  end if;

  v_cant := coalesce(p_cantidad, v_cantidad_default, 1);
  if v_cant < 1 then
    return jsonb_build_object('ok', false, 'error', 'La cantidad debe ser al menos 1');
  end if;
  if v_cant > v_cantidad_max then
    return jsonb_build_object('ok', false, 'error',
      'La cantidad maxima por reserva es ' || v_cantidad_max);
  end if;

  select id into v_estado from flow.nom_estado_agenda where nombre = 'Reservado' limit 1;
  if v_estado is null then
    return jsonb_build_object('ok', false, 'error', 'falta el estado Reservado (correr migracion 03)');
  end if;

  if exists (
    select 1 from flow.agenda a
    where a.uuid_usuario = v_titular
      and a.id_local_servicio = p_id_local_servicio
      and a.id_estado = v_estado
      and (a.fecha_hora_reserva at time zone 'America/Havana')::date = p_fecha
      and a.id_turno is not distinct from p_id_turno
  ) then
    return jsonb_build_object('ok', false, 'error',
      case when v_titular = p_uuid_usuario
           then 'Ya tienes una reserva ese dia'
           else 'Esa persona ya tiene una reserva ese dia' end);
  end if;

  v_fecha_ts := (make_timestamp(extract(year from p_fecha)::int,
                                extract(month from p_fecha)::int,
                                extract(day from p_fecha)::int, 12, 0, 0));

  if p_id_turno is not null then
    v_desc := flow._descontar_tramos_turno(p_id_turno, p_fecha, v_cant);
    if (v_desc ->> 'ok') <> 'true' then
      return jsonb_build_object('ok', false, 'error', v_desc ->> 'error');
    end if;
    -- Transporte: el precio puede venir del turno. Se calcula el precio de
    -- lista por turno y se pasa al MISMO envoltorio que el camino normal, para
    -- que tambien CONSUMA CUPO. Si aqui solo se restara el descuento, el
    -- transporte aplicaria la promo sin gastar cupo y se agotaria infinitas
    -- veces.
    select flow._aplicar_promocion(
             p_id_local_servicio, v_id_servicio,
             cp.precio_total, cp.moneda, cp.precio_unit, true
           )
      into v_cotizacion
    from flow.calcular_precio_turno(
      v_id_servicio, p_id_turno, coalesce(p_datos_adicionales, '{}'::jsonb), p_moneda, v_cant
    ) cp;
  else
    -- ── Camino legacy: plan_servicios ──
    select ps.id, (ps.cantidad - ps.agendados) into v_plan_id, v_disponibles
    from flow.plan_servicios ps
    where ps.id_local_servicio = p_id_local_servicio
      and ps.cantidad is not null
      and ps.agendados < ps.cantidad
      and (ps.fecha at time zone 'America/Havana')::date = p_fecha
    order by ps.id
    limit 1
    for update;

    if v_plan_id is null then
      return jsonb_build_object('ok', false, 'error', 'No hay turnos disponibles');
    end if;
    if v_cant > v_disponibles then
      return jsonb_build_object('ok', false,
        'error', 'No hay suficientes turnos (quedan ' || v_disponibles || ')');
    end if;

    v_cotizacion := flow._precio_con_promocion(
      v_id_servicio, p_id_local_servicio, p_datos_adicionales, p_moneda, v_cant, true
    );
  end if;

  if (v_cotizacion ->> 'ok') = 'false' then
    return jsonb_build_object('ok', false,
      'error', v_cotizacion ->> 'error',
      'codigo', v_cotizacion ->> 'codigo');
  end if;

  v_precio_total := (v_cotizacion ->> 'precio_total')::numeric;
  v_moneda       := (v_cotizacion ->> 'moneda')::varchar;

  -- ── BENEFICIO: reclamo + descuento ──────────────────────────────────────
  -- Despues de las dos ramas, asi que cubre turno y legacy a la vez.
  select b.id_beneficio, b.titulo, b.descuento
    into v_id_beneficio, v_ben_titulo, v_ben_descuento
  from flow._beneficio_bienvenida_aplicable(
    p_uuid_usuario, v_id_entidad, v_moneda, v_precio_total
  ) b;

  if coalesce(v_ben_descuento, 0) > 0 then
    insert into flow.beneficio_canje
      (uuid_usuario, id_beneficio, id_entidad, moneda, monto_descontado)
    values
      (p_uuid_usuario, v_id_beneficio, v_id_entidad, v_moneda, v_ben_descuento)
    on conflict (uuid_usuario) do nothing;

    get diagnostics v_canje_filas = row_count;

    if v_canje_filas = 1 then
      v_precio_total := greatest(v_precio_total - v_ben_descuento, 0);
    else
      -- Otra reserva simultanea se llevo el beneficio: se cobra sin el.
      v_id_beneficio  := null;
      v_ben_titulo    := null;
      v_ben_descuento := 0;
    end if;
  end if;

  insert into flow.agenda
    (uuid_usuario, id_local_servicio, id_estado, fecha_hora_reserva,
     cantidad, datos_adicionales, reservado_por, precio_total, moneda, id_turno)
  values
    (v_titular, p_id_local_servicio, v_estado, v_fecha_ts,
     v_cant, p_datos_adicionales, p_uuid_usuario, v_precio_total, v_moneda, p_id_turno)
  returning id into v_id_agenda;

  -- BENEFICIO: enlazar el canje con la reserva. El insert de arriba no podia
  -- saber el id de la agenda todavia.
  if v_id_beneficio is not null then
    update flow.beneficio_canje
       set id_agenda = v_id_agenda
     where uuid_usuario = p_uuid_usuario
       and id_agenda is null;
  end if;

  if p_id_turno is null then
    update flow.plan_servicios set agendados = agendados + v_cant where id = v_plan_id;
  end if;

  select s.nombre, l.nombre into v_nombre_servicio, v_nombre_local
  from flow.local_servicio ls
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  join flow.app_dat_locales   l on l.id = ls.id_local
  where ls.id = p_id_local_servicio;

  v_saludo := case
    when extract(hour from current_timestamp) between 5 and 11 then 'Buenos dias'
    when extract(hour from current_timestamp) between 12 and 18 then 'Buenas tardes'
    else 'Buenas noches'
  end;

  insert into flow.notificaciones
    (uuid_usuario, tipo, titulo, mensaje, id_local_servicio, id_referencia, data)
  select
    p_uuid_usuario, 'reserva', 'Reservacion confirmada',
    v_saludo || ', '
      || coalesce(nullif(trim(p.nombre || ' ' || p.apellidos), ''), 'estimado cliente')
      || ', se ha realizado satisfactoriamente '
      || case when v_cant > 1 then v_cant || ' reservaciones' else 'su reservacion' end
      || case when coalesce(p_para_tercero, false)
              then ' a nombre de ' || coalesce(nullif(trim(coalesce(p_t_nombre,'') || ' ' || coalesce(p_t_apellidos,'')), ''), 'un tercero')
              else '' end
      || ' para el local "' || coalesce(v_nombre_local, 'local')
      || '" el servicio "' || coalesce(v_nombre_servicio, 'servicio')
      || '" para la fecha ' || to_char(v_fecha_ts, 'DD/MM/YYYY') || '.',
    p_id_local_servicio, v_id_agenda,
    jsonb_build_object('fecha', v_fecha_ts, 'servicio', v_nombre_servicio,
                       'local', v_nombre_local, 'cantidad', v_cant, 'id_turno', p_id_turno)
  from (select 1) x
  left join flow.perfil p on p.uuid_usuario = p_uuid_usuario;

  return jsonb_build_object('ok', true,
    'data', jsonb_build_object(
      'id_agenda', v_id_agenda,
      'fecha',     to_char(v_fecha_ts, 'YYYY-MM-DD'),
      'cantidad',  v_cant,
      'id_turno',  p_id_turno,
      'precio_total', v_precio_total,
      'moneda',       v_moneda,
      -- BENEFICIO: campos nuevos, informativos para la app.
      'descuento_beneficio', coalesce(v_ben_descuento, 0),
      'id_beneficio',        v_id_beneficio,
      'beneficio_titulo',    v_ben_titulo
    ));
exception
  when others then
    return jsonb_build_object('ok', false, 'error', sqlerrm, 'sqlstate', sqlstate);
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.colecciones_activas()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
  with visibles as (
    -- [56] Una fila de `coleccion_servicio` cuenta solo si la entidad de su
    -- local no tiene oculta la categoria del servicio. Es el mismo predicado
    -- que usan el feed y los patrocinados: hoja o padre.
    select
      cs.id_coleccion,
      cs.id_local_servicio,
      cs.orden
    from flow.coleccion_servicio cs
    join flow.local_servicio ls on ls.id = cs.id_local_servicio
    join flow.app_dat_locales l on l.id = ls.id_local
    left join flow.app_dat_servicios s on s.id = ls.id_servicio
    left join flow.nom_tipo_actividad_servicio ta on ta.id = s.id_tipo_actividad
    where not exists (
      select 1
      from flow.entidad_categoria_oculta o
      where o.id_entidad = l.id_entidad
        and (
          o.id_tipo_actividad = ta.id
          or o.id_tipo_actividad = ta.id_padre
        )
    )
  )
  select coalesce(
    jsonb_agg(to_jsonb(t) order by t.orden asc, t.id asc),
    '[]'::jsonb
  )
  from (
    select
      c.id,
      c.titulo,
      c.subtitulo,
      c.icono,
      c.color_inicio,
      c.color_fin,
      c.orden,
      c.hasta,
      (select count(*)
         from visibles v
        where v.id_coleccion = c.id) as total_servicios,
      (select coalesce(
                jsonb_agg(v.id_local_servicio
                          order by v.orden asc, v.id_local_servicio asc),
                '[]'::jsonb)
         from visibles v
        where v.id_coleccion = c.id) as servicios
    from flow.coleccion c
    where c.activo
      and (c.desde is null or (now() at time zone 'America/Havana') >= c.desde)
      and (c.hasta is null or (now() at time zone 'America/Havana') <  c.hasta)
      and exists (select 1 from visibles v where v.id_coleccion = c.id)
  ) t;
$function$
;

CREATE OR REPLACE FUNCTION flow.cotizar_reserva(p_uuid_usuario uuid, p_id_local_servicio integer, p_datos jsonb DEFAULT NULL::jsonb, p_moneda text DEFAULT NULL::text, p_cantidad integer DEFAULT 1, p_id_turno integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_id_servicio   integer;
  v_id_entidad    integer;
  v_lista         numeric;
  v_moneda        varchar;
  v_unit          numeric;
  v_descuento     numeric := 0;
  v_subtotal      numeric;
  v_promo_id      integer;
  v_promo_titulo  varchar;
  v_id_beneficio  integer;
  v_ben_titulo    varchar;
  v_ben_descuento numeric := 0;
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  -- `left join`: si un local no tuviera fila en app_dat_locales, esto no debe
  -- cambiar el mensaje 'El servicio no existe'. Simplemente no habria entidad y
  -- solo aplicarian los beneficios globales.
  select ls.id_servicio, l.id_entidad
    into v_id_servicio, v_id_entidad
  from flow.local_servicio ls
  left join flow.app_dat_locales l on l.id = ls.id_local
  where ls.id = p_id_local_servicio;

  if v_id_servicio is null then
    return jsonb_build_object('ok', false, 'error', 'El servicio no existe');
  end if;

  -- Con turno el precio puede venir del turno (transporte); sin turno, del
  -- servicio. Se obtiene el precio de LISTA por el camino que corresponda.
  if p_id_turno is not null then
    select cp.precio_total, cp.moneda, cp.precio_unit
      into v_lista, v_moneda, v_unit
    from flow.calcular_precio_turno(
      v_id_servicio, p_id_turno, coalesce(p_datos, '{}'::jsonb),
      p_moneda, p_cantidad
    ) cp;
  else
    select cp.precio_total, cp.moneda, cp.precio_unit
      into v_lista, v_moneda, v_unit
    from flow.calcular_precio_reserva(
      v_id_servicio, coalesce(p_datos, '{}'::jsonb), p_moneda, p_cantidad
    ) cp;
  end if;

  v_lista := coalesce(v_lista, 0);

  -- UNA sola resolucion de promocion, igual que al cobrar. Esta funcion no
  -- consume cupo: solo informa de lo que se pagaria ahora mismo.
  --
  -- Se leen escalares y no un `record`: si no hay promo aplicable la consulta
  -- no devuelve filas, y acceder a un campo de un record sin asignar lanza
  -- "record is not assigned yet".
  if v_lista > 0 then
    select pr.id_promocion, pr.descuento, pr.titulo
      into v_promo_id, v_descuento, v_promo_titulo
    from flow._resolver_promocion(p_id_local_servicio, v_id_servicio, v_lista) pr;
    v_descuento := coalesce(v_descuento, 0);
  end if;

  v_subtotal := greatest(v_lista - v_descuento, 0);

  -- Beneficio de bienvenida SOBRE LO QUE QUEDA tras la promocion.
  if v_subtotal > 0 then
    select b.id_beneficio, b.titulo, b.descuento
      into v_id_beneficio, v_ben_titulo, v_ben_descuento
    from flow._beneficio_bienvenida_aplicable(
      p_uuid_usuario, v_id_entidad, v_moneda, v_subtotal
    ) b;
    v_ben_descuento := coalesce(v_ben_descuento, 0);
  end if;

  return jsonb_build_object(
    'ok', true,
    'precio_lista', v_lista,
    'precio_total', greatest(v_subtotal - v_ben_descuento, 0),
    'descuento',    v_descuento,
    'moneda',       coalesce(v_moneda, 'USD'),
    'precio_unit',  coalesce(v_unit, 0),
    'id_promocion', v_promo_id,
    'promo_titulo', v_promo_titulo,
    'descuento_beneficio', v_ben_descuento,
    'id_beneficio',        v_id_beneficio,
    'beneficio_titulo',    v_ben_titulo
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.eliminar_mi_resena(p_uuid_usuario uuid, p_id_resena bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'flow', 'public'
AS $function$
begin
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  delete from flow.resena
   where id = p_id_resena and uuid_usuario = p_uuid_usuario;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'Resena inexistente o no es tuya');
  end if;

  return jsonb_build_object('ok', true);
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.entidad_activa(p_id_entidad integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
  select coalesce((
    select case
             -- Estados que significan "no hay derecho": inactiva sin mirar fechas.
             when s.estado in ('vencida','sin_plan','suspendida','cancelada')
               then false
             -- Estados vivos: manda la fecha. `fecha_gracia_fin` es el corte real.
             else coalesce(s.fecha_gracia_fin, s.fecha_vencimiento) > now()
           end
    from flow.suscripcion s
    where s.id_entidad = p_id_entidad
    order by
      -- Primero las filas vivas (si hay una, es la que gobierna); despues la
      -- mas reciente. El indice unico parcial de la 43 garantiza que haya a lo
      -- sumo UNA viva.
      (s.estado in ('trial','activa','en_gracia','sin_plan','suspendida')) desc,
      s.updated_at desc,
      s.id desc
    limit 1
  ), true);   -- SIN FILA = ACTIVA (grandfathering: ver cabecera)
$function$
;

CREATE OR REPLACE FUNCTION flow.es_admin_de_la_imagen(p_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
  with partes as (
    select
      split_part(p_name, '/', 1) as carpeta,
      -- El nombre del archivo es el id, con o sin extensión: '12.jpg' -> 12.
      nullif(regexp_replace(split_part(p_name, '/', 2), '[^0-9]', '', 'g'), '')::int as id
  )
  select coalesce(
    case
      when p.carpeta = 'locales' then exists (
        select 1
        from flow.app_dat_locales l
        where l.id = p.id
          and flow.is_entidad_admin(l.id_entidad)
      )
      when p.carpeta = 'servicios' then exists (
        select 1
        from flow.app_dat_servicios s
        where s.id = p.id
          and flow.is_entidad_admin(s.id_entidad)
      )
      else false
    end,
    false
  )
  from partes p;
$function$
;

CREATE OR REPLACE FUNCTION flow.fn_saldo_puntos(p_uuid_usuario uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
  select coalesce(sum(m.puntos), 0)::integer
  from flow.puntos_movimiento m
  where m.uuid_usuario = p_uuid_usuario
    and not (
      m.tipo = 'acumulacion'
      and m.liquidado = false
      and m.vence_en is not null
      and m.vence_en <= current_timestamp
    );
$function$
;

CREATE OR REPLACE FUNCTION flow.promociones_de_servicio(p_id_local_servicio integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
  select coalesce(jsonb_agg(to_jsonb(t) order by t.descuento_pct desc nulls last), '[]'::jsonb)
  from (
    select
      pr.id,
      pr.titulo,
      pr.descripcion,
      pr.tipo,
      pr.valor,
      pr.moneda,
      pr.desde,
      pr.hasta,
      pr.cupo_total,
      pr.cupo_usado,
      case when pr.cupo_total is null then null
           else greatest(pr.cupo_total - pr.cupo_usado, 0) end as cupos_restantes,
      case when pr.tipo = 'porcentaje' then pr.valor else null end as descuento_pct
    from flow.promocion pr
    where pr.activo
      and (pr.desde is null or (now() at time zone 'America/Havana') >= pr.desde)
      and (pr.hasta is null or (now() at time zone 'America/Havana') <  pr.hasta)
      and (pr.cupo_total is null or pr.cupo_usado < pr.cupo_total)
      and (
        pr.id_local_servicio = p_id_local_servicio
        -- Promos de entidad: la entidad se toma del servicio consultado, no del
        -- registro de la promo (que en ese caso tiene id_local_servicio null).
        or (
          pr.id_entidad is not null
          and pr.id_entidad = (
            select l.id_entidad
            from flow.local_servicio ls
            join flow.app_dat_locales l on l.id = ls.id_local
            where ls.id = p_id_local_servicio
          )
        )
      )
  ) t;
$function$
;

CREATE OR REPLACE FUNCTION flow.promociones_por_servicio()
 RETURNS TABLE(id_local_servicio integer, id integer, titulo character varying, tipo character varying, valor numeric, moneda character varying, hasta timestamp with time zone, cupos_restantes integer)
 LANGUAGE sql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
  with candidatas as (
    select
      ls.id as id_local_servicio,
      pr.id, pr.titulo, pr.tipo, pr.valor, pr.moneda, pr.hasta,
      -- 0 = promo propia del servicio, 1 = promo de la entidad. Se prefiere la
      -- propia: es mas especifica.
      case when pr.id_local_servicio = ls.id then 0 else 1 end as prioridad,
      case when pr.tipo = 'porcentaje' then pr.valor else 0 end as pct,
      case when pr.cupo_total is null then null
           else greatest(pr.cupo_total - pr.cupo_usado, 0) end as cupos_restantes,
      row_number() over (
        partition by ls.id
        order by
          case when pr.id_local_servicio = ls.id then 0 else 1 end asc,
          case when pr.tipo = 'porcentaje' then pr.valor else 0 end desc,
          pr.id asc
      ) as orden
    from flow.local_servicio ls
    join flow.app_dat_locales l on l.id = ls.id_local
    join flow.promocion pr
      on pr.activo
     and (pr.desde is null or (now() at time zone 'America/Havana') >= pr.desde)
     and (pr.hasta is null or (now() at time zone 'America/Havana') <  pr.hasta)
     and (pr.cupo_total is null or pr.cupo_usado < pr.cupo_total)
     and (
       pr.id_local_servicio = ls.id
       or (pr.id_entidad is not null and pr.id_entidad = l.id_entidad)
     )
  )
  select
    id_local_servicio, id, titulo, tipo, valor, moneda, hasta, cupos_restantes
  from candidatas
  where orden = 1;
$function$
;

CREATE OR REPLACE FUNCTION flow.publicar_resena(p_uuid_usuario uuid, p_id_agenda integer, p_puntuacion smallint, p_comentario text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_agenda      record;
  v_comentario  text;
  v_id          bigint;
begin
  if p_uuid_usuario is null or p_id_agenda is null then
    return jsonb_build_object('ok', false, 'error', 'Faltan parametros');
  end if;

  -- El uuid debe ser el de la sesion: recibirlo por parametro es suplantable.
  if auth.uid() is distinct from p_uuid_usuario then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  if p_puntuacion is null or p_puntuacion < 1 or p_puntuacion > 5 then
    return jsonb_build_object('ok', false, 'error', 'La puntuacion debe ser de 1 a 5');
  end if;

  v_comentario := nullif(btrim(coalesce(p_comentario, '')), '');
  if v_comentario is not null and length(v_comentario) > 1000 then
    return jsonb_build_object('ok', false, 'error', 'El comentario es demasiado largo (max 1000)');
  end if;

  -- `agenda` bajo RLS solo deja ver las propias, asi que este SELECT ya filtra.
  select a.id, a.id_local_servicio, a.uuid_usuario, a.reservado_por, e.nombre as estado
    into v_agenda
  from flow.agenda a
  join flow.nom_estado_agenda e on e.id = a.id_estado
  where a.id = p_id_agenda;

  if v_agenda.id is null then
    return jsonb_build_object('ok', false, 'error', 'La reserva no existe o no es tuya');
  end if;

  if v_agenda.estado <> 'Completado' then
    return jsonb_build_object(
      'ok', false,
      'error', 'Solo puedes resenar un servicio que ya te atendieron'
    );
  end if;

  insert into flow.resena (
    id_agenda, id_local_servicio, uuid_usuario, puntuacion, comentario
  )
  values (
    p_id_agenda, v_agenda.id_local_servicio, p_uuid_usuario, p_puntuacion, v_comentario
  )
  on conflict (id_agenda) do update
    set puntuacion = excluded.puntuacion,
        comentario = excluded.comentario,
        updated_at = current_timestamp
  returning id into v_id;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id', v_id,
      'id_agenda', p_id_agenda,
      'id_local_servicio', v_agenda.id_local_servicio
    )
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.resenas_de_servicio(p_id_local_servicio integer, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_result jsonb;
begin
  -- Definir salta RLS: la autorizacion se hace aqui.
  if coalesce(auth.role(), 'anon') <> 'authenticated' then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  with mias as (
    select r.id, r.id_agenda, r.puntuacion, r.comentario, r.created_at
    from flow.resena r
    where r.id_local_servicio = p_id_local_servicio
      and r.uuid_usuario = auth.uid()
    limit 1
  ),
  resenable as (
    select
      a.id as id_agenda,
      coalesce(a.fecha_hora_atencion, a.fecha_hora_reserva) as atendido
    from flow.agenda a
    join flow.nom_estado_agenda e on e.id = a.id_estado
    where a.id_local_servicio = p_id_local_servicio
      and e.nombre = 'Completado'
      -- Filtro explicito en SQL: como definer se ven TODAS las agendas, asi que
      -- la restriccion a las propias tiene que estar aqui, no en RLS.
      and (a.uuid_usuario = auth.uid() or a.reservado_por = auth.uid())
      and not exists (select 1 from flow.resena r where r.id_agenda = a.id)
    order by coalesce(a.fecha_hora_atencion, a.fecha_hora_reserva) desc
    limit 1
  ),
  listado as (
    select
      r.id,
      r.puntuacion,
      r.comentario,
      r.created_at,
      case
        when p.nombre is null then 'Cliente'
        when p.apellidos is null or btrim(p.apellidos) = '' then btrim(p.nombre)
        else btrim(p.nombre) || ' ' || upper(left(btrim(p.apellidos), 1)) || '.'
      end as autor,
      (r.uuid_usuario = auth.uid()) as es_mia
    from flow.resena r
    left join flow.perfil p on p.uuid_usuario = r.uuid_usuario
    where r.id_local_servicio = p_id_local_servicio
    order by r.created_at desc
    limit greatest(1, least(coalesce(p_limit, 20), 50))
    offset greatest(0, coalesce(p_offset, 0))
  )
  select jsonb_build_object(
    'ok', true,
    'resumen', (
      select jsonb_build_object(
        'total',     count(*),
        'promedio',  coalesce(round(avg(puntuacion)::numeric, 1), 0),
        'estrellas', jsonb_build_object(
          '5', count(*) filter (where puntuacion = 5),
          '4', count(*) filter (where puntuacion = 4),
          '3', count(*) filter (where puntuacion = 3),
          '2', count(*) filter (where puntuacion = 2),
          '1', count(*) filter (where puntuacion = 1)
        )
      )
      from flow.resena
      where id_local_servicio = p_id_local_servicio
    ),
    'items', coalesce(
      (select jsonb_agg(to_jsonb(l) order by l.created_at desc) from listado l),
      '[]'::jsonb
    ),
    'mi_resena', (select to_jsonb(m) from mias m),
    'agenda_resenable', (select to_jsonb(x) from resenable x)
  ) into v_result;

  return v_result;
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.resenas_por_servicio()
 RETURNS TABLE(id_local_servicio integer, total bigint, promedio numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'flow', 'public'
AS $function$
  select r.id_local_servicio, count(*)::bigint,
         round(avg(r.puntuacion)::numeric, 1)
  from flow.resena r
  group by r.id_local_servicio
  order by r.id_local_servicio;
$function$
;

CREATE OR REPLACE FUNCTION flow.resenas_recientes(p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_result jsonb;
begin
  if coalesce(auth.role(), 'anon') <> 'authenticated' then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc), '[]'::jsonb)
    into v_result
  from (
    select
      r.id,
      r.puntuacion,
      r.comentario,
      r.created_at,
      r.id_local_servicio,
      s.nombre as servicio,
      l.nombre as local,
      case
        when p.nombre is null then 'Cliente'
        when p.apellidos is null or btrim(p.apellidos) = '' then btrim(p.nombre)
        else btrim(p.nombre) || ' ' || upper(left(btrim(p.apellidos), 1)) || '.'
      end as autor
    from flow.resena r
    join flow.local_servicio ls on ls.id = r.id_local_servicio
    join flow.app_dat_servicios s on s.id = ls.id_servicio
    join flow.app_dat_locales l on l.id = ls.id_local
    left join flow.perfil p on p.uuid_usuario = r.uuid_usuario
    where r.comentario is not null
    order by r.created_at desc
    limit greatest(1, least(coalesce(p_limit, 5), 20))
  ) t;

  return jsonb_build_object('ok', true, 'data', v_result);
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.suscripcion_expirar()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_cfg     flow.suscripcion_config%rowtype;
  v_r       record;
  v_avisos  integer := 0;
  v_gracia  integer := 0;
  v_venc    integer := 0;
  v_intents integer := 0;
  v_owner   uuid;
begin
  select c.* into v_cfg from flow.suscripcion_config c where c.id = 1;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'Falta flow.suscripcion_config');
  end if;

  -- 1) Aviso "vence pronto", una sola vez por suscripcion (aviso_previo_at).
  for v_r in
    select s.id, s.id_entidad, s.fecha_vencimiento
    from flow.suscripcion s
    where s.estado in ('trial','activa')
      and s.aviso_previo_at is null
      and s.fecha_vencimiento > now()
      and s.fecha_vencimiento <= now()
          + make_interval(days => coalesce(v_cfg.dias_aviso_previo, 7))
  loop
    update flow.suscripcion set aviso_previo_at = now() where id = v_r.id;

    select e.owner_uuid into v_owner from flow.entidad e where e.id = v_r.id_entidad;
    perform flow._susc_notificar_inapp(
      v_r.id_entidad, v_owner,
      'Tu suscripcion vence pronto',
      'La suscripcion de tu entidad vence el '
        || to_char(v_r.fecha_vencimiento, 'DD/MM/YYYY')
        || '. Tienes ' || coalesce(v_cfg.dias_gracia, 7)
        || ' dia(s) de gracia despues de esa fecha.');

    v_avisos := v_avisos + 1;
  end loop;

  -- 2) Vencidas dentro de la gracia -> 'en_gracia'.
  for v_r in
    select s.id, s.id_entidad from flow.suscripcion s
    where s.estado in ('trial','activa')
      and s.fecha_vencimiento <= now()
      and coalesce(s.fecha_gracia_fin, s.fecha_vencimiento) > now()
  loop
    update flow.suscripcion set estado = 'en_gracia' where id = v_r.id;

    select e.owner_uuid into v_owner from flow.entidad e where e.id = v_r.id_entidad;
    perform flow._susc_notificar_inapp(
      v_r.id_entidad, v_owner,
      'Suscripcion vencida, en gracia',
      'La suscripcion vencio. Tu entidad seguira activa durante el margen de gracia; '
        || 'regulariza el pago para no perder visibilidad.');

    v_gracia := v_gracia + 1;
  end loop;

  -- 3) Fuera de la gracia -> 'vencida'. A partir de aqui `entidad_activa` es
  --    false y los locales y servicios de la entidad dejan de mostrarse.
  for v_r in
    select s.id, s.id_entidad from flow.suscripcion s
    where s.estado in ('trial','activa','en_gracia')
      and coalesce(s.fecha_gracia_fin, s.fecha_vencimiento) <= now()
  loop
    update flow.suscripcion set estado = 'vencida' where id = v_r.id;

    insert into flow.suscripcion_movimiento
      (id_entidad, id_suscripcion, tipo, dias, motivo)
    values
      (v_r.id_entidad, v_r.id, 'expiracion', 0,
       'Suscripcion vencida: se agoto el margen de gracia');

    select e.owner_uuid into v_owner from flow.entidad e where e.id = v_r.id_entidad;
    perform flow._susc_notificar_inapp(
      v_r.id_entidad, v_owner,
      'Suscripcion vencida',
      'Se agoto el margen de gracia: la entidad, sus locales y sus servicios '
        || 'dejaron de mostrarse y no admiten reservas. Compra un plan para reactivarla.');

    v_venc := v_venc + 1;
  end loop;

  -- 4) Intents caducados. Se marcan para que la UI no ofrezca pagar un enlace
  --    que Transfermovil ya no acepta.
  update flow.suscripcion_intent
     set estado = 'expirado'
   where estado in ('creado','abierto')
     and expira_at <= now();
  get diagnostics v_intents = row_count;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'avisos_enviados',   v_avisos,
      'pasadas_a_gracia',  v_gracia,
      'vencidas',          v_venc,
      'intents_expirados', v_intents
    )
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.trg_agenda_acreditar_puntos()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
declare
  v_id_completado integer;
begin
  select id into v_id_completado
  from flow.nom_estado_agenda
  where nombre = 'Completado';

  if v_id_completado is null then
    return new;
  end if;

  if new.id_estado = v_id_completado
     and old.id_estado is distinct from v_id_completado then
    perform flow._acreditar_puntos_agenda(new.id);
  end if;

  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.validar_jerarquia_tipo_actividad()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'flow', 'public'
AS $function$
begin
  if new.id_padre is not null then
    if new.id_padre = new.id then
      raise exception 'Una categoria no puede ser su propio padre';
    end if;

    if exists (
      select 1 from flow.nom_tipo_actividad_servicio p
      where p.id = new.id_padre and p.id_padre is not null
    ) then
      raise exception
        'Solo se admiten dos niveles: una subcategoria no puede tener subcategorias';
    end if;

    if tg_op = 'UPDATE' and exists (
      select 1 from flow.nom_tipo_actividad_servicio h
      where h.id_padre = new.id
    ) then
      raise exception
        'Esta categoria ya tiene subcategorias: no puede convertirse en subcategoria';
    end if;
  end if;

  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION flow.vendedor_listar_agendas(p_uuid_usuario uuid, p_id_entidad integer DEFAULT NULL::integer, p_id_local integer DEFAULT NULL::integer, p_id_local_servicio integer DEFAULT NULL::integer, p_id_estado integer DEFAULT NULL::integer, p_desde timestamp without time zone DEFAULT NULL::timestamp without time zone, p_hasta timestamp without time zone DEFAULT NULL::timestamp without time zone)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',                  a.id,
        'fecha_hora_reserva',  a.fecha_hora_reserva,
        'fecha_hora_atencion', a.fecha_hora_atencion,
        'created_at',          a.created_at,
        'updated_at',          a.updated_at,
        'cantidad',            a.cantidad,
        'datos_adicionales',   a.datos_adicionales,
        'reservado_por',       a.reservado_por,
        'precio_total',        a.precio_total,
        'moneda',              a.moneda,
        'id_estado',           a.id_estado,
        'id_turno',            a.id_turno,
        'id_viaje',            a.id_viaje,
        'tipo_trayecto',       a.tipo_trayecto,
        'turno', case when t.id is null then null else jsonb_build_object(
          'id',     t.id,
          'nombre', t.nombre,
          'recurso', jsonb_build_object('id', r.id, 'nombre', r.nombre)
        ) end,
        'estado', jsonb_build_object(
          'id',          es.id,
          'nombre',      es.nombre,
          'descripcion', es.descripcion
        ),
        'id_local_servicio', ls.id,
        'servicio', jsonb_build_object(
          'id',                 s.id,
          'nombre',             s.nombre,
          'descripcion',        s.descripcion,
          'foto',               s.foto,
          'campos_adicionales', s.campos_adicionales
        ),
        'local', jsonb_build_object(
          'id',               l.id,
          'nombre',           l.nombre,
          'direccion',        l.direccion,
          'pais',             l.pais,
          'provincia',        l.provincia,
          'horario_atencion', l.horario_atencion,
          'coordenadas',      l.coordenadas,
          'foto',             l.foto
        ),
        'entidad', jsonb_build_object(
          'id',           en.id,
          'denominacion', en.denominacion,
          'direccion',    en.direccion,
          'telefono',     en.telefono
        ),
        'cliente', case when p.id is null then null else jsonb_build_object(
          'id',           p.id,
          'uuid_usuario', p.uuid_usuario,
          'nombre',       p.nombre,
          'apellidos',    p.apellidos,
          'ci',           p.ci,
          'telefono',     p.telefono,
          'created_at',   p.created_at,
          'updated_at',   p.updated_at
        ) end
      )
      order by a.fecha_hora_reserva desc
    ),
    '[]'::jsonb
  )
  from flow.agenda a
  join flow.local_servicio    ls on ls.id = a.id_local_servicio
  join flow.app_dat_locales   l  on l.id  = ls.id_local
  join flow.app_dat_servicios s  on s.id  = ls.id_servicio
  join flow.entidad           en on en.id = l.id_entidad
  join flow.nom_estado_agenda es on es.id = a.id_estado
  left join flow.perfil       p  on p.uuid_usuario = a.uuid_usuario
  left join flow.turno        t  on t.id = a.id_turno
  left join flow.recurso      r  on r.id = t.id_recurso
  join flow.entidad_vendedor  ev on ev.id_entidad  = l.id_entidad
                                and ev.uuid_usuario = auth.uid()
  where (p_id_entidad        is null or l.id_entidad         = p_id_entidad)
    and (p_id_local          is null or ls.id_local          = p_id_local)
    and (p_id_local_servicio is null or a.id_local_servicio  = p_id_local_servicio)
    and (p_id_estado         is null or a.id_estado          = p_id_estado)
    and (p_desde             is null or a.fecha_hora_reserva >= p_desde)
    and (p_hasta             is null or a.fecha_hora_reserva <= p_hasta);
$function$
;

CREATE OR REPLACE FUNCTION flow.vendedor_listar_agendas_por_estado(p_uuid_usuario uuid, p_id_entidad integer DEFAULT NULL::integer, p_id_local integer DEFAULT NULL::integer, p_id_local_servicio integer DEFAULT NULL::integer, p_id_estado integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'flow', 'public'
AS $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',                  a.id,
        'uuid_usuario',        a.uuid_usuario,
        'id_estado',           a.id_estado,
        'fecha_hora_reserva',  a.fecha_hora_reserva,
        'fecha_hora_atencion', a.fecha_hora_atencion,
        'created_at',          a.created_at,
        'updated_at',          a.updated_at,
        'cantidad',            a.cantidad,
        'datos_adicionales',   a.datos_adicionales,
        'reservado_por',       a.reservado_por,
        'precio_total',        a.precio_total,
        'moneda',              a.moneda,
        'id_turno',            a.id_turno,
        'id_viaje',            a.id_viaje,
        'tipo_trayecto',       a.tipo_trayecto,
        'turno', case when t.id is null then null else jsonb_build_object(
          'id',     t.id,
          'nombre', t.nombre,
          'recurso', jsonb_build_object('id', r.id, 'nombre', r.nombre)
        ) end,
        'estado', jsonb_build_object(
          'id',          es.id,
          'nombre',      es.nombre,
          'descripcion', es.descripcion
        ),
        'id_local_servicio', ls.id,
        'servicio', jsonb_build_object(
          'id',                 s.id,
          'nombre',             s.nombre,
          'descripcion',        s.descripcion,
          'foto',               s.foto,
          'campos_adicionales', s.campos_adicionales,
          'config_precio',      s.config_precio
        ),
        'local', jsonb_build_object(
          'id',               l.id,
          'nombre',           l.nombre,
          'direccion',        l.direccion,
          'pais',             l.pais,
          'provincia',        l.provincia,
          'horario_atencion', l.horario_atencion,
          'coordenadas',      l.coordenadas,
          'foto',             l.foto
        ),
        'entidad', jsonb_build_object(
          'id',           en.id,
          'denominacion', en.denominacion,
          'direccion',    en.direccion,
          'telefono',     en.telefono
        ),
        'cliente', case when p.id is null then null else jsonb_build_object(
          'id',           p.id,
          'uuid_usuario', p.uuid_usuario,
          'nombre',       p.nombre,
          'apellidos',    p.apellidos,
          'ci',           p.ci,
          'telefono',     p.telefono,
          'created_at',   p.created_at,
          'updated_at',   p.updated_at
        ) end
      )
      order by a.fecha_hora_reserva desc
    ),
    '[]'::jsonb
  )
  from flow.agenda a
  join flow.local_servicio    ls on ls.id = a.id_local_servicio
  join flow.app_dat_locales   l  on l.id  = ls.id_local
  join flow.app_dat_servicios s  on s.id  = ls.id_servicio
  join flow.entidad           en on en.id = l.id_entidad
  join flow.nom_estado_agenda es on es.id = a.id_estado
  left join flow.perfil       p  on p.uuid_usuario = a.uuid_usuario
  left join flow.turno        t  on t.id = a.id_turno
  left join flow.recurso      r  on r.id = t.id_recurso
  join flow.entidad_vendedor  ev on ev.id_entidad  = l.id_entidad
                                and ev.uuid_usuario = auth.uid()
  where (p_id_entidad        is null or l.id_entidad         = p_id_entidad)
    and (p_id_local          is null or ls.id_local          = p_id_local)
    and (p_id_local_servicio is null or a.id_local_servicio  = p_id_local_servicio)
    and (p_id_estado         is null or a.id_estado          = p_id_estado)
    and a.fecha_hora_reserva::date >= (timezone('America/Havana', now()))::date;
$function$
;


-- ============================================================
-- 8. Checks y claves foraneas
-- ============================================================
ALTER TABLE flow.agenda DROP CONSTRAINT IF EXISTS agenda_tipo_trayecto_check;
ALTER TABLE flow.agenda ADD CONSTRAINT agenda_tipo_trayecto_check CHECK (((tipo_trayecto IS NULL) OR ((tipo_trayecto)::text = ANY ((ARRAY['ida'::character varying, 'vuelta'::character varying])::text[]))));
ALTER TABLE flow.app_dat_locales DROP CONSTRAINT IF EXISTS locales_horario_detalle_chk;
ALTER TABLE flow.app_dat_locales ADD CONSTRAINT locales_horario_detalle_chk CHECK (((horario_detalle IS NULL) OR ((jsonb_typeof(horario_detalle) = 'object'::text) AND (jsonb_typeof((horario_detalle -> 'dias'::text)) = 'array'::text) AND ((jsonb_array_length((horario_detalle -> 'dias'::text)) >= 1) AND (jsonb_array_length((horario_detalle -> 'dias'::text)) <= 7)) AND ((horario_detalle ->> 'apertura'::text) ~ '^[0-2][0-9]:[0-5][0-9]$'::text) AND ((horario_detalle ->> 'cierre'::text) ~ '^[0-2][0-9]:[0-5][0-9]$'::text))));
ALTER TABLE flow.beneficio_bienvenida DROP CONSTRAINT IF EXISTS beneficio_bienvenida_tipo_chk;
ALTER TABLE flow.beneficio_bienvenida ADD CONSTRAINT beneficio_bienvenida_tipo_chk CHECK (((tipo)::text = ANY ((ARRAY['porcentaje'::character varying, 'monto'::character varying])::text[])));
ALTER TABLE flow.beneficio_bienvenida DROP CONSTRAINT IF EXISTS beneficio_bienvenida_valor_pos;
ALTER TABLE flow.beneficio_bienvenida ADD CONSTRAINT beneficio_bienvenida_valor_pos CHECK ((valor > (0)::numeric));
ALTER TABLE flow.campana DROP CONSTRAINT IF EXISTS campana_alcance_check;
ALTER TABLE flow.campana ADD CONSTRAINT campana_alcance_check CHECK (((id_local_servicio IS NOT NULL) OR (id_entidad IS NOT NULL)));
ALTER TABLE flow.campana DROP CONSTRAINT IF EXISTS campana_vigencia_check;
ALTER TABLE flow.campana ADD CONSTRAINT campana_vigencia_check CHECK (((desde IS NULL) OR (hasta IS NULL) OR (desde < hasta)));
ALTER TABLE flow.fidelidad_config DROP CONSTRAINT IF EXISTS fidelidad_config_fila_unica;
ALTER TABLE flow.fidelidad_config ADD CONSTRAINT fidelidad_config_fila_unica CHECK ((id = 1));
ALTER TABLE flow.local_servicio DROP CONSTRAINT IF EXISTS local_servicio_modo_chk;
ALTER TABLE flow.local_servicio ADD CONSTRAINT local_servicio_modo_chk CHECK (((NOT solo_turnos) OR sin_tramos));
ALTER TABLE flow.nom_tipo_actividad_servicio DROP CONSTRAINT IF EXISTS nom_tipo_actividad_servicio_no_autopadre;
ALTER TABLE flow.nom_tipo_actividad_servicio ADD CONSTRAINT nom_tipo_actividad_servicio_no_autopadre CHECK (((id_padre IS NULL) OR (id_padre <> id)));
ALTER TABLE flow.promocion DROP CONSTRAINT IF EXISTS promocion_alcance_check;
ALTER TABLE flow.promocion ADD CONSTRAINT promocion_alcance_check CHECK (((id_local_servicio IS NULL) <> (id_entidad IS NULL)));
ALTER TABLE flow.promocion DROP CONSTRAINT IF EXISTS promocion_cupo_check;
ALTER TABLE flow.promocion ADD CONSTRAINT promocion_cupo_check CHECK (((cupo_total IS NULL) OR ((cupo_total > 0) AND (cupo_usado >= 0) AND (cupo_usado <= cupo_total))));
ALTER TABLE flow.promocion DROP CONSTRAINT IF EXISTS promocion_moneda_check;
ALTER TABLE flow.promocion ADD CONSTRAINT promocion_moneda_check CHECK ((((tipo)::text <> 'monto'::text) OR ((moneda IS NOT NULL) AND (btrim((moneda)::text) <> ''::text))));
ALTER TABLE flow.promocion DROP CONSTRAINT IF EXISTS promocion_tipo_check;
ALTER TABLE flow.promocion ADD CONSTRAINT promocion_tipo_check CHECK (((tipo)::text = ANY ((ARRAY['porcentaje'::character varying, 'monto'::character varying])::text[])));
ALTER TABLE flow.promocion DROP CONSTRAINT IF EXISTS promocion_valor_check;
ALTER TABLE flow.promocion ADD CONSTRAINT promocion_valor_check CHECK (((valor > (0)::numeric) AND (((tipo)::text <> 'porcentaje'::text) OR (valor <= (100)::numeric))));
ALTER TABLE flow.promocion DROP CONSTRAINT IF EXISTS promocion_vigencia_check;
ALTER TABLE flow.promocion ADD CONSTRAINT promocion_vigencia_check CHECK (((desde IS NULL) OR (hasta IS NULL) OR (desde < hasta)));
ALTER TABLE flow.puntos_movimiento DROP CONSTRAINT IF EXISTS puntos_movimiento_tipo_chk;
ALTER TABLE flow.puntos_movimiento ADD CONSTRAINT puntos_movimiento_tipo_chk CHECK (((tipo)::text = ANY ((ARRAY['acumulacion'::character varying, 'canje'::character varying, 'vencimiento'::character varying, 'ajuste'::character varying])::text[])));
ALTER TABLE flow.regla_fidelidad DROP CONSTRAINT IF EXISTS regla_fidelidad_monto_base_pos;
ALTER TABLE flow.regla_fidelidad ADD CONSTRAINT regla_fidelidad_monto_base_pos CHECK ((monto_base > (0)::numeric));
ALTER TABLE flow.regla_fidelidad DROP CONSTRAINT IF EXISTS regla_fidelidad_puntos_no_neg;
ALTER TABLE flow.regla_fidelidad ADD CONSTRAINT regla_fidelidad_puntos_no_neg CHECK ((puntos_por_monto >= (0)::numeric));
ALTER TABLE flow.regla_fidelidad DROP CONSTRAINT IF EXISTS regla_fidelidad_vigencia_pos;
ALTER TABLE flow.regla_fidelidad ADD CONSTRAINT regla_fidelidad_vigencia_pos CHECK (((vigencia_dias IS NULL) OR (vigencia_dias > 0)));
ALTER TABLE flow.resena DROP CONSTRAINT IF EXISTS resena_comentario_longitud;
ALTER TABLE flow.resena ADD CONSTRAINT resena_comentario_longitud CHECK (((comentario IS NULL) OR (length(comentario) <= 1000)));
ALTER TABLE flow.resena DROP CONSTRAINT IF EXISTS resena_comentario_no_vacio;
ALTER TABLE flow.resena ADD CONSTRAINT resena_comentario_no_vacio CHECK (((comentario IS NULL) OR (length(btrim(comentario)) > 0)));
ALTER TABLE flow.resena DROP CONSTRAINT IF EXISTS resena_puntuacion_check;
ALTER TABLE flow.resena ADD CONSTRAINT resena_puntuacion_check CHECK (((puntuacion >= 1) AND (puntuacion <= 5)));
ALTER TABLE flow.suscripcion DROP CONSTRAINT IF EXISTS suscripcion_estado_check;
ALTER TABLE flow.suscripcion ADD CONSTRAINT suscripcion_estado_check CHECK ((estado = ANY (ARRAY['trial'::text, 'activa'::text, 'en_gracia'::text, 'vencida'::text, 'sin_plan'::text, 'suspendida'::text, 'cancelada'::text])));
ALTER TABLE flow.suscripcion DROP CONSTRAINT IF EXISTS suscripcion_origen_check;
ALTER TABLE flow.suscripcion ADD CONSTRAINT suscripcion_origen_check CHECK ((origen = ANY (ARRAY['trial'::text, 'compra'::text, 'acreditacion_admin'::text, 'promocion'::text])));
ALTER TABLE flow.suscripcion_config DROP CONSTRAINT IF EXISTS suscripcion_config_dias_aviso_previo_check;
ALTER TABLE flow.suscripcion_config ADD CONSTRAINT suscripcion_config_dias_aviso_previo_check CHECK (((dias_aviso_previo >= 0) AND (dias_aviso_previo <= 90)));
ALTER TABLE flow.suscripcion_config DROP CONSTRAINT IF EXISTS suscripcion_config_dias_gracia_check;
ALTER TABLE flow.suscripcion_config ADD CONSTRAINT suscripcion_config_dias_gracia_check CHECK (((dias_gracia >= 0) AND (dias_gracia <= 90)));
ALTER TABLE flow.suscripcion_config DROP CONSTRAINT IF EXISTS suscripcion_config_fila_unica;
ALTER TABLE flow.suscripcion_config ADD CONSTRAINT suscripcion_config_fila_unica CHECK ((id = 1));
ALTER TABLE flow.suscripcion_config DROP CONSTRAINT IF EXISTS suscripcion_config_intent_horas_vigencia_check;
ALTER TABLE flow.suscripcion_config ADD CONSTRAINT suscripcion_config_intent_horas_vigencia_check CHECK (((intent_horas_vigencia >= 1) AND (intent_horas_vigencia <= 720)));
ALTER TABLE flow.suscripcion_config DROP CONSTRAINT IF EXISTS suscripcion_config_trial_meses_default_check;
ALTER TABLE flow.suscripcion_config ADD CONSTRAINT suscripcion_config_trial_meses_default_check CHECK (((trial_meses_default >= 0) AND (trial_meses_default <= 24)));
ALTER TABLE flow.suscripcion_intent DROP CONSTRAINT IF EXISTS suscripcion_intent_estado_check;
ALTER TABLE flow.suscripcion_intent ADD CONSTRAINT suscripcion_intent_estado_check CHECK ((estado = ANY (ARRAY['creado'::text, 'abierto'::text, 'reportado'::text, 'verificado'::text, 'rechazado'::text, 'expirado'::text, 'cancelado'::text])));
ALTER TABLE flow.suscripcion_intent DROP CONSTRAINT IF EXISTS suscripcion_intent_monto_check;
ALTER TABLE flow.suscripcion_intent ADD CONSTRAINT suscripcion_intent_monto_check CHECK ((monto >= (0)::numeric));
ALTER TABLE flow.suscripcion_movimiento DROP CONSTRAINT IF EXISTS suscripcion_movimiento_tipo_check;
ALTER TABLE flow.suscripcion_movimiento ADD CONSTRAINT suscripcion_movimiento_tipo_check CHECK ((tipo = ANY (ARRAY['trial'::text, 'acreditacion'::text, 'renovacion'::text, 'ajuste'::text, 'expiracion'::text, 'suspension'::text, 'reactivacion'::text, 'inicializacion'::text])));
ALTER TABLE flow.suscripcion_notificacion DROP CONSTRAINT IF EXISTS suscripcion_notificacion_canal_check;
ALTER TABLE flow.suscripcion_notificacion ADD CONSTRAINT suscripcion_notificacion_canal_check CHECK ((canal = ANY (ARRAY['in_app'::text, 'whatsapp'::text])));
ALTER TABLE flow.suscripcion_notificacion DROP CONSTRAINT IF EXISTS suscripcion_notificacion_estado_check;
ALTER TABLE flow.suscripcion_notificacion ADD CONSTRAINT suscripcion_notificacion_estado_check CHECK ((estado = ANY (ARRAY['pendiente'::text, 'enviada'::text, 'fallida'::text, 'omitida'::text])));
ALTER TABLE flow.suscripcion_plan DROP CONSTRAINT IF EXISTS suscripcion_plan_duracion_dias_check;
ALTER TABLE flow.suscripcion_plan ADD CONSTRAINT suscripcion_plan_duracion_dias_check CHECK (((duracion_dias >= 1) AND (duracion_dias <= 3650)));
ALTER TABLE flow.suscripcion_plan DROP CONSTRAINT IF EXISTS suscripcion_plan_limites_check;
ALTER TABLE flow.suscripcion_plan ADD CONSTRAINT suscripcion_plan_limites_check CHECK ((jsonb_typeof(limites) = 'object'::text));
ALTER TABLE flow.suscripcion_plan DROP CONSTRAINT IF EXISTS suscripcion_plan_precio_check;
ALTER TABLE flow.suscripcion_plan ADD CONSTRAINT suscripcion_plan_precio_check CHECK ((precio >= (0)::numeric));
ALTER TABLE flow.suscripcion_transaccion DROP CONSTRAINT IF EXISTS suscripcion_transaccion_estado_check;
ALTER TABLE flow.suscripcion_transaccion ADD CONSTRAINT suscripcion_transaccion_estado_check CHECK ((estado = ANY (ARRAY['reportado'::text, 'verificado'::text, 'rechazado'::text])));
ALTER TABLE flow.tramo DROP CONSTRAINT IF EXISTS tramo_tipo_trayecto_check;
ALTER TABLE flow.tramo ADD CONSTRAINT tramo_tipo_trayecto_check CHECK (((tipo_trayecto IS NULL) OR ((tipo_trayecto)::text = ANY ((ARRAY['ida'::character varying, 'vuelta'::character varying])::text[]))));
ALTER TABLE flow.turno DROP CONSTRAINT IF EXISTS turno_horas_chk;
ALTER TABLE flow.turno ADD CONSTRAINT turno_horas_chk CHECK (((hora_inicio IS NULL) OR (hora_fin IS NULL) OR (hora_fin > hora_inicio)));
ALTER TABLE flow.agenda DROP CONSTRAINT IF EXISTS agenda_id_turno_fkey;
ALTER TABLE flow.agenda ADD CONSTRAINT agenda_id_turno_fkey FOREIGN KEY (id_turno) REFERENCES flow.turno(id) ON DELETE SET NULL;
ALTER TABLE flow.beneficio_bienvenida DROP CONSTRAINT IF EXISTS beneficio_bienvenida_id_entidad_fkey;
ALTER TABLE flow.beneficio_bienvenida ADD CONSTRAINT beneficio_bienvenida_id_entidad_fkey FOREIGN KEY (id_entidad) REFERENCES flow.entidad(id) ON DELETE CASCADE;
ALTER TABLE flow.beneficio_canje DROP CONSTRAINT IF EXISTS beneficio_canje_id_agenda_fkey;
ALTER TABLE flow.beneficio_canje ADD CONSTRAINT beneficio_canje_id_agenda_fkey FOREIGN KEY (id_agenda) REFERENCES flow.agenda(id) ON DELETE SET NULL;
ALTER TABLE flow.beneficio_canje DROP CONSTRAINT IF EXISTS beneficio_canje_id_beneficio_fkey;
ALTER TABLE flow.beneficio_canje ADD CONSTRAINT beneficio_canje_id_beneficio_fkey FOREIGN KEY (id_beneficio) REFERENCES flow.beneficio_bienvenida(id) ON DELETE RESTRICT;
ALTER TABLE flow.beneficio_canje DROP CONSTRAINT IF EXISTS beneficio_canje_id_entidad_fkey;
ALTER TABLE flow.beneficio_canje ADD CONSTRAINT beneficio_canje_id_entidad_fkey FOREIGN KEY (id_entidad) REFERENCES flow.entidad(id) ON DELETE SET NULL;
ALTER TABLE flow.campana DROP CONSTRAINT IF EXISTS campana_id_entidad_fkey;
ALTER TABLE flow.campana ADD CONSTRAINT campana_id_entidad_fkey FOREIGN KEY (id_entidad) REFERENCES flow.entidad(id) ON DELETE CASCADE;
ALTER TABLE flow.campana DROP CONSTRAINT IF EXISTS campana_id_local_servicio_fkey;
ALTER TABLE flow.campana ADD CONSTRAINT campana_id_local_servicio_fkey FOREIGN KEY (id_local_servicio) REFERENCES flow.local_servicio(id) ON DELETE CASCADE;
ALTER TABLE flow.coleccion_servicio DROP CONSTRAINT IF EXISTS coleccion_servicio_id_coleccion_fkey;
ALTER TABLE flow.coleccion_servicio ADD CONSTRAINT coleccion_servicio_id_coleccion_fkey FOREIGN KEY (id_coleccion) REFERENCES flow.coleccion(id) ON DELETE CASCADE;
ALTER TABLE flow.coleccion_servicio DROP CONSTRAINT IF EXISTS coleccion_servicio_id_local_servicio_fkey;
ALTER TABLE flow.coleccion_servicio ADD CONSTRAINT coleccion_servicio_id_local_servicio_fkey FOREIGN KEY (id_local_servicio) REFERENCES flow.local_servicio(id) ON DELETE CASCADE;
ALTER TABLE flow.entidad_categoria_oculta DROP CONSTRAINT IF EXISTS entidad_categoria_oculta_entidad_fkey;
ALTER TABLE flow.entidad_categoria_oculta ADD CONSTRAINT entidad_categoria_oculta_entidad_fkey FOREIGN KEY (id_entidad) REFERENCES flow.entidad(id) ON DELETE CASCADE;
ALTER TABLE flow.entidad_categoria_oculta DROP CONSTRAINT IF EXISTS entidad_categoria_oculta_tipo_fkey;
ALTER TABLE flow.entidad_categoria_oculta ADD CONSTRAINT entidad_categoria_oculta_tipo_fkey FOREIGN KEY (id_tipo_actividad) REFERENCES flow.nom_tipo_actividad_servicio(id) ON DELETE CASCADE;
ALTER TABLE flow.favorito DROP CONSTRAINT IF EXISTS favorito_id_local_servicio_fkey;
ALTER TABLE flow.favorito ADD CONSTRAINT favorito_id_local_servicio_fkey FOREIGN KEY (id_local_servicio) REFERENCES flow.local_servicio(id) ON DELETE CASCADE;
ALTER TABLE flow.favorito DROP CONSTRAINT IF EXISTS favorito_uuid_usuario_fkey;
ALTER TABLE flow.favorito ADD CONSTRAINT favorito_uuid_usuario_fkey FOREIGN KEY (uuid_usuario) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE flow.nom_tipo_actividad_servicio DROP CONSTRAINT IF EXISTS nom_tipo_actividad_servicio_id_padre_fkey;
ALTER TABLE flow.nom_tipo_actividad_servicio ADD CONSTRAINT nom_tipo_actividad_servicio_id_padre_fkey FOREIGN KEY (id_padre) REFERENCES flow.nom_tipo_actividad_servicio(id) ON DELETE RESTRICT;
ALTER TABLE flow.promocion DROP CONSTRAINT IF EXISTS promocion_id_entidad_fkey;
ALTER TABLE flow.promocion ADD CONSTRAINT promocion_id_entidad_fkey FOREIGN KEY (id_entidad) REFERENCES flow.entidad(id) ON DELETE CASCADE;
ALTER TABLE flow.promocion DROP CONSTRAINT IF EXISTS promocion_id_local_servicio_fkey;
ALTER TABLE flow.promocion ADD CONSTRAINT promocion_id_local_servicio_fkey FOREIGN KEY (id_local_servicio) REFERENCES flow.local_servicio(id) ON DELETE CASCADE;
ALTER TABLE flow.puntos_movimiento DROP CONSTRAINT IF EXISTS puntos_movimiento_id_agenda_fkey;
ALTER TABLE flow.puntos_movimiento ADD CONSTRAINT puntos_movimiento_id_agenda_fkey FOREIGN KEY (id_agenda) REFERENCES flow.agenda(id) ON DELETE SET NULL;
ALTER TABLE flow.puntos_movimiento DROP CONSTRAINT IF EXISTS puntos_movimiento_id_entidad_fkey;
ALTER TABLE flow.puntos_movimiento ADD CONSTRAINT puntos_movimiento_id_entidad_fkey FOREIGN KEY (id_entidad) REFERENCES flow.entidad(id) ON DELETE SET NULL;
ALTER TABLE flow.puntos_movimiento DROP CONSTRAINT IF EXISTS puntos_movimiento_id_regla_fkey;
ALTER TABLE flow.puntos_movimiento ADD CONSTRAINT puntos_movimiento_id_regla_fkey FOREIGN KEY (id_regla) REFERENCES flow.regla_fidelidad(id) ON DELETE SET NULL;
ALTER TABLE flow.regla_fidelidad DROP CONSTRAINT IF EXISTS regla_fidelidad_id_entidad_fkey;
ALTER TABLE flow.regla_fidelidad ADD CONSTRAINT regla_fidelidad_id_entidad_fkey FOREIGN KEY (id_entidad) REFERENCES flow.entidad(id) ON DELETE CASCADE;
ALTER TABLE flow.resena DROP CONSTRAINT IF EXISTS resena_id_agenda_fkey;
ALTER TABLE flow.resena ADD CONSTRAINT resena_id_agenda_fkey FOREIGN KEY (id_agenda) REFERENCES flow.agenda(id) ON DELETE CASCADE;
ALTER TABLE flow.resena DROP CONSTRAINT IF EXISTS resena_id_local_servicio_fkey;
ALTER TABLE flow.resena ADD CONSTRAINT resena_id_local_servicio_fkey FOREIGN KEY (id_local_servicio) REFERENCES flow.local_servicio(id) ON DELETE CASCADE;
ALTER TABLE flow.resena DROP CONSTRAINT IF EXISTS resena_uuid_usuario_fkey;
ALTER TABLE flow.resena ADD CONSTRAINT resena_uuid_usuario_fkey FOREIGN KEY (uuid_usuario) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE flow.sala_espera DROP CONSTRAINT IF EXISTS sala_espera_id_turno_fkey;
ALTER TABLE flow.sala_espera ADD CONSTRAINT sala_espera_id_turno_fkey FOREIGN KEY (id_turno) REFERENCES flow.turno(id) ON DELETE CASCADE;
ALTER TABLE flow.suscripcion DROP CONSTRAINT IF EXISTS suscripcion_id_entidad_fkey;
ALTER TABLE flow.suscripcion ADD CONSTRAINT suscripcion_id_entidad_fkey FOREIGN KEY (id_entidad) REFERENCES flow.entidad(id) ON DELETE CASCADE;
ALTER TABLE flow.suscripcion DROP CONSTRAINT IF EXISTS suscripcion_id_plan_fkey;
ALTER TABLE flow.suscripcion ADD CONSTRAINT suscripcion_id_plan_fkey FOREIGN KEY (id_plan) REFERENCES flow.suscripcion_plan(id) ON DELETE SET NULL;
ALTER TABLE flow.suscripcion_intent DROP CONSTRAINT IF EXISTS suscripcion_intent_id_entidad_fkey;
ALTER TABLE flow.suscripcion_intent ADD CONSTRAINT suscripcion_intent_id_entidad_fkey FOREIGN KEY (id_entidad) REFERENCES flow.entidad(id) ON DELETE CASCADE;
ALTER TABLE flow.suscripcion_intent DROP CONSTRAINT IF EXISTS suscripcion_intent_id_plan_fkey;
ALTER TABLE flow.suscripcion_intent ADD CONSTRAINT suscripcion_intent_id_plan_fkey FOREIGN KEY (id_plan) REFERENCES flow.suscripcion_plan(id) ON DELETE RESTRICT;
ALTER TABLE flow.suscripcion_intent DROP CONSTRAINT IF EXISTS suscripcion_intent_uuid_usuario_fkey;
ALTER TABLE flow.suscripcion_intent ADD CONSTRAINT suscripcion_intent_uuid_usuario_fkey FOREIGN KEY (uuid_usuario) REFERENCES auth.users(id);
ALTER TABLE flow.suscripcion_movimiento DROP CONSTRAINT IF EXISTS suscripcion_movimiento_id_entidad_fkey;
ALTER TABLE flow.suscripcion_movimiento ADD CONSTRAINT suscripcion_movimiento_id_entidad_fkey FOREIGN KEY (id_entidad) REFERENCES flow.entidad(id) ON DELETE CASCADE;
ALTER TABLE flow.suscripcion_movimiento DROP CONSTRAINT IF EXISTS suscripcion_movimiento_id_suscripcion_fkey;
ALTER TABLE flow.suscripcion_movimiento ADD CONSTRAINT suscripcion_movimiento_id_suscripcion_fkey FOREIGN KEY (id_suscripcion) REFERENCES flow.suscripcion(id) ON DELETE SET NULL;
ALTER TABLE flow.suscripcion_movimiento DROP CONSTRAINT IF EXISTS suscripcion_movimiento_id_transaccion_fkey;
ALTER TABLE flow.suscripcion_movimiento ADD CONSTRAINT suscripcion_movimiento_id_transaccion_fkey FOREIGN KEY (id_transaccion) REFERENCES flow.suscripcion_transaccion(id) ON DELETE SET NULL;
ALTER TABLE flow.suscripcion_notificacion DROP CONSTRAINT IF EXISTS suscripcion_notificacion_id_entidad_fkey;
ALTER TABLE flow.suscripcion_notificacion ADD CONSTRAINT suscripcion_notificacion_id_entidad_fkey FOREIGN KEY (id_entidad) REFERENCES flow.entidad(id) ON DELETE CASCADE;
ALTER TABLE flow.suscripcion_transaccion DROP CONSTRAINT IF EXISTS suscripcion_transaccion_id_entidad_fkey;
ALTER TABLE flow.suscripcion_transaccion ADD CONSTRAINT suscripcion_transaccion_id_entidad_fkey FOREIGN KEY (id_entidad) REFERENCES flow.entidad(id) ON DELETE CASCADE;
ALTER TABLE flow.suscripcion_transaccion DROP CONSTRAINT IF EXISTS suscripcion_transaccion_id_intent_fkey;
ALTER TABLE flow.suscripcion_transaccion ADD CONSTRAINT suscripcion_transaccion_id_intent_fkey FOREIGN KEY (id_intent) REFERENCES flow.suscripcion_intent(id) ON DELETE RESTRICT;
ALTER TABLE flow.suscripcion_transaccion DROP CONSTRAINT IF EXISTS suscripcion_transaccion_reportado_por_fkey;
ALTER TABLE flow.suscripcion_transaccion ADD CONSTRAINT suscripcion_transaccion_reportado_por_fkey FOREIGN KEY (reportado_por) REFERENCES auth.users(id);
ALTER TABLE flow.suscripcion_transaccion DROP CONSTRAINT IF EXISTS suscripcion_transaccion_verificado_por_fkey;
ALTER TABLE flow.suscripcion_transaccion ADD CONSTRAINT suscripcion_transaccion_verificado_por_fkey FOREIGN KEY (verificado_por) REFERENCES auth.users(id);

-- ============================================================
-- 9. Indices
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_campana_entidad ON flow.campana USING btree (id_entidad) WHERE (id_entidad IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_campana_local ON flow.campana USING btree (id_local_servicio) WHERE (id_local_servicio IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_campana_vigente ON flow.campana USING btree (activo, prioridad DESC);
CREATE INDEX IF NOT EXISTS idx_coleccion_activa ON flow.coleccion USING btree (activo, orden, id);
CREATE INDEX IF NOT EXISTS idx_coleccion_servicio_ls ON flow.coleccion_servicio USING btree (id_local_servicio);
CREATE INDEX IF NOT EXISTS idx_entidad_categoria_oculta_tipo ON flow.entidad_categoria_oculta USING btree (id_tipo_actividad);
CREATE INDEX IF NOT EXISTS idx_favorito_usuario_fecha ON flow.favorito USING btree (uuid_usuario, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_nom_tipo_actividad_padre ON flow.nom_tipo_actividad_servicio USING btree (id_padre);
CREATE INDEX IF NOT EXISTS idx_promocion_entidad_vigente ON flow.promocion USING btree (id_entidad) WHERE (activo AND (id_entidad IS NOT NULL));
CREATE INDEX IF NOT EXISTS idx_promocion_ls_vigente ON flow.promocion USING btree (id_local_servicio) WHERE (activo AND (id_local_servicio IS NOT NULL));
CREATE INDEX IF NOT EXISTS idx_resena_servicio_fecha ON flow.resena USING btree (id_local_servicio, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_resena_usuario ON flow.resena USING btree (uuid_usuario, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_suscripcion_entidad ON flow.suscripcion USING btree (id_entidad, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_suscripcion_intent_entidad ON flow.suscripcion_intent USING btree (id_entidad, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_suscripcion_intent_estado ON flow.suscripcion_intent USING btree (estado, expira_at);
CREATE INDEX IF NOT EXISTS idx_suscripcion_movimiento_entidad ON flow.suscripcion_movimiento USING btree (id_entidad, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_suscripcion_notificacion_pendiente ON flow.suscripcion_notificacion USING btree (estado, canal, created_at) WHERE (estado = 'pendiente'::text);
CREATE INDEX IF NOT EXISTS idx_suscripcion_plan_activo ON flow.suscripcion_plan USING btree (activo, orden);
CREATE INDEX IF NOT EXISTS idx_suscripcion_transaccion_entidad ON flow.suscripcion_transaccion USING btree (id_entidad, reportado_at DESC);
CREATE INDEX IF NOT EXISTS idx_suscripcion_transaccion_estado ON flow.suscripcion_transaccion USING btree (estado, reportado_at);
CREATE INDEX IF NOT EXISTS idx_suscripcion_vencimiento ON flow.suscripcion USING btree (fecha_vencimiento) WHERE (estado = ANY (ARRAY['trial'::text, 'activa'::text, 'en_gracia'::text]));
CREATE UNIQUE INDEX IF NOT EXISTS puntos_movimiento_agenda_uidx ON flow.puntos_movimiento USING btree (id_agenda) WHERE (((tipo)::text = 'acumulacion'::text) AND (id_agenda IS NOT NULL));
CREATE INDEX IF NOT EXISTS puntos_movimiento_usuario_idx ON flow.puntos_movimiento USING btree (uuid_usuario, created_at DESC);
CREATE INDEX IF NOT EXISTS puntos_movimiento_vigentes_idx ON flow.puntos_movimiento USING btree (uuid_usuario, vence_en) WHERE (((tipo)::text = 'acumulacion'::text) AND (liquidado = false));
CREATE UNIQUE INDEX IF NOT EXISTS ux_suscripcion_entidad_viva ON flow.suscripcion USING btree (id_entidad) WHERE (estado = ANY (ARRAY['trial'::text, 'activa'::text, 'en_gracia'::text, 'sin_plan'::text, 'suspendida'::text]));

-- ============================================================
-- 10. Triggers
-- ============================================================
DROP TRIGGER IF EXISTS agenda_acreditar_puntos ON flow.agenda;
CREATE TRIGGER agenda_acreditar_puntos AFTER UPDATE OF id_estado ON flow.agenda FOR EACH ROW EXECUTE FUNCTION flow.trg_agenda_acreditar_puntos();
DROP TRIGGER IF EXISTS trg_agenda_ls_disponible ON flow.agenda;
CREATE TRIGGER trg_agenda_ls_disponible BEFORE INSERT ON flow.agenda FOR EACH ROW EXECUTE FUNCTION flow._bloquear_reserva_si_no_disponible();
DROP TRIGGER IF EXISTS trg_entidad_suscripcion_trial ON flow.entidad;
CREATE TRIGGER trg_entidad_suscripcion_trial AFTER INSERT ON flow.entidad FOR EACH ROW EXECUTE FUNCTION flow._suscripcion_trial_entidad();
DROP TRIGGER IF EXISTS trg_nom_tipo_actividad_jerarquia ON flow.nom_tipo_actividad_servicio;
CREATE TRIGGER trg_nom_tipo_actividad_jerarquia BEFORE INSERT OR UPDATE OF id_padre ON flow.nom_tipo_actividad_servicio FOR EACH ROW EXECUTE FUNCTION flow.validar_jerarquia_tipo_actividad();
DROP TRIGGER IF EXISTS trg_sala_espera_ls_disponible ON flow.sala_espera;
CREATE TRIGGER trg_sala_espera_ls_disponible BEFORE INSERT ON flow.sala_espera FOR EACH ROW EXECUTE FUNCTION flow._bloquear_reserva_si_no_disponible();
DROP TRIGGER IF EXISTS trg_suscripcion_touch ON flow.suscripcion;
CREATE TRIGGER trg_suscripcion_touch BEFORE UPDATE ON flow.suscripcion FOR EACH ROW EXECUTE FUNCTION flow._susc_touch();
DROP TRIGGER IF EXISTS trg_suscripcion_config_touch ON flow.suscripcion_config;
CREATE TRIGGER trg_suscripcion_config_touch BEFORE UPDATE ON flow.suscripcion_config FOR EACH ROW EXECUTE FUNCTION flow._susc_touch();
DROP TRIGGER IF EXISTS trg_suscripcion_intent_touch ON flow.suscripcion_intent;
CREATE TRIGGER trg_suscripcion_intent_touch BEFORE UPDATE ON flow.suscripcion_intent FOR EACH ROW EXECUTE FUNCTION flow._susc_touch();
DROP TRIGGER IF EXISTS trg_suscripcion_notificacion_touch ON flow.suscripcion_notificacion;
CREATE TRIGGER trg_suscripcion_notificacion_touch BEFORE UPDATE ON flow.suscripcion_notificacion FOR EACH ROW EXECUTE FUNCTION flow._susc_touch();
DROP TRIGGER IF EXISTS trg_suscripcion_plan_touch ON flow.suscripcion_plan;
CREATE TRIGGER trg_suscripcion_plan_touch BEFORE UPDATE ON flow.suscripcion_plan FOR EACH ROW EXECUTE FUNCTION flow._susc_touch();
DROP TRIGGER IF EXISTS trg_suscripcion_transaccion_touch ON flow.suscripcion_transaccion;
CREATE TRIGGER trg_suscripcion_transaccion_touch BEFORE UPDATE ON flow.suscripcion_transaccion FOR EACH ROW EXECUTE FUNCTION flow._susc_touch();

-- ============================================================
-- 11. Row Level Security
-- ============================================================
ALTER TABLE flow.beneficio_bienvenida ENABLE ROW LEVEL SECURITY; ALTER TABLE flow.beneficio_bienvenida NO FORCE ROW LEVEL SECURITY;
ALTER TABLE flow.beneficio_canje ENABLE ROW LEVEL SECURITY; ALTER TABLE flow.beneficio_canje NO FORCE ROW LEVEL SECURITY;
ALTER TABLE flow.bot_log ENABLE ROW LEVEL SECURITY; ALTER TABLE flow.bot_log NO FORCE ROW LEVEL SECURITY;
ALTER TABLE flow.campana ENABLE ROW LEVEL SECURITY; ALTER TABLE flow.campana NO FORCE ROW LEVEL SECURITY;
ALTER TABLE flow.coleccion ENABLE ROW LEVEL SECURITY; ALTER TABLE flow.coleccion NO FORCE ROW LEVEL SECURITY;
ALTER TABLE flow.coleccion_servicio ENABLE ROW LEVEL SECURITY; ALTER TABLE flow.coleccion_servicio NO FORCE ROW LEVEL SECURITY;
ALTER TABLE flow.entidad_categoria_oculta ENABLE ROW LEVEL SECURITY; ALTER TABLE flow.entidad_categoria_oculta NO FORCE ROW LEVEL SECURITY;
ALTER TABLE flow.favorito ENABLE ROW LEVEL SECURITY; ALTER TABLE flow.favorito NO FORCE ROW LEVEL SECURITY;
ALTER TABLE flow.fidelidad_config ENABLE ROW LEVEL SECURITY; ALTER TABLE flow.fidelidad_config NO FORCE ROW LEVEL SECURITY;
ALTER TABLE flow.nom_tipo_actividad_servicio ENABLE ROW LEVEL SECURITY; ALTER TABLE flow.nom_tipo_actividad_servicio NO FORCE ROW LEVEL SECURITY;
ALTER TABLE flow.promocion ENABLE ROW LEVEL SECURITY; ALTER TABLE flow.promocion NO FORCE ROW LEVEL SECURITY;
ALTER TABLE flow.puntos_movimiento ENABLE ROW LEVEL SECURITY; ALTER TABLE flow.puntos_movimiento NO FORCE ROW LEVEL SECURITY;
ALTER TABLE flow.regla_fidelidad ENABLE ROW LEVEL SECURITY; ALTER TABLE flow.regla_fidelidad NO FORCE ROW LEVEL SECURITY;
ALTER TABLE flow.resena ENABLE ROW LEVEL SECURITY; ALTER TABLE flow.resena NO FORCE ROW LEVEL SECURITY;
ALTER TABLE flow.sala_espera_fraude ENABLE ROW LEVEL SECURITY; ALTER TABLE flow.sala_espera_fraude NO FORCE ROW LEVEL SECURITY;
ALTER TABLE flow.suscripcion ENABLE ROW LEVEL SECURITY; ALTER TABLE flow.suscripcion NO FORCE ROW LEVEL SECURITY;
ALTER TABLE flow.suscripcion_config ENABLE ROW LEVEL SECURITY; ALTER TABLE flow.suscripcion_config NO FORCE ROW LEVEL SECURITY;
ALTER TABLE flow.suscripcion_intent ENABLE ROW LEVEL SECURITY; ALTER TABLE flow.suscripcion_intent NO FORCE ROW LEVEL SECURITY;
ALTER TABLE flow.suscripcion_movimiento ENABLE ROW LEVEL SECURITY; ALTER TABLE flow.suscripcion_movimiento NO FORCE ROW LEVEL SECURITY;
ALTER TABLE flow.suscripcion_notificacion ENABLE ROW LEVEL SECURITY; ALTER TABLE flow.suscripcion_notificacion NO FORCE ROW LEVEL SECURITY;
ALTER TABLE flow.suscripcion_plan ENABLE ROW LEVEL SECURITY; ALTER TABLE flow.suscripcion_plan NO FORCE ROW LEVEL SECURITY;
ALTER TABLE flow.suscripcion_transaccion ENABLE ROW LEVEL SECURITY; ALTER TABLE flow.suscripcion_transaccion NO FORCE ROW LEVEL SECURITY;

-- ============================================================
-- 12. Politicas
-- ============================================================
DROP POLICY IF EXISTS "update ls" ON flow.local_servicio;
DROP POLICY IF EXISTS beneficio_bienvenida_select_autenticados ON flow.beneficio_bienvenida;
CREATE POLICY beneficio_bienvenida_select_autenticados ON flow.beneficio_bienvenida AS PERMISSIVE FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS beneficio_bienvenida_write_superadmin ON flow.beneficio_bienvenida;
CREATE POLICY beneficio_bienvenida_write_superadmin ON flow.beneficio_bienvenida AS PERMISSIVE FOR ALL TO authenticated USING (fn_is_superadmin_full_access()) WITH CHECK (fn_is_superadmin_full_access());
DROP POLICY IF EXISTS beneficio_canje_select_propios ON flow.beneficio_canje;
CREATE POLICY beneficio_canje_select_propios ON flow.beneficio_canje AS PERMISSIVE FOR SELECT TO authenticated USING ((uuid_usuario = auth.uid()));
DROP POLICY IF EXISTS beneficio_canje_write_superadmin ON flow.beneficio_canje;
CREATE POLICY beneficio_canje_write_superadmin ON flow.beneficio_canje AS PERMISSIVE FOR ALL TO authenticated USING (fn_is_superadmin_full_access()) WITH CHECK (fn_is_superadmin_full_access());
DROP POLICY IF EXISTS campana_delete_superadmin ON flow.campana;
CREATE POLICY campana_delete_superadmin ON flow.campana AS PERMISSIVE FOR DELETE TO authenticated USING (fn_is_superadmin_full_access());
DROP POLICY IF EXISTS campana_insert_superadmin ON flow.campana;
CREATE POLICY campana_insert_superadmin ON flow.campana AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (fn_is_superadmin_full_access());
DROP POLICY IF EXISTS campana_select_autenticados ON flow.campana;
CREATE POLICY campana_select_autenticados ON flow.campana AS PERMISSIVE FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS campana_update_superadmin ON flow.campana;
CREATE POLICY campana_update_superadmin ON flow.campana AS PERMISSIVE FOR UPDATE TO authenticated USING (fn_is_superadmin_full_access()) WITH CHECK (fn_is_superadmin_full_access());
DROP POLICY IF EXISTS coleccion_delete_superadmin ON flow.coleccion;
CREATE POLICY coleccion_delete_superadmin ON flow.coleccion AS PERMISSIVE FOR DELETE TO authenticated USING (fn_is_superadmin_full_access());
DROP POLICY IF EXISTS coleccion_insert_superadmin ON flow.coleccion;
CREATE POLICY coleccion_insert_superadmin ON flow.coleccion AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (fn_is_superadmin_full_access());
DROP POLICY IF EXISTS coleccion_select_activas ON flow.coleccion;
CREATE POLICY coleccion_select_activas ON flow.coleccion AS PERMISSIVE FOR SELECT TO authenticated USING (activo);
DROP POLICY IF EXISTS coleccion_select_superadmin ON flow.coleccion;
CREATE POLICY coleccion_select_superadmin ON flow.coleccion AS PERMISSIVE FOR SELECT TO authenticated USING (fn_is_superadmin_full_access());
DROP POLICY IF EXISTS coleccion_update_superadmin ON flow.coleccion;
CREATE POLICY coleccion_update_superadmin ON flow.coleccion AS PERMISSIVE FOR UPDATE TO authenticated USING (fn_is_superadmin_full_access()) WITH CHECK (fn_is_superadmin_full_access());
DROP POLICY IF EXISTS coleccion_servicio_delete_superadmin ON flow.coleccion_servicio;
CREATE POLICY coleccion_servicio_delete_superadmin ON flow.coleccion_servicio AS PERMISSIVE FOR DELETE TO authenticated USING (fn_is_superadmin_full_access());
DROP POLICY IF EXISTS coleccion_servicio_insert_superadmin ON flow.coleccion_servicio;
CREATE POLICY coleccion_servicio_insert_superadmin ON flow.coleccion_servicio AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (fn_is_superadmin_full_access());
DROP POLICY IF EXISTS coleccion_servicio_select_autenticados ON flow.coleccion_servicio;
CREATE POLICY coleccion_servicio_select_autenticados ON flow.coleccion_servicio AS PERMISSIVE FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS coleccion_servicio_update_superadmin ON flow.coleccion_servicio;
CREATE POLICY coleccion_servicio_update_superadmin ON flow.coleccion_servicio AS PERMISSIVE FOR UPDATE TO authenticated USING (fn_is_superadmin_full_access()) WITH CHECK (fn_is_superadmin_full_access());
DROP POLICY IF EXISTS entidad_categoria_oculta_delete ON flow.entidad_categoria_oculta;
CREATE POLICY entidad_categoria_oculta_delete ON flow.entidad_categoria_oculta AS PERMISSIVE FOR DELETE TO authenticated USING ((fn_is_superadmin_full_access() OR flow.is_entidad_admin(id_entidad)));
DROP POLICY IF EXISTS entidad_categoria_oculta_insert ON flow.entidad_categoria_oculta;
CREATE POLICY entidad_categoria_oculta_insert ON flow.entidad_categoria_oculta AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((fn_is_superadmin_full_access() OR flow.is_entidad_admin(id_entidad)));
DROP POLICY IF EXISTS entidad_categoria_oculta_select ON flow.entidad_categoria_oculta;
CREATE POLICY entidad_categoria_oculta_select ON flow.entidad_categoria_oculta AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS favorito_delete_propio ON flow.favorito;
CREATE POLICY favorito_delete_propio ON flow.favorito AS PERMISSIVE FOR DELETE TO authenticated USING ((uuid_usuario = auth.uid()));
DROP POLICY IF EXISTS favorito_insert_propio ON flow.favorito;
CREATE POLICY favorito_insert_propio ON flow.favorito AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((uuid_usuario = auth.uid()));
DROP POLICY IF EXISTS favorito_select_propio ON flow.favorito;
CREATE POLICY favorito_select_propio ON flow.favorito AS PERMISSIVE FOR SELECT TO authenticated USING ((uuid_usuario = auth.uid()));
DROP POLICY IF EXISTS fidelidad_config_select_autenticados ON flow.fidelidad_config;
CREATE POLICY fidelidad_config_select_autenticados ON flow.fidelidad_config AS PERMISSIVE FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS fidelidad_config_write_superadmin ON flow.fidelidad_config;
CREATE POLICY fidelidad_config_write_superadmin ON flow.fidelidad_config AS PERMISSIVE FOR ALL TO authenticated USING (fn_is_superadmin_full_access()) WITH CHECK (fn_is_superadmin_full_access());
DROP POLICY IF EXISTS nom_tipo_actividad_delete_admin ON flow.nom_tipo_actividad_servicio;
CREATE POLICY nom_tipo_actividad_delete_admin ON flow.nom_tipo_actividad_servicio AS PERMISSIVE FOR DELETE TO authenticated USING (((EXISTS ( SELECT 1
   FROM flow.admin_entidades_de_usuario(auth.uid()) admin_entidades_de_usuario(id_entidad))) OR fn_is_superadmin_full_access()));
DROP POLICY IF EXISTS nom_tipo_actividad_insert_admin ON flow.nom_tipo_actividad_servicio;
CREATE POLICY nom_tipo_actividad_insert_admin ON flow.nom_tipo_actividad_servicio AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((EXISTS ( SELECT 1
   FROM flow.admin_entidades_de_usuario(auth.uid()) admin_entidades_de_usuario(id_entidad))) OR fn_is_superadmin_full_access()));
DROP POLICY IF EXISTS nom_tipo_actividad_select_all ON flow.nom_tipo_actividad_servicio;
CREATE POLICY nom_tipo_actividad_select_all ON flow.nom_tipo_actividad_servicio AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS nom_tipo_actividad_update_admin ON flow.nom_tipo_actividad_servicio;
CREATE POLICY nom_tipo_actividad_update_admin ON flow.nom_tipo_actividad_servicio AS PERMISSIVE FOR UPDATE TO authenticated USING (((EXISTS ( SELECT 1
   FROM flow.admin_entidades_de_usuario(auth.uid()) admin_entidades_de_usuario(id_entidad))) OR fn_is_superadmin_full_access())) WITH CHECK (((EXISTS ( SELECT 1
   FROM flow.admin_entidades_de_usuario(auth.uid()) admin_entidades_de_usuario(id_entidad))) OR fn_is_superadmin_full_access()));
DROP POLICY IF EXISTS promocion_select_autenticados ON flow.promocion;
CREATE POLICY promocion_select_autenticados ON flow.promocion AS PERMISSIVE FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS puntos_movimiento_select_propios ON flow.puntos_movimiento;
CREATE POLICY puntos_movimiento_select_propios ON flow.puntos_movimiento AS PERMISSIVE FOR SELECT TO authenticated USING ((uuid_usuario = auth.uid()));
DROP POLICY IF EXISTS puntos_movimiento_write_superadmin ON flow.puntos_movimiento;
CREATE POLICY puntos_movimiento_write_superadmin ON flow.puntos_movimiento AS PERMISSIVE FOR ALL TO authenticated USING (fn_is_superadmin_full_access()) WITH CHECK (fn_is_superadmin_full_access());
DROP POLICY IF EXISTS regla_fidelidad_select_autenticados ON flow.regla_fidelidad;
CREATE POLICY regla_fidelidad_select_autenticados ON flow.regla_fidelidad AS PERMISSIVE FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS regla_fidelidad_write_superadmin ON flow.regla_fidelidad;
CREATE POLICY regla_fidelidad_write_superadmin ON flow.regla_fidelidad AS PERMISSIVE FOR ALL TO authenticated USING (fn_is_superadmin_full_access()) WITH CHECK (fn_is_superadmin_full_access());
DROP POLICY IF EXISTS resena_delete_propia ON flow.resena;
CREATE POLICY resena_delete_propia ON flow.resena AS PERMISSIVE FOR DELETE TO authenticated USING ((uuid_usuario = auth.uid()));
DROP POLICY IF EXISTS resena_insert_propia ON flow.resena;
CREATE POLICY resena_insert_propia ON flow.resena AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((uuid_usuario = auth.uid()) AND (EXISTS ( SELECT 1
   FROM (flow.agenda a
     JOIN flow.nom_estado_agenda e ON ((e.id = a.id_estado)))
  WHERE ((a.id = resena.id_agenda) AND (a.id_local_servicio = a.id_local_servicio) AND ((e.nombre)::text = 'Completado'::text) AND ((a.uuid_usuario = auth.uid()) OR (a.reservado_por = auth.uid())))))));
DROP POLICY IF EXISTS resena_select_autenticados ON flow.resena;
CREATE POLICY resena_select_autenticados ON flow.resena AS PERMISSIVE FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS resena_update_propia ON flow.resena;
CREATE POLICY resena_update_propia ON flow.resena AS PERMISSIVE FOR UPDATE TO authenticated USING ((uuid_usuario = auth.uid())) WITH CHECK ((uuid_usuario = auth.uid()));
DROP POLICY IF EXISTS sala_espera_fraude_insert_propio ON flow.sala_espera_fraude;
CREATE POLICY sala_espera_fraude_insert_propio ON flow.sala_espera_fraude AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((uuid_usuario = auth.uid()));
DROP POLICY IF EXISTS sala_espera_fraude_select_propio ON flow.sala_espera_fraude;
CREATE POLICY sala_espera_fraude_select_propio ON flow.sala_espera_fraude AS PERMISSIVE FOR SELECT TO authenticated USING ((uuid_usuario = auth.uid()));
DROP POLICY IF EXISTS suscripcion_select_propia ON flow.suscripcion;
CREATE POLICY suscripcion_select_propia ON flow.suscripcion AS PERMISSIVE FOR SELECT TO authenticated USING (flow._susc_caller_ve_entidad(id_entidad));
DROP POLICY IF EXISTS suscripcion_write_superadmin ON flow.suscripcion;
CREATE POLICY suscripcion_write_superadmin ON flow.suscripcion AS PERMISSIVE FOR ALL TO authenticated USING (fn_is_superadmin_full_access()) WITH CHECK (fn_is_superadmin_full_access());
DROP POLICY IF EXISTS suscripcion_config_select_autenticados ON flow.suscripcion_config;
CREATE POLICY suscripcion_config_select_autenticados ON flow.suscripcion_config AS PERMISSIVE FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS suscripcion_config_write_superadmin ON flow.suscripcion_config;
CREATE POLICY suscripcion_config_write_superadmin ON flow.suscripcion_config AS PERMISSIVE FOR ALL TO authenticated USING (fn_is_superadmin_full_access()) WITH CHECK (fn_is_superadmin_full_access());
DROP POLICY IF EXISTS suscripcion_intent_select_propio ON flow.suscripcion_intent;
CREATE POLICY suscripcion_intent_select_propio ON flow.suscripcion_intent AS PERMISSIVE FOR SELECT TO authenticated USING (flow._susc_caller_ve_entidad(id_entidad));
DROP POLICY IF EXISTS suscripcion_intent_write_superadmin ON flow.suscripcion_intent;
CREATE POLICY suscripcion_intent_write_superadmin ON flow.suscripcion_intent AS PERMISSIVE FOR ALL TO authenticated USING (fn_is_superadmin_full_access()) WITH CHECK (fn_is_superadmin_full_access());
DROP POLICY IF EXISTS suscripcion_movimiento_select_propio ON flow.suscripcion_movimiento;
CREATE POLICY suscripcion_movimiento_select_propio ON flow.suscripcion_movimiento AS PERMISSIVE FOR SELECT TO authenticated USING (flow._susc_caller_ve_entidad(id_entidad));
DROP POLICY IF EXISTS suscripcion_movimiento_write_superadmin ON flow.suscripcion_movimiento;
CREATE POLICY suscripcion_movimiento_write_superadmin ON flow.suscripcion_movimiento AS PERMISSIVE FOR ALL TO authenticated USING (fn_is_superadmin_full_access()) WITH CHECK (fn_is_superadmin_full_access());
DROP POLICY IF EXISTS suscripcion_notificacion_select_propia ON flow.suscripcion_notificacion;
CREATE POLICY suscripcion_notificacion_select_propia ON flow.suscripcion_notificacion AS PERMISSIVE FOR SELECT TO authenticated USING (flow._susc_caller_ve_entidad(id_entidad));
DROP POLICY IF EXISTS suscripcion_notificacion_write_superadmin ON flow.suscripcion_notificacion;
CREATE POLICY suscripcion_notificacion_write_superadmin ON flow.suscripcion_notificacion AS PERMISSIVE FOR ALL TO authenticated USING (fn_is_superadmin_full_access()) WITH CHECK (fn_is_superadmin_full_access());
DROP POLICY IF EXISTS suscripcion_plan_select_autenticados ON flow.suscripcion_plan;
CREATE POLICY suscripcion_plan_select_autenticados ON flow.suscripcion_plan AS PERMISSIVE FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS suscripcion_plan_write_superadmin ON flow.suscripcion_plan;
CREATE POLICY suscripcion_plan_write_superadmin ON flow.suscripcion_plan AS PERMISSIVE FOR ALL TO authenticated USING (fn_is_superadmin_full_access()) WITH CHECK (fn_is_superadmin_full_access());
DROP POLICY IF EXISTS suscripcion_transaccion_select_propia ON flow.suscripcion_transaccion;
CREATE POLICY suscripcion_transaccion_select_propia ON flow.suscripcion_transaccion AS PERMISSIVE FOR SELECT TO authenticated USING (flow._susc_caller_ve_entidad(id_entidad));
DROP POLICY IF EXISTS suscripcion_transaccion_write_superadmin ON flow.suscripcion_transaccion;
CREATE POLICY suscripcion_transaccion_write_superadmin ON flow.suscripcion_transaccion AS PERMISSIVE FOR ALL TO authenticated USING (fn_is_superadmin_full_access()) WITH CHECK (fn_is_superadmin_full_access());

-- ============================================================
-- 13. Permisos
-- ============================================================
GRANT USAGE ON SCHEMA flow TO anon; GRANT USAGE ON SCHEMA flow TO authenticated;
GRANT SELECT ON flow.beneficio_bienvenida TO anon; GRANT INSERT ON flow.beneficio_bienvenida TO authenticated; GRANT SELECT ON flow.beneficio_bienvenida TO authenticated; GRANT UPDATE ON flow.beneficio_bienvenida TO authenticated; GRANT DELETE ON flow.beneficio_bienvenida TO authenticated;
GRANT SELECT ON flow.beneficio_bienvenida_id_seq TO authenticated; GRANT UPDATE ON flow.beneficio_bienvenida_id_seq TO authenticated; GRANT USAGE ON flow.beneficio_bienvenida_id_seq TO authenticated;
GRANT SELECT ON flow.beneficio_canje TO anon; GRANT INSERT ON flow.beneficio_canje TO authenticated; GRANT SELECT ON flow.beneficio_canje TO authenticated; GRANT UPDATE ON flow.beneficio_canje TO authenticated; GRANT DELETE ON flow.beneficio_canje TO authenticated;
GRANT SELECT ON flow.beneficio_canje_id_seq TO authenticated; GRANT UPDATE ON flow.beneficio_canje_id_seq TO authenticated; GRANT USAGE ON flow.beneficio_canje_id_seq TO authenticated;
GRANT INSERT ON flow.campana TO authenticated; GRANT SELECT ON flow.campana TO authenticated; GRANT UPDATE ON flow.campana TO authenticated; GRANT DELETE ON flow.campana TO authenticated; GRANT INSERT ON flow.campana TO service_role; GRANT SELECT ON flow.campana TO service_role; GRANT UPDATE ON flow.campana TO service_role; GRANT DELETE ON flow.campana TO service_role; GRANT TRUNCATE ON flow.campana TO service_role; GRANT REFERENCES ON flow.campana TO service_role; GRANT TRIGGER ON flow.campana TO service_role; GRANT MAINTAIN ON flow.campana TO service_role;
GRANT SELECT ON flow.campana_id_seq TO authenticated; GRANT UPDATE ON flow.campana_id_seq TO authenticated; GRANT USAGE ON flow.campana_id_seq TO authenticated;
GRANT SELECT ON flow.coleccion TO anon; GRANT INSERT ON flow.coleccion TO authenticated; GRANT SELECT ON flow.coleccion TO authenticated; GRANT UPDATE ON flow.coleccion TO authenticated; GRANT DELETE ON flow.coleccion TO authenticated;
GRANT SELECT ON flow.coleccion_id_seq TO authenticated; GRANT UPDATE ON flow.coleccion_id_seq TO authenticated; GRANT USAGE ON flow.coleccion_id_seq TO authenticated;
GRANT SELECT ON flow.coleccion_servicio TO anon; GRANT INSERT ON flow.coleccion_servicio TO authenticated; GRANT SELECT ON flow.coleccion_servicio TO authenticated; GRANT UPDATE ON flow.coleccion_servicio TO authenticated; GRANT DELETE ON flow.coleccion_servicio TO authenticated;
GRANT INSERT ON flow.entidad_categoria_oculta TO authenticated; GRANT SELECT ON flow.entidad_categoria_oculta TO authenticated; GRANT UPDATE ON flow.entidad_categoria_oculta TO authenticated; GRANT DELETE ON flow.entidad_categoria_oculta TO authenticated; GRANT INSERT ON flow.entidad_categoria_oculta TO service_role; GRANT SELECT ON flow.entidad_categoria_oculta TO service_role; GRANT DELETE ON flow.entidad_categoria_oculta TO service_role; GRANT SELECT ON flow.entidad_categoria_oculta TO anon;
GRANT INSERT ON flow.favorito TO authenticated; GRANT SELECT ON flow.favorito TO authenticated; GRANT UPDATE ON flow.favorito TO authenticated; GRANT DELETE ON flow.favorito TO authenticated; GRANT INSERT ON flow.favorito TO service_role; GRANT SELECT ON flow.favorito TO service_role; GRANT UPDATE ON flow.favorito TO service_role; GRANT DELETE ON flow.favorito TO service_role; GRANT TRUNCATE ON flow.favorito TO service_role; GRANT REFERENCES ON flow.favorito TO service_role; GRANT TRIGGER ON flow.favorito TO service_role; GRANT MAINTAIN ON flow.favorito TO service_role;
GRANT INSERT ON flow.fidelidad_config TO authenticated; GRANT SELECT ON flow.fidelidad_config TO authenticated; GRANT UPDATE ON flow.fidelidad_config TO authenticated; GRANT DELETE ON flow.fidelidad_config TO authenticated; GRANT INSERT ON flow.fidelidad_config TO service_role; GRANT SELECT ON flow.fidelidad_config TO service_role; GRANT UPDATE ON flow.fidelidad_config TO service_role; GRANT DELETE ON flow.fidelidad_config TO service_role; GRANT TRUNCATE ON flow.fidelidad_config TO service_role; GRANT REFERENCES ON flow.fidelidad_config TO service_role; GRANT TRIGGER ON flow.fidelidad_config TO service_role; GRANT MAINTAIN ON flow.fidelidad_config TO service_role;
GRANT INSERT ON flow.promocion TO authenticated; GRANT SELECT ON flow.promocion TO authenticated; GRANT UPDATE ON flow.promocion TO authenticated; GRANT DELETE ON flow.promocion TO authenticated; GRANT INSERT ON flow.promocion TO service_role; GRANT SELECT ON flow.promocion TO service_role; GRANT UPDATE ON flow.promocion TO service_role; GRANT DELETE ON flow.promocion TO service_role; GRANT TRUNCATE ON flow.promocion TO service_role; GRANT REFERENCES ON flow.promocion TO service_role; GRANT TRIGGER ON flow.promocion TO service_role; GRANT MAINTAIN ON flow.promocion TO service_role;
GRANT SELECT ON flow.promocion_id_seq TO authenticated; GRANT UPDATE ON flow.promocion_id_seq TO authenticated; GRANT USAGE ON flow.promocion_id_seq TO authenticated;
GRANT SELECT ON flow.puntos_movimiento TO anon; GRANT INSERT ON flow.puntos_movimiento TO authenticated; GRANT SELECT ON flow.puntos_movimiento TO authenticated; GRANT UPDATE ON flow.puntos_movimiento TO authenticated; GRANT DELETE ON flow.puntos_movimiento TO authenticated;
GRANT SELECT ON flow.puntos_movimiento_id_seq TO authenticated; GRANT UPDATE ON flow.puntos_movimiento_id_seq TO authenticated; GRANT USAGE ON flow.puntos_movimiento_id_seq TO authenticated;
GRANT SELECT ON flow.regla_fidelidad TO anon; GRANT INSERT ON flow.regla_fidelidad TO authenticated; GRANT SELECT ON flow.regla_fidelidad TO authenticated; GRANT UPDATE ON flow.regla_fidelidad TO authenticated; GRANT DELETE ON flow.regla_fidelidad TO authenticated;
GRANT SELECT ON flow.regla_fidelidad_id_seq TO authenticated; GRANT UPDATE ON flow.regla_fidelidad_id_seq TO authenticated; GRANT USAGE ON flow.regla_fidelidad_id_seq TO authenticated;
GRANT INSERT ON flow.resena TO authenticated; GRANT SELECT ON flow.resena TO authenticated; GRANT UPDATE ON flow.resena TO authenticated; GRANT DELETE ON flow.resena TO authenticated; GRANT INSERT ON flow.resena TO service_role; GRANT SELECT ON flow.resena TO service_role; GRANT UPDATE ON flow.resena TO service_role; GRANT DELETE ON flow.resena TO service_role; GRANT TRUNCATE ON flow.resena TO service_role; GRANT REFERENCES ON flow.resena TO service_role; GRANT TRIGGER ON flow.resena TO service_role; GRANT MAINTAIN ON flow.resena TO service_role;
GRANT SELECT ON flow.resena_id_seq TO authenticated; GRANT UPDATE ON flow.resena_id_seq TO authenticated; GRANT USAGE ON flow.resena_id_seq TO authenticated;
GRANT INSERT ON flow.suscripcion TO authenticated; GRANT SELECT ON flow.suscripcion TO authenticated; GRANT UPDATE ON flow.suscripcion TO authenticated; GRANT DELETE ON flow.suscripcion TO authenticated; GRANT INSERT ON flow.suscripcion TO service_role; GRANT SELECT ON flow.suscripcion TO service_role; GRANT UPDATE ON flow.suscripcion TO service_role; GRANT DELETE ON flow.suscripcion TO service_role; GRANT TRUNCATE ON flow.suscripcion TO service_role; GRANT REFERENCES ON flow.suscripcion TO service_role; GRANT TRIGGER ON flow.suscripcion TO service_role; GRANT MAINTAIN ON flow.suscripcion TO service_role;
GRANT INSERT ON flow.suscripcion_config TO authenticated; GRANT SELECT ON flow.suscripcion_config TO authenticated; GRANT UPDATE ON flow.suscripcion_config TO authenticated; GRANT DELETE ON flow.suscripcion_config TO authenticated; GRANT INSERT ON flow.suscripcion_config TO service_role; GRANT SELECT ON flow.suscripcion_config TO service_role; GRANT UPDATE ON flow.suscripcion_config TO service_role; GRANT DELETE ON flow.suscripcion_config TO service_role; GRANT TRUNCATE ON flow.suscripcion_config TO service_role; GRANT REFERENCES ON flow.suscripcion_config TO service_role; GRANT TRIGGER ON flow.suscripcion_config TO service_role; GRANT MAINTAIN ON flow.suscripcion_config TO service_role;
GRANT SELECT ON flow.suscripcion_id_seq TO authenticated; GRANT UPDATE ON flow.suscripcion_id_seq TO authenticated; GRANT USAGE ON flow.suscripcion_id_seq TO authenticated;
GRANT INSERT ON flow.suscripcion_intent TO authenticated; GRANT SELECT ON flow.suscripcion_intent TO authenticated; GRANT UPDATE ON flow.suscripcion_intent TO authenticated; GRANT DELETE ON flow.suscripcion_intent TO authenticated; GRANT INSERT ON flow.suscripcion_intent TO service_role; GRANT SELECT ON flow.suscripcion_intent TO service_role; GRANT UPDATE ON flow.suscripcion_intent TO service_role; GRANT DELETE ON flow.suscripcion_intent TO service_role; GRANT TRUNCATE ON flow.suscripcion_intent TO service_role; GRANT REFERENCES ON flow.suscripcion_intent TO service_role; GRANT TRIGGER ON flow.suscripcion_intent TO service_role; GRANT MAINTAIN ON flow.suscripcion_intent TO service_role;
GRANT SELECT ON flow.suscripcion_intent_id_seq TO authenticated; GRANT UPDATE ON flow.suscripcion_intent_id_seq TO authenticated; GRANT USAGE ON flow.suscripcion_intent_id_seq TO authenticated;
GRANT INSERT ON flow.suscripcion_movimiento TO authenticated; GRANT SELECT ON flow.suscripcion_movimiento TO authenticated; GRANT UPDATE ON flow.suscripcion_movimiento TO authenticated; GRANT DELETE ON flow.suscripcion_movimiento TO authenticated; GRANT INSERT ON flow.suscripcion_movimiento TO service_role; GRANT SELECT ON flow.suscripcion_movimiento TO service_role; GRANT UPDATE ON flow.suscripcion_movimiento TO service_role; GRANT DELETE ON flow.suscripcion_movimiento TO service_role; GRANT TRUNCATE ON flow.suscripcion_movimiento TO service_role; GRANT REFERENCES ON flow.suscripcion_movimiento TO service_role; GRANT TRIGGER ON flow.suscripcion_movimiento TO service_role; GRANT MAINTAIN ON flow.suscripcion_movimiento TO service_role;
GRANT SELECT ON flow.suscripcion_movimiento_id_seq TO authenticated; GRANT UPDATE ON flow.suscripcion_movimiento_id_seq TO authenticated; GRANT USAGE ON flow.suscripcion_movimiento_id_seq TO authenticated;
GRANT INSERT ON flow.suscripcion_notificacion TO authenticated; GRANT SELECT ON flow.suscripcion_notificacion TO authenticated; GRANT UPDATE ON flow.suscripcion_notificacion TO authenticated; GRANT DELETE ON flow.suscripcion_notificacion TO authenticated; GRANT INSERT ON flow.suscripcion_notificacion TO service_role; GRANT SELECT ON flow.suscripcion_notificacion TO service_role; GRANT UPDATE ON flow.suscripcion_notificacion TO service_role; GRANT DELETE ON flow.suscripcion_notificacion TO service_role; GRANT TRUNCATE ON flow.suscripcion_notificacion TO service_role; GRANT REFERENCES ON flow.suscripcion_notificacion TO service_role; GRANT TRIGGER ON flow.suscripcion_notificacion TO service_role; GRANT MAINTAIN ON flow.suscripcion_notificacion TO service_role;
GRANT SELECT ON flow.suscripcion_notificacion_id_seq TO authenticated; GRANT UPDATE ON flow.suscripcion_notificacion_id_seq TO authenticated; GRANT USAGE ON flow.suscripcion_notificacion_id_seq TO authenticated;
GRANT INSERT ON flow.suscripcion_plan TO authenticated; GRANT SELECT ON flow.suscripcion_plan TO authenticated; GRANT UPDATE ON flow.suscripcion_plan TO authenticated; GRANT DELETE ON flow.suscripcion_plan TO authenticated; GRANT INSERT ON flow.suscripcion_plan TO service_role; GRANT SELECT ON flow.suscripcion_plan TO service_role; GRANT UPDATE ON flow.suscripcion_plan TO service_role; GRANT DELETE ON flow.suscripcion_plan TO service_role; GRANT TRUNCATE ON flow.suscripcion_plan TO service_role; GRANT REFERENCES ON flow.suscripcion_plan TO service_role; GRANT TRIGGER ON flow.suscripcion_plan TO service_role; GRANT MAINTAIN ON flow.suscripcion_plan TO service_role;
GRANT SELECT ON flow.suscripcion_plan_id_seq TO authenticated; GRANT UPDATE ON flow.suscripcion_plan_id_seq TO authenticated; GRANT USAGE ON flow.suscripcion_plan_id_seq TO authenticated;
GRANT INSERT ON flow.suscripcion_transaccion TO authenticated; GRANT SELECT ON flow.suscripcion_transaccion TO authenticated; GRANT UPDATE ON flow.suscripcion_transaccion TO authenticated; GRANT DELETE ON flow.suscripcion_transaccion TO authenticated; GRANT INSERT ON flow.suscripcion_transaccion TO service_role; GRANT SELECT ON flow.suscripcion_transaccion TO service_role; GRANT UPDATE ON flow.suscripcion_transaccion TO service_role; GRANT DELETE ON flow.suscripcion_transaccion TO service_role; GRANT TRUNCATE ON flow.suscripcion_transaccion TO service_role; GRANT REFERENCES ON flow.suscripcion_transaccion TO service_role; GRANT TRIGGER ON flow.suscripcion_transaccion TO service_role; GRANT MAINTAIN ON flow.suscripcion_transaccion TO service_role;
GRANT SELECT ON flow.suscripcion_transaccion_id_seq TO authenticated; GRANT UPDATE ON flow.suscripcion_transaccion_id_seq TO authenticated; GRANT USAGE ON flow.suscripcion_transaccion_id_seq TO authenticated;
REVOKE ALL ON FUNCTION flow._acreditar_puntos_agenda(p_id_agenda integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow._acreditar_puntos_agenda(p_id_agenda integer) TO service_role;
REVOKE ALL ON FUNCTION flow._admin_puede_local_servicio(p_uuid_usuario uuid, p_id_local_servicio integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow._admin_puede_local_servicio(p_uuid_usuario uuid, p_id_local_servicio integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow._admin_puede_local_servicio(p_uuid_usuario uuid, p_id_local_servicio integer) TO PUBLIC;
REVOKE ALL ON FUNCTION flow._admin_puede_recurso(p_uuid_usuario uuid, p_id_recurso integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow._admin_puede_recurso(p_uuid_usuario uuid, p_id_recurso integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow._admin_puede_recurso(p_uuid_usuario uuid, p_id_recurso integer) TO PUBLIC;
REVOKE ALL ON FUNCTION flow._aplicar_promocion(p_id_local_servicio integer, p_id_servicio integer, p_precio_lista numeric, p_moneda character varying, p_precio_unit numeric, p_consumir_cupo boolean) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow._aplicar_promocion(p_id_local_servicio integer, p_id_servicio integer, p_precio_lista numeric, p_moneda character varying, p_precio_unit numeric, p_consumir_cupo boolean) TO service_role;
REVOKE ALL ON FUNCTION flow._beneficio_bienvenida_aplicable(p_uuid_usuario uuid, p_id_entidad integer, p_moneda character varying, p_subtotal numeric) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow._beneficio_bienvenida_aplicable(p_uuid_usuario uuid, p_id_entidad integer, p_moneda character varying, p_subtotal numeric) TO service_role;
REVOKE ALL ON FUNCTION flow._bloquear_reserva_si_no_disponible() FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow._bloquear_reserva_si_no_disponible() TO authenticated; GRANT EXECUTE ON FUNCTION flow._bloquear_reserva_si_no_disponible() TO service_role; GRANT EXECUTE ON FUNCTION flow._bloquear_reserva_si_no_disponible() TO PUBLIC;
REVOKE ALL ON FUNCTION flow._caller_es_admin_de_ls(p_id_local_servicio integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow._caller_es_admin_de_ls(p_id_local_servicio integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow._caller_es_admin_de_ls(p_id_local_servicio integer) TO service_role; GRANT EXECUTE ON FUNCTION flow._caller_es_admin_de_ls(p_id_local_servicio integer) TO PUBLIC;
REVOKE ALL ON FUNCTION flow._descontar_tramos_turno(p_id_turno integer, p_fecha date, p_cant integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow._descontar_tramos_turno(p_id_turno integer, p_fecha date, p_cant integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow._descontar_tramos_turno(p_id_turno integer, p_fecha date, p_cant integer) TO PUBLIC;
REVOKE ALL ON FUNCTION flow._liberar_tramos_turno(p_id_turno integer, p_fecha date, p_cant integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow._liberar_tramos_turno(p_id_turno integer, p_fecha date, p_cant integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow._liberar_tramos_turno(p_id_turno integer, p_fecha date, p_cant integer) TO PUBLIC;
REVOKE ALL ON FUNCTION flow._ls_disponible(p_id_local_servicio integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow._ls_disponible(p_id_local_servicio integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow._ls_disponible(p_id_local_servicio integer) TO service_role; GRANT EXECUTE ON FUNCTION flow._ls_disponible(p_id_local_servicio integer) TO PUBLIC;
REVOKE ALL ON FUNCTION flow._ls_tiene_recursos(p_id_local_servicio integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow._ls_tiene_recursos(p_id_local_servicio integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow._ls_tiene_recursos(p_id_local_servicio integer) TO PUBLIC;
REVOKE ALL ON FUNCTION flow._precio_con_promocion(p_id_servicio integer, p_id_local_servicio integer, p_datos jsonb, p_moneda text, p_cantidad integer, p_consumir_cupo boolean) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow._precio_con_promocion(p_id_servicio integer, p_id_local_servicio integer, p_datos jsonb, p_moneda text, p_cantidad integer, p_consumir_cupo boolean) TO service_role;
REVOKE ALL ON FUNCTION flow._resolver_beneficio_bienvenida(p_uuid_usuario uuid, p_id_entidad integer, p_moneda character varying) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow._resolver_beneficio_bienvenida(p_uuid_usuario uuid, p_id_entidad integer, p_moneda character varying) TO service_role;
REVOKE ALL ON FUNCTION flow._resolver_perfil_tercero(p_nombre text, p_apellidos text, p_ci text, p_telefono text) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow._resolver_perfil_tercero(p_nombre text, p_apellidos text, p_ci text, p_telefono text) TO authenticated; GRANT EXECUTE ON FUNCTION flow._resolver_perfil_tercero(p_nombre text, p_apellidos text, p_ci text, p_telefono text) TO anon; GRANT EXECUTE ON FUNCTION flow._resolver_perfil_tercero(p_nombre text, p_apellidos text, p_ci text, p_telefono text) TO service_role;
REVOKE ALL ON FUNCTION flow._resolver_promocion(p_id_local_servicio integer, p_id_servicio integer, p_monto numeric) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow._resolver_promocion(p_id_local_servicio integer, p_id_servicio integer, p_monto numeric) TO service_role;
REVOKE ALL ON FUNCTION flow._resolver_regla_fidelidad(p_id_entidad integer, p_moneda character varying) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow._resolver_regla_fidelidad(p_id_entidad integer, p_moneda character varying) TO service_role;
REVOKE ALL ON FUNCTION flow._susc_acreditar_dias(p_id_entidad integer, p_id_plan bigint, p_dias integer, p_origen text, p_notas text, p_admin uuid, p_id_transaccion bigint) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow._susc_acreditar_dias(p_id_entidad integer, p_id_plan bigint, p_dias integer, p_origen text, p_notas text, p_admin uuid, p_id_transaccion bigint) TO authenticated; GRANT EXECUTE ON FUNCTION flow._susc_acreditar_dias(p_id_entidad integer, p_id_plan bigint, p_dias integer, p_origen text, p_notas text, p_admin uuid, p_id_transaccion bigint) TO service_role;
REVOKE ALL ON FUNCTION flow._susc_caller_ve_entidad(p_id_entidad integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow._susc_caller_ve_entidad(p_id_entidad integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow._susc_caller_ve_entidad(p_id_entidad integer) TO service_role; GRANT EXECUTE ON FUNCTION flow._susc_caller_ve_entidad(p_id_entidad integer) TO PUBLIC;
REVOKE ALL ON FUNCTION flow._susc_notificar_inapp(p_id_entidad integer, p_uuid uuid, p_titulo text, p_mensaje text) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow._susc_notificar_inapp(p_id_entidad integer, p_uuid uuid, p_titulo text, p_mensaje text) TO authenticated; GRANT EXECUTE ON FUNCTION flow._susc_notificar_inapp(p_id_entidad integer, p_uuid uuid, p_titulo text, p_mensaje text) TO service_role;
REVOKE ALL ON FUNCTION flow._susc_notificar_whatsapp(p_id_entidad integer, p_telefono text, p_mensaje text) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow._susc_notificar_whatsapp(p_id_entidad integer, p_telefono text, p_mensaje text) TO authenticated; GRANT EXECUTE ON FUNCTION flow._susc_notificar_whatsapp(p_id_entidad integer, p_telefono text, p_mensaje text) TO service_role;
REVOKE ALL ON FUNCTION flow._susc_touch() FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow._susc_touch() TO authenticated; GRANT EXECUTE ON FUNCTION flow._susc_touch() TO service_role; GRANT EXECUTE ON FUNCTION flow._susc_touch() TO PUBLIC;
REVOKE ALL ON FUNCTION flow._suscripcion_trial_entidad() FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow._suscripcion_trial_entidad() TO authenticated; GRANT EXECUTE ON FUNCTION flow._suscripcion_trial_entidad() TO service_role; GRANT EXECUTE ON FUNCTION flow._suscripcion_trial_entidad() TO PUBLIC;
REVOKE ALL ON FUNCTION flow._upsert_plan_tramos_recurso(p_id_recurso integer, p_fecha date, p_cap integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow._upsert_plan_tramos_recurso(p_id_recurso integer, p_fecha date, p_cap integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow._upsert_plan_tramos_recurso(p_id_recurso integer, p_fecha date, p_cap integer) TO PUBLIC;
REVOKE ALL ON FUNCTION flow.admin_actualizar_datos_reserva(p_id_agenda integer, p_datos_adicionales jsonb) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_actualizar_datos_reserva(p_id_agenda integer, p_datos_adicionales jsonb) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_actualizar_datos_reserva(p_id_agenda integer, p_datos_adicionales jsonb) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_ajustar_puntos_usuario(p_uuid_usuario uuid, p_uuid_destino uuid, p_puntos integer, p_motivo text) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_ajustar_puntos_usuario(p_uuid_usuario uuid, p_uuid_destino uuid, p_puntos integer, p_motivo text) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_ajustar_puntos_usuario(p_uuid_usuario uuid, p_uuid_destino uuid, p_puntos integer, p_motivo text) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_alternar_campana(p_uuid_usuario uuid, p_id integer, p_activo boolean) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_alternar_campana(p_uuid_usuario uuid, p_id integer, p_activo boolean) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_alternar_campana(p_uuid_usuario uuid, p_id integer, p_activo boolean) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_alternar_coleccion(p_uuid_usuario uuid, p_id integer, p_activo boolean) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_alternar_coleccion(p_uuid_usuario uuid, p_id integer, p_activo boolean) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_alternar_coleccion(p_uuid_usuario uuid, p_id integer, p_activo boolean) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_alternar_tipo_actividad(p_id integer, p_activo boolean) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_alternar_tipo_actividad(p_id integer, p_activo boolean) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_alternar_tipo_actividad(p_id integer, p_activo boolean) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_cancelar_agenda(p_id_agenda integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_cancelar_agenda(p_id_agenda integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_cancelar_agenda(p_id_agenda integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_config_guardar(p_config jsonb) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_config_guardar(p_config jsonb) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_config_guardar(p_config jsonb) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_config_modo_gestion(p_uuid_usuario uuid, p_id_local_servicio integer, p_solo_turnos boolean, p_sin_tramos boolean) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_config_modo_gestion(p_uuid_usuario uuid, p_id_local_servicio integer, p_solo_turnos boolean, p_sin_tramos boolean) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_config_modo_gestion(p_uuid_usuario uuid, p_id_local_servicio integer, p_solo_turnos boolean, p_sin_tramos boolean) TO service_role; GRANT EXECUTE ON FUNCTION flow.admin_config_modo_gestion(p_uuid_usuario uuid, p_id_local_servicio integer, p_solo_turnos boolean, p_sin_tramos boolean) TO PUBLIC;
REVOKE ALL ON FUNCTION flow.admin_config_obtener() FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_config_obtener() TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_config_obtener() TO service_role;
REVOKE ALL ON FUNCTION flow.admin_crear_reserva_directa(p_id_local_servicio integer, p_fecha date, p_cantidad integer, p_datos_adicionales jsonb, p_uuid_admin uuid, p_id_turno integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_crear_reserva_directa(p_id_local_servicio integer, p_fecha date, p_cantidad integer, p_datos_adicionales jsonb, p_uuid_admin uuid, p_id_turno integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_crear_reserva_directa(p_id_local_servicio integer, p_fecha date, p_cantidad integer, p_datos_adicionales jsonb, p_uuid_admin uuid, p_id_turno integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_create_perfil(p_uuid_usuario uuid, p_nombre text, p_apellidos text, p_ci text, p_telefono text) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_create_perfil(p_uuid_usuario uuid, p_nombre text, p_apellidos text, p_ci text, p_telefono text) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_create_perfil(p_uuid_usuario uuid, p_nombre text, p_apellidos text, p_ci text, p_telefono text) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_create_plan_servicio(p_id_local_servicio integer, p_fecha date, p_cantidad integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_create_plan_servicio(p_id_local_servicio integer, p_fecha date, p_cantidad integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_create_plan_servicio(p_id_local_servicio integer, p_fecha date, p_cantidad integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_create_user(p_email text, p_password text, p_nombre text, p_apellidos text, p_ci text, p_telefono text) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_create_user(p_email text, p_password text, p_nombre text, p_apellidos text, p_ci text, p_telefono text) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_create_user(p_email text, p_password text, p_nombre text, p_apellidos text, p_ci text, p_telefono text) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_dashboard_entidad(p_uuid_usuario uuid, p_id_entidad integer, p_dias integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_dashboard_entidad(p_uuid_usuario uuid, p_id_entidad integer, p_dias integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_dashboard_entidad(p_uuid_usuario uuid, p_id_entidad integer, p_dias integer) TO service_role; GRANT EXECUTE ON FUNCTION flow.admin_dashboard_entidad(p_uuid_usuario uuid, p_id_entidad integer, p_dias integer) TO PUBLIC;
REVOKE ALL ON FUNCTION flow.admin_delete_plan_servicio(p_id integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_delete_plan_servicio(p_id integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_delete_plan_servicio(p_id integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_eliminar_beneficio_bienvenida(p_uuid_usuario uuid, p_id integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_eliminar_beneficio_bienvenida(p_uuid_usuario uuid, p_id integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_eliminar_beneficio_bienvenida(p_uuid_usuario uuid, p_id integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_eliminar_campana(p_uuid_usuario uuid, p_id integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_eliminar_campana(p_uuid_usuario uuid, p_id integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_eliminar_campana(p_uuid_usuario uuid, p_id integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_eliminar_coleccion(p_uuid_usuario uuid, p_id integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_eliminar_coleccion(p_uuid_usuario uuid, p_id integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_eliminar_coleccion(p_uuid_usuario uuid, p_id integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_eliminar_promocion(p_uuid_usuario uuid, p_id integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_eliminar_promocion(p_uuid_usuario uuid, p_id integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_eliminar_promocion(p_uuid_usuario uuid, p_id integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_eliminar_recurso(p_uuid_usuario uuid, p_id integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_eliminar_recurso(p_uuid_usuario uuid, p_id integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_eliminar_recurso(p_uuid_usuario uuid, p_id integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_eliminar_regla_fidelidad(p_uuid_usuario uuid, p_id integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_eliminar_regla_fidelidad(p_uuid_usuario uuid, p_id integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_eliminar_regla_fidelidad(p_uuid_usuario uuid, p_id integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_eliminar_tipo_actividad(p_id integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_eliminar_tipo_actividad(p_id integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_eliminar_tipo_actividad(p_id integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_eliminar_tramo(p_uuid_usuario uuid, p_id integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_eliminar_tramo(p_uuid_usuario uuid, p_id integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_eliminar_tramo(p_uuid_usuario uuid, p_id integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_eliminar_turno(p_uuid_usuario uuid, p_id integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_eliminar_turno(p_uuid_usuario uuid, p_id integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_eliminar_turno(p_uuid_usuario uuid, p_id integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_entidades_de_usuario(p_uuid_usuario uuid) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_entidades_de_usuario(p_uuid_usuario uuid) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_entidades_de_usuario(p_uuid_usuario uuid) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_existe_ci(p_ci text, p_exclude_uuid uuid) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_existe_ci(p_ci text, p_exclude_uuid uuid) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_existe_ci(p_ci text, p_exclude_uuid uuid) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_existe_plan_fecha(p_id_local_servicio integer, p_fecha date, p_exclude_id integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_existe_plan_fecha(p_id_local_servicio integer, p_fecha date, p_exclude_id integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_existe_plan_fecha(p_id_local_servicio integer, p_fecha date, p_exclude_id integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_generar_plan_mensual(p_uuid_usuario uuid, p_id_local_servicio integer, p_anio integer, p_mes integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_generar_plan_mensual(p_uuid_usuario uuid, p_id_local_servicio integer, p_anio integer, p_mes integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_generar_plan_mensual(p_uuid_usuario uuid, p_id_local_servicio integer, p_anio integer, p_mes integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_get_perfil(p_uuid_usuario uuid) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_get_perfil(p_uuid_usuario uuid) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_get_perfil(p_uuid_usuario uuid) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_get_plan_dias(p_uuid_usuario uuid, p_id_local_servicio integer, p_desde date, p_hasta date) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_get_plan_dias(p_uuid_usuario uuid, p_id_local_servicio integer, p_desde date, p_hasta date) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_get_plan_dias(p_uuid_usuario uuid, p_id_local_servicio integer, p_desde date, p_hasta date) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_get_plan_servicios(p_id_local_servicio integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_get_plan_servicios(p_id_local_servicio integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_get_plan_servicios(p_id_local_servicio integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_guardar_beneficio_bienvenida(p_uuid_usuario uuid, p_titulo text, p_descripcion text, p_tipo text, p_valor numeric, p_moneda text, p_id_entidad integer, p_monto_minimo numeric, p_activo boolean, p_desde timestamp with time zone, p_hasta timestamp with time zone, p_id integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_guardar_beneficio_bienvenida(p_uuid_usuario uuid, p_titulo text, p_descripcion text, p_tipo text, p_valor numeric, p_moneda text, p_id_entidad integer, p_monto_minimo numeric, p_activo boolean, p_desde timestamp with time zone, p_hasta timestamp with time zone, p_id integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_guardar_beneficio_bienvenida(p_uuid_usuario uuid, p_titulo text, p_descripcion text, p_tipo text, p_valor numeric, p_moneda text, p_id_entidad integer, p_monto_minimo numeric, p_activo boolean, p_desde timestamp with time zone, p_hasta timestamp with time zone, p_id integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_guardar_campana(p_uuid_usuario uuid, p_titulo text, p_id_local_servicio integer, p_id_entidad integer, p_subtitulo text, p_descripcion text, p_color_inicio text, p_color_fin text, p_icono text, p_image_url text, p_desde timestamp with time zone, p_hasta timestamp with time zone, p_prioridad integer, p_activo boolean, p_id integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_guardar_campana(p_uuid_usuario uuid, p_titulo text, p_id_local_servicio integer, p_id_entidad integer, p_subtitulo text, p_descripcion text, p_color_inicio text, p_color_fin text, p_icono text, p_image_url text, p_desde timestamp with time zone, p_hasta timestamp with time zone, p_prioridad integer, p_activo boolean, p_id integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_guardar_campana(p_uuid_usuario uuid, p_titulo text, p_id_local_servicio integer, p_id_entidad integer, p_subtitulo text, p_descripcion text, p_color_inicio text, p_color_fin text, p_icono text, p_image_url text, p_desde timestamp with time zone, p_hasta timestamp with time zone, p_prioridad integer, p_activo boolean, p_id integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_guardar_coleccion(p_uuid_usuario uuid, p_titulo text, p_subtitulo text, p_icono text, p_color_inicio text, p_color_fin text, p_orden integer, p_activo boolean, p_desde timestamp with time zone, p_hasta timestamp with time zone, p_servicios jsonb, p_id integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_guardar_coleccion(p_uuid_usuario uuid, p_titulo text, p_subtitulo text, p_icono text, p_color_inicio text, p_color_fin text, p_orden integer, p_activo boolean, p_desde timestamp with time zone, p_hasta timestamp with time zone, p_servicios jsonb, p_id integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_guardar_coleccion(p_uuid_usuario uuid, p_titulo text, p_subtitulo text, p_icono text, p_color_inicio text, p_color_fin text, p_orden integer, p_activo boolean, p_desde timestamp with time zone, p_hasta timestamp with time zone, p_servicios jsonb, p_id integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_guardar_config_plan(p_uuid_usuario uuid, p_id_local_servicio integer, p_config jsonb, p_activo boolean) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_guardar_config_plan(p_uuid_usuario uuid, p_id_local_servicio integer, p_config jsonb, p_activo boolean) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_guardar_config_plan(p_uuid_usuario uuid, p_id_local_servicio integer, p_config jsonb, p_activo boolean) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_guardar_datos_servicio(p_uuid_usuario uuid, p_id_servicio integer, p_campos jsonb, p_permite_tercero boolean, p_config_precio jsonb) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_guardar_datos_servicio(p_uuid_usuario uuid, p_id_servicio integer, p_campos jsonb, p_permite_tercero boolean, p_config_precio jsonb) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_guardar_datos_servicio(p_uuid_usuario uuid, p_id_servicio integer, p_campos jsonb, p_permite_tercero boolean, p_config_precio jsonb) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_guardar_fidelidad_config(p_uuid_usuario uuid, p_activa boolean) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_guardar_fidelidad_config(p_uuid_usuario uuid, p_activa boolean) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_guardar_fidelidad_config(p_uuid_usuario uuid, p_activa boolean) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_guardar_promocion(p_uuid_usuario uuid, p_id_local_servicio integer, p_titulo text, p_tipo text, p_valor numeric, p_moneda text, p_desde timestamp with time zone, p_hasta timestamp with time zone, p_cupo_total integer, p_activo boolean, p_id integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_guardar_promocion(p_uuid_usuario uuid, p_id_local_servicio integer, p_titulo text, p_tipo text, p_valor numeric, p_moneda text, p_desde timestamp with time zone, p_hasta timestamp with time zone, p_cupo_total integer, p_activo boolean, p_id integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_guardar_promocion(p_uuid_usuario uuid, p_id_local_servicio integer, p_titulo text, p_tipo text, p_valor numeric, p_moneda text, p_desde timestamp with time zone, p_hasta timestamp with time zone, p_cupo_total integer, p_activo boolean, p_id integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_guardar_recurso(p_uuid_usuario uuid, p_id_local_servicio integer, p_nombre text, p_capacidad integer, p_orden integer, p_activo boolean, p_id integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_guardar_recurso(p_uuid_usuario uuid, p_id_local_servicio integer, p_nombre text, p_capacidad integer, p_orden integer, p_activo boolean, p_id integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_guardar_recurso(p_uuid_usuario uuid, p_id_local_servicio integer, p_nombre text, p_capacidad integer, p_orden integer, p_activo boolean, p_id integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_guardar_regla_fidelidad(p_uuid_usuario uuid, p_nombre text, p_id_entidad integer, p_moneda text, p_puntos_por_monto numeric, p_monto_base numeric, p_vigencia_dias integer, p_activo boolean, p_desde timestamp with time zone, p_hasta timestamp with time zone, p_id integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_guardar_regla_fidelidad(p_uuid_usuario uuid, p_nombre text, p_id_entidad integer, p_moneda text, p_puntos_por_monto numeric, p_monto_base numeric, p_vigencia_dias integer, p_activo boolean, p_desde timestamp with time zone, p_hasta timestamp with time zone, p_id integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_guardar_regla_fidelidad(p_uuid_usuario uuid, p_nombre text, p_id_entidad integer, p_moneda text, p_puntos_por_monto numeric, p_monto_base numeric, p_vigencia_dias integer, p_activo boolean, p_desde timestamp with time zone, p_hasta timestamp with time zone, p_id integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_guardar_tipo_actividad(p_codigo text, p_nombre text, p_activo boolean, p_id integer, p_id_padre integer, p_orden integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_guardar_tipo_actividad(p_codigo text, p_nombre text, p_activo boolean, p_id integer, p_id_padre integer, p_orden integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_guardar_tipo_actividad(p_codigo text, p_nombre text, p_activo boolean, p_id integer, p_id_padre integer, p_orden integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_guardar_tramo(p_uuid_usuario uuid, p_id_recurso integer, p_nombre text, p_capacidad integer, p_orden integer, p_activo boolean, p_id integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_guardar_tramo(p_uuid_usuario uuid, p_id_recurso integer, p_nombre text, p_capacidad integer, p_orden integer, p_activo boolean, p_id integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_guardar_tramo(p_uuid_usuario uuid, p_id_recurso integer, p_nombre text, p_capacidad integer, p_orden integer, p_activo boolean, p_id integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_guardar_tramo_transporte(p_uuid_usuario uuid, p_id_recurso integer, p_nombre text, p_tipo_trayecto character varying, p_id integer, p_activo boolean) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_guardar_tramo_transporte(p_uuid_usuario uuid, p_id_recurso integer, p_nombre text, p_tipo_trayecto character varying, p_id integer, p_activo boolean) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_guardar_tramo_transporte(p_uuid_usuario uuid, p_id_recurso integer, p_nombre text, p_tipo_trayecto character varying, p_id integer, p_activo boolean) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_guardar_turno(p_uuid_usuario uuid, p_id_recurso integer, p_nombre text, p_tramos jsonb, p_orden integer, p_activo boolean, p_id integer, p_precios jsonb, p_hora_inicio time without time zone, p_hora_fin time without time zone) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_guardar_turno(p_uuid_usuario uuid, p_id_recurso integer, p_nombre text, p_tramos jsonb, p_orden integer, p_activo boolean, p_id integer, p_precios jsonb, p_hora_inicio time without time zone, p_hora_fin time without time zone) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_guardar_turno(p_uuid_usuario uuid, p_id_recurso integer, p_nombre text, p_tramos jsonb, p_orden integer, p_activo boolean, p_id integer, p_precios jsonb, p_hora_inicio time without time zone, p_hora_fin time without time zone) TO service_role; GRANT EXECUTE ON FUNCTION flow.admin_guardar_turno(p_uuid_usuario uuid, p_id_recurso integer, p_nombre text, p_tramos jsonb, p_orden integer, p_activo boolean, p_id integer, p_precios jsonb, p_hora_inicio time without time zone, p_hora_fin time without time zone) TO PUBLIC;
REVOKE ALL ON FUNCTION flow.admin_guardar_turno_auto(p_uuid_usuario uuid, p_id_local_servicio integer, p_nombre text, p_orden integer, p_activo boolean, p_precios jsonb, p_hora_inicio time without time zone, p_hora_fin time without time zone, p_id integer, p_id_recurso integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_guardar_turno_auto(p_uuid_usuario uuid, p_id_local_servicio integer, p_nombre text, p_orden integer, p_activo boolean, p_precios jsonb, p_hora_inicio time without time zone, p_hora_fin time without time zone, p_id integer, p_id_recurso integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_guardar_turno_auto(p_uuid_usuario uuid, p_id_local_servicio integer, p_nombre text, p_orden integer, p_activo boolean, p_precios jsonb, p_hora_inicio time without time zone, p_hora_fin time without time zone, p_id integer, p_id_recurso integer) TO service_role; GRANT EXECUTE ON FUNCTION flow.admin_guardar_turno_auto(p_uuid_usuario uuid, p_id_local_servicio integer, p_nombre text, p_orden integer, p_activo boolean, p_precios jsonb, p_hora_inicio time without time zone, p_hora_fin time without time zone, p_id integer, p_id_recurso integer) TO PUBLIC;
REVOKE ALL ON FUNCTION flow.admin_listar_admins(p_id_entidad integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_listar_admins(p_id_entidad integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_listar_admins(p_id_entidad integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_listar_agendas(p_uuid_usuario uuid, p_id_entidad integer, p_id_local integer, p_id_local_servicio integer, p_id_estado integer, p_desde timestamp without time zone, p_hasta timestamp without time zone) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_listar_agendas(p_uuid_usuario uuid, p_id_entidad integer, p_id_local integer, p_id_local_servicio integer, p_id_estado integer, p_desde timestamp without time zone, p_hasta timestamp without time zone) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_listar_agendas(p_uuid_usuario uuid, p_id_entidad integer, p_id_local integer, p_id_local_servicio integer, p_id_estado integer, p_desde timestamp without time zone, p_hasta timestamp without time zone) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_listar_agendas_por_estado(p_uuid_usuario uuid, p_id_entidad integer, p_id_local integer, p_id_local_servicio integer, p_id_estado integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_listar_agendas_por_estado(p_uuid_usuario uuid, p_id_entidad integer, p_id_local integer, p_id_local_servicio integer, p_id_estado integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_listar_agendas_por_estado(p_uuid_usuario uuid, p_id_entidad integer, p_id_local integer, p_id_local_servicio integer, p_id_estado integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_listar_beneficios_bienvenida(p_uuid_usuario uuid) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_listar_beneficios_bienvenida(p_uuid_usuario uuid) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_listar_beneficios_bienvenida(p_uuid_usuario uuid) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_listar_campanas(p_uuid_usuario uuid) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_listar_campanas(p_uuid_usuario uuid) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_listar_campanas(p_uuid_usuario uuid) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_listar_colecciones(p_uuid_usuario uuid) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_listar_colecciones(p_uuid_usuario uuid) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_listar_colecciones(p_uuid_usuario uuid) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_listar_entidades(p_uuid_usuario uuid) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_listar_entidades(p_uuid_usuario uuid) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_listar_entidades(p_uuid_usuario uuid) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_listar_locales(p_uuid_usuario uuid, p_id_entidad integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_listar_locales(p_uuid_usuario uuid, p_id_entidad integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_listar_locales(p_uuid_usuario uuid, p_id_entidad integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_listar_locales_servicios(p_uuid_usuario uuid, p_id_entidad integer, p_id_local integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_listar_locales_servicios(p_uuid_usuario uuid, p_id_entidad integer, p_id_local integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_listar_locales_servicios(p_uuid_usuario uuid, p_id_entidad integer, p_id_local integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_listar_movimientos_puntos(p_uuid_usuario uuid, p_uuid_destino uuid) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_listar_movimientos_puntos(p_uuid_usuario uuid, p_uuid_destino uuid) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_listar_movimientos_puntos(p_uuid_usuario uuid, p_uuid_destino uuid) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_listar_promociones(p_uuid_usuario uuid, p_id_local_servicio integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_listar_promociones(p_uuid_usuario uuid, p_id_local_servicio integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_listar_promociones(p_uuid_usuario uuid, p_id_local_servicio integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_listar_recursos(p_uuid_usuario uuid, p_id_local_servicio integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_listar_recursos(p_uuid_usuario uuid, p_id_local_servicio integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_listar_recursos(p_uuid_usuario uuid, p_id_local_servicio integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_listar_reglas_fidelidad(p_uuid_usuario uuid) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_listar_reglas_fidelidad(p_uuid_usuario uuid) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_listar_reglas_fidelidad(p_uuid_usuario uuid) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_listar_salas_espera(p_uuid_usuario uuid, p_id_entidad integer, p_id_local integer, p_id_local_servicio integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_listar_salas_espera(p_uuid_usuario uuid, p_id_entidad integer, p_id_local integer, p_id_local_servicio integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_listar_salas_espera(p_uuid_usuario uuid, p_id_entidad integer, p_id_local integer, p_id_local_servicio integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_listar_servicios(p_uuid_usuario uuid, p_id_entidad integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_listar_servicios(p_uuid_usuario uuid, p_id_entidad integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_listar_servicios(p_uuid_usuario uuid, p_id_entidad integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_listar_vendedores(p_id_entidad integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_listar_vendedores(p_id_entidad integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_listar_vendedores(p_id_entidad integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_notificacion_marcar(p_id bigint, p_estado text, p_error text) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_notificacion_marcar(p_id bigint, p_estado text, p_error text) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_notificacion_marcar(p_id bigint, p_estado text, p_error text) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_notificaciones_pendientes(p_limit integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_notificaciones_pendientes(p_limit integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_notificaciones_pendientes(p_limit integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_obtener_config_plan(p_uuid_usuario uuid, p_id_local_servicio integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_obtener_config_plan(p_uuid_usuario uuid, p_id_local_servicio integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_obtener_config_plan(p_uuid_usuario uuid, p_id_local_servicio integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_obtener_fidelidad_config(p_uuid_usuario uuid) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_obtener_fidelidad_config(p_uuid_usuario uuid) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_obtener_fidelidad_config(p_uuid_usuario uuid) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_ocultar_categoria_entidad(p_id_entidad integer, p_id_tipo_actividad integer, p_oculto boolean) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_ocultar_categoria_entidad(p_id_entidad integer, p_id_tipo_actividad integer, p_oculto boolean) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_ocultar_categoria_entidad(p_id_entidad integer, p_id_tipo_actividad integer, p_oculto boolean) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_plan_eliminar(p_id bigint) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_plan_eliminar(p_id bigint) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_plan_eliminar(p_id bigint) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_plan_guardar(p_id bigint, p_codigo text, p_nombre text, p_descripcion text, p_duracion_dias integer, p_precio numeric, p_moneda text, p_limites jsonb, p_orden integer, p_activo boolean) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_plan_guardar(p_id bigint, p_codigo text, p_nombre text, p_descripcion text, p_duracion_dias integer, p_precio numeric, p_moneda text, p_limites jsonb, p_orden integer, p_activo boolean) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_plan_guardar(p_id bigint, p_codigo text, p_nombre text, p_descripcion text, p_duracion_dias integer, p_precio numeric, p_moneda text, p_limites jsonb, p_orden integer, p_activo boolean) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_planes_listar() FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_planes_listar() TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_planes_listar() TO service_role;
REVOKE ALL ON FUNCTION flow.admin_planificar_dia(p_uuid_usuario uuid, p_id_local_servicio integer, p_fecha date, p_caps jsonb, p_cantidad integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_planificar_dia(p_uuid_usuario uuid, p_id_local_servicio integer, p_fecha date, p_caps jsonb, p_cantidad integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_planificar_dia(p_uuid_usuario uuid, p_id_local_servicio integer, p_fecha date, p_caps jsonb, p_cantidad integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_reservar_pasaje_omnibus(p_uuid_admin uuid, p_id_local_servicio integer, p_tipo_viaje character varying, p_fecha_ida date, p_id_turno_ida integer, p_fecha_vuelta date, p_id_turno_vuelta integer, p_cantidad integer, p_datos_adicionales jsonb, p_moneda text) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_reservar_pasaje_omnibus(p_uuid_admin uuid, p_id_local_servicio integer, p_tipo_viaje character varying, p_fecha_ida date, p_id_turno_ida integer, p_fecha_vuelta date, p_id_turno_vuelta integer, p_cantidad integer, p_datos_adicionales jsonb, p_moneda text) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_reservar_pasaje_omnibus(p_uuid_admin uuid, p_id_local_servicio integer, p_tipo_viaje character varying, p_fecha_ida date, p_id_turno_ida integer, p_fecha_vuelta date, p_id_turno_vuelta integer, p_cantidad integer, p_datos_adicionales jsonb, p_moneda text) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_set_reserva_directa(p_uuid_usuario uuid, p_id_local_servicio integer, p_permite boolean) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_set_reserva_directa(p_uuid_usuario uuid, p_id_local_servicio integer, p_permite boolean) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_set_reserva_directa(p_uuid_usuario uuid, p_id_local_servicio integer, p_permite boolean) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_suscripcion_acreditar(p_id_entidad integer, p_dias integer, p_id_plan bigint, p_motivo text) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_suscripcion_acreditar(p_id_entidad integer, p_dias integer, p_id_plan bigint, p_motivo text) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_suscripcion_acreditar(p_id_entidad integer, p_dias integer, p_id_plan bigint, p_motivo text) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_suscripcion_aprobar_pago(p_id_transaccion bigint, p_observaciones text) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_suscripcion_aprobar_pago(p_id_transaccion bigint, p_observaciones text) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_suscripcion_aprobar_pago(p_id_transaccion bigint, p_observaciones text) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_suscripcion_detalle(p_id_entidad integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_suscripcion_detalle(p_id_entidad integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_suscripcion_detalle(p_id_entidad integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_suscripcion_inicializar(p_dias integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_suscripcion_inicializar(p_dias integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_suscripcion_inicializar(p_dias integer) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_suscripcion_listar(p_filtro text, p_buscar text) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_suscripcion_listar(p_filtro text, p_buscar text) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_suscripcion_listar(p_filtro text, p_buscar text) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_suscripcion_reactivar(p_id_entidad integer, p_motivo text) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_suscripcion_reactivar(p_id_entidad integer, p_motivo text) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_suscripcion_reactivar(p_id_entidad integer, p_motivo text) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_suscripcion_rechazar_pago(p_id_transaccion bigint, p_motivo text) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_suscripcion_rechazar_pago(p_id_transaccion bigint, p_motivo text) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_suscripcion_rechazar_pago(p_id_transaccion bigint, p_motivo text) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_suscripcion_suspender(p_id_entidad integer, p_motivo text) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_suscripcion_suspender(p_id_entidad integer, p_motivo text) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_suscripcion_suspender(p_id_entidad integer, p_motivo text) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_update_perfil(p_uuid_usuario uuid, p_nombre text, p_apellidos text, p_ci text, p_telefono text) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_update_perfil(p_uuid_usuario uuid, p_nombre text, p_apellidos text, p_ci text, p_telefono text) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_update_perfil(p_uuid_usuario uuid, p_nombre text, p_apellidos text, p_ci text, p_telefono text) TO service_role;
REVOKE ALL ON FUNCTION flow.admin_update_plan_servicio(p_id integer, p_fecha date, p_cantidad integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.admin_update_plan_servicio(p_id integer, p_fecha date, p_cantidad integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.admin_update_plan_servicio(p_id integer, p_fecha date, p_cantidad integer) TO service_role;
REVOKE ALL ON FUNCTION flow.bot_procesar_plan(p_id_plan bigint) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.bot_procesar_plan(p_id_plan bigint) TO service_role;
REVOKE ALL ON FUNCTION flow.bot_procesar_recurso_dia(p_id_turno integer, p_fecha date) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.bot_procesar_recurso_dia(p_id_turno integer, p_fecha date) TO authenticated; GRANT EXECUTE ON FUNCTION flow.bot_procesar_recurso_dia(p_id_turno integer, p_fecha date) TO service_role;
REVOKE ALL ON FUNCTION flow.bot_sweep() FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.bot_sweep() TO authenticated; GRANT EXECUTE ON FUNCTION flow.bot_sweep() TO anon; GRANT EXECUTE ON FUNCTION flow.bot_sweep() TO service_role;
REVOKE ALL ON FUNCTION flow.calcular_precio_con_reglas(p_id_servicio integer, p_datos jsonb, p_moneda text, p_cantidad integer, p_base_unit numeric) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.calcular_precio_con_reglas(p_id_servicio integer, p_datos jsonb, p_moneda text, p_cantidad integer, p_base_unit numeric) TO authenticated; GRANT EXECUTE ON FUNCTION flow.calcular_precio_con_reglas(p_id_servicio integer, p_datos jsonb, p_moneda text, p_cantidad integer, p_base_unit numeric) TO service_role; GRANT EXECUTE ON FUNCTION flow.calcular_precio_con_reglas(p_id_servicio integer, p_datos jsonb, p_moneda text, p_cantidad integer, p_base_unit numeric) TO PUBLIC;
REVOKE ALL ON FUNCTION flow.calcular_precio_reserva(p_id_servicio integer, p_datos jsonb, p_moneda text, p_cantidad integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.calcular_precio_reserva(p_id_servicio integer, p_datos jsonb, p_moneda text, p_cantidad integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.calcular_precio_reserva(p_id_servicio integer, p_datos jsonb, p_moneda text, p_cantidad integer) TO PUBLIC;
REVOKE ALL ON FUNCTION flow.calcular_precio_turno(p_id_servicio integer, p_id_turno integer, p_datos jsonb, p_moneda text, p_cantidad integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.calcular_precio_turno(p_id_servicio integer, p_id_turno integer, p_datos jsonb, p_moneda text, p_cantidad integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.calcular_precio_turno(p_id_servicio integer, p_id_turno integer, p_datos jsonb, p_moneda text, p_cantidad integer) TO PUBLIC;
REVOKE ALL ON FUNCTION flow.campanas_activas() FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.campanas_activas() TO authenticated; GRANT EXECUTE ON FUNCTION flow.campanas_activas() TO service_role;
REVOKE ALL ON FUNCTION flow.cliente_actualizar_fecha_regla(p_uuid_usuario uuid, p_id_sala_espera integer, p_fecha_regla date) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.cliente_actualizar_fecha_regla(p_uuid_usuario uuid, p_id_sala_espera integer, p_fecha_regla date) TO authenticated; GRANT EXECUTE ON FUNCTION flow.cliente_actualizar_fecha_regla(p_uuid_usuario uuid, p_id_sala_espera integer, p_fecha_regla date) TO anon; GRANT EXECUTE ON FUNCTION flow.cliente_actualizar_fecha_regla(p_uuid_usuario uuid, p_id_sala_espera integer, p_fecha_regla date) TO PUBLIC;
REVOKE ALL ON FUNCTION flow.cliente_cancelar_reserva(p_uuid_usuario uuid, p_id_agenda integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.cliente_cancelar_reserva(p_uuid_usuario uuid, p_id_agenda integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.cliente_cancelar_reserva(p_uuid_usuario uuid, p_id_agenda integer) TO anon;
REVOKE ALL ON FUNCTION flow.cliente_crear_intent_suscripcion(p_id_entidad integer, p_id_plan bigint) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.cliente_crear_intent_suscripcion(p_id_entidad integer, p_id_plan bigint) TO authenticated; GRANT EXECUTE ON FUNCTION flow.cliente_crear_intent_suscripcion(p_id_entidad integer, p_id_plan bigint) TO service_role;
REVOKE ALL ON FUNCTION flow.cliente_entrar_sala_espera_cola(p_uuid_usuario uuid, p_id_local_servicio integer, p_fecha_regla timestamp without time zone, p_datos_adicionales jsonb, p_para_tercero boolean, p_t_nombre text, p_t_apellidos text, p_t_ci text, p_t_telefono text) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.cliente_entrar_sala_espera_cola(p_uuid_usuario uuid, p_id_local_servicio integer, p_fecha_regla timestamp without time zone, p_datos_adicionales jsonb, p_para_tercero boolean, p_t_nombre text, p_t_apellidos text, p_t_ci text, p_t_telefono text) TO authenticated; GRANT EXECUTE ON FUNCTION flow.cliente_entrar_sala_espera_cola(p_uuid_usuario uuid, p_id_local_servicio integer, p_fecha_regla timestamp without time zone, p_datos_adicionales jsonb, p_para_tercero boolean, p_t_nombre text, p_t_apellidos text, p_t_ci text, p_t_telefono text) TO anon; GRANT EXECUTE ON FUNCTION flow.cliente_entrar_sala_espera_cola(p_uuid_usuario uuid, p_id_local_servicio integer, p_fecha_regla timestamp without time zone, p_datos_adicionales jsonb, p_para_tercero boolean, p_t_nombre text, p_t_apellidos text, p_t_ci text, p_t_telefono text) TO PUBLIC;
REVOKE ALL ON FUNCTION flow.cliente_entrar_sala_espera_reserva(p_uuid_usuario uuid, p_id_local_servicio integer, p_fecha_regla timestamp without time zone, p_datos_adicionales jsonb, p_para_tercero boolean, p_t_nombre text, p_t_apellidos text, p_t_ci text, p_t_telefono text, p_id_turno integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.cliente_entrar_sala_espera_reserva(p_uuid_usuario uuid, p_id_local_servicio integer, p_fecha_regla timestamp without time zone, p_datos_adicionales jsonb, p_para_tercero boolean, p_t_nombre text, p_t_apellidos text, p_t_ci text, p_t_telefono text, p_id_turno integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.cliente_entrar_sala_espera_reserva(p_uuid_usuario uuid, p_id_local_servicio integer, p_fecha_regla timestamp without time zone, p_datos_adicionales jsonb, p_para_tercero boolean, p_t_nombre text, p_t_apellidos text, p_t_ci text, p_t_telefono text, p_id_turno integer) TO anon; GRANT EXECUTE ON FUNCTION flow.cliente_entrar_sala_espera_reserva(p_uuid_usuario uuid, p_id_local_servicio integer, p_fecha_regla timestamp without time zone, p_datos_adicionales jsonb, p_para_tercero boolean, p_t_nombre text, p_t_apellidos text, p_t_ci text, p_t_telefono text, p_id_turno integer) TO PUBLIC;
REVOKE ALL ON FUNCTION flow.cliente_estado_suscripcion(p_id_entidad integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.cliente_estado_suscripcion(p_id_entidad integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.cliente_estado_suscripcion(p_id_entidad integer) TO anon; GRANT EXECUTE ON FUNCTION flow.cliente_estado_suscripcion(p_id_entidad integer) TO service_role;
REVOKE ALL ON FUNCTION flow.cliente_home_feed(p_query text, p_id_categoria integer, p_provincia text, p_id_coleccion integer, p_mejor_valorados boolean, p_id_subcategoria integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.cliente_home_feed(p_query text, p_id_categoria integer, p_provincia text, p_id_coleccion integer, p_mejor_valorados boolean, p_id_subcategoria integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.cliente_home_feed(p_query text, p_id_categoria integer, p_provincia text, p_id_coleccion integer, p_mejor_valorados boolean, p_id_subcategoria integer) TO service_role;
REVOKE ALL ON FUNCTION flow.cliente_listar_servicios(p_id_entidad integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.cliente_listar_servicios(p_id_entidad integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.cliente_listar_servicios(p_id_entidad integer) TO anon; GRANT EXECUTE ON FUNCTION flow.cliente_listar_servicios(p_id_entidad integer) TO PUBLIC;
REVOKE ALL ON FUNCTION flow.cliente_marcar_intent_abierto(p_id_intent bigint) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.cliente_marcar_intent_abierto(p_id_intent bigint) TO authenticated; GRANT EXECUTE ON FUNCTION flow.cliente_marcar_intent_abierto(p_id_intent bigint) TO service_role;
REVOKE ALL ON FUNCTION flow.cliente_mi_fidelidad() FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.cliente_mi_fidelidad() TO authenticated; GRANT EXECUTE ON FUNCTION flow.cliente_mi_fidelidad() TO service_role;
REVOKE ALL ON FUNCTION flow.cliente_mis_pagos_suscripcion(p_id_entidad integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.cliente_mis_pagos_suscripcion(p_id_entidad integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.cliente_mis_pagos_suscripcion(p_id_entidad integer) TO service_role;
REVOKE ALL ON FUNCTION flow.cliente_obtener_agendas(p_uuid_usuario uuid, p_id_estado integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.cliente_obtener_agendas(p_uuid_usuario uuid, p_id_estado integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.cliente_obtener_agendas(p_uuid_usuario uuid, p_id_estado integer) TO anon; GRANT EXECUTE ON FUNCTION flow.cliente_obtener_agendas(p_uuid_usuario uuid, p_id_estado integer) TO PUBLIC;
REVOKE ALL ON FUNCTION flow.cliente_obtener_disponibilidad(p_id_local_servicio integer, p_desde date, p_hasta date) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.cliente_obtener_disponibilidad(p_id_local_servicio integer, p_desde date, p_hasta date) TO authenticated; GRANT EXECUTE ON FUNCTION flow.cliente_obtener_disponibilidad(p_id_local_servicio integer, p_desde date, p_hasta date) TO anon; GRANT EXECUTE ON FUNCTION flow.cliente_obtener_disponibilidad(p_id_local_servicio integer, p_desde date, p_hasta date) TO PUBLIC;
REVOKE ALL ON FUNCTION flow.cliente_obtener_disponibilidad_transporte(p_id_local_servicio integer, p_fecha date, p_tipo_trayecto character varying) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.cliente_obtener_disponibilidad_transporte(p_id_local_servicio integer, p_fecha date, p_tipo_trayecto character varying) TO authenticated; GRANT EXECUTE ON FUNCTION flow.cliente_obtener_disponibilidad_transporte(p_id_local_servicio integer, p_fecha date, p_tipo_trayecto character varying) TO anon; GRANT EXECUTE ON FUNCTION flow.cliente_obtener_disponibilidad_transporte(p_id_local_servicio integer, p_fecha date, p_tipo_trayecto character varying) TO PUBLIC;
REVOKE ALL ON FUNCTION flow.cliente_obtener_fechas_disponibles_transporte(p_id_local_servicio integer, p_tipo_trayecto character varying) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.cliente_obtener_fechas_disponibles_transporte(p_id_local_servicio integer, p_tipo_trayecto character varying) TO authenticated; GRANT EXECUTE ON FUNCTION flow.cliente_obtener_fechas_disponibles_transporte(p_id_local_servicio integer, p_tipo_trayecto character varying) TO anon; GRANT EXECUTE ON FUNCTION flow.cliente_obtener_fechas_disponibles_transporte(p_id_local_servicio integer, p_tipo_trayecto character varying) TO PUBLIC;
REVOKE ALL ON FUNCTION flow.cliente_obtener_locales(p_id_entidad integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.cliente_obtener_locales(p_id_entidad integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.cliente_obtener_locales(p_id_entidad integer) TO anon; GRANT EXECUTE ON FUNCTION flow.cliente_obtener_locales(p_id_entidad integer) TO PUBLIC;
REVOKE ALL ON FUNCTION flow.cliente_obtener_salas_espera(p_uuid_usuario uuid) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.cliente_obtener_salas_espera(p_uuid_usuario uuid) TO authenticated; GRANT EXECUTE ON FUNCTION flow.cliente_obtener_salas_espera(p_uuid_usuario uuid) TO anon; GRANT EXECUTE ON FUNCTION flow.cliente_obtener_salas_espera(p_uuid_usuario uuid) TO PUBLIC;
REVOKE ALL ON FUNCTION flow.cliente_obtener_servicios(p_id_local integer, p_id_servicio integer, p_id_entidad integer, p_nombre_local text, p_nombre_servicio text, p_pais text, p_provincia text, p_incluir_inactivos boolean) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.cliente_obtener_servicios(p_id_local integer, p_id_servicio integer, p_id_entidad integer, p_nombre_local text, p_nombre_servicio text, p_pais text, p_provincia text, p_incluir_inactivos boolean) TO authenticated; GRANT EXECUTE ON FUNCTION flow.cliente_obtener_servicios(p_id_local integer, p_id_servicio integer, p_id_entidad integer, p_nombre_local text, p_nombre_servicio text, p_pais text, p_provincia text, p_incluir_inactivos boolean) TO service_role; GRANT EXECUTE ON FUNCTION flow.cliente_obtener_servicios(p_id_local integer, p_id_servicio integer, p_id_entidad integer, p_nombre_local text, p_nombre_servicio text, p_pais text, p_provincia text, p_incluir_inactivos boolean) TO PUBLIC;
REVOKE ALL ON FUNCTION flow.cliente_planes_suscripcion() FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.cliente_planes_suscripcion() TO authenticated; GRANT EXECUTE ON FUNCTION flow.cliente_planes_suscripcion() TO anon; GRANT EXECUTE ON FUNCTION flow.cliente_planes_suscripcion() TO service_role;
REVOKE ALL ON FUNCTION flow.cliente_ranking_semanal(p_limite integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.cliente_ranking_semanal(p_limite integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.cliente_ranking_semanal(p_limite integer) TO service_role;
REVOKE ALL ON FUNCTION flow.cliente_reportar_pago_suscripcion(p_id_intent bigint, p_codigo_confirmacion text, p_comprobante_url text) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.cliente_reportar_pago_suscripcion(p_id_intent bigint, p_codigo_confirmacion text, p_comprobante_url text) TO authenticated; GRANT EXECUTE ON FUNCTION flow.cliente_reportar_pago_suscripcion(p_id_intent bigint, p_codigo_confirmacion text, p_comprobante_url text) TO service_role;
REVOKE ALL ON FUNCTION flow.cliente_reservar_directo(p_uuid_usuario uuid, p_id_local_servicio integer, p_fecha date, p_cantidad integer, p_datos_adicionales jsonb, p_para_tercero boolean, p_t_nombre text, p_t_apellidos text, p_t_ci text, p_t_telefono text, p_moneda text, p_id_turno integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.cliente_reservar_directo(p_uuid_usuario uuid, p_id_local_servicio integer, p_fecha date, p_cantidad integer, p_datos_adicionales jsonb, p_para_tercero boolean, p_t_nombre text, p_t_apellidos text, p_t_ci text, p_t_telefono text, p_moneda text, p_id_turno integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.cliente_reservar_directo(p_uuid_usuario uuid, p_id_local_servicio integer, p_fecha date, p_cantidad integer, p_datos_adicionales jsonb, p_para_tercero boolean, p_t_nombre text, p_t_apellidos text, p_t_ci text, p_t_telefono text, p_moneda text, p_id_turno integer) TO service_role;
REVOKE ALL ON FUNCTION flow.cliente_reservar_pasaje_omnibus(p_uuid_usuario uuid, p_id_local_servicio integer, p_tipo_viaje character varying, p_fecha_ida date, p_id_turno_ida integer, p_fecha_vuelta date, p_id_turno_vuelta integer, p_cantidad integer, p_datos_adicionales jsonb, p_moneda text, p_para_tercero boolean, p_t_nombre text, p_t_apellidos text, p_t_ci text, p_t_telefono text) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.cliente_reservar_pasaje_omnibus(p_uuid_usuario uuid, p_id_local_servicio integer, p_tipo_viaje character varying, p_fecha_ida date, p_id_turno_ida integer, p_fecha_vuelta date, p_id_turno_vuelta integer, p_cantidad integer, p_datos_adicionales jsonb, p_moneda text, p_para_tercero boolean, p_t_nombre text, p_t_apellidos text, p_t_ci text, p_t_telefono text) TO authenticated; GRANT EXECUTE ON FUNCTION flow.cliente_reservar_pasaje_omnibus(p_uuid_usuario uuid, p_id_local_servicio integer, p_tipo_viaje character varying, p_fecha_ida date, p_id_turno_ida integer, p_fecha_vuelta date, p_id_turno_vuelta integer, p_cantidad integer, p_datos_adicionales jsonb, p_moneda text, p_para_tercero boolean, p_t_nombre text, p_t_apellidos text, p_t_ci text, p_t_telefono text) TO PUBLIC;
REVOKE ALL ON FUNCTION flow.cliente_salir_sala_espera(p_uuid_usuario uuid, p_id_local_servicio integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.cliente_salir_sala_espera(p_uuid_usuario uuid, p_id_local_servicio integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.cliente_salir_sala_espera(p_uuid_usuario uuid, p_id_local_servicio integer) TO anon; GRANT EXECUTE ON FUNCTION flow.cliente_salir_sala_espera(p_uuid_usuario uuid, p_id_local_servicio integer) TO PUBLIC;
REVOKE ALL ON FUNCTION flow.colecciones_activas() FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.colecciones_activas() TO authenticated; GRANT EXECUTE ON FUNCTION flow.colecciones_activas() TO service_role;
REVOKE ALL ON FUNCTION flow.cotizar_reserva(p_uuid_usuario uuid, p_id_local_servicio integer, p_datos jsonb, p_moneda text, p_cantidad integer, p_id_turno integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.cotizar_reserva(p_uuid_usuario uuid, p_id_local_servicio integer, p_datos jsonb, p_moneda text, p_cantidad integer, p_id_turno integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.cotizar_reserva(p_uuid_usuario uuid, p_id_local_servicio integer, p_datos jsonb, p_moneda text, p_cantidad integer, p_id_turno integer) TO service_role;
REVOKE ALL ON FUNCTION flow.eliminar_mi_resena(p_uuid_usuario uuid, p_id_resena bigint) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.eliminar_mi_resena(p_uuid_usuario uuid, p_id_resena bigint) TO authenticated; GRANT EXECUTE ON FUNCTION flow.eliminar_mi_resena(p_uuid_usuario uuid, p_id_resena bigint) TO service_role;
REVOKE ALL ON FUNCTION flow.entidad_activa(p_id_entidad integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.entidad_activa(p_id_entidad integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.entidad_activa(p_id_entidad integer) TO anon; GRANT EXECUTE ON FUNCTION flow.entidad_activa(p_id_entidad integer) TO service_role;
REVOKE ALL ON FUNCTION flow.es_admin_de_la_imagen(p_name text) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.es_admin_de_la_imagen(p_name text) TO authenticated; GRANT EXECUTE ON FUNCTION flow.es_admin_de_la_imagen(p_name text) TO service_role; GRANT EXECUTE ON FUNCTION flow.es_admin_de_la_imagen(p_name text) TO PUBLIC;
REVOKE ALL ON FUNCTION flow.fn_saldo_puntos(p_uuid_usuario uuid) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.fn_saldo_puntos(p_uuid_usuario uuid) TO authenticated; GRANT EXECUTE ON FUNCTION flow.fn_saldo_puntos(p_uuid_usuario uuid) TO service_role;
REVOKE ALL ON FUNCTION flow.get_uuid_by_email(p_email text) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.get_uuid_by_email(p_email text) TO authenticated; GRANT EXECUTE ON FUNCTION flow.get_uuid_by_email(p_email text) TO anon; GRANT EXECUTE ON FUNCTION flow.get_uuid_by_email(p_email text) TO PUBLIC;
REVOKE ALL ON FUNCTION flow.is_entidad_admin(p_id_entidad integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.is_entidad_admin(p_id_entidad integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.is_entidad_admin(p_id_entidad integer) TO anon; GRANT EXECUTE ON FUNCTION flow.is_entidad_admin(p_id_entidad integer) TO PUBLIC;
REVOKE ALL ON FUNCTION flow.promociones_de_servicio(p_id_local_servicio integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.promociones_de_servicio(p_id_local_servicio integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.promociones_de_servicio(p_id_local_servicio integer) TO service_role;
REVOKE ALL ON FUNCTION flow.promociones_por_servicio() FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.promociones_por_servicio() TO authenticated; GRANT EXECUTE ON FUNCTION flow.promociones_por_servicio() TO service_role;
REVOKE ALL ON FUNCTION flow.publicar_resena(p_uuid_usuario uuid, p_id_agenda integer, p_puntuacion smallint, p_comentario text) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.publicar_resena(p_uuid_usuario uuid, p_id_agenda integer, p_puntuacion smallint, p_comentario text) TO authenticated; GRANT EXECUTE ON FUNCTION flow.publicar_resena(p_uuid_usuario uuid, p_id_agenda integer, p_puntuacion smallint, p_comentario text) TO service_role;
REVOKE ALL ON FUNCTION flow.resenas_de_servicio(p_id_local_servicio integer, p_limit integer, p_offset integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.resenas_de_servicio(p_id_local_servicio integer, p_limit integer, p_offset integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.resenas_de_servicio(p_id_local_servicio integer, p_limit integer, p_offset integer) TO service_role;
REVOKE ALL ON FUNCTION flow.resenas_por_servicio() FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.resenas_por_servicio() TO authenticated; GRANT EXECUTE ON FUNCTION flow.resenas_por_servicio() TO service_role;
REVOKE ALL ON FUNCTION flow.resenas_recientes(p_limit integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.resenas_recientes(p_limit integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.resenas_recientes(p_limit integer) TO service_role;
REVOKE ALL ON FUNCTION flow.staff_cancelar_reserva(p_id_agenda integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.staff_cancelar_reserva(p_id_agenda integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.staff_cancelar_reserva(p_id_agenda integer) TO service_role;
REVOKE ALL ON FUNCTION flow.staff_marcar_estado_agenda(p_id_agenda integer, p_id_estado integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.staff_marcar_estado_agenda(p_id_agenda integer, p_id_estado integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.staff_marcar_estado_agenda(p_id_agenda integer, p_id_estado integer) TO service_role;
REVOKE ALL ON FUNCTION flow.suscripcion_expirar() FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.suscripcion_expirar() TO authenticated; GRANT EXECUTE ON FUNCTION flow.suscripcion_expirar() TO service_role;
REVOKE ALL ON FUNCTION flow.trg_agenda_acreditar_puntos() FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.trg_agenda_acreditar_puntos() TO service_role;
REVOKE ALL ON FUNCTION flow.trg_plan_servicio_procesar() FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.trg_plan_servicio_procesar() TO authenticated; GRANT EXECUTE ON FUNCTION flow.trg_plan_servicio_procesar() TO anon; GRANT EXECUTE ON FUNCTION flow.trg_plan_servicio_procesar() TO PUBLIC;
REVOKE ALL ON FUNCTION flow.trg_plan_tramo_procesar() FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.trg_plan_tramo_procesar() TO authenticated; GRANT EXECUTE ON FUNCTION flow.trg_plan_tramo_procesar() TO PUBLIC;
REVOKE ALL ON FUNCTION flow.update_updated_at_column() FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.update_updated_at_column() TO authenticated; GRANT EXECUTE ON FUNCTION flow.update_updated_at_column() TO anon; GRANT EXECUTE ON FUNCTION flow.update_updated_at_column() TO PUBLIC;
REVOKE ALL ON FUNCTION flow.validar_jerarquia_tipo_actividad() FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.validar_jerarquia_tipo_actividad() TO authenticated; GRANT EXECUTE ON FUNCTION flow.validar_jerarquia_tipo_actividad() TO service_role; GRANT EXECUTE ON FUNCTION flow.validar_jerarquia_tipo_actividad() TO PUBLIC;
REVOKE ALL ON FUNCTION flow.vendedor_entidades_de_usuario(p_uuid_usuario uuid) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.vendedor_entidades_de_usuario(p_uuid_usuario uuid) TO authenticated; GRANT EXECUTE ON FUNCTION flow.vendedor_entidades_de_usuario(p_uuid_usuario uuid) TO service_role;
REVOKE ALL ON FUNCTION flow.vendedor_listar_agendas(p_uuid_usuario uuid, p_id_entidad integer, p_id_local integer, p_id_local_servicio integer, p_id_estado integer, p_desde timestamp without time zone, p_hasta timestamp without time zone) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.vendedor_listar_agendas(p_uuid_usuario uuid, p_id_entidad integer, p_id_local integer, p_id_local_servicio integer, p_id_estado integer, p_desde timestamp without time zone, p_hasta timestamp without time zone) TO authenticated; GRANT EXECUTE ON FUNCTION flow.vendedor_listar_agendas(p_uuid_usuario uuid, p_id_entidad integer, p_id_local integer, p_id_local_servicio integer, p_id_estado integer, p_desde timestamp without time zone, p_hasta timestamp without time zone) TO service_role;
REVOKE ALL ON FUNCTION flow.vendedor_listar_agendas_por_estado(p_uuid_usuario uuid, p_id_entidad integer, p_id_local integer, p_id_local_servicio integer, p_id_estado integer) FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE ON FUNCTION flow.vendedor_listar_agendas_por_estado(p_uuid_usuario uuid, p_id_entidad integer, p_id_local integer, p_id_local_servicio integer, p_id_estado integer) TO authenticated; GRANT EXECUTE ON FUNCTION flow.vendedor_listar_agendas_por_estado(p_uuid_usuario uuid, p_id_entidad integer, p_id_local integer, p_id_local_servicio integer, p_id_estado integer) TO service_role;


-- ============================================================
-- 14. Datos semilla (nomencladores y configuracion de main)
-- ============================================================
-- En NEWA estas tablas estan vacias: sin `nom_estado_agenda` ninguna reserva
-- puede crearse (FK id_estado) y sin categorias no se pueden crear servicios.
INSERT INTO flow.nom_estado_agenda (id, nombre, descripcion) VALUES
  (1, 'Reservado', 'Turno reservado por el usuario'),
  (2, 'Cancelado', 'Turno cancelado por el usuario o sistema'),
  (3, 'Completado', 'Turno ya atendido y completado')
ON CONFLICT (id) DO UPDATE SET nombre = EXCLUDED.nombre, descripcion = EXCLUDED.descripcion;
SELECT setval('flow.nom_estado_agenda_id_seq', (SELECT max(id) FROM flow.nom_estado_agenda));

-- Categorias raiz primero; despues las subcategorias (el trigger de jerarquia
-- consulta al padre).
INSERT INTO flow.nom_tipo_actividad_servicio (id, codigo, nombre, activo, id_padre, orden) OVERRIDING SYSTEM VALUE VALUES
  (1, 'general', 'General', false, NULL, 0),
  (6, 'belleza', 'Belleza', true, NULL, 30),
  (11, 'salud', 'Salud', false, NULL, 0),
  (12, 'hogar', 'Hogar y Reparaciones', false, NULL, 0),
  (13, 'mascotas', 'Mascotas', false, NULL, 0),
  (14, 'gastronomia', 'Gastronomía', true, NULL, 20),
  (15, 'eventos', 'Eventos y Celebraciones', false, NULL, 0),
  (16, 'tecnologia', 'Tecnología', false, NULL, 0),
  (20, 'alojamiento', 'Alojamiento', true, NULL, 10),
  (23, 'transporte', 'Transporte', true, NULL, 40),
  (24, 'recreacion', 'Recreación', true, NULL, 50),
  (25, 'juridicos', 'Jurídicos', true, NULL, 60)
ON CONFLICT (id) DO UPDATE SET codigo = EXCLUDED.codigo, nombre = EXCLUDED.nombre, activo = EXCLUDED.activo, id_padre = EXCLUDED.id_padre, orden = EXCLUDED.orden;

INSERT INTO flow.nom_tipo_actividad_servicio (id, codigo, nombre, activo, id_padre, orden) OVERRIDING SYSTEM VALUE VALUES
  (2, 'transporte_omnibus', 'Transporte en ómnibus', true, 23, 10),
  (7, 'unas', 'Uñas / Manicure', false, 6, 20),
  (8, 'cejas_pestanas', 'Cejas y Pestañas', false, 6, 30),
  (9, 'peluqueria', 'Peluquería / Barbería', false, 6, 10),
  (10, 'estetica_spa', 'Estética / Spa', false, 6, 40),
  (18, 'transporte_privado', 'Transporte privado / Taxi', true, 23, 20),
  (26, 'hoteleria_hostal', 'Hotelería / Hostal', true, 20, 10),
  (27, 'casa_particular_apartamento', 'Casa particular / Apartamento', true, 20, 20),
  (28, 'campismo_cabanas', 'Campismo / Cabañas', true, 20, 30),
  (29, 'alojamiento_rural_finca', 'Alojamiento rural / Finca', true, 20, 40),
  (30, 'resort_todo_incluido', 'Resort / Todo incluido', true, 20, 50),
  (31, 'restaurantes', 'Restaurantes', true, 14, 10),
  (32, 'cafeteria', 'Cafetería', true, 14, 20),
  (33, 'paladar_comida_criolla', 'Paladar / Comida criolla', true, 14, 30),
  (34, 'bar_cocteleria', 'Bar / Coctelería', true, 14, 40),
  (35, 'reposteria_panaderia', 'Repostería / Panadería', true, 14, 50),
  (40, 'maquillaje', 'Maquillaje', false, 6, 50),
  (43, 'alquiler_vehiculos', 'Alquiler de vehículos', true, 23, 30),
  (44, 'talleres_gasolineras', 'Talleres / Gasolineras', true, 23, 40),
  (45, 'grua_fregado_carros', 'Grúa / Fregado de carros', true, 23, 50),
  (46, 'turismo_excursiones', 'Turismo / Excursiones', true, 24, 10),
  (47, 'cine_teatro', 'Cine / Teatro', true, 24, 20),
  (48, 'fiestas_eventos', 'Fiestas / Eventos', true, 24, 30),
  (49, 'deportes_gimnasio', 'Deportes / Gimnasio', true, 24, 40),
  (50, 'parques_entretenimiento', 'Parques / Entretenimiento', true, 24, 50),
  (51, 'asesoria_legal', 'Asesoría legal', true, 25, 10),
  (52, 'notaria_documentos', 'Notaría / Documentos', true, 25, 20),
  (53, 'penal_civil', 'Penal / Civil', true, 25, 30),
  (54, 'laboral_migratorio', 'Laboral / Migratorio', true, 25, 40),
  (55, 'contabilidad_fiscal', 'Contabilidad / Fiscal', true, 25, 50)
ON CONFLICT (id) DO UPDATE SET codigo = EXCLUDED.codigo, nombre = EXCLUDED.nombre, activo = EXCLUDED.activo, id_padre = EXCLUDED.id_padre, orden = EXCLUDED.orden;
SELECT setval(pg_get_serial_sequence('flow.nom_tipo_actividad_servicio', 'id'), (SELECT max(id) FROM flow.nom_tipo_actividad_servicio));

-- OJO: precios y modo_prueba copiados tal cual de main (valores de prueba).
INSERT INTO flow.suscripcion_plan (id, codigo, nombre, descripcion, duracion_dias, precio, moneda, limites, orden, activo) OVERRIDING SYSTEM VALUE VALUES
  (1, 'flow_mensual', 'Mensual', 'Suscripcion de 1 mes (30 dias)', 30, 1.00, 'CUP', '{}'::jsonb, 10, true),
  (2, 'flow_trimestral', 'Trimestral', 'Suscripcion de 3 meses (90 dias)', 90, 2.00, 'CUP', '{}'::jsonb, 20, true),
  (3, 'flow_anual', 'Anual', 'Suscripcion de 12 meses (365 dias)', 365, 3.00, 'CUP', '{}'::jsonb, 30, true)
ON CONFLICT (id) DO NOTHING;
SELECT setval(pg_get_serial_sequence('flow.suscripcion_plan', 'id'), (SELECT max(id) FROM flow.suscripcion_plan));

INSERT INTO flow.suscripcion_config (id, trial_meses_default, trial_auto, trial_por_usuario, dias_gracia, dias_aviso_previo, soporte_whatsapp, whatsapp_notif_activa, whatsapp_bot_activo, transfermovil_numero_proveedor, transfermovil_titulo, transfermovil_intent_template, transfermovil_url_template, moneda_default, intent_horas_vigencia, modo_prueba) VALUES
  (1, 3, true, true, 7, 7, '5354590207', false, false, '4055432', 'Carnaval Alimentos',
   'transfermovil://tm_compra_en_linea/action?id_transaccion=$id_transaccion&importe=$importe&moneda=$moneda&numero_proveedor=$numero_proveedor&version=1.0.0&titulo=$titulo&set_title=$titulo',
   'https://transfermovil.app/action?id_transaccion=$id_transaccion&importe=$importe&moneda=$moneda&numero_proveedor=$numero_proveedor&version=5&titulo=$titulo&set_title=$titulo',
   'CUP', 24, true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO flow.fidelidad_config (id, activa) VALUES (1, true) ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- 15. Storage: politicas del bucket flow-imagenes (el bucket ya existe en newa)
-- ============================================================
DROP POLICY IF EXISTS flow_imagenes_delete_admin ON storage.objects;
CREATE POLICY flow_imagenes_delete_admin ON storage.objects AS PERMISSIVE FOR DELETE TO authenticated USING (((bucket_id = 'flow-imagenes'::text) AND flow.es_admin_de_la_imagen(name)));
DROP POLICY IF EXISTS flow_imagenes_insert_auth ON storage.objects;
CREATE POLICY flow_imagenes_insert_auth ON storage.objects AS PERMISSIVE FOR INSERT TO public WITH CHECK (((bucket_id = 'flow-imagenes'::text) AND (auth.role() = 'authenticated'::text)));
DROP POLICY IF EXISTS flow_imagenes_read_public ON storage.objects;
CREATE POLICY flow_imagenes_read_public ON storage.objects AS PERMISSIVE FOR SELECT TO public USING ((bucket_id = 'flow-imagenes'::text));
DROP POLICY IF EXISTS flow_imagenes_update_admin ON storage.objects;
CREATE POLICY flow_imagenes_update_admin ON storage.objects AS PERMISSIVE FOR UPDATE TO authenticated USING (((bucket_id = 'flow-imagenes'::text) AND flow.es_admin_de_la_imagen(name))) WITH CHECK (((bucket_id = 'flow-imagenes'::text) AND flow.es_admin_de_la_imagen(name)));

-- ============================================================
-- 16. Realtime (los errores RealtimeSubscribeException de reservas y
--     notificaciones vienen de que estas tablas no estaban publicadas)
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'flow' AND tablename = 'agenda') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE flow.agenda;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'flow' AND tablename = 'notificaciones') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE flow.notificaciones;
  END IF;
END $$;

-- Refresca el cache de esquema de PostgREST (causa del PGRST204 "activo").
NOTIFY pgrst, 'reload schema';

COMMIT;

-- ============================================================
-- OPCIONAL (fuera de la transaccion): job que vence suscripciones.
-- En main corre cada 15 min con pg_cron. NEWA no tiene pg_cron instalado:
-- activa la extension en Dashboard > Database > Extensions y luego ejecuta:
-- ============================================================
-- SELECT cron.schedule('flow-suscripciones-expirar', '*/15 * * * *', 'select flow.suscripcion_expirar();');
