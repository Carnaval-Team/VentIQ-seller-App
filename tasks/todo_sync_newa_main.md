# Tasks: sincronizar newa con main

No ejecutar hasta cerrar el trabajo en curso. El plan está en `tasks/plan_sync_newa_main.md`. `tasks/todo.md` sigue siendo el de fondo de caja.

- [ ] Task 1: Cerrar moneda, precio vigente y las specs de TPV y admin
  - Acceptance: las specs citan el comportamiento cerrado
  - Verify: lectura de specs y de las RPC de pago en main
  - Files: `docs/specs/SPEC-ventiq-app.md`, spec de admin

- [ ] Task 2: RLS de configuración de tienda, de newa a main
  - Acceptance: el vendedor de la tienda lee la config; un ajeno no; dueño y gerente escriben
  - Verify: SELECT de prueba revertido con JWT de vendedor y con uno ajeno
  - Files: script nuevo en `sql_updates/`

- [ ] Task 3: Tablas de costo de producto y recepción, de newa a main
  - Acceptance: tablas, RLS, políticas y trigger de `costo_real` iguales a newa
  - Verify: columnas y políticas; insert de prueba revertido
  - Files: script nuevo en `sql_updates/`

- [ ] Task 4: Gasto de fondo y `repartir_igual`, de newa a main
  - Acceptance: `fn_fdi_gasto` y la firma con `p_repartir_igual` existen en main
  - Verify: firmas en `pg_proc`; monto 0 sigue fallando
  - Files: script nuevo en `sql_updates/`

- [ ] Task 5: Descuento de venta con `p_ruta`, de main a newa
  - Acceptance: la firma de newa incluye `p_ruta` y una llamada sin él sigue resolviendo el origen
  - Verify: argumentos iguales en los dos proyectos y una venta de prueba en newa
  - Files: script tomado del cuerpo de main

- [ ] Task 6: Columna `reporte_tpvs_modo_turno`, WAPI agotado y referidos, de main a newa
  - Acceptance: newa tiene la columna, `app_wapi_agotado_*` y `referral_*`
  - Verify: `pg_class` en newa
  - Files: script de esquema tomado de main, sin datos

- [ ] Task 7: Revisar las funciones del TPV cuyo cuerpo difiere y quedarse con el más nuevo
  - Acceptance: cada función de la lista del plan tiene lado ganador
  - Verify: `md5(prosrc)` igual en los dos proyectos para las decididas
  - Files: `tasks/plan_sync_newa_main.md`

- [ ] Task 8: Revisar el resto de firmas con cuerpo distinto
  - Acceptance: cada una tiene lado ganador o queda fuera del pase
  - Verify: ninguna función del TPV queda sin decisión
  - Files: `tasks/plan_sync_newa_main.md`
