# 02 — Contabilidad del Fondo de Inversión (multimoneda)

**Rol:** controller financiero. **Fecha:** 2026-11-19. **Alcance:** fondo (`fdi_*`), compra/recepción, costo aterrizado, inversores.
**Método:** lectura del repo + consultas **SELECT** contra la BD conectada (PostgreSQL 17.4). Nada se modificó.

**Marcas:** `[H]` = hecho verificado (repo con `ruta:línea`, o BD con la consulta descrita). `[R]` = recomendación mía, discutible.
**Tasa de referencia usada en los ejemplos:** 1 USD = 1.000 CUP (`tasas_conversion`, fila USD→CUP = `1000.000000`, actualizada 2026-11-18 `[H]`).

## 0. Veredicto en seis líneas

1. El saldo **sí** es fuente de verdad materializada y verificable: cada movimiento guarda `saldo_anterior`/`saldo_nuevo`, así que hay tres comprobaciones independientes `[H]`.
2. Pero el sistema **cotiza la tasa en dos sentidos distintos** según el documento, y `fn_fdi_transferir` la usa al revés que el resto: el mismo par tiene dos números recíprocos `[H]`.
3. **No existe reserva/comprometido** en ninguna parte: el saldo es bruto y el "disponible" que se muestra es el saldo `[H]`.
4. El costo aterrizado **ya actualiza** `precio_promedio` y `precio_costo_usd` (valoración y margen futuros) `[H]`, pero con una ponderación defectuosa `[H]`.
5. El **pago a la importadora no es hoy costo del producto**: vive en un libro aparte sin moneda `[H]`. Sumarlo otra vez duplicaría el costo.
6. `fdi_dat_inversor` es **socio de utilidad**, no aportante de dinero. Son dos pasivos distintos y hoy solo existe el primero `[H]`.

## 1. Modelo de saldo actual

### 1.1 Qué es el saldo (HECHO)

`fdi_dat_saldo` = una fila por **(cuenta, medio de pago, moneda)** con un `saldo` almacenado, `CHECK (saldo >= 0)` y `UNIQUE (id_cuenta, id_medio_pago, moneda)` (`ventiq_admin_app/lib/sql/fondo_inversion_schema.sql:100-109`; constraints confirmados en BD).

**La moneda no es atributo de la cuenta.** `fdi_dat_cuenta` no tiene columna `moneda` (`:45-55`): la moneda vive en la fila de saldo. Por tanto una misma cuenta "Caja" puede tener CUP-efectivo y USD-efectivo como dos libros separados, y **no hay un "saldo de la cuenta"** sin decir moneda y medio. Esto contradice la premisa de "saldo por cuenta/moneda": el saldo es por **cuenta × medio × moneda**, y el medio (efectivo/transferencia) también segmenta el libro.

**¿Real o derivado?** Es **real (materializado) y redundante**. `_fdi_aplicar_movimiento` bloquea la fila (`FOR UPDATE`), calcula `saldo_nuevo = saldo_previo + delta`, actualiza el saldo y escribe el movimiento con ambos valores (`:349-407`). Nunca hay un saldo que se calcule sumando movimientos al vuelo: se lee la tabla. La suma de movimientos es el control, no la fuente.

### 1.2 Invariantes que el código mantiene (HECHO)

| # | Invariante | Dónde |
|---|---|---|
| I1 | `saldo_nuevo = saldo_anterior + monto` en cada movimiento | `:384`, `:395-405` |
| I2 | El `saldo` de la tabla es el `saldo_nuevo` del último movimiento de esa clave | `:391-393` |
| I3 | `saldo >= 0` siempre (CHECK + excepción explícita) | `:106`, `:385-389` |
| I4 | El saldo se crea en 0 si no existe; un solo escritor (`SECURITY DEFINER`, sin políticas de escritura en RLS) | `:377-382`, `:110-115` |

**Cuadre verificable:** para cada (cuenta, medio, moneda) debe cumplirse `saldo = Σ movimientos` **y** la cadena `saldo_anterior+ monto = saldo_nuevo` **y** `último saldo_nuevo = saldo`. Las tres se pueden calcular con SQL; es el reporte R1 de §6.

**Estado en la BD conectada (2026-11-19):** `fdi_dat_saldo` = 0 filas, `fdi_dat_movimiento` = 0, `fdi_dat_inversion` = 0, `fdi_dat_liquidacion` = 0. **El invariante nunca se ha ejercitado con dinero real en este entorno**: no hay histórico que auditar ni descuadre heredado que arrastrar. También hay deriva repo↔BD: `fn_fdi_gasto` **no existe** en la BD y el CHECK de `fdi_dat_movimiento` admite 8 tipos (sin `'gasto'`), mientras el repo ya define 9 (`fondo_inversion_gasto.sql:10-20`). Hoy **no hay camino válido para pagar a un proveedor desde el fondo**: una compra solo se puede modelar como "inversión" (`extraccion_inversion`).

### 1.3 Los otros tres libros de saldo (HECHO)

| Libro | Grano | Moneda | Escala |
|---|---|---|---|
| `fdi_dat_saldo` | tienda × cuenta × medio × moneda | `text` libre, **sin FK** a `monedas` | `numeric` sin escala |
| `dep_dat_saldo` | tienda × banco | en `dep_dat_banco.id_moneda` | `NUMERIC(14,2)` (`depositos_bancarios_schema.sql:111-118`) |
| `prv_dat_saldo` | tienda × proveedor | en `prv_dat_proveedor_config` | `NUMERIC(14,2)` |
| `imp_dat_saldo` | tienda (UNIQUE) | **sin columna de moneda**; el comentario dice "Saldo actual en USD" (`importadora_facturas_schema.sql:49-55`) | `NUMERIC(14,2)` |

`[H]` `fdi_dat_saldo.moneda` y `fdi_dat_movimiento.moneda` son `text` sin FK ni CHECK, mientras `monedas.codigo` es `bpchar(3)` y `app_dat_pago_venta.moneda` es `bpchar(3)` con CHECK: **el texto de la moneda no está normalizado entre módulos**.

`[R]` (D1) Un solo catálogo (`monedas`) con FK desde toda columna de moneda, `CHECK (moneda = upper(moneda))` y **la escala tomada de `monedas.decimales`** (ya existe: CUP/USD/EUR = 2; `monedas` verificado en BD). Sin esto, un `'usd'` tecleado crea un libro paralelo invisible.

## 2. Multi-moneda

### 2.1 Qué es una tasa y cómo la cotiza el código (HECHO)

Definición contable que adopto: **`T(A→B)` = unidades de B por 1 unidad de A**. `monto_B = monto_A × T(A→B)` y `T(B→A) = 1/T(A→B)`.

El sistema usa esa definición en tres sitios y **la inversa en uno**:

| Documento | Fórmula real | Sentido del par |
|---|---|---|
| `fdi_dat_inversion_fuente.tasa_a_ref` | `monto_ref := monto * tasa` (`:1313`) | **T(moneda → referencia)** — directo |
| `fdi_dat_inversion_recepcion.tasa_a_ref` | `monto_ref := monto * tasa` (`:1425`) | **T(moneda → referencia)** — directo |
| `app_dat_pago_venta.tasa_usd` | `monto_cup_equivalente = monto * tasa_usd` (`docs/plan-multimoneda/recon-esquema.md:258`) | T(moneda → CUP) — directo |
| `fdi_dat_transferencia.tasa` (`fn_fdi_transferir`) | `base_origen := monto_destino * p_tasa` (`:917-918`) | **T(destino → origen)** — par invertido |

No son dos tasas distintas: es el **mismo ratio expresado con el par al revés**. Ejemplo con 1 USD = 1.000 CUP:

- Transferir **1.000 USD → CUP**: `monto_destino = 1.000.000` CUP y `p_tasa` debe ser **0,001** (USD por 1 CUP) para que `base_origen = 1.000 USD`.
- Transferir **1.000.000 CUP → USD**: `monto_destino = 1.000` USD y `p_tasa` debe ser **1.000**.

Mismo par, mismo día, dos números recíprocos según la dirección. `fn_fdi_transferir` solo valida `p_tasa > 0` (`:889-891`): **no valida el sentido ni el orden de magnitud**.
`[R]` (D1) Regla única: guardar siempre **(moneda_origen, moneda_destino, tasa)** con `T(origen→destino)`, y prohibir un campo `tasa` sin par. En `fn_fdi_transferir` conservar la columna pero poblarla como `T(destino→origen)` **explícito** y desnormalizar la inversa para que ningún consumidor la recalcule. Añadir validación de cordura: rechazar si `T` se aparta >20 % de la última tasa de `tasa_cambio_extraoficial`/`tasas_conversion` del mismo par.

### 2.2 Las cuatro monedas y quién manda en cada documento (R)

| Moneda | Qué es | Manda en |
|---|---|---|
| **De la cuenta** | la del saldo físico (fila de `fdi_dat_saldo`) | el libro de caja: débitos/créditos, `saldo_anterior/nuevo` |
| **De la compra** | `app_dat_operacion_recepcion.moneda_factura` | la factura, el costo unitario y el costo aterrizado |
| **De referencia del fondo** | `fdi_dat_inversion.moneda_referencia` | la comparación "puse X, volvió Y" y el cierre de la inversión |
| **De reporte** | CUP (es la base del negocio: `monedas.es_base = true`) | estado de resultados, ganancia, márgenes |

`[H]` No hay una sola moneda de valuación: `app_dat_precio_costo.precio_costo_usd` guarda el costo en **USD**, `fdi_dat_liquidacion.ganancia_reporte` es en **CUP** (`:738`), y los reportes de valoración devuelven ambos (`warehouse_valuation_service.dart:99-128`).
`[R]` Añadir la **moneda del costo = USD** a la tabla anterior y hacerla explícita en el modelo: todo costo de producto se almacena en USD; todo asiento de caja se almacena en la moneda del saldo; todo reporte se presenta en CUP con la tasa del día de cierre y **la tasa usada se imprime en el reporte**.

### 2.3 Tasa congelada: cuándo y por qué (HECHO + R)

`[H]` Hoy la tasa solo se congela si la recepción está vinculada a una inversión: `tasa_cambio_aplicada`/`fecha_tasa_aplicada` se escriben **solo** cuando `p_id_inversion IS NOT NULL` (`fondo_inversion_recepcion_patch.sql:130-132`). Una compra normal queda con `tasa_cambio_aplicada = NULL` para siempre. Las tasas de las fuentes y de las recepciones de inversión sí se congelan al crear el documento (`:1324-1325`, `:1437-1445`), pero el **pago** no tiene ni columna de tasa.

`[R]` **Dos tasas por documento, ambas obligatorias:**
1. **Tasa de factura** (fecha de factura, o de recepción si la factura no la trae): congela el **costo**. `costo_cup = costo_usd × T(factura)`.
2. **Tasa de pago** (fecha del pago): congela la **salida de caja**.

`[R]` **La diferencia cambiaria es resultado financiero, no inventario.** Se reconoce en el momento del pago: `dif = monto_pagado_en_ref − monto_facturado_en_ref`; `dif > 0` = pérdida, `dif < 0` = ganancia. Cuenta de resultado "diferencia cambiaria" del fondo, ligada al documento de compra.

Ejemplo verificado: factura **2.000 USD @1.000 = 2.000.000 CUP**. Se paga 15 días después @1.100 = **2.200.000 CUP**. Inventario entra a **2.000.000**; la pérdida de **200.000 CUP** va a resultado. Si se capitalizara en el inventario, el costo unitario pasaría de 10.000 a 11.000 CUP (+10 %) y el margen de la venta dependería de **cuándo pagaste**, no de cuánto costó la mercancía. Se rechaza capitalizar.
`[R]` Y al revés: si la recepción ocurre **después** del pago, el inventario sigue entrando a la tasa de factura; la diferencia ya reconocida no se reajusta. **Una tasa, un momento, un documento.** Nunca "no se registra".

### 2.4 Redondeo (R)

`[H]` `monedas.decimales` ya existe y vale 2 para CUP/USD/EUR (BD). `fdi_dat_saldo.saldo` es `numeric` **sin escala**; `dep_dat_saldo` es `NUMERIC(14,2)`. Conviven dos políticas.

`[R]` (D5)
- Almacenar **montos** con la escala de `monedas.decimales` (2) y **tasas** con 6 decimales. Redondear **una sola vez**, al escribir el asiento, y **en servidor** (el plan multimoneda ya lo decidió así: `docs/plan-multimoneda/auditoria-fase3-tpv.md:401`). Ojo: en efectivo CUP la unidad mínima real es **1** (denominaciones 1, 3, 5 … 20.000: no hay centavos), así que un residuo de 0,01 CUP **no se puede pagar en cash**; si la cuenta es efectivo CUP, el residuo se lleva a la cuenta de ajuste, no se "pierde".
- Reparto de un monto global `M` entre líneas con pesos `wᵢ`: `asigᵢ = ROUND(M × wᵢ / Σw, 2)`; `residuo = M − Σ asigᵢ` (|residuo| ≤ 0,01 × n). **El residuo va a la línea de mayor base** (no a la última: la última es arbitraria y puede ser una línea de 0,50 CUP, donde 1 céntimo es 2 %). Si la mayor base está empatada, a la de menor `id` (determinista y auditable).
- Prohibido redondear dos veces el mismo importe (hoy el factor de presentación divide y luego se redondea: `costos_adicionales_producto.sql:456-457`). Ejemplo: comisión de 1.000 CUP entre 3 líneas iguales → 333,33 × 3 = 999,99 → residuo **0,01** a la primera. `Σ = 1.000,00`.

## 3. Costo real del producto (landed cost)

### 3.1 Fórmula exacta

```
costo_factura_unitario_neto[USD/base] =
    (precio_unitario − descuento_monto − precio_referencia × descuento_% / 100) / factor_rel

costo_aterrizado[USD/base] = costo_factura_unitario_neto + Σ_k (costo_adicional_k[USD] / cantidad_base_recibida)

costo_aterrizado_total = costo_aterrizado[USD/base] × cantidad_base_recibida
```

`[H]` Es literalmente lo que ya se calcula: `costo_real = (precio_unitario − descuento_monto) − (precio_referencia × descuento_%/100) + adicionales × factor_rel` (`costos_adicionales_producto.sql:427-435`) y la ponderación con `precio_unitario/factor_rel + Σ monto_usd` (`:453-476`). Los tres componentes existen: factura (`precio_unitario`), adicionales por concepto (`app_dat_cont_tipo_costo`), y factor de presentación.

`[H]` **Defecto:** `costo_real` solo se escribe `IF v_adicionales <> 0` (`:425`). Sin costos adicionales queda `NULL` y los reportes caen a `precio_unitario` (`fn_reporte_ventas_con_proveedor_por_turno.sql:229`). El mismo hecho tiene dos representaciones, y la que sobrevive depende de si hubo flete.

### 3.2 El "pago a la importadora" NO es un costo adicional (H)

`imp_dat_saldo` es un saldo **aparte**, sin moneda, que baja con `imp_dat_factura.valor` (`importadora_facturas_schema.sql:49-55`); no hay ninguna FK entre `imp_dat_factura` y `app_dat_recepcion_productos`. Es un **libro de financiamiento**, no una línea de costo.

`[R]` Hay que decidir **qué es** la factura de la importadora, y son excluyentes:
- **Si es la factura de la mercancía** (ella trae los productos y sus precios) → es **el** costo de factura. No se suma como adicional: hacerlo **duplica el costo**.
- **Si es un servicio de importación** (fija o % del valor) → es un **costo adicional** prorrateable. Debe entrar por `app_cont_tipo_costo`, no por `imp_dat_saldo`.

`[R]` Regla dura: **un pago = un documento origen**. Un mismo desembolso no puede tocar `imp_dat_saldo` y a la vez entrar como línea de costo adicional de la misma compra.

### 3.3 Criterio de reparto de los costos globales (R)

| Criterio | Cuándo | Ejemplo |
|---|---|---|
| **Por valor** (default) | el costo escala con el dinero: arancel, seguro, comisión % | aduana 5 % de 2.000 USD = 100 USD |
| Por cantidad | el costo escala con bultos/unidades: flete interno, manipulación | 60.000 CUP / 200 u = 300 CUP/u |
| Por peso/volumen | transporte real y el dato existe y es fiable | flete marítimo por m³ |


`[R]` **Default: por valor.** Es el único peso que siempre existe (está en la factura), no exige capturar peso ni volumen, y no se puede manipular por la puerta de atrás. Se cambia a **peso/volumen** cuando el transporte supere ~15 % del valor de la factura o cuando la densidad de la mercancía sea muy heterogénea (una compra de colchones y tornillos repartida por valor es falsa). Nunca "por cantidad" si los artículos tienen precios muy distintos.
`[H]` Lo que hay hoy es, de hecho, **"por cantidad" implícito**: un monto por unidad base configurado por producto (`app_dat_producto_costo.monto_usd`, `docs/PLAN_COSTOS_ADICIONALES.md:19-22`) y ponderado por cantidad recibida. No hay reparto por valor en el sistema.

### 3.4 ¿Actualiza el costo del producto? Sí (H) — y sus consecuencias

`[H]` El aterrizado entra en `app_dat_producto_presentacion.precio_promedio` (`costos_adicionales_producto.sql:516-526`) y deja historia en `app_dat_precio_costo.precio_costo_usd`. La valoración de almacén se calcula desde ahí (devuelve costo y venta en USD **y** CUP, `warehouse_valuation_service.dart:99-128`) y el margen comercial se define contra ese costo (`margin_service.dart:28-33`, `app_cont_margen_comercial`). Las ventas **pasadas** no se reescriben porque el costo se busca por fecha (`fondo_inversion_schema.sql:573-577`).

Consecuencia contable: subir el aterrizado **baja el margen de las ventas futuras** y sube el valor del inventario; es correcto, siempre que el costo se aplique en la recepción y no se reescriba después. Si mañana se corrige un flete de una compra ya cerrada, hay que generar un **ajuste de costo** (documento nuevo), no un UPDATE del histórico.

`[H]` **Defecto de ponderación:** `fn_actualizar_precio_promedio_recepcion_v3` toma como "cantidad anterior" la cantidad de **esa misma recepción** (`ventiq_admin_app/docs/migrations/12_fix_precio_promedio_recepciones_consignacion.sql:102-110`). Con ambos precios > 0, la fórmula `(pa × qa + pn × qn)/(qa + qn)` degenera en la **media simple** de precio viejo y nuevo. La valoración del inventario queda mal ponderada en toda recepción con stock previo.
`[R]` El peso "anterior" debe ser el **stock real antes de la recepción** (por presentación y almacén), y la fórmula debe quedar: `nuevo = (prom_previo × stock_previo + aterrizado × cant_recibida) / (stock_previo + cant_recibida)`, con `cant_recibida` en unidad base.

### 3.5 Recepción parcial: la regla (R)

**El costo global se reparte solo sobre lo recibido; lo no recibido no absorbe costo.**
Flete global 100.000 CUP para 100 unidades → 1.000 CUP/u. Se reciben **60**: se aplican **60.000** a las 60 unidades y **40.000 quedan "por asignar"** en una cuenta de costos pendientes hasta que llegue el resto.
Si se cargara todo a las 60: 100.000/60 = 1.666,67 CUP/u, un sobrecosto del **66,7 %** que se come el margen de las 60 y deja las 40 restantes con costo cero. Se rechaza.
`[R]` Si la compra se **cancela** con mercancía ya recibida, el remanente pendiente se reconoce como **pérdida** (o se devuelve al proveedor), nunca se redistribuye al inventario ya valorado.

## 4. Reserva vs consumo de fondos

### 4.1 Definiciones (R)

- **Saldo (bruto):** lo que hay. `fdi_dat_saldo.saldo`, con `saldo ≥ 0` `[H]`.
- **Reservado / comprometido:** dinero asignado a un documento abierto (compra autorizada, factura por pagar) que **todavía no salió**. No es un movimiento: **no toca el saldo** (si lo tocara, el `CHECK >= 0` lo convertiría en un pago).
- **Ejecutado:** ya salió (suma de movimientos negativos). **Disponible = saldo − reservado.**

`[H]` Reservado **no existe**: no hay tabla, columna ni tipo de movimiento; la búsqueda en `*.sql` del admin no devuelve ninguna reserva de fondos (las únicas "reservas" del repo son de **stock**, no de dinero). Hoy disponible ≡ saldo.

### 4.2 Cómo se reserva en multimoneda (R)

Se reserva **en la moneda de la cuenta** (monto nativo), no en equivalente de referencia. Motivo: la reserva protege la **capacidad de pagar en esa moneda**; un equivalente en CUP no paga una factura en USD.

Se guardan **dos columnas** y solo la primera manda: `monto` (nativo, duro) y `monto_ref_informativo` (equivalente con la tasa del día de la reserva, **solo para reporte, nunca para disponibilidad**). La tasa **no se revalúa** mientras la reserva esté viva: revaluarla cambiaría el disponible por un hecho (la tasa) que no cambió el dinero.
`[R]` Si el pago se hace con otra moneda, la reserva se **libera** y se crea una nueva en la moneda correcta; no se "convierte" una reserva.

### 4.3 Cuándo se libera y qué asientos genera (R)

| Evento | Asiento |
|---|---|
| Cancelación de la compra | liberación total: reserva → 0. **Sin movimiento de saldo.** |
| Recepción parcial con sobrante | libera el sobrante (`reservado − pagado_aplicado`) y mantiene vivo el resto |
| Pago | la reserva se **consume** y se crea el movimiento real (salida de saldo), en la misma transacción |
| Ajuste manual | liberación con motivo obligatorio + usuario (nunca silenciosa) |

Regla de oro: **la reserva y el pago de la misma compra no pueden coexistir** por el mismo monto (sería contar dos veces la misma salida).

### 4.4 "No se puede cerrar la compra si falta dinero" (R)

Se valida contra **disponible**, no contra saldo bruto.

Ejemplo: cuenta USD-efectivo con **2.000 USD**. Compra A reserva **1.500**; compra B pide **1.000**.
- Contra disponible (2.000 − 1.500 = **500**) → B se rechaza. Correcto.
- Contra saldo bruto (2.000 ≥ 1.000) → B se autoriza; compras la mercancía; al pagar A el saldo baja a 500 y el pago de B revienta con `Saldo insuficiente ... disponible 500, requerido 1000` (`fondo_inversion_schema.sql:386-388`). El error llega **después** de comprar.

`[R]` Regla: toda compra nace con reserva; el cierre exige `Σ disponible ≥ 0` **por (cuenta, medio, moneda)**, no en el total del fondo. Un total consolidado que cuadra puede esconder una cuenta CUP sin fondos y una USD sobrada.

## 5. Inversores que aportan a una compra

### 5.1 Lo que hay hoy (H)

`fdi_dat_inversor` es un **socio con porcentaje de utilidad**, no un aportante: `porcentaje` (>0 y ≤100), `activo`, y un trigger que reparte la ganancia retirada de cada liquidación según ese porcentaje (`fondo_inversion_inversores.sql:3-10`, `:88-131`). Detalles que confirman la naturaleza:
- Los porcentajes activos **deben sumar 100 %** salvo `repartir_igual` (`:110-112`).
- El reparto se trunca a **enteros**, **el remanente queda en el fondo** (`:114-122`, `:50-58`) y se paga marcando `pagado_at` + referencia (`:133-147`).
No hay monto aportado, ni devolución, ni interés, ni relación con una compra concreta. **No sirve** para "el inversor X puso 1.000 USD en esta compra".

### 5.2 Las tres figuras posibles (decisión del cliente) con su consecuencia contable (R)

| Opción | Naturaleza | Al aportar | Al devolver | Si la compra se cancela | Riesgo |
|---|---|---|---|---|---|
| **A. Pasivo / deuda** (recomendada si hay devolución pactada) | préstamo del inversor al fondo | entra caja; se acredita **deuda inversor** 1.000 USD | pago de 1.000 + interés pactado; el interés es **gasto financiero** | se devuelve íntegro + interés devengado | el fondo puede deber más de lo que ganó |
| **B. Capital (equity)** | aporte al patrimonio | entra caja; sube **capital** | solo por liquidación o con utilidades; sin fecha | **no se devuelve**: queda capital | el inversor exige % y diluye al dueño |
| **C. Anticipo restringido** | pasivo afectado a una compra | entra caja; **anticipo** etiquetado a la compra X | devolución del 100 %, sin rendimiento | devolución íntegra e inmediata | si se usa en otra compra, deja de ser anticipo |

`[R]` **Recomendación: C por defecto, A cuando haya rendimiento pactado, B solo si el inversor acepta pérdida.** Regla de hierro: **un inversor no puede tener simultáneamente porcentaje de utilidad y aporte de monto sobre la misma compra** — se contarían dos veces sus derechos (una por el reparto del trigger, otra por la deuda). Si convive, debe ser con documentos distintos y campos distintos.
`[R]` El modelo correcto necesita: `aporte(id_inversor, id_compra, moneda, monto, tasa_congelada, tipo: pasivo|capital|anticipo, vencimiento, tasa_interes)` + `devolucion(id_aporte, moneda, monto, fecha, referencia)`. La devolución **no** es un gasto: es cancelación de pasivo. Solo el interés es gasto.

Ejemplo verificado: inversor pone **1.000 USD** para la compra X. La compra deja **200 USD** de ganancia.
- A con 2 % pactado: devuelve **1.020 USD**; **20 USD** son gasto financiero; los **180 USD** restantes son del fondo.
- C: devuelve **1.000 USD**; los **200 USD** son del fondo.
- B: no se devuelve nada; el inversor reclama su % de los 200 USD según el contrato de capital.

## 6. Trazabilidad y auditoría

### 6.1 Lo que `fdi_dat_movimiento` ya registra (H)

`id_tienda`, `id_cuenta`, `id_medio_pago`, `moneda`, `monto`, `saldo_anterior`, `saldo_nuevo`, `tipo`, `id_liquidacion`, `id_transferencia`, `id_inversion`, `observacion` (texto libre), `created_by`, `created_at` (`fondo_inversion_schema.sql:117-136`).

Eso responde: **quién** (`created_by`), **cuándo** (`created_at`), **qué documento** (los tres `id_*`), **qué saldo antes/después** (columnas propias). Es una base buena y suficiente para reconstruir cualquier diferencia de saldo, no así de tasa (§6.2-1).

### 6.2 Lo que falta (H)

1. **No hay columna de tasa** en el movimiento: un movimiento en moneda distinta de la de reporte no se puede re-expresar después con la tasa que se usó. Es el hueco más caro.
2. **No hay `id_compra`/`id_operacion`**: una salida por compra solo se puede enlazar por `id_inversion`. Si la compra no es una inversión, el movimiento no apunta a nada.
3. **Idempotencia por texto**: `fn_fdi_gasto`/`ingreso_manual`/`ajuste` detectan el duplicado con `observacion LIKE '%idem:<uuid>'` (`:993-998`, `:1039-1044`, `:1093-1098`). No es una restricción única: dos reintentos concurrentes pueden pasar los dos y **duplicar el asiento**.
4. **No hay estado del documento**: `fdi_dat_liquidacion` y `fdi_dat_transferencia` no tienen `anulado`/`anulado_por`; solo se corrige con documento nuevo (`ajuste_correccion`, `id_transferencia_corregida`), lo cual está bien, pero no hay un campo que lo diga de un vistazo.
5. **`observacion` libre** como único motivo y **`fdi_dat_liquidacion` sin columna de moneda**: no hay `motivo` estructurado, y `ganancia_retirada_equivalente` se calcula con una tasa **que envía el cliente** (`p_tasa_validacion`, `:630`, `:761-763`, `:819-821`), así que el control de diferencia (`abs(diferencia) > 0.01`, `:768`) se puede neutralizar eligiendo la tasa.

### 6.3 Reportes mínimos de control (R)

| # | Reporte | Qué debe dar | Frecuencia |
|---|---|---|---|
| **R1** | **Conciliación de saldo** | por (cuenta, medio, moneda): `saldo` vs `Σ movimientos` vs `último saldo_nuevo`. Diferencia debe ser **0,00** | diario / tras cada cierre |
| R2 | Saldo por cuenta y moneda | saldo bruto, reservado, **disponible**, ejecutado del periodo | a demanda |
| R3 | Compras por estado | autorizada / recibida parcial / recibida total / pagada / cancelada, con **facturado vs costo aterrizado vs pagado** y la diferencia | semanal |
| R4 | Costo real vs factura | por compra: factura + adicionales = aterrizado; y % de desvío | por compra cerrada |
| R5 | Diferencias cambiarias | por documento: tasa factura, tasa pago, monto de la diferencia, signo | mensual |
| R6 | Movimientos por usuario y día | quién movió qué, con saldo antes/después (auditoría dura) | mensual |
| R7 | Inversores | aportes vs devoluciones vs utilidad repartida vs saldo pendiente | mensual |

`[R]` R1 es **no negociable**: es el único que prueba que el saldo es real. Debe correr solo y fallar ruidosamente (no un dashboard que nadie mira).

## 7. Riesgos de dinero y su defensa

| # | Escenario | Cómo descuadra | Defensa (punto de control) |
|---|---|---|---|
| **X1** | **Doble uso del mismo dinero**: dos compras se autorizan contra el saldo bruto | ambos pagos se comprometen; el segundo falla **después** de comprar | disponible = saldo − reservado; validar por (cuenta, medio, moneda) (§4.4) |
| **X2** | **Tasa en sentido contrario** en `fn_fdi_transferir` | crea o destruye valor sin contrapartida (ver abajo) | par explícito + validación de cordura ±20 % + inversa desnormalizada |
| X3 | **Doble costo de la importadora** | el mismo pago entra en `imp_dat_saldo` y como adicional | un pago = un documento origen; FK `id_compra` obligatoria |
| X4 | **Recepción parcial con costo global completo** | costo unitario inflado 66,7 % y margen falso | reparto pro-rata a lo recibido + cuenta "costos por asignar" |
| X5 | **Ponderación del promedio** con la cantidad de la misma recepción | inventario valorado mal en cada recepción con stock | peso = stock previo real (§3.4) |
| X6 | **Retry duplicado** de gasto/ajuste/ingreso | asiento doble, saldo doblemente debitado | `idempotency_key` como **columna UNIQUE**, no texto |
| X7 | **`moneda` como texto libre** en `fdi_*` y escalas distintas (`fdi` sin escala vs `dep` 14,2) | `'usd'` abre un libro paralelo; céntimos que no cuadran entre libros | FK a `monedas.codigo` + CHECK uppercase + `numeric(…, monedas.decimales)` |
| X8 | **Libro de importadora sin moneda** | pagos en CUP mueven un saldo "USD" | añadir `moneda` o fijar USD con CHECK y validarlo |
| X9 | **Liquidación con tasa del cliente** | la "ganancia" se cuadra a voluntad | tasa resuelta en servidor (histórico `tasa_cambio_extraoficial` por fecha); el cliente no la provee |
| X10 | **Cancelar recepción ya contabilizada** | `monto_recibido_ref` baja pero el costo y el promedio no se revierten | reversión explícita de costo (documento), no solo desvincular |
| X11 | **`fn_fdi_ajuste` solo positivo** como válvula de escape | se "arregla" un faltante inventando un ingreso | ajuste con motivo estructurado + doble aprobación por encima de un umbral |

**X2 en números (el descuadre más silencioso del código actual).** Cuenta CUP con 1.000.000 CUP. Se transfieren 1.000 USD a esa cuenta CUP y el operador (o la UI) escribe `p_tasa = 0,001` —el valor del USD→CUP leído al revés—. `base_origen = 1.000 × 0,001 = **1 CUP**`. La operación **pasa todas las validaciones** (`:889-891` solo exige `> 0`, y hay saldo), debita 1 CUP, acredita 1.000 USD y registra un movimiento con `saldo_anterior = 1.000.000`, `saldo_nuevo = 999.999`. El libro queda **perfectamente conciliado consigo mismo** (R1 da 0,00) mientras el fondo perdió **999.999 CUP**. Ningún reporte de los que existen lo detecta, porque la pérdida no está en ningún asiento: está en la aritmética.

## 8. Las cinco decisiones que hay que cerrar antes de escribir código

**D1 — Una sola convención de tasa.** `T(A→B)` = unidades de B por 1 de A; todo registro lleva el par explícito; `fn_fdi_transferir` se alinea o se documenta como `T(destino→origen)` con inversa desnormalizada y validación de cordura. *(Bloquea: transferencias, compras, valuación, reportes.)*

**D2 — Diferencia cambiaria = resultado financiero del fondo, reconocida en el pago**, con dos tasas congeladas por documento (factura y pago). Nunca capitalizada en inventario, nunca omitida. *(Bloquea: costo, margen, estado de resultados.)*

**D3 — Reserva explícita y disponible real.** Tabla de reservas por (cuenta, medio, moneda) en monto nativo; `disponible = saldo − reservado`; toda compra nace reservada y se valida por cuenta, no por total del fondo. *(Bloquea: autorización de compras, cierre de compra, doble uso.)*

**D4 — Reparto del costo global por valor por defecto** (cantidad/peso como excepción justificada), **el aterrizado sí actualiza `precio_promedio`**, y en recepción parcial el costo se aplica solo a lo recibido con un saldo "por asignar". *(Bloquea: costo unitario, inventario valorado, margen.)*

**D5 — Naturaleza del aporte del inversor (pasivo / capital / anticipo) separada del porcentaje de utilidad**, con devolución como cancelación de pasivo y solo el interés como gasto. **Decisión del cliente**; recomendación: anticipo restringido (C) por defecto, pasivo (A) si hay rendimiento pactado, capital (B) solo con aceptación de pérdida. *(Bloquea: todo el módulo de inversores y el cierre de la compra.)*