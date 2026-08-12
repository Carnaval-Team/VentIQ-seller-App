create table if not exists flow.nom_tipo_actividad_servicio (
  id integer generated always as identity primary key,
  codigo varchar(64) not null unique,
  nombre varchar(120) not null,
  activo boolean not null default true
);

insert into flow.nom_tipo_actividad_servicio (codigo, nombre)
values
  ('general', 'General'),
  ('transporte_omnibus', 'Transporte en ómnibus')
on conflict (codigo) do update set nombre = excluded.nombre;

alter table flow.app_dat_servicios
  add column if not exists id_tipo_actividad integer;

update flow.app_dat_servicios
set id_tipo_actividad = (
  select id from flow.nom_tipo_actividad_servicio where codigo = 'general'
)
where id_tipo_actividad is null;

alter table flow.app_dat_servicios
  alter column id_tipo_actividad set not null;

alter table flow.app_dat_servicios
  drop constraint if exists app_dat_servicios_id_tipo_actividad_fkey;

alter table flow.app_dat_servicios
  add constraint app_dat_servicios_id_tipo_actividad_fkey
  foreign key (id_tipo_actividad)
  references flow.nom_tipo_actividad_servicio(id);

alter table flow.tramo
  add column if not exists tipo_trayecto varchar(16);

alter table flow.tramo
  drop constraint if exists tramo_tipo_trayecto_check;

alter table flow.tramo
  add constraint tramo_tipo_trayecto_check
  check (tipo_trayecto is null or tipo_trayecto in ('ida', 'vuelta'));

alter table flow.agenda
  add column if not exists id_viaje uuid,
  add column if not exists tipo_trayecto varchar(16);

alter table flow.agenda
  drop constraint if exists agenda_tipo_trayecto_check;

alter table flow.agenda
  add constraint agenda_tipo_trayecto_check
  check (tipo_trayecto is null or tipo_trayecto in ('ida', 'vuelta'));

create index if not exists idx_agenda_id_viaje
  on flow.agenda (id_viaje)
  where id_viaje is not null;

create unique index if not exists uq_plan_tramo_fecha
  on flow.plan_tramo (id_tramo, fecha);

alter table flow.plan_tramo
  drop constraint if exists plan_tramo_cantidad_check,
  drop constraint if exists plan_tramo_agendados_check;

alter table flow.plan_tramo
  add constraint plan_tramo_cantidad_check check (cantidad >= 0),
  add constraint plan_tramo_agendados_check check (agendados >= 0 and agendados <= cantidad);

create or replace function flow.admin_guardar_tramo_transporte(
  p_uuid_usuario uuid,
  p_id_recurso integer,
  p_nombre text,
  p_tipo_trayecto varchar,
  p_id integer default null,
  p_activo boolean default true
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = flow, public
as $$
declare
  v_id integer;
begin
  if p_tipo_trayecto not in ('ida', 'vuelta') then
    return jsonb_build_object('ok', false, 'error', 'Tipo de trayecto inválido');
  end if;
  if p_id is null then
    if not flow._admin_puede_recurso(p_uuid_usuario, p_id_recurso) then
      return jsonb_build_object('ok', false, 'error', 'Recurso inexistente o sin permiso');
    end if;
    insert into flow.tramo (id_recurso, nombre, tipo_trayecto, activo)
    values (p_id_recurso, p_nombre, p_tipo_trayecto, p_activo)
    returning id into v_id;
  else
    if not exists (
      select 1 from flow.tramo tr
      where tr.id = p_id
        and tr.id_recurso = p_id_recurso
        and flow._admin_puede_recurso(p_uuid_usuario, tr.id_recurso)
    ) then
      return jsonb_build_object('ok', false, 'error', 'Tramo inexistente o sin permiso');
    end if;
    update flow.tramo
       set nombre = p_nombre,
           tipo_trayecto = p_tipo_trayecto,
           activo = p_activo,
           updated_at = now()
     where id = p_id
     returning id into v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

grant execute on function flow.admin_guardar_tramo_transporte(uuid, integer, text, varchar, integer, boolean) to authenticated;
grant select on flow.nom_tipo_actividad_servicio to authenticated, anon;
