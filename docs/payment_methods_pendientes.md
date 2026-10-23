# Refactor de medios de pago — Estado y puntos pendientes

## 🔍 Validación en vivo (Supabase MCP, proyecto VentiQ `vsieeihstajlrdvpuooh`)

Verificado directamente contra la base remota:

- **`app_nom_medio_pago`** solo tiene 2 métodos activos: `1` "Pago
  oferta(Efectivo)" y `4` "Pago regular(Transferencia)". Los IDs `998` y `999`
  **no existen** en el catálogo — son pseudo-métodos solo del cliente.
- **`fn_registrar_pago_venta`** en vivo es la versión con moneda
  (`moneda`, `tasa_usd`, `monto_cup_equivalente`, `tipo_pago`), igual a
  `venta_usd.sql`. Hace inserts puros: **no es idempotente**.
- **`fn_registrar_pago_venta_idempotente`** (el SQL nuevo de esta sesión)
  **todavía no está aplicado** — no existe en la base.
- **`fn_registrar_venta_offline` con `p_pagos` ya está desplegado** como
  sobrecarga de la función original (no como `..._con_pagos`). Es atómico e
  idempotente por `client_uuid` vía `app_dat_operacion_offline_idempotencia`.
- ⚠️ **Hallazgo nuevo:** dentro de ese RPC offline, la reparación de pagos usa
  la misma guarda binaria que se corrigió en la app:
  `IF NOT EXISTS (SELECT 1 FROM app_dat_pago_venta WHERE id_operacion_venta = v_op LIMIT 1)`.
  Si una sync anterior insertó pagos parciales y falló, los reintentos los
  consideran completos. El fix de `_pagosCoincidenConEsperado` debe aplicarse
  también del lado servidor (ver punto 6).
- **No hay triggers** sobre `app_dat_pago_venta` — los `es_pagada`/recálculos
  los hace solo el RPC.
- **Pagos USD reales existen:** 121,877 filas CUP y 7 USD. Los 7 USD usan
  `id_medio_pago = 1` con `tasa_usd = 550` — o sea, la moneda ya funciona como
  propiedad de la **línea de pago**, no del método. El hueco está solo en la
  app (`_paymentCurrencyByMethodId` nunca se llena).
- **CxC con volumen mínimo:** 3 clientes CxC, 5 liquidaciones, 1 venta
  pendiente, 0 clientes bloqueados. Una migración sería barata en datos, pero
  las tablas siguen teniendo sentido funcional (ver punto 4).

## ✅ Lo que ya se atacó en esta sesión

### 1. Corrección de la guarda idempotente `_pagosYaRegistrados`

**Problema:** la función solo consultaba "¿hay algún pago?". Si una llamada
anterior insertó pagos parcialmente, las llamadas siguientes consideraban la
operación pagada y no la reparaban.

**Cambios:**

- `lib/services/order_service.dart`:
  - Se reemplazó `_pagosYaRegistrados` por `_pagosCoincidenConEsperado`.
  - Compara el desgloe esperado `(id_medio_pago, moneda, monto)` con el que
    existe en `app_dat_pago_venta`.
  - Solo devuelve `true` cuando el desglose coincide exactamente.

- `lib/sql/fn_registrar_pago_venta_idempotente.sql`:
  - Define **`fn_registrar_pago_venta_v2`** (función NUEVA; la original queda
    intacta para las apps desplegadas).
  - Antes de insertar, borra los pagos previos de la operación cuyo
    `id_liquidacion IS NULL` y reescribe el desglose → realmente idempotente.
  - Los pagos ligados a una liquidación de CxC no se tocan.

- `lib/sql/fn_registrar_venta_offline_v3.sql`:
  - Define **`fn_registrar_venta_offline_v3`** (función NUEVA; `v1`/`v2`
    quedan intactas).
  - Igual a `fn_registrar_venta_offline_v2` (ya desplegada en vivo) pero el
    bloque de pagos llama a `fn_registrar_pago_venta_v2` en lugar de la
    guarda binaria `NOT EXISTS` + `fn_registrar_pago_venta`.

- App (con fallback a la versión anterior si el RPC nuevo no existe):
  - `order_service.dart` → intenta `fn_registrar_pago_venta_v2`, cae a
    `fn_registrar_pago_venta`.
  - `auto_sync_service.dart` → intenta `fn_registrar_venta_offline_v3`, cae
    a `fn_registrar_venta_offline` (con y sin `p_pagos`) y luego
    `fn_registrar_venta`. En la reparación de pagos intenta
    `fn_registrar_pago_venta_v2` antes del original.
  - `settings_screen.dart` (sync manual) → mismo patrón v2 → original.

**Actualización 2026-10-14 (MCP):** `fn_registrar_pago_venta_v2` y
`fn_registrar_venta_offline_v3` **ya están desplegados** en main y newa.
En `auto_sync_service` se reemplazó `_operacionTienePagos` (guarda binaria)
por `_pagosCoincidenConEsperado` (compara desglose completo por
`id_medio_pago|moneda` + montos).

---

## ⏳ Puntos pendientes de decisión / implementación

### 1. Mover todos los métodos de pago al catálogo `app_nom_medio_pago`

**Pregunta original:** *¿Es lógico crear todos los métodos de pago en el sistema?*

**Respuesta:** sí, es lo lógico. Hoy hay métodos "fantasma" que solo existen en
el cliente:

- `id = 999` — "Pago Regular (Efectivo)"
- `id = 998` — "Pago Pendiente" (cuentas por cobrar)

**Ventajas de llevarlos a `app_nom_medio_pago`:**

- El servidor los distingue en reportes y consultas sin lógica especial.
- Se eliminan conversiones mágicas `999 -> 1` en varias pantallas y servicios.
- Se puede usar RLS y activación/desactivación por tienda si se necesita.

**Consideraciones:**

- "Pago Pendiente" no debe generar fila en `app_dat_pago_venta`. Se necesita
  algún mecanismo para identificarlo: una columna `genera_pago boolean` en
  `app_nom_medio_pago`, o un campo `es_pago_pendiente` reconocido por
  `fn_registrar_pago_venta`.
- "Pago Regular (Efectivo)" sí generaría pago normal; solo se diferencia porque
  no aplica descuento por efectivo. Eso se puede resolver dándole su propio
  `id` real y marcándolo como `es_efectivo = true`.

**Archivos que tocaría:**

- `lib/models/payment_method.dart`
- `lib/services/payment_method_service.dart`
- `lib/screens/preorder_screen.dart`
- `lib/screens/servicentro_cantidad_screen.dart`
- `lib/screens/orders_screen.dart`
- `lib/screens/checkout_screen.dart`
- `lib/services/order_service.dart`
- `lib/services/auto_sync_service.dart`
- `lib/utils/price_utils.dart`
- SQL: `fn_registrar_pago_venta` y posiblemente `app_nom_medio_pago`

**Estado:** pendiente de decisión de negocio + implementación.

---

### 2. Fuente única de verdad para los pagos

**Problema:** hoy hay tres fuentes de pagos:

1. `order.pagos` (desglose por método/moneda que genera el checkout).
2. `order.items[].paymentMethod` (método asignado a cada ítem).
3. `desglose_pagos` almacenado en las órdenes offline.

`_registerPaymentsInSupabase` prioriza `order.pagos`; si está vacío recae a (2).
`AutoSyncService._pagosParaSincronizar` prioriza `desglose_pagos`; si está vacío
recae a los ítems. Esto permite que el desglose real difiera del que se muestra.

**Propuesta:** la fuente canónica debe ser `order.items[].paymentMethod` + la
configuración de moneda por método. `order.pagos` y `desglose_pagos` deben ser
**derivados**, no fuentes. Antes de guardar o sincronizar se ejecuta un único
helper `buildPaymentBreakdownFromItems`.

**Excepción:** si se implementa un modo de pago "libre" donde el vendedor
reparte montos a mano entre métodos (sin ligarlos a ítems), ese desglose manual
sí debe guardarse como fuente. Hoy el modo fluido no está completamente
integrado, así que no hay un caso real.

**Archivos que tocaría:**

- `lib/services/order_service.dart` (`_registerPaymentsInSupabase`)
- `lib/services/auto_sync_service.dart` (`_pagosParaSincronizar`)
- `lib/screens/checkout_screen.dart` (`_currencyPaymentLines`, `_processOfflineOrder`)
- `lib/widgets/fluid_payment_methods_widget.dart` y `fluid_mode_screen.dart`

**Estado:** pendiente de implementación.

---

### 3. Configuración de moneda USD/CUP paralela

**Problema:** en `checkout_screen.dart` existe
`final Map<int, String> _paymentCurrencyByMethodId = {}` y **nunca se llenaba**.
Por eso todos los pagos terminaban en CUP; el soporte USD no se usaba aunque
el RPC `fn_registrar_pago_venta` ya lo soporta (en vivo hay 7 pagos USD).

**Decisión tomada:** la moneda la selecciona el cajero **por venta**, por
método de pago — no es atributo del método ni de la tienda. No hace falta
cambio de esquema (la moneda viaja en cada línea de `app_dat_pago_venta`).

**Implementado:**

- `checkout_screen.dart`:
  - `_paymentMethodInfoForName` — resuelve `id` (normalizado 999→1) y
    `esPagoPendiente` de cada método del desglose.
  - `_buildCurrencyToggle` — toggle compacto CUP/USD por método en el
    "Desglose de Pagos". Solo aparece si hay tasa USD (`_usdRate > 0`) y el
    método no es Pago Pendiente. Escribe `_paymentCurrencyByMethodId`.
  - El monto de la fila se muestra en la moneda elegida.
- `_currencyPaymentLines`, `_displayTotalsInUsd`, el desglose offline y
  `_pagosParaSincronizar` ya leían ese mapa — sin más cambios.

**Pendiente:** probar en app un cobro mixto (efectivo CUP + transferencia
USD) y verificar `app_dat_pago_venta`.

---

### 4. Eliminación de tablas específicas de Cuentas por Cobrar

**Pregunta original:** *¿Con todos los tipos de pago las cuentas por cobrar no
necesitarían las tablas específicas?*

**Respuesta:** no es tan simple. Hoy CxC usa:

- `app_dat_cliente_cxc` — clientes dedicados a CxC (creados en migración 11).
- `app_dat_liquidacion_cxc` — recibos que agrupan abonos.
- `app_dat_pago_venta.id_liquidacion` — vínculo del abono al recibo.
- `app_dat_operacion_venta.id_cliente_cxc` y `es_pagada = false`.

**Opciones:**

**A) Eliminar `app_dat_cliente_cxc` y volver a usar `app_dat_clientes`:**

- Originalmente la migración 10 hizo exactamente esto.
- La migración 11 creó `app_dat_cliente_cxc` porque `app_dat_clientes` se
  llenaba automáticamente con un registro por cada venta normal vía
  `fn_insertar_cliente_con_contactos`, haciendo imposible gestionar deudas.
- Para volver a `app_dat_clientes` habría que **dejar de crear clientes
  automáticamente en ventas normales** y solo crearlos cuando el vendedor
  explicitamente guarde un cliente o use CxC.
- Esto es un cambio grande: checkout, servicios, impresión, reportes.

**B) Eliminar `app_dat_liquidacion_cxc` y agrupar abonos por referencia:**

- Técnicamente posible: varios abonos podrían compartir `referencia_pago`.
- Se perdería el concepto de recibo (`monto_total`, `observaciones`, creador).
- Reports de cobranza se complicarían.

**C) Mantener las tablas actuales:**

- Es el camino más seguro.
- `app_dat_cliente_cxc` cumple bien su propósito: clientes de crédito limpios,
  por tienda, bloqueables.
- `app_dat_liquidacion_cxc` es útil para recibos.

**Recomendación:** no eliminar las tablas específicas. Si se quiere simplificar,
el esfuerzo debería ir por unificar la lógica de clientes (no duplicar
`app_dat_clientes` vs `app_dat_cliente_cxc`) o por integrar CxC como un
método de pago más con su propio `id` real.

**Archivos afectados si se decide eliminar:**

- `ventiq_admin_app/lib/services/cxc_service.dart`
- `ventiq_admin_app/lib/screens/cuentas_por_cobrar_screen.dart`
- `ventiq_admin_app/docs/migrations/10_cuentas_por_cobrar.sql`
- `ventiq_admin_app/docs/migrations/11_cuentas_por_cobrar_clientes_independientes.sql`
- `ventiq_app/lib/services/order_service.dart`
- `ventiq_app/lib/screens/checkout_screen.dart`
- `ventiq_app/lib/services/auto_sync_service.dart`
- `lib/models/cxc_cliente.dart`

**Estado (2026-10-14):** CxC **no se gestiona desde `ventiq_app`**. El método
998 no se inyecta ni se lista (inactivo / fuera del catálogo activo). El
checkout aborta si aún llega un ítem con sentinel 998. La cartera queda en
admin. Código legacy de lectura/sync de CxC puede quedar para órdenes viejas;
no crear nuevas desde el TPV.

---

### 5. Desglose offline (`es_digital` / `es_efectivo`) — decisión

**Qué son:** campos guardados en `desglose_pagos` al crear la venta offline
(junto a `id_medio_pago`, `monto`, `moneda`, etc.).

**Quién los usa:**

- **UI local** (cierre de turno, impresión, listado offline): leen la "foto"
  del método en el momento de la venta, sin consultar BD.
- **RPC de registro de pagos:** **no** los usa. El servidor clasifica el medio
  por `id_medio_pago` → `app_nom_medio_pago` y por `tipo_pago`.

**Decisión (2026-10-14):** dejarlos como están. Son informativos para offline;
no son fuente de verdad al sincronizar. No limpiar ni refactorizar por ahora.

**Riesgo aceptado:** si admin cambia `es_efectivo`/`es_digital` de un método
después, las ventas offline ya guardadas siguen mostrando la foto antigua en
cierre/impresión local. Los totales en servidor siguen correctos vía el id.

---

### 6. Mejorar la idempotencia en sincronización offline

El flujo offline atómico (`fn_registrar_venta_offline` con `p_pagos`) ya está
desplegado en vivo como **sobrecarga** de la función original y es
idempotente por `client_uuid`. **Pero** verificado en vivo, su bloque de
reparación de pagos repite la guarda binaria del servidor:

```sql
IF NOT EXISTS (SELECT 1 FROM app_dat_pago_venta
               WHERE id_operacion_venta = v_op LIMIT 1) THEN
  v_ok := public.fn_registrar_pago_venta(...);
```

Si una sync insertó pagos parciales y falló a mitad, los reintentos marcan
`pagos_registrados: true` sin reparar. El fallback de la app a
`fn_registrar_venta` + `fn_registrar_pago_venta` usa `_operacionTienePagos`,
la misma guarda binaria corregida en `order_service.dart`.

**Resuelto (2026-10-14):**

- SQL v2/v3 desplegado en main y newa.
- `auto_sync_service`: eliminado `_operacionTienePagos`; ahora
  `_pagosCoincidenConEsperado` compara el desglose completo. Un pago
  parcial (1 de 2 medios) ya no se considera “listo”.
- Reparación preferente vía `fn_registrar_pago_venta_v2`.

**Archivos:**

- `lib/services/auto_sync_service.dart`
- `lib/sql/fn_registrar_venta_offline_con_pagos.sql`

---

## 🎯 Propuesta de orden de ataque

1. **Aplicar el SQL idempotente** (`fn_registrar_pago_venta_idempotente.sql`).
2. **Moneda paralela:** decidir A o B y agregar `moneda` al modelo.
3. **Fuente única de pagos:** refactorizar `_registerPaymentsInSupabase` y
   `_pagosParaSincronizar` para que siempre deriven del ítem + moneda del
   método.
4. **Catálogo real:** mover 999 y 998 a `app_nom_medio_pago`.
5. **CxC:** mantener tablas actuales; opcionalmente integrar el método 998 en
   el catálogo.
6. **Limpieza offline:** quitar `es_digital`/`es_efectivo` del payload al RPC.

---

## 📎 Archivos relevantes

- `lib/services/order_service.dart`
- `lib/services/auto_sync_service.dart`
- `lib/screens/checkout_screen.dart`
- `lib/models/payment_method.dart`
- `lib/sql/fn_registrar_pago_venta_idempotente.sql`
- `ventiq_admin_app/docs/migrations/10_cuentas_por_cobrar.sql`
- `ventiq_admin_app/docs/migrations/11_cuentas_por_cobrar_clientes_independientes.sql`
