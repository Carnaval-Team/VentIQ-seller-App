-- ════════════════════════════════════════════════════════════════════════════
-- MIGRACION 31: FIDELIDAD (puntos) + BENEFICIO DE BIENVENIDA  [NUCLEO]
-- ════════════════════════════════════════════════════════════════════════════
--
-- QUE HACE
--   1. `flow.regla_fidelidad`  — reglas de acumulacion configurables (globales o
--      por entidad), con vigencia y caducidad de los puntos.
--   2. `flow.puntos_movimiento` — LIBRO de movimientos (append-only). Es la
--      auditoria y, a la vez, el saldo: no hay columna "saldo" que pueda quedar
--      desincronizada.
--   3. Acreditacion automatica al COMPLETAR una reserva, por trigger.
--   4. `flow.beneficio_bienvenida` + `flow.beneficio_canje` — el beneficio y su
--      canje, **una sola vez por usuario** (unique en uuid_usuario).
--   5. `flow.cliente_mi_fidelidad()` — lo que el Home necesita: saldo, regla,
--      beneficio disponible y los ultimos movimientos.
--
-- POR QUE EL TRIGGER Y NO `staff_marcar_estado_agenda`
--   Los archivos del repo pueden estar desactualizados respecto a la base (leccion
--   de la migracion 29). `staff_marcar_estado_agenda` es una funcion viva larga:
--   redefinirla para anadir un `perform` obliga a reproducirla entera y arriesga
--   pisar cambios que solo existen en la base. Un trigger `after update of
--   id_estado` consigue lo mismo, funciona venga la transicion de donde venga, y
--   NO reescribe ninguna funcion existente.
--   Ademas el trigger corre en la MISMA transaccion: si la reserva hace rollback,
--   los puntos tambien. No puede quedar una acreditacion huerfana.
--
-- IDEMPOTENCIA DE LA ACREDITACION
--   El ciclo de vida de `flow.agenda` es terminal: solo se permite
--   Reservado->Completado, Reservado->Cancelado y Cancelado->Completado, y desde
--   Completado no se puede ir a ningun lado (cancelar exige estado Reservado).
--   Aun asi, el indice unico parcial `puntos_movimiento_agenda_uidx` garantiza que
--   una agenda acredita puntos **como maximo una vez**, incluso si esa logica
--   cambiara en el futuro.
--
-- ORDEN DE DESCUENTO (para la migracion que aplica el precio)
--   1) precio de lista
--   2) descuento por promocion   (el que ya existe)
--   3) descuento por beneficio de bienvenida, sobre lo que quede
--   4) total = greatest(lista - promo - bienvenida, 0)
--
-- REVERSIBILIDAD (volver atras)
--   drop trigger if exists agenda_acreditar_puntos on flow.agenda;
--   drop function if exists flow.trg_agenda_acreditar_puntos();
--   drop function if exists flow.cliente_mi_fidelidad();
--   drop function if exists flow._acreditar_puntos_agenda(integer);
--   drop function if exists flow._resolver_beneficio_bienvenida(uuid, integer, varchar);
--   drop function if exists flow._resolver_regla_fidelidad(integer, varchar);
--   drop function if exists flow.fn_saldo_puntos(uuid);
--   drop table if exists flow.beneficio_canje;
--   drop table if exists flow.beneficio_bienvenida;
--   drop table if exists flow.puntos_movimiento;
--   drop table if exists flow.regla_fidelidad;
--   (Ninguna funcion existente fue redefinida, asi que no hay nada que restaurar.)
--
-- NO CAMBIA PRECIOS. Esta migracion es puramente aditiva: ninguna reserva cuesta
--   distinto despues de aplicarla. El descuento del beneficio entra en la
--   migracion siguiente, que si toca el camino de precio y lleva su prueba.
-- ════════════════════════════════════════════════════════════════════════════

-- ── Comprobacion previa ─────────────────────────────────────────────────────
do $pre$
begin
  if to_regclass('flow.agenda') is null
     or to_regclass('flow.entidad') is null
     or to_regclass('flow.local_servicio') is null
     or to_regclass('flow.app_dat_locales') is null
     or to_regclass('flow.nom_estado_agenda') is null then
    raise exception 'Falta el esquema base de flow (agenda / entidad / local_servicio / app_dat_locales / nom_estado_agenda). Aplica primero las migraciones 01..30.';
  end if;

  if to_regprocedure('public.fn_is_superadmin_full_access()') is null then
    raise exception 'Falta public.fn_is_superadmin_full_access().';
  end if;

  if to_regprocedure('flow.staff_marcar_estado_agenda(integer,integer)') is null then
    raise exception 'Falta flow.staff_marcar_estado_agenda(integer,integer): es quien lleva una reserva a Completado, y sin eso el trigger de acreditacion nunca dispara.';
  end if;
end
$pre$;

-- ══ 1. TABLAS ═══════════════════════════════════════════════════════════════

-- Reglas de acumulacion. `id_entidad is null` = regla global (la que se muestra
-- al cliente); con entidad = excepcion de esa entidad.
create table if not exists flow.regla_fidelidad (
  id                serial primary key,
  nombre            varchar(120) not null,
  id_entidad        integer references flow.entidad(id) on delete cascade,
  moneda            varchar(3),
  puntos_por_monto  numeric(12,2) not null default 1,
  monto_base        numeric(12,2) not null default 10,
  vigencia_dias     integer,
  activo            boolean not null default true,
  desde             timestamptz,
  hasta             timestamptz,
  created_by        uuid,
  created_at        timestamptz not null default current_timestamp,
  updated_at        timestamptz not null default current_timestamp,
  constraint regla_fidelidad_monto_base_pos  check (monto_base > 0),
  constraint regla_fidelidad_puntos_no_neg  check (puntos_por_monto >= 0),
  constraint regla_fidelidad_vigencia_pos   check (vigencia_dias is null or vigencia_dias > 0)
);

-- Libro de movimientos. `puntos` negativo = canje / vencimiento / ajuste a la baja.
-- `liquidado` marca una acumulacion ya caducada y ya asentada con su movimiento
-- de vencimiento, para no descontarla dos veces (ver `fn_saldo_puntos`).
create table if not exists flow.puntos_movimiento (
  id            bigserial primary key,
  uuid_usuario  uuid not null,
  puntos        integer not null,
  tipo          varchar(20) not null,
  motivo        text,
  id_agenda     integer references flow.agenda(id) on delete set null,
  id_entidad    integer references flow.entidad(id) on delete set null,
  id_regla      integer references flow.regla_fidelidad(id) on delete set null,
  moneda        varchar(3),
  monto         numeric(12,2),
  vence_en      timestamptz,
  liquidado     boolean not null default false,
  created_by    uuid,
  created_at    timestamptz not null default current_timestamp,
  constraint puntos_movimiento_tipo_chk
    check (tipo in ('acumulacion','canje','vencimiento','ajuste'))
);

-- Una agenda acredita puntos como maximo UNA vez. Es la red de seguridad de la
-- idempotencia, independiente de la logica de estados.
create unique index if not exists puntos_movimiento_agenda_uidx
  on flow.puntos_movimiento (id_agenda)
  where tipo = 'acumulacion' and id_agenda is not null;

create index if not exists puntos_movimiento_usuario_idx
  on flow.puntos_movimiento (uuid_usuario, created_at desc);

-- Busca rapido las acumulaciones sin caducar (saldo y vencimientos pendientes).
create index if not exists puntos_movimiento_vigentes_idx
  on flow.puntos_movimiento (uuid_usuario, vence_en)
  where tipo = 'acumulacion' and liquidado = false;

create table if not exists flow.beneficio_bienvenida (
  id            serial primary key,
  titulo        varchar(120) not null,
  descripcion   text,
  tipo          varchar(20) not null default 'porcentaje',
  valor         numeric(12,2) not null,
  moneda        varchar(3),
  id_entidad    integer references flow.entidad(id) on delete cascade,
  monto_minimo  numeric(12,2),
  activo        boolean not null default true,
  desde         timestamptz,
  hasta         timestamptz,
  created_by    uuid,
  created_at    timestamptz not null default current_timestamp,
  updated_at    timestamptz not null default current_timestamp,
  constraint beneficio_bienvenida_tipo_chk  check (tipo in ('porcentaje','monto')),
  constraint beneficio_bienvenida_valor_pos check (valor > 0)
);

-- El canje. `unique (uuid_usuario)` es literalmente la regla de negocio:
-- "aplicable una sola vez por usuario", en cualquier entidad y con cualquier
-- beneficio. La base lo impone, no el codigo.
--
-- `on delete restrict` (NO cascade) en id_beneficio, a proposito: si borrar un
-- beneficio se llevase por delante sus canjes, el usuario volveria a ser elegible
-- y la regla "una sola vez" se romperia sola. Un beneficio ya canjeado no se
-- borra: se desactiva (`activo = false`). La funcion admin_eliminar_* lo explica.
create table if not exists flow.beneficio_canje (
  id               bigserial primary key,
  uuid_usuario     uuid not null,
  id_beneficio     integer not null references flow.beneficio_bienvenida(id) on delete restrict,
  id_agenda        integer references flow.agenda(id) on delete set null,
  id_entidad       integer references flow.entidad(id) on delete set null,
  moneda           varchar(3),
  monto_descontado numeric(12,2),
  created_at       timestamptz not null default current_timestamp,
  constraint beneficio_canje_usuario_uidx unique (uuid_usuario)
);

-- Regla global por defecto: 1 punto por cada 10 gastados, caducan a los 12 meses.
-- Solo se inserta si no existe ya una global, para que re-ejecutar no duplique.
insert into flow.regla_fidelidad
  (nombre, id_entidad, moneda, puntos_por_monto, monto_base, vigencia_dias, activo)
select 'Programa de fidelidad', null, null, 1, 10, 365, true
where not exists (
  select 1 from flow.regla_fidelidad where id_entidad is null
);

-- ══ 2. RLS Y PERMISOS DE LECTURA ════════════════════════════════════════════

alter table flow.regla_fidelidad     enable row level security;
alter table flow.puntos_movimiento   enable row level security;
alter table flow.beneficio_bienvenida enable row level security;
alter table flow.beneficio_canje     enable row level security;

-- Las reglas y los beneficios son informacion publica del programa: el cliente
-- necesita saber "ganas 1 punto por cada 10" y que beneficio tiene pendiente.
drop policy if exists regla_fidelidad_select_autenticados on flow.regla_fidelidad;
create policy regla_fidelidad_select_autenticados on flow.regla_fidelidad
  for select to authenticated using (true);

drop policy if exists regla_fidelidad_write_superadmin on flow.regla_fidelidad;
create policy regla_fidelidad_write_superadmin on flow.regla_fidelidad
  for all to authenticated
  using (public.fn_is_superadmin_full_access())
  with check (public.fn_is_superadmin_full_access());

drop policy if exists beneficio_bienvenida_select_autenticados on flow.beneficio_bienvenida;
create policy beneficio_bienvenida_select_autenticados on flow.beneficio_bienvenida
  for select to authenticated using (true);

drop policy if exists beneficio_bienvenida_write_superadmin on flow.beneficio_bienvenida;
create policy beneficio_bienvenida_write_superadmin on flow.beneficio_bienvenida
  for all to authenticated
  using (public.fn_is_superadmin_full_access())
  with check (public.fn_is_superadmin_full_access());

-- Los movimientos son datos personales: cada uno ve SOLO los suyos. Nada de
-- `using (true)` aqui (a diferencia de resena/promocion, donde si lo hay).
drop policy if exists puntos_movimiento_select_propios on flow.puntos_movimiento;
create policy puntos_movimiento_select_propios on flow.puntos_movimiento
  for select to authenticated using (uuid_usuario = auth.uid());

drop policy if exists puntos_movimiento_write_superadmin on flow.puntos_movimiento;
create policy puntos_movimiento_write_superadmin on flow.puntos_movimiento
  for all to authenticated
  using (public.fn_is_superadmin_full_access())
  with check (public.fn_is_superadmin_full_access());

drop policy if exists beneficio_canje_select_propios on flow.beneficio_canje;
create policy beneficio_canje_select_propios on flow.beneficio_canje
  for select to authenticated using (uuid_usuario = auth.uid());

drop policy if exists beneficio_canje_write_superadmin on flow.beneficio_canje;
create policy beneficio_canje_write_superadmin on flow.beneficio_canje
  for all to authenticated
  using (public.fn_is_superadmin_full_access())
  with check (public.fn_is_superadmin_full_access());

-- El cliente lee por RPC `security invoker`, asi que necesita privilegio de tabla
-- (RLS filtra despues). Sin estos GRANT, el Data API devuelve 0 filas o 42501.
grant select on flow.regla_fidelidad       to authenticated;
grant select on flow.beneficio_bienvenida  to authenticated;
grant select on flow.puntos_movimiento     to authenticated;
grant select on flow.beneficio_canje       to authenticated;

-- ══ 3. SALDO ════════════════════════════════════════════════════════════════

-- Saldo = suma del libro, excluyendo solo las acumulaciones caducadas que AUN NO
-- se han asentado. Una acumulacion ya liquidada SI se cuenta (junto a su
-- movimiento negativo de vencimiento): +N y -N se anulan y el saldo sigue siendo
-- correcto tanto antes como despues de asentar. Sin doble descuento.
create or replace function flow.fn_saldo_puntos(p_uuid_usuario uuid)
returns integer
language sql
stable
set search_path to 'flow','public'
as $function$
  select coalesce(sum(m.puntos), 0)::integer
  from flow.puntos_movimiento m
  where m.uuid_usuario = p_uuid_usuario
    and not (
      m.tipo = 'acumulacion'
      and m.liquidado = false
      and m.vence_en is not null
      and m.vence_en <= current_timestamp
    );
$function$;

-- ══ 4. RESOLUTORES ══════════════════════════════════════════════════════════

-- Regla aplicable: la mas especifica gana (entidad antes que global, moneda
-- concreta antes que cualquiera). `moneda` nula en la regla = sirve para todas.
create or replace function flow._resolver_regla_fidelidad(
  p_id_entidad integer,
  p_moneda     varchar default null
)
returns table (
  id_regla         integer,
  puntos_por_monto numeric,
  monto_base       numeric,
  vigencia_dias    integer,
  moneda           varchar
)
language sql
stable
set search_path to 'flow','public'
as $function$
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
$function$;

-- Beneficio de bienvenida pendiente. Devuelve 0 filas si el usuario ya canjeo
-- alguno (la regla es "una sola vez por usuario", no una por beneficio).
create or replace function flow._resolver_beneficio_bienvenida(
  p_uuid_usuario uuid,
  p_id_entidad   integer default null,
  p_moneda       varchar default null
)
returns table (
  id_beneficio integer,
  titulo       varchar,
  descripcion  text,
  tipo         varchar,
  valor        numeric,
  moneda       varchar,
  monto_minimo numeric
)
language sql
stable
set search_path to 'flow','public'
as $function$
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
$function$;

-- ══ 5. ACREDITACION AL COMPLETAR ════════════════════════════════════════════

-- Acredita los puntos de una reserva completada. NUNCA lanza excepcion: si algo
-- falla devuelve {ok:false} y la reserva se completa igual. Un fallo de puntos no
-- puede bloquear la operacion principal del negocio.
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

  -- Ya acreditada. El indice unico tambien lo impediria; esto es para no calcular.
  if exists (
    select 1 from flow.puntos_movimiento m
    where m.id_agenda = p_id_agenda and m.tipo = 'acumulacion'
  ) then
    return jsonb_build_object('ok', true, 'ya_acreditado', true, 'puntos', 0);
  end if;

  -- Reserva sin importe (config_precio = '{}'): no hay nada que acumular.
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

  -- Redondeo hacia abajo: nunca se regalan puntos por fracciones incompletas.
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

-- Dispara la acreditacion cuando una reserva pasa a Completado. `after update of
-- id_estado` + `is distinct from` evita acreditaciones por updates que no cambian
-- el estado.
create or replace function flow.trg_agenda_acreditar_puntos()
returns trigger
language plpgsql
security definer
set search_path to 'flow','public'
as $function$
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
$function$;

drop trigger if exists agenda_acreditar_puntos on flow.agenda;
create trigger agenda_acreditar_puntos
  after update of id_estado on flow.agenda
  for each row
  execute function flow.trg_agenda_acreditar_puntos();

-- ══ 6. LECTURA PARA EL CLIENTE ══════════════════════════════════════════════

-- Todo lo que el Home necesita en UNA llamada. `security invoker`: respeta RLS,
-- asi que los movimientos que devuelve son siempre los de quien llama.
-- Si no hay sesion devuelve un objeto vacio coherente en vez de reventar.
create or replace function flow.cliente_mi_fidelidad()
returns jsonb
language sql
stable
set search_path to 'flow','public'
as $function$
  with yo as (select auth.uid() as u)
  select jsonb_build_object(
    'con_sesion', (select u from yo) is not null,
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

-- ══ 7. PERMISOS DE EJECUCION ════════════════════════════════════════════════

-- ⚠ TRAMPA DE SUPABASE (y motivo de este bloque): Supabase concede EXECUTE a
--   `authenticated` por **privilegios por defecto** en el momento de crear cada
--   funcion. Por eso `revoke all ... from public` NO BASTA: deja en pie ese grant
--   explicito y `has_function_privilege('authenticated', ...)` sigue devolviendo
--   true. Hay que revocar tambien de `anon` y `authenticated`, y volver a
--   conceder solo a quien de verdad lo necesita. Es el mismo idioma que usa la
--   migracion 27 (ver `_aplicar_promocion`, cuyo ACL es {postgres, service_role}).

-- El cliente solo puede leer su fidelidad.
revoke all on function flow.cliente_mi_fidelidad() from public, anon;
grant execute on function flow.cliente_mi_fidelidad() to authenticated, service_role;

-- `fn_saldo_puntos` SI es ejecutable por el cliente: lo llama
-- `cliente_mi_fidelidad()` (security invoker). No filtra datos ajenos porque RLS
-- sobre `puntos_movimiento` es `uuid_usuario = auth.uid()`: preguntar por el uuid
-- de otro devuelve 0 filas, o sea saldo 0, no el suyo. Se quita solo de public y
-- anon.
revoke all on function flow.fn_saldo_puntos(uuid) from public, anon;
grant execute on function flow.fn_saldo_puntos(uuid) to authenticated, service_role;

-- Helpers internos: nadie los llama desde la app.
-- `_acreditar_puntos_agenda` es `security definer` y REPARTE PUNTOS: si el
-- cliente pudiera llamarla, acreditaria puntos de una reserva sin completarla (y
-- como cancelar solo exige estado Reservado, se los quedaria). Se revoca de los
-- tres roles publicos y se concede solo a service_role.
revoke all on function flow._acreditar_puntos_agenda(integer) from public, anon, authenticated;
grant execute on function flow._acreditar_puntos_agenda(integer) to service_role;

revoke all on function flow._resolver_regla_fidelidad(integer, varchar) from public, anon, authenticated;
grant execute on function flow._resolver_regla_fidelidad(integer, varchar) to service_role;

revoke all on function flow._resolver_beneficio_bienvenida(uuid, integer, varchar) from public, anon, authenticated;
grant execute on function flow._resolver_beneficio_bienvenida(uuid, integer, varchar) to service_role;

-- La funcion del trigger tampoco se llama a mano.
revoke all on function flow.trg_agenda_acreditar_puntos() from public, anon, authenticated;
grant execute on function flow.trg_agenda_acreditar_puntos() to service_role;

-- PostgREST cachea el esquema: sin esto, las tablas y RPC nuevas no se ven hasta
-- que el servicio recargue por su cuenta.
notify pgrst, 'reload schema';

-- ══ 8. VERIFICACION ═════════════════════════════════════════════════════════

-- 8.a Las 4 tablas existen con sus politicas.
select c.relname as tabla,
       (select count(*) from pg_policy po where po.polrelid = c.oid) as politicas,
       c.relrowsecurity as rls_activo
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'flow'
  and c.relname in ('regla_fidelidad','puntos_movimiento','beneficio_bienvenida','beneficio_canje')
order by c.relname;
-- Esperado: 4 filas, rls_activo = true, y 2 politicas en cada una.

-- 8.b Regla global por defecto (1 punto por cada 10, caducan a los 365 dias).
select id, nombre, puntos_por_monto, monto_base, vigencia_dias, activo
from flow.regla_fidelidad
where id_entidad is null;
-- Esperado: 1 fila activa.

-- 8.c Indice unico de idempotencia y constraint del canje unico.
select indexname from pg_indexes
where schemaname = 'flow'
  and indexname in ('puntos_movimiento_agenda_uidx','beneficio_canje_usuario_uidx');
-- Esperado: 2 filas.

-- 8.d El trigger esta creado y apunta a Completado.
select tgname, pg_get_triggerdef(t.oid) as definicion
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'flow' and c.relname = 'agenda' and not t.tgisinternal;
-- Esperado: agenda_acreditar_puntos con "after update of id_estado".

-- 8.e Los 5 campos de la lectura del cliente.
select flow.cliente_mi_fidelidad() as mi_fidelidad;
-- Sin sesion en el SQL Editor sale con_sesion=false, saldo=0, movimientos=[].
-- Es lo correcto: no hay auth.uid() que leer.

-- 8.f Saldo y movimientos de un usuario real (solo lectura).
select u.uuid_usuario,
       flow.fn_saldo_puntos(u.uuid_usuario) as saldo,
       count(*) as movimientos
from (
  select uuid_usuario from flow.agenda group by uuid_usuario limit 5
) u
left join flow.puntos_movimiento m on m.uuid_usuario = u.uuid_usuario
group by u.uuid_usuario
order by u.uuid_usuario;
-- Esperado: los usuarios con reservas completadas tendran movimientos; el resto 0.
-- (Antes de esta migracion no hay ningun movimiento: la tabla arranca vacia.)

-- ══ 9. PRUEBA MANUAL (opcional, no persiste nada) ═══════════════════════════
-- Pega este bloque aparte para comprobar la acreditacion de punta a punta:
--
-- begin;
--   -- 1) Crear un beneficio de bienvenida de prueba (20%).
--   insert into flow.beneficio_bienvenida (titulo, tipo, valor, moneda, activo)
--   values ('TEST 20%', 'porcentaje', 20, 'USD', true);
--
--   -- 2) Reserva recien completada: elegir una agenda real y completarla.
--   --    (sustituye 123 por un id de flow.agenda en estado Reservado)
--   update flow.agenda set id_estado = 3 where id = 123;
--
--   -- 3) Debe existir exactamente UN movimiento de acumulacion para esa agenda.
--   select * from flow.puntos_movimiento where id_agenda = 123;
--
--   -- 4) Re-completar NO debe acreditar de nuevo (el trigger no dispara porque
--   --    el estado no cambia; y si disparara, el indice unico lo corta).
--   update flow.agenda set id_estado = 3 where id = 123;
--   select count(*) from flow.puntos_movimiento
--    where id_agenda = 123 and tipo = 'acumulacion';   -- debe seguir siendo 1
--
--   -- 5) Saldo coherente con el libro.
--   select flow.fn_saldo_puntos(uuid_usuario) from flow.agenda where id = 123;
-- rollback;
-- ════════════════════════════════════════════════════════════════════════════