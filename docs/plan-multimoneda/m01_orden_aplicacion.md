# M01 — Orden de aplicación del paquete de hardening

Todos los archivos son **borradores para revisión y ejecución manual en newa** (SQL Editor, usuario postgres). Nada se aplica automáticamente.

Cada script exige en su preflight `SET app.m01_<corte>_approved = 'yes'` (o la GUC correspondiente) dentro de la transacción: es el mecanismo de aprobación explícita por entrega.

> **Promoción a main:** antes de aplicar nada en main, leer
> `desincronizacion_newa_main.md`. Main tiene producción que newa no tiene (WhatsApp,
> referidos, versiones de app, precios Carnaval, fix de egresos por turno). Además, los
> preflight de estos scripts validan md5 de newa: hay que regenerarlos para main.

## Prerequisito

- **S01** (endurecimiento de `app_dat_configuracion_tienda` + helpers `fn_config_tienda_puede_leer/escribir`) debe estar aplicado y verificado — ya aplicado.

## Orden

| # | Script | Por qué en ese lugar |
|---|---|---|
| 1 | `m01_r0a_duenos_propuesta.sql` | Predicado estricto de dueño/superadmin full; no depende de los demás. |
| 2 | `m01_r0b_guard_reasignacion_vendedor_propuesta.sql` | La guarda interna es requisito de la RPC de reasignación. |
| 3 | `m01_r0b_rpc_reasignacion_vendedor_propuesta.sql` | Preflight exige la guarda (2) ya instalada. |
| 4 | `m01_r0b_policies_personal_propuesta.sql` | Crea helper RH + policies de trabajadores/vendedor + control de columnas. |
| 5 | `m01_r0b_identidad_trabajador_propuesta.sql` | RPC de identidad; restaura la vinculación de usuario que (4) bloquea. |
| 6 | `m01_r0b_policies_recursos_humanos_propuesta.sql` | Protege la fuente de pertenencia RH usada por (4). |
| 7 | `m01_r0c_policies_tpv_almacen_cocina_propuesta.sql` | Crea helpers `tienda_de_almacen`/`tienda_de_cocina` requeridos por (8). |
| 8 | `m01_r0c_policies_roles_propuesta.sql` | Policies de membresías + RLS en supervisor/auditor/jefe_cocina/cocina. |
| 9 | `m01_r0d_entradas_protegidas_propuesta.sql` | search_path fijo, revoca DEFINER legacy, crea los 8 wrappers `fn_m01_*`. Después de (4)–(8) porque sus wrappers asumen el modelo de ámbito. |
| 10 | `m01_r0e_operaciones_tienda_idempotencia_propuesta.sql` | Cierra `app_dat_tienda` (ancla), operaciones e idempotencia. |
| 11 | `m01_r0f_invoker_roles_propuesta.sql` | Wrappers DEFINER de las 4 INVOKER de rol y revocación de su ejecución directa. Exige helpers R0b/R0c y restaura flujos que los cortes 4–8 bloquean. |
| 12 | `m01_r0g_offline_definer_propuesta.sql` | Cierra EXECUTE anónimo y fija search_path en la flota DEFINER offline/registro; no valida internamente actor/ámbito ni completa M01. |
| 13 | `m01_r0i_idempotencia_evidencia_propuesta.sql` | Única alta de `m01_solicitud` y `m01_id_tienda`. Es control compartido de la clave global, no un corte de Admin Lite. Sin backfill. |
| 14 | `m01_r0i_venta_offline_v4_propuesta.sql` | Registro offline del vendedor normal. Exige actor, vendedor/TPV/trabajador coherentes y huella. El replay no reescribe pagos. Revoca al cliente las sobrecargas offline anteriores. Requiere (10) y (13). |
| 15 | `m01_r0i_pago_offline_propuesta.sql` | Cobro offline del vendedor. Misma evidencia de (13). El actor cobra su venta o delega como administrador; el replay no vuelve a registrar pagos. Requiere (10) y (13). |
| 16 | `m01_r0i_estado_offline_propuesta.sql` | Cambio de estado offline. Misma evidencia de (13). El replay no repite el cambio. No revoca la función online. Requiere (10) y (13). |
| 17 | `m01_r0i_caja_cocina_propuesta.sql` | Apertura, cierre, egreso, pedido de mesa, estado de plato y cierre de un turno duplicado sin inventario. Misma evidencia de (13). El pedido delega en `fn_pedir_item_cuenta_v2`. El replay no repite el efecto. Requiere (10) y (13). |
| 18 | `m01_r0i_descuento_pago_propuesta.sql` | Descuento manual y traslado de un pago. Misma evidencia de (13). El actor es `auth.uid()`. El replay no rebaja ni mueve otra vez. Requiere (10) y (13). |
| 19 | `m01_r0i_anotaciones_propuesta.sql` | Cierre solicitado, limpieza del marcador, cuenta por cobrar, foto y cliente de la venta. Misma evidencia de (13). El replay no reescribe. Requiere (10) y (13). |
| 20 | `m01_r0i_turno_personal_propuesta.sql` | Recibir una orden anterior al turno, trabajadores del turno y registro de cambio de precio. Requiere (13) y (19). El replay no repite el efecto. |
| 21 | `m01_r0i_config_tienda_propuesta.sql` | Modo restaurante, impresora, tickets, copias y autocompletado del conteo. Solo `fn_config_tienda_puede_escribir`. Requiere (13). El replay no cambia el valor. |
| 22 | `m01_r0e_tienda_columnas_propuesta.sql` | El cliente solo actualiza el perfil de `app_dat_tienda`. Validación, prueba y vínculo Carnaval pasan por superadmin. Requiere (10). |
| 23 | `m01_r0i_foto_sms_notificaciones_propuesta.sql` | Quitar foto, limpiar el SMS y reactivar o borrar una notificación propia. Requiere (13) y (19). |
| 24 | `m01_r0b_desvincular_usuario_propuesta.sql` | Desvincula el login del trabajador. No borra `auth.users` ni las filas de rol. Requiere `fn_config_tienda_puede_escribir`. |
| 25 | `m01_r06_politica_revision_propuesta.sql` | MC-006. Flag `permitir_moneda_por_producto` en false y revisión inmutable del snapshot. Aplicado en newa. |
| 26 | `m01_r07_constancia_politica_propuesta.sql` | MC-007. Entrega la revisión al usuario y al dispositivo. Aplicado en newa. |
| 27 | `m01_r08_idempotencia_aislamiento_propuesta.sql` | MC-008. La clave solo se lee si es del usuario y de una tienda que puede leer. |
| 28 | `m01_r09_capacidad_politica_propuesta.sql` | MC-009. Rechaza encender el flag. Falta el registro de venta v1. |
| 29 | `m01_r10_precio_tpv_usd_propuesta.sql` | MC-010. USD opcional en el precio de TPV. El CUP sigue obligatorio. |
| 30 | `m01_r11_precio_tpv_resolver_propuesta.sql` | MC-011. Resuelve la vigencia de mayor id. No rescata un USD viejo. |
| 31 | `m01_r11_precio_tpv_guardar_propuesta.sql` | MC-011. Alta de una vigencia nueva. No reescribe la anterior. |
| 32 | `m01_r12_extraccion_v1_propuesta.sql` | MC-022. Columnas de producto-v1 en la venta y la extracción. Aplicado en newa. |
| 33 | `m01_r12_pago_aplicacion_propuesta.sql` | MC-023. Atribución pago-línea. Aplicado en newa. |
| 34 | `m01_r13_calcular_linea_propuesta.sql` | MC-024. Calcula y valida la línea desde su snapshot. Aplicado en newa. |
| 35 | `m01_r14_registrar_venta_v1_propuesta.sql` | MC-025. Alta de mostrador. Aplicado en newa. |
| 36 | `m01_r15_pagos_v1_propuesta.sql` | MC-026. Cobro nativo y atribución. Aplicado en newa. |
| 37 | `m01_r16_ajustar_linea_v1_propuesta.sql` | MC-027. Selección y aumento de cantidad. Aplicado en newa. |
| 38 | `m01_r16_harness_v1.sql` | MC-028. Rechazo sin actor. El usuario lo ejecutó y revirtió. |
| 39 | `m01_r17_legacy_con_flag_propuesta.sql` | MC-037. Aplicado en newa. Una venta nueva sin versión no entra si el flag está encendido. No reescribe filas viejas. El flag sigue apagado. |
| 40 | `m01_r18_mesa_v1_columnas_propuesta.sql` | MC-039. Aplicado en newa. Columnas de mesa y tablas nuevas con RLS. No rellena cuentas viejas. |
| 41 | `m01_r19_mesa_pedido_v1_propuesta.sql` | MC-040. Aplicado en newa. Pedir y cancelar sin unir monedas distintas. |
| 42 | `m01_r20_mesa_cierre_v1_propuesta.sql` | MC-041. Aplicado en newa. Cierre y cobro en una transacción. No vuelve a descontar lo ya pedido. |
| 43 | `m01_r21_cxc_v1_propuesta.sql` | MC-042 y MC-043. Aplicado en newa. Deuda y liquidación por moneda. |
| 44 | `m01_r22_ajuste_v1_propuesta.sql` | MC-044. Aplicado en newa. Devolución que no reescribe la línea original. |
| 45 | `m01_r23_revocar_anon_mesa_cxc_propuesta.sql` | MC-048. Aplicado en newa. anon ya no ejecuta mesa, deuda ni devolución. El flag sigue apagado. |
| 46 | `m01_r24_pedir_mesa_enrutado_propuesta.sql` | MC-040. Aplicado en newa. La comanda queda solo en cocina al pedido. |
| 47 | `m01_r25_activar_flag_tienda_propuesta.sql` | Borrador para pegar. Deja que el administrador guarde el flag. No enciende ninguna tienda. |
| 48 | `m01_r0e2_idempotencia_revokes_propuesta.sql` | Enmienda del (10), ya aplicado: `REVOKE ALL ON TABLE` no retiró los privilegios heredados de PUBLIC ni los GRANTs por columna. Revoca tabla y columnas a PUBLIC/anon/authenticated y aborta si queda escritura efectiva. Solo idempotencia; sin policies ni datos. |
| 49 | `m01_r26_preorden_v1_propuesta.sql` | La preorden del TPV entra por el mismo alta v1 (origen `preorden`). Reemplaza el cuerpo de (35); la mesa sigue rechazada. Además corrige el alta: `app_dat_operaciones.uuid` referencia `users` y lleva el actor (antes iba el client_uuid y violaba la FK en el alta real). Preflight acepta el cuerpo de (35) o una corrida previa. |
| 50 | `m01_r27_pagos_v1_operacion_lookup_propuesta.sql` | Enmienda del cobro v1 (36): la venta se resuelve por `app_dat_operacion_offline_idempotencia` (`tipo='venta_v1'`), no por `operaciones.uuid`, que tras (49) guarda al actor. Sin este cambio el cobro cae con 42501. Preflight acepta el cuerpo de (36) o una corrida previa. |
| 51 | `m01_r28_estado_devolucion_presentacion_propuesta.sql` | Enmienda del cambio de estado: la devolución/cancelación resuelve `id_presentacion` NULL (base en v1) a la fila `es_base` de `app_dat_producto_presentacion`, en el match del saldo y en el INSERT del ledger (NOT NULL). Sin este cambio cancelar una venta v1 cae con 23502. Preflight exige el cuerpo vigente o una corrida previa. |
| 52 | `m01_r29_listar_ordenes_v1_propuesta.sql` | Enmienda del listado de órdenes: `detalles.items` expone las columnas v1 de `app_dat_extraccion_productos` (moneda, selección, snapshots) y `detalles` la versión y `client_uuid` (huella de idempotencia). Sin este cambio la reimpresión cae al camino legacy y las líneas USD imprimen precio 0. **Corregido el 19/11:** la clave de cada pago salía como `'tipo_paago'` y el TPV lee `tipo_pago`. La fuente ya está corregida; newa vivo se parchea con `sql_updates/fix_listar_ordenes_tipo_pago.sql` (pendiente de correr). Preflight exige el cuerpo vigente o una corrida previa. |
| 53 | `m01_r30_flag_forzada_exclusion_propuesta.sql` | MC-056. Exclusión mutua flag/forzada: `fn_m01_fijar_moneda_por_producto` apaga `forzar_moneda_venta`/`moneda_venta_forzada` en el mismo UPDATE al activar, y el trigger `fn_validar_moneda_forzada` rechaza forzar=true con el flag encendido. No toca `mostrar_selector_moneda` (retirada del admin y del TPV nuevo; la columna queda para clientes viejos). Preflight exige los cuerpos vigentes o corridas previas. |
| 54 | `m01_r31_reporte_ordenes_v1_propuesta.sql` | M06-R02. Borrador para pegar. `reporte_ordenes_json_v2` aditiva: no toca la legacy. Items con `version_monetaria` + `linea_v1` (id_linea_cliente, componentes nativos/equivalentes como decimales exactos, medio seleccionado), pagos por identidad con `aplicaciones` (sin fan-out, sin filtrar medios inactivos), `totales_por_moneda` por orden y envelope R01 (versiones, base comercial, completitud con `V1_SIN_METADATA_DE_LINEA`). Exige `fn_config_tienda_puede_leer` en servidor — la v1 del reporte no validaba tienda. Preflight exige columnas v1 de extracción y `app_dat_pago_aplicacion`. |
| 55 | `m01_r32_ventas_por_moneda_v2_propuesta.sql` | M06-R05. Borrador para pegar. `fn_reporte_ventas_por_moneda_v2` aditiva: mismo cálculo que la v1 de newa (cohorte: operaciones por created_at + último estado 2) pero declarado — envelope R01 con `magnitud='cobrado'`, `base_temporal='cohorte_ventas'` (no flujo de caja), decimales exactos, `PAGOS_SIN_EQUIVALENTE_CUP` como incompletitud, medios por LEFT JOIN, consolidado etiquetado como presentación con tasa actual, y `fn_config_tienda_puede_leer` en servidor. Preflight exige la v1 y `fn_moneda_consolidacion`. |
| 56 | `m01_r33_turno_offline_fecha_propuesta.sql` | Aplicado en newa (verificado el 19/11). Enmienda de (14) y (17), vivos en newa. Ventas offline que quedan fuera de su turno (`docs/issues/ventas_offline_desaparecen_tras_sync.md`). La apertura reutilizada o en replay recupera la hora real con `fn_turno_alinear_fecha_apertura`: solo hacia atrás, nunca futura, sin pisar el turno anterior, tope 72 h. Candado por TPV + vendedor además del de `client_uuid`. Fechas de cierre y de venta acotadas a `now()`. La huella del replay ignora la fecha. Nueva `fn_alinear_apertura_turno_offline` para el cliente. Preflight exige los md5 vivos de (14) y (17). Sin tablas nuevas. Compatible con el cliente actual. Va antes de D1 (ver "R33 — cliente"). |

**Nota de interdependencia:** aplicar (4)–(8) endurece los INSERT de trabajadores/roles. Hasta aplicar (9), el alta inicial de tiendas (`crear_estructura_tienda` directa) queda bloqueada — se restaura mediante `fn_m01_crear_estructura_tienda`. Aplicar el conjunto sin pausa larga entre (4) y (9), o aceptar esa ventana de bloqueo.

## Admin Lite — no forma parte de esta liberación

`m01_r0h_vendor_assign_offline_propuesta.sql`, `m01_r0h_vendor_flags_offline_propuesta.sql` y `m01_r0h_vendor_flags_harness.sql` quedan como antecedentes. No se aplican para cerrar el TPV normal. La asignación ya no crea columnas: exige la evidencia de (13). Aplicarlos sigue siendo un cambio de Admin Lite y necesita su propia revisión. No borran ni revierten los borradores.

## Verificadores de solo lectura (ejecutar después de cada corte)

| Corte | Verificador |
|---|---|
| R0a | `verificar_m01_r0a_duenos.sql` |
| R0b | `verificar_m01_r0b_personal.sql` |
| R0e | `verificar_m01_r0e_operaciones.sql` |
| R0c + R0d | `verificar_m01_r0c_r0d.sql` |
| R0i (13–23) | `verificar_m01_r0i.sql` |
| Columnas de tienda (22) | `verificar_m01_tienda_columnas.sql` |
| Política (25) | `verificar_m01_politica_revision.sql` |
| Entrega de política (26) | `verificar_m01_constancia_politica.sql` |
| Lote 27–31 | `verificar_m01_lote_27_31.sql` |
| Lote 32–33 | `verificar_m01_lote_32_33.sql` |
| Lote 34–38 | `verificar_m01_lote_34_38.sql` |
| Lote 39 | `verificar_m01_lote_39.sql` |
| Lote 40–44 | `verificar_m01_lote_40_44.sql` |
| Piloto 49–51 | `verificar_m01_m07_piloto.sql` |
| R33 (56) | `verificar_m01_r33.sql` |

## Migración de clientes

El admin ya llama primero a `fn_m01_*`. Si esa función todavía no existe, usa la llamada anterior. Un 42501 no abre el UPDATE ni la RPC vieja. Hay que correr los scripts 1 a 12 antes de quitar ese respaldo: hoy newa no tiene los wrappers.

| Llamada actual | Sustituto |
|---|---|
| `fn_asignar_vendedor` / `fn_desasignar_vendedor` | `fn_m01_asignar_vendedor` / `fn_m01_desasignar_vendedor` |
| `fn_asignar_supervisor` / `fn_desasignar_supervisor` | `fn_m01_asignar_supervisor` / `fn_m01_desasignar_supervisor` |
| `fn_asignar_jefe_cocina` | `fn_m01_asignar_jefe_cocina` |
| `crear_tpv_completo` | `fn_m01_crear_tpv` |
| `create_gerente_from_email` | `fn_m01_crear_gerente` |
| `crear_estructura_tienda` | `fn_m01_crear_estructura_tienda` (sin `usuario_creador`) |
| `VendedorService` UPDATE directo `id_tpv` | `fn_m01_personal_reasignar_vendedor` (script 3) |
| `WorkerService.updateWorkerUUID` | `fn_m01_personal_vincular_usuario_trabajador` (script 5) |
| `fn_desvincular_usuario_trabajador` | `fn_m01_personal_desvincular_usuario_trabajador` (script 24). Quita el uuid del trabajador y de sus filas de rol. No borra la cuenta ni las filas de rol. |
| `fn_editar_trabajador_basico` | `fn_m01_editar_trabajador_basico` (`p_uuid` debe ir NULL; la identidad es la RPC dedicada) |
| `fn_agregar_rol_trabajador` | `fn_m01_agregar_rol_trabajador` (`p_id_tienda`/`p_usuario_uuid` se validan contra el trabajador en DB) |
| `fn_actualizar_datos_rol_trabajador` | `fn_m01_actualizar_datos_rol_trabajador` |
| `fn_eliminar_rol_trabajador` | `fn_m01_eliminar_rol_trabajador` |

## R33 — ventas offline fuera de su turno

Diagnóstico completo y SQL de main en `docs/issues/ventas_offline_desaparecen_tras_sync.md`.
El script 56 es la versión para newa, montada sobre los cuerpos de (14) y (17).

### Estado en newa (consultado el 2026-11-18)

- (14) y (17) **están aplicados**: los cuerpos llevan `m01_solicitud`, existe
  `fn_m01_cerrar_turno_residual` y `anon` no ejecuta apertura, cierre ni venta. La nota
  de "Pendientes" que dice "no está aplicado" quedó vieja.
- **Actualización 2026-11-19: newa ya usa `America/Havana`** (como main) y el script 56
  está aplicado (`fn_turno_alinear_fecha_apertura` y `fn_alinear_apertura_turno_offline`
  existen). El cliente D1–D7 está en el commit `337c2920`. Lo que sigue describe el
  estado del 18/11 por la mañana, cuando newa estaba en UTC.
- **`TimeZone = UTC` en newa el 18/11** (main usa `America/Havana`). El cliente envía las fechas
  offline con `toIso8601String()` de un `DateTime` local, sin offset. En newa la hora
  local de Cuba se guardaba como si fuera UTC: **5 h antes** de la real. Las aperturas y
  cierres hechos online, en cambio, usan `now()`. El mismo build sale bien o mal según el
  proyecto: debug apunta a newa, release a main (`supabase_config.dart`). Hace falta D1
  antes de cualquier piloto offline en newa.

| Causa | (14)/(17) en newa | Lo cubre |
|---|---|---|
| Reutilizar un turno abierto no recupera la apertura real | No: la rama "reutilizado" solo inserta la idempotencia | 56 + D2 |
| Dos aperturas simultáneas con distinta `client_uuid` | No: el candado es por `client_uuid` | 56 + D3 |
| Fechas futuras (venta, apertura, cierre) | No: se copian tal cual | 56 + D1 |
| El cierre toma el turno de otro vendedor del TPV | **Sí** (`creado_por = p_usuario`) | — |
| `anon` ejecuta apertura y cierre | **Sí**, revocado | — |
| Huella con la fecha: un replay con D1 cae en 42501 | Riesgo nuevo de (14)/(17) | 56 (la huella ignora la fecha) |

### R33 — cliente (`ventiq_app`, rama `multimoneda`)

El código y la explicación de cada cambio están en la sección 6.3 del documento de
diagnóstico. Todo implementado el 18/11 en `multimoneda` (sin commit).

| # | Cambio | Estado | Dónde |
|---|---|---|---|
| D1 | Enviar las fechas como UTC con `Z` | **Hecho**. Test `test/fecha_rpc_test.dart` | `lib/utils/fecha_rpc.dart` (`fechaUtcParaRpc`). `auto_sync_service.dart`: `p_fecha_apertura`, `p_fecha_cierre`, `p_fecha_creacion` |
| D2 | Alinear la apertura al reutilizar un turno | **Hecho** | `auto_sync_service.dart`: `_alinearFechaAperturaEnServidor` → `fn_alinear_apertura_turno_offline`. Se llama en las cinco salidas de `_ensureAperturaForQueueEntryUnlocked` que reutilizan un turno abierto. Si la RPC no existe, solo lo registra en el log |
| D3 | Encadenar aperturas por TPV + vendedor | **Hecho**. Test `test/cadena_por_clave_test.dart` | `lib/utils/cadena_por_clave.dart`. `_ensureAperturaForQueueEntry` usa `_aperturaPorTpv` (clave `id_tpv:id_vendedor`) además del candado por `local_id` |
| D4 | Conservar la copia local sincronizada mientras su turno siga abierto | **Hecho** | `removeSyncedPendingPresentOnServer` no borra las del turno abierto. `loadOrdersFromLocalCacheForOpenTurno` no repite `ORD-{id}` ya presentes en el cache. `getSellerVisiblePendingOrdersCount` cuenta solo `synced != true` |
| D5 | `saveOfflineTurno` conserva la apertura más temprana del mismo turno | **Hecho**. Test `test/apertura_mas_temprana_test.dart` | `UserPreferencesService.aperturaMasTemprana`, en `fecha_apertura` de la entrada y de `apertura` |
| D6 | `savePendingOrder` no pisa `created_offline_at` | **Hecho** | `??=` en `savePendingOrder` |
| D7 | Ajustes: un solo camino de sync | **Hecho** | `_SyncDialog`: el paso `pending_orders` pasa a `sync_turno_queue` (`AutoSyncService().forceSyncPendingOrders()`). Se eliminó `_processPendingOrders`. `pending_operations` sigue procesando `order_status_change` |

Pendiente de prueba en dispositivo: pruebas de la sección 6.4 del diagnóstico en newa,
con el teléfono en una zona horaria distinta de Cuba.

### Orden de despliegue

1. Script 56 en newa + `verificar_m01_r33.sql`. Mantiene firmas y retornos, así que el
   build actual sigue funcionando. Tiene que ir **antes** de D1: con (14)/(17) sin
   enmendar, un replay de una clave ya registrada con la fecha vieja y reenviada en UTC
   cae en 42501 y la cola se detiene.
2. Cliente con D1 a D7. D2 tolera que la RPC no exista (`_isRpcUnavailable`).
3. Piloto offline en newa (pruebas de la sección 6.4 del diagnóstico), con el teléfono
   en una zona horaria distinta de Cuba.
4. Main: hasta que M01 llegue, se aplica el hotfix S1–S6 del diagnóstico (mismos nombres
   `fn_turno_alinear_fecha_apertura` / `fn_alinear_apertura_turno_offline`, cuerpos sin
   huella M01). Al promover M01 a main, (14), (17) y (56) necesitan baselines md5 de
   main: los actuales son de newa y el hotfix cambia los cuerpos.

## Pendientes fuera de este paquete
- Los scripts 14, 15 y 16 cubren la venta, el cobro y el cambio de estado offline, todavía sin aplicar. El 14 también revoca `fn_registrar_venta_offline_v2`. El vendedor ya no registra la venta offline ni el cambio de estado en cola con las funciones sin clave: ajustes delega en el sync y la cola usa `fn_registrar_cambio_estado_offline`. La apertura y el cierre de ajustes ya no llaman `fn_cerrar_turno_tpv` ni `registrar_apertura_turno`: los sube `uploadTurno`. Si `fn_cerrar_turno_offline` existe y rechaza, el sync no cierra sin clave. El cambio de estado online sale por `fn_registrar_cambio_estado_offline` y solo usa `fn_registrar_cambio_estado_operacion` si esa RPC no existe. La apertura online sale por `fn_apertura_turno_offline_monedas`. Si el cierre dice que cerró y la fila sigue abierta, el sync no la cierra con `UPDATE`. `fn_admin_caja_*` sigue con su cuerpo actual. Sus INSERT nombran columnas y toleran las columnas nuevas en NULL. El script 17 reemplaza los cuerpos con clave de turno, egreso y comanda. El cierre online ya llama `fn_cerrar_turno_offline_monedas` antes que `fn_cerrar_turno_tpv`. El KDS ya llama `fn_cambiar_estado_comanda_item_offline` antes que la función sin clave. El script 17 endurece apertura, cierre, egreso, pedido y estado de plato, guarda el mapa de monedas en la huella y hace que el pedido con clave delegue en v2. No está aplicado. El pedido online sigue en `fn_pedir_item_cuenta_v2` y, si esa función no existe, no llama la anterior. El ticket completo del KDS marca cada plato con `fn_cambiar_estado_comanda_item_offline` y, sin platos, no llama `fn_cambiar_estado_comanda`. El cierre offline envía `fecha_cierre` en la RPC con clave. Admin Lite no se continúa. El script 20 recibe una orden anterior al turno, anota los trabajadores y registra el cambio de precio. Si esa RPC no existe, el TPV conserva la escritura de hoy. Un 42501 no la abre. El script 21 escribe la configuración de tienda que el TPV cambia hoy a mano. Solo quien puede escribir la tienda. La cola de trabajadores y la campana usan las funciones del script 20. El 22 cierra las columnas de confianza de `app_dat_tienda`. El 23 quita la foto, limpia el SMS y reactivar o borra la notificación propia. El 24 desvincula el login sin borrar la cuenta ni los roles. El usuario corrió `m01_r0i_rol_harness.sql` en newa el 2026-11-14 y no saltó error. Termina en ROLLBACK. El 14 de noviembre de 2026 las huellas MD5 de las nueve funciones que los scripts 14 a 17 reemplazan coincidían con newa, y `fn_desvincular_usuario_trabajador` seguía ausente. Esa lectura no ejecuta los cuerpos.
- Harness de Admin Lite preparado, NO EJECUTADO y fuera de esta liberación: `m01_r0h_vendor_flags_harness.sql`. No se aplica junto con los scripts 13–14. Si más adelante se autoriza, en la misma ejecución del SQL Editor y antes del archivo hay que fijar `app.m01_r0h_flags_harness_approved = 'yes'`, `app.m01_fixture_vendor_id`, `app.m01_fixture_admin_uuid` y `app.m01_fixture_denied_uuid`, con IDs de prueba revisados. El harness modifica temporalmente el permiso y crea claves sintéticas dentro de BEGIN/ROLLBACK. No usar vendedores reales ni main.
- Cliente Admin Lite: `_syncVendorAssignTpv` y `_syncVendorUpdateFlags` ya no intentan UPDATE directo ante errores de RPC. Las demás rutas Admin Lite no se siguen en este corte.
- Compilar y probar los borradores en PostgreSQL autorizado antes de liberar M01. Para el script 14: vendedor del TPV, otro TPV, delegación de administrador, UUID legacy sin evidencia, misma clave con otra solicitud, replay sin segundo cobro y dos sesiones. Los tests Dart solo inspeccionan texto SQL.
- UUID anteriores de asignación sin solicitud/tienda verificables se rechazan para revisión: no hay backfill, borrado de cola ni regeneración automática de UUID. El replay nuevo comprueba acceso administrativo actual a la tienda registrada y devuelve el resultado original sin repetir la asignación, aunque después haya cambiado el TPV. El cliente debe mostrar el error y conservar la operación.
- Mapeo de columnas de `app_dat_tienda` para restringir el UPDATE directo.
- El harness de rol ya corrió en newa el 2026-11-14 y pasó en una sesión. Siguen fuera de esa corrida la carrera de dos pestañas, el anónimo y el superadmin inactivo: newa no tiene uno.
