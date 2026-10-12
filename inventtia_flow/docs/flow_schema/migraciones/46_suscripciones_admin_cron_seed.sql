-- ════════════════════════════════════════════════════════════════════════════
-- MIGRACION 46: SUSCRIPCIONES — PANEL DEL SUPERADMIN, CRON Y SEED
-- ════════════════════════════════════════════════════════════════════════════
--
-- QUE HACE
--   Lo que consume `ventiq_superadmin` y el mantenimiento periodico:
--
--     admin_suscripcion_listar        -> bandeja: entidades + estado + vencimiento
--     admin_suscripcion_detalle       -> ficha completa de una entidad
--     admin_suscripcion_inicializar   -> crea la suscripcion que falte (historico)
--     admin_suscripcion_suspender / reactivar
--     admin_planes_listar / guardar / eliminar
--     admin_config_obtener / guardar  -> trial, gracia, soporte, plantillas
--     admin_notificaciones_pendientes / notificacion_marcar  (despachador WAPI)
--     cliente_marcar_intent_abierto   -> embudo: "el cliente abrio Transfermovil"
--     CRON: pg_cron cada 15 min -> flow.suscripcion_expirar()
--     SEED: 3 planes de ejemplo DESACTIVADOS y sin precio real
--
-- POR QUE LOS PLANES SEMILLA NACEN DESACTIVADOS
--   Un plan activo con precio 0 se puede "comprar" y reportar. Con verificacion
--   manual no se acreditaria nada, pero es ruido y una mala primera impresion.
--   Desactivados: la pantalla del cliente no ofrece nada hasta que el superadmin
--   ponga precio y los encienda. Nada se activa por accidente.
--
-- POR QUE EL CRON ES SOLO HIGIENE
--   El corte real lo hace `flow.entidad_activa` comparando fechas. Si el cron no
--   corre (o pg_cron no esta disponible en el proyecto), una entidad impagada
--   deja de mostrarse igual. El cron solo ordena el estado visible y manda
--   avisos. `pg_cron` puede no estar habilitado: todo va dentro de un bloque que
--   comprueba su existencia y, si falta, deja la instruccion impresa como aviso.
--
-- DEPENDE DE: migraciones 43, 44 y 45.
--
-- REVERSIBILIDAD
--   select cron.unschedule('flow-suscripciones-expirar');   -- si existe
--   drop function if exists flow.admin_notificacion_marcar(bigint,text,text);
--   drop function if exists flow.admin_notificaciones_pendientes(integer);
--   drop function if exists flow.admin_config_guardar(jsonb);
--   drop function if exists flow.admin_config_obtener();
--   drop function if exists flow.admin_plan_eliminar(bigint);
--   drop function if exists flow.admin_plan_guardar(bigint,text,text,text,integer,numeric,text,jsonb,integer,boolean);
--   drop function if exists flow.admin_planes_listar();
--   drop function if exists flow.admin_suscripcion_reactivar(integer,text);
--   drop function if exists flow.admin_suscripcion_suspender(integer,text);
--   drop function if exists flow.admin_suscripcion_inicializar(integer);
--   drop function if exists flow.admin_suscripcion_detalle(integer);
--   drop function if exists flow.admin_suscripcion_listar(text,text);
--   drop function if exists flow.cliente_marcar_intent_abierto(bigint);
--   delete from flow.suscripcion_plan
--    where codigo in ('flow_mensual','flow_trimestral','flow_anual');
--
-- ORDEN: 46 es la ultima del modulo de suscripciones.
-- ════════════════════════════════════════════════════════════════════════════

-- ── Comprobacion previa ─────────────────────────────────────────────────────
do $pre$
begin
  if to_regprocedure('flow.suscripcion_expirar()') is null then
    raise exception 'Falta la migracion 45. Aplicala antes que la 46.';
  end if;

  if to_regprocedure('public.fn_is_superadmin_full_access()') is null then
    raise exception 'Falta public.fn_is_superadmin_full_access().';
  end if;
end
$pre$;

-- ══ 1. CLIENTE: EMBUDO DEL INTENT ══════════════════════════════════════════

-- Marca que el cliente realmente abrio Transfermovil. Es solo para el embudo del
-- panel (intents creados vs abiertos vs reportados); no cambia ningun derecho.
create or replace function flow.cliente_marcar_intent_abierto(p_id_intent bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'flow', 'public'
as $function$
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
$function$;

comment on function flow.cliente_marcar_intent_abierto(bigint) is
  'Marca el intent como abierto (el cliente lanzo el deep link). Solo telemetria del embudo.';

-- ══ 2. SUPERADMIN: BANDEJA ═════════════════════════════════════════════════

create or replace function flow.admin_suscripcion_listar(
  p_filtro text default 'todas',
  p_buscar text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'flow', 'public'
as $function$
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
$function$;

comment on function flow.admin_suscripcion_listar(text,text) is
  'Bandeja del superadmin: entidades con su estado de suscripcion, filtros y busqueda. Ordenada por urgencia.';

-- ══ 3. SUPERADMIN: FICHA DE UNA ENTIDAD ════════════════════════════════════

create or replace function flow.admin_suscripcion_detalle(p_id_entidad integer)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'flow', 'public'
as $function$
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
$function$;

comment on function flow.admin_suscripcion_detalle(integer) is
  'Ficha completa de una entidad para el superadmin: estado, historial, pagos, movimientos y notificaciones.';

-- ══ 4. SUPERADMIN: INICIALIZAR, SUSPENDER, REACTIVAR ═══════════════════════

-- Crea la suscripcion que le falte a las entidades que no tienen ninguna.
-- Es el paso explicito que sustituye al backfill automatico (que habria apagado
-- o regalado tiempo a todas las entidades de golpe). NO toca las que ya tienen.
create or replace function flow.admin_suscripcion_inicializar(
  p_dias integer default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'flow', 'public'
as $function$
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
$function$;

comment on function flow.admin_suscripcion_inicializar(integer) is
  'Superadmin: crea la suscripcion (trial o sin_plan) de las entidades que no tienen ninguna. No toca las que ya tienen.';

create or replace function flow.admin_suscripcion_suspender(
  p_id_entidad integer,
  p_motivo     text
)
returns jsonb
language plpgsql
security definer
set search_path to 'flow', 'public'
as $function$
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
$function$;

comment on function flow.admin_suscripcion_suspender(integer,text) is
  'Superadmin: suspende la entidad (temporada cerrada, incidencia). Distinto de vencida: no es impago.';

create or replace function flow.admin_suscripcion_reactivar(
  p_id_entidad integer,
  p_motivo     text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'flow', 'public'
as $function$
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
$function$;

comment on function flow.admin_suscripcion_reactivar(integer,text) is
  'Superadmin: quita la suspension si todavia queda tiempo vigente. Si ya vencio, obliga a acreditar.';

-- ══ 5. SUPERADMIN: PLANES ══════════════════════════════════════════════════

create or replace function flow.admin_planes_listar()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'flow', 'public'
as $function$
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
$function$;

comment on function flow.admin_planes_listar() is
  'Superadmin: todos los planes, activos e inactivos.';

create or replace function flow.admin_plan_guardar(
  p_id            bigint default null,
  p_codigo        text  default null,
  p_nombre        text  default null,
  p_descripcion   text  default null,
  p_duracion_dias integer default null,
  p_precio        numeric default null,
  p_moneda        text  default null,
  p_limites       jsonb default null,
  p_orden         integer default null,
  p_activo        boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'flow', 'public'
as $function$
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
$function$;

comment on function flow.admin_plan_guardar(bigint,text,text,text,integer,numeric,text,jsonb,integer,boolean) is
  'Superadmin: crea o actualiza un plan de suscripcion. Los campos nulos se conservan al actualizar.';

create or replace function flow.admin_plan_eliminar(p_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'flow', 'public'
as $function$
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
$function$;

comment on function flow.admin_plan_eliminar(bigint) is
  'Superadmin: borra el plan si nadie lo uso; si tiene historia, lo desactiva (no se rompe el libro).';

-- ══ 6. SUPERADMIN: CONFIGURACION ═══════════════════════════════════════════

create or replace function flow.admin_config_obtener()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'flow', 'public'
as $function$
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
$function$;

comment on function flow.admin_config_obtener() is
  'Superadmin: la configuracion completa de suscripciones (trial, gracia, soporte, plantillas).';

create or replace function flow.admin_config_guardar(p_config jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'flow', 'public'
as $function$
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
$function$;

comment on function flow.admin_config_guardar(jsonb) is
  'Superadmin: guarda solo las claves presentes en el JSON. Devuelve la configuracion resultante.';

-- ══ 7. DESPACHADOR DE WHATSAPP (para cuando exista bot) ════════════════════

create or replace function flow.admin_notificaciones_pendientes(p_limit integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'flow', 'public'
as $function$
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
$function$;

comment on function flow.admin_notificaciones_pendientes(integer) is
  'Cola de WhatsApp pendiente para el despachador (Edge Function). Vacia mientras whatsapp_bot_activo sea false.';

create or replace function flow.admin_notificacion_marcar(
  p_id     bigint,
  p_estado text,
  p_error  text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'flow', 'public'
as $function$
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
$function$;

comment on function flow.admin_notificacion_marcar(bigint,text,text) is
  'El despachador marca el resultado del envio de un aviso de WhatsApp.';

-- ══ 8. PERMISOS ════════════════════════════════════════════════════════════

revoke all on function flow.cliente_marcar_intent_abierto(bigint) from public;
revoke all on function flow.admin_suscripcion_listar(text,text) from public;
revoke all on function flow.admin_suscripcion_detalle(integer) from public;
revoke all on function flow.admin_suscripcion_inicializar(integer) from public;
revoke all on function flow.admin_suscripcion_suspender(integer,text) from public;
revoke all on function flow.admin_suscripcion_reactivar(integer,text) from public;
revoke all on function flow.admin_planes_listar() from public;
revoke all on function flow.admin_plan_guardar(bigint,text,text,text,integer,numeric,text,jsonb,integer,boolean) from public;
revoke all on function flow.admin_plan_eliminar(bigint) from public;
revoke all on function flow.admin_config_obtener() from public;
revoke all on function flow.admin_config_guardar(jsonb) from public;
revoke all on function flow.admin_notificaciones_pendientes(integer) from public;
revoke all on function flow.admin_notificacion_marcar(bigint,text,text) from public;

grant execute on function flow.cliente_marcar_intent_abierto(bigint) to authenticated;
grant execute on function flow.admin_suscripcion_listar(text,text) to authenticated;
grant execute on function flow.admin_suscripcion_detalle(integer) to authenticated;
grant execute on function flow.admin_suscripcion_inicializar(integer) to authenticated;
grant execute on function flow.admin_suscripcion_suspender(integer,text) to authenticated;
grant execute on function flow.admin_suscripcion_reactivar(integer,text) to authenticated;
grant execute on function flow.admin_planes_listar() to authenticated;
grant execute on function flow.admin_plan_guardar(bigint,text,text,text,integer,numeric,text,jsonb,integer,boolean) to authenticated;
grant execute on function flow.admin_plan_eliminar(bigint) to authenticated;
grant execute on function flow.admin_config_obtener() to authenticated;
grant execute on function flow.admin_config_guardar(jsonb) to authenticated;

grant execute on function flow.cliente_marcar_intent_abierto(bigint) to service_role;
grant execute on function flow.admin_suscripcion_listar(text,text) to service_role;
grant execute on function flow.admin_suscripcion_detalle(integer) to service_role;
grant execute on function flow.admin_suscripcion_inicializar(integer) to service_role;
grant execute on function flow.admin_suscripcion_suspender(integer,text) to service_role;
grant execute on function flow.admin_suscripcion_reactivar(integer,text) to service_role;
grant execute on function flow.admin_planes_listar() to service_role;
grant execute on function flow.admin_plan_guardar(bigint,text,text,text,integer,numeric,text,jsonb,integer,boolean) to service_role;
grant execute on function flow.admin_plan_eliminar(bigint) to service_role;
grant execute on function flow.admin_config_obtener() to service_role;
grant execute on function flow.admin_config_guardar(jsonb) to service_role;
grant execute on function flow.admin_notificaciones_pendientes(integer) to service_role;
grant execute on function flow.admin_notificacion_marcar(bigint,text,text) to service_role;

-- ══ 9. SEED DE EJEMPLO (DESACTIVADOS: el superadmin pone precio y los enciende) ══

insert into flow.suscripcion_plan
  (codigo, nombre, descripcion, duracion_dias, precio, moneda, limites, orden, activo)
values
  ('flow_mensual',    'Mensual',    'Suscripcion de 1 mes (30 dias)',
   30,  0, 'CUP', '{}'::jsonb, 10, false),
  ('flow_trimestral', 'Trimestral', 'Suscripcion de 3 meses (90 dias)',
   90,  0, 'CUP', '{}'::jsonb, 20, false),
  ('flow_anual',      'Anual',      'Suscripcion de 12 meses (365 dias)',
   365, 0, 'CUP', '{}'::jsonb, 30, false)
on conflict (codigo) do nothing;

-- ══ 10. CRON ═══════════════════════════════════════════════════════════════
--
-- Cada 15 minutos. Si `pg_cron` no esta disponible se avisa y el modulo sigue
-- funcionando: el corte real no depende de esto.

do $cron$
declare
  v_ya boolean;
begin
  if to_regclass('cron.job') is null then
    raise notice 'pg_cron no esta disponible: NO se programa flow.suscripcion_expirar(). El corte de entidades sigue funcionando (flow.entidad_activa compara fechas); solo faltan los avisos automaticos. Programa el barrido a mano si lo quieres.';
    return;
  end if;

  select exists (
    select 1 from cron.job where jobname = 'flow-suscripciones-expirar'
  ) into v_ya;

  if v_ya then
    perform cron.unschedule('flow-suscripciones-expirar');
  end if;

  perform cron.schedule(
    'flow-suscripciones-expirar',
    '*/15 * * * *',
    $job$select flow.suscripcion_expirar();$job$
  );

  raise notice 'Cron programado: flow-suscripciones-expirar cada 15 minutos.';
end
$cron$;

-- ══ 11. VERIFICACION (ejecutar a mano despues de aplicar) ══════════════════
--
-- 11.a Los 3 planes semilla existen y estan DESACTIVADOS.
-- select codigo, duracion_dias, precio, activo
--   from flow.suscripcion_plan order by orden;   -- activo = false en los 3
--
-- 11.b La configuracion sigue siendo editable y legible desde el panel.
-- select flow.admin_config_obtener();            -- requiere sesion de superadmin
--
-- 11.c El cron quedo programado (si pg_cron existe).
-- select jobname, schedule, active from cron.job
--  where jobname = 'flow-suscripciones-expirar';  -- 1 fila, */15 * * * *
--
-- 11.d SIN sesion de superadmin, la bandeja rechaza.
-- select flow.admin_suscripcion_listar();
--   -- {"ok": false, "error": "Solo el superadmin puede ver las suscripciones"}
--
-- 11.e Nada se apago: mismas entidades activas que antes de aplicar todo el modulo.
-- select count(*) filter (where flow.entidad_activa(id)) as activas,
--        count(*)                                  as total
--   from flow.entidad;
-- ════════════════════════════════════════════════════════════════════════════
