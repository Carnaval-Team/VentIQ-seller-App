# Implementation Plan: Cobro en USD o CUP en la gestión del vendedor

## Overview
Permitir que el vendedor cobre operaciones en USD, CUP o mezcla de ambas por línea de pago, usando los precios USD ya configurados (`app_dat_precio_venta.precio_venta_usd`) y la tasa de la tienda como regla de conversión. El cierre de turno declara efectivo CUP y efectivo USD por separado. Debe funcionar online y offline, y **no romper** la app actual (cambios aditivos y retrocompatibles).

## Decisiones de negocio (confirmadas por el usuario)
1. **Mezcla por línea de pago**: cada línea de pago (efectivo/digital) tiene su moneda.
2. **Origen del precio USD**: `precio_venta_usd` del producto; como los precios responden a la tasa de la tienda, la conversión con esa tasa cuadra los montos.
3. **Producto sin precio USD**: se convierte el precio CUP por la tasa de la tienda.
4. **Cierre de turno**: el vendedor declara efectivo CUP y efectivo USD por separado, con diferencias separadas.
5. **Offline**: soportado (cola de ventas y cierre offline llevan la moneda).
6. **Medios en USD**: efectivo y digital.

## Principios de retrocompatibilidad
- Columnas nuevas con `DEFAULT` (moneda `'CUP'`), nunca `NOT NULL` sin default.
- Parámetros nuevos de RPC siempre `DEFAULT NULL`; si no llegan, el comportamiento es idéntico al actual.
- La app vieja que no manda moneda sigue funcionando: todo se registra como CUP.
- El payload offline sin campo `moneda` se interpreta como CUP.

## Architecture

### Base de datos (aditivo)
1. `app_dat_pago_venta`:
   - `moneda TEXT NOT NULL DEFAULT 'CUP'` (valores `'CUP'` / `'USD'`).
   - `tasa_usd NUMERIC` (tasa aplicada al momento del pago; NULL para CUP).
   - `monto_cup_equivalente NUMERIC` (para reportes existentes: pago USD × tasa; en CUP = monto).
2. `app_dat_caja_turno`:
   - `efectivo_inicial_usd NUMERIC DEFAULT 0`
   - `efectivo_real_usd NUMERIC`
   - `diferencia_usd NUMERIC`
3. RPCs (versión con parámetros opcionales, sin romper firmas actuales):
   - `fn_registrar_pago_venta`: aceptar por pago `moneda` y `tasa_usd` (default CUP).
   - `fn_registrar_venta` / `fn_registrar_venta_mesa`: si el pago viaja embebido, propagar moneda.
   - `fn_cerrar_turno*`: nuevo parámetro `p_efectivo_real_usd NUMERIC DEFAULT NULL`; si llega, calcular `diferencia_usd` con las ventas USD en efectivo del turno.
   - `fn_apertura_turno*` (o el flujo de apertura): `p_efectivo_inicial_usd DEFAULT NULL`.
   - `fn_resumen_diario_cierre_v3`: retornar además `ventas_usd`, `efectivo_usd_esperado`, `digital_usd`, manteniendo v2 intacta para la app vieja.
4. Todas las modificaciones en un solo script SQL idempotente (`IF NOT EXISTS` / `CREATE OR REPLACE`).

### ventiq_app (vendedor)
1. **Modelo**: `PaymentMethod` no cambia; se agrega la moneda en la línea de pago (checkout) y en el payload de venta: `moneda`, `tasa_usd`, `monto` (en la moneda elegida).
2. **Checkout** (`checkout_screen.dart`):
   - Selector CUP/USD por línea de pago (junto al método de pago).
   - Mostrar total USD (ya existe `_usdRate` y `_loadUsdRate`); el restante por cubrir se calcula convirtiendo los pagos USD a CUP por la tasa.
   - Validación: la suma de pagos convertidos cubre el total; tasa > 0 obligatoria para permitir USD.
3. **Registro de venta** (`order_service.dart`):
   - `_registerPaymentsInSupabase`: incluir `moneda` y `tasa_usd` por pago.
   - Persistir moneda en la orden local para impresión/ticket.
4. **Turno** (`turno_service.dart` + pantallas de apertura/cierre):
   - Apertura: campo opcional efectivo inicial USD.
   - Cierre: segundo campo "Efectivo real USD"; enviar `p_efectivo_real_usd`.
   - Resumen de cierre: mostrar ventas/efectivo USD por separado (usar v3; fallback a v2 si el RPC no existe → comportamiento actual).
5. **Offline**:
   - Payload de venta offline: agregar `moneda`/`tasa_usd` por pago (tasa desde cache: `getCambioCupUsd`, ya existe).
   - Cola de cierre offline: incluir `efectivo_real_usd`.
   - `auto_sync_service.dart`: reenviar los campos nuevos en el replay; si el RPC no los soporta aún (BD sin migración), degradar a comportamiento actual con warning.
   - `SyncModule` existentes cachean la tasa; verificar que la tasa esté en el prep offline.
6. **Ticket/impresión**: mostrar pagos con su moneda.

### ventiq_admin_app (solo lectura, fase posterior opcional)
- Reportes de ventas/turnos muestran columna USD. **No se toca en esta fase** salvo que algo se rompa por la columna nueva (no debería: todo es aditivo).

## Task List

### Phase 1: Base de datos
- [x] Script SQL aditivo: columnas en `app_dat_pago_venta` y `app_dat_caja_turno`.
- [x] Actualizar RPCs de pago con parámetros opcionales de moneda.
- [x] Actualizar RPCs de apertura/cierre de turno + `fn_resumen_diario_cierre_v3`.

### Checkpoint 1
- Ejecutar el script en Supabase sobre datos existentes sin errores; la app actual sin cambios sigue vendiendo (todo CUP).

### Phase 2: Checkout y registro de venta (online)
- [x] Selector de moneda por línea de pago en checkout + validación con tasa.
- [x] Enviar moneda/tasa en `_registerPaymentsInSupabase` y flujo de mesa.
- [x] Ticket con moneda por pago.

### Checkpoint 2
- Venta 100% CUP idéntica a hoy; venta USD y mixta registran filas correctas en `app_dat_pago_venta`.

### Phase 3: Turno
- [x] Apertura con efectivo inicial USD opcional.
- [x] Cierre con efectivo real USD + diferencias separadas; resumen v3 con fallback a v2.

### Phase 4: Offline
- [x] Payload offline de venta y cierre con moneda/tasa; replay en `auto_sync_service`.
- [x] Verificar tasa USD en cache de prep offline.

### Checkpoint final
- `flutter analyze` limpio; prueba online, offline con cache fresco y offline con cache sin tasa (bloquear USD con aviso).

## Risks and Mitigations
| Riesgo | Impacto | Mitigación |
|---|---|---|
| RPC migrado pero app vieja instalada | Alto | Parámetros opcionales con default; firma vieja intacta |
| App nueva contra BD sin migrar | Alto | Detectar error de firma y degradar a flujo CUP con aviso |
| Tasa desactualizada offline | Medio | Mostrar tasa usada en checkout; bloquear USD si no hay tasa en cache |
| Reportes existentes suman USD como CUP | Alto | `monto_cup_equivalente` para agregados; revisar `fn_resumen_diario_cierre_v2` para que solo sume CUP + equivalente |
| Vuelto en moneda cruzada | Medio | Fase 1 no calcula vuelto cruzado: el vendedor ajusta montos manualmente |

## Fuera de alcance (esta fase)
- Cambios de UI en admin/reportes (solo se garantiza que no se rompan).
- EUR u otras monedas.
- Vuelto automático en moneda cruzada.
