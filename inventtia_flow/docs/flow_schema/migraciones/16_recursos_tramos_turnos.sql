-- ============================================================================
-- MIGRACION 16: Recursos, tramos y turnos por local_servicio
--
-- Objetivo: modelar capacidad COMPARTIDA por "tramos". Ejemplo (transporte):
--   Servicio "Transporte" en un local tiene 2 RECURSOS: "Carro 1", "Carro 2".
--   Carro 1 ofrece los TRAMOS "Ida" y "Vuelta" (cada uno con su capacidad).
--   Sobre esos tramos define TURNOS reservables:
--     - "Ida y vuelta" -> ocupa {Ida, Vuelta}
--     - "Solo ida"     -> ocupa {Ida}
--     - "Solo vuelta"  -> ocupa {Vuelta}
--   Reservar "Ida y vuelta" descuenta 1 de Ida y 1 de Vuelta.
--   Reservar "Solo ida"     descuenta 1 de Ida (Vuelta queda intacto).
--   Disponibilidad de un turno = MIN(disponibles de todos sus tramos).
--
-- AUTODETECCION: un turno con un solo tramo se comporta como "independiente".
--
-- COMPATIBILIDAD: estas tablas son ADITIVAS. Un local_servicio SIN recursos
-- activos sigue usando flow.plan_servicios exactamente como hoy (un cupo/dia).
--
-- El primitivo de capacidad-por-dia es flow.plan_tramo (analogo a plan_servicios
-- pero por tramo). agenda.id_turno / sala_espera.id_turno enlazan la reserva a
-- su turno (NULL = flujo legacy sin recursos).
--
-- RLS: identica a flow.plan_servicios / flow.plan_config. La cadena de propiedad
-- baja siempre hasta el local_servicio y de ahi a la entidad del usuario:
--   recurso.id_local_servicio -> local_servicio.id_local -> app_dat_locales.id_entidad
-- Los hijos (tramo, turno, turno_tramo, plan_tramo) resuelven propiedad subiendo
-- hasta su recurso.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) RECURSO: unidad fisica que presta el servicio (Carro 1, Sala A, Mesa 3...)
-- ----------------------------------------------------------------------------
create table if not exists flow.recurso (
  id                integer generated always as identity primary key,
  id_local_servicio integer not null
                    references flow.local_servicio(id) on delete cascade,
  nombre            varchar not null,
  capacidad         integer not null default 1,   -- capacidad por defecto de sus tramos
  orden             integer not null default 0,
  activo            boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

comment on table  flow.recurso is
  'Unidad que presta un local_servicio (ej: Carro 1). Agrupa tramos y turnos.';
comment on column flow.recurso.capacidad is
  'Capacidad por defecto que heredan los tramos del recurso si no definen la suya.';

create index if not exists idx_recurso_local_servicio
  on flow.recurso (id_local_servicio) where activo;

-- ----------------------------------------------------------------------------
-- 2) TRAMO: bucket de capacidad compartida dentro de un recurso (Ida, Vuelta)
-- ----------------------------------------------------------------------------
create table if not exists flow.tramo (
  id          integer generated always as identity primary key,
  id_recurso  integer not null references flow.recurso(id) on delete cascade,
  nombre      varchar not null,
  capacidad   integer,               -- NULL = hereda recurso.capacidad
  orden       integer not null default 0,
  activo      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table  flow.tramo is
  'Bucket de capacidad compartida dentro de un recurso (ej: Ida, Vuelta). '
  'Varios turnos pueden consumir el mismo tramo.';
comment on column flow.tramo.capacidad is
  'Capacidad del tramo/dia. NULL = hereda recurso.capacidad al generar plan_tramo.';

create index if not exists idx_tramo_recurso
  on flow.tramo (id_recurso) where activo;

-- ----------------------------------------------------------------------------
-- 3) TURNO: opcion reservable = conjunto de tramos (Ida y vuelta, Solo ida...)
-- ----------------------------------------------------------------------------
create table if not exists flow.turno (
  id          integer generated always as identity primary key,
  id_recurso  integer not null references flow.recurso(id) on delete cascade,
  nombre      varchar not null,
  orden       integer not null default 0,
  activo      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table flow.turno is
  'Opcion reservable de un recurso. Consume 1 plaza de CADA tramo asociado.';

create index if not exists idx_turno_recurso
  on flow.turno (id_recurso) where activo;

-- ----------------------------------------------------------------------------
-- 4) TURNO_TRAMO: que tramos ocupa cada turno (M:N)
-- ----------------------------------------------------------------------------
create table if not exists flow.turno_tramo (
  id_turno integer not null references flow.turno(id) on delete cascade,
  id_tramo integer not null references flow.tramo(id) on delete cascade,
  primary key (id_turno, id_tramo)
);

comment on table flow.turno_tramo is
  'Tramos que consume un turno. Reservar el turno descuenta 1 de cada tramo aqui.';

-- ----------------------------------------------------------------------------
-- 5) PLAN_TRAMO: capacidad y consumo por (tramo, dia). Analogo a plan_servicios.
-- ----------------------------------------------------------------------------
create table if not exists flow.plan_tramo (
  id          bigint generated always as identity primary key,
  id_tramo    integer not null references flow.tramo(id) on delete cascade,
  fecha       timestamptz not null default now(),
  cantidad    integer not null default 0,
  agendados   integer not null default 0,
  created_at  timestamptz not null default now(),
  unique (id_tramo, fecha)
);

comment on table flow.plan_tramo is
  'Cupo por (tramo, dia): cantidad total y agendados. Disponible = cantidad - agendados.';

create index if not exists idx_plan_tramo_tramo_fecha
  on flow.plan_tramo (id_tramo, fecha);

-- ----------------------------------------------------------------------------
-- 6) Enlaces de reserva -> turno (NULL = reserva legacy sin recursos)
-- ----------------------------------------------------------------------------
alter table flow.agenda
  add column if not exists id_turno integer references flow.turno(id);
comment on column flow.agenda.id_turno is
  'Turno reservado (NULL = servicio sin recursos, usa plan_servicios).';

alter table flow.sala_espera
  add column if not exists id_turno integer references flow.turno(id);
comment on column flow.sala_espera.id_turno is
  'Turno solicitado en cola (NULL = servicio sin recursos, usa plan_servicios).';

create index if not exists idx_agenda_turno      on flow.agenda (id_turno)      where id_turno is not null;
create index if not exists idx_sala_espera_turno on flow.sala_espera (id_turno) where id_turno is not null;

-- ============================================================================
-- RLS
-- ============================================================================
alter table flow.recurso     enable row level security;
alter table flow.tramo       enable row level security;
alter table flow.turno       enable row level security;
alter table flow.turno_tramo enable row level security;
alter table flow.plan_tramo  enable row level security;

-- Helper de pertenencia (inline por tabla): ¿auth.uid() administra la entidad
-- dueña del local_servicio de ESTE recurso?
-- recurso -> local_servicio -> app_dat_locales -> entidad
-- Se repite el patron ya usado en 05_rls_plan_servicios / 09_tabla_plan_config.

-- ---- RECURSO -------------------------------------------------------------
drop policy if exists "recurso_select" on flow.recurso;
drop policy if exists "recurso_insert" on flow.recurso;
drop policy if exists "recurso_update" on flow.recurso;
drop policy if exists "recurso_delete" on flow.recurso;

create policy "recurso_select" on flow.recurso
  for select to authenticated using (true);

create policy "recurso_insert" on flow.recurso
  for insert to authenticated with check (
    exists (
      select 1 from flow.local_servicio ls
      join flow.app_dat_locales l on l.id = ls.id_local
      where ls.id = recurso.id_local_servicio
        and l.id_entidad in (select id_entidad from flow.admin_entidades_de_usuario(auth.uid()))
    )
  );

create policy "recurso_update" on flow.recurso
  for update to authenticated
  using (
    exists (
      select 1 from flow.local_servicio ls
      join flow.app_dat_locales l on l.id = ls.id_local
      where ls.id = recurso.id_local_servicio
        and l.id_entidad in (select id_entidad from flow.admin_entidades_de_usuario(auth.uid()))
    )
  )
  with check (
    exists (
      select 1 from flow.local_servicio ls
      join flow.app_dat_locales l on l.id = ls.id_local
      where ls.id = recurso.id_local_servicio
        and l.id_entidad in (select id_entidad from flow.admin_entidades_de_usuario(auth.uid()))
    )
  );

create policy "recurso_delete" on flow.recurso
  for delete to authenticated using (
    exists (
      select 1 from flow.local_servicio ls
      join flow.app_dat_locales l on l.id = ls.id_local
      where ls.id = recurso.id_local_servicio
        and l.id_entidad in (select id_entidad from flow.admin_entidades_de_usuario(auth.uid()))
    )
  );

-- ---- TRAMO (propiedad via su recurso) ------------------------------------
drop policy if exists "tramo_select" on flow.tramo;
drop policy if exists "tramo_write"  on flow.tramo;

create policy "tramo_select" on flow.tramo
  for select to authenticated using (true);

create policy "tramo_write" on flow.tramo
  for all to authenticated
  using (
    exists (
      select 1 from flow.recurso r
      join flow.local_servicio ls on ls.id = r.id_local_servicio
      join flow.app_dat_locales l on l.id = ls.id_local
      where r.id = tramo.id_recurso
        and l.id_entidad in (select id_entidad from flow.admin_entidades_de_usuario(auth.uid()))
    )
  )
  with check (
    exists (
      select 1 from flow.recurso r
      join flow.local_servicio ls on ls.id = r.id_local_servicio
      join flow.app_dat_locales l on l.id = ls.id_local
      where r.id = tramo.id_recurso
        and l.id_entidad in (select id_entidad from flow.admin_entidades_de_usuario(auth.uid()))
    )
  );

-- ---- TURNO (propiedad via su recurso) ------------------------------------
drop policy if exists "turno_select" on flow.turno;
drop policy if exists "turno_write"  on flow.turno;

create policy "turno_select" on flow.turno
  for select to authenticated using (true);

create policy "turno_write" on flow.turno
  for all to authenticated
  using (
    exists (
      select 1 from flow.recurso r
      join flow.local_servicio ls on ls.id = r.id_local_servicio
      join flow.app_dat_locales l on l.id = ls.id_local
      where r.id = turno.id_recurso
        and l.id_entidad in (select id_entidad from flow.admin_entidades_de_usuario(auth.uid()))
    )
  )
  with check (
    exists (
      select 1 from flow.recurso r
      join flow.local_servicio ls on ls.id = r.id_local_servicio
      join flow.app_dat_locales l on l.id = ls.id_local
      where r.id = turno.id_recurso
        and l.id_entidad in (select id_entidad from flow.admin_entidades_de_usuario(auth.uid()))
    )
  );

-- ---- TURNO_TRAMO (propiedad via su turno -> recurso) ---------------------
drop policy if exists "turno_tramo_select" on flow.turno_tramo;
drop policy if exists "turno_tramo_write"  on flow.turno_tramo;

create policy "turno_tramo_select" on flow.turno_tramo
  for select to authenticated using (true);

create policy "turno_tramo_write" on flow.turno_tramo
  for all to authenticated
  using (
    exists (
      select 1 from flow.turno t
      join flow.recurso r on r.id = t.id_recurso
      join flow.local_servicio ls on ls.id = r.id_local_servicio
      join flow.app_dat_locales l on l.id = ls.id_local
      where t.id = turno_tramo.id_turno
        and l.id_entidad in (select id_entidad from flow.admin_entidades_de_usuario(auth.uid()))
    )
  )
  with check (
    exists (
      select 1 from flow.turno t
      join flow.recurso r on r.id = t.id_recurso
      join flow.local_servicio ls on ls.id = r.id_local_servicio
      join flow.app_dat_locales l on l.id = ls.id_local
      where t.id = turno_tramo.id_turno
        and l.id_entidad in (select id_entidad from flow.admin_entidades_de_usuario(auth.uid()))
    )
  );

-- ---- PLAN_TRAMO (propiedad via su tramo -> recurso) ----------------------
drop policy if exists "plan_tramo_select" on flow.plan_tramo;
drop policy if exists "plan_tramo_write"  on flow.plan_tramo;

create policy "plan_tramo_select" on flow.plan_tramo
  for select to authenticated using (true);

create policy "plan_tramo_write" on flow.plan_tramo
  for all to authenticated
  using (
    exists (
      select 1 from flow.tramo tr
      join flow.recurso r on r.id = tr.id_recurso
      join flow.local_servicio ls on ls.id = r.id_local_servicio
      join flow.app_dat_locales l on l.id = ls.id_local
      where tr.id = plan_tramo.id_tramo
        and l.id_entidad in (select id_entidad from flow.admin_entidades_de_usuario(auth.uid()))
    )
  )
  with check (
    exists (
      select 1 from flow.tramo tr
      join flow.recurso r on r.id = tr.id_recurso
      join flow.local_servicio ls on ls.id = r.id_local_servicio
      join flow.app_dat_locales l on l.id = ls.id_local
      where tr.id = plan_tramo.id_tramo
        and l.id_entidad in (select id_entidad from flow.admin_entidades_de_usuario(auth.uid()))
    )
  );

-- ============================================================================
-- GRANTS (igual que el resto del esquema flow)
-- ============================================================================
grant all on flow.recurso     to authenticated, anon;
grant all on flow.tramo       to authenticated, anon;
grant all on flow.turno       to authenticated, anon;
grant all on flow.turno_tramo to authenticated, anon;
grant all on flow.plan_tramo  to authenticated, anon;
