# Análisis de las 8 funciones pendientes de decidir (newa vs main)

> ## Decisiones tomadas el 19/11/2026 y scripts
>
> | # | Función | Decisión | Script |
> |---|---|---|---|
> | 1 y 2 | `get_detalle_producto`, `get_detalles_productos_batch` | Sin cambio lógico; se ignoran | — |
> | 3 | `fn_dashboard_carnaval_proveedor` | Traer main a newa | `sql_updates/newa_traer_funciones_main.sql` |
> | 4 | `fn_stock_producto_almacen_detalle` | Traer main a newa | ídem |
> | 5 | `fn_stock_saldos_presentacion` | Traer main a newa (y crear el índice parcial) | ídem |
> | 6 | `fn_reporte_ventas_con_proveedor_por_turno` | Traer main a newa | ídem |
> | 7 | `fn_reporte_ventas_por_turno` | Manda main (lo desplegado); se corrige el fin del turno sin operación de cierre usando el criterio por fecha, acotado por el siguiente turno | `sql_updates/fix_reporte_ventas_por_turno_sin_cierre.sql` (main y newa) |
> | 8 | `fn_registrar_cambio_estado_operacion_mejorado` | Cancelar una recepción devuelve la cantidad si el inventario no se tocó; si algún producto ya se usó, no se cancela y se informa cuál | `sql_updates/fix_cambio_estado_operacion_mejorado_recepcion.sql` (main y newa) + `ventiq_admin_app/lib/screens/inventory_operations_screen.dart` |
>
> Los scripts no están aplicados. Verificación hecha: las funciones de `newa_traer_funciones_main.sql` coinciden con main
> por hash md5 y todos los objetos que usan existen en newa; la lógica nueva de la función 7 se contrastó con datos de
> main (turnos normales: 0 cambios de 632; turnos sin cierre: 56.228 → 631 ventas); la función 8 se probó en newa dentro
> de una transacción revertida (recepción sin tocar: devuelve 6 → 0 con origen 4; recepción con 5 productos usados:
> se bloquea, los lista y no escribe nada; paso 3 → 4: no revierte dos veces).

Fecha del análisis: 19/11/2026. Solo lectura: cuerpos vivos de las dos bases, consultas SELECT sobre main y newa,
y el código de `ventiq_admin_app` y `ventiq_app`.

Punto de partida: en `comparacion_funciones_newa_main.md` quedaron 8 funciones en "hay que combinar a mano".
Al leerlas a fondo, **5 de las 8 se resuelven solas** (una resultó ser sin cambio lógico, cuatro son claramente
de main). Quedan **3 que sí necesitan decisión**.

| # | Función | Resolución propuesta |
|---|---|---|
| 1 | `get_detalle_producto` | Sin cambio lógico. Ignorar |
| 2 | `get_detalles_productos_batch` | Sin cambio lógico. Ignorar |
| 3 | `fn_dashboard_carnaval_proveedor` | Main gana. Traerla a newa |
| 4 | `fn_stock_producto_almacen_detalle` | Main gana (misma lógica, mucho más rápida). Traerla a newa |
| 5 | `fn_stock_saldos_presentacion` | Main gana (misma lógica, mucho más rápida). Traerla a newa |
| 6 | `fn_reporte_ventas_con_proveedor_por_turno` | Main gana. Es solo respaldo de la v2 |
| 7 | `fn_reporte_ventas_por_turno` | **Decidir**. Ningún criterio de los dos es correcto tal cual |
| 8 | `fn_registrar_cambio_estado_operacion_mejorado` | **Decidir**. Cada lado perdió una mitad; hay que combinar |

Con esto las cuentas pasan a: A newa más nueva = 21, B sin cambio = 42, C main más nueva = 16, D decidir = 2
(las funciones 7 y 8 de arriba). La tercera "a decidir" es el criterio compartido de turno, que afecta a la 7.

---

## 1 y 2. `get_detalle_producto` y `get_detalles_productos_batch`: sin cambio lógico

**Qué cambia.** Solo una línea, en el subselect de `precio_actual`:

```sql
-- main
WHERE id_producto = p.id
-- newa
WHERE id_producto = p.id AND COALESCE(id_variante, 0) = 0
```

**Por qué no cambia el resultado.** El subselect lee `app_v_precio_venta_base_vigente`, y esa vista ya es:

```sql
SELECT ... FROM app_v_precio_venta_vigente WHERE COALESCE(id_variante, 0::bigint) = 0;
```

Comprobé la definición viva en las dos bases y es idéntica. El filtro extra de newa repite lo que la vista ya hace.
Con la vista no puede aparecer una fila de variante.

**Corrección a mi análisis anterior.** Dije que newa estaba "bien" y que había que llevarlo a main. No hay nada que
llevar: ninguna base tiene el defecto. Sigue cumpliendo la regla de AGENTS.md porque el precio sale de la vista de vigencia.

**Quién las llama.** `ventiq_app` (`product_detail_service.dart`, `preorder_screen*.dart`, `settings_screen.dart`,
`servicentro_service.dart`) y la sincronización de productos del TPV.

**Acción.** Ignorarlas (pasan a "sin cambio lógico").

---

## 3. `fn_dashboard_carnaval_proveedor`: main gana

**Qué hace cada una.**

| Bloque del JSON | main | newa |
|---|---|---|
| `resumen.productos_vendidos` y `monto_total` | Solo órdenes con `status = 'Completado'` | Todas las órdenes, canceladas incluidas |
| `resumen.ticket_promedio` | `monto_total / ordenes_completadas` | `monto_total / ordenes_count` (todas) |
| `por_estado[].monto` | Presente | Ausente |
| `top_productos` | Top 10 **por cada estado**, con campo `status` | Top 10 global, sin `status` |

**Qué espera el cliente.** El modelo `CarnavalProviderDashboardData` y la pantalla
`carnaval_provider_dashboard_screen.dart` (admin):

- `CarnavalProviderEstado.fromJson` lee `monto` de cada estado. Con newa llega 0.
- `CarnavalProviderTopProducto.fromJson` lee `status`, y la pantalla filtra
  `topProductos.where((p) => p.status == status)` (línea 442). Con newa `status` llega vacío, ninguno coincide
  y la lista "Productos en órdenes …" sale vacía.
- El selector de estado arranca en `'Completado'`.

**Implicación.** newa es una versión anterior del dashboard: el cliente actual no funciona con ella (top de
productos vacío, montos por estado en 0) y el resumen se infla con órdenes canceladas.

**Acción.** Copiar el cuerpo de main a newa. No hay nada que rescatar de newa.

Nota: las dos usan `ORDER BY pv.fecha_desde DESC, pv.created_at DESC` para el precio, pero aquí el precio es
histórico a la fecha de la orden (`fecha_desde <= order_date < fecha_hasta`). Es una consulta histórica, así que
la regla del ID mayor de AGENTS.md no aplica.

---

## 4 y 5. `fn_stock_producto_almacen_detalle` y `fn_stock_saldos_presentacion`: main gana

**Qué es cada versión.**

- **newa**: la consulta "original". `DISTINCT ON` sobre **todo** el historial del producto (ordena todas las filas de
  inventario del producto para quedarse con la última por combinación).
- **main**: la misma consulta, optimizada con un *skip scan* recursivo sobre `idx_inv_prod_combo`: lee solo la última
  fila de cada combinación (variante, opción, presentación, ubicación).

**Documentado en el repo** (`sql_updates/optimizar_saldos_vigentes_skip_scan.sql`): nace de un error real en main,
el 29/10/2026. Una venta de 2 pizzas y 1 café murió por `statement_timeout` (8 s) porque cada ingrediente tiene
5.000 a 8.000 filas de historial y la receta llama varias veces a `fn_stock_saldos_presentacion`. Medido: 79 ms → 0,3 ms
por llamada. El propio script declara que la semántica es idéntica.

**Verificación de que la lógica es equivalente (leí los dos cuerpos).**

- `fn_stock_producto_almacen_detalle`: no distingue lotes en ninguna versión. Filtrar por almacén/ubicación antes
  (newa) o después (main) del "última fila por combinación" da lo mismo, porque la ubicación es parte de la
  combinación.
- `fn_stock_saldos_presentacion`: main tiene dos ramas. Si el producto **tiene** filas con `id_lote`, ejecuta la
  consulta original sin cambios (el mismo `DISTINCT ON` que newa). Si **no** tiene lotes, usa el skip scan. Sin
  lotes la clave `COALESCE(id_lote, 0)` es constante, así que las dos coinciden.
- La única diferencia posible sería un `NULL` frente a `0` en `id_presentacion`/`id_variante`, porque el skip scan
  agrupa con `COALESCE(..., 0)` y el `DISTINCT ON` de newa usa el valor crudo. Lo comprobé en los datos de las dos
  bases: **0 filas** con `id_presentacion`, `id_variante`, `id_opcion_variante` o `id_ubicacion` iguales a 0. No hay
  colisión posible.

**Corrección a mi análisis anterior.** Dije que main tenía la rama de lotes en las dos funciones. Solo la tiene
`fn_stock_saldos_presentacion`. Dije también que la equivalencia no estaba confirmada: ya está confirmada.

**Dependencias en newa.**

| Elemento | main | newa |
|---|---|---|
| `idx_inv_prod_combo` | existe | existe (misma definición) |
| `idx_inv_prod_lote_producto` (parcial, `WHERE id_lote IS NOT NULL`) | existe | **no existe** |
| Productos con lotes | 0 | 1 |

El skip scan de main necesita `idx_inv_prod_lote_producto` solo para saber rápido si el producto maneja lotes. Sin él
sigue funcionando, pero la comprobación `EXISTS` recorre más. Hay que crearlo en newa antes (el script lo trae como
"PASO 1", con `CREATE INDEX CONCURRENTLY`, que no admite transacción).

**Sobre `06_lotes_stock_sum_fefo.sql`** ("aplicar SOLO en newa, NO en main hasta el pase final"): la rama con lotes de
main ya es la versión "SUM de saldos por lote" que ese script lleva a newa. El `id_lote` ya existe en main (las
consultas de main lo usan sin error). Traer la versión de main a newa no choca con ese script.

**Acción.** Crear el índice parcial en newa y copiar los dos cuerpos de main. El comportamiento no cambia y el
rendimiento mejora en los ingredientes con mucho historial.

---

## 6. `fn_reporte_ventas_con_proveedor_por_turno`: main gana

**Qué cambia.**

| | main | newa |
|---|---|---|
| Qué ventas cuenta | Operaciones con `created_at` dentro del rango de fechas (de la fecha desde a la fecha hasta + 1 día) | Operaciones dentro de los turnos abiertos en ese rango, por rango de id de operación (`id_operacion_apertura` a `id_operacion_cierre`, o el máximo id si no hay cierre) |

**Quién la usa.** `sales_service.dart:503`, y **solo como respaldo**. El cliente llama primero a
`fn_reporte_ventas_con_proveedor_por_turno_v2` (línea 472) y solo cae a la v1 si la v2 "no está disponible".
La v2 es idéntica en las dos bases y usa la ventana por `created_at`, igual que la v1 de main.

**Implicaciones de newa.**

1. Contradice a su propia v2: la v1 de newa cuenta por turno y la v2 por fecha.
2. Hereda el defecto del criterio por id que se explica abajo (turnos cerrados sin operación de cierre).
3. Como la v2 existe en las dos bases, la v1 solo se ejecutaría si falla la v2.

**Acción.** No llevar la versión de newa a main. Dejar la de main. Para newa, traer la de main por coherencia.

---

## 7. `fn_reporte_ventas_por_turno`: decidir (criterio de turno)

Esta sí importa: **no es solo un respaldo**. `fn_reporte_ventas_por_turno_v2`, que usa `sales_service.dart:1097` para
la pestaña de TPVs, es un envoltorio que llama a esta función y le añade `desglose_monedas` y `total_base`.

### Qué hace cada una

| | main | newa |
|---|---|---|
| Qué turnos | Abiertos dentro del rango de fechas | Igual |
| Qué ventas son del turno | Mismo vendedor y TPV, tipo venta, pagada, último estado 2, con **id de operación** entre `id_operacion_apertura` y `COALESCE(id_operacion_cierre, MAX(id) global)` | Mismo, pero con **`created_at`** entre `fecha_apertura` y `COALESCE(fecha_cierre, NOW())` |
| Tipo de venta inexistente | Devuelve vacío (`RETURN`) | No lo comprueba |
| Filtro de tienda | `turnos` por TPV **y** `o.id_tienda = p_id_tienda` en la operación | Solo por TPV del turno |
| Evita duplicados | `DISTINCT ON (o.id)` | No |
| Volatilidad | `STABLE`, `search_path = public, pg_temp` | Sin `STABLE`, `search_path = public` |

### Evidencia con datos reales de main (turnos abiertos en los últimos 90 días)

Comparé las dos formas de contar ventas (completadas y pagadas) por turno:

| Tipo de turno | Turnos | Ventas por id | Ventas por fecha | Solo por id | Solo por fecha |
|---|---|---|---|---|---|
| Cerrado con operación de cierre | 633 | 26.322 | 25.735 | 652 | 65 |
| **Cerrado sin operación de cierre** | **32** | **56.228** | **681** | 55.547 | 0 |
| Abierto | 21 | 181 | 179 | 2 | 0 |

Lo que dicen los números:

1. **El criterio por id de main está roto para los 32 turnos cerrados sin `id_operacion_cierre`.** Para ellos usa el
   máximo id global como fin del turno, así que cuenta todas las ventas posteriores del mismo vendedor y TPV: 56.228
   frente a 681 reales. Un solo turno llega a mostrar 4.559 ventas frente a 149. Hay además 15 turnos abiertos desde hace
   más de 2 días con el mismo riesgo.
2. **El criterio por fecha de newa también pierde ventas**, pero pocas. En los 633 turnos normales cuenta 652 ventas
   menos (2,5 %) en 77 turnos: 567 tienen `created_at` posterior al cierre (media 57 min, máximo unas 8 horas) y 85
   anterior a la apertura. A cambio cuenta 65 que el criterio por id deja fuera. En las 39 que analicé por
   separado (en turnos con fecha de cierre registrada) el id es posterior al de la operación de cierre: son ventas que se
   subieron después de cerrar el turno, típico del modo offline.
3. Los turnos abiertos casi no cambian entre criterios.

### Por qué conviene el criterio por fecha de newa

- `fn_desglose_monedas_turno` y `fn_esperado_turno_por_moneda` (**idénticas en las dos bases**) ya usan ventana por
  `created_at` entre apertura y `COALESCE(fecha_cierre, now())`. La v2 une esta función con el desglose. En main el
  conteo sale del criterio por id y el desglose del criterio por fecha, y los dos pueden no coincidir. Con el criterio de
  newa los dos cuadran.
- `fn_turno_alinear_fecha_apertura` (R33, solo en newa) mueve la apertura de un turno offline hacia atrás, hasta 72 horas
  y sin pisar el cierre del turno anterior del mismo TPV y vendedor. Existe precisamente para que una ventana por fecha
  incluya las ventas hechas offline. El cierre offline en newa también se ajusta (`GREATEST(apertura, LEAST(cierre, now()))`).

### Riesgos del criterio de newa (lo que hay que arreglar al llevarlo)

1. **Sin `DISTINCT ON (o.id)`**: si dos turnos del mismo vendedor y TPV se solapan (por ejemplo un turno abierto que
   nunca se cerró y otro posterior), la misma venta se cuenta dos veces. R33 evita solapes al abrir, pero main tiene hoy
   15 turnos abiertos viejos que no pasaron por R33. Hay que conservar el `DISTINCT ON`.
2. **Sin `RETURN` si falta el tipo "venta"** y sin el filtro `o.id_tienda`: son guardas de main que no cuestan nada.
3. **Sin `STABLE`**: pierde el cacheo por consulta. Debe volver a `STABLE` y a `search_path = public, pg_temp`.
4. Los 567 + 85 casos de ventas fuera de la ventana de su turno siguen sin cubrirse. Es el mismo defecto que ya tiene el
   desglose de monedas en las dos bases, así que no es una regresión, pero conviene saberlo.

### Opciones

**Opción 1 (recomendada).** Cuerpo de newa (ventana por `created_at`) más las guardas de main: `STABLE`,
`search_path = public, pg_temp`, `RETURN` si falta el tipo venta, filtro `o.id_tienda` y `DISTINCT ON (o.id)`
(si hay solape, dejarla en el turno más reciente).
Ventaja: cuadra con `fn_desglose_monedas_turno` y `fn_esperado_turno_por_moneda`, corrige los 55.547 falsos positivos.
Coste: pierde 652 ventas en 77 turnos que hoy el criterio por id sí cuenta.

**Opción 2.** Criterio por id de main con arreglo del defecto: fin del turno = `COALESCE(id_operacion_cierre, máximo id
con created_at <= COALESCE(fecha_cierre, now()))`. Conserva las 652 y no inventa ventas en los turnos sin cierre.
Coste: sigue sin cuadrar con el desglose de monedas, que cuenta por fecha, y no recoge las ventas subidas después del
cierre (65 en la muestra).

**Opción 3.** Unión de los dos criterios. No la recomiendo: duplica el riesgo de sobreconteo.

**Mi propuesta:** opción 1, y registrar aparte las 652 ventas fuera de ventana para estudiarlas (probablemente la
causa es `cambiar_fecha_creacion_operacion_al_cierre`, que reescribe `created_at` al cerrar la operación, aunque no lo
verifiqué).

---

## 8. `fn_registrar_cambio_estado_operacion_mejorado`: combinar

### Qué hace cada una

El estado de operación puede ser 1 pendiente, 2 completada, 3 devuelta, 4 cancelada.

| Paso | main | newa |
|---|---|---|
| Validar estado y evitar repetir el mismo | Sí | Sí |
| **Recepción pasa a 2** | Recalcula el stock real y inserta el movimiento (`stock + cantidad`), tras borrar el movimiento prematuro de esa recepción | **No hace nada** ("las recepciones solo cambian de estado") |
| **Recepción pasa a 3 o 4** | Borra de `app_dat_inventario_productos` las filas ligadas a las líneas de esa recepción (movimientos prematuros) | **No hace nada** |
| Registrar el estado en `app_dat_estado_operacion` | Después de lo anterior | Antes |
| **Operación pasa a 2: flag de tienda** `cambiar_fecha_creacion_operacion_al_cierre` | **No lo aplica** | Si el flag está activo, `created_at = NOW()` |
| Extracción pasa a 3 o 4: devolver stock e ingredientes | Sí | Sí, igual |

### De dónde viene

Las dos copias son el resultado de dos scripts que **se pisaron**, cada uno reescribiendo la función completa:

- `sql_updates/fix_recepcion_inventario_al_completar.sql` (línea 275): añade la lógica de recepciones. Es lo que tiene main.
- `sql_updates/update_fecha_creacion_cierre.sql` (línea 217): añade el flag de fecha. Es lo que tiene newa.

Ninguna de las dos incluye la mitad que le falta. Por eso no hay una "más nueva": hay que unirlas.

### Implicaciones concretas

1. **Hay inventario prematuro real en main.** Consulté: **109 filas de inventario en 74 recepciones que siguen
   pendientes**; en newa hay 0. Con el cuerpo de main, al cancelar una de esas recepciones se borran esas filas. Con el
   cuerpo de newa se quedarían, y el inventario seguiría mostrando mercancía que nunca se recibió. No verifiqué si el
   listado de venta excluye esas filas.
2. **Alcance real del código de recepción.** El cliente solo llama a esta función con estado 3, desde el botón de
   cancelar de `inventory_operations_screen.dart`. *(Corrección 19/11: antes escribí que ese botón solo se muestra para
   operaciones pendientes. No es así: `_shouldShowCancelButton` devuelve `isPending || isCompleted`, así que también
   aparece en operaciones completadas, y entonces el `DELETE` de main sí borra el stock de una recepción ya completada.)*
   Completar una recepción usa `fn_completar_recepcion_operacion`, no esta función. La rama de "pasa a 2" nunca se
   ejecuta desde la app.
3. **Alcance real del flag de fecha.** Solo actúa con estado 2, y esta función no se llama con 2 desde la app. Sigue
   funcionando en `fn_registrar_cambio_estado_operacion` (la función sin "mejorado"), que lo tiene en las dos bases. Perder
   el flag aquí no cambia nada hoy.
4. **Riesgo de main que conviene arreglar.** El `DELETE` de recepciones con estado 3 o 4 **no comprueba que la recepción
   estuviera pendiente**. Como el botón de cancelar de admin también aparece en operaciones completadas, hoy cancelar
   una recepción completada borra sus filas de inventario y rompe la cadena `cantidad_inicial` / `cantidad_final` de los
   movimientos posteriores. El comentario de main dice "limpiar filas prematuras", pero el código no lo restringe.

### Propuesta

Cuerpo de **main** como base (mantiene la limpieza de las 74 recepciones y la rama de completar), más:

1. El bloque del flag `cambiar_fecha_creacion_operacion_al_cierre` de newa, tras registrar el estado 2.
2. Restringir el `DELETE` de estados 3 y 4 a recepciones cuyo estado anterior fuera pendiente (1) o sin estado. Una
   recepción completada que se devuelva o cancele **no debe** reescribir el historial de inventario.

### Decisión que queda abierta (de negocio)

Qué debe pasar con el stock cuando se devuelve o cancela una recepción **ya completada**:

- main (hoy): al borrar las filas de esa recepción, el stock baja.
- newa: no toca el inventario ("cancelar una recepción no debe sumar existencias").

Con la restricción propuesta, ninguna de las dos pasa por esta función. Si el negocio quiere revertir el stock de una
recepción completada, eso debería ir por un movimiento nuevo de ajuste, no por borrar filas.

---

## Qué hacer con cada una (resumen)

| Función | Acción |
|---|---|
| `get_detalle_producto` | Ninguna |
| `get_detalles_productos_batch` | Ninguna |
| `fn_dashboard_carnaval_proveedor` | Copiar main a newa |
| `fn_stock_producto_almacen_detalle` | Crear `idx_inv_prod_lote_producto` en newa y copiar main a newa |
| `fn_stock_saldos_presentacion` | Igual |
| `fn_reporte_ventas_con_proveedor_por_turno` | Copiar main a newa |
| `fn_reporte_ventas_por_turno` | Decidir criterio (propuesta: opción 1); luego llevar a main |
| `fn_registrar_cambio_estado_operacion_mejorado` | Decidir (propuesta: main + flag + DELETE restringido); luego llevar a las dos |

Siguientes pasos que puedo hacer cuando confirmes: escribir el script de newa (índice y cuerpos de main para las
funciones 3 a 6) y los scripts de las dos funciones combinadas (7 y 8) para que los revises antes de aplicarlos.
