-- ============================================================================
-- MIGRACION 17: Fix _descontar_tramos_turno -> "DELETE requires a WHERE clause"
--
-- Sintoma: al crear una reserva CON turno (servicios con recursos), las RPC
--   flow.admin_crear_reserva_directa y flow.cliente_reservar_directo devolvian
--     { "ok": false, "error": "DELETE requires a WHERE clause", "sqlstate": "21000" }
--
-- Causa: la version previa de flow._descontar_tramos_turno usaba una tabla
--   temporal (_tmp_pt) y ejecutaba `delete from _tmp_pt;` SIN clausula WHERE.
--   Con sql_safe_updates activo (default en el pooler de Supabase), Postgres
--   rechaza cualquier DELETE/UPDATE sin WHERE -> sqlstate 21000. Solo afectaba
--   al camino "con turno"; la reserva sin recursos (plan_servicios) funcionaba.
--
-- Fix: se elimina por completo la tabla temporal. Se bloquean los plan_tramo
--   del turno para la fecha con un CTE `for update of pt` (mismo comportamiento
--   FIFO-safe contra el bot), se valida cupo y se descuenta con un UPDATE que ya
--   lleva su WHERE. Misma firma y misma semantica; sin el DELETE problematico.
--
-- Idempotente: CREATE OR REPLACE. No altera datos.
-- ============================================================================

create or replace function flow._descontar_tramos_turno(
  p_id_turno integer, p_fecha date, p_cant integer)
returns jsonb
language plpgsql
set search_path to 'flow', 'public'
as $function$
declare
  v_n_tramos integer;
  v_n_plan   integer;
  v_min_disp integer;
begin
  -- Cuantos tramos consume el turno.
  select count(*) into v_n_tramos
  from flow.turno_tramo tt where tt.id_turno = p_id_turno;

  if coalesce(v_n_tramos, 0) = 0 then
    return jsonb_build_object('ok', false, 'error', 'El turno no tiene tramos configurados');
  end if;

  -- Bloquea los plan_tramo del turno para ese dia (FIFO-safe contra el bot)
  -- y calcula cuantos hay y el minimo disponible, en una sola pasada.
  with bloqueados as (
    select pt.id, (pt.cantidad - pt.agendados) as disp
    from flow.turno_tramo tt
    join flow.tramo tr      on tr.id = tt.id_tramo and tr.activo
    join flow.plan_tramo pt on pt.id_tramo = tr.id
    where tt.id_turno = p_id_turno
      and (pt.fecha at time zone 'America/Havana')::date = p_fecha
    for update of pt
  )
  select count(*), min(disp) into v_n_plan, v_min_disp from bloqueados;

  -- Todos los tramos del turno deben tener plan ese dia.
  if coalesce(v_n_plan, 0) < v_n_tramos then
    return jsonb_build_object('ok', false, 'error', 'El turno no esta disponible esa fecha');
  end if;

  if v_min_disp < p_cant then
    return jsonb_build_object('ok', false,
      'error', 'No hay cupo suficiente (quedan ' || greatest(v_min_disp, 0) || ')');
  end if;

  -- Descontar en todos los tramos del turno.
  update flow.plan_tramo pt
     set agendados = pt.agendados + p_cant
  from flow.turno_tramo tt
  join flow.tramo tr on tr.id = tt.id_tramo and tr.activo
  where tt.id_turno = p_id_turno
    and pt.id_tramo = tr.id
    and (pt.fecha at time zone 'America/Havana')::date = p_fecha;

  return jsonb_build_object('ok', true, 'disponibles', v_min_disp);
end;
$function$;
