# 12 · Inventario de migraciones pendientes (`multimoneda` → `newa`)

Medido el 2026-11-20 en solo lectura contra `newa` = `qhprswhhfasrikhawjoz` (MCP `supabase-debug`)
y Main = `vsieeihstajlrdvpuooh` (MCP `supabase`).

**Método (la base manda, no los documentos).** Se cruzaron las llamadas `.rpc(` de
`ventiq_admin_app/lib/` (334 nombres; el escaneo debe ser multilínea o se pierde
`fn_fdi_registrar_recepcion`) y los 616 `CREATE FUNCTION` distintos de los 927 `.sql` del repo
contra `pg_proc`, `information_schema.columns`, `pg_constraint` y `pg_trigger` de ambas bases. Se
corrió además el semáforo del repo (`ventiq_admin_app/lib/sql/compra/verify/00_linea_base.sql`).

**Resultado.** Falta **una** migración de la rama en `newa`:
`fondo_inversion_financiar_recepcion.sql`. Las otras 42 RPC que el cliente llama y no existen
**tampoco están en Main**: son código muerto anterior a la rama, no deuda del pase.

---

## 1. RPC llamadas por el cliente que NO existen en `newa`

Verificadas también contra Main: **ninguna existe allí tampoco**.

| # | RPC | Cliente (`archivo:línea`) | Script que la crea | Gravedad |
|---|---|---|---|---|
| 1 | `fn_fdi_registrar_recepcion` | `services/inventory_service.dart:1379-1382` | `lib/sql/fondo_inversion_financiar_recepcion.sql:19` | **Crítica** |
| 2 | `get_categoria_mapeada` | `services/consignacion_categoria_service.dart:241` | `SQL_OPTIMIZATION/mapeo_categorias_consignacion.sql:33` | Alta |
| 3 | `get_productos_consignacion_sin_mapeo` | `services/consignacion_categoria_service.dart:21` | `…mapeo_categorias_consignacion.sql:65` | Alta |
| 4 | `get_productos_consignacion_para_venta` | `services/consignacion_categoria_service.dart:141` | `…mapeo_categorias_consignacion.sql:169` | Alta |
| 5 | `asignar_categoria_producto_consignacion` | `services/consignacion_categoria_service.dart:108` | `…mapeo_categorias_consignacion.sql:131` | Alta |
| 6 | `fn_crear_variante` | `services/variant_service.dart:671` | — | Media |
| 7 | `fn_listar_productos_por_atributo` | `services/variant_service.dart:279` | — | Media |
| 8 | `fn_listar_subcategorias_por_atributo` | `services/variant_service.dart:560` | — | Media |
| 9 | `fn_actualizar_producto` | `services/product_service.dart:1702` | — | Media |
| 10 | `fn_duplicar_producto` | `services/product_service.dart:1772` | — | Media |
| 11 | `fn_eliminar_producto_completo` | `services/product_service.dart:1807` | — | Media |
| 12 | `fn_duplicar_layout_almacen` | `services/warehouse_service.dart:860` | — | Media |
| 13 | `fn_eliminar_layout_almacen` | `services/warehouse_service.dart:830` | — | Media |
| 14 | `fn_actualizar_abc_layouts_masivo` | `services/warehouse_service.dart:900` | — | Media |
| 15 | `fn_actualizar_condiciones_layout` | `services/warehouse_service.dart:936` | — | Media |
| 16 | `fn_actualizar_limites_stock_almacen` | `services/warehouse_service.dart:973` | — | Media |
| 17 | `fn_crear_preorden_transferencia` | `services/transfer_service.dart:69` | — | Media |
| 18 | `fn_listar_preordenes_transferencia` | `services/transfer_service.dart:93` | — | Media |
| 19 | `fn_confirmar_preorden_transferencia` | `services/transfer_service.dart:111` | — | Media |
| 20 | `fn_ejecutar_operacion_transferencia` | `services/transfer_service.dart:131` | — | Media |
| 21 | `fn_cancelar_preorden_transferencia` | `services/transfer_service.dart:154` | — | Media |
| 22 | `fn_obtener_detalle_preorden_transferencia` | `services/transfer_service.dart:174` | — | Media |
| 23 | `fn_listar_productos_zona_variantes` | `services/transfer_service.dart:197` | — | Media |
| 24 | `fn_generar_codigo_promocion` | `services/promotion_service.dart:467` | — | Media |
| 25 | `fn_reporte_eficiencia_restaurante` | `services/restaurant_service.dart:873` | — | Media |
| 26 | `fn_profit_and_loss` | `services/financial_dashboard_service.dart:21` | — | Media |
| 27 | `fn_sales_metrics` | `services/financial_dashboard_service.dart:102` | — | Media |
| 28 | `fn_inventory_metrics` | `services/financial_dashboard_service.dart:167` | — | Media |
| 29 | `fn_product_profitability` | `services/financial_dashboard_service.dart:189` | — | Media |
| 30 | `fn_category_profitability` | `services/financial_dashboard_service.dart:209` | — | Media |
| 31 | `fn_cash_flow_projections` | `services/financial_dashboard_service.dart:272` | — | Media |
| 32 | `fn_historical_trends` | `services/financial_dashboard_service.dart:291` | — | Media |
| 33 | `fn_profitability_report` | `services/financial_reports_service.dart:32` | — | Media |
| 34 | `fn_category_profitability_analysis` | `services/financial_reports_service.dart:65` | — | Media |
| 35 | `fn_low_profitability_products` | `services/financial_reports_service.dart:90` | — | Media |
| 36 | `fn_historical_cash_flow` | `services/financial_reports_service.dart:165` | — | Media |
| 37 | `fn_historical_comparison` | `services/financial_reports_service.dart:288` | — | Media |
| 38 | `fn_trend_analysis` | `services/financial_reports_service.dart:319` | — | Media |
| 39 | `fn_budget_variance_analysis` | `services/financial_reports_service.dart:372` | — | Media |
| 40 | `fn_analytics_inventory_trends` | `services/analytics_service.dart:599` | — | Media |
| 41 | `fn_analytics_category_analysis` | `services/analytics_service.dart:629` | — | Media |
| 42 | `fn_analytics_rotation_report` | `services/analytics_service.dart:659` | — | Media |
| 43 | `fn_analytics_efficiency_report` | `services/analytics_service.dart:687` | — | Media |

**Baja, fuera de la tabla:** `fn_eliminar_almacenero` (`worker_service.dart:886`) y
`fn_obtener_almacen_almacenero` (`worker_service.dart:915`) los crea
`SQL_OPTIMIZATION/crear_tabla_almacenero.sql`, pero `newa` ya tiene el reemplazo
`fn_asignar_almacenero` / `fn_desasignar_almacenero`. Legado sustituido: **no aplicar**.

**Verificado:** las filas 6-43 no existen en ningún lado ni tienen script. `fn_crear_variante` no
tiene hermano cercano (solo `fn_eliminar_variante_subcategoria`); no hay **ninguna** función con
`preorden` ni `zona_variante`; de la familia BI solo existe `fn_analytics_inventory_metrics`.

---

## 2. Objetos de esquema pendientes

| Objeto | `newa` | Main | Script | ¿Aditivo? |
|---|---|---|---|---|
| `fn_fdi_registrar_recepcion(jsonb,jsonb,uuid)` | **falta** | falta | `fondo_inversion_financiar_recepcion.sql:19` | Sí (`CREATE OR REPLACE`) |
| `app_dat_operacion_recepcion`: `fdi_idempotency_key uuid`, `fdi_solicitud jsonb`, `idx_recepcion_fdi_idempotency` | **falta** | falta | ídem `:12-17` | Sí (`IF NOT EXISTS`) |
| `app_dat_producto_costo` | ok | **falta** | `sql_updates/costos_adicionales_producto.sql:17` | ya aplicado en `newa` |
| `app_dat_recepcion_producto_costo` | ok | **falta** | ídem `:87` | ya aplicado en `newa` |
| `trg_recepcion_productos_costo_real` + `trg_fn_…` | ok | **falta** | ídem | ya aplicado en `newa` |
| `app_dat_recepcion_productos.costo_real` no generada | ok (`NEVER`) | **falla** (`ALWAYS`) | ídem `:6` | ya aplicado en `newa` |
| `fdi_dat_movimiento.tipo` admite `'gasto'` | ok | **falta** | `fondo_inversion_gasto.sql` | ya aplicado en `newa` |
| `fn_fdi_gasto` (8 args) | ok | **falta** | ídem | ya aplicado en `newa` |
| `fn_fdi_crear_liquidacion` 11 args | ok (11) | **falla** (10) | `fondo_inversion_inversores.sql` | ya aplicado en `newa` |
| `app_v_precio_venta_vigente` / `_base_vigente` | ok | ok | `lib/sql/precio_venta_vigente.sql:3,14` | ya aplicado en ambos |
| `trg_convert_price_update_to_insert` | ok (con el fix) | — | `fix_trg_convert_price_update_to_insert.sql:18` | ya aplicado en `newa` |
| `fn_guardar_precio_venta_base` (3 args) | ok | ok | — | ya aplicado en ambos |
| Compensatorio recepción 4/5 (`RECEPCION_INVENTARIO_USADO`) | ok | **falta** | `sql_updates/fix_cambio_estado_operacion_mejorado_recepcion.sql:291` | ya aplicado en `newa` |
| `fn_fdi_validar_monto_reparto` | **falta** | falta | — (la define FDI) | sin dependientes: ningún `fn_fdi_*` vivo la llama |

**Corrección al encargo:** `app_dat_producto_costo`, `app_dat_recepcion_producto_costo`, el
trigger `trg_recepcion_productos_costo_real`, `costo_real` no generada y `fn_fdi_gasto` con el
tipo `'gasto'` **ya están en `newa`**. Son deuda de **Main** (`tasks/plan_sync_newa_main.md:24-25`
va en esa dirección), no de `newa`.

---

## 3. Orden de aplicación recomendado (en `newa`)

1. **`ventiq_admin_app/lib/sql/fondo_inversion_financiar_recepcion.sql`** — el único bloqueante. Su
   preflight (`:5-8`) exige `fn_registrar_recepcion_con_inventario` de 12 args y
   `fn_fdi_crear_inversion` de 7: **ambas ok en `newa`**, pasa tal cual. Crea columnas e índice
   antes de la función, en un solo `BEGIN/COMMIT`. Desbloquea `inventory_service.dart:1382`.
2. **`ventiq_admin_app/lib/sql/compra/verify/00_linea_base.sql`** — solo lectura, no migra. Tras (1)
   el chequeo 4 pasa de `falla` a `ok`; los otros 7 ya están `ok`/`info` en `newa`.
3. **Decisión, no aplicar a ciegas:** `SQL_OPTIMIZATION/mapeo_categorias_consignacion.sql` es el
   único script del repo con RPC que el cliente llama y la base no tiene (filas 2-5). No está en
   `newa` **ni en Main**: ese módulo nunca se desplegó. O se aplica en ambos, o se retira la
   pantalla; aplicarlo solo en `newa` crea deriva en sentido contrario.

Después de (1), lo abierto es el pase `main→newa` de `tasks/plan_sync_newa_main.md:103` (12 cuerpos
de Main), que no es de esta rama.

---

## 4. Riesgos

- **No es reversible por sí solo.** Hace `ADD COLUMN` y crea un índice único parcial; re-ejecutar
  es seguro (`IF NOT EXISTS`), pero las columnas quedan. El índice puede fallar si ya hubiera dos
  recepciones con la misma clave; hoy no hay ninguna, la columna no existe.
- **No recrea funciones de otro entorno.** Solo `fn_fdi_registrar_recepcion`, que no existe en
  ninguno. Colisión baja.
- **Choca con el pase `_m01` si se promueve mal.** El script usa nombres sin sufijo `_m01`; el pase
  renombra las funciones con cambio de contrato. `newa` tiene `fn_fdi_crear_liquidacion` de 11 args
  y Main de 10: **Main debe recibir la firma de 11 antes o junto con este script**, o el `_m01` se
  encuentra dos contratos vivos.
- **El aviso de `AGENTS.md` sobre `precio_venta` ya está cumplido en `newa`.** Sigue vigente para
  Main y entornos nuevos. No reaplicar a ciegas: redefinir el trigger durante tráfico activo cierra
  vigencias.
- **Los 42 RPC sin script no se arreglan con SQL.** Son pantallas que fallarán en runtime en
  cualquier entorno: hay que retirarlas o implementarlas.

---

## 5. Lo que ya está aplicado en `newa` (no reaplicar)

Semáforo `verify/00_linea_base.sql` corrido hoy en `newa`: **7 de 8 en `ok`/`info`, solo el
chequeo 4 en `falla`**.

- FDI completo: 15 tablas `fdi_*`, `'gasto'` en el CHECK, `fn_fdi_gasto` (8), `fn_fdi_crear_inversion`
  (7), `fn_fdi_vincular_recepcion` (6), `fn_fdi_desvincular_recepcion`, `fn_fdi_crear_liquidacion`
  (11), `fn_fdi_recalcular_inversion`, `fn_fdi_repartir_ganancia`.
- Costos: las 2 tablas, trigger `trg_recepcion_productos_costo_real`, `costo_real` en `NEVER`.
- Precio de venta: las 2 vistas, `fn_guardar_precio_venta_base`, y el trigger update→insert **con**
  el fix de `fecha_desde`/`NOW()`.
- `fn_registrar_cambio_estado_operacion_mejorado` **con** `RECEPCION_INVENTARIO_USADO`
  (`tasks/plan_sync_newa_main.md:100`); `fn_registrar_recepcion_con_inventario` con **una sola**
  firma de 12 args.
- M01: `fn_m01_*` presentes; tablas `app_dat_mesas`, `app_dat_mesa_cuenta_abierta`,
  `app_dat_produccion_tanda`, `dep_dat_deposito`, `paqueteria_ordenes`.

---

## Divergencias documento ↔ base (manda la base)

- **`tasks/hallazgos_pruebas_newa.md:13` (H2) está obsoleto.** Dice que `fn_listar_ordenes` en
  `newa` emite `'tipo_paago'` y que `fix_listar_ordenes_tipo_pago.sql` está pendiente. Consulta
  `SELECT proname FROM pg_proc WHERE prosrc ILIKE '%paago%'` → **0 filas en toda la base**; la
  única firma (11 args) emite `'tipo_pago'`. **Ese script no hace falta.**
- **`docs/plan-multimoneda/diagnostico_fase0.sql:135-136` no crea `fn_profit_and_loss` ni
  `fn_sales_metrics`**: son filtros `LIKE` de una consulta de diagnóstico, no fuente de migración.
- `tasks/plan_sync_newa_main.md:9` fija 1005 funciones públicas en `newa`: medido hoy, **1005**.

**Nada de este informe se aplicó: solo `SELECT` sobre `information_schema` / `pg_proc` /
`pg_trigger` / `pg_constraint` en ambas bases.**