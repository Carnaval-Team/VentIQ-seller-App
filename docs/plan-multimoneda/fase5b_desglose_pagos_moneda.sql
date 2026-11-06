-- ============================================================================
-- FASE 5b — «Desglose»: la divisa de cada pago
--
-- PROBLEMA: la pestaña «Desglose» de Ventas pinta los pagos con `$` y los lee
-- como si todos fueran la moneda base. La RPC `reporte_ordenes_json` construía
-- cada pago con `monto`, `importe_sin_descuento`, `referencia_pago`, `fecha_pago`,
-- `es_digital` y `es_efectivo`, **sin la divisa**.
--
-- SOLUCIÓN: parche en sitio del jsonb que arma `pagos_agg`, añadiendo dos claves
-- a cada pago:
--     'moneda'                → la divisa real del pago
--     'monto_cup_equivalente' → el consolidable (fiable desde R11)
--
-- POR QUÉ PARCHE Y NO REESCRITURA: la función devuelve `jsonb`, no una
-- `RETURNS TABLE`, así que **se puede hacer `CREATE OR REPLACE` sin soltarla** y
-- sin cambiar su firma. Las claves nuevas son aditivas: quien no las lea, no se
-- entera. El parche se hace sobre el texto **desplegado** (`pg_get_functiondef`),
-- no sobre una copia del repo, así que no hay deriva, y es fail-closed: si el
-- cuerpo no es el esperado, aborta sin tocar nada.
--
-- Idempotente. Verificado en `newa` el 2026-11-06: el jsonb de salida contiene
-- `"moneda":` y `"monto_cup_equivalente":` (31 KB de respuesta para una tienda
-- con pagos reales).
-- ============================================================================

do $$
declare
  v_def text;
  v_old constant text := chr(10) || '                ''es_efectivo'',           mp.es_efectivo';
  v_new constant text := chr(10) || '                ''es_efectivo'',           mp.es_efectivo,' || chr(10) ||
                         '                ''moneda'',                pv.moneda,' || chr(10) ||
                         '                ''monto_cup_equivalente'', pv.monto_cup_equivalente';
  v_n int;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'reporte_ordenes_json';

  if v_def is null then
    raise exception 'FASE5b: no existe public.reporte_ordenes_json';
  end if;

  v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);

  -- Ya parcheada: no se toca (idempotencia).
  if v_n = 0 and position('''moneda'',                pv.moneda' in v_def) > 0 then
    raise notice 'FASE5b: reporte_ordenes_json ya estaba parcheada';
    return;
  end if;

  if v_n <> 1 then
    raise exception 'FASE5b: se esperaba 1 ocurrencia del bloque de pagos y hay %. NO se aplica.', v_n;
  end if;

  execute replace(v_def, v_old, v_new);
  raise notice 'FASE5b: reporte_ordenes_json parcheada';
end $$;

-- ---------------------------------------------------------------------------
-- Verificación: las dos claves deben estar presentes en la salida
-- ---------------------------------------------------------------------------
with r as (
  select public.reporte_ordenes_json(
           (select o.id_tienda
            from public.app_dat_pago_venta pv
            join public.app_dat_operacion_venta ov on ov.id_operacion = pv.id_operacion_venta
            join public.app_dat_operaciones o on o.id = ov.id_operacion
            limit 1),
           now() - interval '400 days', now(), null)::text as j
)
select position('"moneda":' in j) > 0                as tiene_moneda,
       position('"monto_cup_equivalente":' in j) > 0 as tiene_equivalente
from r;