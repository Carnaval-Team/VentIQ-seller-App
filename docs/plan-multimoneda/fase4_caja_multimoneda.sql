-- ============================================================================
-- FASE 4 — CAJA Y ARQUEO MULTIMONEDA · PARTE 1
--
--   1. FIX del defecto contable de `fn_resumen_diario_cierre_v2` (riesgo R4).
--   2. Tabla `app_dat_caja_turno_moneda` + backfill del USD legacy (§4.6).
--
-- Idempotente: se puede ejecutar dos veces.
-- Fail-closed: si el cuerpo desplegado de `_v2` no es el esperado, ABORTA sin
-- tocar nada (no reescribe la función a ciegas).
--
-- Por qué el fix NO es la línea que decía el plan (§5.3):
--   Cambiar `pv.monto` por `pv.monto_cup_equivalente` en las DOS líneas habría
--   metido el efectivo USD (convertido) dentro de `efectivo_esperado`, y ese
--   campo es el **efectivo CUP que debe haber en el cajón**. El vendedor que
--   cuenta solo CUP habría visto un faltante igual al efectivo USD.
--   El reparto correcto es:
--     · `v_ventas`      = total consolidado en CUP  → monto × tasa, TODAS las monedas
--     · `v_tot_efectivo` = efectivo **CUP** de las ventas → solo pagos en CUP (cajón CUP)
--   Con eso `v_ventas = v_tot_efectivo + v_tot_otros` sigue cuadrando, el cajón
--   CUP queda correcto y el desglose por divisa llega en la parte 2.
--   Para una tienda 100% CUP el resultado es **idéntico al de hoy**.
--
--   Y no se usa `monto_cup_equivalente` porque esa columna está corrupta
--   (R11: 666 NULL y 97 filas con el total de la operación). Se calcula desde
--   `monto × tasa`, que es determinista y no depende de la reparación pendiente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. MEDICIÓN PREVIA (solo lectura) — cuánto está mal hoy
-- ---------------------------------------------------------------------------
with p as (
  select pv.moneda,
         coalesce(mp.es_efectivo, false) as es_efectivo,
         sum(pv.monto) as nativo,
         sum(pv.monto * coalesce(pv.tasa_cambio, pv.tasa_usd, 1)) as equiv
  from public.app_dat_pago_venta pv
  join public.app_nom_medio_pago mp on mp.id = pv.id_medio_pago
  where upper(trim(pv.moneda)) <> 'CUP'
  group by 1, 2
)
select moneda, es_efectivo,
       sum(nativo) as sum_nativo_lo_que_suma_hoy,
       sum(equiv)  as sum_equivalente_correcto,
       sum(equiv - nativo) as subestimacion_cup
from p
group by 1, 2
order by 1, 2;

-- ---------------------------------------------------------------------------
-- 1. TABLA DE ARQUEO POR DIVISA (§4.6)
-- ---------------------------------------------------------------------------
create table if not exists public.app_dat_caja_turno_moneda (
  id_turno          bigint      not null references public.app_dat_caja_turno(id) on delete cascade,
  moneda            character(3) not null references public.monedas(codigo),
  efectivo_inicial  numeric     not null default 0,
  efectivo_esperado numeric     not null default 0,
  efectivo_real     numeric,
  diferencia        numeric generated always as (efectivo_real - efectivo_esperado) stored,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  primary key (id_turno, moneda)
);

comment on table public.app_dat_caja_turno_moneda is
  'Arqueo de caja por divisa. Sustituye funcionalmente a *_usd, que se sigue escribiendo para la app vieja.';

-- Backfill desde las columnas USD legacy (idempotente).
insert into public.app_dat_caja_turno_moneda
  (id_turno, moneda, efectivo_inicial, efectivo_real)
select ct.id, 'USD',
       coalesce(ct.efectivo_inicial_usd, 0),
       ct.efectivo_real_usd
from public.app_dat_caja_turno ct
where (coalesce(ct.efectivo_inicial_usd, 0) <> 0 or ct.efectivo_real_usd is not null)
on conflict (id_turno, moneda) do nothing;

-- Semilla de la moneda base en todos los turnos (necesaria para que el cierre
-- pueda escribir el arqueo CUP aunque hoy no exista la fila).
insert into public.app_dat_caja_turno_moneda (id_turno, moneda, efectivo_inicial)
select ct.id, 'CUP', coalesce(ct.efectivo_inicial, 0)
from public.app_dat_caja_turno ct
on conflict (id_turno, moneda) do nothing;

-- ---------------------------------------------------------------------------
-- 2. FIX DE `fn_resumen_diario_cierre_v2` (parche en sitio)
--
--    Se parchea el TEXTO DESPLEGADO con `pg_get_functiondef`, no se reescribe
--    la función a mano: así no hay deriva entre repo y producción.
-- ---------------------------------------------------------------------------
do $$
declare
  v_def   text;
  v_old_a constant text := 'CASE WHEN mp.es_efectivo THEN pv.monto ELSE';
  v_new_a constant text := 'CASE WHEN mp.es_efectivo AND upper(trim(pv.moneda)) = ''CUP'' THEN pv.monto ELSE';
  v_old_b constant text := 'CASE WHEN NOT mp.es_efectivo THEN pv.monto ELSE';
  v_new_b constant text := 'CASE WHEN NOT (mp.es_efectivo AND upper(trim(pv.moneda)) = ''CUP'') THEN pv.monto * COALESCE(pv.tasa_cambio, pv.tasa_usd, 1) ELSE';
  v_n_a   int;
  v_n_b   int;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'fn_resumen_diario_cierre_v2';

  if v_def is null then
    raise exception 'FASE4: no existe public.fn_resumen_diario_cierre_v2';
  end if;

  v_n_a := (length(v_def) - length(replace(v_def, v_old_a, ''))) / length(v_old_a);
  v_n_b := (length(v_def) - length(replace(v_def, v_old_b, ''))) / length(v_old_b);

  -- Fail-closed: si ya está parcheada (0) y también la otra (0) es idempotente;
  -- si el texto no es el esperado, no se toca nada.
  if v_n_a = 0 and v_n_b = 0 then
    raise notice 'FASE4: _v2 ya estaba parcheada, no se toca';
    return;
  end if;
  if v_n_a <> 1 or v_n_b <> 1 then
    raise exception 'FASE4: se esperaba 1 ocurrencia de cada patrón en _v2 y hay % / %. NO se aplica el parche.', v_n_a, v_n_b;
  end if;

  v_def := replace(replace(v_def, v_old_a, v_new_a), v_old_b, v_new_b);
  execute v_def;
  raise notice 'FASE4: fn_resumen_diario_cierre_v2 parcheada';
end $$;

-- ---------------------------------------------------------------------------
-- 3. VERIFICACIÓN
-- ---------------------------------------------------------------------------

-- 3.1 La función sigue existiendo y con la misma firma.
select p.proname, pg_get_function_identity_arguments(p.oid) as args
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'fn_resumen_diario_cierre_v2';

-- 3.2 El parche está realmente en el cuerpo (debe devolver true/true).
select position('upper(trim(pv.moneda)) = ''CUP''' in pg_get_functiondef(p.oid)) > 0 as marcador_cup,
       position('COALESCE(pv.tasa_cambio, pv.tasa_usd, 1)' in pg_get_functiondef(p.oid)) > 0 as marcador_tasa
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'fn_resumen_diario_cierre_v2';

-- 3.3 La tabla y el backfill.
select count(*) as filas,
       count(*) filter (where moneda = 'CUP') as cup,
       count(*) filter (where moneda = 'USD') as usd,
       count(distinct id_turno) as turnos
from public.app_dat_caja_turno_moneda;

-- 3.4 Para una tienda 100% CUP el resultado NO puede cambiar.
--     (Comparación de la fórmula vieja vs la nueva sobre los mismos datos.)
with calc as (
  select pv.id_operacion_venta,
         sum(case when mp.es_efectivo then pv.monto else 0 end) as viejo_efectivo,
         sum(case when not mp.es_efectivo then pv.monto else 0 end) as viejo_otros,
         sum(case when mp.es_efectivo and upper(trim(pv.moneda)) = 'CUP' then pv.monto else 0 end) as nuevo_efectivo,
         sum(case when not (mp.es_efectivo and upper(trim(pv.moneda)) = 'CUP')
                  then pv.monto * coalesce(pv.tasa_cambio, pv.tasa_usd, 1) else 0 end) as nuevo_otros
  from public.app_dat_pago_venta pv
  join public.app_nom_medio_pago mp on mp.id = pv.id_medio_pago
  group by 1
)
select count(*) filter (where viejo_efectivo + viejo_otros <> nuevo_efectivo + nuevo_otros) as operaciones_que_cambian,
       sum(nuevo_efectivo + nuevo_otros - viejo_efectivo - viejo_otros) as diferencia_total_cup
from calc;

-- ---------------------------------------------------------------------------
-- 4. PARTE 2 (pendiente, no incluida aquí)
--    · fn_resumen_diario_cierre_v4 con `desglose_monedas` jsonb + `total_base`
--    · registrar_apertura_turno_monedas / fn_cerrar_turno_tpv_monedas
--    · equivalentes offline
--    · pantallas: apertura, cierre, cash_count_dialog, bill_count_dialog
-- ---------------------------------------------------------------------------