# Plan: inventario físico por presentaciones

Checklist de implementación. Marca `[x]` lo hecho y deja `[ ]` lo pendiente.

**Problema:** el modelo de datos ya permite stock por presentación (caja, unidad, etc.), pero la lógica convierte casi todo a la presentación `es_base` (“unidad”). No se puede entrar ni reportar “4 cajas y 4 unidades” como existencias distintas.

**Modelo objetivo:** el inventario es físico por presentación. 4 cajas y 4 unidades son dos saldos. Los reportes muestran exactamente eso. Si un egreso pide unidades y solo hay cajas, el sistema abre cajas; si pide cajas y solo hay sueltas, empaqueta. Precio de venta y costo siempre se derivan de la presentación base × factor.

---

## Decisiones cerradas

Tomadas en la sesión de planificación. No reabrir salvo cambio explícito al revisar este documento.

- [x] Stock físico separado por presentación. El reporte muestra “4 Cajas + 4 Unidades”, no el equivalente “52 unidades” como cantidad de almacén.
- [x] Abrir automático: vender/mover 1 unidad con 4 cajas y 0 sueltas → `-1 caja`, `+(factor − 1) unidades`, luego descuenta 1 unidad.
- [x] Empaquetar automático: vender/mover 1 caja con 0 cajas y 20 sueltas (factor 12) → arma 1 caja desde 12 unidades y la mueve; quedan 8 unidades.
- [x] Abrir/empaquetar aplica a **todos los egresos** (venta, extracción, transferencia, recetas/BOM) y a **ajuste/conteo** cuando el delta de **una** presentación no cubre con su propio saldo.
- [x] Precio de venta y costo: siempre presentación base × factor. No hay precio ni costo independiente por caja. `precio_promedio` vive en la fila `es_base`; el resto se deriva.
- [x] Alcance: inventario completo + TPV + IPV + valoración de almacén + costos + reportes de ventas, en `ventiq_app` y `ventiq_admin_app`.
- [x] Marketplace: fuera de alcance.
- [x] Cadena con 3+ presentaciones (Pallet / Caja / Unidad): ordenar por `app_dat_producto_presentacion.cantidad` (factor a base). Abrir convierte a la **siguiente más chica**; empaquetar a la **siguiente más grande**. No saltar a base si hay nivel intermedio.
- [x] Kardex de movimientos: **misma tabla**. Entrada/Salida muestran `{qty} {presentación}` (`4 Cajas`, `1 Unidad`). Saldo = texto mixto del almacén tras ese movimiento (`3 Cajas + 11 U`). Filtro opcional por presentación.
- [x] Reportes de ventas (general, por proveedor y resumen de cierre): **una fila por producto**. Cantidad visible = desglose mixto. Columna extra **Equiv. unidades**. Dinero = precio/costo **base** × equivalente.

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

### 0.1 Funciones nuevas (nombres tentativos)

- [ ] `fn_stock_saldos_presentacion` — saldo actual por presentación (producto, ubicación, variante, opción).
- [ ] `fn_equivalente_base` — `sum(saldo * factor / factor_base)` solo para dinero, rotación y “¿alcanza el equivalente?”.
- [ ] `fn_formatear_stock_mixto` — texto `"4 Cajas + 4 Unidades"` (omitir presentaciones con saldo 0).
- [ ] `fn_rebalancear_presentaciones` — abrir o empaquetar en cadena hasta cubrir `cantidad` de la presentación pedida; escribe movimientos de conversión.
- [ ] `fn_descontar_con_rebalanceo` — rebalancea y descuenta. Usar en venta, extracción, transfer, BOM, ajuste parcial.
- [ ] `fn_ingresar_presentacion` — o reutilizar recepción actual **sin** conversión previa. Una línea por presentación.

Definir `origen_cambio` (o tipo) para conversión. No reusar el de venta ni el de merma.

### 0.2 Tests SQL mínimos

- [ ] Entrar 4 cajas + 4 u (caja=12) → saldos 4 y 4; equivalente base 52.
- [ ] Vender 1 u con 4 cajas y 0 sueltas → 3 cajas + 11 u.
- [ ] Vender 1 caja con 0 cajas y 20 u → 0 cajas + 8 u.
- [ ] Pallet/caja/unidad: vender 1 u con solo 1 pallet (factores 120 / 12 / 1) → 0 pallet, 9 cajas, 11 u.
- [ ] Stock insuficiente en equivalente base → error, no saldos negativos.

**Dependencias:** ninguna.  
**Entrega:** RPCs de movimiento pueden dejar de convertir en cliente.

---

## Fase 1 · Dejar de convertir en escrituras

> El JSON llega con presentación y cantidad reales. El SQL escribe eso.

- [ ] Quitar conversión en [presentation_converter.dart](../ventiq_admin_app/lib/utils/presentation_converter.dart).
- [ ] Quitar `convertToBasePresentacion` en rutas de escritura de [inventory_service.dart](../ventiq_admin_app/lib/services/inventory_service.dart) y [product_service.dart](../ventiq_admin_app/lib/services/product_service.dart).
- [ ] Transfers: no llamar `fn_productos_json_a_presentacion_base`; descontar/ingresar con rebalanceo por presentación pedida.
- [ ] `ventiq_app` admin: extracción / transfer / ajuste dejan de forzar `es_base`.
- [ ] Consignación ([aceptar_envio_consignacion](../SQL_OPTIMIZATION/aceptar_envio_consignacion.sql)): no reescribir a base.
- [ ] Validar en RPC que `id_presentacion` sea PK de `app_dat_producto_presentacion` del producto.

**Dependencias:** Fase 0 (para egresos que hoy dependían de “todo está en base”).  
**Entrega:** una recepción de 4 cajas queda 4 en caja, no 48 en unidad.

---

## Fase 2 · UI de entrada / salida mixta

> Un formulario, N cantidades (una por presentación del producto).

### Admin

- [ ] [product_quantity_dialog.dart](../ventiq_admin_app/lib/widgets/product_quantity_dialog.dart): campos 4 cajas + 4 unidades (etc.), no un solo dropdown.
- [ ] Precio de línea: en la presentación de esa línea; convertir a base solo para promedio (ver contrato).
- [ ] Extracción, transferencia, ajuste: mismas cantidades mixtas.
- [ ] Listas de operación: mostrar presentación por línea, no “unidades” genérico.
- [ ] Formatter compartido de stock mixto (widget o helper Dart alineado a `fn_formatear_stock_mixto`).

### Vendedor (`ventiq_app`)

- [ ] [admin_reception_screen.dart](../ventiq_app/lib/screens/admin/admin_reception_screen.dart): mixto.
- [ ] Extracción / transfer / ajuste: mixto, no forzar base.
- [ ] Línea de recepción: mostrar “4 Cajas + 4 Unidades”, no solo `Cantidad: N`.

**Dependencias:** Fase 1.  
**Entrega:** se puede dar entrada real de 4 cajas y 4 unidades en ambas apps.

---

## Fase 3 · Lecturas: stock, IPV, valoración, costos, ventas

> Lo que se ve tiene que coincidir con el ledger físico.

### Stock

- [ ] `fn_listar_inventario_productos_paged2` y [fn_inventario_detallado_optimizado](../ventiq_app/fn_inventario_optimized.sql): devolver saldos por presentación; UI agrupa por producto+ubicación con desglose (no tratar cada presentación como SKU distinto, salvo filas hijas).
- [ ] [inventory_stock_screen.dart](../ventiq_admin_app/lib/screens/inventory_stock_screen.dart), `inventory_summary_card`, `warehouse_detail_screen`, `admin_stock_screen`: dejar de pintar `"N unidades"`.
- [ ] `fn_stock_producto_almacen`: disponibilidad total en **equivalente base**; detalle mixto.
- [ ] `fn_inventario_resumen_*`: `cant_unidades_base = sum(saldo * factor_de_esa_fila / factor_base)`.

### IPV y valoración

- [ ] [obtener_ipv](../SQL_OPTIMIZATION/obtener_inventario_completo.sql) + [inventory_ipv_report_screen.dart](../ventiq_admin_app/lib/screens/inventory_ipv_report_screen.dart) + [admin_ipv_screen.dart](../ventiq_app/lib/screens/admin/admin_ipv_screen.dart): cantidades físicas por presentación; valor = equivalente base × `precio_promedio` de `es_base`; rotación/días en equivalente base.
- [ ] [warehouse_valuation.sql](../ventiq_admin_app/sql/warehouse_valuation.sql): nunca `qty_caja * costo_unitario` sin factor.
- [ ] Exportaciones (`obtener_reporte_inventario_completo*`).

### Costos

- [ ] [fn_actualizar_precio_promedio_recepcion_v2](../SQL_OPTIMIZATION/fn_actualizar_precio_promedio.sql): ponderar en unidades base; actualizar solo `es_base`.

### Kardex de movimientos del producto

Archivos: [product_movements_screen.dart](../ventiq_admin_app/lib/screens/product_movements_screen.dart), [product_movements_service.dart](../ventiq_admin_app/lib/services/product_movements_service.dart), RPC [get_product_movements_v3](../ventiq_admin_app/docs/migrations/get_product_movements_v3_filtro_almacen.sql).

Hoy: columnas Fecha, Almacén, N° Op., Tipo Op., Estado, Entrada / Salida / Saldo (números). Chips Total / Recepción / Extracción / Control cuentan **número de filas** (se quedan así).

Ejemplo de filas (recepción 4 cajas + 4 u, luego venta 1 u que abre caja):

- Recepción cajas: Entrada `4 Cajas` | Saldo `4 Cajas`
- Recepción unidades: Entrada `4 Unidades` | Saldo `4 Cajas + 4 U`
- Conversión (abrir): **una fila** con Salida `1 Caja` y Entrada `12 U` | Saldo mixto actualizado
- Venta: Salida `1 Unidad` | Saldo `3 Cajas + 11 U` (el detalle exacto conversión+venta lo define el helper de Fase 0)

Cambios RPC:

- [ ] `get_product_movements_v3`: añadir `id_presentacion`, `presentacion_nombre`, `factor`.
- [ ] Tipo **Conversión** (abrir/empaquetar) con `origen_cambio` propio. No entra en chips Recepción/Extracción ni en IPV como venta.
- [ ] Saldo mixto post-movimiento: calcularlo en Dart recorriendo cronológico (la pantalla ya carga todos y ordena ASC), o devolver `saldo_mixto` desde SQL. El saldo es del **almacén de esa fila**, no global.

Cambios UI:

- [ ] Entrada/Salida como `{qty} {nombre}`; no hace falta columna Presentación extra.
- [ ] Filtro Presentación (junto a almacén / tipo op.).
- [ ] Chip **Conversión** en el resumen.
- [ ] Detalle al tap: presentación, factor, y si fue conversión el par origen/destino.
- [ ] Excel/PDF: mismas columnas de texto. Totales de pie = equivalente base (`sum(qty * factor)`) etiquetado “u. base”, no sumar 4+4.
- [ ] Auditoría de huecos: agrupar por `(almacen_id, ubicacion, id_presentacion)`, no por producto global.

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
- [ ] Offline: no hacer `item.cantidad.toInt()` a ciegas; usar presentación del ítem (`OrderItem.idPresentacion` en Fase 4) y factores cacheados.

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

- [ ] `fn_registrar_venta` / variantes
- [ ] `fn_registrar_venta_mesa` / cuenta mesa
- [ ] Wrappers offline (`fn_registrar_venta_offline` y afines)
- [ ] Edición de pendiente / cocina ([funcionalidad_cocina](../funcionalidad_cocina/))
- [ ] Descuento: `fn_descontar_con_rebalanceo` filtrando **ubicación y presentación**. Prohibido “último movimiento del producto”.
- [ ] [product_details_screen.dart](../ventiq_app/lib/screens/product_details_screen.dart) / `fluid_product_details_widget`: no convertir qty a base en el carrito; `inventoryData.id_presentacion` = la elegida.
- [ ] `OrderItem`: guardar `idPresentacion` + nombre/factor para cierre y resumen offline.
- [ ] Máximo vendible = saldo propio + convertible (abrir/empaquetar). Mostrar desglose mixto.
- [ ] [01_helpers_bom_almacen.sql](../funcionalidad_cocina/01_helpers_bom_almacen.sql): ingrediente en su presentación de receta/UM; helper rebalancea en el almacén de esa cocina.

**Dependencias:** Fase 0. Puede ir en paralelo a UI de recepción (Fase 2) si el helper ya existe.  
**Entrega:** vender 1 unidad abre caja; vender 1 caja empaqueta sueltas; elaborados descuentan MP con rebalanceo.

---

## Fase 5 · Conteo, offline, datos existentes

- [ ] Conteo: un campo por presentación (modo mixto completo = seteo).
- [ ] Ajuste de una sola presentación: rebalanceo si no alcanza el saldo propio.
- [ ] Offline `ventiq_app`: deltas locales por `id_presentacion`; sync **sin** reconvertir a base.
- [ ] Datos viejos: **no migrar**.

**Dependencias:** Fases 0–1.  
**Entrega:** conteo físico 4 cajas + 4 unidades; offline no aplana a unidad.

---

## RPCs y servicios (checklist técnico)

### Nuevos

- [ ] `fn_stock_saldos_presentacion`
- [ ] `fn_equivalente_base`
- [ ] `fn_formatear_stock_mixto`
- [ ] `fn_rebalancear_presentaciones`
- [ ] `fn_descontar_con_rebalanceo`

### Cambiar (dejar de convertir / filtrar presentación)

- [ ] `fn_registrar_recepcion_con_inventario` (validar ID; N líneas mixtas)
- [ ] `fn_crear_extraccion_con_movimiento`
- [ ] `fn_transferir_inventario_entre_layouts` (+ personas, tipos 7/8)
- [ ] `fn_insertar_ajuste_inventario2`
- [ ] `fn_registrar_venta*` / mesa / offline / cocina
- [ ] Helpers BOM cocina
- [ ] `fn_listar_inventario_productos_paged2`
- [ ] `fn_inventario_detallado_optimizado`
- [ ] `fn_stock_producto_almacen` / resumen
- [ ] `obtener_ipv` / `obtener_reporte_inventario_completo*`
- [ ] `fn_actualizar_precio_promedio_recepcion_v2`
- [ ] `fn_reporte_ventas_con_proveedor*` (compactar a 1 fila/producto + jsonb desglose + equiv)
- [ ] `get_product_movements_v3` (presentación, factor, tipo Conversión)
- [ ] `fn_resumen_diario_cierre` (`productos_vendidos` en equivalente base)
- [ ] Valoración almacén
- [ ] `aceptar_envio_consignacion`
- [ ] `fn_admin_caja_recepcion_offline` y sync de caja

### Apps

- [ ] `presentation_converter.dart` — dejar de aplanar, o deprecarlo
- [ ] `product_quantity_dialog.dart` + extracción/transfer/ajuste admin
- [ ] `inventory_stock_screen.dart` + IPV + summary cards
- [ ] `product_movements_screen.dart` + export Excel/PDF + auditoría
- [ ] `sales_screen.dart` (tab productos y tab proveedores) + `ProductSalesReport`
- [ ] `venta_total_screen.dart` / `sales_monitor_fab.dart` / `cierre_screen.dart` (resumen ventas)
- [ ] `admin_reception_screen.dart` + ops admin en `ventiq_app`
- [ ] `product_details_screen.dart` / `order_service.dart` / `mesa_cuenta_service.dart` / `OrderItem`
- [ ] `admin_inventory_service.dart` (normalizer que fuerza base)
- [ ] Formatter de stock mixto compartido (o duplicado alineado admin/vendedor)

---

## Pantallas (checklist UI)

### Admin / gerente / almacenero

- [ ] Recepción: cantidades por presentación
- [ ] Extracción / transferencia / ajuste / conteo: igual
- [ ] Stock por almacén/zona: desglose físico
- [ ] IPV y exportación: desglose + valor en equivalente base
- [ ] Valoración de almacén
- [ ] Kardex del producto: Entrada/Salida con presentación; saldo mixto; filtro presentación; chip Conversión
- [ ] Ventas general: 1 fila/producto, mixto + Equiv. u, dinero × equiv
- [ ] Ventas por proveedor: detalle/PDF con mixto + Equiv. u

### Vendedor (`ventiq_app`)

- [ ] Recepción / extracción / transfer / ajuste (admin caja)
- [ ] Catálogo y ficha: stock mixto; venta en la presentación elegida
- [ ] Cuenta mesa: línea con presentación real
- [ ] Resumen de ventas del cierre (`VentaTotalScreen`): Inicial/Entra/Vend/Final mixtos + equiv
- [ ] FAB / `fn_resumen_diario_cierre`: `u. base`, no suma cruda
- [ ] IPV local si aplica

---

## Criterios de aceptación (smoke)

- [ ] Entrar 4 cajas + 4 unidades (caja=12): ledger 4 y 4; UI/reporte “4 Cajas + 4 Unidades”; valoración = 52 × costo base.
- [ ] Vender 1 unidad con 4 cajas y 0 sueltas → 3 cajas + 11 unidades. IPV no registra “venta de 1 caja”.
- [ ] Vender 1 caja con 0 cajas y 20 unidades → 0 cajas + 8 unidades.
- [ ] IPV y exportación no muestran un solo “unidades” que sume 4+4=8.
- [ ] Transferir 2 cajas no las convierte a 24 unidades en destino.
- [ ] Venta elaborada descuenta MP con rebalanceo en el almacén correcto (no última fila global).
- [ ] Precio de 1 caja en TPV = 12 × precio de la unidad. Costo promedio solo se actualiza en `es_base`.
- [ ] Producto que hoy solo tiene unidades sigue funcionando (un campo; sin regresiones).
- [ ] Kardex: recepción 4 cajas + 4 u y venta 1 u muestran saldo mixto; conversión no cuenta como venta; Excel no suma 4+4=8.
- [ ] Ventas general y proveedor: 2 cajas + 5 u (factor 12) = “2 Cajas + 5 U”, Equiv. 29, dinero = 29 × precio base. Una sola fila por producto.
- [ ] Cierre: Vend. mixto; FAB en u. base.

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
| 0 Helper SQL mixto / rebalanceo | [ ] | |
| 1 Dejar de convertir en escrituras | [ ] | |
| 2 UI entrada/salida mixta | [ ] | |
| 3 Reportes, IPV, valoración, costos, kardex, ventas, cierre | [ ] | Mixto + Equiv. u |
| 4 Venta TPV + BOM | [ ] | |
| 5 Conteo, offline | [ ] | |

---

## Referencias

- Schema: [VentiQ.sql](../VentiQ.sql)
- Recepción actual: [fn_registrar_recepcion_con_inventario.sql](../SQL_OPTIMIZATION/fn_registrar_recepcion_con_inventario.sql)
- Conversión cliente (a eliminar en escrituras): [presentation_converter.dart](../ventiq_admin_app/lib/utils/presentation_converter.dart)
- Venta actual: [registrarventa_ok.sql](../registrarventa_ok.sql)
- IPV: [obtener_inventario_completo.sql](../SQL_OPTIMIZATION/obtener_inventario_completo.sql)
- Kardex: [get_product_movements_v3_filtro_almacen.sql](../ventiq_admin_app/docs/migrations/get_product_movements_v3_filtro_almacen.sql), [product_movements_screen.dart](../ventiq_admin_app/lib/screens/product_movements_screen.dart)
- Ventas: [fn_reporte_ventas_con_proveedor4_optimizada.sql](../ventiq_admin_app/SQL_OPTIMIZATION/fn_reporte_ventas_con_proveedor4_optimizada.sql), [sales_screen.dart](../ventiq_admin_app/lib/screens/sales_screen.dart)
- Cierre: [venta_total_screen.dart](../ventiq_app/lib/screens/venta_total_screen.dart), [sales_monitor_fab.dart](../ventiq_app/lib/widgets/sales_monitor_fab.dart)
- Plan relacionado (no mezclar): [PLAN_RESTAURANTE_COCINA.md](PLAN_RESTAURANTE_COCINA.md)
