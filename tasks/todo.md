# Tasks: Fondo de Caja y preparación offline

- [ ] Task 1: Schema de cuenta predeterminada y vínculo egreso-recarga
  - Acceptance: máximo una predeterminada activa por tienda; una recarga por egreso.
  - Verify: revisar SQL y constraints.
  - Files: `ventiq_admin_app/lib/sql/depositos_bancarios_schema.sql`.

- [ ] Task 2: RPC financiero transaccional
  - Acceptance: egreso marcado crea exactamente una recarga/saldo/historial; reintento no duplica.
  - Verify: casos SQL documentados y análisis del contrato RPC.
  - Files: SQL de idempotencia/migración.

- [ ] Task 3: Gestión admin de cuenta predeterminada
  - Acceptance: crear/editar identifica y cambia la cuenta predeterminada.
  - Verify: analyze de modelo, servicio y pantalla.
  - Files: modelo, servicio y `bancos_screen.dart`.

- [ ] Checkpoint 1: Base financiera consistente.

- [ ] Task 4: Caché y manifiesto de módulos offline
  - Acceptance: registra éxito incluso con resultado vacío y lo liga a tienda/sesión.
  - Verify: tests unitarios enfocados.
  - Files: preferencias, sincronizador y tests.

- [ ] Task 5: Bloqueo de activación offline
  - Acceptance: todos los módulos obligatorios completos; lista faltantes si falla.
  - Verify: tests de readiness y analyze de settings.
  - Files: servicio readiness, settings y tests.

- [ ] Checkpoint 2: Offline no se activa con datos parciales.

- [ ] Task 6: Check de egreso y payload persistente
  - Acceptance: deshabilitado sin cuenta; online/offline conserva indicador.
  - Verify: tests del payload/UI y analyze.
  - Files: `egreso_screen.dart` y servicio cliente.

- [ ] Task 7: Sincronización idempotente de egresos marcados
  - Acceptance: no usa fallback inseguro; solo retira de cola tras confirmación completa.
  - Verify: tests de sincronización y analyze.
  - Files: `auto_sync_service.dart`, preferencias y tests.

- [ ] Checkpoint final: pruebas enfocadas, analyze y diff revisado.
