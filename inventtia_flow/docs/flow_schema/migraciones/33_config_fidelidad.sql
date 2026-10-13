-- ════════════════════════════════════════════════════════════════════════════
-- MIGRACION 33: INTERRUPTOR GLOBAL DE FIDELIDAD
-- ════════════════════════════════════════════════════════════════════════════
--
-- QUE HACE
--   Le da al superadmin UN interruptor para decidir si el programa de fidelidad
--   existe para los clientes o no. En una sola fila (`flow.fidelidad_config`).
--
--   `activa = false` significa:
--     1. NO se acreditan puntos (el trigger del Paso 8 sale sin hacer nada).
--     2. El Home NO pinta la seccion de fidelidad.
--     3. (Con la migracion 34) el beneficio de bienvenida tampoco se aplica.
--
--   Lo que NO significa: borrar. Apagar es **pausar**.
--     - El libro de movimientos se conserva entero (es append-only).
--     - Al reactivar, se sigue acumulando desde ese momento y cada cliente
--       recupera el saldo que tenia. Nadie pierde puntos por un interruptor.
--
-- POR QUE UNA TABLA Y NO REUTILIZAR `regla_fidelidad.activo`
--   Son dos cosas distintas y hacian falta las dos:
--     - `regla_fidelidad.activo` dice "ESTA regla no aplica" (puede haber otra
--       que si, por entidad o por moneda).
--     - `fidelidad_config.activa` dice "el programa no existe para nadie".
--   Con solo `regla_fidelidad.activo`, apagar todas las reglas dejaria al cliente
--   sin regla y el Home sin nada, pero seguiriamos sin poder distinguir "no hay
--   reglas configuradas" de "el programa esta apagado a proposito".
--
-- FILA UNICA
--   `check (id = 1)` + PK: es imposible que haya dos configuraciones que se
--   contradigan. No hay que elegir "la ultima" ni ordenar por fecha.
--
-- DEPENDE DE: migracion 31 (tablas y helpers de fidelidad).
--
-- REVERSIBILIDAD
--   drop function if exists flow.admin_guardar_fidelidad_config(uuid, boolean);
--   drop function if exists flow.admin_obtener_fidelidad_config(uuid);
--   drop table if exists flow.fidelidad_config;
--   -- y volver a pegar `_acreditar_puntos_agenda` y `cliente_mi_fidelidad`
--   -- desde la migracion 31 para quitarles la lectura del interruptor.
-- ════════════════════════════════════════════════════════════════════════════

-- ── Comprobacion previa ─────────────────────────────────────────────────────
do $pre$
begin
  if to_regclass('flow.puntos_movimiento') is null
     or to_regclass('flow.regla_fidelidad') is null then
    raise exception 'Falta la migracion 31 (fidelidad). Aplicala antes que la 33.';
  end if;

  if to_regprocedure('public.fn_is_superadmin_full_access()') is null then
    raise exception 'Falta public.fn_is_superadmin_full_access().';
  end if;
end
$pre$;

-- ══ 1. LA CONFIGURACION (fila unica) ════════════════════════════════════════

create table if not exists flow.fidelidad_config (
  id         integer primary key default 1,
  activa     boolean not null default true,
  updated_by uuid,
  updated_at timestamptz not null default current_timestamp,
  constraint fidelidad_config_fila_unica check (id = 1)
);

-- Arranca ENCENDIDA: el programa se disena para existir, y apagarlo es una
-- decision explicita del superadmin. Si no hubiera fila, `cliente_mi_fidelidad`
-- tambien asume `true` (ver el `coalesce`), asi que no hay ventana de ambiguedad.
insert into flow.fidelidad_config (id, activa)
select 1, true
where not exists (select 1 from flow.fidelidad_config where id = 1);

-- ══ 2. RLS Y PERMISOS ═══════════════════════════════════════════════════════

alter table flow.fidelidad_config enable row level security;

-- El cliente necesita poder leer `activa` (lo hace `cliente_mi_fidelidad`, que es
-- `security invoker`). No es informacion sensible: es un booleano de plataforma.
drop policy if exists fidelidad_config_select_autenticados on flow.fidelidad_config;
create policy fidelidad_config_select_autenticados on flow.fidelidad_config
  for select to authenticated using (true);

drop policy if exists fidelidad_config_write_superadmin on flow.fidelidad_config;
create policy fidelidad_config_write_superadmin on flow.fidelidad_config
  for all to authenticated
  using (public.fn_is_superadmin_full_access())
  with check (public.fn_is_superadmin_full_access());

revoke all on flow.fidelidad_config from anon;
grant select on flow.fidelidad_config to authenticated;
grant all on flow.fidelidad_config to service_role;

-- ══ 3. EL TRIGGER DE ACREDITACION RESPETA EL INTERRUPTOR ═══════════════════
--    (unica diferencia con la version de la 31: el bloque `if not activa`)

create or replace function flow._acreditar_puntos_agenda(p_id_agenda integer)
returns jsonb
language plpgsql
security definer
set search_path to 'flow','public'
as $function$
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
$function$;

-- ══ 4. LA LECTURA DEL CLIENTE INFORMA EL ESTADO ════════════════════════════

-- Se anade `activa` para que el Home pueda decidir no pintar nada. El resto de
-- campos se siguen devolviendo aunque este apagada: el historial no se oculta a
-- quien pregunta por el, y asi el panel del superadmin tambien puede auditarlo.
create or replace function flow.cliente_mi_fidelidad()
returns jsonb
language sql
stable
set search_path to 'flow','public'
as $function$
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
$function$;

-- ══ 5. RPC DEL PANEL SUPERADMIN ═════════════════════════════════════════════

create or replace function flow.admin_obtener_fidelidad_config(
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
$function$;

-- Activa o desactiva el programa para TODOS los clientes.
create or replace function flow.admin_guardar_fidelidad_config(
  p_uuid_usuario uuid,
  p_activa       boolean
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
$function$;

-- ══ 6. PERMISOS DE EJECUCION ════════════════════════════════════════════════
-- Idioma de la migracion 27: revocar de los TRES roles publicos y volver a
-- conceder solo a quien lo necesita. Recordar que Supabase concede EXECUTE a
-- `authenticated` por privilegios por defecto en el CREATE: revocar solo de
-- `public` no basta.

revoke all on function flow.cliente_mi_fidelidad() from public, anon;
grant execute on function flow.cliente_mi_fidelidad() to authenticated, service_role;

revoke all on function flow.admin_obtener_fidelidad_config(uuid) from public, anon;
grant execute on function flow.admin_obtener_fidelidad_config(uuid) to authenticated, service_role;

revoke all on function flow.admin_guardar_fidelidad_config(uuid, boolean) from public, anon;
grant execute on function flow.admin_guardar_fidelidad_config(uuid, boolean) to authenticated, service_role;

-- Se vuelve a cerrar el helper interno: es SECURITY DEFINER y reparte puntos, asi
-- que no puede estar al alcance del cliente. (Redefinirlo en esta migracion
-- recrea su ACL con el grant por defecto a `authenticated`; hay que revocarlo
-- otra vez, o el agujero que cerro la 32 volveria a abrirse.)
revoke all on function flow._acreditar_puntos_agenda(integer) from public, anon, authenticated;
grant execute on function flow._acreditar_puntos_agenda(integer) to service_role;

notify pgrst, 'reload schema';

-- ══ 7. VERIFICACION ═════════════════════════════════════════════════════════

-- 7.a La configuracion existe, es una sola fila y arranca encendida.
select id, activa, updated_at, updated_by from flow.fidelidad_config;
-- Esperado: exactamente 1 fila con activa = true.

-- 7.b La estructura impide una segunda fila (check id = 1).
select conname, pg_get_constraintdef(oid) as definicion
from pg_constraint
where conrelid = 'flow.fidelidad_config'::regclass
order by conname;
-- Esperado: PK + el check `id = 1`.

-- 7.c El cliente ya recibe el estado del interruptor.
select flow.cliente_mi_fidelidad() -> 'activa' as activa,
       flow.cliente_mi_fidelidad() -> 'con_sesion' as con_sesion;
-- Sin sesion en el SQL Editor: activa = true, con_sesion = false.

-- 7.d El helper interno sigue cerrado tras la redefinicion (esto es lo critico).
select p.proname,
       has_function_privilege('authenticated', p.oid, 'execute') as authenticated_puede,
       p.proacl
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'flow'
  and p.proname in ('_acreditar_puntos_agenda','admin_guardar_fidelidad_config',
                    'admin_obtener_fidelidad_config','cliente_mi_fidelidad');
-- Esperado: _acreditar_puntos_agenda con authenticated_puede = FALSE y su proacl
-- sin `authenticated`. Los otros tres en TRUE.

-- 7.e Comprobacion de que apagar NO borra el libro.
select count(*) as movimientos_antes from flow.puntos_movimiento;
-- Apaga con la RPC del panel, vuelve a contar (debe ser el mismo numero) y
-- reactiva. Los puntos ganados siguen ahi.
-- ════════════════════════════════════════════════════════════════════════════