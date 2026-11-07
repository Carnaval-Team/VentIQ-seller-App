# Recon: contabilización en `ventiq_admin_app` y administración de monedas en `ventiq_superadmin`

- **Autor:** recon-admin (teammate de task-3)
- **Fecha:** 2026-11-04
- **Alcance:** solo lectura de `ventiq_admin_app/` y `ventiq_superadmin/`, más SQL de apoyo del repo para verificar DDL/RLS. No se ejecutó ninguna escritura salvo este archivo.
- **Clases de evidencia usadas** (igual que en `docs/plan-multimoneda/recon-esquema.md`):
  - `[DART]` evidencia directa en código Dart del repo (archivo:línea).
  - `[DDL-REPO]` DDL existente en un `.sql` del repo.
  - `[INFER]` inferencia a partir de embeds PostgREST/Dart, no de un DDL.
  - `[NO ENCONTRADO]` búsqueda negativa explícita (se indica dónde se buscó).

> **Regla de separación aplicada en todo el documento:** módulo **TPV/ventas** (lo relevante) ≠ módulo **Carnaval/comercio electrónico** ≠ **suscripciones** (`app_suscripciones_plan` ya tiene columna `moneda`) ≠ **paquetería/referidos/otros**. Cada vez que aparece `moneda`/`totalUsd` se indica a qué subsistema pertenece.

---

## 0. Resumen ejecutivo (10 líneas)

1. **TPV/ventas:** la app admin no tiene concepto de moneda en sus pantallas de venta; todos los totales se muestran con `$` sin código de moneda y todos los agregados vienen de **RPC SQL** (`fn_reporte_ventas_*`, `fn_reporte_ventas_ganancias`, `fn_listar_turnos_admin`, etc.).
2. La moneda **sí existe** en el modelo de datos del TPV, pero **del lado del vendedor** (`app_dat_pago_venta.moneda/tasa_usd/monto_cup_equivalente` y `app_dat_caja_turno.efectivo_*_usd`, añadidas por `ventiq_app/sql/venta_usd.sql:1-9`). El admin **no lee ninguna de esas columnas**.
3. La app admin **ya lee `public.monedas`** (catálogo global de monedas, DDL en `VentiQ.sql:1195-1204`) pero **solo en modo lectura/display** (`currency_display_service.dart:14,186`; `inventory_ipv_report_screen.dart:135,142`).
4. La app admin **escribe** dos catálogos de moneda propios de módulo: `dep_nom_moneda` (depósitos) y `prv_nom_moneda` (pago a proveedores); y **actualiza** `tasas_conversion` (¡global!) desde `currency_service.dart:292-330`.
5. Existen **4 catálogos de moneda distintos** en el ecosistema (`monedas`, `tipos_moneda`, `dep_nom_moneda`, `prv_nom_moneda`) + el par de tasas (`tasas_conversion` global, `tasa_cambio_extraoficial` por tienda).
6. La app superadmin **no lee ni escribe `public.monedas` hoy** (`[NO ENCONTRADO]` en todo `ventiq_superadmin/lib`), y **no tiene pantalla de monedas**. Solo lee `tasas_conversion` en 2 servicios para conversiones USD.
7. La app superadmin sí tiene un **patrón CRUD claro y reutilizable** (pantalla + `AlertDialog` + `Supabase.instance.client` directo, o pantalla + `*Service`), con `RouteGuard`/`AppRoutes`/`AppDrawer` y permisos por rol (`app_dat_superadmin_roles.permisos` = lista de rutas).
8. RLS: el repo trae el helper `public.fn_is_superadmin_full_access()` y políticas de ejemplo (`ventiq_superadmin/database/superadmin_roles.sql:48-120`); **no hay políticas en el repo para `monedas` ni `tasas_conversion`** (`[NO ENCONTRADO]`).
9. **Hallazgo de seguridad crítico:** ambas apps compilan con la clave `SERVICE_ROLE` de Supabase en release (`supabase_config.dart:9-16` en admin y superadmin). En release **se salta RLS por completo**; en debug (rama `newa`) se usa `anon` y RLS sí aplica.
10. El único reporte/export del admin con desglose por moneda es el **IPV** (`inventory_ipv_report_screen.dart`, selector CUP/USD); el resto (ventas, turnos, contabilidad, PDFs/Excel) es CUP implícito.

---

## A1) Pantallas y servicios de ventas, totales, cierres de caja, reportes y contabilidad (`ventiq_admin_app`)

Rutas registradas en `ventiq_admin_app/lib/main.dart` (fuente de verdad de navegación):
`/dashboard` y `/dashboard-web` (`main.dart:210,212`), `/sales` (`:221`), `/tpv-prices` (`:222`), `/tpv-management` (`:223`), `/financial*` (`:240-244`), `/pago-proveedores-monedas` (`:293`), `/depositos-monedas` (`:297`), `/carnaval-orders` (`:279`).

### A1.1 Ventas / TPV

| Pantalla | archivo:línea | Servicio → RPC | Qué muestra | Moneda |
|---|---|---|---|---|
| `SalesScreen` (Ventas) | `screens/sales_screen.dart:34` | `SalesService` | 6 solapas: tiempo real (`:2164`), TPVs (`:2197`), proveedores (`:2357`), desglose de ventas (`:2579`), analítica (`:3377`), analista IA (`:3391`) | `$` sin código; CUP implícito |
| Tarjetas "Ventas"/"Productos" | `screens/sales_screen.dart:4390-4469` (`'\$${totalSales...}'` en `:4417`) | `SalesService.getSalesMetrics` (`sales_service.dart:701`) → RPC `fn_reporte_ventas_ganancias` (`:738-741`) | total ventas + nº productos | CUP implícito |
| Tabla "TPVs" | `screens/sales_screen.dart:2197` + `_buildVendorCard` `:5792` | `SalesService.getSalesVendorReportByTurno` (`:1861` / `sales_service.dart:1007`) → RPC `fn_reporte_ventas_por_turno` (`sales_service.dart:1033-1036`) | efectivo/transferencia/total por turno | CUP implícito |
| Aviso de tasa | `screens/sales_screen.dart:2116` `_buildMissingExchangeRateWarning` + `:1817` `hasUsdToCupRate` | `sales_service.dart:386-415` (`tasa_cambio_extraoficial` + `tasas_conversion`) | avisa si falta tasa USD→CUP | única mención conceptual de moneda en ventas |
| Gestión TPV / Turnos de caja | `screens/tpv_management_screen.dart:6` importa `widgets/tpv_managements/caja_turnos.dart`; clase `CajaTurnosTabView` `:16` | `CajaTurnoService.listTurnos` (`caja_turnos.dart:188`) → RPC `fn_listar_turnos_admin` (`caja_turno_service.dart:120-123`), fallback PostgREST `:146-199` | ventas totales, ticket promedio, pagos, efectivo/digital, egresos, conciliación (`caja_turnos.dart:1027-1032,1585`) | CUP implícito; no existe columna moneda |
| Precios por TPV | `screens/tpv_prices_screen.dart` + `services/tpv_price_service.dart` | tablas `app_dat_producto_precio_venta` (modelo `models/tpv_price.dart:6`) | `precio_venta_cup` por TPV | solo CUP |

### A1.2 Dashboards / KPIs

| Pantalla | archivo:línea | Servicio → RPC |
|---|---|---|
| `DashboardScreen` | `screens/dashboard_screen.dart:179,192` | `DashboardService.validateSupervisorStore` + `getStoreAnalysis` (`dashboard_service.dart:69-87`) → RPC `fn_dashboard_analisis_tienda` (`:77-79`) |
| `DashboardWebScreen` | `screens/dashboard_web_screen.dart:81,90` | idem |
| `InventoryDashboard` | `screens/inventory_dashboard.dart:47,76` | `getCompleteStoreAnalysis` (`dashboard_service.dart:90-160`; internamente `getMainKPIs`, `_getSupplierDashboardMetrics` → `fn_dashboard_proveedores` `dashboard_service.dart:376-379`, `_getTopSuppliersForPeriod` → `fn_top_proveedores` `:503-506`) + `SalesService.getProductSalesWithSupplier` (`sales_service.dart:1212` → `fn_reporte_ventas_con_proveedor2` `:1234`) |
| Compras del mes (USD/CUP) | `dashboard_service.dart:196-285` | lectura directa `app_dat_operaciones` + `app_dat_operacion_recepcion(moneda_factura, tasa_cambio_aplicada)` + `app_dat_recepcion_productos`, suma en Dart y devuelve `{total_cup, total_usd}` (`:277-285`) |

### A1.3 Contabilidad / finanzas

| Pantalla | archivo:línea | Servicio |
|---|---|---|
| `FinancialScreen` | `screens/financial_screen.dart` | `services/financial_service.dart` (CRUD gastos, categorías, centros de costo, márgenes; `:20`…`:2758`) |
| `FinancialDashboardScreen` | `screens/financial_dashboard_screen.dart:14` | `FinancialDashboardService` → RPCs `fn_profit_and_loss` (`financial_dashboard_service.dart:21`), `fn_sales_metrics` (`:83`), `fn_inventory_metrics` (`:152`), `fn_product_profitability` (`:173`), `fn_category_profitability` (`:193`), `fn_cash_flow_projections` (`:256`), `fn_historical_trends` (`:275`) |
| `FinancialReportsScreen` | `screens/financial_reports_screen.dart:14` | `FinancialReportsService` → `fn_profitability_report` (`financial_reports_service.dart:27`), `fn_category_profitability_analysis` (`:55`), `fn_low_profitability_products` (`:80`), `fn_historical_cash_flow` (`:136`), `fn_historical_comparison` (`:254`), `fn_trend_analysis` (`:280`), `fn_budget_variance_analysis` (`:328`) |
| Gastos | `screens/financial_expenses_screen.dart` | `financial_service.dart` |
| Configuración contable | `screens/financial_configuration_screen.dart`, `financial_setup_screen.dart`, `financial_activity_history_screen.dart` | `financial_service.dart` (`:1322` `initializeFinancialSystem`, etc.) |
| Contadores de operaciones pendientes | `financial_service.dart:2613-2619` y `:2725-2731` | RPC `fn_count_pending_operations_optimized` |

**Ninguno de estos archivos menciona `moneda`, `USD`, `currency`** (búsqueda A3; ver anexo). La contabilidad es CUP implícita.

### A1.4 Consignación / liquidaciones (ventas por convenio, no TPV)

| Pantalla | archivo:línea | Servicio / tabla |
|---|---|---|
| `LiquidacionesListScreen` | `screens/liquidaciones_list_screen.dart` (carga `:40`; totales `:44`; confirmar `:236`; rechazar `:331`; cancelar `:382`) | `LiquidacionService` (`services/liquidacion_service.dart`) |
| Crear liquidación | `liquidacion_service.dart:11-62` | INSERT `app_dat_liquidacion_consignacion` con `monto_cup`, `monto_usd`, `tasa_cambio` (`:38-50`); calcula `montoUsd = montoCup / tasa` en Dart (`:31`) |
| Confirmar / rechazar | `liquidacion_service.dart:108-115` / `:138-145` | RPC `fn_confirmar_liquidacion` / `fn_rechazar_liquidacion` |
| Totales de contrato | `liquidacion_service.dart:174-218` | lee `app_dat_contrato_consignacion.monto_total` + `app_dat_liquidacion_consignacion.monto_usd` y **suma en Dart** (`:194-198`) |
| Detalle contrato | `screens/detalle_contrato_consignacion_screen.dart:105` | `LiquidacionService.obtenerTotalesContrato` |
| Detalle operación de venta (consignación) | `screens/detalle_operacion_venta_screen.dart:41,48` | lee `app_dat_operaciones` + `app_dat_extraccion_productos`; suma en Dart (`:194-199`) y muestra **`'$… USD'` hardcodeado** (`:318`) |
| UI de liquidaciones | `liquidaciones_list_screen.dart:108,151-186,537-556,607-609,703,721,737` | muestra `monto_usd`/`monto_cup`/`tasa_cambio` explícitamente (es el único flujo del admin con doble importe) |

> **Ojo:** `detalle_operacion_venta_screen.dart` se llama "operación de venta" pero carga `app_dat_extraccion_productos` y lo usa el módulo de consignación; **no es el TPV**.

### A1.5 Servicios del admin que tocan ventas/pagos/contabilidad

- `services/sales_service.dart` (1389 líneas, todo por RPC; ver A2).
- `services/caja_turno_service.dart` (turnos, RPC + fallback PostgREST).
- `services/dashboard_service.dart` (dashboard + compras).
- `services/financial_service.dart`, `financial_dashboard_service.dart`, `financial_reports_service.dart`.
- `services/liquidacion_service.dart`.
- `services/analytics_service.dart` (7 RPCs en `:94,296,390,599,629,659,687`).
- `services/products_analytics_service.dart` (márgenes; convierte USD→CUP con `tasas_conversion` en `:600-603`).
- `services/export_service.dart`, `services/caja_turno_pdf_service.dart` (reportes/PDF).

---

## A2) ¿Dónde se calculan/suman los montos: Dart o SQL?

**Regla general del admin: los importes de venta vienen agregados por SQL; Dart solo suma lo que ya llega agregado y hace conversiones de presentación.** No hay una capa de "moneda" en esa agregación.

### A2.1 Sumas hechas en Dart (pocas y localizadas)

| Qué | archivo:línea | Detalle |
|---|---|---|
| Total de ventas del tab "tiempo real" | `sales_service.dart:753-781` | itera filas de `fn_reporte_ventas_ganancias` y acumula `ingresos_totales` en `totalSales` |
| Totales de liquidación de consignación | `liquidacion_service.dart:194-209` | `totalLiquidaciones += monto_usd` |
| Egresos por vendedor | `sales_service.dart:1147-1174` | suma `montoEntrega` de entregas |
| Compras del mes CUP/USD | `dashboard_service.dart:241-261` | `cantidad*precio_unitario`, y convierte con `tasa_cambio_aplicada` según `moneda_factura` |
| Efectivo esperado del turno (fallback) | `models/caja_turno.dart:308-313` | `efectivo_inicial + totalEfectivo - totalEgresos` |
| Subtotales USD de la factura de operación de inventario | `screens/inventory_operations_screen.dart:5482-5526` | `subCup / usdRate` |

### A2.2 Agregación en SQL (RPC) — inventario de RPC usadas por el admin en el dominio ventas/caja

| RPC | Llamada en admin | Devuelve moneda? |
|---|---|---|
| `fn_reporte_ventas_ganancias` | `sales_service.dart:738-741` | no (CUP) |
| `fn_reporte_ventas_con_proveedor5` / `_por_turno_v2` / `_precios_actuales` (nombre dinámico) | `sales_service.dart:454-489` | no (CUP; `valor_usd` es **costo** histórico USD, no moneda de venta) |
| `fn_reporte_ventas_con_proveedor_por_turno` (fallback) | `sales_service.dart:482-485` | no |
| `fn_reporte_ventas_con_proveedor2` | `sales_service.dart:1234-1237` | no |
| `fn_reporte_ventas_proveedor` | `sales_service.dart:1194-1197` | no |
| `fn_reporte_ventas_por_vendedor_sch` | `sales_service.dart:970-973` | no |
| `fn_reporte_ventas_por_turno` | `sales_service.dart:1033-1036` (SQL local: `lib/sql/fn_reporte_ventas_por_turno.sql`) | no: grep `usd/moneda` → 0 |
| `fn_reporte_cronologico_producto` | `sales_service.dart:576-579` | no |
| `fn_ordenes_producto_proveedor` | `sales_service.dart:1351-1354` | no |
| `listar_ordenes` | `sales_service.dart:1098` | sí devuelve pagos pero el modelo no los usa para moneda (ver A3) |
| `fn_listar_entregas_por_fechas_usuario` | `sales_service.dart:890-893` | no |
| `fn_listar_turnos_admin` | `caja_turno_service.dart:120-123` (SQL doc: `docs/migrations/fn_listar_turnos_admin.sql:66,181`) | **no**: campos `ventas_totales`, `total_efectivo`, `total_digital`, `total_egresos`; grep `moneda|usd` en ese SQL → 0 |
| `fn_dashboard_analisis_tienda` | `dashboard_service.dart:77-80` | no |
| `fn_dashboard_proveedores`, `fn_top_proveedores` | `dashboard_service.dart:376-379`, `:503-506` | no |
| `fn_confirmar_liquidacion`, `fn_rechazar_liquidacion` | `liquidacion_service.dart:108,138` | n/a (escribe estado) |
| `fn_profit_and_loss`, `fn_sales_metrics`, `fn_inventory_metrics`, `fn_product_profitability`, `fn_category_profitability`, `fn_cash_flow_projections`, `fn_historical_trends` | `financial_dashboard_service.dart:21,83,152,173,193,256,275` | no |
| `fn_*_report/analysis/comparison/budget` (7) | `financial_reports_service.dart:27,55,80,136,254,280,328` | no |
| `fn_count_pending_operations_optimized` | `financial_service.dart:2613,2725` | no |
| 7 RPC de analítica | `analytics_service.dart:94,296,390,599,629,659,687` | no |
| `fn_vista_precios_productos3` | `sales_service.dart:832-835` | no |

### A2.3 Tablas leídas directamente (PostgREST) en el dominio ventas/caja

| Tabla | archivo:línea | Uso |
|---|---|---|
| `app_dat_operacion_venta` + embed `app_dat_pago_venta(monto, app_nom_medio_pago)` | `sales_service.dart:593-598` | solo para **etiquetar método de pago** en el histórico; **no selecciona `moneda`, `tasa_usd` ni `monto_cup_equivalente`** |
| `app_dat_caja_turno` (+ `app_dat_tpv`, `app_dat_vendedor`, `app_nom_estado_operacion`) | `caja_turno_service.dart:149-161` | fallback si la RPC no existe; selecciona `efectivo_inicial/esperado/real/diferencia`, **no** las columnas `*_usd` |
| `app_dat_operaciones` | `detalle_operacion_venta_screen.dart:41`, `dashboard_service.dart:205-229` | detalle/compras |
| `app_dat_extraccion_productos` | `detalle_operacion_venta_screen.dart:48` | detalle consignación |
| `app_dat_liquidacion_consignacion`, `app_dat_contrato_consignacion` | `liquidacion_service.dart:77-79,180-190` | liquidaciones |
| Vistas SQL (`.from('v_…')`) | solo `v_bitacora_capitan` (`carnaval_service.dart:1745,1786`, **Carnaval**) y `v_consignacion_envios` (`consignacion_envio_service.dart:808,828`, **consignación**) | **NINGUNA vista de ventas/TPV**; los agregados TPV son RPC (búsqueda `from('v_` en admin → 4 matches, todos de otros módulos) |

---

## A3) ¿Existe hoy concepto de moneda en el admin? (mapa completo, por subsistema)

### A3.1 Catálogos de moneda que la app admin usa

| # | Tabla | DDL / evidencia | Quién la usa en admin | Escritura desde admin |
|---|---|---|---|---|
| 1 | `public.monedas` (`codigo` PK, `nombre`, `simbolo`, `pais`, `activo`) | `[DDL-REPO]` `VentiQ.sql:1195-1204` | `currency_display_service.dart:14-19` (dropdowns) y `:184-192`; `inventory_ipv_report_screen.dart:135,142`; `widgets/currency_converter_widget.dart:56-67` | **solo lectura** (grep `from('monedas')` en admin → 4 selects, 0 insert/update) |
| 2 | `public.tipos_moneda` (`id`, `denominacion`, `simbolo`, `nombre_corto`, `pais`, `activo`) | `[INFER]` `personal_rates_service.dart:9-15`; DDL `[NO ENCONTRADO]` en `*.sql` | `personal_rates_service.dart:11` (selector de moneda origen de tasas de tienda) | lectura |
| 3 | `public.tasas_conversion` (`moneda_origen`→`monedas.codigo`, `moneda_destino`→`monedas.codigo`, `tasa`) | `[DDL-REPO]` `VentiQ.sql:1205-1214` | `currency_service.dart:123-129` (timeline), `:539-544` (lectura), `:317-323` (**UPDATE global**); `sales_service.dart:407-414`; `inventory_export_dialog.dart:213-216`; `products_analytics_service.dart:600-603`; `inventory_ipv_report_screen.dart:165-168` | **UPDATE** `tasas_conversion` desde `currency_service.dart:292-330` |
| 4 | `public.tasa_cambio_extraoficial` (por tienda: `id_tienda`, `id_moneda_origen`, `id_moneda_destino`, `valor_cambio`, `usar_precio_toque`, `activo`, `created_at`) | `[INFER]` `personal_rates_service.dart:19-41` (embed FK), `currency_service.dart:22-32`; DDL `[NO ENCONTRADO]` en `*.sql` | `currency_service.dart:24,113-129`; `personal_rates_service.dart`; `sales_service.dart:395-405`; `inventory_export_dialog.dart:202-211` | **CRUD completo**: `personal_rates_service.dart:100-125` (crear), `:129-167` (versionar), `:170-175` (desactivar) |
| 5 | `public.dep_nom_moneda` (`id`, `codigo` UNIQUE, `denominacion`, `simbolo`, `activo`) | `[DDL-REPO]` `lib/sql/depositos_bancarios_schema.sql:14-30` | `depositos_bancarios_service.dart:18-82`; pantalla `screens/depositos_bancarios/monedas_depositos_screen.dart` | **CRUD completo** (`depositos_bancarios_service.dart:34-82`) |
| 6 | `public.prv_nom_moneda` (`id`, `codigo` UNIQUE, `denominacion`, `simbolo`, `activo`) | `[DDL-REPO]` `lib/sql/pago_proveedores_schema.sql:13-29` | `pago_proveedores_service.dart:97-149`; pantalla `screens/pago_proveedores/monedas_proveedores_screen.dart` | **CRUD completo** (`pago_proveedores_service.dart:113-149`) |

Pantallas de gestión de moneda **existentes** en admin: `/pago-proveedores-monedas` (`main.dart:293-294`) y `/depositos-monedas` (`main.dart:297`). Son catálogos **por módulo**, no el catálogo global.

### A3.2 Moneda dentro del flujo de precios/recepción de la tienda (no es "moneda de venta")

- **Precio dual del producto:** `Product.precioVenta` y opcional `Product.precioVentaUsd` (`models/product.dart:33,66,192`); en BD `app_dat_precio_venta.precio_venta_cup/precio_venta_usd` (`[DDL-REPO]` `VentiQ.sql:347,352`).
- **Recepción (compras) con moneda de factura:** `app_dat_operacion_recepcion.moneda_factura DEFAULT 'USD'` (`[DDL-REPO]` `VentiQ.sql:393`), `tasa_cambio_aplicada`/`fecha_tasa_aplicada` (`:396-397`); RPC de recepción valida `'USD'|'EUR'|'CUP'` (`lib/sql/02_lotes_recepcion_rpc.sql:84-90`) y escribe la moneda (`:116-119`). UI: `reception_edit_dialog.dart:40,68,709-722`, `reception_total_widget.dart:115-190,235`, `inventory_reception_screen.dart:450,916`, `product_quantity_dialog.dart:429-442` (payload `moneda_precio`), `excel_import_screen.dart:45,1148-1315`.
- **Selector de moneda de venta por tienda (flag):** `mostrar_selector_moneda` en `app_dat_configuracion_tienda` (`store_config_service.dart:88,244-246`; UI `widgets/global_config_tab_view.dart:716-741,1853-1863`, texto "El cajero puede seleccionar la moneda (CUP/USD) en cada venta" `:732`).
- **Tasas "personales"/por tienda:** pestaña `Tasas pers.` en Ajustes (`screens/settings_screen.dart:202`), `PersonalRatesTabView(canEdit: …)` (`:220`, widget `widgets/personal_rates_tab_view.dart:6-11`), servicio `personal_rates_service.dart`.
- **Tickets/impresión en moneda distinta sin tocar el registro:** `inventory_extractionbysale_screen.dart:61,1793-1808,1938,2564` ("Moneda del ticket (USD…/CUP…)", "no afectan el registro").

### A3.3 Moneda en el PAGO del TPV: existe en BD, el admin la ignora

- Columnas añadidas en vivo por `ventiq_app/sql/venta_usd.sql:1-4` (`app_dat_pago_venta.moneda TEXT NOT NULL DEFAULT 'CUP'`, `tasa_usd`, `monto_cup_equivalente`) y check `moneda IN ('CUP','USD')` (`:16-19`).
- Columnas de caja en USD: `app_dat_caja_turno.efectivo_inicial_usd/efectivo_real_usd/diferencia_usd` (`venta_usd.sql:6-9`).
- **El admin no las lee:** `sales_service.dart:593-598` selecciona solo `monto` y método de pago; `caja_turno_service.dart:149-161` no selecciona `*_usd`; el modelo `CajaTurno` no tiene campos USD (grep `usd` en `models/caja_turno.dart` → 0); la RPC del admin (`docs/migrations/fn_listar_turnos_admin.sql`) no devuelve USD.
- Consecuencia: **los totales del admin son CUP** y no hay desglose por moneda aunque el TPV ya registre pagos USD.

### A3.4 Carnaval / comercio electrónico (NO es TPV, NO confundir)

- `order['moneda']`, `order['totalUsd']`, `order['totalEuro']` son columnas de **pedidos Carnaval**: `screens/carnaval_orders_screen.dart:1639-1641,2149-2164`; `widgets/carnaval_order_detail_sheet.dart:1600-1627`.
- En superadmin: `carnaval_dashboard_service.dart:84-94` ("9: Dinero por moneda"), `:279` (`id, created_at, total, status, metodo_pago, moneda, totalUsd, totalEuro, user_id`), `screens/carnaval_dashboard_screen.dart:576,956`.
- En SQL del repo: `lib/sql/fn_cancelar_orden_carnaval_v2.sql:33,59,98,109`; `lib/sql/registrar_orden_paqueteria.sql:259-264` y `_v2.sql:229-234` (**paquetería**, otro subsistema).
- Pago a Inventtia / referidos usan `moneda`+`totalUsd`+`totalEuro` de **pedidos Carnaval/referidos**: `inventtia_payment_service.dart:118-164`, `referral_payments_service.dart:80,108-125`, `referral_payment_model`/`referral_pdf_service.dart:264-270,369`.
- **Estas columnas no existen en `app_dat_operacion_venta` ni en `app_dat_pago_venta` como `totalUsd/totalEuro`** (DDL `VentiQ.sql:401-425` y `1098-1116`).

### A3.5 Suscripciones (ya tiene moneda; no tocar en este plan)

- `app_suscripciones_plan.moneda text NOT NULL DEFAULT 'USD'` (`[DDL-REPO]` `VentiQ.sql:1155`).
- Superadmin la edita con lista **hardcodeada** (`flow_planes_screen.dart:465,994-1004`) y advierte que "el cobro real es en CUP" (`planes_ui.dart:222-239,778-780`; `flow_planes_screen.dart:1011`).

---

## A4) Modelos Dart monetarios del admin

| Modelo | archivo:línea | Campos monetarios | Moneda |
|---|---|---|---|
| `Sale` | `models/sales.dart:1-60` | `subtotal`, `discount`, `tax`, `total` (`:12-15`) | **ninguna**; y el modelo **no se usa para leer datos reales**: `Sale.fromJson`/`SaleItem` solo se referencian dentro del propio archivo (grep → `models/sales.dart` únicamente; `promotion_validator.dart:210` es otra cosa) |
| `SaleItem` | `models/sales.dart:62-98` | `unitPrice`, `totalPrice` | ninguna |
| `CashDelivery` | `models/sales.dart:144-180` | `montoEntrega` (`monto_entrega`) | ninguna |
| `SalesVendorReport` | `models/sales.dart:182-323` | `totalDineroEfectivo`, `totalDineroTransferencia`, `totalDineroGeneral`, `totalImporteVentas`, `totalEgresos` (`:189-196`) | ninguna; mapea RPC (`:253-277`) |
| `CajaTurno` | `models/caja_turno.dart:205-435` | `efectivoInicial`, `efectivoEsperado*`, `efectivoReal`, `diferencia*`, `ventasTotales`, `ticketPromedio`, `totalPagos`, `totalEfectivo`, `totalDigital`, `totalEgresos` (`:212-235`), getters (`:434-566`) | ninguna (CUP implícito); **no tiene** `*_usd` que sí existen en BD |
| `CurrencyRate` / `CurrencyRatesResponse` | `models/currency_rate.dart:1-106` | `value` por moneda; trío fijo USD/EUR/MLC (`:33-74`) + fallbacks 420/470/60 (`:55,61,67`) y 440/495/210 (`:84,90,96`) | USD/EUR/MLC→CUP |
| `MonedaDeposito` | `models/depositos_bancarios.dart:1-89` | `codigo`, `denominacion`, `simbolo`, `activo`; embed `moneda(codigo,denominacion,simbolo)` (`:69-78`) | catálogo `dep_nom_moneda` |
| `MonedaPago` | `models/pago_proveedores.dart:307-380` | `codigo`, `simbolo`, `denominacion`; embed `moneda(id_moneda)` (`:367-375`) | catálogo `prv_nom_moneda` |
| `Product` | `models/product.dart:33,66,192` | `precioVenta` (CUP) + `precioVentaUsd` opcional | dual CUP/USD de catálogo |
| `TpvPrice` | `models/tpv_price.dart:6,43` | `precioVentaCup` | solo CUP |

**Conclusión A4:** no existe ningún modelo de venta/pago del admin con dimensión moneda; los importes son `double` sin unidad. Agregar multimoneda requiere cambios de modelo (o al menos de contrato con las RPC) y no solo de UI.

---

## A5) Reportes y exportaciones donde faltaría desglose por moneda

| Export / reporte | archivo:línea | Moneda hoy | Qué habría que añadir |
|---|---|---|---|
| Reporte ventas por producto (PDF) | `screens/sales_screen.dart:4508-4616`; usa `precioVentaCup`, `ingresosReportados`, `costoReportado` | CUP (redondea precios) | columna moneda y `equiv` por moneda |
| Reporte ventas por producto (Excel) | `screens/sales_screen.dart:4617-4722` | CUP | idem |
| Órdenes por vendedor (PDF) | `screens/sales_screen.dart:517-916` | CUP | idem |
| Histórico producto PDF/Excel | `screens/sales_screen.dart:4770-4867` / `:4868-4959` | CUP | idem |
| Reporte proveedor detalle PDF/Excel | `screens/sales_screen.dart:9920-10283` / `:10284-10474` | CUP | idem |
| Reporte proveedor resumen PDF/Excel | `screens/sales_screen.dart:10475-10724` / `:10725-10823` | CUP | idem |
| **Cierre de turno / caja PDF** | `services/caja_turno_pdf_service.dart` (23 KB) | grep `moneda|USD|CUP|currency` → **0** | ni siquiera declara moneda; añadir desglose CUP/USD del turno |
| **Oferta comercial PDF** | `services/export_service.dart:46,527` con `currencyCode` (`:51,66,531,619,698,702,755`); UI `inventory_extractionbysale_screen.dart:885` (`['CUP','USD','EUR','MLC']`), `:959-1012` | **único export que ya parametriza moneda** (texto "Moneda: X") | convertirlo en multi-moneda real (hoy solo etiqueta) |
| Factura de operación de inventario | `export_service.dart:3896-4230`; columnas `subtotal_cup`/`subtotal_usd` (`:3887,4013-4050,4217-4219`); origen `inventory_operations_screen.dart:5340,5482-5526` | CUP+USD por columnas | generalizar a N monedas |
| Reporte **IPV** PDF/Excel/email | `screens/inventory_ipv_report_screen.dart:26,38,130-168,378-404,956,1184,1223,1280-1383` | selector `Moneda.cup/usd` | único reporte operativo con conmutador de moneda; hoy solo 2 |
| Reportes contables/financieros | `screens/financial_reports_screen.dart`, `financial_dashboard_screen.dart` | CUP (sin `moneda`) | definir si el plan multimoneda toca contabilidad (hoy no) |
| Export Carnaval | `export_service.dart:3419` (`exportCarnavalOrders`) | Carnaval (totalUsd/totalEuro) | **fuera de alcance TPV** |
| Reportes superadmin con moneda | `referral_pdf_service.dart:264-270`, `carnaval_dashboard_screen.dart:956`, `pago_proveedores_screen.dart:627-649`, `referral_payments_screen.dart:706-718,914-918` | listas/tarjetas CUP/USD/EUR | fuera del alcance TPV; sirven de referencia de UX |

**Riesgo transversal:** al no existir `moneda` en los contratos de las RPC de ventas, cualquier desglose por moneda exige **cambiar SQL** (RPC/vistas), no solo el PDF.

---

## B6) Estructura de `ventiq_superadmin` y patrón CRUD reutilizable

### B6.1 Organización

```
ventiq_superadmin/lib/
  config/   (6: app_routes.dart, supabase_config.dart, app_colors, app_theme, gemini_config)
  models/   (20: tienda.dart, catalog_store.dart, superadmin.dart, superadmin_role.dart, fidelidad.dart, …)
  screens/  (55 archivos; + screens/muevete/ 11)
  services/ (38 archivos)
  utils/    (2)
  widgets/  (9: app_drawer.dart, route_guard.dart, planes_ui.dart, …)
  main.dart (13 KB)
```
Evidencia: listado de `lib/` (glob/pwsh sobre `ventiq_superadmin/lib`); `pubspec.yaml:1-8` (`ventiq_superadmin`, `1.0.0+1`, `sdk ^3.7.0`).

### B6.2 Registro de una pantalla nueva (3 puntos obligatorios)

1. **Ruta:** `main.dart:91-316` — cada pantalla se registra en `routes:` envuelta en `RouteGuard(route: '/x', child: XScreen())` (ej. `/configuracion` en `main.dart:136-139`, `/almacenes` en `:118-120`).
2. **Permiso:** `config/app_routes.dart:21-205` — entrada `AppRoute(route:'/x', label:'…', group:'…')`; grupos existentes: Tiendas, Licencias, Usuarios, Operaciones, Muévete, Carnaval, Marketing, Flow, Aplicaciones, Sistema.
3. **Menú:** `widgets/app_drawer.dart:20-321` — sección + `_DrawerItem(title, route)`; hay un `if` de rutas con badge/estado en `:452-484` (no hace falta tocar si la ruta no está en esa lista).

Nota: `/almacenes`, `/tpvs`, `/consignacion`, `/ingresos-distribucion`, `/carnaval-geo` existen en `main.dart` (`:118,121,141,245,265`) pero **no** están en `AppRoutes.protected`; el guard las deja pasar solo por el fallback legacy (`auth_service.dart:250`: nivel 1 sin rol → acceso total). Si se quiere permiso explícito para "Monedas", hay que añadir la ruta a `AppRoutes.protected`.

### B6.3 Patrón CRUD **recomendado** (catálogo global simple): `configuracion_screen.dart` (planes)

| Paso | archivo:línea | Cómo |
|---|---|---|
| Estado + carga | `screens/configuracion_screen.dart:14-29,82-103` | `List<Map<String,dynamic>> _planes`; `_loadPlanes()` → `_supabase.from('app_suscripciones_plan').select().order('id')` |
| Crear | `:105-224` | `showDialog` + `AlertDialog` con `TextEditingController` por campo; al guardar `insert` directo (`:193-201`) + `_loadPlanes()` + `SnackBar` (`:203-209`) |
| Editar | `:226-345` | mismo diálogo prefillado; `update` (`:315-322`) + reload |
| Borrar | `:347-387` | diálogo de confirmación; `delete().eq('id', plan['id'])` (`:361`) |
| Listado | `:462-533` (desktop `DataTable`) y `:535-591` (móvil `ExpansionTile`) | `PlatformUtils.shouldUseDesktopLayout` (`:392`) |
| Botón alta en AppBar | `:394-405` | `IconButton(Icons.add)` |

- **No usa service**: la pantalla habla con Supabase directamente. Para un catálogo pequeño ("Monedas") este es el patrón más rápido y ya probado.
- **Patrón con service (catálogo más grande):** `screens/flow_categorias_screen.dart:6` importa `services/categoria_admin_service.dart`; llama `CategoriaAdminService.taxonomia()` (`:48`), `.guardar(...)` (`:807`), `.alternar(...)` (`:103`), `.eliminar(...)` (`:152`); el service está en `services/categoria_admin_service.dart:20`.
- **Anti-patrón a NO copiar:** `screens/almacenes_screen.dart` tiene la lista/filtros completos pero **crear/editar/eliminar son stubs** "Funcionalidad … en desarrollo" (`:553-567`, `:600-614`, `:616-641`).

### B6.4 Modelo de datos

Los servicios/pantallas trabajan mayoritariamente con `Map<String,dynamic>` crudo (p. ej. `configuracion_screen.dart:90-93`). Cuando hay modelo, el patrón es clase inmutable + `fromJson` (+ `copyWith`): `models/catalog_store.dart:1-96`. Para `monedas` basta `Map` (como planes) o un `Currency` con `codigo/nombre/simbolo/pais/activo`.

### B6.5 Captura/análisis con MCP Dart (restricción B8 del enunciado)

- `mcp__dart__roots add file:///C:/Users/cesar/Documents/VentIQ-seller-App/ventiq_superadmin` → `Success`.
- `mcp__dart__analyze_files` **proyecto completo** → **`Error: Request timed out`** (no devolvió diagnósticos; ~10 min de espera).
- Reintento **acotado** a rutas concretas → **`No errors`** para `lib/main.dart`, `lib/screens/flow_planes_screen.dart`, `lib/screens/configuracion_screen.dart`, `lib/screens/almacenes_screen.dart`, `lib/widgets/app_drawer.dart`.
- Conclusión: no hay evidencia de errores en los archivos que usa un CRUD de monedas; **el resto de la app no quedó analizado** (limitación de tiempo del MCP). No se usó `flutter analyze` por shell.

---

## B7) Listas de monedas hardcodeadas y campos `moneda` en formularios

### B7.1 Superadmin (todas las ocurrencias accionables)

| archivo:línea | Contenido | Subsistema |
|---|---|---|
| `screens/flow_planes_screen.dart:465` | `static const List<String> _monedas = ['USD','CUP','EUR','MLC'];` | Suscripciones Flow |
| `screens/flow_planes_screen.dart:481,523-524,713,994-1004` | `late String _moneda`; default `USD` si no está en la lista; `DropdownButtonFormField(initialValue: _moneda)` con `for (final m in _monedas)`; se guarda `moneda: _moneda` (`:713`) | Suscripciones Flow |
| `screens/flow_planes_screen.dart:272,1011` | avisos "plan activo con precio 0 en la moneda del cobro" / "La tarifa va en la moneda elegida; el cobro real, siempre en CUP." | Suscripciones Flow |
| `widgets/planes_ui.dart:174-177` | `monedaDePlan()` → `plan['moneda']` o `'USD'` | Suscripciones Flow |
| `widgets/planes_ui.dart:222-239,726-780` | avisos de tarifa vs cobro CUP | Suscripciones Flow |
| `widgets/suscripcion_ui.dart:112-115` | `formatearMoneda(monto, moneda)` default `'CUP'`; `if (mon == 'USD') …` | Suscripciones |
| `screens/flow_config_screen.dart:37,102,145,431` | `_moneda` controller; `moneda_default` (default `'CUP'`) en jsonb de config (`:145`) | Suscripciones Flow |
| `screens/flow_suscripcion_detalle_screen.dart:109,625` | muestra `pago['moneda']` default `'CUP'` | Suscripciones Flow |
| `screens/fidelidad_screen.dart:1227,1250,1293-1327,1434` y `:1523,1544,1586-1625,1716` | `TextEditingController _moneda` default `'USD'` (reglas y beneficios) — **campo libre de texto**, no dropdown | Marketing/Fidelidad |
| `models/fidelidad.dart:20,113,200` | `String? moneda` en Regla/Beneficio/Movimiento | Marketing/Fidelidad |
| `screens/pago_proveedores_screen.dart:627-649,794` | tarjetas/labels `'CUP'`, `'USD'`, `'EUR'` hardcodeadas | Pago a proveedores (Carnaval/tiendas) |
| `screens/referral_payments_screen.dart:706-718,845,914-918` | filtros y totales `'CUP'`,`'USD'`,`'EUR'` | Referidos |
| `services/referral_payments_service.dart:112-125` | normaliza `moneda` (`CUP`/`USD`/`EUR`/`EURO`) | Referidos |
| `services/referral_pdf_service.dart:264-270,369` | totales CUP/USD/EUR | Referidos |
| `screens/muevete/muevete_cargas_screen.dart:270-271` | `carga['moneda'] ?? 'USD'` | Muévete |
| `services/inventtia_payment_service.dart:133-164`, `screens/pago_inventtia_screen.dart:787-825` | `switch (order.moneda)` `USD`/`EUR` | Pago a Inventtia |
| `services/ingresos_service.dart:11-24` | `tasas_conversion` USD→CUP con fallback `440.0` | Ingresos/distribución |
| `services/inventtia_payment_service.dart:12-37` | USD de `tasas_conversion`; **EUR de `carnavalapp.configuraciones_admin.valor_euro`** | Pago a Inventtia |

### B7.2 Admin (para el plan multimoneda, no para el superadmin)

| archivo:línea | Contenido |
|---|---|
| `screens/inventory_extractionbysale_screen.dart:885` | `const currencies = <String>['CUP','USD','EUR','MLC'];` |
| `widgets/product_quantity_dialog.dart:991` | `...['USD','CUP'].map(...)` (selector modo mixto) |
| `widgets/reception_edit_dialog.dart:714` | `items: ['USD','CUP'].map(...)` |
| `models/currency_rate.dart:54-70,84-96` | trío USD/EUR/MLC + fallbacks numéricos |
| `services/currency_service.dart:355,369` | parseo ElToque `tasas['USD']`, `tasas['ECU']`(→EUR), `tasas['MLC']` |
| `services/currency_display_service.dart:23-27,196-217` | fallback de monedas **hardcodeado** si falla `monedas` |
| `screens/detalle_operacion_venta_screen.dart:318` | `'… USD'` fijo |
| `services/dashboard_service.dart:19` (ingresos) y `financial_*` | sin moneda (CUP implícito) |

**Conclusión B7:** la lista `['USD','CUP','EUR','MLC']` está duplicada al menos en `flow_planes_screen.dart:465` y `inventory_extractionbysale_screen.dart:885`, y hay defaults `'USD'`/`'CUP'` dispersos. Una pantalla "Monedas" en superadmin debería alimentar esos dropdowns (sobre todo el de planes) y retirar los `static const`.

---

## B8) ¿Existe pantalla/servicio que lea o escriba `monedas` o `tasas_conversion`?

### B8.1 En `ventiq_superadmin` — **NO ENCONTRADO para `monedas`**

Búsquedas realizadas (grep con `include:*.dart` sobre `ventiq_superadmin/lib`):
- `monedas` → **0 coincidencias** (solo aparecen `moneda`/`monedas` como variable local en Flow/Fidelidad/Muévete, nunca la tabla).
- `tasas_conversion` → 2 coincidencias, **solo lectura**:
  - `services/inventtia_payment_service.dart:20-27` → `from('tasas_conversion').select('tasa').eq('moneda_origen','USD')`;
  - `services/ingresos_service.dart:10-16` → `from('tasas_conversion').select('tasa').eq('moneda_origen','USD')`.
- `tasa_cambio_extraoficial` → **0 coincidencias**.
- `tipos_moneda` → **0 coincidencias**.
- `moneda_default` → `flow_config_screen.dart:102,145` (jsonb de configuración Flow, no tabla de monedas).

**Respuesta explícita:** hoy **no existe en superadmin ninguna pantalla ni servicio CRUD de `public.monedas` ni de `public.tasas_conversion`**; tampoco hay pantalla "Monedas". Lo único que hay son dos lecturas puntuales de la tasa USD y una lista hardcodeada en planes.

### B8.2 En `ventiq_admin_app` — sí hay acceso

- `public.monedas`: **solo SELECT**, 4 llamadas (`currency_display_service.dart:14,186`; `inventory_ipv_report_screen.dart:135,142`).
- `public.tasas_conversion`: SELECT en `currency_service.dart:540`, `sales_service.dart:407`, `inventory_export_dialog.dart:213`, `products_analytics_service.dart:600`, `inventory_ipv_report_screen.dart:165`; **UPDATE** en `currency_service.dart:317-323` (bucle de `updateExchangeRatesInDatabase`, `:292-309`). Nota: ese UPDATE filtra solo por `moneda_origen` y podría tocar varias filas si hubiera más de una por origen.
- `public.tasa_cambio_extraoficial`: SELECT/INSERT/UPDATE en `currency_service.dart`, `personal_rates_service.dart` (CRUD), `sales_service.dart:395`, `inventory_export_dialog.dart:202`.
- `dep_nom_moneda` y `prv_nom_moneda`: CRUD completo (A3.1).

### B8.3 DDL y RLS en el repo

- DDL de `monedas`/`tasas_conversion`: `[DDL-REPO]` `VentiQ.sql:1195-1214` (con FKs de `tasas_conversion` a `monedas(codigo)`).
- DDL de `tipos_moneda` y `tasa_cambio_extraoficial`: `[NO ENCONTRADO]` en `*.sql` del repo (grep `tipos_moneda` en `*.sql` → 0 DDL; grep `CREATE TABLE … tasa_cambio_extraoficial` → 0). Su forma se infiere de `[INFER]` `personal_rates_service.dart:19-41` y `currency_service.dart:22-32`.
- Políticas RLS de `monedas`/`tasas_conversion`: `[NO ENCONTRADO]` (grep `POLICY.*(monedas|tasas_conversion|tasa_cambio_extraoficial)` en `*.sql` → 0). **No se puede afirmar desde el repo si un usuario `authenticated` puede escribir `monedas`.**
- Políticas RLS de los catálogos de módulo: **permisivas para todo autenticado**:
  - `dep_nom_moneda`: `lib/sql/depositos_bancarios_schema.sql:406,418-419` → `FOR ALL TO authenticated USING (TRUE) WITH CHECK (TRUE)`.
  - `prv_nom_moneda`: `lib/sql/pago_proveedores_schema.sql:198,209-210` → idem.
- Patrón de RLS "superadmin puede escribir" ya existente: helper `public.fn_is_superadmin_full_access()` (`ventiq_superadmin/database/superadmin_roles.sql:48-63`) usado por políticas `superadmin_roles_write_full_access` (`:77-83`) y `superadmin_*_full_access` de `app_dat_superadmin` (`:100-120`). **Ese helper es el candidato natural para una política de escritura de `monedas`.**

---

## B9) Selección de tienda y permisos del superadmin (¿puede escribir catálogos globales?)

### B9.1 El superadmin es global: no hay "tienda actual"

- No existe store-context persistido tipo `StoreSelectorService` (el admin sí lo tiene: `ventiq_admin_app/lib/services/store_selector_service.dart`). En superadmin cada pantalla lista tiendas y filtra con dropdown local:
  - `screens/almacenes_screen.dart:21,34-37,132-137,217-237`
  - `screens/tpvs_screen.dart:27,169-184,292-306`
  - `screens/administradores_screen.dart:21,99,199-213`; `trabajadores_screen.dart:23,210-211`; `movimientos_screen.dart:25,92-112`; `licencias_screen.dart:2731,2861,2906`; `carnaval_store_products_screen.dart:28,64`.
- Consecuencia para "Monedas": **un catálogo global no necesita selector de tienda**; encaja en la sección "Sistema" (junto a Configuración/Roles) o "Licencias". Lo único que hay que definir es el alcance tienda-vs-global de `tasas_conversion`/`tasa_cambio_extraoficial`.

### B9.2 Autenticación y permisos

- Login: `services/auth_service.dart:23-102`; exige fila en **`app_dat_superadmin`** (`activo=true`, `uuid=auth.uid()`), si no → "No tienes permisos de superadministrador" (`:41-56`).
- Rol: `app_dat_superadmin_roles` (`services/superadmin_role_service.dart:7-95`); `permisos` es un **jsonb con lista de rutas** (`database/superadmin_roles.sql:8`; `auth_service.dart:242-253`).
- Niveles: `nivelAcceso` 1..3 con `hasFullAccess()==1` y `canWrite()<=2` / `canRead()<=3` (`auth_service.dart:227-237`).
- Enrutado: `RouteGuard` bloquea si `!AuthService.canAccessRoute(route)` (`widgets/route_guard.dart:19-19`), con "Acceso denegado" (`:21-53`).
- Gating de UI: `AuthService.canWrite()` en `colecciones_screen.dart:168`, `home_banners_screen.dart:126,218-224`, `patrocinados_screen.dart:151`; `hasFullAccess()` en `fidelidad_screen.dart:308` y `home_banners_screen.dart:79`.
- **Un CRUD de "Monedas" debería ir en `AppRoutes.protected` y gatearse con `canWrite()`** (igual que banners/colecciones), no solo con el nivel legado.

### B9.3 ¿Puede el superadmin escribir catálogos globales hoy?

- **En debug (`newa`):** usa la clave `anon` (`config/supabase_config.dart:5-7`), por tanto **depende de RLS**. Como no hay políticas en el repo para `monedas`/`tasas_conversion`, **no verificable desde el repo** (`[NO ENCONTRADO]`); habría que mirar la BD (el MCP Supabase de esta sesión no tiene conectividad).
- **En release (main):** **sí, sin restricción de RLS**, porque la constante `_releaseAnonKey` (`config/supabase_config.dart:9-12`) es en realidad un JWT con `"role":"service_role"` (payload visible en el propio token; mismo patrón en `ventiq_admin_app/lib/config/supabase_config.dart:11-12`).
  - **Riesgo crítico:** ambas apps distribuyen la *service role key* en el cliente. Cualquiera puede extraerla del APK y saltarse RLS en toda la base. No se reproduce la clave aquí a propósito.
  - Efecto colateral para este plan: **en release cualquier pantalla del superadmin puede escribir `monedas` sin política nueva**; en debug no. Cualquier diseño debe asumir que **el control real de escritura tiene que ser RLS**, no la UI.

---

## C) Huecos, riesgos y preguntas abiertas

### C.1 Huecos funcionales (lo que falta para "crear monedas desde el superadmin")

1. **No hay pantalla ni servicio de `monedas` en superadmin** (B8.1). Hay que crearla: ruta en `main.dart`, entrada en `AppRoutes.protected`, ítem en `AppDrawer`, pantalla con el patrón `configuracion_screen.dart` (B6.3).
2. **No hay modelo** `Moneda` en `ventiq_superadmin/lib/models/`; hoy todo es `Map<String,dynamic>` (basta para el CRUD).
3. **No hay CRUD de `tasas_conversion` en superadmin**: la única escritura global la hace el **admin** (`currency_service.dart:317-323`) y la única UI de tasas es de **solo lectura** (`exchange_rates_screen.dart:6`, "Pantalla para visualizar tasas de cambio (solo lectura)").
4. **`exchange_rates_screen.dart` no está registrada en `main.dart`** ni importada por ninguna pantalla (grep `ExchangeRatesScreen` → solo su propio archivo): **código muerto** hoy.
5. **Cuatro catálogos de moneda** (`monedas`, `tipos_moneda`, `dep_nom_moneda`, `prv_nom_moneda`) sin sincronización. Crear una moneda nueva en `monedas` **no** la hace aparecer en:
   - tasas por tienda (`tipos_moneda`, `personal_rates_service.dart:11`) → no se podrá definir tasa para ella;
   - depósitos (`dep_nom_moneda`) ni pago a proveedores (`prv_nom_moneda`).
6. **`tasas_conversion` está cableada a los 3 códigos del trío**: `CurrencyRatesResponse` es USD/EUR/MLC fijo (`models/currency_rate.dart:33-105`) y `currency_service.dart:579-590` busca solo USD/EUR/MLC → una moneda nueva no se refresca ni se muestra en el convertidor (`currency_converter_widget.dart` sí es genérico, pero la lista de tasas no).
7. **El admin de ventas no puede desglosar por moneda** porque las RPC no devuelven moneda (A2.2) y sus modelos no la tienen (A4). El dato existe en `app_dat_pago_venta.moneda` (A3.3) pero nadie lo agrega.
8. **`fn_listar_turnos_admin` / `CajaTurno` ignoran el USD del turno** (columnas `*_usd` en BD, no leídas). Los cierres de caja del admin quedarán incompletos si el TPV cobra en USD.
9. **`dynamic`/hardcodes de moneda** en superadmin (B7.1) impiden que una moneda nueva aparezca en Flow, Fidelidad, Referidos, Muévete, Pago a Inventtia.

### C.2 Riesgos técnicos

1. **RLS desconocido en `monedas`/`tasas_conversion`** (no en el repo, sin conectividad al proyecto): hay que verificarlo antes de asumir que "el superadmin podrá escribir". Mitigación ya existente: política con `public.fn_is_superadmin_full_access()` (`superadmin_roles.sql:48-83`).
2. **`service_role` en el cliente** (C.1 → B9.3): cualquier endurecimiento de RLS es cosmético en release hasta rotar esa clave y separar configuración por rol. **Esto debería ser un prerrequisito del plan multimoneda** si se va a escribir catálogo global.
3. **Escritura global desde una app de tienda:** hoy un usuario de tienda puede `UPDATE` `tasas_conversion` (`currency_service.dart:317-323`), lo que permite a una tienda alterar la tasa global de todas. Al abrir un CRUD de monedas/tasas en superadmin, conviene **quitar** esa escritura del admin o restringirla por RLS.
4. **`tipos_moneda`/`tasa_cambio_extraoficial` sin DDL en el repo** → cambios de esquema no reproducibles; el plan debería versionar su DDL.
5. **Inconsistencia `moneda_precio`** del payload de recepción (`product_quantity_dialog.dart:440`): no se encontró columna `moneda_precio` en `*.sql` (`[NO ENCONTRADO]`); confirmar si se persiste o es solo cliente.
6. **Doble fuente de tasa para EUR:** `tasa_cambio_extraoficial`/`tasas_conversion` vs `carnavalapp.configuraciones_admin.valor_euro` (`inventtia_payment_service.dart:12-18`). Unificar criterio.

### C.3 Preguntas abiertas (para el lead / plan)

1. ¿El catálogo canónico del plan es **`public.monedas`** (el que ya lee el admin) o hay que converger los 4 catálogos? ¿Se deprecan `tipos_moneda`/`dep_nom_moneda`/`prv_nom_moneda` o se les añade FK a `monedas(codigo)`?
2. ¿La pantalla "Monedas" del superadmin debe gestionar también **tasas** (`tasas_conversion` global) y/o **tasas por tienda** (`tasa_cambio_extraoficial`), o solo el catálogo?
3. `monedas.codigo` es `character` (bpchar) y PK natural (`VentiQ.sql:1196,1203`): ¿se acepta PK textual (ISO-4217) para las nuevas monedas? ¿`pais`/`simbolo` obligatorios?
4. ¿`monedas` necesita `orden`, `decimales`, `es_predeterminada`? Hoy no existen (`VentiQ.sql:1195-1204`).
5. Para el admin: ¿el objetivo es **mostrar** el desglose por moneda (cambiar RPC + modelos) o solo **capturarla** en tienda (ya está en `app_dat_pago_venta`)? Sin decisión no se puede dimensionar A5.
6. ¿Se corrige el flag `mostrar_selector_moneda` (`global_config_tab_view.dart:1853-1863`) para que dependa del catálogo (p.ej. lista de monedas habilitadas por tienda) en lugar de CUP/USD binario?
7. ¿Se rota la clave `service_role` y se separan builds por rol antes o después de este plan? (bloqueante de seguridad).

---

## Anexo A — Búsquedas negativas explícitas (`NO ENCONTRADO`)

| Búsqueda | Ámbito | Resultado |
|---|---|---|
| `monedas` (tabla) en Dart | `ventiq_superadmin/lib/**/*.dart` | **0 coincidencias** |
| `tasa_cambio_extraoficial`, `tipos_moneda` en Dart | `ventiq_superadmin/lib/**/*.dart` | **0 coincidencias** |
| `from('monedas')` con `insert`/`update` | `ventiq_admin_app/lib/**/*.dart` | **0**: solo SELECT (4) |
| `POLICY … monedas|tasas_conversion|tasa_cambio_extraoficial` | `**/*.sql` (repo) | **0 coincidencias** |
| `CREATE TABLE … tipos_moneda` / `… tasa_cambio_extraoficial` | `**/*.sql` (repo) | **0 coincidencias** (solo inferencia Dart) |
| `moneda_precio` (columna) | `**/*.sql` (repo) | **0 coincidencias** (sí en payload Dart) |
| Columna `moneda` / `totalUsd` en `app_dat_operacion_venta` | `VentiQ.sql:401-425` | **no existe** (solo `importe_total`, `precio_con_descuento_total`) |
| Columna `moneda` / `totalUsd` en `app_dat_pago_venta` (dump) | `VentiQ.sql:1098-1116` | **no está en el dump**; la añade `ventiq_app/sql/venta_usd.sql:1-4` |
| Vistas SQL (`.from('v_…')`) de ventas/TPV en admin | `ventiq_admin_app/lib/**/*.dart` | **0**: solo `v_bitacora_capitan` (Carnaval) y `v_consignacion_envios` (consignación) |
| Pantalla `Monedas` en superadmin | `ventiq_superadmin/lib/screens/` + `main.dart` | **no existe** |
| `exchange_rates_screen.dart` referenciada | `ventiq_admin_app/lib/**/*.dart` | **no**: solo su propio archivo → código muerto |
| `flutter analyze` por shell | — | **no ejecutado** (política de la tarea: usar MCP Dart) |
| MCP Dart `analyze_files` proyecto completo superadmin | `mcp__dart__` | **`Request timed out`** (ver B6.5) |
| MCP Supabase | — | **no usado** (sin conectividad, indicado en el enunciado) |

### Anexo B — Comandos/herramientas usadas

- `grep` del harness (no `rg`/`find` de shell) con `include:*.dart` / `*.sql` sobre `ventiq_admin_app/lib`, `ventiq_superadmin/lib`, `VentiQ.sql`, `ventiq_app/sql`, `docs/plan-multimoneda/`.
- `read` con `offset/limit` para los archivos grandes (`sales_screen.dart`, `sales_service.dart`, `export_service.dart`, etc.).
- `pwsh Get-ChildItem` solo para inventariar directorios/archivos y tamaños.
- `mcp__dart__roots add` + `mcp__dart__analyze_files` (resultado en B6.5).
- No se modificó ningún archivo salvo este documento.