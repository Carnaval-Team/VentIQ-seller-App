# Spec: Recarga de Fondo de Caja originada por egreso

## Objective
Permitir que un egreso de caja incremente opcionalmente el saldo de la cuenta predeterminada de Fondo de Caja, conservando consistencia e idempotencia tanto online como offline.

## User flow
- `egreso_screen.dart` muestra un check desmarcado por defecto: `Contabilizar en Fondo de Caja`.
- El check está habilitado solo cuando hay una cuenta predeterminada activa cacheada para la tienda.
- Sin cuenta, se muestra `Configure una cuenta predeterminada de Fondo de Caja`; el egreso normal permanece disponible.
- Marcarlo significa que el dinero sale de la caja de ventas e ingresa al Fondo de Caja. No crea una extracción.

## Data contract
- Cada egreso lleva un indicador persistente de contabilización en Fondo de Caja.
- `dep_dat_recarga_saldo` debe almacenar el vínculo con el egreso de origen, con restricción única para impedir más de una recarga por egreso.
- La recarga usa la cuenta predeterminada vigente y validada para la tienda al procesar la operación.
- La observación identifica el egreso y su motivo.
- Registrar la recarga, actualizar `dep_dat_saldo` y crear `dep_hist_saldo` debe ocurrir de forma atómica y bajo bloqueo de la fila de saldo para evitar actualizaciones perdidas.

## Server operation
- Extender o acompañar el RPC idempotente de egresos para recibir `contabilizar_fondo_caja`.
- Si es `FALSE`, conserva exactamente el flujo actual.
- Si es `TRUE`, la misma operación transaccional valida cuenta predeterminada, registra/reutiliza el egreso por `client_uuid`, crea/reutiliza la recarga por egreso y actualiza saldo/historial una sola vez.
- La respuesta incluye `egreso_id`, `recarga_id`, `fondo_caja_aplicado` e `id_banco`.
- Un error en Fondo de Caja hace fallar la operación completa; no debe quedar un egreso confirmado sin su recarga cuando el check estaba marcado.

## Offline/synchronization contract
- La cola offline conserva `client_uuid`, el indicador y los datos actuales del egreso.
- La sincronización usa exclusivamente el RPC transaccional para egresos marcados; no usa el fallback no atómico `registrarEgresoParcial` en ese caso.
- El elemento se elimina de la cola únicamente cuando la respuesta confirma tanto egreso como recarga.
- Reintentar con el mismo `client_uuid` devuelve el resultado existente sin volver a incrementar saldo.
- Egresos históricos y elementos de cola sin el nuevo campo se interpretan como `FALSE`.

## Testing strategy
- SQL/integration: operación normal; operación marcada; reintento; concurrencia; cuenta inexistente/inactiva/de otra tienda; rollback completo ante fallo.
- Unit tests de payload offline y compatibilidad de registros históricos.
- Widget tests: check habilitado/deshabilitado y envío del indicador.
- Sync tests: no retirar de cola ante éxito parcial o error; retirar tras confirmación completa.

## Commands
- Client focused tests: `flutter test test/screens/egreso_screen_test.dart test/services/expense_cash_fund_sync_test.dart`
- Analyze: `flutter analyze lib/screens/egreso_screen.dart lib/services/auto_sync_service.dart lib/services/user_preferences_service.dart`
- Full client tests: `flutter test`

## Boundaries
- Always: idempotencia por egreso; transacción en servidor; compatibilidad con colas antiguas; importe positivo.
- Ask first: permitir selección manual de cuenta desde el egreso o contabilizar por defecto sin check.
- Never: modificar saldo con una secuencia de llamadas independientes desde Flutter; crear una extracción; eliminar el egreso pendiente tras éxito parcial.

## Success criteria
- Un egreso marcado produce exactamente una recarga y un incremento de saldo.
- Los reintentos online/offline no duplican recargas ni saldo.
- Si falla cualquier parte, no queda una operación parcial confirmada.
- Un egreso no marcado funciona igual que antes.
