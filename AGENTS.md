# Precios de venta

- El precio actual se resuelve por vigencia usando CURRENT_DATE del servidor y el ID mayor por producto/variante. NULL y 0 representan la variante base.
- Usar `app_v_precio_venta_vigente` para variantes y `app_v_precio_venta_base_vigente` para precios base. No sustituir consultas históricas por estas vistas.
- La edición base usa `fn_guardar_precio_venta_base`, con permisos de dueño/gerente/superadmin y bloqueo por producto. No reintroducir selección por created_at ni escrituras alternativas tras errores de permisos.
- Migraciones: primero `ventiq_admin_app/lib/sql/fix_trg_convert_price_update_to_insert.sql`, después `ventiq_admin_app/lib/sql/precio_venta_vigente.sql`. Deben aplicarse antes de desplegar el cliente que consume las vistas/RPC nuevas. No asumir que ya están instaladas en un proyecto remoto.
- `ventiq_admin_app/lib/sql/verificar_precio_venta_vigente.sql` contiene verificaciones de solo lectura para después de la migración. Su primer bloque usa datos ficticios y se puede ejecutar independientemente.
- No recalcular ventas, pagos, costos ni liquidaciones históricas al cambiar la gestión del catálogo.
- El TPV reutiliza el pipeline de productos existente para offline. Invalidar detalles en memoria después del merge de productos; no borrar órdenes pendientes ni crear otro catálogo offline.

## Verificación focalizada

Desde `ventiq_admin_app`:

`flutter test --no-pub test/precio_venta_contract_test.dart test/precio_venta_sql_contract_test.dart test/app_compile_test.dart test/sales_totals_summary_test.dart`

Desde `ventiq_app`:

`flutter test --no-pub test/home/product_detail_price_cache_test.dart test/home/product_detail_phase5_test.dart test/home/app_compile_test.dart`

Las pruebas de contrato SQL inspeccionan el archivo de migración; no sustituyen su validación de ejecución en PostgreSQL.

## Cobro por líneas multimoneda

- El checkout permite distribuir pagos independientemente de los medios asignados a los productos; redistribuir el cobro no recalcula sus precios. Con desglose editado, usar las mismas líneas en `Order.pagos` online y `desglose_pagos` offline, no reconstruirlas desde los ítems.
- Verificación desde `ventiq_app`: `flutter test --no-pub test/checkout_payment_lines_test.dart test/multimoneda_core_test.dart test/descuento_multimoneda_test.dart test/order_usd_payments_test.dart test/payment_currency_amounts_test.dart test/home/app_compile_test.dart`.
- Las pruebas locales no sustituyen una venta real, su sincronización remota ni la impresión física del ticket.
- Las tarjetas y el detalle de órdenes `producto-v1` muestran `TicketV1.totalesNativos`; su equivalente CUP usa el snapshot de cada línea, no la tasa actual ni el total escalar persistido. Esto también aplica a órdenes restauradas offline.
- El contador compartido valida las líneas `producto-v1` en su moneda nativa, excluye transferencias/pendientes y conserva conteos al cambiar de moneda. No compensar faltantes de una moneda con sobrantes de otra.
- Pruebas del contador y listado: desde `ventiq_app`, `flutter test --no-pub test/bill_count_dialog_test.dart test/order_card_totals_test.dart test/preorder_totales_moneda_test.dart test/home/app_compile_test.dart`.
- La factura PDF del cliente se genera mediante `OrdersScreen.buildCustomerInvoicePdf` sin consultas remotas: usa la orden persistida (incluidos ingredientes) y `getStorePrintInfo`. El login cachea también dirección, ubicación y teléfono; caché vacío permite generar sin esos datos opcionales. Verificación: `flutter test --no-pub test/customer_invoice_offline_test.dart test/home/app_compile_test.dart`.
- En el admin, `especial` pertenece a `app_dat_categoria_tienda`, no a la subcategoría ni al nomenclador global de categorías. El diálogo combinado del alta de productos envía el valor a `ProductService.createCategoria`. Verificación desde `ventiq_admin_app`: `flutter test --no-pub test/add_product_category_special_test.dart test/app_compile_test.dart`.

## Servicios e inventario

- Al crear servicios o elaborados desde el admin, `crearInventarioInicialProducto` registra cantidad 1 en una zona por almacén de la tienda usando la presentación base. No duplicar por zona ni habilitar inventario si falla el guardado de la receta. El alta no exige stock de ingredientes ni los descuenta: la disponibilidad real se comprueba al crear la orden. Los productos físicos normales no reciben inventario artificial.
- Recepción usa `ProductSearchType.reception`: excluir servicios antes de paginar, también al buscar por texto. Otros selectores conservan los servicios.
- En preorden, los ingredientes de servicios se verifican en el almacén del TPV con `exigirAlmacen: true`; no usar stock global ni interpretar errores como receta vacía. Offline sin receta o sin alcance de almacén verificado bloquea la operación.
- Pruebas admin: `flutter test --no-pub test/service_inventory_test.dart test/app_compile_test.dart`.
- Pruebas vendedor: `flutter test --no-pub test/service_ingredients_warehouse_test.dart test/home/app_compile_test.dart test/home/product_detail_phase5_test.dart test/venta_ingredient_consumo_test.dart`.
- En Windows, si el wrapper Bash de Flutter no produce salida, ejecutar `flutter.bat` desde PowerShell.

## Recepciones financiadas con el fondo

- La financiación directa usa `fn_fdi_registrar_recepcion`: varias fuentes cuenta/medio/moneda, importes nativos y `tasa_a_ref` (moneda de factura por una unidad de moneda origen). La suma de los equivalentes redondeados por fuente debe cubrir exactamente la factura. Las inversiones existentes ya retiraron dinero: amortizarlas no vuelve a descontar saldos.
- La RPC crea inversión, movimientos, recepción y vínculo en una transacción, bloquea saldos y conserva una clave por formulario para reintentos. No sustituirla por llamadas separadas ni reintentar mediante la recepción sin financiación cuando falle.
- Migración aditiva: `ventiq_admin_app/lib/sql/fondo_inversion_financiar_recepcion.sql`. Requiere el esquema FDI y la firma de recepción del parche `fondo_inversion_recepcion_patch.sql`; valida las dependencias al iniciar. No asumir que está desplegada. La cancelación conserva la política existente del módulo: desvincula y recalcula la inversión, sin devolver automáticamente dinero al fondo.
- Verificación desde `ventiq_admin_app`: `flutter test --no-pub test/fdi_recepcion_test.dart test/fdi_recepcion_rpc_test.dart test/fdi_liquidacion_dialog_test.dart test/service_inventory_test.dart test/app_compile_test.dart`. Las pruebas SQL de contrato no sustituyen una ejecución transaccional en PostgreSQL.
