-- ============================================================================
-- 52. Turno nuevo en el recurso elegido (modo "sin tramos" con varios recursos)
-- ============================================================================
-- PROBLEMA QUE CORRIGE
--   `flow.admin_guardar_turno_auto` resolvía el recurso destino así:
--
--       select r.id into v_recurso
--       from flow.recurso r
--       where r.id_local_servicio = p_id_local_servicio
--       order by r.orden, r.id
--       limit 1;
--
--   Es decir: **siempre el primero del local_servicio**. En el modo "no uso
--   tramos" los recursos siguen visibles y cada tarjeta tiene su botón
--   "Agregar turno", pero el turno se creaba siempre en el mismo recurso,
--   eligiera el admin el que eligiera (visible para el usuario como "me añade
--   los turnos al mismo recurso no importa cuál seleccione").
--
-- CAMBIO
--   Nuevo parámetro `p_id_recurso` (último, con default null):
--     * `p_id_recurso` informado y el turno es NUEVO → se usa ese recurso, que
--       debe pertenecer al local_servicio y estar bajo el permiso del admin.
--     * `p_id_recurso` null → comportamiento anterior (el primero del
--       local_servicio o, si no hay ninguno, el recurso oculto 'Cupo'): es el
--       caso del modo "solo configurar turnos", donde el admin no elige recurso.
--     * Al EDITAR un turno (`p_id` informado) `p_id_recurso` se ignora: el
--       recurso sale del propio turno, como antes.
--
--   El resto (tramo propio del turno, enlace turno_tramo, renombrado del tramo
--   cuando el local_servicio es `sin_tramos`) queda idéntico: sólo cambia de
--   qué recurso cuelga el turno nuevo.
--
--   Es ADITIVA respecto al cliente: si el admin no manda `p_id_recurso` (o usa
--   una versión anterior de la app) todo sigue funcionando igual.
--
-- REVERSIÓN (volver atrás): pegar de nuevo la sección 3 de
--   `41_rpc_admin_dashboard_modo_y_horas.sql` (recrea la firma de 9 args sin
--   `p_id_recurso`). Antes hay que borrar la de 10:
--     drop function if exists flow.admin_guardar_turno_auto(
--       uuid, integer, text, integer, boolean, jsonb, time, time, integer, integer
--     );
--   Con eso la app vuelve al comportamiento anterior (el turno nuevo caía en el
--   primer recurso del local_servicio). No hay datos que revertir.
--
-- APLICAR A MANO en el SQL Editor de Supabase, después de la 50 y la 51.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- COMPROBACIÓN PREVIA: aborta con un mensaje claro si falta lo que reemplaza.
-- (Acepta la firma de 9 o la de 10 args para poder re-ejecutar la migración.)
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'flow'
      and p.proname = 'admin_guardar_turno_auto'
      and p.pronargs in (9, 10)
  ) then
    raise exception 'Falta flow.admin_guardar_turno_auto: aplica antes la migracion 41.';
  end if;

  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'flow' and p.proname = '_admin_puede_recurso'
  ) then
    raise exception 'Falta flow._admin_puede_recurso: aplica antes las migraciones 16 y 24 (recursos + permisos admin).';
  end if;
end $$;

-- La firma vieja (9 args) se elimina para no dejar dos sobrecargas de la misma
-- RPC: PostgREST no sabría cuál resolver al llamarla por parámetros con nombre.
drop function if exists flow.admin_guardar_turno_auto(
  uuid, integer, text, integer, boolean, jsonb, time, time, integer
);

-- Re-ejecutable: si ya se aplicó la 52, esta línea no hace nada.
drop function if exists flow.admin_guardar_turno_auto(
  uuid, integer, text, integer, boolean, jsonb, time, time, integer, integer
);

create or replace function flow.admin_guardar_turno_auto(
  p_uuid_usuario uuid,
  p_id_local_servicio integer,
  p_nombre text,
  p_orden integer default 0,
  p_activo boolean default true,
  p_precios jsonb default '{}'::jsonb,
  p_hora_inicio time default null,
  p_hora_fin time default null,
  p_id integer default null,
  p_id_recurso integer default null
)
returns jsonb
language plpgsql
set search_path to 'flow', 'public'
as $function$
declare
  v_recurso integer;
  v_turno   integer;
  v_tramo   integer;
begin
  if not flow._admin_puede_local_servicio(p_uuid_usuario, p_id_local_servicio) then
    return jsonb_build_object('ok', false, 'error', 'local_servicio inexistente o sin permiso');
  end if;

  if coalesce(btrim(p_nombre), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'el nombre del turno es obligatorio');
  end if;

  if p_id is null then
    if p_id_recurso is not null then
      -- Recurso elegido por el admin: tiene que ser de este local_servicio y
      -- estar bajo su permiso. Si no, se falla en vez de colocar el turno en
      -- otro recurso por sorpresa.
      select r.id into v_recurso
      from flow.recurso r
      where r.id = p_id_recurso
        and r.id_local_servicio = p_id_local_servicio
        and flow._admin_puede_recurso(p_uuid_usuario, r.id);

      if v_recurso is null then
        return jsonb_build_object('ok', false, 'error', 'recurso inexistente o sin permiso');
      end if;
    else
      -- Sin recurso indicado: el único del local_servicio; si no hay, uno oculto.
      select r.id into v_recurso
      from flow.recurso r
      where r.id_local_servicio = p_id_local_servicio
      order by r.orden, r.id
      limit 1;

      if v_recurso is null then
        insert into flow.recurso (id_local_servicio, nombre, capacidad, orden, activo)
        select p_id_local_servicio,
               'Cupo',
               greatest(coalesce(ls.cantidad_max_capacidad, 1), 1),
               0,
               true
        from flow.local_servicio ls
        where ls.id = p_id_local_servicio
        returning id into v_recurso;
      end if;
    end if;

    insert into flow.turno (id_recurso, nombre, orden, activo, precios, hora_inicio, hora_fin)
    values (
      v_recurso, btrim(p_nombre), coalesce(p_orden, 0), coalesce(p_activo, true),
      coalesce(p_precios, '{}'::jsonb), p_hora_inicio, p_hora_fin
    )
    returning id into v_turno;
  else
    -- Edición: el recurso es el del propio turno; p_id_recurso se ignora.
    select t.id_recurso into v_recurso
    from flow.turno t
    where t.id = p_id
      and flow._admin_puede_recurso(p_uuid_usuario, t.id_recurso);

    if v_recurso is null then
      return jsonb_build_object('ok', false, 'error', 'turno inexistente o sin permiso');
    end if;

    update flow.turno
       set nombre      = btrim(p_nombre),
           orden       = coalesce(p_orden, orden),
           activo      = coalesce(p_activo, activo),
           precios     = coalesce(p_precios, '{}'::jsonb),
           hora_inicio = p_hora_inicio,
           hora_fin    = p_hora_fin,
           updated_at  = now()
     where id = p_id
    returning id into v_turno;
  end if;

  -- Tramo propio del turno, sólo si aún no tiene ninguno.
  insert into flow.tramo (id_recurso, nombre, capacidad, orden, activo)
  select v_recurso, btrim(p_nombre), null, coalesce(p_orden, 0), true
  where not exists (
    select 1 from flow.turno_tramo tt where tt.id_turno = v_turno
  )
  returning id into v_tramo;

  if v_tramo is not null then
    insert into flow.turno_tramo (id_turno, id_tramo)
    values (v_turno, v_tramo)
    on conflict do nothing;
  end if;

  -- En modo simplificado los tramos son invisibles: se renombran con el turno
  -- para que la BD se lea sola si alguien la inspecciona a mano.
  if exists (
    select 1
    from flow.local_servicio ls
    join flow.recurso r      on r.id_local_servicio = ls.id
    join flow.turno_tramo tt on tt.id_turno = v_turno
    join flow.tramo tr       on tr.id = tt.id_tramo
    where ls.id = p_id_local_servicio and ls.sin_tramos
  ) then
    update flow.tramo tr
       set nombre = btrim(p_nombre), updated_at = now()
     where tr.id in (
       select tt.id_tramo from flow.turno_tramo tt where tt.id_turno = v_turno
     );
  end if;

  return jsonb_build_object(
    'ok', true,
    'id', v_turno,
    'id_recurso', v_recurso,
    'id_tramo', v_tramo
  );
end;
$function$;

grant execute on function flow.admin_guardar_turno_auto(
  uuid, integer, text, integer, boolean, jsonb, time, time, integer, integer
) to authenticated;

-- ---------------------------------------------------------------------------
-- VERIFICACIÓN (pegar junto y comprobar la salida)
-- ---------------------------------------------------------------------------
-- a) Debe haber UNA sola `admin_guardar_turno_auto` (10 args) y ninguna de 9.
select p.proname, pg_get_function_arguments(p.oid) as argumentos
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'flow' and p.proname = 'admin_guardar_turno_auto';

-- b) El cuerpo nuevo referencia p_id_recurso (esperado: true).
select position('p_id_recurso' in pg_get_functiondef(p.oid)) > 0 as tiene_id_recurso
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'flow' and p.proname = 'admin_guardar_turno_auto';

-- c) Prueba manual (opcional): crea un turno en un recurso concreto y comprueba
--    el recurso devuelto. Sustituye los ids por los de tu local_servicio.
-- select flow.admin_guardar_turno_auto(
--   '<uuid-admin>', 1, 'Turno de prueba', 0, true, '{}'::jsonb, null, null, null, 2
-- );
-- Esperado: {"ok": true, "id": N, "id_recurso": 2, "id_tramo": M}
-- Después borra el turno de prueba desde la app (o con
-- select flow.admin_eliminar_turno('<uuid-admin>', N);).