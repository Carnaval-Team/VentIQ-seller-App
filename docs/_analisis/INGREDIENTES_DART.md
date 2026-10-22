# INGREDIENTES_DART — Venta de elaborados y cartel de «stock insuficiente» en `ventiq_app`

**Alcance:** `ventiq_app/lib` (TPV Inventtia Caja). Solo lectura de código; no se ejecutó
`flutter analyze`/`build`/`run`. Todas las afirmaciones van con `ruta:línea`.

**Método:** lectura con `read`/`grep`/`glob` sobre el workspace. El root de análisis
`file:///C:/Users/cesar/Documents/VentIQ-seller-App/ventiq_app` quedó registrado en el MCP
de Dart (`mcp__dart__roots`), pero no se invocó ninguna herramienta que compile el proyecto.

**Límite importante de entorno:** el MCP de Supabase de esta sesión apunta a **producción**
(`https://vsieeihstajlrdvpuooh.supabase.co`, verificado con `supabase get_project_url`). El
caso reportado ocurre en el proyecto **debug `qhprswhhfasrikhawjoz`**
(`ventiq_app/lib/config/supabase_config.dart:5` y `:14`), al que **este entorno no tiene
acceso**. Por eso el backend del caso se analiza desde el SQL versionado del repo y desde el
comportamiento defensivo del cliente, no desde `pg_proc` del proyecto debug.

---

## 0 · Resumen ejecutivo

El vendedor vende **un elaborado** («arroz moro», producto 5, receta con arroz 3 y frijoles 4
— ids del proyecto debug). Hay **cinco emisores** distintos de un cartel de stock insuficiente
y **ninguno** de ellos resuelve el ingrediente por equivalente base ni rebalancea sus
presentaciones:

| # | Emisor | Dónde | ¿Bloquea? | ¿Modo? |
|---|---|---|---|---|
| 1 | **Servidor** `INSUFFICIENT_STOCK_INGREDIENT` | `funcionalidad_cocina/01_helpers_bom_almacen.sql:181-195` vía `fn_pedir_item_cuenta` / `fn_registrar_venta*` | Sí | Con red |
| 2 | **Servidor** `INSUFFICIENT_STOCK` (rebalanceo) | `fn_registrar_venta`/`_mesa` → `fn_rebalancear_presentaciones` (SQL versionado) | Sí | Con red |
| 3 | **Servidor** `INSUFFICIENT_PORTIONS` | `funcionalidad_cocina/10_enrutamiento_venta_cocina.sql:453` | Sí | Con red |
| 4 | **Cliente** `getProductIngredients` + `_showStockAlert` «⚠️ Stock Insuficiente» | `preorder_screen.dart:2702` alimentado por `product_detail_service.dart:549-559` | No (solo avisa) | Con red |
| 5 | **Cliente** `DesarmeBultoLocal` / `_avisarStockInsuficienteOffline` | `product_details_screen.dart:3703-3704` → `:3436-3461` | Sí | **Sin red** (caché) |

El cartel que el usuario describe —«sólo cuenta la presentación base en gramos, ignorando
kg»— encaja con **#4** (es el único que imprime la unidad de la receta: `Necesario: X <unidad>`
/ `Disponible: Y <unidad>`, `preorder_screen.dart:2824-2828`) y con **#1** si el backend del
proyecto debug no tiene aplicada `presentaciones_inventario/27_stock_almacen_en_base.sql`
(§9.6 del tutorial, ver §7). **#5** es la única vía que produce un falso positivo sin red, y
sólo dispara si el elaborado tiene filas de inventario propias en caché.

La causa raíz común de #4 y de la validación de cliente (#3 del §4) es la misma:
**`getProductIngredients` toma UNA fila de `app_dat_inventario_productos` (la de `created_at`
más reciente) y la compara cruda contra `cantidad_necesaria × cantidad` de la receta, sin
convertir a equivalente base ni sumar las demás presentaciones** (`product_detail_service.dart:549-559`,
`preorder_screen.dart:1380`).

> **Añadidos posteriores (preguntas del lead):** §10 responde quién elige la presentación del
> **ingrediente** (nadie en el cliente: la elige el servidor, y por eso «a veces gramo, a veces
> kg»), §11 mapea **qué texto exacto ve el vendedor** en cada emisor (`message` del servidor vs
> texto propio del cliente) y §12 lista los **fallbacks del cliente ante RPC ausentes** en el
> proyecto debug.

---

## 1 · Cómo llega una venta de elaborado al servidor (rutas completas)

### 1.1 · Detalle de producto (ruta normal del TPV) — `product_details_screen.dart`

Punto único de entrada al carrito: `_addToCart` (`product_details_screen.dart:3624`).

- **Antes de tocar el carrito** evalúa el desarme (`:3661-3736`):
  - `useLocalData = shouldUseLocalData()` (`:3691-3692`).
  - **Offline** → `DesarmeBultoLocal.evaluar` con la cadena y los saldos locales
    (`:3696-3701`); `esImposible` → `_avisarStockInsuficienteOffline` y `seguir = false`
    (`:3703-3705`); `requiereDesarme` → diálogo de confirmación (`:3706-3713`).
  - **Online** → `PreviewRebalanceoService.consultar` + `confirmarSiHaceFalta`
    (`:3716-3728`), que llaman `fn_preview_rebalanceo` (`preview_rebalanceo_service.dart:115-125`).
  - La compuerta es `idPresPreview != null && idUbicPreview != null` (`:3680-3682`),
    sacados de `_buildInventoryData` (`:3550-3613`). Para un elaborado sin filas de
    inventario propias, `inventoryMetadata` es `null` y `_buildInventoryData` devuelve
    `id_ubicacion: null, id_presentacion: null` (`:3567-3578`), así que **todo el bloque se
    salta**.
- **Payload de venta** (`:3759-3774`):
  - `cantidad = selectedQuantity` (**en la presentación elegida**, no en base) y
    `precioUnitario = finalPrice × conversionFactor` (`:3759-3761`).
  - `inventoryData = _buildInventoryData(...)` → `id_producto`, `id_variante`,
    `id_ubicacion`, `id_presentacion` (presentación **elegida**),
    `presentacion_nombre`, `presentacion_factor_rel` (`:3597-3605`).
  - Llama `orderService.addItemToCurrentOrder(...)` con **`await`** (`:3766-3774`).
- **Errores:** el `catch` genérico muestra un snackbar rojo con `e.toString()`
  (`:3912-3925`). **No hay rama para `PedidoException`**: el `error_code` del servidor nunca
  se lee en la UI (ver §3).

### 1.2 · `order_service.addItemToCurrentOrder` — la bifurcación real

`order_service.dart:142-231`:

- Con **cuenta de mesa activa** y `SalesModeService.mostradorActivo == false` (`:156-158`):
  - `StoreConfigService.cocinaActivaSync == true` → **`MesaCuentaService.pedirItem`**
    (`:186-201`), que llama la RPC **`fn_pedir_item_cuenta`** con
    `p_id_presentacion` incluido (`mesa_cuenta_service.dart:282-303`) y `p_cantidad` tal cual
    (presentación elegida).
  - `cocinaActivaSync == false` → `MesaCuentaService.agregarItem` (`:204-220`): la línea queda
    con `stock_movido = false` y el inventario se mueve al cobrar.
  - Los dos `catch` releen la excepción (`:225-229`), así que `PedidoException` sube a la
    pantalla.
- Sin cuenta de mesa: carrito local (`:233+`). La presentación se congela con
  `_datosPresentacion` (`:126-140`) y `item.cantidad` sigue en la presentación elegida.

`_registerSaleInSupabase` (`order_service.dart:1279-1552`) arma
`p_productos` con **sólo el producto vendido** (`:1344-1358`): `id_presentacion` +
`cantidad` en presentación + `precio_unitario × factor` + `es_producto_venta: true`. El bloque
que añadía los ingredientes descompuestos está **comentado** (`:1360-1385`). La RPC es
`fn_registrar_venta_mesa` si hay `id_mesa`, si no `fn_registrar_venta` (`:1442-1461`).
Conclusión: **el TPV no manda la receta al servidor en la ruta online; el servidor la
reconstruye por producto.**

### 1.3 · Preorden / cobro y proceso de elaborados — `preorder_screen.dart`

- `_finalizeOrder` (`:848-1054`) valida stock **siempre** antes de cobrar
  (`_checkInventoryAvailability`, `:926-929`) y **corta la venta** si hay problemas
  (`:932-935`).
- `_processElaboratedProducts` (`:2023-2277`) corre después, en las tres salidas
  (`:1016`, `:1035`, `:1042`), y en modo **online** con `permiteVenderAunSinDisponibilidad`
  en falso llama además `_checkIngredientsAvailability` (`:2125-2159`), que es el emisor #4.
- Descompone la receta en Dart (`_decomposeElaboratedProducts` `:2280-2345` →
  `_decomposeRecursively` `:2348-2391` → `ProductDetailService.getProductIngredients`) y
  guarda el resultado en `item.inventoryData['decomposition_data']`
  (`_updateOrderWithDecomposedProducts`, `:2411-2476`). **Ese mapa lo ignora el envío de la
  venta** (bloque comentado en `order_service.dart:1360`).
- Offline directo: `_submitOrderOfflineDirect` (`:1894-2019`) **omite la rebaja de stock local
  de elaborados y servicios** (`:1976-1977`).

### 1.4 · Modo fluido — `fluid_product_details_widget.dart` + `fluid_mode_screen.dart`

- El widget sólo **construye** `OrderItem`s y los devuelve por callback:
  `_createOrderItems` (`fluid_product_details_widget.dart:572-644`) y
  `widget.onCompleted(orderItems)` (`:646-659`). Nunca llama al `OrderService`.
- `fluid_mode_screen.dart:66-71` guarda esos ítems en `_orderItems` y avanza al paso de pago,
  pero **jamás los agrega a la orden**: `_processOrder` (`:87-106`) llama
  `_orderService.finalizeCurrentOrder(...)` **sin `await` y sin haber cargado los ítems**. Con
  un carrito vacío esa llamada lanza `'No hay productos en la orden'`
  (`order_service.dart:862-863`) y la excepción se pierde (no hay `await`). **La ruta de venta
  del modo fluido es un no-op hoy**, no una ruta de consumo de elaborados.

### 1.5 · Mesa — `mesa_cuenta_service.dart`, `cuenta_mesa_screen.dart`, `mesa_detail_screen.dart`

- `cuenta_mesa_screen.dart:18-27` documenta el flujo: agregar productos va a
  `agregarOrderItem`/`pedirItem` con la cuenta activa; «Cerrar Nota» hidrata una `Order` y
  cobra por `fn_registrar_venta_mesa`.
- `pedirItem` (`mesa_cuenta_service.dart:263-315`) manda `p_id_presentacion` (`:291`) y
  `p_inventory_data` completo (`:296`), y lanza `PedidoException` si `status != 'success'`
  (`:310-312`).
- `cancelarItemPedido` (`:357-376`) puede devolver `INSUFFICIENT_*` u otros códigos, también
  como `PedidoException` (`:371-373`).
- `loadPreorderFromCuenta` (`order_service.dart:959-1058`) reconstruye los ítems con
  `idPresentacion` de la cuenta (`:1000`, `:1029`) y `stock_movido` (`:1009`) para no contar
  doble al cobrar.
- `cuenta_mesa_screen.dart` no llama ninguna RPC de validación por su cuenta: sólo
  `actualizarCantidad`/`eliminarItem`/`cancelarCuenta` (`:105`, `:140`, `:178`).

### 1.6 · Cola offline de cocina — `cocina_offline_queue.dart`

Define `encolarPedido` y la RPC `fn_pedir_item_cuenta_offline` (`:81`, `:198`, `:284`) y
lanza `PedidoException` (`:317`), pero **no tiene ni un solo llamador en `lib`** (grep de
`CocinaOfflineQueue` sólo devuelve su propia definición). Es código muerto: hoy un pedido de
cocina sin red no se encola, la excepción llega a la pantalla.

### 1.7 · Venta por acuerdo (admin dentro del TPV) — `admin_sale_agreement_screen.dart` + `admin_inventory_service.dart`

- La pantalla arma una línea por presentación con `id_presentacion`, `cantidad` y precio
  ×factor (`admin_sale_agreement_screen.dart:159-208`, `:273-274`).
- `registerSaleByAgreement` (`admin_inventory_service.dart:1190-1254`) aplica
  `_applyStockDeltaLocally` a **todas** las líneas (`:1229-1238`) **sin excluir elaborados ni
  servicios** — divergencia con `checkout_screen.dart:2183-2190` y
  `preorder_screen.dart:1976-1977`, que sí los excluyen. El envío va por
  `fn_admin_caja_venta_acuerdo_offline` con fallback a `fn_registrar_venta`
  (`:1756-1821`).

### 1.8 · Tandas / producción — `produccion_screen.dart` + `comanda_service.dart` + `tanda.dart`

Consume materia prima de recetas por otra vía: `_producir` → `ComandaService.producirTanda`
(`produccion_screen.dart:116-141`, `comanda_service.dart:221-229`, RPC `fn_producir_tanda`).
El error de stock es `TandaException` con `INSUFFICIENT_STOCK` (`tanda.dart:307`) y
`faltantes` por ingrediente (`:299`, `:330-338`); `produccion_screen.dart:141` los muestra.
No hay validación de cliente.

### 1.9 · Edición de pendientes y lectura de órdenes — `order_service.dart`, `orders_screen.dart`

`editPendingOrderV2` / `updatePendingOrderItemQuantity` / `removePendingOrderItem` /
`addProductToPendingOrder` (`order_service.dart:2827-2959`) delegan toda la validación en
`fn_editar_orden_pendiente_v2`, `fn_actualizar_cantidad_producto_orden`,
`fn_eliminar_producto_orden` y `fn_agregar_producto_orden_pendiente`. No reenvían
`id_presentacion` explícito salvo lo que venga en `p_producto`.
`orders_screen.dart:5694-5741` sólo carga ingredientes **para imprimir/ver** (nombre,
`cantidad_necesaria`, `unidad_medida`), sin tocar inventario.

---

## 2 · Dónde se origina exactamente cada cartel

### 2.1 · Emisor #4 — «⚠️ Stock Insuficiente» con unidad de la receta (el que coincide con el reporte)

`preorder_screen.dart`:

- Título literal: `_showStockAlert(title: '⚠️ Stock Insuficiente', message: 'Los siguientes
  ingredientes no tienen stock suficiente:', isError: true)` → **`preorder_screen.dart:2700-2706`**.
- Cuerpo por ingrediente: `'Necesario: ${necesaria.toStringAsFixed(2)} $unidad'`
  (`:2824`) y `'Disponible: ${disponible.toStringAsFixed(2)} $unidad'` (`:2828`).
  `unidad` sale de `ingrediente['unidad_medida']` (`:2665`, `:2770`), o sea **la unidad de la
  receta**, mientras `disponible` es la `cantidad_final` cruda de **una sola** fila de
  inventario (`product_detail_service.dart:549-559`). Si la fila elegida está en kg y la receta
  en gramos (o al revés), los dos números se comparan sin conversión: **falso faltante**.
- Alimentación: `_checkIngredientsAvailability` (`:2643-2718`); el umbral es
  `cantidadDisponible < cantidadTotalNecesaria` (`:2677`) con
  `cantidadTotalNecesaria = cantidadNecesaria × cantidadProducto` (`:2667`).
- Se dispara **sólo con red** y sólo cuando `permiteVenderSinDisponibilidad == false`
  (`:2125-2159`). **No bloquea**: tras el diálogo el flujo continúa
  (`:2161+` → `_updateOrderWithDecomposedProducts` → checkout/venta).

### 2.2 · Emisor #4-bis — «Problema de Inventario» (mismo origen, pero bloqueante)

`_checkInventoryAvailability` (`preorder_screen.dart:1271-1594`) usa para elaborados la
**misma** fuente:

- Online: `getProductIngredients` (`:1355-1356`) y comparación cruda
  `cantidadDisponible < cantidadNecesaria` (`:1380`).
- Offline: receta desde `detalles_completos['ingredientes']` (`:1311-1312`); si no hay receta
  en caché **se permite continuar** (`:1318-1323`). Ver §5: ningún escritor del caché guarda
  `ingredientes`, así que esta rama es inerte.
- El resultado se muestra en `_showStockProblemsDialog` (título **«Problema de Inventario»**,
  `:1655-1660`, con chips «Pedido / En stock / Faltante» `:1700-1725`) y **corta la venta** en
  `_finalizeOrder` (`:932-935`).

### 2.3 · Emisor #5 — «No hay suficiente» offline (cliente, sin red)

`product_details_screen.dart`:

- `_avisarStockInsuficienteOffline` (`:3436-3461`): título **«No hay suficiente»** (`:3444`) y
  cuerpo `'No alcanza el stock disponible. Como máximo se pueden servir N.'` (`:3448-3451`).
- Se llama cuando `DesarmeBultoLocal.evaluar(...).esImposible` con `useLocalData == true`
  (`:3695-3705`).
- `DesarmeBultoLocal.evaluar` (`desarme_bulto_local.dart:79-156`) calcula
  `equivalente = Σ (saldo(p) × factorRel(p)/factorRel(pedida))` (`:96-102`); si `cadena` vacía o
  la presentación pedida no está en la cadena devuelve `_alcanza` para no bloquear (`:85-89`,
  `:158`). Es un cálculo **correcto para un producto normal**; el problema es que se ejecuta
  también cuando el producto es un elaborado con filas de inventario propias.
- Hermano online: `PreviewRebalanceoService._avisarImposible` (`preview_rebalanceo_service.dart:196-222`),
  mismo texto «No hay suficiente», alimentado por `estrategia = 'imposible'` de
  `fn_preview_rebalanceo` (`:183-186`).

### 2.4 · Emisores #1-#3 — códigos del servidor y qué hace el cliente con ellos

| `error_code` | Quién lo produce (SQL versionado) | Cómo llega al vendedor |
|---|---|---|
| `INSUFFICIENT_STOCK` | `fn_rebalancear_presentaciones` consumida por `fn_registrar_venta`/`_mesa` | `order_service.dart:1542-1547` → `success:false` + `response['message']`; se muestra en snackbar (`preorder_screen.dart:1868-1875`) o en el checkout |
| `INSUFFICIENT_STOCK` (tandas) | `fn_producir_tanda` | `TandaException` (`tanda.dart:307`) → `produccion_screen.dart:141` |
| `INSUFFICIENT_STOCK_INGREDIENT` | `fn_validar_ingredientes_elaborado` (`01_helpers_bom_almacen.sql:181-195`) y `fn_descontar_ingredientes_elaborado` (`:322-336`) | `PedidoException` (`pedido_resultado.dart:180-183`) si viene de `fn_pedir_item_cuenta`; o `success:false` si viene de la venta |
| `INSUFFICIENT_PORTIONS` | enrutamiento de venta a cocina (`10_enrutamiento_venta_cocina.sql:453`) | `PedidoException` (`pedido_resultado.dart:182`) |

El mensaje del servidor para ingredientes es literalmente
`'Stock insuficiente para el ingrediente: <denominación> (disponible: X, requerido: Y)'`
(`01_helpers_bom_almacen.sql:184-187`) — **sin unidad**, dos números crudos. La segunda rama
dice `'(faltan N)'` (`:325-329`).

**Lo que hace el cliente con esos códigos:** casi nada.
- `PedidoException.titulo` mapea `esFaltaDeStock` a «Sin existencias» / «Sin porciones
  preparadas» (`pedido_resultado.dart:189-199`), pero **ese getter no se usa en ninguna
  pantalla** (grep de `PedidoException` en `lib` sólo devuelve el modelo y los dos servicios
  que lo lanzan).
- `product_details_screen.dart:3912-3925` lo degrada a snackbar genérico
  `'❌ Error al agregar: ${e.toString()}'`; `PedidoException.toString()` devuelve el `mensaje`
  del servidor (`pedido_resultado.dart:230-231`).
- `PedidoResultado.avisoStock` / `sinStockDescontado`
  (`pedido_resultado.dart:40-42`, `:70`, `:89-91`) existe para el caso `forzarSinStock` y
  **tampoco se consume en la UI**.
- `forzarSinStock` sólo se usa desde `mesa_cuenta_service.pedirOrderItem`
  (`mesa_cuenta_service.dart:319-350`), sin llamadores en pantallas.

---

## 3 · Qué valida el cliente ANTES de mandar la venta de un elaborado

| Validación | ¿Se usa? | Archivo:línea | Unidad que compara |
|---|---|---|---|
| `fn_preview_rebalanceo` | Sí, pero **sólo para el producto vendido y sólo si tiene `id_presentacion`/`id_ubicacion`** | `preview_rebalanceo_service.dart:106-136`; llamada en `product_details_screen.dart:3716-3728` y `preorder_screen.dart:1498-1509` | Presentación elegida (equivale a base vía factor) |
| `fn_disponibilidad_plato` | **No** desde `ventiq_app` (sólo existe en SQL y en `ventiq_admin_app/lib/services/cocina_service.dart:281`) | — | — |
| `fn_validar_ingredientes_elaborado` | **No** desde `ventiq_app` (sólo SQL; la app la llama indirectamente vía `fn_pedir_item_cuenta`) | `funcionalidad_cocina/01_helpers_bom_almacen.sql:145` | Unidades base (`fn_stock_producto_almacen` × receta) |
| Caché offline de ingredientes | Sí, pero **inerte** (nunca hay receta en caché) | `preorder_screen.dart:1292-1352` | Receta × `_getStockFromCache` |
| `getProductIngredients` (lectura directa a Supabase) | Sí — **ésta es la validación real de cliente** | `product_detail_service.dart:506-593` | `cantidad_final` de **una fila** vs receta |
| `DesarmeBultoLocal` | Sí, offline, para el producto vendido | `product_details_screen.dart:3696-3701`, `desarme_bulto_local.dart:79-184` | Equivalente base (correcto) |

**La validación de cliente de un elaborado se pide en la unidad de la receta, pero el
disponible se lee en la presentación de una fila arbitraria de inventario.** No hay ninguna
conversión de unidad ni suma por presentaciones en `getProductIngredients`:

```dart
// product_detail_service.dart:549-559
final inventoryResponse = await _supabase
    .from('app_dat_inventario_productos')
    .select('cantidad_final')
    .eq('id_producto', idIngrediente)
    .order('created_at', ascending: false)   // ← la MÁS RECIENTE, no la base ni la suma
    .limit(1);
```

```dart
// preorder_screen.dart:1367-1380
final cantidadNecesaria =
    ((ingrediente['cantidad_necesaria'] as num?)?.toDouble() ?? 0.0) * item.cantidad;
final cantidadDisponible =
    (ingrediente['cantidad_disponible'] as num?)?.toDouble() ?? 0.0;
...
if (cantidadDisponible < cantidadNecesaria) { problems.add({...}); }
```

Nótese que el resultado **no pasa por `PresentacionCadenaLocal` ni por
`DesarmeBultoLocal`**: no hay `factorRel`, no hay cadena del ingrediente, no hay
`id_presentacion`, no hay rebalanceo.

---

## 4 · Caché offline: representación de presentaciones y falsos positivos

### 4.1 · Cómo se construye el caché (`auto_sync_service._syncProducts`)

`auto_sync_service.dart:457-614`:

- `detalles_completos` = respuesta cruda de `get_detalles_productos_batch`
  (`:506-521`), normalizada por `_normalizeInventarioUbicaciones` (`:522`, definida en
  `:637-690`) y con `cantidad` alineada por `_alignProductCantidadWithInventario`
  (`:523`, definida en `:618-633`, que **suma** `cantidad_disponible` de todas las filas).
- `presentaciones` se guarda a nivel de producto con `id`, `id_producto`, `id_presentacion`,
  `cantidad`, `es_base` y el nomenclador anidado (`:537-571`). Es la forma que lee
  `PresentacionCadenaLocal.extraerCrudas` (`presentacion_cadena_local.dart:77-99`).
- El payload del RPC tiene `producto` (con `presentaciones` dentro, `sql_offline/01_get_detalles_productos_batch.sql:138-150`)
  e `inventario` (`:166-222`), y **no tiene `ingredientes`** (grep sin resultados en
  `ventiq_app/sql_offline/`). Consecuencia directa: `preorder_screen.dart:1311-1312`
  (`detalles?['ingredientes']`) lee siempre `null` y la validación offline de receta cae en
  «se permite continuar» (`:1318-1323`). **El caché no puede producir por sí mismo un falso
  «stock insuficiente» de ingredientes**, porque no valida ingredientes sin red.

### 4.2 · Dónde SÍ se colapsa un ingrediente con kg + gramos

```dart
// inventory_service.dart:185-203
Map<String, dynamic>? bestRow;
double sumQty = 0;
for (final inv in inventarioList) {
  ...
  sumQty += qty;
  bestRow ??= inv;          // ← se queda con la PRIMERA presentación
}
...
final presentacion = bestRow?['presentacion'] is Map ? ... : null;
```

- `buildFromOfflineCache` (`inventory_service.dart:125-152`) indexa **por `productId`**
  (`byId[productId]`), así que un producto con varias presentaciones entra **una sola vez**
  (`:133-141`). `_inventoryProductFromOfflineMap` **suma** los saldos de todas las
  presentaciones (`:187-195`) y se queda con la primera como `id_presentacion` (`:194`,
  `:203`) — un kg y unos gramos quedan fundidos en un número que ya no es de ninguna unidad.
  El caché devuelve **una fila por producto, no una por presentación**.
- `apertura_screen.dart:781-799` repite el colapso en la UI: agrupa «SOLO por id_producto
  (sin considerar ubicaciones ni presentaciones)» (`:781`) y **descarta duplicados** (`:789-799`).
  Ambos coinciden con el pendiente documentado en `docs/PLAN_PRESENTACIONES_INVENTARIO.md:523`.
- `InventoryProduct` de elaborados/servicios se descarta explícitamente
  (`inventory_service.dart:165-169`), y `apertura_screen.dart:785` también los salta.

### 4.3 · Delta de stock local

- `updateProductInventoryInCache` (`user_preferences_service.dart:1867-2034`) **sí** filtra por
  presentación (`:1930-1944`) y **no** tiene fallback silencioso cuando `presentationId != null`
  (`:1994-2015`); la firma es `num` para no truncar fracciones (`:1865-1866`, `:1969-1977`).
  Es correcto **si el llamador pasa la presentación**.
- Llamadores que la pasan: `checkout_screen.dart:2205-2214`, `preorder_screen.dart:1982-1997`,
  `admin_inventory_service._applyStockDeltaLocally` (`:1367-1379`).
- **El delta nunca se aplica a los ingredientes de un elaborado**: `checkout_screen.dart:2183-2190`
  y `preorder_screen.dart:1976-1977` lo omiten a propósito (comentario en `checkout_screen.dart:2177-2182`),
  pero **`admin_inventory_service.dart:1229-1238` no omite nada** → en venta por acuerdo el
  elaborado recibe un delta local sobre una fila que representa su propio (inexistente) stock.
- Riesgo de «falso stock» offline: como el caché **no** rebaja ingredientes, tras vender
  elaborados sin red el saldo de arroz/frijoles sigue igual hasta la sincronización; el
  vendedor puede vender de más y el error real aparece al sincronizar
  (`auto_sync_service.dart:3907-3960`, RPC `fn_registrar_venta_offline_v3` → fallback
  `fn_registrar_venta`, `:4010-4072`).
- `_getStockFromCache` (`preorder_screen.dart:1060-1144`) tiene un segundo colapso: recorre las
  filas y **devuelve la primera que casa** (`matched = qty; break;`, `:1125-1131`), no la suma;
  el `invSum` de respaldo sólo se usa si `matched == null` (`:1132`). Con `idPresentacion == null`
  (el caso de los ingredientes, `:1337-1339`) **siempre casa la primera fila**. Hoy no se explota
  porque la rama offline de elaborados es inerte (§4.1), pero es una trampa latente.

### 4.4 · Presentación de la cadena (lado correcto)

`PresentacionCadenaLocal.resolverDesdeCrudas` (`presentacion_cadena_local.dart:111-196`)
replica `fn_presentaciones_producto`: base por `es_base DESC, cantidad ASC, id ASC`
(`:154-166`) y `factorRel = cantidad / cantidad_de_la_base` (`:184-186`). Es la pieza que
**haría falta reutilizar por ingrediente** y hoy no se usa en ninguna de las dos validaciones
de ingredientes.

---

## 5 · Modo con/sin conexión: qué se dispara en cada caso

| Escenario | Vía | Resultado |
|---|---|---|
| Online, `permiteVenderSinDisponibilidad = false`, vende elaborado | `preorder_screen.dart:2149` → `getProductIngredients` | Emisor #4 («⚠️ Stock Insuficiente», **no bloquea**) y, si también hay problema en `_finalizeOrder`, emisor #4-bis («Problema de Inventario», **bloquea**) |
| Online, `permiteVenderSinDisponibilidad = true` | `:2141-2144` | Se salta la verificación de ingredientes; sólo queda #4-bis en `_finalizeOrder` |
| Online, RPC de ingredientes cae por red | `product_detail_service.dart:589-592` (`catch` → `[]`) | `preorder_screen.dart:1358-1363` «sin ingredientes definidos, se permite continuar» → **no hay cartel** |
| Online, `fn_preview_rebalanceo` no existe / falla | `preview_rebalanceo_service.dart:131-135` | Devuelve `PreviewRebalanceo.sinConversion` (`:67-70`) → **no hay cartel**, la venta sigue y el error real lo da el servidor |
| Sin red (modo offline o full offline), vende elaborado | `preorder_screen.dart:1292-1323` | Receta no está en caché → **se permite continuar**; no hay validación de ingredientes |
| Sin red, el elaborado tiene filas de inventario propias en caché y `id_presentacion`/`id_ubicacion` resueltos | `product_details_screen.dart:3691-3705` | Emisor #5 («No hay suficiente», **bloquea**) — es el único falso positivo puramente local |
| Sin red, venta por acuerdo con elaborado | `admin_inventory_service.dart:1229-1238` | Delta local aplicado a una fila del elaborado (incorrecto, silencioso) |

---

## 6 · Qué pasa si al proyecto debug le faltan las RPC de presentaciones

- **`get_productos_by_categoria_tpv_search_meta_v3`** (`product_service.dart:46-58`, `:215-227`):
  es la **única** RPC del catálogo. No hay fallback a una v2 ni a `cantidad` cruda: si no
  existe, `withNetworkRetry` propaga, `getProductsByCategory` hace `rethrow`
  (`:118-122`) y `products_screen._loadProducts` cae al `catch` (`:274-290`) mostrando el
  widget de error. Sólo hay datos si `useLocalData` es verdadero (`:238-246` →
  `_getProductsByCategoryLocal`, `:126-152`, que lee SQLite/`offline_products`).
  Es decir: **sin esa RPC y sin caché, el TPV no lista productos**.
- **`fn_productos_cocina_tpv`** (`product_service.dart:294-321`): sí degrada — `catch` →
  lista vacía (`:317-320`), «el catálogo de barra debe seguir funcionando igual».
- **`fn_preview_rebalanceo`**: degrada a neutro (`preview_rebalanceo_service.dart:131-135`),
  y en `preorder_screen.dart:1521-1525` también se traga el error; el fallback local
  `_cadenaYStocksOnline` (`:1223-1265`) usa `get_detalle_producto`.
- **`fn_descontar_con_rebalanceo`** / `fn_rebalancear_presentaciones`: no hay defensa en el
  cliente. La venta devuelve `status != 'success'` → `order_service.dart:1542-1547` →
  `success:false` con el `message` del servidor; el vendedor ve «Error al registrar la venta: …».
  Si la RPC no existe, el error de PostgREST (`PGRST202`) acaba en `order_service.dart:1548-1551`.
- **`fn_pedir_item_cuenta`** (`mesa_cuenta_service.dart:282-303`): si no existe, la excepción
  sube por `order_service.dart:225-229` y termina en el snackbar genérico de la pantalla.
- El único detector de «RPC no desplegada» del repo es `_isRpcUnavailable`
  (`auto_sync_service.dart:3672-3679`, busca `pgrst202` / `could not find the function` /
  `schema cache`), y **sólo se usa en la sincronización de ventas offline** (`:4010-4072`),
  no en el catálogo ni en el pedido.

**No verificable desde aquí:** si el proyecto debug `qhprswhhfasrikhawjoz` tiene aplicadas
`27_stock_almacen_en_base.sql`, `10_preview_rebalanceo.sql`, `22/24/25` de
`presentaciones_inventario/`. En **producción** sí están: consulta de sólo lectura al MCP
(`pg_proc`) confirma que `fn_stock_producto_almacen` contiene `factor_rel` y que
`fn_preview_rebalanceo`, `fn_rebalancear_presentaciones`, `fn_pedir_item_cuenta`,
`fn_validar_ingredientes_elaborado`, `fn_productos_cocina_tpv` y
`get_productos_by_categoria_tpv_search_meta_v3` existen. Si en debug **no** está el `27`,
entonces `fn_stock_producto_almacen` suma presentaciones sin factor y el
`INSUFFICIENT_STOCK_INGREDIENT` de `fn_validar_ingredientes_elaborado` reproduce exactamente
el síntoma «sólo cuenta una presentación, ignora los kg» — hay que confirmarlo en ese
proyecto, no en éste.

---

## 7 · Divergencias doc ↔ código

1. **`docs/TUTORIAL_PRUEBAS_PRESENTACIONES.md` §9.6 (`:1254-1273`) y pendiente #4
   (`:1791`) dicen que `fn_stock_producto_almacen` «suma sin factor» y «queda anotado, no
   resuelto».** `docs/PLAN_PRESENTACIONES_INVENTARIO.md:484` dice lo contrario:
   `27_stock_almacen_en_base.sql` **aplicado** y devolviendo unidades base. La consulta al
   `pg_proc` de producción confirma que **hoy usa `factor_rel`**: el tutorial está desfasado
   respecto al plan y respecto a producción. Importante para el caso: si el proyecto **debug**
   no tiene el `27`, el tutorial describe la realidad de ese backend y el plan no.
2. **`TUTORIAL §7.3` (`:899-912`) afirma que las dos rutas de venta (detalle y modo fluido)
   guardan la presentación.** En el código, `fluid_mode_screen.dart:66-106` **nunca agrega los
   ítems a la orden** (y `finalizeCurrentOrder` se llama sin `await`), así que en la práctica
   el modo fluido no vende nada. Es un fallo de flujo, no de presentación, pero invalida la
   prueba §7.3 tal como está escrita.
3. **`PLAN_PRESENTACIONES_INVENTARIO.md:838-840` (Paso 4) lista como pendientes «cuenta de
   mesa (`mesa_cuenta_service`) y venta por acuerdo»**, mientras `:486` da la venta por
   acuerdo por migrada. En el código, la venta por acuerdo **sí** manda `id_presentacion`
   (`admin_sale_agreement_screen.dart:173-174`, `:207`, `:273`); la cuenta de mesa también lo
   manda en `pedirItem` (`mesa_cuenta_service.dart:291`). Lo que falta de verdad en ambas es
   la **exclusión de elaborados en la venta por acuerdo** (§1.7), no la presentación.
4. **`TUTORIAL §8.5` (`:1138-1140`) dice que el rebalanceo sólo aplica a barra no elaborada.**
   Coherente con el SQL. Pero **el cliente no lo respeta**: `product_details_screen.dart:3680-3735`
   ejecuta el preview/desarme local **sin comprobar `currentProduct.esElaborado`**, cuando en
   el resto del archivo sí lo comprueba (`:121`, `:1581`, `:2096`, `:2608`).
5. **`TUTORIAL §3.4` (`:464-480`) dice que la venta por acuerdo «antes mandaba siempre
   `null`».** Hoy no: `PresentationSelection.forInventoryPayload()` (`admin_sale_agreement_screen.dart:207`)
   es sólo el fallback del campo único cuando el producto no tiene cadena.
6. **Documentación ausente:** ningún doc describe que `getProductIngredients`
   (`product_detail_service.dart:506-593`) sea la validación de cliente real de un elaborado,
   ni que tome **una sola fila** de inventario. Es el hueco documental que explica el caso.

---

## 8 · Cambios necesarios, priorizados y separados por capa

### 8.1 · Lógica de datos / servicios (sin UI)

1. **`product_detail_service.dart:506-593` — `getProductIngredients`.** Sustituir
   `select('cantidad_final').order(created_at desc).limit(1)` por una lectura de **todas las
   filas** de `app_dat_inventario_productos` del ingrediente + su `presentacion.id`, y exponer
   `disponible_base` (equivalente) además de las filas crudas. Comportamiento esperado: el
   disponible de un ingrediente es la **suma en equivalente base** de todas sus presentaciones
   del almacén del TPV, no la fila más reciente. Idealmente delegar en la RPC viva
   (`fn_stock_producto_almacen` / `fn_validar_ingredientes_elaborado`) en vez de reimplementar.
2. **`preorder_screen.dart:2643-2718` y `:1271-1594` — validación de elaborados.** Que la
   comparación use el disponible en **unidades base** y la receta convertida a base
   (`cantidad_necesaria × cantidad × factorRel` de la presentación de la receta). Si el
   ingrediente está en kg + gramos, debe contar la equivalencia total (igual que ya hace
   `DesarmeBultoLocal.evaluar`, `desarme_bulto_local.dart:96-102`).
3. **`preorder_screen.dart:1271-1594` — reutilizar `PresentacionCadenaLocal` por ingrediente.**
   Hoy la cadena sólo se usa para el producto vendido (`_cadenaYStocksOffline` `:1155-1215`,
   `_cadenaYStocksOnline` `:1223-1265`). El ingrediente necesita la suya.
4. **`preorder_screen.dart:1060-1144` — `_getStockFromCache`.** Devolver la **suma** de las
   filas que casan (o el equivalente por `factorRel`) en vez de la primera
   (`:1125-1131`); es el arreglo previo obligatorio si algún día se reactiva la rama offline de
   ingredientes.
5. **`preorder_screen.dart:1292-1352` — rama offline de receta.** Hoy es inerte (§4.1).
   Decidir: o se cachea la receta en `_syncProducts` (`auto_sync_service.dart:457-614`) y la
   rama funciona, o se elimina y la validación de elaborados se declara **online-only**.
6. **`product_details_screen.dart:3680-3736` — no aplicar el desarme de presentaciones a un
   elaborado.** Condicionar el bloque a `!currentProduct.esElaborado && !currentProduct.esServicio`
   (coherente con `TUTORIAL §8.5` y con el resto del archivo).
7. **`admin_inventory_service.dart:1229-1238` — venta por acuerdo.** Excluir elaborados y
   servicios del delta local, igual que `checkout_screen.dart:2183-2190` y
   `preorder_screen.dart:1976-1977`.
8. **`order_service.dart:1360-1385` — bloque comentado.** O se borra (y se documenta que el
   servidor descompone la receta) o se reactiva mandando los ingredientes con su
   `id_presentacion`; hoy `decomposition_data` se calcula y se descarta.
9. **`fluid_mode_screen.dart:66-106` — modo fluido.** Agregar los `OrderItem` a la orden
   (`addItemToCurrentOrder`) o eliminar la ruta; hoy es un no-op con `finalizeCurrentOrder`
   sin `await`.
10. **`cocina_offline_queue.dart`** — cablear `encolarPedido` en el flujo de `pedirItem` o
    eliminarlo; hoy no tiene llamadores.

### 8.2 · UI

11. **`product_details_screen.dart:3912-3925`.** Añadir rama `on PedidoException` que use
    `titulo` (`pedido_resultado.dart:189-199`) y, si `esFaltaDeStock`, ofrezca «pedir de todas
    formas» cuando la tienda lo permita (`forzarSinStock`, ya soportado en
    `mesa_cuenta_service.dart:280`,`:301`). Hoy el `error_code` se pierde.
12. **`preorder_screen.dart:2700-2714` y `:1642-1740`.** Mostrar la **unidad y la presentación**
    del ingrediente («faltan 300 g» o «1 kg») en vez de dos números con la unidad de la receta;
    y decir de qué presentaciones se dispone (rebalanceo posible) para que el cartel no mienta.
13. **`preorder_screen.dart:2824-2828`.** Etiquetar el equivalente base en gris, como manda la
    regla de UI de `PLAN_PRESENTACIONES_INVENTARIO.md:845-847`.
14. **`apertura_screen.dart:781-799` + `inventory_service.dart:125-203`.** Clave por
    `(id_producto, id_presentacion, id_ubicacion)` para que un ingrediente con kg + gramos no
    se colapse a una fila (pendiente ya reconocido en `PLAN_PRESENTACIONES_INVENTARIO.md:523`).
15. **`elaborated_product_chip.dart:40`** consume `getProductIngredients` para mostrar el
    preview de ingredientes; heredará el arreglo del punto 1 (no requiere cambio propio).

### 8.3 · SQL / Supabase (aplicar en **las dos** ramas: debug `qhprswhhfasrikhawjoz` y release `vsieeihstajlrdvpuooh`)

16. **`fn_descontar_ingredientes_elaborado`** (`funcionalidad_cocina/01_helpers_bom_almacen.sql:271-277`).
    El `LEAST(v_ubic.cantidad_final, v_pendiente)` compara una cantidad **en la presentación de
    la fila** contra un pendiente **en unidades base**. Comportamiento esperado: descontar por
    equivalente base y dejar las conversiones auditadas, es decir pasar por
    `fn_descontar_con_rebalanceo` (es la recomendación que ya está escrita en
    `presentaciones_inventario/27_stock_almacen_en_base.sql:82-89`). **No existe hoy en ninguna
    migración**; es el defecto que produce el «toma una aleatoria para descontar» y el descuento
    de menos.
17. **`fn_stock_producto_almacen`** (`01:123-124`): confirmar que el proyecto **debug** tiene
    aplicado `presentaciones_inventario/27_stock_almacen_en_base.sql` (`:95-119`, suma con
    `factor_rel`). En producción ya está (verificado por `pg_proc`). Sin él, el `disponible` del
    cartel mezcla gramos con kg.
18. **`fn_validar_ingredientes_elaborado`** (`01:175-181`): el mensaje va **sin unidad**
    (`:184-187`); conviene añadir la presentación/unidad resuelta para que el vendedor lea
    «faltan 3 kg» y no dos números ambiguos. Y el descuento debe contar **todas** las
    presentaciones del ingrediente en equivalente base, no la suma cruda.
19. **FIFO entre presentaciones** (`fn_stock_producto_almacen_detalle`, `01:100-101`): el orden
    por `cantidad_final DESC` es lo que hace que una fila en kg (2) se consuma después de una en
    gramos (2000) y se compare contra un pendiente en gramos. Debe ordenarse por equivalente
    base o resolverse presentación por presentación con su factor.
20. **`fn_descontar_venta_enrutada`** (`10_enrutamiento_venta_cocina.sql:343-350`): no tiene
    parámetro de presentación y para `ingredientes` delega en el punto 16 (`:398-405`); su
    mensaje de error (`:442-451`) también va sin unidad, igual que el del punto 18.

> Nota de alcance: los puntos 16-20 son SQL y afectan a **ambos** proyectos por igual; los
> puntos 1-15 son `ventiq_app/lib` y no dependen de qué migraciones tenga cada backend, salvo
> los `catch` de §12.

---

## 9 · Apéndice · Trazabilidad de los ids del caso

Los ids **3 (arroz), 4 (frijoles) y 5 (arroz moro)** pertenecen al proyecto **debug**
`qhprswhhfasrikhawjoz` (`ventiq_app/lib/config/supabase_config.dart:5`, usado por
`flutter run` / `--debug`, `:14`). En producción no existen (mínimo 95), así que no se buscaron
en el código ni en el `pg_proc` de producción. Todo lo anterior es lógica de `ventiq_app/lib`
más el SQL versionado del repo, aplicable a los dos proyectos.

---

# Anexo · Respuestas a las preguntas nuevas del lead

## §10 · ¿Elige el cliente la presentación del **ingrediente**? — No. «A veces gramo, a veces kg» es del servidor + un display del cliente

### 10.1 · El cliente nunca manda ni hereda una presentación de ingrediente

1. **No la pide.** `getProductIngredients` selecciona sólo `cantidad_final` y no menciona
   `id_presentacion` en el `select` ni en el `order` (`product_detail_service.dart:549-554`); el
   mapa que devuelve (`:571-581`) tampoco expone presentación. La fila la decide
   **`ORDER BY created_at DESC LIMIT 1`**, o sea la última fila escrita del ledger.
2. **No la hereda del plato vendido.** `_decomposeRecursively` /
   `_updateOrderWithDecomposedProducts` guardan `{id_producto, cantidad, producto_elaborado_id,
   es_ingrediente}` y `{id_producto, cantidad}` (`preorder_screen.dart:2427-2432`,
   `:2443-2446`): **ningún `id_presentacion`**.
3. **El bloque que lo habría hecho está comentado** en `order_service.dart:1360-1385`, y ahí
   se lee la intención original: `'id_presentacion': null, // Will be handled by base
   presentation logic` (`:1373`).
4. **`p_id_presentacion` de `fn_pedir_item_cuenta` es la del plato, no la del ingrediente**
   (`mesa_cuenta_service.dart:291`). El servidor lo usa para la línea del SKU y para
   `fn_cantidad_en_base` (línea convertida a base, `presentaciones_inventario/24_bom_cantidad_en_base.sql:41-48`),
   nunca para elegir la fila del ingrediente: `fn_descontar_venta_enrutada` no tiene parámetro
   de presentación (`funcionalidad_cocina/10_enrutamiento_venta_cocina.sql:343-350`) y para
   `descontar = 'ingredientes'` delega con
   `fn_descontar_ingredientes_elaborado(p_id_producto_elaborado, p_cantidad, p_id_almacen, p_id_extraccion, p_origen_cambio)`
   (`:398-405`).

**Conclusión:** no hay selección de presentación de ingrediente en el cliente ni herencia desde
el plato. **Toda la elección de qué fila de ingrediente se valida/descuenta es del servidor**,
más un display del cliente que lee una fila distinta (10.3).

### 10.2 · Cómo elige el servidor (y por qué parece aleatorio)

- `fn_stock_producto_almacen_detalle` devuelve **una fila por combinación
  `(id_ubicacion, id_variante, id_opcion_variante, id_presentacion)`** vigente y con
  `cantidad_final > 0`, ordenada por **`cantidad_final DESC, v.id_ubicacion`**
  (`funcionalidad_cocina/01_helpers_bom_almacen.sql:74-101`).
- `fn_descontar_ingredientes_elaborado` recorre esas filas en ese orden y descuenta con
  `v_a_descontar := LEAST(v_ubic.cantidad_final, v_pendiente)` (`:271-277`), donde
  `v_pendiente` viene de la receta **en unidades base** (`:265-269`).
- Es decir: **el orden lo decide la magnitud física, no la unidad**. Con arroz repartido en
  `2000` (presentación gramo) y `2` (presentación kg), primero sale la fila de 2000 y luego la
  de 2; cuando el pendiente base es 3000, el `LEAST(2, 3000) = 2` **descuenta 2 unidades de una
  fila que está en kg** creyendo que descuenta 2 gramos → descuenta **mucho menos** de lo que
  corresponde, y el saldo que queda en el ledger es incoherente. Esto reproduce la sensación de
  «toma una aleatoria para descontar» y encaja con su número: pedido 5000, disponible 2000,
  faltante 3000.
- **Esta deuda está documentada y abierta** en
  `presentaciones_inventario/27_stock_almacen_en_base.sql:82-89`: «`fn_descontar_ingredientes_elaborado`
  L33 hace `LEAST(v_ubic.cantidad_final, v_pendiente)`: compara una cantidad EN PRESENTACIÓN
  (del detalle) contra un pendiente en UNIDADES BASE (de la receta). Con una presentación de
  factor <> 1 descuenta de menos. […] el arreglo correcto es que esa función pase por
  `fn_descontar_con_rebalanceo`». **No existe ningún archivo del repo que lo arregle.**
- La **validación** usa otro camino: `fn_stock_producto_almacen(...)` (`01:175-181`), que en su
  versión base es `SUM(d.cantidad_final)` a secas (`01:123-124`) — **suma presentaciones
  distintas sin factor** (`27:11-21`). El `27` lo corrige a
  `SUM(d.cantidad_final * COALESCE(f.factor_rel, 1))` (`27:115-118`) y, según la consulta de
  sólo lectura al `pg_proc` de producción de este informe, **producción ya lo tiene**. Si el
  proyecto debug `qhprswhhfasrikhawjoz` **no** lo tiene, el `disponible` que sale en el cartel
  mezcla gramos con kg (p. ej. `2000 + 2 = 2002`) — literalmente «sólo cuenta una presentación y
  la otra la mete como si fuera lo mismo».

### 10.3 · El display del cliente también salta de una presentación a otra

`getProductIngredients` toma **una sola** fila, la de `created_at` más reciente
(`product_detail_service.dart:549-554`). Cada movimiento de inventario **inserta una fila
nueva** (`01_helpers_bom_almacen.sql:279-304`), así que «la más reciente» va rotando entre la
presentación de gramos y la de kg: el mismo stock puede reportarse como `2000` o como `2` según
el momento. Eso es, en el cliente, la razón del «a veces aparece gramo, otras kg»; el número se
usa crudo contra la receta (`preorder_screen.dart:1367-1380`).

### 10.4 · Resumen por capa (lo que el lead pidió separar)

| Capa | Defecto | ¿Depende del proyecto Supabase? |
|---|---|---|
| Servidor · validación | `fn_stock_producto_almacen` suma presentaciones sin factor si falta `27` | **Sí**: aplicado en prod, por confirmar en debug |
| Servidor · descuento | `LEAST(cantidad en presentación, pendiente en base)` en `fn_descontar_ingredientes_elaborado` | **No**: el arreglo no existe en ninguna migración; hay que hacerlo en las dos ramas |
| Servidor · orden | FIFO por `cantidad_final DESC` entre presentaciones de distinta unidad | No: es la definición viva en ambos |
| Cliente · display online | `created_at DESC LIMIT 1` en `getProductIngredients` | No: misma consulta en las dos ramas |
| Cliente · display offline | `_getStockFromCache` devuelve la primera fila que casa, no la suma (`preorder_screen.dart:1125-1131`) | No |
| Cliente · offline receta | rama de ingredientes inerte (no hay receta en caché) | No |

---

## §11 · Qué texto ve el vendedor: ¿`message` del servidor o texto propio?

Ninguno de los diálogos lee `PedidoException.errorCode`; lo que decide el texto es **por dónde
salió el error**:

| Lo que dice el cartel | Emisor real | ¿Verbatim del servidor? | Cita |
|---|---|---|---|
| `Stock insuficiente para el ingrediente: <nombre> (disponible: 2000, requerido: 5000)` | Validación del BOM | **Sí**, `PedidoException.mensaje` → `e.toString()` | `01_helpers_bom_almacen.sql:184-187`; `pedido_resultado.dart:212-213`, `:230-231`; `product_details_screen.dart:3914-3916` |
| `Stock insuficiente para el ingrediente: <nombre> (faltan N)` | Descuento del BOM (segunda rama) | **Sí** — **es el único texto que dice «faltan N»** | `01_helpers_bom_almacen.sql:325-329` |
| `Stock insuficiente (disponible: N, requerido: M)` | Enrutamiento de venta (SKU propio) | **Sí** | `10_enrutamiento_venta_cocina.sql:449-450`, código en `:452-454` |
| `No hay suficientes porciones preparadas en "X" (disponibles: N, requeridas: M)` | Enrutamiento por tanda | **Sí**, `INSUFFICIENT_PORTIONS` | `10_enrutamiento_venta_cocina.sql:443-447` |
| `No alcanza: se piden X y como máximo se pueden servir Y` | `fn_preview_rebalanceo` → `mensajeUsuario` | **Sí** | `preview_rebalanceo_service.dart:210-213` |
| `No alcanza el stock disponible. Como máximo se pueden servir N.` | **Cliente** (desarme offline) | No | `product_details_screen.dart:3448-3451` |
| `Los siguientes ingredientes no tienen stock suficiente:` + `Necesario: 5000.00 g` / `Disponible: 2000.00 g` | **Cliente** (validación de ingredientes en preorden) | No — **es el único que imprime la unidad** | `preorder_screen.dart:2703` y `:2824-2828` |
| `Los siguientes productos no tienen suficiente existencia:` + chips `Pedido / En stock / Faltante` | **Cliente** (validación de inventario, bloqueante) | No | `preorder_screen.dart:1670`, `:1700-1725` |
| `Falta materia prima` (título) + `faltantes` por ingrediente | Cliente de tandas | No | `tanda.dart:307`, `:322-323`; `produccion_screen.dart:141` |

**Regla de identificación para el usuario:** si el texto trae **unidad** («gramo»/«kg») es el
emisor de cliente `preorder_screen.dart:2824-2828` (no bloqueante). Si trae
**«disponible:/requerido:»** sin unidad o **«faltan N»**, es el servidor. Si los tres números son
`pedido / existencias / faltante`, es el diálogo bloqueante de cliente
(`preorder_screen.dart:1670`).

Y sobre `fn_descontar_venta_enrutada`: sí es la ruta viva que llama `fn_registrar_venta` y
`fn_registrar_venta_mesa` (`funcionalidad_cocina/11_venta_enrutada.sql:504`, `:940`;
`funcionalidad_cocina/14_pedir_comanda.sql:397`), y **para un elaborado no decide nada de
presentaciones**: sólo delega en el BOM (`10:398-405`). Los códigos que puede devolver llegan al
cliente como `PedidoException` (`pedido_resultado.dart:180-183`) o como `success:false`
(`order_service.dart:1542-1547`), y el cliente no los desambigua.

---

## §12 · Fallbacks del cliente ante RPC ausentes en el proyecto debug

| RPC que podría faltar | Comportamiento real del cliente | Cita |
|---|---|---|
| `get_productos_by_categoria_tpv_search_meta_v3` | **Sin fallback**: `rethrow` → `products_screen._loadProducts` cae al `catch` y muestra el widget de error; sólo hay datos si el modo offline está activo (SQLite) | `product_service.dart:46-58`, `:118-122`; `products_screen.dart:274-290`, `:238-246` |
| `get_detalles_productos_batch` | **Fallback explícito** a una llamada `get_detalle_producto` por producto | `product_detail_service.dart:98-125`, `:127-138` |
| `fn_productos_cocina_tpv` | `catch` → lista vacía («el catálogo de barra debe seguir funcionando igual») | `product_service.dart:317-320` |
| `fn_preview_rebalanceo` | `catch` → `PreviewRebalanceo.sinConversion` → **no pregunta y no bloquea**; en preorden se traga el error y usa `_cadenaYStocksOnline` (`get_detalle_producto`) como respaldo | `preview_rebalanceo_service.dart:131-135`, `:67-70`; `preorder_screen.dart:1521-1525`, `:1223-1265` |
| `fn_registrar_venta_offline_v3` | Cadena de fallbacks: `_v3` → `fn_registrar_venta_offline` → sin `p_pagos` → sin `p_fecha_creacion` → `fn_registrar_venta`, todo gated por `_isRpcUnavailable` | `auto_sync_service.dart:4010-4072`, `:3672-3679` |
| `fn_pedir_item_cuenta` | Sin fallback: la excepción sube y termina en el snackbar genérico | `mesa_cuenta_service.dart:282-303`; `order_service.dart:225-229` |
| Presentaciones vacías en el caché | `PresentacionCadenaLocal` vacía → `DesarmeBultoLocal` devuelve `_alcanza` (**no bloquea**) y el factor cae a `1.0` (precio sin factor) | `auto_sync_service.dart:577-583`; `desarme_bulto_local.dart:85-89`, `:175`; `product_details_screen.dart:2902` |
| `metadata.stock_filas` / `stock_texto` ausentes | `Product.stockMixto`/`stockEquivalenteBase` quedan `null` → `stockLabel()` **cae a `cantidadReal` cruda** | `product_service.dart:387-393`; `product.dart:76-91` |
| `24_bom_cantidad_en_base` ausente (servidor) | No hay defensa en el cliente: la receta se multiplicaría por la cantidad **en presentación** (vender 1 empaque descuenta la receta de 1 unidad) | `24_bom_cantidad_en_base.sql:11-18` |
| `27_stock_almacen_en_base` ausente (servidor) | No hay defensa en el cliente: `fn_stock_producto_almacen` suma presentaciones crudas → `INSUFFICIENT_STOCK_INGREDIENT` con unidades mezcladas | `01_helpers_bom_almacen.sql:123-124`; `27_stock_almacen_en_base.sql:11-21` |
| `fn_descontar_con_rebalanceo` | **Ningún Dart la llama**. En producción verificado: lo usan sólo `fn_crear_extraccion_con_movimiento` y `fn_insertar_ajuste_inventario2`; **la venta rebalancea por otra vía** (`fn_rebalancear_presentaciones`, ver §13) | §13; `presentaciones_inventario/25_venta_con_rebalanceo.sql` |

**Respuesta directa:** el único comportamiento de cliente que *decide degradar* por la ausencia
de una RPC nueva son los cuatro `catch` de la tabla (batch de detalles, catálogo de cocina,
preview de rebalanceo y la cadena de versiones de la venta offline). El resto de degradaciones
**no dependen de «RPC nueva vs vieja» sino de qué campos trae la respuesta** (`presentaciones`,
`stock_filas`, `metadata`): si faltan, el cliente no bloquea y muestra lo crudo
(`stockLabel()` → `cantidadReal`; factor `1.0`). Y si falta una RPC **sin** `catch` (catálogo v3,
`fn_pedir_item_cuenta`, y en general las funciones de venta), el vendedor ve un error visible,
no un cartel de stock.

**Sobre las dos ramas:** el arreglo del caso (descuento/validación de ingredientes por
equivalente base y rebalanceo de presentaciones) vive en **SQL**, no en Dart, así que aplicarlo
en debug y release es el mismo cambio. Lo único que la app tendría que tocar para no depender
del proyecto es el display de §10.3 (`getProductIngredients` debe pedir todas las filas con su
presentación y sumar en equivalente base) y el manejo de `PedidoException.errorCode` (§8.2,
puntos 11-12).

---

## §13 · Estado verificado en el backend de **producción** (`pg_proc`, sólo lectura)

Consultas de sólo lectura al MCP de Supabase, que apunta a
`https://vsieeihstajlrdvpuooh.supabase.co` (producción). **El proyecto debug
`qhprswhhfasrikhawjoz` no es accesible desde este entorno**, así que esto describe release, no
el backend donde ocurrió el caso; sirve como referencia de qué migraciones están vivas y como
lista de comprobación para debug.

| Hecho verificado | Cómo se verificó | Lectura |
|---|---|---|
| `fn_stock_producto_almacen` **sí** usa `factor_rel` | `prosrc like '%factor_rel%'` = true | `27_stock_almacen_en_base.sql` aplicado (§7.1) |
| Existen `fn_preview_rebalanceo`, `fn_rebalancear_presentaciones`, `fn_pedir_item_cuenta`, `fn_validar_ingredientes_elaborado`, `fn_productos_cocina_tpv`, `get_productos_by_categoria_tpv_search_meta_v3` | consulta a `pg_proc` | las RPC del catálogo y del preview están desplegadas en release |
| `fn_registrar_venta` y `fn_registrar_venta_mesa`: `fn_cantidad_en_base` = true y `fn_descontar_venta_enrutada` = true | `prosrc` | `24_bom_cantidad_en_base.sql` aplicado y **no revertido** por `17` |
| **`fn_pedir_item_cuenta`: `fn_descontar_venta_enrutada` = true pero `fn_cantidad_en_base` = false** | `prosrc` | **Gap real**: la ruta de «pedir» (mesa + cocina activa) manda la cantidad **en la presentación vendida** al BOM/porciones. Vender 1 empaque descuenta la receta de **1** unidad base. `24` sólo parchea las dos funciones de venta (`24:126-133`), y `14_pedir_comanda.sql:397-404` pasa `p_cantidad` crudo |
| `fn_registrar_venta`/`_mesa` **sí** referencian `fn_rebalancear_presentaciones` | `prosrc` | la venta **sí** abre/arma empaques en release; `PLAN_PRESENTACIONES_INVENTARIO.md:483` es correcto |
| `fn_descontar_con_rebalanceo` sólo lo usan `fn_crear_extraccion_con_movimiento` y `fn_insertar_ajuste_inventario2` | consumidores por `prosrc` | el rebalanceo de la **venta** va por `fn_rebalancear_presentaciones`, no por este helper |
| `fn_descontar_ingredientes_elaborado` y `fn_descontar_venta_enrutada` **no** referencian ningún rebalanceo | consumidores por `prosrc` | la deuda del `LEAST` (`27:82-89`) sigue **viva**: el descuento de MP no rebalancea presentaciones del ingrediente |
| `fn_pedir_item_cuenta` no referencia `fn_rebalancear_presentaciones` | `prosrc` | la ruta de «pedir» no rebalancea; sólo el preview de cliente avisa antes (`product_details_screen.dart:3716`) |

**Qué significa para el caso:** en release, la validación de ingredientes ya compara en unidades
base (gracias al `27`), pero el **descuento** sigue mezclando presentación con base
(`LEAST`) y la ruta de «pedir» sigue pasando la cantidad sin convertir. Es decir: el arreglo del
caso es exactamente §8.3 puntos 16-20, y hay que confirmar en debug si además falta el `27`
(único punto que cambiaría el número que ve el vendedor).