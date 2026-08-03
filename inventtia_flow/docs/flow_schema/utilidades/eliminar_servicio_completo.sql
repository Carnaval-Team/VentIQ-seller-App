-- ============================================================================
-- ELIMINAR UN SERVICIO (flow.app_dat_servicios) CON TODAS SUS RELACIONES
--
-- Uso:
--   1) Reemplaza :id_servicio por el id numérico del servicio.
--   2) Ejecuta primero el SELECT de inspección.
--   3) Si todo cuadra, ejecuta el bloque DELETE dentro de una transacción.
--
-- Notas:
--   - local_servicio tiene ON DELETE CASCADE desde app_dat_servicios.
--   - Muchas hijas de local_servicio también son CASCADE (agenda, sala_espera,
--     recurso→tramo/turno/plan_tramo, plan_config, ultimo_numero).
--   - plan_servicios NO tiene ON DELETE CASCADE (solo UPDATE CASCADE) → hay
--     que borrarlo a mano antes.
--   - agenda.id_turno / sala_espera.id_turno no son CASCADE al borrar turno;
--     al borrar local_servicio primero (CASCADE) se van las agendas, o se
--     anulan id_turno antes de tocar turnos.
--   - bot_log / sala_espera_fraude pueden tener id_local_servicio sin FK.
-- ============================================================================

-- ── 0) Inspección (seguro, no borra) ──────────────────────────────────────
-- Reemplaza 123 por el id del servicio.
-- select s.id, s.nombre, s.descripcion, s.id_entidad, s.id_tipo_actividad
-- from flow.app_dat_servicios s
-- where s.id = 123;

-- select ls.id as id_local_servicio, l.nombre as local
-- from flow.local_servicio ls
-- join flow.app_dat_locales l on l.id = ls.id_local
-- where ls.id_servicio = 123;

-- select
--   (select count(*) from flow.agenda a
--      join flow.local_servicio ls on ls.id = a.id_local_servicio
--     where ls.id_servicio = 123) as agendas,
--   (select count(*) from flow.plan_servicios ps
--      join flow.local_servicio ls on ls.id = ps.id_local_servicio
--     where ls.id_servicio = 123) as plan_servicios,
--   (select count(*) from flow.recurso r
--      join flow.local_servicio ls on ls.id = r.id_local_servicio
--     where ls.id_servicio = 123) as recursos,
--   (select count(*) from flow.sala_espera se
--      join flow.local_servicio ls on ls.id = se.id_local_servicio
--     where ls.id_servicio = 123) as sala_espera;

-- ── 1) Borrado completo ───────────────────────────────────────────────
begin;

-- Parámetro: cambia este valor
-- \set id_servicio 123
do $$
declare
  v_id_servicio integer := 0; -- <<< PON AQUÍ EL ID DEL SERVICIO
  v_ls integer[];
begin
  if v_id_servicio is null or v_id_servicio <= 0 then
    raise exception 'Define v_id_servicio con el id del servicio a eliminar';
  end if;

  if not exists (
    select 1 from flow.app_dat_servicios s where s.id = v_id_servicio
  ) then
    raise exception 'No existe flow.app_dat_servicios.id = %', v_id_servicio;
  end if;

  select coalesce(array_agg(ls.id), '{}'::integer[])
    into v_ls
  from flow.local_servicio ls
  where ls.id_servicio = v_id_servicio;

  -- Tablas sin CASCADE / sin FK limpia
  delete from flow.plan_servicios
  where id_local_servicio = any (v_ls);

  delete from flow.bot_log
  where id_local_servicio = any (v_ls);

  delete from flow.sala_espera_fraude
  where id_local_servicio = any (v_ls);

  -- Evitar bloqueo si quedan referencias a turno antes del cascade de recurso
  update flow.agenda
     set id_turno = null
   where id_local_servicio = any (v_ls);

  update flow.sala_espera
     set id_turno = null
   where id_local_servicio = any (v_ls);

  -- Notificaciones: FK SET NULL, pero limpiamos referencias del servicio
  update flow.notificaciones
     set id_local_servicio = null
   where id_local_servicio = any (v_ls);

  -- Borra el servicio → CASCADE a local_servicio → agenda, sala_espera,
  -- ultimo_numero, plan_config, recurso (y tramo/turno/turno_tramo/plan_tramo).
  delete from flow.app_dat_servicios
  where id = v_id_servicio;

  raise notice 'Servicio % eliminado (local_servicio ids: %)',
    v_id_servicio, v_ls;
end $$;

commit;

-- Si algo falla: rollback;
