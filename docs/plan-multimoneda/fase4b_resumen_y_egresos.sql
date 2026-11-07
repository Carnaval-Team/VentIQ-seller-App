-- ============================================================================
-- FASE 4b — DIVISA DEL EGRESO Y DESGLOSE POR TURNO
--
--   1. `app_dat_entregas_parciales_caja.moneda` (no existía) + FK al catálogo.
--   2. `registrar_egreso_parcial_v3(..., p_moneda)` — envuelve a la v2.
--   3. `egresos_por_turno` devuelve `moneda` (aditivo; cambia RETURNS TABLE).
--   4. `fn_desglose_monedas_turno(turno, criterio)` — ÚNICA implementación.
--   5. `fn_resumen_turno_por_id_v2` / `fn_resumen_turno_kpi_v2` — las vigentes
--      + `desglose_monedas` + `total_base`.
--   6. `fn_resumen_diario_cierre_v4` pasa a usar la misma fuente.
--
-- DECISIONES DE DISEÑO (por qué)
--
-- · La v3 **envuelve** a la v2 en vez de reescribirla: 3,5 KB de plpgsql con
--   validaciones de negocio ya probadas en producción. La v3 solo valida la
--   divisa y ajusta la fila recién creada.
-- · `egresos_por_turno` cambia su `RETURNS TABLE` y eso NO se puede hacer con
--   CREATE OR REPLACE: hay que soltarla y recrearla.
-- · El desglose tiene DOS criterios y por eso recibe un flag:
--     `true`  → el del resumen de turno (`fn_resumen_turno_por_id`): vendedor
--               asignado al turno, solo tipo «venta» y SIN cota superior de
--               fecha, que es como está escrito ese resumen. Así el desglose
--               cuadra con las ventas que muestra.
--     `false` → el del arqueo/cierre: quien abrió el turno (`creado_por`) y
--               ventana acotada por `fecha_cierre`, para no arrastrar ventas
--               posteriores al cierre.
-- · **`total_base` puede ser menor que `ventas_totales`, y es correcto**: el
--   desglose solo cuenta operaciones en estado 2 (venta completada, igual que
--   `fn_resumen_diario_cierre_v2`), mientras que `fn_resumen_turno_por_id` NO
--   filtra por estado. `total_base` es dinero realmente cobrado y completado;
--   `ventas_totales` arrastra operaciones en otros estados. Diferencia medida
--   en `newa`: 4.500 vs 141.500, porque solo 1 de 6 operaciones estaba en
--   estado 2. En producción, con la mayoría en estado 2, la brecha es pequeña.
--
-- Idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Divisa del egreso
-- ---------------------------------------------------------------------------
alter table public.app_dat_entregas_parciales_caja
  add column if not exists moneda character(3) not null default 'CUP';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'app_dat_entregas_parciales_caja_moneda_fkey'
      and conrelid = 'public.app_dat_entregas_parciales_caja'::regclass
  ) then
    alter table public.app_dat_entregas_parciales_caja
      add constraint app_dat_entregas_parciales_caja_moneda_fkey
      foreign key (moneda) references public.monedas(codigo);
  end if;
end $$;

-- Todo el histórico se hizo en moneda base: no había forma de registrar otra.
update public.app_dat_entregas_parciales_caja
set moneda = 'CUP'
where moneda is null or moneda = '';

-- ---------------------------------------------------------------------------
-- 2. Alta de egreso con divisa
-- ---------------------------------------------------------------------------
create or replace function public.registrar_egreso_parcial_v3(
  p_id_turno        bigint,
  p_monto_entrega   numeric,
  p_nombre_recibe   character varying,
  p_nombre_autoriza character varying,
  p_motivo_entrega  text,
  p_id_medio_pago   smallint,
  p_moneda          text default 'CUP'
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_res    jsonb;
  v_id     bigint;
  v_moneda text;
begin
  v_moneda := upper(trim(coalesce(nullif(p_moneda, ''), 'CUP')));

  if not exists (select 1 from public.monedas m where m.codigo = v_moneda and m.activo) then
    raise exception 'La moneda % no existe o no está activa en el catálogo', v_moneda;
  end if;

  v_res := public.registrar_egreso_parcial_v2(
             p_id_turno, p_monto_entrega, p_nombre_recibe,
             p_nombre_autoriza, p_motivo_entrega, p_id_medio_pago);

  if coalesce((v_res->>'success')::boolean, false) then
    v_id := nullif(v_res->>'egreso_id', '')::bigint;
    if v_id is not null then
      update public.app_dat_entregas_parciales_caja
      set moneda = v_moneda
      where id = v_id;
    end if;
  end if;

  return v_res;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Lectura de egresos con divisa
-- ---------------------------------------------------------------------------
drop function if exists public.egresos_por_turno(bigint);

create function public.egresos_por_turno(p_id_turno bigint)
returns table(
  id_egreso bigint,
  monto_entrega numeric,
  motivo_entrega text,
  nombre_recibe character varying,
  nombre_autoriza character varying,
  fecha_entrega timestamp with time zone,
  id_medio_pago smallint,
  turno_estado smallint,
  moneda character varying
)
language plpgsql
as $function$
BEGIN
    RETURN QUERY
    SELECT
        epc.id,
        epc.monto_entrega,
        epc.motivo_entrega,
        epc.nombre_recibe,
        epc.nombre_autoriza,
        epc.fecha_entrega,
        epc.id_medio_pago,
        ct.estado,
        epc.moneda::character varying
    FROM app_dat_entregas_parciales_caja epc
    INNER JOIN app_dat_caja_turno ct ON epc.id_turno = ct.id
    WHERE ct.id = p_id_turno
      and auth.uid() = coalesce(epc.uuid_vendedor, ct.creado_por)
    ORDER BY epc.fecha_entrega;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 4. Desglose por divisa de un turno (fuente única)
--    Sin DEFAULT en el segundo argumento a propósito: un default haría
--    ambigua cualquier llamada de un solo argumento mientras exista la
--    sobrecarga antigua. Se suelta la de 1 argumento al final.
-- ---------------------------------------------------------------------------
drop function if exists public.fn_desglose_monedas_turno(bigint, boolean);
drop function if exists public.fn_desglose_monedas_turno(bigint);

create function public.fn_desglose_monedas_turno(
  p_id_turno        bigint,
  p_criterio_resumen boolean
) returns table(desglose_monedas jsonb, total_base numeric)
language sql
security definer
set search_path to 'public'
as $$
  with turno as (
    select id, id_tpv, id_vendedor, creado_por, fecha_apertura,
           coalesce(fecha_cierre, now()) as fecha_fin
    from public.app_dat_caja_turno
    where id = p_id_turno
  ),
  venta_tipo as (
    select id from public.app_nom_tipo_operacion
    where lower(denominacion) = 'venta' limit 1
  ),
  pagos as (
    select upper(trim(pv.moneda)) as moneda,
           count(distinct pv.id_operacion_venta) as operaciones,
           sum(pv.monto) as importe_nativo,
           sum(pv.monto * coalesce(pv.tasa_cambio, pv.tasa_usd, 1)) as importe_base,
           sum(pv.monto) filter (where mp.es_efectivo) as efectivo_nativo,
           sum(pv.monto) filter (where not mp.es_efectivo) as digital_nativo
    from turno t
    join public.app_dat_operaciones o
      on o.created_at >= t.fecha_apertura
     -- El resumen vigente no acota por fecha superior; el arqueo sí.
     and (p_criterio_resumen or o.created_at <= t.fecha_fin)
     and o.uuid = case when p_criterio_resumen
                       then (select v.uuid from public.app_dat_vendedor v
                             where v.id = t.id_vendedor)
                       else t.creado_por end
     and (not p_criterio_resumen or o.id_tipo_operacion = (select id from venta_tipo))
    join public.app_dat_operacion_venta ov
      on ov.id_operacion = o.id and ov.id_tpv = t.id_tpv
    join public.app_dat_pago_venta pv on pv.id_operacion_venta = ov.id_operacion
    join public.app_nom_medio_pago mp on mp.id = pv.id_medio_pago and mp.es_activo
    where exists (
      select 1 from public.app_dat_estado_operacion eo
      where eo.id_operacion = o.id and eo.estado = 2
        and eo.id = (select max(eo2.id) from public.app_dat_estado_operacion eo2
                     where eo2.id_operacion = o.id))
    group by 1
  )
  select coalesce(
           jsonb_agg(jsonb_build_object(
             'moneda',          p.moneda,
             'operaciones',     p.operaciones,
             'importe_nativo',  p.importe_nativo,
             'importe_base',    p.importe_base,
             'efectivo_nativo', coalesce(p.efectivo_nativo, 0),
             'digital_nativo',  coalesce(p.digital_nativo, 0)
           ) order by p.importe_base desc), '[]'::jsonb),
         coalesce(sum(p.importe_base), 0)
  from pagos p;
$$;

-- ---------------------------------------------------------------------------
-- 5. Resúmenes de turno con desglose (aditivo al final del RETURNS TABLE)
-- ---------------------------------------------------------------------------
create or replace function public.fn_resumen_turno_por_id_v2(p_turno_id bigint)
returns table(
  turno_id bigint, tpv character varying, vendedor character varying,
  fecha_apertura timestamp with time zone, fecha_cierre timestamp with time zone,
  duracion interval, estado_turno smallint, estado_descripcion character varying,
  ventas_totales numeric, productos_vendidos numeric, ticket_promedio numeric,
  efectivo_inicial numeric, efectivo_esperado numeric, efectivo_real numeric,
  diferencia_efectivo numeric, porcentaje_efectivo numeric, porcentaje_otros numeric,
  operaciones_totales bigint, operaciones_por_hora numeric,
  conciliacion_estado character varying, total_egresos_parciales numeric,
  efectivo_real_ajustado numeric, diferencia_ajustada numeric,
  desglose_monedas jsonb, total_base numeric
)
language sql
security definer
set search_path to 'public'
as $$
  with base as (
    select * from public.fn_resumen_turno_por_id(p_turno_id)
  )
  select b.*, d.desglose_monedas, d.total_base
  from base b
  cross join lateral public.fn_desglose_monedas_turno(b.turno_id, true) d;
$$;

create or replace function public.fn_resumen_turno_kpi_v2(
  p_id_tpv      bigint,
  p_id_vendedor bigint,
  p_fecha_desde timestamp with time zone,
  p_fecha_hasta timestamp with time zone
) returns table(
  turno_id bigint, tpv character varying, vendedor character varying,
  fecha_apertura timestamp with time zone, fecha_cierre timestamp with time zone,
  duracion interval, estado_turno smallint, ventas_totales numeric,
  productos_vendidos bigint, ticket_promedio numeric, efectivo_inicial numeric,
  efectivo_esperado numeric, efectivo_real numeric, diferencia_efectivo numeric,
  porcentaje_efectivo numeric, porcentaje_otros numeric, operaciones_totales bigint,
  operaciones_por_hora numeric, conciliacion_estado text,
  desglose_monedas jsonb, total_base numeric
)
language sql
security definer
set search_path to 'public'
as $$
  with base as (
    select * from public.fn_resumen_turno_kpi(p_id_tpv, p_id_vendedor,
                                              p_fecha_desde, p_fecha_hasta)
  )
  select b.*, d.desglose_monedas, d.total_base
  from base b
  cross join lateral public.fn_desglose_monedas_turno(b.turno_id, true) d;
$$;

-- ---------------------------------------------------------------------------
-- 6. `_v4` usa la misma fuente (criterio del arqueo: false)
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
as $$
  with base as (
    select * from public.fn_resumen_diario_cierre_v3(id_tpv_param, id_usuario_param)
  )
  select b.*, d.desglose_monedas, d.total_base
  from base b
  cross join lateral public.fn_desglose_monedas_turno(b.turno_id, false) d;
$$;

-- ---------------------------------------------------------------------------
-- 7. Verificación
-- ---------------------------------------------------------------------------
select column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'app_dat_entregas_parciales_caja'
  and column_name = 'moneda';

select p.oid::regprocedure::text as firma
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('registrar_egreso_parcial_v3', 'egresos_por_turno',
                    'fn_desglose_monedas_turno', 'fn_resumen_turno_por_id_v2',
                    'fn_resumen_turno_kpi_v2', 'fn_resumen_diario_cierre_v4')
order by 1;