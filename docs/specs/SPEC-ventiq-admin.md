# Spec: ventiq-admin (Inventtia Gestión)

Línea base as-built de `ventiq_admin_app` solamente. Describe lo que la administración hace hoy. Cada afirmación lleva una marca:

- **Observado** — está en el código, en un test de esta app, o en una RPC leída en main el 2026-11-14.
- **Inferido** — se sigue del comportamiento, sin un test que lo fije.
- **Abierto** — el código no decide si ese comportamiento es el deseado.

Esta app configura la tienda, el catálogo y el inventario. No cobra en el mostrador: eso es `ventiq_app`. El Admin Lite que existe dentro de Caja está cerrado y no forma parte de esta spec.

El contrato de moneda de producto que cruza las dos apps sigue en `tasks/SPEC-product-currency-*.md`. Cuando se cierre, se actualizan esta spec y la del TPV con lo implementado en cada una. El pase newa ↔ main está en `tasks/plan_sync_newa_main.md` y no se aplica todavía.

## Objective

**Observado.** Inventtia Gestión (`pubspec.yaml`: `ventiq_admin_app` 2.9.1+290) administra tiendas ya creadas o por registrar: catálogo, precios, inventario, ventas consultadas, personal, finanzas y canales. El título de la app es `Inventtia Gestión`. La versión que muestra la pantalla sale de `assets/changelog.json`, no del `pubspec`.

Quién entra, por tienda, en `PermissionsService`:

| Rol | De dónde sale | Qué puede, en corto |
|---|---|---|
| Dueño | `app_dat_dueno` | El de gerente, más ganancias, márgenes y costos de venta. Asigna el rol dueño. El dueño también tiene fila de gerente; si la sesión guardó gerente, se vuelve a leer `app_dat_dueno` para no ocultarle las ganancias |
| Gerente | `app_dat_gerente` | Catálogo, inventario, ajustes, importación, configuración, fondo de inversión |
| Supervisor | `app_dat_supervisor` | Ve y opera recepción, transferencia y aprobación de ajustes. No borra productos ni importa Excel |
| Auditor | `auditor` | Consulta. No crea productos ni movimientos de stock |
| Almacenero | fila de almacenero | Ve productos y hace recepción y transferencia. No entra a cocinas |
| Recursos humanos | rol de RR. HH. | Check-in, check-out, salario e historial |
| Vendedor | `app_dat_vendedor` | El login lo rechaza: «Los vendedores deben usar la app de ventas.» |

Jerarquía de mayor a menor: dueño, gerente, supervisor, auditor, almacenero, recursos humanos, vendedor. Si alguien tiene varios roles, manda el más alto.

Sin suscripción válida el flujo puede ir a `/subscription-detail`. La sesión queda atada a una tienda elegida.

Éxito para esta app: un gerente abre el dashboard de su tienda, mantiene catálogo e inventario, y el TPV lee después esos mismos datos. Un cambio de precio o de receta no reescribe ventas, pagos, costos ni liquidaciones ya hechos.

## Tech Stack

**Observado.**

- Flutter / Dart SDK `^3.10.0`. Material. Cliente de Supabase `supabase_flutter` ^2.5.6.
- Esta app no trae SQLite. Trabaja online contra el mismo Postgres que el TPV.
- Gráficos con `fl_chart`. Archivos con `file_picker` e `image_picker`. Fechas con `intl`.
- Empaquetado y lints: `flutter_lints` en `analysis_options.yaml`.

## Commands

Desde `ventiq_admin_app`. En Windows, si el wrapper Bash de Flutter no produce salida, usar `flutter.bat`.

```
flutter pub get
flutter analyze
flutter test
flutter run
```

Pruebas de esta línea base:

```
flutter test --no-pub test/precio_venta_contract_test.dart test/precio_venta_sql_contract_test.dart test/app_compile_test.dart test/sales_totals_summary_test.dart
flutter test --no-pub test/service_inventory_test.dart test/app_compile_test.dart
```

Los tests `m01_*` y `precio_venta_*` inspeccionan el archivo SQL o el contrato del cliente. No sustituyen ejecutar la migración en PostgreSQL. Una recepción real y el stock que ve el TPV después tampoco los cubre la suite local.

## Project Structure

**Observado.** Código en `ventiq_admin_app/`.

```
lib/main.dart                 Arranque y rutas con nombre
lib/screens/                  Pantallas por dominio (inventario, ventas, finanzas, RR. HH., WAPI)
lib/services/                 Permisos, productos, inventario, ventas, marketing
lib/sql/                      Scripts que esta app espera en el servidor
test/                         Contratos de precio, inventario de servicios, fondo, WAPI
assets/changelog.json         Versión que muestra la UI
```

`/dashboard` elige `DashboardWebScreen` en web y `DashboardScreen` en el resto. `/categories` abre Ajustes: la gestión real de categorías (especial, orden en el home, contador) vive ahí. `/restaurant-costs` abre `ProductionCostsScreen`.

## Qué hace la app

### Tienda y personal

**Observado.** `/store-registration` y el detalle de tienda crean o editan la tienda, sus almacenes, TPV y personal. `/workers` y `/tpv-management` asignan vendedores y puntos de venta. `/cocinas-management` configura estaciones; el almacenero no entra. `/servicentro-management` configura combustibles de un TPV y solo lo abre el gerente. `/settings` (gerente y supervisor) guarda los flags que el TPV lee, entre ellos `modo_restaurante`, `cocina_activa`, `permitir_modo_offline_completo` y los de ticket.

En newa, leer y escribir `app_dat_configuracion_tienda` ya pasa por RLS. En main esa tabla sigue con RLS apagado. La regla que manda, cuando se haga el pase, es la de newa: el vendedor de la tienda puede leer; dueño, gerente y superadmin de nivel 1 escriben. Está descrita en la spec del TPV y en `tasks/plan_sync_newa_main.md`.

### Catálogo y precio

**Observado.** Productos, presentaciones, variantes, atributos y precios viven en `/products`, `/add-product`, `/precios-productos` y `/tpv-prices`. El precio vigente no se elige por `created_at`. Lo resuelven `app_v_precio_venta_vigente` (variante) y `app_v_precio_venta_base_vigente` (base), con `CURRENT_DATE` del servidor y el ID mayor del producto o variante. NULL y 0 son la variante base. Esas vistas no sustituyen una consulta histórica.

La edición de la base llama `fn_guardar_precio_venta_base`. En main la función bloquea la fila del producto (`FOR UPDATE`) y solo sigue si `fn_user_is_gerente_or_superadmin` o `fn_user_is_dueno` responden verdadero. Si el producto no existe, lanza `Producto inexistente`. No hay otra escritura de respaldo si el permiso falla.

Alta de un servicio o un elaborado: `crearInventarioInicialProducto` inserta cantidad final 1 en una sola zona por almacén de la tienda, usando la presentación con `es_base`. Si un almacén no tiene zonas, o no hay presentación base, no se inserta esa fila y el alta no deja el inventario a medias por ese almacén: lanza y no continúa el bucle. Un producto físico normal no recibe esa fila artificial. El alta no exige stock de ingredientes ni lo descuenta. La disponibilidad real se comprueba al vender, en el TPV.

Recepción usa `ProductSearchType.reception` y quita los servicios antes de paginar, también en la búsqueda por texto. Los demás selectores conservan los servicios.

Cambiar un precio o una receta no recalcula ventas, pagos, costos ni liquidaciones ya registradas.

### Inventario

**Observado.** Recepción, extracción, transferencia, ajuste, IPV, lotes y caducidades están en las pantallas `inventory_*`, `caducidades_screen` y `product_movements_screen`.

| Acción | Quién |
|---|---|
| Ver productos | Gerente, supervisor, auditor, almacenero |
| Crear o editar producto | Gerente, supervisor |
| Borrar producto | Gerente |
| Recepción y transferencia | Gerente, supervisor, almacenero |
| Extracción y ajuste | Gerente |
| Aprobar ajuste | Gerente, supervisor |
| Importar Excel | Gerente |

La matriz está en `PermissionsService._actionPermissions` y `_routePermissions`.

El costo desglosado por línea de recepción (`app_dat_producto_costo`, `app_dat_recepcion_producto_costo` y el trigger que rellena `costo_real`) está en newa y no en main. No cambia el stock que ve el TPV. El pase está en el plan de sincronización.

## Reglas que impone el servidor

**Verificado el 2026-11-14 en main**, leyendo el cuerpo de las RPC de escritura y de informe que esta app llama. La matriz de `PermissionsService` es la puerta de la pantalla. Donde la función mira rol o estado, manda la función.

### Precio y costo

`fn_guardar_precio_venta_base` bloquea el producto, rechaza un precio inválido y lanza `Sin permiso para modificar precios` si quien llama no es dueño, gerente o superadmin de esa tienda.

`fn_corregir_costo_recepcion` solo deja corregir al dueño (`Solo el dueño de la tienda puede corregir costos`). El costo nuevo tiene que ser mayor que cero y la línea de recepción tiene que existir. Hay dos firmas desplegadas. Las dos repiten esa regla.

### Recepción, extracción, transferencia y ajuste

`fn_registrar_recepcion_con_inventario` exige al menos un producto, y cada línea necesita `id_producto` y cantidad. No rechaza servicios: quitarlos es regla del cliente (`ProductSearchType.reception`), no de esta RPC. `fn_completar_recepcion_operacion` no completa algo que no es recepción, ni una recepción ya completada. Si no puede contabilizar el inventario, la operación no queda completada.

`fn_crear_extraccion_con_movimiento_v2` exige usuario autenticado, `client_request_uuid` y acceso a la tienda. Rechaza tienda inexistente, motivo inexistente, cantidad no positiva, precio negativo, producto o ubicación de otra tienda, presentación que no es del producto, variante u opción incoherentes, líneas duplicadas y producto sin presentación base. Reusar el mismo UUID con otro payload lanza `IDEMPOTENCY_KEY_REUSED`. Si una línea no se puede cumplir, la extracción no sigue.

`fn_transferir_inventario_entre_layouts` exige `id_producto` y cantidad mayor que cero en cada línea. Si falla la extracción o la recepción del movimiento, la transferencia no queda a medias: devuelve el error de ese paso.

`fn_insertar_ajuste_inventario2` exige producto y ubicación. La cantidad nueva no puede ser negativa. Un producto por lotes, en un ajuste positivo, necesita código de lote y fecha de vencimiento.

### Cocina, servicentro, personal y cobros a plazo

`fn_crear_cocina` exige nombre y tienda existente. El almacén tiene que ser de esa tienda, no puede ser el almacén de venta de un TPV y no puede estar ya asignado a otra cocina. No admite dos cocinas con el mismo nombre en la tienda.

`fn_set_modo_servicentro` rechaza un número de columnas fuera de 1 a 4.

`fn_insertar_trabajador_completo` no crea un vendedor si la tienda no tiene TPV, ni un almacenero si no tiene almacén. `fn_eliminar_trabajador_completo` no borra a quien no existe. Si el trabajador tiene historial operativo, lo desactiva y quita los roles. Si no tiene historial, lo elimina.

`fn_cxc_registrar_liquidacion` exige un monto mayor que cero. `fn_fdi_crear_liquidacion`, en main, solo la ejecuta un gerente o superadmin, exige cuenta destino de la misma tienda, órdenes elegibles en el periodo y una ganancia a retirar dentro de rango. La firma con `p_repartir_igual` sigue solo en newa.

### Reportes

**Verificado el 2026-11-14 en main y contrastado con newa.** El informe que el vendedor ve en Gestión sale de estas funciones. Ninguna de las de ganancia exige ser dueño: comprueban acceso a la tienda, o no comprueban rol. El dueño como único lector de márgenes es `canViewGanancias` en el cliente.

#### Ventas y margen

`fn_reporte_ventas_ganancias` exige `check_user_has_access_to_tienda`. Suma extracciones de operaciones cuyo tipo es «venta», cuyo último estado es 2 (completada) y cuya venta está pagada (`es_pagada`). La fecha es `created_at` de la operación. El costo unitario en CUP es el costo de la recepción por la tasa USD. La ganancia total es ingresos menos cantidad vendida por ese costo. Una cantidad sumada en cero no entra.

`fn_reporte_ventas_con_proveedor5` es el informe de producto por fechas. Exige acceso a la tienda. El filtro de fecha admite `creacion` o `completado`; cualquier otro valor vuelve a `creacion`. Delega en `fn_reporte_ventas_con_proveedor4` y deja una fila por cada combinación de precio de venta y costo, sin promediarlos. Esa v4 solo cuenta ventas completadas (último estado 2).

`fn_reporte_ventas_con_proveedor_por_turno_v2` usa la misma ventana que el informe por turno y el mismo corte de venta completada. También exige acceso a la tienda. El costo de cada fila es el precio promedio de esa presentación por la cantidad. Si esta firma no está, el cliente cae a `fn_reporte_ventas_con_proveedor_por_turno`.

`fn_reporte_ventas_con_proveedor_precios_actuales` valoriza con `app_v_precio_venta_vigente` y la tasa extraoficial de la tienda. También filtra venta completada. Esta firma no llama a `check_user_has_access_to_tienda`.

`fn_reporte_cronologico_producto` arma la línea de tiempo del producto con ventas completadas. La fecha del evento es la creación de la operación, o la del estado actual si el filtro es `completado`. Arrastra costo, precio y tasa.

`fn_reporte_ventas_por_vendedor_sch`, sin fechas, usa el turno abierto del vendedor. Con fechas, filtra ese rango. Solo cuenta ventas completadas e incluye pagos.

`fn_reporte_ventas_por_moneda` agrupa `app_dat_pago_venta` por moneda, separa efectivo y digital, y calcula la tasa promedio como equivalente CUP entre monto nativo. Solo entran pagos de operaciones cuyo último estado es 2. No comprueba acceso a la tienda.

`fn_moneda_consolidacion` devuelve la moneda forzada de la tienda si está activa en el catálogo de la tienda. La tasa preferida es CUP hacia esa moneda. Si no hay tasa, la moneda queda CUP con tasa 1.

`fn_reporte_ventas_por_turno_v2` envuelve el reporte por turno y le añade el desglose de monedas del usuario. `fn_resumen_turno_por_id_v2` envuelve el resumen del turno y le añade el desglose de monedas de ese turno.

`fn_listar_turnos_admin` pagina turnos de la tienda. El límite queda entre 1 y 200, y la página mínima es 1. Lee apertura, cierre, pagos y extracciones. No es `SECURITY DEFINER` y no comprueba rol.

`listar_ordenes` es `SECURITY DEFINER`. Arma las tiendas visibles con el uuid del usuario en gerente, supervisor, auditor y almacenero. El listado de ventas de `/sales` usa esta función, no el checkout del TPV.

`fn_ordenes_producto_proveedor` lista órdenes de recepción del producto y solo las completadas.

#### Tablero, BCG y valoración

`fn_dashboard_analisis_tienda` exige `check_user_has_access_to_any_tienda`. El periodo admite 5 años, 3 años y 1 año, y compara el tramo contra el tramo anterior. Devuelve ventas, productos y productos sin stock.

`get_bcg_productos_sin_log` exige acceso a la tienda. Toma las ventas del último mes. Clasifica contra el promedio de la tienda: por encima de cuota y de crecimiento es Estrella; cuota alta y crecimiento bajo es Vaca lechera; cuota baja y crecimiento alto es Interrogante; el resto es Perro. Hay una segunda clasificación con umbrales al 0,8 y 1,2 de esos promedios. El costo sale de la recepción; si la recepción no trae tasa, usa la última tasa USD a CUP.

`fn_warehouses_valuation_summary`, `fn_warehouse_valuation_zones` y `fn_zone_valuation_products` leen `fn_inventory_valuation_rows`. El stock es el último inventario de la presentación, y `id_presentacion` es la fila de `app_dat_producto_presentacion`, no el id del nomenclador. El valor de costo y el de venta se convierten con la tasa USD de la tienda. La ganancia es la diferencia de esos dos valores. Un almacén sin stock igual aparece, en cero, si no está borrado. Estas tres no comprueban rol.

`fn_vista_precios_productos3` resuelve la tasa de la tienda en este orden: extraoficial activa USD, conversión global, y si no hay ninguna, 1. Cruza precio de venta, costo e ingredientes. No comprueba rol.

`fn_listar_cambios_precio` pagina el historial de cambios de precio por producto, variante y TPV. No comprueba rol.

`fn_preview_cumplimiento_v2` exige usuario autenticado y acceso a la tienda del producto. El producto borrado no se previsualiza. Devuelve cuánto se puede servir con las presentaciones disponibles.

#### Inventario analítico

`fn_analytics_inventory_metrics` mide el último inventario por producto, no el historial acumulado. Sin `p_store_id`, la tienda sale del supervisor y, si no hay, del auditor. Si no resuelve tienda, lanza `No se pudo determinar la tienda del usuario`.

`fn_analytics_stock_alerts` resuelve la tienda en este orden: parámetro, supervisor, auditor, gerente. Compara el último inventario con los límites del almacén y con la caducidad del lote.

`fn_analytics_product_movements` lista movimientos de inventario de esa misma resolución supervisor y luego auditor.

`fn_analytics_inventory_trends`, `fn_analytics_category_analysis`, `fn_analytics_rotation_report` y `fn_analytics_efficiency_report` no están en main ni en newa. El cliente, al fallar la llamada, devuelve listas vacías.

#### Proveedores, marketing, personas y carnaval

`fn_dashboard_proveedores` tiene dos firmas. La larga calcula compras, lead time y el mes anterior. La corta cuenta filas de `app_dat_proveedor` sin filtrar tienda. `fn_metricas_proveedor_completas` rechaza un proveedor que no pertenece a la tienda y devuelve órdenes, valor, lead time y un score. `fn_top_proveedores` ordena por la suma de cantidad por `costo_real` de las recepciones.

`fn_marketing_dashboard_resumen` exige usuario autenticado y acceso a la tienda. Cuenta campañas, comunicaciones, eventos de fidelización, promociones y segmentos. `fn_marketing_metricas_rendimiento` exige el mismo acceso, una fecha hasta posterior a la desde, y un rango de un año como máximo.

`fn_analisis_promociones` cruza ventas con promociones aplicadas al cliente. `fn_analisis_clientes` cuenta altas de cliente. `fn_fidelizacion_resumen` resume clientes y eventos. Las tres leen por `id_tienda` y no comprueban rol.

`fn_hr_salary_report` y `fn_hr_dashboard_summary` suman asistencia con hora de salida, entre la fecha desde y el día siguiente de la fecha hasta. El salario es la base más el pago por resultado cuando la fila lo marca. La tarifa de un jornalero es `salario_dia`; la de un horario es `salario_horas`. `fn_hr_top_workers_by_pay` ordena por ese total. Ninguna comprueba rol: la puerta es la ruta de RR. HH. en el cliente.

`fn_dashboard_carnaval_proveedor` rechaza un rango de fechas inválido y a quien no está autorizado en la tienda. Cruza la orden de carnaval con el producto local y su precio. `fn_audit_carnaval_order_lines` y `fn_audit_inventtia_carnaval_lines` comparan líneas entre el esquema `carnavalapp` y las órdenes locales. `fn_info_contabilizacion_ordenes_carnaval` resuelve la tienda por gerente, supervisor, auditor o trabajador.

`fn_reporte_eficiencia_restaurante` no está en main ni en newa.

#### Informes que el cliente aún no puede leer del servidor

Estas funciones no existen en main ni en newa. `FinancialReportsService` ni las llama: rentabilidad, rentabilidad por categoría, productos de margen bajo, flujo histórico, comparación histórica, tendencia y variación de presupuesto devuelven vacío. `FinancialDashboardService` sí llama `fn_profit_and_loss`, `fn_sales_metrics`, `fn_inventory_metrics`, `fn_product_profitability`, `fn_category_profitability`, `fn_cash_flow_projections` y `fn_historical_trends`. Al fallar, el tablero sustituye la respuesta por cifras de ejemplo armadas en el cliente. Esas cifras no son ventas de la tienda.

### Lo que el servidor de esta app no decide

La matriz de pantallas (quién ve ganancias, quién importa Excel, quién aprueba un ajuste) vive en `PermissionsService`. Una RPC de las de arriba no vuelve a comprobar ese mapa. Donde la función sí mira rol, manda la función.

El enrutamiento de stock al vender (cocina ligada, receta, porción de tanda) lo imponen las RPC del TPV, no estas. Esta app configura la cocina y el catálogo. El descuento ocurre al pedir o al cobrar en Caja.

### Ventas, caja y canales

**Observado.** `/sales` lista con `listar_ordenes`, acotada a las tiendas del usuario. Cuentas por cobrar (`/cuentas-por-cobrar`) las ven gerente y supervisor. El fondo de inversión (`/fondo-inversion`) lo ven dueño y gerente. En newa el gasto del fondo y `repartir_igual` van por delante de main; el detalle del pase no se duplica aquí.

Consignación, carnaval, WAPI (avisos y agotado), depósitos bancarios, facturas de importadora y pago a proveedores tienen pantalla propia. El aviso de agotado de WAPI y las tablas de referidos están en main y todavía no en newa.

### Finanzas, marketing y personas

**Observado.** Ganancias, márgenes y costos de venta solo los pinta el dueño (`canViewGanancias`). La RPC de ganancias deja pasar a quien tenga acceso a la tienda. Marketing, CRM y campañas son de gerente, con consulta de auditor en varias rutas. RR. HH. (entrada, salida, salario, historial) lo usan gerente, supervisor y recursos humanos. El salario que muestra el informe es el de la asistencia ya cerrada.

## Code Style

**Observado.** Servicios estáticos o de una sola instancia sobre `Supabase.instance.client`. Permisos en mapas de rol, no repartidos por cada botón. UI en español. Rutas con nombre.

```dart
'product.delete': [UserRole.gerente],
'inventory.create_reception': [
  UserRole.gerente,
  UserRole.supervisor,
  UserRole.almacenero,
],
```

## Testing Strategy

**Observado.** `flutter_test` en `ventiq_admin_app/test`. No hay un umbral de cobertura escrito. Precio e inventario de servicios tienen contrato. `test/app_compile_test.dart` comprueba que el paquete analiza.

**Inferido.** Una recepción guardada en Supabase y el stock que el TPV descuenta después no los cubre la suite local.

## Boundaries

- **Always:** Resolver el precio vigente con las dos vistas y el ID mayor. Editar la base solo con `fn_guardar_precio_venta_base`. Dar inventario inicial 1, en una zona, solo a servicios y elaborados, y solo si la receta se guardó. Excluir servicios en la búsqueda de recepción. Dejar intactas las ventas y liquidaciones históricas. Correr los tests del área tocada.
- **Ask first:** Cambiar el esquema o una RPC que esta app llama. Añadir una dependencia. Activar en main el RLS de configuración de tienda. Subir las tablas de costo o `fn_fdi_gasto` antes del plan de sincronización.
- **Never:** Documentar aquí el cobro del TPV, Muevete o Flow. Tratar el Admin Lite de Caja como esta app. Reintroducir la selección de precio por `created_at`. Duplicar el inventario inicial por cada zona del almacén. Dar inventario artificial a un producto físico. Copiar secretos a docs o logs.

## Success Criteria

1. Un gerente con tienda seleccionada abre `/dashboard` y llega al dashboard de su plataforma.
2. `fn_guardar_precio_venta_base` rechaza a quien no es dueño, gerente o superadmin de la tienda del producto, y bloquea la fila del producto mientras guarda.
3. El precio que muestran las vistas vigentes es el de mayor ID dentro de la fecha del servidor. NULL y 0 son la variante base.
4. Crear un servicio o elaborado deja cantidad 1 en una zona de cada almacén, con la presentación base. Un producto físico no recibe esa fila.
5. La búsqueda de recepción no ofrece servicios. El resto de selectores sí.
6. `canViewGanancias` es verdadero solo para el dueño de la tienda en sesión.
7. `flutter test --no-pub test/app_compile_test.dart test/service_inventory_test.dart test/precio_venta_contract_test.dart` pasa.
8. Una extracción v2 sin usuario, sin UUID de idempotencia, con cantidad no positiva o con producto de otra tienda no mueve inventario.
9. Completar una recepción que ya estaba completada, o que no es recepción, no vuelve a contabilizar el inventario.
10. El informe de ganancias y el de ventas por moneda solo suman operaciones cuyo último estado es completada. El de ganancias, además, exige la venta pagada.
11. Ganancias, ventas por proveedor, ventas por moneda y ventas por turno leen operaciones reales de la tienda. El tablero que llama `fn_profit_and_loss` queda fuera de ese contrato hasta que esas funciones existan en main.

## Open Questions

Ninguna que bloquee esta línea base. El RLS de configuración, los costos de recepción y el gasto del fondo con `repartir_igual` ya tienen destino: el plan de sincronización, cuando se cierre el trabajo en curso.

## Dependencias que esta app no posee

- El cobro, la caja del turno y el catálogo offline del vendedor: `ventiq_app`.
- Esquema, RLS y cuerpos de las RPC: `supabase/` y `sql_updates/`. Esta app asume que `fn_guardar_precio_venta_base` y las vistas vigentes están desplegadas antes que el cliente que las llama.
- `inventtia_muevete` e `inventtia_flow` no se describen en este archivo.
