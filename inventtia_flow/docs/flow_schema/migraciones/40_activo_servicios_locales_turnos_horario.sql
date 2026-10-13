-- ============================================================================
-- 40_activo_servicios_locales_turnos_horario.sql
-- ============================================================================
-- QUE HACE
--   Añade el estado de publicación (activo) a locales, servicios y pares
--   local-servicio; las horas opcionales del turno; el horario estructurado del
--   local; y el modo de gestión simplificado de recursos/tramos.
--   Añade además `flow._ls_disponible(id)`, el ÚNICO predicado que define si un
--   local-servicio es visible y reservable para el cliente.
--
-- POR QUE UN SOLO PREDICADO
--   La visibilidad del cliente depende de TRES banderas (local, servicio y par).
--   Si cada RPC repitiera el AND a mano, tarde o temprano uno lo olvidaría y el
--   feed diría "visible" donde la reserva dice "no disponible". Igual que
--   `_ls_tiene_recursos`, la regla vive en una función y se compone.
--
-- POR QUE `default true` Y `coalesce(..., false)`
--   `default true` garantiza que NINGÚN dato existente cambia de visibilidad al
--   migrar. `coalesce(..., false)` protege de inserciones con NULL hechas por
--   `service_role` o scripts, donde el DEFAULT no aplica.
--
-- SEGURIDAD (cambio deliberado, autorizado por el usuario)
--   `flow.local_servicio` tenía la política "update ls" con roles {public} y
--   qual/with_check = true: cualquiera con la anon key podía UPDATE cualquier
--   fila (incluido `activo`, que ahora gobierna todo el catálogo). Se elimina.
--   Los escritores reales del repo usan las políticas *_admin para
--   `authenticated`, que se mantienen.
--
-- MODOS DE GESTIÓN (punto 6 del plan)
--   · sin_tramos  = true  → la UI oculta Tramos; cada turno recibe un tramo
--                           oculto propio (cupo independiente por turno).
--   · solo_turnos = true  → la UI oculta Recursos y Tramos; si el local_servicio
--                           no tiene ningún recurso se crea uno oculto "Cupo".
--                           Con más de un recurso el modo se rechaza (no se
--                           mueven turnos entre recursos: eso dejaría
--                           `turno_tramo` apuntando a tramos de otro recurso).
--   `solo_turnos` implica `sin_tramos` (CHECK).
--
-- REVERSIBILIDAD
--   alter table flow.app_dat_locales   drop column if exists activo, horario_detalle;
--   alter table flow.app_dat_servicios drop column if exists activo;
--   alter table flow.local_servicio    drop column if exists activo;
--   alter table flow.local_servicio    drop column if exists solo_turnos;
--   alter table flow.local_servicio    drop column if exists sin_tramos;
--   alter table flow.turno             drop column if exists hora_inicio, hora_fin;
--   drop function if exists flow._ls_disponible(integer);
--   (la política "update ls" NO se recrea: su ausencia es el arreglo)
--
-- ORDEN: antes de 41 y 42.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Banderas de publicación
-- ---------------------------------------------------------------------------
alter table flow.app_dat_locales
  add column if not exists activo boolean not null default true;

alter table flow.app_dat_servicios
  add column if not exists activo boolean not null default true;

alter table flow.local_servicio
  add column if not exists activo boolean not null default true;

comment on column flow.app_dat_locales.activo is
  'Si false, el local y TODOS sus servicios dejan de mostrarse y de poder reservarse (clientes).';
comment on column flow.app_dat_servicios.activo is
  'Si false, el servicio deja de mostrarse y de poder reservarse en TODOS los locales.';
comment on column flow.local_servicio.activo is
  'Si false, esa combinación local-servicio desaparece del catálogo y no admite reservas.';

-- ---------------------------------------------------------------------------
-- 2. Horario de atención estructurado (punto 10 del plan)
-- ---------------------------------------------------------------------------
-- `horario_atencion` (text) sigue siendo la fuente legible y el respaldo del
-- parser. `horario_detalle` SOLO se escribe cuando el admin usa el constructor
-- de días + hora apertura/cierre, y en ese caso manda:
--   { "dias": [1,2,3,4,5], "apertura": "08:00", "cierre": "17:00" }
--   días ISO 1=lunes … 7=domingo, como en el resto de `flow`.
-- Si el admin usa texto libre, queda NULL y se interpreta con el parser viejo.
-- Nunca los dos: sin dos fuentes de verdad que puedan divergir.
alter table flow.app_dat_locales
  add column if not exists horario_detalle jsonb;

comment on column flow.app_dat_locales.horario_detalle is
  'Horario estructurado: {"dias":[1..7],"apertura":"HH:MM","cierre":"HH:MM"}. NULL = usar el parser de texto libre sobre horario_atencion.';

alter table flow.app_dat_locales
  drop constraint if exists locales_horario_detalle_chk;
alter table flow.app_dat_locales
  add constraint locales_horario_detalle_chk check (
    horario_detalle is null
    or (
      jsonb_typeof(horario_detalle) = 'object'
      and jsonb_typeof(horario_detalle -> 'dias') = 'array'
      and jsonb_array_length(horario_detalle -> 'dias') between 1 and 7
      and (horario_detalle ->> 'apertura') ~ '^[0-2][0-9]:[0-5][0-9]$'
      and (horario_detalle ->> 'cierre')   ~ '^[0-2][0-9]:[0-5][0-9]$'
    )
  );

-- ---------------------------------------------------------------------------
-- 3. Modo de gestión de recursos/tramos
-- ---------------------------------------------------------------------------
alter table flow.local_servicio
  add column if not exists solo_turnos boolean not null default false;
alter table flow.local_servicio
  add column if not exists sin_tramos  boolean not null default false;

comment on column flow.local_servicio.solo_turnos is
  'UI simplificada: no se muestran recursos ni tramos; el sistema gestiona un recurso oculto "Cupo" y un tramo por turno.';
comment on column flow.local_servicio.sin_tramos is
  'UI: se ocultan los tramos. Mantiene los recursos. Cada turno recibe un tramo oculto propio.';

alter table flow.local_servicio
  drop constraint if exists local_servicio_modo_chk;
alter table flow.local_servicio
  add constraint local_servicio_modo_chk check (not solo_turnos or sin_tramos);

-- ---------------------------------------------------------------------------
-- 4. Horas opcionales del turno (punto 7 del plan)
-- ---------------------------------------------------------------------------
alter table flow.turno add column if not exists hora_inicio time;
alter table flow.turno add column if not exists hora_fin    time;

comment on column flow.turno.hora_inicio is
  'Hora de inicio del turno (opcional, solo presentación: no altera cupo ni reserva).';

alter table flow.turno
  drop constraint if exists turno_horas_chk;
alter table flow.turno
  add constraint turno_horas_chk check (
    hora_inicio is null or hora_fin is null or hora_fin > hora_inicio
  );

-- ---------------------------------------------------------------------------
-- 5. SEGURIDAD: quitar el UPDATE abierto a `public` sobre local_servicio
-- ---------------------------------------------------------------------------
-- Ver cabecera. Las políticas `local_servicio_*_admin` (authenticated) siguen
-- cubriendo todos los escritores reales.
drop policy if exists "update ls" on flow.local_servicio;

-- ---------------------------------------------------------------------------
-- 6. Visibilidad efectiva de un local-servicio para el cliente
-- ---------------------------------------------------------------------------
create or replace function flow._ls_disponible(p_id_local_servicio integer)
returns boolean
language sql
stable
set search_path to 'flow', 'public'
as $function$
  select coalesce(l.activo, false)
     and coalesce(s.activo, false)
     and coalesce(ls.activo, false)
  from flow.local_servicio ls
  join flow.app_dat_locales   l on l.id = ls.id_local
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  where ls.id = p_id_local_servicio;
$function$;

comment on function flow._ls_disponible(integer) is
  'UNICA definicion de "este local-servicio es visible y reservable para el cliente".';

-- ---------------------------------------------------------------------------
-- 7. ¿El llamador actual es admin de la entidad dueña del local-servicio?
-- ---------------------------------------------------------------------------
-- Lo usan los guards de lectura y los triggers de reserva para NO bloquear al
-- admin de la entidad: el cliente no ve nada, pero el admin sigue pudiendo
-- consultar disponibilidad y crear reservas manuales (mostrador).
create or replace function flow._caller_es_admin_de_ls(p_id_local_servicio integer)
returns boolean
language sql
stable
set search_path to 'flow', 'public'
as $function$
  select exists (
    select 1
    from flow.local_servicio ls
    join flow.app_dat_locales l on l.id = ls.id_local
    where ls.id = p_id_local_servicio
      and flow.is_entidad_admin(l.id_entidad)
  );
$function$;

-- ---------------------------------------------------------------------------
-- 8. Verificación posterior (ejecutar a mano)
-- ---------------------------------------------------------------------------
-- 8.a Ningún dato cambió de visibilidad: los 3 valores deben ser iguales.
-- select (select count(*) from flow.app_dat_locales)   as locales,
--        (select count(*) from flow.app_dat_servicios) as servicios,
--        (select count(*) from flow.local_servicio)    as local_servicio;
-- select count(*) from flow.app_dat_locales   where activo;   -- esperado: mismos que arriba
-- select count(*) from flow.app_dat_servicios where activo;
-- select count(*) from flow.local_servicio    where activo;
--
-- 8.b La política anónima desapareció: esperado 0 filas.
-- select policyname from pg_policies
--  where schemaname = 'flow' and tablename = 'local_servicio'
--    and cmd = 'UPDATE' and 'public' = any(roles);
--
-- 8.c El predicado responde: esperado true/false, nunca NULL.
-- select flow._ls_disponible(id) from flow.local_servicio limit 5;
-- ============================================================================