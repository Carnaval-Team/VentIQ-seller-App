-- ============================================================================
-- MIGRACION 51: precio del turno + reglas de datos adicionales (F6).
--
-- BUG QUE ARREGLA
--   `flow.calcular_precio_turno` (21_precio_turno.sql:36-45) devolvia el precio
--   del turno y NUNCA miraba `p_datos`: en un servicio con turno de precio fijo
--   las reglas de `config_precio` por dato adicional no se cobraban jamas.
--   Ademas, una regla sin precio para la moneda elegida devolvia 0 en vez del
--   precio base (15_servicio_precio.sql:109-113).
--
-- DISENO (decision D5 del plan)
--   La aritmetica se extrae al helper `flow.calcular_precio_con_reglas`, que
--   comparten las DOS funciones publicas:
--     1. BASE: el precio propio del turno si viene `p_base_unit` (`origen`
--        'turno'); si no, `config_precio->precios_base` de la moneda elegida y,
--        como respaldo, de la moneda por defecto.
--     2. REGLAS en orden: gana la PRIMERA coincidente cuyo precio sea
--        resoluble en la moneda elegida (o en la moneda por defecto); si una
--        regla coincide pero no tiene precio, se IGNORA y se sigue buscando.
--        Nunca se devuelve 0 por "la regla no tiene precio en esa moneda".
--   - `calcular_precio_reserva` conserva EXACTAMENTE su firma y sus 3 columnas
--     (y el caso `config_precio = '{}'` -> 0), delegando con `p_base_unit null`.
--   - `calcular_precio_turno` conserva firma y 3 columnas, resuelve el precio
--     unitario del turno (con respaldo a la moneda por defecto) y lo pasa como
--     `p_base_unit`, de modo que las reglas por dato adicional SI se evaluan
--     sobre el precio del turno.
--
-- ORDEN: el helper primero (lo llaman las otras dos). `create or replace` no
-- cambia tipos de retorno, asi que las firmas publicas siguen intactas
-- (`cotizar_reserva`, los RPC de omnibus, los bots y `agenda_admin_service.dart`
-- siguen llamandolas igual).
--
-- SEGURIDAD: las tres se recrean **invoker** (sin `security definer`) con
-- `search_path = flow, public` fijo, exactamente como las definia 15/21. OJO:
-- `create or replace` reescribe tambien `prosecdef`, asi que conviene comparar
-- la definicion VIVA antes de aplicar (el plan §3 ya lo avisa); hay una
-- consulta para ello en el bloque de comprobacion del final.
--
-- NOTA: lo aplica el usuario a mano en Supabase -> SQL Editor (decision D9).
-- Este fichero no se ejecuta solo.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Helper compartido: base (turno o servicio) + reglas por dato adicional.
-- ----------------------------------------------------------------------------
create or replace function flow.calcular_precio_con_reglas(
  p_id_servicio integer,
  p_datos       jsonb,
  p_moneda      text default null,
  p_cantidad    integer default 1,
  p_base_unit   numeric default null
)
returns table (
  precio_total numeric,
  moneda       varchar,
  precio_unit  numeric,
  origen       text
)
language plpgsql
stable
set search_path = flow, public
as $$
declare
  v_cfg         jsonb;
  v_moneda      text;
  v_monedas     text[];
  v_default     text;
  v_unit        numeric;
  v_regla       jsonb;
  v_clave       text;
  v_valor       text;
  v_precios     jsonb;
  v_precios_opc jsonb;
  v_cant        integer;
begin
  v_cant := greatest(coalesce(p_cantidad, 1), 1);

  select coalesce(s.config_precio, '{}'::jsonb)
    into v_cfg
  from flow.app_dat_servicios s
  where s.id = p_id_servicio;

  -- Sin configuracion en el servicio y sin base del turno: 0, igual que antes
  -- (`config_precio = '{}'` es el caso real de los servicios sin precio).
  if p_base_unit is null and (v_cfg is null or v_cfg = '{}'::jsonb) then
    return query
    select 0::numeric,
           coalesce(nullif(trim(p_moneda), ''), 'USD')::varchar,
           0::numeric,
           'sin_config'::text;
    return;
  end if;

  v_cfg := coalesce(v_cfg, '{}'::jsonb);
  v_default := coalesce(v_cfg->>'moneda_default', 'USD');
  select coalesce(array_agg(x::text), array[v_default])
    into v_monedas
  from jsonb_array_elements_text(
    coalesce(v_cfg->'monedas', jsonb_build_array(v_default))) x;

  v_moneda := coalesce(nullif(trim(p_moneda), ''), v_default);
  if not (v_moneda = any (v_monedas)) then
    v_moneda := v_default;
  end if;

  -- Reglas en orden: gana la primera coincidente CON precio resoluble.
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

    -- Formato anterior (opciones + precios compartidos): migracion en lectura.
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

    if v_precios is null
       or v_precios = 'null'::jsonb
       or v_precios = '{}'::jsonb then
      continue;
    end if;

    -- Sin precio para la moneda elegida ni para la moneda por defecto: la
    -- regla se IGNORA y se sigue buscando (nunca 0 por este motivo).
    v_unit := coalesce(
      nullif(v_precios->>v_moneda, '')::numeric,
      nullif(v_precios->>v_default, '')::numeric
    );
    if v_unit is null then
      continue;
    end if;

    return query
    select (v_unit * v_cant)::numeric, v_moneda::varchar, v_unit::numeric, 'regla'::text;
    return;
  end loop;

  -- Base: precio propio del turno si vino.
  if p_base_unit is not null then
    return query
    select (p_base_unit * v_cant)::numeric,
           v_moneda::varchar,
           p_base_unit::numeric,
           'turno'::text;
    return;
  end if;

  -- Base: precios_base del servicio (moneda elegida y respaldo al default).
  v_precios := coalesce(v_cfg->'precios_base', '{}'::jsonb);
  v_unit := coalesce(
    nullif(v_precios->>v_moneda, '')::numeric,
    nullif(v_precios->>v_default, '')::numeric
  );

  if v_unit is null then
    return query
    select 0::numeric, v_moneda::varchar, 0::numeric, 'sin_config'::text;
    return;
  end if;

  return query
  select (v_unit * v_cant)::numeric, v_moneda::varchar, v_unit::numeric, 'base'::text;
end;
$$;

comment on function flow.calcular_precio_con_reglas(integer, jsonb, text, integer, numeric) is
  'Precio unitario x cantidad de una reserva: base (turno o servicio) + primera regla de config_precio con precio resoluble para la moneda.';

-- ----------------------------------------------------------------------------
-- Precio del servicio (sin turno): misma firma y mismas 3 columnas de siempre.
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
begin
  return query
  select h.precio_total, h.moneda, h.precio_unit
  from flow.calcular_precio_con_reglas(
    p_id_servicio,
    p_datos,
    p_moneda,
    greatest(coalesce(p_cantidad, 1), 1),
    null::numeric
  ) h;
end;
$$;

-- ----------------------------------------------------------------------------
-- Precio del turno: su precio propio es la BASE sobre la que se aplican las
-- reglas de datos adicionales del servicio.
-- ----------------------------------------------------------------------------
create or replace function flow.calcular_precio_turno(
  p_id_servicio integer,
  p_id_turno    integer,
  p_datos       jsonb,
  p_moneda      text default null,
  p_cantidad    integer default 1
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
  v_precios jsonb;
  v_moneda  text;
  v_default text;
  v_unit    numeric;
  v_cant    integer := greatest(coalesce(p_cantidad, 1), 1);
begin
  select t.precios,
         coalesce(s.config_precio->>'moneda_default', 'USD')
    into v_precios, v_default
  from flow.turno t
  join flow.recurso r on r.id = t.id_recurso
  join flow.local_servicio ls on ls.id = r.id_local_servicio
  join flow.app_dat_servicios s on s.id = ls.id_servicio
  where t.id = p_id_turno and s.id = p_id_servicio;

  v_default := coalesce(v_default, 'USD');
  v_moneda := coalesce(nullif(trim(p_moneda), ''), v_default);

  -- Precio unitario del turno, con respaldo a la moneda por defecto. Si no hay
  -- precio propio (`precios = '{}'`), `v_unit` queda NULL y la base la pone el
  -- `precios_base` del servicio dentro del helper.
  if coalesce(v_precios, '{}'::jsonb) <> '{}'::jsonb then
    v_unit := coalesce(
      nullif(v_precios->>v_moneda, '')::numeric,
      nullif(v_precios->>v_default, '')::numeric
    );
  end if;

  -- El helper evalua las reglas por dato adicional sobre esa base.
  return query
  select h.precio_total, h.moneda, h.precio_unit
  from flow.calcular_precio_con_reglas(
    p_id_servicio, p_datos, v_moneda, v_cant, v_unit
  ) h;
end;
$$;

-- ----------------------------------------------------------------------------
-- Permisos: las tres las llaman RPC que corren como `authenticated` (una
-- funcion anidada exige EXECUTE sobre la llamada).
-- ----------------------------------------------------------------------------
grant execute on function flow.calcular_precio_con_reglas(integer, jsonb, text, integer, numeric) to authenticated;
grant execute on function flow.calcular_precio_reserva(integer, jsonb, text, integer) to authenticated;
grant execute on function flow.calcular_precio_turno(integer, integer, jsonb, text, integer) to authenticated;

-- El helper es nuevo: que PostgREST refresque su cache de esquema.
notify pgrst, 'reload schema';

-- ============================================================================
-- COMPROBACION MANUAL (descomentar y ejecutar tras aplicar la migracion).
--
-- 0) ANTES de aplicar, comparar con la definicion VIVA (firmas y `prosecdef`):
--      select p.oid::regprocedure as firma, p.prosecdef, p.provolatile, p.proconfig
--      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--      where n.nspname = 'flow'
--        and p.proname in ('calcular_precio_reserva', 'calcular_precio_turno');
--
-- 1) Un turno con precio propio y una regla que casa debe cobrar la REGLA:
--      select * from flow.calcular_precio_turno(7, 20, '{"tipo":"vip"}'::jsonb, null, 1);
--    -> precio_unit = precio de la regla, origen... (las publicas no exponen
--       `origen`; para verlo, llamar al helper):
--      select * from flow.calcular_precio_con_reglas(7, '{"tipo":"vip"}'::jsonb, null, 1, 90);
--
-- 2) El mismo turno con un dato que NO casa ninguna regla: precio del turno.
--      select * from flow.calcular_precio_turno(7, 20, '{}'::jsonb, null, 1);
--
-- 3) Una regla que casa pero SIN precio ni en la moneda elegida ni en la de por
--    defecto NO puede devolver 0: se ignora y cae al base (aqui, 90).
--      select * from flow.calcular_precio_con_reglas(7, '{"tipo":"vip"}'::jsonb, 'CUP', 1, 90);
--
-- 4) `config_precio = '{}'` en el servicio sigue devolviendo 0:
--      select * from flow.calcular_precio_reserva(<id_sin_config>, '{}'::jsonb, null, 1);
-- ============================================================================