-- ════════════════════════════════════════════════════════════════════════════
-- MIGRACION 32: FIDELIDAD — CONFIGURACION Y AUDITORIA (panel superadmin)
-- ════════════════════════════════════════════════════════════════════════════
--
-- QUE HACE
--   La API que consume `ventiq_superadmin` para configurar el programa y auditar
--   los puntos. Todas son `security invoker` + doble comprobacion:
--     1) `auth.uid() is distinct from p_uuid_usuario`  -> 'Sesion no valida'
--     2) `public.fn_is_superadmin_full_access()`
--   Es el mismo patron que patrocinados (28) y colecciones (30).
--
--   Reglas de acumulacion ....... admin_listar_reglas_fidelidad
--                                 admin_guardar_regla_fidelidad
--                                 admin_eliminar_regla_fidelidad
--   Beneficio de bienvenida ..... admin_listar_beneficios_bienvenida
--                                 admin_guardar_beneficio_bienvenida
--                                 admin_eliminar_beneficio_bienvenida
--   Auditoria ................... admin_listar_movimientos_puntos
--                                 admin_ajustar_puntos_usuario
--
-- NO CAMBIA PRECIOS ni acredita puntos por si sola: eso lo hace la 31 (trigger al
-- completar) y la 33 (descuento del beneficio). Esta es la capa de gestion.
--
-- DEPENDE DE: migracion 31 (tablas y helpers de fidelidad).
--
-- REVERSIBILIDAD
--   drop function if exists flow.admin_listar_reglas_fidelidad(uuid);
--   drop function if exists flow.admin_guardar_regla_fidelidad(uuid,text,integer,text,numeric,numeric,integer,boolean,timestamptz,timestamptz,integer);
--   drop function if exists flow.admin_eliminar_regla_fidelidad(uuid,integer);
--   drop function if exists flow.admin_listar_beneficios_bienvenida(uuid);
--   drop function if exists flow.admin_guardar_beneficio_bienvenida(uuid,text,text,text,numeric,text,integer,numeric,boolean,timestamptz,timestamptz,integer);
--   drop function if exists flow.admin_eliminar_beneficio_bienvenida(uuid,integer);
--   drop function if exists flow.admin_listar_movimientos_puntos(uuid,uuid);
--   drop function if exists flow.admin_ajustar_puntos_usuario(uuid,uuid,integer,text);
-- ════════════════════════════════════════════════════════════════════════════

-- ── Comprobacion previa ─────────────────────────────────────────────────────
do $pre$
begin
  if to_regclass('flow.regla_fidelidad') is null
     or to_regclass('flow.puntos_movimiento') is null
     or to_regclass('flow.beneficio_bienvenida') is null
     or to_regclass('flow.beneficio_canje') is null then
    raise exception 'Falta la migracion 31 (fidelidad). Aplicala antes que la 32.';
  end if;

  if to_regprocedure('public.fn_is_superadmin_full_access()') is null then
    raise exception 'Falta public.fn_is_superadmin_full_access().';
  end if;
end
$pre$;

-- ══ 1. REGLAS DE ACUMULACION ════════════════════════════════════════════════

create or replace function flow.admin_listar_reglas_fidelidad(
  p_uuid_usuario uuid
)
returns jsonb
language plpgsql
stable
set search_path to 'flow','public'
as $function$
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
$function$;

create or replace function flow.admin_guardar_regla_fidelidad(
  p_uuid_usuario    uuid,
  p_nombre          text,
  p_id_entidad      integer,
  p_moneda          text,
  p_puntos_por_monto numeric,
  p_monto_base      numeric,
  p_vigencia_dias   integer,
  p_activo          boolean,
  p_desde           timestamptz,
  p_hasta           timestamptz,
  p_id              integer
)
returns jsonb
language plpgsql
security invoker
set search_path to 'flow','public'
as $function$
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
$function$;

create or replace function flow.admin_eliminar_regla_fidelidad(
  p_uuid_usuario uuid,
  p_id           integer
)
returns jsonb
language plpgsql
security invoker
set search_path to 'flow','public'
as $function$
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
$function$;

-- ══ 2. BENEFICIO DE BIENVENIDA ══════════════════════════════════════════════

create or replace function flow.admin_listar_beneficios_bienvenida(
  p_uuid_usuario uuid
)
returns jsonb
language plpgsql
stable
set search_path to 'flow','public'
as $function$
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
$function$;

create or replace function flow.admin_guardar_beneficio_bienvenida(
  p_uuid_usuario uuid,
  p_titulo       text,
  p_descripcion  text,
  p_tipo         text,
  p_valor        numeric,
  p_moneda       text,
  p_id_entidad   integer,
  p_monto_minimo numeric,
  p_activo       boolean,
  p_desde        timestamptz,
  p_hasta        timestamptz,
  p_id           integer
)
returns jsonb
language plpgsql
security invoker
set search_path to 'flow','public'
as $function$
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
$function$;

create or replace function flow.admin_eliminar_beneficio_bienvenida(
  p_uuid_usuario uuid,
  p_id           integer
)
returns jsonb
language plpgsql
security invoker
set search_path to 'flow','public'
as $function$
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
$function$;

-- ══ 3. AUDITORIA DE PUNTOS ══════════════════════════════════════════════════

-- El libro completo de un usuario. Es la herramienta para responder "por que este
-- cliente tiene estos puntos".
create or replace function flow.admin_listar_movimientos_puntos(
  p_uuid_usuario  uuid,
  p_uuid_destino  uuid
)
returns jsonb
language plpgsql
stable
set search_path to 'flow','public'
as $function$
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
$function$;

-- Ajuste manual con motivo obligatorio. No permite poner el saldo en negativo: un
-- saldo negativo no significa nada para el cliente y rompe la lectura del Home.
create or replace function flow.admin_ajustar_puntos_usuario(
  p_uuid_usuario uuid,
  p_uuid_destino uuid,
  p_puntos       integer,
  p_motivo       text
)
returns jsonb
language plpgsql
security invoker
set search_path to 'flow','public'
as $function$
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
$function$;

-- ══ 4. PERMISOS ═════════════════════════════════════════════════════════════

revoke all on function flow.admin_listar_reglas_fidelidad(uuid) from public, anon;
revoke all on function flow.admin_guardar_regla_fidelidad(uuid,text,integer,text,numeric,numeric,integer,boolean,timestamptz,timestamptz,integer) from public, anon;
revoke all on function flow.admin_eliminar_regla_fidelidad(uuid,integer) from public, anon;
revoke all on function flow.admin_listar_beneficios_bienvenida(uuid) from public, anon;
revoke all on function flow.admin_guardar_beneficio_bienvenida(uuid,text,text,text,numeric,text,integer,numeric,boolean,timestamptz,timestamptz,integer) from public, anon;
revoke all on function flow.admin_eliminar_beneficio_bienvenida(uuid,integer) from public, anon;
revoke all on function flow.admin_listar_movimientos_puntos(uuid,uuid) from public, anon;
revoke all on function flow.admin_ajustar_puntos_usuario(uuid,uuid,integer,text) from public, anon;

grant execute on function flow.admin_listar_reglas_fidelidad(uuid) to authenticated, service_role;
grant execute on function flow.admin_guardar_regla_fidelidad(uuid,text,integer,text,numeric,numeric,integer,boolean,timestamptz,timestamptz,integer) to authenticated, service_role;
grant execute on function flow.admin_eliminar_regla_fidelidad(uuid,integer) to authenticated, service_role;
grant execute on function flow.admin_listar_beneficios_bienvenida(uuid) to authenticated, service_role;
grant execute on function flow.admin_guardar_beneficio_bienvenida(uuid,text,text,text,numeric,text,integer,numeric,boolean,timestamptz,timestamptz,integer) to authenticated, service_role;
grant execute on function flow.admin_eliminar_beneficio_bienvenida(uuid,integer) to authenticated, service_role;
grant execute on function flow.admin_listar_movimientos_puntos(uuid,uuid) to authenticated, service_role;
grant execute on function flow.admin_ajustar_puntos_usuario(uuid,uuid,integer,text) to authenticated, service_role;

-- ── CORRECTIVO para bases donde la 31 ya se aplico ──────────────────────────
-- La primera version de la 31 revocaba solo de `public`, y Supabase concede
-- EXECUTE a `authenticated` por privilegios por defecto en el CREATE. Resultado:
-- `_acreditar_puntos_agenda` quedaba ejecutable por cualquier cliente. Este
-- bloque lo cierra sin necesidad de re-ejecutar la 31 (que ya esta corregida
-- para instalaciones nuevas). Es idempotente.
revoke all on function flow._acreditar_puntos_agenda(integer) from public, anon, authenticated;
grant execute on function flow._acreditar_puntos_agenda(integer) to service_role;

revoke all on function flow._resolver_regla_fidelidad(integer, varchar) from public, anon, authenticated;
grant execute on function flow._resolver_regla_fidelidad(integer, varchar) to service_role;

revoke all on function flow._resolver_beneficio_bienvenida(uuid, integer, varchar) from public, anon, authenticated;
grant execute on function flow._resolver_beneficio_bienvenida(uuid, integer, varchar) to service_role;

revoke all on function flow.trg_agenda_acreditar_puntos() from public, anon, authenticated;
grant execute on function flow.trg_agenda_acreditar_puntos() to service_role;

-- `fn_saldo_puntos` se queda para `authenticated`: lo llama `cliente_mi_fidelidad`
-- (invoker). Solo se le quita `public`/`anon`. RLS ya impide leer el saldo ajeno.
revoke all on function flow.fn_saldo_puntos(uuid) from public, anon;
grant execute on function flow.fn_saldo_puntos(uuid) to authenticated, service_role;

notify pgrst, 'reload schema';

-- ══ 5. VERIFICACION ═════════════════════════════════════════════════════════

-- 5.a Las 8 funciones existen, con la firma esperada.
select p.proname,
       pg_get_function_arguments(p.oid) as argumentos,
       p.prosecdef as es_definer,
       has_function_privilege('authenticated', p.oid, 'execute') as authenticated_puede
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'flow'
  and p.proname in (
    'admin_listar_reglas_fidelidad',    'admin_guardar_regla_fidelidad',
    'admin_eliminar_regla_fidelidad',   'admin_listar_beneficios_bienvenida',
    'admin_guardar_beneficio_bienvenida','admin_eliminar_beneficio_bienvenida',
    'admin_listar_movimientos_puntos',  'admin_ajustar_puntos_usuario'
  )
order by p.proname;
-- Esperado: 8 filas, es_definer = false en todas, authenticated_puede = true.

-- 5.b Sin sesion de superadmin, las funciones rechazan. En el SQL Editor
--     auth.uid() es NULL, asi que este es justo el caso "sin sesion".
select flow.admin_listar_reglas_fidelidad('00000000-0000-0000-0000-000000000000'::uuid) as sin_sesion;
-- Esperado: {"ok": false, "error": "Sesion no valida"}

-- 5.c La regla global se lee bien.
select flow.admin_listar_reglas_fidelidad(null) as reglas;
-- Esperado: {"ok": false, "error": "Sesion no valida"} (no hay auth.uid()).
-- Con una sesion real de superadmin devolveria la lista con la regla global.

-- 5.d Los helpers internos de la 31 NO son ejecutables por el cliente.
select p.proname,
       has_function_privilege('authenticated', p.oid, 'execute') as authenticated_puede
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'flow'
  and p.proname in ('_acreditar_puntos_agenda','_resolver_regla_fidelidad',
                    '_resolver_beneficio_bienvenida','trg_agenda_acreditar_puntos',
                    'fn_saldo_puntos');
-- Esperado: _acreditar_puntos_agenda, _resolver_regla_fidelidad,
-- _resolver_beneficio_bienvenida y trg_agenda_acreditar_puntos con
-- authenticated_puede = FALSE. `fn_saldo_puntos` debe salir TRUE y es correcto:
-- lo llama `cliente_mi_fidelidad()` (invoker), y RLS ya limita sus filas a las
-- del propio usuario.
-- Lo importante es `_acreditar_puntos_agenda`: es security definer y REPARTE
-- PUNTOS. Si el cliente pudiera llamarla, acreditaria los puntos de una reserva
-- sin completarla y, como cancelar solo exige estado Reservado, se los quedaria.
-- ════════════════════════════════════════════════════════════════════════════