# Recon: flujo de cobro multimoneda en `ventiq_app` (TPV vendedor)

> **Alcance**: inventario de solo lectura de `ventiq_app/` (paquete `ventiq_app`, v2.6.0+850,
> Dart ^3.7.0, `provider` + `supabase_flutter`). Complementado con el esquema SQL del monorepo
> (`VentiQ.sql`, `ventiq_app/sql/`, `sql_updates/`) porque el contrato real del cobro vive en la DB.
> **Objetivo**: qué falta para poder cobrar en monedas **arbitrarias** definidas desde el superadmin,
> contabilizando en USD.
>
> Todas las citas son `archivo:línea`. Lo que no se encontró se marca **NO ENCONTRADO** con el
> detalle de la búsqueda.

---

## 0. Resumen ejecutivo (lo que importa en 10 líneas)

1. **Lo que ya está generalizado**: el catálogo de denominaciones (`app_dat_denominaciones_moneda`,
   N monedas, global) se descarga en login y los diálogos de conteo **ya enumeran N monedas**
   (`getMonedasDisponibles()`), y el esquema de tasas (`tasas_conversion`, `tasa_cambio_extraoficial`)
   soporta pares arbitrarios.
2. **Lo que está cableado a 2 monedas**: todo el **cálculo y la persistencia**. `PriceUtils.paymentCurrency`
   colapsa a `'CUP'` cualquier cosa que no sea `'USD'` (`price_utils.dart:136`); `CurrencyService` tiene
   `_cupId=1`/`_usdId=2` fijos (`currency_service.dart:7-8`); el checkout tiene un toggle binario
   `['CUP','USD']` (`checkout_screen.dart:898`); y la DB **rechaza** cualquier otra moneda por
   constraint (`venta_usd.sql:16-19`: `CHECK (moneda IN ('CUP','USD'))`).
3. **Consecuencia neta**: si el superadmin definiera `EUR`/`MLC`, el conteo de billetes lo mostraría
   (dropdown), pero se **sumaría como si fuera CUP** y el sync lo **persistiría como CUP**. No hay
   soporte real de N monedas en el cobro.
4. **Bloqueante de backend**: el `CHECK` de `app_dat_pago_venta.moneda` y las columnas
   específicas de USD (`tasa_usd`, `efectivo_inicial_usd`, `efectivo_real_usd`, `diferencia_usd`).
5. **NO ENCONTRADO**: no existe en el repo la DDL de `app_dat_denominaciones_moneda` ni de
   `tasa_cambio_extraoficial`; tampoco existe **ninguna UI/servicio de superadmin** que administre
   monedas (`grep 'denominaciones_moneda'` en todo el workspace → **1 sola coincidencia**, la lectura
   en `login_screen.dart:731`).

**Grado de generalización global: ~25 %.** Se generalizó el *catálogo/visualización*; el *cálculo,
la persistencia, el arqueo y el contrato SQL* siguen siendo binarios CUP/USD (con USD como única
divisa extranjera).

---

## 1. Ruta completa del cobro

### 1.1 Carrito / orden

| Paso | Archivo:línea | Detalle |
|---|---|---|
| Modelo orden | `ventiq_app/lib/models/order.dart:10-51` | `Order.total` (CUP), `items`, `pagos: List<dynamic>?` (línea 18). **Sin campo de moneda.** |
| Modelo ítem | `ventiq_app/lib/models/order.dart:236` | `OrderItem.subtotal`, `precioUnitario`, `paymentMethod`. |
| Método de pago por ítem | `ventiq_app/lib/models/payment_method.dart:3-9` | `PaymentMethod{id,denominacion,esDigital,esEfectivo,esActivo}`. **Sin moneda ni tasa.** |
| Servicio de orden | `ventiq_app/lib/services/order_service.dart:868` | `finalizeOrderWithDetails(Order, orderData)`. |
| Cálculo de subtotal con promoción | `ventiq_app/lib/screens/checkout_screen.dart:358-413` | `_calculateItemPrice(item)` → devuelve **monto en CUP** (`itemTotal`, promos aparte). |

### 1.2 Checkout: selección de moneda por método de pago

| Paso | Archivo:línea | Detalle |
|---|---|---|
| Estado | `ventiq_app/lib/screens/checkout_screen.dart:74-77` | `_usdRate`, `_mostrarSelectorMoneda`, `final Map<int,String> _paymentCurrencyByMethodId`. |
| Carga de config | `checkout_screen.dart:187-228` | `_loadStoreConfig()` lee `mostrar_selector_moneda` (línea 205 cache / 223 Supabase). |
| Carga de tasa | `checkout_screen.dart:146-172` | `_loadUsdRate()` → `CurrencyService.getUsdRate()`; fallback `getCambioCupUsd()`. |
| Mostrar toggle | `checkout_screen.dart:823-829` | Solo si `methodId != null && !esPendiente && _usdRate > 0 && _mostrarSelectorMoneda`. |
| Toggle binario | `checkout_screen.dart:888-935` | `_buildCurrencyToggle`: lista `['CUP','USD']` (línea 898); tap CUP → `remove()` (=default CUP), tap USD → `'USD'` (903-906). |
| Display "todo USD" | `checkout_screen.dart:419-442` | `_displayTotalsInUsd` = *todos* los métodos en USD (432); `_formatCheckoutAmount` etiqueta `'USD' : 'CUP'` (440). |
| Líneas de pago online | `checkout_screen.dart:459-483` | `_currencyPaymentLines`: `monto = currency=='USD' ? cupAmount/_usdRate : cupAmount` (480), `tasa_usd = currency=='USD' ? _usdRate : null` (474). |

### 1.3 Persistencia ONLINE

| Paso | Archivo:línea | Detalle |
|---|---|---|
| Crear orden | `checkout_screen.dart:1860-1965` | `_createOrder()`: valida `usesUsd && _usdRate<=0` (1889-1895). |
| Ruta online | `checkout_screen.dart:2259-2391` | `_processOnlineOrder()` → `_orderService.finalizeOrderWithDetails(updatedOrder, orderData)` (2329). Inyecta `pagos: _currencyPaymentLines` (2323). |
| Venta (RPC) | `order_service.dart:1291-1491` | `_registerSaleInSupabase()` → `fn_registrar_venta_v3` / `fn_registrar_venta_mesa_v3` (1457-1491), fallback legacy `fn_registrar_venta[_mesa]`. |
| Pagos (RPC) | `order_service.dart:1592-1789` | `_registerPaymentsInSupabase()` → `fn_registrar_pago_venta_v2` (1731) → fallback `fn_registrar_pago_venta` (1737). Idempotencia vía `_pagosCoincidenConEsperado` (1809). |
| Foto operación | `order_service.dart:1505-1511` | `update({foto_operacion_url})` sobre `app_dat_operacion_venta`. |

### 1.4 Persistencia OFFLINE

| Paso | Archivo:línea | Detalle |
|---|---|---|
| Ruta offline | `checkout_screen.dart:1968-2256` | `_processOfflineOrder()`. |
| Desglose local | `checkout_screen.dart:2008-2028` | Arma `desglose_pagos` con `moneda`, `tasa_usd`, `es_digital`, `es_efectivo` (**sin** `monto_cup_equivalente`, que se calcula al sincronizar). |
| Guardado | `checkout_screen.dart:2146` → `user_preferences_service.dart:1508-1534` | `savePendingOrder(orderData)` → **SharedPreferences**, clave `pending_orders` (`user_preferences_service.dart:88`). **No usa SQLite.** |
| Estructura | `checkout_screen.dart:2044-2120` | `orderData['desglose_pagos']` (2119), `items[]` (2096-2118), `estado='pendiente_sincronizacion'`. |

> Detalle importante: la venta offline **no** pasa por `fn_registrar_pago_venta` en el checkout; el
> desglose se sube al sincronizar.

### 1.5 Sincronización

| Paso | Archivo:línea | Detalle |
|---|---|---|
| Normalización de pagos | `auto_sync_service.dart:3695-3777` | `_pagosParaSincronizar()`: re-agrupa por `'$id|$normalizedCurrency'` (3719), construye `monto_cup_equivalente` (3728-3731). |
| Validación | `auto_sync_service.dart:3981-3990` | `usdSinTasa` → excepción *"pagos USD sin tasa válida"*. |
| Venta offline (RPC) | `auto_sync_service.dart:3998-4103` | `ventaParams` (3998-4012) → `fn_registrar_venta_offline_v4` (4023) → `_v3` (4042) → viva (4053) → `fn_registrar_venta` (4085). |
| Pagos offline (RPC) | `auto_sync_service.dart:4313-4437` | `_registerPaymentBreakdownFromOfflineData()` → `fn_registrar_pago_venta_v2` (4370) → `fn_registrar_pago_venta_offline` (4383) → `fn_registrar_pago_venta` (4416). |
| Verificación | `auto_sync_service.dart:3836-3879` | `_pagosCoincidenConEsperado` agrupa por `(id_medio_pago, moneda)` USD/CUP. |

### 1.6 Lectura / listado / ticket

| Paso | Archivo:línea | Detalle |
|---|---|---|
| Listar órdenes | `order_service.dart:1866-1949` | `fn_listar_ordenes` (1926). |
| Pagos de una venta | `order_service.dart:1225-1247` | `get_sale_payments2` → `PriceUtils.normalizePayments`. |
| Normalización lectura | `price_utils.dart:130-137, 257-286` | `paymentCurrency`, `normalizePaymentMap`. |
| Ticket | `bluetooth_printer_service.dart:1224-1229` | `PriceUtils.formatTicketMoney(...)`; `web_printer_service_web.dart:494`; `wifi_printer_service.dart:932`. |

---

## 2. Hardcodes CUP/USD (tabla completa)

> Se recorrió `ventiq_app/lib` con `grep` de literales `'CUP'|"CUP"|'USD'|"USD"` (**86 coincidencias**)
> y de `moneda` (**127 coincidencias**), más los SQL del repo. La tabla incluye también las
> *suposiciones* (no solo literales).

### 2.1 Dart — cálculo y normalización

| Archivo:línea | Fragmento | Efecto |
|---|---|---|
| `lib/utils/price_utils.dart:136` | `return raw == 'USD' ? 'USD' : 'CUP';` | **Punto central**: toda moneda ≠ USD se etiqueta CUP. |
| `lib/utils/price_utils.dart:160` | `if (paymentCurrency(payment) != 'USD') return amount;` | Equivalente CUP = monto nativo si no es USD. |
| `lib/utils/price_utils.dart:185-187` | `paymentTotalUsd` (filtra `== 'USD'`) | Total USD solo suma USD. |
| `lib/utils/price_utils.dart:192-197` | `payments.every(... 'USD') ? 'USD' : 'CUP'` | Moneda de visualización binaria. |
| `lib/utils/price_utils.dart:199-210` | `paymentUsdRate` | Solo busca `tasa_usd`. |
| `lib/utils/price_utils.dart:217-225` | `formatCupAmountForPayments` | `'* USD'` o `'* CUP'`. |
| `lib/utils/price_utils.dart:234-237` | `cupToTicketAmount` | Divide por tasa USD. |
| `lib/utils/price_utils.dart:246-253` | `formatTicketMoney` | Solo dos ramas USD/CUP. |
| `lib/utils/price_utils.dart:261-263` | `map['moneda'] == null && map['currency'] != null` | Alias, sin validar código de moneda. |
| `lib/services/currency_service.dart:7-8` | `static const int _cupId = 1; static const int _usdId = 2;` | **IDs de moneda hardcodeados.** |
| `lib/services/currency_service.dart:20-21` | `.eq('id_moneda_origen', _usdId).eq('id_moneda_destino', _cupId)` | Solo par USD→CUP. |
| `lib/services/currency_service.dart:89-93` | `moneda_origen == 'USD' && (moneda_destino == 'CUP' \|\| null)` | Solo USD→CUP. |
| `lib/services/currency_service.dart:142-143` | mismas igualdades por id | Timeline histórica solo USD→CUP. |
| `lib/services/currency_service.dart:151-152` | `.eq('moneda_origen','USD').eq('moneda_destino','CUP')` | Fallback global solo USD→CUP. |
| `lib/screens/checkout_screen.dart:432` | `(_paymentCurrencyByMethodId[id] ?? 'CUP') == 'USD'` | Default CUP. |
| `lib/screens/checkout_screen.dart:440` | `_displayTotalsInUsd ? 'USD' : 'CUP'` | Etiqueta binaria. |
| `lib/screens/checkout_screen.dart:465` | `_paymentCurrencyByMethodId[methodId] ?? 'CUP'` | Default CUP. |
| `lib/screens/checkout_screen.dart:474` | `'tasa_usd': currency == 'USD' ? _usdRate : null` | Tasa solo si USD. |
| `lib/screens/checkout_screen.dart:480` | `currency == 'USD' ? cupAmount / _usdRate : cupAmount` | Conversión solo USD. |
| `lib/screens/checkout_screen.dart:793-798` | `methodId == null ? 'CUP' : (... ?? 'CUP')` | Default CUP. |
| `lib/screens/checkout_screen.dart:898` | `['CUP', 'USD'].map((c) {` | **Toggle binario.** |
| `lib/screens/checkout_screen.dart:903-906` | `if (c == 'CUP') { remove(methodId) } else { = 'USD' }` | Solo dos estados. |
| `lib/screens/checkout_screen.dart:1889` | `_paymentCurrencyByMethodId.values.contains('USD')` | Validación solo USD. |
| `lib/screens/checkout_screen.dart:2011-2014` | `normalizedMethodId == null ? 'CUP' : (... ?? 'CUP')` | Default CUP offline. |
| `lib/screens/checkout_screen.dart:2021,2028` | `tasa_usd` / división por `_usdRate` | Solo USD. |
| `lib/services/order_service.dart:1616-1624` | `payment['moneda']?.toString().toUpperCase() == 'USD' ? 'USD' : 'CUP'` | Normaliza al persistir. |
| `lib/services/order_service.dart:1692` | `'moneda': paymentCurrencyByMethod[entry.key] ?? 'CUP'` | Default CUP. |
| `lib/services/order_service.dart:1829,1841` | key `'$id|$currency'` con USD/CUP | Idempotencia binaria. |
| `lib/services/auto_sync_service.dart:3717-3718` | `moneda?.toUpperCase() == 'USD' ? 'USD' : 'CUP'` | Normaliza sync. |
| `lib/services/auto_sync_service.dart:3728-3731,3736-3739` | `monto_cup_equivalente = USD && rate ? monto*rate : monto` | Equivalente siempre CUP. |
| `lib/services/auto_sync_service.dart:3853-3854,3865-3866` | USD/CUP | Idempotencia. |
| `lib/services/auto_sync_service.dart:3982-3985` | `pago['moneda'] == 'USD' && tasa <= 0` | Bloquea sync. |
| `lib/services/auto_sync_service.dart:4336-4338` | `'moneda': paymentData['moneda'] ?? 'CUP'` | Default CUP. |

### 2.2 Dart — caja, arqueo y conteo de efectivo

| Archivo:línea | Fragmento | Efecto |
|---|---|---|
| `lib/widgets/cash_count_dialog.dart:57-62` | `if (availableCurrencies.contains('CUP'))...; if (...'USD')...; currencies.addAll(['CUP','USD'])` | Filtra/fallback binario. |
| `lib/widgets/cash_count_dialog.dart:67-71` | fallback por moneda | Solo CUP/USD. |
| `lib/widgets/cash_count_dialog.dart:106,117` | fallback CUP `[1000..1]`, USD `[100..1]` | Denominaciones cableadas. |
| `lib/widgets/cash_count_dialog.dart:148-170` | `if (currency == 'USD') usdCup += v*c*rate; else cup += v*c;` | **Toda moneda ≠ USD suma como CUP.** |
| `lib/widgets/cash_count_dialog.dart:172-174` | `Navigator.pop(context, _totalCup + _totalUsdCup)` | Devuelve **un solo** total CUP. |
| `lib/widgets/bill_count_dialog.dart:101-103` | `if (currencies.contains('CUP')) _selectedCurrency='CUP'` | Preselección CUP. |
| `lib/widgets/bill_count_dialog.dart:200-204` | `if (_selectedCurrency == 'USD') total += v*c*_cambioCupUsd; else total += v*c;` | **Toda moneda ≠ USD suma como CUP.** |
| `lib/widgets/bill_count_dialog.dart:411` | `if (_selectedCurrency == 'USD')` | Nota de conversión solo USD. |
| `lib/widgets/bill_count_dialog.dart:459-461` | subtotal USD vs resto | Solo USD. |
| `lib/widgets/bill_count_dialog.dart:565-567` | `(v*c) USD` solo si USD | Solo USD. |
| `lib/widgets/bill_count_dialog.dart:639,661` | `'\$${...} CUP'` | Etiqueta fija CUP. |
| `lib/screens/cierre_screen.dart:386-397` | `if (moneda == 'USD') efectivoUsd += montoNativo; else efectivo += montoNativo;` | **Toda moneda ≠ USD va al cubo CUP.** |
| `lib/screens/cierre_screen.dart:558-566` | `efectivo_inicial_usd` / `efectivo_usd_esperado` | Solo USD. |
| `lib/screens/cierre_screen.dart:639-648` | idem desde resumen | Solo USD. |
| `lib/screens/cierre_screen.dart:1574,1582` | `_totalEfectivoUsd`, `_efectivoUsdEsperado` | Solo USD. |
| `lib/screens/cierre_screen.dart:3273,3380` | `'efectivo_real_usd': ...` | Solo USD. |
| `lib/screens/venta_total_screen.dart:140-163` | `if (moneda == 'USD') ... else totalCup += ...` | **Toda moneda ≠ USD al cubo CUP.** |
| `lib/screens/venta_total_screen.dart:174` | `'Cuenta por cobrar (CUP)' : 'Efectivo (CUP)'` | Etiqueta fija CUP. |

### 2.3 Dart — visualización y SMS

| Archivo:línea | Fragmento | Efecto |
|---|---|---|
| `lib/screens/orders_screen.dart:1497-1498` | `cardCurrency == 'USD' ? 'Equivalente CUP' : 'USD'` | Binario. |
| `lib/screens/orders_screen.dart:1902-1908` | `detailCurrency == 'USD'` | Binario. |
| `lib/screens/orders_screen.dart:3908-3917` | `primaryCurrency == 'USD'` | Binario. |
| `lib/widgets/order_product_summary.dart:32-41` | `currency == 'USD' ? ... : ...` | Binario. |
| `lib/screens/products_screen.dart:683`, `categories_screen.dart:886`, `categories_web_screen.dart:649`, `venta_total_screen.dart:2174`, `package_product_screen.dart:1724-2043` | `'USD: \$${_usdRate...}'`, `_usdRate > 0 ? ...` | Precios secundarios solo USD. |
| `lib/screens/checkout_screen.dart:1384-1390` | `'Equivalente USD (1 USD = ... CUP)'` | Solo USD. |
| `lib/utils/bank_sms_parser.dart:143-150` | `'...([A-Z]{3})' ... ?? 'CUP'` | Default CUP al parsear SMS. |
| `lib/models/bank_sms_payment.dart:78` | `this.moneda = 'CUP',` | Default CUP. |
| `lib/models/bank_sms_payment.dart:122` | `moneda: json['moneda'] as String? ?? 'CUP'` | Default CUP. |
| `lib/widgets/usd_rate_chip.dart:88` | `'1 USD = ${_tasa.toStringAsFixed(0)} CUP'` | Solo USD. |
| `lib/screens/settings_screen.dart:57,660-665,1619-1634` | `_isPrintUsdEnabled`, `print_usd_enabled` | Preferencia binaria de impresión. |
| `lib/services/user_preferences_service.dart:1017` | `_printUsdEnabledKey = 'print_usd_enabled'` | Preferencia binaria. |

### 2.4 SQL / backend (fuera de `lib`, pero es el contrato real)

| Archivo:línea | Fragmento | Efecto |
|---|---|---|
| `ventiq_app/sql/venta_usd.sql:2` | `ADD COLUMN ... moneda TEXT NOT NULL DEFAULT 'CUP'` | Columna genérica **con default CUP**. |
| `ventiq_app/sql/venta_usd.sql:16-19` | `ADD CONSTRAINT app_dat_pago_venta_moneda_check CHECK (moneda IN ('CUP','USD'));` | **BLOQUEANTE**: la DB rechaza cualquier otra moneda. |
| `ventiq_app/sql/venta_usd.sql:63` | `CASE WHEN UPPER(COALESCE(v_pago->>'moneda','CUP'))='USD' THEN 'USD' ELSE 'CUP' END` | **Coacción server-side**. |
| `ventiq_app/sql/venta_usd.sql:95` | `CASE WHEN v_moneda='USD' THEN v_tasa ELSE NULL END` | `tasa_usd` solo USD. |
| `ventiq_app/sql/venta_usd.sql:7-9` | `efectivo_inicial_usd`, `efectivo_real_usd`, `diferencia_usd` | Columnas de caja solo USD. |
| `ventiq_app/sql/venta_usd.sql:112` | `registrar_apertura_turno_usd` | RPC específica USD. |
| `ventiq_app/sql/fn_registrar_pago_venta_idempotente.sql:92` | `importe_sin_descuento, moneda, tasa_usd, monto_cup_equivalente` | Mismo contrato en `_v2`. |
| `ventiq_app/sql_offline/13_...con_pagos.sql:119` | `fn_registrar_pago_venta(...)` | Payload offline con mismas claves. |
| `sql_triggers/sync_valor_usd_carnaval.sql:2,20,29-33` | `id_moneda_origen = 2, id_moneda_destino = 1`, `moneda_origen='USD'` | Trigger específico del par 2→1. |
| `SQL_OPTIMIZATION/trigger_actualizar_precios_cup_por_tasa_usd.sql:48-59` | `IF NEW.id_moneda_origen = 2 AND NEW.id_moneda_destino = 1 ... ELSIF 1 AND 2` | Triggers binarios. |
| `VentiQ.sql:393` | `moneda_factura character DEFAULT 'USD'::bpchar` | Recepciones (no venta). |
| `VentiQ.sql:1205-1213` | `tasas_conversion(moneda_origen, moneda_destino, tasa)` FK a `monedas(codigo)` | **Sí soporta pares arbitrarios.** |
| `VentiQ.sql:1195-1204` | `monedas(codigo PK, nombre, simbolo, pais, activo)` | **Catálogo de monedas arbitrarias existe.** |

---

## 3. Modelos Dart y esquema local

### 3.1 Modelos

| Modelo | Archivo:línea | Campos de moneda/tasa |
|---|---|---|
| `Order` | `lib/models/order.dart:10-41` | `total` (CUP), `pagos: List<dynamic>?` (18). **Sin `moneda`.** |
| `OrderItem` | `lib/models/order.dart:236+` | `subtotal`, `precioUnitario`. **Sin `moneda`.** |
| `PaymentMethod` | `lib/models/payment_method.dart:3-9` | **Sin `moneda`/`tasa`.** Sentinels `pagoPendienteId=998` (15). |
| `BankSmsPayment` | `lib/models/bank_sms_payment.dart:55,78,101,122` | `moneda` con default `'CUP'` (78) y `?? 'CUP'` (122). |
| Turno/caja | No hay modelo Dart: se maneja como `Map<String,dynamic>` | Claves `efectivo_inicial`, `efectivo_inicial_usd`, `efectivo_real`, `efectivo_real_usd` (`apertura_screen.dart:2594-2595`, `cierre_screen.dart:3271-3273`). |
| Preferencias | `lib/services/user_preferences_service.dart:1017,1028-1030` | `print_usd_enabled`, `monedas_denominacion`, `cambio_cup_usd`, `hidden_denominations`. |

**No existe un modelo Dart de "Moneda"** (`grep ':moneda' | class .*Moneda` → ninguna clase).
El código de moneda viaja como `String` suelto en mapas.

### 3.2 Esquema local offline: **SharedPreferences, no SQLite**

- Órdenes pendientes: **SharedPreferences**, clave `pending_orders`
  (`user_preferences_service.dart:88`, `savePendingOrder` 1508-1534, `getPendingOrders` 1583-1591).
  Los pagos pendientes viven dentro del JSON de la orden, en `desglose_pagos`
  (`checkout_screen.dart:2119`). **No hay tabla SQLite de pagos pendientes.**
- Turnos offline: también SharedPreferences (`createOpenOfflineTurno`, `saveOfflineTurno`
  `user_preferences_service.dart:3016`, `getOfflineTurnos` 2273).
- **SQLite existe pero solo para catálogo y ops de admin** (`lib/services/offline_database_service.dart`):
  - `offline_sections` (127), `offline_categories` (135), `offline_products` (144),
    `offline_meta` (166), `admin_pending_ops` (177).
  - **Ninguna columna de moneda/tasa.**
  - En web se degrada a SharedPreferences (`_webPrefsMode`, `offline_database_service.dart:17,120-123`).
- Caché de denominaciones: SharedPreferences `monedas_denominacion`
  (`user_preferences_service.dart:1028,4687-4732`).

---

## 4. Payload EXACTO al backend

### 4.1 Venta online — `fn_registrar_venta_v3` / `fn_registrar_venta_mesa_v3`

Origen: `lib/services/order_service.dart:1440-1451` (fallback legacy `fn_registrar_venta[_mesa]`, 1457-1460).

```
p_codigo_promocion : String?
p_denominacion     : String        // 'Venta Inventtia Caja - <id>' | 'Mesa X - Zona Y'
p_estado_inicial   : 1
p_id_tpv           : int
p_observaciones    : String
p_productos        : [{ id_producto, id_variante, id_opcion_variante, id_ubicacion,
                        id_presentacion, cantidad, precio_unitario, sku_producto,
                        sku_ubicacion, es_producto_venta }]      // order_service.dart:1355-1367
p_uuid             : UUID (userId)
p_id_cliente       : int?
p_id_mesa          : int?          // solo en la variante _mesa
```
**No hay ninguna clave de moneda ni de tasa en la venta.** El precio unitario va en CUP
(`order_service.dart:1344`).

### 4.2 Pagos online — `fn_registrar_pago_venta_v2` (fallback `fn_registrar_pago_venta`)

Origen: `order_service.dart:1688-1696` y `1731-1741`.

```
p_id_operacion_venta : int
p_pagos : [ { id_medio_pago, monto, tipo_pago, moneda, tasa_usd, referencia_pago } ]
```
- `monto`: **monto nativo** (en la moneda indicada).
- `moneda`: `'CUP'` | `'USD'` (única bifurcación, `order_service.dart:1616-1624`).
- `tasa_usd`: solo si USD (`order_service.dart:1622-1624`).
- **`monto_cup_equivalente` NO se envía en el flujo online**: lo calcula el servidor
  (`venta_usd.sql:80,96`).

### 4.3 Venta offline — `fn_registrar_venta_offline_v4` (cadena `_v3` → viva → `fn_registrar_venta`)

Origen: `auto_sync_service.dart:3998-4012` y `4023`.

```
p_client_uuid      : UUID
p_codigo_promocion : String?
p_denominacion     : 'Venta Offline - <id>'
p_estado_inicial   : 1
p_id_tpv           : int
p_observaciones    : String
p_productos        : [...]                    // auto_sync_service.dart:3946-3965
p_uuid             : UUID
p_id_cliente       : int?
p_fecha_creacion   : ISO-8601
p_pagos            : [ ... ]                  // ver abajo
```

### 4.4 Pagos offline — `fn_registrar_pago_venta_v2` / `_offline` / `fn_registrar_pago_venta`

Origen: `auto_sync_service.dart:3722-3741` (`_pagosParaSincronizar`) y `4332-4343`.

```
p_id_operacion_venta : int
p_pagos : [{
    id_medio_pago, monto, tipo_pago, moneda, tasa_usd,
    monto_cup_equivalente,        // calculado en el cliente (auto_sync_service.dart:3728)
    denominacion?, referencia_pago
}]
```
`_registerPaymentBreakdownFromOfflineData` añade además `p_client_uuid` y `p_uuid_usuario`
en la variante `fn_registrar_pago_venta_offline` (`auto_sync_service.dart:4383-4391`).

### 4.5 Validación server-side que hay que cambiar sí o sí

- `venta_usd.sql:16-19` — `CHECK (moneda IN ('CUP','USD'))`.
- `venta_usd.sql:63` — `CASE ... 'USD' ELSE 'CUP'` (coacciona cualquier código).
- `venta_usd.sql:76-78` — exige `tasa_usd > 0` cuando `moneda='USD'`; **no hay validación de tasa
  para otras monedas**.
- `venta_usd.sql:80` — `monto_cup_equivalente = CASE WHEN USD THEN monto*tasa ELSE monto END`
  (asume que todo lo no-USD ya está en CUP).

---

## 5. Caja, turnos y arqueo

### 5.1 Apertura

| Paso | Archivo:línea | Detalle |
|---|---|---|
| UI | `lib/screens/apertura_screen.dart` | `_montoInicialController` (CUP) + `_montoInicialUsdController` (USD). |
| Online | `apertura_screen.dart:2018-2028` | `TurnoService.registrarAperturaTurno(efectivoInicial, efectivoInicialUsd, ...)`. |
| RPC | `lib/services/turno_service.dart:760-775` | `efectivoInicialUsd == null ? 'registrar_apertura_turno_v3' : 'registrar_apertura_turno_usd'`; parámetro `p_efectivo_inicial_usd`. |
| Offline | `apertura_screen.dart:2564-2601` | `_createOfflineApertura` → claves `efectivo_inicial` (2594) y `efectivo_inicial_usd` (2595). |
| Sync offline | `auto_sync_service.dart:1359-1398` | `p_efectivo_inicial_usd` / RPC `fn_apertura_turno_offline_usd` (1396-1398). |

**Respuesta: NO.** La apertura solo puede contar CUP + USD (dos campos fijos).

### 5.2 Cierre

| Paso | Archivo:línea | Detalle |
|---|---|---|
| Totales por moneda | `cierre_screen.dart:341-425` | `_calculateClosureTotalsFromOrders`: `efectivoUsd`/`transferenciaUsd` solo si `moneda == 'USD'` (386,393); **el resto cae en CUP**. |
| Campos | `cierre_screen.dart:35,78-80` | `_montoFinalUsdController`, `_efectivoUsdEsperado`, `_efectivoInicialUsd`, `_totalEfectivoUsd`. |
| UI | `cierre_screen.dart:2028-2065` | Campo "Efectivo real USD" + diferencia USD (`_buildDiferenciaUsd` 2377-2415). |
| Envío online | `cierre_screen.dart:3037` | `efectivoRealUsd: double.tryParse(_montoFinalUsdController.text) ?? 0`. |
| RPC | `turno_service.dart:593-605` | `efectivoRealUsd == null ? 'fn_cerrar_turno_tpv' : 'fn_cerrar_turno_tpv_usd'`. |
| Snapshot local | `cierre_screen.dart:3259-3283` | `efectivo_real_usd` (3273). |
| Offline | `cierre_screen.dart:3349-3380` | `efectivo_real_usd` (3380); sync en `auto_sync_service.dart:1114,1135,2255`. |

**Respuesta: NO.** Solo CUP + USD. Cualquier tercera moneda se contaría como CUP.

### 5.3 Los dos diálogos de conteo (importante)

**`CashCountDialog`** (`lib/widgets/cash_count_dialog.dart`) — usado en CIERRE:
- **Sí enumera N monedas**: `getMonedasDisponibles()` (52-53) y filtra CUP/USD solo como
  *fallback* (57-62).
- **Pero solo sabe convertir USD**: `if (currency == 'USD') usdCup += ...; else cup += ...`
  (158-162) — **una moneda distinta de USD se suma como si fuera CUP**.
- Devuelve **un único total en CUP** (172-174), que el cierre escribe en el campo CUP:
  `cierre_screen.dart:2325-2335` → `_montoFinalController.text = total`.

**`BillCountDialog`** (`lib/widgets/bill_count_dialog.dart`) — usado al **cobrar/cerrar órdenes**:
- Dropdown con N monedas (395-409).
- Conversión solo USD (200-204, 459-461, 565-567); etiqueta fija CUP (639, 661).
- Sirve para *verificar* el objetivo en CUP (`_targetAmount`, 49-50), no para devolver un monto
  nativo por moneda.
- Usado en `orders_screen.dart:3487-3506` (pago de orden) y `preorder_screen.dart:815-825`.
- **En el checkout de venta normal NO se usa** (no hay conteo de billetes al cobrar).

---

## 6. Denominaciones

| Aspecto | Hallazgo | Evidencia |
|---|---|---|
| Tabla | `app_dat_denominaciones_moneda` | `lib/screens/login_screen.dart:731` |
| Query | `select('*').eq('active', true).order('codigo_moneda').order('denominacion')` | `login_screen.dart:730-735` |
| Alcance | **GLOBAL** (sin filtro `id_tienda`) | `login_screen.dart:730-735` |
| Columnas usadas | `id`, `codigo_moneda`, `denominacion` (valor numérico), `active` | `login_screen.dart:732-735`; `user_preferences_service.dart:4744,4796`; `bill_count_dialog.dart:141,197` |
| Caché | SharedPreferences `monedas_denominacion` | `user_preferences_service.dart:1028,4687-4732` |
| Monedas disponibles | `getMonedasDisponibles()` → `Set<String>` de `codigo_moneda` | `user_preferences_service.dart:4790-4808` |
| Denominaciones por moneda | `getDenominacionesPorMoneda(codigo)` filtra `active==true`, ordena desc | `user_preferences_service.dart:4735-4762` |
| Fallback | `CashCountDialog`: CUP `[1000,500,200,100,50,20,10,5,3,1]`, USD `[100,50,20,10,5,1]` | `cash_count_dialog.dart:100-120` |
| Ocultas | `hidden_denominations` por `id` | `user_preferences_service.dart:1030,4765-4787` |
| **DDL** | **NO ENCONTRADO**. Buscado: `grep 'denominaciones_moneda'` en todo el workspace → solo `login_screen.dart:731`. No está en `VentiQ.sql` ni en `supabase/`. | — |
| **Admin** | **NO ENCONTRADO**. No hay pantalla/servicio de superadmin que gestione monedas ni denominaciones: `grep 'denominaciones_moneda'` en `ventiq_superadmin/` → 0 coincidencias. La app superadmin sí tiene catálogos de monedas *de planes* (`flow_planes_screen.dart:465`: `['USD','CUP','EUR','MLC']`), pero **no** de medios de cobro del TPV. | — |

**¿Soporta N monedas el código?** *Parcialmente*: la **lista** de monedas es N (dropdowns y
`getMonedasDisponibles`), pero **la aritmética solo distingue USD de "todo lo demás = CUP"**
(`cash_count_dialog.dart:158-162`, `bill_count_dialog.dart:200-204`).

---

## 7. Configuración de tienda relevante

| Clave | Dónde se define | Dónde se lee | Notas |
|---|---|---|---|
| `mostrar_selector_moneda` | `sql_updates/add_mostrar_selector_moneda.sql:2-6` (`app_dat_configuracion_tienda`, `boolean DEFAULT false`) | `lib/services/store_config_service.dart:339-349`; `checkout_screen.dart:205` (cache) y `223` (Supabase) | Solo **habilita** el toggle binario CUP/USD. El comentario SQL dice literalmente *"selector de moneda (CUP/USD)"*. |
| Escritura de `mostrar_selector_moneda` | **NO ENCONTRADO en `ventiq_app`** (solo lector). Se escribe desde admin: `ventiq_admin_app/lib/services/store_config_service.dart:245` y `ventiq_admin_app/lib/widgets/global_config_tab_view.dart:464`. | — | — |
| `moneda_factura` | `VentiQ.sql:393` (columna de recepción/extracción, `DEFAULT 'USD'`) | **No se lee en el flujo de venta de `ventiq_app`**. Solo en conteos de inventario admin: `lib/services/admin_inventory_service.dart:150,166,1150,1571,1588,1766,1786`. | No afecta al cobro. |
| `cambio_cup_usd` | Preferencia local | `user_preferences_service.dart:1029,4865-4914`; usada por `currency_service.dart:58,102,105,114,123` | Caché de la tasa USD. |
| `tasa_cambio_extraoficial` | **NO ENCONTRADO DDL** (ver abajo) | `currency_service.dart:16-24,139-145`; columnas usadas: `id_tienda`, `id_moneda_origen`, `id_moneda_destino`, `valor_cambio`, `usar_precio_toque`, `activo`, `created_at`. | Por tienda + par de monedas por **id**. |
| `tasas_conversion` | `VentiQ.sql:1205-1214` (`moneda_origen`, `moneda_destino` FK a `monedas(codigo)`) | `currency_service.dart:38-41,148-153` | Global; **soporta pares arbitrarios por código**. |
| `usar_precio_toque` | — | `currency_service.dart:72,180` | Si es `true`, ignora `valor_cambio` y usa la tasa global. |
| `print_usd_enabled` | Preferencia local | `user_preferences_service.dart:1017,1072-1082`; `settings_screen.dart:660-665`; impresoras `bluetooth_printer_service.dart:975`, `wifi_printer_service.dart:673`, `web_printer_service_web.dart:42` | Si está activo **y** hay tasa, el ticket se imprime en USD (todo-o-nada). |
| `monedas_denominacion` | Preferencia local | `user_preferences_service.dart:1028` | Catálogo cacheado. |

**NO ENCONTRADO**: DDL de `tasa_cambio_extraoficial`.
Buscado: `grep 'tasa_cambio_extraoficial\s*\(|CREATE TABLE.*tasa_cambio'` en `*.sql` de todo el
workspace → solo *usos* (`sql_triggers/sync_valor_usd_carnaval.sql`, `SQL_OPTIMIZATION/*`,
`ventiq_admin_app/*`); ninguna definición.

---

## 8. Grado de generalización y puntos de extensión

### 8.1 Lo que YA está generalizado (reutilizable)

| Pieza | Por qué sirve | Evidencia |
|---|---|---|
| Catálogo `monedas(codigo, nombre, simbolo, pais, activo)` | Soporta N monedas reales | `VentiQ.sql:1195-1204` |
| `tasas_conversion(moneda_origen, moneda_destino, tasa)` | Pares arbitrarios por código | `VentiQ.sql:1205-1214` |
| `tasa_cambio_extraoficial` (id_tienda + par por id + `usar_precio_toque`) | Modelo por tienda y par | `currency_service.dart:16-24` |
| `app_dat_denominaciones_moneda` + `codigo_moneda` | Denominaciones por moneda, N | `login_screen.dart:730-735` |
| `getMonedasDisponibles()` / `getDenominacionesPorMoneda()` | API ya lista para N | `user_preferences_service.dart:4735,4790` |
| Dropdowns de moneda en ambos diálogos | UI ya lista para N | `bill_count_dialog.dart:395-409`, `cash_count_dialog.dart:246` |
| `app_dat_pago_venta.moneda TEXT` | Columna textual (no FK, pero flexible) | `venta_usd.sql:2` |
| `mostrar_selector_moneda` | Interruptor de tienda ya existente | `add_mostrar_selector_moneda.sql:2-6` |

### 8.2 Lo que está CABLEADO (lista de trabajo)

1. **Contrato SQL**: quitar `CHECK (moneda IN ('CUP','USD'))` (`venta_usd.sql:16-19`) y sustituir la
   coacción `CASE` (`63`, `80`) por una tasa genérica. Decidir entre `moneda_id`/`codigo` +
   `tasa` (no `tasa_usd`) o una tabla `app_dat_pago_venta_tasa`.
2. **`CurrencyService`**: eliminar `_cupId=1`/`_usdId=2` (`currency_service.dart:7-8`) y
   generalizar `getUsdRate` → `getRate(from, to)` usando `monedas.codigo` y
   `tasas_conversion`/`tasa_cambio_extraoficial` (`10-32, 51-125, 128-204`).
3. **Núcleo de cálculo**: `PriceUtils.paymentCurrency` y todo su bloque USD
   (`price_utils.dart:130-253`). Debe pasar de booleano a `(codigo, tasa)`.
4. **Checkout**: `_buildCurrencyToggle` (`checkout_screen.dart:888-935`) → selector N monedas;
   `_displayTotalsInUsd` (419-434) → multimoneda; `_currencyPaymentLines` (459-483) y el bloque
   offline (2011-2028).
5. **Persistencia**: `order_service.dart:1616-1624` y `auto_sync_service.dart:3717-3741, 3853-3866,
   3982-3985, 4336-4338` → normalización genérica y `monto_cup_equivalente` calculado con la tasa
   del par correspondiente.
6. **Arqueo/cierre**: `cierre_screen.dart:341-425` y `cash_count_dialog.dart:148-170` →
   acumuladores por moneda (mapa `codigo → total`) en vez de dos cubos + `else CUP`.
   `BillCountDialog` (200-204) igual.
7. **Caja**: columnas `efectivo_inicial_usd`/`efectivo_real_usd`/`diferencia_usd`
   (`venta_usd.sql:7-9`) → columnas por moneda o tabla hija; RPC `*_usd` (`turno_service.dart:596,763`)
   → RPC con lista de montos por moneda.
8. **Modelo**: crear `Currency`/`Money` y tipar `Order.pagos` (`models/order.dart:18`) en vez de
   `List<dynamic>` con claves string.
9. **Admin**: no existe UI de superadmin para `app_dat_denominaciones_moneda`
   (**NO ENCONTRADO**, ver §6/§9).

### 8.3 Puntos de extensión recomendados (orden de menor a mayor riesgo)

| # | Extensión | Archivos |
|---|---|---|
| E1 | Modelo `Currency` + `Money(amount, code)` | `lib/models/` (nuevo), `lib/models/order.dart` |
| E2 | `CurrencyService.getRate(from,to)` genérico y catálogo cacheado de monedas | `lib/services/currency_service.dart`, `lib/services/user_preferences_service.dart` |
| E3 | Generalizar `PriceUtils` (mapa de pagos con `moneda`+`tasa`) | `lib/utils/price_utils.dart` |
| E4 | Selector N monedas por método en checkout | `lib/screens/checkout_screen.dart:888-935` |
| E5 | Normalización genérica online/offline | `lib/services/order_service.dart`, `lib/services/auto_sync_service.dart` |
| E6 | Arqueo multimoneda (cierre + caja chica) | `lib/screens/cierre_screen.dart`, `lib/widgets/cash_count_dialog.dart`, `lib/widgets/bill_count_dialog.dart` |
| E7 | Migración SQL: quitar CHECK, tasa genérica, caja multimoneda, RPC genéricas | `ventiq_app/sql/venta_usd.sql` + nueva migración |
| E8 | UI superadmin de monedas/denominaciones | `ventiq_superadmin/` (**no existe hoy**) |

---

## 9. Riesgos y preguntas abiertas

1. **¿Quién administra `app_dat_denominaciones_moneda`?**
   **NO ENCONTRADO** en el repo: `grep 'denominaciones_moneda'` en todo el workspace → 1 sola
   coincidencia (lectura, `login_screen.dart:731`). No hay DDL ni UI de superadmin. Si las monedas
   arbitrarias deben definirse "desde el superadmin", **hay que construir esa pieza**.
   *Riesgo*: hoy la lista llega desde una tabla que nadie administra desde estas apps (¿SQL manual?
   ¿otro sistema?). Confirmar con el equipo de backend.
2. **Constraint duro en la DB** (`venta_usd.sql:16-19`). Sin migración, cualquier intento de guardar
   `EUR` falla con error de constraint (o se coacciona a `CUP` en la rama del RPC, `venta_usd.sql:63`,
   dependiendo de si se usa `_v2` o la versión con `CASE`). **Ambos caminos son incorrectos**:
   uno falla, el otro corrompe el dato.
3. **`tasa_usd` como nombre de columna**: aunque se agregaran monedas, cada pago necesita su propia
   tasa y su divisa base. Con `monto_cup_equivalente` como único equivalente, toda contabilidad
   intermedia sigue anclada a CUP (no a USD, que es el objetivo declarado).
4. **Conversión cruzada**: hoy solo existe USD→CUP. Cobrar `EUR` requeriría EUR→CUP y/o EUR→USD.
   `tasas_conversion` lo permite por diseño, pero **`CurrencyService` nunca lo consulta por par**
   (`currency_service.dart:89-93,151-152`).
5. **`usar_precio_toque`** (`currency_service.dart:72,180`) desactiva la tasa por tienda y cae a la
   global; al generalizar, ¿se replica por par de monedas? Definir.
6. **Redondeo**: hoy el monto USD se guarda nativo + `tasa_usd` + `monto_cup_equivalente`
   (`price_utils.dart:162-171` tolera diferencias de redondeo). Con N monedas, definir política de
   redondeo por divisa (2 decimales vs enteros en CUP).
7. **Offline**: la normalización ocurre **en el sincronizar** (`auto_sync_service.dart:3717`), no al
   guardar (`checkout_screen.dart:2020` ya escribe `moneda`). Si se cambia la regla, hay riesgo de
   **órdenes pendientes viejas** con `moneda` no reconocida. Definir migración de
   `pending_orders` (SharedPreferences).
8. **Idempotencia**: `_pagosCoincidenConEsperado` agrupa por `(id_medio_pago, moneda)`
   (`order_service.dart:1806-1854`, `auto_sync_service.dart:3833-3879`). Con N monedas, si la
   normalización cambia, la guarda puede no reconocer pagos ya escritos → **riesgo de duplicado**
   en el reintento. Cambiar en el mismo deploy que la migración.
9. **Tickets**: `print_usd_enabled` es binario y la conversión es *todo-o-nada*
   (`price_utils.dart:192-197,240-253`). Un ticket con pago mixto EUR+CUP siempre se imprime en CUP.
10. **Caja chica / fondos** (`egreso_screen.dart:176-183`) lee `dep_dat_banco(... id_moneda ...)`,
    es decir el modelo de *cuentas* sí tiene `id_moneda`; conviene reutilizarlo como referencia.
    **No investigado a fondo** (fuera del alcance de este recon de cobro).

### Búsquedas realizadas que no dieron resultado (resumen de "NO ENCONTRADO")

| Qué | Búsqueda | Resultado |
|---|---|---|
| DDL de `app_dat_denominaciones_moneda` | `grep 'denominaciones_moneda'` (workspace) | 1 match (lectura) |
| DDL de `tasa_cambio_extraoficial` | `grep 'CREATE TABLE.*tasa_cambio'` en `*.sql` | 0 (solo usos) |
| UI/servicio de superadmin para monedas de cobro | `grep 'denominaciones_moneda'` + `grep 'moneda'` en `ventiq_superadmin/lib` | 0 para monedas de cobro; solo monedas de *planes* |
| Esquema SQLite de pagos pendientes | `grep 'CREATE TABLE\|openDatabase\|sqflite'` en `ventiq_app/lib` | SQLite = catálogo + admin ops; pagos pendientes en SharedPreferences |
| Modelo Dart `Moneda`/`Currency` | `grep 'moneda'` en `ventiq_app/lib/models` | Solo `bank_sms_payment.dart` tiene `moneda: String` |
| Lectura de `moneda_factura` en el flujo de venta | `grep 'moneda_factura'` en `ventiq_app/lib` | Solo `admin_inventory_service.dart` (inventario/recepción) |
