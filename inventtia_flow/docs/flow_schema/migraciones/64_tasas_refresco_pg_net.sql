-- ============================================================================
-- MIGRACION 64: refresco de la tasa de cambio SIN depender de una Edge Function
--
-- POR QUE EXISTE
--   La Edge Function `flow-tasas` (docs/flow_schema/edge_functions/flow-tasas)
--   es el camino limpio: se despliega una vez y devuelve la tasa lista. Pero
--   desplegarla exige un token con permiso `edge_functions_write`, que no
--   siempre hay. Con `pg_net` (ya instalado en el proyecto) el refresco se puede
--   hacer ENTERAMENTE desde Postgres: la base pide la URL, y una segunda llamada
--   ingiere la respuesta y la cachea. Asi la funcion automatica de precios
--   funciona aunque no haya ninguna Edge Function desplegada.
--
-- COMO SE USA (la app hace esto, en este orden)
--   1. `flow.tasas_actuales()`                    -- lectura barata de la cache
--   2. si `vigente = false`:
--        `flow.tasas_refrescar()`                 -- pide la URL (async)
--        -> {estado:'vigente'}     : ya habia tasa de hoy, nada que hacer
--        -> {estado:'solicitado', request_id:N}
--   3. en bucle (cada ~250 ms, max ~1.5 s):
--        `flow.tasas_ingest(N)`                   -- mira si ya llego
--        -> {estado:'pendiente'} | {estado:'ingerido', ...tasas}
--   4. `flow.tasas_actuales()` otra vez para leer el resultado.
--
--   `pg_net` es ASINCRONO: por eso son dos llamadas. No se puede esperar la
--   respuesta dentro de la misma transaccion.
--
-- TABLA NUEVA
--   * flow.tasa_cambio_sondeo — un registro por peticion HTTP lanzada. Sirve de
--     pestillo anti-spam (no se lanza otra igual en 2 minutos) y de bandeja de
--     "pendiente de ingerir".
--
-- FUNCIONES NUEVAS
--   * flow._tasas_conversiones(p_tasas jsonb)  -- matriz cruzada por CUP
--   * flow.tasas_refrescar(p_forzar boolean)   -- pide la URL si la cache no es de hoy
--   * flow.tasas_ingest(p_request_id bigint)   -- lee la respuesta y cachea
--
-- LO QUE NO CAMBIA
--   * `flow.tasa_cambio` es la MISMA tabla de la migracion 60: la Edge Function
--     y esta via escriben exactamente la misma forma. Conviven sin conflicto.
--   * `flow.tasas_actuales()` y `flow.tasa_factor()` no se tocan.
--
-- REVERSION
--   drop function if exists flow.tasas_ingest(bigint);
--   drop function if exists flow.tasas_refrescar(boolean);
--   drop function if exists flow._tasas_conversiones(jsonb);
--   drop table if exists flow.tasa_cambio_sondeo;
--
-- IDEMPOTENTE: if not exists / create or replace / drop policy if exists.
-- ============================================================================

-- ══ 1. BANDEJA DE SONDEO ═══════════════════════════════════════════════════

create table if not exists flow.tasa_cambio_sondeo (
  request_id bigint primary key,
  creado_at  timestamptz not null default now(),
  ingerido   boolean     not null default false,
  ingerido_at timestamptz,
  error      text
);

comment on table flow.tasa_cambio_sondeo is
  'Una fila por peticion HTTP lanzada con pg_net para leer la tasa. Evita lanzar peticiones repetidas y sirve de bandeja de respuestas pendientes de ingerir.';

create index if not exists idx_tasa_cambio_sondeo_pendientes
  on flow.tasa_cambio_sondeo (creado_at desc)
  where not ingerido;

-- ══ 2. MATRIZ DE CONVERSIONES (espejo SQL de la Edge Function) ════════════

create or replace function flow._tasas_conversiones(p_tasas jsonb)
returns jsonb
language plpgsql
immutable
set search_path = flow, public
as $function$
declare
  v_monedas text[] := array['USD', 'EUR', 'CUP', 'MLC'];
  v_salida  jsonb := '{}'::jsonb;
  v_fila    jsonb;
  v_o       text;
  v_d       text;
  v_val     numeric;
  v_a       numeric;
  v_b       numeric;
begin
  if p_tasas is null or jsonb_typeof(p_tasas) <> 'object' then
    return '{}'::jsonb;
  end if;

  foreach v_o in array v_monedas loop
    -- OJO: `jsonb_set` NO crea objetos intermedios, solo la ultima clave. Por eso
    -- se arma la fila de la moneda origen aparte y se cuelga entera de la salida
    -- (`jsonb_set('{}', '{USD,EUR}', ...)` no hacia NADA y devolvia `{}`).
    v_fila := '{}'::jsonb;

    foreach v_d in array v_monedas loop
      if v_o = v_d then
        v_val := 1;
      elsif v_o = 'CUP' then
        -- El proveedor no publica una fila CUP: se invierte X -> CUP.
        v_val := nullif(p_tasas -> v_d ->> 'CUP', '')::numeric;
        v_val := case when v_val is not null and v_val > 0
                      then 1 / v_val else null end;
      elsif v_d = 'CUP' then
        v_val := nullif(p_tasas -> v_o ->> 'CUP', '')::numeric;
      else
        v_val := nullif(p_tasas -> v_o ->> v_d, '')::numeric;
        if v_val is null then
          -- Cruce por CUP: (origen -> CUP) / (destino -> CUP).
          v_a := nullif(p_tasas -> v_o ->> 'CUP', '')::numeric;
          v_b := nullif(p_tasas -> v_d ->> 'CUP', '')::numeric;
          if v_a is not null and v_b is not null and v_b > 0 then
            v_val := v_a / v_b;
          end if;
        end if;
      end if;

      if v_val is not null and v_val > 0 then
        v_fila := jsonb_set(v_fila, array[v_d], to_jsonb(round(v_val, 6)), true);
      end if;
    end loop;

    v_salida := jsonb_set(v_salida, array[v_o], v_fila, true);
  end loop;

  return v_salida;
end;
$function$;

comment on function flow._tasas_conversiones(jsonb) is
  'Matriz de conversion entre USD/EUR/CUP/MLC a partir del JSON crudo del proveedor, cruzando por CUP cuando no hay tasa directa.';

-- ══ 3. PEDIR LA TASA ═══════════════════════════════════════════════════════

create or replace function flow.tasas_refrescar(p_forzar boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = flow, public
as $function$
declare
  v_hoy     date := (timezone('America/Havana', now()))::date;
  v_row     flow.tasa_cambio%rowtype;
  v_pend    flow.tasa_cambio_sondeo%rowtype;
  v_req     bigint;
begin
  -- Fast path: ya hay tasa de hoy y no se fuerza.
  if not coalesce(p_forzar, false) then
    select * into v_row
    from flow.tasa_cambio
    order by fecha desc, id desc
    limit 1;

    if v_row.id is not null and v_row.fecha = v_hoy then
      return jsonb_build_object(
        'ok', true, 'estado', 'vigente',
        'fecha', v_row.fecha, 'hora', v_row.hora, 'actualizado', v_row.actualizado,
        'tasas', v_row.tasas, 'conversiones', v_row.conversiones
      );
    end if;
  end if;

  -- Pestillo: si hay una peticion de hace menos de 2 minutos sin ingerir, se
  -- devuelve ESA en vez de lanzar otra. Evita que pulsar "reintentar" en la app
  -- dispare una peticion HTTP por toque.
  select * into v_pend
  from flow.tasa_cambio_sondeo
  where not ingerido
    and creado_at > now() - interval '2 minutes'
  order by creado_at desc
  limit 1;

  if v_pend.request_id is not null then
    return jsonb_build_object(
      'ok', true, 'estado', 'solicitado', 'request_id', v_pend.request_id
    );
  end if;

  v_req := net.http_get(
    'https://widgets.directoriocubano.info/api/tasas',
    headers := jsonb_build_object(
      'Accept', 'application/json',
      'User-Agent', 'Mozilla/5.0 (compatible; GoReserva-flow-tasas/1.0)'
    ),
    timeout_milliseconds := 12000
  );

  insert into flow.tasa_cambio_sondeo (request_id)
  values (v_req)
  on conflict (request_id) do nothing;

  return jsonb_build_object(
    'ok', true, 'estado', 'solicitado', 'request_id', v_req
  );
exception
  when others then
    return jsonb_build_object('ok', false, 'estado', 'error', 'error', sqlerrm);
end;
$function$;

comment on function flow.tasas_refrescar(boolean) is
  'Pide la tasa del dia al proveedor via pg_net (asincrono). Devuelve la tasa vigente si ya la tiene, o el request_id a ingerir.';

-- ══ 4. INGERIR LA RESPUESTA ════════════════════════════════════════════════

create or replace function flow.tasas_ingest(p_request_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = flow, public
as $function$
declare
  v_resp    record;
  v_json    jsonb;
  v_tasas   jsonb;
  v_conv    jsonb;
  v_hoy     date := (timezone('America/Havana', now()))::date;
  v_act     text;
  v_fecha   date;
  v_hora    text;
  v_sondeo  flow.tasa_cambio_sondeo%rowtype;
begin
  select * into v_sondeo
  from flow.tasa_cambio_sondeo
  where request_id = p_request_id;

  if v_sondeo.request_id is not null and v_sondeo.ingerido then
    -- Ya se proceso: se devuelve la cache (idempotente).
    return flow.tasas_actuales();
  end if;

  select * into v_resp from net._http_response where id = p_request_id;

  if v_resp.id is null or v_resp.status_code is null then
    return jsonb_build_object('ok', true, 'estado', 'pendiente',
                              'request_id', p_request_id);
  end if;

  if v_resp.status_code <> 200 then
    update flow.tasa_cambio_sondeo
       set ingerido = true, ingerido_at = now(),
           error = 'HTTP ' || v_resp.status_code
     where request_id = p_request_id;
    return jsonb_build_object('ok', false, 'estado', 'error',
                              'error', 'HTTP ' || v_resp.status_code);
  end if;

  begin
    v_json := coalesce(v_resp.content, '{}')::jsonb;
  exception
    when others then
      update flow.tasa_cambio_sondeo
         set ingerido = true, ingerido_at = now(), error = 'respuesta no JSON'
       where request_id = p_request_id;
      return jsonb_build_object('ok', false, 'estado', 'error',
                                'error', 'El proveedor no devolvio JSON');
  end;

  if coalesce(v_json -> 'ok', 'false'::jsonb) <> 'true'::jsonb
     or jsonb_typeof(v_json -> 'tasas') <> 'object' then
    update flow.tasa_cambio_sondeo
       set ingerido = true, ingerido_at = now(), error = 'respuesta sin tasas'
     where request_id = p_request_id;
    return jsonb_build_object('ok', false, 'estado', 'error',
                              'error', 'El proveedor devolvio una respuesta sin tasas');
  end if;

  v_tasas := v_json -> 'tasas';
  v_conv  := flow._tasas_conversiones(v_tasas);
  v_act   := nullif(btrim(coalesce(v_json ->> 'actualizado', '')), '');
  v_hora  := nullif(btrim(coalesce(v_json ->> 'hora', '')), '');

  -- La cache se indexa por el dia del proveedor. Se valida el formato; si no
  -- es una fecha, se usa hoy (hora de La Habana).
  begin
    v_fecha := (left(v_act, 10))::date;
  exception
    when others then
      v_fecha := v_hoy;
  end;
  if v_fecha is null then
    v_fecha := v_hoy;
  end if;

  insert into flow.tasa_cambio (fecha, fuente, hora, actualizado, tasas, conversiones, updated_at)
  values (
    v_fecha,
    'directoriocubano',
    v_hora,
    case when v_act is null then null else v_act::timestamptz end,
    v_tasas,
    v_conv,
    now()
  )
  on conflict (fecha, fuente) do update
    set hora         = excluded.hora,
        actualizado  = excluded.actualizado,
        tasas        = excluded.tasas,
        conversiones = excluded.conversiones,
        updated_at   = now();

  update flow.tasa_cambio_sondeo
     set ingerido = true, ingerido_at = now(), error = null
   where request_id = p_request_id;

  -- Limpieza: las respuestas de pg_net no se borran solas.
  delete from net._http_response where created < now() - interval '2 days';
  delete from flow.tasa_cambio_sondeo where ingerido and creado_at < now() - interval '7 days';

  return jsonb_build_object(
    'ok', true, 'estado', 'ingerido',
    'fecha', v_fecha, 'hora', v_hora, 'actualizado', v_act,
    'tasas', v_tasas, 'conversiones', v_conv
  );
exception
  when others then
    return jsonb_build_object('ok', false, 'estado', 'error', 'error', sqlerrm);
end;
$function$;

comment on function flow.tasas_ingest(bigint) is
  'Lee la respuesta de pg_net de un request_id, calcula las conversiones y cachea la tasa. Idempotente: llamarla dos veces no duplica nada.';

-- ══ 5. RLS Y GRANTS ════════════════════════════════════════════════════════

alter table flow.tasa_cambio_sondeo enable row level security;

revoke all on flow.tasa_cambio_sondeo from anon;
grant select on flow.tasa_cambio_sondeo to authenticated;
grant all    on flow.tasa_cambio_sondeo to service_role;

revoke all on function flow._tasas_conversiones(jsonb) from public, anon;
revoke all on function flow.tasas_refrescar(boolean) from public, anon;
revoke all on function flow.tasas_ingest(bigint) from public, anon;

grant execute on function flow.tasas_refrescar(boolean) to authenticated;
grant execute on function flow.tasas_ingest(bigint) to authenticated;

notify pgrst, 'reload schema';

-- ══ 6. VERIFICACION (ejecutar a mano despues de aplicar) ══════════════════
--
-- 6.a La conversion cruzada da lo mismo que la Edge Function.
-- select flow._tasas_conversiones(
--   '{"USD":{"CUP":840,"MLC":1.2,"USD":null},"EUR":{"CUP":925,"MLC":1.33,"USD":1.1},"MLC":{"CUP":697.62,"MLC":null,"USD":0.83}}'::jsonb
-- ) -> 'MLC' ->> 'EUR';   -- 0.754184 (697.62 / 925)
--
-- 6.b Pedir + ingerir (tarda ~1 s: la respuesta es asincrona).
-- select flow.tasas_refrescar();
--   -- {ok:true, estado:'solicitado', request_id:N}
-- select pg_sleep(2);
-- select flow.tasas_ingest(N);         -- {ok:true, estado:'ingerido', ...}
-- select flow.tasas_actuales();        -- {ok:true, vigente:true, ...}
--
-- 6.c El pestillo: dos peticiones seguidas devuelven el MISMO request_id.
-- select flow.tasas_refrescar(true);   -- mismo request_id
--
-- 6.d Una vez cacheada la tasa de hoy, sin forzar no se pide nada.
-- select flow.tasas_refrescar();       -- {ok:true, estado:'vigente'}