# Propagación de la «moneda de venta» a las pantallas del TPV

**Estado:** ✅ **completada** (2026-11-04). Este documento es la especificación de
trabajo compartida que se usó para la propagación; se conserva como registro del
contrato aplicado. El resumen de resultados y las decisiones de la revisión del
Lead están en `plan.md` §3.3.

## 1. Qué es la moneda de venta

El vendedor elige, al entrar, la divisa en la que **se muestran los precios** de
este teléfono. No cambia el precio del producto (que sigue guardado en CUP), solo
la presentación: un producto de 45.000 CUP se muestra como `$45.000,00` si la
moneda de venta es CUP, o como `45,45 EUR` si es EUR con tasa 990.

El estado vive **en memoria** en `MonedaVentaService` porque las pantallas
formatean dentro de `build()` y ahí no se puede esperar a SharedPreferences ni a
la red:

```dart
MonedaVentaService.actual                        // 'CUP', 'USD', 'EUR'...
MonedaVentaService.tasas                         // {'CUP': 1, 'USD': 900, 'EUR': 990}
MonedaVentaService.hayVariasDivisas              // bool
MonedaVentaService.enDivisaAlternativa           // bool
```

## 2. La única API de formateo

```dart
static String formatearPrecio(
  double importeBase, {     // importe en CUP (moneda base)
  int decimales = 2,
  bool conSimbolo = false,
})
```

| Caso | `conSimbolo: false` (defecto) | `conSimbolo: true` |
|---|---|---|
| moneda base (CUP) | `45.000,00 CUP` | `$45.000,00` |
| divisa alternativa | `45,45 EUR` | `45,45 EUR` |

Reglas duras:

1. **El argumento es siempre un importe en CUP.** Si el valor ya está en otra
   divisa (billetes contados en USD, conversión explícita a USD de un ticket),
   **no** se le pasa a este método.
2. **No se inventa ninguna conversión.** Si la divisa activa no tiene tasa, el
   método forma en CUP. Nunca devuelve un importe falso.
3. `conSimbolo: true` existe para las pantallas que hoy escriben
   `'\$${x.toMoneyString(2)}'`: así una tienda que solo cobra en CUP ve
   **exactamente el mismo texto que antes** (`$45.000,00`) y no hay regresión
   visual. Úsalo siempre que el sitio actual tenga el prefijo `$`.
4. `decimales` debe conservar el que tenía el sitio (`toMoneyString(0)` →
   `decimales: 0`), para no cambiar el redondeo que ya veía el vendedor.

### Equivalencias exactas de migración

| Antes | Después |
|---|---|
| `'\$${x.toMoneyString(2)}'` | `MonedaVentaService.formatearPrecio(x, conSimbolo: true)` |
| `'\$${x.toMoneyString(0)}'` | `MonedaVentaService.formatearPrecio(x, decimales: 0, conSimbolo: true)` |
| `'${x.toMoneyString(2)} CUP'` | `MonedaVentaService.formatearPrecio(x)` |
| `'\$${PriceUtils.formatAmount(x)}'` | `MonedaVentaService.formatearPrecio(x, conSimbolo: true)` |
| `'\$${PriceUtils.formatDiscountPrice(x)}'` | `MonedaVentaService.formatearPrecio(PriceUtils.roundDiscountPrice(x), conSimbolo: true)` |

Import a añadir donde falte:

```dart
import '../services/moneda_venta_service.dart';   // desde lib/screens o lib/widgets
import '../../services/moneda_venta_service.dart'; // desde lib/widgets/home
```

## 3. Qué NO se migra (importante)

No se toca ningún importe que **no sea un precio de catálogo/venta en CUP**:

- **Arqueo y caja**: `cierre_screen.dart`, `apertura_screen.dart`,
  `cash_count_dialog.dart`, `bill_count_dialog.dart`, `settings_screen.dart`
  (resúmenes de turno), y los bloques de efectivo/arqueo de `venta_total_screen.dart`.
  Ahí los importes son billetes contados en una divisa concreta; convertirlos
  sería un error contable.
- **Egresos y gastos**: `egreso_screen.dart`, `egresos_list_screen.dart`,
  `models/expense.dart`.
- **Conversiones explícitas a USD** que ya existen (p. ej. la línea secundaria
  `'USD ${(subtotal / usdRate).toMoneyString(2)}'`): se dejan como están; son
  informativas y no dependen de la moneda de venta.
- **Resúmenes de pagos ya cobrados** (`totalPaidCup`, `usdPaid`,
  `_resolveOriginalPaymentAmount`, «mover montos»): están en la divisa real del
  pago, no son precios de catálogo.
- **Totales diarios / monitor de ventas** (`sales_monitor_fab`,
  `filtered_orders_screen`): agregan cobros reales de varias divisas.
- **Depósitos, proveedores, suscripciones, paquetes** (`package_product_screen`,
  `subscription_detail_screen`): módulos con su propia noción de divisa.

**Sí se migra** (todo lo que el vendedor ve como precio de una venta):
catálogo, listado y detalle de producto, carrito, checkout, pedidos pendientes,
cuenta de mesa, detalle de mesa, **comprobante PDF de la venta**, listas de
precios de administración (`admin_tpv_prices_screen`, `admin_sale_agreement_screen`)
y los precios/subtotales de la lista de ventas de `venta_total_screen`.

Ante la duda: si el valor viene de `precio_venta_cup`, `item.precio`,
`item.precioUnitario`, `item.subtotal`, `product.precio`, `order.total`,
`cuenta.total` o es un descuento aplicado a la venta, es candidato.
Si viene de contar billetes, de un egreso o de `_totalEfectivoUsd`, **no**.

## 4. Reparto de ficheros (sin solapes)

| Responsable | Ficheros |
|---|---|
| Lead | `lib/services/moneda_venta_service.dart`, `lib/screens/home_shell_screen.dart`, `lib/screens/checkout_screen.dart`, `lib/services/auth_service.dart` |
| Teammate `home-catalogo` | `lib/widgets/home/producto_tile.dart`, `lib/widgets/home/riel_productos.dart`, `lib/widgets/home/quick_add_sheet.dart`, `lib/widgets/order_product_summary.dart`, `lib/screens/products_screen.dart` |
| Teammate `detalle-producto` | `lib/screens/product_details_screen.dart`, `lib/screens/servicentro_screen.dart`, `lib/screens/servicentro_cantidad_screen.dart`, `lib/screens/default_order_items_screen.dart` |
| Teammate `carrito` | `lib/screens/orders_screen.dart` |

## 5. Además de migrar: montar el chip

`MonedaVentaChip(onChanged: (_) => setState(() {}))` se monta en la barra de las
pantallas de venta donde el vendedor está mirando precios. El chip se oculta solo
si la tienda tiene una sola divisa con tasa, así que montarlo no añade ruido.

- Home (`home_shell_screen.dart`): en `acciones:` del `HomeHeroHeader`. (Lead)
- `products_screen.dart`: en el `AppBar` (si tiene `actions`). (Teammate)
- `orders_screen.dart`: en el `AppBar` (si tiene `actions`). (Teammate)

Si el `AppBar` no existe o no tiene `actions`, se añade `actions: [const
MonedaVentaChip()]` (o se añade al listado existente). El `onChanged` debe
provocar un `setState` para que los precios de esa pantalla se repinten.

## 6. Verificación obligatoria

Desde `ventiq_app/`:

```powershell
$env:APPDATA = 'C:\Users\cesar\Documents\VentIQ-seller-App\.dsh\dart-tool'
flutter analyze lib          # debe decir "No issues found!" (o solo infos previos)
flutter test test/moneda_venta_formato_test.dart
```

`dart analyze` **no** detecta los errores de formato de texto: hay que revisar a
ojo que cada sustitución conserve el `\$` (vía `conSimbolo: true`) y los
decimales originales.

## 7. Entregable de cada teammate

1. La lista de sustituciones hechas, con `archivo:línea` y el antes/después.
2. Salida real de `flutter analyze lib` (no "creo que compila").
3. Lo que haya dejado sin migrar y por qué (si algo).

## 8. Correcciones de la revisión del Lead (aplicadas)

1. **El chip tiene que actualizar el estado, no solo repintar.** `MonedaVentaChip`
   guardaba la divisa y llamaba a `onChanged`, pero **no** llamaba a
   `MonedaVentaService.configurar(...)`: en Home el repintado lo tapaba (el Home
   recargaba el estado por su cuenta), pero en `products_screen` y
   `orders_screen` los precios habrían seguido en CUP mientras el chip mostraba
   EUR. Ahora `_cargar()` y `_elegir()` configuran el servicio, y `_cargar()` no
   degrada el estado si la consulta falla (`disponibles.isEmpty`).
2. **El comprobante PDF de la venta SÍ se migra** (`orders_screen`, 5 sitios).
   Primero se dejó en CUP y el usuario lo corrigió: es una vista con precios y
   debe mostrar lo mismo que la pantalla. El motivo por el que ahora sí es
   coherente: ese PDF **no imprime las líneas de pago**, así que no mezcla la
   divisa de visualización con la divisa real del cobro. Los **tickets de las
   impresoras** (bluetooth/wifi/web/admin) sí imprimen pagos y por eso se quedan
   en moneda base + divisa real del pago, como ya hacían con el USD.
3. **Los rótulos «Equivalente CUP» / «Equiv. CUP»** (`orders_screen:1505` y
   `:1915`) se quedan en CUP: la etiqueta nombra la divisa y el valor no puede
   contradecirla. Son el desglose secundario de un cobro ya hecho, no un precio.
4. **El checkout cobra en la moneda de venta sin exigir el flag legado
   `mostrar_selector_moneda`** (`_aplicarMonedaVentaPorDefecto`). Ese flag
   gobernaba el antiguo toggle CUP/USD; exigirlo dejaría el Home mostrando EUR y
   el cobro registrándose en CUP. Solo aplica si el vendedor eligió
   **activamente** una divisa distinta de la base y la tienda la acepta con tasa.
5. **Segunda pasada de cobertura** (el usuario pidió «todo lo que tenga precio»):
   categorías legacy (móvil y web), cuenta de mesa, detalle de mesa,
   `preorder_screen`, `pending_orders_fab`, `web_print_dialog`,
   `admin_tpv_prices_screen`, `admin_sale_agreement_screen`, la lista de ventas de
   `venta_total_screen` y los totales de venta de `filtered_orders_screen`.
   Exclusión consciente y verificada en `filtered_orders_screen`: `totalAmount`
   (~59) y el promedio (~66) **no** son suma de `order.total`, reciben
   `_totalEfectivo`/`_totalTransferencia` de `venta_total_screen` → son arqueo.

## 9. Verificación final

- `analyze_files` (MCP de Dart) sobre **los 26 ficheros tocados** → **No errors**.
- `flutter test` de la suite completa → **407 pasan, 1 falla**.
- El único fallo es `test/widget_test.dart` «Counter increments smoke test»: el
  test plantilla de Flutter, que pide un contador inexistente y arranca
  `MyApp` sin inicializar Supabase. **`main.dart` y `widget_test.dart` no están
  modificados** (`git status` vacío para ambos) → fallo preexistente y ajeno.
- `dart analyze` / `flutter analyze` por CLI **no es utilizable** en esta sesión:
  el sandbox deniega las tuberías del analysis server
  (`CreateFile failed 5 (Acceso denegado)`), y el comando se cuelga. El MCP de
  Dart usa el mismo analizador y sí funciona.