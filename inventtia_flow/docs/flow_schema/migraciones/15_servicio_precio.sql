-- ============================================================================
-- MIGRACION: precios en servicios y reservas (agenda).
--
-- app_dat_servicios.config_precio (jsonb):
--   moneda_default, monedas[], precios_base{}, reglas[{si_clave, precios_opcion{opcion:{moneda:precio}}}]
--
-- agenda.precio_total / agenda.moneda: precio calculado al crear la reserva.
-- ============================================================================

alter table flow.app_dat_servicios
  add column if not exists config_precio jsonb not null default '{}'::jsonb;

alter table flow.agenda
  add column if not exists precio_total numeric,
  add column if not exists moneda varchar(8);

comment on column flow.app_dat_servicios.config_precio is
  'Precio base, monedas habilitadas y reglas por datos adicionales (jsonb).';
comment on column flow.agenda.precio_total is
  'Precio total de la reserva al momento de crearla (unitario x cantidad).';
comment on column flow.agenda.moneda is
  'Código de moneda del precio_total (USD, EUR, CUP, MLC).';

-- ----------------------------------------------------------------------------
-- Helper: calcula precio unitario según config_precio del servicio.
-- ----------------------------------------------------------------------------
create or replace function flow.calcular_precio_reserva(
  p_id_servicio     integer,
  p_datos           jsonb,
  p_moneda          text default null,
  p_cantidad        integer default 1
)
returns table (
  precio_total numeric,
  moneda       varchar,
  precio_unit  numeric
)
language plpgsql
stable
set search_path = flow, public
as $$
declare
  v_cfg       jsonb;
  v_moneda    text;
  v_monedas   text[];
  v_default   text;
  v_unit      numeric := 0;
  v_regla     jsonb;
  v_clave     text;
  v_valor     text;
  v_precios   jsonb;
  v_precios_opc jsonb;
  v_cant      integer;
begin
  v_cant := greatest(coalesce(p_cantidad, 1), 1);

  select coalesce(s.config_precio, '{}'::jsonb)
    into v_cfg
  from flow.app_dat_servicios s
  where s.id = p_id_servicio;

  if v_cfg is null or v_cfg = '{}'::jsonb then
    return query select 0::numeric, coalesce(p_moneda, 'USD')::varchar, 0::numeric;
    return;
  end if;

  v_default := coalesce(v_cfg->>'moneda_default', 'USD');
  select coalesce(array_agg(x::text), array[v_default])
    into v_monedas
  from jsonb_array_elements_text(coalesce(v_cfg->'monedas', jsonb_build_array(v_default))) x;

  v_moneda := coalesce(nullif(trim(p_moneda), ''), v_default);
  if not (v_moneda = any (v_monedas)) then
    v_moneda := v_default;
  end if;

  -- Reglas en orden: primera coincidencia con precio para la opción elegida gana.
  for v_regla in
    select * from jsonb_array_elements(coalesce(v_cfg->'reglas', '[]'::jsonb))
  loop
    v_clave := v_regla->>'si_clave';
    if v_clave is null or v_clave = '' then
      continue;
    end if;
    v_valor := coalesce(p_datos->>v_clave, '');
    if v_valor = '' then
      continue;
    end if;

    v_precios_opc := coalesce(v_regla->'precios_opcion', '{}'::jsonb);

    -- Formato anterior (opciones + precios compartidos): migración en lectura.
    if v_precios_opc = '{}'::jsonb
       and v_regla ? 'opciones'
       and jsonb_typeof(v_regla->'opciones') = 'array'
       and exists (
         select 1 from jsonb_array_elements_text(v_regla->'opciones') o
         where o = v_valor
       ) then
      v_precios := coalesce(v_regla->'precios', '{}'::jsonb);
    else
      v_precios := v_precios_opc->v_valor;
    end if;

    if v_precios is null or v_precios = 'null'::jsonb or v_precios = '{}'::jsonb then
      continue;
    end if;

    v_unit := coalesce(
      nullif(v_precios->>v_moneda, '')::numeric,
      nullif(v_precios->>v_default, '')::numeric,
      0
    );
    return query select (v_unit * v_cant)::numeric, v_moneda::varchar, v_unit::numeric;
    return;
  end loop;

  -- Precio base
  v_precios := coalesce(v_cfg->'precios_base', '{}'::jsonb);
  v_unit := coalesce(
    nullif(v_precios->>v_moneda, '')::numeric,
    nullif(v_precios->>v_default, '')::numeric,
    0
  );
  return query select (v_unit * v_cant)::numeric, v_moneda::varchar, v_unit::numeric;
end;
$$;

grant execute on function flow.calcular_precio_reserva(integer, jsonb, text, integer) to authenticated;
