# Consumo de ingredientes de elaborados por presentación — análisis SQL

**Autor:** `sql-analyst` (task-1) · **Fecha:** 2026-10-21
**Proyecto medido:** producción `vsieeihstajlrdvpuooh` (`https://vsieeihstajlrdvpuooh.supabase.co`), MCP Supabase **solo lectura**.
**Alcance del archivo:** este único documento. No se modificó código, SQL ni docs del repo.

---

## 0. Alcance, límites y correcciones al brief

| Punto del brief | Realidad medida | Evidencia |
|---|---|---|
| «producto 5, arroz id 3, frijoles id 4» | **No existen.** `min(id) = 95`, `max(id) = 11358` en `app_dat_producto` | `SELECT min(id), max(id) FROM app_dat_producto;` → `95 / 11358` |
| Denominación «arroz moro» | **No existe** ningún producto/servicio con `denominacion ILIKE '%moro%'` en producción | consulta de §4.1 |
| Proyecto del caso real | Proyecto **debug `qhprswhhfasrikhawjoz`**, al que apunta la app en `flutter run` (`ventiq_app/lib/config/supabase_config.dart:5`). El MCP de esta sesión está atado a **producción** y no puede consultarlo | confirmado por el Lead |
| `fn_planificador_cumplimiento_presentaciones_v2` | Nombre **inexacto**: la función viva es **`fn_planificar_cumplimiento_presentaciones_v2`** | `pg_proc` §6 |

**Consecuencia metodológica.** Este documento hace dos cosas separadas y claramente etiquetadas:

- **(A)** causa raíz y censo **medidos en producción** (§1–§8): aquí sí hay números reales.
- **(B)** paquete de consultas **listo para pegar en el proyecto debug** (§9), que determina qué migraciones de presentaciones le faltan y qué síntoma produce cada una.

Todo lo de §1–§8 está verificado contra la **definición viva** (`pg_get_functiondef`), no contra las copias del repo.

**Destino del arreglo: los DOS proyectos Supabase** — debug `qhprswhhfasrikhawjoz` (rama de prueba, donde el usuario reproduce el fallo) y release/producción `vsieeihstajlrdvpuooh`. Producción se usa aquí como **referencia del estado esperado** de cada migración: los marcadores booleanos y los `md5(pg_get_functiondef)` de §6 y §10 son el patrón contra el que se compara el debug. Los dos tomas del síntoma reportadas por el usuario (5000/3000/2000 y 5000/2000/3000) se analizan con su fórmula en §4.4–§4.5.

---

## 1. Funciones vivas que participan en consumir ingredientes de un elaborado

Ninguna firma del repo local difiere de la viva para las funciones de esta tabla; las diferencias repo↔producción que sí existen se anotan en §6.

### 1.1 Cadena de expansión y medición

| Función (firma viva) | Rol | ¿Factor / base? | Defecto |
|---|---|---|---|
| `fn_obtener_ingredientes_recursivos(p_id_producto_elaborado bigint, p_cantidad_producto numeric) → TABLE(id_ingrediente bigint, cantidad_total_necesaria numeric, nivel_recursion integer)` | Expande la receta recursivamente. Devuelve `cantidad_necesaria × p_cantidad_producto` | **Unidades base** del ingrediente (la receta se guarda así) | — |
| `fn_stock_producto_almacen_detalle(p_id_producto bigint, p_id_almacen bigint) → TABLE(id_ubicacion, id_almacen, id_variante, id_opcion_variante, id_presentacion, cantidad_final, sku_producto, sku_ubicacion)` | Última fila del ledger por `(ubicación, variante, opción, presentación)` con `cantidad_final > 0`; **L39: `ORDER BY v.cantidad_final DESC, v.id_ubicacion`** | **NO aplica factor. Deliberado**: es la cantidad **física** de esa presentación, la que se **persiste** en el ledger | Ninguno *per se*; el defecto es usarla como si fuera base **y** que su orden dependa del número físico (§1.9) |
| `fn_stock_producto_almacen(p_id_producto bigint, p_id_almacen bigint) → numeric` | Total del almacén **en unidades base** | **SÍ** — `factor_rel` | — (línea 14: `SUM(d.cantidad_final * COALESCE(f.factor_rel, 1))`) |

Definición viva (extracto, líneas reales de `prosrc`):

```sql
-- fn_stock_producto_almacen, líneas 14-15 (md5 ecad724f55e19af4eb21d4f73d4ccc61)
SELECT COALESCE(SUM(d.cantidad_final * COALESCE(f.factor_rel, 1)), 0)::numeric
  FROM public.fn_stock_producto_almacen_detalle(p_id_producto, p_id_almacen) d
  LEFT JOIN LATERAL public.fn_presentaciones_producto(p_id_producto) f
         ON f.id_presentacion = d.id_presentacion;
```

### 1.2 Validación (correcta pero ciega a almacén)

`fn_validar_ingredientes_elaborado(p_id_producto_elaborado bigint, p_cantidad numeric, p_id_almacen bigint) → jsonb`
— `STABLE`, md5 `c23f85d245c97f89c33e508574fd1aa0`.

```sql
-- línea 19
FROM public.fn_obtener_ingredientes_recursivos(p_id_producto_elaborado, p_cantidad)
-- línea 23
v_disponible := public.fn_stock_producto_almacen(v_ing.id_ingrediente, p_id_almacen);
-- línea 29
IF v_disponible < v_ing.cantidad_total_necesaria THEN
```

Mide **bien** (base contra base, `factor_rel` aplicado) pero **solo dentro del `p_id_almacen` recibido**. Es el primer punto donde aparece el síntoma «hay menos de lo que hay» (§4.2).

### 1.3 Consumo — el defecto central

`fn_descontar_ingredientes_elaborado(p_id_producto_elaborado bigint, p_cantidad numeric, p_id_almacen bigint, p_id_extraccion bigint, p_origen_cambio integer) → jsonb`
— `VOLATILE`, md5 `47be3a93f8d026eba2f5fbfc31b0cd4a`. `usa_detalle = true`, `usa_factor_rel = false`.

```sql
-- Línea 12
v_validacion := public.fn_validar_ingredientes_elaborado(
    p_id_producto_elaborado, p_cantidad, p_id_almacen);
-- Línea 23  (expansión: cantidad_total_necesaria EN UNIDADES BASE)
FROM public.fn_obtener_ingredientes_recursivos(p_id_producto_elaborado, p_cantidad)
-- Línea 25
v_pendiente := v_ing.cantidad_total_necesaria;          -- ← BASE
-- Línea 29  (detalle: cantidad_final ES LA CANTIDAD FÍSICA DE LA PRESENTACIÓN)
FROM public.fn_stock_producto_almacen_detalle(v_ing.id_ingrediente, p_id_almacen)
-- ★ LÍNEA 33 — EL DEFECTO ★
v_a_descontar := LEAST(v_ubic.cantidad_final, v_pendiente);
-- Línea 55 (escritura: física − física, coherente con el detalle)
v_ubic.cantidad_final - v_a_descontar
-- Línea 72
v_pendiente := v_pendiente - v_a_descontar;             -- ← resta física de base
-- Línea 78-91 (fallo con mensaje engañoso: 'faltan N')
```

**L33 compara la cantidad FÍSICA de una presentación contra un pendiente en UNIDADES BASE.** Las tres líneas que hay que leer juntas son **L25 (base) · L29 (física) · L33 (mezcla)**. No es un `LEAST` mal escrito: es un `LEAST` entre dos magnitudes distintas.

### 1.4 Enrutado de venta — segundo sitio del mismo defecto

`fn_descontar_venta_enrutada(p_id_producto bigint, p_cantidad numeric, p_id_tpv bigint, p_id_extraccion bigint, p_origen_cambio integer, p_ya_descontado_sku boolean) → jsonb`
— `VOLATILE SECURITY DEFINER`, md5 `d56b117f2c9307a8c6bfaac29ce5e1e8`.

```sql
-- Rama receta (L~40): delega en el helper del 01
v_resultado := fn_descontar_ingredientes_elaborado(...)   -- hereda L33
-- Rama SKU propio:
-- Línea 83
v_disponible := fn_stock_producto_almacen(p_id_producto, v_id_almacen);   -- BASE
-- Línea 85
IF COALESCE(v_disponible, 0) < p_cantidad THEN                            -- BASE vs BASE (ok)
-- Línea 114
SELECT * FROM fn_stock_producto_almacen_detalle(p_id_producto, v_id_almacen)  -- FÍSICA
-- ★ LÍNEA 118 — MISMO DEFECTO, OTRA COPIA ★
v_a_descontar := LEAST(v_ubic.cantidad_final, v_pendiente);
-- Línea 159-162: si sobra pendiente, RAISE EXCEPTION (no devuelve jsonb)
```

**Censo global del patrón:** buscando `LEAST(\s*v_<alias>.cantidad_final` en `prosrc` de **todas** las funciones de `public`, hay exactamente **2 sitios vivos**:

| Función | Línea | md5 |
|---|---|---|
| `fn_descontar_ingredientes_elaborado` | **33** | `47be3a93f8d026eba2f5fbfc31b0cd4a` |
| `fn_descontar_venta_enrutada` | **118** | `d56b117f2c9307a8c6bfaac29ce5e1e8` |

### 1.5 Venta: dónde se convierte la cantidad (y dónde NO)

`fn_registrar_venta` (md5 `371402e5622517270563ef7f73aa8bc3`) — **sí** convierte:

```sql
-- Línea 353
v_descuento_bom := public.fn_descontar_venta_enrutada(
-- Líneas 355-356
p_cantidad          := public.fn_cantidad_en_base(
                         v_producto_presentacion_id, (v_producto->>'cantidad')::NUMERIC),
```

`fn_registrar_venta_mesa` idem en **L425 / L427** (md5 `74b4751f30a745a6c21f4b3b7334d3b8`).

**Las otras tres rutas vivas NO convierten** — pasan la cantidad en la presentación elegida como si fuera base:

| Ruta | Línea | Código | Consecuencia |
|---|---|---|---|
| `fn_pedir_item_cuenta` | **83–90** | `p_cantidad := p_cantidad` | Vender 1 **Caja** de un elaborado con `descontar='ingredientes'` descuenta la receta de **1 unidad** |
| `fn_agregar_producto_orden_pendiente` | **135–141** | `p_cantidad := (p_producto->>'cantidad')::NUMERIC` | Ídem; además **ignora `id_presentacion`** |
| `fn_actualizar_cantidad_producto_orden` | **117–123** | `p_cantidad := v_delta` | Ídem al subir la cantidad de una comanda (y `fn_devolver_ingredientes_elaborado` con `ABS(v_delta)` al bajarla) |

Estas tres tienen **la mitad del parche del 24** (§6): el `24` se aplicó solo a `fn_registrar_venta` y `fn_registrar_venta_mesa`.

### 1.6 Disponibilidad de plato (cara al vendedor)

`fn_disponibilidad_plato(p_id_producto bigint, p_id_tpv bigint) → jsonb` — `STABLE SECURITY DEFINER`, md5 `fec1805ea0052fb3b4c3c5e0dbe6906e`.

- **L88/L91/L92** (elaborado sin cocina) y **L227/L231/L232** (cocina `al_pedido`): `v_stock_ing := fn_stock_producto_almacen(...)` → **correcto en unidades**.
- Pero el almacén es **uno solo**: `v_almacen_tpv` (L91) o `v_almacen_cocina` (L231). Hereda el sesgo de §4.2.
- **L199** (modo `por_tanda`): `v_disponible := fn_stock_producto_almacen(p_id_producto, v_almacen_cocina)` — stock terminado del propio SKU; aquí un saldo en presentación ≠ base sí escala.

### 1.7 Tandas / producción y devoluciones (copias propias del cálculo)

| Función | Líneas | Qué hace mal |
|---|---|---|
| `fn_producir_tanda(p_id_cocina bigint, p_id_producto bigint, p_porciones numeric, p_notas text, p_ajuste_mp numeric)` | **96-97** elige ubicación con `ORDER BY d.cantidad_final DESC LIMIT 1`; **93** `v_cant_mp := cantidad_total_necesaria * COALESCE(p_ajuste_mp, 1.0)` (base); **130** `v_actual - v_cant_mp` | **Resta base de física sin `LEAST` y sin factor**: puede dejar el ledger **negativo**. Además usa otra expansión de receta (`fn_ingredientes_con_parada_tanda`, L90), no la recursiva |
| `fn_devolver_ingredientes_elaborado(..., p_cantidad, p_id_almacen, ...)` | 2ª pasada, md5 `7a4a71902aae6719bcac5513a3db9027` | Devuelve `v_actual + v_ing.cantidad_total_necesaria` (**base**) eligiendo `id_presentacion` con una cascada `COALESCE` (última fila de la ubicación → última del almacén → **primera fila por `pp.id ASC`**). Puede escribir **500 en una fila marcada `Kilogramo`** |
| `fn_cancelar_item_pedido(p_id_item bigint, p_id_motivo text)` | **107** detalle, **121** `v_ubic.cantidad_final + v_a_devolver` | Misma familia: devuelve a la presentación de la ubicación elegida |
| `fn_ubicacion_destino_devolucion(p_id_producto bigint, p_id_almacen bigint)` | usa detalle | Elige destino por cantidad física, sin factor |

### 1.8 Código muerto que **parece** vivo (hallazgo colateral)

Cinco funciones de `public` referencian el esquema **`app_rest_*`, que NO existe** en producción (`SELECT table_name FROM information_schema.tables WHERE table_name LIKE 'app_rest%'` → **0 filas**):

`fn_verificar_disponibilidad_plato(bigint,bigint,integer)` · `fn_validar_stock_plato(bigint,integer)` · `fn_descontar_inventario_plato()` (trigger) · `fn_descontar_inventario_plato(bigint,bigint,uuid)` · `fn_descontar_modificaciones()`.

Si alguna se ejecutara daría `42P01 relation "app_rest_recetas" does not exist`. **No son rutas a arreglar**: son residuo. Además, dos de ellas contienen el mismo error de unidades por si alguien las resucita:

```sql
-- fn_verificar_disponibilidad_plato:  SUM(cantidad_final)  ← físico crudo, sin factor
-- fn_descontar_inventario_plato(bigint,bigint,uuid):  WHERE i.cantidad_final >= v_cantidad_necesaria
--   ← exige que UNA sola ubicación cubra la necesidad en BASE; FIFO, sin factor
-- fn_descontar_inventario_plato() (trigger):  UPDATE ... WHERE id_producto = ...   ← ¡SIN filtro de ubicación!
```

No hay triggers vivos que las invoquen (`pg_trigger` filtrado por esas funciones → 0 filas).

### 1.9 Por qué «a veces aparece gramo, otras kg» — no es aleatorio, es `ORDER BY` físico

El usuario lo describe como aleatorio:

> «me parece que está tomando una aleatoria para descontar o seleccionar, porque a veces aparece gramo, otras kg»

**Es determinista.** El orden lo fija el `ORDER BY` de la fuente, y todas las fuentes ordenan por **cantidad física** (nunca por factor ni por nivel de presentación):

| Función | Línea | Orden | Efecto |
|---|---|---|---|
| `fn_stock_producto_almacen_detalle` | **39** | `ORDER BY v.cantidad_final DESC, v.id_ubicacion` | El bucle consume **primero la fila con el número físico más grande** |
| `fn_producir_tanda` | **97** | `ORDER BY d.cantidad_final DESC LIMIT 1` | Elige **una sola** ubicación: la del número físico mayor |
| `fn_stock_saldos_presentacion` | 49 | `ORDER BY v.id_ubicacion, COALESCE(c.nivel, 999), v.id_presentacion` | Ordena por **nivel de presentación** (el mayor empaque primero) — es el único que ordena «por empaque» |

Fórmula del «empate» que percibe el usuario: con saldos `(q_kg, q_g)` la primera fila que se toca es

```
primera_fila = argmax_i ( q_i )        -- empate → id_ubicacion ASC
```

Así, para un pedido de 5000 g:

| Saldos en la ubicación | Sale primero | Por qué |
|---|---|---|
| 3 kg (`q=3`) + 2000 g (`q=2000`) | **gramos** | `2000 > 3` |
| 5 kg (`q=5`) + 2000 g (`q=2000`) | **gramos** | `2000 > 5` |
| 3 kg (`q=3`) + 900 g (`q=900`) | **gramos** | `900 > 3` |
| 3000 g (`q=3000`) + 2 kg (`q=2`) | **gramos** | `3000 > 2` |
| 1 kg (`q=1`) + 2000 (`q=2000`) en **otra ubicación** | kg | la otra ubicación no compite |

**Regla:** mientras el saldo en gramos sea numéricamente mayor que el saldo en kg (que es el caso casi siempre, porque 1 kg se guarda como `1` o como `3`, no como `3000`), **los gramos van primero**. El «a veces kg» aparece cuando el usuario registra el kg con un número alto (p. ej. `cantidad_final = 3000` en una fila `Kilogramo`) o cuando la fila de gramos está en **otra ubicación** y no entra en el `detalle` del almacén consultado. En ambos casos el número que se compara contra `v_pendiente` es **físico**, y `v_pendiente` está en **base**: por eso el resultado cambia de presentación *y* de resto pendiente.

---

## 2. Censo de callers vivos (confirmación/corrección del brief)

Método: `regexp_matches(prosrc, '<nombre>\(')` sobre **todas** las funciones de `public`. Cuenta llamadas estáticas (no detecta SQL dinámico ni RPC desde la app).

| Función llamada | Callers vivos | ¿Coincide con el brief? |
|---|---|---|
| `fn_stock_producto_almacen` (escalar) | `fn_anular_tanda`, `fn_cerrar_tanda`, `fn_descontar_venta_enrutada`, `fn_disponibilidad_plato` (×4), `fn_listar_tandas_cocina`, `fn_platos_por_tanda_cocina` (×2), `fn_producir_tanda`, `fn_productos_cocina_tpv` (×3), `fn_resolver_origen_venta`, `fn_validar_ingredientes_elaborado` → **11 funciones** | Sí (el 27 decía 13 *llamadas*; son 11 funciones) |
| `fn_stock_producto_almacen_detalle` | `fn_cancelar_item_pedido`, `fn_descontar_ingredientes_elaborado`, `fn_descontar_venta_enrutada`, `fn_producir_tanda`, `fn_stock_producto_almacen`, `fn_ubicacion_destino_devolucion` → **6** | Sí |
| `fn_validar_ingredientes_elaborado` | `fn_descontar_ingredientes_elaborado`, **`fn_descontar_con_rebalanceo_almacen`** | ⚠️ el brief no listaba el segundo |
| `fn_descontar_ingredientes_elaborado` | `fn_descontar_venta_enrutada`, `fn_agregar_producto_orden_pendiente`, `fn_actualizar_cantidad_producto_orden` → **3** | **Confirmado** |
| `fn_devolver_ingredientes_elaborado` | `fn_cancelar_item_pedido`, `fn_actualizar_cantidad_producto_orden`, `fn_eliminar_producto_orden` → **3** | nuevo (pedido por el Lead) |
| `fn_obtener_ingredientes_recursivos` | `fn_descontar_ingredientes_elaborado`, `fn_devolver_ingredientes_elaborado` (×2), `fn_disponibilidad_plato` (×2), `fn_eliminar_producto_orden`, `fn_productos_cocina_tpv`, `fn_validar_ingredientes_elaborado` → **6** | — |
| `fn_descontar_venta_enrutada` | `fn_registrar_venta`, `fn_registrar_venta_mesa`, `fn_registrar_venta_v2`, `fn_registrar_venta_mesa_v2`, `fn_pedir_item_cuenta` → **5** | **Confirmado** |
| `fn_disponibilidad_plato` | **0 callers SQL** (solo RPC desde la app) | — |
| `fn_descontar_inventario_plato` | **0 callers SQL** (y `app_rest_*` no existe) | — |

**Rutas de escritura que hay que arreglar para el BOM de elaborados (7):**
`fn_descontar_ingredientes_elaborado` (L33) · `fn_descontar_venta_enrutada` (L118, rama SKU) · `fn_producir_tanda` (L93/L96/L130) · `fn_devolver_ingredientes_elaborado` · `fn_cancelar_item_pedido` (L121) · `fn_pedir_item_cuenta`/`fn_agregar_producto_orden_pendiente`/`fn_actualizar_cantidad_producto_orden` (**falta `fn_cantidad_en_base`**).

---

## 3. Hechos de datos que sostienen el análisis

```sql
-- 3.1 Catálogo
SELECT count(*) AS elaborados, count(DISTINCT id_tienda) AS tiendas
  FROM app_dat_producto WHERE es_elaborado;         -- → 124 | 14
```
```sql
-- 3.2 Presentaciones de masa: solo dos nombres, «Gramo» (id 16) y «Kilogramo» (id 15)
SELECT np.id, np.denominacion, count(*) FROM app_nom_presentacion np
  JOIN app_dat_producto_presentacion pp ON pp.id_presentacion = np.id
 WHERE np.denominacion IN ('Gramo','Kilogramo') GROUP BY 1,2;
-- → 16 «Gramo» 29 usos | 15 «Kilogramo» 7 usos
```

`fn_presentaciones_producto` (md5 `4514c0e9667e3e472608b6dc8d2bd0c3`) calcula
`factor_rel = round(pp.cantidad / NULLIF(base.cantidad,0), 6)` y resuelve la base con
`ORDER BY pp.es_base DESC, pp.cantidad ASC, pp.id ASC LIMIT 1`. **Un `Kilogramo` con `cantidad = 1` sobre una base `Gramo` con `cantidad = 1` da `factor_rel = 1`** — es la mina del caso del usuario y el censo que la detecta está en §9 D1/D3.

---

## 4. Reproducción con datos reales (solo `SELECT`; ninguna escritura)

### 4.1 No hay caso «arroz moro» en producción; el análogo más cercano sí existe

```sql
SELECT e.id, e.denominacion, e.id_tienda, i.id_ingrediente, p.denominacion, i.cantidad_total_necesaria
  FROM app_dat_producto e
  CROSS JOIN LATERAL fn_obtener_ingredientes_recursivos(e.id, 1) i
  JOIN app_dat_producto p ON p.id = i.id_ingrediente
 WHERE e.es_elaborado AND e.deleted_at IS NULL
   AND (p.denominacion ILIKE '%arroz%' OR p.denominacion ILIKE '%frijol%' OR p.denominacion ILIKE '%moro%');
```
→ **1 fila**: `10122 «potaje de frijoles»` (tienda 218) con ingrediente `10120 «frijoles Negros» × 500`, ambas presentación única `Gramo` base (`factor_rel = 1`), saldo **999999** en ubicación 292 / almacén 275.
→ El análogo estructural (elaborado con ingrediente multipresentación) es otro: ver §4.2 y §7.

### 4.2 Caso A — **multi-almacén**: la validación ve «hay 0» cuando hay 980 (100 % real, producción)

Elaborado **`240 «pan con perro»`** (tienda 11), receta/1 unidad: `238 pan solo × 1`, `239 perro caliente × 2`.
Saldo vivo de `239`: **160 en almacén 1**, **0 en almacén 12** (`contendor refrigerado`).

```sql
SELECT 'stock 239 almacen 12' AS caso, fn_stock_producto_almacen(239,12)::text
UNION ALL SELECT 'stock 239 almacen 1',       fn_stock_producto_almacen(239,1)::text
UNION ALL SELECT 'stock 239 toda la tienda',  fn_stock_producto_almacen(239,NULL)::text
UNION ALL SELECT 'validar(240,1,12)', fn_validar_ingredientes_elaborado(240,1,12)::text
UNION ALL SELECT 'validar(240,1,1)',  fn_validar_ingredientes_elaborado(240,1,1)::text
UNION ALL SELECT 'validar(240,1,NULL)', fn_validar_ingredientes_elaborado(240,1,NULL)::text;
```

Resultado medido (recortado):

```
stock 239 almacen 12 = 0
stock 239 almacen 1  = 160.0000000
validar(240,1,12)  = {"status":"error","error_code":"INSUFFICIENT_STOCK_INGREDIENT",
                      "message":"Stock insuficiente para el ingrediente: pan solo
                                 (disponible: 0, requerido: 1.0)",
                      "id_ingrediente":238,"cantidad_disponible":0,"id_almacen":12}
validar(240,1,1)   = {"status":"success", ... "pan solo":980.0 ... "perro caliente":160.0}
validar(240,1,NULL)= {"status":"success", ... idéntico ...}
```

Es **exactamente** el síntoma del usuario, con números reales: `disponible: 0` / `requerido: 1.0`, mientras el ingrediente tiene stock de sobra en la misma tienda. El mensaje que ve el vendedor sale de aquí (o de `fn_disponibilidad_plato`, que usa el mismo `fn_stock_producto_almacen` por almacén único).

### 4.3 Caso B — **unidades mixtas en el bucle**: descuenta TODO el estante y aun así dice «faltan 932»

No hay hoy en producción ningún elaborado cuyo ingrediente tenga stock en una presentación `factor_rel <> 1` (§7), así que el bucle se **simula** (solo `SELECT`) sobre filas **reales** de `11007 «cerveza cristal»` (tienda 223, almacén 331, ubicación 349), cuyas presentaciones y saldos vivos son reales:

| fila | presentación | saldo físico | `factor_rel` | equivalente base |
|---|---|---|---|---|
| 1 | Caja | 30 | 24 | 720 |
| 2 | Blister | 23 | 6 | 138 |
| 3 | Cajón | 13 | 30 | 390 |
| 4 | Unidad | 2 | 1 | 2 |
| | | | **total** | **1250** |

El `24` no se toca: el detalle devuelve `cantidad_final` **física**; el bucle resta esa física del pendiente **base**. Simulación **exacta** del bucle (misma recursión que el `FOR`):

```sql
WITH RECURSIVE d AS (
  SELECT row_number() OVER (ORDER BY cantidad_final DESC, id_ubicacion) AS i,
         cantidad_final, id_presentacion, id_ubicacion
    FROM fn_stock_producto_almacen_detalle(11007, 331)
), s AS (
  SELECT i, cantidad_final, id_presentacion, id_ubicacion,
         1000::numeric AS pendiente_antes,
         LEAST(cantidad_final, 1000::numeric) AS a_descontar
    FROM d WHERE i = 1
  UNION ALL
  SELECT d.i, d.cantidad_final, d.id_presentacion, d.id_ubicacion,
         s.pendiente_antes - s.a_descontar,
         LEAST(d.cantidad_final, s.pendiente_antes - s.a_descontar)
    FROM s JOIN d ON d.i = s.i + 1
)
SELECT s.i, f.nombre AS presentacion, s.cantidad_final AS saldo_fisico, f.factor_rel,
       s.pendiente_antes, s.a_descontar AS descuenta_el_bucle,
       s.pendiente_antes - s.a_descontar AS pendiente_despues,
       round(s.a_descontar * f.factor_rel, 3) AS base_realmente_consumida
  FROM s
  LEFT JOIN LATERAL fn_presentaciones_producto(11007) f ON f.id_presentacion = s.id_presentacion
 ORDER BY s.i;
```

Resultado medido:

```
paso 1  Caja     30      24.0   1000 → descuenta 30   → 970   (base real  720)
paso 2  Blister  23       6.0    970 → descuenta 23   → 947   (base real  138)
paso 3  Cajón    13      30.0    947 → descuenta 13   → 934   (base real  390)
paso 4  Unidad    2       1.0    934 → descuenta  2   → 932   (base real    2)
```

**El bucle vacía el estante entero** (68 piezas físicas = **1250 unidades base**) para una necesidad de **1000**, le abona al pendiente solo **68** (las piezas), y termina con `v_pendiente = 932 > 0`, devolviendo:

```
{"status":"error","error_code":"INSUFFICIENT_STOCK_INGREDIENT",
 "message":"Stock insuficiente para el ingrediente: cerveza cristal (faltan 932)",
 "cantidad_requerida":1000,"cantidad_disponible":68}
```

Es peor que un rechazo: **si el llamador no está en una transacción que aborte, el inventario ya quedó a cero** y la venta se reporta fallida. `fn_validar_ingredientes_elaborado` había dicho `success` con 1250 ≥ 1000.

### 4.4 Caso C — la reconstrucción «pido 5000, hay 3000, faltan 2000» (1ª toma)

Producto base `Gramo`; `Kilogramo` con `factor_rel = 1000`; receta/1 unidad = **5000 g**. Saldo: **3 kg en almacén A**, **2 kg en almacén B**.

Datos textuales del usuario, en **dos tomas** del mismo problema:

| Toma | Pedido | «había» | «faltaban» | Suma |
|---|---|---|---|---|
| 1ª | 5000 | 3000 | 2000 | 5000 |
| 2ª | 5000 | 2000 | 3000 | 5000 |

**Observación clave: `disponible + faltante = requerido` en las dos tomas, y el total que el usuario cree tener siempre es 5000.** No es ruido: es la firma de un cálculo que **sólo mira una parte** (un almacén, o una presentación) mientras el total real es 5000. Lo que cambia entre tomas es *qué parte* entra en la cuenta — no la aritmética. Las dos tomas se desarrollan en §4.5.

| Paso | Llamada | Resultado | Mensaje al vendedor |
|---|---|---|---|
| 1 | `fn_stock_producto_almacen(ing, A)` | `3 × 1000 = 3000` | «hay **3000**» |
| 2 | `fn_validar_ingredientes_elaborado(elab, 1, A)` | `3000 < 5000` → `error` | «pido **5000**g … faltan **2000**» |
| 3 | `fn_stock_producto_almacen(ing, NULL)` | `3000 + 2000 = 5000` | (nadie lo consulta) |

La 1ª toma sale **clavada** de §4.2 con sólo cambiar los kg por gramos: **basta mirar un solo almacén**, no hace falta ningún defecto adicional. La 2ª toma es el mismo mecanismo con el reparto invertido. El desarrollo completo de las dos, con la fórmula para cada estado de migraciones, va en §4.5.

### 4.5 Escenarios y fórmulas: debug **sin** vs **con** las migraciones

El usuario confirma que los ids son del **proyecto debug** (rama de prueba) y que el arreglo irá a **los dos** proyectos. Por eso el mismo síntoma hay que saber leerlo en los dos estados. Definiciones:

```
fila          = (ubicación, presentación) con cantidad_final > 0 devuelta por
                fn_stock_producto_almacen_detalle(producto, almacén)      [L39]
q             = cantidad_final de la fila                 (unidades FÍSICAS de su presentación)
k             = factor_rel de la fila                     (equivalente base de esa presentación)
A             = el almacén que el TPV/cocina resolvió (p_id_almacen)
```

#### Escenario α — debug **sin** la migración `27`

`fn_stock_producto_almacen` es `SUM(cantidad_final)` **crudo, sin factor**:

```
disponible_A = Σ_{fila ∈ A} q                       (física; el factor NO entra)
```

| Saldo vivo (base `Gramo`; `Kilogramo` ⇒ `k=1000`) | `disponible_A` | Mensaje del vendedor |
|---|---|---|
| A: `Gramo 2000` + `Kilogramo 3` ; B: `3 kg` | `2000 + 3 = 2003` | «había **2003**, faltaban **2997**» |
| A: `Gramo 2000` ; B: `3 kg` | `2000` | «había **2000**, faltaban **3000**» ✅ **2ª toma exacta** |
| A: `Kilogramo 3` ; B: `2 kg` | `3` | «había **3**, faltaban **4997**» |

→ α **sólo da el número exacto del usuario si el almacén consultado tiene una sola presentación**. Si el kg y los gramos conviven en el mismo almacén, el crudo da `2003` (o `5003`), no `2000`/`3000`.

#### Escenario β — debug **con** el `27` (estado de producción)

`fn_stock_producto_almacen` aplica `factor_rel`:

```
disponible_A = Σ_{fila ∈ A} q × k
```

| Saldo vivo | `disponible_A` | Tienda completa | Mensaje |
|---|---|---|---|
| A: `2 kg` (`k=1000`) ; B: `3 kg` | `2 × 1000 = 2000` | `5000` | «había **2000**, faltaban **3000**» ✅ 2ª toma |
| A: `3 kg` ; B: `2 kg` | `3 × 1000 = 3000` | `5000` | «había **3000**, faltaban **2000**» ✅ 1ª toma |
| A: `Gramo 2000` (`k=1`) ; B: `3 kg` | `2000` | `5000` | «había **2000**, faltaban **3000**» ✅ 2ª toma |
| A: `Kilogramo 3` con `cantidad = 1` sobre base `Gramo` `cantidad = 1` ⇒ `k = 1` | `3` | `3` | «había **3**, faltaban **4997**» |

→ **β cuadra exacto con las dos tomas sin suponer nada nuevo**: basta que el kg y los gramos estén en **almacenes distintos**, que es justo lo medido en producción (§4.2 y §7.4: 36 elaborados en 8 tiendas con esa asimetría). Y explica por qué el usuario vio `3000` primero y `2000` después: **cambió el reparto entre almacenes** (una venta, una recepción), no el motor.

#### Conclusión de los dos escenarios

| Pregunta | Respuesta |
|---|---|
| ¿Qué produce «había 2000, faltaban 3000»? | `fn_validar_ingredientes_elaborado` L29, con `cantidad_disponible = fn_stock_producto_almacen(ing, A) = 2000` y `cantidad_requerida = 5000`. La app resta `5000 − 2000 = 3000` |
| ¿Hace falta el defecto de unidades mixtas para estos números? | **No.** El `LEAST` mixto (§4.3) produce un mensaje distinto y sólo alcanzable si la validación pasó (§4.6) |
| ¿Cuál es la causa de «sólo 2000»? | **Alcance**: se mide `A`, no toda la tienda (`disponible = Σ_{fila ∈ A} q × k`, con `k = 1` si falta el `27`) |
| ¿Qué arreglo desbloquea al usuario? | El de **alcance** (validar/consumir contra el equivalente base de la tienda, o resolver bien el almacén). **Arreglar el `LEAST` mixto por sí solo NO lo desbloquea** |
| Si además el catálogo tiene el kg con `k = 1` | Hace falta el `35`/`fn_presentaciones_producto_v2` (§9 D1, D3.2) |

### 4.6 Qué mensaje produce cada función (y cuál es alcanzable con qué números)

Tabla de atribución: sirve para saber **de qué función viene** lo que vio el usuario. Textos = literales del `prosrc` vivo.

| Texto del mensaje | Función y línea | Campos del `jsonb` | ¿Cuándo es alcanzable? |
|---|---|---|---|
| `Stock insuficiente para el ingrediente: X (disponible: D, requerido: R)` | `fn_validar_ingredientes_elaborado` L29-40 | `status='error'`, `error_code='INSUFFICIENT_STOCK_INGREDIENT'`, `id_ingrediente`, `ingrediente`, `cantidad_requerida=R`, `cantidad_disponible=D`, `id_almacen`. **Sin `faltante`** | Siempre que `D < R`. `D = fn_stock_producto_almacen(ing, almacén)`. ⭐ **Es el candidato de «había 2000, faltaban 3000»** |
| `Stock insuficiente para el ingrediente: X (faltan N)` | `fn_descontar_ingredientes_elaborado` L78-91 | `cantidad_requerida`, `cantidad_disponible = R − N`, `id_almacen`, **con `movimientos`** | **Sólo si la validación PASÓ** (se llama primero, L12, y si falla se devuelve su resultado tal cual). `N` es artificial y `R − N` **no es stock**: es lo que el bucle creyó consumir (§4.7) |
| `Stock insuficiente (disponible: D, requerido: R)` — *sin* «ingrediente» | `fn_descontar_venta_enrutada` L95 | `error_code='INSUFFICIENT_STOCK'`, `origen`, `id_almacen`, `id_cocina` | Rama SKU propio; aquí `D` **sí** es el escalar con factor |
| `No hay suficientes porciones preparadas en "C" (disponibles: D, requeridas: R)` | `fn_descontar_venta_enrutada` L89-93 | `error_code='INSUFFICIENT_PORTIONS'` | Origen `cocina_por_tanda` |
| «Stock insuficiente» redactado por la app | cliente Flutter | — | Si el texto **no** coincide con ninguno de arriba, lo compone la app desde `fn_disponibilidad_plato` / `fn_stock_saldos_presentacion` (§9 D10) |

**Regla de atribución:** `(disponible: D, requerido: R)` **sin** `movimientos` ⇒ **validación/escalar**. `(faltan N)` **con** `movimientos` ⇒ **bucle**, y entonces el `cantidad_disponible` reportado es mentira.

### 4.7 Aritmética explícita del bucle mezclado (fórmula general)

Sean `N` la necesidad en base, `q_i` la cantidad **física** de la i-ésima fila en el orden de L39 (`q_i` descendente, empate `id_ubicacion ASC`, §1.9) y `k_i` su `factor_rel`:

```
p_0 = N
a_i = LEAST(q_i, p_{i-1})        ← EL DEFECTO: min(física, base)
p_i = p_{i-1} - a_i              ← resta FÍSICA de BASE

base_realmente_descontada      = Σ a_i · k_i      (lo que sale del estante)
base_que_el_bucle_cree_consumir = Σ a_i           (lo que abona al pendiente)
faltante_reportado             = p_último = N − Σ a_i
cantidad_disponible_reportada  = N − p_último = Σ a_i     ← no es stock
```

- Error si `p_último > 0` → mensaje `(faltan N − Σ a_i)` y escribe `q_i − a_i` por fila.
- Si `Σ a_i·k_i > N` → **consume de más** y aun así reporta faltante (caso medido §4.3: `Σ a_i·k_i = 1250`, `N = 1000`, `Σ a_i = 68` → `(faltan 932)` con el estante en cero).
- Si `k_i < 1` → **subdescuento**: `Σ a_i·k_i < N` cuando debía descontarse `N`, y la venta **pasa** con el inventario inflado (el error silencioso de `24_bom_cantidad_en_base.sql:34-36`).
- Orden: `primera_fila = argmax_i q_i` ⇒ el «aleatorio» de §1.9.

Con `N = 5000`, `(q_g = 2000, k_g = 1)` y un `Kilogramo` con `k = 1000`:

| Saldo | 1ª fila | `a_1` | `a_2` | `Σ a_i` | base real | Resultado |
|---|---|---|---|---|---|---|
| `q_kg = 3` | gramos (2000) | 2000 | 3 | 2003 | 2000 + 3000 = **5000** | `(faltan 2997)` |
| `q_kg = 3000` | kg (3000) | 3000 | 2000 | 5000 | **3 000 000 + 2000** | pasa (`p = 0`), destroza el ledger |
| sólo gramos (`q_g = 2000`) | gramos | 2000 | — | 2000 | **2000** | `(faltan 3000)` ✅ **pero inalcanzable** |

→ La tercera fila produce `faltan 3000`, **pero no es alcanzable** por el bucle con un pedido de 5000: la validación habría visto `disponible = 2000 < 5000` y el bucle nunca corre (§4.6). **Confirma que los números del usuario vienen de la validación/escalar, no del bucle.**

---

## 5. Causa raíz exacta y semántica mínima correcta

### 5.1 Causa raíz (una frase)

**El sistema mezcla dos magnitudes —cantidad física de presentación y cantidad en unidades base— en tres lugares distintos y en ningún momento convierte/abre empaques durante el consumo:**

1. **`LEAST` mixto** — `fn_descontar_ingredientes_elaborado` L33 y `fn_descontar_venta_enrutada` L118 comparan `v_ubic.cantidad_final` (física) con `v_pendiente` (base).
2. **Alcance de almacén** — la validación mira **un** `p_id_almacen`; el stock del resto de la tienda y el de otras ubicaciones del mismo producto no entra. (§4.2)
3. **No hay conversión en el consumo** — ni el escalar ni el bucle pasan por `fn_descontar_con_rebalanceo(_almacen)`, el único helper que sabe abrir un `Kilogramo` para servir gramos y que deja la conversión **auditada**.
4. **Tres rutas de escritura no convierten la cantidad vendida** (`fn_pedir_item_cuenta` L85, `fn_agregar_producto_orden_pendiente` L137, `fn_actualizar_cantidad_producto_orden` L119), y `_v2` de venta se quedó sin el `25`.

Y el efecto dominó: como la escritura es `v_ubic.cantidad_final - v_a_descontar` (física − física), el ledger **queda coherente consigo mismo** — por eso el error es silencioso: el inventario se vacía y la venta se reporta fallida, o al revés (subdescuento por el factor) según el signo de la diferencia.

### 5.2 Semántica mínima correcta

Un ingrediente repartido en **N ubicaciones × M presentaciones** debe consumirse así, en **unidades base** de punta a punta:

```
necesidad_base (receta × cantidad_en_base)
  → Por CADA ubicación con saldo del ingrediente, en el almacén resuelto:
        equivalente_base(ubicación, presentación) = saldo_físico × factor_rel
  → Pasada 1: consumir el saldo de la MISMA presentación solicitada (0 conversiones).
  → Pasada 2: donde solo hay presentaciones distintas, abrir/empaquetar con
              fn_descontar_con_rebalanceo_almacen, que:
                · valida el equivalente base del ALMACÉN completo (no de una ubicación),
                · deja la conversión auditada (`app_dat_conversion_presentacion_evento` / `_pata`),
                · NUNCA produce cantidades fraccionarias de empaque:
                  el objetivo se descompone en combinaciones enteras de factores.
  → El pendiente se mide SIEMPRE en base; cada escritura al ledger se expresa en la
    presentación física que se movió (física − física) y se registra su equivalente.
```

Restricciones que fija la semántica (y que el plan de correcciones debe respetar):

- **Sin fracciones de empaque**: si el objetivo no se descompone en factores enteros, el máximo servible es `TRUNC(equivalente_base / factor, 3)` — exactamente lo que ya calcula `fn_descontar_con_rebalanceo_almacen` (`maximo_convertible`, L51; `convertible`, L96).
- **`fn_stock_producto_almacen_detalle` NO se toca.** Su `cantidad_final` debe seguir siendo física porque es lo que se persiste (`fn_descontar_ingredientes_elaborado` L55, `fn_descontar_venta_enrutada` L140, `fn_producir_tanda` L130). Aplicarle el factor escribiría saldos falsos — mucho peor que el bug. Lo que hay que arreglar es **quien la consume para medir**, no ella.
- **La validación y el consumo deben medir con la MISMA función** (§9 D4). Hoy la validación usa el escalar (base, factor) y el consumo usa el detalle (física): ese divorcio es la causa.
- **Almacén**: o se valida contra el almacén resuelto **y** se permite la conversión dentro de él, o la tienda debe exponer el total. Decidir explícitamente; hoy es implícito y produce §4.2.

### 5.3 Qué NO se puede tocar (compatibilidad con builds viejos) y qué debe ir a `_vX`

**No tocar la firma de** (hay apps en producción llamando estas RPC por nombre):

`fn_registrar_venta(bigint,uuid,jsonb,text,text,text,smallint,bigint)` · `fn_registrar_venta_mesa(...9 args)` · `fn_registrar_venta_v2` · `fn_registrar_venta_mesa_v2` · `fn_descontar_venta_enrutada` · `fn_descontar_ingredientes_elaborado` · `fn_validar_ingredientes_elaborado` · `fn_stock_producto_almacen` · `fn_stock_producto_almacen_detalle` · `fn_disponibilidad_plato` · `fn_obtener_ingredientes_recursivos` · `fn_cantidad_en_base` · `fn_pedir_item_cuenta` · `fn_agregar_producto_orden_pendiente` · `fn_actualizar_cantidad_producto_orden` · `fn_producir_tanda`.

Razón: son las llamadas vivas del TPV móvil. Cambiar una firma rompe builds ya instalados. La app vieja manda `id_presentacion = null` y cantidades ya en base: los fallbacks de `fn_cantidad_en_base` (`NULL` o presentación inexistente → cantidad sin tocar) preservan ese comportamiento — **mantenerlos**.

**Pueden arreglarse in-place (misma firma, `CREATE OR REPLACE`)** porque el arreglo es interno y retrocompatible: `fn_descontar_ingredientes_elaborado` y `fn_descontar_venta_enrutada` (sustituir el `LEAST` por la llamada al rebalanceo, y devolver el mismo contrato `jsonb` con `status`/`error_code` que ya espera la app).

**Debe ser `_v2` / `_v3`** (cambio de contrato o de semántica de entrada):

| Propuesta | Por qué `_vX` |
|---|---|
| `fn_descontar_ingredientes_elaborado_v2` con argumento de política (`p_permitir_conversion boolean`, `p_alcance_almacen text`) | Cambia el resultado para casos donde hoy **falla**; un build viejo que espera el error debe poder seguir pidiendo el comportamiento antiguo |
| `fn_registrar_venta_v3` / `fn_registrar_venta_mesa_v3` que apliquen el `25` **y** la conversión en las tres rutas de cocina | `_v2` ya está desplegado **sin** el `25`; corregirlo in-place cambiaría el comportamiento de un RPC que ya tiene consumidores |
| `fn_pedir_item_cuenta_v2` · `fn_agregar_producto_orden_pendiente_v2` · `fn_actualizar_cantidad_producto_orden_v2` | Introducen `fn_cantidad_en_base` en la entrada: la cantidad pasa a interpretarse **en la presentación**, no en base. Cambio semántico de entrada |
| `fn_devolver_ingredientes_elaborado_v2` | Debe devolver **a la presentación correcta** (hoy elige con una cascada), y el destino hoy es una decisión implícita |

**Reutilizar tal cual, ya vivas y probadas:** `fn_presentaciones_producto_v2` (md5 `dce860b00574524aea50cdaedc6f0388`), `fn_planificar_cumplimiento_presentaciones_v2` (`c061cdd43146d837c46ee17bb954aad9`), `fn_combinar_factores_presentacion_v2`, `fn_descomponer_equivalente_presentacion_v2`, `fn_preview_cumplimiento_v2` (`2a67058d973c93e7925e294fdfe44ddd`), `fn_aplicar_cumplimiento_v2` (`96654b7d7b7ebb430a64ab5987fb5a29`), `fn_ejecutar_entrega_fisica_v2` (`9edf415b400a467a1d6627a628fd3376`), `fn_aplicar_plan_extraccion_v2`, `fn_crear_extraccion_con_movimiento_v2`, `fn_descontar_con_rebalanceo(_almacen)`, `fn_rebalancear_presentaciones`, `fn_registrar_conversion_v2`.

---

## 6. Completitud del stack de presentaciones en producción (incl. huecos detectados)

Marcadores sobre `prosrc` de los RPC de venta vivos:

```sql
SELECT p.proname,
       p.prosrc LIKE '%fn_cantidad_en_base(%'                                        AS m24,
       p.prosrc LIKE '%fn_rebalancear_presentaciones%'                               AS m25,
       p.prosrc LIKE '%COALESCE(id_presentacion, 0) = COALESCE(v_producto_presentacion_id, 0)%' AS m22,
       p.prosrc LIKE '%fn_descontar_venta_enrutada(%'                                AS m10
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname='public' AND p.proname LIKE 'fn_registrar_venta%'
 ORDER BY 1;
```

| RPC | `22` | `24` | `25` | `10` |
|---|---|---|---|---|
| `fn_registrar_venta` | ✅ | ✅ | ✅ | ✅ |
| `fn_registrar_venta_mesa` | ✅ | ✅ | ✅ | ✅ |
| `fn_registrar_venta_v2` | ✅ | ✅ | **❌ falta el 25** | ✅ |
| `fn_registrar_venta_mesa_v2` | ✅ | ✅ | **❌ falta el 25** | ✅ |

**Hueco vivo:** los `_v2` validan y convierten la cantidad, pero **no pueden abrir/armar empaques**. Si la app llama a `_v2`, vender 1 Unidad cuando solo hay Cajas devuelve el error del `CHECK`/validación en vez de abrir la Caja. Confirmar en la app qué RPC se invoca (`dart-analyst`).

**Objetos presentes en producción** (verificado con `to_regprocedure`/`to_regclass`):

- Tablas: `app_dat_conversion_presentacion`, `app_dat_conversion_presentacion_evento`, `app_dat_conversion_presentacion_pata`, `app_dat_cumplimiento_inventario_solicitud`, `app_dat_extraccion_v2_solicitud`; columnas `app_dat_inventario_productos.id_conversion` y `id_conversion_evento`.
- Helpers previos: `fn_presentaciones_producto`, `fn_presentaciones_producto_v2`, `fn_presentaciones_producto_editable`, `fn_stock_saldos_presentacion`, `fn_equivalente_base`, `fn_formatear_stock_mixto`, `fn_stock_mixto_json`, `fn_stock_mixto_almacen`, `fn_stock_mixto_producto_por_ubicacion`, `fn_validar_cantidad_final_inventario`, `fn_preview_rebalanceo`.

**Ausente/no aplicado en producción:** nada del stack de presentaciones; los únicos «faltantes» son los que nunca existieron (`app_rest_*`) y las variantes `_v2` de parches en los RPC `_v2`.

---

## 7. Censo de exposición en producción

### 7.1 Elaborados cuyo ingrediente está configurado en varias presentaciones

```sql
WITH elab AS (SELECT id, denominacion, id_tienda FROM app_dat_producto WHERE es_elaborado AND deleted_at IS NULL),
     ing AS (SELECT e.id AS id_elab, e.denominacion AS elab, e.id_tienda, i.id_ingrediente, i.cantidad_total_necesaria AS nee
               FROM elab e CROSS JOIN LATERAL fn_obtener_ingredientes_recursivos(e.id, 1) i)
SELECT ing.id_elab, ing.elab, ing.id_tienda, ing.id_ingrediente, p.denominacion,
       ing.nee, count(pp.id) AS n_pres,
       string_agg(COALESCE(np.denominacion,'?')||'(c='||pp.cantidad||',base='||pp.es_base||')',
                  ' | ' ORDER BY pp.cantidad DESC) AS pres
  FROM ing JOIN app_dat_producto p ON p.id = ing.id_ingrediente
  LEFT JOIN app_dat_producto_presentacion pp ON pp.id_producto = ing.id_ingrediente
  LEFT JOIN app_nom_presentacion np ON np.id = pp.id_presentacion
 GROUP BY 1,2,3,4,5,6 HAVING count(pp.id) >= 2
 ORDER BY ing.id_tienda, ing.id_elab;
```

→ **4 filas / 4 elaborados / 3 tiendas:**

| Elaborado | Tienda | Ingrediente | Necesario/1 | Presentaciones |
|---|---|---|---|---|
| `220 pan de la casa` | 11 | 217 azúcar refino | 3.0 | Bulto(c=10, no base) · Bolsa(c=1, base) |
| `221 pan con croqueta` | 11 | 217 azúcar refino | 3.00 | idem |
| `240 pan con perro` | 11 | 239 perro caliente | 2.0 | Caja(c=24, no base) · Unidad(c=1, base) |
| `961 combo max` | 47 | 960 refrresco coral | 4.0 | Caja(24) · Blister(12) · Unidad(1, base) |

### 7.2 Stock vivo con `factor_rel <> 1` (donde el `LEAST` mixto muerde hoy)

```sql
WITH det AS (
  SELECT DISTINCT ON (ip.id_producto, la.id_almacen, ip.id_ubicacion,
                      COALESCE(ip.id_variante,0), COALESCE(ip.id_opcion_variante,0), COALESCE(ip.id_presentacion,0))
         ip.id_producto, la.id_almacen, ip.id_presentacion, ip.cantidad_final
    FROM app_dat_inventario_productos ip
    JOIN app_dat_layout_almacen la ON la.id = ip.id_ubicacion
   WHERE la.deleted_at IS NULL
   ORDER BY ip.id_producto, la.id_almacen, ip.id_ubicacion,
            COALESCE(ip.id_variante,0), COALESCE(ip.id_opcion_variante,0), COALESCE(ip.id_presentacion,0), ip.id DESC
), vivos AS (SELECT * FROM det WHERE COALESCE(cantidad_final,0) > 0)
SELECT count(DISTINCT (v.id_producto, v.id_almacen)) AS combos, count(*) AS filas,
       count(DISTINCT v.id_producto) AS productos, count(DISTINCT p.id_tienda) AS tiendas,
       count(DISTINCT v.id_producto) FILTER (WHERE p.es_elaborado) AS elaborados
  FROM vivos v JOIN app_dat_producto p ON p.id = v.id_producto
  LEFT JOIN LATERAL fn_presentaciones_producto(v.id_producto) f ON f.id_presentacion = v.id_presentacion
 WHERE COALESCE(f.factor_rel,1) <> 1;
```

→ **6 combos · 9 filas · 6 productos · 3 tiendas · 0 elaborados**:

| Producto | Tienda | Almacén | Presentación | `factor_rel` | Saldo físico | Equivalente base |
|---|---|---|---|---|---|---|
| 4545 FREEGELLS EXTRA FUERTE | 25 | 29 | Caja | 24 | 533 | 12 792 |
| 4558 Salchicha 350 gm | 25 | 29 | Caja | 24 | 15 | 360 |
| 11001 prod azucar multiipresentacion | 223 | 331 | Caja | 24 | 49 | 1 176 |
| 11001 prod azucar multiipresentacion | 223 | 331 | Bulto | 5 | 2.8 | 14 |
| 11007 cerveza cristal | 223 | 331 | Caja / Blister / Cajón | 24 / 6 / 30 | 30 / 23 / 13 | 720 / 138 / 390 |
| 11151 Aceite | 227 | 346 | Caja | 12 | 218 | 2 616 |
| 11152 Agua de Pomo 500mgx12 | 227 | 346 | Blister | 12 | 185 | 2 220 |

**Lectura:** el bug está **latente para elaborados** (0 elaborados afectados hoy) y **activo para SKU propio** — pero `fn_descontar_venta_enrutada` L118 sólo se alcanza cuando `v_origen <> 'barra'` o `p_ya_descontado_sku = false`; en barra el early-return de L~76 lo salta. Por eso no ha estallado. **Se dispara en cuanto el usuario configure un `Kilogramo` en un elaborado de arroz/frijoles.**

### 7.3 Multipresentación con saldo (para descartar el censo equivocado)

```sql
-- mismo CTE det/vivos; agrupar por (producto, almacén) y quedarse con count(DISTINCT presentación) > 1
```
→ **4 combos · 4 productos · 3 tiendas · 0 elaborados**: `11001 prod azucar multiipresentacion` (t223, 2), `11007 cerveza cristal` (t223, 4), `3046 aaa` (t69, 2), `9753 fer` (t179, 2).
⚠️ Este censo es el **equivocado** para el bug (el `LEAST` mixto no necesita 2 presentaciones, sólo 1 con `factor_rel <> 1`). El correcto es §7.2 — tal como ya advertía `presentaciones_inventario/27_stock_almacen_en_base.sql:73-77`.

### 7.4 Exposición multi-almacén (el riesgo de §4.2) — **36 elaborados en 8 tiendas**

Para cada elaborado: unidades producibles con el **mejor almacén único** vs con **toda la tienda**.

```sql
WITH elab AS (SELECT id, denominacion, id_tienda FROM app_dat_producto WHERE es_elaborado AND deleted_at IS NULL),
     ing AS (SELECT e.id AS id_elab, e.denominacion AS elab, e.id_tienda, i.id_ingrediente, i.cantidad_total_necesaria AS nee
               FROM elab e CROSS JOIN LATERAL fn_obtener_ingredientes_recursivos(e.id, 1) i),
     per_alm AS (SELECT ing.id_elab, ing.elab, ing.id_tienda, alm.id AS id_almacen,
                        min(floor(fn_stock_producto_almacen(ing.id_ingrediente, alm.id)/NULLIF(ing.nee,0))) AS unidades
                   FROM ing JOIN app_dat_almacen alm ON alm.id_tienda = ing.id_tienda
                  GROUP BY 1,2,3,4),
     best_alm AS (SELECT id_elab, elab, id_tienda, max(unidades) AS mejor_almacen,
                         (array_agg(id_almacen ORDER BY unidades DESC))[1] AS almacen_top
                    FROM per_alm GROUP BY 1,2,3),
     tienda AS (SELECT ing.id_elab,
                       min(floor(fn_stock_producto_almacen(ing.id_ingrediente, NULL)/NULLIF(ing.nee,0))) AS unidades_tienda
                  FROM ing GROUP BY 1)
SELECT b.id_elab, b.elab, b.id_tienda, b.almacen_top, b.mejor_almacen, t.unidades_tienda,
       t.unidades_tienda - b.mejor_almacen AS unidades_ganadas
  FROM best_alm b JOIN tienda t ON t.id_elab = b.id_elab
 WHERE t.unidades_tienda > b.mejor_almacen
 ORDER BY (t.unidades_tienda - b.mejor_almacen) DESC;
```

**Resultado: 36 filas.** Los casos extremos (mejor almacén = **0** producible, tienda = mucho):

| Elaborado | Tienda | Almacén top | Producible en ese almacén | Producible con toda la tienda |
|---|---|---|---|---|
| `10800 tacos` | 223 | 333 | 41 000 | 100 000 |
| `10873 Croqueta` | 221 | 339 | 5 000 | 5 486 |
| `680 CARTUCHO NATURAL` | 25 | 29 | **0** | 331 |
| `635 COPO NATURAL PLUSS` | 25 | 29 | **0** | 133 |
| `240 pan con perro` | 11 | 12 | **0** | 80 |
| `10811 caipiroska` | 223 | 334 | **0** | 52 |

Los `0` de la tienda 25 son el caso más grave: **todo el bloque de elaborados de heladería/pizza queda invendible** si el almacén del TPV no es donde está la materia prima.

---

## 8. Huecos y riesgos

| # | Hueco | Evidencia | Severidad |
|---|---|---|---|
| R1 | **Validación y consumo miden con funciones distintas** (escalar base vs detalle físico) | §5.1; `fn_validar_ingredientes_elaborado` L23 vs `fn_descontar_ingredientes_elaborado` L29/L33 | **Crítica** — causa raíz |
| R2 | **`LEAST` mixto en 2 sitios** | L33 y L118 | **Crítica** |
| R3 | **Sin conversión/rebalanceo en el consumo de receta**: `fn_descontar_ingredientes_elaborado` no llama a `fn_descontar_con_rebalanceo(_almacen)` (0 coincidencias en `prosrc`) | §1.3 | **Crítica** — imposible «abrir el kg» |
| R4 | **Alcance de almacén**: validación y `fn_disponibilidad_plato` miran **un** almacén | 36 elaborados / 8 tiendas (§7.4) | **Alta** — síntoma «hay 0» con stock |
| R5 | **Tres rutas de cocina no convierten la cantidad** | `fn_pedir_item_cuenta` L85, `fn_agregar_producto_orden_pendiente` L137, `fn_actualizar_cantidad_producto_orden` L119 | **Alta** — subdescuento silencioso por el factor |
| R6 | **`_v2` de venta sin el `25`**: no abre empaques | §6 | **Alta** si la app usa `_v2` |
| R7 | **`fn_producir_tanda` con su propia copia**: `v_actual - v_cant_mp` (L130) sin factor ni `LEAST`, y otra expansión de receta (`fn_ingredientes_con_parada_tanda`) | §1.7 | **Alta** — puede dejar ledger negativo |
| R8 | **`fn_devolver_ingredientes_elaborado` devuelve base a una presentación elegida por cascada** (`pp.id ASC` como último fallback) | §1.7 | Media — corrompe el saldo de la presentación |
| R9 | **`fn_cancelar_item_pedido` / `fn_ubicacion_destino_devolucion`** devuelven a la presentación de la ubicación por **cantidad física** | L121 / detalle | Media |
| R10 | **Código muerto con el mismo error**: 5 funciones `app_rest_*` inexistente; `fn_descontar_inventario_plato()` haría `UPDATE` **sin filtro de ubicación** | §1.8 | Media (latente: no hay triggers, pero es una trampa) |
| R11 | **Catálogos con `cantidad` que no es el equivalente real**: 131 filas `es_base` con `cantidad` 12/24/30; `Kilogramo`/`Gramo` con `cantidad = 1` → `factor_rel = 1` | `24_bom_cantidad_en_base.sql:44-48`; §3.2 | **Alta** — causa del «hay 3000» mal calculado en el debug |
| R12 | **Censo de exposición engañoso**: filtrar por «>1 presentación con saldo» da 4 productos y esconde el bug; el filtro correcto es `factor_rel <> 1` | §7.2 vs §7.3 | Media (metodológica) |

---

## 9. Paquete de diagnóstico para el proyecto debug `qhprswhhfasrikhawjoz`

> Pegar **bloque por bloque** en el SQL Editor del proyecto debug. Todo es `SELECT`; ningún bloque escribe. Los `<placeholders>` se completan con lo que devuelva D1.

### D0 · Contexto del proyecto

```sql
SELECT current_database() AS db, current_setting('server_version') AS pg,
       (SELECT count(*) FROM app_dat_producto)                       AS productos,
       (SELECT min(id) FROM app_dat_producto)                         AS min_id,
       (SELECT count(*) FROM app_dat_producto WHERE es_elaborado)     AS elaborados;
```

### D1 · ¿Qué migraciones de presentaciones están aplicadas? (marcadores, robusto a firmas)

```sql
WITH f AS (SELECT p.proname, p.prosrc
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public'),
     t AS (SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
             WHERE n.nspname = 'public' AND c.relkind = 'r'),
     col AS (SELECT table_name, column_name FROM information_schema.columns
              WHERE table_schema = 'public')
SELECT v.migracion, v.aplicada, v.sintoma_si_falta
  FROM (VALUES
  ('01 schema conversion',
   (SELECT count(*) FROM t WHERE relname = 'app_dat_conversion_presentacion') > 0
   AND EXISTS (SELECT 1 FROM col WHERE table_name='app_dat_inventario_productos' AND column_name='id_conversion'),
   'Sin tabla de conversiones ni id_conversion: cualquier arreglo de empaques es imposible.'),
  ('02 helpers lectura mixta (fn_presentaciones_producto + fn_stock_saldos_presentacion)',
   EXISTS (SELECT 1 FROM f WHERE proname='fn_presentaciones_producto')
   AND EXISTS (SELECT 1 FROM f WHERE proname='fn_stock_saldos_presentacion'),
   'No hay forma de leer saldo por presentacion: la app solo ve cantidades fisicas crudas.'),
  ('03/07 rebalanceo (fn_descontar_con_rebalanceo[ _almacen] + fn_rebalancear_presentaciones)',
   EXISTS (SELECT 1 FROM f WHERE proname='fn_descontar_con_rebalanceo')
   AND EXISTS (SELECT 1 FROM f WHERE proname='fn_rebalancear_presentaciones'),
   'NADIE puede abrir un Kilogramo para servir gramos: la venta exige la presentacion exacta.'),
  ('18 lecturas stock mixto (fn_stock_mixto_almacen)',
   EXISTS (SELECT 1 FROM f WHERE proname='fn_stock_mixto_almacen'),
   'El admin no ve el stock mixto por almacen.'),
  ('22 venta: saldo leido por presentacion',
   (SELECT count(*) FROM f WHERE proname LIKE 'fn_registrar_venta%'
      AND prosrc LIKE '%COALESCE(id_presentacion, 0) = COALESCE(v_producto_presentacion_id, 0)%') >= 1,
   'La venta arrastra el saldo de OTRA presentacion de la ubicacion (inventa stock de la nada).'),
  ('24 BOM: cantidad convertida a base (fn_cantidad_en_base)',
   EXISTS (SELECT 1 FROM f WHERE proname='fn_cantidad_en_base')
   AND (SELECT count(*) FROM f WHERE proname LIKE 'fn_registrar_venta%' AND prosrc LIKE '%fn_cantidad_en_base(%') >= 1,
   'Vender 1 Caja de un elaborado descuenta la receta de 1 unidad (subdescuento por el factor).'),
  ('27 fn_stock_producto_almacen devuelve BASE (factor_rel)',
   (SELECT count(*) FROM f WHERE proname='fn_stock_producto_almacen' AND prosrc LIKE '%factor_rel%') > 0,
   'El escalar SUMA cantidad_final sin factor: con 3 Kg devuelve 3 (no 3000) y con 3 Kg + 2000 g devuelve 2003. La validacion ve "3000"/"2003" en vez del equivalente base -> "Stock insuficiente" falso.'),
  ('25 venta con rebalanceo (abre/arma empaques)',
   (SELECT count(*) FROM f WHERE proname LIKE 'fn_registrar_venta%' AND prosrc LIKE '%fn_rebalancear_presentaciones%') >= 1,
   'La venta NO convierte: vender 5 Unidades con solo Cajas falla en vez de abrir una Caja.'),
  ('35 fn_presentaciones_producto_v2',
   EXISTS (SELECT 1 FROM f WHERE proname='fn_presentaciones_producto_v2'),
   'Falta la validacion de catalogo (base unica, factores unicos, no fraccionarios).'),
  ('38 fn_planificar_cumplimiento_presentaciones_v2',
   EXISTS (SELECT 1 FROM f WHERE proname='fn_planificar_cumplimiento_presentaciones_v2'),
   'No hay planificador de extraccion en combinaciones enteras de empaques.'),
  ('39/41/42 cumplimiento v2 (_preview/_aplicar/_entrega_fisica/_conversion_evento)',
   EXISTS (SELECT 1 FROM f WHERE proname='fn_preview_cumplimiento_v2')
   AND EXISTS (SELECT 1 FROM f WHERE proname='fn_aplicar_cumplimiento_v2')
   AND EXISTS (SELECT 1 FROM t WHERE relname='app_dat_conversion_presentacion_evento'),
   'Sin extraccion con conversion auditada: no se puede consumir 500 g de un Kg dejando traza.')
  ) AS v(migracion, aplicada, sintoma_si_falta)
 ORDER BY v.aplicada, v.migracion;
```

### D2 · Cobertura por RPC de venta (detecta el hueco `_v2` sin `25`)

```sql
SELECT p.proname,
       pg_get_function_identity_arguments(p.oid) AS args,
       p.prosrc LIKE '%fn_cantidad_en_base(%'                                                      AS m24,
       p.prosrc LIKE '%fn_rebalancear_presentaciones%'                                              AS m25,
       p.prosrc LIKE '%COALESCE(id_presentacion, 0) = COALESCE(v_producto_presentacion_id, 0)%'      AS m22,
       p.prosrc LIKE '%fn_descontar_venta_enrutada(%'                                                AS m10,
       md5(pg_get_functiondef(p.oid)) AS md5_def
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname='public' AND p.proname LIKE 'fn_registrar_venta%'
 ORDER BY 1;
```

### D3 · Localizar el caso del usuario (arroz moro / arroz / frijoles) y su catálogo real

```sql
-- D3.1 el/los elaborados
SELECT p.id, p.denominacion, p.id_tienda, p.modo_elaboracion, p.id_cocina, p.es_vendible
  FROM app_dat_producto p
 WHERE p.deleted_at IS NULL
   AND (p.es_elaborado OR p.es_servicio)
   AND (p.denominacion ILIKE '%moro%' OR p.denominacion ILIKE '%arroz%'
        OR p.denominacion ILIKE '%frijol%' OR p.denominacion ILIKE '%potaje%')
 ORDER BY p.id_tienda, p.id;
```

```sql
-- D3.2 receta + catalogo de presentaciones de cada ingrediente (con factor_rel)
SELECT e.id AS id_elaborado, e.denominacion AS elaborado, e.id_tienda,
       i.id_ingrediente, ing.denominacion AS ingrediente, i.cantidad_total_necesaria AS nee_base,
       pp.id AS fila_presentacion, np.denominacion AS presentacion,
       pp.cantidad AS cantidad_catalogo, pp.es_base, f.factor_rel
  FROM app_dat_producto e
  CROSS JOIN LATERAL fn_obtener_ingredientes_recursivos(e.id, 1) i
  JOIN app_dat_producto ing ON ing.id = i.id_ingrediente
  LEFT JOIN app_dat_producto_presentacion pp ON pp.id_producto = i.id_ingrediente
  LEFT JOIN app_nom_presentacion np ON np.id = pp.id_presentacion
  LEFT JOIN LATERAL fn_presentaciones_producto(i.id_ingrediente) f ON f.id_presentacion = pp.id
 WHERE e.es_elaborado AND e.deleted_at IS NULL
   AND e.id IN (<ids de D3.1>)
 ORDER BY e.id, i.id_ingrediente, pp.cantidad DESC;
```

🚩 **Qué mirar**: si una fila `Kilogramo`/`kg` tiene `cantidad_catalogo = 1` y su base `Gramo` también `cantidad = 1`, entonces `factor_rel = 1` → **el Kg se cuenta como 1 gramo**. Es la mina R11 y produciría un `hay 3`, no un `hay 3000`.

### D4 · Comparar las TRES mediciones del mismo ingrediente (físico / escalar vivo / base correcta)

```sql
WITH det AS (
  SELECT DISTINCT ON (ip.id_producto, la.id_almacen, ip.id_ubicacion,
                      COALESCE(ip.id_variante,0), COALESCE(ip.id_opcion_variante,0), COALESCE(ip.id_presentacion,0))
         ip.id_producto, la.id_almacen, ip.id_ubicacion, ip.id_presentacion, ip.cantidad_final
    FROM app_dat_inventario_productos ip
    JOIN app_dat_layout_almacen la ON la.id = ip.id_ubicacion
   WHERE la.deleted_at IS NULL AND ip.id_producto IN (<ids de ingredientes de D3.2>)
   ORDER BY ip.id_producto, la.id_almacen, ip.id_ubicacion,
            COALESCE(ip.id_variante,0), COALESCE(ip.id_opcion_variante,0), COALESCE(ip.id_presentacion,0), ip.id DESC
), vivos AS (SELECT * FROM det WHERE COALESCE(cantidad_final,0) > 0)
SELECT v.id_producto, p.denominacion, v.id_almacen, v.id_ubicacion, v.id_presentacion,
       f.nombre AS presentacion, f.factor_rel, f.es_base,
       v.cantidad_final AS saldo_fisico,
       round(v.cantidad_final * COALESCE(f.factor_rel,1), 3) AS equivalente_base,
       public.fn_stock_producto_almacen(v.id_producto, v.id_almacen) AS escalar_almacen,
       public.fn_stock_producto_almacen(v.id_producto, NULL)         AS escalar_toda_la_tienda
  FROM vivos v
  JOIN app_dat_producto p ON p.id = v.id_producto
  LEFT JOIN LATERAL fn_presentaciones_producto(v.id_producto) f ON f.id_presentacion = v.id_presentacion
 ORDER BY 1, 3, 4, 5;
```

🚩 **Cómo leerlo**
- `saldo_fisico` sin factor y `escalar_almacen` = **suma cruda** → **falta el `27`** (síntoma «hay 3000» mal medido).
- `escalar_almacen` correcto pero **menor** que `escalar_toda_la_tienda` → **multi-almacén** (síntoma §4.2: «hay 3000, faltan 2000» con 5000 en la tienda).
- `escalar_almacen` correcto e igual a la tienda, pero la app igual dice «insuficiente» → el problema es **cliente** (la app lee el saldo de una sola presentación), no SQL.

### D5 · Qué ve exactamente la validación hoy, por almacén de cada TPV

```sql
SELECT t.id AS id_tpv, t.denominacion AS tpv, t.id_almacen,
       public.fn_stock_producto_almacen(<id_ingrediente>, t.id_almacen) AS stock_almacen_tpv,
       public.fn_stock_producto_almacen(<id_ingrediente>, NULL)         AS stock_toda_la_tienda,
       public.fn_validar_ingredientes_elaborado(<id_elaborado>, 1, t.id_almacen) AS validar_1_unidad
  FROM app_dat_tpv t
 WHERE t.id_tienda = <id_tienda del elaborado>
 ORDER BY t.id;
```

### D6 · Simulador EXACTO del bucle de descuento (sin escribir nada)

```sql
-- Sustituir <id_ingrediente>, <id_almacen> y <necesidad_base>.
WITH RECURSIVE d AS (
  SELECT row_number() OVER (ORDER BY cantidad_final DESC, id_ubicacion) AS i,
         cantidad_final, id_presentacion, id_ubicacion
    FROM fn_stock_producto_almacen_detalle(<id_ingrediente>, <id_almacen>)
), s AS (
  SELECT i, cantidad_final, id_presentacion, id_ubicacion,
         <necesidad_base>::numeric AS pendiente_antes,
         LEAST(cantidad_final, <necesidad_base>::numeric) AS a_descontar
    FROM d WHERE i = 1
  UNION ALL
  SELECT d.i, d.cantidad_final, d.id_presentacion, d.id_ubicacion,
         s.pendiente_antes - s.a_descontar,
         LEAST(d.cantidad_final, s.pendiente_antes - s.a_descontar)
    FROM s JOIN d ON d.i = s.i + 1
)
SELECT s.i AS paso, f.nombre AS presentacion, s.cantidad_final AS saldo_fisico, f.factor_rel,
       s.pendiente_antes, s.a_descontar AS descuenta_el_bucle,
       s.pendiente_antes - s.a_descontar AS pendiente_despues,
       round(s.a_descontar * f.factor_rel, 3) AS base_realmente_consumida
  FROM s
  LEFT JOIN LATERAL fn_presentaciones_producto(<id_ingrediente>) f ON f.id_presentacion = s.id_presentacion
 ORDER BY s.i;
```

- Si la última `pendiente_despues` es **> 0** mientras `SUM(base_realmente_consumida)` ya cubre la necesidad → **el bucle va a fallar con «faltan N» y, aun así, dejar el estante en cero**. Es §4.3.

### D7 · ¿Existe ya el patrón de datos que dispara el bug?

```sql
SELECT count(*) AS filas_con_factor_no_1_y_saldo
  FROM app_dat_inventario_productos ip
  JOIN app_dat_layout_almacen la ON la.id = ip.id_ubicacion
  LEFT JOIN LATERAL fn_presentaciones_producto(ip.id_producto) f ON f.id_presentacion = ip.id_presentacion
 WHERE la.deleted_at IS NULL AND COALESCE(ip.cantidad_final,0) > 0
   AND COALESCE(f.factor_rel,1) <> 1;
```

### D8 · (Verificación de que la prueba no escribió nada)

Si en algún momento se ejecuta una RPC que escribe, hacerlo **solo** así y comprobar que el saldo quedó idéntico:

```sql
BEGIN;
  SELECT public.fn_descontar_ingredientes_elaborado(<id_elaborado>, 1, <id_almacen>);
ROLLBACK;

-- y DESPUÉS, comparar con la foto previa:
SELECT ip.id_producto, la.id_almacen, ip.id_ubicacion, ip.id_presentacion, ip.cantidad_final, ip.created_at
  FROM app_dat_inventario_productos ip
  JOIN app_dat_layout_almacen la ON la.id = ip.id_ubicacion
 WHERE ip.id_producto IN (<ids>) ORDER BY ip.id DESC LIMIT 20;
```

> En **producción** no ejecuté ninguna RPC que escribe: §4.2 y §4.3 son `SELECT` puros sobre los CTE de §7.2 y §7.4 más las funciones `STABLE` de lectura (`fn_stock_producto_almacen`, `fn_stock_producto_almacen_detalle`, `fn_validar_ingredientes_elaborado`, `fn_obtener_ingredientes_recursivos`, `fn_presentaciones_producto`). **No hubo `BEGIN/ROLLBACK` porque no hubo escritura que revertir.**

### D9 · Tabla síntoma ↔ migración faltante (para leer D1)

| Síntoma observado | Migración sospechosa | Cómo lo confirma D1/D4 |
|---|---|---|
| «pido 5000, **había 2000**, faltaban 3000» (o su espejo «había 3000, faltaban 2000») | **alcance**: multi-almacén / una sola presentación, **no** una migración | D4 `escalar_almacen < escalar_toda_la_tienda`; D5 por TPV; D10 `cantidad_disponible` de la validación |
| «había **2003**» en vez de 2000/3000 (un `+3` sospechoso) | **27** (`fn_stock_producto_almacen` suma físico sin factor) | D1 `27 = false`; D4 `escalar_almacen = Σ cantidad_final` cruda |
| El Kg se cuenta como 1 unidad (`hay 3` en vez de `hay 3000`) | **catálogo mal configurado** (R11) o **35** | D3.2 `cantidad_catalogo = 1` en Kg **y** en Gramo |
| «Vender 1 Caja descuenta la receta de 1 unidad» | **24** (falta `fn_cantidad_en_base`) | D1 `24 = false`; D2 `m24 = false` |
| «Vender 5 Unidades con solo Cajas falla» (no abre empaque) | **25** | D1 `25 = false`; D2 `m25 = false` (típico en `_v2`) |
| El saldo de una presentación salta solo / aparece stock de otra | **22** | D1 `22 = false` |
| La validación dice `success` y la venta falla con «faltan N» | **LEAST mixto** (no es migración) | D6 última `pendiente_despues > 0` con base consumida ≥ necesidad |
| Tras el fallo, el estante quedó en cero | **LEAST mixto + falta de transacción** | D6 `base_realmente_consumida` acumulada ≥ saldo total |

---

### D10 · Capturar la **respuesta cruda** para atribuir el mensaje (§4.6)

```sql
-- El/los TPV de la tienda del elaborado, y lo que ve el vendedor, tal cual.
SELECT t.id AS id_tpv, t.denominacion AS tpv, t.id_almacen,
       public.fn_disponibilidad_plato(<id_elaborado>, t.id)               AS disponibilidad,
       public.fn_validar_ingredientes_elaborado(<id_elaborado>, 1, t.id_almacen) AS validar_1u
  FROM app_dat_tpv t
 WHERE t.id_tienda = <id_tienda_del_elaborado>
 ORDER BY t.id;
```

🚩 **Cómo atribuir lo que vio el usuario** (comparar con §4.6):

| Lo que ve el usuario | De dónde viene | Comprobación en D10 |
|---|---|---|
| «había **2000**, faltaban **3000**» con pedido 5000 | `fn_validar_ingredientes_elaborado` | `validar_1u->>'cantidad_disponible' = 2000` (o el equivalente para la cantidad pedida) |
| «había **3000**, faltaban **2000**» | idem, otro reparto de almacenes | `cantidad_disponible = 3000` |
| `(faltan N)` con `movimientos` en la respuesta | `fn_descontar_ingredientes_elaborado` L85 | requiere que `validar_1u` haya dado `success` antes |
| «Stock insuficiente (disponible: …)» sin «ingrediente» | `fn_descontar_venta_enrutada` L95 (SKU propio) | el mensaje no trae `id_ingrediente` |
| Texto con formato propio que no aparece arriba | cliente Flutter | `disponibilidad->'ingredientes'` trae `stock_disponible` por ingrediente — comparar con D4 |

**Si `disponibilidad` da un `disponible` correcto (5000) pero la app igual bloquea**, entonces el defecto es **cliente** (la app lee el saldo de una sola presentación): eso lo cierra `dart-analyst`, no SQL.

## 10. Anexo — huellas `md5(pg_get_functiondef)` de producción

⚠️ El md5 incluye `SET search_path` y el formato exacto: sirve como **segunda comprobación**, no como prueba semántica. Los marcadores de §D1 son la comprobación primaria.

| Función | md5 en producción |
|---|---|
| `fn_descontar_ingredientes_elaborado` | `47be3a93f8d026eba2f5fbfc31b0cd4a` |
| `fn_descontar_venta_enrutada` | `d56b117f2c9307a8c6bfaac29ce5e1e8` |
| `fn_validar_ingredientes_elaborado` | `c23f85d245c97f89c33e508574fd1aa0` |
| `fn_stock_producto_almacen` | `ecad724f55e19af4eb21d4f73d4ccc61` |
| `fn_stock_producto_almacen_detalle` | `0c452407ab12122a5b8262efd05a51a9` |
| `fn_obtener_ingredientes_recursivos` | `953eabdde12f97b63657339ba0116cfc` |
| `fn_cantidad_en_base` | `8af1cc7f9c90cc52dc330207e6b0f7eb` |
| `fn_presentaciones_producto` | `4514c0e9667e3e472608b6dc8d2bd0c3` |
| `fn_presentaciones_producto_v2` | `dce860b00574524aea50cdaedc6f0388` |
| `fn_stock_saldos_presentacion` | `7619323274189428e7dd68bf5c08d478` |
| `fn_registrar_venta` | `371402e5622517270563ef7f73aa8bc3` |
| `fn_registrar_venta_mesa` | `74b4751f30a745a6c21f4b3b7334d3b8` |
| `fn_registrar_venta_v2` | `253d9d1636f252fe01108a7c52615180` |
| `fn_registrar_venta_mesa_v2` | `6d34466b5645dad1407cb8d104d40a9c` |
| `fn_disponibilidad_plato` | `fec1805ea0052fb3b4c3c5e0dbe6906e` |
| `fn_resolver_origen_venta` | `8172c183168bc9ade85d667fb675646a` |
| `fn_devolver_ingredientes_elaborado` | `7a4a71902aae6719bcac5513a3db9027` |
| `fn_descontar_con_rebalanceo` | `6f81fc122100b463b0f7e04bbcb5f865` |
| `fn_descontar_con_rebalanceo_almacen` | `d5740ca01bc2f846e94d0e35aacf03b2` |
| `fn_planificar_cumplimiento_presentaciones_v2` | `c061cdd43146d837c46ee17bb954aad9` |
| `fn_preview_cumplimiento_v2` | `2a67058d973c93e7925e294fdfe44ddd` |
| `fn_aplicar_cumplimiento_v2` | `96654b7d7b7ebb430a64ab5987fb5a29` |
| `fn_ejecutar_entrega_fisica_v2` | `9edf415b400a467a1d6627a628fd3376` |

---

## 11. `file:line` del repo local utilizado

| Afirmación | Referencia |
|---|---|
| Deuda anotada del `LEAST` mixto («el arreglo correcto es que pase por `fn_descontar_con_rebalanceo`») | `presentaciones_inventario/27_stock_almacen_en_base.sql:80-89` |
| `fn_stock_producto_almacen` en base, y por qué el detalle **no** se toca | `presentaciones_inventario/27_stock_almacen_en_base.sql:26-36, 95-119` |
| Censo equivocado («>1 presentación») vs correcto (`factor_rel <> 1`) | `presentaciones_inventario/27_stock_almacen_en_base.sql:73-77` |
| `fn_cantidad_en_base` + parche de venta; fallbacks de compatibilidad | `presentaciones_inventario/24_bom_cantidad_en_base.sql:41-60, 90-117, 126-173` |
| Los 3 productos elaborados que el `24` dejó fuera de riesgo (hoy siguen siéndolo) | `presentaciones_inventario/24_bom_cantidad_en_base.sql:25-36, 214-224` |
| `LEAST(v_ubic.cantidad_final, v_a_descontar)` comentado como «así su `cantidad_final` tiene que seguir siendo la cantidad física» | `presentaciones_inventario/27_stock_almacen_en_base.sql:31-32` |
| Venta: saldo por presentación (22) y su análisis del producto 217 | `presentaciones_inventario/22_venta_saldo_por_presentacion.sql:11-51` |
| Venta con rebalanceo (25): guardas y por qué la venta sí validaba | `presentaciones_inventario/25_venta_con_rebalanceo.sql:5-16, 19-46` |
| Helpers de lectura mixta y `fn_stock_saldos_presentacion` | `presentaciones_inventario/02_helpers_lectura_mixta.sql:71, 165` |
| Rebalanceo y `fn_descontar_con_rebalanceo[_almacen]` | `presentaciones_inventario/03_rebalanceo.sql:474, 589` |
| BOM por almacén (helpers cocina) | `funcionalidad_cocina/01_helpers_bom_almacen.sql` |
| Fix del descuento BOM por almacén | `funcionalidad_cocina/03_fix_descuento_bom_por_almacen.sql` |
| Devolución de BOM | `funcionalidad_cocina/05_helpers_devolucion_bom.sql` |
| Tandas con su propia copia del cálculo | `funcionalidad_cocina/21_tandas_produccion.sql` |
| App apuntando al proyecto debug | `ventiq_app/lib/config/supabase_config.dart:5` |

---

### Resumen ejecutivo (para el plan de correcciones)

1. **Los números que vio el usuario (5000 pedido · 2000 disponible · 3000 faltante, y su espejo 3000/2000) los produce la VALIDACIÓN, no el bucle**: `fn_validar_ingredientes_elaborado` L29 devuelve `cantidad_disponible = fn_stock_producto_almacen(ing, A)`, y la app resta `5000 − 2000 = 3000`. `disponible + faltante = requerido` en las dos tomas ⇒ **el cálculo mira una sola parte mientras el total es 5000**. Detalle y fórmulas de los dos escenarios (debug sin/con el `27`) en **§4.5**.
2. **Consecuencia de priorización:** el defecto de unidades mixtas (§4.3, real y grave) **no es lo que bloquea al usuario** — su mensaje `(faltan N)` sólo es alcanzable si la validación pasó (§4.6/§4.7). Lo que lo desbloquea es el **alcance** (medir el equivalente base de toda la tienda, o resolver bien el almacén). Arreglar sólo el `LEAST` **no** desbloquea la venta.
3. **El síntoma de alcance está medido al 100 % en producción** (§4.2): elaborado `240` con `disponible: 0, requerido: 1.0` mientras el ingrediente tiene 980 en la misma tienda. **36 elaborados en 8 tiendas** en esa situación (§7.4), con la tienda 25 en `0` producible.
4. **La «aleatoriedad» gramo/kg es determinista**: `fn_stock_producto_almacen_detalle` **L39** `ORDER BY v.cantidad_final DESC, v.id_ubicacion` ⇒ se consume primero la fila de **mayor número físico** (`argmax q_i`), y ese número se compara contra un pendiente en **base**. `fn_producir_tanda` L97 hace lo mismo con `LIMIT 1`. Fórmulas y tabla de casos en **§1.9** y **§4.7**.
5. **Dos `LEAST` mixtos** (`fn_descontar_ingredientes_elaborado:33`, `fn_descontar_venta_enrutada:118`). Hoy **latentes para elaborados** (§7.2: 0 elaborados con `factor_rel <> 1` y saldo) pero **se disparan en cuanto se configure un Kg en arroz/frijoles**; activos ya para SKU propio (§4.3: descuenta TODO el estante y reporta `faltan 932`).
6. **El consumo de receta nunca llama al rebalanceo**: `fn_descontar_ingredientes_elaborado` tiene 0 referencias a `fn_descontar_con_rebalanceo(_almacen)`. Por eso es **imposible abrir un empaque** al vender (§5.1 R3).
7. **Tres rutas de cocina no convierten la cantidad** (`fn_pedir_item_cuenta:85`, `fn_agregar_producto_orden_pendiente:137`, `fn_actualizar_cantidad_producto_orden:119`) y **`_v2` de venta no tiene el `25`** (§6).
8. **Arreglo in-place** para los dos `LEAST` (misma firma, mismo contrato `jsonb`); **`_v2`** para las rutas que cambian la semántica de entrada; **no tocar** firmas ni `fn_stock_producto_almacen_detalle`.
9. **El arreglo va a LOS DOS proyectos** (debug `qhprswhhfasrikhawjoz` y release `vsieeihstajlrdvpuooh`). Producción sirve de **referencia de estado esperado** (marcadores + md5 de §10); lo que le falta al debug se decide con **§9 D1/D2**, se confirma con **D4/D5/D6/D10** y se traduce a causa en **§D9**.