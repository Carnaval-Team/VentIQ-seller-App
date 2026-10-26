# Pase a Main — stack lotes + venta v3 + fixes

Todo esto ya está aplicado y probado en Newa. Ejecutar en el SQL Editor del
proyecto **Main** (`vsieeihstajlrdvpuooh`) en este orden. Si algún archivo
aborta con error de dependencia/anchor, NO continuar con los siguientes:
reportar el error para ajustar el parche a la definición que tenga Main.

Leyenda: [N] = nuevo objeto · [R] = reemplaza función viva (misma firma)

## Fase A — Lotes y vencimiento (`ventiq_admin_app/lib/sql/`)

| # | Archivo | Qué crea/modifica |
|---|---------|-------------------|
| A1 | `01_lotes_vencimiento_schema.sql` | `app_dat_lote` (+RLS), `ep.id_lote`, columnas de vencimiento |
| A2 | `02_lotes_recepcion_rpc.sql` | Recepción con lotes |
| A3 | `03_lotes_fases_2_3_ajuste.sql` | Ajustes por lote |
| A4 | `04_lotes_fefo_egresos.sql` | `fn_fefo_saldos_en_ubicacion` y egresos FEFO |
| A5 | `05_lotes_bulk_import.sql` | Importación masiva de lotes |
| A6 | `06_lotes_stock_sum_fefo.sql` | `fn_inventario_saldo_por_clave` + stock por lote |
| A7 | `07_lotes_stock_real_y_listados.sql` | Listados de stock con lote |
| A8 | `08_lotes_rebalanceo_egresos.sql` | Rebalanceo FEFO en egresos |
| A9 | `09_lotes_asignar_sin_lote.sql` | Asignar lote a stock "Sin lote" |
| A10 | `10_lotes_fefo_empaquetar.sql` | Empaquetar con FEFO |
| A11 | `11_lotes_extraccion_fefo_empaquetar.sql` | Extracción FEFO + empaquetado |
| A12 | `12_operaciones_con_presentacion.sql` | Presentación por línea en `fn_listar_operaciones_inventario_new` (firma de 12 params — coincide con Main) |
| A13 | `13_operaciones_importe_factor_rel.sql` | Importe con `factor_rel` en extracciones/transferencias |

## Fase B.0 — Guard seguro (`presentaciones_inventario/`)

Requisito previo de B1–B3: las funciones nuevas llaman a
`fn_check_user_has_access_to_tienda_safe`, que NO existe en Main.

| # | Archivo | Crea/modifica |
|---|---------|---------------|
| B0a | `45_guard_search_path.sql` | `fn_check_user_has_access_to_tienda_safe` — guard que califica las 7 tablas con `public.` y fija `search_path`. Solo agrega, idempotente. **Requerido por B1.** |
| B0b | `46_patch_guard_en_sitio.sql` | *(opcional pero recomendado)* Parchea `check_user_has_access_to_tienda` viva: califica tablas + fija `search_path`. Arregla el bug vivo 42P01 en `fn_registrar_venta_offline_v2/v3` que usa la app hoy (`auto_sync_service`). |

## Fase B — Cocina / venta v3 (`funcionalidad_cocina/`)

Requieren las funciones `_v2` de ingredientes que Main **ya tiene**
(`fn_descontar_ingredientes_elaborado_v2`, `fn_descontar_venta_enrutada_v2`,
`fn_ejecutar_entrega_fisica_v3`, `fn_cantidad_en_base`) **más B0a**. Todas crean
funciones NUEVAS `_v2`/`_v3`/`_v4` — no tocan las vivas.

| # | Archivo | Crea |
|---|---------|------|
| B1 | `33_ordenes_cocina_cantidad_en_base.sql` | `fn_pedir_item_cuenta_v2`, `fn_agregar_producto_orden_pendiente_v2`, `fn_actualizar_cantidad_producto_orden_v2` |
| B2 | `34_venta_v3_presentaciones.sql` | `fn_registrar_venta_v3`, `fn_registrar_venta_mesa_v3`, `fn_registrar_venta_offline_v4` — **OBLIGATORIO antes de C1/C2**; verificar que las 3 funciones existen tras correrlo |
| B3 | `35_devoluciones_presentacion.sql` | `fn_devolver_ingredientes_elaborado_v2`, `fn_cancelar_item_pedido_v2`, `fn_eliminar_producto_orden_v2` |

## Fase C — Fixes aplicados en Newa (`sql_updates/`)

| # | Archivo | Depende de |
|---|---------|------------|
| C1 | `fix_venta_v3_movimiento_inventario_duplicado.sql` | B2 (necesita las `venta_v3` creadas) |
| C2 | `fix_entrega_fisica_v3_saldos_por_lote.sql` | A4/A6/A8/A10/A11 (fn_fefo_*) **y C1** — el validador exige el parche de venta antes |
| C3 | `propagar_costo_presentaciones.sql` | `fn_presentaciones_producto` (ya en Main) |
| C4 | `fn_listar_operaciones_inventario_monto_exacto.sql` | A12/A13 — va después del parche de presentación para conservarlo |
| C5 | `fn_listar_ordenes_presentacion_item.sql` | `ep.id_presentacion` (ya en Main); aborta si los JOINs pp/np difieren |
| C6 | `restringir_extraccion_ajuste_negativo_maria.sql` | — (solo Main; reejecutar la versión que relee la fila) |

## Ya aplicado / descartado

- `add_mostrar_selector_moneda.sql` ✅
- `get_product_movements_v3_order_by_fecha.sql` ❌ (v3 sin consumidores; la app usa v4)

## Verificación posterior

1. Venta con producto por lotes en 2 presentaciones → `app_dat_inventario_productos` muestra consumo por lote correcto, sin fila duplicada.
2. Detalle de orden muestra Galón/Litro separados.
3. Tab Movimientos: presentación por línea, importe correcto, filtro de monto.
4. Recepción → `precio_promedio` en todas las presentaciones (`costo_base × factor_rel`); SELECT de verificación de C3 = 0 filas.
5. María: extracción/ajuste negativo → error; transferencia → OK.
