# Compras, costo aterrizado y recepciones — plan de corrección

**Versión 1 · 2026-11-26 · entorno `newa` (`qhprswhhfasrikhawjoz`, MCP `supabase-debug`) · main no se toca.**

Este plan nace de los 10 puntos del dueño y del caso real **recepciones 230 y 231** (compra 80, tienda 4),
cuyos números no cuadraban con lo esperado. No es un plan nuevo del módulo: corrige y completa la fase 6
del [`PLAN.md`](PLAN.md) sin contradecir sus decisiones cerradas (PD1-PD8).

---

## 0. Los 10 puntos → dónde se arreglan

| # | Punto del dueño | Fase |
|---|---|---|
| 1 | Nº de factura obligatorio al crear la compra | 2 (servidor) + 5 (UI) |
| 2 | Tasa por defecto = la extraoficial configurada de la tienda, no 1 | 2 + 5 |
| 3 | Conceptos de costo **por tienda**, no un nomenclador fijo global | 1 + 5 + 7 |
| 4 | Ajuste global siempre **por cantidad**; origen según fondo/inversores | 2 + 5 |
| 5 | Reservar el fondo **desde el alta**, no solo desde el detalle | 5 |
| 6 | Información de recepciones en el detalle (hoy muestra 0,00) | 6 |
| 7 | Cálculo del costo aterrizado y sus conceptos, hoy enrevesado | 3 + 6 |
| 8 | Costo por línea recibida (hoy duplica el cargo) | 3 + 6 |
| 9 | El ajuste debe subir el costo unitario del producto + preview | 3 + 5 |
| 10 | Costos adicionales en la recepción (transporte, etc.) y costo vs precio CUP | 7 |

---

## 1. Diagnóstico del caso 230/231 (datos reales de `newa`)

Compra **80** (`SASD1234567`, PUCARA, USD): mercancía 22.500,00 · ajustes globales 5.000,00 ·
financiado 27.500,00 · estado `completada`. Dos líneas (5.000 × 0,50 y 20.000 × 1,00) y dos recepciones.

| Dato | Guardado hoy | Lo que debería ser |
|---|---|---|
| `valor_vinculado` (resumen) | **45.000,00** | 22.500,00 (valor realmente recibido) |
| `cargo_importadora` | **9.250,00** | 8.250,00 si el % se aplica a lo recibido |
| `pct_importadora_efectivo` | **20,56 %** | 10 % + 40 % sobre bases distintas |
| `total_aterrizado` (resumen) | **59.250,00** | 35.750,00 – 36.750,00 |
| `costo_real` línea 77 | **250,50 /u** | 0,75 /u |
| `costo_real` línea 78 | **1,00 /u** | 1,60 /u |
| `costo_aterrizado_unit` línea 77 | **250,55 /u** | 0,75 /u |
| `precio_promedio` producto 2 (base) | **84,2984** | ~0,75 |
| `precio_promedio` caja 24 (producto 2) | **2.023,16** | ~18,00 |
| `precio_promedio` producto 3 (base) | **0,614286** | ~1,60 |
| `app_dat_producto_costo` (prod. 2, Importadora) | **116,23 USD/u** | ~0,10 USD/u |
| Recepciones en el detalle | «0,00 USD» | valor recibido de cada recepción |

### Causas raíz (todas verificadas contra el catálogo de `newa`)

- **C1 · `monto_usd` tiene dos significados.** El diálogo de producto lo captura **por unidad**
  (`product_quantity_dialog.dart:183`), pero `fn_fdi_compra_repartir_aterrizaje` escribe el **total**
  repartido de la línea. `_v2` lo suma como si fuera unitario: `costo_real = precio + Σ monto_usd`
  (`fn_actualizar_precio_promedio_recepcion_v2_m01`). De ahí 250,50 y el promedio de 84,30.
- **C2 · el cargo de importadora se guarda neto y no se puede auditar.** La RPC guarda
  `monto_importadora = base × % − reembolso` (`fn_fdi_compra_vincular_recepcion`) y además guarda el
  reembolso, sin columna de bruto. El panel muestra el neto como «cargo» y esconde el reembolso; cualquier
  consumidor nuevo (resumen, reporte, margen) tiene que adivinar si restarlo o no.
- **C3 · la base de importadora es la compra entera en cada recepción parcial.** La UI precarga
  `base_importadora = compra.totalMercancia` (`inventory_reception_screen.dart:344-345`). Dos recepciones
  suman 45.000 de base sobre una compra de 22.500.
- **C4 · el ajuste global nunca se capitaliza.** `fdi_dat_compra_ajuste` (5.000, reparto `cantidad`) solo
  aparece en el resumen como `ajustes_aplicados = ajustes × %recibido`; no hay fila de costo con
  `id_ajuste`, ni reparto entre líneas, ni efecto en `precio_promedio`. El «aterrizado» de 27.500 de la
  tabla `fdi_dat_compra` y el 59.250 del panel son dos verdades distintas en la misma pantalla.
- **C5 · `origen_pago = 'fondo'` en la recepción no paga nada.** `repartir_aterrizaje` devuelve
  `omitido/origen_pago_fondo` con el texto «ya está en su ledger», pero el fondo solo pagó los 27.500 de
  `total_financiado`: los 9.000 del vínculo 31 no salieron de ninguna cuenta ni entraron al costo. En
  `inversores` ese origen además está prohibido por trigger.
- **C6 · el resumen suma el cargo dos veces.** `costo_aterrizado_unit = COALESCE(costo_real, precio) +
  costos_total/cantidad`, y `costo_real` ya trae el cargo: 250,50 + 0,05 = 250,55.
- **C7 · `monto_valorizado` nunca se escribe** (0,00 en los 5 vínculos). El panel de recepciones del
  detalle muestra ese campo (`compra_detail_screen.dart:1523-1532`).
- **C8 · las líneas no se atribuyen a la recepción.** `fdi_dat_compra_recepcion_linea.id_recepcion_producto`
  es NULL en las 2 filas; el reparto adivina por operación y la base puede salir de `costo_real`
  (ya contaminado) en la segunda recepción (`fn_fdi_compra_recepcion_bases`).

Productos contaminados por el mismo patrón en las recepciones 227-231: **2, 3, 10 y 18**
(`costo_real` 52,60 / 80,53 / 116,83 / 2,53).

**Anomalías adicionales en los otros vínculos** (se conservan, no se reinterpretan): el vínculo 27
(compra 77) guarda `pct_importadora = 0,13` con `base 8.350` y cargo neto 0,86 —el porcentaje parece
fracción, no 13 %—; el vínculo 28 (compra 79) usa `base 4.000` sobre una compra de 3.350. Son la misma
enfermedad de C3: la base no es el valor recibido. La reparación de la fase 4 los trata con respaldo y
solo cambia el bruto derivado, nunca el neto ya declarado.

---

## 2. Decisiones de modelo que adopta este plan

- **D1 · `app_dat_recepcion_producto_costo.monto_usd` = importe TOTAL de la línea en USD.** El unitario se
  deriva (`total / cantidad`). Es la única forma de que Σ filas = cargo y de auditar el reparto. El
  diálogo seguirá pidiendo el importe **por unidad** y multiplicará por la cantidad antes de enviar.
  (Alternativa descartada: guardar unitario y que la suma cuadre por redondeo; el descuadre de centavos
  sería inevitable en líneas grandes.)
- **D2 · importadora bruta + reembolso separados.** `monto_importadora = round(base × pct / 100, 2)` y
  `cargo_neto` como columna generada `monto_importadora − reembolso_importadora`. Nunca se resta dos veces.
- **D3 · la base de importadora por defecto es el valor recibido en esa recepción**, editable; si se
  cambia, se avisa. El reembolso no puede superar el bruto.
- **D4 · el ajuste global se reparte siempre por cantidad.** Se retira el selector de reparto del alta; el
  reparto por valor/ peso queda como deuda documentada. El origen se deriva del modo: `fondo` → `fondo`
  (entra en `total_financiado`); `inversores` → `externo` (capitaliza, no lo paga el fondo).
- **D5 · conceptos de costo por tienda con respaldo global.** `app_cont_tipo_costo.id_tienda` nullable:
  NULL = global (los 4 sembrados), con tienda = propio. El listado muestra propios + globales; el
  concepto «Importadora» se resuelve primero por tienda y luego global. Dueño/gerente administran los de
  su tienda; superadmin, los globales.
- **D6 · la tasa de la factura se precarga de `tasa_cambio_extraoficial`** (USD→CUP de la tienda) cuando
  la moneda es CUP; USD ⇒ 1; EUR manual. Se puede corregir y queda congelada en el documento.
- **D7 · en la recepción, «fondo» no puede ser un origen mudo.** O se financia en el acto (reserva + pago,
  como 06d) o el origen se limita a `wallet_importadora`/`externo` y el cargo se declara como ajuste
  posterior. Se elige lo segundo para esta iteración: menos superficie de dinero nuevo.

### Decisiones del dueño (2026-11-26, cerradas)

| Tema | Decisión |
|---|---|
| Tasa de la factura | **Bloqueada por defecto** con la tasa de la tienda y un **botón «editar»** al lado; al desbloquearla se puede corregir y se avisa que queda congelada en el documento. |
| Base de importadora | **Valor recibido** de esa recepción, por defecto. |
| Origen fondo en la recepción | **Deshabilitado**: solo `wallet_importadora` y `externo`. |
| Conceptos de costo | **Dueño y gerente** crean y editan los de su tienda; superadmin, los globales. |
| Datos históricos | **No se recostean**: la corrección aplica de aquí en adelante, para poder comparar. |


---

## 3. Fases

Cada fase es una sesión de agente. Ninguna se marca `done` sin su `verify` en verde y sin el E2E del
dueño cuando toque dinero. Todo script lleva `_rollback.sql`.

### Fase 1 — Esquema: conceptos por tienda y bruto de importadora

**Objetivo:** que el modelo soporte D2 y D5 sin tocar todavía ninguna cifra.

- `10_costos_tienda.sql`
  - `alter table app_cont_tipo_costo add column id_tienda bigint references app_dat_tienda(id);`
  - índice único `(coalesce(id_tienda,0), lower(btrim(denominacion)))`;
  - `fn_cont_tipo_costo_guardar/eliminar` con `p_id_tienda` (default NULL) y guardas por rol; se **borra**
    la firma vieja para no dejar overload;
  - `app_cont_tipo_costo` sigue solo lectura por PostgREST.
- `11_importadora_bruto.sql` — **sin reescribir historia**
  - `monto_importadora` se queda como **neto** (lo que ya está guardado); se añade
    `monto_bruto_importadora numeric generated always as (monto_importadora + reembolso_importadora) stored`;
  - `fn_fdi_compra_vincular_recepcion` sigue guardando el neto y valida `0 ≤ reembolso ≤ base × pct / 100`;
  - `repartir_aterrizaje` sigue usando el neto (es el cargo que capitaliza);
  - `costo_resumen` devuelve bruto, reembolso y neto por separado sin tocar filas viejas.
- `verify/10_costos_tienda.sql` y `verify/11_importadora.sql` (solo lectura + control negativo).

**Salida:** `verify` en verde; las 5 filas de vínculo conservan su cargo neto (250 y 9.000) y ahora
explican bruto y reembolso sin haber cambiado un centavo.

### Fase 2 — Backend de la compra

**Objetivo:** factura obligatoria, tasa por defecto de la tienda, ajustes por cantidad y origen por modo.

- `12_compra_contrato.sql`
  - `fn_fdi_compra_crear/editar`: `numero_factura` no vacío (22023 con mensaje claro);
  - si `p_tasa_factura` es NULL y la moneda es CUP: resolver la tasa activa de la tienda
    (`tasa_cambio_extraoficial` USD→CUP, `usar_precio_toque = false`) y usarla; si no hay, error;
  - `p_ajustes`: forzar `reparto = 'cantidad'`; `origen_pago` según `modo_liquidacion`;
  - `fn_fdi_compra_ajuste_agregar`: mismo reparto por cantidad y misma derivación de origen (ya deriva
    origen; falta el reparto);
  - `fn_fdi_compra_crear` valida que el tipo de costo pertenezca a la tienda o sea global.
- `verify/12_compra_contrato.sql`: factura vacía rechazada, CUP sin tasa usa 850 (tienda 4), ajuste con
  `reparto` distinto se normaliza, modo inversores deja `externo`.

**Salida:** crear una compra CUP sin tasa explícita la deja con 850; sin factura, no crea.

### Fase 3 — Aterrizaje correcto (el corazón del problema)

**Objetivo:** un solo número de aterrizado y un costo unitario que no explote.

- `13_aterrizaje_unidad.sql`
  - `fn_fdi_compra_vincular_recepcion`: si `p_base_importadora` es NULL/0, calcularla como Σ
    `cantidad_recibida × costo_unitario_aplicado`; escribir `monto_valorizado` del vínculo; poblar
    `id_recepcion_producto` en `fdi_dat_compra_recepcion_linea` (match producto/variante/presentación).
  - `fn_fdi_compra_recepcion_bases`: base = `costo_unitario_aplicado` (o precio de la línea), **nunca**
    `costo_real`.
  - `fn_fdi_compra_repartir_aterrizaje`: reparte (a) el cargo neto de importadora y (b) **cada ajuste
    global que capitaliza**, con `id_ajuste`, entre las líneas recibidas **por cantidad**; la porción del
    vínculo es `monto_capitalizado × cantidad_recibida / cantidad_comprada`, así los parciales suman el
    total y reejecutar un vínculo solo reescribe lo suyo. Persiste `monto_usd` **total** por línea.
  - `fn_actualizar_precio_promedio_recepcion_v2_m01`: unitario = `monto_usd / cantidad_base`;
    `costo_real = precio + Σ unitarios`; la ponderación usa el unitario, no el total.
  - `fn_fdi_compra_costo_resumen`: `valor_vinculado` = Σ valor recibido; `cargo` bruto/reembolso/neto;
    `ajustes_aplicados` = Σ filas con `id_ajuste`; `total_aterrizado` = valor + cargo neto + ajustes
    aplicados; `costo_factura_unit` = precio de factura (no `costo_real`);
    `costo_aterrizado_unit = factura + Σ total/cantidad`; una sola vez.
- `verify/13_aterrizaje_unidad.sql` transaccional con `ROLLBACK` y control negativo: cargo 250 en 5.000 u
  ⇒ 0,05/u y `costo_real` 0,55; ajuste 5.000 en 25.000 u al 20 % recibido ⇒ 1.000 aplicados y 4.000 por
  asignar; segunda recepción no recalcula la primera.

**Salida:** el caso 230/231 reproducido en una transacción revertida da 0,75 y 1,60 por unidad, y
`total_aterrizado` 35.750 (o 36.750 si se conserva el cargo declarado), nunca 59.250.

### Fase 4 — Sin recosteo histórico: comparación y reinicio manual

**Objetivo:** cumplir la decisión del dueño (no tocar el pasado) sin que los promedios contaminados sigan
envenenando las recepciones nuevas.

- `14_diagnostico_costos.sql` (solo lectura, no modifica nada):
  - vista/reporte `app_v_diagnostico_costo_producto`: costo de referencia por producto contra su precio de
    venta CUP y contra el último costo de factura; marca en rojo los que superan 10× la factura.
  - así el dueño **compara** antes/después sin que se le reescriba una fila.
- `fn_reset_costo_promedio_producto(p_id_producto, p_motivo)` (RPC nueva, dueño/gerente):
  - reinicia `precio_promedio` y `app_dat_producto_costo.monto_promedio_usd` del producto a partir de su
    **última recepción** con la fórmula corregida de la fase 3;
  - exige motivo, deja fila en el historial y **no** toca ventas, COGS ni recepciones.
  - es la salida manual para los productos 2, 3, 10 y 18 si el dueño decide limpiarlos.
- `verify/14_diagnostico.sql`: el reporte lista los 4 productos; el reset está bloqueado para no-dueño.

**Salida:** ningún dato histórico cambia por el plan; el dueño ve la tabla comparativa y decide si usa el
reset producto por producto.

### Fase 5 — UI del alta de compra

**Objetivo:** los puntos 1, 2, 3, 4, 5 y 9 en la pantalla de alta.

- `compra_form_screen.dart`
  - `_validar`: factura obligatoria; aviso en el campo (quitar «Opcional»).
  - `_campoTasa`: al pasar a CUP, precargar `CurrencyService.getEffectiveUsdToCupRate()` y mostrar «tasa
    configurada de la tienda: 850»; USD ⇒ 1 bloqueado; EUR manual.
  - `_filaAjuste`: concepto desde el catálogo **de la tienda** + «+ Nuevo concepto» (abre el diálogo de
    `cost_types_management_screen`); reparto fijo «Por cantidad» (chip, sin dropdown); origen automático
    según modo con texto «lo paga el fondo / lo pagan los inversores»; se elimina el selector de origen.
  - **Preview de costo unitario** por línea: «Factura 0,50 → Aterrizado 0,70 (+0,20, +40 %)» y total;
    se actualiza al escribir cantidades/ajustes. Etiqueta «estimado si recibes todo».
  - **Financiación en el alta:** panel plegable «Reservar del fondo» con fuentes (cuenta/medio/moneda/
    monto/tasa); al guardar, `crear` y luego `fn_fdi_compra_reservar` con la misma clave de idempotencia.
    Si la reserva falla, la compra queda creada y se muestra el error con enlace al detalle. En
    `inversores` el panel no se pinta.
- Refactor: extraer el editor de fuentes de `compra_liquidacion_screen.dart` a
  `widgets/compra_fuentes_editor.dart`, usado por alta y liquidación.
- Tests: `test/compra_alta_contrato_test.dart` (factura, tasa, reparto, origen) y
  `test/compra_costo_preview_test.dart` (0,50 + 0,20 = 0,70).

**Salida:** crear una compra CUP con 2 líneas y un flete de 5.000 muestra el nuevo unitario antes de
guardar, y permite reservar sin salir del alta.

### Fase 6 — UI del detalle de compra

**Objetivo:** los puntos 6, 7 y 8; una sola historia numérica.

- `_panelRecepciones`: por recepción, operación y fecha, **líneas y cantidades recibidas**, valor recibido
  (`monto_valorizado` ya escrito), bruto/reembolso/neto de importadora, origen y estado; botón «Ver
  recepción». Se elimina el 0,00.
- `_panelCostoAterrizado`: cascada única
  `Mercancía recibida + Importadora neta + Ajustes aplicados = Aterrizado`, con «por asignar» solo si hay
  parciales y su explicación. Se quita el «Total aterrizado» que duplicaba la tabla de cifras.
- «Costo por línea recibida»: producto · cantidad · factura/u · adicionales/u (desglosados por concepto) ·
  aterrizado/u · **precio venta CUP** · margen CUP y % (usando la tasa de la operación).
- Se elimina cualquier resta de reembolso en el cliente: el servidor manda bruto, reembolso y neto.

**Salida:** abrir la compra 80 muestra 22.500 recibidos, 8.250 de importadora y 35.750 de aterrizado.

### Fase 7 — UI de la recepción

**Objetivo:** el punto 10 completo.

- `inventory_reception_screen.dart`
  - «Base importadora» = valor recibido de las líneas marcadas (editable, con aviso si se cambia);
    reembolso ≤ bruto; el cargo mostrado es el neto.
  - **«Otros costos de la recepción»**: agregar concepto del catálogo de la tienda + importe total +
    reparto por cantidad; preview del unitario que suma a cada línea. Mismo componente que los ajustes
    del alta.
  - Diálogo de producto: conceptos del catálogo de la tienda (no solo los precargados del producto),
    importe **por unidad** y preview «costo actual → costo con adicionales».
  - Tabla de líneas: factura/u · adicionales/u · aterrizado/u · precio venta CUP · margen CUP/%.
  - Origen de pago: `fondo` deshabilitado con explicación (D7); en `inversores`, solo `externo`.
- Tests: `test/recepcion_costos_contrato_test.dart`, `test/recepcion_margen_cup_test.dart`.

**Salida:** una recepción con transporte de 300 USD sobre 5.000 u muestra +0,06/u y el margen en CUP por
línea antes de confirmar.

### Fase 8 — Verificación integral y cierre

- Repetir el escenario 230/231 en `newa` con una compra nueva y las cifras de la tabla del §1.
- `verify/13` + `verify/11` + `verify/12` + `verify/14` en verde; `verify/06` y `06c/06d` sin regresión.
- `flutter test` de los contratos nuevos y `analyze_files` limpio en `ventiq_admin_app`.
- Actualizar `PLAN.md` (fase 6.1 «costos comprensibles»), `README.md` y `tasks/hallazgos_pruebas_newa.md`.
- E2E del dueño: compra CUP con tasa automática, reserva desde el alta, recepción parcial con transporte,
  margen visible y cancelación con reversa.

---

## 4. Archivos que se tocan

| Capa | Archivo |
|---|---|
| SQL | `ventiq_admin_app/lib/sql/compra/10_costos_tienda.sql`, `11_importadora_bruto.sql`, `12_compra_contrato.sql`, `13a`-`13e`, `14_diagnostico_costos.sql` (+ rollbacks y `verify/`) |
| Servicios | `compra_service.dart`, `inventory_service.dart`, `costos_adicionales_service.dart`, `financial_service.dart`, `currency_service.dart` (solo lectura de tasa) |
| Modelos | `models/compra.dart` (bruto/reembolso/neto, reparto fijo, origen derivado) |
| Alta | `compras/compra_form_screen.dart`, `compras/compras_widgets.dart` |
| Detalle | `compras/compra_detail_screen.dart` |
| Recepción | `screens/inventory_reception_screen.dart`, `widgets/product_quantity_dialog.dart` |
| Catálogo | `screens/cost_types_management_screen.dart`, `widgets/compra_fuentes_editor.dart` (nuevo) |
| Tests | `test/compra_alta_contrato_test.dart`, `compra_costo_preview_test.dart`, `recepcion_costos_contrato_test.dart`, `recepcion_margen_cup_test.dart` |

---

## 5. Riesgos y cómo se controlan

| Riesgo | Control |
|---|---|
| Cambiar la semántica de `monto_usd` rompe recepciones viejas | La fase 3 corrige el cálculo nuevo; la fase 4 **no reescribe** ninguna fila histórica, solo diagnostica y ofrece un reset manual por producto. |
| El reparto por cantidad no coincide con el `reparto` histórico de compras 79 (`valor`) | Se respeta el reparto guardado para lo histórico; las compras nuevas fuerzan `cantidad`. |
| `origen_pago = fondo` deja de capitalizar y el costo queda corto | Se deshabilita en la UI y el servidor lo rechaza con un aviso explícito; el cargo se declara como ajuste posterior financiable. |
| Los promedios contaminados siguen pesando en la próxima recepción | El diagnóstico compara contra el precio de venta y el reset manual queda a un botón; no se toca nada sin que el dueño lo pida. |
| Redondeo por unidad vs total | Se guarda total y se deriva unitario con 6 decimales; el cuadre exige `|Σ − cargo| < 0,005`. |

---

## 6. Decisiones cerradas (2026-11-26)

1. **Tasa:** bloqueada por defecto con la de la tienda y botón «editar» funcional al lado.
2. **Base de importadora:** valor recibido de la recepción por defecto.
3. **Origen fondo en recepción:** deshabilitado (solo wallet de importadora y externo).
4. **Conceptos por tienda:** dueño y gerente crean/editan los suyos; superadmin los globales.
5. **Histórico:** no se recostea; se corrige de aquí en adelante y se ofrece comparación + reset manual.

La fase 1 arranca en `newa` sin tocar main.

---

## 2.1 Estado de ejecución (2026-11-27)

| Fase | Estado en `newa` | Notas |
|---|---|---|
| 1. Conceptos por tienda + bruto | **aplicada** | `10_costos_tienda.sql`, `11_importadora_bruto.sql`. Funciones probadas: dueño/gerente por tienda, duplicado por ámbito, Importadora no se renombra. |
| 2. Backend de compra | **aplicada** | `12_compra_contrato.sql`. Probado: factura vacía → `22023`; compra CUP sin tasa → 850 (tienda 4); ajuste con `reparto` distinto → `cantidad`; inversores → `externo`. |
| 3. Aterrizaje | **aplicada (backend)** | `13a` vincular/bases, `13b` reparto, `13c` `_v2` unitario, `13d` resumen. Probado en transacción revertida sobre el vínculo 30: importadora 250 + ajuste 1.000 y `costo_real` 0,75. Ajuste tardío también por cantidad. |
| 4. Sin recosteo | **hecha** | Vista `app_v_diagnostico_costo_producto` y RPC `fn_reset_costo_promedio_producto` con motivo e historial (`app_hist_reset_costo`). Probado en revertido sobre el producto 2: 84,2984 → 0,55 (caja 13,20) y catálogo 0,05. Se ejecuta a mano, producto por producto; nada automático. |
| 5. UI del alta | **hecha** | Factura obligatoria, tasa de tienda bloqueada con botón de editar, reparto y origen derivados (ocultos, son fijos), preview por unidad, **costo unitario sugerido del último historial**, reserva del fondo activada por defecto y **aportes de inversores desde el alta** (se abre el panel al guardar). |
| 6. UI del detalle | **hecha** | Recepciones con `valor_recibido` y bruto/reembolso; costo por línea con factura → aterrizado, **costo CUP, precio de venta y margen**, y desglose por concepto. |
| 7. UI de la recepción | **hecha** | Base = valor recibido; «fondo» fuera; **importadora opcional con interruptor, nombres de mostrador y cuenta en vivo**; otros costos por cantidad; tabla costo vs venta CUP por línea. |
| 8. Verificación integral | **hecha (técnica)** | `analyze` limpio; `app_compile`, modelos de compra/liquidación y **8 tests nuevos** en verde (28 en total); `verify/10` 7/7, `verify/11` 4/4, `verify/12` 7/7; **E2E SQL revertido**: compra nueva de 2.500 + 250 de importadora + 500 de ajuste → costo unitario 0,7167 y 1,2667 y sin filas persistidas. Falta el E2E visual del dueño. |

**Reparación de la compra 80 (2026-11-27, autorizada por el dueño).** Se corrigió el documento real en
`newa`, con respaldo en `_bkp_compra80_20261127`:

| Dato | Antes | Ahora |
|---|---|---|
| Vínculo 30 (op 230) | base 22.500 · 10 % · reembolso 2.000 · neto 250 · valorizado 0 | base **2.500** · 10 % · reembolso 0 · neto **250** · valorizado **2.500** |
| Vínculo 31 (op 231) | base 22.500 · 40 % · origen fondo · neto 9.000 · valorizado 0 | base **20.000** · 45 % · origen **wallet_importadora** · neto **9.000** · valorizado **20.000** |
| Costos línea 77 | importadora 250 | importadora 250 + seguro **1.000** |
| Costos línea 78 | ninguno | importadora **9.000** + seguro **4.000** |
| `costo_real` | 250,50 / 1,00 | **0,75 / 1,65** |
| `precio_promedio` prod. 2 | 84,2984 | **0,75** (caja 24 = 18,00) |
| `precio_promedio` prod. 3 | 0,614286 | **1,65** (kg = 1.650) |
| `costo_aterrizado` compra | 27.500 | **36.750** |
| Resumen | 59.250 | **36.750** (22.500 + 9.250 + 5.000) |

Los promedios se limpiaron con `fn_reset_costo_promedio_producto` (2 filas de historial). El respaldo
permite volver atrás con un `INSERT ... SELECT` desde las tablas `bkp`.


