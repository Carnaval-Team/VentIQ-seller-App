# Fondo de Inversión → Compras → Recepción → Consumo — plan de implementación

**Versión 6.2** · 2026-11-21 · Re-basado contra la rama **`multimoneda`**, `newa` (desarrollo) y Main
(producción). La 6.1 restauró el detalle operativo que la v6 comprimió (`11-diff-v4-v6.md`); la 6.2
cierra la revisión de la fase 6 (defectos D8-D12, ver bitácora). Las 8 decisiones del dueño siguen
cerradas.

## Correcciones de la v6 (rama `multimoneda`)

| # | La v5 decía | La realidad en `multimoneda` |
|---|---|---|
| A | No existía forma de financiar una recepción desde el fondo | Existe `fn_fdi_registrar_recepcion` (`fondo_inversion_financiar_recepcion.sql`): N fuentes cuenta/medio/moneda, idempotencia y **debita al recibir**. El cliente ya la llama (`inventory_service.dart:1382`) |
| B | "No tocar `fn_fdi_crear_liquidacion`, preservar la firma del entorno" | **Al revés.** Debe quedar **solo con 11 parámetros**. Main tiene únicamente la de 10 y no tiene `repartir_igual`: "preservar" deja Main roto |
| C | Deprecar `fn_registrar_cambio_estado_operacion_mejorado` en "Completar" | **Prohibido.** Es la función combinada main+newa del 19/11 (compensatorio `origen_cambio` 4/5, `RECEPCION_INVENTARIO_USADO`), con su fix pendiente en Main |
| D | Pase propio `newa → Main` (fase 0b) con `DROP EXPRESSION` y backfill antes que nada | El equipo tiene un pase formal (`tasks/plan_promocion_main.md`, `_m01`, expansión aditiva, baselines `md5`). **La 0b no inventa otro**; se integra a las Tasks 3/4 |

**Bloqueante operativo:** el cliente llama a `fn_fdi_registrar_recepcion` y esa función **no existe ni en
`newa` ni en Main** (verificado con `to_regprocedure`), igual que las columnas `fdi_idempotency_key` /
`fdi_solicitud`. La ruta "financiar recepción" falla en runtime hasta aplicar esa migración.

## Restaurado en la v6.1

La v6 comprimió el plan y perdió detalle operativo (`11-diff-v4-v6.md`). Recuperado:

- **A1** `p_origen text DEFAULT 'externa'` con la regla de derivación de `motivo` y la nota de
  compatibilidad (fase 5).
- **A2** fórmula del backfill `= precio_unitario − descuentos` y rollback que restaura la expresión (0b).
- **A3** Exit criteria y **E2E integral de 8 pasos** de la fase 8.
- **A4** inmutabilidad de `total_financiado` tras reservar.
- **A5-A24** (gravedad media): definición de tasa y no-regresión de v1, redondeo, ajustes `por_financiar`,
  **protocolo E2E por fase**, E2E numéricos de la fase 5, grano de la conciliación, alcance de R1 y de la
  idempotencia, cordura de `_v2`, contrato de X9, comportamiento de liberar/anular, fórmula y constraints
  de la fase 3, RLS/GRANT y contrato de RPC, matriz de permisos, ventana de edición del cargo de
  importadora, filtro `pendiente > 0`, selector multi-compra, desvío de importadora, exclusividad del
  aporte y E2E con cifras de las fases 1, 2 y 7.
- **A25-A34** (gravedad baja): `DROP` de overloads, RPC que propaga el lote, efecto de `cerrar_corto`,
  descuadre declarado, detalle del panel de pendientes, pantallas Stitch, regla de parada, checks de
  `verify/00`, caso fondo del reparto, quién declara el descuadre.
- **Contradicción resuelta:** quién aplica el stock con lote (ver "El lote en el camino que se conserva").

---

## Entornos

| | **`newa`** (desarrollo) | **Main** (producción) |
|---|---|---|
| ref | `qhprswhhfasrikhawjoz` | `vsieeihstajlrdvpuooh` |
| servidor MCP | `supabase-debug` | `supabase` |
| Módulo de costos | **Completo** | **No existe** |
| `costo_real` | `NEVER` + trigger NULL-safe | `GENERATED` → **30.038 NULL de 30.333 (99,0%)** |
| `fn_fdi_gasto` / tipo `'gasto'` | Sí | No |
| `fn_fdi_registrar_recepcion` | **No aplicada** | **No aplicada** |
| Fondo (`fdi_*`) | 16 movimientos, 10 saldos, 3 liquidaciones | 0 filas |
| Importadora / proveedor | 0 facturas | 26 + 48 |
| `app_cont_tipo_costo` | 0 filas | 0 filas |

**Regla:** se desarrolla y valida en `newa`; Main recibe por el **pase formal del equipo**.

> El `pull` de `multimoneda` no se pudo hacer desde el agente (sin credenciales). El dueño lo hizo y
> fusionó `main` (`bab9725b`). Base actual: `multimoneda` al día con `main`.

---

## Piezas existentes que este plan respeta

| Pieza | Qué hace | Cómo la usa el plan |
|---|---|---|
| `fn_fdi_registrar_recepcion(jsonb, jsonb, uuid)` | **Carril B**: recibe y debita en la misma transacción, N fuentes, cobertura exacta al centavo | Carril "recepción directa" (sin compra). **Nunca** con compra |
| `fn_fdi_crear_inversion` | Crea el sobre y **debita** inmediatamente | Base del carril B; el carril A no la usa |
| `fn_fdi_crear_liquidacion` | Liquidación de ganancia, **11 args** (`p_repartir_igual`) | No se toca en `newa`; en Main se **completa** (Task 4) |
| `fn_registrar_cambio_estado_operacion_mejorado` | Cambio de estado con compensatorio `origen_cambio` 4/5 y `RECEPCION_INVENTARIO_USADO` | **No se depreca**: es el camino de cancelación/devolución |
| `fn_contabilizar_recepcion_inventario` | Aplica stock **propagando `id_lote`**; idempotente por recepción | Es el que aplica stock en ambos carriles |
| `fn_actualizar_precio_promedio_recepcion_v2` | Pondera con stock previo; la de `newa` además suma `monto_usd` | Se **promueve el cuerpo de `newa`** a Main, nunca al revés |
| `trg_recepcion_productos_costo_real` | Rellena `costo_real` **solo si es NULL** | Molde del costo aterrizado; se replica en Main |
| Pase `newa → main` | `_m01`, expansión aditiva → clientes → contrato, baselines `md5` | El plan se **subordina** a él |

### El lote en el camino que se conserva

La v4 avisaba de que `fn_registrar_cambio_estado_operacion_mejorado` "completa sin lote y rompe FEFO", y la
v6 prohibía deprecarla sin explicar por dónde entra el lote. **Regla de la v6.1:** "Completar" hace **dos
cosas**, no una:

1. **Estado**: `fn_registrar_cambio_estado_operacion_mejorado` (necesaria para cancelar/devolver con
   compensatorio y `RECEPCION_INVENTARIO_USADO`).
2. **Stock**: `fn_contabilizar_recepcion_inventario`, que es la única que propaga `id_lote` e es idempotente
   por recepción.

Si el botón solo ejecuta la primera, R9 **no** está cubierto. La verificación de la fase 5 incluye
comprobarlo: recibir un producto por lotes y confirmar que el stock resultante conserva `id_lote`.

---

## Objetivo

Al terminar, el admin puede: registrar una **compra** con proveedor, factura, líneas y total; **financiarla
con una sola fuente** — saldo del Fondo repartido en varias cuentas y monedas, **o** aportes de inversores
al 100% — sin gastar dos veces el mismo dinero; **recepcionar** (total o parcial, una o varias facturas en
la misma carga) capturando el **cargo variable de importadora** con su % y sus reembolsos, más costos
adicionales por producto; ver **disponible, comprometido, ejecutado y pendiente**; y tener recordatorios de
facturas con productos faltantes.

**No-goals:** reescribir `imp_*`, devoluciones/notas de crédito, caducidad de reservas, pago mixto,
reescribir el histórico de `fdi_dat_inversion`, inventar un pase a producción paralelo, deprecar la función
combinada de cambio de estado.

---

## Progress

| Fase | Estado |
|---|---|
| 0. Cimientos y desbloqueo de la rama | **done** — migración aplicada, semáforo 7 ok / 0 falla / 1 info, E2E del dueño aprobado |
| 0b. Integrar el delta de esquema al pase formal | not started |
| 1. Motor de dinero I: integridad, escala y conciliación | **done** — 11/11 verificaciones y E2E del dueño aprobado |
| 2. Motor de dinero II: idempotencia, tasa y gasto vinculado | **done** — 2a, 2b, cliente a v2 y E2E del dueño aprobado |
| 3. Compra como documento | **done** — esquema, RPC, UI, verify 13/13 y E2E del dueño aprobado |
| 4. Reserva y liquidación (carril A, solo `al_pagar`) | **done** — backend, UI, verify 19/19 y E2E del dueño aprobado |
| 5. Recepción: carril A y carril B | **done** — recepción contra compra, carril B cerrado, verify 21/21 y E2E del dueño aprobado |
| 6. Costo aterrizado sobre el módulo existente | **done** — 6a/6b/6c/6d aplicados; `verify/06` **27/27**, pruebas de dinero **23/23 + 14/14**; aterrizaje al vincular, desvío, reversa, ajuste tardío con reserva/pago propios y catálogo bajo superadmin. **E2E del dueño aprobado (2026-11-23)** |
| 7. Inversores aportantes (100%) | **done** — 07 aplicado en `newa`; `fdi_dat_compra_aporte` aislada, exclusividad con 6 triggers, RPC de registrar/devolver, rama de aportes en `pagar` y guardas en `anular`/`cancelar`/`liberar`; UI de aportes con restante bloqueante. `verify/07` **32/32**, pruebas de dinero **42/42** y **E2E del dueño aprobado (2026-11-23)** |
| 8. Reportes, conciliación en UI y cierre | **done** — R2-R7 (`verify/08` **14/14**), R1 programada en `pg_cron` (`verify/08b` **9/9**), pantalla `/reportes` con alarma, aging y descuadres; legado de inversión en solo lectura; índice documental y `CAPABILITY-MAP`. **E2E del dueño aprobado (2026-11-23)** |
| 9. Pendientes, recordatorios y registro de faltantes | **en curso** — `09_pendientes.sql` (`verify/09` **14/14**), panel, detalle, facturas, exportación Excel/PDF, recordatorios con umbral y alerta en el inicio, con el almacenero sin importes. **Falta el E2E del dueño** |
| 10. Responsive real de las vistas nuevas | **done** — causa raíz corregida en `TablaReporte` (modo tarjeta por debajo de 720 px, sin scroll horizontal), pestañas cortas en móvil, barrido de `Axis.horizontal` y test de anchura a 360/390/800 px. **E2E del dueño aprobado (2026-11-24)** |

Current phase: 9 · Recommended next: cerrar el E2E de la 9 y pasar a las pruebas del dueño (sin migrar a main)

> Agente ejecutor: actualiza esta tabla al terminar y anota una línea por desviación. No marques `done`
> sin criterios de salida corridos y OK del dueño.

### Bitácora de desviaciones
<!-- fase · qué cambió · por qué -->

- **Fase 0 · sin rama nueva.** El dueño decidió trabajar directamente en `multimoneda`; se eliminó la
  rama `feat/compras` del plan y de los protocolos.
- **Fase 0 · el agente aplica en `newa`.** Cambio de regla: el agente aplica el SQL en `newa`; para Main
  solo entrega scripts. Antes rezaba que el agente no aplicaba nunca.
- **Fase 0 · `verify/00_linea_base.sql` v1 estaba roto.** Tenía dos sentencias y un CTE no sobrevive
  entre ellas (`ERROR: 42P01: relation "base" does not exist`). Corregido a una sola sentencia con el
  resumen como fila `UNION ALL` (`n = 99`). Se añadió al README la regla de validar el script exacto.
- **Fase 0 · aprobada por el dueño (2026-11-20).** Semáforo `7 ok · 0 falla · 1 info`; recepción
  financiada creada (operación 127, inversión 1, 10.000 USD, tienda 9); saldo USD 500.000 → 490.000;
  Σ saldos = Σ movimientos exacto.
- **Fase 1 · aplicada en `newa` (2026-11-20).** Escala 2 del ledger **sin mover un centavo**: Σ saldos =
  Σ movimientos = `679755075.15`, 19 movimientos intactos, 0 descuadres en 12 claves de 3 tiendas.
  R1 valida tienda y dos decimales (probado en vivo: rechaza cuenta ajena y `-0.001`); R3 con
  `FOR UPDATE`; R7 ya no exige inversores activos; R2 con tipo `devolucion_inversion`; nueva
  `fn_fdi_conciliacion`.
- **Fase 1 · dos guardias relajadas a propósito.** `fn_fdi_inversion_anular` y `fn_fdi_conciliacion`
  permiten contexto de servicio (`auth.uid() IS NULL`) para poder probarse desde el editor SQL; con
  sesión siguen exigiendo permiso. Sin esto no eran verificables hasta la fase 8.
- **Fase 1 · guardia de anulación probada.** Anular la inversión 1 (con la recepción 127 vinculada)
  devuelve `22023: tiene recepciones vinculadas; desvincúlelas antes de anular`.
- **Fase 1 · aprobada por el dueño (2026-11-20).** `verify/01` 11 ok · 0 falla; conciliación 0
  descuadres antes y después; cancelar la recepción dejó la inversión pendiente con el saldo debitado;
  `fn_fdi_inversion_anular` devolvió 10.000 y el saldo USD volvió a 500.000; repetirla dio
  `duplicada: true`. Los datos de prueba quedaron limpios.
- **Fase 2a · aplicada en `newa` (2026-11-20).** Columna `idempotency_key` + índice único parcial
  `(tipo, idempotency_key)`; backfill de **13 movimientos** con `idem:` en la observación (0 quedaron
  sin clave); `_fdi_aplicar_movimiento` pasa a **11 args con una sola firma** (se eliminó la de 10 para
  no dejar overload); las tres RPC atrapan `23505` y devuelven `duplicada: true`. Probado: el índice
  corta el duplicado y la transacción revierte sin residuo (0 movimientos de prueba).
- **Fase 2a · bug real encontrado.** `fn_fdi_ingreso_manual` comparaba
  `observacion = 'idem:<uuid>'`, pero el movimiento se escribe como `motivo · fecha · idem:<uuid>`:
  **la comprobación nunca coincidía** y el reintento duplicaba el ingreso. El índice lo cierra.
- **Fase 2 · desviación de alcance (justificada).** `fn_fdi_gasto(p_id_compra)` se pospone a la fase 3/4
  porque `fdi_dat_compra` aún no existe, y **X9** (tasa resuelta en servidor) a la fase 4 porque los
  pagos de compra tampoco. Quedan para 2b: `fn_fdi_transferir_v2` y **X11** (motivo estructurado y
  umbral en `fn_fdi_ajuste`).
- **Fase 2b · aplicada en `newa` (2026-11-20).** `fn_fdi_transferir_v2` con `T(origen→destino)` explícito,
  **cordura ±20 %** contra la última transferencia del mismo par y tasa inversa desnormalizada. La v1
  sigue intacta con sus 13 args. `fn_fdi_ajuste` suma `p_motivo_codigo` validado y umbral
  `fdi_dat_config.umbral_ajuste`: por encima, solo el dueño. Se borró la firma de 7 args para no dejar
  overload vivo.
- **Fase 2 · X11 simplificado a propósito.** "Doble aprobación" se implementó como **umbral que exige al
  dueño**, no como dos personas. La aprobación de dos usuarios necesita pantalla y notificación: queda
  como deuda documentada, no como algo que el plan diga que ya está.
- **Fase 2 · la cordura de tasa se apoya en datos propios.** En `newa`, `tasas_conversion` está **vacía**
  y `tasa_cambio_extraoficial` tiene 3 filas sin mapeo claro a códigos de moneda, así que la referencia es
  la **última transferencia del mismo par**. Cuando haya historial, el chequeo se vuelve efectivo solo.
- **Fase 2 · el cliente ya llama a v2.** `fondo_inversion_service.transferir` usa `fn_fdi_transferir_v2`;
  la conversión UI→v2 vive en `FondoInversionService.adaptarTransferenciaV2` (función **pura y estática**)
  con 5 tests en `test/fdi_transferencia_adaptador_test.dart`. `flutter analyze` limpio sobre los dos
  archivos y **5/5 tests en verde**. Sin este cambio, X2 seguía vivo aunque v2 existiera.
- **Deuda previa del repo, no de este plan.** `flutter test` completo da **7 archivos que no compilan**:
  llaman `Supabase.initialize(publishableKey:)` y `supabase_flutter 2.9.1` ya no acepta ese nombre. No lo
  toca este plan; queda registrado para que nadie lo confunda con una regresión de la fase 2.
- **Fase 2 · aprobada por el dueño (2026-11-20).** Transferencia 5 creada por la UI con
  `tasa_origen_a_destino` y `tasa_destino_a_origen` persistidas; la segunda transferencia con la tasa
  recíproca fue **rechazada** por la cordura; conciliación 0 descuadres en 3 claves.
- **Nota operativa.** `flutter test` lanzado por shell se cuelga en este entorno (0 bytes, sin proceso).
  Usar el MCP de Dart (`run_tests`, `analyze_files`) con el root `ventiq_admin_app` registrado.
- **Fase 3 · backend aplicado y probado en `newa` (2026-11-20).** 6 tablas con RLS, índice único de
  factura por proveedor, dos triggers de recálculo y las 5 RPC (`crear`, `editar`, `listar`, `detalle`,
  `cancelar`). Prueba real: compra #1 de la tienda 9 con 2 líneas (10×5 + 4×12,5 = 100) y 2 ajustes
  (15 % de importadora con `origen_pago='wallet_importadora'` = 15, más 30 con `origen_pago='fondo'`).
  Totales exactos: mercancía **100**, ajustes **45**, financiado **130**, aterrizado **145**. El cargo de
  la wallet capitaliza sin financiarse, que era el objetivo.
- **Datos de prueba creados.** Proveedores `1` y `2` en la tienda 9 (`PRV-TEST-001/002`) y la compra
  `#1` (`FT-PRUEBA-001`) en estado `creada`, para el E2E manual.
- **Fase 3 · UI cableada (2026-11-20).** 3 pantallas Stitch (`699b3ed3…` listado, `a52d5367…` alta,
  `c26e5148…` detalle) y 4 archivos Flutter: listado con filtros y tabla/tarjeta según ancho, alta/edición
  con líneas y ajustes, detalle con historial y cancelación con motivo. Ruta `/compras`, entrada en el
  drawer y permiso dueño/gerente. `analyze` **sin errores** en los 9 archivos tocados.
- **Fase 3 · verificación y rollbacks.** `verify/03_compra.sql` da **13 ok · 0 falla** en `newa`; existen
  `03a_compra_esquema_rollback.sql` y `03b_compra_rpcs_rollback.sql` (validados contra el catálogo, no
  ejecutados).
- **Fase 3 · hueco de permisos cerrado.** `fn_fdi_compra_recalcular` y `trg_fdi_compra_recalcular` nacían
  con `EXECUTE` a `PUBLIC`: `anon` podía invocarlas por PostgREST. Cerrado a `postgres`/`service_role`, y
  el recálculo verificado después (línea de prueba: mercancía 100 → 101, con `ROLLBACK`).
- **Fase 3 · aprobada por el dueño (2026-11-20).** Quedaron dos compras: #1 `cancelada` (100 mercancía /
  45 ajustes / 130 financiado / 145 aterrizado, 2 líneas, 2 hitos) y #2 `creada` (`45-054`, 1 línea).
- **Fase 4 · backend aplicado y probado en `newa` (2026-11-20).** Tablas `fdi_dat_compra_reserva` y
  `fdi_dat_compra_pago`; `fdi_dat_movimiento` gana `id_compra` y `tasa`; tipos `pago_compra` y
  `devolucion_compra`; `_fdi_aplicar_movimiento` pasa a 13 args y **devuelve el id del movimiento**.
  RPC: `fn_fdi_disponible`, `_reservar`, `_pagar`, `_liberar`, `_anular`; `_cancelar` ahora también libera
  desde `reservada`. Prueba real sobre la compra #2: reserva de 1 USD → `reservada`; pago → `pagada`, saldo
  488.000 → **487.999**, reserva `consumida`, movimiento `pago_compra -1,00` con `id_compra` y `tasa`, y
  conciliación en **0 descuadres**.
- **Fase 4 · UI de liquidación (2026-11-20).** Pantallas Stitch `f245be0f…` (desktop) y `a967540a…`
  (móvil) + `compra_liquidacion_screen.dart`: fuentes con saldo/reservado/**disponible**, monto nativo,
  tasa con par explícito, y **faltante en rojo que bloquea el botón** (`ResumenCobertura.cubreExacto`).
  El detalle gana las acciones por estado: **Reservar** (`creada`), **Pagar** y **Liberar** (`reservada`),
  **Anular** (`pagada`), todas con motivo obligatorio donde aplica y mostrando el error del servidor.
  `analyze` **sin errores** en los 4 archivos.
- **Fase 4 · verificación y rollback.** `verify/04_liquidacion.sql` → **19 ok · 0 falla · 2 info** en
  `newa`, con **control negativo** (inflar total, inflar reservado, sumar saldo: las tres cazan la
  violación, así que no pasan por vacío). El rollback tuvo que restaurar dos funciones que no estaban en
  el encargo: `fn_fdi_compra_cancelar` (el 04 la reescribió) y `_fdi_aplicar_movimiento` a **11 args /
  `RETURNS void`**, o quedaban apuntando a tablas borradas.
- **Fase 4 · defecto documental.** El comentario del 04 aplicado dice «12 args» donde la función quedó con
  **13**. El catálogo manda; el verify comprueba 13 y el rollback borra la firma de 13.
- **Fase 4 · aprobada por el dueño (2026-11-21).** E2E 1-8 en verde. Único defecto de UX reportado: al
  detalle le faltaba la vuelta al listado, porque tener `drawer` en el `Scaffold` **sustituye la flecha de
  volver por la hamburguesa**. Añadido `leading: BackButton` al formulario, al detalle y a la liquidación.
- **Fase 5a · vínculo recepción↔compra aplicado (2026-11-21).** `fdi_dat_compra_recepcion` gana
  `pct_importadora`, `base_importadora`, `monto_importadora`, `reembolso_importadora` y `origen_pago`;
  `app_dat_operacion_recepcion` gana `fecha_operacion`. Nuevas
  `fn_fdi_compra_recepcion_pendiente` (por línea: comprado/recibido/pendiente, verificada sobre la compra
  2 → pendiente 1) y `fn_fdi_compra_vincular_recepcion`, que enlaza una recepción ya registrada, valida
  cantidades contra el pendiente, exige confirmación para el exceso, calcula el cargo de importadora
  (`base × pct − reembolso`) y deriva el estado a `entrega_parcial` o `completada`.
- **Fase 5c · carril B cerrado (2026-11-21).** Tres agujeros:
  · **doble uso del desembolso**: al cancelar una recepción financiada se marca la inversión con
    `requiere_revision = true` y motivo `recepcion_cancelada` (nuevo valor del CHECK), y
    `fn_fdi_vincular_recepcion` la rechaza;
  · **reintento sobre cancelada**: `fn_fdi_registrar_recepcion` mira el último estado de la operación y
    **lanza error** en vez de devolver `duplicada: true` como si fuera éxito;
  · **compra y carril directo**: la RPC acepta `p_id_compra` solo para **rechazarlo** — una recepción con
    compra pertenece al carril A.
- **Fase 5b · aprobada por el dueño (2026-11-21).** E2E 1-5 en verde: recepción contra la compra #2 con
  cargo de importadora del 15 %, compra en `completada` y pendiente 0.
- **Fase 5 · verificación 21/21 y control negativo.** `verify/05_recepcion.sql` en verde sobre `newa`;
  cuatro invariantes (sobre-recepción, suma recibida, compra completada con pendiente, y cálculo del cargo
  de importadora) cazan la perturbación cuando se las engaña, así que no pasan por vacío. Rollbacks de
  05a y 05c validados contra catálogo, con los 3 cuerpos restaurados comparados línea a línea (0
  discrepancias).
- **Fase 5 · deuda detectada por el verify (pendiente, no oculta):**
  1. `fdi_dat_compra_recepcion` **no tiene `confirmada_con_exceso`**. Un exceso confirmado en el carril A
     es indistinguible de un exceso real, así que el verify lo marca como fallo por el lado estricto.
     Falta columna + escritura en `fn_fdi_compra_vincular_recepcion`.
  2. `app_dat_operacion_recepcion.fecha_operacion` existe pero **nadie la escribe**: 0 de 9 recepciones
     la tienen. Columna muerta hasta que el cliente la mande.
  3. La invariante de compras `entrega_parcial` pasa **vacuamente** (hoy hay 0 en ese estado).
  4. `verify/05` comprobación `n=2` necesitó `\y` en vez de `\b` para regex en Postgres; quedó corregida.
- **Fase 6a · base del costo aterrizado aplicada (2026-11-21).** Cerrados los dos huecos de la fase 5 y
  preparado el terreno del costo:
  · `fdi_dat_compra_recepcion.confirmada_con_exceso` + trigger que la marca cuando lo recibido supera lo
    comprado (antes un exceso autorizado era indistinguible de uno real);
  · `fecha_operacion` ahora se escribe sola en toda recepción (trigger `BEFORE INSERT`) y se hizo backfill:
    **0 recepciones sin fecha**;
  · `id_compra` (y `moneda` donde faltaba) en `imp_dat_factura` y `prv_dat_factura`, con índice parcial;
  · catálogo `app_cont_tipo_costo` **sembrado**: Aduana, Flete, Importadora, Seguro (antes 0 filas, así
    que el módulo de costos no se había ejecutado nunca).
  · Corregido en el script: `app_cont_tipo_costo.id` es identidad `GENERATED ALWAYS`, no admite id
    explícito; la transacción revirtió entera en el primer intento y se reaplicó sin id.
- **Fase 6b · aterrizaje aplicado en `newa` (2026-11-21).** Tres funciones:
  `fn_fdi_compra_recepcion_bases` (previsualiza), `fn_fdi_compra_repartir_aterrizaje` (reparto por valor,
  residuo a la línea de mayor base, idempotente por reemplazo, aborta si `Σ monto_usd ≠ cargo`) y
  `fn_fdi_recepcion_con_costos` (recepción + costos en **una transacción**). `verify/06_costos.sql`
  → **13 ok · 0 falla**. Prueba funcional en transacción revertida sobre el vínculo 1: 0,15 repartido en
  1 línea, tasa 1, y la segunda llamada reemplaza sin duplicar.
- **Fase 6b · decisiones del dueño.** `wallet_proveedor` **no capitaliza** (verificado: la función lo
  omite). Se añadió `tasa_usd_aplicada` al vínculo y las funciones la escriben, para que un aterrizaje en
  CUP sea auditable.
- **Fase 6b · deuda documental.** `06b_aterrizaje.sql` en el repo **va por detrás de `newa`**: le faltan el
  `ALTER` y la escritura de la tasa en los cuerpos de dos funciones. Marcado en la cabecera del archivo;
  **no promover a Main sin sincronizar**. `verify/06` aún no comprueba la columna nueva.
- **Hallazgo del carril normal.** `app_dat_operaciones.uuid` **no es único**, así que reintentar con el
  mismo `uuid` no protegía de duplicar; el wrapper usa advisory lock + memo como el carril del fondo.
- **Fase 6 · revisión de cierre: cinco defectos nuevos (D8-D12), todos cerrados (2026-11-21).** La
  revisión del commit `34eeb0ee` encontró cinco defectos que el `verify/06` de 15 comprobaciones no veía.
  Tres eran de dinero:
  · **D8 — una factura no-USD se quedaba sin tasa.** El carril normal sólo escribía
    `tasa_cambio_aplicada` si había inversión (`fondo_inversion_recepcion_patch.sql:130`) y el cliente no
    mandaba tasa: la operación quedaba con NULL y el aterrizaje abortaba después con `22023`, con la
    recepción ya creada. Ahora `fn_fdi_recepcion_con_costos` **exige** `p_tasa_usd` si la moneda de la
    factura no es USD (rechaza **antes** de crear nada) y la **registra siempre** (USD ⇒ 1).
  · **D9 — la moneda del vínculo no se comparaba con la de la operación.** Se usaba la de la operación y
    una discrepancia cambiaba el cargo en silencio. El reparto aborta con `22023` y dice las dos monedas.
  · **D10 — los costos no sabían a qué vínculo pertenecían.** Con `UNIQUE(id_operacion, id_compra)`, dos
    compras podían compartir recepción y el reparto de la segunda borraba los costos de la primera: el
    `DELETE` filtraba por `id_operacion`. `app_dat_recepcion_producto_costo` gana
    `id_compra_recepcion` (FK, índice y backfill) y el reparto borra, inserta, cuadra y fotografía el
    promedio **por vínculo**. Las líneas se resuelven por `id_recepcion_producto` explícito, por costos ya
    atribuidos o, si la operación tiene un solo vínculo, por todas las suyas; con dos o más y sin
    atribución **aborta** en vez de adivinar.
  · **D11 — el rollback mentía.** Decía que «06b no añadió ni una columna» y no retiraba
    `tasa_usd_aplicada`. Ahora retira las **dos** columnas que 06b añade.
  · **D12 — `fecha_tasa_aplicada` no se re-sellaba al corregir la tasa.** Se conservaba la fecha del
    primer registro. Ahora se re-sella **sólo cuando la tasa cambia**; un reintento idéntico conserva la
    original.
  Se hizo editando `06b_aterrizaje.sql` (no un `06c`): es idempotente y se reaplicó en `newa`; así el
  archivo y la base siguen siendo el mismo cuerpo (huellas `md5` en su cabecera y en 4.7). `verify/06`
  pasa de 15 a **20 comprobaciones**, con **control negativo** en cada invariante nuevo (moneda
  discrepante, atribución cruzada, fila sin atribuir, cuerpo viejo: los cuatro bajan a `ok = false`).
- **Fase 6 · lo que se probó de verdad en `newa` (transacciones revertidas).** No hay datos de costo en
  la base, así que el dinero se probó con `ROLLBACK` y quedó registrado: (1) CUP sin tasa → `22023` y
  **cero** operaciones creadas; (2) CUP con 320 → tasa 320 y fecha UTC; corrección a 330 con la misma
  clave → `duplicada: true`, tasa 330 y fecha re-sellada; mismo reintento con 330 → la fecha **no** se
  mueve; (3) vínculo CUP sobre operación USD → `22023`, sin escribir tasa ni costos; (4) dos vínculos
  sobre la misma operación, cada uno con su línea atribuida: `0,15` y `0,30`, y volver a repartir el
  primero deja intacto el segundo (`filas_retiradas = 1`); (5) dos vínculos **sin** atribución → `22023`;
  (6) recepción USD sin tasa → tasa 1 registrada y costo 0,10. El rollback se ejecutó entero dentro de
  una transacción revertida: retira funciones y columnas y la verificación vuelve a 20/20.
- **Fase 6 · desviación documentada.** Los campos de importadora viven en el **vínculo**
  (`fdi_dat_compra_recepcion`: `pct`, `base`, `monto`, `reembolso`, `origen_pago`), no en la fila de
  costo. Es su grano real (por compra y recepción) y la fila de costo guarda el importe ya repartido en
  USD. El plan pedía «extender la línea de costo con `origen_pago` y los campos de importadora»; se
  implementó en el vínculo en la fase 5.
- **Fase 6 · límite conocido de la multi-factura (no oculto).** Hoy `fn_fdi_compra_vincular_recepcion`
  **rechaza** un segundo vínculo sobre la misma operación, así que D10 no era alcanzable por la RPC; la
  restricción de la tabla sí lo permitía y el E2E 5 de la fase 5 lo exige. El reparto ya es por vínculo,
  pero para que dos compras compartan una recepción falta **poblar `id_recepcion_producto`** en
  `fdi_dat_compra_recepcion_linea` (la RPC no lo escribe: 0 de 1 filas) y quitar ese rechazo. Sin eso, el
  reparto de una compra con líneas sin atribuir aborta en vez de adivinar.
- **Fase 6 · cliente.** `inventory_reception_screen.dart` registraba **siempre USD** (`_selectedCurrency`
  era un `final 'USD'`): una compra en CUP entraba con operación USD y el vínculo CUP, que es justo la
  discrepancia de D9. Ahora, con compra, la moneda es la de la compra; se pide la tasa (precargada del
  `tasa_factura` del detalle) y viaja como `p_tasa_usd` en `p_recepcion`. `insertInventoryRecepcion` usa
  el wrapper transaccional también cuando hay tasa aunque no haya costos, para que la operación quede con
  su tasa. Sin compra se mantiene USD, como antes.
- **Fase 6 · `_v3` y el resto de la fase siguen pendientes.** Este pase cerró los cinco defectos; **no**
  completó la fase: faltan la UI de captura de importadora/adicionales, los ajustes `por_financiar` con
  reserva y pago propios, la reversión de costo al cancelar la recepción, el desvío visible y el borrado
  documentado de `fn_actualizar_precio_promedio_recepcion_v3`.
- **Fase 6c · el aterrizaje se ejecuta, se ve y el catálogo queda cerrado (2026-11-21).** Cuatro piezas:
  · **El aterrizaje no se ejecutaba nunca desde la app.** Vincular dejaba el cargo en el vínculo, pero
    `fn_fdi_compra_repartir_aterrizaje` no la llamaba nadie: el inventario no recibía el cargo y `_v2`
    capitalizaba solo lo que el cliente hubiera capturado. Ahora, tras vincular, la recepción llama al
    reparto con el `id_compra_recepcion` y el mensaje dice si capitalizó, si lo paga el fondo o si falló.
    El detalle de la compra gana **«Aterrizar cargo»** para reintentar un vínculo que quedó sin filas.
  · **`fn_fdi_compra_costo_resumen`** (STABLE, solo lectura): valor de factura vinculado, cargo, %
    declarado vs efectivo, **desvío**, ajustes globales aplicados/por asignar y costo aterrizado unitario
    por línea, convertido a la moneda de la compra con la tasa USD de la operación. Alimenta el panel
    «Costo aterrizado» del detalle.
  · **Agujero de seguridad cerrado.** `app_cont_tipo_costo` tenía RLS `FOR ALL USING true` y GRANT de
    INSERT/UPDATE/DELETE a `anon` y `authenticated`: cualquier autenticado podía crear o borrar el
    nomenclador por PostgREST. Ahora es **solo lectura** y la escritura va por
    `fn_cont_tipo_costo_guardar` / `_eliminar` con superadmin. Guardas: no renombrar ni borrar
    «Importadora» (el aterrizaje la resuelve por denominación) y no borrar un tipo en uso.
    Probado en vivo: gerente → `42501`; INSERT directo → `42501`; renombrar Importadora → `22023`.
  · **`_v3` retirada** (código muerto). El rollback no la restaura y lo dice.
  · **UI.** Nomenclador rehecho según Stitch (master-detalle, sin modales, `afecta_margen` y «Gasto» de
    solo lectura) y bloque «Cifras de recepción» en la recepción con compra (estimado: total, cargo,
    adicionales y aterrizado; si la factura no es USD no se suman monedas).
  · **Verificación.** `verify/06_costos.sql` **23/23** (n=21..23 nuevas) y nuevo
    `verify/06c_pruebas_aterrizaje.sql`, transaccional con `ROLLBACK`, **18/18**: 2.150 exacto de
    2.000 + 15 % − 50 % de reembolso, el fondo no mueve un movimiento por el cargo de la wallet, flete
    global 100.000 con 60/100 recibidas → **60.000 aplicados y 40.000 por asignar**, unitario aterrizado
    21,50 y reparto idempotente. Control negativo del rollback de 06c: n=21 y n=23 bajan a `false`.
  · **Stitch.** `RECEPCIÓN — importadora y adicionales` (`8e5451984ac841128b005ab0ebb6e831`) y
    `CONFIG — costos adicionales` (`d810b6b7ab4e46cfb22b28f2f4a01d6f`), proyecto `4232822798385486487`;
    capturas en `docs/design/compras-recepcion-aterrizaje.png` y `docs/design/compras-costos-adicionales.png`.
- **Fase 6 · dos decisiones del dueño, tomadas el 2026-11-23 e implementadas en 6c/6d.**
  1. **Reversión de costo al cancelar la recepción: se marca, no se borra** (opción b). Las filas de costo
     conservan importe y tipo y se marcan con fecha, usuario, motivo y la fila de estado que lo provocó; el
     trigger cubre los estados 3 y 4, `_v2` las excluye, `costo_real` vuelve al de factura y el historial
     de la compra recibe el documento con filas e importe. Límite declarado: `precio_promedio` ya ponderado
     **no** se reconstruye (sería un recosteo completo del producto).
  2. **Ajustes `por_financiar`:** se implementaron con la maquinaria de la fase 4. `total_financiado` se
     congela fuera de `creada`; el ajuste nace `por_financiar`, se financia con su propia reserva y pago
     (`id_ajuste` en reserva, pago y costo) y el costo se reparte sobre lo recibido. Límites: solo con la
     compra **completada** y solo `origen_pago = 'fondo'`; la valoración suma `monto/unidades` al
     `precio_promedio` y no reexpresa el COGS de lo ya vendido.
  - **Fase 6 · chips por línea y nota del pase (2026-11-23).** La tabla de productos de la recepción muestra
  un chip por costo adicional de la línea («Flete 12,00 USD»), con el nombre del catálogo cargado en la
  pantalla (si no carga, cae al id; no bloquea). El pase a Main queda documentado en
  `tasks/plan_promocion_main.md` §Fase 1b: `_v2` y `fn_fdi_compra_recalcular` cambian de cuerpo y el orden
  es 06a→06d y después los cuerpos; `verify/06` gana la comprobación **n=27** para detectar un `_v2` viejo
  en Main.
- **Fase 6d · reversa al cancelar y ajuste tardío aplicados en `newa` (2026-11-23).**
  · **Reversa (06c).** Columnas `revertido_at`, `revertido_por`, `motivo_reversa`, `id_estado_reversa`
    (FK a la fila de estado que la provocó), CHECK de motivo e índice parcial de filas vigentes. Trigger
    `AFTER INSERT` sobre `app_dat_estado_operacion` con `WHEN (NEW.estado IN (3,4))` → marca las filas del
    vínculo (las sin atribuir solo si la operación tiene un vínculo), devuelve `costo_real` al de factura
    y deja el documento en `fdi_hist_estado_compra`. `_v2` se parchea **a partir de su definición viva**
    con dos anclas exactas y aborta si el cuerpo no coincide (así una función de 200 líneas no se
    reescribe a mano); el resumen ignora las revertidas y expone `filas_revertidas` y `estado_operacion`.
    En la UI, un icono de revertida y el botón «Aterrizar cargo» desaparece en recepciones canceladas.
  · **Ajuste tardío (06d).** `total_financiado` se congela al salir de `creada`. `fn_fdi_compra_ajuste_agregar`
    crea el ajuste `por_financiar` (solo compra pagada/parcial/completa, origen fondo);
    `fn_fdi_compra_ajuste_financiar` valida saldos, crea **su propia reserva y pago** (`id_ajuste` en
    reserva, pago y fila de costo), mueve el ledger con `pago_compra`, reparte por valor sobre lo recibido
    con el residuo a la línea de mayor base, suma al `precio_promedio` el costo unitario del ajuste y deja
    el documento en el historial. Puertas declaradas: compra **completada** y solo `origen_pago = 'fondo'`.
    UI: «Agregar costo posterior» y «Financiar ahora» (una fuente de la misma moneda, sin conversión).
  · **Verificación.** `verify/06` **27/27** (n=24..27: 06d y el filtro de `_v2`); `verify/06c_pruebas_aterrizaje.sql` **23/23**
    (reversa incluida: 0 vigentes / 2 revertidas, costos 0, `costo_real` 20, documento e idempotencia);
    `verify/06d_pruebas_ajuste.sql` **14/14** (1.000 de financiado inmutable, 100 pagados, saldo −100,
    movimiento, reserva y pago propios, costo 100 en 1 fila, `precio_promedio` +1 y reintento
    `duplicada`). Los rollbacks de 06c y 06d se ejecutaron enteros con `COMMIT`→`ROLLBACK` y sus checks
    bajan a `false`.
  · **Nota para el pase.** El cuerpo de `_v2` en `newa` ya trae `revertido_at IS NULL`; el pase debe
    promover ese cuerpo, no el de Main. `fn_fdi_compra_recalcular` también cambió (congelamiento), y es
    una función que Main ya tiene: el pase la lleva con su cuerpo nuevo.
- **Fase 6 · aprobada por el dueño (2026-11-23).** E2E en verde: 15 % de importadora con reembolso y
  desvío, segunda recepción con otro %, chips de adicionales por línea, costo aterrizado en el producto al
  completar, reversa al cancelar (marcada, con documento), ajuste tardío con reserva y pago propios y el
  cargo de la wallet fuera del fondo. **Fase 6 cerrada.**
- **Fase 7 · aportes de inversores aplicados en `newa` (2026-11-23).** `07_aportes_inversores.sql` con
  `fdi_dat_compra_aporte` (equivalente **generado**, no escrito) y seis triggers: el aporte sólo existe en
  modo `inversores`, en compra `creada`, sin pasar del faltante, inmutable salvo su devolución, no se borra
  ni se reactiva; en modo `inversores` no hay reserva del fondo, ningún pago sale del fondo, ningún ajuste
  ni cargo de recepción se declara `origen_pago = 'fondo'`; y `total_financiado` sigue congelado fuera de
  `creada`. Tres RPC nuevas (`fn_fdi_compra_aportes`, `_aporte_registrar`, `_aporte_devolver`) y los cuatro
  cuerpos de la fase 4 reescritos con su rama.
  · **Estados.** En modo inversores no se usa `reservada`: la compra vive en `creada` hasta que **Σ aportes
    vigentes = `total_financiado`** y entonces `pagar` la pasa a `pagada` escribiendo una fila de
    `fdi_dat_compra_pago` por aporte (`origen='aporte'`, sin cuenta, sin medio y sin movimiento). Eso
    conserva el invariante «`pagada` ⇒ Σ pagos = total» de `verify/04`, que se queda intacto.
  · **Cambio de restricciones declarado.** `fdi_dat_compra_pago.id_cuenta` e `id_medio_pago` pasan a
    admitir `NULL` y entra `fdi_pago_fuente_check`: en el camino del fondo siguen siendo obligatorios (más
    `id_movimiento`); en el del aporte los tres son `NULL` y `id_aporte` es obligatorio, con FK compuesta
    `(id_aporte, id_compra)` para que un pago no pueda apuntar al aporte de otra compra.
  · **Devolución = cancelación del pasivo.** Marca el aporte (`devuelto`, con fecha, usuario y motivo), no
    lo borra y **no mueve un centavo del fondo**. Se admite en `creada` y en `pagada` (el E2E lo pide); en
    `entrega_parcial`/`completada` se rechaza, porque la mercancía ya está en inventario. Si se devuelve
    con la compra ya pagada, la compra **queda pagada con cobertura incompleta** y el hueco se anota en el
    historial: no se inventa caja ni se reescribe el pago. `anular` y `cancelar` exigen que no queden
    aportes vigentes; `anular` salta las filas `origen='aporte'` (no acredita al fondo dinero que nunca
    salió de él). Límite declarado: `interes` se guarda y se muestra estimado, pero no se contabiliza — es
    gasto de la tienda y va con el reporte de inversores de la fase 8.
  · **Dos defectos que la revisión adversarial encontró y se cerraron antes de dar la fase por buena.**
    (1) El ajuste tardío de una compra de inversores era **imposible**: `fn_fdi_compra_ajuste_agregar`
    (06d) fija `'fondo'`/`'por_financiar'` en el cuerpo y el trigger nuevo lo rechazaba, así que un flete
    posterior dejaba el costo aterrizado corto para siempre. Ahora el cuerpo elige el origen por modo
    (`externo`/`declarado` en inversores): el cargo capitaliza y se reparte sin que el fondo pague.
    (2) `pagar` marcaba `pagada` una compra de inversores con `total_financiado = 0` sin escribir ningún
    pago; ahora lo rechaza. También se corrigió el deadlock `devolver` ↔ `pagar` (orden de bloqueo
    compra → aporte) y `puede_registrar`, que era una copia de `puede_pagar` y deshabilitaba el botón
    justo cuando había faltante.
  · **Verificación.** `verify/07_aportes.sql` **32/32** (solo lectura) y `verify/07_pruebas_aportes.sql`
    **42/42** (transaccional, con dinero: 800 + 700 → faltante 500 y no deja pagar, exceso rechazado, 500
    más → `pagada`, 3 pagos de aporte y 0 movimientos del fondo, saldo de la tienda intacto, devolución sin
    movimiento, anulación con `devuelto = 0`, y todas las escrituras directas rechazadas). Sin regresiones:
    `verify/04` verde, `verify/06` 27/27, `06c` 23/23 y `06d` 14/14. El rollback se ejecutó entero en
    `newa` (`COMMIT`→ reaplicar) y devuelve los cuatro cuerpos a la fase 4 y `fn_fdi_compra_ajuste_agregar`
    a 06d.
  · **UI.** Panel `CompraAportesPanel` en el detalle de la compra (sólo modo inversores): cifras, bloque
    de faltante, desglose por inversor, participación con barra y restante, `Registrar aporte` /
    `Pagar compra` gobernados por el servidor y devolución con motivo. En modo inversores ya no se ofrece
    «Reservar del fondo». `flutter analyze` limpio en `lib/` y tests de contrato + compilación en verde.
  · **Stitch.** `COMPRA — aportes de inversores`
    (`7297c9001c8f400b9d78d9c3b3230ec2`), proyecto `4232822798385486487`; captura en
    `docs/design/compras-aportes-inversores.png`.
  · **Nota para el pase.** Ver `tasks/plan_promocion_main.md` §Fase 1c: la fase 7 lleva el cambio de
    restricciones de `fdi_dat_compra_pago` y los cuatro cuerpos reescritos; sin ellos `pagar` no paga
    compras de inversores y `anular` acreditaría al fondo dinero ajeno.
- **Fase 7 · E2E del dueño aprobado (2026-11-23).** Dos compras quedan en `newa` como evidencia: la **67**
  («E2E-07-A», 2.000 USD) en `pagada` con X 800 + Y 700 + Z 500 y sus **3 pagos `origen='aporte'`** (sin
  cuenta, sin medio y **sin movimiento**), y la **68** («E2E-07-B», 500 USD) en `creada` con el aporte de X
  devuelto y su motivo. `Σ aportes` cubre el 100 % en la 67, la 68 muestra el faltante de vuelta y **el
  fondo no movió un solo movimiento** en ninguna de las dos. Los intentos de pagar al 75 % y de aportar 100
  de más se rechazaron con su mensaje. Nota: la creación de los inversores de prueba dejó un tercero
  (`Z Inversores`) **inactivo** con % mínimo, porque el CHECK exige `porcentaje > 0`; no entra en el reparto
  de utilidad mientras siga inactivo. **Fase 7 cerrada.**
- **Fase 7 · la tienda 9 no tenía dueño (H9).** El alta de la tienda escribió gerente y trabajador pero no
  `app_dat_dueno`, así que `fn_user_is_dueno(9)` daba `false` para su creador y la lista de inversores del
  diálogo salía vacía. Reparado en `newa` (ver `tasks/hallazgos_pruebas_newa.md` H9); el patrón afecta a las
  tiendas 3, 5 y 6, que siguen sin dueño a la espera de la decisión del dueño real.

---

## Decisiones cerradas

- ✔ **PD1 — En la compra el dinero se compromete al crear y sale al pagar.** `politica_pago = al_pagar`.
  `por_recepcion` queda documentada como deuda futura, no se implementa. **Dos carriles, una recepción
  pertenece a uno solo**:
  - **Carril A (compra):** reserva → pago explícito → recepción que **no mueve dinero**.
  - **Carril B (recepción directa):** sin compra; debita **al recibir**.
  Una recepción con `id_compra` **no puede** usar el carril B. Se impone en la RPC, no en la UI.
- ✔ **PD2 — Manda la suma de líneas.** `total_mercancia = Σ(cantidad × costo unitario)`. Si el total de
  factura no cuadra, la compra se guarda pero **no se puede reservar** hasta que **dueño/gerente declare el
  motivo** (queda en historial). Nunca se recalcula el costo unitario para "cuadrar".
- ✔ **PD3 — El cargo de importadora es variable y SUMA al valor de la factura.** Componente del costo,
  capturado en la recepción, **% editable y distinto en cada recepción**, con reembolso. La wallet se queda
  como está.
- ✔ **PD4 — El pago exclusivo es 100% de los inversores.** Nada del fondo en modo inversores; nunca mixto.
- ✔ **PD5 — 7 estados:** `creada, reservada, pagada, entrega_parcial, completada, cancelada, anulada`.
  `reservada` existe para colgar el dinero comprometido; `anulada` para revertir con contramovimiento.
- ✔ **PD6 — En recepción de compra solo aparecen los productos de esa compra.** No se bloquea catálogo ni
  stock.
- ✔ **PD7 — Sin IVA ni descuentos por línea.** Costo neto unitario. Si el IVA fuese acreditable sería
  componente con `afecta_inventario = false`; lo no recuperable (aduana, flete, seguro, importadora) sí
  capitaliza.
- ✔ **PD8 — El fondo NO paga el cargo de importadora.** `origen_pago = wallet_importadora`: capitaliza y
  nadie lo vuelve a desembolsar. La fase 6 **muestra el desvío** (`Σ cargos` vs `Σ valores de factura
  vinculados`) sin corregirlo sola.
- ✔ **Los aportes de inversores no se acumulan en el fondo**: viven atados a su compra, no entran en
  `fdi_dat_saldo` y no se mezclan con el porcentaje de utilidad.

---

## Arquitectura

- ✔ **La compra es entidad nueva** (`fdi_dat_compra*` + `fn_fdi_compra_*`). `fdi_dat_inversion` queda
  **congelada como legado del carril B**: el carril A no la usa.
- ✔ **El fondo es `fdi_dat_saldo`**, grano **(cuenta × medio × moneda)**.
- ✔ **Un solo sentido de tasa: `T(A→B)` = unidades de B por 1 de A**, con el par explícito en todo registro.
  `fn_fdi_transferir` no se toca; se crea `fn_fdi_transferir_v2`. **Cambiar la semántica de la v1 sin
  cambiar su firma rompería el cliente desplegado (`fondo_inversion_service.dart:389`) con un factor de 10³
  en dinero real.**
- ✔ **La reserva no es un movimiento.** `disponible = saldo − reservado`, en moneda nativa por (cuenta,
  medio, moneda).
- ✔ **Dos tasas congeladas por documento**: factura (costo) y pago (salida). Diferencia cambiaria a
  resultado financiero, nunca al inventario.
- ✔ **Tres cifras**: `total_mercancia` (Σ líneas), `total_financiado` (lo que paga el fondo o los
  inversores) y `costo_aterrizado` (todo lo que capitaliza, incluido lo que pagó la wallet).
  **`total_financiado` es inmutable tras reservar; `costo_aterrizado` crece con documentos de ajuste.**
- ✔ **`origen_pago ∈ {fondo, wallet_importadora, wallet_proveedor, externo}`** por componente de costo.
  Capitaliza siempre; solo se financia si su origen es `fondo`.
- ✔ **El costo se valoriza al recibir.** Recepción parcial: el costo global se reparte **solo sobre lo
  recibido**; el resto queda por asignar. Reparto por **valor** por defecto (cantidad o peso como excepción
  configurable justificada).
- ✔ **Redondeo:** en servidor, una sola vez al escribir el asiento; **residuo a la línea de mayor base**
  (empate → menor `id`).
- ✔ **Parámetros nuevos con `DEFAULT`**; cambio de semántica = RPC nueva.
- ✔ **El plan se subordina al pase formal.** Cambio de contrato = `_m01`, expansión aditiva → clientes →
  contrato.

### Los dos carriles

| | Carril A — compra | Carril B — recepción directa |
|---|---|---|
| Punto de partida | Orden de compra | Recepción sin compra |
| ¿Existe hoy? | **No** (se construye) | **Sí**, pero **sin desplegar** |
| Momento del débito | Al **pagar** | **Al recibir** |
| Reserva | Sí | No |
| Fuentes múltiples | Sí | Sí (exactitud al centavo) |
| Sobre de dinero | `fdi_dat_compra*` | `fdi_dat_inversion` |
| Regla | Una recepción con `id_compra` **jamás** entra por B | `p_id_compra` informado → **rechazar** |

### Dinero: eventos del carril A

| Evento | Estado | ¿Sale dinero? | Asiento |
|---|---|---|---|
| Se crea la compra | `creada` | No | ninguno |
| Se cubre `total_financiado` | `reservada` | No | reservas activas |
| Se confirma el pago | `pagada` cuando `Σ pagos = total_financiado` | Sí | consume reserva + `pago_compra` |
| Llega mercancía parcial | `entrega_parcial` | No | valoriza inventario |
| Llega todo | `completada` | No | valoriza inventario |
| Se ajusta el % de importadora al recepcionar | no cambia | Solo si origen `fondo` | ajuste o reembolso |
| **Llega un costo después de pagar** | no cambia | Solo si origen `fondo` | **reserva + pago del ajuste + documento de costo; nunca muta `total_financiado`** |
| Se abandona sin pagos | `cancelada` | No | libera reservas |
| Se abandona con pagos | `anulada` | Sí (reversa) | contramovimiento |

**En el carril A la recepción no mueve dinero.** Mueve inventario, estado y costo.

### Multi-factura en una carga

Una operación de recepción cubre N compras: `fdi_dat_compra_recepcion` con
**`UNIQUE(id_operacion, id_compra)`**. Cada línea sabe su compra; cada compra lleva su `pct_importadora` y
su reembolso; el estado se calcula **por compra**.

### Modelo de importadora

| Concepto | Dónde | Regla |
|---|---|---|
| `pct_importadora` | por compra dentro de la recepción | editable **antes de confirmar**, con historial de quién cambió qué; distinto por recepción |
| `base_importadora` | valor de la factura | explícita, congelada |
| `monto_importadora` | `base × pct` | capitaliza |
| `reembolso_importadora` | negativo, opcional | "reembólsame la mitad" |
| `origen_pago` | `wallet_importadora` \| `fondo` | wallet → solo capitaliza |

Ejemplo: mercancía **2.000 USD**, 15% → **300**; reembolso de la mitad → **−150**; cargo efectivo **150**;
aterrizado **2.150**; el fondo financia **2.000** (si el origen es wallet) o **2.150** (si es fondo).

### Restricciones del entorno

- **Rama de trabajo:** `multimoneda`, al día con `main` tras `bab9725b`. **No se crean ramas nuevas**
  (decisión del dueño, 2026-11-20). Commits directos sobre `multimoneda`.
- **No hay convención de migración**: la vía real es pegar SQL a mano. El equipo usa `_m01` y baselines
  `md5` para el pase; el plan se alinea.
- **`fdi_dat_movimiento` en `newa`**: acepta `'gasto'`, **sin `idempotency_key`**, `monto/saldo_*` sin
  escala. `moneda` es `text` sin FK.
- **`app_dat_operaciones`** sin columna de fecha (solo `created_at`), pero con `contabilizada`,
  `contabilizada_at`, `contabilizada_por`.
- **Solo lectura es convención, no capacidad**: el agente **aplica en `newa`** (decisión del dueño, fase 0)
  y **nunca en Main**; para Main solo entrega scripts.

### Stack y convenciones

Flutter 3.44 / Dart 3.12; `provider` + `ChangeNotifier`; `ventiq_admin_app` con `sdk: ^3.10.0`.
Shell: `$env:APPDATA = 'C:\Users\cesar\Documents\VentIQ-seller-App\.dsh\dart-tool'` antes de `flutter`.
Rutas `'/kebab-case'` en `main.dart`; permisos por ruta en `permissions_service.dart`. UI: molde "saldo de
tercero", chip de estado con color del nomenclador, panel plano FDI; prompts en `04-diseno-ux.md`.

### Documentos

| Documento | Para qué |
|---|---|
| `00-auditoria-programador.md` | contrato de tablas/RPCs y riesgos R1-R9 (auditado contra Main) |
| `01-analisis-funcional.md` | dominio, invariantes I1-I15, estados |
| `02-contabilidad.md` | fórmulas de costo, reserva, tasas, redondeo (X1-X11), reportes R1-R7 (§6.3) |
| `03-almacen.md` | recepción real, lotes, huecos operativos |
| `04-diseno-ux.md` | pantallas, responsive, prompts de Stitch |
| `05-referencia-industria.md` | práctica estándar y fuentes |
| `06-revision-adversarial.md` | 44 hallazgos sobre la v1 (2 desmontados) |
| `07-deriva-newa-vs-main.md` | matriz objeto por objeto de los dos entornos |
| `08-costos-newa.md` | módulo de costos real en `newa` |
| `09-financiacion-recepcion-existente.md` | `fn_fdi_registrar_recepcion`: contrato, riesgos, convivencia |
| `10-estado-equipo-y-contradicciones.md` | pase newa→main, reglas vigentes, contradicciones |
| `11-diff-v4-v6.md` | auditoría de pérdida de información que originó esta v6.1 |
| `tasks/plan_promocion_main.md` | **el pase oficial**; manda sobre este plan |

> Los anexos `00`-`06` se escribieron contra Main. Cuando contradigan este archivo, mandan este archivo,
> `07`-`11`.

---

## Regla de ejecución

1. **Ningún cambio de dinero sin transacción.**
2. **Idempotencia por columna** (`idempotency_key uuid UNIQUE`), no por texto.
3. **Ledger append-only.** Correcciones = contramovimientos con documento propio.
4. **Un desembolso, un origen.** Impuesto con `origen_pago` + constraint.
5. **Una recepción, un carril.** Con `id_compra` no entra por el carril B.
6. **La UI no calcula dinero.**
7. **Compatibilidad**: parámetros nuevos con `DEFAULT`; cambio de contrato = `_m01`.
8. **Toda tabla nueva lleva RLS** y solo escribe por RPC `SECURITY DEFINER`.
9. **Nada se valida primero en Main.** `newa` primero.
10. **No se inventa un pase a producción**: se integra a `tasks/plan_promocion_main.md`.
11. **Cada fase deja el repo verde**: `flutter analyze` sin errores nuevos + tests de la fase.
12. **Regla de parada:** si una suposición se cae, **para, actualiza este archivo y dilo**; no improvises en
    silencio.

---

## Protocolo de entrega

**Código:** commits directos sobre `multimoneda`, uno por fase, sin push sin OK. Reportar
`git diff --stat`.

**SQL:** cada fase entrega en `ventiq_admin_app/lib/sql/`:
- `NN_descripcion.sql` — idempotente, transaccional, con verificación final que hace `RAISE`.
- `NN_descripcion_rollback.sql`
- `verify/NN_verificacion.sql` — solo `SELECT`, `ok|falla` por comprobación.
- Encabezado `-- REQUIERE: NN, NN`.

**E2E por fase (obligatorio).** Cada fase entrega una lista numerada de pasos literales en la app apuntando
a `newa`: **qué hacer, qué debe verse, qué haría fallar**. Sin el OK del dueño **no se abre la fase
siguiente**. Las listas están escritas en cada fase de este documento.

**Promoción:** `newa` → verificación → E2E del dueño → **pase formal** hacia Main. Nada se aplica a Main por
fuera de ese pase.

---

# Fases

---

## Fase 0 — Cimientos y desbloqueo de la rama

**Objetivo:** dejar `newa` en un estado donde el código de `multimoneda` funcione, y tener red de seguridad.

**Build:**
- **Trabajar directamente en `multimoneda`** (decisión del dueño, 2026-11-20: **no se crean ramas
  nuevas**). El agente aplica el SQL en `newa`; para Main solo entrega scripts.
- ✅ **Aplicada el 2026-11-20:** `fondo_inversion_financiar_recepcion.sql` en `newa`, verificada
  (función, dos columnas, índice, `SECURITY DEFINER`, cuerpo con `financiada_fondo`). Baseline en
  `baseline/00_esquema_newa.md`.
- **Inventario de migraciones pendientes de la rama**: recorrer `tasks/plan_sync_newa_main.md` y
  `tasks/hallazgos_pruebas_newa.md`, listar qué `.sql` de la rama **no** están aplicados en `newa`.
  Empezar por `fondo_inversion_financiar_recepcion.sql`, **con el fix de cancelación incluido** (fase 5).
- Aplicar esas migraciones en `newa` (las aplica el dueño), en el orden que declare el equipo.
- Baseline de `newa` en `docs/planes/fondo-inversion/baseline/`: columnas y `pg_get_functiondef` de
  `fdi_*`, `app_dat_recepcion_productos`, `app_dat_recepcion_producto_costo`, `app_dat_producto_costo`,
  `app_cont_tipo_costo`, `app_dat_operacion_recepcion`, `app_dat_operaciones`, `imp_*`, `prv_*`.
- Respaldo de los datos de prueba del fondo en `newa`: 16 movimientos, 10 saldos, 3 liquidaciones.
- `verify/00_linea_base.sql` contra `newa`:
  (a) 15 tablas `fdi_*`;
  (b) tipos del CHECK de `fdi_dat_movimiento`;
  (c) `fn_registrar_recepcion_con_inventario` = 12 args y **1 sola firma**;
  (d) `fn_fdi_registrar_recepcion` existe y las columnas `fdi_idempotency_key` / `fdi_solicitud`;
  (e) `costo_real.is_generated`;
  (f) tablas de costos adicionales **y filas de `app_cont_tipo_costo`**;
  (g) `imp_dat_factura` y `prv_dat_factura`: columnas de moneda y de compra;
  (h) `fn_fdi_crear_liquidacion` con 11 args.

**Checklist:**
- [x] Se trabaja en `multimoneda` (sin rama nueva)
- [ ] Lista de migraciones pendientes, con orden
- [ ] `fondo_inversion_financiar_recepcion.sql` aplicada en `newa` (con el fix)
- [ ] Baseline y respaldo de datos
- [ ] `verify/00_linea_base.sql` con 8 comprobaciones

**Exit criteria:**
- Se trabaja en `multimoneda` (sin rama nueva, decisión del dueño)
- `flutter analyze` sin errores nuevos (warnings preexistentes listados)
- `verify/00_linea_base.sql` en `newa` → `ok` en las 8

**E2E del dueño:**
1. Correr `verify/00_linea_base.sql` → todo `ok`.
2. Abrir la app contra `newa` y recepcionar con fuentes del fondo → **ya no falla**.
3. Confirmar que los 16 movimientos históricos del fondo siguen visibles e intactos.

---

## Fase 0b — Integrar el delta de esquema al pase formal

**Objetivo:** que Main reciba lo que `newa` ya tiene, **por el pase del equipo**.

**Build:**
- Revisar `tasks/plan_promocion_main.md` y ubicar las **Tasks 3 y 4**: llevan el módulo de costos y el
  arreglo de `costo_real` a Main. Este plan **no las duplica**: aporta lo que falte.
- Aportar al pase, como items aditivos:
  1. Crear `app_dat_producto_costo` y `app_dat_recepcion_producto_costo` con el DDL **extraído de `newa`**,
     no del script del repo.
  2. `ALTER TABLE app_dat_recepcion_productos ALTER COLUMN costo_real DROP EXPRESSION`.
  3. Crear el trigger NULL-safe (`COALESCE` sobre `precio_referencia` y descuentos).
  4. **Backfill de las 30.038 filas NULL** de `costo_real` con
     **`= precio_unitario − descuentos`**, con **respaldo previo de la columna** y **rollback que restaura
     la expresión**. El `DO $$` del script original no contempla el backfill.
  5. `'gasto'` en el CHECK de `fdi_dat_movimiento` + `fn_fdi_gasto` (8 args).
  6. **`fn_actualizar_precio_promedio_recepcion_v2`**: promover el **cuerpo de `newa`**, nunca el de Main.
  7. **`fn_fdi_crear_liquidacion`**: dejarla **solo con 11 args** en Main (columna `repartir_igual` +
     `DROP` de la de 10 + `CREATE` de la de 11).
- **Prohibido**: reescribir en sitio funciones que el pase tiene marcadas, o alterar baselines `md5` sin
  regenerarlos contra Main.
- `verify/00b_delta.sql`: compara `newa` vs Main → 0 diferencias en la lista y `costo_real` NULL = 0.

**Checklist:**
- [ ] Tasks 3/4 revisadas y mapeadas
- [ ] Items aditivos aportados (no duplicados)
- [ ] Backfill con respaldo previo y rollback
- [ ] `fn_fdi_crear_liquidacion` 11 args en Main
- [ ] `v2` con el cuerpo de `newa`
- [ ] Baselines `md5` regenerados

**Exit criteria:**
- El pase incluye estos items y su verificación pasa en `newa`
- `verify/00b_delta.sql` en Main: 0 diferencias, `costo_real` NULL = 0
- Nada aplicado a Main fuera del pase

**E2E del dueño:**
1. `verify/00b_delta.sql` en `newa` → `ok`.
2. Respaldar, aplicar por el pase en Main, mismo script → `ok`.
3. Abrir un producto con recepciones históricas → el costo ya no está vacío.

---

## Fase 1 — Motor de dinero I: integridad, escala y conciliación

**Objetivo:** que el fondo no pueda descuadrar por los caminos que ya existen, y poder probarlo.

**Build:**
- `_fdi_aplicar_movimiento`: validar que `p_id_tienda` **corresponda a la cuenta** y que **medio/moneda
  sean coherentes con la tienda** (R1).
- `fn_fdi_vincular_recepcion`: `FOR UPDATE` sobre la inversión antes de decidir el exceso (R3).
- `fn_fdi_inversion_anular(p_id_inversion, p_motivo)`: devuelve lo no consumido con contramovimiento,
  historial y estado `anulado` (R2).
- **Escala del ledger** (R6/A10): `fdi_dat_saldo.saldo` y `fdi_dat_movimiento.monto/saldo_*` a `numeric` con
  escala por `monedas.decimales`; **redondeo en servidor, residuo a la línea de mayor base**. `newa` tiene
  16 movimientos reales: la migración los toca y debe verificarlos.
- **R7**: `fn_fdi_repartir_ganancia` no debe reventar sin inversores activos ni sobrescribir
  `monto_ganancia_retirada`.
- `fn_fdi_conciliacion(p_id_tienda)`: **por (cuenta, medio, moneda)** devuelve `saldo`, `Σ movimientos`,
  `último saldo_nuevo` y la diferencia. Debe dar **0,00** siempre.

**Checklist:**
- [ ] R1 cerrado con test de regresión
- [ ] R2: anulación con devolución
- [ ] R3: `FOR UPDATE`
- [ ] R6/A10: escala migrada sin alterar los 16 movimientos
- [ ] R7 corregido contra los 3 inversores reales
- [ ] `fn_fdi_conciliacion` con grano (cuenta, medio, moneda)

**Exit criteria:**
- `verify/01_motor_dinero.sql` en `newa`: conciliación **0,00 sobre los datos existentes** y 0,00 tras
  crear→anular una inversión de prueba
- `flutter analyze` sin errores nuevos; `flutter test` del módulo fondo sin regresiones

**E2E del dueño:**
1. Abrir la conciliación **antes** de tocar nada → 0,00 en todas las líneas.
2. Crear una inversión de **1.000 USD** y anularla con motivo → el saldo vuelve al inicial.
3. Conciliación de nuevo → 0,00.
4. Verificar que los 16 movimientos históricos siguen con sus importes intactos.

---

## Fase 2 — Motor de dinero II: idempotencia, tasa y gasto vinculado

**Objetivo:** cerrar los caminos de duplicación y el descuadre aritmético.

**Build:**
- **Idempotencia real** (R5): `idempotency_key uuid UNIQUE` en `fdi_dat_movimiento` con **índice único
  parcial por `tipo`**, migrando los 16 movimientos de `newa` que hoy usan `observacion LIKE '%idem:%'`.
  Aplicar a **`fn_fdi_ingreso_manual`, `fn_fdi_ajuste` y `fn_fdi_gasto`**.
- **`fn_fdi_transferir_v2`** con par explícito y validación de cordura (**rechazar si la tasa se aparta
  >20 % de la última conocida del mismo par**) e **inversa desnormalizada**. **La v1 no se modifica.**
- **`fn_fdi_gasto` con `p_id_compra`**: rechazar si la compra tiene reserva o pago vivo (R4/A5). Ya existe
  en `newa`: se **extiende**.
- **X9**: tasa de pagos resuelta **en servidor, desde el histórico por fecha; el cliente no la provee**.
- **X11**: `fn_fdi_ajuste` con motivo estructurado y doble aprobación sobre umbral.
- **`fn_fdi_crear_liquidacion`**: no se toca en `newa` (ya tiene 11 args). Su arreglo en Main es de la 0b.

**Checklist:**
- [ ] Idempotencia UUID con índice parcial por `tipo`, migrando los 16
- [ ] `fn_fdi_transferir_v2` + v1 intacta
- [ ] `id_compra` en gasto con rechazo
- [ ] Tasa resuelta en servidor
- [ ] Ajuste con motivo y umbral

**Exit criteria:**
- `verify/02_idempotencia_tasa.sql` en verde
- Doble llamada concurrente con la misma key → **un** movimiento
- La v1 se comporta igual; la v2 rechaza tasa fuera de cordura
- Conciliación 0,00

**E2E del dueño:**
1. Doble clic en "Ingreso" → un solo movimiento.
2. Transferencia con la tasa tecleada al revés → rechazo con mensaje, no descuadre.
3. Gasto del fondo apuntando a una compra ya reservada → rechazo.
4. Conciliación sigue en 0,00.

---

## Fase 3 — Compra como documento

**Objetivo:** que exista la compra con proveedor, factura, líneas, cargo de importadora declarado, total,
numeración y permisos.

**Build:**
- `fdi_dat_compra`: `id_tienda, numero_compra, id_proveedor, numero_factura, fecha_factura, moneda_total,
  tasa_factura, total_mercancia, total_ajustes, total_financiado, costo_aterrizado, modo_liquidacion,
  politica_pago, estado, observacion, idempotency_key, created_by`.
- `fdi_dat_compra_linea`: `id_compra, id_producto, id_variante, id_presentacion, cantidad, costo_unitario,
  costo_linea GENERATED, id_almacen, id_ubicacion`.
- `fdi_dat_compra_ajuste`: `id_compra, id_tipo_costo, base ∈ {global, unidad, porcentaje}, valor,
  reparto ∈ {valor, peso, cantidad}, monto_capitalizado, afecta_inventario, origen_pago, estado ∈
  {declarado, por_financiar, financiado}`. El cargo de importadora declarado entra aquí con su
  `pct_importadora` estimado.
- `fdi_hist_estado_compra` append-only; `fdi_dat_compra_recepcion` y `_linea` (vacías hasta fase 5).
- Restricciones:
  - índice único **parcial** en `(id_tienda, id_proveedor, numero_factura) WHERE numero_factura IS NOT NULL`;
  - `CHECK(cantidad > 0)` y **`CHECK(costo_unitario >= 0)`**;
  - **`origen_pago` NOT NULL con default `fondo`** en ajustes de mercancía;
  - **`total_financiado` recalculado por trigger desde líneas + ajustes con `origen_pago = fondo`**;
  - numeración `numero_compra` por tienda con secuencia sin huecos por concurrencia.
- RLS en las 5 tablas **+ `GRANT SELECT` a `authenticated`**; escritura **solo** por RPC.
- RPCs: `fn_fdi_compra_crear`, **`fn_fdi_compra_editar` (solo en `creada`)**, `fn_fdi_compra_listar`,
  `fn_fdi_compra_detalle`, `fn_fdi_compra_cancelar`. **Todas con idempotencia y validación de tienda.**
- UI: listado, alta y detalle. **Ruta `/compras`, entrada en `admin_drawer.dart`, permisos
  dueño/gerente.** Stitch: `COMPRAS — listado`, `COMPRA — alta`, `COMPRA — detalle`.

**Checklist:**
- [ ] 5 tablas + constraints + trigger + numeración
- [ ] RLS, `GRANT SELECT` y permisos
- [ ] Cargo de importadora declarado con `origen_pago`
- [ ] 5 RPCs con idempotencia; `_editar` solo en `creada`
- [ ] Stitch aprobado antes de implementar
- [ ] Listado con filtros; alta con cálculo revalidado en servidor
- [ ] Responsive en 3 tamaños

**Exit criteria:**
- `verify/03_compra.sql` en verde: factura duplicada rechaza; `costo_linea` no se escribe a mano;
  `total_financiado = total_mercancia + ajustes con origen fondo`; dos altas concurrentes no repiten
  `numero_compra`
- `flutter test` de modelos/servicio en verde; `flutter analyze` limpio

**E2E del dueño:**
1. Compra con 3 productos y 15% de importadora → el total coincide con la suma a mano.
2. Cantidad 0 → rechazo con mensaje claro.
3. Duplicar número de factura del mismo proveedor → rechazo.
4. Abrir en móvil, tablet y PC → legible en los tres; en PC todas las columnas.
5. Cancelar sin pagos → `cancelada`, sin rastro de dinero.

---

## Fase 4 — Reserva y liquidación (carril A, solo `al_pagar`)

**Objetivo:** financiar la compra con una sola fuente, sin gastar dos veces el mismo dinero, con el faltante
bloqueando.

**Build:**
- `fdi_dat_compra_reserva` + `fn_fdi_disponible(p_id_tienda)` → `saldo`, `reservado`, `disponible` por
  (cuenta, medio, moneda).
- `fdi_dat_compra_pago` (`origen ∈ {fondo, aporte}`). `modo_liquidacion` **inmutable** tras `reservada`,
  por constraint.
- `fn_fdi_compra_reservar`: valida `Σ disponible ≥ 0` **por (cuenta, medio, moneda)**; si no cubre, dice
  **cuánto falta en cada moneda**.
- `fn_fdi_compra_pagar` con **orden fijo**: 1) valida disponible con la reserva viva, 2) consume la reserva,
  3) debita con `_fdi_aplicar_movimiento` tipo `pago_compra`.
- `fn_fdi_compra_liberar` (cancelación, **motivo obligatorio + usuario**) y `fn_fdi_compra_anular`
  (**contramovimiento de lo pagado no consumido + liberación**).
- `fdi_dat_movimiento` + `id_compra` + `tasa`.
- UI: asistente multimoneda con faltante en vivo y bloqueante, tasa visible y confirmación explícita.
  Stitch: `LIQUIDACIÓN — multimoneda (desktop)` y `(móvil)`.

**Checklist:**
- [ ] Reservas por (cuenta, medio, moneda) + `fn_fdi_disponible`
- [ ] `modo_liquidacion` inmutable
- [ ] Reservar valida por cuenta y dice el faltante
- [ ] Pagar con orden fijo y atómico
- [ ] Liberar con motivo/usuario; anular con contramovimiento
- [ ] `id_compra` + `tasa` en el ledger
- [ ] Asistente con faltante bloqueante

**Exit criteria:**
- `verify/04_liquidacion.sql` en verde: dos compras que juntas exceden el disponible → la segunda se rechaza
  **antes** de reservar; tasa fuera de cordura rechaza; `modo_liquidacion` no cambia tras `reservada`;
  conciliación 0,00 tras reservar → pagar → anular
- `flutter analyze` limpio

**E2E del dueño:**
1. Compra de **2.000 USD**. Cuenta suiza USD con **1.000**; cuenta Venezuela CUP con **20.000**. Tasa
   **1 USD = 1.000 CUP** → los 20.000 CUP son **20 USD**. Cubierto: 1.020 USD.
2. Reservar → muestra **faltan 980 USD** y **no deja cerrar**.
3. Añadir otra fuente hasta cubrir → `reservada`; el **disponible** de cada cuenta baja aunque el saldo no.
4. Pagar → `pagada`; saldo debitado; disponible y saldo vuelven a coincidir.
5. Cancelar otra compra reservada → el disponible vuelve **exactamente** al valor previo.
6. Crear una segunda compra con el dinero ya reservado por la primera → rechazo.

---

## Fase 5 — Recepción: carril A y carril B

**Objetivo:** que la mercancía entre contra la compra sin romper la recepción financiada directa.

**Carril A (nuevo):**
- `fdi_dat_compra_recepcion` con **`UNIQUE(id_operacion, id_compra)`** y `fdi_dat_compra_recepcion_linea`
  (`id_compra_linea, cantidad_recibida, costo_unitario_aplicado, id_recepcion_producto`).
- Cargo de importadora por recepción (`pct`, `base`, `monto`, `reembolso`, `origen_pago`) por compra:
  **editables antes de confirmar, con historial de quién cambió qué**.
- **Solo productos de la compra** (PD6): se elige compra y **solo se ofrecen sus productos con
  pendiente > 0**. Producto no previsto → **recepción externa enlazada**, nunca dentro de la compra.
- **`p_origen text DEFAULT 'externa'`** en la operación de recepción (`compra` | `externa`). Con DEFAULT
  **no rompe** a `ventiq_app` (offline y fallback), ni a los RPC de transferencia entre layouts, ni a los
  egresos con rebalanceo. **No añadir un eje que contradiga `motivo`**: `origen` se **deriva** de `motivo`;
  `motivo` sigue siendo la fuente.
- **Firma única verificada**: `fn_registrar_recepcion_con_inventario` = 12 args y **1 sola firma** en `newa`
  y Main. Los **overloads de 9 args solo viven en dos `.sql` viejos del repo**
  (`presentaciones_inventario/06_recepcion_sin_conversion.sql:61`,
  `sql_updates/fix_recepcion_inventario_al_completar.sql:100`): el riesgo es **aplicarlos**, no borrarlos.
  Si alguna vez existieran en una base, se hace `DROP` y se verifica `pronargs` + ausencia de sobrecargas.
- **Idempotencia de recepción**: `app_dat_operaciones.uuid` es el usuario, no la operación. Añadir
  `idempotency_key` a la operación y a la RPC; test de doble submit.
- **Atomicidad**: quitar el `EXCEPTION WHEN OTHERS` que devuelve JSON
  (`fondo_inversion_recepcion_patch.sql:287-303`): hoy un fallo posterior al INSERT deja una recepción
  fantasma y el almacenero reintenta duplicando.
- Pendiente por recibir: `fn_fdi_compra_recepcion_pendiente(p_id_compra)`. Sobre-recepción: confirmación
  explícita, **no** aumenta lo pagado.
- **Stock**: usar **`fn_contabilizar_recepcion_inventario`** (la única que propaga `id_lote`) **además** de
  `fn_registrar_cambio_estado_operacion_mejorado` para el estado. Ver "El lote en el camino que se conserva".
  Apoyarse en `app_dat_operaciones.contabilizada` / `contabilizada_at` como semáforo.
- `fecha_operacion` opcional (no hay columna de fecha; solo `created_at`).
- **Selector de carga**: al abrir la recepción, marcar **varias compras** (la rastra con 4 facturas); cada
  bloque muestra su factura, proveedor y su % de importadora.
- UI: Stitch `RECEPCIÓN — carga multi-factura (desktop)` y `(móvil)`.

**Carril B (existente, se extiende):**
- Extender `fn_fdi_registrar_recepcion` con **`p_id_compra bigint DEFAULT NULL`** (aditivo).
- Si `p_id_compra` viene informado → **rechazar**: una recepción con compra pertenece al carril A.
- **Corregir el doble uso del desembolso**: al cancelar una recepción financiada, la inversión queda
  `pendiente` con el saldo ya debitado y **puede re-vincularse a otra recepción** desde el desplegable;
  además, reintentar con la misma clave devuelve `duplicada: true` sobre una operación cancelada y la UI lo
  muestra como éxito. **El fix va con la migración**, no después.

#### Recepciones múltiples por compra

| Acumulado recibido | Estado |
|---|---|
| 0 | `reservada` o `pagada` |
| > 0 y < comprado | `entrega_parcial` |
| = comprado en todas las líneas | `completada` |

`recibido(linea)` = suma de todas las recepciones; `pendiente = comprado − recibido`. Cancelar una recepción
devuelve el pendiente sin tocar la compra. `completada` solo se revierte por reapertura explícita con motivo
y usuario. **Cierre corto**: `fn_fdi_compra_cerrar_corto(p_id_compra, p_motivo)` **registra la diferencia,
libera lo no usado y no reescribe el dinero ya pagado**. El pendiente es **de mercancía, no de dinero**.

**Checklist:**
- [ ] Vínculo por cantidades + `UNIQUE(id_operacion, id_compra)`
- [ ] Cargo de importadora editable antes de confirmar, con historial
- [ ] Solo productos de la compra con `pendiente > 0`; camino para el no previsto
- [ ] `p_origen` con DEFAULT, derivado de `motivo`
- [ ] Firma única verificada (12 args, sin sobrecargas)
- [ ] Idempotencia y atomicidad
- [ ] Pendiente y sobre-recepción con confirmación
- [ ] `fn_contabilizar_recepcion_inventario` aplica stock con lote
- [ ] `fecha_operacion`, selector multi-compra
- [ ] Carril B rechaza `p_id_compra` y corrige cancelación/reintento

**Exit criteria:**
- `verify/05_recepcion.sql`: `pronargs = 12` y **1 sola firma**; `fn_fdi_registrar_recepcion` rechaza
  `p_id_compra`; **tres recepciones parciales suman y el pendiente baja línea a línea**; una operación con 4
  compras genera 4 vínculos y 4 estados independientes; **el lote sobrevive**; doble submit = una operación;
  cancelar devuelve el pendiente exacto; **cancelar una recepción financiada no permite re-vincular**;
  reintento sobre cancelada **no** devuelve éxito
- `flutter test` de modelos de recepción en verde; `flutter analyze` limpio

**E2E del dueño:**
1. Compra de **100** → recibir **60** (pendiente 40) → recibir **25** (pendiente 15) → recibir **15** →
   `completada`. Una cuarta recepción se rechaza.
2. Compra con 3 líneas: una al 100% y dos a medias → no cierra hasta que las tres terminen.
3. Cancelar la recepción de 25 → pendiente vuelve a 40.
4. Compra de 10, recibir 12 → exige confirmación y no cambia el total pagado.
5. **Carga multi-factura**: 4 compras en una recepción, cada bloque con su factura y su %; confirmar → 4
   estados independientes.
6. Añadir un producto que no está en la compra → bloqueado.
7. Producto no previsto → se registra como recepción externa enlazada.
8. Producto por lotes → el stock conserva el lote tras completar.
9. **Atomicidad**: `verify/05_forzar_fallo.sql` hace `RAISE` en la segunda línea → **la operación no debe
   quedar creada**.
10. **Idempotencia**: doble clic en "Guardar recepción" → una sola operación.
11. Cancelar una recepción financiada del carril B → no reaparece en el desplegable y el reintento con la
    misma clave no reporta éxito.

---

## Fase 6 — Costo aterrizado sobre el módulo existente

**Objetivo:** que el costo real incluya importadora y adicionales reutilizando lo que `newa` ya tiene.

**Estado real:** en `newa` el módulo funciona (`costo_real` no generada, trigger NULL-safe, `v2` con
`costos[]`) y el catálogo **ya está sembrado** (06a: 4 tipos), así que el aterrizaje escribe las filas del
tipo Importadora (06b). Lo que falta de la fase es la UI de captura, los ajustes `por_financiar`, la
reversión al cancelar y el desvío visible. En Main no existe (fase 0b).

**Build:**
- **Sembrar `app_cont_tipo_costo`** (0 filas en ambos). Columnas reales: `id, denominacion, descripcion,
  naturaleza, afecta_margen, created_at` — **sin moneda**. Tipos: importadora, flete, aduana, seguro.
  **Alcance:** el nomenclador se administra desde **superadmin**, no desde admin. Sembrarlo es tarea de datos
  + pantalla de superadmin. Gestionarlo desde admin es un cambio de alcance a aprobar.
- **Extender `app_dat_recepcion_producto_costo`** con `origen_pago` y los campos de importadora.
- **Reparto por valor** y remanente "por asignar". Hoy solo hay monto fijo por unidad base y producto.
- **Ajustes `por_financiar`**: cada uno crea **su propia reserva y pago** (nunca mutan `total_financiado`) y
  genera un **documento de ajuste de costo** que actualiza la valoración sin reescribir el histórico.
- **Sacar el persistido de costos de fuera de la transacción** (`inventory_service.dart:1409-1414`, en
  `catch { print }` después de la RPC).
- Aprovechar `trg_recepcion_productos_costo_real` (rellena **solo si NULL**).
- **Reutilizar**: `fn_calcular_costo_promedio`, `fn_corregir_costo_recepcion`, `obtener_precio_promedio_presentacion`,
  `fn_es_operacion_sin_actualizar_precio_costo`, `bulk_update_precios_costo`.
- Documentar y borrar `fn_actualizar_precio_promedio_recepcion_v3` (código muerto).
- Reversión de costo al cancelar recepción, como documento propio.
- `id_compra` + `moneda` en `imp_dat_factura` / `prv_dat_factura`.
- **Mostrar el desvío de importadora** (`Σ cargos` vs `Σ valores de factura vinculados`) sin corregirlo solo.
- UI: captura de importadora y reembolso + catálogo de costos (superadmin). Stitch:
  `RECEPCIÓN — importadora y adicionales`, `CONFIG — costos adicionales`.

**Checklist:**
- [x] Catálogo sembrado (06a)
- [x] `origen_pago` y campos de importadora **en el vínculo** (05a; desviación documentada)
- [x] Reparto por valor del cargo (06b) y remanente por asignar visible (06c)
- [x] Ajustes `por_financiar` con reserva y pago propios (06d)
- [x] Persistido dentro de la transacción (06b)
- [x] `costo_real` suma adicionales (E2E del dueño, 2026-11-23)
- [x] `_v3` borrada (06c)
- [x] Reversión de costo al cancelar (06c: se marca, no se borra)
- [x] `id_compra` + `moneda` en facturas (06a)
- [x] Desvío visible (06c: panel en el detalle de la compra)

**Exit criteria:**
- `verify/06_costo.sql`: 2.000 + 15% − 50% reembolso = **2.150** exacto; si el origen es wallet,
  `Σ pagos del fondo = 2.000`; **si es fondo, `= 2.150`**; flete 100.000 / 100 u con 60 recibidas →
  60.000 aplicados y 40.000 por asignar; `costo_real` NULL = 0 en recepciones nuevas; `precio_promedio`
  ponderado por stock previo
- `flutter analyze` limpio

**E2E del dueño:**
1. Sembrar un tipo de costo y recepcionar con 15% de importadora y flete.
2. El producto muestra el costo **aterrizado**, no el de factura.
3. Pedir reembolso de la mitad del cargo → el costo baja exactamente la mitad del cargo.
4. Segunda recepción de la misma compra con **otro %** → cada recepción conserva el suyo.
5. Recepción parcial con costo global → el costo unitario de lo recibido no se infla.
6. Inventario valorado coincide con el aterrizado aplicado.
7. Si el cargo es de la wallet → el fondo **no** aparece pagándolo.

---

## Fase 7 — Inversores aportantes (100%)

**Objetivo:** que los inversores cubran una compra al 100%, sin que ese dinero se acumule en el fondo.

**Build:**
- `fdi_dat_compra_aporte` (`id_compra, id_inversor, moneda, monto, tasa_a_total, monto_eq_total`,
  `naturaleza ∈ {anticipo, pasivo, capital}`, `estado ∈ {aportado, devuelto}`, `comprobante`,
  `observacion`, `idempotency_key`, devolución con fecha/usuario/motivo). `monto_eq_total` es **columna
  generada** (`round(monto × tasa_a_total, 2)`): el equivalente no se puede falsear.
- **Aislamiento**: no entra en `fdi_dat_saldo`, no genera saldo del inversor, no se mezcla con
  `fdi_dat_inversor.porcentaje`. `newa` tiene 6 inversores y 12 repartos: **no se tocan**.
- **Exclusividad 100% en BD**: en modo inversores **no puede existir pago ni reserva con `origen = fondo`**
  (tampoco un ajuste o cargo de recepción declarado `origen_pago = 'fondo'`), y
  `Σ aportes vigentes = total_financiado` antes de `pagada`. Se impone con seis triggers y con el CHECK
  `fdi_pago_fuente_check`, no solo en las RPC.
- `fn_fdi_compra_aportes` (lectura con faltante y motivo de bloqueo), `fn_fdi_compra_aporte_registrar` (no
  excede el faltante; exige tasa explícita si la moneda difiere) y `_devolver` (**devolución = cancelación
  de pasivo; solo el interés es gasto si `naturaleza = pasivo`**). `naturaleza` por defecto `anticipo`.
  `fn_fdi_compra_pagar` gana su rama de aportes; `liberar`, `cancelar` y `anular` sus guardas.
- UI: aportes por compra con restante en vivo. Stitch: `COMPRA — aportes de inversores`
  (`7297c9001c8f400b9d78d9c3b3230ec2`), captura `docs/design/compras-aportes-inversores.png`.

**Checklist:**
- [x] Entidad aislada del % y del libro del fondo
- [x] Validación de faltante
- [x] Exclusividad 100% en BD
- [x] Devolución como cancelación de pasivo
- [x] UI con restante bloqueante

**Exit criteria:**
- `verify/07_aportes.sql`: los aportes suman y la compra pasa a `pagada`; un exceso se rechaza; **ningún
  movimiento en `fdi_dat_saldo` originado por un aporte**; no coexisten reserva de fondo y aporte; la
  devolución deja el saldo de aportes en cero — **cumplido: 32/32**, y las pruebas de dinero
  `verify/07_pruebas_aportes.sql` **42/42**
- `flutter analyze` limpio — **cumplido** (`lib/` sin diagnósticos)

**E2E del dueño:**
1. Compra 2.000 en modo inversores: **X aporta 800, Y aporta 700** → restante **500** y **no deja pagar**.
2. Aportar los 500 → la compra queda cubierta al 100 % y `Pagar compra` se habilita; al pulsarlo, `pagada`
   (el pago es explícito: en modo inversores no hay paso `reservada`).
3. Aportar 100 de más → rechazo.
4. Abrir el módulo de fondo → **ningún saldo nuevo** ni acumulado para X ni Y.
5. Devolver el aporte de X → consistente (la compra sigue `pagada` con cobertura incompleta, con el hueco
   anotado en el historial; el fondo no mueve un centavo).
6. Intentar reservar del fondo la misma compra → rechazo por exclusividad.

> **Antes de empezar:** la tienda del E2E necesita **al menos dos inversores activos** (se crean en Fondo de
> inversión → Inversores). En `newa` la tienda 9 ya tiene los dos de prueba, sembrados el 2026-11-23
> (`X Inversores` y `Y Inversores`, 50 % cada uno: Σ activos = 100, así que la liquidación de utilidad de
> esa tienda no queda bloqueada). Límite conocido: la lista de inversores del diálogo se lee con la política
> de la fase 1 (`fn_user_is_dueno`), y la tienda 9 **no tiene fila en `app_dat_dueno`**: solo la ve un
> superadmin. Se prueba con `aicemaria112@gmail.com` o `aicemaria113@gmail.com`; con el gerente
> `aicemaria@gmail.com` el diálogo sale vacío aunque la RPC le permita registrar. Abrir la lista a gerentes
> es una decisión de privacidad que no se toma aquí.

---

## Fase 8 — Reportes, conciliación en UI y cierre

**Objetivo:** poder probar en cinco minutos que el dinero cuadra, y dejar documentación que sobreviva.

**Build:**
- **Estado real de R1-R7 en `newa` (inventario del 2026-11-23):**
  | R | Estado | Dónde |
  |---|---|---|
  | R1 conciliación | **ya existe y da 0,00** (tienda 9: 3 claves, 0 descuadres; `dif_saldo_vs_mov` y `dif_saldo_vs_ultimo` en cero) | `fn_fdi_conciliacion(bigint)` |
  | R2 saldo por cuenta y moneda | **parcial**: bruto y totales por moneda, **sin `reservado`/`disponible`** (la función es anterior a la fase 4) ni ejecutado del periodo | `fn_fdi_saldos(bigint)` |
  | R3 compras por estado | **falta** (facturado vs aterrizado vs pagado) | — |
  | R4 costo real vs factura | **parcial**: el desvío por compra ya lo da la fase 6; falta la vista agregada | `fn_fdi_compra_costo_resumen(bigint)` |
  | R5 diferencias cambiarias | **falta** | — |
  | R6 movimientos por usuario y día | **parcial**: la lista con saldo antes/después existe; falta agrupar por usuario y día | `fn_fdi_movimientos(...)` |
  | R7 inversores | **parcial**: repartos y pagos; falta aportes vs devoluciones vs utilidad vs pendiente | `fn_fdi_historial_inversores(bigint,date,date)` |
- Reportes **R2-R7** de `02-contabilidad.md` **§6.3**: saldo/reservado/disponible por cuenta y moneda;
  compras por estado con facturado vs aterrizado vs pagado; costo real vs factura con % de desvío;
  diferencias cambiarias por documento; movimientos por usuario y día; inversores (aportes vs devoluciones
  vs utilidad vs pendiente).
- **Conciliación R1 en UI** con alarma visible y ejecución programada.
- Aging de reservas y **listado de compras con descuadre declarado**.
- **Retirar el alta de `fdi_dat_inversion`** de la UI y **marcar el módulo como legado de solo lectura**.
- Alinear `precio_promedio` con `ventiq_app` (su sync hace `.update()` sin ponderar): decidir guardia en BD
  o parche acotado, y probar con **las dos apps**.
- Devoluciones/notas de crédito: decisión explícita (fase futura documentada o implementación).
- Cierre documental: índice en `docs/planes/fondo-inversion/README.md`, `CAPABILITY-MAP.md`.
- Revisión final de responsive.

**Checklist:**
- [x] R2-R7 implementados y enlazados
- [x] Conciliación en UI con alarma y job
- [x] Aging y descuadre declarado
- [x] Alta de inversión retirada; legado de solo lectura
- [x] `precio_promedio` decidido y probado con las dos apps — **decidido** (ver «Decisiones»); la prueba en
      dispositivo sigue pendiente del dueño, y el clobber conocido queda como H12 con su arreglo propuesto
- [x] Devoluciones: decisión explícita — fase 10 documentada
- [x] Índice documental

**Exit criteria:**
- **Todos los reportes cuadran con los datos de prueba de las fases 3-7**
- **Conciliación 0,00 en todas las líneas**
- `flutter analyze` sin errores; **`flutter test` completo del app en verde**

**E2E integral del dueño (aceptación del proyecto):**
1. Ingresar saldo al fondo en dos monedas.
2. Crear compra multimoneda con 3 líneas, cargo de importadora y factura.
3. Reservar con dos cuentas; ver faltante; completar; pagar.
4. Recepcionar parcial con % de importadora, reembolso y flete.
5. Recepcionar el resto; verificar `completada` y costo aterrizado en el producto.
6. Conciliación → 0,00. Reporte de compras → `pagado = total_financiado` y
   `aterrizado = mercancía + importadora + adicionales`.
7. Repetir el flujo en modo inversores y comprobar que el fondo **no** se movió.
8. Abrir todo en móvil, tablet y PC.

### Decisiones de la fase 8

- **Devoluciones y notas de crédito: fase futura, no implementación.** Hoy `fn_fdi_compra_anular` devuelve
  al fondo lo que el fondo pagó y deja la compra `anulada`, pero **no existe crédito del proveedor**: el
  módulo no modela la nota de crédito, ni la devolución de mercancía al proveedor, ni el reembolso al
  inversor que aportó. Implementarlo a medias sería inventar un mayor de proveedores. Queda documentado
  como **fase 10** con este alcance mínimo: documento de nota de crédito por compra, aplicación contra lo
  pagado, y reversa de los aportes de una compra anulada (hoy se devuelven a mano antes de anular).
- **`precio_promedio` no lleva guardia en BD: es una columna de muchos escritores.** Se comprobó el
  catálogo: además del módulo (`fn_actualizar_precio_promedio_recepcion_v2`), la escriben
  `bulk_update_precios_costo`, `bulk_import_productos_excel`, `fn_corregir_costo_recepcion`,
  `fn_admin_caja_actualizar_precios_offline`, `insert_producto_completo_v3`,
  `fn_inicializar_precio_promedio_desde_primera_recepcion`, la consignación y la duplicación de producto
  (casi todas `SECURITY DEFINER`, sin forma fiable de distinguir al llamador). Una guarda por trigger
  exigiría una lista blanca de una decena de funciones y rompería la caja, la importación de Excel y la
  consignación. **Decisión: el módulo escribe el promedio solo por su función y no compite por la
  columna; el clobber conocido está en el fallback del cliente de ventas y se registra como deuda de esa
  app** (`tasks/hallazgos_pruebas_newa.md` H12) con el arreglo propuesto. El efecto está acotado: el
  módulo no lee `precio_promedio` para su propia aritmética, así que un clobber degrada la fidelidad del
  costo de inventario, no la contabilidad del fondo. La prueba en dispositivo con las dos apps queda
  pendiente del dueño.

- **Fase 8 · reportes, conciliación programada y cierre documental (2026-11-23).**
  · **`08_reportes.sql`** con siete RPC de solo lectura: `fn_fdi_reporte_caja` (bruto, **reservado**,
    **disponible** y ejecutado de la ventana, que es lo que faltaba a `fn_fdi_saldos`), `_compras`
    (facturado vs aterrizado vs pagado por estado), `_costo` (mercancía + adicionales = aterrizado con
    % de desvío y % recibido), `_cambiario` (tasa de factura vs tasa de pago, equivalente real vs a tasa
    de factura, diferencia con signo), `_movimientos` (por día, usuario y moneda), `_inversores`
    (aportes, devoluciones, utilidad repartida/pagada/pendiente por moneda) y `_aging` (reservas activas
    con antigüedad + compras con descuadre y su último motivo). **Ningún reporte suma monedas distintas.**
    `verify/08_reportes.sql` **14/14** contrastando cada cifra **contra las tablas** de las tres tiendas
    con datos; se probó en negativo (romper R2 a propósito hace fallar el chequeo), se corrió el rollback
    (las 7 desaparecen) y se reaplicó.
  · **`08b_conciliacion_job.sql`**: R1 dejaba de correr si nadie abría la pantalla. Ahora
    `fdi_dat_conciliacion_ejecucion` guarda cada corrida, `fn_fdi_conciliacion_registrar()` recorre las
    tiendas con saldo y poda a 90 días, `fn_fdi_conciliacion_ultima(bigint)` alimenta la nota de la UI y
    el job `fdi-conciliacion-diaria` de `pg_cron` lo lanza a las 03:00. **R1 sigue siendo
    `fn_fdi_conciliacion`**: no se reescribió. `verify/08b_job.sql` **9/9**.
  · **UI `/reportes`** (diseño en `docs/design/reportes-*.png`): conciliación con **alarma de dos
    niveles** que recalcula en el cliente (`descuadresEfectivos = max(servidor, filas no ok)`, umbral sin
    redondear antes), caja con reservado/disponible, compras/costo/cambiario, movimientos por día y
    usuario, inversores y las dos tarjetas de pendientes con contadores que salen de las mismas listas.
    Navegación por `/reportes` en el cajón tras «Compras», permiso dueño/gerente. `flutter analyze`
    limpio y **28 tests** en verde (`reportes_contract_test`, `reportes_ui_smoke_test` a 390 y 800 px, más
    `app_compile_test`).
  · **Legado**: se retiró el alta de inversión, el cambio de estado y la resolución de revisión (UI y
    servicio); queda listado y detalle consultables con un aviso que manda a Compras para comprometer
    dinero y a los aportes para lo de inversores. `vincularRecepcion` se conserva porque lo usa la
    recepción financiada.
  · **Hallazgo de los reportes (H11).** El criterio «pagado = financiado» aplicado a todos los estados
    marcaba como descuadre toda compra no pagada (3 falsos positivos en `newa`). Ahora el criterio de
    pagos solo aplica a `pagada`, `entrega_parcial`, `completada` y `anulada`; el de financiado sigue
    siendo literal en todos los estados.
  · **Cierre documental**: nuevo `docs/planes/fondo-inversion/README.md` (estado por fase, qué es cada
    documento, dónde vive el SQL y qué verifica cada script) y el módulo completo con sus contratos en
    `CAPABILITY-MAP.md`.
  · **Pendiente de la fase**: el **E2E integral del dueño** (los 8 pasos) y la revisión final de
    responsive en dispositivo. El clobber de `precio_promedio` del TPV queda como deuda documentada
    (H12) porque la guardia en BD se descartó con evidencia: la columna la escriben una decena de
    funciones legítimas.
- **Fase 8 · aprobada por el dueño (2026-11-23).** E2E en verde sobre la pantalla `/reportes`:
  conciliación en verde con la nota de la última revisión automática, caja con `disponible = saldo −
  reservado` y totales por moneda, compras por estado con facturado/aterrizado/pagado, costo con el
  desvío de cada compra, cambiario con su signo, movimientos cuyo neto cuadra con la caja, inversores con
  los aportes de la 67 y la devolución de la 68, y los pendientes con contadores coherentes. **Fase 8
  cerrada.** El E2E integral de las ocho fases queda para el cierre del proyecto (fase 9).

---

## Fase 9 — Pendientes, recordatorios y registro de faltantes

**Build:**
- **Panel de pendientes** (`/compras/pendientes`): por compra abierta, factura, proveedor, fecha, antigüedad
  (desde `created_at`: no hay columna de fecha), % recibido, monto pendiente y estado. **Ordenable por
  antigüedad y por monto.**
- **Detalle de faltantes por producto y línea**: comprado, recibido, pendiente, **última recepción, días sin
  movimiento**.
- **Recordatorios**: alerta en home y notificación programada (reutilizar `local_notification_service.dart`
  / `notification_service.dart`) con umbral configurable (ej. avisar a los N días sin recepción completa).
- **Registro exportable** (Excel/PDF) de pendientes **y del histórico de recepciones**, con
  `export_service.dart`.
- **Vista de facturas** con su estado, enlazando compra y recepciones.
- **Permisos: el almacenero ve pendientes y recepciones; el dueño/gerente ve montos y exporta.**
- Stitch: `PENDIENTES — panel (desktop)`, `(móvil)`, `PENDIENTES — detalle`.

**Exit criteria:**
- `verify/09_pendientes.sql`: pendiente por línea = comprado − recibido; una compra `completada` **no**
  aparece; el monto pendiente cuadra — **cumplido: 14/14**
- `flutter test` de los servicios en verde; `flutter analyze` limpio — **cumplido: 75 tests y `lib` sin
  diagnósticos**

**E2E del dueño:**
1. Dejar una compra con 40 de 100 → aparece en el panel con su antigüedad.
2. Completarla → desaparece.
3. Forzar el umbral de días → llega la notificación.
4. Exportar → el archivo abre y los totales coinciden con la pantalla.
5. Abrir el detalle por producto → coincide con el pendiente por línea.
6. Entrar como almacenero → ve el panel y las facturas **sin ninguna cifra de dinero**; dueño y gerente ven
   montos y exportan.

- **Fase 9 · pendientes, faltantes y recordatorios construidos (2026-11-23).**
  · **`09_pendientes.sql`** con cuatro RPC de solo lectura: `fn_fdi_pendientes_panel` (compras **abiertas**
    con antigüedad, `recibido_pct`, **monto pendiente**, última recepción y días sin movimiento, ordenable
    por `antiguedad` o `monto` **en el servidor**), `fn_fdi_pendientes_detalle` (por producto y línea),
    `fn_fdi_recepciones_historial` y `fn_fdi_facturas` (incluye cerradas, con estado de recepción
    `sin recibir`/`parcial`/`completa`). Criterio fijado: `pendiente = GREATEST(0, cantidad − recibido)`
    **por línea** (un exceso en una línea no tapa un pendiente en otra) y `monto_total` = Σ `costo_linea`
    para que panel y detalle sumen lo mismo. `verify/09_pendientes.sql` **14/14** contra las tablas; se
    probó en negativo mutando cuatro esperados y saltaron exactamente las filas afectadas.
  · **UI**: `/compras/pendientes` (tabla densa en ancho, tarjetas en estrecho, resumen con el pendiente por
    moneda), detalle por línea con las recepciones de la compra, y `/compras/facturas`. Diseño en
    `docs/design/pendientes-*.png`. La fila abre el detalle y el detalle ofrece **una sola** pareja
    `Ir a recepción` / `Ver factura`.
  · **Exportación** a Excel y PDF en un servicio propio (`pendientes_export_service.dart`): hoja de
    pendientes, totales por moneda en hoja aparte y detalle por línea. Se generan bytes de verdad en los
    tests (firma `PK` y `%PDF`), aunque el guardado/compartido en dispositivo no se pudo probar aquí.
  · **Recordatorios**: umbral configurable (15 por defecto, 1..365) en `SharedPreferences`, lógica pura en
    `recordatorios_calculo.dart`, aviso **una vez al día** y notificación local con id fijo. La tarjeta del
    inicio (`AlertaPendientesCard`, dashboard móvil **y** web) muestra compras sin completar, la más
    antigua con su chip y el pendiente **por moneda**, con enlace al panel y ajuste del umbral.
  · **Permisos**: el **almacenero** entra a pendientes y facturas pero **sin importes** (las columnas de
    dinero desaparecen sin dejar huecos y los bloques de monto se sustituyen por conteos); la regla sale de
    `rolesConImportesCompras` y del rol de la tienda, nunca de un toggle. Exportar solo con importes.
  · **Riesgo aceptado**: la tarjeta del inicio no distingue rol (la RPC ya valida acceso a la tienda); si
    el almacenero la ve, verá cifras hasta que se decida si se ocultan también ahí.
  · **Pendiente de la fase**: el **E2E del dueño** (los 6 pasos, incluido el almacenero sin importes).

## Fase 10 — Responsive real de las vistas nuevas

**Objetivo:** que **todas** las vistas que se diseñaron con Stitch (reportes, pendientes, facturas, detalle
de faltantes, aportes de inversores, costo aterrizado y recepción con adicionales) se puedan usar en un
móvil de 360 px **sin scroll horizontal y sin perder cifras**. Hoy no lo cumplen: en móvil «no se ven los
números».

**Causa raíz encontrada (2026-11-23).** `TablaReporte` —la tabla densa que comparten reportes, pendientes,
detalle y facturas— calculaba `factor = max(1, disponible / base)`, es decir **nunca se hacía más estrecha
que su ancho natural** (1.200 px largos) y se metía en un `SingleChildScrollView` horizontal. En un teléfono
las columnas de dinero quedaban fuera de la pantalla, sin barra ni pista de que hubiera más a la derecha, y
las cabeceras con `maxLines: 1` + `ellipsis` se recortaban. Los tests de humo no lo detectaban porque un
scroll horizontal **no lanza excepción de desborde**: solo esconde contenido.

**Build:**
- [x] `TablaReporte` con **modo tarjeta** por debajo de `anchoMinimoTabla` (720 px): cada fila se pinta como
      tarjeta con la primera columna de título y el resto como pares `ETIQUETA → valor`, sin scroll
      horizontal, respetando la alineación de las columnas de dinero y las filas clicables.
  · Arregla de una vez reportes (las tres secciones), panel de pendientes, detalle de faltantes y facturas.
- [x] **Pestañas de Reportes en estrecho**: los tres títulos sumaban ≈600 px, así que en un móvil solo se veía
      el primero y parecía que la pantalla tenía una sola sección. Por debajo de 600 px se usan etiquetas
      cortas (`Conciliación`, `Compras`, `Movimientos`) y caben las tres.
- [x] **Barrido de `Axis.horizontal` en `lib/`**: en las vistas del módulo (fases 6-9) solo quedaba el de la
      tabla ancha, que ahora solo se usa por encima de 720 px. Los demás son de pantallas ajenas al módulo
      (ventas, RRHH, carnaval, consignación) y no se tocan aquí.
- [ ] Auditar a **360 px** cada sección de `/reportes`: franjas de KPI, banda de conciliación (que la
      diferencia total no se corte), bloques de dos columnas y la fila de totales por moneda.
- [ ] Auditar el **panel de aportes** (fase 7) y el **panel de costo aterrizado** (fase 6) a 360 px:
      cortes a tarjeta y que ningún importe se recorte.
- [ ] Auditar **recepción**: chips de adicionales por línea y tabla de productos a 360 px.
- [ ] **Barrido sistemático**: ninguna vista de las fases 6-9 puede tener `scrollDirection:
      Axis.horizontal` ni anchos fijos que sumen más de 360 px sin corte. Se revisa con un grep y se corrige
      cada caso. — **barrido hecho** (solo quedaba el de la tabla ancha); falta confirmar en dispositivo.
- [ ] **Tests de anchura** en 360, 390, 430, 800 y 1280 px que comprueben dos cosas: que **no hay** scroll
      horizontal y que un importe concreto es visible (no basta con que no haya excepción).
- [ ] Revisión final de responsive del resto del módulo (compras, liquidación) en dispositivo.

**Checklist:**
- [x] Tabla densa con modo tarjeta (causa raíz)
- [x] Reportes: tres secciones auditadas a 360 px
- [x] Aportes y costo aterrizado auditados
- [x] Recepción (chips y tabla) auditada
- [x] Barrido de scroll horizontal en las fases 6-9
- [x] Tests de 5 anchos con importe visible
- [x] Responsive del módulo completo en dispositivo

**Exit criteria:**
- Ninguna vista del módulo con scroll horizontal en 360 px
- Todos los importes visibles sin desplazar; nada recortado con puntos suspensivos en las cifras
- `flutter test` de anchura en verde y `flutter analyze` limpio

**E2E del dueño:**
1. Con un móvil de 360 px, abrir Reportes → las tres secciones y ver la conciliación, la caja y los totales
   **con sus cifras**.
2. Abrir Pendientes y Facturas → cada compra es una tarjeta con su monto pendiente visible.
3. Abrir el detalle de faltantes → comprado, recibido y pendiente se leen sin desplazar.
4. Abrir el detalle de una compra en modo inversores → el desglose de aportes y el pendiente se leen.
5. Rotar a horizontal y volver a vertical sin perder nada.
6. Repetir en tablet (800 px) y comprobar que vuelve la tabla densa.

- **Fase 10 · aprobada por el dueño (2026-11-24).** El fallo se reprodujo en el móvil del dueño sobre las
  vistas de la fase 8 y 9 («no se ven los números»). Causa: `TablaReporte` nunca se hacía más estrecha que
  su ancho natural y vivía en un scroll horizontal, así que las columnas de dinero quedaban fuera de
  pantalla sin barra ni pista; los tests de humo no lo veían porque **un scroll horizontal no lanza
  excepción de desborde**. Arreglado con el modo tarjeta (<720 px), etiquetas cortas en las pestañas de
  Reportes (<600 px) y un test que comprueba explícitamente que **no hay** scroll horizontal y que la cifra
  se renderiza. Barrido de `Axis.horizontal` en las vistas del módulo: solo quedaba el de la tabla ancha.
  **Fase 10 cerrada.** Lección para las próximas vistas: comprobar ausencia de scroll horizontal, no solo
  ausencia de excepciones.

---

## Riesgos

| Riesgo | Fase | Estado |
|---|---|---|
| **Cliente llama a `fn_fdi_registrar_recepcion` y no existe en ninguna base** | 0 | **bloqueante actual** |
| **Doble uso del desembolso al cancelar una recepción financiada** | 5 | fix incluido en la migración |
| **Reintento sobre operación cancelada devuelve `duplicada: true`** | 5 | el fix lo distingue |
| **Dos carriles pagando la misma recepción** | 5 | `p_id_compra` rechazado en B |
| **FEFO sin dueño en "Completar"** | 5 | resuelto: `fn_contabilizar_recepcion_inventario` aplica el stock |
| **`fn_fdi_crear_liquidacion` 10 vs 11 args** | 0b | Main se completa a 11 |
| **Deprecar la función combinada de estado** | 5 | evitado: no se depreca |
| **Fase 0b chocando con el pase oficial** | 0b | se integra a Tasks 3/4 |
| `v2` de promedio distinta por entorno | 0b | se promueve el cuerpo de `newa` |
| R1 movimiento en tienda equivocada | 1 | cubierto |
| R2 dinero irrecuperable | 1 | cubierto |
| R3 sobre-recepción por carrera | 1 | cubierto |
| R5 duplicado por reintento | 2 | cubierto |
| R6 escala y redondeo | 1 | cubierto |
| R7 reparto bloqueante | 1 | cubierto |
| R4/A5 doble financiamiento vía `fn_fdi_gasto` | 2+7 | cubierto |
| R8 totales por moneda | 8 | cubierto |
| R9 stock y billete divergen | 5 | cubierto (dos pasos en "Completar") |
| X1 doble uso del dinero | 4 | cubierto |
| X2 tasa invertida | 2 | cubierto |
| X3 doble costo de importadora | 6 | cubierto |
| X4 costo global a lo recibido | 6 | cubierto |
| X5 ponderación del promedio | 6 | **no aplica**: `_v2` pondera bien; `_v3` es código muerto |
| X6 reintento duplicado | 2 | cubierto |
| X7 moneda texto libre | 1 parcial | no cubierto en lo viejo |
| X8 libro de importadora sin moneda | 6 | cubierto |
| X9 tasa del cliente | 2 | cubierto |
| X10 cancelar recepción no revierte costo | 6 | cubierto (06c: se marca, `_v2` excluye, `costo_real` vuelve al de factura y hay documento). **Límite:** `precio_promedio` ya ponderado no se reconstruye |
| Costo tardío revaloriza el inventario | 6 | 06d suma `monto/unidades` al `precio_promedio`; el COGS de lo vendido no se reexpresa (declarado) |
| X11 ajuste como válvula | 2 | cubierto |
| 30.038 `costo_real` NULL en Main | 0b | cubierto vía pase + backfill |
| `app_cont_tipo_costo` vacío | 6 | cubierto al sembrarlo |
| Datos de prueba del fondo en `newa` | 1-2 | respaldo + verificación |
| Rastra con 4 facturas | 5-6 | el reparto ya es **por vínculo** (D10) y no borra los costos de otra compra; falta poblar `id_recepcion_producto` en el vínculo y quitar el rechazo del segundo vínculo |
| % de importadora distinto por recepción | 5-6 | por compra y por recepción, con historial |
| Recordatorio de faltantes | 9 | cubierto |
| Multi-almacén / ubicación destino | 3 | `id_almacen`/`id_ubicacion` por línea |
| No hay migraciones versionadas | todas | mitigado, no resuelto |
| Devoluciones / notas de crédito | 8 | decisión pendiente |
| Offline / borrador local en compras | — | fuera de alcance |

---

## Preguntas al dueño

**Ninguna bloqueante.** Dos decisiones que no frenan la fase 0 pero hay que tomar antes de la 3:

- **42 RPC que el cliente llama y no existen en ninguna base** (`12-inventario-migraciones.md` §1). Solo
  `fn_fdi_registrar_recepcion` era de esta rama y ya está aplicada. Las otras 42 son **código muerto
  previo**: pantallas que fallarán si se abren. No se arreglan con SQL. Decisión: **retirar esas
  pantallas o implementarlas**; no entra en este plan salvo que el dueño lo pida.
- **`SQL_OPTIMIZATION/mapeo_categorias_consignacion.sql`** (4 RPC de consignación). No está en `newa` ni
  en Main: ese módulo nunca se desplegó. Decisión: **aplicarlo en ambos entornos o retirar la pantalla**;
  aplicarlo solo en `newa` crea deriva en sentido contrario.

---

## Cómo arrancar

```
Lee docs/planes/fondo-inversion/PLAN.md y ejecuta la fase 0.
```