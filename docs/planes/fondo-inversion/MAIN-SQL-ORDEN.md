# SQL para main — orden exacto

**Proyecto main:** `vsieeihstajlrdvpuooh` · **2026-11-27**
Aplicar de arriba a abajo. Cada script aborta si no encuentra su ancla: si uno falla, **no sigas**.
No hay migración de datos: la compra 80 es de `newa` y no existe en main.

---

## 0. Respaldo

```sql
create schema if not exists bkp_20261127;

create table bkp_20261127.app_cont_tipo_costo              as select * from public.app_cont_tipo_costo;
create table bkp_20261127.fdi_dat_compra_recepcion         as select * from public.fdi_dat_compra_recepcion;
create table bkp_20261127.fdi_dat_compra_recepcion_linea   as select * from public.fdi_dat_compra_recepcion_linea;
create table bkp_20261127.app_dat_recepcion_producto_costo as select * from public.app_dat_recepcion_producto_costo;
create table bkp_20261127.app_dat_producto_presentacion    as select id, id_producto, precio_promedio from public.app_dat_producto_presentacion;
create table bkp_20261127.app_dat_producto_costo           as select * from public.app_dat_producto_costo;

create table bkp_20261127.funciones as
  select p.proname, pg_get_function_identity_arguments(p.oid) as args, pg_get_functiondef(p.oid) as def
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in (
       'fn_fdi_compra_crear','fn_fdi_compra_editar','fn_fdi_compra_vincular_recepcion',
       'fn_fdi_compra_repartir_aterrizaje','fn_fdi_compra_recepcion_bases',
       'fn_fdi_compra_costo_resumen','fn_fdi_compra_detalle',
       'fn_actualizar_precio_promedio_recepcion_v2_m01',
       'fn_fdi_compra_ajuste_agregar','fn_fdi_compra_ajuste_financiar',
       'fn_cont_tipo_costo_guardar','fn_cont_tipo_costo_eliminar',
       'fn_listar_operaciones_inventario_new'
     );
```

---

## 1. Orden de scripts

| # | Script | Rollback |
|---|---|---|
| 1 | [`10_costos_tienda.sql`](../../../ventiq_admin_app/lib/sql/compra/10_costos_tienda.sql) | `10_..._rollback.sql` |
| 2 | [`11_importadora_bruto.sql`](../../../ventiq_admin_app/lib/sql/compra/11_importadora_bruto.sql) | `11_..._rollback.sql` |
| 3 | [`12_compra_contrato.sql`](../../../ventiq_admin_app/lib/sql/compra/12_compra_contrato.sql) | `12_..._rollback.sql` |
| 4 | [`13a_vincular_recepcion.sql`](../../../ventiq_admin_app/lib/sql/compra/13a_vincular_recepcion.sql) | desde `bkp.funciones` |
| 5 | [`13b_repartir_aterrizaje.sql`](../../../ventiq_admin_app/lib/sql/compra/13b_repartir_aterrizaje.sql) | desde `bkp.funciones` |
| 6 | [`13c_precio_promedio_unidad.sql`](../../../ventiq_admin_app/lib/sql/compra/13c_precio_promedio_unidad.sql) | desde `bkp.funciones` |
| 7 | [`13d_costo_resumen.sql`](../../../ventiq_admin_app/lib/sql/compra/13d_costo_resumen.sql) | desde `bkp.funciones` |
| 8 | [`13e_detalle_valor_recibido.sql`](../../../ventiq_admin_app/lib/sql/compra/13e_detalle_valor_recibido.sql) | desde `bkp.funciones` |
| 9 | [`13f_ajuste_tardio_cantidad.sql`](../../../ventiq_admin_app/lib/sql/compra/13f_ajuste_tardio_cantidad.sql) | desde `bkp.funciones` |
| 10 | [`14_diagnostico_costos.sql`](../../../ventiq_admin_app/lib/sql/compra/14_diagnostico_costos.sql) | `14_..._rollback.sql` |
| 11 | [`15_reset_costo_producto.sql`](../../../ventiq_admin_app/lib/sql/compra/15_reset_costo_producto.sql) | `15_..._rollback.sql` |
| 12 | [`17_operaciones_detalle_costo_real.sql`](../../../ventiq_admin_app/lib/sql/compra/17_operaciones_detalle_costo_real.sql) | `17_..._rollback.sql` |

`13c`, `13e` y `13f` son parches sobre la función viva: **se corren una vez**.
`13a`–`13f` no tienen rollback propio; se restauran desde `bkp_20261127.funciones`.

---

## 2. Cierre

```sql
notify pgrst, 'reload schema';

select public.fn_fdi_tasa_cup_por_usd_tienda(1) as cup_por_usd;

select is_generated
  from information_schema.columns
 where table_schema = 'public'
   and table_name = 'fdi_dat_compra_recepcion'
   and column_name = 'monto_bruto_importadora';
```

Después: desplegar la app de admin. Sin ella, una compra sin factura empezará a rechazarse con `22023`.
