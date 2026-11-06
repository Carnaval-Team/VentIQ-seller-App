-- ============================================================================
-- FASE 4 — CAJA MULTIMONEDA · PARTE 3: EQUIVALENTES OFFLINE
--
--   `fn_apertura_turno_offline_monedas` y `fn_cerrar_turno_offline_monedas`.
--
-- POR QUÉ HACEN FALTA:
--   El sync offline (`auto_sync_service.dart:1379-1400` y `:2255-2273`) llama a
--   las variantes `*_offline_usd` y **omite `p_efectivo_inicial_usd` cuando es
--   null**, así que puede acabar en la variante sin USD. Con el trigger
--   `trg_sync_turno_moneda` el arqueo CUP/USD ya queda bien, pero **una tercera
--   divisa (EUR)** nunca se sembraría: esa es la razón de estas funciones.
--
-- DEPENDENCIA: usa `fn_esperado_turno_por_moneda` (parte 1c,
--   `fase4_arqueo_esperado.sql`). Se vuelve a declarar aquí, idéntica, para que
--   este fichero funcione por sí solo. Ejecutar 1c antes es lo recomendado.
--
-- Idempotente. Sigue el patrón de las funciones online ya verificadas.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- 0. Guardia de dependencia
--
--    El cálculo del esperado por divisa vive en `fase4_arqueo_esperado.sql`
--    (parte 1c) como `fn_esperado_turno_por_moneda`. Se declara UNA sola vez a
--    propósito: duplicarlo en dos ficheros garantiza que acaben divergiendo.
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_esperado_turno_por_moneda'
  ) then
    raise exception
      'Falta public.fn_esperado_turno_por_moneda. Ejecuta antes fase4_arqueo_esperado.sql (parte 1c).';
  end if;
end $$;
-- 1. APERTURA offline por divisa
--    Devuelve el MISMO jsonb que la variante vigente (status/message/id_turno/
--    idempotent) para no cambiar el contrato del sincronizador.
-- ---------------------------------------------------------------------------
create or replace function public.fn_apertura_turno_offline_monedas(
  p_client_uuid            uuid,
  p_id_tpv                 bigint,
  p_id_vendedor            bigint,
  p_usuario                uuid,
  p_maneja_inventario      boolean,
  p_productos              jsonb,
  p_efectivo_inicial_por_moneda jsonb,
  p_observaciones          text default null,
  p_fecha_apertura         timestamptz default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_res      jsonb;
  v_turno_id bigint;
  v_cup      numeric;
  v_usd      numeric;
begin
  if p_efectivo_inicial_por_moneda is null
     or jsonb_typeof(p_efectivo_inicial_por_moneda) <> 'object' then
    raise exception 'Se esperaba un objeto {"MONEDA": monto} de efectivo inicial';
  end if;

  v_cup := coalesce(public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, 'CUP'), 0);
  v_usd := coalesce(public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, 'USD'), 0);

  v_res := public.fn_apertura_turno_offline_usd(
    p_client_uuid        := p_client_uuid,
    p_efectivo_inicial   := v_cup,
    p_id_tpv             := p_id_tpv,
    p_id_vendedor        := p_id_vendedor,
    p_usuario            := p_usuario,
    p_maneja_inventario  := p_maneja_inventario,
    p_productos          := p_productos,
    p_observaciones      := p_observaciones,
    p_fecha_apertura     := p_fecha_apertura,
    p_efectivo_inicial_usd := v_usd);

  -- La variante vigente SÍ devuelve `id_turno` (a diferencia del camino online,
  -- que devuelve el id de la operación).
  if (v_res->>'status') = 'success' then
    v_turno_id := nullif(v_res->>'id_turno', '')::bigint;
    if v_turno_id is not null then
      insert into public.app_dat_caja_turno_moneda (id_turno, moneda, efectivo_inicial)
      select v_turno_id, upper(trim(e.key)),
             public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, e.key)
      from jsonb_each(p_efectivo_inicial_por_moneda) e
      where public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, e.key) is not null
        and exists (select 1 from public.monedas m where m.codigo = upper(trim(e.key)))
      on conflict (id_turno, moneda) do update
        set efectivo_inicial = excluded.efectivo_inicial,
            updated_at       = now();
    end if;
  end if;

  return v_res;
end $$;

-- ---------------------------------------------------------------------------
-- 2. CIERRE offline por divisa
-- ---------------------------------------------------------------------------
create or replace function public.fn_cerrar_turno_offline_monedas(
  p_client_uuid            uuid,
  p_id_tpv                 bigint,
  p_usuario                uuid,
  p_productos              jsonb,
  p_efectivo_real_por_moneda jsonb,
  p_observaciones          text default null,
  p_fecha_cierre           timestamptz default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_res      jsonb;
  v_turno_id bigint;
  v_cup      numeric;
  v_usd      numeric;
  v_esperado record;
begin
  if p_efectivo_real_por_moneda is null
     or jsonb_typeof(p_efectivo_real_por_moneda) <> 'object' then
    raise exception 'Se esperaba un objeto {"MONEDA": monto} de efectivo real';
  end if;

  v_cup := coalesce(public.fn_jsonb_monto(p_efectivo_real_por_moneda, 'CUP'), 0);
  v_usd := coalesce(public.fn_jsonb_monto(p_efectivo_real_por_moneda, 'USD'), 0);

  -- Resolver ANTES de cerrar: el resultado de la RPC vigente no trae el turno.
  select ct.id into v_turno_id
  from public.app_dat_caja_turno ct
  where ct.id_tpv = p_id_tpv and ct.estado = 1 and ct.creado_por = p_usuario
  order by ct.fecha_apertura desc
  limit 1;

  v_res := public.fn_cerrar_turno_offline_usd(
    p_client_uuid        := p_client_uuid,
    p_id_tpv             := p_id_tpv,
    p_efectivo_real      := v_cup,
    p_usuario            := p_usuario,
    p_productos          := p_productos,
    p_observaciones      := p_observaciones,
    p_fecha_cierre       := p_fecha_cierre,
    p_efectivo_real_usd  := v_usd);

  if (v_res->>'status') = 'success' and v_turno_id is not null then
    for v_esperado in
      select moneda, esperado from public.fn_esperado_turno_por_moneda(v_turno_id)
    loop
      insert into public.app_dat_caja_turno_moneda
        (id_turno, moneda, efectivo_inicial, efectivo_esperado, efectivo_real)
      values (v_turno_id, v_esperado.moneda,
              coalesce((select m.efectivo_inicial
                        from public.app_dat_caja_turno_moneda m
                        where m.id_turno = v_turno_id
                          and m.moneda = v_esperado.moneda), 0),
              v_esperado.esperado,
              public.fn_jsonb_monto(p_efectivo_real_por_moneda, v_esperado.moneda))
      on conflict (id_turno, moneda) do update
        set efectivo_esperado = excluded.efectivo_esperado,
            efectivo_real     = coalesce(excluded.efectivo_real,
                                         public.app_dat_caja_turno_moneda.efectivo_real),
            updated_at        = now();
    end loop;
  end if;

  return v_res;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Verificación
-- ---------------------------------------------------------------------------
select p.proname, pg_get_function_identity_arguments(p.oid) as args
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('fn_apertura_turno_offline_monedas',
                    'fn_cerrar_turno_offline_monedas',
                    'fn_esperado_turno_por_moneda')
order by 1;