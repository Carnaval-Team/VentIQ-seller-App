-- ============================================================================
-- RPC CLIENTE: dias con DISPONIBILIDAD para reserva directa de un servicio.
--
-- Devuelve, para un local_servicio, los dias que tienen un plan_servicios con
-- cupo libre (disponibles > 0) dentro de un rango. Pensado para pintar el
-- calendario de "Reservar ahora" con la capacidad libre de cada dia.
--
-- Solo tiene sentido cuando el local_servicio tiene permite_reserva_directa,
-- pero la funcion no lo filtra (la UI decide si ofrece el boton); aun asi, si
-- no esta habilitado, cliente_reservar_directo rechazara la reserva.
--
-- Compara el dia por hora local (America/Havana), igual que el resto del flujo.
-- Rango por defecto: hoy .. hoy + 90 dias.
-- security invoker, stable. Grant a authenticated y anon (catalogo publico).
-- Devuelve: array (vacio [] si no hay dias con cupo).
--   [{ "fecha":"2026-07-03", "cantidad":50, "agendados":12, "disponibles":38 }]
-- ============================================================================

create or replace function flow.cliente_obtener_disponibilidad(
  p_id_local_servicio integer,
  p_desde             date default null,
  p_hasta             date default null
)
returns jsonb
language sql
stable
security invoker
set search_path = flow, public
as $$
  with rango as (
    select coalesce(p_desde, (current_timestamp at time zone 'America/Havana')::date) as d_desde,
           coalesce(p_hasta,
                    (current_timestamp at time zone 'America/Havana')::date + 90)      as d_hasta
  ),
  -- Agrupa por dia local: puede haber mas de un plan el mismo dia.
  por_dia as (
    select (ps.fecha at time zone 'America/Havana')::date as dia,
           sum(ps.cantidad)                                as cantidad,
           sum(ps.agendados)                               as agendados
    from flow.plan_servicios ps, rango r
    where ps.id_local_servicio = p_id_local_servicio
      and ps.cantidad is not null
      and (ps.fecha at time zone 'America/Havana')::date >= r.d_desde
      and (ps.fecha at time zone 'America/Havana')::date <= r.d_hasta
    group by (ps.fecha at time zone 'America/Havana')::date
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'fecha',       to_char(pd.dia, 'YYYY-MM-DD'),
        'cantidad',    pd.cantidad,
        'agendados',   pd.agendados,
        'disponibles', pd.cantidad - pd.agendados
      )
      order by pd.dia
    ),
    '[]'::jsonb
  )
  from por_dia pd
  where pd.cantidad - pd.agendados > 0;
$$;

grant execute on function flow.cliente_obtener_disponibilidad(integer, date, date) to authenticated, anon;

-- Uso:
--   select flow.cliente_obtener_disponibilidad(7);
--   select flow.cliente_obtener_disponibilidad(7, '2026-07-01', '2026-07-31');
