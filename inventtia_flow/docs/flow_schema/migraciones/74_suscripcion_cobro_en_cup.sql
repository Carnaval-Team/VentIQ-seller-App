-- ════════════════════════════════════════════════════════════════════════════
-- MIGRACION 74: LA SUSCRIPCION SE COBRA SIEMPRE EN CUP (CAMBIO DEL DIA)
-- ════════════════════════════════════════════════════════════════════════════
--
-- QUE ARREGLA
--   `flow.cliente_crear_intent_suscripcion` (versión de la 72) arma el intent de
--   Transfermóvil con `monto = plan.precio` y `moneda = plan.moneda`. Con los
--   planes nuevos en USD (starter/plus/professional), el deep link salía en USD
--   y Transfermóvil, que SOLO cobra en CUP, no puede procesarlo.
--
--   Es el mismo problema que ya resolvió el prepago de servicios en la 62 con
--   `flow._monto_cobro_reserva`: convertir al cambio del día con la tasa
--   cacheada (`flow.tasa_cambio` + `flow.tasa_factor`, migración 60) y redondear
--   a pesos enteros.
--
-- QUE HACE
--   1. Helper nuevo `flow._monto_en_cup(p_monto numeric, p_moneda text)`:
--      convierte un importe de cualquier moneda a CUP con el factor cacheado.
--      · null si el monto es null o <= 0;
--      · moneda NULL/vacía o 'CUP' -> round(monto) (CUP siempre entero);
--      · si no -> factor = flow.tasa_factor(moneda,'CUP'); null si no hay factor
--        o es <= 0 (sin tasa NO se inventa un importe); si hay -> round(monto*factor).
--   2. `create or replace` de `flow.cliente_crear_intent_suscripcion`
--      (MISMA firma, sin sobrecarga): conserva TODO lo de la 72 (sesión,
--      `_susc_caller_ve_entidad`, config, plan activo, validación de plan
--      privado) y cambia solo el importe/moneda del intent:
--      · `monto = _monto_en_cup(plan.precio, plan.moneda)` y `moneda = 'CUP'`;
--      · si no hay tasa -> `{ok:false, error:'No hay tasa de cambio para cobrar
--        en CUP. Inténtalo más tarde.'}` (no se crea intent a medias);
--      · el deep link va con `$moneda = 'CUP'` y `$importe` entero;
--      · `data` añade `monto_plan`, `moneda_plan` y `tasa_cup` para que la app
--        pueda mostrar "20 USD = 16 900 CUP (tasa 845)".
--   3. `create or replace` de `flow.cliente_planes_suscripcion` (MISMA firma):
--      conserva todo lo de la 72 (públicos + privados, modalidad, etiqueta,
--      es_privado, id_entidad, entidad_denominacion, contacto_whatsapp, guarda
--      de anon) y añade `precio_cup` a cada plan (null si no hay tasa).
--
-- CONTRATO CONGELADO
--   · `cliente_crear_intent_suscripcion` conserva los campos de `data` de la 72
--     (`id, id_entidad, id_plan, plan_nombre, duracion_dias, importe,
--      id_transaccion, numero_proveedor, titulo, url_intent, url_http,
--      expira_at, soporte_whatsapp, modo_prueba`) y añade `monto`,
--      `moneda`, `monto_plan`, `moneda_plan`, `tasa_cup`.
--     OJO: `monto`/`moneda` cambian de significado (antes eran los del plan):
--     ahora son SIEMPRE los del cobro (CUP). Los valores del plan quedan en
--     `monto_plan`/`moneda_plan`, para no perder información.
--   · `cliente_planes_suscripcion` añade `precio_cup` (numeric|null).
--
-- DATO REAL LEÍDO DE LA CACHE (MCP, solo lectura, 2026-10-30)
--   La última fila de `flow.tasa_cambio` es del 2026-10-28 (fuente
--   directoriocubano) y sus conversiones a CUP son:
--       USD -> CUP = 845.00     EUR -> CUP = 930.00     MLC -> CUP = 698.81
--   `tasa_factor` usa siempre la fila más reciente (no comprueba la fecha), así
--   que HOY un plan de 20 USD se cobraría 16 900 CUP.
--
-- NOTA SOBRE PLANES DE CONTACTO
--   Un plan `modalidad = 'contacto'` suele tener precio 0 (p. ej. enterprise).
--   Con este contrato `_monto_en_cup(0, ...)` es null y el intent devuelve el
--   error de "no hay tasa". Es correcto: la app NO debe ofrecer pago para un
--   plan de contacto (debe abrir WhatsApp). Se documenta aquí porque el mensaje
--   de error no distingue ese caso.
--
-- DEPENDE DE: 60 (`flow.tasa_factor`) y 72 (que redefine las dos funciones).
--             El bloque previo lo comprueba y falla claro si falta alguna.
-- ORDEN: aplicar 72 y después 74.
-- NO APLICAR AUTOMATICAMENTE: este archivo lo pega el usuario en el editor SQL.
--
-- REVERSIBILIDAD: ver el bloque comentado al final (volver a pegar las
-- versiones de la 72 y borrar el helper). No toca datos ni tablas.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 0. Comprobación previa ──────────────────────────────────────────────────
do $pre$
begin
  if to_regprocedure('flow.tasa_factor(text,text)') is null then
    raise exception 'Falta flow.tasa_factor(text,text): aplica primero la migración 60.';
  end if;

  if not exists (select 1 from information_schema.columns
                  where table_schema = 'flow' and table_name = 'suscripcion_plan'
                    and column_name = 'id_entidad') then
    raise exception 'Falta flow.suscripcion_plan.id_entidad: aplica primero la migración 72.';
  end if;

  if to_regclass('flow.tasa_cambio') is null then
    raise exception 'Falta flow.tasa_cambio: aplica primero la migración 60.';
  end if;
end
$pre$;

-- ══ 1. HELPER: IMPORTE EN CUP CON EL CAMBIO DEL DÍA ═════════════════════════
--
-- Misma filosofía que `flow._monto_cobro_reserva` (62): si no hay tasa, null y
-- quien llama decide; nunca se inventa un importe. CUP siempre entero porque
-- Transfermóvil cobra pesos sin centavos.
create or replace function flow._monto_en_cup(p_monto numeric, p_moneda text)
returns numeric
language plpgsql
stable
security definer
set search_path to 'flow', 'public'
as $function$
declare
  v_moneda text := upper(btrim(coalesce(p_moneda, '')));
  v_factor numeric;
begin
  if p_monto is null or p_monto <= 0 then
    return null;
  end if;

  -- Sin moneda o ya en CUP: el importe es el mismo, redondeado a pesos.
  if v_moneda = '' or v_moneda = 'CUP' then
    return round(p_monto);
  end if;

  v_factor := flow.tasa_factor(v_moneda, 'CUP');
  if v_factor is null or v_factor <= 0 then
    return null;   -- sin tasa no hay cobro posible
  end if;

  return round(p_monto * v_factor);
end;
$function$;

comment on function flow._monto_en_cup(numeric, text) is
  'Convierte un importe a CUP con la tasa cacheada. NULL si el monto es null/<=0 o si no hay factor de cambio. CUP siempre entero.';

-- ══ 2. INTENT DE SUSCRIPCION: SIEMPRE EN CUP ════════════════════════════════
--
-- Base: versión de la 72 (que a su vez partía de la 45). Se conserva el orden de
-- los chequeos y todos los mensajes; solo cambia el cálculo del importe.
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
  v_monto_cup    numeric;
  v_tasa_cup     numeric;
  v_importe_txt  text;
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

  -- (72) Un plan privado sólo lo puede comprar SU entidad. Un plan público
  -- (id_entidad NULL) lo puede comprar cualquiera.
  if v_plan.id_entidad is not null and v_plan.id_entidad <> p_id_entidad then
    return jsonb_build_object('ok', false,
      'error', 'Este plan no está disponible para esta entidad');
  end if;

  -- (74) NUEVO: el cobro va SIEMPRE en CUP, con el cambio del día.
  v_monto_cup := flow._monto_en_cup(v_plan.precio, v_plan.moneda);
  if v_monto_cup is null then
    return jsonb_build_object('ok', false,
      'error', 'No hay tasa de cambio para cobrar en CUP. Inténtalo más tarde.');
  end if;

  -- Factor informativo para la app: 1 cuando el plan ya estaba en CUP.
  v_tasa_cup := case
                  when upper(btrim(coalesce(v_plan.moneda, ''))) in ('', 'CUP') then 1
                  else flow.tasa_factor(v_plan.moneda, 'CUP')
                end;

  -- Transfermovil espera 1500, no 1500.00: importe entero en CUP.
  v_importe_txt := trunc(v_monto_cup)::bigint::text;

  -- Referencia interna UNICA por intent. NO viaja en el link: es un bug de la
  -- app de Transfermovil, que trata el id_transaccion como estatico ("ESTATICO")
  -- aunque se mande uno unico. El link lleva el literal ESTATICO; esta
  -- referencia queda para que SOPORTE ubique el intento en el panel y para
  -- auditar.
  v_id_trx := 'FLW-' || p_id_entidad || '-' || to_char(now(), 'YYYYMMDDHH24MISS') || '-'
              || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));

  v_expira := now() + make_interval(hours => coalesce(v_cfg.intent_horas_vigencia, 24));

  v_url_intent := replace(replace(replace(replace(replace(
                    v_cfg.transfermovil_intent_template,
                    '$id_transaccion',   'ESTATICO'),
                    '$importe',          v_importe_txt),
                    '$moneda',           'CUP'),
                    '$numero_proveedor', v_cfg.transfermovil_numero_proveedor),
                    '$titulo',           v_cfg.transfermovil_titulo);

  v_url_http := replace(replace(replace(replace(replace(
                    v_cfg.transfermovil_url_template,
                    '$id_transaccion',   'ESTATICO'),
                    '$importe',          v_importe_txt),
                    '$moneda',           'CUP'),
                    '$numero_proveedor', v_cfg.transfermovil_numero_proveedor),
                    '$titulo',           v_cfg.transfermovil_titulo);

  insert into flow.suscripcion_intent
    (id_entidad, id_plan, uuid_usuario, monto, moneda, id_transaccion,
     numero_proveedor, url_intent, url_http, estado, expira_at)
  values
    (p_id_entidad, v_plan.id, v_uid, v_monto_cup, 'CUP', v_id_trx,
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
      -- Cobro real: CUP y entero.
      'monto',             v_monto_cup,
      'moneda',            'CUP',
      'importe',           v_importe_txt,
      -- Precio del plan tal cual, para mostrarlo al lado del cobro.
      'monto_plan',        v_plan.precio,
      'moneda_plan',       v_plan.moneda,
      'tasa_cup',          v_tasa_cup,
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
  'Crea el intent de pago de Transfermovil SIEMPRE en CUP (precio del plan convertido con la tasa del dia). Conserva la validacion de plan publico/privado. Si no hay tasa, no crea intent.';

-- ══ 3. PLANES: PRECIO EQUIVALENTE EN CUP ════════════════════════════════════
--
-- Base: versión de la 72 (públicos + privados del llamante, guarda de anon). Se
-- añade `precio_cup` para que la pantalla de "Mi suscripción" pueda mostrar el
-- importe que Transfermóvil va a cobrar sin recalcular nada en el cliente.
create or replace function flow.cliente_planes_suscripcion()
returns jsonb
language sql
stable
security definer
set search_path to 'flow', 'public'
as $function$
  select jsonb_build_object(
    'ok', true,
    'data', coalesce(
      (select jsonb_agg(
                jsonb_build_object(
                  'id',                   p.id,
                  'codigo',               p.codigo,
                  'nombre',               p.nombre,
                  'descripcion',          p.descripcion,
                  'duracion_dias',        p.duracion_dias,
                  'precio',               p.precio,
                  'moneda',               p.moneda,
                  'precio_cup',           flow._monto_en_cup(p.precio, p.moneda),
                  'limites',              p.limites,
                  'orden',                p.orden,
                  'modalidad',            p.modalidad,
                  'etiqueta',             p.etiqueta,
                  'es_privado',           (p.id_entidad is not null),
                  'id_entidad',           p.id_entidad,
                  'entidad_denominacion', e.denominacion,
                  'contacto_whatsapp',    cfg.soporte_whatsapp
                ) order by p.orden, p.precio, p.id)
         from flow.suscripcion_plan p
         left join flow.entidad e on e.id = p.id_entidad
         left join flow.suscripcion_config cfg on cfg.id = 1
        where p.activo
          and (
            p.id_entidad is null
            or (
              auth.uid() is not null
              and p.id_entidad in (
                select a.id_entidad
                from flow.admin_entidades_de_usuario(auth.uid()) a
              )
            )
          )),
      '[]'::jsonb
    )
  );
$function$;

comment on function flow.cliente_planes_suscripcion() is
  'Planes activos para "Mi suscripción": públicos + privados del llamante, con modalidad, etiqueta, es_privado y precio_cup (importe que se cobrará en CUP). Con anon sólo públicos.';

-- ══ 4. PERMISOS ═════════════════════════════════════════════════════════════

-- El helper lo llaman funciones SECURITY DEFINER: no se expone a la app
-- (mismo criterio que `flow._monto_cobro_reserva` en la 62).
revoke all on function flow._monto_en_cup(numeric, text) from public, anon;

revoke all on function flow.cliente_crear_intent_suscripcion(integer,bigint) from public;
grant execute on function flow.cliente_crear_intent_suscripcion(integer,bigint) to authenticated;
grant execute on function flow.cliente_crear_intent_suscripcion(integer,bigint) to service_role;

revoke all on function flow.cliente_planes_suscripcion() from public;
grant execute on function flow.cliente_planes_suscripcion() to anon;
grant execute on function flow.cliente_planes_suscripcion() to authenticated;
grant execute on function flow.cliente_planes_suscripcion() to service_role;

notify pgrst, 'reload schema';

-- ════════════════════════════════════════════════════════════════════════════
-- 5. VERIFICACIÓN (comentada: ejecutar a mano DESPUÉS de aplicar)
-- ════════════════════════════════════════════════════════════════════════════
--
-- 5.1 El helper responde con la forma esperada.
-- select flow._monto_en_cup(20, 'USD')   as usd_20,     -- 20 * tasa USD->CUP
--        flow._monto_en_cup(20, 'CUP')   as cup_20,     -- 20
--        flow._monto_en_cup(20, null)    as sin_moneda, -- 20
--        flow._monto_en_cup(0, 'USD')    as cero,       -- null
--        flow._monto_en_cup(20, 'XYZ')   as sin_tasa;   -- null
--
-- 5.2 Precio del plan, factor del día y monto en CUP (la consulta que pidió el
--     lead). `flow.tasa_factor` usa la fila más reciente de `flow.tasa_cambio`.
-- select p.codigo, p.nombre, p.precio, p.moneda,
--        flow.tasa_factor(p.moneda, 'CUP')      as factor_a_cup,
--        flow._monto_en_cup(p.precio, p.moneda) as precio_cup
--   from flow.suscripcion_plan p
--  where p.activo
--  order by p.orden, p.id;
--
-- 5.3 El RPC de planes ya trae `precio_cup` (con sesión o anon).
-- select jsonb_pretty(flow.cliente_planes_suscripcion());
--
-- 5.4 Reejecutar la migración no cambia nada: `create or replace` con la misma
--     firma, sin sobrecargas nuevas (esperado: una sola fila por función).
-- select p.proname, pg_get_function_identity_arguments(p.oid) as args
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'flow'
--    and p.proname in ('cliente_crear_intent_suscripcion',
--                      'cliente_planes_suscripcion', '_monto_en_cup')
--  order by p.proname;
--
-- 5.5 El intent cobra en CUP (requiere sesión de dueño/admin de una entidad).
--     Sustituir :ent por una entidad real y :plan por un plan activo de pago.
-- select flow.cliente_crear_intent_suscripcion(:ent, :plan);
--   -- esperado: ok=true, data.moneda='CUP', data.monto = data.monto_plan * data.tasa_cup
--   --           redondeado, data.importe entero y las URLs con moneda CUP.
-- select monto, moneda, url_intent
--   from flow.suscripcion_intent
--  order by id desc limit 1;      -- moneda = 'CUP'
--
-- 5.6 Sin tasas en cache el RPC no crea intent (probar en debug: borrar la fila
--     de `flow.tasa_cambio` dentro de una transacción y hacer rollback).
-- begin;
--   delete from flow.tasa_cambio;
--   select flow.cliente_crear_intent_suscripcion(:ent, :plan);
--     -- esperado: {"ok": false, "error": "No hay tasa de cambio para cobrar en CUP. Inténtalo más tarde."}
-- rollback;
--
-- ════════════════════════════════════════════════════════════════════════════
-- 6. REVERSIÓN (comentada: NO ejecutar salvo que haya que deshacer)
-- ════════════════════════════════════════════════════════════════════════════
--
-- -- 6.1 Volver a pegar la versión de la 72 de las dos funciones (misma firma,
-- --     con `create or replace`): sección 6.3 y 6.4 de
-- --     72_planes_limites_privados.sql. Con eso el intent vuelve a cobrar en la
-- --     moneda del plan y los planes dejan de traer `precio_cup`.
--
-- -- 6.2 Borrar el helper (ya no lo usa nadie tras el paso anterior).
-- drop function if exists flow._monto_en_cup(numeric, text);
--
-- -- 6.3 Recordar los grants de las funciones restauradas:
-- revoke all on function flow.cliente_crear_intent_suscripcion(integer,bigint) from public;
-- grant execute on function flow.cliente_crear_intent_suscripcion(integer,bigint) to authenticated;
-- grant execute on function flow.cliente_crear_intent_suscripcion(integer,bigint) to service_role;
-- revoke all on function flow.cliente_planes_suscripcion() from public;
-- grant execute on function flow.cliente_planes_suscripcion() to anon;
-- grant execute on function flow.cliente_planes_suscripcion() to authenticated;
-- grant execute on function flow.cliente_planes_suscripcion() to service_role;
--
-- notify pgrst, 'reload schema';
-- ════════════════════════════════════════════════════════════════════════════