# SQL para main — correcciones de compras y costos

**Proyecto main:** `vsieeihstajlrdvpuooh` · **Verificado el 2026-11-27.**
**No es la reparación de la compra 80:** eso es dato de `newa` y no existe en main.

Main ya tiene el módulo de compras (`fdi_dat_compra*`, `fn_fdi_compra_*`) y sus funciones base.
Le faltan exactamente los deltas de este plan: `id_tienda` en el nomenclador, la tasa de la tienda,
el aterrizaje por cantidad, el costo unitario, el resumen/detalle corregidos, el diagnóstico y el reset.

> Aplicar **en este orden**, en una sola ventana de mantenimiento. Los scripts están escritos para
> abortar si el cuerpo de una función no coincide con el esperado: si algo falla, no deja cambios a medias.
> Después de cada script, el propio archivo hace `NOTIFY pgrst, 'reload schema'`.

---

## 0. Respaldo (ejecutar primero)

```sql
create schema if not exists bkp_20261127;

create table if not exists bkp_20261127.app_cont_tipo_costo as
  select * from public.app_cont_tipo_costo;

create table if not exists bkp_20261127.fdi_dat_compra_recepcion as
  select * from public.fdi_dat_compra_recepcion;

create table if not exists bkp_20261127.fdi_dat_compra_recepcion_linea as
  select * from public.fdi_dat_compra_recepcion_linea;

create table if not exists bkp_20261127.app_dat_recepcion_producto_costo as
  select * from public.app_dat_recepcion_producto_costo;

create table if not exists bkp_20261127.app_dat_producto_presentacion as
  select id, id_producto, precio_promedio from public.app_dat_producto_presentacion;

create table if not exists bkp_20261127.app_dat_producto_costo as
  select * from public.app_dat_producto_costo;

create table if not exists bkp_20261127.funciones as
  select p.proname, pg_get_function_identity_arguments(p.oid) as args,
         pg_get_functiondef(p.oid) as def
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in (
       'fn_fdi_compra_crear','fn_fdi_compra_editar','fn_fdi_compra_vincular_recepcion',
       'fn_fdi_compra_repartir_aterrizaje','fn_fdi_compra_recepcion_bases',
       'fn_fdi_compra_costo_resumen','fn_fdi_compra_detalle',
       'fn_actualizar_precio_promedio_recepcion_v2_m01',
       'fn_fdi_compra_ajuste_agregar','fn_fdi_compra_ajuste_financiar',
       'fn_cont_tipo_costo_guardar','fn_cont_tipo_costo_eliminar'
     );
```

---

## 1. Preflight (debe dar todo `true`)

```sql
with f as (
  select
    pg_get_functiondef('public.fn_fdi_compra_crear(bigint,bigint,text,date,text,numeric,jsonb,jsonb,text,text,text,uuid)'::regprocedure) as crear,
    pg_get_functiondef('public.fn_fdi_compra_editar(bigint,text,date,text,numeric,jsonb,jsonb,text)'::regprocedure) as editar,
    pg_get_functiondef('public.fn_fdi_compra_vincular_recepcion(bigint,bigint,jsonb,boolean,numeric,numeric,numeric,text)'::regprocedure) as vincular,
    pg_get_functiondef('public.fn_fdi_compra_repartir_aterrizaje(bigint,numeric)'::regprocedure) as repartir,
    pg_get_functiondef('public.fn_actualizar_precio_promedio_recepcion_v2_m01(bigint,jsonb)'::regprocedure) as v2,
    pg_get_functiondef('public.fn_fdi_compra_costo_resumen(bigint)'::regprocedure) as resumen,
    pg_get_functiondef('public.fn_fdi_compra_detalle(bigint)'::regprocedure) as detalle
)
select
  position('coalesce(p_tasa_factura, 1)' in crear) > 0 as crear_es_el_viejo,
  position('''valor''' in editar) > 0 as editar_es_el_viejo,
  position('v_monto := round(v_base * v_pct / 100, 2) - v_reemb' in vincular) > 0 as vincular_es_el_viejo,
  position('origen_pago = ''fondo''' in repartir) > 0 as repartir_es_el_viejo,
  position('v_costo.monto_usd' in v2) > 0 as v2_es_el_viejo,
  position('sum(r.base_importadora)' in resumen) > 0 as resumen_es_el_viejo,
  position('to_jsonb(r)' in detalle) > 0 as detalle_es_el_viejo,
  not exists (
    select 1 from information_schema.columns
     where table_schema='public' and table_name='app_cont_tipo_costo' and column_name='id_tienda'
  ) as falta_id_tienda
from f;
```

Si algún campo sale `false`, **detente**: main ya tiene una versión distinta y hay que comparar antes
de reemplazar cuerpos.

---

## 2. Scripts, en orden

| # | Archivo | Qué deja |
|---|---|---|
| 1 | [`10_costos_tienda.sql`](../../../ventiq_admin_app/lib/sql/compra/10_costos_tienda.sql) | `id_tienda` en `app_cont_tipo_costo`, índice por ámbito y RPC de conceptos con rol por tienda |
| 2 | [`11_importadora_bruto.sql`](../../../ventiq_admin_app/lib/sql/compra/11_importadora_bruto.sql) | `monto_bruto_importadora` generada (neto + reembolso) |
| 3 | [`12_compra_contrato.sql`](../../../ventiq_admin_app/lib/sql/compra/12_compra_contrato.sql) | factura obligatoria, tasa de la tienda, ajustes por cantidad y origen por modo |
| 4 | [`13a_vincular_recepcion.sql`](../../../ventiq_admin_app/lib/sql/compra/13a_vincular_recepcion.sql) | base = valor recibido, `monto_valorizado`, líneas atribuidas, sin origen «fondo» |
| 5 | [`13b_repartir_aterrizaje.sql`](../../../ventiq_admin_app/lib/sql/compra/13b_repartir_aterrizaje.sql) | importadora por valor + ajustes por cantidad, `monto_usd` total |
| 6 | [`13c_precio_promedio_unidad.sql`](../../../ventiq_admin_app/lib/sql/compra/13c_precio_promedio_unidad.sql) | `_v2` divide el total entre la cantidad (costo unitario real) |
| 7 | [`13d_costo_resumen.sql`](../../../ventiq_admin_app/lib/sql/compra/13d_costo_resumen.sql) | resumen sin doble conteo + precio de venta, costo CUP y conceptos por línea |
| 8 | [`13e_detalle_valor_recibido.sql`](../../../ventiq_admin_app/lib/sql/compra/13e_detalle_valor_recibido.sql) | `valor_recibido` en el detalle de la compra |
| 9 | [`13f_ajuste_tardio_cantidad.sql`](../../../ventiq_admin_app/lib/sql/compra/13f_ajuste_tardio_cantidad.sql) | el ajuste posterior también reparte por cantidad |
| 10 | [`14_diagnostico_costos.sql`](../../../ventiq_admin_app/lib/sql/compra/14_diagnostico_costos.sql) | vista de comparación (solo lectura) |
| 11 | [`15_reset_costo_producto.sql`](../../../ventiq_admin_app/lib/sql/compra/15_reset_costo_producto.sql) | reset manual con motivo e historial |

Rollbacks disponibles: `10_..._rollback.sql`, `11_..._rollback.sql`, `12_..._rollback.sql`,
`14_..._rollback.sql`, `15_..._rollback.sql`. **13a-13f no tienen rollback propio**: restauran desde el
respaldo de `bkp_20261127.funciones` si hiciera falta.

---

## 3. Post-check

```sql
-- a) Tasa de la tienda (cambia el id por una tienda real de main)
select public.fn_fdi_tasa_cup_por_usd_tienda(1) as cup_por_usd;

-- b) El concepto por tienda quedó
select column_name from information_schema.columns
 where table_schema='public' and table_name='app_cont_tipo_costo' and column_name='id_tienda';

-- c) La columna generada quedó
select is_generated from information_schema.columns
 where table_schema='public' and table_name='fdi_dat_compra_recepcion'
   and column_name='monto_bruto_importadora';

-- d) Los tres cuerpos nuevos se aplicaron
select
  position('El número de factura es obligatorio'
           in pg_get_functiondef('public.fn_fdi_compra_crear(bigint,bigint,text,date,text,numeric,jsonb,jsonb,text,text,text,uuid)'::regprocedure)) > 0 as factura,
  position('fn_fdi_tasa_cup_por_usd_tienda'
           in pg_get_functiondef('public.fn_fdi_compra_crear(bigint,bigint,text,date,text,numeric,jsonb,jsonb,text,text,text,uuid)'::regprocedure)) > 0 as tasa,
  position('v_unit'
           in pg_get_functiondef('public.fn_actualizar_precio_promedio_recepcion_v2_m01(bigint,jsonb)'::regprocedure)) > 0 as v2_unidad;
```

También están las verificaciones completas:
`verify/10_costos_tienda.sql` (7), `verify/11_importadora.sql` (4), `verify/12_compra_contrato.sql` (7).

---

## 4. Después de aplicar

1. **Desplegar** la app de admin con los cambios de UI (factura, tasa bloqueada, reserva en el alta,
   costos extra en recepción, margen CUP). El backend nuevo no rompe la app vieja salvo por la factura
   obligatoria: una compra sin factura empezará a rechazarse con `22023`.
2. Probar **una compra CUP** (debe tomar la tasa de la tienda sin escribirla) y **una recepción** con
   transporte. Las recepciones históricas no cambian.
3. Si algún producto quedó con un costo promedio absurdo, usar «Reiniciar costo promedio» en su detalle
   (RPC de la 15). No se ejecuta solo.

**La compra 80 no se toca en main.** Esa reparación ya se hizo en `newa` y no tiene equivalente allí.
