# Fondo de Inversión → Compras → Recepción → Consumo — plan de implementación

**Versión 6** · 2026-11-20 · Re-basado contra la rama **`multimoneda`**, `newa` (desarrollo) y Main
(producción). Las 8 decisiones del dueño siguen cerradas.

## Correcciones de la v6 (rama `multimoneda`)

La rama `multimoneda` (commit `2bff5b18`, 2026-11-20) adelanta trabajo que la v5 no conocía. Cuatro
cosas cambian:

| # | La v5 decía | La realidad en `multimoneda` |
|---|---|---|
| A | No existía forma de financiar una recepción desde el fondo | Existe `fn_fdi_registrar_recepcion` (`fondo_inversion_financiar_recepcion.sql`): N fuentes cuenta/medio/moneda, idempotencia y **debita al recibir**. El cliente ya la llama (`inventory_service.dart:1382`) |
| B | "No tocar `fn_fdi_crear_liquidacion`, preservar la firma del entorno" | **Al revés.** La regla del equipo es que quede **solo con 11 parámetros**. Main tiene únicamente la de 10 y no tiene `repartir_igual`: "preservar" deja Main roto |
| C | Deprecar `fn_registrar_cambio_estado_operacion_mejorado` en el botón "Completar" | **Prohibido.** Es la función combinada main+newa del 19/11 (compensatorio `origen_cambio` 4/5, `RECEPCION_INVENTARIO_USADO`), con su fix pendiente en Main |
| D | Crear un pase propio `newa → Main` (fase 0b) con `DROP EXPRESSION` y backfill antes que nada | El equipo tiene un pase formal (`tasks/plan_promocion_main.md`, `_m01`, expansión aditiva, baselines `md5`). **La fase 0b no puede inventar otro**; se integra a las Tasks 3/4 |

Y un bloqueante operativo inmediato: **el cliente llama a una RPC que no existe en ninguna base**.
`fn_fdi_registrar_recepcion` está en el repo pero **no está aplicada ni en `newa` ni en Main**
(verificado con `to_regprocedure`), igual que las columnas `fdi_idempotency_key` / `fdi_solicitud`. La
ruta "financiar recepción" revienta en runtime hasta que se aplique esa migración.

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

**Regla:** se desarrolla y valida en `newa`; Main recibe por el **pase formal del equipo**, no por un
camino paralelo.

> El `pull` de `multimoneda` **no se pudo hacer**: no hay credenciales de git (`SEC_E_NO_CREDENTIALS`).
> Se trabaja con lo que ya estaba descargado (`2bff5b18`, hace una hora). Si hay commits más nuevos en
> el remoto, no están aquí.

---

## Piezas existentes que este plan respeta

No se rediseñan. Se usan como están o se extienden de forma aditiva.

| Pieza | Qué hace | Cómo la usa el plan |
|---|---|---|
| `fn_fdi_registrar_recepcion(jsonb, jsonb, uuid)` | **Carril B**: recibe y debita en la misma transacción, con N fuentes y cobertura exacta al centavo | Carril de "recepción directa" (sin compra). **Nunca** para una recepción con compra |
| `fn_fdi_crear_inversion` | Crea el sobre y **debita** inmediatamente | Base del carril B; en el carril A no se usa tal cual |
| `fn_fdi_crear_liquidacion` | Liquidación de ganancia, **11 args** (`p_repartir_igual`) | No se toca en `newa`; en Main se **completa** (Task 4: columna + 11 args + `DROP` de la de 10) |
| `fn_registrar_cambio_estado_operacion_mejorado` | Cambio de estado con compensatorio `origen_cambio` 4/5 y `RECEPCION_INVENTARIO_USADO` | **No se depreca.** Es el camino de cancelación/devolución |
| `fn_actualizar_precio_promedio_recepcion_v2` | Pondera con stock previo; la de `newa` además suma `monto_usd` de adicionales | Se **promueve el cuerpo de `newa`** a Main, nunca al revés |
| `trg_recepcion_productos_costo_real` | Rellena `costo_real` **solo si es NULL** | Molde del costo aterrizado; se replica en Main |
| Pase `newa → main` (`tasks/plan_promocion_main.md`) | Nombre `_m01`, expansión aditiva → clientes → contrato, baselines `md5` | El plan se **subordina** a él |

---

## Objetivo

Al terminar, el admin puede: registrar una **compra** con proveedor, factura, líneas y total;
**financiarla con una sola fuente** — saldo del Fondo repartido en varias cuentas y monedas, **o**
aportes de inversores al 100% — sin gastar dos veces el mismo dinero; **recepcionar** (total o parcial,
una o varias facturas en la misma carga) capturando el **cargo variable de importadora** con su % y sus
reembolsos, más costos adicionales por producto; ver **disponible, comprometido, ejecutado y pendiente**;
y tener recordatorios de facturas con productos faltantes.

**No-goals:** reescribir `imp_*`, devoluciones/notas de crédito, caducidad de reservas, pago mixto,
reescribir el histórico de `fdi_dat_inversion`, inventar un pase a producción paralelo, deprecar la
función combinada de cambio de estado.

---

## Progress

| Fase | Estado |
|---|---|
| 0. Cimientos: rama, migraciones pendientes de la rama, baseline | not started |
| 0b. Integrar el delta de esquema al pase formal (no un pase propio) | not started |
| 1. Motor de dinero I: integridad, escala y conciliación | not started |
| 2. Motor de dinero II: idempotencia, tasa y gasto vinculado | not started |
| 3. Compra como documento | not started |
| 4. Reserva y liquidación (carril A, solo `al_pagar`) | not started |
| 5. Recepción: carril A (contra compra) y carril B (directa) | not started |
| 6. Costo aterrizado sobre el módulo existente | not started |
| 7. Inversores aportantes (100% de la compra) | not started |
| 8. Reportes, conciliación en UI y cierre | not started |
| 9. Pendientes, recordatorios y registro de faltantes | not started |

Current phase: 0 · Recommended next: 0

> Agente ejecutor: actualiza esta tabla al terminar y anota una línea por desviación. No marques `done`
> sin criterios de salida corridos y OK del dueño.

### Bitácora de desviaciones
<!-- fase · qué cambió · por qué -->

---

## Decisiones cerradas

- ✔ **PD1 — En la compra el dinero se compromete al crear y sale al pagar.** `politica_pago =
  al_pagar`. **Matiz importante (v6):** conviven **dos carriles** de pago y una recepción pertenece a
  **uno solo**:
  - **Carril A (compra):** reserva al crear → pago explícito → recepción que **no mueve dinero**.
  - **Carril B (recepción directa):** sin compra; `fn_fdi_registrar_recepcion` debita **al recibir**.
  Una recepción con `id_compra` **no puede** usar el carril B. Se impone en la RPC, no en la UI.
- ✔ **PD2 — Manda la suma de líneas.** `total_mercancia = Σ(cantidad × costo unitario)`. Descuadre con
  la factura → no se puede reservar hasta declarar motivo. Nunca se recalcula el costo unitario.
- ✔ **PD3 — El cargo de importadora es variable y SUMA al valor de la factura.** Componente del costo,
  capturado en la recepción, **% editable y distinto en cada recepción**, con reembolso. La wallet de
  importadora se queda como está.
- ✔ **PD4 — El pago exclusivo es 100% de los inversores.** Nada del fondo en modo inversores; nunca mixto.
- ✔ **PD5 — 7 estados:** `creada, reservada, pagada, entrega_parcial, completada, cancelada, anulada`.
- ✔ **PD6 — En recepción de compra solo aparecen los productos de esa compra.** No se bloquea catálogo
  ni stock.
- ✔ **PD7 — Sin IVA ni descuentos por línea.** Costo neto unitario. Si el IVA fuese acreditable, sería
  componente con `afecta_inventario = false`.
- ✔ **PD8 — El fondo NO paga el cargo de importadora.** `origen_pago = wallet_importadora`: capitaliza y
  nadie lo vuelve a desembolsar.
- ✔ **Los aportes de inversores no se acumulan en el fondo**: viven atados a su compra, no entran en
  `fdi_dat_saldo` y no se mezclan con el porcentaje de utilidad.

---

## Arquitectura

- ✔ **La compra es entidad nueva** (`fdi_dat_compra*` + `fn_fdi_compra_*`). `fdi_dat_inversion` queda
  **congelada como legado del carril B**: el carril A no la usa.
- ✔ **El fondo es `fdi_dat_saldo`**, grano **(cuenta × medio × moneda)**. La compra reutiliza ese libro.
- ✔ **Un solo sentido de tasa: `T(A→B)`** con par explícito. `fn_fdi_transferir` no se toca; se crea
  `fn_fdi_transferir_v2`.
- ✔ **La reserva no es un movimiento.** `disponible = saldo − reservado`, en moneda nativa, validado por
  (cuenta, medio, moneda).
- ✔ **Dos tasas congeladas por documento**: factura (costo) y pago (salida). Diferencia cambiaria a
  resultado financiero, nunca al inventario.
- ✔ **Tres cifras**: `total_mercancia`, `total_financiado` y `costo_aterrizado`.
- ✔ **`origen_pago ∈ {fondo, wallet_importadora, wallet_proveedor, externo}`** por componente de costo.
  Capitaliza siempre; solo se financia si su origen es `fondo`.
- ✔ **El costo se valoriza al recibir.** Recepción parcial: el costo global se reparte **solo sobre lo
  recibido**; el resto queda por asignar. Reparto por **valor**.
- ✔ **Parámetros nuevos con `DEFAULT`**, nunca cambio de semántica sobre una RPC viva.
- ✔ **El plan se subordina al pase formal del equipo.** Cambio de contrato = nombre `_m01`, expansión
  aditiva primero, clientes después, contrato al final.

### Los dos carriles

| | Carril A — compra | Carril B — recepción directa |
|---|---|---|
| Punto de partida | Orden de compra | Recepción sin compra |
| ¿Existe hoy? | **No** (se construye) | **Sí** (`fn_fdi_registrar_recepcion`) |
| Momento del débito | Al **pagar** | **Al recibir** |
| Reserva | Sí | No |
| Fuentes múltiples | Sí | Sí (exactitud al centavo) |
| Tabla de dinero | `fdi_dat_saldo` | `fdi_dat_saldo` |
| Tabla de sobre | `fdi_dat_compra*` | `fdi_dat_inversion` |
| Regla | Una recepción con `id_compra` **jamás** entra por B | Una recepción con `p_id_compra` debe **rechazarse** en B |

### Dinero: eventos del carril A

| Evento | Estado | ¿Sale dinero? | Asiento |
|---|---|---|---|
| Se crea la compra | `creada` | No | ninguno |
| Se cubre `total_financiado` | `reservada` | No | reservas activas |
| Se confirma el pago | `pagada` cuando `Σ pagos = total_financiado` | Sí | consume reserva + `pago_compra` |
| Llega mercancía parcial | `entrega_parcial` | No | valoriza inventario |
| Llega todo | `completada` | No | valoriza inventario |
| Se ajusta el % de importadora | no cambia | Solo si origen `fondo` | ajuste o reembolso |
| Se abandona sin pagos | `cancelada` | No | libera reservas |
| Se abandona con pagos | `anulada` | Sí (reversa) | contramovimiento |

**En el carril A la recepción no mueve dinero.** Mueve inventario, estado y costo.

### Multi-factura en una carga

Una operación de recepción cubre N compras: `fdi_dat_compra_recepcion` con
**`UNIQUE(id_operacion, id_compra)`**. Cada línea sabe su compra; cada compra lleva su `pct_importadora`
y su reembolso; el estado se calcula **por compra**.

### Modelo de importadora

| Concepto | Dónde | Regla |
|---|---|---|
| `pct_importadora` | por compra dentro de la recepción | editable, distinto por recepción |
| `monto_importadora` | `base × pct` | capitaliza |
| `reembolso_importadora` | negativo, opcional | "reembólsame la mitad" |
| `origen_pago` | wallet \| fondo | wallet → solo capitaliza |

Ejemplo: 2.000 USD + 15% (300) − 50% reembolso (150) → cargo efectivo 150, aterrizado **2.150**, fondo
financia **2.000**.

### Restricciones del entorno

- **No hay rama `dev`** en git; se trabaja en `multimoneda`. El plan original pedía crear `dev`; ahora
  **la base es `multimoneda`** y la rama de trabajo se crea desde ella (`git switch -c feat/compras
  origin/multimoneda`) para no ensuciar la rama compartida.
- **Sin credenciales de git**: no se puede `fetch`/`pull`. Todo lo que se afirme de la rama vale para
  `2bff5b18`.
- **No hay convención de migración**: la vía real es pegar SQL a mano. El equipo usa `_m01` y baselines
  `md5` para el pase; el plan se alinea.
- **`fdi_dat_movimiento` en `newa`**: acepta `'gasto'`, **sin `idempotency_key`**, `monto/saldo_*` sin
  escala. `moneda` es `text` sin FK.
- **`app_dat_operaciones`** sin columna de fecha (solo `created_at`), pero con `contabilizada`,
  `contabilizada_at`, `contabilizada_por`.
- **Solo lectura es convención, no capacidad**: el agente no aplica SQL por regla.

### Stack

Flutter 3.44 / Dart 3.12; `provider` + `ChangeNotifier`; `ventiq_admin_app` con `sdk: ^3.10.0`.
Shell: `$env:APPDATA = '...\.dsh\dart-tool'` antes de `flutter`. Rutas `'/kebab-case'` en `main.dart`;
permisos en `permissions_service.dart`. UI: molde "saldo de tercero", chip de estado del nomenclador,
panel plano FDI; prompts en `04-diseno-ux.md`.

### Documentos

| Documento | Para qué |
|---|---|
| `00-auditoria-programador.md` | contrato de tablas/RPCs y riesgos R1-R9 (auditado contra Main) |
| `01-analisis-funcional.md` | dominio, invariantes I1-I15, estados |
| `02-contabilidad.md` | fórmulas de costo, reserva, tasas, redondeo, X1-X11 |
| `03-almacen.md` | recepción real, lotes, huecos operativos |
| `04-diseno-ux.md` | pantallas, responsive, prompts de Stitch |
| `05-referencia-industria.md` | práctica estándar y fuentes |
| `06-revision-adversarial.md` | 44 hallazgos sobre la v1 (2 desmontados) |
| `07-deriva-newa-vs-main.md` | matriz objeto por objeto de los dos entornos |
| `08-costos-newa.md` | módulo de costos real en `newa` |
| `09-financiacion-recepcion-existente.md` | `fn_fdi_registrar_recepcion`: contrato, riesgos, convivencia |
| `10-estado-equipo-y-contradicciones.md` | pase newa→main, reglas vigentes, contradicciones |
| `tasks/plan_promocion_main.md` | **el pase oficial**; manda sobre este plan |
| `tasks/plan_sync_newa_main.md`, `tasks/hallazgos_pruebas_newa.md` | estado y pendientes |

> Los anexos `00`-`06` se escribieron contra Main. Cuando contradigan este archivo, mandan este archivo,
> `07`, `08`, `09` y `10`.

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

---

## Protocolo de entrega

**Código:** rama de trabajo desde `multimoneda`, commits por fase, sin push sin OK.

**SQL:** cada fase entrega en `ventiq_admin_app/lib/sql/`:
- `NN_descripcion.sql` — idempotente, transaccional, con verificación final que hace `RAISE`.
- `NN_descripcion_rollback.sql`
- `verify/NN_verificacion.sql` — solo `SELECT`, `ok|falla` por comprobación.
- Encabezado `-- REQUIERE: NN, NN`.

**Promoción:** `newa` → verificación → E2E del dueño → **pase formal del equipo** hacia Main. Ningún
script de este plan se aplica a Main por fuera de ese pase.

---

# Fases

---

## Fase 0 — Cimientos y desbloqueo de la rama

**Objetivo:** dejar `newa` en un estado donde el código de `multimoneda` **funcione**, y tener red de
seguridad.

**El bloqueante actual:** el cliente llama a `fn_fdi_registrar_recepcion` (`inventory_service.dart:1382`)
y esa función **no existe** en `newa` ni en Main. Cualquier E2E de recepción financiada falla hoy.

**Build:**
- Crear rama de trabajo desde `multimoneda` (`git switch -c feat/compras`). No ensuciar la compartida.
- **Inventario de migraciones pendientes de la rama**: recorrer `tasks/plan_sync_newa_main.md` y
  `tasks/hallazgos_pruebas_newa.md`, y listar qué `.sql` de la rama **no** están aplicados en `newa`.
  Empezar por `ventiq_admin_app/lib/sql/fondo_inversion_financiar_recepcion.sql`.
- Aplicar esas migraciones **en `newa`** (las aplica el dueño), en el orden que declare el equipo.
- Decidir y documentar el **fix del carril B** antes de aplicarlo (ver fase 5, riesgo de re-vinculación).
- Baseline de `newa` en `docs/planes/fondo-inversion/baseline/`: columnas y `pg_get_functiondef` de
  `fdi_*`, `app_dat_recepcion_productos`, `app_dat_recepcion_producto_costo`, `app_dat_producto_costo`,
  `app_dat_operacion_recepcion`, `app_dat_operaciones`, `imp_*`, `prv_*`.
- Respaldo de los datos de prueba del fondo en `newa` (16 movimientos, 10 saldos, 3 liquidaciones).
- `verify/00_linea_base.sql` contra `newa`: (a) 15 tablas `fdi_*`; (b) tipos del CHECK de
  `fdi_dat_movimiento`; (c) `fn_registrar_recepcion_con_inventario` = 12 args y **1 sola firma**;
  (d) `fn_fdi_registrar_recepcion` existe y las columnas `fdi_idempotency_key`/`fdi_solicitud`;
  (e) `costo_real.is_generated`; (f) tablas de costos adicionales; (g) filas de `app_cont_tipo_costo`;
  (h) `fn_fdi_crear_liquidacion` con 11 args.

**Checklist:**
- [ ] Rama de trabajo creada desde `multimoneda`
- [ ] Lista de migraciones pendientes de la rama, con orden
- [ ] `fondo_inversion_financiar_recepcion.sql` aplicada en `newa`
- [ ] Baseline y respaldo de datos
- [ ] `verify/00_linea_base.sql` con 8 comprobaciones

**Exit criteria:**
- `git branch --show-current` → rama de trabajo
- `flutter analyze` sin errores (warnings preexistentes listados)
- `verify/00_linea_base.sql` en `newa` devuelve `ok` en las 8
- La ruta de recepción financiada **deja de fallar** en `newa` (prueba manual mínima)

---

## Fase 0b — Integrar el delta de esquema al pase formal

**Objetivo:** que Main reciba lo que `newa` ya tiene, **por el pase del equipo**, sin inventar un camino
paralelo.

**Por qué cambió (v6):** la v5 proponía un script propio con `DROP EXPRESSION` + backfill antes que
cualquier otro. Eso choca con el pase oficial (`_m01`, expansión aditiva, baselines `md5`) y con que las
Tasks 3/4 ya son dueñas de esos objetos.

**Build:**
- Revisar `tasks/plan_promocion_main.md` y ubicar las **Tasks 3 y 4**: son las que llevan el módulo de
  costos y el arreglo de `costo_real` a Main. **Este plan no las duplica**: aporta lo que falte y se
  coordina.
- Aportar al pase, como items aditivos:
  1. Crear `app_dat_producto_costo` y `app_dat_recepcion_producto_costo` con el DDL **extraído de
     `newa`**, no del script del repo.
  2. `DROP EXPRESSION` de `costo_real` + trigger NULL-safe (`COALESCE` sobre `precio_referencia`).
  3. **Backfill de las 30.038 filas NULL** de Main, con respaldo previo de la columna. El `DO $$` del
     script original no lo contempla.
  4. `'gasto'` en el CHECK de `fdi_dat_movimiento` + `fn_fdi_gasto` (8 args).
  5. **`fn_actualizar_precio_promedio_recepcion_v2`**: promover el **cuerpo de `newa`**, nunca el de Main.
  6. **`fn_fdi_crear_liquidacion`**: dejarla **solo con 11 args** en Main (columna `repartir_igual` +
     `DROP` de la de 10 + `CREATE` de la de 11). Regla del equipo, verificada: Main hoy tiene solo la de 10.
- **Prohibido**: reescribir en sitio funciones que el pase tiene marcadas, o alterar los baselines `md5`
  sin regenerarlos contra Main.

**Checklist:**
- [ ] Tasks 3/4 del pase revisadas y mapeadas
- [ ] Items aditivos aportados al pase (no duplicados)
- [ ] Backfill con respaldo previo
- [ ] `fn_fdi_crear_liquidacion` 11 args en Main
- [ ] `v2` con el cuerpo de `newa`
- [ ] Baselines `md5` regenerados

**Exit criteria:**
- El pase del equipo incluye estos items y su verificación pasa en `newa`
- `verify/00b_delta.sql` compara `newa` vs Main: 0 diferencias en la lista, `costo_real` NULL = 0
- Nada se aplica a Main fuera del pase

---

## Fase 1 — Motor de dinero I: integridad, escala y conciliación

**Build:**
- `_fdi_aplicar_movimiento`: validar que `p_id_tienda` corresponda a la cuenta (R1).
- `fn_fdi_vincular_recepcion`: `FOR UPDATE` antes de decidir el exceso (R3).
- `fn_fdi_inversion_anular`: devuelve lo no consumido con contramovimiento y estado `anulado` (R2).
- **Escala del ledger** (R6/A10): `fdi_dat_saldo.saldo` y `fdi_dat_movimiento.monto/saldo_*` a `numeric`
  con escala por `monedas.decimales`. `newa` tiene 16 movimientos reales: la migración los toca y debe
  verificarlos.
- **R7**: `fn_fdi_repartir_ganancia` no debe reventar sin inversores activos ni sobrescribir lo pedido.
- `fn_fdi_conciliacion(p_id_tienda)`: `saldo`, `Σ movimientos`, `último saldo_nuevo`, diferencia = 0,00.

**Checklist / Exit criteria / E2E:** conciliación 0,00 sobre los datos existentes y tras crear→anular una
inversión de prueba; `verify/01_motor_dinero.sql` en verde; `flutter analyze` limpio; los 16 movimientos
históricos intactos.

---

## Fase 2 — Motor de dinero II: idempotencia, tasa y gasto vinculado

**Build:**
- **Idempotencia real** (R5): `idempotency_key uuid UNIQUE` en `fdi_dat_movimiento`, con migración de los
  16 movimientos de `newa` que hoy usan `observacion LIKE '%idem:%'`.
- **`fn_fdi_transferir_v2`** con par explícito y validación de cordura (>20% → rechazo). La v1 intacta.
- **`fn_fdi_gasto` con `p_id_compra`**: rechazar si la compra tiene reserva o pago vivo (R4/A5). Ya existe
  en `newa`: se **extiende**, no se crea.
- **X9**: tasa de pagos resuelta en servidor.
- **X11**: `fn_fdi_ajuste` con motivo estructurado y doble aprobación sobre umbral.
- **`fn_fdi_crear_liquidacion`**: no se toca en `newa` (ya tiene 11 args). Su arreglo en Main es de la
  fase 0b.

**Exit criteria:** `verify/02_idempotencia_tasa.sql` en verde; doble llamada concurrente = un movimiento;
la v1 se comporta igual; conciliación 0,00.

---

## Fase 3 — Compra como documento

**Build:**
- `fdi_dat_compra`: `id_tienda, numero_compra, id_proveedor, numero_factura, fecha_factura,
  moneda_total, tasa_factura, total_mercancia, total_ajustes, total_financiado, costo_aterrizado,
  modo_liquidacion, politica_pago, estado, observacion, idempotency_key, created_by`.
- `fdi_dat_compra_linea`: `... id_almacen, id_ubicacion, costo_linea GENERATED`.
- `fdi_dat_compra_ajuste`: `base, valor, reparto, monto_capitalizado, afecta_inventario, origen_pago,
  estado ∈ {declarado, por_financiar, financiado}`.
- `fdi_hist_estado_compra`; `fdi_dat_compra_recepcion` y `_linea`.
- Restricciones: único parcial de factura por proveedor; `cantidad > 0`; numeración sin huecos;
  `total_financiado` por trigger.
- RLS en las 5 tablas; escritura solo por RPC.
- RPCs `fn_fdi_compra_crear/_editar/_listar/_detalle/_cancelar`.
- UI: listado, alta y detalle. Stitch: `COMPRAS — listado`, `COMPRA — alta`, `COMPRA — detalle`.

**Exit criteria:** `verify/03_compra.sql` en verde (factura duplicada rechaza, `costo_linea` no se escribe
a mano, totales cuadran, numeración concurrente no repite); tests en verde; responsive en 3 tamaños.

---

## Fase 4 — Reserva y liquidación (carril A, solo `al_pagar`)

**Build:**
- `fdi_dat_compra_reserva` + `fn_fdi_disponible` → `saldo`, `reservado`, `disponible`.
- `fdi_dat_compra_pago` (`origen ∈ {fondo, aporte}`). `modo_liquidacion` **inmutable** tras `reservada`.
- `fn_fdi_compra_reservar`: valida `Σ disponible ≥ 0` **por (cuenta, medio, moneda)**; dice cuánto falta.
- `fn_fdi_compra_pagar` con orden fijo: valida → consume reserva → debita.
- `fn_fdi_compra_liberar` y `fn_fdi_compra_anular`.
- `fdi_dat_movimiento` + `id_compra` + `tasa`.
- UI: asistente multimoneda con faltante bloqueante y tasa visible.

**Exit criteria:** dos compras que juntas exceden el disponible → la segunda se rechaza **antes** de
reservar; tasa fuera de cordura rechaza; conciliación 0,00 tras reservar→pagar→anular; E2E con el caso
2.000 USD / 1.000 USD + 20.000 CUP (tasa 1.000) → faltan 980 USD.

---

## Fase 5 — Recepción: carril A y carril B

**Objetivo:** que la mercancía entre contra la compra (carril A) **sin romper** la recepción financiada
directa (carril B).

**Carril A (nuevo):**
- `fdi_dat_compra_recepcion` con `UNIQUE(id_operacion, id_compra)` y `_linea`.
- Cargo de importadora por recepción (`pct`, `base`, `monto`, `reembolso`, `origen_pago`) por compra.
- **Solo productos de la compra** (PD6); producto no previsto → recepción externa enlazada.
- Pendiente por recibir por línea; sobre-recepción con confirmación que no aumenta lo pagado.
- Idempotencia de la operación; atomicidad (quitar el `EXCEPTION WHEN OTHERS` que devuelve JSON).
- `fecha_operacion` (no existe columna de fecha; solo `created_at`).
- Regla de N recepciones por compra (ver abajo).
- **No se depreca** `fn_registrar_cambio_estado_operacion_mejorado`: se usa para cancelar/devolver.

**Carril B (existente, se extiende):**
- Extender `fn_fdi_registrar_recepcion` con **`p_id_compra bigint DEFAULT NULL`** (aditivo, sin romper).
- Si `p_id_compra` viene informado → **rechazar**: una recepción con compra pertenece al carril A.
- **Corregir el doble uso del desembolso** (riesgo del anexo 09): hoy, al cancelar una recepción
  financiada, la inversión queda `pendiente` con el saldo ya debitado y **puede re-vincularse a otra
  recepción** desde el desplegable; además, reintentar con la misma clave devuelve `duplicada: true`
  sobre una operación cancelada y la UI lo muestra como éxito. El fix va **con la migración**, no después.

#### Recepciones múltiples por compra

| Acumulado recibido | Estado |
|---|---|
| 0 | `reservada` o `pagada` |
| > 0 y < comprado | `entrega_parcial` |
| = comprado en todas las líneas | `completada` |

`recibido(linea)` = suma de todas las recepciones; `pendiente = comprado − recibido`. Cancelar una
recepción devuelve el pendiente sin tocar la compra. `completada` solo se revierte por reapertura
explícita con motivo. **Cierre corto**: `fn_fdi_compra_cerrar_corto` para cuando el proveedor no manda el
resto. El pendiente es **de mercancía, no de dinero**.

**Exit criteria:** `verify/05_recepcion.sql`: `fn_registrar_recepcion_con_inventario` = 12 args y 1 firma;
`fn_fdi_registrar_recepcion` rechaza `p_id_compra`; 3 recepciones parciales suman y el pendiente baja línea
a línea; 4 compras en una operación → 4 estados independientes; cancelar una recepción financiada **no**
permite re-vincular; reintento sobre cancelada **no** devuelve éxito; el lote sobrevive; doble submit = una
operación.

---

## Fase 6 — Costo aterrizado sobre el módulo existente

**Estado real:** en `newa` el módulo funciona (`costo_real` no generada, trigger NULL-safe, `v2` con
`costos[]`); pero **no suma adicionales** porque el catálogo tiene 0 filas. En Main no existe (fase 0b).

**Build:**
- **Sembrar `app_cont_tipo_costo`** (0 filas en ambos). Columnas reales: `id, denominacion, descripcion,
  naturaleza, afecta_margen, created_at` — **sin moneda**. Tipos: importadora, flete, aduana, seguro.
  **Alcance:** el nomenclador se administra desde **superadmin**, no desde el admin. Sembrarlo es tarea de
  datos + pantalla de superadmin. Gestionarlo desde admin es un cambio de alcance a aprobar.
- **Extender `app_dat_recepcion_producto_costo`** con `origen_pago` y los campos de importadora.
- **Reparto por valor** y remanente "por asignar". Hoy solo hay monto fijo por unidad base y producto.
- **Sacar el persistido de costos de fuera de la transacción** (`inventory_service.dart:1409-1414`, en
  `catch { print }` después de la RPC).
- Aprovechar `trg_recepcion_productos_costo_real` (rellena **solo si NULL**): la RPC puede escribir el
  aterrizado sin que el trigger lo pise.
- **Reutilizar**: `fn_calcular_costo_promedio`, `fn_corregir_costo_recepcion`, `obtener_precio_promedio_presentacion`,
  `fn_es_operacion_sin_actualizar_precio_costo`, `bulk_update_precios_costo`.
- Documentar y borrar `fn_actualizar_precio_promedio_recepcion_v3` (código muerto).
- Reversión de costo al cancelar recepción, como documento propio.
- `id_compra` + `moneda` en `imp_dat_factura` / `prv_dat_factura`.
- UI: captura de importadora y reembolso en la recepción + catálogo de costos (superadmin).

**Exit criteria:** `verify/06_costo.sql`: 2.000 + 15% − 50% reembolso = **2.150** exacto; si el origen es
wallet, `Σ pagos del fondo = 2.000`; flete 100.000 / 100 u con 60 recibidas → 60.000 aplicados, 40.000 por
asignar; `costo_real` NULL = 0 en recepciones nuevas; una fila del catálogo basta para que `v2` sume.

---

## Fase 7 — Inversores aportantes (100%)

- `fdi_dat_compra_aporte` (`id_compra, id_inversor, moneda, monto, tasa_a_total, monto_eq_total,
  naturaleza ∈ {anticipo, pasivo, capital}, estado, comprobante, idempotency_key`).
- Aislamiento: no entra en `fdi_dat_saldo`, no genera saldo del inversor, no se mezcla con
  `fdi_dat_inversor.porcentaje`. `newa` tiene 3 inversores y 12 repartos: no se tocan.
- Exclusividad 100% en BD; `Σ aportes = total_financiado` antes de `pagada`.
- `fn_fdi_compra_aporte_registrar` / `_devolver`; `naturaleza` por defecto `anticipo`.
- UI: aportes por compra con restante en vivo.

**Exit criteria:** aportes suman y la compra pasa a `pagada`; un exceso se rechaza; **ningún movimiento en
`fdi_dat_saldo` originado por un aporte**; no coexisten reserva de fondo y aporte.

---

## Fase 8 — Reportes, conciliación en UI y cierre

Reportes R2-R7; conciliación R1 con alarma y job; aging de reservas; retirar el alta de
`fdi_dat_inversion` de la UI (legado del carril B); alinear `precio_promedio` con `ventiq_app` (su sync
hace `.update()` sin ponderar) y probar con las dos apps; decisión explícita sobre devoluciones; índice
documental; revisión final de responsive.

---

## Fase 9 — Pendientes, recordatorios y registro de faltantes

Panel `/compras/pendientes` con factura, proveedor, antigüedad (desde `created_at`), % recibido y monto;
detalle de faltantes por producto y línea; alerta en home y notificación programada con umbral; registro
exportable; vista de facturas con estado; permisos por rol.

**Exit criteria:** pendiente por línea = comprado − recibido; una compra `completada` no aparece; el monto
pendiente cuadra; exportación coincide con pantalla.

---

## Riesgos

| Riesgo | Fase | Estado |
|---|---|---|
| **Cliente llama a `fn_fdi_registrar_recepcion` y no existe en ninguna base** | 0 | **bloqueante actual**, se resuelve aplicando la migración en `newa` |
| **Doble uso del desembolso al cancelar una recepción financiada** | 5 | cubierto: fix incluido en la migración |
| **Reintento sobre operación cancelada devuelve `duplicada: true`** | 5 | cubierto: el fix lo distingue |
| **Dos carriles pagando la misma recepción** | 5 | cubierto: `p_id_compra` rechazado en el carril B |
| **`fn_fdi_crear_liquidacion` 10 vs 11 args** | 0b | cubierto: Main se completa a 11 |
| **Deprecar la función combinada de cambio de estado** | 5 | **evitado**: no se depreca |
| **Fase 0b chocando con el pase oficial** | 0b | cubierto: se integra a Tasks 3/4 |
| `v2` de promedio distinta por entorno | 0b | cubierto: se promueve el cuerpo de `newa` |
| R1 movimiento en tienda equivocada | 1 | cubierto |
| R2 dinero irrecuperable | 1 | cubierto |
| R3 sobre-recepción por carrera | 1 | cubierto |
| R5 duplicado por reintento | 2 | cubierto |
| R6 escala y redondeo | 1 | cubierto, migrando 16 movimientos |
| R7 reparto bloqueante | 1 | cubierto contra 3 inversores reales |
| R4/A5 doble financiamiento vía `fn_fdi_gasto` | 2+7 | cubierto |
| R8 totales por moneda | 8 | cubierto |
| R9 stock y billete divergen | 5 | cubierto con el camino único con lote |
| X1 doble uso del dinero | 4 | cubierto |
| X2 tasa invertida | 2 | cubierto |
| X3 doble costo de importadora | 6 | cubierto |
| X4 costo global a lo recibido | 6 | cubierto |
| X5 ponderación del promedio | 6 | **no aplica**: `_v2` pondera bien; `_v3` es código muerto |
| X6 reintento duplicado | 2 | cubierto |
| X7 moneda texto libre | 1 parcial | no cubierto en lo viejo |
| X8 libro de importadora sin moneda | 6 | cubierto |
| X9 tasa del cliente | 2 | cubierto |
| X10 cancelar recepción no revierte costo | 6 | cubierto |
| X11 ajuste como válvula | 2 | cubierto |
| 30.038 `costo_real` NULL en Main | 0b | cubierto vía pase + backfill |
| `app_cont_tipo_costo` vacío | 6 | cubierto al sembrarlo |
| Datos de prueba del fondo en `newa` | 1-2 | cubierto: respaldo + verificación |
| **Sin credenciales de git: no hay `fetch`/`pull`** | 0 | **abierto**: hay que configurar credenciales o el dueño debe traer los commits |
| No hay migraciones versionadas | todas | mitigado, no resuelto |
| Devoluciones / notas de crédito | 8 | decisión pendiente |
| Offline / borrador local en compras | — | fuera de alcance |

---

## Preguntas al dueño

Ninguna bloqueante. Una operativa:

- **Credenciales de git**: sin ellas no se puede `pull` de `multimoneda`. O las configuras, o me pasas los
  commits. Mientras tanto, todo lo verificado vale para `2bff5b18`.

---

## Cómo arrancar

```
Lee docs/planes/fondo-inversion/PLAN.md y ejecuta la fase 0.
```