-- ════════════════════════════════════════════════════════════════════════════
-- MIGRACION 45: SUSCRIPCIONES — PAGO (intent, reporte, verificacion, expiracion)
-- ════════════════════════════════════════════════════════════════════════════
--
-- QUE HACE
--   El circuito completo de pago por Transfermovil y la maquina de estados de la
--   suscripcion:
--
--     cliente_crear_intent_suscripcion   -> arma el deep link con un id_transaccion UNICO
--     cliente_reportar_pago_suscripcion  -> "Ya he pagado": guarda codigo + comprobante
--     cliente_mis_pagos_suscripcion      -> lo que la pantalla muestra al cliente
--     admin_suscripcion_aprobar_pago     -> el superadmin verifica y ACREDITA
--     admin_suscripcion_rechazar_pago    -> el superadmin rechaza con motivo
--     admin_suscripcion_acreditar        -> acreditacion manual (cortesia/ajuste)
--     suscripcion_expirar                -> barrido del cron: avisos y expiraciones
--     _susc_notificar_inapp / _susc_notificar_whatsapp
--
-- POR QUE ACREDITAR SUMA Y NO REINICIA
--   Decision del usuario: si el cliente paga antes de que le venza, los dias se
--   SUMAN al vencimiento actual. La base del calculo es
--   `greatest(vigente_hasta, now())`: nunca se acredita hacia atras ni se regala
--   menos de lo comprado. Un pago despues de la gracia arranca de `now()`.
--
-- POR QUE "YA HE PAGADO" NO ACREDITA NADA
--   El boton solo PONE EN COLA la verificacion. Con Transfermovil no hay callback
--   (ver el informe del plan: el deep link no devuelve resultado), asi que la
--   unica verdad es que el superadmin compruebe el pago en el banco. La app no
--   tiene forma de activar una suscripcion: no existe ningun RPC que lo haga sin
--   pasar por `admin_suscripcion_*`, todas protegidas por
--   `public.fn_is_superadmin_full_access()`.
--
-- POR QUE EL CODIGO DE CONFIRMACION ES OBLIGATORIO Y UNICO
--   Es la unica defensa anti-reuso. Sin el, el mismo pago podria acreditarse dos
--   veces. El UNIQUE esta en la tabla (migracion 43) y aqui se traduce el
--   `unique_violation` a un mensaje legible en vez de un error crudo.
--
-- POR QUE EL WHATSAPP AUTOMATICO NO SE ENVIA DESDE AQUI
--   La API de WhatsApp (WAPI) vive detras de una Edge Function con la X-API-Key
--   oculta; Postgres no debe llamar a la red desde un RPC. El aviso se escribe en
--   `flow.suscripcion_notificacion` (outbox) y lo despacha la Edge Function.
--   Mientras no haya bot (Q33) las filas nacen `omitida` y la app ofrece el
--   deep link `wa.me` con el mensaje ya redactado, que se devuelve en la respuesta.
--
-- DEPENDE DE: migraciones 43 (tablas) y 44 (predicado + helpers).
--
-- REVERSIBILIDAD
--   drop function if exists flow.suscripcion_expirar();
--   drop function if exists flow.admin_suscripcion_acreditar(integer,integer,bigint,text);
--   drop function if exists flow.admin_suscripcion_rechazar_pago(bigint,text);
--   drop function if exists flow.admin_suscripcion_aprobar_pago(bigint,text);
--   drop function if exists flow.cliente_mis_pagos_suscripcion(integer);
--   drop function if exists flow.cliente_reportar_pago_suscripcion(bigint,text,text);
--   drop function if exists flow.cliente_crear_intent_suscripcion(integer,bigint);
--   drop function if exists flow._susc_notificar_whatsapp(integer,text,text);
--   drop function if exists flow._susc_notificar_inapp(integer,uuid,text,text);
--
-- ORDEN: 45 va despues de 44 y antes de 46.
-- ════════════════════════════════════════════════════════════════════════════

-- ── Comprobacion previa ─────────────────────────────────────────────────────
do $pre$
begin
  if to_regclass('flow.suscripcion_intent') is null
     or to_regclass('flow.suscripcion_notificacion') is null then
    raise exception 'Falta la migracion 43 (tablas de suscripcion).';
  end if;

  if to_regprocedure('flow.entidad_activa(integer)') is null then
    raise exception 'Falta la migracion 44 (entidad_activa). Aplicala antes que la 45.';
  end if;
end
$pre$;

-- ══ 1. NOTIFICACIONES (outbox + campana in-app) ════════════════════════════

-- Aviso in-app: SIEMPRE se entrega (es una fila, no depende de nadie).
create or replace function flow._susc_notificar_inapp(
  p_id_entidad integer,
  p_uuid       uuid,
  p_titulo     text,
  p_mensaje    text
)
returns void
language plpgsql
security definer
set search_path to 'flow', 'public'
as $function$
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
$function$;

comment on function flow._susc_notificar_inapp(integer,uuid,text,text) is
  'Aviso in-app de suscripcion: outbox + flow.notificaciones (si el destinatario tiene perfil).';

-- Aviso por WhatsApp: se ENCOLA; no se envia desde Postgres.
create or replace function flow._susc_notificar_whatsapp(
  p_id_entidad integer,
  p_telefono   text,
  p_mensaje    text
)
returns void
language plpgsql
security definer
set search_path to 'flow', 'public'
as $function$
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
$function$;

comment on function flow._susc_notificar_whatsapp(integer,text,text) is
  'Encola un aviso de WhatsApp en el outbox. Con whatsapp_bot_activo=false queda en omitida y la app ofrece el deep link wa.me.';

revoke all on function flow._susc_notificar_inapp(integer,uuid,text,text) from public;
revoke all on function flow._susc_notificar_whatsapp(integer,text,text) from public;
grant execute on function flow._susc_notificar_inapp(integer,uuid,text,text) to service_role;
grant execute on function flow._susc_notificar_whatsapp(integer,text,text) to service_role;

-- ══ 2. CREAR EL INTENT DE PAGO ═════════════════════════════════════════════

create or replace function flow.cliente_crear_intent_suscripcion(
  p_id_entidad integer,
  p_id_plan    bigint
)
returns jsonb
language plpgsql
security definer
set search_path to 'flow', 'public'
as $function$
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

  -- id_transaccion UNICO: si se repite, Transfermovil reutiliza el importe de la
  -- transaccion anterior (lo sufrio Carnaval). Lleva entidad + fecha + azar.
  v_id_trx := 'FLW-' || p_id_entidad || '-' || to_char(now(), 'YYYYMMDDHH24MISS') || '-'
              || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));

  v_expira := now() + make_interval(hours => coalesce(v_cfg.intent_horas_vigencia, 24));

  v_url_intent := replace(replace(replace(replace(replace(
                    v_cfg.transfermovil_intent_template,
                    '$id_transaccion',   v_id_trx),
                    '$importe',          v_importe_txt),
                    '$moneda',           v_moneda),
                    '$numero_proveedor', v_cfg.transfermovil_numero_proveedor),
                    '$titulo',           v_cfg.transfermovil_titulo);

  v_url_http := replace(replace(replace(replace(replace(
                    v_cfg.transfermovil_url_template,
                    '$id_transaccion',   v_id_trx),
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
$function$;

comment on function flow.cliente_crear_intent_suscripcion(integer,bigint) is
  'Crea el intent de pago de Transfermovil con id_transaccion unico y devuelve el deep link y el respaldo https.';

-- ══ 3. "YA HE PAGADO": REPORTAR EL PAGO ════════════════════════════════════

create or replace function flow.cliente_reportar_pago_suscripcion(
  p_id_intent          bigint,
  p_codigo_confirmacion text,
  p_comprobante_url    text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'flow', 'public'
as $function$
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
            || '. Transaccion: ' || v_int.id_transaccion
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
$function$;

comment on function flow.cliente_reportar_pago_suscripcion(bigint,text,text) is
  'Boton "Ya he pagado": registra el codigo de confirmacion (UNICO) y el comprobante, avisa al dueno y encola el mensaje a soporte. NO acredita nada.';

-- ══ 4. LO QUE VE EL CLIENTE ════════════════════════════════════════════════

create or replace function flow.cliente_mis_pagos_suscripcion(p_id_entidad integer)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'flow', 'public'
as $function$
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
$function$;

comment on function flow.cliente_mis_pagos_suscripcion(integer) is
  'Intents, pagos y movimientos de la entidad para la pantalla "Mi suscripcion".';

-- ══ 5. SUPERADMIN: VERIFICAR, RECHAZAR, ACREDITAR ══════════════════════════

-- Acredita N dias a partir de `base` y devuelve la suscripcion viva resultante.
-- Helper interno para no repetir la misma aritmetica en tres RPC.
create or replace function flow._susc_acreditar_dias(
  p_id_entidad   integer,
  p_id_plan      bigint,
  p_dias         integer,
  p_origen       text,
  p_notas        text,
  p_admin        uuid,
  p_id_transaccion bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'flow', 'public'
as $function$
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
$function$;

comment on function flow._susc_acreditar_dias(integer,bigint,integer,text,text,uuid,bigint) is
  'Aritmetica unica de acreditacion: SUMA dias a lo vigente (o a now() si ya vencio) y escribe el movimiento.';

create or replace function flow.admin_suscripcion_aprobar_pago(
  p_id_transaccion bigint,
  p_observaciones  text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'flow', 'public'
as $function$
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
$function$;

comment on function flow.admin_suscripcion_aprobar_pago(bigint,text) is
  'Superadmin: verifica un pago reportado, acredita los dias del plan y reactiva la entidad.';

create or replace function flow.admin_suscripcion_rechazar_pago(
  p_id_transaccion bigint,
  p_motivo         text
)
returns jsonb
language plpgsql
security definer
set search_path to 'flow', 'public'
as $function$
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
$function$;

comment on function flow.admin_suscripcion_rechazar_pago(bigint,text) is
  'Superadmin: rechaza un pago reportado con motivo obligatorio y avisa al cliente.';

create or replace function flow.admin_suscripcion_acreditar(
  p_id_entidad integer,
  p_dias       integer,
  p_id_plan    bigint default null,
  p_motivo     text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'flow', 'public'
as $function$
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
$function$;

comment on function flow.admin_suscripcion_acreditar(integer,integer,bigint,text) is
  'Superadmin: acredita dias a mano (cortesia, compensacion, correccion). Exige motivo y lo deja en el libro.';

-- ══ 6. BARRIDO DEL CRON ════════════════════════════════════════════════════
--
-- Idempotente. El corte REAL no depende de esta funcion (entidad_activa compara
-- fechas): aqui solo se ordena el estado visible y se mandan los avisos.

create or replace function flow.suscripcion_expirar()
returns jsonb
language plpgsql
security definer
set search_path to 'flow', 'public'
as $function$
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
$function$;

comment on function flow.suscripcion_expirar() is
  'Barrido idempotente: avisa antes de vencer, pasa a en_gracia y despues a vencida, y expira intents. Solo service_role/pg_cron.';

-- ══ 7. PERMISOS ════════════════════════════════════════════════════════════

revoke all on function flow.cliente_crear_intent_suscripcion(integer,bigint) from public;
revoke all on function flow.cliente_reportar_pago_suscripcion(bigint,text,text) from public;
revoke all on function flow.cliente_mis_pagos_suscripcion(integer) from public;
revoke all on function flow.admin_suscripcion_aprobar_pago(bigint,text) from public;
revoke all on function flow.admin_suscripcion_rechazar_pago(bigint,text) from public;
revoke all on function flow.admin_suscripcion_acreditar(integer,integer,bigint,text) from public;
revoke all on function flow._susc_acreditar_dias(integer,bigint,integer,text,text,uuid,bigint) from public;
revoke all on function flow.suscripcion_expirar() from public;

grant execute on function flow.cliente_crear_intent_suscripcion(integer,bigint) to authenticated;
grant execute on function flow.cliente_reportar_pago_suscripcion(bigint,text,text) to authenticated;
grant execute on function flow.cliente_mis_pagos_suscripcion(integer) to authenticated;
grant execute on function flow.admin_suscripcion_aprobar_pago(bigint,text) to authenticated;
grant execute on function flow.admin_suscripcion_rechazar_pago(bigint,text) to authenticated;
grant execute on function flow.admin_suscripcion_acreditar(integer,integer,bigint,text) to authenticated;

grant execute on function flow.cliente_crear_intent_suscripcion(integer,bigint) to service_role;
grant execute on function flow.cliente_reportar_pago_suscripcion(bigint,text,text) to service_role;
grant execute on function flow.cliente_mis_pagos_suscripcion(integer) to service_role;
grant execute on function flow.admin_suscripcion_aprobar_pago(bigint,text) to service_role;
grant execute on function flow.admin_suscripcion_rechazar_pago(bigint,text) to service_role;
grant execute on function flow.admin_suscripcion_acreditar(integer,integer,bigint,text) to service_role;
grant execute on function flow._susc_acreditar_dias(integer,bigint,integer,text,text,uuid,bigint) to service_role;

-- El barrido lo llama el cron, que corre como service_role (o postgres).
grant execute on function flow.suscripcion_expirar() to service_role;

-- ══ 8. VERIFICACION (ejecutar a mano despues de aplicar) ═══════════════════
--
-- 8.a Existen las funciones.
-- select p.proname
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'flow'
--    and p.proname in ('cliente_crear_intent_suscripcion',
--                      'cliente_reportar_pago_suscripcion',
--                      'cliente_mis_pagos_suscripcion',
--                      'admin_suscripcion_aprobar_pago',
--                      'admin_suscripcion_rechazar_pago',
--                      'admin_suscripcion_acreditar',
--                      'suscripcion_expirar');   -- esperado: 7 filas
--
-- 8.b Ninguna quedo con el EXECUTE implicito de PUBLIC (esperado: 0 filas).
-- select p.proname
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'flow'
--    and p.proname in ('cliente_crear_intent_suscripcion','admin_suscripcion_aprobar_pago')
--    and has_function_privilege('public', p.oid, 'EXECUTE');
--
-- 8.c El barrido responde (no debe fallar aunque no haya nada que expirar).
-- select flow.suscripcion_expirar();
--   -- {"ok": true, "data": {"avisos_enviados": 0, "pasadas_a_gracia": 0,
--   --  "vencidas": 0, "intents_expirados": 0}}
--
-- 8.d SIN sesion de superadmin, aprobar devuelve error y NO acredita nada.
-- select flow.admin_suscripcion_aprobar_pago(1, 'prueba');
--   -- {"ok": false, "error": "Solo el superadmin puede verificar pagos"}
--
-- 8.e Prueba de humo completa (en el proyecto debug, con una entidad de prueba):
--   a) insert into flow.suscripcion_plan (codigo,nombre,duracion_dias,precio,moneda)
--        values ('prueba_30','Prueba 30 dias',30,100,'CUP');
--   b) select flow.cliente_crear_intent_suscripcion(<id_entidad>, <id_plan>);
--   c) select flow.cliente_reportar_pago_suscripcion(<id_intent>, 'CODIGO123');
--   d) (con sesion de superadmin) select flow.admin_suscripcion_aprobar_pago(<id_trx>);
--   e) select flow.cliente_estado_suscripcion(<id_entidad>);  -- estado 'activa'
--   f) repetir (c) con el MISMO codigo en otro intent:
--        -- {"ok": false, "error": "Ese numero de confirmacion ya fue usado..."}
-- ════════════════════════════════════════════════════════════════════════════
