# Spec: Cuenta predeterminada de Fondo de Caja

## Objective
Permitir que cada tienda marque exactamente una cuenta activa de `dep_dat_banco` como receptora predeterminada de los egresos contabilizados en Fondo de Caja.

## Data contract
- Agregar `es_predeterminada_fondo_caja BOOLEAN NOT NULL DEFAULT FALSE` a `dep_dat_banco`.
- Crear un índice único parcial por `idtienda` cuando el valor sea `TRUE`, garantizando una sola cuenta predeterminada por tienda.
- Una cuenta predeterminada debe estar activa y pertenecer a la misma tienda.
- Desactivar la cuenta predeterminada debe exigir elegir otra cuenta o dejar explícitamente la tienda sin predeterminada; en ese último caso el check de egreso y la activación offline quedan bloqueados.
- No se asignará automáticamente una cuenta existente durante la migración.

## Admin behavior
- La gestión de bancos/proveedores muestra cuál es la cuenta predeterminada.
- Crear o editar una cuenta permite marcarla como predeterminada.
- Al marcar una nueva, la anterior se desmarca dentro de una operación atómica de base de datos.
- El selector principal de Fondo de Caja puede priorizar visualmente la predeterminada, sin impedir consultar las demás.

## Client/offline contract
- `ventiq_app` descarga únicamente los datos mínimos de la cuenta predeterminada activa: `id`, `idtienda`, denominación, moneda y estado.
- El resultado se guarda asociado a la tienda actual.
- Si no existe, se guarda que la consulta finalizó sin resultado, pero `offline-readiness` lo considera no utilizable y bloquea el modo offline.

## Testing strategy
- Pruebas SQL: unicidad por tienda, pertenencia, cuenta activa y cambio atómico de predeterminada.
- Unit tests de serialización y caché por tienda.
- Widget/service tests de gestión administrativa.

## Commands
- Admin analyze: `flutter analyze lib/models/depositos_bancarios.dart lib/services/depositos_bancarios_service.dart lib/screens/depositos_bancarios/bancos_screen.dart`
- Client focused tests: `flutter test test/services/default_cash_fund_service_test.dart`
- Full tests per app: `flutter test`

## Boundaries
- Always: validar tienda en servidor; mantener una sola predeterminada; conservar cuentas y saldos existentes.
- Ask first: asignar automáticamente una cuenta histórica como predeterminada.
- Never: eliminar cuentas existentes; confiar solamente en validación de UI para la unicidad.

## Success criteria
- Cada tienda puede tener cero o una cuenta predeterminada, nunca más de una.
- El administrador puede identificarla y cambiarla.
- El cliente obtiene y conserva offline la cuenta de su propia tienda.
- Sin cuenta predeterminada, el egreso normal funciona pero no puede alimentar Fondo de Caja.
