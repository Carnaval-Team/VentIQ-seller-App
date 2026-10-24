-- ============================================================================
-- MIGRACION 59: reservas completadas SIN resena (para pedirla desde la app)
--
-- QUE RESUELVE
--   `resenas_de_servicio(p_id_local_servicio)` ya dice, **para un servicio
--   concreto**, si el usuario tiene una reserva completada sin resenar
--   (`agenda_resenable`). Lo que no existe es la pregunta al reves: «¿de que
--   servicios me falta opinar?», que es lo que necesita el Home para pedir la
--   resena en cuanto el cliente entra, sin abrir el detalle de cada servicio.
--
--   Hacerlo desde el cliente serian N+1 peticiones (una por servicio) y no hay
--   ninguna lectura del cliente que liste sus resenas. Esta funcion lo resuelve
--   en una sola llamada.
--
-- QUE DEVUELVE
--   { "ok": true, "data": [ {id_agenda, id_local_servicio, atendido, servicio,
--                            servicio_foto, categoria, local} ] }
--   ordenado por `atendido` descendente (lo ultimo primero) y como maximo
--   `p_limite` (1..10, 3 por defecto).
--
-- REGLAS (las mismas que `publicar_resena`, que es quien acaba validando)
--   * La reserva es del usuario: `uuid_usuario = auth.uid()` o
--     `reservado_por = auth.uid()` (una reserva para un tercero cuenta para
--     quien la hizo).
--   * La reserva esta **Completado**: no se pide resena de lo que aun no te
--     atendieron.
--   * No tiene resena todavia (`flow.resena.id_agenda`).
--
-- POR QUE `security definer`
--   Igual que `resenas_de_servicio`: sin definir, el filtro de propiedad se
--   apoyaria en RLS y una reserva hecha `para un tercero` (uuid_usuario =
--   tercero, reservado_por = yo) quedaria fuera. El filtro explicito esta en el
--   WHERE y la sesion se comprueba de entrada.
--
-- REVERSION
--   drop function if exists flow.cliente_resenas_pendientes(integer);
-- ============================================================================

create or replace function flow.cliente_resenas_pendientes(
  p_limite integer default 3
)
returns jsonb
language plpgsql
stable
security definer
set search_path = flow, public
as $function$
declare
  v_limite integer;
  v_data   jsonb;
begin
  -- Definir salta RLS: la autorizacion se hace aqui.
  if coalesce(auth.role(), 'anon') <> 'authenticated' then
    return jsonb_build_object('ok', false, 'error', 'Sesion no valida');
  end if;

  v_limite := greatest(1, least(coalesce(p_limite, 3), 10));

  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id_agenda',         p.id_agenda,
             'id_local_servicio', p.id_local_servicio,
             'atendido',          p.atendido,
             'servicio',          p.servicio,
             'servicio_foto',     p.servicio_foto,
             'categoria',         p.categoria,
             'local',             p.local
           )
           order by p.atendido desc
         ), '[]'::jsonb)
    into v_data
    from (
      select
        a.id                        as id_agenda,
        a.id_local_servicio,
        coalesce(a.fecha_hora_atencion, a.fecha_hora_reserva) as atendido,
        s.nombre                    as servicio,
        s.foto                      as servicio_foto,
        -- La categoria de la HOJA es la subcategoria; para el rotulo sirve
        -- cualquiera de las dos, y si no hay nomenclador queda NULL (el cliente
        -- no pinta el chip y ya).
        coalesce(
          nullif(btrim(ta.nombre), ''),
          replace(coalesce(ta.codigo, ''), '_', ' ')
        )                           as categoria,
        l.nombre                    as local
      from flow.agenda a
      join flow.nom_estado_agenda e on e.id = a.id_estado
      join flow.local_servicio ls on ls.id = a.id_local_servicio
      join flow.app_dat_servicios s on s.id = ls.id_servicio
      join flow.app_dat_locales l on l.id = ls.id_local
      left join flow.nom_tipo_actividad_servicio ta on ta.id = s.id_tipo_actividad
      where e.nombre = 'Completado'
        and (a.uuid_usuario = auth.uid() or a.reservado_por = auth.uid())
        and not exists (
          select 1 from flow.resena r where r.id_agenda = a.id
        )
      order by atendido desc
      limit v_limite
    ) p;

  return jsonb_build_object('ok', true, 'data', v_data);
end;
$function$;

revoke all on function flow.cliente_resenas_pendientes(integer) from public, anon;
grant execute on function flow.cliente_resenas_pendientes(integer)
  to authenticated, service_role;

notify pgrst, 'reload schema';


-- ============================================================================
-- VERIFICACION (ejecutar despues de aplicar)
--
--   -- Cuantas reservas completadas sin resena tiene el usuario de la sesion:
--   select jsonb_array_length(flow.cliente_resenas_pendientes(10) -> 'data');
--
--   -- Que no se cuele nada ya resenado ni sin completar:
--   select count(*) as no_deberia_haber
--   from jsonb_array_elements(flow.cliente_resenas_pendientes(10) -> 'data') d
--   join flow.resena r on r.id_agenda = (d ->> 'id_agenda')::int;   -- 0
-- ============================================================================
