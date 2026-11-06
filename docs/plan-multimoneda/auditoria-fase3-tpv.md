# Auditoría independiente del TPV (`ventiq_app`) para la Fase 3 — contraste de `plan.md` §6.3

> **Modo**: solo lectura. No se modificó ni una línea del código.
> **Alcance auditado**: `ventiq_app/` (TPV vendedor) y, como contrato de referencia, los `.sql` del repo
> (`ventiq_app/sql/`, `ventiq_app/sql_offline/`, `funcionalidad_cocina/`).
> **Base**: `plan.md` §6.3 (tabla de 13 filas), §4.4 (modelo de pago) y `docs/plan-multimoneda/recon-ventiq_app.md`
> (contrastado, no asumido).
> **Estado del árbol al auditar**: commit `d56fbcae`, `git status --porcelain` **no** muestra ningún archivo de
> `ventiq_app/` modificado — las fases 1 y 2 no tocaron la app. Por eso las citas del plan siguen siendo, en
> general, válidas; los desajustes encontrados son de **contenido**, no de deriva del código.
> **Fecha**: 2026-11-04.

---

## 0. Veredicto en cinco líneas

1. **Ninguna de las 13 filas de §6.3 apunta a un archivo/línea que ya no exista.** 8 son exactas; 2 traen un dato
   inexacto (fila 2: «30 llamadas» → son **13**; fila 4: `_paymentCurrencyByMethodId` **ya** es `Map<int,String>`);
   3 son correctas pero **incompletas** (filas 5, 6 y 11).
2. **La tabla es un buen mapa, no un inventario.** Fuera de ella quedan **6 puntos que escriben
   `app_dat_pago_venta` o que deciden/suman moneda**, uno de ellos con un INSERT directo del cliente.
3. **El riesgo más grave no está en el cliente: está en que `fn_registrar_pago_venta_v2` sigue vivo.** Coacciona
   *cualquier* moneda ≠ `USD` a `'CUP'` y calcula el equivalente como `monto` (no `monto*tasa`). La app actual la
   prefiere. Es la trampa de la ventana de despliegue.
4. **El modelo de moneda por método de pago (un `String` por `id_medio_pago`) no permite cobrar el mismo método en
   dos monedas.** No es un detalle de UI: limita el producto (efectivo CUP + efectivo USD en la misma venta).
5. **Offline**: `pending_orders` es compatible con el normalizador propuesto **salvo** por dos escritores que no
   ponen moneda (edición de desglose offline y preorden), y por un cuadre offline que ignora el USD.

---

## 1. Lista de verificación de §6.3 (fila por fila)

Leyenda: **OK** = archivo/línea correctos y el cambio descrito es cierto · **INEXACTO** = el punto de cambio es
real pero algún dato de la fila no lo es · **INCOMPLETO** = cierto, pero le faltan puntos del mismo archivo/servicio.

| # | Plan §6.3 | Veredicto | Evidencia verificada |
|---|---|---|---|
| 1 | `lib/models/currency.dart` **(nuevo)**; `Currency`/`Money`; hoy la moneda viaja como `String` en mapas | **OK** | No existe: `glob ventiq_app/lib/models/*.dart` → 18 modelos, ninguno `currency.dart`. La moneda viaja como `String` en mapas: `checkout_screen.dart:77,465,473`; `order_service.dart:1604,1692`; `auto_sync_service.dart:3704,3726`; `models/bank_sms_payment.dart:78,122`. `Order.pagos` sigue siendo `List<dynamic>?` (`models/order.dart`, ver fila 3 del recon). |
| 2 | `CurrencyService`: borrar `_cupId=1`/`_usdId=2` (`:7-8`); añadir `getRate(from,to)`/`getRatesForStore()`; `getUsdRate()` se conserva «para no tocar 30 llamadas»; cachear catálogo+tasas | **INEXACTO** | `_cupId`/`_usdId` **sí** están en `currency_service.dart:7-8` y se usan en `:20-21` y `:142-143`. Pero las llamadas a `getUsdRate()` son **13**, no 30 (grep `getUsdRate()` en `ventiq_app/lib` → 13 usos + 1 definición): `categories_screen:369`, `categories_web_screen:197`, `usd_rate_chip:37`, `checkout_screen:152`, `orders_screen:137`, `products_screen:150`, `package_product_screen:374`, `settings_screen:3758`, `device_offline_prep_service:107`, `bluetooth_printer_service:980`, `venta_total_screen:254`, `web_printer_service_web:47`, `wifi_printer_service:678`. El «alias» es viable pero el argumento de coste está mal dimensionado. |
| 3 | `price_utils.dart`: `paymentCurrency` (`:136`) deja de colapsar; `paymentCupEquivalent` con `tasa_cambio`; `paymentTotalUsd` → `paymentTotalIn`; `formatTicketMoney` por moneda | **OK** | `paymentCurrency` en `:130-137` (el `return` es `:136`) ✓; `paymentCupEquivalent` `:155-174` (solo `tasa_usd`, `:162`) ✓; `paymentTotalUsd` `:185-187` ✓; `formatTicketMoney` `:240-254` ✓. El resto de funciones con la misma asunción está en §2.1. |
| 4 | `checkout_screen.dart`: `_buildCurrencyToggle` (`:888-935`) de `['CUP','USD']` a monedas de `app_dat_tienda_moneda`; `_paymentCurrencyByMethodId` «pasa a `Map<int,String>`»; `_currencyPaymentLines` (`:459-483`) y bloque offline (`:2011-2028`) con la tasa del par; mostrar total base + desglose | **INEXACTO** | `_buildCurrencyToggle` **es exactamente** `:888-935`, con `['CUP','USD']` en `:898` ✓. `_currencyPaymentLines` **es** `:459-483` (`tasa_usd` en `:474`, división en `:480`) ✓. Bloque offline **es** `:2011-2028` (`:2020`, `:2021`, `:2026-2028`) ✓. **Pero** `_paymentCurrencyByMethodId` ya está declarado `final Map<int, String>` en `checkout_screen.dart:77`: no hay cambio de tipo, solo de dominio de valores. |
| 5 | `order_service.dart`: `_registerPaymentsInSupabase` (`:1592-1789`): normalización genérica (`:1616-1624`), enviar `tasa_cambio`, encadenar `fn_registrar_pago_venta_v4` → `_v2` → original; idempotencia `_pagosCoincidenConEsperado` (`:1809`) | **INCOMPLETO** | Función real `:1591-1788` (comentario `:1591`, `}` de cierre `:1788`) ✓; normalización `:1616-1624` ✓; idempotencia `:1802-1854` (helper `:1809`) ✓; cadena **actual** `_v2`→v1 en `:1730-1741` ✓ (el `_v4` es el cambio pendiente, correcto). **Falta** en la fila: el camino de respaldo `:1627-1662` que, si `order.pagos` viene vacío, registra **siempre en CUP** (`:1692`), y los otros dos puntos que escriben pagos en este mismo archivo (§2.3). |
| 6 | `auto_sync_service.dart`: `_pagosParaSincronizar` (`:3695-3777`) genérico, `monto_cup_equivalente = monto*tasa_cambio`, validación «moneda ≠ CUP requiere tasa» (`:3981-3990`); reparación de pagos (`:4313-4437`) | **INCOMPLETO** | Los cuatro rangos son exactos: `:3695-3777` ✓, normalización `:3717`, equivalente `:3728-3731`, validación `:3981-3990` ✓, reparación `:4313-4437` ✓. **Falta** en la fila: `_repairMissingSalePayments` (`:3411-3462`) que es una **segunda** reparación que también reescribe pagos, y la selección de RPC de apertura/cierre offline por `usd == null` (§2.4). |
| 7 | `cierre_screen.dart`: `_calculateClosureTotalsFromOrders` (`:341-425`) de 2 cubos a `Map<codigo,total>`; campos de efectivo real por moneda; `p_efectivo_real_por_moneda` | **OK** | Función `:330-425` exacta; cubos `efectivoUsd`/`transferenciaUsd` en `:344-346`, `moneda == 'USD'` en `:386`, `:393`; retorno `:416-424`. **No** se cita en la fila, pero pertenece al mismo cambio: `_showCashCountDialog` vuelca un único total al campo CUP (`:2325-2335`). |
| 8 | `apertura_screen.dart`: campos dinámicos en vez de solo `_montoInicialUsdController`; `p_efectivo_inicial_por_moneda` | **OK** | `_montoInicialUsdController` en `:33`, UI en `:1424`, envío online `efectivoInicialUsd` en `:2007-2021`, payload offline `efectivo_inicial_usd` en `:2595`. |
| 9 | `cash_count_dialog.dart`: `:148-170` de `if USD/else CUP` a acumuladores por moneda; devolver mapa, no un total CUP (`:172-174`) | **OK** | `_calculateTotals` `:148-170` (`if (currency == 'USD')` en `:158`), `_useTotal` devuelve `_totalCup + _totalUsdCup` en `:172-174`. |
| 10 | `bill_count_dialog.dart`: conversión genérica (`:200-204`), etiquetas por moneda (`:639,661`) | **OK** | `:200-204` exacto; etiquetas `'\$... CUP'` en `:639` y `:661`. |
| 11 | `orders_screen.dart`, `venta_total_screen.dart`, `order_product_summary.dart`, `usd_rate_chip.dart`: sustituir condicionales binarias; renombrar `usd_rate_chip` | **INCOMPLETO** | Los 4 archivos existen y tienen el patrón: `orders_screen:1497-1502`, `:1806-1819`, `:3897-3923`; `venta_total_screen:115-198` (`:140,152,158`), `:2030-2065`, `:2174`; `order_product_summary:32-41`; `usd_rate_chip:88`. **Falta**: `cierre_pendiente_detalle_screen.dart:465-477` (imprime el monto del pago **sin** código de moneda) y `orders_screen:3508-3539` (`_resolveCashExpectedAmount` suma efectivo nativo de varias monedas como si fuera una). |
| 12 | `turno_service.dart`: `:593-605` y `:760-775`: elegir RPC por `por_moneda`, no por `usd == null` | **OK** | Selección en `:593-596` (`efectivoRealUsd == null ? 'fn_cerrar_turno_tpv' : '..._usd'`) y en `:761-767` (`registrar_apertura_turno_v3` / `..._usd`). Detalle no advertido: `cierre_screen:3035-3037` pasa `efectivoRealUsd: double.tryParse(...) ?? 0`, es decir **nunca null** ⇒ en la práctica la variante `_usd` es la única que se usa al cerrar desde la pantalla. |
| 13 | `user_preferences_service.dart`: cache de catálogo (`monedas`+`tasas`+`denominaciones`) «ya existe para denominaciones» (`:4687-4757`); extender a tasas por moneda | **OK (rango ±10)** | Bloque real `:4684-4762`: `saveMonedasDenominacion :4686-4704`, `getMonedasDenominacion :4706-4732`, `getDenominacionesPorMoneda :4734-4762`. Claves en `:1028` (`monedas_denominacion`) y `:1029` (`cambio_cup_usd`). **Precisión**: de «catálogo» solo existe el de denominaciones; **no** hay cache de `monedas` ni de `tasas_conversion` (solo una tasa USD escalar, `:4865-4914`). |

**Resumen**: 8 OK · 2 INEXACTO (filas 2 y 4) · 3 INCOMPLETO (filas 5, 6 y 11). Ninguna fila «muerta».

---

## 2. HUECOS: lo que normaliza, suma o decide moneda y **no** está en §6.3

### 2.1 `price_utils.dart` — las 10 funciones que asumen CUP/USD (no solo `paymentCurrency`)

Se leyó el archivo completo (346 líneas). `paymentCurrency` es el **canonizador**: todo lo demás hereda su sesgo.

| Líneas | Función | Qué asume | Impacto con una 3.ª moneda |
|---|---|---|---|
| `130-137` | `paymentCurrency` | `raw == 'USD' ? 'USD' : 'CUP'` | Una fila `moneda='EUR'` se **lee como CUP**. Es el punto de contaminación raíz. |
| `144-153` | `paymentAmount` | Prob. de claves `monto/total/monto_pago/monto_total/monto_entrega` | Ambigüedad de fuente (no de moneda), pero multiplica los casos al normalizar. |
| `155-174` | `paymentCupEquivalent` | Si no es USD → **devuelve el monto nativo** (`:160`); solo lee `tasa_usd` (`:162`) | EUR → devuelve EUR como si fueran CUP. Nunca mira `tasa_cambio` (la columna nueva). |
| `176-183` | `paymentTotalCup` | Suma de `paymentCupEquivalent` | Total consolidado corrupto con cualquier moneda ≠ USD. |
| `185-187` | `paymentTotalUsd` | Filtra `== 'USD'` | No hay análogo por código. Usado en `orders_screen:3901`. |
| `189-190` | `formatPaymentAmount` | Etiqueta con `paymentCurrency` | Imprime «5,00 CUP» para 5 EUR (ticket web, `web_printer_service_web:440`). |
| `192-197` | `paymentDisplayCurrency` | Todo USD → `'USD'`, si no → `'CUP'` | Venta 100 % EUR se rotula CUP. |
| `199-210` | `paymentUsdRate` | Solo `tasa_usd` | Sin tasa genérica; con EUR devuelve null → los llamadores caen a `fallbackRate` (USD). |
| `212-226` | `formatCupAmountForPayments` | Dos ramas | Rótulo erróneo con EUR. |
| `229-238` | `cupToTicketAmount` | Divide por tasa USD | Ídem. |
| `240-254` | `formatTicketMoney` | `isUsd ? 'USD' : '\$... CUP'` | **Ticket impreso con EUR como CUP** (3 impresoras, ver §2.5). |
| `257-277` | `normalizePaymentMap` | Alias `currency→moneda` **sin validar** el código (`:261-263`); no normaliza `tasa_cambio` | Un `currency:'eu'` o `'EUR '` pasa tal cual y luego `paymentCurrency` lo colapsa. |

> `toMoneyString` (`:343-346`) es agnóstico de moneda (solo formatea) — **no** requiere cambio. Correcto que el plan no lo liste.

### 2.2 `checkout_screen.dart` — además del toggle

| Líneas | Punto | Por qué importa |
|---|---|---|
| `74-77` | `_usdRate`, `_mostrarSelectorMoneda`, `_paymentCurrencyByMethodId` | Estado global **de una sola tasa**; el selector necesita N tasas (o resolver por par al vuelo). |
| `419-434` | `_displayTotalsInUsd` | Exige que **todos** los métodos estén en USD para mostrar el total en USD. Con 3 monedas el total siempre se rotula CUP (`:440`). |
| `436-442` | `_formatCheckoutAmount` | Binario USD/CUP. |
| `459-483` | `_currencyPaymentLines` | **Un solo `moneda`/`tasa_usd` por `id_medio_pago`** (clave del mapa en `:467`). Ver limitación estructural abajo. |
| `784-841` | Filas del desglose | `:791-798` default `'CUP'` y división por `_usdRate`; `:831` rótulo `$currency`. |
| `823-827` | **Gate del toggle** | El toggle **solo se pinta si `_usdRate > 0 && _mostrarSelectorMoneda`**. Con EUR y sin tasa USD, no hay selector; y el flag booleano de tienda sigue gobernando. §6.3 no menciona este gate (el plan lo da por sustituido por `app_dat_tienda_moneda`, pero ese dato **no se lee en ninguna parte**, ver §2.9). |
| `1378-1391` | `_buildFinalTotalSection` | «Equivalente USD (1 USD = …)» hardcodeado. |
| `1889-1895` | Validación previa al cobro | Solo valida `USD` sin tasa; una moneda nueva sin tasa **no se bloquea** en cliente (el servidor sí debería). |
| `1993-2029` | Bloque offline | `:2020` moneda, `:2021` `tasa_usd`, `:2026-2028` conversión. Escribe `es_digital`/`es_efectivo` (bien) pero **no** `monto_cup_equivalente` (se calcula al sincronizar, `auto_sync:3728`). |
| `2323` | `pagos: _currencyPaymentLines` | Es el único origen de `order.pagos` para el flujo online. |

**Limitación estructural (no está en el plan y condiciona el diseño):** la moneda se elige **por método de pago**
(`Map<int,String>`), no por línea. Dos productos con el mismo `id_medio_pago` comparten moneda, y **no se puede
cobrar el mismo método en dos monedas** (p. ej. efectivo 1.000 CUP + 10 USD). El «truco» actual es que existen dos
métodos de efectivo (`id 1` y `999`, ver `price_utils.dart:315-324`), lo que es frágil. Si la Fase 3 quiere
multimoneda real en efectivo, hay que cambiar la clave a `(id_medio_pago, moneda)` **y** tocar los 4 consumidores
(`_currencyPaymentLines`, bloque offline, `order_service:1601-1625`, `auto_sync:3698-3741`).

### 2.3 `order_service.dart` — pagos fuera de `_registerPaymentsInSupabase`

| Líneas | Punto | Hallazgo |
|---|---|---|
| `1627-1662` + `1687-1697` | Respaldo cuando `order.pagos` viene vacío | Agrupa por `item.subtotal` (precio de catálogo **en CUP**) y registra `'moneda': ... ?? 'CUP'`, `tasa_usd: null`. Es el camino que usa **preorden** (ver §2.8). Cualquier venta que llegue sin `pagos` se registra en CUP. |
| `447-468` | Descuento manual aplicado a venta ya creada | Hace `UPDATE app_dat_pago_venta SET monto = precioFinal` sobre **el pago de mayor `monto`, sin mirar su `moneda`** (`:464-467`). Si el pago mayor es USD 10 y el `precioFinal` es 850 CUP, el pago queda «850 USD». Tampoco actualiza `monto_cup_equivalente` ni `tasa_cambio`. |
| `578-712` | `moveSalePaymentAmount` (mover monto entre métodos, **online**) | `UPDATE monto` en origen (`:674-677`) y destino (`:682-685`), `DELETE` del origen (`:669-672`) e **`INSERT` directo** (`:688-696`) sin `moneda`, sin `tasa_usd`, sin `monto_cup_equivalente`. La fila nueva toma el `DEFAULT 'CUP'` (`venta_usd.sql:2`) y deja `monto_cup_equivalente` NULL. **Rompe R11 otra vez y hace imposible mover montos en moneda ≠ CUP.** |
| `714-812` | `moveSalePaymentAmount` (**offline**) | La línea nueva (`:785-791`) se crea **sin `moneda` ni `tasa_usd`**. Si la venta pendiente era USD, al sincronizar esa línea se normaliza a CUP (`auto_sync:3717`) con el monto nativo USD ⇒ fila corrupta y `es_pagada` mal. |
| `1200-1247` | `getSalePayments` → `get_sale_payments2` | Es la **lectura** de pagos que alimenta tickets/cierre/orders. La RPC devuelve `moneda`, `tasa_usd`, `monto_cup_equivalente` **pero no `tasa_cambio`** (`venta_usd.sql:377-393`): el cliente no puede calcular el equivalente genérico desde la BD. La Fase 3 debe **extender el `RETURNS TABLE`** (aditivo) en el mismo deploy; §6.3 no lo menciona. |
| `1343-1367` | Productos de la venta | El precio de catálogo viaja **siempre en CUP** (`displayPrice`). Es correcto y hay que mantenerlo: `importe_total` sigue en CUP y por eso el equivalente del pago debe cuadrar por redondeo (ver riesgo R2). |

**Inventario completo de accesos directos del cliente a `app_dat_pago_venta`** (grep `.from('app_dat_pago_venta')`):
`order_service:449` (select), `:465` (**update monto**), `:629` (select), `:670` (**delete**), `:675` (**update monto**),
`:683` (**update monto**), `:688` (**INSERT**), `:1815` (select); `auto_sync:3842` (select), `:4406` (select).
**Ninguno** de los updates/insert escribe `moneda`, `tasa_usd`, `tasa_cambio` ni `monto_cup_equivalente`.

### 2.4 `auto_sync_service.dart` — otros puntos (además de los 3 que cita el plan)

| Líneas | Punto | Hallazgo |
|---|---|---|
| `3411-3462` | `_repairMissingSalePayments` | **Segunda** reparación de pagos (la que cita el plan es `:4313-4437`). Repara ventas ya `synced` sin pagos; usa `_pagosParaSincronizar` + `_registerPaymentBreakdownFromOfflineData`. Mismo cambio, otra entrada. |
| `1395-1399` | Apertura offline: elige `fn_apertura_turno_offline` vs `..._usd` por `efectivoInicialUsd == null` | **No está en §6.3** (la fila 12 solo cita `turno_service`, que es el camino online). |
| `2249-2273` | Cierre offline: elige `fn_cerrar_turno_offline` vs `..._usd` por `efectivoFinalUsd == null` | Ídem. |
| `1357-1360`, `2153-2155` | Payloads de apertura/cierre | Solo `efectivo_inicial` (CUP) + `efectivo_inicial_usd`/`efectivo_real_usd`. Una 3.ª moneda **no tiene dónde viajar**. |
| `3744-3758` / `3760-3771` | Fallback de `desglose_pagos` a `items` | Si no hay desglose, agrupa por `id_medio_pago` con el `subtotal` del ítem ⇒ CUP implícito, `tasa_usd: null`. |
| `3968-3996` | Idempotencia de la venta + validación | `usdSinTasa` solo mira USD (`:3982-3985`). Debe pasar a «toda moneda ≠ CUP/NULL requiere tasa». |
| `4015-4058` | Cadena de RPC de venta offline | `usedAtomicPagos` (`:4015`, `:4058`) se asigna y **nunca se lee**; los pagos se vuelven a verificar/registrar aparte en `:4146-4165`. No es un fallo, pero conviene saberlo antes de tocar la cadena. |
| `4150-4165` | Registro/verificación de pagos tras la venta | Aquí se decide si la orden se marca `pagos_registrados`; cualquier cambio de normalización afecta a esta guarda. |

### 2.5 Servicios de impresión — **no aparecen en §6.3** y formatean la moneda del pago

Los tres construyen un resumen «FORMA DE PAGO» que **decide la moneda con `endsWith('(USD)')`**:

| Archivo:líneas | Código | Efecto con EUR |
|---|---|---|
| `bluetooth_printer_service.dart:1333-1384` | `key = '$method ($currency)'` (`:1339`), `isUsd = entry.key.endsWith('(USD)')` (`:1366`), salida `USD`/`CUP` (`:1374-1378`) | Un pago EUR se imprime **«5 CUP»**. |
| `wifi_printer_service.dart:1042-1092` | Idéntico (`:1048`, `:1075`, `:1083-1087`) | Ídem. |
| `web_printer_service_web.dart:436-441` | `formatPaymentAmount(payment)` → `paymentCurrency` | Ídem (vía `price_utils:136`). |

Además, el ticket entero es **todo-o-nada** en USD: `formatTicketMoney(..., fallbackRate: usdRate)` en
`bluetooth:1224-1229`, `wifi:932-940`, `web:493-495`, con la tasa obtenida por `_getUsdRateForPrint()`
(`bluetooth:974-985`, `wifi:673-681`, `web:42-49`) gobernada por la preferencia booleana `print_usd_enabled`
(`user_preferences_service:1017,1080`; UI en `settings_screen:57,660-665,1619-1634`). Con una 3.ª moneda hay que
decidir explícitamente si el ticket se imprime en nativo, en base o mixto — **hoy no hay decisión posible**.

### 2.6 Caja / arqueo / cuadre offline

| Archivo:líneas | Hallazgo |
|---|---|
| `user_preferences_service.dart:2739-2860` (`buildOfflineTurnoCuadreFromLocalData`) | **No está en §6.3.** Reconstruye el cuadre del turno offline sumando `paymentCupEquivalent(payment)` (`:2805`, sin `fallbackRate`) y clasificando efectivo/digital con `es_efectivo`/`es_digital` (`:2806-2812`). Usa solo `efectivo_inicial` (`:2752`): **`efectivo_inicial_usd` no se lee en ningún punto de este servicio** (grep `efectivo_inicial_usd` en `user_preferences_service.dart` → 0 coincidencias). Es decir, el cuadre offline **hoy ya ignora el efectivo inicial en USD**. |
| `cierre_screen.dart:2028-2065` | Campo único «Efectivo real USD» + diferencia USD (`_buildDiferenciaUsd :2377-2415`). |
| `cierre_screen.dart:3259-3283` / `:3349-3380` | Snapshots online/offline con `efectivo_final` (un solo número, CUP) y `efectivo_real_usd`. |
| `cierre_screen.dart:558-566`, `:639-648`, `:1574-1582` | `_efectivoInicialUsd`, `_totalEfectivoUsd`, `_efectivoUsdEsperado`: solo USD. |
| `cash_count_dialog.dart:236`, `:363-380` | Muestra una única «Tasa 1 USD = …» y dos totales (CUP / USD-en-CUP). |
| `egreso_screen.dart:164-201`, `:767`, `:889-922` | Los egresos **no tienen moneda** (`monto_entrega` pelado) aunque la cuenta de fondo de caja sí trae `id_moneda` (`:179`, leído y **no usado**). Un egreso en USD se resta del cubo CUP. Es Fase 4, pero la Fase 3 puede introducir cobros en EUR que luego no cuadran. |

### 2.7 `venta_total_screen.dart` (además de la fila 11)

`105-198`: clasifica `if (moneda == 'USD') ... else totalCup += montoNativo` (`:140-163`) y añade el remanente a
«Efectivo (CUP)» (`:168-184`). `_printReport` (`:2030-2065`) imprime `Total Ventas USD`, `Egresado USD`,
`Efectivo Real USD`, `Transferencia USD` y `suffix = medio.key.contains('(USD)') ? ' USD' : ' CUP'` (`:2038`) —
mismo sesgo que las impresoras.

### 2.8 Preorden — segundo escritor de `pending_orders` (no está en §6.3)

`preorder_screen.dart:2444-2515` (`_submitOrderOfflineDirect`) guarda `desglose_pagos` **sin `moneda` y sin
`tasa_usd`** (`:2460-2470`), a diferencia del checkout (`:2015-2024`). Y el camino online
(`:2341-2391`) llama a `finalizeOrderWithDetails` con una orden **sin `pagos`** (`:2370-2375`), lo que activa el
respaldo CUP de `order_service:1627-1662`. Hoy da igual (la preorden es CUP); con multimoneda, la preorden queda
fuera del modelo y es el candidato natural a producir filas mixtas.

### 2.9 Catálogo de monedas por tienda: **el TPV no lo lee**

`grep 'app_dat_tienda_moneda|tienda_moneda'` en `ventiq_app/lib` → **0 coincidencias**. La única fuente de monedas
del cliente sigue siendo `app_dat_denominaciones_moneda` (global, sin `id_tienda`) en `login_screen.dart:725-748` →
`saveMonedasDenominacion` → `getMonedasDisponibles` (`user_preferences_service:4790-4808`). El toggle del checkout se
gobierna por `mostrar_selector_moneda` (`checkout_screen:205,223-224`; `store_config_service:339-349`).
**Consecuencia**: la fila 4 del plan («las monedas de `app_dat_tienda_moneda`») exige una pieza que hoy no existe
(servicio + cache + módulo de sincronización offline). §6.3 solo lo insinúa en la fila 2 (`getRatesForStore`).

### 2.10 SMS bancario

- Parser: `bank_sms_parser.dart:143-150` → `moneda` por regex `[A-Z]{3}` con **default `'CUP'`**.
- Modelo: `models/bank_sms_payment.dart:78` (`this.moneda = 'CUP'`) y `:122` (`?? 'CUP'`).
- El matching es **por importe**, no por moneda: `bank_sms_service.dart:450-…` (`findMatchingPayment`) y
  `transfer_sms_confirmation_banner.dart:105-163`; el importe esperado es **CUP** (`checkout_screen:109-117`,
  `transferExpectedAmount`). Un SMS «Monto Pagado: 1.00 USD» frente a una venta de 850 CUP no casa; y una venta en
  EUR/USD compara nativo contra CUP. `fn_confirmar_pago_sms` recibe el JSON con `moneda` (`:136-143`) — el contrato
  server-side existe, el cliente no lo usa para decidir nada.
- Banner: `transfer_sms_confirmation_banner.dart:333` muestra `… ${confirmed.moneda}` (correcto, informativo).

### 2.11 CxC / liquidaciones / `id_liquidacion`

**NO ENCONTRADO** en el TPV: `grep -i 'liquidacion'` en `ventiq_app/lib` → **0 coincidencias**.
El TPV **no crea CxC** hoy: el sentinel 998 se rechaza al cobrar (`checkout_screen:1897-1908`) y no genera fila en
`app_dat_pago_venta` (`order_service:1633-1638`, `auto_sync:3708`). El único rastro de CxC es la lectura de
`es_pagada = false` (`order_service:1513-1546`, `auto_sync:4125-4144`) y `id_cliente_cxc`. Por tanto la migración
`_v4` que borra «pagos con `id_liquidacion IS NULL`» **no tiene contraparte en el cliente**: no hay nada que enviar,
pero también implica que el cliente **no puede distinguir** pagos liquidados al reparar (ver C4 en §5).

### 2.12 Código legado que también escribe pagos — **inerte hoy**, pero es una mina

`settings_screen.dart` contiene **dos** implementaciones propias de sincronización de pagos:
`:5208-5275` y `:5844-5890` (esta última, la del flujo `desglose_pagos` de `:5760-5769`). Ambas reconstruyen el
array enviando **solo** `id_medio_pago`, `monto` y `referencia_pago`: pierden `moneda`/`tasa_usd` y llaman a
`fn_registrar_pago_venta_v2` → coacción a CUP (ver §3). **Están en código muerto**: los diálogos que las usan
(`_SyncDialog :3993`, `_ManualSyncDialog :5507`) **no se instancian en ninguna parte** (grep `_SyncDialog(` /
`_ManualSyncDialog(` → solo constructores), y la sincronización manual viva usa
`AutoSyncService().syncModules` (`settings_screen:3425-3430`). **No es riesgo de producción**, pero (a) no debe
contarse como cubierto por la Fase 3, y (b) si alguien «rescata» ese diálogo, corrompe pagos de moneda ≠ CUP.

---

## 3. Modelo offline: `pending_orders` (SharedPreferences)

**Dónde**: `user_preferences_service.dart:88` (`_pendingOrdersKey = 'pending_orders'`); escritura
`:1507-1534` (`savePendingOrder`), parcheo `:1536-1556` (`updatePendingOrderPayments`) y `:1560-1580`
(`patchPendingOrder`); lectura `:1582-1591`. **No hay SQLite para pagos** (confirmado: SQLite solo catálogo/admin).

### 3.1 Esquema real de una orden pendiente (checkout)

Construida en `checkout_screen.dart:2044-2120`:

```
id, client_uuid, id_tienda, id_tpv, id_vendedor, id_usuario,
fecha_creacion, subtotal, total_descuentos, total, estado='pendiente_sincronizacion',
estado_final='completada', is_pending_sync=true, created_offline_at,
[local_turno_id], buyer_name, buyer_phone, extra_contacts, promo_code, promo_discount,
id_mesa, mesa_numero,
items[]: { id_producto, denominacion, cantidad, precio_unitario, subtotal,
           id_medio_pago, metodo_pago, inventory_metadata,
           id_presentacion, presentacion_nombre, presentacion_factor },
desglose_pagos[],
[pago_sms_json], [foto_operacion_local_path | foto_operacion_base64, foto_operacion_mime]
```

### 3.2 Claves exactas de cada línea de `desglose_pagos` HOY

**Checkout** (`checkout_screen.dart:2015-2024`) — 7 claves:

| Clave | Valor |
|---|---|
| `id_medio_pago` | int |
| `denominacion` | String |
| `monto` | **monto nativo** (CUP si CUP; `cupTotal/_usdRate` si USD) |
| `moneda` | `'CUP'` \| `'USD'` (siempre presente, default CUP) |
| `tasa_usd` | `_usdRate` si USD, `null` si CUP |
| `es_digital` | bool (del catálogo de métodos) |
| `es_efectivo` | bool |

**No** lleva: `monto_cup_equivalente` (se calcula al sincronizar, `auto_sync:3728`), `tasa_cambio`, `tipo_pago`,
`importe_sin_descuento`.

**Preorden** (`preorder_screen.dart:2460-2470`) — solo 5 claves: `id_medio_pago`, `denominacion`, `monto`,
`es_digital`, `es_efectivo`. **Sin `moneda` ni `tasa_usd`.**

**Edición offline del desglose** (`order_service.dart:785-791`) — solo 5 claves: `id_medio_pago`, `denominacion`,
`monto`, `es_digital`, `es_efectivo`. **Sin `moneda` ni `tasa_usd`.**

### 3.3 ¿Qué pasaría con las órdenes pendientes antiguas si cambia la normalización?

El normalizador que propone el plan (§6.4, línea 729: `tasa_cambio ?? tasa_usd`, `moneda ?? 'CUP'`) **funciona**
para lo que escribe el checkout, porque `moneda` está siempre presente desde el commit `5b345c11`
(`git blame` de `checkout_screen.dart:2011-2028`): ese bloque es de 2026-09-19; antes (`a8c92113d`, 2025-10-04) el
desglose **no tenía** `moneda`/`tasa_usd`. Órdenes creadas con versiones anteriores a ese commit siguen siendo
semánticamente CUP (el toggle no existía), así que el default CUP es correcto.

**Pero hay tres casos que el plan da por seguros y no lo son:**

1. **Línea añadida al mover monto offline** (`order_service:785-791`): sin `moneda` ⇒ una venta USD editada offline
   se sincroniza con esa línea como CUP y el resto USD. Resultado: pagos mezclados y `es_pagada` probablemente falso.
2. **Preorden** (`preorder_screen:2460-2470`): sin `moneda`/`tasa_usd`. Hoy es CUP legítimo; si la Fase 3 habilita
   cobro en EUR en preorden, se perderá la moneda.
3. **`pago_sms_json`** (`checkout_screen:2140-2143`): lleva su propio `moneda` (default CUP,
   `bank_sms_payment.dart:78,122`), independiente del `desglose_pagos`. Dos fuentes de moneda en el mismo registro.

Además, el sincronizador **recalcula** `monto_cup_equivalente` en cliente (`auto_sync:3728-3731`) sin tocar el
`desglose_pagos` persistido: el equivalente nunca se guarda offline, siempre se deriva al vuelo con la tasa que haya
*en ese momento* (si `tasa_usd` falta, usa `monto`). Es decir: **la política de tasa del offline es «la que traiga
la orden, o ninguna»**, y el plan no define qué pasa si la orden no trae tasa para una moneda nueva.

---

## 4. Riesgos concretos de la Fase 3 (ordenados por gravedad)

### R1 — **Crítico**: `fn_registrar_pago_venta_v2` (y la viva) coaccionan toda moneda ≠ USD a CUP, y la app la prefiere
Evidencia: `ventiq_app/sql/venta_usd.sql:63` (`CASE WHEN UPPER(...)='USD' THEN 'USD' ELSE 'CUP' END`), `:80`
(`v_monto_cup := CASE WHEN USD THEN monto*tasa ELSE monto END`), `:94-96`; idéntico en
`ventiq_app/sql/fn_registrar_pago_venta_idempotente.sql:69`, `:86`, `:100-102`. La app llama `_v2` primero
(`order_service:1730-1741`; `auto_sync:4368-4373`) y **solo** cae a la anterior si el error es «RPC no existe»
(`_isRpcUnavailable`, `order_service:1793-1800`). Escenario real: se aplica la migración, `fn_registrar_pago_venta_v4`
no queda desplegada (o el nombre/migración se aplica a medias), la app nueva cobra EUR → fallback a `_v2` → fila
`moneda='CUP'`, `monto_cup_equivalente = monto (EUR leído como CUP)`, `es_pagada` probablemente **false**. Es
**corrupción silenciosa**, no un error visible. Mitigación que el plan no pide: **el cliente no debe caer a `_v2`/v1
si la moneda no es CUP/USD** (guard explícito) y/o `_v2` debe dejar de aceptar monedas desconocidas.

### R2 — **Alto**: redondeo del equivalente vs `es_pagada`
El cliente divide por la tasa con doble precisión y **sin redondear** (`checkout_screen:480`, `:2028`;
`auto_sync:3728`). El servidor antiguo multiplica sin redondear y compara `v_total_pagos_cup >= importe_total`
(`venta_usd.sql:80,100-104`; `idempotente:86,106-110`). Con la 3.ª moneda, `(total/r)*r` puede quedar por debajo del
total por épsilon → la venta **no se marca pagada** aunque el dinero esté cobrado, y `_pagosCoincidenConEsperado`
también compara montos con tolerancia `1e-4` (`order_service:1849-1853`). El plan corrige esto en las RPC nuevas
(§5.1 usa `round(monto*tasa,2)`), pero **las viejas siguen vivas como fallback**.

### R3 — **Alto**: offline queda contablemente peor que online, incluso antes de la Fase 4
Si se permite cobrar EUR offline: (a) el cuadre del turno offline (`user_preferences_service:2739-2860`) suma
`paymentCupEquivalent` que devuelve el nativo para no-USD (`price_utils:160`) y **nunca lee `efectivo_inicial_usd`**;
(b) la apertura/cierre offline solo admiten CUP+USD (`apertura_screen:2595`, `cierre_screen:3273,3380`,
`auto_sync:1357-1360,2153-2155`); (c) las líneas sin moneda (§3.3) se sincronizan como CUP. El plan trata el offline
en una sola frase (§8 Fase 3 punto 4) y §6.4 lo despacha como «compatible».

### R4 — **Alto**: el ticket imprime un pago EUR como CUP o inventa la etiqueta
§2.5. Además de la etiqueta, el ticket completo decide «USD o CUP» por `paymentDisplayCurrency`, con lo que una
venta mixta EUR+CUP siempre se imprime en CUP y el `TOTAL:` puede no coincidir con la suma de las líneas mostradas.

### R5 — **Medio-alto**: mover montos y aplicar descuentos corrompen pagos de moneda ≠ CUP
`order_service:447-468` (descuento sobre el pago de mayor monto, sin mirar moneda, escribiendo un precio CUP como
`monto` nativo) y `:578-712`/`:714-812` (mover montos: INSERT sin `moneda` ⇒ default CUP; sin
`monto_cup_equivalente`). Ambos son **puntos de escritura de producción** y **no** están en §6.3. Con USD ya son
peligrosos; con EUR lo son más porque no hay `CHECK` que frene nada.

### R6 — **Medio**: `monto_cup_equivalente` reabierto por escrituras directas del cliente
`order_service:688-696` inserta sin equivalente (NULL). Si R11 («666 NULL, 97 filas con el total de la operación»)
se cerró a base de recalcular, estas dos rutas vuelven a abrir el agujero de forma continua. §4.4.1 solo menciona
`fn_registrar_pago_venta_offline`.

### R7 — **Medio**: no se puede cobrar el mismo método en dos monedas
§2.2. Decisión de producto que el plan no toma: o se rediseña la clave a `(método, moneda)` (afecta a 4 servicios) o
se acepta que el efectivo solo puede ir en una divisa por venta y se documenta.

### R8 — **Medio**: la app no tiene de dónde saber qué monedas acepta la tienda
§2.9: `app_dat_tienda_moneda` no se lee. Además, según el propio plan (§8 Fase 2), en **producción** esa tabla
todavía no está aplicada; el TPV debe degradar con seguridad si la consulta falla (fallback CUP/USD), y §6.3 no dice
cómo.

### R9 — **Bajo-medio**: colisión de nomenclatura «Fase 3»
`auto_sync_service.dart:4017-4021` habla de «Fase 3 (decisión 1B)» y de `fn_registrar_venta_offline_v4`, pero eso
pertenece al proyecto de **presentaciones/inventario** (`funcionalidad_cocina/34_venta_v3_presentaciones.sql:2`,
`:30`, `:145`), no al multimoneda. Quien implemente «v4» de pagos puede confundirse: son funciones distintas
(`fn_registrar_venta_offline_v4` vs `fn_registrar_pago_venta_v4`), pero los comentarios invitan al error.

### R10 — **Bajo**: deuda de lectura
`get_sale_payments2` no devuelve `tasa_cambio` (`venta_usd.sql:375-406`) y `PriceUtils` solo lee `tasa_usd`: aunque
la escritura quede perfecta, la lectura del histórico EUR no podrá calcular el equivalente sin extender el RPC.

---

## 5. Contradicciones internas (dos partes que esperan cosas distintas del mismo dato)

1. **¿Quién calcula `monto_cup_equivalente`?** El cliente lo calcula y lo **envía** (`auto_sync:3728-3731`,
   `:4338`), pero el servidor lo **ignora y recalcula** desde `moneda`+`tasa_usd`
   (`venta_usd.sql:80,96`; `idempotente:86,102`). Dos fuentes de verdad para la misma columna; con `tasa_cambio`
   genérica el cliente seguirá enviando un valor que no se usa.
2. **El cierre y el informe no calculan igual el equivalente.** `cierre_screen.dart:383` llama
   `PriceUtils.paymentCupEquivalent(pago)` **sin** `fallbackRate`; `venta_total_screen.dart:125-128` lo llama **con**
   `fallbackRate: _usdRate`. Una fila USD sin `tasa_usd`/`monto_cup_equivalente` (posible: INSERT directo de
   `order_service:688`) se cuenta **nativa** en el cierre y **convertida** en el informe. Mismo dato, dos números.
3. **«Moneda» significa cosas distintas por capa.** `get_sale_payments2` devuelve el `moneda` crudo de la tabla
   (`venta_usd.sql:402`); `PriceUtils.paymentCurrency` lo reescribe a CUP/USD (`:136`); `_pagosCoincidenConEsperado`
   agrupa por la versión colapsada (`order_service:1828-1843`, `auto_sync:3853-3866`); y las RPC viejas lo vuelven a
   colapsar (`venta_usd.sql:63`). Si en la BD llega a haber `'EUR'`, cuatro capas lo interpretarán de tres maneras.
4. **`es_pagada`**: el cliente lo fuerza a `false` para CxC (`order_service:1533-1539`, `auto_sync:4125-4132`) y
   después la RPC de pagos lo pone a `true` si la suma alcanza (`venta_usd.sql:100-104`). Con equivalencias mal
   calculadas, la venta CxC puede «auto-pagarse» o una venta cobrada quedar impaga.
5. **Descuento manual vs desglose**: el descuento reescribe `monto` del pago mayor (`order_service:466`) mientras
   `price_utils` sigue mostrando `importe_sin_descuento` — dos visiones del importe cobrado que el multimoneda agrava.
6. **Plan vs SQL del repo (§4.4.1).** El plan afirma que `fn_registrar_pago_venta_offline` **no escribe**
   `monto_cup_equivalente`; en el repo esa función delega en `fn_registrar_pago_venta`
   (`ventiq_app/sql_offline/06_idempotencia_extra.sql:125-128`), que **sí** lo escribe
   (`venta_usd.sql:86,96`). No es verificable contra la BD real desde esta auditoría (solo lectura de repo):
   **el lead debería confirmar el cuerpo real de esa función en `newa`/producción** antes de dar R11 por cerrado.
7. **Efectivo esperado vs conteo.** `orders_screen:3508-3539` suma `monto` nativo de todos los pagos en efectivo,
   sin convertir, y lo pasa como `expectedAmount` a `BillCountDialog`, cuyo `_targetAmount` es CUP
   (`bill_count_dialog:193-216`, `:639`). Con efectivo en dos monedas el «esperado» no significa nada.

---

## 6. NO ENCONTRADO / no verificable

| Qué | Búsqueda realizada | Resultado |
|---|---|---|
| Modelo `Currency`/`Money` | `glob ventiq_app/lib/models/*.dart` (18 archivos) | **NO EXISTE** (correcto: el plan lo marca «nuevo»). |
| `id_liquidacion` / CxC en el TPV | `grep -i 'liquidacion'` en `ventiq_app/lib` | **NO ENCONTRADO** (0 coincidencias). El TPV no crea CxC (§2.11). |
| Lectura de `app_dat_tienda_moneda` | `grep 'app_dat_tienda_moneda|tienda_moneda'` en `ventiq_app/lib` | **NO ENCONTRADO** (0 coincidencias) → §2.9. |
| DDL de `fn_registrar_pago_venta_v3/v4` propuestas | `grep 'fn_registrar_pago_venta_v3|_v4'` en `*.sql` | **NO EXISTE** en el repo; solo el pseudocódigo de `plan.md` §5.1 ⇒ el contrato final no es auditable todavía. |
| `efectivo_inicial_usd` en el cuadre offline | `grep 'efectivo_inicial_usd'` en `user_preferences_service.dart` | **NO ENCONTRADO** (0) ⇒ el cuadre offline ignora el USD (§2.6). |
| Cuerpo real de `fn_registrar_venta_offline` / `fn_resumen_diario_cierre_v2` en la BD | — | **NO VERIFICADO** (fuera de alcance: solo lectura de repo; el lead tiene la verificación de esquema). |
| Escrituras a `app_dat_pago_venta` desde otros archivos | `grep "from('app_dat_pago_venta')"` en `ventiq_app/lib` | 10 accesos, 5 escrituras directas, todas en `order_service` (§2.3). **No hay más.** |

---

## 7. Recomendaciones mínimas para no romper el cobro (derivadas de lo anterior)

1. **Añadir a §6.3 las filas que faltan**: impresoras (3), `user_preferences_service` (cuadre offline),
   `preorder_screen`, `order_service` (descuento + mover montos + fallback sin `pagos`), `turno_service` **offline**
   (en realidad `auto_sync:1395-1399`/`:2268-2272`), `get_sale_payments2` (RETURNS TABLE), y el servicio/cache de
   `app_dat_tienda_moneda`.
2. **Guard de moneda en el cliente antes de cualquier fallback RPC**: si `moneda ∉ {CUP, USD}`, no llamar a `_v2`
   ni a `fn_registrar_pago_venta`. Es la única forma de que R1 no dependa de que el deploy sea perfecto.
3. **Congelar la política de redondeo en un solo sitio**: `monto_base = round(monto_nativo * tasa, 2)` calculado en
   servidor (y replicado igual en `auto_sync:3728`), y comparar `es_pagada` con tolerancia, no con `>=` exacto.
4. **Cerrar R11 también en las escrituras directas del cliente** (§2.3): el UPDATE de descuento y el INSERT/UPDATE de
   mover montos deben recalcular `monto_cup_equivalente`/`tasa_cambio`, o dejar de tocar `monto` (mover a RPC).
5. **Decidir explícitamente** (y escribir en el plan): (a) ¿se permite el mismo método en dos monedas?; (b) ¿se
   permite cobrar en moneda ≠ CUP/USD **offline** en la Fase 3 o se bloquea hasta la Fase 4?; (c) ¿en qué moneda se
   imprime el ticket con cobro mixto?
6. **Purga/migración de `pending_orders`**: antes de cambiar el normalizador, o se drena la cola (forzar sync con la
   app vieja) o el nuevo normalizador debe tratar «sin moneda» como CUP **y** rechazar/marcar las órdenes con líneas
   sin moneda si la venta tiene alguna línea en otra divisa (hoy imposible en checkout, posible por §3.3-1/2).