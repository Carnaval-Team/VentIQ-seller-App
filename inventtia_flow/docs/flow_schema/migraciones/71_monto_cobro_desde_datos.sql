-- ============================================================================
-- MIGRACION 71: el cobro por adelantado no puede depender de que la reserva
--               tenga `precio_total` guardado
--
-- QUE ARREGLA
--   `flow.cliente_crear_pago_reserva` calcula el importe con
--   `flow._monto_cobro_reserva(id, moneda)`, que SOLO lee `agenda.precio_total`.
--   Si esa columna está a 0/NULL, el RPC contesta
--       «Esta reserva no tiene precio configurado: no se puede pagar por
--        adelantado»
--   aunque el servicio tenga su `config_precio` y sus turnos con precio.
--
--   Comprobado con MCP contra la base real (2026-10-29): TODAS las reservas de
--   `flow.agenda` tienen `precio_total = 0` (ids 304-315, creadas entre el 27 y
--   el 29 de octubre), mientras que las funciones de precio devuelven el valor
--   correcto para esos mismos servicios/turnos:
--       calcular_precio_turno(15, 32, '{"b":"5"}', null, 1) -> 2 USD
--       calcular_precio_reserva(15, '{}', 'USD', 1)          -> 5 USD
--       calcular_precio_reserva(14, '{}', 'CUP', 1)          -> 2795 CUP
--   El resultado: el cliente ve el precio en la ficha, reserva, y al pagar
--   recibe «no tiene precio configurado» tanto desde el detalle del servicio
--   como desde «Mis reservas».
--
-- QUE HACE
--   1. Nuevo helper `flow._precio_agenda_desde_datos(id_agenda)`: recalcula el
--      precio de una reserva **a partir de sus propios datos** (local_servicio
--      -> servicio, `id_turno`, `cantidad` y `datos_adicionales`), con las
--      mismas funciones que usa la app para MOSTRAR el precio:
--        * con turno -> `calcular_precio_turno`
--        * sin turno -> `calcular_precio_reserva`
--      Devuelve `{precio_total, moneda}` o NULL si no se puede resolver.
--   2. `flow.cliente_crear_pago_reserva`: si la reserva no tiene precio
--      guardado, lo recalcula con el helper, lo ESCRIBE en la agenda (para que
--      los listados, el resumen y el propio chip dejen de mostrar 0) y sigue con
--      la conversion a la moneda de cobro que ya tenia.
--
-- POR QUE ASI (y no metiendo el precio al crear la reserva)
--   * El precio se recalcula en el SERVIDOR: un cliente no puede enviar un
--     importe a mano y pagar de menos.
--   * Arregla las reservas que YA existen (no hace falta migrar datos a mano):
--     se auto-corrigen la primera vez que se intenta pagar.
--   * Es idempotente: solo actua cuando `precio_total` es 0/NULL; si la reserva
--     ya trae precio, no se toca (ni se le cambia el importe al cliente).
--
-- LIMITACION CONOCIDA (y asumida)
--   Recalcular usa la configuracion ACTUAL del servicio. En una reserva vieja con
--   precio 0 no hay nada que respetar (el precio nunca se guardo), asi que es la
--   unica opcion razonable. Para las nuevas, si al crear la reserva se guarda el
--   precio, este bloque no se ejecuta.
--
-- NO CAMBIA
--   * Firmas, defaults ni contrato jsonb de `cliente_crear_pago_reserva`.
--   * `_monto_cobro_reserva` (conversion a la moneda de cobro): intacto.
--   * El orden de los chequeos (sesion, pertenencia, estado, intento vivo,
--     entidad, config del cobro) y los mensajes existentes.
--   * Nada de DDL sobre tablas ni de datos: solo dos funciones.
-- ============================================================================

-- ── 1. Helper: precio de una reserva a partir de sus datos ──────────────────
create or replace function flow._precio_agenda_desde_datos(p_id_agenda integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = flow, public
as $function$
declare
  v_agenda      flow.agenda%rowtype;
  v_id_servicio integer;
  v_cant        integer;
  v_calc        record;
begin
  select * into v_agenda from flow.agenda where id = p_id_agenda;
  if v_agenda.id is null then
    return null;
  end if;

  select ls.id_servicio into v_id_servicio
  from flow.local_servicio ls
  where ls.id = v_agenda.id_local_servicio;
  if v_id_servicio is null then
    return null;
  end if;

  v_cant := greatest(coalesce(v_agenda.cantidad, 1), 1);

  if v_agenda.id_turno is not null then
    select * into v_calc
    from flow.calcular_precio_turno(
      v_id_servicio,
      v_agenda.id_turno,
      coalesce(v_agenda.datos_adicionales, '{}'::jsonb),
      null,
      v_cant
    );
  else
    select * into v_calc
    from flow.calcular_precio_reserva(
      v_id_servicio,
      coalesce(v_agenda.datos_adicionales, '{}'::jsonb),
      null,
      v_cant
    );
  end if;

  if v_calc.precio_total is null or v_calc.precio_total <= 0 then
    return null;
  end if;

  return jsonb_build_object(
    'precio_total', v_calc.precio_total,
    'moneda',       v_calc.moneda
  );
end;
$function$;

-- El helper NO se expone a `anon`/`authenticated`: solo lo llama
-- `cliente_crear_pago_reserva`, que es `security definer` (corre como el owner),
-- y así no se puede consultar el importe de una reserva ajena por su id.
revoke all on function flow._precio_agenda_desde_datos(integer) from public;
grant execute on function flow._precio_agenda_desde_datos(integer) to service_role;

comment on function flow._precio_agenda_desde_datos(integer) is
  'Precio de una reserva calculado desde sus datos (turno/servicio/cantidad/datos adicionales). NULL si no se puede resolver. Lo usa cliente_crear_pago_reserva cuando agenda.precio_total esta a 0.';

-- ── 2. `cliente_crear_pago_reserva` con auto-correccion del precio ──────────
create or replace function flow.cliente_crear_pago_reserva(p_id_agenda integer)
returns jsonb
language plpgsql
security definer
set search_path to 'flow', 'public'
as $function$
declare
  v_uid        uuid := auth.uid();
  v_agenda     flow.agenda%rowtype;
  v_estado_res integer;
  v_id_entidad integer;
  v_cfg        flow.cobro_config%rowtype;
  v_monto      numeric(12,2);
  v_importe    text;
  v_id_trx     text;
  v_url_intent text;
  v_url_http   text;
  v_expira     timestamptz;
  v_id         bigint;
  v_calc       jsonb;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Sesion requerida');
  end if;

  select a.* into v_agenda from flow.agenda a where a.id = p_id_agenda;
  if v_agenda.id is null then
    return jsonb_build_object('ok', false, 'error', 'Reserva no encontrada');
  end if;

  if v_agenda.uuid_usuario <> v_uid and coalesce(v_agenda.reservado_por, v_uid) <> v_uid then
    return jsonb_build_object('ok', false, 'error', 'No tienes permiso sobre esta reserva');
  end if;

  select id into v_estado_res from flow.nom_estado_agenda where nombre = 'Reservado' limit 1;
  if v_agenda.id_estado is distinct from v_estado_res then
    return jsonb_build_object('ok', false, 'error', 'Solo se puede pagar una reserva activa');
  end if;

  -- Un solo intento vivo por reserva.
  if exists (
    select 1 from flow.reserva_pago rp
    where rp.id_agenda = p_id_agenda
      and rp.estado in ('creado', 'reportado')
      and rp.expira_at > now()
  ) then
    return jsonb_build_object('ok', false, 'error',
      'Ya tienes un pago en curso para esta reserva. Revisa su estado antes de crear otro.');
  end if;

  select l.id_entidad into v_id_entidad
  from flow.local_servicio ls
  join flow.app_dat_locales l on l.id = ls.id_local
  where ls.id = v_agenda.id_local_servicio;

  if v_id_entidad is null then
    return jsonb_build_object('ok', false, 'error', 'No se pudo resolver la entidad de la reserva');
  end if;

  select * into v_cfg from flow.cobro_config where id_entidad = v_id_entidad;
  if v_cfg.id_entidad is null or not v_cfg.activo then
    return jsonb_build_object('ok', false, 'error',
      'Este servicio no tiene activado el pago por adelantado');
  end if;

  -- [71] Auto-correccion: si la reserva no tiene precio guardado, se recalcula
  -- desde sus datos y se persiste. Sin esto, cualquier reserva creada por una
  -- ruta que no escribio `precio_total` contesta «no tiene precio configurado»
  -- aunque el servicio y el turno tengan precio.
  if coalesce(v_agenda.precio_total, 0) <= 0 then
    v_calc := flow._precio_agenda_desde_datos(p_id_agenda);
    if v_calc is not null then
      update flow.agenda
         set precio_total = (v_calc ->> 'precio_total')::numeric,
             moneda       = (v_calc ->> 'moneda')::varchar,
             updated_at   = current_timestamp
       where id = p_id_agenda
         and coalesce(precio_total, 0) <= 0;

      v_agenda.precio_total := (v_calc ->> 'precio_total')::numeric;
      v_agenda.moneda       := (v_calc ->> 'moneda')::varchar;
    end if;
  end if;

  v_monto := flow._monto_cobro_reserva(p_id_agenda, v_cfg.moneda);
  if v_monto is null or v_monto <= 0 then
    if v_agenda.precio_total is not null and v_agenda.precio_total > 0 then
      return jsonb_build_object('ok', false, 'error',
        'No hay tasa de cambio para cobrar en ' || v_cfg.moneda || '. Intentalo mas tarde.');
    end if;
    return jsonb_build_object('ok', false, 'error',
      'Esta reserva no tiene precio configurado: no se puede pagar por adelantado');
  end if;

  v_importe := case when v_monto = trunc(v_monto)
                    then trunc(v_monto)::bigint::text
                    else to_char(v_monto, 'FM9999999990.00') end;

  v_id_trx := 'FLW-PAGO-' || p_id_agenda || '-' || to_char(now(), 'YYYYMMDDHH24MISS') || '-'
              || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));

  v_expira := now() + make_interval(hours => coalesce(v_cfg.intent_horas_vigencia, 24));

  v_url_intent := replace(replace(replace(replace(replace(
                    v_cfg.transfermovil_intent_template,
                    '$id_transaccion',   'ESTATICO'),
                    '$importe',          v_importe),
                    '$moneda',           v_cfg.moneda),
                    '$numero_proveedor', v_cfg.transfermovil_numero_proveedor),
                    '$titulo',           v_cfg.transfermovil_titulo);

  v_url_http := replace(replace(replace(replace(replace(
                    v_cfg.transfermovil_url_template,
                    '$id_transaccion',   'ESTATICO'),
                    '$importe',          v_importe),
                    '$moneda',           v_cfg.moneda),
                    '$numero_proveedor', v_cfg.transfermovil_numero_proveedor),
                    '$titulo',           v_cfg.transfermovil_titulo);

  insert into flow.reserva_pago (
    id_agenda, id_entidad, uuid_usuario, monto, moneda, id_transaccion,
    numero_proveedor, url_intent, url_http, estado, expira_at
  ) values (
    p_id_agenda, v_id_entidad, v_uid, v_monto, v_cfg.moneda, v_id_trx,
    v_cfg.transfermovil_numero_proveedor, v_url_intent, v_url_http, 'creado', v_expira
  ) returning id into v_id;

  update flow.agenda
     set pago_estado = 'pendiente',
         pago_id     = v_id,
         pago_monto  = v_monto,
         pago_moneda = v_cfg.moneda,
         updated_at  = current_timestamp
   where id = p_id_agenda;

  return jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'id',               v_id,
      'id_agenda',        p_id_agenda,
      'monto',            v_monto,
      'moneda',           v_cfg.moneda,
      'importe',          v_importe,
      'id_transaccion',   v_id_trx,
      'numero_proveedor', v_cfg.transfermovil_numero_proveedor,
      'titulo',           v_cfg.transfermovil_titulo,
      'url_intent',       v_url_intent,
      'url_http',         v_url_http,
      'expira_at',        v_expira,
      'whatsapp_verificacion', v_cfg.whatsapp_verificacion,
      'soporte_whatsapp',      v_cfg.soporte_whatsapp,
      'instrucciones',         v_cfg.instrucciones
    )
  );
end;
$function$;

grant execute on function flow.cliente_crear_pago_reserva(integer) to authenticated;

-- ── 3. Verificacion (no modifica nada; ejecutar despues de aplicar) ─────────
-- a) Las reservas que estaban a 0 siguen a 0 hasta que alguien intente pagar
--    (se corrigen solas en ese momento). Para comprobarlo con una real:
--      select flow._precio_agenda_desde_datos(315);   -- {precio_total: 2, moneda: USD}
--      select flow._precio_agenda_desde_datos(314);   -- {precio_total: 3500, moneda: CUP}
--
-- b) Backfill opcional de TODAS las reservas a 0 (no hace falta para cobrar,
--    pero arregla los listados de una vez). Revisar el SELECT antes del UPDATE:
--      select a.id, a.id_local_servicio, a.id_turno, a.cantidad,
--             flow._precio_agenda_desde_datos(a.id) as precio
--        from flow.agenda a
--       where coalesce(a.precio_total, 0) <= 0
--       order by a.id;
--    y, si el resultado cuadra:
--      begin;
--        update flow.agenda a
--           set precio_total = (p.precio ->> 'precio_total')::numeric,
--               moneda       = (p.precio ->> 'moneda')::varchar,
--               updated_at   = current_timestamp
--          from (
--            select a2.id, flow._precio_agenda_desde_datos(a2.id) as precio
--              from flow.agenda a2
--             where coalesce(a2.precio_total, 0) <= 0
--          ) p
--         where a.id = p.id
--           and p.precio is not null;
--        -- comprobar: select count(*) from flow.agenda where coalesce(precio_total,0) <= 0;
--      commit;