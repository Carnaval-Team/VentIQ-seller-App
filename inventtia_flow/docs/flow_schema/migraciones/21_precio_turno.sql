-- Precio fijo opcional por turno reservable.
alter table flow.turno
  add column if not exists precios jsonb not null default '{}'::jsonb;

comment on column flow.turno.precios is
  'Precio unitario fijo por moneda. Si está vacío, se aplica la configuración del servicio.';

create or replace function flow.calcular_precio_turno(
  p_id_servicio integer,
  p_id_turno integer,
  p_datos jsonb,
  p_moneda text default null,
  p_cantidad integer default 1
)
returns table (precio_total numeric, moneda varchar, precio_unit numeric)
language plpgsql
stable
set search_path = flow, public
as $$
declare
  v_precios jsonb;
  v_moneda text;
  v_default text;
  v_unit numeric;
  v_cantidad integer := greatest(coalesce(p_cantidad, 1), 1);
begin
  select t.precios, coalesce(s.config_precio->>'moneda_default', 'USD')
    into v_precios, v_default
  from flow.turno t
  join flow.recurso r on r.id = t.id_recurso
  join flow.local_servicio ls on ls.id = r.id_local_servicio
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  where t.id = p_id_turno and s.id = p_id_servicio;

  v_moneda := coalesce(nullif(trim(p_moneda), ''), v_default);
  if coalesce(v_precios, '{}'::jsonb) <> '{}'::jsonb then
    v_unit := coalesce(
      nullif(v_precios->>v_moneda, '')::numeric,
      nullif(v_precios->>v_default, '')::numeric
    );
    if v_unit is not null then
      return query select v_unit * v_cantidad, v_moneda::varchar, v_unit;
      return;
    end if;
  end if;

  return query
  select * from flow.calcular_precio_reserva(
    p_id_servicio, p_datos, v_moneda, v_cantidad
  );
end;
$$;
