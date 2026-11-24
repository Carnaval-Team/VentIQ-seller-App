# 10 — Estado del equipo y contradicciones con el plan del fondo

Revisión de solo lectura, 2026-11-20, rama `multimoneda` (activa). Verificado contra los documentos
del equipo **y** contra `prosrc`/catálogo de `newa` (debug) y Main (release) por SELECT.
Jerarquía de fuentes cuando choquen: `AGENTS.md` (20/11 09:32) > este plan (20/11 09:31) > `tasks/*`
(19–20/11) > anexos `00`-`06` (19/11, escritos contra Main).

Fuentes vivas: 79 funciones `fn_m01_*` en newa y **0** en Main; `app_dat_producto_costo` y
`app_dat_recepcion_producto_costo` solo en newa; `fn_fdi_gasto` solo en newa; `fdi_dat_liquidacion`
sin `repartir_igual` en Main; `costo_real` `generated` en Main y no generada en newa;
`fn_fdi_registrar_recepcion` **no existe en ninguno de los dos entornos**.

---

## 1. Estado del pase `newa` → main

| Pieza | newa | Main | Orden | Bloqueo |
|---|---|---|---|---|
| RLS `app_dat_configuracion_tienda` + 3 `fn_config_tienda_*` | sí (Task 2) | RLS apagado, sin políticas | fase 1 | G2: usuarios sin rol admitido (`plan_promocion_main.md:85`) |
| `app_dat_producto_costo`, `app_dat_recepcion_producto_costo`, trigger `costo_real` | sí | **no** (verificado) | fase 1, Task 3 (`plan_sync_newa_main.md:54`) | ninguna; la fase 0b del plan duplica esto |
| `fn_fdi_gasto` + tipo `'gasto'` + `repartir_igual` + `crear_liquidacion` 11 args | sí (8 args) | **no**: solo 10 args, sin columna | fase 1, Task 4 (`plan_sync_newa_main.md:59`) | la regla de los 11 args (§2 R1) |
| M01 completo (scripts 1–56) | sí, 79 `fn_m01_*` | **0** | fase 1, al final | G1–G4; baselines `md5` 14/17/56; H4 |
| `fix_reporte_ventas_por_turno_sin_cierre.sql` | sí | pendiente | fase 1 | criterio de turno único |
| `fix_cambio_estado_operacion_mejorado_recepcion.sql` | sí (`RECEPCION_INVENTARIO_USADO` presente) | **no** (verificado) | fase 1; publicar Admin después | — |
| `fix_apertura_turno_offline_id_turno.sql` | aplicado 20/11 (H1) | **el defecto existe** | fase 1 | revisar turnos ya afectados |
| `fix_listar_ordenes_tipo_pago.sql` | sin `'tipo_paago'` hoy (verificado) | ya emitía `tipo_pago` | fase 0 | el registro dice «pendiente»: fila desactualizada |
| 12 funciones main → newa (`fn_check_update`, las 8 de precio, etc.) | pendiente | — | fase 0/3 | `ORDER BY id DESC` (`plan_admin_multimoneda.md:28`) |

**Orden acordado** (`plan_admin_multimoneda.md:47-51`): 1) parche `tipo_pago`, 2) regenerar baselines
`md5` 14/17/56 contra Main, 3) traer las 12 a newa **y** aplicar en Main en este orden:
contabilización → `fn_reporte_ventas_por_turno` → `mejorado` → firma de 11 args → M01. Nada se aplica
en Main sin OK del dueño (`plan_admin_multimoneda.md:16`).

**Qué bloquea:** H4 (R0b no puede ir en la primera pasada, `plan_promocion_main.md:36-38`), G1/G2/G3/G4,
los baselines, y que Main no tenga **nada** de M01. El pase **no ha empezado**.

---

## 2. Reglas vigentes que obligan al plan

- **R1 — `fn_fdi_crear_liquidacion` debe quedar con 11 parámetros y solo esa.**
  `AGENTS.md:55`, `plan_admin_multimoneda.md:32` y `:49`, `comparacion_funciones_newa_main.md:160` y
  `:211-223`, `ventiq_admin_app/lib/sql/fondo_inversion_schema.sql:618-634` (hace `DROP` de la de 10).
  Motivo: Admin manda siempre `p_repartir_igual`. **El plan está mal** al decir «preservar la firma del
  entorno» (`PLAN.md:314-315`, `:776`, `:18`): preservar deja a Main con 10 y Admin fallando.
- **R2 — La recepción financiada tiene un único camino: `fn_fdi_registrar_recepcion`.**
  Varias fuentes cuenta/medio/moneda, importes nativos, `tasa_a_ref`, la suma de equivalentes
  redondeados debe cubrir la factura exacta; crea inversión, movimientos, recepción y vínculo en
  **una** transacción, bloquea saldos y guarda clave por formulario. **No sustituirla por llamadas
  separadas ni reintentar por la recepción sin financiación.** Cancelar desvincula y recalcula la
  inversión **sin devolver dinero** al fondo (`AGENTS.md:45-47`). Aviso: hoy **no está desplegada** en
  newa ni en Main; es migración del repo (`lib/sql/fondo_inversion_financiar_recepcion.sql:19-161`).
- **R3 — `costo_real`, adicionales y `precio_promedio`.** `costo_real`: en newa no es generada y tiene
  trigger NULL-safe (`plan_sync_newa_main.md:24`); en Main sigue generada y 30.038/30.333 filas en NULL
  (`PLAN.md:12`, `:30`). Los adicionales por tipo y la ponderación los resuelve
  `fn_actualizar_precio_promedio_recepcion_v2` de newa (`comparacion_funciones_newa_main.md:67`);
  `_v3` es código muerto. **No se recalculan costos históricos** (`AGENTS.md:8`) y **cancelar una
  recepción no revierte costos** (`AGENTS.md:52`).
- **R4 — `fn_registrar_cambio_estado_operacion_mejorado` (estados 3 y 4) está decidida y cerrada.**
  No borra filas de `app_dat_inventario_productos`: devuelve con movimiento compensatorio
  (`origen_cambio` 4 devolución / 5 cancelación); si algún producto ya se usó devuelve
  `RECEPCION_INVENTARIO_USADO` con `productos_con_problema` y **no cancela nada**. Es el híbrido
  main+newa acordado el 19/11 (`AGENTS.md:52`, `plan_admin_multimoneda.md:31`,
  `comparacion_funciones_newa_main.md:132`, `plan_sync_newa_main.md:100`). Falta llevarla a Main.
- **R5 — Nombres y fases.** Cambio de contrato o de semántica = nombre nuevo `_m01`, el cliente llama
  `_m01` y cae a la antigua solo si la función no existe (`AGENTS.md:56`, `plan_promocion_main.md:44-46`,
  `:80`). Mismo nombre solo si la respuesta es idéntica o superconjunto **sin rechazos nuevos**
  (`plan_promocion_main.md:44`). Orden: **expansión → clientes → contrato** (`plan_promocion_main.md:74-109`).
- **R6 — En el pase manda el cuerpo de Main** salvo decisión documentada; no copiar de newa las 16 donde
  Main es más nueva ni a newa lo que solo Main tiene (`AGENTS.md:54`).
- **R7 — La expansión no altera nada**: nada de `REVOKE`, `DROP`, `DROP FUNCTION` ni triggers nuevos en
  el camino de venta (`plan_promocion_main.md:89-94`).
- **R8 — Puerta de hallazgos**: no se pasa a Main nada con filas «pendiente» (`AGENTS.md:56`,
  `tasks/hallazgos_pruebas_newa.md:3`).

---

## 3. Hallazgos abiertos en `newa`

| # | Estado real | Toca fondo/recepción/costos |
|---|---|---|
| H1 (`hallazgos:12`) | aplicado en newa; **el defecto existe en Main** | no (turno/caja) |
| H2 (`hallazgos:13`) | el registro dice «pendiente», pero `prosrc` de newa ya **no** tiene `'tipo_paago'` (md5 `27297d9c…`, Main `7b4e85d9…`) | no (`fn_listar_ordenes`) |
| H3 (`hallazgos:14`) | corregido en cliente `ventiq_app`; Admin sin decisión | no (sesión/refresh) |
| H4 (`hallazgos:15`) | abierto por diseño: R0b va a contrato | no (trabajadores) |
| H5/H6 (`hallazgos:25-26`) | por confirmar (respaldo de monedas en apertura) | no (apertura de turno) |

**Ningún hallazgo abierto toca fondo, recepción ni costos.** Pero H2 es puerta del pase y su fila está
desactualizada: verificar y cerrar antes de apoyarse en ella.

---

## 4. Contradicciones plan ↔ equipo

| # | El plan dice | El equipo tiene decidido | Corrección |
|---|---|---|---|
| C1 | «**No tocar** `fn_fdi_crear_liquidacion`… preservar la firma del entorno» (`PLAN.md:314-315`, riesgo `:776`) | Main debe terminar con **solo** los 11 args (`AGENTS.md:55`, `plan_admin:32,49`, `comparacion:211-223`; el esquema hace `DROP` de la de 10) | En newa se preserva 11 (nunca reescribir 11→10). En Main se **aplica** el Task 4: columna `repartir_igual`, `fn_fdi_gasto`, `DROP` de la de 10, `CREATE` de la de 11 |
| C2 | PD1 y «**la recepción no mueve dinero**»; fase 5 solo valoriza (`PLAN.md:90-91`, `:143-155`, `:508`) | La financiación de recepción mueve dinero **en la recepción**: `fn_fdi_registrar_recepcion` crea inversión y descuenta saldos en la misma transacción y prohíbe dos caminos (`AGENTS.md:45-46`) | Decidir y escribir: o la compra **usa** esa RPC como único camino al recepcionar, o es otro producto y la RPC se retira por decisión del dueño. Dos caminos de dinero para el mismo acto no |
| C3 | «**Deprecar** `fn_registrar_cambio_estado_operacion_mejorado` en el botón Completar» (`PLAN.md:527-529`) | Es la función **combinada y arreglada** el 19/11; su fix está en newa y **falta en Main** (`AGENTS.md:52`, `plan_admin:31`, `comparacion:132`, `plan_sync:100`) | No deprecarla. Promover el fix y usar `contabilizada` como semáforo dentro de ella. Que `fn_contabilizar_recepcion_inventario` sea el único que propaga lote no la sustituye |
| C4 | Fase 0b va a Main «**antes que cualquier otro**»: `DROP EXPRESSION`, backfill 30.038, reescritura de cuerpo (`PLAN.md:253-254`, `:296-341`) | Expansión solo aditiva; alteraciones en contrato, con respaldo y reversa; Tasks 3 y 4 ya son dueños de esos objetos (`plan_promocion:87-94`, `:103-109`, `plan_sync:54-62`) | Partir 0b: lo aditivo (tablas, trigger, `'gasto'`, `fn_fdi_gasto`, `repartir_igual`) viaja con Tasks 3/4. `DROP EXPRESSION` + backfill + cambio de cuerpo van a contrato |
| C5 | «**Reescribir** `fn_actualizar_precio_promedio_recepcion_v2` en Main con el cuerpo de newa» (`PLAN.md:312-313`) | Cambio de cálculo = **nombre nuevo `_m01`**; mismo nombre solo con respuesta idéntica (`plan_promocion:44`, `:58`, `AGENTS.md:56`). Cuerpos distintos hoy: Main 6.118 car. vs newa 13.235 | `_m01` en Main + caída del cliente + retiro de la vieja en contrato. Nunca un swap silencioso: cambia el costo del inventario sin tocar al cliente |
| C6 | Quitar el `EXCEPTION WHEN OTHERS` y añadir idempotencia **en la misma** firma de 12 args (`PLAN.md:522-524`) | «Cambio de semántica = RPC nueva» (el propio `PLAN.md:235`); cambio de contrato = `_m01` y sin rechazos nuevos para usuarios legítimos (`plan_promocion:44`) | Hacerlo en una `_m01`/`_v2` y pasar G1 antes de Main. La viva de 12 args no se toca: `fn_fdi_registrar_recepcion` y el Admin desplegado dependen de ella |
| C7 | Crear rama `dev` desde `origin/main` y «no hay convención de migración» (`PLAN.md:185-190`, `:269`) | La rama de trabajo es `multimoneda` (no existe `dev`); sí hay convención: `sql_updates/` (70 scripts), `verificar_*`, test de contrato (`AGENTS.md:7,47,52`; `plan_admin:40`) | Trabajar en `multimoneda`; si se quiere `dev`, crearla **desde `multimoneda`**, nunca desde `origin/main` (perdería el trabajo del pase) |
| C8 | Entregar SQL en `ventiq_admin_app/lib/sql/compra/` + `verify/NN_verificacion.sql` (`PLAN.md:246-251`, `:270`) | `ventiq_admin_app/lib/sql/` es plano (`fondo_inversion_schema.sql`, `fondo_inversion_financiar_recepcion.sql`); los parches aplicados van a `sql_updates/`; los borradores son `m01_r*_propuesta.sql`; las comprobaciones, `verificar_*` (`docs/plan-multimoneda/`) | Usar `sql_updates/` + `verificar_*` y añadir casos a `sync_newa_main_sql_contract_test.dart`. No abrir subcarpeta nueva |

**Lo que el plan sí aporta y no existe** (no hay que buscar más): `fdi_dat_compra*`, `fn_fdi_compra_*`,
aportes de inversores al 100% y panel de pendientes no aparecen en `tasks/` ni en `docs/plan-multimoneda/`
(búsqueda sin resultados). Fases 3, 7 y 9 son trabajo nuevo. Fases 1–2 chocan con datos reales de newa
(16 movimientos, 3 liquidaciones) y eso ya está previsto en `PLAN.md:275-276`, `:355-359`.

---

## 5. Convenciones que debe adoptar el plan

1. **`_m01`** para funciones con cambio de contrato o semántica; el cliente la llama primero y cae a la
   antigua solo si no existe (`AGENTS.md:56`, `plan_promocion:9,46,80`). No inventar `_v5`/`compra_v1`.
2. **Expansión → clientes → contrato**: aditivo primero, clientes después, retiradas al final y por
   tienda o versión mínima (`plan_promocion:74-109`).
3. **`sql_updates/<fix_*.sql>`** para cada script que se aplique (`AGENTS.md:47,52-53`;
   `plan_promocion:93`). Si nace de una prueba, entrada inmediata en
   `tasks/hallazgos_pruebas_newa.md` (`AGENTS.md:56`).
4. **`verificar_*.sql`** de solo lectura con salida `ok|falla`, no `verify/NN_*.sql`
   (`AGENTS.md:7`; `docs/plan-multimoneda/verificar_m01_*.sql`).
5. **Borrador = `_propuesta.sql`** (o `preflight_*`) hasta que el dueño apruebe
   (`docs/plan-multimoneda/m01_r*_propuesta.sql`, `preflight_m01_*.sql`).
6. **Contrato de los scripts en Dart**: `ventiq_admin_app/test/sync_newa_main_sql_contract_test.dart`
   (15 casos, `plan_admin:40`). Añadir ahí, no crear un runner nuevo.
7. **Esquemas completos** (tipo `fondo_inversion_schema.sql`) van planos en `ventiq_admin_app/lib/sql/`;
   los parches de una base concreta, en `sql_updates/`. Nada de `lib/sql/compra/`.
8. **Nada de `DROP`/`REVOKE`/triggers en la fase de expansión** (`plan_promocion:94`) y **nada se valida
   primero en Main** (`PLAN.md:237`): newa primero, siempre.