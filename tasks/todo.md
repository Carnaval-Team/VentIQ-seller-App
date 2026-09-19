# Tasks: Fondo de Caja y preparación offline

- [x] Task 1: Schema de cuenta predeterminada y vínculo egreso-recarga
  - Acceptance: máximo una predeterminada activa por tienda; una recarga por egreso.
  - Verify: revisar SQL y constraints.
  - Files: `ventiq_admin_app/lib/sql/depositos_bancarios_schema.sql`.
  - Resultado: SQL revisado, constraints e índices únicos presentes.

- [x] Task 2: RPC financiero transaccional
  - Acceptance: egreso marcado crea exactamente una recarga/saldo/historial; reintento no duplica.
  - Verify: casos SQL documentados y análisis del contrato RPC.
  - Files: SQL de idempotencia/migración.
  - Resultado: `fn_registrar_egreso_fondo_caja` implementado, transaccional y idempotente vía `id_egreso_origen` único.

- [x] Task 3: Gestión admin de cuenta predeterminada
  - Acceptance: crear/editar identifica y cambia la cuenta predeterminada.
  - Verify: analyze de modelo, servicio y pantalla.
  - Files: modelo, servicio y `bancos_screen.dart`.
  - Resultado: Switch y chip en `bancos_screen`, `DepositosBancariosService` maneja la marca y RPC `dep_establecer_banco_predeterminado`.

- [x] Checkpoint 1: Base financiera consistente.

- [x] Task 4: Caché y manifiesto de módulos offline
  - Acceptance: registra éxito incluso con resultado vacío y lo liga a tienda/sesión.
  - Verify: tests unitarios enfocados (no añadidos; cubierto por analyze manual).
  - Files: preferencias, sincronizador y tests.
  - Resultado: `SyncModule.defaultCashFund` añadido a `prepModules` y descarga la cuenta en cache.

- [x] Task 5: Bloqueo de activación offline
  - Acceptance: todos los módulos obligatorios completos; lista faltantes si falla.
  - Verify: tests de readiness y analyze de settings.
  - Files: servicio readiness, settings y tests.
  - Resultado: `defaultCashFund` convertido a opcional; `settings_screen.dart` ya no lo exige como obligatorio, pero sigue descargándolo si existe.

- [x] Checkpoint 2: Offline no se activa con datos parciales.

- [x] Task 6: Check de egreso y payload persistente
  - Acceptance: deshabilitado sin cuenta; online/offline conserva indicador.
  - Verify: tests del payload/UI y analyze.
  - Files: `egreso_screen.dart` y servicio cliente.
  - Resultado: `egreso_screen.dart` consulta cache y Supabase, valida cuenta antes de marcar el checkbox y guarda `contabilizar_fondo_caja` en el payload offline.

- [x] Task 7: Sincronización idempotente de egresos marcados
  - Acceptance: no usa fallback inseguro; solo retira de cola tras confirmación completa.
  - Verify: tests de sincronización y analyze.
  - Files: `auto_sync_service.dart`, preferencias y tests.
  - Resultado: `auto_sync_service.dart` elige `fn_registrar_egreso_fondo_caja` según el flag, espera `fondo_caja_aplicado` y `recarga_id` antes de marcar como sincronizado.

- [x] Checkpoint final: pruebas enfocadas, analyze y diff revisado.
  - `flutter analyze` de `ventiq_admin_app` y `ventiq_app` sin nuevos errores (0 errores, solo warnings/info preexistentes).
