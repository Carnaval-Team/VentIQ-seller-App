# 01 — Análisis funcional: Fondo de Inversión → Compras

Analista funcional · Fase 1 (modelo de dominio, previo a SQL y a Stitch).
Leyenda: **[HECHO]** = verificado en el repo con cita. **[PROPUESTA]** = decisión a validar con el dueño. **[AUSENTE]** = no existe en el repo.

---

## 0. Resumen ejecutivo

- El **fondo** existe y opera de verdad: conceptos → cuentas → saldos por medio/moneda, ingresos, gastos, ajustes, transferencias multimoneda, liquidación de ganancia y reparto a inversores. **[HECHO]**
- La **compra NO existe** en ninguna forma. **[AUSENTE]** Lo que el dueño cree que ya está implementado es `fdi_dat_inversion`, que es otra cosa: una **extracción de dinero identificada por un texto**, sin productos, sin proveedor, sin factura y **sin reserva** — el dinero sale del fondo en el instante de crearla. **[HECHO]**
- La **recepción** ya sabe vincularse a esa "inversión" y acumular "recibido" contra "total", pero prorratea por **monto**, no por **cantidades**. **[HECHO]**
- Los **inversores** son socios con % de ganancia sobre liquidaciones; **no aportan montos a compras**. **[HECHO]** El pedido #5 del dueño exige un modelo nuevo, no una extensión.
- Faltan, por tanto: compra, líneas con producto/cantidad/costo unitario, pagos multimoneda repartidos, reserva de saldo, aportes de inversores, y los 5 estados pedidos.

---

## 1. Lo que ya está implementado (revisión previa obligatoria)

### 1.1 Fondo: sí existe **[HECHO]**

| Tabla | Rol | Cita |
|---|---|---|
| `fdi_dat_concepto` / `fdi_dat_cuenta` | estructura (concepto → cuentas) | `ventiq_admin_app/lib/sql/fondo_inversion_schema.sql:16,45` |
| `fdi_dat_saldo` | saldo por cuenta+medio+moneda, `CHECK (saldo >= 0)` | `…schema.sql:100-108` |
| `fdi_dat_movimiento` | ledger append-only con saldo anterior/nuevo y `tipo` | `…schema.sql:117-136` |
| `fdi_dat_liquidacion(+_detalle,_orden)` | entrada de ganancia de ventas | `…schema.sql:152,182,200` |
| `fdi_dat_transferencia` | traspaso multimoneda con tasa y comisión | `…schema.sql:218-243` |
| `fdi_dat_inversion(+_fuente,_recepcion)` | "inversión" (ver 1.3) | `…schema.sql:254,284,322` |
| `fdi_dat_inversor` / `_reparto` | socios y reparto de ganancia | `ventiq_admin_app/lib/sql/fondo_inversion_inversores.sql:3,22` |

Roles: lectura por `fn_user_can_access_tienda`; escritura de dinero **solo** por RPC `SECURITY DEFINER`; gerente/superadmin para config y movimientos manuales; dueño para inversores (`…inversores.sql:72-74`).

### 1.2 "Añadir saldo de inversión con cuenta + monto + moneda" ya existe **[HECHO]**

`fn_fdi_ingreso_manual(id_tienda, id_cuenta, id_medio_pago, moneda, monto, fecha, motivo, idempotency_key)` (`…schema.sql:968-977`), con `fn_fdi_ajuste` (`…schema.sql:1012`) y `fn_fdi_gasto` (`ventiq_admin_app/lib/sql/fondo_inversion_gasto.sql:22-30`). UI: pestaña *Saldos* con botones *Ingreso* / *Gasto* (`ventiq_admin_app/lib/screens/fondo_inversion_screen.dart:356,364`). **El punto 2 del pedido está cubierto** salvo el matiz "saldo de inversión" (ver P10).

### 1.3 La "inversión" NO es una compra **[HECHO]**

`fn_fdi_crear_inversion(p_identificador, p_detalles, p_descripcion, p_moneda_referencia, p_fuentes)` — solo texto y fuentes de dinero (`…schema.sql:1242-1249`). En la misma transacción **debita** cada fuente con tipo `extraccion_inversion` (`…schema.sql:1316-1321`). No hay producto, cantidad, costo unitario, proveedor ni factura. Estados: `pendiente|parcial|completado` (`…schema.sql:264-265`), recalculados como `recibido < total` (`…schema.sql:1212-1215`) y forzables a mano con marca de revisión (`…schema.sql:1372-1380`).

Consecuencia dura: **no existe reserva en el módulo**. El único saldo es `fdi_dat_saldo.saldo`, y `_fdi_aplicar_movimiento` revienta si el resultado queda negativo (`…schema.sql:385-388`). Grep de `reserv` en `lib/sql`, el modelo y el servicio del fondo: 0 coincidencias propias (solo `stock_reservado`, ajeno, en reportes de inventario).

### 1.4 Recepción: se vincula a "inversión", no a "compra" **[HECHO]**

`fn_registrar_recepcion_con_inventario` ganó 3 parámetros opcionales: `p_id_inversion`, `p_tasa_inversion`, `p_confirmar_exceso_inversion` (`ventiq_admin_app/lib/sql/fondo_inversion_recepcion_patch.sql:37-39`). Crea `app_dat_operaciones` + `app_dat_recepcion_productos` con `precio_unitario` por línea (`…patch.sql:224-236`), y si no llega `p_monto_total` calcula `Σ cantidad × precio_unitario` (`…patch.sql:238,244-248`). Moneda de factura restringida a `USD|EUR|CUP` (`…patch.sql:94-101`); la tasa se congela en `app_dat_operacion_recepcion.tasa_cambio_aplicada` (`…patch.sql:126-132`). Estados de operación: `1` pendiente, `2` Completada, `3/4` Cancelada, `5` Anulada; al cancelar se desvincula y recalcula (`…patch.sql:241,336-351`). UI: desplegable de inversiones abiertas con "faltan X" y campo de tasa si la moneda difiere (`ventiq_admin_app/lib/screens/inventory_reception_screen.dart:688-728`).

### 1.5 "Factura como las actuales" no tiene líneas y ya descuenta saldo prepago **[HECHO]**

`prv_dat_factura` = `id_proveedor, numero_factura, valor, fecha_procesamiento, foto_url, id_estado` (`ventiq_admin_app/lib/sql/pago_proveedores_schema.sql:140-150`); fotos en `prv_dat_factura_foto` (`:180`). **Sin tabla de detalle** (grep `factura_detalle|factura_linea`: 0). Moneda única por proveedor (`prv_dat_proveedor_config`, `…schema.sql:36-42`). Y al crear la factura **se descuenta el saldo prepago del proveedor** con tipo `descuento_factura` (`ventiq_admin_app/lib/services/pago_proveedores_service.dart:630-637`). El módulo importadora (`imp_*`) es el mismo patrón, en migración hacia `prv_*` (`ventiq_admin_app/lib/sql/migracion_importadora_a_proveedores.sql:1-17`).

### 1.6 Inversores: socios, no aportantes **[HECHO]**

`fdi_dat_inversor(id_tienda, nombre, porcentaje ≤ 100, activo)` (`…inversores.sql:3-10`); el reparto nace de un trigger sobre `fdi_dat_liquidacion_detalle`, prorratea `monto_ganancia_retirada` por % y exige suma 100% salvo modo igualitario (`…inversores.sql:88-131`); pago manual con referencia (`:133-146`). **No hay monto aportado, ni compra asociada, ni moneda de aporte.** Modelo distinto al pedido #3.

### 1.7 Costos adicionales: diseñados, **no aplicados** **[HECHO]**

`sql_updates/costos_adicionales_producto.sql` define `app_dat_producto_costo` (monto por **unidad base**, en USD) y `app_dat_recepcion_producto_costo` (auditoría por línea), y hace que `costo_real` deje de ser generado para inyectar la fórmula (`sql_updates/costos_adicionales_producto.sql:17,87,189-217,225`). Decisión ya acordada: **se capitalizan** al `precio_promedio`, ponderado por cantidad; nomenclador global `app_cont_tipo_costo` gestionado por superadmin (`docs/PLAN_COSTOS_ADICIONALES.md:15-31,73-86`). Estado declarado: "implementación en curso, aplicar en Newa" (`docs/PLAN_COSTOS_ADICIONALES.md:3`).

### 1.8 Tasas: por tienda, mutables, sin pareja única **[HECHO]**

`tasa_cambio_extraoficial` filtrada por `id_tienda` (`ventiq_admin_app/lib/services/currency_service.dart:24,114`); catálogo global `monedas` y `tasas_conversion` sin `UNIQUE(origen,destino)` — se resuelve "la más reciente" (`docs/plan-multimoneda/recon-esquema.md:31-66`). No hay tasa histórica versionada por operación: la que se congela es la que la RPC guarda en la fila.

---

## 2. (A) Modelo de dominio propuesto **[PROPUESTA]**

### 2.1 Entidades

| Entidad | Tipo | Atributos clave | Relación |
|---|---|---|---|
| `fdi_dat_compra` | nueva | `id_tienda, id_proveedor, numero_factura, fecha_factura, moneda_total, tasa_a_base, total_lineas, total_ajustes, total, modo_liquidacion ∈ {fondo,inversores}, estado, observacion, idempotency_key, created_by` | 1—N líneas, ajustes, pagos, reservas, aportes, recepciones |
| `fdi_dat_compra_linea` | nueva | `id_compra, id_producto, id_variante?, id_presentacion?, cantidad, costo_unitario, costo_linea` | N—1 compra; N—1 `app_dat_producto` |
| `fdi_dat_compra_ajuste` | nueva | `id_compra, id_tipo_costo, base ∈ {global,unidad,porcentaje}, valor, reparto ∈ {valor,peso,cantidad}, monto_capitalizado, afecta_inventario` | N—1 compra; N—1 `app_cont_tipo_costo` |
| `fdi_dat_compra_pago` | nueva | `id_compra, id_cuenta, id_medio_pago, moneda, monto, tasa_a_total, monto_eq_total, origen ∈ {fondo,aporte}, id_aporte?` | N—1 compra |
| `fdi_dat_compra_reserva` | nueva | `id_compra, id_cuenta, id_medio_pago, moneda, monto, estado ∈ {activa,consumida,liberada}, id_movimiento?` | N—1 compra; N—1 `fdi_dat_saldo` (por clave) |
| `fdi_dat_compra_aporte` | nueva | `id_compra, id_inversor, moneda, monto, tasa_a_base, monto_eq, estado ∈ {comprometido,recibido,devuelto}, comprobante` | N—1 compra; N—1 `fdi_dat_inversor` |
| `fdi_dat_compra_recepcion` | nueva | `id_compra, id_operacion UNIQUE, monto_valorizado, moneda, tasa_a_base` | N—1 compra; 1—1 `app_dat_operaciones` |
| `fdi_hist_estado_compra` | nueva | `id_compra, estado_anterior, estado_nuevo, origen, motivo, created_by, created_at` | append-only |
| reutiliza | existente | `fdi_dat_cuenta/saldo/movimiento`, `fdi_dat_inversor`, `app_dat_proveedor`, `app_dat_producto`, `app_dat_operaciones`, `app_dat_recepcion_productos` | — |

Se **conserva** `fdi_dat_inversion` sin tocar (histórico y RLS intactos); no se reutiliza como compra porque su semántica de dinero es inversa (sale dinero y luego "llega valor" medido en monto, no en cantidades).

### 2.2 Invariantes

- **I1** `total = total_lineas + total_ajustes_capitalizados`, con `total_lineas = Σ(cantidad × costo_unitario)`.
- **I2** Si `total_factura ≠ total_lineas`, la compra **no se puede reservar** hasta declarar el descuadre (ver C3); nunca se "corrige" en silencio.
- **I3** `modo_liquidacion` es único por compra: `fondo ⊻ inversores`; jamás mixto dentro de una compra.
- **I4** Reserva activa: `Σ reserva.activa(compra) = total − Σ liberado` y `reserva.activa ≤ saldo` por `(cuenta, medio, moneda)`.
- **I5** `disponible(cuenta,medio,moneda) = saldo − Σ reservas_activas` **≥ 0** en todo momento.
- **I6** Para pasar a `pagada`: `Σ monto_eq_total(pagos) = total` (tolerancia 0; redondeo solo a favor del faltante).
- **I7** Para `modo=inversores`: `Σ aportes.recibido_eq = total` antes de `pagada`; ningún aporte excede el faltante en el momento de registrarse.
- **I8** Consumo de dinero: `Σ movimientos(tipo=pago_compra) + Σ movimientos(tipo=contramovimiento) = Σ pagos` — el ledger nunca se reescribe.
- **I9** Una recepción pertenece a **una** compra (`UNIQUE(id_operacion)`), igual que hoy con inversión (`…schema.sql:325`).
- **I10** `Σ cantidad_recibida ≤ Σ cantidad_comprada + tolerancia`; el exceso exige confirmación explícita y no aumenta lo pagado.
- **I11** `estado = completada ⇔ Σ cantidad_recibida = Σ cantidad_comprada` (o cierre manual con nota y diferencia registrada).
- **I12** Tasa congelada: cada pago y cada recepción guardan su `tasa_a_*`; cambiar la tasa de tienda **no** altera compras existentes.
- **I13** Compra `anulada`/`cancelada` deja `Σ reservas_activas = 0` y `Σ pagos netos = 0`.
- **I14** Costos capitalizados: `costo_efectivo_unidad(linea) = costo_unitario + ajuste/unidad + Σ costos_adicionales`; `Σ costo_efectivo × cantidad = valor de inventario recibido`.
- **I15** Toda transición inserta fila en `fdi_hist_estado_compra` y toda operación de dinero es idempotente por `idempotency_key`.

---

## 3. (B) Máquina de estados de la COMPRA

Estados del dueño: `creada, pagada, entrega_parcial, completada, cancelada`. **[PROPUESTA]** se mantienen los 5 y se añaden dos, con justificación al final.

| # | Transición | Dispara | Dinero |
|---|---|---|---|
| T1 | ∅ → `creada` | admin/gerente | nada |
| T2 | `creada` → `reservada` | admin/gerente (validación de cobertura) | crea reservas por cuenta/medio/moneda; **saldo no se mueve** |
| T3 | `reservada` → `creada` | admin (soltar reserva) | libera reservas |
| T4 | `reservada` → `pagada` | admin/gerente | fondo: libera reserva **y** debita `pago_compra` por cada cuenta; inversores: registra aportes y su ingreso, no toca el fondo |
| T5 | `pagada` → `entrega_parcial` | sistema, al recepcionar parcial | ninguna (si T4 ya movió el dinero) |
| T6 | `entrega_parcial` → `completada` | sistema, al cubrir cantidades | ninguna |
| T7 | `pagada` → `completada` | sistema, recepción total | ninguna |
| T8 | `creada`/`reservada` → `cancelada` | admin | libera reservas; sin movimientos |
| T9 | `pagada`/`entrega_parcial` → `anulada` | dueño, con motivo | contramovimiento que devuelve al fondo lo no consumido; si ya hay inventario, exige decisión (C13/D5) |

**Irreversible:** `completada`, `cancelada`, `anulada`; y cada pago aplicado (solo se revierte con contramovimiento). Las reservas son libres hasta T4.

**Contraste con el pedido:** los 5 estados del dueño se quedan cortos en dos puntos.
- `reservada` **[falta]**: la reserva es un evento de dinero visible (dinero comprometido) y el dueño la pidió explícitamente; meterla dentro de "creada" hace imposible distinguir una compra intención de una comprometida, y rompe la invariante I5 al no haber dónde colgar las reservas.
- `anulada` **[falta]**: `cancelada` solo sirve si no salió dinero. Con pagos hechos y recepciones aplicadas hace falta una salida con reversa contable; llamarla "cancelada" obliga a reescribir movimientos, que es exactamente lo que el ledger prohíbe.
- `vencida` **[no en fase 1]**: solo tiene sentido si la reserva caduca por SLA. Recomiendo no introducirla hasta que exista una política de caducidad; si se quiere, es un job que libera reservas, no un estado nuevo de la compra.
- `pagada` **necesita definición**: ver C1. Si "pagada" = comprometida, entonces T4 no mueve dinero y `pago_compra` ocurre en T5/T6/T7; la máquina no cambia, cambia el momento del asiento.

---

## 4. (C) Contradicciones y ambigüedades

**C1 — "reservar al crear" vs "descontar según se recepciona" (la más cara).**
Hoy no hay reserva: la inversión debita al instante (`…schema.sql:1316-1321`). El pedido mezcla dos momentos de dinero (reserva al crear, cargo al recepcionar) con un estado llamado `pagada` que en cualquier lectura normal significa "ya salió el dinero". Si `pagada` mueve dinero y además se descuenta en cada recepción, **se paga dos veces**; si `pagada` no mueve dinero, el nombre engaña y el dueño verá "pagada" con saldo intacto.
*Recomendación:* **PROPUESTA** un solo asiento real por compra: el dinero sale al pasar a `pagada` (T4), y la reserva se libera en ese mismo acto; las recepciones solo valorizan inventario y mueven `entrega_parcial/completada`. Es más simple, elimina el caso "saldo insuficiente a mitad de recepción" y hace que la factura del proveedor se comporte como la factura actual. Si el dueño exige pago contra entrega, entonces renombrar `pagada` → `comprometida` y no liberar la reserva hasta la última recepción.

**C2 — Cancelación con reserva activa.** No está definido. **PROPUESTA:** cancelar libera reservas (I5, I13) y deja rastro en el historial; si ya hubo pagos, es `anulada` con contramovimiento, nunca borrado.

**C3 — Total de factura vs `Σ(cantidad × costo unitario)`.** La factura actual solo guarda `valor` (`…pago_proveedores_schema.sql:145`) y las líneas viven en la recepción (`…patch.sql:224-236`); no hay nada que reconcilie ambos. **PROPUESTA:** `total_lineas` es la verdad operativa; `total_factura` es un dato de control. Si difieren, la compra queda `creada` con descuadre bloqueante y solo el dueño/gerente puede forzar el cierre declarando el motivo (queda en historial). Nunca se recalcula el costo unitario para "cuadrar".

**C4 — Recepción con MENOS cantidad.** Dos efectos distintos: la reserva sobrante y el pago ya hecho. **PROPUESTA:** si el dinero salió (C1 opción A), el sobrante **no se libera automáticamente**: queda como saldo a favor del proveedor o como pendiente de recepción hasta cierre manual, porque devolverlo al fondo sin decisión del dueño crea dinero de la nada. Si el dueño elige C1 opción B (reserva hasta recepción), entonces sí se libera al cerrar la compra.

**C5 — Recepción con MÁS cantidad.** Hoy existe el patrón "confirmar exceso" para montos (`…schema.sql:1427-1435`). **PROPUESTA:** mismo patrón por cantidad; el excedente entra a inventario con su costo real y **no** suma a la deuda de la compra; se registra aparte para que el total pagado nunca cambie.

**C6 — Multimoneda: dónde vive el total y qué tasa se congela.** No hay tasa histórica por operación (`recon-esquema.md:31-66`); hoy se congela al recepcionar (`…patch.sql:130-132`). **PROPUESTA:** moneda del total = la de la factura (una sola por compra); `total` inmutable tras `reservada`; **tasa congelada por pago** (`fdi_dat_compra_pago.tasa_a_total`) y por recepción, tomada de la tasa de la tienda en ese instante; solo dueño/gerente puede editar una tasa antes de `pagada` y queda en historial.

**C7 — "Pago a la importadora": forma y destino.** Es ambiguo y peligroso: ya existe una cartera prepago por proveedor que **descuenta la factura al crearla** (`pago_proveedores_service.dart:630-637`). Si además se capitaliza "el pago a la importadora" como costo de la compra, **se cuenta dos veces el mismo dinero**. **PROPUESTA:** distinguir (a) valor de mercancía de la factura del proveedor — ya cubierto por la cartera prepago — de (b) **cargo de servicio de la importadora**, que sí es un ajuste capitalizable (`fdi_dat_compra_ajuste`), con base y reparto explícitos. Base recomendada: **monto global repartido por valor** (es un flete/servicio, no un costo por unidad); `afecta_inventario = true` para que el costo del stock sea el real.

**C8 — Costos adicionales: capitalizar o gasto, y con qué alcance.** Ya está decidido capitalizar y ponderar por cantidad, nomenclador global por producto (`PLAN_COSTOS_ADICIONALES.md:19-31`). La contradicción es de **momento y alcance**: el plan los captura al recepcionar; el pedido #10 los quiere "seleccionables por producto con su monto" en la recepción, y el #9 quiere ver la compra/factura. **PROPUESTA:** el catálogo y el monto por defecto viven en el producto (`app_dat_producto_costo`), el valor aplicado se captura **por línea de recepción** (una sola fuente de verdad: `app_dat_recepcion_producto_costo`), y la compra solo lleva los ajustes de cabecera (flete/aduanal/importadora). Editar el monto después de recepcionar **no** reescribe el costo histórico ya aplicado: exige nota de ajuste y un asiento nuevo.

**C9 — "Bloquear productos a solo los seleccionados en la compra".** No está claro el objeto del bloqueo. **PROPUESTA:** bloquear **recepción**, no catálogo: al recepcionar contra una compra solo se pueden elegir las líneas de esa compra; el producto sigue vendible y visible. Bloquear stock o catálogo es otra funcionalidad y no la pidió el dueño con esas palabras (P11).

**C10 — Fondo vs inversores: exclusividad.** El dueño dice "solo un tipo de liquidación". **PROPUESTA:** `modo_liquidacion` único e inmutable tras `pagada` (I3). Impacto: si mañana quiere mixto, hay que añadir una tabla de composición, no un campo; por eso conviene decidirlo ya (P4). Nota: hoy son modelos **incompatibles** — el fondo paga desde cuentas; el inversor hoy no tiene saldo, solo % de ganancia.

**C11 — Inversores: socio vs aportante (confirmado).** `fdi_dat_inversor` es un socio con `porcentaje` de la ganancia (`…inversores.sql:3-10,88-131`), y el reparto nace de una **liquidación de ventas**, no de una compra. El pedido #3 exige: inversor + compra + monto + moneda. **PROPUESTA:** `fdi_dat_compra_aporte` nueva, colgada de `fdi_dat_inversor` como identidad pero con semántica de **acreedor de esa compra**; el % de ganancia sigue siendo otra cosa y no se mezcla. Nombres distintos en UI: "reparto de ganancia" vs "aporte a compra".

**C12 — Recepción externa sin compra.** Hoy no hay bandera; la recepción siempre puede ir sin vínculo (`…patch.sql:257`). **PROPUESTA:** campo explícito `origen ∈ {compra, externa}` en la operación de recepción, obligatorio; `externa` no toca el fondo y no puede vincularse a compra.

---

## 5. (D) Casos borde y flujos alternos

| Caso | Regla propuesta |
|---|---|
| Cancelación con reserva activa | libera reservas, estado `cancelada`, historial con motivo; sin movimientos |
| Cancelación con pagos hechos | `anulada` + contramovimiento por lo no consumido; si hay inventario recibido, decisión explícita del dueño |
| Compra sin factura | permitida como borrador; **no** se puede pasar a `pagada` en modo fondo (no hay soporte documental), sí en modo inversores con comprobantes por aporte |
| Recepción duplicada | `UNIQUE(id_operacion)` en `fdi_dat_compra_recepcion` + idempotency key en la RPC (patrón ya usado, `…schema.sql:325`, `…patch.sql:252-274`) |
| Recepción externa sin compra | `origen=externa`, sin vínculo, sin efecto en fondo |
| Devolución al proveedor | compra no se reabre: nota de crédito como ajuste negativo con su propio asiento; el inventario se descuenta por el flujo de egreso existente |
| Compra en moneda distinta a la del fondo | pagos con `tasa_a_total` congelada por pago; nunca se convierte el total |
| Saldo insuficiente a mitad de recepción | imposible si C1 opción A; si B, la reserva ya cubre el total y la recepción no vuelve a pedir dinero |
| Edición de costos adicionales tras recepcionar | no reescribe histórico; ajuste nuevo con nota |
| Merma/pérdida tras recepción | fuera del alcance del fondo: es ajuste de inventario |

---

## 6. (E) Preguntas bloqueantes para el dueño

Ordenadas por impacto en el diseño. **P1–P4 bloquean la fase 1.**

1. **P1 (BLOQUEA) — ¿El dinero sale al marcar `pagada` o al completar cada recepción?** Rec.: sale al pagar y la reserva se libera en ese acto. Motivo: define si hay uno o dos asientos por compra; hoy no existe reserva y cualquier doble asiento duplica el gasto (C1).
2. **P2 (BLOQUEA) — ¿Manda el total de la factura o `Σ(cantidad × costo unitario)`?** Rec.: manda la suma de líneas; el total de factura es control y el descuadre bloquea. Motivo: la factura actual no tiene líneas, así que la reconciliación hay que crearla (C3).
3. **P3 (BLOQUEA) — ¿El pago a la importadora es costo capitalizable, gasto, o ya está cubierto por la cartera prepago del proveedor?** Rec.: cargo de servicio capitalizable aparte; la mercancía la paga la cartera existente. Motivo: doble conteo de dinero real (C7).
4. **P4 (BLOQUEA) — Inversores: ¿aportan monto a una compra concreta (modelo nuevo) o seguimos con el % de ganancia actual?** Rec.: aporte por compra como entidad nueva. Motivo: son dos modelos incompatibles y hoy solo existe el segundo (C11).
5. ¿Puede editarse una compra ya `reservada`? Rec.: solo cabecera no monetaria; líneas y total bloqueados. Motivo: editar el total invalida reservas y pagos (C1, I2).
6. ¿Qué pasa con el sobrante de reserva si la recepción trae menos? Rec.: no se libera sola si el dinero ya salió. Motivo: liberar crea saldo inexistente (C4).
7. ¿Se admite exceso de cantidad recibida? Rec.: sí, con confirmación y sin tocar el total pagado (C5).
8. ¿En qué moneda se fija el total y quién puede cambiar la tasa? Rec.: moneda de la factura, tasa congelada por pago, cambio solo antes de `pagada` y auditado (C6).
9. ¿Los costos adicionales son por producto (config) o por compra? Rec.: config en producto, valor aplicado en la línea de recepción (C8).
10. "Añadir saldo de inversión" (#2): ¿es el *Ingreso manual* que ya existe, o un aporte de capital de un inversor? Rec.: confirmar que se refiere al ingreso manual existente; si es aporte, es otra entidad. Motivo: evita duplicar dos veces el mismo movimiento.
11. "Bloquear productos" (#12): ¿bloquea recepción, stock o catálogo? Rec.: solo recepción contra compra (C9).
12. ¿Pago mixto fondo + inversores en una misma compra? Rec.: no en fase 1; exclusivo. Motivo: si hay duda, el modelo necesita composición desde el día uno (C10).

---

## 7. Supuestos y fuera de alcance (fase 1)

- Una compra = un proveedor y una moneda de total. Los pagos sí son multimoneda.
- No se toca `fdi_dat_inversion` ni su historial; convive con compras.
- No se toca el pipeline de `precio_promedio` más allá de inyectar el costo efectivo ya diseñado en `sql_updates/costos_adicionales_producto.sql`.
- No hay devoluciones, notas de crédito ni caducidad de reservas en fase 1.
- Stitch y UI: fase posterior, con este modelo como contrato de datos.