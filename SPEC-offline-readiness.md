# Spec: Preparación para modo offline manual

## Objective
Impedir que el usuario active manualmente el modo offline mientras no exista una descarga confirmada y utilizable de todos los módulos obligatorios de su tienda y sesión.

## Required modules
- Licencia offline válida.
- Configuración de tienda.
- Credenciales del usuario.
- Métodos de pago.
- Promociones.
- Categorías.
- Productos.
- Ubicaciones/layouts.
- Turno actual.
- Egresos.
- Órdenes.
- Trabajadores del turno.
- Cuenta predeterminada de Fondo de Caja.

Una consulta exitosa con cero registros cuenta como sincronizada para promociones, turno, egresos, órdenes, trabajadores y otros módulos que legítimamente puedan estar vacíos. Categorías, productos, métodos de pago, credenciales, licencia y cuenta predeterminada además deben contener datos utilizables.

## Design contract
- `AutoSyncService` debe devolver y persistir el resultado por `SyncModule`, no inferir preparación por el tamaño agregado del caché.
- El estado persistido debe pertenecer a la tienda y al contexto de sesión actuales y registrar fecha de sincronización.
- Cambiar tienda, TPV, almacén o usuario invalida cualquier estado incompatible.
- La activación manual ejecuta una sincronización fresca de todos los módulos requeridos sin reutilizar como éxito un checkpoint parcial anterior incompatible.
- Antes de llamar `setOfflineMode(true)`, un validador produce `ready` y una lista de módulos faltantes/fallidos.
- Si `ready == false`, el switch vuelve a apagado y se muestra la lista; no se conserva el comportamiento actual de continuar con caché viejo tras una sincronización fallida.
- La cuenta de Fondo de Caja se considera lista solamente si la consulta terminó y devolvió una cuenta activa predeterminada de la tienda.

## UI behavior
- Mientras se verifica/sincroniza, el switch queda deshabilitado.
- En fallo, se mantiene modo online y se presenta un diálogo o mensaje legible con módulos pendientes.
- En éxito, se activa offline y se notifica al `SmartOfflineManager` como actualmente.

## Testing strategy
- Unit tests del evaluador: todos completos; módulo faltante; módulo vacío válido; datos obligatorios vacíos; contexto de tienda distinto; licencia inválida.
- Test de servicio para comprobar persistencia/invalidación del manifiesto.
- Widget test del switch: nunca llama a activar offline si `ready == false`.

## Commands
- Focused tests: `flutter test test/services/offline_readiness_service_test.dart`
- Analyze: `flutter analyze lib/services lib/screens/settings_screen.dart`
- Full tests: `flutter test`

## Boundaries
- Always: bloquear de forma conservadora ante estado desconocido; conservar resultados vacíos confirmados; mostrar causa concreta.
- Ask first: cambiar la lista de módulos obligatorios o permitir caché antiguo tras un fallo.
- Never: activar offline basándose solo en `hasOfflineData()`; borrar colas locales pendientes para conseguir estado listo.

## Success criteria
- No se activa manualmente offline si cualquiera de los módulos requeridos no terminó correctamente.
- Cero resultados confirmados no se confunden con una descarga fallida.
- El usuario conoce exactamente qué módulos impiden el cambio.
- La validación utiliza exclusivamente datos de la tienda/sesión actuales.
