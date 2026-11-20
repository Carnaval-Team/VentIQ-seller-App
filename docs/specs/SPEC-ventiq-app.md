# Spec: ventiq-app (Inventtia Caja)

Línea base as-built de `ventiq_app` solamente. Describe lo que el TPV hace hoy. Cada afirmación lleva una marca:

- **Observado** — está en el código o en un test de esta app.
- **Inferido** — se sigue del comportamiento, sin un test que lo fije.
- **Abierto** — el código no decide si ese comportamiento es el deseado.

El contrato de moneda de producto y precio vigente que cruza esta app con `ventiq_admin_app` no forma parte de esta línea base. Vive en `tasks/SPEC-product-currency-*.md` y en `AGENTS.md`, y sigue en implementación. Cuando ese trabajo se cierre, se actualizan esta spec y la de admin con lo que haya quedado implementado en cada app.

## Objective

**Observado.** Inventtia Caja (`pubspec.yaml`: `ventiq_app` 2.7.0+851) es el punto de venta. El usuario opera una tienda ya creada: vende, cobra, abre y cierra caja, y trabaja sin red con lo que haya sincronizado. El título de la app es `Inventtia Caja`.

Quién entra:

- **Vendedor.** Fila en `app_dat_vendedor`. Es el único rol que `SellerService.verifySellerAndGetProfile` acepta en el login online, y el `entryRole` que ese método guarda es siempre `vendedor`.
- **Gerente o supervisor.** El código de Admin Lite los resuelve en `app_dat_gerente` / `app_dat_supervisor`. En esta línea base ese modo está cerrado: el login deja `entryRole` en `vendedor` y `canManageInventory` devuelve falso para ese rol. No se reabre junto con esta spec.
- **Cocina.** `jefe_cocina` o `cocinero`. Su home es `/kds`. Quien entra como vendedor y además tiene cocinas asignadas ve Cocina en el drawer; el home `/kds` es para la sesión cuyo rol guardado es de cocina.
- **Superadmin.** Fila activa en `app_dat_superadmin`. No cambia el home. Habilita el visor de datos offline del drawer. Si la consulta falla, la herramienta no se muestra.

La sesión queda atada a tienda, TPV, almacén del TPV y trabajador. Sin suscripción activa el splash manda a `/subscription-detail` y no al home.

Éxito para esta app: un vendedor con licencia abre el home que corresponde a su modo, arma la venta, la cobra o la deja pendiente, y al volver la red sube ventas, egresos y turno sin pedir otro catálogo.

## Tech Stack

**Observado.**

- Flutter / Dart SDK `^3.7.0`. Material 3. Color semilla `#194B8C`.
- Backend: Supabase (`supabase_flutter` ^2.5.6). Esta app no crea el esquema. Llama tablas y RPC que viven en `supabase/` y `sql_updates/`.
- Offline: `sqflite` en móvil, `sqflite_common_ffi` en escritorio, `SharedPreferences` en web (ahí no hay SQLite). Preferencias de sesión también en `SharedPreferences`.
- Impresión: Bluetooth (`print_bluetooth_thermal`, ESC/POS), Sunmi (`sunmi_printer_plus`), WiFi, e impresión del navegador en web. Detalle en `ventiq_app/lib/services/README_PRINTING.md`.
- Otros: `mobile_scanner`, `connectivity_plus`, `another_telephony` (SMS de transferencia, solo Android), `pdf`, `share_plus`, `flutter_local_notifications`.
- Empaquetado Windows: MSIX (`msix` en dev). La config está en `pubspec.yaml` (`msix_config`). No se copia a esta spec.

## Commands

Desde `ventiq_app`. En Windows, si el wrapper Bash de Flutter no produce salida, usar `flutter.bat`.

```
flutter pub get
flutter analyze
flutter test
flutter run
```

Pruebas que ya cubren este cliente (no sustituyen una venta real, su sync ni un ticket físico):

```
flutter test --no-pub test/home/app_compile_test.dart test/home/home_shell_test.dart test/home/offline_home_test.dart test/home/home_catalogo_test.dart
flutter test --no-pub test/service_ingredients_warehouse_test.dart test/venta_ingredient_consumo_test.dart test/home/product_detail_phase5_test.dart test/home/elaborated_availability_test.dart
flutter test --no-pub test/mesa_pending_order_test.dart test/mesas_resumen_test.dart
flutter test --no-pub test/bank_sms_service_test.dart test/bank_sms_parser_test.dart test/desarme_bulto_local_test.dart test/presentacion_cadena_local_test.dart
flutter test --no-pub test/sunmi_printer_test.dart test/receipt_options_test.dart
```

Los tests `*_multimoneda*`, `moneda_venta_*`, `checkout_payment_lines_test.dart`, `order_usd_payments_test.dart` y `payment_currency_amounts_test.dart` existen en el cliente y pertenecen al contrato en curso, no a esta línea base.

## Project Structure

**Observado.** Código en `ventiq_app/`.

```
lib/main.dart                 Arranque, tema, rutas con nombre
lib/screens/                  Pantallas. login y categories tienen variante web
lib/screens/admin/            Admin Lite (inventario dentro de Caja, no es ventiq_admin_app)
lib/services/                 Singletons. Auth, venta, turno, sync, offline, impresión
lib/widgets/                  Drawer, home, checkout, diálogos de caja
lib/widgets/home/             Catálogo del home nuevo
lib/controllers/              HomeController
lib/models/                   Producto, catálogo, gasto, mesa
lib/tutorial/                 Recorrido guiado de venta
lib/theme/ventiq_home_theme.dart
lib/utils/                    Navegación, precios, plataforma, sesión
test/                         Tests del paquete. Varios bajo test/home/
assets/                       Logo, changelog, imágenes de producto vacío
```

Rutas registradas en `MyApp.routes`. El home real lo elige `NavigationHelper.homeRoute`, no una sola ruta fija.

| Prioridad | Condición | Ruta |
|---|---|---|
| 1 | `entryRole` gerente o supervisor | `/admin-home` (rama en código; Admin Lite está cerrado, así que el vendedor no la toma) |
| 2 | Sesión `jefe_cocina` o `cocinero` | `/kds` |
| 3 | Modo servicentro del TPV | `/servicentro` |
| 4 | `flujoMesaActivo` (tienda restaurante y no estás en mostrador) | `/mesas` |
| 5 | Resto | `/categories` → `HomeShellScreen` |

`/categories` es el home de venta. `/categories-mobile` y `/categories-web` siguen registradas y ninguna pantalla navega hacia ellas. Quitarlas es opcional y no forma parte de esta línea base.

`/preorder` sirve `PreorderScreenStyled` porque `kPreorderStyled` está en `true`. Ponerlo en `false` devuelve `PreorderScreen` sin tocar el resto. Notas visuales en `docs/design/preorder-styled.md`.

## Qué hace la app

### Arranque y sesión

**Observado.** `main` inicializa Supabase, la base offline (un fallo no bloquea el primer frame), el cache de `modo_restaurante` y de servicentro, y el desfase de reloj (`ServerTimeService`) para que apertura, cierre y órdenes offline no dependan del reloj del dispositivo.

El splash espera 2 segundos, comprueba sesión y licencia, y navega. El selector `/offline-user-switch` y la preparación del dispositivo quedan apagados a propósito, igual que Admin Lite: `UserPreferencesService.enableDeviceFullOffline` es `false`, y con el flag en falso `isDeviceFullOfflineReady` limpia la marca y devuelve falso.

Login online: email y contraseña de Supabase, luego perfil de vendedor. Guarda TPV, tienda, almacén, vendedor y trabajador. Cachea superadmin, rol de cocina y rol admin. Guarda credenciales para reentrada. Login offline de Caja solo acepta un usuario cacheado con `entryRole == vendedor`.

### Venta de mostrador

**Observado.** Home (`HomeShellScreen`) muestra el catálogo de la tienda (`HomeCatalogService`, categorías, búsqueda, alta rápida). El producto se detalla en `ProductDetailsScreen` y entra a la preorden. El checkout cobra. La venta online llama `fn_registrar_venta_v3` y, si PostgREST dice que no existe, `fn_registrar_venta`. El pago llama `fn_registrar_pago_venta_v3`, luego `fn_registrar_pago_venta_v2`, luego `fn_registrar_pago_venta`. El cambio de estado de la operación usa `fn_registrar_cambio_estado_operacion`.

La preorden puede arrancar con los productos por defecto del vendedor (`/default-order-items`). Hay escáner de barras. Los ingredientes de un servicio se comprueban en el almacén del TPV (`exigirAlmacen: true` en el flujo de preorden). Sin receta o sin alcance de almacén verificado, la operación offline no sigue. Tests: `service_ingredients_warehouse_test.dart`, `venta_ingredient_consumo_test.dart`.

**Inferido.** El catálogo que el vendedor ve es el que bajó el sync de productos. No hay un segundo catálogo offline.

### Caja

**Observado.** Drawer del vendedor: apertura, egreso, venta total, cierre, trabajadores del turno. El resumen de cierre prueba `fn_resumen_diario_cierre_v4` y cae a `fn_resumen_diario_cierre_v2`. El cierre de turno prueba `fn_cerrar_turno_tpv_monedas` y cae a `fn_cerrar_turno_tpv_usd` o `fn_cerrar_turno_tpv`. El egreso parcial online usa `registrar_egreso_parcial_v2`. Un cierre que no pudo subirse aparece en el drawer como "Cierre pendiente" (`/cierre-pendiente`).

### Restaurante

**Observado.** `modo_restaurante` es un flag de tienda en `app_dat_configuracion_tienda`, cacheado en `StoreConfigService`. Con ese flag, el home es `/mesas`. La cuenta vive en base (`app_dat_mesa_cuenta_item`), no en la preorden local. El botón de carrito, si hay flujo de mesa, abre la cuenta activa en memoria, si no la última cuenta abierta del TPV (`fn_ultima_cuenta_abierta_tpv`), y si no hay ninguna va a `/mesas`.

"Venta de Mostrador" (`SalesModeService.activarMostrador`) es solo memoria de la sesión: no se persiste. Mientras está activa, carrito y checkout se comportan como venta normal. Al reiniciar la app, una tienda restaurante vuelve a mesas. Entrar a Mesas llama `salirDeMostrador`.

La venta de mesa usa `fn_registrar_venta_mesa_v3` y, si no existe, `fn_registrar_venta_mesa`.

Cocina: el drawer muestra Cocina y Producción solo si `ComandaService.listarMisCocinas` devuelve algo. El home `/kds` es para la sesión de cocina, no para un vendedor que además tiene una cocina asignada. Producción (`/produccion`) es de tandas y porciones; el comentario de `isJefeCocinaSession` reserva producir tandas al jefe de cocina.

### Servicentro

**Observado.** El modo es del TPV, no de la tienda (`ServicentroService.modoServicentroSync`). El home es `/servicentro` y en `homeRoute` gana sobre restaurante. El drawer de ese modo ofrece Combustibles y las opciones de caja, no el catálogo ni las mesas.

### Admin Lite (dentro de Caja)

**Decidido.** Está implementado y cerrado en el vendedor. Esta línea base no lo abre. La gestión de inventario, productos y tienda sigue en `ventiq_admin_app`, que se documenta aparte.

**Observado.** El hub es `/admin-home`, dentro de Caja, no en la app de admin. `canManageInventory` mira primero el `entryRole`: `vendedor` devuelve falso; `gerente` o `supervisor` devuelve verdadero. El login online deja siempre `vendedor`, así que el drawer no muestra Administración y `homeRoute` no cae en `/admin-home`.

Con el modo abierto, el hub lista stock, stock por ubicación, recepción, extracción, venta por acuerdo, transferencia, ajuste, productos, precios por TPV, TPVs y vendedores, IPV, proveedores, clientes, cola de operaciones y cuadres offline. "Preparar dispositivo offline" además exige `enableDeviceFullOffline`, que también permanece en `false`. Las operaciones de inventario offline se encolan en `admin_pending_ops` y suben con `SyncModule.uploadAdminOps`. Ese código se queda; no forma parte de la operación actual del vendedor.

### Offline y sync

**Observado.** `AutoSyncService.syncModules` baja y sube por módulo. Licencia no se puede deseleccionar.

Bajada: licencia, configuración de tienda, credenciales, métodos de pago, promociones, categorías, productos, layouts, órdenes, turno, egresos, trabajadores del turno, fondo de caja.

Subida: ventas, egresos, turno (apertura/cierre), cambios de trabajadores, operaciones de admin.

SQLite guarda secciones, categorías y productos (`offline_sections`, `offline_categories`, `offline_products`) más `offline_meta` y `admin_pending_ops`. En web el mismo contenido va a un JSON de preferencias.

Al fusionar productos no se borran órdenes pendientes ni se crea otro catálogo. El reloj offline usa el offset persistido de `ServerTimeService`.

Flags de tienda que el TPV lee desde el cache de configuración (la escritura de la mayoría vive en admin): `modo_restaurante`, `cocina_activa`, `permitir_modo_offline_completo`, `permitir_imprimir_pendientes`, `need_master_password_to_cancel`, `need_all_orders_completed_to_continue`, `permite_vender_aun_sin_disponibilidad`, `no_solicitar_cliente`, `allow_discount_on_vendedor`, `mostrar_metodo_pago_ticket`, imagen de operación, modificaciones del vendedor, días máximos sin revalidar licencia, impresora por defecto y copias por ticket. `mostrar_selector_moneda` y `forzar_moneda_venta` están en el cliente y pertenecen al contrato de moneda en curso.

**Actualizado el 2026-11-19.** El flag `permitir_moneda_por_producto` (apagado por defecto) lo lee `store_config_service.dart` y existe solo en newa: main no tiene la columna ni ninguna `fn_m01_*`. En newa está encendido en una tienda piloto; con el flag apagado o ausente rige el flujo de siempre. Cuando se enciende, `forzar_moneda_venta` y `moneda_venta_forzada` se apagan en el mismo UPDATE y no se pueden activar juntos (script 53). `mostrar_selector_moneda` se retiró del admin y del TPV nuevo; la columna queda para clientes viejos. El contrato completo sigue en `tasks/SPEC-product-currency-*.md` y su estado en `tasks/plan_admin_multimoneda.md`.

### Impresión y SMS

**Observado.** `PrinterManager` elige canal: Bluetooth ESC/POS en móvil, diálogo de navegador en web, WiFi en `/wifi-printers`, Sunmi donde el dispositivo lo tiene. Qué tickets y cuántas copias salen de la config de tienda.

En Android, `another_telephony` lee SMS para confirmar un pago por transferencia (PAGOxMOVIL). En las demás plataformas la confirmación es manual. Tests: `bank_sms_parser_test.dart`, `bank_sms_service_test.dart`.

## Reglas que impone el servidor

**Verificado el 2026-11-14** contra main (`vsieeihstajlrdvpuooh`) y newa (`qhprswhhfasrikhawjoz`), y revisado el 2026-11-19. Cuando los dos difieren, esta spec describe la versión más nueva y dice en cuál proyecto está. El pase de un proyecto al otro está en `tasks/plan_sync_newa_main.md` y no se aplica todavía a main. Desde el 18/11 newa usa la misma zona horaria que main (`America/Havana`).

El Dart arma la llamada. Quién puede vender qué, de qué almacén sale, si el inventario se mueve al pedir o al cobrar, y si un error deja la venta a medias, lo deciden estas RPC. Si el proyecto al que apunta el TPV no tiene la variante nueva, el cliente cae a la anterior y rigen las reglas de esa variante.

La venta que el TPV intenta primero es `fn_registrar_venta_v3` (mesa: `fn_registrar_venta_mesa_v3`). En `funcionalidad_cocina/34_venta_v3_presentaciones.sql` esas funciones se clonan de la v2 viva y solo cambian el descuento: `fn_ejecutar_entrega_fisica_v3` y `fn_descontar_venta_enrutada_v2`. El cuerpo de validación está en `funcionalidad_cocina/11_venta_enrutada.sql`. `sql_updates/fix_venta_rollback_parcial.sql` envuelve cada variante: si la implementación devuelve `status` distinto de `success`, lanza `ROLLBACK_VENTA_PARCIAL` y revierte operación, extracciones y descuentos de esa llamada. Un error a mitad del carrito no deja líneas ya descontadas.

### Qué acepta una venta

Cada línea necesita `id_producto`, `cantidad` y `precio_unitario`. El arreglo de productos no puede ir vacío. El TPV tiene que existir. Si viene `id_cliente`, el cliente tiene que existir. En mesa, la mesa tiene que estar activa y ser de la misma tienda (`MESA_NOT_FOUND`, `MESA_WRONG_TIENDA`).

El producto tiene que ser de la tienda del TPV (`TIENDA_MISMATCH`, `PRODUCTO_NOT_FOUND`). Cantidad menor o igual a cero: `INVALID_QUANTITY`.

Si la línea no trae presentación, o la presentación no existe, el servidor toma la primera de `app_dat_producto_presentacion`. Si el producto no tiene ninguna, esa línea se salta (`CONTINUE`) y la venta sigue con el resto.

Una venta con total 0 inserta ella misma un pago en efectivo de monto 0. El cobro de una venta con importe lo registra después `fn_registrar_pago_venta_*`, no la función de venta.

### De dónde sale el stock

`fn_resolver_origen_venta` clasifica cada línea antes de mover inventario:

| Origen | Cuándo | Qué se descuenta |
|---|---|---|
| `servicio` | Servicio sin elaborado | Nada |
| `barra` | Sin cocina, o el plato tiene stock propio en el almacén del TPV | El SKU en la barra. Si es elaborado con receta y no hay stock de barra, la receta del almacén del TPV |
| `cocina_por_tanda` | Plato de cocina ligada, sin stock en barra, modo por tanda | La porción ya hecha en el almacén de la cocina. La receta no se vuelve a consumir |
| `cocina_al_pedido` | Plato de cocina ligada, modo al pedido | La receta en el almacén de la cocina |

No se puede vender un plato de una cocina a la que el TPV no está ligado (`COCINA_NO_LIGADA`), ni de una cocina inactiva (`COCINA_INACTIVA`), ni de una cocina borrada (`COCINA_NOT_FOUND`), ni un elaborado al pedido sin receta (`SIN_RECETA`). Si no hay ubicación de inventario en el almacén de origen, la venta corta con `NO_LOCATION_FOUND`. En cocina al pedido, si el plato no tiene fila propia, se usa un layout de esa cocina.

Stock corto: `INSUFFICIENT_STOCK` en barra, `INSUFFICIENT_PORTIONS` en porciones de tanda, `INSUFFICIENT_STOCK_INGREDIENT` si falta materia prima. Un descuento de SKU que no consume la cantidad pedida aborta con `DESCUENTO_SKU_INCOMPLETO` para no confirmar un parcial.

En main, `fn_descontar_venta_enrutada_v2` acepta `p_ruta`. Si ese JSON ya trae `status = success` y el mismo `id_producto`, el descuento reutiliza esa ruta y no vuelve a llamar a `fn_resolver_origen_venta`. Si no, resuelve la ruta como antes. Newa ya tiene la misma firma (aplicado el 18/11 con `sql_updates/optimizar_venta_v3_ruta_y_lock_timeout.sql` y `m01_mesa_ruta_y_lock_timeout.sql`), y la venta v3, la de mesa y las cuatro `fn_m01_*` de venta y mesa llevan `lock_timeout = 3s`. La regla que manda es la de main.

`fn_pedir_item_cuenta_v2` mueve ese inventario al pedir, no al cobrar. Exige cuenta existente, estado abierta (`CUENTA_NO_ABIERTA`), TPV en la cuenta (`CUENTA_SIN_TPV`) y acceso a la tienda. Si `p_forzar_sin_stock` es verdadero y no hay stock, la línea entra igual y queda `stock_movido = false`. Al cobrar, `fn_registrar_venta_mesa` no vuelve a descontar una línea que ya movió stock (`funcionalidad_cocina/17_cobro_sin_redescontar.sql`). Una venta de mostrador no busca cuenta abierta: pedir y cobrar son el mismo acto.

La subida offline (`fn_registrar_venta_offline_v4`) exige acceso a la tienda y es idempotente por `client_uuid`: si esa venta ya se subió, devuelve la misma operación y no la duplica. Delega el alta en `fn_registrar_venta_v3`.

### Pago

En main están desplegadas `fn_registrar_pago_venta`, `_v2` y `_v3`. El comentario del script `docs/plan-multimoneda/fase3_1_pago_generico.sql` que dice que la v3 no está en producción está viejo: la función sí está en `vsieeihstajlrdvpuooh`. El archivo `ventiq_app/sql/fn_registrar_pago_venta_idempotente.sql` también se quedó atrás: ahí la v2 convierte a CUP cualquier moneda que no sea USD; en main ya no hace eso.

Las tres exigen que la operación exista, que tenga `importe_total` y que quien la creó esté en `app_dat_vendedor`. El medio de pago tiene que estar activo y el monto mayor que cero. `_v2` y `_v3` reescriben el desglose borrando pagos de esa operación que aún no tienen liquidación. `es_pagada` pasa a verdadero cuando la suma en CUP cubre el importe.

En main, `_v2` solo admite CUP y USD. Otra moneda lanza excepción y el mensaje manda a usar `_v3`. `_v3` consulta el catálogo y rechaza una moneda que no existe o no está activa (`La moneda % no existe o no está activa en el catálogo`). El detalle de cómo el TPV arma esas líneas sigue fuera de esta línea base hasta que se cierre ese trabajo.

### Turno y licencia

`fn_cerrar_turno_tpv` (`sql_updates/fn_cerrar_turno_tpv_idempotent.sql`) exige usuario. Cierra el turno abierto más reciente (`estado = 1`) de ese TPV y ese usuario. Si ya está cerrado (`estado = 2`), devuelve verdadero y no abre otro cierre. Si no hay ninguno, lanza excepción. Si el turno maneja inventario, la lista de productos del conteo es obligatoria y no puede ir vacía.

**Venta offline y pertenencia al turno (2026-11-19).** Una venta pertenece al turno de su TPV y vendedor. El reporte por turno (`fn_reporte_ventas_por_turno`) usa el rango de ids de operación cuando el turno tiene `id_operacion_cierre`. Si no lo tiene, usa la fecha de cierre (o `now()` si sigue abierto) y nunca pasa de la siguiente apertura del mismo TPV y vendedor. En newa, la apertura reutilizada o repetida recupera la hora real con `fn_turno_alinear_fecha_apertura` (solo hacia atrás, tope 72 h, sin pisar el turno anterior; script 56). En el cliente, `UserPreferencesService.aperturaMasTemprana` conserva la apertura más temprana al fusionar la local con la del servidor, las órdenes ya sincronizadas del turno abierto siguen en la cola hasta el cierre y no se cuentan como pendientes, y `created_offline_at` no se pisa si el checkout ya mandó la hora corregida con `ServerTimeService`. Tests: `apertura_mas_temprana_test.dart`, `fecha_rpc_test.dart`, `cadena_por_clave_test.dart`. Main todavía no tiene `fn_turno_alinear_fecha_apertura`.

`fn_obtener_licencia_firmada` devuelve error si la tienda no tiene suscripción con `estado = 1`. El secreto HMAC vive en una tabla con RLS y sin políticas; no se documenta aquí.

### Quién lee la configuración de la tienda

La versión nueva está en newa y main todavía no la aplica. En newa, `app_dat_configuracion_tienda` tiene RLS y cuatro políticas. Escriben el dueño, el gerente y el superadmin de nivel 1 (`fn_config_tienda_puede_escribir`). Leen esos mismos roles más el supervisor, el auditor y el vendedor de un TPV de esa tienda (`fn_config_tienda_puede_leer`). `fn_config_tienda_exigir_lectura` corta con `42501` si la lectura no está permitida; `service_role` pasa. En main la tabla tiene RLS apagado y cero políticas, así que esa restricción hoy no corre en producción.

El TPV sigue leyendo los mismos flags. Cuando el pase se aplique, un vendedor de la tienda tiene que seguir pudiendo leerlos.

## Code Style

**Observado.** Servicios de una sola instancia, métodos async que atrapan el error, lo registran con `print` y relanzan o devuelven un valor seguro. Precios mostrados con separador de miles (espacio fino) y 2 decimales. UI en español. Navegación por nombre de ruta (`Navigator.pushNamed`).

```dart
class PriceUtils {
  static String formatAmount(
    num amount, {
    int decimals = 2,
    String separator = '\u202F',
  }) {
    final parts = amount.toStringAsFixed(decimals).split('.');
    final integer = parts.first.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]}$separator',
    );
    return parts.length == 1 ? integer : '$integer.${parts.last}';
  }
}
```

Lints: `flutter_lints` vía `analysis_options.yaml`, sin reglas extra activas. `avoid_print` sigue activo en el paquete y el código de servicios imprime igual.

Convención de RPC: llamar la variante nueva (`_v3`, `_v4`) y, solo si PostgREST responde que la función no existe, caer a la anterior. Otro error no se disfraza de "función ausente".

## Testing Strategy

**Observado.** `flutter_test` dentro de `ventiq_app/test`. No hay un umbral de cobertura escrito. Los tests de esta línea base son de contrato y de widget sobre home, mesas, ingredientes, desarme de bulto, SMS bancario e impresión Sunmi. `test/home/app_compile_test.dart` comprueba que el paquete analiza.

**Decidido.** Los tests de moneda (`*_multimoneda*`, `moneda_venta_*`, `checkout_payment_lines_test.dart`, `order_usd_payments_test.dart`, `payment_currency_amounts_test.dart`) no son criterio de esta línea base. Pasan a serlo cuando se cierre ese trabajo y se actualicen esta spec y la de admin. Estado al 19/11: la suite completa de `ventiq_app` corre y 594 casos pasan; falla solo `widget_test.dart`, la plantilla de contador, que no es de moneda. El caso del 429 de `session_refresh_service_test.dart` se corrigió el 20/11: el servicio usa `AuthState.signOutReason` de gotrue 2.26 (`supabase_flutter ^2.16.0`) para distinguir un cierre del usuario de uno que el SDK provoca al fallar el refresh. Siguen sin ser criterio de esta línea base hasta que M01 esté en main.

**Inferido.** Una venta cobrada, su fila en Supabase y el ticket impreso no los cubre la suite local.

## Boundaries

- **Always:** Reusar el sync de productos para el catálogo offline. Invalidar el detalle en memoria después del merge. Dejar las órdenes pendientes. Comprobar ingredientes de servicio contra el almacén del TPV. Tratar la licencia como módulo de sync obligatorio. Caer de RPC nueva a vieja solo cuando la función no está desplegada. Correr `flutter test` del área tocada antes de dar por cerrado un cambio de esta app.
- **Ask first:** Cambiar el esquema o una RPC que esta app llama. Añadir una dependencia. Reabrir Admin Lite o poner `enableDeviceFullOffline` en `true`. Cambiar el orden de `NavigationHelper.homeRoute`. Activar o apagar `kPreorderStyled`. Quitar `/categories-mobile` y `/categories-web` (limpieza opcional).
- **Never:** Documentar aquí el comportamiento de `ventiq_admin_app`, Muevete o Flow. Tratar `tasks/SPEC-product-currency-*` como cerrados. Borrar órdenes pendientes al actualizar productos. Crear un segundo catálogo offline. Copiar secretos de `msix_config` a docs, commits o logs. Dar por buena una venta solo con tests locales.

## Success Criteria

1. Con licencia y `entryRole` vendedor, el splash abre `/categories`, `/mesas`, `/servicentro` o `/kds` según la tabla de home, y no `/admin-home`.
2. Sin licencia, el splash abre `/subscription-detail`.
3. Una venta de mostrador online termina en `fn_registrar_venta_v3` o, si esa función no existe, en `fn_registrar_venta`, y el pago en la cadena `fn_registrar_pago_venta_v3` → `_v2` → sin sufijo.
4. Con `modo_restaurante` y sin mostrador activo, el carrito no abre `/preorder`: abre la cuenta de mesa o `/mesas`.
5. Con mostrador activo, el carrito abre `/preorder` aunque la tienda sea restaurante. Al reiniciar, el mostrador no sigue activo.
6. Servicentro y restaurante no comparten home: si el TPV es servicentro, `homeRoute` devuelve `/servicentro`.
7. Offline, el catálogo leído es el de `offline_products` (o el JSON de preferencias en web). Una orden que no pudo subirse sigue en la cola `uploadSales` después de un sync de productos.
8. Un cierre no subido aparece en el drawer y en `/cierre-pendiente`.
9. Login offline rechaza un usuario cacheado cuyo `entryRole` no es `vendedor`.
10. `flutter test --no-pub test/home/app_compile_test.dart` pasa.
11. Una línea rechazada por la RPC de venta (`status` distinto de `success`) no deja operación ni descuento de las líneas anteriores de esa misma llamada: el wrapper revierte con `ROLLBACK_VENTA_PARCIAL`.
12. Un plato de cocina sin stock en la barra no se descuenta del almacén del TPV. Sale de la cocina ligada, como porción hecha o como receta, según `fn_resolver_origen_venta`.
13. Pedir un ítem de cuenta mueve el inventario. Cobrar esa misma línea en `fn_registrar_venta_mesa` no lo mueve otra vez.

## Decisiones de esta línea base

1. Admin Lite queda implementado y cerrado en el vendedor. El candado es el `entryRole` `vendedor`.
2. La preparación del dispositivo y el selector de usuario offline quedan apagados con Admin Lite. `enableDeviceFullOffline` sigue en `false`.
3. Al cerrar moneda y precio vigente se actualizan `SPEC-ventiq-app.md` y la spec de admin con lo implementado en cada una.
4. Los tests de moneda no cuentan como criterio de esta línea base hasta ese cierre.
5. **Opcional.** Borrar `/categories-mobile` (`CategoriesScreen`) y `/categories-web` (`CategoriesWebScreen`). Hoy ninguna pantalla las abre. El home nuevo ya muestra el changelog, el splash ya comprueba actualizaciones y el modo fluido está retirado. Se conservan como vuelta atrás. No bloquean esta spec.

## Open Questions

Ninguna. Lo único pendiente de código en esta app, y sin fecha, es la limpieza opcional del punto 5.

## Dependencias que esta app no posee

- Alta de tienda, catálogo maestro, recetas, listas de precio y flags de `app_dat_configuracion_tienda`: los escribe administración. Aquí se leen.
- Esquema, RLS y cuerpos de las RPC: `supabase/` y `sql_updates/`. El TPV asume que la variante que llama puede no estar desplegada y por eso tiene fallback.
- `ventiq_admin_app`, `inventtia_muevete` e `inventtia_flow` no se describen en este archivo.
- El costo por producto en la recepción (`app_dat_producto_costo`, `app_dat_recepcion_producto_costo`) y el gasto del fondo (`fn_fdi_gasto`, `fdi_dat_liquidacion.repartir_igual`) están más nuevos en newa. No cambian el cobro del TPV. El pase a main está en el plan de sincronización, no en esta spec.
