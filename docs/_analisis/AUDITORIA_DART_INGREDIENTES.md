# Auditoría Dart · Fase 7 (ingredientes elaborados / presentaciones)

Alcance: `ventiq_app/lib` (7 archivos de la task-2). Plan: `docs/PLAN_CONSUMO_INGREDIENTES_ELABORADOS_PRESENTACIONES.md:300-318`.
Método: grep + lectura puntual del código actual (las líneas del plan estaban desfasadas). Analyzer: `mcp__dart__analyze_files` sobre los 7 archivos.
Nota: el árbol de trabajo está limpio respecto a HEAD; la Fase 7 ya está commiteada.

## P0

| Punto | Archivo:línea | Cita (≤3 líneas) | Veredicto |
|---|---|---|---|
| (a) `getProductIngredients` deja de leer 1 fila y suma base | `lib/services/product_detail_service.dart:583`, `:719-723`, `:802-867` | `totalBase += cantidad * factor;` … `'cantidad_disponible': cantidadDisponible` … `'desglose_presentaciones': desglose` | **IMPLEMENTADO ~90 %** (vía fallback documentado, no vía RPC nueva) |
| (a.1) RPC nueva del plan (`fn_ingredientes_elaborado_base` / `fn_validar_ingredientes_elaborado_v2`) | no aparece en `lib/` (solo comentarios en `product_detail_service.dart:22,545`) | grep sin coincidencias de código | **NO IMPLEMENTADO** (usa `fn_stock_producto_almacen_detalle`, `:811-814`) |
| (a.2) Fallback 1 fila `created_at DESC LIMIT 1` | `product_detail_service.dart:677-688` | `.order('created_at', ascending: false).limit(1)` | **PARCIAL**: solo si no hay cadena o falla la RPC; etiqueta `alcanceDesconocido` |
| (b) `_checkInventoryAvailability` compara base y usa almacén de venta | `lib/screens/preorder_screen.dart:1286`, `:1391-1396`, `:1418-1420` | `idAlmacen: idAlmacenVenta` … `cantidadDisponible < cantidadNecesaria` | **IMPLEMENTADO (online) ~90 %**; offline queda inerte (ver P1) |
| (b.2) `_checkIngredientsAvailability` base + almacén de venta | `preorder_screen.dart:2819`, `:2831-2834`, `:2854` | `idAlmacen: await _resolverAlmacenDeVenta(productId)` | **IMPLEMENTADO ~90 %** |
| (b.3) Almacén de venta resuelto con `fn_resolver_origen_venta` | `preorder_screen.dart:1659-1695` | `params: {'p_id_producto': …, 'p_id_tpv': idTpv}` | **IMPLEMENTADO** (null ⇒ mide todos y lo etiqueta) |
| (c) Desarme NO aplicado a elaborados/servicios | `lib/screens/product_details_screen.dart:3680-3736` | `if (idPresPreview != null && idUbicPreview != null && cantidadPreview > 0) {` | **NO IMPLEMENTADO**: sin guarda `!esElaborado && !esServicio` (sí existe en `:118-122`, `:886-890`) |
| (d) Unidad/presentación en carteles | `preorder_screen.dart:1826-1831`, `:3008-3012` | `'Unidad base: $unidad'` … `'Necesario: ${necesaria.toStringAsFixed(2)} $unidad'` | **PARCIAL ~70 %**: unidad y alcance sí; “equivalente base en gris” no |
| (d.1) Desglose por presentación en UI | `product_detail_service.dart:723` (único uso del grep) | `'desglose_presentaciones': desglose` | **NO IMPLEMENTADO** en UI (se calcula y se descarta) |

## P1

| Punto | Archivo:línea | Cita | Veredicto |
|---|---|---|---|
| Rama `on PedidoException` en `_addToCart` (`titulo`/`esFaltaDeStock`/`forzarSinStock`) | `product_details_screen.dart:3912-3925` | `} catch (e) { … Text('❌ Error al agregar: ${e.toString()}')` | **NO IMPLEMENTADO** (no hay `PedidoException` en el archivo) |
| `_getStockFromCache` prioriza la suma | `preorder_screen.dart:1131-1132` | `if (matched != null) return matched; if (hasInvRows && invSum > 0) return invSum;` | **PARCIAL ~50 %**: la suma existe pero sigue siendo el respaldo |
| Venta por acuerdo: excluir elaborados del delta local | `lib/services/admin_inventory_service.dart:1229-1238`, `:1367-1379` | `await _applyStockDeltaLocally(productId: id, delta: -qty, …)` | **NO IMPLEMENTADO**: sin filtro de elaborados; `_applyStockDeltaLocally` tampoco lo comprueba |
| Offline: ¿se cachea la receta? | `preorder_screen.dart:1307-1338` vs `ventiq_app/sql_offline/01_get_detalles_productos_batch.sql:250-251` | `detalles?['ingredientes']` … `'producto'`/`'inventario'` (sin `ingredientes`) | **NO IMPLEMENTADO**: el detalle cacheado nunca trae `ingredientes` ⇒ rama inerte |

## P2

| Punto | Archivo:línea | Cita | Veredicto |
|---|---|---|---|
| Modo fluido | `lib/screens/fluid_mode_screen.dart:66-106` | `_onProductDetailsCompleted` / `_processOrder` sin presentación ni base | **NO IMPLEMENTADO** |
| `cocina_offline_queue` | `lib/services/cocina_offline_queue.dart:284-293` | `'fn_pedir_item_cuenta_offline'` | **NO IMPLEMENTADO** (sin ruta `_v2`) |
| Apertura: conteo mixto | `lib/screens/apertura_screen.dart:781-791` | `// Agrupar productos SOLO por id_producto (sin considerar ubicaciones ni presentaciones)` | **NO IMPLEMENTADO** |

## Fase 3 / Fase 4 (Dart)

| Punto | Archivo:línea | Cita | Veredicto |
|---|---|---|---|
| Fase 3 venta normal/mesa `_v3` | `lib/services/order_service.dart:1447-1450` | `useMesaRpc ? 'fn_registrar_venta_mesa_v3' : 'fn_registrar_venta_v3'` + fallback a las vivas | **IMPLEMENTADO** |
| Fase 3 offline `_v4`→`_v3`→viva | `lib/services/auto_sync_service.dart:4016-4051` | `'fn_registrar_venta_offline_v4'` → `'fn_registrar_venta_offline_v3'` → `'fn_registrar_venta_offline'` | **IMPLEMENTADO** |
| Fase 4 pedir item de cuenta `_v2` | `lib/services/mesa_cuenta_service.dart:285-286`, `:310-315` | `const fnNueva = 'fn_pedir_item_cuenta_v2';` | **IMPLEMENTADO** (con fallback) |
| Fase 4 cancelar item `_v2` | `mesa_cuenta_service.dart:377-389` | `const fnNueva = 'fn_cancelar_item_pedido_v2';` | **IMPLEMENTADO** |
| Fase 4 eliminar producto de orden `_v2` | `order_service.dart:2960-2970` | `'fn_eliminar_producto_orden_v2'` … `'fn_eliminar_producto_orden'` | **IMPLEMENTADO** |
| `fn_devolver_ingredientes_elaborado_v2` desde Dart | — (se invoca dentro del SQL `_v2`: `funcionalidad_cocina/35_devoluciones_presentacion.sql:505,727`) | — | **N/A correcto** (no debe llamarse desde la app) |
| `fn_descontar_ingredientes_elaborado_v2` / `fn_descontar_venta_enrutada_v2` desde Dart | grep `lib/` sin coincidencias | — | **N/A correcto** (internas de `_v3`) |

## Calidad (analyzer)

- `mcp__dart__analyze_files` con `roots add` de `file:///C:/Users/cesar/Documents/VentIQ-seller-App/ventiq_app` y `paths` = los 7 archivos de la task-2 ⇒ **“No errors”**. No se detectaron errores nuevos (el preexistente de `package_image_picker_web.dart`/`dart:js_util` no entra en esta lista).

## Riesgos / gates

1. **Divergencia cliente↔servidor**: el cliente suma `cantidad_final × factor_rel` con `fn_stock_producto_almacen_detalle`, mientras el helper de validación vivo `fn_stock_producto_almacen` suma **sin** factor (`funcionalidad_cocina/01_helpers_bom_almacen.sql:123-124`). La coherencia depende de que la Fase 3 (`_v3`) y la validación `_v2` estén desplegadas en **ambos** proyectos.
2. **P0(c)** puede disparar el diálogo de desarme sobre un elaborado si trae presentación de inventario: no hay guarda explícita.
3. Offline: P0(b) y P1 (receta cacheada) siguen inertes; el cartel offline se apoya solo en `_getStockFromCache` (fila única / suma de respaldo).
