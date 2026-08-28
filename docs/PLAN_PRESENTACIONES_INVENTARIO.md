# Plan: inventario físico por presentaciones

Checklist de implementación. Marca `[x]` lo hecho y deja `[ ]` lo pendiente.

**Problema:** el modelo de datos ya permite stock por presentación (caja, unidad, etc.), pero la lógica convierte casi todo a la presentación `es_base` (“unidad”). No se puede entrar ni reportar “4 cajas y 4 unidades” como existencias distintas.

**Modelo objetivo:** el inventario es físico por presentación. 4 cajas y 4 unidades son dos saldos. Los reportes muestran exactamente eso. Si un egreso pide unidades y solo hay cajas, el sistema abre cajas; si pide cajas y solo hay sueltas, empaqueta. Precio de venta y costo siempre se derivan de la presentación base × factor.

---

## Decisiones cerradas

Tomadas en la sesión de planificación. No reabrir salvo cambio explícito al revisar este documento.

- [x] Stock físico separado por presentación. El reporte muestra “4 Cajas + 4 Unidades”, no el equivalente “52 unidades” como cantidad de almacén.
- [x] Abrir automático: vender/mover 1 unidad con 4 cajas y 0 sueltas → `-1 caja`, `+(factor − 1) unidades`, luego descuenta 1 unidad.
- [x] **Pero el TPV pregunta antes de abrir** (decidido después de investigar la industria; ver [Fase 4.1](#41-confirmar-antes-de-abrir-empaque-decidido-sí-se-pregunta)). El rebalanceo automático se queda en el SQL sin cambios; lo que se agrega es un diálogo de confirmación en la UI de venta, con opción de "no volver a preguntar" por TPV. Ningún ERP grande rompe un empaque en silencio, y abrir una caja es irreversible en el mundo físico. Habilitado por `fn_preview_rebalanceo` (`presentaciones_inventario/10_preview_rebalanceo.sql`), que simula sin escribir.
- [x] Empaquetar automático: vender/mover 1 caja con 0 cajas y 20 sueltas (factor 12) → arma 1 caja desde 12 unidades y la mueve; quedan 8 unidades.
- [x] Abrir/empaquetar aplica a **todos los egresos** (venta, extracción, transferencia, recetas/BOM) y a **ajuste/conteo** cuando el delta de **una** presentación no cubre con su propio saldo.
- [x] Precio de venta y costo: siempre presentación base × factor. No hay precio ni costo independiente por caja. `precio_promedio` vive en la fila `es_base`; el resto se deriva.
- [x] Alcance: inventario completo + TPV + IPV + valoración de almacén + costos + reportes de ventas, en `ventiq_app` y `ventiq_admin_app`.
- [x] Marketplace: fuera de alcance.
- [x] Cadena con 3+ presentaciones (Pallet / Caja / Unidad): ordenar por `app_dat_producto_presentacion.cantidad` (factor a base). Abrir convierte a la **siguiente más chica**; empaquetar a la **siguiente más grande**. No saltar a base si hay nivel intermedio.
- [x] Kardex de movimientos: **misma tabla**. Entrada/Salida muestran `{qty} {presentación}` (`4 Cajas`, `1 Unidad`). Saldo = texto mixto del almacén tras ese movimiento (`3 Cajas + 11 U`). Filtro opcional por presentación.
- [x] Reportes de ventas (general, por proveedor y resumen de cierre): **una fila por producto**. Cantidad visible = desglose mixto. Columna extra **Equiv. unidades**. Dinero = precio/costo **base** × equivalente.
- [x] **El factor de una presentación con movimientos no se puede editar** (decidido después de investigar la industria; ver [Fase 2.0](#20-prerequisito--congelar-el-factor-decidido-sí-con-trigger--aplicado)). El factor se interpreta al leer, así que cambiarlo reescribe el histórico sin dejar traza. Trigger aplicado: `presentaciones_inventario/12_congelar_factor_presentacion.sql`, con escape explícito para errores de carga.

Ejemplo de cadena: 1 pallet = 10 cajas = 120 unidades. Vender 1 unidad teniendo solo 1 pallet → abre pallet a 10 cajas, abre 1 caja a 12 unidades, vende 1 unidad → `0 pallet, 9 cajas, 11 unidades`.

---

## Diagnóstico: por qué hoy todo es “unidad”

### Lo que el schema ya permite

Definido en [VentiQ.sql](../VentiQ.sql):

| Tabla | Rol |
|-------|-----|
| `app_nom_presentacion` | Catálogo (Caja, Unidad, …) + `es_fraccionable` |
| `app_dat_producto_presentacion` | Producto ↔ presentación: `cantidad` (factor a base), `es_base`, `precio_promedio` |
| `app_dat_inventario_productos` | Ledger. Clave `(producto, variante, opción, ubicación, id_presentacion)`. `id_presentacion NOT NULL` |
| `app_dat_recepcion_productos` / `app_dat_extraccion_productos` / `app_dat_control_productos` | Movimientos con `id_presentacion` + `cantidad` |
| `app_dat_presentacion_unidad_medida` | Puente a UM (recetas/costo culinario). **No** es el ledger de inventario |
| `app_inf_presentacion_producto` | Equivalencias informativas. **No** mueve stock |

`app_dat_producto_presentacion.cantidad` = cuántas unidades **base** representa esa presentación (ej. Caja × 12). `es_base` marca la unidad de registro comercial (costo y precio).

La RPC [fn_registrar_recepcion_con_inventario](../SQL_OPTIMIZATION/fn_registrar_recepcion_con_inventario.sql) **no convierte**: toma `id_presentacion` y `cantidad` del JSON, busca el último `cantidad_final` de **esa** presentación en esa ubicación, y suma.

### Lo que la lógica hace mal

Quien rompe el modelo son los **callers**, no el schema:

```
UI elige 4 Cajas
        │
        ▼
PresentationConverter / convertToBasePresentacion
  o fn_productos_json_a_presentacion_base
        │  cantidad = 4 × 12, id → presentación base
        ▼
RPC recepción / extracción / transfer
        │
        ▼
inventario: 48 unidades base  (se pierde el empaque físico)
```

**Admin (`ventiq_admin_app`)**

- [presentation_converter.dart](../ventiq_admin_app/lib/utils/presentation_converter.dart): `cantidad_final = qty * factor` y cambia `id_presentacion` a la base **antes** de guardar. El comentario dice que el precio ingresado es “por presentación base”.
- [product_quantity_dialog.dart](../ventiq_admin_app/lib/widgets/product_quantity_dialog.dart): un dropdown + una cantidad. No hay “4 cajas y 4 unidades” en el mismo formulario.
- [inventory_service.dart](../ventiq_admin_app/lib/services/inventory_service.dart): vuelve a convertir con `convertToBasePresentacion` al armar el payload.
- Transfers: `fn_productos_json_a_presentacion_base` (en migraciones de transfer entre layouts y personas).
- Stock UI ([inventory_stock_screen.dart](../ventiq_admin_app/lib/screens/inventory_stock_screen.dart)): `"${qty} unidades"` hardcodeado.
- Kardex ([product_movements_screen.dart](../ventiq_admin_app/lib/screens/product_movements_screen.dart)): Entrada/Salida/Saldo son números. RPC `get_product_movements_v3` **no devuelve** presentación. La auditoría de huecos asume un solo flujo del producto (con mixto hay uno por ubicación+presentación). Excel/PDF suman qty crudas (4+4=8).
- Ventas admin ([sales_screen.dart](../ventiq_admin_app/lib/screens/sales_screen.dart)): `Cant Vendidos` numérico; dinero = `precioVentaCup * totalVendido`. El SQL agrupa por `id_presentacion` pero **no la expone**.
- Cierre vendedor ([venta_total_screen.dart](../ventiq_app/lib/screens/venta_total_screen.dart), [sales_monitor_fab.dart](../ventiq_app/lib/widgets/sales_monitor_fab.dart)): `Vend.` e `Inicial/Final` son un número; FAB dice `N uds`. `fn_resumen_diario_cierre.productos_vendidos` suma qty crudas. `OrderItem` no tiene presentación.

**Vendedor (`ventiq_app`)**

- Recepción ([admin_reception_screen.dart](../ventiq_app/lib/screens/admin/admin_reception_screen.dart)): un dropdown + una cantidad; envía la presentación elegida **sin** convertir en cliente (mejor que admin), pero no permite mixto.
- Extracción / transferencia / ajuste: fuerzan `es_base`.
- Venta ([product_details_screen.dart](../ventiq_app/lib/screens/product_details_screen.dart)): la UI deja elegir Caja, pero el carrito manda `cantidad = qty * factor` (unidades base) y el `id_presentacion` de la **fila de inventario**, no de la presentación elegida.
- Listados: un número de stock, sin desglose.

**SQL de venta** ([registrarventa_ok.sql](../registrarventa_ok.sql) y variantes mesa/offline/cocina)

- Si no viene `id_presentacion`, toma la primera fila de `app_dat_producto_presentacion` por `id ASC` (no necesariamente `es_base`).
- El descuento de inventario a menudo toma el **último movimiento del producto** y **no filtra por `id_presentacion`**. Con stock mixto descuenta la fila equivocada.
- Recetas/BOM: mismo patrón de “última fila” (parcialmente corregido por almacén en cocina; sigue sin rebalanceo de presentaciones).

**Reportes**

- `obtener_ipv` agrupa internamente por presentación, pero valora `qty * costo` sin pasar por factor, y la UI no arma “4 Cajas + 4 Unidades”.
- `fn_stock_producto_almacen`: `SUM(cantidad_final)` entre presentaciones **sin factor** (4 cajas + 4 unidades = 8, no 52).
- `fn_inventario_resumen_*`: `cant_unidades_base` multiplica **todas** las filas por el factor de la base (correcto solo si el stock ya está en base).
- Reportes de ventas / costos: prefieren `ORDER BY es_base DESC` y `precio_promedio / cantidad_um`. `fn_reporte_ventas_con_proveedor4` hace `GROUP BY id_presentacion` y luego oculta esa clave: el cliente puede ver dos filas del mismo producto o fusionar mal 2 cajas + 5 u = 7.

**Dato de producción (contexto):** ~99.7 % de los saldos actuales viven en presentación base. El schema ya permite no-base; la operación no las usa.

### Dos sistemas que no hay que mezclar

1. **Presentaciones de inventario** (`app_dat_producto_presentacion`) = empaque físico. Este plan.
2. **Unidades de medida** (`app_nom_unidades_medida`, `app_dat_producto_unidades`, `app_dat_presentacion_unidad_medida`) = recetas y costo culinario. Siguen igual.

`app_inf_presentacion_producto` queda informativo (“1 Caja = 12 Unidades” en ficha de producto).

### Confusión de IDs (hay que cerrarla)

En JSON de apps a veces va:

- `app_dat_producto_presentacion.id` (PK del vínculo; es el FK real de inventario), o
- `app_nom_presentacion.id` (catálogo).

**Contrato:** `id_presentacion` en movimientos e inventario = `app_dat_producto_presentacion.id`. Documentar y validar en RPCs.

---

## Contrato de datos (sin rediseñar tablas)

No hace falta cambiar el schema de inventario. Sí hace falta:

- Dejar de convertir a base **antes** de escribir.
- Un helper SQL único de descuento/rebalanceo, usado por todas las rutas de egreso.
- Movimientos de **conversión** (abrir/empaquetar) en el mismo ledger, con `origen_cambio` (o tipo de operación) propio, para que IPV no cuente una apertura como venta ni como merma.
- Cantidad en cada fila = unidades **de esa presentación**, no equivalente en base.

Costo: al recibir, el precio de línea se interpreta en la presentación de esa línea y se convierte a base solo para el promedio ponderado:

```
costo_base = precio_linea / factor
qty_base   = cantidad_linea * factor
precio_promedio (es_base) = promedio ponderado por qty_base
precio_caja (display)     = precio_promedio_base * factor_caja
```

Venta: `precio_unitario` de la línea = precio de venta base × factor de la presentación vendida. La cantidad de la línea es en esa presentación.

---

## Conteo vs rebalanceo (importante)

Hay dos modos; no confundirlos:

1. **Conteo mixto completo:** el usuario declara lo que hay físicamente (4 cajas y 4 unidades). El sistema **setea** cada saldo. La cuenta física manda. No se abren cajas solas.
2. **Ajuste de una sola presentación:** el usuario baja (o extrae) solo unidades y no hay sueltas suficientes. Ahí sí se abren cajas para cubrir el delta (decisión cerrada).

La UI de conteo debe capturar cantidades **por presentación** para que el caso 1 sea el normal.

---

## No hacer

- [x] No guardar todo en unidades base y “dibujar” 4 cajas + 4 unidades con división greedy.
- [x] No dar precio/costo independiente por presentación.
- [x] No rediseñar UM / recetas más allá de usar el helper de descuento.
- [x] No incluir marketplace en este plan.
- [x] No migrar saldos históricos (ya están en base = “N Unidades”). Las entradas nuevas crean saldos no-base.
- [ ] Operación manual de menú “Abrir caja”: no en este plan. El rebalanceo es implícito en egresos. Se puede añadir UI explícita después.

---

## Fase 0 · Helper SQL de stock mixto y rebalanceo

> Una sola fuente de verdad para saldos, equivalente a base, abrir y empaquetar.

**Estado: aplicado en producción y verificado.**
SQL en [presentaciones_inventario/](../presentaciones_inventario/) (ver su README para el detalle y el resultado de los tests).

### 0.1 Funciones nuevas

- [x] `fn_stock_saldos_presentacion` — saldo actual por presentación (producto, ubicación, variante, opción). Archivo `02`.
- [x] `fn_equivalente_base` — `sum(saldo * factor_rel)` solo para dinero, rotación y “¿alcanza el equivalente?”. Archivo `02`.
- [x] `fn_formatear_stock_mixto` — texto `"4 Cajas + 4 Unidades"` (omite saldo 0). Es **pura** (opera sobre jsonb, no consulta la base) para que el helper Dart la replique idéntica. Archivo `02`.
- [x] `fn_rebalancear_presentaciones` — abrir o empaquetar en cadena hasta cubrir `cantidad`; escribe movimientos de conversión. Archivo `03`.
- [x] `fn_descontar_con_rebalanceo` — rebalancea y descuenta. Archivo `03`. Más `fn_descontar_con_rebalanceo_almacen` para cuando el caller solo sabe el almacén.
- [x] `fn_ingresar_presentacion` — entrada en la presentación tal cual, sin conversión. Una llamada por línea. Archivo `03`.

Extras que hicieron falta al mirar producción:

- [x] `fn_presentaciones_producto` — cadena Pallet>Caja>Unidad con `factor_rel`, `factor_hijo` (abrir un escalón) y `factor_padre` (empaquetar). Es la base de todo lo demás.
- [x] `fn_validar_id_presentacion` — cierra la confusión de IDs; distingue el caso “me mandaste `app_nom_presentacion.id`”.
- [x] `fn_stock_mixto_json` — payload único (desglose + equivalente + texto) para las apps.
- [x] `fn_plural_presentacion` — pluralización en español del nombre de la presentación.

Tipo de conversión: se reutiliza `app_nom_tipo_operacion.id = 20` (“Cambio de presentacion”, ya existía con 0 usos) y `origen_cambio = 20`. **No basta con `origen_cambio`**: `obtener_ipv` y `obtener_reporte_inventario_completo*` clasifican como ajuste toda fila con `id_recepcion/id_extraccion/id_control` en NULL, así que hace falta la marca explícita `app_dat_inventario_productos.id_conversion` (archivo `01`).

### 0.2 Tests SQL mínimos

Todos ejecutados con `BEGIN; … ROLLBACK;` sobre datos reales (archivo `05`). Producción quedó intacta, verificado después del rollback.

- [x] Entrar 4 cajas + 4 u (caja=12) → saldos 4 y 4; equivalente base 52.
- [x] Vender 1 u con 4 cajas y 0 sueltas → 3 cajas + 11 u (estrategia `abrir`).
- [x] Vender 1 caja con 0 cajas y 20 u → 0 cajas + 8 u (estrategia `empaquetar`).
- [x] Pallet/caja/unidad: vender 1 u con solo 1 pallet (factores 120 / 12 / 1) → 0 pallet, 9 cajas, 11 u, con **dos** conversiones en cadena (no se salta a base).
- [x] Stock insuficiente en equivalente base → error `INSUFFICIENT_STOCK_CONVERTIBLE`, 0 saldos negativos.
- [x] Extra: si el saldo propio alcanza, no se abre nada (estrategia `ninguna`).
- [x] Extra: cada conversión deja 2 patas en el ledger y su neto en equivalente base es 0.
- [x] Extra: producto de una sola presentación sin regresiones.
- [x] Extra: almacén con 2 ubicaciones — consume el saldo propio de una y abre en la otra.

### 0.3 Guardas de triggers (no estaba en el plan original)

`app_dat_inventario_productos` tiene tres triggers vivos. Dos hacen algo incorrecto con stock mixto y hubo que blindarlos (archivo `04`, **hay que aplicarlo antes de usar el `03` en producción**):

- [x] `fn_sincronizar_stock_producto` publicaba `NEW.cantidad_final` crudo en `carnavalapp."Productos"`: con 4 cajas de 24 publicaba “4”. Ahora publica el equivalente en unidades base de la ubicación e ignora las patas de conversión.
- [x] `fn_notificar_producto_disponible` habría mandado un push falso “ya está disponible” cada vez que se abre una caja (las sueltas nacen en 0). Ahora ignora las conversiones.
- [x] `fn_notificar_producto_agotado` es AFTER UPDATE y la Fase 0 solo hace INSERT: no se toca.

**Dependencias:** ninguna.  
**Entrega:** RPCs de movimiento pueden dejar de convertir en cliente.

---

## Fase 1 · Dejar de convertir en escrituras

> El JSON llega con presentación y cantidad reales. El SQL escribe eso.

**Estado: SQL escrito, ensayado y aplicado. Dart hecho, `dart analyze` limpio.**
SQL en [presentaciones_inventario/](../presentaciones_inventario/) archivos `06`, `07`, `08` y los tests `09`.

### SQL

- [x] `fn_registrar_recepcion_con_inventario` (archivo `06`): valida `id_presentacion` (rechaza el id del catálogo y el de otro producto, etapa `validacion_presentacion` / `V0008`), resuelve la base si no viene, y delega el movimiento en `fn_ingresar_presentacion`. **Además arregla un empate real:** leía el saldo con `ORDER BY created_at DESC`, y como `NOW()` es constante dentro de la transacción, varias líneas del mismo producto en una recepción empataban y el desempate lo decidía el plan de ejecución. Verificado: 2+3+4 cajas ahora encadena 0→2, 2→5, 5→9.
- [x] `fn_crear_extraccion_con_movimiento` (archivo `07`): **es el único punto de egreso del sistema** — lo llaman consignación (`crear_devolucion_consignacion_v2`, `aprobar_devolucion_consignacion_v2`), la transferencia, `fn_admin_caja_extraccion_offline` y cuatro sitios en Dart. No validaba stock en ningún punto: pedir 1 unidad con 4 cajas y 0 sueltas escribía `cantidad_final = -1`. Ahora exige `id_ubicacion`, valida la presentación y descuenta con `fn_descontar_con_rebalanceo`.
- [x] `fn_transferir_inventario_entre_layouts` (archivo `07`): se eliminó la llamada a `fn_productos_json_a_presentacion_base`. **Criterio de aceptación cumplido:** transferir 2 cajas deja `2 Cajas` en el destino, no `24 Unidades`.
- [x] `fn_insertar_ajuste_inventario2` (archivo `08`): lee el saldo previo real en vez de creerle al cliente. **De las 3.235 filas de ajuste del ledger, 202 tenían un `cantidad_inicial` que no coincidía con el saldo real previo** — un conteo con la pantalla desactualizada pisaba el saldo. Ahora manda el saldo real y anota el desfase en las observaciones (`[saldo declarado 99, saldo real 2]`) y en la respuesta (`desfase: true`). `fn_admin_caja_ajuste_inventario_offline` hereda el arreglo sin tocarla, porque solo delega.
- [x] Ya no queda **ninguna** función viva que llame a `fn_productos_json_a_presentacion_base` (verificado en el catálogo, filtrando los comentarios). La función se deja existir, sin usarse.
- [x] Ninguna firma cambió, así que ningún caller —Dart o SQL— necesitó adaptarse.

### Dart

- [x] [presentation_converter.dart](../ventiq_admin_app/lib/utils/presentation_converter.dart): reescrito. Ya no multiplica por el factor ni sustituye el `id_presentacion` por el de la base. Se conservan las claves de metadatos (`conversion_applied`, `presentacion_original_info`, `presentation_info`) que consumen `conversion_info_widget.dart` e `inventory_reception_screen.dart`; `conversion_applied` es siempre `false`, así que el aviso naranja de "Conversiones Aplicadas" ya no aparece.
- [x] [inventory_service.dart](../ventiq_admin_app/lib/services/inventory_service.dart): `processProductsForReception` / `processProductsForExtraction` **aplanaban una segunda vez** lo que ya venía del diálogo. Ahora solo validan la forma de la línea.
- [x] `ProductService.convertToBasePresentacion` marcado `@Deprecated`; sin llamadores.
- [x] `ventiq_app`: nuevo [presentation_selection.dart](../ventiq_app/lib/utils/presentation_selection.dart) y las cuatro pantallas admin (extracción, transferencia, ajuste, venta por acuerdo) dejan de forzar `es_base`. **El patrón que quitaron tenía un fallo concreto:** `orElse: presentaciones.first` elegía la primera fila cuando el producto no tiene ninguna marcada `es_base` (hay 9 así) y el orden no está garantizado, así que podía caer la Caja y registrar 3 cajas donde el usuario contó 3 unidades.
- [x] `admin_sale_agreement_screen.dart` mandaba `id_presentacion: presentationId ?? 1`. Ese `1` es el id de la presentación de **otro** producto; la validación del servidor ahora lo rechaza con un mensaje explícito.
- [x] `admin_inventory_service._normalizeReceptionProducts` deja de resolver la presentación (seguía teniendo el mismo `orElse`). Sigue rellenando `id_ubicacion`, que el ledger sí necesita.
- [x] `admin_reception_screen.dart` (`ventiq_app`) no necesitó cambios: ya tiene dropdown de presentación y manda la elegida sin convertir. Solo la **preselecciona** por defecto, que es un default de UI y el usuario lo ve y lo puede cambiar.

### Revisado después (no era Fase 1)

- [x] Consignación (`aceptar_envio_consignacion(bigint,uuid,jsonb)`): **sí existe** (la verificación anterior fue incorrecta). Revisada: **no aplana** — no llama a `fn_productos_json_a_presentacion_base`. Es un caso aparte porque es **cross-tienda**: duplica el producto en la tienda destino y usa `app_dat_producto_consignacion_duplicado.id_presentacion_duplicada`, cayendo a `es_base` del producto **duplicado** solo si no hay mapeo. Medido: **558 duplicados, 0 con presentación no-base**, así que hoy el fallback nunca se ejerce con empaques. Queda anotado como límite conocido: si algún día se consigna en Cajas, la línea de recepción del destino se registrará en la base de ese producto duplicado.
- [x] Ventas TPV (`fn_registrar_venta*`, mesa, offline, cocina): **cerrado en Fase 4** (`22`, `24`, `25`).

**Dependencias:** Fase 0.
**Entrega:** una recepción de 4 cajas queda 4 en caja, no 48 en unidad; los egresos abren empaque en vez de dejar saldo negativo.

---

## Fase 2 · UI de entrada / salida mixta

> Un formulario, N cantidades (una por presentación del producto).

### 2.0 Prerequisito · congelar el factor (decidido: sí, con trigger) — **APLICADO**

**SQL aplicado y verificado en producción el 2026-08-26:**
`presentaciones_inventario/11_indices_presentacion.sql` (6 índices),
`12_congelar_factor_presentacion.sql` (el trigger), tests en el `13` — los 12 bloques pasan.

El factor **no se copia al ledger, se interpreta al leer**
(`factor_rel = pp.cantidad / cantidad_de_la_base`). El ledger guarda `4` en la
fila de Caja; que eso valga 48 unidades o 96 lo decide `pp.cantidad` **hoy**.
Cambiar el 12 por un 24 en una Caja que ya tiene historia no corrige un dato:
reescribe el pasado. El IPV y la valoración de meses cerrados cambian solos, sin
que se haya insertado ni borrado un solo movimiento y sin dejar traza.

Medido en producción: **7.486 de 8.891 filas ya tienen movimientos (84 %)**, y
antes de esto nada lo impedía — el único trigger de la tabla mira
`precio_promedio`. NetSuite y SAP B1 prohíben cambiar la UM base de un ítem con
transacciones por exactamente esto.

Va antes de la Fase 2 porque la Fase 2 abre la edición de presentaciones en la
UI: sin la red debajo, cada pantalla nueva es otra puerta al mismo daño.

- [x] Trigger `trg_congelar_factor_presentacion` BEFORE UPDATE OF (`cantidad`, `id_presentacion`, `es_base`, `id_producto`) OR DELETE, que solo bloquea si esa fila ya tiene movimientos. Rechaza con **SQLSTATE 23001** y un mensaje que explica el motivo.
- [x] `fn_presentacion_tiene_movimientos(id)` con GRANT, para que la UI decida antes de dejar escribir.
- [x] **6 índices por `id_presentacion`** (archivo `11`). Los dos que existían sobre el ledger arrancan por `id_producto` y no servían: la comprobación hacía 4 Seq Scan sobre 720.000 filas, ~120 ms. Ahora **0,3 ms** con Index Only Scan. Lo destapó un timeout al correr los tests, y hubiera pegado en producción cada vez que se abriera la pantalla de edición de un producto.
- [x] Escape explícito para errores de carga: `SET LOCAL ventiq.permitir_cambio_factor = 'on'` (muere con la transacción).
- [x] `precio_promedio`, los INSERT y las filas sin historia siguen libres.
- [x] **UI que lo acompaña** — resuelta. Los tres sitios de `add_product_screen.dart` que el trigger rechazaba ya llevan guardas (verificado en el código): el UPDATE de `es_base` (~6380) solo toca filas que cambian de verdad, el de `cantidad` de la base (~6403) solo corre si el campo es editable, el de las adicionales (~6844) lleva `.neq('cantidad', cantidad)`, y el `catch` final traduce el error con `PresentacionEditableService.mensajeDeError`.
- [x] **RPC de apoyo para la UI**: `presentaciones_inventario/14_presentaciones_editable.sql` — `fn_presentaciones_producto_editable(id_producto)` devuelve la cadena completa con `factor_editable`, `puede_borrarse` y `motivo_bloqueo`. **Una** llamada por producto en vez de una por presentación. **Aplicada y verificada**, con guarda `check_user_has_access_to_tienda` (el proyecto no usa RLS).
- [x] **Dart**: `ventiq_admin_app/lib/services/presentacion_editable_service.dart` (modelo `PresentacionEditable` + `mensajeDeError` que traduce 23001 y 23503).
- [x] `add_product_screen.dart`: campo de cantidad de la base en `readOnly` con candado y diálogo explicativo; las presentaciones adicionales muestran "Factor bloqueado" en la fila y sus botones editar/eliminar explican en vez de fallar; los borrados imposibles se saltan y se avisan al final sin abortar el guardado del resto.
- [x] **Bug bloqueante que introdujo el trigger, corregido**: el guardado hacía `update({'es_base': false})` sobre todas las filas y luego reafirmaba la base — eso rompía **7.454 de 8.779 productos** con un 23001 aunque el usuario no cambiara nada. Ahora cada UPDATE lleva un `WHERE` que lo limita a filas que cambian de valor de verdad. Verificado contra producción: guardar sin cambios pasa, un cambio de factor genuino sigue rechazado.
- [x] Ojo con el borrado: hay **87 presentaciones sin movimientos que igual no se pueden borrar** porque `trg_registrar_precio_costo` les creó una fila en `app_dat_precio_costo` y esa FK es NO ACTION. Es preexistente; la UI ya lo informa en vez de fallar (`PresentacionEditableService.mensajeDeError` traduce el 23503 y el guardado sigue con el resto).
- [x] Revisados los otros write paths que tocan `app_dat_producto_presentacion`: **ninguno necesita cambios.** `ventiq_app/lib/services/admin_inventory_service.dart:1436-1443` solo escribe `precio_promedio` (que el trigger no bloquea) y el `.eq('es_base', true)` es un **filtro de WHERE**, no un `SET`. `ventiq_marketplace/lib/services/store_management_service.dart` solo **lee** (`select ... .eq('es_base', true)`) en tres sitios.
- [x] Los tres sitios de `add_product_screen.dart` que el trigger rechazaba **ya están resueltos** (verificado en el código): el UPDATE de `es_base` (línea ~6380) lleva `WHERE` que lo limita a filas que cambian de verdad, el de `cantidad` (~6403) solo corre si el campo es editable, el de presentaciones adicionales (~6844) lleva `.neq('cantidad', cantidad)`, y el `catch` final traduce el error con `PresentacionEditableService.mensajeDeError`.

### Admin

- [x] [product_quantity_dialog.dart](../ventiq_admin_app/lib/widgets/product_quantity_dialog.dart): **enchufado y emitiendo una línea por presentación.** Verificado en el código: importa `cantidad_mixta_input.dart`, tiene `List<LineaMixta> _lineasMixtas`, monta el `CantidadMixtaInput` (línea ~881) y `_submitForm` itera `for (final linea in _lineasMixtas)` llamando `onProductAdded` una vez por línea. Los descuentos y la bonificación van **solo en la primera línea** (`linea == _lineasMixtas.first`) para no multiplicarlos por presentación, y `lineasSinPrecio` bloquea el guardado si falta un precio.
      **Piezas de apoyo, con `dart analyze` limpio:**
      `ventiq_admin_app/lib/services/presentacion_cadena_service.dart` — `PresentacionCadena` (cadena desde `fn_presentaciones_producto`, con caché por producto) y `StockMixto` (desde `fn_stock_mixto_json`, con `saldoDe(idPresentacion)`).
      `ventiq_admin_app/lib/widgets/cantidad_mixta_input.dart` — un campo por eslabón de la cadena, del empaque mayor al menor; muestra `1 Caja = 12 Unidades` y `disponible: N` por fila; abajo el resumen `4 Cajas + 4 Unidades` / `= 52 Unidades`; avisa cuando falta saldo suelto y el servidor va a abrir empaque. Emite `List<LineaMixta>`, no convierte nada.
      **Falta:** enchufarlo en el diálogo y que `_submitForm` emita una línea por presentación (la pantalla de recepción ya dedupe por `id_producto + id_presentacion`, así que basta llamar `onProductAdded` una vez por línea).
      **Decisión tomada: un precio por presentación.** El widget acepta `capturarPrecio: true` y pide precio en cada fila con cantidad, con el importe de la línea y el total abajo. No se deriva `precio_base × factor` porque una caja no cuesta 12× la unidad (descuento por volumen) — derivarlo sería reintroducir por el lado del dinero el mismo aplanado que la Fase 1 quitó del inventario. `lineasSinPrecio` expone las filas con cantidad y sin precio para que el formulario padre no deje guardar.
- [x] Precio de línea: en la presentación de esa línea; el promedio a base lo hace el servidor (`20_costo_promedio_en_base.sql`), no el cliente.
- [x] **Extracción admin**: `inventory_extraction_screen.dart` usa `CantidadMixtaInput` (verificado).
- [x] **Ajuste admin**: `inventory_adjustment_screen.dart` abre un diálogo **por presentación** con el desglose mixto de la zona a la vista (Fase 2) y manda `null` en vez de `?? 0` (Fase 5).
- [x] **Transferencia admin**: ya está migrada, el pendiente apuntaba a **dos sitios muertos**. La pantalla real (`inventory_transfer_screen.dart`) **no usa diálogo de cantidad**: usa una lista con un campo por fila, y las filas ya son **una por presentación** — el `variant_key` incluye `id_presentacion` (L178), el dedupe agrupa por `id_producto + id_presentacion` (L187), la fila muestra `presentacion_nombre` (L1039) y el payload manda `id_presentacion` (L241). Transferir «2 Cajas + 3 Bolsas» se hace **en un solo pase**: son dos filas. Ya tiene el trabajo de Fase 2: el validador **no rechaza** pedir más de lo suelto (comentario «FASE 2» en L1089) y muestra un icono `auto_awesome` con el tooltip del rebalanceo.
      **Código muerto detectado (no borrado, requiere tu OK):** `widgets/transfer_product_quantity_dialog.dart` (archivo entero, **0 usos en el repo**) y la clase privada `_ProductQuantityDialog` de `inventory_transfer_screen.dart` L1331 (**390 líneas, nunca instanciada**; `dart analyze` avisa «A value for optional parameter 'sourceLayoutId' isn't ever given»). Son de cuando la pantalla trabajaba con diálogos. Ninguno aplana, así que no hay bug.
- [ ] Listas de operación: mostrar presentación por línea. **Confirmado que falta**: `fn_listar_operaciones_inventario_new` no menciona `id_presentacion` **ni una vez** en sus 32.828 caracteres. Arma su `detalles` jsonb por tipo de operación, así que hay que ampliar cada rama (venta, recepción, extracción, transferencia…). El detalle por presentación sí está disponible en el kardex y en el stock.
- [x] `inventory_summary_card.dart` y `warehouse_detail_screen.dart`: la palabra en duro eliminada. **No se cambió por otra palabra**: el problema de fondo era que el número no significa nada — `cantidadTotalEnAlmacen` suma cantidades **físicas** de presentaciones distintas (4 Cajas + 4 Unidades = 8). Ahora la tarjeta muestra el número y, si el producto tiene varias presentaciones, el equivalente `= N u. base` al lado (comparable); y el diálogo de la zona agrupa por `presentacion` —que la RPC ya devolvía— y arma el desglose real «4 Cajas + 4 Unidades». `totalStock` queda solo como bandera «¿hay algo?» para permitir o no borrar la zona.
- [x] **Formatter compartido de stock mixto**: `ventiq_admin_app/lib/utils/stock_mixto_formatter.dart` — `plural`, `cantidad`, `mixto`, `linea`, `mixtoConEquivalente`. Replica letra por letra `fn_plural_presentacion`, `fn_fmt_cantidad` y `fn_formatear_stock_mixto` (el SQL las declaró IMMUTABLE y sin tocar la base justamente para permitir esto). Cubierto por `test/stock_mixto_formatter_test.dart` — **32 tests verdes**. Las salidas **ya se compararon contra las funciones vivas**: `fn_plural_presentacion('Bolsa',1)='Bolsa'` / `(...,5)='Bolsas'`, `fn_fmt_cantidad(4.0)='4'` / `(4.5)='4.5'` / `(NULL)='0'`, y el texto mixto del producto 217 sale `'100 Bolsas'` con `texto_corto='100 BOL'`.
      `linea()` no inventa "unidades" cuando `id_presentacion` es nulo: el ledger no sabe en qué estaba expresada esa fila.

### Vendedor (`ventiq_app`)

- [x] **La cadena de presentaciones ya estaba en el caché offline** — no hizo falta migrar el esquema. `AutoSyncService._syncProducts` (~línea 532) las baja en batch por categoría y las mete en `product['presentaciones']`, que viaja serializado dentro del `payload` JSON de `offline_products`. (Un grep del DDL de la tabla no las encuentra porque no son una columna.)
- [x] **`ventiq_app/lib/utils/presentacion_cadena_local.dart`** (nuevo) — `PresentacionLocal` + `PresentacionCadenaLocal.resolver()` replican la cascada de `fn_presentaciones_producto` en Dart puro, **sin red**: base = `es_base DESC, cantidad ASC, id ASC`; `factorRel = round(cantidad/base, 6)`; `nivel = ROW_NUMBER() OVER (cantidad DESC, id ASC)`. Incluye `FormatoPresentacion` (gemelo de `StockMixtoFormatter` del admin; las dos apps no comparten paquete, si cambia una hay que tocar la otra).
- [x] **`test/presentacion_cadena_local_test.dart`** — **22 tests verdes**. Los casos esperados son la salida literal de la función viva sobre productos reales: **1072** (Caja 40 / Blister 6 / Unidad 1), **9635** (cuatro filas, **tres** marcadas `es_base` → gana la de menor id, las otras quedan `false`), **4380** (base con factor 30 → `factorRel` = 1), **217** (Bulto 10 / Bolsa 1).
- [x] **`ventiq_app/lib/widgets/captura_mixta_presentacion.dart`** (nuevo) — un campo por eslabón con su equivalencia, resumen mixto + equivalente, y aviso de rebalanceo en egresos. Emite `List<LineaPresentacion>`.
- [x] [admin_reception_screen.dart](../ventiq_app/lib/screens/admin/admin_reception_screen.dart): captura mixta; una línea por presentación; el dropdown del modo simple ahora muestra el factor (`Blister = 6 Unidades`); las líneas dicen `4 Bultos`.
- [x] Extracción y transferencia: captura mixta con el widget compartido; si el producto no tiene cadena en caché, cae al campo único y manda `null` (la RPC resuelve la base).
- [x] Ajuste: **no lleva captura mixta a propósito** — "cantidad nueva" es un conteo físico de UNA presentación, sumar 2 cajas y 3 unidades en un ajuste no significa nada. En su lugar lleva un dropdown para elegir **cuál** presentación se cuenta (antes mandaba `null` y el SQL adivinaba la base) y la etiqueta del campo dice la unidad: `Cantidad nueva (Caja)`.
- [x] **Bug corregido en el camino**: `admin_reception_screen` resolvía la base con `firstWhere(es_base, orElse: list.first)`. Con el producto 9635 (tres filas marcadas) podía elegir una distinta a la del servidor, y con los 9 productos sin `es_base` tomaba la primera del array — que puede ser la Caja: una recepción de 3 unidades quedaba registrada como 3 Cajas.

**Dependencias:** Fase 1.  
**Entrega:** se puede dar entrada real de 4 cajas y 4 unidades en ambas apps.

---

## Fase 3 · Lecturas: stock, IPV, valoración, costos, ventas

> Lo que se ve tiene que coincidir con el ledger físico.

### Stock

- [x] `fn_listar_inventario_productos_paged2` **ya devolvía saldos por presentación** (columnas 23-24, `id_presentacion` + `presentacion`): una fila por (ubicación, variante, presentación). No hacía falta tocarla; lo que faltaba era usar el dato en la UI.
- [x] `fn_inventario_resumen_por_usuario_almacen2` — **`18_lecturas_stock_presentacion.sql`, aplicado**. `cant_unidades_base` ahora es `sum(saldo * factor_rel_de_esa_fila)`. **Dos bugs vivos corregidos**, medidos en producción:
      **(a) el factor de la base no es 1.** El CTE `presentacion_base` tomaba `cantidad` de la fila `es_base` y lo aplicaba a todas las filas del producto. Hay 131 presentaciones `es_base` con factor ≠ 1 y **30 de esos productos tienen stock**. Producto 4380: 16 en almacén → reportaba **480**.
      **(b) el JOIN multiplicaba filas.** `id_producto` no es único en ese CTE: el producto 9635 tiene **tres** filas `es_base`, el `LEFT JOIN` devolvía 3 filas por fila de inventario y el `SUM` las contaba todas → reportaba **15 donde hay 5**. Este inflaba la **cantidad física**, no solo el equivalente.
      No-regresión: tienda 174, 270 filas antes = 270 después, cambian solo las 2 celdas del 9635; `stock_disponible` y `zonas_count` intactos. El `DO` block aborta si no parchea **las dos ramas** (con-almacén / sin-almacén) — parchear una dejaría el bug vivo al filtrar.
- [x] `fn_stock_mixto_almacen(producto, almacen)` (nueva, `18`): desglose + `equivalente_base` + `texto` («4 Cajas + 4 Unidades») + `texto_corto` («4 CAJ + 4 UNI»).
- [x] [inventory_stock_screen.dart](../ventiq_admin_app/lib/screens/inventory_stock_screen.dart): `InventoryProduct.cantidadConPresentacion` / `cantidadEnPresentacion(v)`; 6 usos de `"N unidades"` eliminados.
- [x] `inventory_summary_card.dart` y `warehouse_detail_screen.dart`: corregidos (ver Fase 2). `admin_stock_screen.dart` **no existe** en el repo.
- [ ] `fn_stock_producto_almacen`: sigue devolviendo el equivalente crudo (suma de `cantidad_final` sin factor). Es el helper que usa la cocina; cambiarlo toca el BOM.

### IPV y valoración

- [x] **`fn_inventory_valuation_rows` — `19_valoracion_costo_presentacion.sql`, aplicado.** El bug: `app_dat_producto_presentacion` tiene dos columnas de id y el JOIN usaba la equivocada. `pp.id` es la fila (lo que el ledger guarda en `id_presentacion`); `pp.id_presentacion` es la FK al nomenclador (1=Unidad, 3=Caja…). El JOIN comparaba nomenclador contra fila: **0 de 6.647 filas con stock casaban**, y como es `LEFT JOIN` todo caía al fallback «cualquier presentación del producto, la más reciente por `created_at`» — arbitrario, porque las presentaciones se crean en el mismo instante.
      **5.861 de 6.647 filas se valoraban con el costo de otra presentación.** Medido, tienda 189 producto 6841: 12 Bolsas (fila 6946, costo 186,64) se valoraban con el costo del Bulto (fila 6947, 9,80) → **117,60 USD en vez de 2.239,68**. El error no era simétrico (producto 4485: 0,0525 → 0,048, el valor baja), por eso pasaba por número plausible.
      Afecta a las tres RPC de la pantalla de valoración: `fn_warehouses_valuation_summary`, `fn_warehouse_valuation_zones`, `fn_zone_valuation_products` (las tres llaman a `fn_inventory_valuation_rows`).
      Lleva guarda `AND lc.id_producto = li.id_producto`: hay **6 filas con stock cuyo `id_presentacion` pertenece a otro producto** (el 4720 «Pqt Pechuga De Pollo» apunta a una presentación del 4623 «BLOWER FAN Peugeot»). Sin la guarda habrían heredado el costo de un producto ajeno.
      No-regresión: 7 tiendas, 1.056 filas antes = después, cambian exactamente las 6 filas esperadas.
- [ ] ⚠️ **Pendiente de dato, no de código**: 20 filas / **14 productos** con stock no casan con ninguna presentación con `precio_promedio > 0` y su producto tiene varios costos distintos → siguen dependiendo del fallback arbitrario. Hay que cargarle el costo a la presentación donde está el stock. Censo en la verificación V5 del `19`.
- [x] [obtener_ipv](../SQL_OPTIMIZATION/obtener_inventario_completo.sql) → **`obtener_ipv2`** (`21_ipv_con_presentacion.sql`, aplicado). `obtener_ipv` **ya agrupaba por presentación** (todos sus CTE llevan `COALESCE(id_presentacion,0)` en el `DISTINCT ON`/`GROUP BY`); lo que faltaba era sacar el dato al cliente — solo lo usaba para pegar el nombre entre paréntesis («CALDO SABOR CARNE (Paquete)»), que es un string inútil para filtrar o sumar. La v2 añade `id_presentacion`, `presentacion_nombre`, `presentacion_factor`, `cantidad_final_formateada` («12 Bolsas») y `equivalente_base`. Función nueva y no `CREATE OR REPLACE` por el **42P13** (no se puede cambiar el `RETURNS TABLE`) y porque un `DROP`+`CREATE` deja el IPV de todas las tiendas roto entre sentencias. No-regresión: **1.189 filas** en 4 tiendas, 0 diferencias en `cantidad_final`, `costo_promedio_usd`, `cantidad_ventas` y `valor_inventario_venta`.
- [x] [inventory_ipv_report_screen.dart](../ventiq_admin_app/lib/screens/inventory_ipv_report_screen.dart): la columna UM muestra la presentación de la fila (`Caja ×12` cuando el factor ≠ 1) en pantalla, PDF y Excel; los **totales se suman en equivalente base** (antes sumaban Cajas con Unidades).
- [x] Exportaciones (`obtener_reporte_inventario_completo*`): las 5 versiones **ya agrupan por presentación** igual que el IPV, y `export_service.dart` ya mapeaba `id_presentacion`/`presentacion` a `InventoryProduct`. Corregido el resumen, que decía «Stock total: N **unidades**» sumando presentaciones distintas — ahora dice «N en X línea(s) de presentación».
- [ ] ⚠️ **Rotación y días de inventario no son interpretables en productos partidos.** Al agrupar por presentación, un producto comprado en Cajas y vendido en Unidades sale en dos filas: una con el stock y 0 ventas, otra con las ventas y 0 stock. `dias_inventario` y `rotacion_anual` se calculan dentro de la fila, así que en una el numerador es 0 y en la otra el denominador. Medido: **4 combinaciones producto+ubicación partidas, 3 con stock y ventas separados** (tienda 165: `CALDO SABOR CARNE (Paquete)` stock 0 / ventas 18 junto a `(Unidad)` stock 794 / ventas 52). Con `equivalente_base` la app ya puede sumar las filas del producto; se deja en la UI porque cambiarlo en SQL obliga a decidir si el IPV se reporta por presentación o por producto, y hoy sirve para las dos cosas.
- [ ] ⚠️ **514 productos con stock y `costo_promedio_usd = 0`** (tiendas 45/165/174, de 1.183 filas). El CTE `costo_promedio` de `obtener_ipv` solo lee recepciones con precio > 0, así que el stock que entró por conteo inicial, ajuste o importación no tiene costo ahí — aunque sí lo tenga en `app_dat_producto_presentacion.precio_promedio`, que es lo que usa la valoración del `19`. Explica por qué IPV y valoración pueden discrepar.
- [x] ✅ **[warehouse_valuation.sql](../ventiq_admin_app/sql/warehouse_valuation.sql) SINCRONIZADO** (2026-08-28). Estaba con la versión anterior al `19`: `latest_costo` hacía `DISTINCT ON (pp.id_producto, pp.id_presentacion)` y el JOIN casaba contra la FK del nomenclador — reaplicarlo reintroducía el bug del 88 %.
      **Método:** comparación por **huella md5 del cuerpo normalizado** (sin espacios, minúsculas) de cada función contra `pg_get_functiondef`. Reveló que **solo 1 de las 5** difería (`fn_inventory_valuation_rows`, 3.693 vs 3.915 chars); `fn_get_usd_cup_rate`, `fn_warehouses_valuation_summary`, `fn_warehouse_valuation_zones` y `fn_zone_valuation_products` ya eran idénticas. Así se parchearon **2 regiones** en vez de volcar el archivo entero y perder la cabecera y el formato.
      Verificado después: **5/5 huellas idénticas** a producción y pglast valida las 10 sentencias. La cabecera ahora avisa de que la valoración vive en **dos** sitios (`19` y este archivo).

### Costos

- [x] [fn_actualizar_precio_promedio_recepcion_v2](../SQL_OPTIMIZATION/fn_actualizar_precio_promedio.sql) — **`20_costo_promedio_en_base.sql`, aplicado**. Ver el detalle abajo en «Bugs encontrados»: la RPC **fallaba en el 100 % de las llamadas** y el cálculo real vivía duplicado en Dart con la fórmula mala. Ahora pondera en unidades base, agrupa las líneas del mismo producto y escribe **solo en la presentación base**.

### Kardex de movimientos del producto

Archivos: [product_movements_screen.dart](../ventiq_admin_app/lib/screens/product_movements_screen.dart), [product_movements_service.dart](../ventiq_admin_app/lib/services/product_movements_service.dart), RPC [get_product_movements_v3](../ventiq_admin_app/docs/migrations/get_product_movements_v3_filtro_almacen.sql).

Hoy: columnas Fecha, Almacén, N° Op., Tipo Op., Estado, Entrada / Salida / Saldo (números). Chips Total / Recepción / Extracción / Control cuentan **número de filas** (se quedan así).

Ejemplo de filas (recepción 4 cajas + 4 u, luego venta 1 u que abre caja):

- Recepción cajas: Entrada `4 Cajas` | Saldo `4 Cajas`
- Recepción unidades: Entrada `4 Unidades` | Saldo `4 Cajas + 4 U`
- Conversión (abrir): **una fila** con Salida `1 Caja` y Entrada `12 U` | Saldo mixto actualizado
- Venta: Salida `1 Unidad` | Saldo `3 Cajas + 11 U` (el detalle exacto conversión+venta lo define el helper de Fase 0)

Cambios RPC:

- [x] `get_product_movements_v3` → **`get_product_movements_v4`** (`17_kardex_con_presentacion.sql`, aplicado). Añade `id_presentacion`, `presentacion_nombre`, `presentacion_factor`, `cantidad_formateada` («21 Bultos»), `id_conversion` y `es_conversion`. Las 28 columnas de la v3 no se movieron: verificado fila por fila contra producción (26/26 iguales en cantidad, tipo_operacion y almacén).
      **Por qué v4 y no reemplazar la v3:** `CREATE OR REPLACE` que cambia el `RETURNS TABLE` falla con 42P13, y un `DROP` + `CREATE` deja el kardex de todas las tiendas roto entre las dos sentencias.
      **Cómo se generó:** el `17` no contiene el cuerpo — es un `DO` block que baja el `pg_get_functiondef` de la v3 viva, aplica 10 inserciones y **aborta si el conteo por grupo no da exacto** (3 CTE de la base + 6 referencias con alias + 11 de conversión). La v3 tiene 591 líneas y 3 CTE que alimentan un `UNION ALL` **posicional**: reescribirla a mano desalinea el UNION y el error sale 200 líneas más abajo como un cast imposible.
- [x] Tipo **Conversión** con color propio (índigo) e icono `unfold_more` en el kardex. **Dos bugs que esto destapó:** (1) el `CASE` de `tipo_movimiento` no contemplaba `id_conversion`, así que abrir una caja salía como «Reajuste»; (2) el brazo de cancelaciones etiquetaba en duro `'Reajuste de cancelación'` y una conversión cae ahí (no tiene recepción/extracción/control ni ajuste) — un movimiento deliberado se reportaba como corrección de error. También en Dart: `ProductMovementsService.isCancelacionReajuste` devolvía `true` para conversiones; ahora sale por `es_conversion`.
- [x] `fn_presentacion_item_json` ampliada con **`presentacion_factor_rel`** y **`equivalente_base`** (aplicada). Hacía falta para los totales: `factor` es lo que el usuario escribió y `factor_rel` es lo que sirve para equivalencias — en el producto 4380 la base tiene `factor 30` y `factor_rel 1`.
- [x] Entrada/Salida como `{qty} {nombre}` en la tabla, el PDF y el Excel. Detalle al tap: `Presentación: Bulto (= 10 base)` y, si fue conversión, la etiqueta «Cambio de presentación (abrir/empaquetar)».
- [x] Totales de pie del PDF/Excel = **equivalente base** etiquetado `u. base` (`sum(qty * factor_rel)`), no la suma de cantidades crudas: sumar 4 cajas + 4 unidades como «8» es un número sin significado.
- [x] **Filtro Presentación** (`_selectedPresentacionId`). Las opciones se **derivan de los movimientos cargados**, no de `fn_presentaciones_producto`: ofrecer la cadena completa dejaría elegir presentaciones sin un solo movimiento y la lista saldría vacía sin explicación. Cada opción lleva su conteo (`Bulto (12)`). Solo se muestra el dropdown si hay **más de una** presentación con movimientos. Es **filtro local**, no recarga: la v4 no tiene parámetro de presentación y añadírselo cambiaría la firma que usa la app vieja. Aplicado también en `_prepareMovementsForExport`, o el Excel traería filas que la pantalla oculta.
- [x] **Chip Conversión** en el resumen. Cuenta por `es_conversion` (la bandera del `17`, que viene de `id_conversion IS NOT NULL`), no por el nombre del tipo. **Solo aparece si hay conversiones en el rango**: la mayoría de los productos no tiene ninguna y un chip permanente en 0 gasta ancho de pantalla. Índigo, igual que la fila.
- [x] **Saldo con su presentación** en pantalla, PDF y Excel (`4` + `Caja` debajo; `4.00 (Caja)` en Excel). **Decisión: no se reconstruye el saldo mixto del almacén.** Haría falta el histórico completo de todas las presentaciones de esa ubicación, y el kardex está **paginado a 20 filas y filtrado por fecha**: si la otra presentación se movió fuera de la ventana cargada, el mixto saldría mal. Un saldo inventado es peor que un saldo parcial bien etiquetado — y etiquetarlo ya resuelve el problema real, que era leer «4» y «100» en dos filas seguidas como si fuera un error de datos.
- [x] **Auditoría de huecos por `(ubicación, id_presentacion)`**. La cadena de saldos del ledger es por `(producto, variante, opción, ubicación, id_presentacion)`; agrupar solo por ubicación mezclaba las cadenas de Caja y Unidad en una secuencia, así que **cada alternancia entre dos presentaciones generaba un falso positivo**. La presentación entra también en la etiqueta del hallazgo (`Almacén · Zona · Bulto`) para que un hueco real diga en qué cadena está. Ojo: la clave pasó a `'id:N|pres:M|etiqueta'`, así que el parseo de la etiqueta busca el **segundo** `|`.

`dart analyze lib`: **0 errores**.

> La lista de «Cambios UI» que estaba aquí duplicaba los puntos de arriba, que ya están
> todos marcados. **El kardex queda cerrado.**

### Reporte de ventas general (admin)

Archivos: [sales_screen.dart](../ventiq_admin_app/lib/screens/sales_screen.dart) `_buildProductSalesReport`, modelo `ProductSalesReport` en [sales_service.dart](../ventiq_admin_app/lib/services/sales_service.dart), RPC [fn_reporte_ventas_con_proveedor4](../ventiq_admin_app/SQL_OPTIMIZATION/fn_reporte_ventas_con_proveedor4_optimizada.sql).

Hoy: Producto | Precio (u) | Cant Vendidos | Total Venta | Costo (u) | Total Costo | Ganancias. Dinero en UI = `precioVentaCup * totalVendido` (ignora `ingresos_totales` del SQL).

Fila objetivo (caja=12, vendido 2 cajas + 5 u, precio base $10, costo base $4):

| Producto | Precio (u) | Cant. vendidos | Equiv. u | Total venta | Costo (u) | Total costo | Ganancia |
|----------|------------|----------------|----------|-------------|-----------|-------------|----------|
| Refresco | $10 | 2 Cajas + 5 U | 29 | $290 | $4 | $116 | $174 |

`equiv = sum(qty_presentacion * factor)`; `total venta = precio_base * equiv`; `total costo = costo_base * equiv`. Pie “Cant Vendidos” = **suma de equivalentes**, etiqueta “u. base”.

- [ ] Compactar RPC a **una fila por producto**. Devolver `cantidades_por_presentacion jsonb` + `equiv_unidades_base`. Ingresos/costo = `SUM` de líneas, no `precio * sum(qty crudas)`.
- [ ] `ProductSalesReport`: `desglosePresentaciones`, `equivUnidadesBase`; UI usa `equiv` para dinero. Dejar de hacer `precio * totalVendido` con qty cruda.
- [ ] Detalle de operación (ya muestra `Presentación: …` ~línea 7549): cantidad `2 Cajas`, no solo el número.
- [ ] PDF/Excel del tab productos: mismas dos columnas de cantidad.

Riesgo: compactar `fn_reporte_ventas_con_proveedor4` cambia el contrato del cliente.

### Reporte por proveedor (admin)

Mismo `sales_screen.dart` tab Proveedores. Agrupa `_productSalesReports` por `idProveedor`. Totales actuales son **solo dinero** (Ventas / Costo / Ganancia): se quedan.

- [ ] Diálogo `_showSupplierDetailDialog` y PDF: productos con desglose mixto + Equiv. u (igual que el general).
- [ ] Si hay “cantidad vendida” agregada del proveedor: suma de equivalentes, no qty crudas.
- [ ] No hace falta columna mixto en la tabla resumen de proveedores.

### Resumen de ventas del cierre (`ventiq_app`)

Tres superficies (el conteo físico “debe haber / real” es Fase 5, no este resumen):

1. [venta_total_screen.dart](../ventiq_app/lib/screens/venta_total_screen.dart) — Producto | Inicial | Entra. | Vend. | Final | Total ($). Agrupa por nombre; `OrderItem` no tiene presentación.
2. [sales_monitor_fab.dart](../ventiq_app/lib/widgets/sales_monitor_fab.dart) — `Productos: N uds` desde `fn_resumen_diario_cierre.productos_vendidos`.
3. [cierre_screen.dart](../ventiq_app/lib/screens/cierre_screen.dart) — `_productosVendidos` como entero.

- [ ] **Vend.** = mixto. **Inicial / Entra. / Final** = mixto del almacén del TPV. **Equiv.** en Vend. (columna o letra chica): `29 u`. **Total $** = importe, no precio × qty cruda.
- [ ] Agrupar por `id_producto`; acumular por presentación y formatear.
- [ ] FAB / header de cierre: `productos_vendidos` = equivalente base; etiqueta `u. base` (el mixto no cabe).
- [ ] `fn_resumen_diario_cierre` y ticket impreso: `sum(qty * factor)`.
- [x] Offline: **hecho en Fase 5**. `updateProductInventoryInCache` recibe `presentationId` y la firma pasó de `int` a `num`, así que ya no se trunca `item.cantidad`. Los 5 llamadores migrados.

Hasta que Fase 4 mande cantidad en la presentación vendida, el RPC puede reconstruir mixto desde `app_dat_extraccion_productos.id_presentacion`; si el cliente sigue mandando base, todo saldrá como unidades.

**Dependencias:** Fases 0–2 (si no, se vería mixto vacío porque todo sigue en base). Resumen de cierre con datos reales de cajas depende de Fase 4.  
**Entrega:** IPV y valoración cuadran con 4 cajas + 4 unidades = 52 × costo base, no 8 × costo. Kardex y ventas muestran mixto + equiv.

---

## Fase 4 · Venta TPV (`ventiq_app`) + BOM

> La presentación elegida es la que se vende; el stock se rebalancea en SQL.

Hoy: UI en cajas, payload en unidades base, `id_presentacion` del inventario.

Nuevo payload:

- `id_presentacion` = presentación **elegida** (`app_dat_producto_presentacion.id`)
- `cantidad` = cantidad **en esa presentación**
- `precio_unitario` = precio base × factor (una sola convención; documentarla en el RPC)

Cambiar **todas** las rutas, no solo una:

- [x] `fn_registrar_venta` / variantes — **`22_venta_saldo_por_presentacion.sql`, aplicado**. Ver «Bugs encontrados»: leían el saldo anterior con el patrón prohibido («último movimiento del producto», sin filtro de presentación) y escribían ese saldo en una fila marcada con OTRA presentación. Ahora filtran por presentación y el subselect va envuelto en un `COALESCE` escalar para no dejar de descontar en la primera venta de una presentación sin historial.
- [x] `fn_registrar_venta_mesa` / cuenta mesa — mismo parche, mismo archivo.
- [x] [product_details_screen.dart](../ventiq_app/lib/screens/product_details_screen.dart): **dejó de convertir a base en el carrito**. `cantidad` va en la presentación elegida y `precio_unitario` es `precio_base × factor`. El importe es el mismo producto de los dos números, así que ni el total de la orden ni el arqueo cambian. `id_presentacion` sale de la presentación ELEGIDA (`_presentacionElegidaId`), no de la del inventario.
- [x] [fluid_product_details_widget.dart](../ventiq_app/lib/widgets/fluid_product_details_widget.dart): mismo cambio en las dos ramas (con y sin variantes). Era una segunda ruta de venta que también aplanaba a base.
- [x] `OrderItem`: `idPresentacion`, `presentacionNombre` y `presentacionFactor`, con `equivalenteBase` y `cantidadFormateada`. Los tres se persisten en `toJson`/`fromJson` (si no, la cola offline reconstruía el ítem sin presentación) y se arrastran en `copyWith` (si no, sumar unidades a un ítem del carrito le borraba la presentación). Nombre y factor se **congelan** al vender: el cierre se arma offline y ya no puede consultar la cadena.
- [x] Wrappers offline (`fn_registrar_venta_offline` y afines) — el wrapper **no necesitaba SQL**: solo hace idempotencia por `client_uuid` y delega en `fn_registrar_venta` pasando el `jsonb` tal cual. Lo que faltaba era en Dart: la orden pendiente de `checkout_screen`/`preorder_screen` no guardaba la presentación, y `auto_sync_service` + los 3 puntos de sync de `settings_screen` la subían desde `inventory_metadata` sin más. Ahora se guarda `id_presentacion`/`presentacion_nombre`/`presentacion_factor` por ítem, se prefiere la del ítem al sincronizar y `order_service` la reconstruye al releer la orden.
- [x] Edición de pendiente / cocina — `fn_descontar_venta_enrutada` recibe la cantidad **convertida a unidades base** (`24_bom_cantidad_en_base.sql`). Ver «Bugs encontrados»: sin esto, vender 1 Caja de 24 croquetas descontaba la receta de **1** croqueta.
- [x] [01_helpers_bom_almacen.sql](../funcionalidad_cocina/01_helpers_bom_almacen.sql): no hizo falta tocarlo. El helper ya recibe la cantidad correcta desde la venta gracias al `24`; la conversión se hace en un solo punto (la frontera de la venta) en vez de en cada consumidor.
- [x] Descuento: `fn_descontar_con_rebalanceo` filtrando **ubicación y presentación** — **`25_venta_con_rebalanceo.sql` aplicado y verificado**. La venta abre y arma empaques, en cadena si hace falta: vender 5 Cajas del producto 1073 con solo Unidades hace Unidad 2400→2280, Blister 0→10, Blister 10→0, Caja 0→5 y luego vende, con `id_conversion` propio por eslabón. Lleva **dos** guardas de compatibilidad: solo multipresentación (los 8.699 productos de una presentación se saltan) y, si no alcanza, respeta `permite_vender_aun_sin_disponibilidad` (2 tiendas / 31 productos que venden en negativo a propósito siguen pudiendo). **Corrección del análisis: la venta SÍ validaba stock**, vía el CHECK `chk_cantidad_final_conditional` que lee esa bandera por tienda — los 5 saldos negativos vivos son de las tiendas con la bandera encendida, no de una ausencia de validación.
- [ ] ⚠️ **`fn_stock_producto_almacen` suma `cantidad_final` de presentaciones distintas sin factor.** La usan 13 funciones (disponibilidad de platos, tandas, enrutamiento de venta). Hoy no afecta a nadie: hay **1 sola combinación producto+almacén con más de una presentación con stock** en todo el ledger, y es el producto de prueba 3046 con dos filas base de factor 1 (reporta 2.939 = 1.469 + 1.470, que en ese caso es correcto). Es el próximo bug en cuanto se configure un empaque real en un elaborado o un producto por tanda.
- [ ] Máximo vendible = saldo propio + convertible. Ya lo calcula `fn_preview_rebalanceo` (`maximo_convertible`); falta mostrarlo como tope en el selector de cantidad.
- [x] `admin_sale_agreement_screen.dart` (venta por acuerdo) migrado a `CapturaMixtaPresentacion`, la cuarta ruta de venta. Mandaba **siempre `null`** en `id_presentacion` (`PresentationSelection.forInventoryPayload()`), así que toda venta por acuerdo caía a la base sin importar lo que se estuviera vendiendo. El precio del catálogo es por unidad base, así que se multiplica por `factorRel` igual que en el TPV; sin eso una Caja se vendería al precio de una Unidad. Queda el fallback de campo único para productos sin cadena en caché.

### 4.1 Confirmar antes de abrir empaque (decidido: sí, se pregunta)

El rebalanceo automático se queda en el SQL. La UI del TPV pregunta antes.

Es la única parte del diseño donde VentIQ se separaba del mainstream sin red: la
industria nunca abre empaque en silencio — o convierte solo aritméticamente, o
exige una transacción explícita (SAP HU02 Repack, NetSuite Assembly Unbuild,
Odoo Unpack), o bloquea directamente (D365 `Restrict to sales unit`). Abrir una
caja es una decisión física del cajero: rompe un empaque que ya no se puede
rearmar y cambia lo que el cliente siguiente ve en el estante.

**Habilitado por SQL ya escrito y ensayado:** `presentaciones_inventario/10_preview_rebalanceo.sql`
(`fn_preview_rebalanceo`, solo lectura, no escribe ni reserva).

- [x] Al agregar al carrito, llamar `fn_preview_rebalanceo(producto, ubicación, presentación, cantidad)` — `preview_rebalanceo_service.dart` (nuevo) + llamada en `product_details_screen._addToCart`, **antes** de tocar el carrito: con cocina activa `addItemToCurrentOrder` ya descuenta inventario, así que preguntar después sería preguntar por algo ya hecho.
- [x] `necesita_conversion = false` → seguir sin molestar (`mensaje_usuario` viene `NULL`).
- [x] `estrategia = 'imposible'` → no dejar agregar; se muestra el `mensaje_usuario` con el máximo. **Este aviso NO lo silencia la preferencia**: «no volver a preguntar» calla la confirmación de abrir empaques, no la falta de stock.
- [x] `estrategia = 'abrir' | 'empaquetar'` → diálogo con `mensaje_usuario` y botón **Desempaquetar** / **Poner en paquete** (decisión 15) + casilla «No volver a preguntar en este TPV».
- [x] Preferencia por TPV (`preview_rebalanceo_no_preguntar_tpv_<id>` en SharedPreferences). Sin TPV no se guarda nada: una clave global silenciaría el aviso en todos los mostradores.
- [x] El texto viene del SQL. Verificado contra producción con el producto 217: `'Faltan 1 Bulto. ¿Armar 1 Bulto con 10 Bolsas?'` (estrategia `empaquetar`), `mensaje_usuario` **null** cuando alcanza, y `'No alcanza: se piden 99999 Bultos y como máximo se pueden servir 10.'` con `maximo_convertible = 10`.
- [x] Si la RPC falla (offline, caída), se devuelve un resultado neutro y la venta sigue: la consulta es de solo lectura y no bloquea nada. El servidor sigue siendo la autoridad.

No es una reserva: entre la preview y la venta otra caja puede mover el saldo, así
que la escritura real vuelve a calcular y puede fallar aunque la preview dijera
que sí. Hay que manejar ese error igual que hoy, no asumir que el diálogo lo evita.

**Dependencias:** Fase 0. Puede ir en paralelo a UI de recepción (Fase 2) si el helper ya existe.  
**Entrega:** vender 1 unidad abre caja; vender 1 caja empaqueta sueltas; elaborados descuentan MP con rebalanceo.

---

## Fase 5 · Conteo, offline, datos existentes

- [x] Conteo: un campo por presentación (modo mixto completo = seteo). **Corregido un bug que rompía el ajuste por completo**: `inventory_adjustment_screen.dart` mandaba `idPresentacion: row.idPresentacion ?? 0`, y `fn_insertar_ajuste_inventario2` valida el id contra `app_dat_producto_presentacion` → devolvía `id_presentacion 0 no existe` (22023) dentro del `jsonb`, así que la pantalla lo contaba como error genérico sin decir el motivo. Mismo `?? 0` en `productos_zona_destino_screen.dart`. Ahora se manda `null` y el servidor resuelve la base. Verificado con la función viva: `0` → error, `null` → success (100 → 95), `337` (Bulto, saldo 0) → setear 3 → success con `diferencia 3.0`. La pantalla **ya abría un diálogo por presentación** desde la Fase 2 (una fila por cada una, con el desglose mixto de la zona a la vista).
- [x] Ajuste de una sola presentación: rebalanceo si no alcanza el saldo propio. **Ya estaba resuelto en el `08`**: `fn_insertar_ajuste_inventario2` lee el saldo real (no le cree al cliente), anota el desfase si el declarado difiere, y cuando la diferencia es negativa llama a `fn_descontar_con_rebalanceo`.
- [ ] ⚠️ **El conteo de apertura de turno colapsa el producto a una sola fila.** `apertura_screen.dart` usa un `TextEditingController` por **`product.id`**, y `InventoryService.buildFromOfflineCache()` **suma `cantidad_disponible` de todas las presentaciones** en un solo `InventoryProduct`, quedándose con la **primera** presentación como `id_presentacion` (`bestRow ??= inv`). Así, contar «4 Cajas + 4 Unidades» es imposible: hay un solo campo y el conteo se atribuye a una presentación arbitraria. Exposición hoy: **2 productos** con más de una presentación con saldo en la misma ubicación (4 filas). Requiere cambiar la clave del mapa a `(id_producto, id_presentacion, id_ubicacion)` y que el caché devuelva una fila por presentación — no es un parche de una línea.
- [x] Offline `ventiq_app`: deltas locales por `id_presentacion`; sync **sin** reconvertir a base. `updateProductInventoryInCache` acepta `presentationId` y **filtra la fila del caché por presentación**; sin eso el delta caía en la primera fila que casara (la base) y vender 2 Bultos descontaba 2 **Bolsas** del caché local — el vendedor veía un stock inexistente hasta la siguiente sincronización. Con presentación explícita se **elimina el fallback** a `inventarioList.first`: tocar otra fila es escribir un saldo falso; si no hay fila de esa presentación solo se ajusta el total del producto y se avisa por log. Segundo bug del mismo sitio: la firma era `int quantityToSubtract` y los 5 llamadores hacían `.toInt()`, así que **toda venta fraccionada se perdía** (0,5 kg → 0 → no descontaba nada). Ahora es `num`. Migrados los 5 puntos: `checkout_screen`, `preorder_screen` y los 4 usos de `_applyStockDeltaLocally` en `admin_inventory_service` (recepción, extracción ×2, transferencia y ajuste).
- [x] Datos viejos: **no migrar**. Confirmado: `fn_presentaciones_producto` resuelve la base por cascada y aguanta los 9 productos sin fila `es_base`, así que el histórico se lee sin tocarlo.

**Nota sobre `fn_registrar_control_inventario`:** existe, acepta `id_presentacion` por línea y valida `APERTURA`/`CIERRE`/`CONTEO`, pero **ningún Dart la llama** y su cuerpo tiene `COMMIT`/`ROLLBACK` explícitos dentro de un bloque PL/pgSQL — al invocarla falla con **2D000 `invalid transaction termination`**. Además inserta en `app_dat_control_productos_detalle`, tabla que **no existe** (la real es `app_dat_control_productos`, con las columnas de detalle dentro). Está muerta: no es la vía para el conteo. El conteo real de apertura pasa por `registrar_apertura_turno_v3`, que sí escribe `id_presentacion` en `app_dat_control_productos`.

**Dependencias:** Fases 0–1.  
**Entrega:** conteo físico 4 cajas + 4 unidades; offline no aplana a unidad.

---

## RPCs y servicios (checklist técnico)

> Estado verificado contra producción. **25 archivos SQL aplicados** en
> `presentaciones_inventario/`.

### Nuevos — todos vivos (9/9 verificados en `pg_proc`)

- [x] `fn_stock_saldos_presentacion` · `fn_equivalente_base` · `fn_formatear_stock_mixto`
- [x] `fn_rebalancear_presentaciones` · `fn_descontar_con_rebalanceo` (+ `_almacen`) · `fn_ingresar_presentacion`
- [x] `fn_presentaciones_producto` · `fn_validar_id_presentacion` · `fn_stock_mixto_json` · `fn_plural_presentacion` · `fn_fmt_cantidad`
- [x] `fn_preview_rebalanceo` (dry-run del diálogo del TPV)
- [x] `fn_presentacion_tiene_movimientos` · `fn_presentaciones_producto_editable`
- [x] `fn_stock_mixto_almacen` · `fn_presentacion_item_json` (con `factor_rel`)
- [x] **`fn_cantidad_en_base`** (`24`) — la frontera BOM
- [x] **`get_product_movements_v4`** y **`obtener_ipv2`** (funciones nuevas, las viejas intactas)

### Cambiar (dejar de convertir / filtrar presentación)

- [x] `fn_registrar_recepcion_con_inventario` (`06`) — valida el ID, delega en `fn_ingresar_presentacion`
- [x] `fn_crear_extraccion_con_movimiento` (`07`) — el único punto de egreso; ya no deja negativos
- [x] `fn_transferir_inventario_entre_layouts` (`07`) — 2 Cajas llegan como 2 Cajas
- [x] `fn_insertar_ajuste_inventario2` (`08`) — lee el saldo real; rebalancea si el delta es negativo
- [x] `fn_registrar_venta` / `fn_registrar_venta_mesa` (`22` saldo por presentación, `24` BOM en base, `25` rebalanceo)
- [x] `fn_registrar_venta_offline` — **no necesitaba SQL**: delega pasando el `jsonb` tal cual, hereda `22`/`24`/`25`
- [x] Helpers BOM cocina — **no necesitaban cambios**: reciben la cantidad ya convertida por el `24`
- [x] `fn_listar_inventario_productos_paged2` — **ya devolvía** `id_presentacion` + `presentacion` (col. 23-24)
- [x] `fn_inventario_resumen_por_usuario_almacen2` (`18`) — 2 bugs de factor y JOIN
- [x] `obtener_ipv` → **`obtener_ipv2`** (`21`); `obtener_reporte_inventario_completo*` — las 5 **ya agrupaban** por presentación
- [x] `fn_actualizar_precio_promedio_recepcion_v2` (`20`) — pondera en base, escribe en la base
- [x] `get_product_movements_v3` → **`get_product_movements_v4`** (`17`)
- [x] Valoración almacén (`19`) — el bug del 88 %; las 3 RPC de la pantalla lo heredan
- [x] `aceptar_envio_consignacion` — revisada, **no aplana** (ver Fase 1). Cross-tienda, 558 duplicados y 0 con presentación no-base
- [x] `fn_admin_caja_*_offline` (recepción / extracción / ajuste) — **heredan** el arreglo porque solo delegan
- [ ] **`fn_inventario_detallado_optimizado`** — menciona `id_presentacion` **37 veces**: hay que auditar si agrupa o aplana. **No revisada todavía.**
- [ ] **`fn_stock_producto_almacen`** — `SUM(cantidad_final)` sin factor (0 menciones de `factor_rel`). La usan 13 funciones de cocina. Hoy inofensivo (1 sola combinación afectada), próximo bug al configurar un empaque en un elaborado
- [ ] **`fn_reporte_ventas_con_proveedor4`** — menciona `id_presentacion` 15 veces (agrupa por ella) pero **no la expone**: el cliente puede ver dos filas del mismo producto. Falta compactar a 1 fila + `jsonb` de desglose + equivalente
- [ ] **`fn_resumen_diario_cierre`** — **0 menciones** de `id_presentacion`: `productos_vendidos` suma cantidades crudas de presentaciones distintas

### Apps

- [x] `presentation_converter.dart` — reescrito, ya no aplana
- [x] `product_quantity_dialog.dart` (recepción) + extracción + ajuste admin
- [x] `inventory_stock_screen.dart` + IPV (pantalla, PDF y Excel)
- [x] `product_movements_screen.dart` + export Excel/PDF (totales en `u. base`)
- [x] `admin_reception_screen.dart` + extracción / transferencia / ajuste / venta por acuerdo en `ventiq_app`
- [x] `product_details_screen.dart` + `fluid_product_details_widget.dart` + `order_service.dart` + `OrderItem`
- [x] `admin_inventory_service.dart` — el normalizer ya no resuelve la presentación; `_applyStockDeltaLocally` lleva `presentationId`
- [x] `user_preferences_service.dart` — delta offline por presentación y `num` en vez de `int`
- [x] `preview_rebalanceo_service.dart` (nuevo) — el diálogo de Fase 4.1
- [x] Formatter de stock mixto: `StockMixtoFormatter` (admin, 32 tests) + `FormatoPresentacion` (vendedor, 22 tests)
- [ ] **`transfer_product_quantity_dialog.dart`** — la transferencia admin sigue con un campo único (no aplana, pero no permite mixto)
- [ ] **`sales_screen.dart`** (tab productos y proveedores) + `ProductSalesReport` — **0 menciones** de desglose/equivalente: es el bloque más grande que queda
- [ ] **`venta_total_screen.dart`** / `sales_monitor_fab.dart` / `cierre_screen.dart` — **0 menciones** de presentación
- [x] `inventory_summary_card.dart` y `warehouse_detail_screen.dart` — «unidades» en duro eliminada; la tarjeta muestra el equivalente base y el diálogo de zona el desglose por presentación
- [ ] `mesa_cuenta_service.dart` — la línea de cuenta lleva `idPresentacion` pero sin nombre ni factor (la RPC de la cuenta no los devuelve)

---

## Pantallas (checklist UI)

### Admin / gerente / almacenero

- [x] Recepción: cantidades por presentación
- [x] Extracción y ajuste: captura mixta / diálogo por presentación
- [x] Stock por almacén/zona: desglose físico
- [x] IPV y exportación: desglose + totales en equivalente base
- [x] Valoración de almacén (el bug del 88 % corregido)
- [x] Kardex: Entrada/Salida con presentación, detalle con factor, totales en `u. base`
- [x] Transferencia: ya usa lista con una fila por presentación + aviso de rebalanceo
- [x] Kardex: filtro por presentación, chip Conversión, saldo etiquetado, auditoría por (ubicación, presentación)
- [ ] Ventas general: 1 fila/producto, mixto + Equiv. u, dinero × equiv
- [ ] Ventas por proveedor: detalle/PDF con mixto + Equiv. u
- [ ] Lista de Operaciones: presentación por línea

### Vendedor (`ventiq_app`)

- [x] Recepción / extracción / transferencia / ajuste / venta por acuerdo (admin caja)
- [x] Venta en la presentación elegida, en las **dos** rutas (detalle y modo fluido)
- [x] Diálogo de confirmación antes de abrir empaque (4.1)
- [x] Offline: deltas por presentación, sin truncar fracciones
- [ ] Catálogo y ficha: mostrar el stock mixto (hoy muestra un número)
- [ ] Cuenta mesa: la línea lleva `idPresentacion` pero sin nombre ni factor (la RPC de la cuenta no los devuelve)
- [ ] Resumen del cierre (`VentaTotalScreen`): Inicial/Entra/Vend/Final mixtos + equiv
- [ ] FAB / `fn_resumen_diario_cierre`: `u. base`, no suma cruda
- [ ] Conteo mixto en apertura de turno (postergado por decisión)

---

## Criterios de aceptación (smoke)

Verificados **en SQL** contra producción (ver `docs/TUTORIAL_PRUEBAS_PRESENTACIONES.md`).
Los que dicen «pendiente de UI» necesitan ejecutar la app en un dispositivo.

- [x] Entrar 4 cajas + 4 unidades (caja=12): ledger 4 y 4 (tests de Fase 0, archivo `05`); valoración = equivalente × costo **base** (`19`).
- [x] Vender 1 unidad con 4 cajas y 0 sueltas → 3 cajas + 11 unidades. La conversión lleva `id_conversion`, así que el IPV **no** la cuenta como venta.
- [x] Vender 1 caja con 0 cajas y 20 unidades → 0 cajas + 8 unidades (estrategia `empaquetar`).
- [x] Transferir 2 cajas no las convierte a 24 unidades en destino (`07`).
- [x] Venta elaborada descuenta MP con la cantidad **convertida a base** (`24`) en el almacén correcto.
- [x] Costo promedio solo se actualiza en `es_base` (`20`, verificado: la fila del Bulto queda intacta).
- [x] Producto de una sola presentación sin regresiones: **8.699 productos** se saltan el rebalanceo por la guarda del `25`; `fn_cantidad_en_base` devuelve la cantidad intacta en las **8.785** presentaciones base.
- [x] Kardex: conversión con tipo propio, y los totales del PDF/Excel en `u. base` en vez de sumar 4+4=8.
- [x] Rebalanceo en cadena real en una venta: Unidad 2400→2280 → Blister 0→10 → 10→0 → Caja 0→5 → vendida (`25`).
- [ ] **Pendiente de UI**: que la pantalla muestre «4 Cajas + 4 Unidades» y que el precio de 1 caja en el TPV sea 12 × el de la unidad. El código está; falta ejecutarlo (§2, §7 del tutorial).
- [ ] **Pendiente**: IPV y exportación ya no dicen «unidades» sumando 4+4, pero la **lista de Operaciones** sigue sin presentación.
- [ ] **Pendiente (bloque 1)**: Ventas general y proveedor con «2 Cajas + 5 U», Equiv. 29, una sola fila por producto.
- [ ] **Pendiente (bloque 2)**: Cierre con Vend. mixto y FAB en `u. base`.

---

## Riesgos

- Wrappers duplicados de venta (mesa, offline, cocina, pending edit): si queda **una** ruta sin el helper, el stock mixto se rompe solo en ese camino.
- `id` vs `id_presentacion` en JSON: hay que validar en RPC o se escriben FKs inválidos / filas huérfanas.
- Conteo a medias + auto-abrir puede sorprender. La UI debe dejar claro si es conteo mixto completo (seteo) o ajuste de una presentación (rebalanceo).
- `PresentationConverter` se llama más de una vez hoy; al quitarlo, revisar que no quede un segundo paso que siga aplanando.
- Cocina/BOM usa UM; el puente a presentación de inventario hay que hacerlo **dentro** del helper, no volviendo a convertir a base en Dart.
- Compactar `fn_reporte_ventas_con_proveedor4` a una fila por producto: el cliente debe dejar de hacer `precio * totalVendido` con qty cruda.
- Kardex: emparejar los dos movimientos de conversión en **una** fila (entrada + salida). Si se muestran sueltos, el saldo intermedio confunde.

---

## Progreso por fase

| Fase | Estado | Notas |
|------|--------|-------|
| 0 Helper SQL mixto / rebalanceo | [x] **cerrada** | `01`–`05`. 9 tests verdes. Incluye guardas de triggers (`04`) que no estaban previstas. |
| 1 Dejar de convertir en escrituras | [x] **cerrada** | `06`–`08` + tests `09`. 3 bugs de datos: saldos negativos en egreso, empate por `created_at`, 202 ajustes que rompían la cadena de saldos. Consignación revisada: no aplana. |
| 2 UI entrada/salida mixta | [x] **cerrada** (queda 1 hueco menor) | Prerequisito 2.0 aplicado (`11` índices + `12` trigger + `23` liberar `es_base`). Recepción, extracción y ajuste con captura mixta en las dos apps. **Falta:** transferencia admin con campo único y la lista de Operaciones sin presentación. |
| 3 Lecturas: stock, IPV, valoración, costos, kardex | [x] **cerrada** en lo medible | `17`–`21`. **4 bugs de cálculo graves**: valoración 88 % mal costeada, resumen con factor de base y JOIN multiplicador, RPC de costo rota al 100 %, conversión etiquetada como error. **Falta:** reportes de ventas y resumen de cierre (bloque grande, ver abajo). |
| 4 Venta TPV + BOM | [x] **cerrada** | `22` saldo por presentación, `24` BOM en base, `25` rebalanceo con 2 guardas de compatibilidad. Diálogo 4.1 con `fn_preview_rebalanceo`. 4 rutas de venta migradas. |
| 5 Conteo, offline | [x] **cerrada** (1 pendiente documentado) | Ajuste con `null` en vez de `?? 0`; deltas offline por presentación; fracciones ya no se truncan. **Falta por decisión:** conteo mixto en apertura de turno. |
| **Tutorial de pruebas** | [x] | `docs/TUTORIAL_PRUEBAS_PRESENTACIONES.md` — 15 secciones, SQL ejecutado contra producción, checklist de 12 pruebas críticas. |

### Lo que queda, por tamaño

| # | Qué | Tamaño | Por qué importa |
|---|-----|--------|-----------------|
| 1 | **Reportes de ventas admin** (`sales_screen` + `fn_reporte_ventas_con_proveedor4`) | grande | La RPC agrupa por presentación y **no la expone**: el cliente puede ver 2 filas del mismo producto o fusionar mal 2 cajas + 5 u = 7. Requiere compactar el contrato a 1 fila/producto + `jsonb` de desglose. |
| 2 | **Resumen de cierre vendedor** (`venta_total_screen`, `sales_monitor_fab`, `fn_resumen_diario_cierre`) | grande | `productos_vendidos` suma cantidades crudas de presentaciones distintas. La RPC no menciona `id_presentacion`. |
| 3 | **`fn_stock_producto_almacen` sin factor** | medio | 13 funciones de cocina la usan. Hoy inofensivo (1 combinación afectada); explota al configurar un empaque en un elaborado. |
| 4 | **`fn_inventario_detallado_optimizado`** | medio | 37 menciones de `id_presentacion`, sin auditar. Puede estar bien o estar aplanando. |
| ~~5~~ | ✅ **Kardex cerrado** | hecho | Filtro por presentación (local, con conteos), chip Conversión (solo si hay), saldo etiquetado con su presentación en pantalla/PDF/Excel, y auditoría por `(ubicación, presentación)` — que era un **generador de falsos positivos** con stock mixto. |
| ~~6~~ | ✅ **Transferencia admin: ya estaba migrada** | hecho | El pendiente apuntaba a 2 clases **muertas**. La pantalla real usa lista con una fila por presentación y ya tiene el aviso de rebalanceo. |
| 7 | **Lista de Operaciones con presentación** | medio | `fn_listar_operaciones_inventario_new` (32.828 chars) no la menciona; hay que ampliar cada rama del `detalles` jsonb. |
| 8 | **Conteo mixto en apertura de turno** | medio | Documentado y postergado por decisión (2 productos afectados). |
| 9 | **«unidades» en duro** en 2 widgets | trivial | `inventory_summary_card:207`, `warehouse_detail_screen:1967`. |
| 10 | **Datos sucios**: 21 costos inconsistentes, 14 productos sin costo en su presentación, 514 con costo 0 en IPV | dato, no código | No se arreglan con código: hay que cargar el costo donde está el stock. |
| ~~11~~ | ✅ **`warehouse_valuation.sql` sincronizado** | hecho | Solo 1 de las 5 funciones difería (detectado por huella md5). 5/5 idénticas a producción, pglast 10/10. |
| ~~9~~ | ✅ **«unidades» en duro** | hecho | `inventory_summary_card` muestra el número + `= N u. base` cuando hay varias presentaciones; `warehouse_detail_screen` agrupa por presentación y arma «4 Cajas + 4 Unidades». |

**Orden acordado (de menor a mayor).** Hechos: **11** ✅, **9** ✅, **6** ✅ (ya estaba),
**5** ✅. Quedan: **4** (auditar `fn_inventario_detallado_optimizado`), **3**
(`fn_stock_producto_almacen` con factor), **7** (lista de Operaciones), y al final el
**1** y el **2** — los dos cambian contratos de RPC que la app vieja consume, así que van
de uno en uno con su propia no-regresión.

**Herramienta reutilizable:** para detectar archivos `.sql` desincronizados sin
transportar el cuerpo entero, comparar `md5(lower(regexp_replace(prosrc,'\s','','g')))`
de la función viva contra la misma normalización del archivo local. Aísla *qué* función
difiere y permite parchear solo esa región.

---

## Referencias

- Schema: [VentiQ.sql](../VentiQ.sql)
- **Investigación de industria (Odoo / SAP / NetSuite / D365 / Zoho): [REFERENCIA_INDUSTRIA_PRESENTACIONES.md](REFERENCIA_INDUSTRIA_PRESENTACIONES.md)** — terminología, patrones de UI citados y quejas de usuarios a evitar. Leer antes de la Fase 2.
- SQL de la Fase 0: [presentaciones_inventario/](../presentaciones_inventario/)
- Recepción actual: [fn_registrar_recepcion_con_inventario.sql](../SQL_OPTIMIZATION/fn_registrar_recepcion_con_inventario.sql)
- Conversión cliente (a eliminar en escrituras): [presentation_converter.dart](../ventiq_admin_app/lib/utils/presentation_converter.dart)
- Venta actual: [registrarventa_ok.sql](../registrarventa_ok.sql)
- IPV: [obtener_inventario_completo.sql](../SQL_OPTIMIZATION/obtener_inventario_completo.sql)
- Kardex: [get_product_movements_v3_filtro_almacen.sql](../ventiq_admin_app/docs/migrations/get_product_movements_v3_filtro_almacen.sql), [product_movements_screen.dart](../ventiq_admin_app/lib/screens/product_movements_screen.dart)
- Ventas: [fn_reporte_ventas_con_proveedor4_optimizada.sql](../ventiq_admin_app/SQL_OPTIMIZATION/fn_reporte_ventas_con_proveedor4_optimizada.sql), [sales_screen.dart](../ventiq_admin_app/lib/screens/sales_screen.dart)
- Cierre: [venta_total_screen.dart](../ventiq_app/lib/screens/venta_total_screen.dart), [sales_monitor_fab.dart](../ventiq_app/lib/widgets/sales_monitor_fab.dart)
- Plan relacionado (no mezclar): [PLAN_RESTAURANTE_COCINA.md](PLAN_RESTAURANTE_COCINA.md)
