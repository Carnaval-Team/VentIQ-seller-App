-- ============================================================================
-- FASE 4 — CAJA Y ARQUEO MULTIMONEDA · PARTE 2
--
--   1. `registrar_apertura_turno_monedas`  → apertura con efectivo por divisa.
--   2. `fn_cerrar_turno_tpv_monedas`       → cierre con arqueo por divisa.
--   3. `fn_resumen_diario_cierre_v4`       → resumen + `desglose_monedas` + `total_base`.
--
-- Requiere la PARTE 1 (`fase4_caja_multimoneda.sql`): tabla
-- `app_dat_caja_turno_moneda` y el parche de `fn_resumen_diario_cierre_v2`.
--
-- Diseño: las funciones nuevas **reutilizan** las RPC vigentes (`_usd`) para no
-- duplicar la lógica de creación/cierre del turno, y encima escriben el arqueo
-- por divisa. Así la app vieja sigue funcionando y el camino nuevo no reimplementa
-- nada ya probado.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- 0. Auxiliar: extrae un monto del jsonb {"MONEDA": monto} sin romper si falta
--    la clave o el valor no es numérico (devuelve NULL).
-- ---------------------------------------------------------------------------
create or replace function public.fn_jsonb_monto(p jsonb, p_moneda text)
returns numeric
language plpgsql
immutable
as $$
declare v numeric;
begin
  if p is null or jsonb_typeof(p) <> 'object' then return null; end if;
  select case
           when jsonb_typeof(e.value) = 'number' then (e.value #>> '{}')::numeric
           when jsonb_typeof(e.value) = 'string'
                and trim(e.value #>> '{}') ~ '^-?[0-9]+([.][0-9]+)?$'
             then trim(e.value #>> '{}')::numeric
         end
  into v
  from jsonb_each(p) e
  where upper(trim(e.key)) = upper(trim(p_moneda))
  limit 1;
  return v;
end $$;
-- 1. APERTURA multimoneda
--    p_efectivo_inicial_por_moneda: {"CUP":1000,"USD":20}
-- ---------------------------------------------------------------------------
create or replace function public.registrar_apertura_turno_monedas(
  p_id_tpv                  bigint,
  p_id_vendedor             bigint,
  p_usuario                 uuid,
  p_maneja_inventario       boolean,
  p_productos               jsonb,
  p_efectivo_inicial_por_moneda jsonb,
  p_observaciones           text default null
) returns bigint
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_operacion_id bigint;
  v_turno_id     bigint;
  v_cup  numeric;
  v_usd  numeric;
begin
  if p_efectivo_inicial_por_moneda is null
     or jsonb_typeof(p_efectivo_inicial_por_moneda) <> 'object' then
    raise exception 'Se esperaba un objeto {"MONEDA": monto} de efectivo inicial';
  end if;

  -- Reutiliza la RPC vigente: escribe el turno y las columnas legacy.
  v_cup := coalesce(public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, 'CUP'), 0);
  v_usd := coalesce(public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, 'USD'), 0);

  v_operacion_id := public.registrar_apertura_turno_usd(
            p_efectivo_inicial      := v_cup,
            p_id_tpv                := p_id_tpv,
            p_id_vendedor           := p_id_vendedor,
            p_usuario               := p_usuario,
            p_maneja_inventario     := p_maneja_inventario,
            p_productos             := p_productos,
            p_observaciones         := p_observaciones,
            p_efectivo_inicial_usd  := v_usd);


  -- La RPC vigente devuelve el id de la OPERACIÓN de apertura, NO el del turno
  -- (la app lo consume como 'operacion_id'). Hay que resolver el turno real
  -- antes de escribir el arqueo por divisa.
  select ct.id into v_turno_id
  from public.app_dat_caja_turno ct
  where ct.id_operacion_apertura = v_operacion_id
  order by ct.id desc
  limit 1;
  if v_turno_id is null then
    select ct.id into v_turno_id from public.app_dat_caja_turno ct
    where ct.id = v_operacion_id limit 1;
  end if;
  if v_turno_id is null then
    raise exception 'No se pudo resolver el turno recién abierto (operacion_apertura=%)', v_operacion_id;
  end if;
  insert into public.app_dat_caja_turno_moneda (id_turno, moneda, efectivo_inicial)
  select v_turno_id, upper(trim(e.key)), public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, e.key)
  from jsonb_each(p_efectivo_inicial_por_moneda) e
  where public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, e.key) is not null
    and exists (select 1 from public.monedas m where m.codigo = upper(trim(e.key)))
  on conflict (id_turno, moneda) do update
    set efectivo_inicial = excluded.efectivo_inicial,
        updated_at = now();

  return v_operacion_id;
end $$;

-- ---------------------------------------------------------------------------
-- 2. CIERRE multimoneda
--    p_efectivo_real_por_moneda: {"CUP":1500,"USD":18}
--    Devuelve boolean (la app exige `== true`).
-- ---------------------------------------------------------------------------
create or replace function public.fn_cerrar_turno_tpv_monedas(
  p_id_tpv      bigint,
  p_usuario     uuid,
  p_productos   jsonb,
  p_efectivo_real_por_moneda jsonb,
  p_observaciones text default null
) returns boolean
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_turno   record;
  v_ok      boolean;
  v_cup     numeric;
  v_usd     numeric;
begin
  if p_efectivo_real_por_moneda is null
     or jsonb_typeof(p_efectivo_real_por_moneda) <> 'object' then
    raise exception 'Se esperaba un objeto {"MONEDA": monto} de efectivo real';
  end if;

  select * into v_turno
  from public.app_dat_caja_turno
  where id_tpv = p_id_tpv and estado = 1 and creado_por = p_usuario
  order by fecha_apertura desc
  limit 1;
  if not found then
    return false;
  end if;

  v_cup := coalesce(public.fn_jsonb_monto(p_efectivo_real_por_moneda, 'CUP'), 0);
  v_usd := coalesce(public.fn_jsonb_monto(p_efectivo_real_por_moneda, 'USD'), 0);

  -- Reutiliza la RPC vigente: cierra el turno y las columnas legacy.
  v_ok := public.fn_cerrar_turno_tpv_usd(
            p_id_tpv            := p_id_tpv,
            p_efectivo_real     := v_cup,
            p_usuario           := p_usuario,
            p_productos         := p_productos,
            p_observaciones     := p_observaciones,
            p_efectivo_real_usd := v_usd);
  if not coalesce(v_ok, false) then
    return false;
  end if;

  -- Esperado por divisa = efectivo inicial de esa divisa + pagos EN EFECTIVO de
  -- esa divisa dentro de la ventana del turno (mismo criterio que _v2).
  with pagos as (
    select upper(trim(pv.moneda)) as moneda,
           sum(pv.monto) as efectivo_nativo
    from public.app_dat_operaciones o
    join public.app_dat_operacion_venta ov on ov.id_operacion = o.id
    join public.app_dat_pago_venta pv on pv.id_operacion_venta = ov.id_operacion
    join public.app_nom_medio_pago mp on mp.id = pv.id_medio_pago
    where ov.id_tpv = p_id_tpv
      and o.uuid = p_usuario
      and o.created_at >= v_turno.fecha_apertura
      and mp.es_efectivo and mp.es_activo
      and exists (
        select 1 from public.app_dat_estado_operacion eo
        where eo.id_operacion = o.id and eo.estado = 2
          and eo.id = (select max(eo2.id) from public.app_dat_estado_operacion eo2
                       where eo2.id_operacion = o.id))
    group by 1
  ),
  inicial as (
    select moneda, efectivo_inicial
    from public.app_dat_caja_turno_moneda
    where id_turno = v_turno.id
  ),
  esperado as (
    select coalesce(i.moneda, p.moneda) as moneda,
           coalesce(i.efectivo_inicial, 0) as inicial,
           coalesce(i.efectivo_inicial, 0) + coalesce(p.efectivo_nativo, 0) as esperado
    from inicial i
    full join pagos p on p.moneda = i.moneda
  )
  insert into public.app_dat_caja_turno_moneda
    (id_turno, moneda, efectivo_inicial, efectivo_esperado, efectivo_real)
  select v_turno.id, e.moneda, e.inicial, e.esperado,
         coalesce(public.fn_jsonb_monto(p_efectivo_real_por_moneda, e.moneda), 0)
  from esperado e
  where exists (select 1 from public.monedas m where m.codigo = e.moneda)
  on conflict (id_turno, moneda) do update
    set efectivo_esperado = excluded.efectivo_esperado,
        efectivo_real     = excluded.efectivo_real,
        updated_at        = now();

  return true;
end $$;

-- ---------------------------------------------------------------------------
-- 3. RESUMEN con desglose por moneda (aditivo al final del RETURNS TABLE)
-- ---------------------------------------------------------------------------
create or replace function public.fn_resumen_diario_cierre_v4(
  id_tpv_param     bigint default null,
  id_usuario_param uuid default null
) returns table(
  ventas_totales numeric, efectivo_inicial numeric, efectivo_real numeric,
  efectivo_esperado numeric, productos_vendidos numeric, ticket_promedio numeric,
  porcentaje_efectivo numeric, porcentaje_otros numeric, operaciones_totales integer,
  operaciones_por_hora numeric, promedio_operaciones_por_hora numeric,
  conciliacion_estado text, efectivo_real_ajustado numeric, diferencia_ajustada numeric,
  turno_id bigint, fecha_apertura timestamptz, horas_transcurridas numeric,
  productos_vendidos_base numeric, productos_vendidos_desglose text,
  ventas_usd numeric, efectivo_usd_esperado numeric, digital_usd numeric,
  desglose_monedas jsonb, total_base numeric
)
language sql
security definer
set search_path to 'public'
as $function$
  with base as (
    select * from public.fn_resumen_diario_cierre_v3(id_tpv_param, id_usuario_param)
  ),
  pagos as (
    select upper(trim(pv.moneda)) as moneda,
           count(distinct pv.id_operacion_venta) as operaciones,
           sum(pv.monto) as importe_nativo,
           sum(pv.monto * coalesce(pv.tasa_cambio, pv.tasa_usd, 1)) as importe_base,
           sum(pv.monto) filter (where mp.es_efectivo) as efectivo_nativo,
           sum(pv.monto) filter (where not mp.es_efectivo) as digital_nativo
    from base b
    join public.app_dat_operaciones o
      on o.uuid = id_usuario_param
     and o.created_at >= b.fecha_apertura
    join public.app_dat_operacion_venta ov
      on ov.id_operacion = o.id
     and ov.id_tpv = id_tpv_param
    join public.app_dat_pago_venta pv on pv.id_operacion_venta = ov.id_operacion
    join public.app_nom_medio_pago mp on mp.id = pv.id_medio_pago and mp.es_activo
    where exists (
      select 1 from public.app_dat_estado_operacion eo
      where eo.id_operacion = o.id and eo.estado = 2
        and eo.id = (select max(eo2.id) from public.app_dat_estado_operacion eo2
                     where eo2.id_operacion = o.id))
    group by 1
  ),
  desglose as (
    select coalesce(
             jsonb_agg(jsonb_build_object(
               'moneda',          p.moneda,
               'operaciones',     p.operaciones,
               'importe_nativo',  p.importe_nativo,
               'importe_base',    p.importe_base,
               'efectivo_nativo', coalesce(p.efectivo_nativo, 0),
               'digital_nativo',  coalesce(p.digital_nativo, 0)
             ) order by p.importe_base desc), '[]'::jsonb) as j,
           coalesce(sum(p.importe_base), 0) as total
    from pagos p
  )
  select b.*, d.j, d.total
  from base b cross join desglose d;
$function$;

-- ---------------------------------------------------------------------------
-- 4. Verificación
-- ---------------------------------------------------------------------------
select p.proname, pg_get_function_identity_arguments(p.oid) as args
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('registrar_apertura_turno_monedas', 'fn_cerrar_turno_tpv_monedas',
                    'fn_resumen_diario_cierre_v4', 'fn_jsonb_monto')
order by 1;

-- ---------------------------------------------------------------------------
-- 5. Pendiente (parte 3)
--    · equivalentes offline: fn_apertura_turno_offline_monedas / fn_cerrar_turno_offline_monedas
--    · pantallas: cash_count_dialog, cierre, apertura, turno_service,
--      venta_total, bill_count_dialog (ver `fase4-recon-caja.md`)
-- ---------------------------------------------------------------------------