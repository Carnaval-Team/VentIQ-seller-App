# Fondo de Inversión → Compras → Recepción → Consumo — plan de implementación

**Versión 4** · 2026-11-19 · Las 8 decisiones cerradas. Sin preguntas abiertas.
Incorpora también la revisión adversarial (`06-revision-adversarial.md`). Si algo choca con un anexo,
**manda este archivo**; los anexos son evidencia, no contrato.

## Objetivo

Al terminar, el admin de `ventiq_admin_app` puede: registrar una **compra** con proveedor, factura,
líneas (producto, cantidad, costo unitario) y total calculado; **financiarla con una sola fuente** —
saldos del Fondo de Inversión repartidos en varias cuentas y monedas, **o** aportes de inversores que
la cubren al 100% — sin poder gastar dos veces el mismo dinero; **recepcionar** la mercancía (total o
parcial, una o varias facturas en la misma carga) contra esa compra, capturando el **cargo variable de
importadora** con su porcentaje editable y sus reembolsos, más los costos adicionales por producto; y
ver en todo momento **disponible, comprometido, ejecutado y pendiente de recibir**, con recordatorios
de facturas con productos faltantes. Todo movimiento de dinero es idempotente, transaccional y
conciliable.

**No-goals:** reescribir el módulo de importadora (`imp_*`), devoluciones/notas de crédito al
proveedor, caducidad automática de reservas, pago mixto fondo+inversores, reescribir el histórico de
`fdi_dat_inversion`, reenumerar migraciones. No se toca `ventiq_app` ni `ventiq_superadmin` salvo el
punto explícito de la fase 8 sobre `precio_promedio`.

---

## Progress

| Fase | Estado |
|---|---|
| 0. Cimientos: rama, proyecto, baseline, convención SQL | not started |
| 1. Motor de dinero I: integridad, escala y conciliación | not started |
| 2. Motor de dinero II: idempotencia, tasa y gasto vinculado | not started |
| 3. Compra como documento | not started |
| 4. Reserva y liquidación (solo `al_pagar`) | not started |
| 5. Recepción contra compra (multi-factura y cargo de importadora) | not started |
| 6. Costo aterrizado (importadora + adicionales) | not started |
| 7. Inversores aportantes (100% de la compra) | not started |
| 8. Reportes, conciliación en UI y cierre | not started |
| 9. Pendientes, recordatorios y registro de faltantes | not started |

Current phase: 0 · Recommended next: 0

> Agente ejecutor: al terminar tu corrida, actualiza esta tabla y anota debajo una línea por
> desviación. No marques `done` sin haber corrido los criterios de salida y sin el OK del dueño.

### Bitácora de desviaciones
<!-- fase · qué cambió · por qué -->

---

## Decisiones y contexto

### Cerradas por el dueño (2026-11-19)

- ✔ **PD1 — El dinero se compromete al crear y sale al pagar.** `politica_pago = al_pagar` es la
  única política de esta iteración. `por_recepcion` queda documentada como deuda futura, **no** se
  implementa: la reserva cubre el total y el pago lo ejecuta una acción explícita.
- ✔ **PD3 — El pago a la importadora es un cargo variable que SUMA al valor de la factura.** No es un
  gasto aparte ni un "servicio" opcional: es componente del costo. Se captura **en la recepción**, con
  **porcentaje editable y distinto en cada recepción**, y **admite reembolso** (ej.: pagué por el
  producto, llegó, y digo "reembólsame la mitad"). El módulo de wallet de importadora **se queda como
  está**; no se reescribe.
- ✔ **PD4 — El pago exclusivo es dinero de los inversores al 100%.** Si una compra se liquida en modo
  inversores, **nada** sale del fondo de inversión; si se liquida en modo fondo, los inversores no
  participan. Nunca mixto.
- ✔ **PD6 — En una recepción de compra con factura solo pueden aparecer los productos de esa compra.**
  Decidido por el cliente. No se bloquea catálogo ni stock: se restringe la selección.
- ✔ **Aportes de inversores NO se acumulan en la gestión del fondo.** El dinero de un aporte vive
  atado a su compra: no entra en `fdi_dat_saldo`, no aparece como saldo del inversor en el módulo del
  fondo, y no se mezcla con su porcentaje de utilidad (que es otra cosa y sigue aparte).
- ✔ **PD2 — Manda la suma de líneas, no el total de la factura.** `total_mercancia = Σ(cantidad ×
  costo unitario)`. El total de factura es control: si no cuadra, la compra se guarda pero **no se puede
  reservar** hasta que dueño/gerente declare el motivo (queda en historial). Nunca se recalcula el costo
  unitario para "cuadrar": eso convierte un error de captura en un costo falso.
- ✔ **PD5 — Se aprueban 7 estados:** `creada, reservada, pagada, entrega_parcial, completada,
  cancelada, anulada`. `reservada` existe para colgar el dinero comprometido; `anulada` para revertir un
  pago con contramovimiento en vez de reescribir el ledger.
- ✔ **PD7 — Sin IVA ni descuentos por línea en esta iteración.** Se captura el costo neto unitario.
  **Advertencia:** si el IVA de compras es acreditable, capitalizarlo infla el costo y hunde el margen;
  en ese caso entra como componente con `afecta_inventario = false`. Lo no recuperable (aduana, flete,
  seguro, cargo de importadora) sí capitaliza.
- ✔ **PD8 — El fondo NO paga el cargo de importadora.** `origen_pago = wallet_importadora` por defecto,
  siempre: el cargo **capitaliza al costo** y nadie lo vuelve a desembolsar. Motivo: la wallet se recarga
  por su cuenta; si esa recarga sale del fondo, volver a pagar el cargo por compra lo cuenta dos veces y
  el sistema no podría detectarlo. Si algún día el fondo debe pagarlo, es un flag y un camino de pago —
  aditivo, no reescritura. **Consecuencia:** la pregunta "¿el % está dentro de `imp_dat_factura.valor`?"
  deja de bloquear; solo cambia la **base** del cálculo, y la fase 6 muestra el desvío (`Σ cargos` vs
  `Σ valores de factura vinculados`) sin corregirlo sola.

> Nota de método: intenté resolver PD8 con datos (las 26 facturas de importadora del proyecto). El único
> patrón aparente —múltiplos exactos de 1,20— **no resistió** la prueba exacta en centavos (10 de 26), así
> que se descartó. PD8 se cerró por decisión, no por inferencia.

### Arquitectura

- ✔ **La compra es entidad nueva** (`fdi_dat_compra*` + `fn_fdi_compra_*`), no una reinvención de
  `fdi_dat_inversion`. Esta queda **congelada como legado**: sin campos nuevos, sin compras nuevas, y
  su alta se retira de la UI en fase 8. Su semántica es inversa (debita al crear y acumula "recibido"
  en dinero, no en cantidades).
- ✔ **El fondo es `fdi_dat_saldo`**, grano **(cuenta × medio de pago × moneda)**. No existe "saldo de
  la cuenta". La compra **reutiliza** ese libro y su ledger; no se crea un quinto libro.
- ✔ **Un solo sentido de tasa: `T(A→B)` = unidades de B por 1 de A**, con el par explícito. *(v2)*
  `fn_fdi_transferir` **no se toca**: se crea `fn_fdi_transferir_v2` con par explícito y la v1 queda
  delegando con su inversa. Cambiar la semántica de la v1 sin cambiar su firma rompería el cliente
  desplegado (`fondo_inversion_service.dart:389`) con un factor de 10³ en dinero real.
- ✔ **La reserva no es un movimiento.** `disponible = saldo − reservado`, en **moneda nativa** por
  (cuenta, medio, moneda). Validar por cuenta, nunca por el total consolidado del fondo.
- ✔ **Dos tasas congeladas por documento**: factura (congela costo) y pago (congela salida). La
  diferencia cambiaria va a **resultado financiero**, jamás al inventario.
- ✔ **Tres cifras separadas** *(v3, amplía la v2)*: `total_mercancia` (Σ líneas), `total_financiado`
  (lo que paga el fondo o los inversores, incluye el cargo de importadora **si su origen de pago es el
  fondo**) y `costo_aterrizado` (todo lo que capitaliza: mercancía + cargo de importadora + adicionales,
  **incluido lo que pagó la wallet**). El `total_financiado` es inmutable tras reservar; el
  `costo_aterrizado` crece con documentos de ajuste.
- ✔ **Cada componente de costo lleva `origen_pago ∈ {fondo, wallet_importadora, wallet_proveedor,
  externo}`.** Es lo que hace estructuralmente imposible contar dos veces el mismo desembolso: un
  componente capitaliza siempre, pero solo se financia si su origen es `fondo`.
- ✔ **El costo se valoriza al recibir, no al pagar.** Recepción parcial: el costo global se reparte
  **solo sobre lo recibido**; el resto queda "por asignar". Reparto por **valor** por defecto.
- ✔ **Obligatoriedad por DEFAULT, no por firma**: todo parámetro nuevo de una RPC existente entra con
  `DEFAULT` para no romper a los llamadores desplegados.

### Dinero: los cinco eventos

| Evento | Estado | ¿Sale dinero? | Asiento |
|---|---|---|---|
| Se crea la compra (mercancía + cargo de importadora declarado) | `creada` | No | ninguno |
| Se cubre `total_financiado` con una fuente | `reservada` | No | reservas activas |
| Se confirma el pago | `pagada` cuando `Σ pagos = total_financiado` | Sí, por lo pagado | consume reserva + `pago_compra` |
| Llega mercancía parcial | `entrega_parcial` | No | valoriza inventario |
| Llega todo | `completada` | No | valoriza inventario |
| Se ajusta el % de importadora al recepcionar | no cambia de estado | Solo si su origen es `fondo` | ajuste financiado o reembolso |
| Llega un costo después de pagar | no cambia de estado | Solo si su origen es `fondo` | reserva + pago del ajuste + documento de costo |
| Se abandona sin pagos | `cancelada` | No | libera reservas |
| Se abandona con pagos | `anulada` | Sí (reversa) | contramovimiento |

**La recepción no mueve dinero por sí sola.** Mueve inventario, estado y costo. El dinero lo mueve un
**pago**. Esa separación es la que permite conciliar.

### Restricciones del entorno

- **No hay rama `dev`.** `git branch` muestra `main` más ramas ad-hoc (`mkarla`, `new-task-*`,
  `devin/...`) y **11 ramas `worktree-agent-*`**. `git status` real: **6 modificados** y **3 sin
  trackear** (`dist/`, `docs/planes/`, `tools/upload_offline_map.mjs`). Fase 0 crea `dev` con
  `git switch -c dev origin/main` y decide si `docs/planes/` se versiona.
- **No hay convención de migración**: `supabase/migrations/` tiene 10 migraciones, ninguna del módulo
  `fdi_*`; no hay `config.toml` ni `db push`. La vía real es pegar SQL a mano. **Este plan no lo
  arregla**: entrega scripts numerados para que el dueño los aplique.
- **Deriva repo↔BD** (verificada 2026-11-19): `fn_fdi_gasto` **no existe** y el `CHECK` de
  `fdi_dat_movimiento` no admite `'gasto'`; las tablas `fdi_*` tienen **0 filas**;
  `app_dat_recepcion_productos.costo_real` es **`GENERATED ALWAYS`**; **`app_dat_producto_costo` y
  `app_dat_recepcion_producto_costo` no existen** (solo `app_cont_tipo_costo`), es decir
  `sql_updates/costos_adicionales_producto.sql` **nunca se aplicó**.
- **Solo lectura es una convención, no una capacidad**: el MCP expone `apply_migration` y
  `execute_sql`. El agente **no** aplica SQL por regla; fase 0 documenta URL y rol del proyecto.
- **Dos definiciones vivas del RPC de recepción**: convive una de 9 argumentos
  (`presentaciones_inventario/06_recepcion_sin_conversion.sql:61`,
  `sql_updates/fix_recepcion_inventario_al_completar.sql:100`) con la de 12. `CREATE OR REPLACE` con
  otra lista crea **overload**. Fase 5 designa la canónica, hace `DROP` del resto y verifica `pronargs`.

### Modelo de importadora (v3, según PD3 y PD8)

Hoy: la importadora es un **proveedor prepago**. El dueño carga saldo (`imp_dat_recarga_saldo`), cada
factura descuenta del saldo al crearse (`imp_dat_factura.valor`), y hay ciclo de estados
(*Procesando por Proveedor → Pagado a Importadora → En Recogida → Finalizado*). **Cero relación con la
recepción y con el costo del producto.**

Lo que se construye encima, sin tocar esa wallet:

| Concepto | Dónde vive | Regla |
|---|---|---|
| `pct_importadora` | por **compra dentro de la recepción** | editable, distinto en cada recepción |
| `base_importadora` | valor de la factura sobre el que se aplica | explícita, congelada |
| `monto_importadora` | `base × pct` | capitaliza al costo |
| `reembolso_importadora` | negativo, opcional | "reembólsame la mitad"; ajusta el cargo efectivo |
| `origen_pago` | `wallet_importadora` \| `fondo` | si es wallet, **solo capitaliza**; si es fondo, se reserva y se paga |
| Vinculación | `id_compra` en la factura de importadora | hoy no existe; se añade en fase 6 |

Ejemplo cerrado: factura de mercancía **2.000 USD**, `pct_importadora = 15%` → cargo **300 USD**;
el dueño pide reembolso de la mitad → **−150 USD**; cargo efectivo **150 USD**; costo aterrizado
**2.150 USD**; si el origen es la wallet, el fondo sigue financiando solo **2.000**.

### Multi-factura en una sola carga (v3)

"Una rastra puede venir con 4 facturas, cada una con su pago a la importadora." Por tanto:

- **Una operación de recepción puede cubrir N compras.** `fdi_dat_compra_recepcion` cambia
  `UNIQUE(id_operacion)` por **`UNIQUE(id_operacion, id_compra)`**.
- Cada línea de recepción sabe a qué compra pertenece, y solo se pueden elegir productos **de la
  compra seleccionada** (PD6).
- Cada compra de la carga lleva su propio `pct_importadora` y su propio reembolso.
- El estado (`entrega_parcial` / `completada`) se calcula **por compra**, no por la carga.

### Stack y convenciones

- Flutter 3.44 / Dart 3.12; `provider` + `ChangeNotifier`; `ventiq_admin_app` con `sdk: ^3.10.0`.
- Shell: `$env:APPDATA = 'C:\Users\cesar\Documents\VentIQ-seller-App\.dsh\dart-tool'` antes de
  `flutter`, o el CLI muere con `PathAccessException`.
- Rutas `'/kebab-case'` en `main.dart`; permisos por ruta en `permissions_service.dart:732`.
- UI: reutilizar el **molde "saldo de tercero"**, el **chip de estado con color del nomenclador** y el
  **panel plano FDI**. Prompts de Stitch listos en `04-diseno-ux.md`.

### Documentos

| Documento | Para qué |
|---|---|
| `00-auditoria-programador.md` | contrato real de tablas/RPCs, gaps, riesgos R1-R9 |
| `01-analisis-funcional.md` | dominio, invariantes I1-I15, máquina de estados, casos borde |
| `02-contabilidad.md` | fórmulas de costo, reserva, tasas, redondeo, reportes, riesgos X1-X11 |
| `03-almacen.md` | flujo real de recepción, lotes, huecos operativos, modelo de importadora |
| `04-diseno-ux.md` | pantallas, responsive, prompts de Stitch |
| `05-referencia-industria.md` | práctica estándar y fuentes |
| `06-revision-adversarial.md` | 44 hallazgos sobre la v1; la v2/v3 son la respuesta |
| `ventiq_admin_app/lib/sql/fondo_inversion_schema.sql` | esquema del fondo que se reutiliza |

> **Nota de numeración:** los anexos usan su propia numeración de fases y decisiones (`01` llama
> "fase 1" al modelo de dominio; `03` se rotula "Fase 2"; `02` tiene D1-D5). Las decisiones de este
> plan son **PD1-PD8** y las fases son las de la tabla de Progress. No hay equivalencia uno a uno.

---

## Regla de ejecución

Al empezar cada fase, verifica este plan contra el repo vivo y las desviaciones anotadas. No reabras
decisiones cerradas sin evidencia nueva. Si una suposición se cae, **para, actualiza este archivo y
dilo**; no improvises en silencio.

1. **Ningún cambio de dinero sin transacción.** Una sola transacción por RPC; falla entera o no falla.
2. **Idempotencia por columna** (`idempotency_key uuid UNIQUE`), no por texto.
3. **Ledger append-only.** Las correcciones son contramovimientos con documento propio.
4. **Un desembolso, un origen.** Un mismo pago no puede tocar la wallet de importadora y el fondo a la
   vez. Se impone con `origen_pago` + constraint, no con disciplina.
5. **La UI no calcula dinero.** Tasas, totales, porcentajes y redondeos se resuelven en servidor.
6. **Compatibilidad**: parámetros nuevos siempre con `DEFAULT`; cambio de semántica = RPC nueva.
7. **Toda tabla nueva lleva RLS** y solo escribe por RPC `SECURITY DEFINER`.
8. **Cada fase deja el repo verde**: `flutter analyze` sin errores nuevos + tests de la fase.

---

## Protocolo de entrega

**Código:** rama `dev`, commits por fase, sin push a `main` sin OK. Al final de cada fase: `git diff
--stat dev` y lista de archivos.

**SQL:** cada fase entrega `ventiq_admin_app/lib/sql/compra/`:
- `NN_descripcion.sql` — idempotente, `BEGIN; … COMMIT;`, con bloque final de verificación que hace
  `RAISE` si el esquema no quedó como se esperaba.
- `NN_descripcion_rollback.sql` — revierte, o dice por qué no es reversible.
- `verify/NN_verificacion.sql` — solo `SELECT`, devuelve `ok|falla` por comprobación.
- Encabezado `-- REQUIERE: NN, NN` con el orden.

El dueño aplica **primero en dev**, corre `verify/`, y solo tras su E2E aplica a producción.

**E2E:** cada fase entrega una lista numerada de pasos literales en la app dev: qué hacer, qué debe
verse, qué haría fallar. **Sin OK del dueño no se abre la fase siguiente.**

---

# Fases

---

## Fase 0 — Cimientos

**Objetivo:** saber exactamente sobre qué se construye, poder revertir, y confirmar la deriva.

**Build:**
- `git switch -c dev origin/main`. Decidir y documentar qué pasa con los 6 modificados y 3 sin
  trackear (no se mezclan con este trabajo). Enumerar las 11 ramas `worktree-agent-*`.
- Identificar el proyecto Supabase conectado (`supabase/.temp/linked-project.json`) y responder: ¿es
  el mismo que producción? ¿producción tiene filas en `fdi_dat_saldo`? ¿`fn_fdi_gasto` existe en
  producción? ¿`costo_real` es generada también allí?
- Baseline de esquema en `docs/planes/fondo-inversion/baseline/`: `information_schema.columns` y
  `pg_get_functiondef` de `fdi_*`, `app_dat_recepcion_productos`, `app_dat_operacion_recepcion`,
  `app_cont_tipo_costo`, `imp_*`, `prv_*`; y `pg_proc` con `pronargs` de
  `fn_registrar_recepcion_con_inventario`.
- `lib/sql/compra/README.md` con el protocolo y el orden.
- `verify/00_linea_base.sql`: (a) las 15 tablas `fdi_*` existen; (b) `fdi_dat_movimiento` admite los
  tipos que el repo espera; (c) `fn_registrar_recepcion_con_inventario` tiene 12 args y **cuántas
  sobrecargas** hay; (d) `costo_real` es `GENERATED` o no; (e) existen o no `app_dat_producto_costo` y
  `app_dat_recepcion_producto_costo`; (f) `imp_dat_factura` tiene columnas de moneda y de compra.
  **Es el semáforo de deriva y lo que dimensiona las fases 5, 6 y 9.**

**Checklist:**
- [ ] Rama `dev` creada; estado del árbol documentado
- [ ] Proyecto Supabase identificado (URL + rol), dev vs prod respondido
- [ ] Baseline capturado
- [ ] `README.md` con el protocolo
- [ ] `00_linea_base.sql` con sus 6 comprobaciones

**Exit criteria:**
- `git branch --show-current` → `dev`
- `cd ventiq_admin_app; $env:APPDATA='...\.dsh\dart-tool'; flutter analyze` → sin errores (warnings
  preexistentes listados uno a uno)
- `verify/00_linea_base.sql` ejecutado **por el dueño** devuelve `ok` o el detalle exacto de la deriva

---

## Fase 1 — Motor de dinero I: integridad, escala y conciliación

**Objetivo:** que el fondo no pueda descuadrar por los caminos que ya existen, y poder probarlo.

**Build:**
- `_fdi_aplicar_movimiento`: validar que `p_id_tienda` corresponda a la cuenta y que medio/moneda sean
  coherentes con la tienda (R1: hoy mueve el saldo correcto y registra el movimiento en otra tienda).
- `fn_fdi_vincular_recepcion`: `FOR UPDATE` sobre la inversión antes de decidir el exceso (R3).
- `fn_fdi_inversion_anular(p_id_inversion, p_motivo)`: devuelve al fondo lo no consumido con
  contramovimiento, deja historial y requiere estado `anulado` (R2: hoy el dinero es irrecuperable).
- **Escala del ledger** (A10/R6): migrar `fdi_dat_saldo.saldo` y `fdi_dat_movimiento.monto/saldo_*` a
  `numeric` con escala por `monedas.decimales`; redondeo en servidor, residuo a la línea de mayor base.
  Sin esto la conciliación "0,00" no significa nada.
- **R7**: `fn_fdi_repartir_ganancia` revienta si no hay inversores activos y sobrescribe
  `monto_ganancia_retirada`. Corregir para que no bloquee liquidaciones sin reparto ni pise lo pedido.
- `fn_fdi_conciliacion(p_id_tienda)`: por (cuenta, medio, moneda) devuelve `saldo`, `Σ movimientos`,
  `último saldo_nuevo` y la diferencia. **Debe dar 0,00 siempre.**

**Checklist:**
- [ ] R1 cerrado con test de regresión
- [ ] R2: anulación con devolución de saldo
- [ ] R3: `FOR UPDATE` en vinculación
- [ ] R6/A10: escala migrada en el ledger
- [ ] R7: reparto no bloqueante ni sobrescrito
- [ ] `fn_fdi_conciliacion` en verde con datos de prueba

**Exit criteria:**
- `verify/01_motor_dinero.sql` en verde: conciliación 0,00 tras ingreso → gasto → ajuste →
  transferencia → anulación
- Test de anulación: inversión de 1.000 USD anulada → saldo vuelve al inicial, conciliación 0,00
- `flutter analyze` sin errores nuevos; `flutter test` del módulo fondo sin regresiones
- E2E del dueño aprobado

**E2E del dueño:**
1. Ingresar 1.000 USD a una cuenta del fondo.
2. Crear una inversión de 500 USD → saldo 500.
3. Anularla con motivo → saldo 1.000 y movimiento de reversa visible.
4. Abrir la conciliación → **diferencia 0,00 en todas las líneas**.

---

## Fase 2 — Motor de dinero II: idempotencia, tasa y gasto vinculado

**Objetivo:** cerrar los caminos de duplicación y el descuadre aritmético.

**Build:**
- **Idempotencia real** (R5): `idempotency_key uuid UNIQUE` en `fdi_dat_movimiento` con índice único
  parcial por `tipo`, migrando los históricos que hoy llevan `observacion LIKE '%idem:%'`. Aplicar a
  `fn_fdi_ingreso_manual`, `fn_fdi_ajuste`, `fn_fdi_gasto`. Hoy dos reintentos concurrentes duplican el
  asiento.
- **`fn_fdi_transferir_v2`** con par explícito (`moneda_origen`, `moneda_destino`, `tasa` con
  `T(origen→destino)`), validación de cordura (rechazar si la tasa se aparta >20 % de la última
  conocida del mismo par) e inversa desnormalizada. **La v1 no se modifica.** Es el descuadre
  invisible X2: libros que cuadran y 999.999 CUP perdidos.
- **`fn_fdi_gasto` con `p_id_compra`** (A5): rechazar el gasto si la compra tiene reserva o pago vivo.
  Hoy es el puente abierto para financiar dos veces la misma compra (R4).
- **X9**: que la tasa de los pagos de compra se resuelva **en servidor** desde el histórico por fecha;
  el cliente no la provee.
- **X11**: `fn_fdi_ajuste` con motivo estructurado y doble aprobación sobre un umbral configurable.
- Crear `fn_fdi_gasto` en el entorno si la fase 0 confirmó que falta.

**Checklist:**
- [ ] Idempotencia UUID en las 3 RPCs, históricos migrados
- [ ] `fn_fdi_transferir_v2` + v1 intacta
- [ ] `id_compra` en gasto con rechazo si hay reserva/pago vivo
- [ ] Tasa resuelta en servidor
- [ ] Ajuste con motivo estructurado y umbral

**Exit criteria:**
- `verify/02_idempotencia_tasa.sql` en verde
- Test de concurrencia: dos `fn_fdi_ingreso_manual` con la misma key en paralelo → **un** movimiento
- Test de tasa invertida: la v1 sigue comportándose igual (no regresión) y la v2 rechaza una tasa fuera
  del ±20 %
- `flutter analyze` sin errores nuevos
- E2E del dueño aprobado

**E2E del dueño:**
1. Doble clic en "Ingreso" → un solo movimiento.
2. Transferencia con la tasa tecleada al revés → rechazo con mensaje, no descuadre.
3. Gasto del fondo apuntando a una compra ya reservada → rechazo.
4. Conciliación sigue en 0,00.

---

## Fase 3 — Compra como documento

**Objetivo:** que exista la compra: proveedor, factura, líneas, cargo de importadora declarado, total,
numeración y permisos.

**Bloqueada por:** nada. Las 8 decisiones están cerradas (v4).

**Build:**
- `fdi_dat_compra`: `id_tienda, numero_compra, id_proveedor, numero_factura, fecha_factura,
  moneda_total, tasa_factura, total_mercancia, total_ajustes, total_financiado, costo_aterrizado,
  modo_liquidacion, politica_pago, estado, observacion, idempotency_key, created_by`.
- `fdi_dat_compra_linea`: `id_compra, id_producto, id_variante, id_presentacion, cantidad,
  costo_unitario, costo_linea GENERATED, id_almacen, id_ubicacion` (almacén destino por línea).
- `fdi_dat_compra_ajuste`: `id_compra, id_tipo_costo, base ∈ {global, unidad, porcentaje}, valor,
  reparto ∈ {valor, peso, cantidad}, monto_capitalizado, afecta_inventario, origen_pago,
  estado ∈ {declarado, por_financiar, financiado}`. El **cargo de importadora declarado** entra aquí
  con `id_tipo_costo = importadora` y su `pct_importadora` inicial (estimado). Los que llegan después
  nacen `por_financiar`.
- `fdi_hist_estado_compra` append-only; `fdi_dat_compra_recepcion` y `_linea` (vacías hasta fase 5).
- Restricciones: índice único parcial en `(id_tienda, id_proveedor, numero_factura) WHERE
  numero_factura IS NOT NULL`; `CHECK(cantidad > 0)`, `CHECK(costo_unitario >= 0)`;
  `origen_pago` NOT NULL con default `fondo` en ajustes de mercancía. `total_financiado` recalculado por
  trigger desde líneas + ajustes con `origen_pago = fondo`. Numeración `numero_compra` por tienda con
  secuencia y sin huecos por concurrencia.
- RLS en las 5 tablas nuevas + `GRANT SELECT` a `authenticated`; escritura **solo** por RPC.
- RPCs: `fn_fdi_compra_crear`, `fn_fdi_compra_editar` (solo en `creada`), `fn_fdi_compra_listar`,
  `fn_fdi_compra_detalle`, `fn_fdi_compra_cancelar`. Todas con idempotencia y validación de tienda.
- UI: listado + alta + detalle. Stitch: `COMPRAS — listado`, `COMPRA — alta`, `COMPRA — detalle`.
  Ruta `/compras`, entrada en `admin_drawer.dart`, permisos dueño/gerente.

**Checklist:**
- [ ] 5 tablas + constraints + trigger de total + numeración
- [ ] RLS y permisos
- [ ] Cargo de importadora declarado y campo de origen de pago
- [ ] 5 RPCs con idempotencia
- [ ] Pantallas Stitch aprobadas antes de implementar
- [ ] Listado con filtros y totales; alta con cálculo revalidado en servidor
- [ ] Responsive en los 3 tamaños

**Exit criteria:**
- `verify/03_compra.sql` en verde: factura duplicada rechaza; `costo_linea` no se puede escribir a
  mano; `total_financiado = total_mercancia + ajustes con origen fondo`; dos altas concurrentes no
  repiten `numero_compra`
- `flutter test` de modelos/servicio nuevos en verde
- `flutter analyze` sin errores nuevos
- E2E del dueño aprobado

**E2E del dueño:**
1. Crear compra con 3 productos y un cargo de importadora del 15% → el total coincide con la suma a mano.
2. Cantidad 0 → rechazo con mensaje claro.
3. Duplicar número de factura del mismo proveedor → rechazo.
4. Abrir en móvil, tablet y PC → legible en los tres; en PC todas las columnas.
5. Cancelar sin pagos → `cancelada`, sin rastro de dinero.

---

## Fase 4 — Reserva y liquidación (solo `al_pagar`)

**Objetivo:** financiar la compra con una sola fuente, sin gastar dos veces el mismo dinero, con el
faltante bloqueando.

**Bloqueada por:** nada (v4: PD2 cerrada).

**Build:**
- `fdi_dat_compra_reserva` (`id_compra, id_cuenta, id_medio_pago, moneda, monto, estado, id_movimiento`)
  + `fn_fdi_disponible(p_id_tienda)` → `saldo`, `reservado`, `disponible` por (cuenta, medio, moneda).
- `fdi_dat_compra_pago` (`id_compra, id_cuenta, id_medio_pago, moneda, monto, tasa_a_total,
  monto_eq_total, origen ∈ {fondo, aporte}, id_aporte`). `modo_liquidacion` **inmutable** tras
  `reservada`, impuesto por constraint/trigger.
- `fn_fdi_compra_reservar`: valida `Σ disponible ≥ 0` **por (cuenta, medio, moneda)**. Si no cubre,
  rechaza y dice **cuánto falta en cada moneda**.
- `fn_fdi_compra_pagar` con **orden fijo**: 1) valida disponible con la reserva viva, 2) consume la
  reserva, 3) debita con `_fdi_aplicar_movimiento` tipo `pago_compra`, todo en la misma transacción.
  Debita antes de consumir revienta el `CHECK saldo >= 0`; consumir antes de validar hace la
  comprobación inútil.
- `fn_fdi_compra_liberar` (cancelación, motivo obligatorio + usuario) y `fn_fdi_compra_anular`
  (contramovimiento de lo pagado no consumido + liberación).
- Extender `fdi_dat_movimiento` con `id_compra` y **`tasa`** (hoy no hay columna de tasa: sin ella un
  movimiento en otra moneda no se puede re-expresar después).
- UI: asistente de liquidación multimoneda con **faltante en vivo y bloqueante**, tasa visible (no en
  un `ExpansionTile` cerrado) y confirmación explícita. Stitch: `LIQUIDACIÓN — multimoneda (desktop)`
  y `(móvil)`.

**Checklist:**
- [ ] Reservas por (cuenta, medio, moneda) + `fn_fdi_disponible`
- [ ] `modo_liquidacion` inmutable en BD
- [ ] Reservar valida por cuenta, no por total
- [ ] Pagar con orden fijo documentado y atómico
- [ ] Cancelar libera; anular revierte
- [ ] `id_compra` + `tasa` en el ledger
- [ ] Asistente con faltante bloqueante y tasa visible

**Exit criteria:**
- `verify/04_liquidacion.sql` en verde: dos compras que juntas exceden el disponible → la segunda se
  rechaza **antes** de reservar; tasa fuera de cordura se rechaza; `modo_liquidacion` no cambia tras
  `reservada`; conciliación 0,00 tras reservar → pagar → anular
- `flutter analyze` sin errores nuevos
- E2E del dueño aprobado

**E2E del dueño (números fijos):**
1. Compra de **2.000 USD**. Cuenta suiza USD con 1.000; cuenta Venezuela CUP con 20.000.
   Tasa **1 USD = 1.000 CUP** → los 20.000 CUP son **20 USD**. Cubierto: 1.020 USD.
2. Reservar → el sistema muestra **faltan 980 USD** y **no deja cerrar**.
3. Añadir otra fuente hasta cubrir → `reservada`; el **disponible** de cada cuenta baja aunque el saldo no.
4. Pagar → `pagada`; saldo debitado; disponible y saldo vuelven a coincidir.
5. Cancelar otra compra reservada → el disponible vuelve **exactamente** al valor previo.
6. Crear una segunda compra con el dinero ya reservado por la primera → rechazo.

---

## Fase 5 — Recepción contra compra (multi-factura y cargo de importadora)

**Objetivo:** que la mercancía entre contra la compra, por cantidades, con una o varias facturas en la
misma carga, capturando el cargo variable de importadora con su reembolso, sin sobre-recepción
silenciosa ni recepciones fantasma.

**Build:**
- `fdi_dat_compra_recepcion` (`id_compra, id_operacion, monto_valorizado, moneda, tasa_a_base`) con
  **`UNIQUE(id_operacion, id_compra)`** *(v3: una carga puede traer 4 facturas → una operación, cuatro
  compras)*.
- `fdi_dat_compra_recepcion_linea` (`id_compra_linea, cantidad_recibida, costo_unitario_aplicado,
  id_recepcion_producto`). Sin ella no se sabe si la entrega parcial es de las líneas 1-3 o 4-5.
- **Cargo de importadora por recepción** *(v3)*: `pct_importadora`, `base_importadora`,
  `monto_importadora`, `reembolso_importadora`, `origen_pago` — **por compra dentro de la recepción**,
  editables antes de confirmar, con historial de quién cambió qué. Distinto en cada recepción.
- **Restricción de productos (PD6)**: al añadir una línea se elige primero la compra y solo se ofrecen
  sus productos con pendiente > 0. Producto fuera de la compra → bloqueado. **Producto no previsto**:
  se resuelve como recepción **externa enlazada**, nunca metiéndolo en la compra (si no, se rompe la
  restricción que el cliente aprobó).
- **`p_origen text DEFAULT 'externa'`** en la operación de recepción (`compra` | `externa`). Con
  DEFAULT no rompe a `ventiq_app`, ni a los RPC de transferencia entre layouts, ni a los egresos con
  rebalanceo. **No añadir un eje que contradiga `motivo`**: `origen` se **deriva** de `motivo`.
- **RPC canónica**: designar `fn_registrar_recepcion_con_inventario` (12 args) como la única viva,
  `DROP` de los overloads de 9 args y verificar `pronargs` + ausencia de sobrecargas.
- **Idempotencia de recepción**: `app_dat_operaciones.uuid` es el usuario, no la operación. Añadir
  `idempotency_key` a la operación y a la RPC; test de doble submit.
- **Atomicidad**: quitar el `EXCEPTION WHEN OTHERS` que devuelve JSON
  (`fondo_inversion_recepcion_patch.sql:287-303`): hoy un fallo posterior al INSERT deja una recepción
  fantasma y el almacenero reintenta duplicando.
- Pendiente por recibir: `fn_fdi_compra_recepcion_pendiente(p_id_compra)` por línea.
- Sobre-recepción: exige confirmación explícita y **no** aumenta lo pagado.
- **Un solo camino de stock**: usar `fn_contabilizar_recepcion_inventario` (el único que propaga
  `id_lote`) y **redirigir o deprecar** `fn_registrar_cambio_estado_operacion_mejorado` en el botón
  "Completar": hoy completa sin lote y rompe FEFO en toda recepción externa.
- `fecha_operacion` opcional para recepción retroactiva (hoy todo entra con `NOW()`).
- **Selector de carga**: al abrir la recepción, poder marcar **varias compras** (la rastra con 4
  facturas) y que cada bloque muestre su factura, proveedor y su % de importadora.
- UI: Stitch: `RECEPCIÓN — carga multi-factura (desktop)` y `(móvil)`.

#### Regla de recepciones múltiples (v3.1)

**Una compra admite N recepciones**, sin límite, hasta cubrir todas sus líneas. Cada recepción
descuenta del pendiente y el estado se deriva sola:

| Acumulado recibido (por compra) | Estado |
|---|---|
| 0 | `reservada` o `pagada` (según el dinero) |
| > 0 y < comprado | `entrega_parcial` |
| = comprado en **todas** las líneas | `completada` |

Fórmulas exactas (en servidor, nunca en la UI):

```
recibido(linea)  = Σ fdi_dat_compra_recepcion_linea.cantidad_recibida   (todas las recepciones)
pendiente(linea) = comprado(linea) − recibido(linea)                     (nunca < 0 sin confirmación)
estado(compra)   = 'completada'  si Σ pendiente(línea) = 0
                 = 'entrega_parcial' si Σ recibido > 0
                 = el estado de dinero en otro caso
```

Reglas asociadas:

- `cantidad_recibida` se guarda **por recepción**, no se acumula en la compra: el acumulado es siempre
  la suma. Así una recepción cancelada se resta sola al borrar su línea, sin tocar la compra.
- **El estado se calcula por compra**, aunque la operación cubra 4 compras en una carga: cerrar una
  factura no cierra las demás.
- `completada` es **irreversible**: no se puede añadir otra recepción a una compra completa salvo
  reapertura explícita con motivo y usuario (decisión de dueño/gerente, queda en historial).
- **Cierre corto**: si el proveedor no manda el resto, dueño/gerente puede cerrar la compra con
  pendiente > 0 usando `fn_fdi_compra_cerrar_corto(p_id_compra, p_motivo)`. Registra la diferencia,
  libera lo no usado y **no** reescribe el dinero ya pagado. Sin esto el pendiente queda eterno en la
  fase 9.
- **Ojo con el dinero** (consecuencia de PD1): al pagarse en el acto del pago, la compra puede estar
  `pagada` y recibida al 60%. El fondo ya desembolsó el 100%. **El pendiente es de mercancía, no de
  dinero**: no se "recupera" saldo al recibir menos, y la fase 9 lo muestra como faltante, no como
  deuda. Si algún día se quiere que el dinero siga a la recepción, es la política `por_recepcion`.

**Checklist:**
- [ ] Vínculo por cantidades, no solo por monto
- [ ] `UNIQUE(id_operacion, id_compra)` y carga multi-factura
- [ ] Cargo de importadora editable por compra y por recepción, con reembolso
- [ ] Solo productos de la compra (PD6) y camino explícito para el no previsto
- [ ] `origen` derivado de `motivo`, con DEFAULT en la firma
- [ ] RPC canónica y overloads eliminados
- [ ] Idempotencia de la operación de recepción
- [ ] Recepción atómica (sin fantasmas)
- [ ] Pendiente por recibir y sobre-recepción con confirmación
- [ ] Un solo camino de stock, con lote
- [ ] `fecha_operacion`

**Exit criteria:**
- `verify/05_recepcion.sql` en verde: `pronargs = 12` y sin sobrecargas; no se recibe de más sin
  confirmar; **tres recepciones parciales suman bien y el pendiente baja línea a línea**;
  **una operación con 4 compras genera 4 vínculos y calcula 4 estados independientes**; el lote
  sobrevive al completar; doble submit = una sola operación; cancelar una recepción devuelve el
  pendiente exacto sin tocar la compra
- `flutter test` de modelos de recepción en verde
- `flutter analyze` sin errores nuevos
- E2E del dueño aprobado

**E2E del dueño:**
1. Compra de 100 → recibir 60 → `entrega_parcial`, pendiente 40.
2. Recibir 40 → `completada`, pendiente 0.
3. Compra de 10, recibir 12 → exige confirmación y no cambia el total pagado.
4. **Carga multi-factura:** abrir una recepción y marcar 4 compras; cada bloque con su factura y su %
   de importadora; confirmar → las 4 quedan correctas e independientes.
5. Intentar añadir un producto que no está en la compra → bloqueado.
6. Producto no previsto → se registra como recepción externa enlazada, no dentro de la compra.
7. Producto por lotes → el stock conserva el lote tras completar.
8. **Atomicidad (literal):** ejecutar `verify/05_forzar_fallo.sql`, que hace `RAISE` en la segunda
   línea; la operación **no** debe quedar creada.
9. **Idempotencia (literal):** doble clic en "Guardar recepción" → una sola operación.

**E2E de recepciones múltiples (v3.1):**
1. Compra de 100 unidades → recibir 60 → `entrega_parcial` con pendiente 40.
2. Recibir **25** → sigue `entrega_parcial` con pendiente **15**. No hace falta recibir todo de golpe.
3. Recibir **15** → `completada`, pendiente 0. Una cuarta recepción debe rechazarse.
4. Compra con 3 líneas: recibir la línea 1 completa y las líneas 2-3 a medias → `entrega_parcial`
   hasta que **las tres** cierren, aunque una ya esté al 100%.
5. Cancelar la recepción del paso 2 desde el historial → el pendiente vuelve a 40 y el estado vuelve a
   `entrega_parcial`, sin tocar el dinero.
6. Reabrir una compra `completada` con motivo → permite recepcionar de nuevo y queda en historial.
7. Cerrar corto una compra con 15 pendientes y motivo → sale del panel de pendientes de la fase 9 y el
   dinero ya pagado no se altera.

---

## Fase 6 — Costo aterrizado (importadora + adicionales)

**Objetivo:** que el costo del producto sea el real, con el cargo de importadora y sus reembolsos, y
que la valoración del inventario lo refleje.

**Bloqueada por:** nada (v4: PD8 cerrada).

**Prerequisitos que la fase 0 confirmó ausentes:**
- `app_dat_recepcion_productos.costo_real` es **`GENERATED ALWAYS`**: hay que
  `ALTER TABLE … ALTER COLUMN costo_real DROP EXPRESSION`, hacer **backfill**
  (`= precio_unitario − descuentos`) y dejar un **rollback** que restaure la expresión.
- `app_dat_producto_costo` y `app_dat_recepcion_producto_costo` **no existen**:
  `sql_updates/costos_adicionales_producto.sql` nunca se aplicó. La fase 6 lo aplica **adaptado**, con
  verificación y rollback. No se asume nada: se lee, se ajusta al esquema real y se prueba en dev.

**Build:**
- **Cargo de importadora como componente de costo** *(v3)*: `pct` editable por recepción y por compra,
  `base` congelada, `monto` y `reembolso`. Se materializa en `app_dat_recepcion_producto_costo` (o su
  equivalente si el script se adapta) con `origen_pago`, y entra en `costo_real`.
- **Regla de un solo origen**: si `origen_pago = wallet_importadora`, el cargo **capitaliza y no se
  financia**; si es `fondo`, genera reserva + pago como ajuste `por_financiar`. Constraint + validación
  en RPC. Es la defensa contra X3.
- **Vinculación documental**: `id_compra` y `moneda` en `imp_dat_factura` / `prv_dat_factura` (hoy no
  existen). La factura de importadora deja de ser un libro ciego.
- Reparto del costo global por **valor** por defecto (cantidad/peso como excepción configurable),
  residuo a la línea de mayor base.
- Recepción parcial: el costo global se reparte **solo sobre lo recibido**; el resto queda "por
  asignar". Cargarlo todo infla el costo unitario 66,7 % en el ejemplo del flete de 100.000 para 100
  unidades recibiendo 60.
- `costo_real` poblado **siempre**, con o sin adicionales.
- Costos adicionales: catálogo por producto, valor aplicado **por línea de recepción**, dentro de la
  transacción. Eliminar el `catch { print }` de `inventory_service.dart:1394-1402`.
- Ajustes `por_financiar`: cada uno crea su propia reserva y pago (nunca mutan `total_financiado`) y
  generan un **documento de ajuste de costo** que actualiza la valoración sin reescribir el histórico.
- **`precio_promedio`**: verificar primero **cuál función está viva** — el defecto documentado está en
  `_v3`, que no tiene llamadores; la app usa `_v2`, que sí pondera por stock previo vía
  `fn_stock_saldos_presentacion`. Arreglar **la viva** y quitar el criterio si ya estaba bien.
- **Reversión de costo al cancelar recepción**: documento propio, verificable.
- UI: captura del % de importadora y del reembolso dentro de la recepción + administración del catálogo
  de costos. Stitch: `RECEPCIÓN — importadora y adicionales` y `CONFIG — costos adicionales`.

**Checklist:**
- [ ] `costo_real` deja de ser generada, con backfill y rollback
- [ ] Tablas de costos adicionales creadas y verificadas
- [ ] Cargo de importadora con %, base, reembolso y origen de pago
- [ ] Regla de un solo origen impuesta en BD
- [ ] `id_compra` + `moneda` en facturas de importadora/proveedor
- [ ] Reparto por valor con ejemplo numérico cerrado
- [ ] Recepción parcial no carga todo el costo
- [ ] `precio_promedio`: función viva identificada y corregida
- [ ] Reversión de costo al cancelar

**Exit criteria:**
- `verify/06_costo.sql` en verde: `costo_real` con `is_generated = 'NEVER'`; el ejemplo de 2.000 + 15 %
  − 50 % de reembolso = costo aterrizado **2.150** exacto, sin céntimos perdidos; si el origen es
  wallet, `Σ pagos del fondo = 2.000`; si es fondo, `= 2.150`; flete 100.000 / 100 u recibiendo 60 →
  60.000 aplicados y 40.000 por asignar; `precio_promedio` cuadra con la ponderación por stock previo
- `flutter analyze` sin errores nuevos
- E2E del dueño aprobado

**E2E del dueño:**
1. Compra con factura conocida; recepcionar con 15 % de importadora y flete.
2. El producto muestra el costo **aterrizado**, no el de factura.
3. Pedir reembolso de la mitad del cargo → el costo baja exactamente a la mitad del cargo.
4. Segunda recepción de la misma compra con **otro %** de importadora → cada recepción conserva el suyo.
5. Recepción parcial con costo global → el costo unitario de lo recibido no se infla.
6. Inventario valorado → coincide con el aterrizado aplicado.
7. Si el cargo es de la wallet → el fondo **no** aparece pagándolo (verificable en conciliación).

---

## Fase 7 — Inversores aportantes (100% de la compra)

**Objetivo:** que los inversores cubran una compra al 100%, con montos concretos y monedas concretas,
sin que ese dinero se acumule en el fondo ni se mezcle con el reparto de utilidad.

**Bloqueada por:** nada (v4: PD4 cerrada). `naturaleza` del aporte por defecto **`anticipo`**
(reembolsable, sin rendimiento), editable por aporte: `pasivo` si hay interés pactado, `capital` solo si
el inversor acepta pérdida. No hay que decidirlo ahora porque es un campo, no un esquema.

**Build:**
- `fdi_dat_compra_aporte` (`id_compra, id_inversor, moneda, monto, tasa_a_total, monto_eq_total,
  naturaleza ∈ {anticipo, pasivo, capital}, estado ∈ {comprometido, recibido, devuelto}, comprobante,
  idempotency_key`).
- **Aislamiento explícito**: el aporte **no** entra en `fdi_dat_saldo`, **no** genera saldo a favor del
  inversor en el módulo del fondo y **no** se mezcla con `fdi_dat_inversor.porcentaje`. Se registra
  contra la compra y muere con ella (se consume o se devuelve).
- **Exclusividad 100%**: si `modo_liquidacion = inversores`, no puede existir pago ni reserva con
  `origen = fondo` para esa compra, y `Σ aportes recibidos = total_financiado` antes de `pagada`.
  Impuesto en BD, no en UI.
- `fn_fdi_compra_aporte_registrar` (el aporte no excede el faltante al registrarse) y
  `fn_fdi_compra_aporte_devolver` (devolución = cancelación de pasivo; solo el interés es gasto si
  `naturaleza = pasivo`).
- UI: aportes por compra con "restante" en vivo y bloqueante. Stitch: `COMPRA — aportes de inversores`.

**Checklist:**
- [ ] Entidad de aporte separada del % de utilidad y aislada del libro del fondo
- [ ] Validación de faltante al registrar
- [ ] Exclusividad 100% impuesta en BD
- [ ] Devolución como cancelación de pasivo
- [ ] UI con restante bloqueante

**Exit criteria:**
- `verify/07_aportes.sql` en verde: los aportes suman al total y la compra pasa a `pagada`; un aporte
  que excede el faltante se rechaza; **no existe ningún movimiento en `fdi_dat_saldo` originado por un
  aporte**; no coexisten reserva de fondo y aporte; la devolución deja el saldo de aportes en cero
- `flutter analyze` sin errores nuevos
- E2E del dueño aprobado

**E2E del dueño:**
1. Compra 2.000 USD en modo inversores: X aporta 800, Y aporta 700 → restante 500 y **no deja pagar**.
2. Aportar los 500 → `pagada`.
3. Aportar 100 de más → rechazo.
4. Abrir el módulo de fondo → **ningún saldo nuevo**, ningún acumulado para X ni Y.
5. Devolver el aporte de X → saldo de aportes baja, compra consistente.
6. Intentar reservar del fondo la misma compra → rechazo por exclusividad.

---

## Fase 8 — Reportes, conciliación en UI y cierre

**Objetivo:** poder probar en cinco minutos que el dinero cuadra, y dejar documentación que sobreviva.

**Build:**
- Reportes R2-R7 de `02-contabilidad.md` §6.3: saldo/reservado/disponible por cuenta y moneda; compras
  por estado con facturado vs aterrizado vs pagado; costo real vs factura con % de desvío; diferencias
  cambiarias por documento; movimientos por usuario y día; inversores (aportes vs devoluciones vs
  utilidad vs pendiente).
- **Conciliación R1 en UI** con alarma visible y ejecución programada (no un dashboard que nadie mira).
- Aging de reservas activas y listado de compras con descuadre declarado.
- **Retirar el alta de `fdi_dat_inversion` de la UI** y marcar el módulo como legado de solo lectura.
- **Alinear la escritura de `precio_promedio` con `ventiq_app`**: su sync offline hace
  `.update({'precio_promedio': costo})` sin ponderar y deshace el arreglo de la fase 6. Se elige guardia
  en BD o parche acotado en `ventiq_app`, se documenta y se prueba con **las dos apps**.
- **Devoluciones/notas de crédito**: decisión explícita — o fase futura documentada, o se implementa.
- Cierre documental: `docs/planes/fondo-inversion/README.md` como índice, decisiones movidas a `docs/`,
  `CAPABILITY-MAP.md` actualizado si aplica.
- Revisión final de responsive en los 3 tamaños.

**Checklist:**
- [ ] R2-R7 implementados y enlazados
- [ ] Conciliación en UI con alarma
- [ ] Aging de reservas
- [ ] Alta de inversión retirada
- [ ] `precio_promedio`: decisión tomada y probada con las dos apps
- [ ] Devoluciones: decisión explícita
- [ ] Índice de documentación

**Exit criteria:**
- Todos los reportes cuadran con los datos de prueba de las fases 3-7
- Conciliación 0,00 en todas las líneas
- `flutter analyze` sin errores; `flutter test` completo del app en verde
- E2E integral aprobado

**E2E final del dueño:**
1. Ingresar saldo al fondo en dos monedas.
2. Crear compra multimoneda con 3 líneas, cargo de importadora y factura.
3. Reservar con dos cuentas; ver faltante; completar; pagar.
4. Recepcionar parcial con % de importadora, reembolso y flete.
5. Recepcionar el resto; verificar `completada` y costo aterrizado en el producto.
6. Conciliación → 0,00. Reporte de compras → `pagado = total_financiado` y
   `aterrizado = mercancía + importadora + adicionales`.
7. Repetir el flujo en modo inversores y comprobar que el fondo **no** se movió.
8. Abrir todo en móvil, tablet y PC.

---

## Fase 9 — Pendientes, recordatorios y registro de faltantes

**Objetivo:** que nunca se olvide una factura con productos sin llegar, y que exista un registro
detallado y exportable de todo lo que falta.

> Esta fase no estaba en la v2. El dueño la pidió explícitamente ("debe haber un recordatorio de
> facturas con productos pendientes y un registro detallado de facturas, compras y productos que
> faltan").

**Build:**
- **Panel de pendientes** (`/compras/pendientes`): una fila por compra abierta con factura, proveedor,
  fecha, días de antigüedad, % recibido, monto pendiente y estado. Ordenable por antigüedad y por monto.
- **Detalle de faltantes por producto**: por compra y por línea, `comprado`, `recibido`, `pendiente`,
  última recepción, días sin movimiento.
- **Recordatorios**: alerta en el home del admin con el número de compras con pendiente y su monto;
  notificación programada (reutilizar `local_notification_service.dart` / `notification_service.dart`)
  con umbral configurable (ej. avisar a los N días sin recepción completa).
- **Registro exportable**: exportación a Excel/PDF del listado de pendientes y del histórico de
  recepciones por compra, reutilizando `export_service.dart`.
- **Vista de facturas**: histórico de facturas de compra con su estado (pendiente, parcial, cerrada),
  enlazando a la compra y a sus recepciones.
- Permisos: el almacenero ve pendientes y recepciones; el dueño/gerente ve montos y exporta.
- Stitch: `PENDIENTES — panel (desktop)`, `(móvil)` y `PENDIENTES — detalle de faltantes`.

**Checklist:**
- [ ] Panel de pendientes con antigüedad, % recibido y monto
- [ ] Detalle de faltantes por producto y por línea
- [ ] Alerta en home + notificación con umbral configurable
- [ ] Exportación de pendientes e histórico
- [ ] Vista de facturas con su estado
- [ ] Permisos por rol
- [ ] Responsive en los 3 tamaños

**Exit criteria:**
- `verify/09_pendientes.sql` en verde: el pendiente por línea coincide con `comprado − recibido`; una
  compra `completada` **no** aparece en el panel; el monto pendiente cuadra con `total_financiado −
  pagado`
- `flutter test` de los servicios de pendientes en verde
- `flutter analyze` sin errores nuevos
- E2E del dueño aprobado

**E2E del dueño:**
1. Dejar una compra con 40 de 100 recibidos → aparece en el panel con 60 pendientes y su antigüedad.
2. Completarla → desaparece del panel.
3. Forzar el umbral de días → llega la notificación.
4. Exportar el panel → el archivo abre y los totales coinciden con la pantalla.
5. Abrir el detalle de faltantes por producto → coincide con el pendiente por línea.

---

## Riesgos: qué cubre cada fase y qué no

| Riesgo | Fase | Estado |
|---|---|---|
| R1 movimiento en tienda equivocada | 1 | cubierto |
| R2 dinero irrecuperable (inversión sin anular) | 1 | cubierto |
| R3 sobre-recepción por carrera | 1 | cubierto |
| R5 duplicado por reintento | 2 | cubierto |
| R6 / A10 escala y redondeo | 1 | cubierto (migración del ledger) |
| R7 reparto de ganancia bloqueante | 1 | cubierto |
| R4 / A5 doble financiamiento vía `fn_fdi_gasto` | 2 + 7 | cubierto (`id_compra` + exclusividad) |
| R8 totales por moneda sin consolidar | 8 | cubierto en reportes |
| R9 stock y billete divergen | 5 | cubierto (camino único con lote) |
| X1 doble uso del dinero | 4 | cubierto |
| X2 tasa invertida | 2 | cubierto (`_v2`, v1 intacta) |
| X3 doble costo de importadora | 6 | cubierto (`origen_pago` + constraint) |
| X8 libro de importadora sin moneda | 6 | cubierto (`moneda` en la factura) |
| X4 costo global a lo recibido | 6 | cubierto |
| X5 ponderación del promedio | 6 | cubierto, salvo `ventiq_app` (fase 8) |
| X6 reintento duplicado | 2 | cubierto |
| X7 moneda como texto libre | 1 parcial | **no cubierto en lo viejo**: se normaliza en lo nuevo |
| X9 tasa enviada por el cliente | 2 | cubierto |
| X10 cancelar recepción no revierte costo | 6 | cubierto |
| X11 ajuste como válvula de escape | 2 | cubierto (motivo + umbral) |
| No hay migraciones versionadas | todas | **mitigado, no resuelto** |
| Convivencia `fdi_dat_inversion` legado y compras | 8 | **mitigado**: alta retirada |
| Devoluciones / notas de crédito | 8 | **decisión pendiente** |
| Offline / borrador local en compras | — | **fuera de alcance** esta iteración |
| Rastra con 4 facturas | 5 | cubierto (`UNIQUE(id_operacion, id_compra)`) |
| % de importadora distinto por recepción | 5-6 | cubierto (por compra y por recepción, con historial) |
| Recordatorio de faltantes | 9 | cubierto |
| Multi-almacén / ubicación destino | 3 | cubierto (`id_almacen`/`id_ubicacion` por línea) |

---

## Preguntas al dueño

| # | Pregunta | Bloquea | Estado |
|---|---|---|---|
| PD1 | ¿El dinero sale al pagar o al recepcionar? | — | **cerrada**: reserva al crear, salida al pagar |
| PD2 | ¿Manda la factura o la suma de líneas? | — | **cerrada**: manda la suma de líneas; descuadre bloquea la reserva |
| PD3 | ¿Qué es el pago a la importadora? | — | **cerrada**: cargo variable que suma, % editable por recepción, con reembolso |
| PD4 | ¿Inversores aportan monto o siguen con %? | — | **cerrada**: aporte 100% en modo exclusivo, aislado del fondo |
| PD5 | ¿Se aprueban 7 estados? | — | **cerrada**: 7 estados, con `reservada` y `anulada` |
| PD6 | "Bloquear productos" | — | **cerrada**: solo los productos de la compra en la recepción |
| PD7 | ¿IVA/descuentos por línea? | — | **cerrada**: sin IVA; lo acreditable no capitaliza (`afecta_inventario = false`) |
| PD8 | ¿El % de importadora lo paga el fondo? | — | **cerrada**: no; `origen_pago = wallet_importadora` |

---

## Cómo arrancar

Sin preguntas abiertas: la fase 0 puede arrancar ya.

```
Lee docs/planes/fondo-inversion/PLAN.md y ejecuta la fase 0.
```