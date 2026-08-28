# Tutorial de pruebas · Inventario por presentación

Guía paso a paso para probar **todo** lo implementado en las fases 0–5 de
`docs/PLAN_PRESENTACIONES_INVENTARIO.md`, en las dos apps.
Cada paso dice qué hacer, qué debe pasar y cómo comprobarlo.

> **Antes de empezar, léete esto:**
> - Todo el SQL (`presentaciones_inventario/01`–`25`) está **aplicado en producción** y verificado.
> - La idea central: **el stock se guarda y se muestra por presentación**. «4 Cajas» y
>   «4 Unidades» son dos saldos distintos, no 52 unidades sueltas.
> - **Retrocompatibilidad**: la app vieja sigue funcionando. Donde el contrato tenía que
>   cambiar se crearon funciones nuevas (`get_product_movements_v4`, `obtener_ipv2`) y
>   las viejas quedaron intactas. §13 lo prueba.
> - Las apps **no se han compilado** en la sesión de desarrollo: solo `dart analyze`.
>   El §0 cubre el arranque.
> - Se encontraron **9 bugs de cálculo** que no eran parte del plan (valoración, resumen,
>   costo promedio, venta, BOM, ajuste, caché offline). Las secciones marcadas ⭐ los
>   prueban: son las que más importan.

---

## Estado real verificado

Medido contra producción (`vsieeihstajlrdvpuooh`) el día de escribir esto.

| Qué | Valor |
|-----|-------|
| Productos con presentaciones | **8.793** (8.905 filas) |
| Productos **multipresentación** | **94** ← los que este plan habilita |
| Productos de una sola presentación | **8.699** (no cambian en nada) |
| Presentaciones **congeladas** (con movimientos) | **7.498** |
| Bases con factor ≠ 1 | **131** ← por eso existe `factor_rel` |
| Funciones clave vivas | **9 / 9** ✅ |

### Las dos tiendas del tutorial

| | Tienda 11 | Tienda 47 |
|---|---|---|
| Nombre | Tienda La estrella | Mi Tienda |
| TPV | **18** — TPV La estrella | **56** — caja1 |
| Ubicación de trabajo | **37** «Área principal» (almacén 12) | **63** «pos» (almacén 59) |
| `permite_vender_aun_sin_disponibilidad` | **`true`** ← vende en negativo | **`false`** ← rechaza |
| Gerente (uuid) | `0a6886f2-ac36-416a-bfba-bd08d0671568` | `b12bb482-5119-4cc4-ae0a-a18bdc503edd` |

> ⚠️ **Las dos tiendas hacen falta.** La 11 tiene la bandera de vender en negativo
> encendida y la 47 no. La guarda 2 del `25` depende justo de eso, y solo se puede
> probar teniendo una de cada.

### Productos que se usan

| id | Producto | Tienda | Cadena de presentaciones | Saldo hoy |
|----|----------|--------|--------------------------|-----------|
| **217** | azúcar refino | 11 | **Bulto** 337 ×10 → **Bolsa** 336 ×1 (base) | 100 Bolsas, 0 Bultos (ubic. 37) |
| **1073** | ala | 47 | **Caja** 1191 ×24 → **Blister** 1190 ×12 → **Unidad** 1189 ×1 (base) | 2.400 Unidades (ubic. 63) |
| 1072 | malta | 47 | Caja 1188 ×40 → Blister 1187 ×6 → Unidad 1186 ×1 (base) | — |
| 219 | croqueta (elaborado) | 11 | Caja 340 ×24 → Unidad 339 ×1 (base) | receta: harina ×40 + sal ×10 |
| 4380 | Compresor Kia Picanto | 45 | **Unidad 4445 ×30, `es_base`** ← el factor de la base **no es 1** | 16 |
| 9635 | Pizza de Queso Gouda | 174 | **3 filas con `es_base = true`** ← el caso raro | 5 |
| 6841 | (valoración) | 189 | Bolsa 6946 (costo 186,64) · Bulto 6947 (costo 9,80) | 12 Bolsas |

El **1073 «ala»** es la estrella: cadena de **tres** niveles, en una tienda que **no**
permite vender en negativo. Con él se prueba el rebalanceo encadenado (§8).

---

## Índice

| § | Qué se prueba | App | Tiempo |
|---|---------------|-----|--------|
| 0 | Arranque y consultas de apoyo | ambas | 10 min |
| 1 | Fase 0 — cadena, saldos y texto mixto | SQL | 10 min |
| 2 | Fase 2 — captura mixta en el admin | admin | 25 min |
| 3 | Fase 2 — captura mixta en el vendedor | vendedor | 20 min |
| 4 | Fase 3 — kardex con presentación (v4) | admin | 15 min |
| 5 | ⭐ Fase 3 — stock, resumen y **valoración** | admin | 20 min |
| 6 | ⭐ Fase 3 — **costo promedio** e IPV | admin | 20 min |
| 7 | Fase 4 — TPV: carrito y diálogo de empaque | vendedor | 25 min |
| 8 | ⭐ Fase 4 — **la venta abre y arma empaques** | vendedor | 25 min |
| 9 | ⭐ Fase 4 — BOM de cocina y porciones | vendedor | 15 min |
| 10 | ⭐ Fase 5 — offline: deltas y fracciones | vendedor | 20 min |
| 11 | Fase 5 — conteo y ajuste por presentación | admin | 15 min |
| 12 | Congelado de factores (23001) y `es_base` | admin | 15 min |
| 13 | ⭐ No-regresión: la app vieja sigue viva | SQL | 20 min |
| 14 | Checklist final | — | — |

**Total ≈ 3 h 30 min** si se hace todo seguido. Cada sección es independiente salvo
que se diga lo contrario.

Hay un **apéndice al final** con las trampas de las firmas (parámetros invertidos,
columnas que no se llaman como parece). Si una prueba «sale vacía», mira ahí.

---

## Cómo verificar por SQL

Abre el **SQL Editor de Supabase** y ten estas tres consultas a mano. Se usan
constantemente.

**A · Saldos por presentación de un producto en una ubicación** — la más usada:

```sql
-- Firma: (p_id_producto, p_id_almacen, p_id_ubicacion, p_incluir_cero)
-- ⚠️ El 4.º parámetro es `p_incluir_cero`. Con `false` (el default) las
--    presentaciones en 0 NO salen. Para ver la cadena completa, pásalo en `true`.
SELECT s.id_presentacion,
       s.presentacion_nombre,
       s.factor_rel,
       s.es_base,
       s.nivel,
       s.saldo,
       s.equivalente_base
  FROM public.fn_stock_saldos_presentacion(217, NULL, 37, true) s
 ORDER BY s.nivel;
```

**B · El texto mixto que ve el usuario** (lo mismo que arma la app):

```sql
SELECT public.fn_stock_mixto_json(217, NULL, 37) AS mixto;
-- devuelve: desglose, equivalente_base, texto ("100 Bolsas"), texto_corto
```

**C · Las últimas filas del ledger de un producto** — para ver qué escribió una operación:

```sql
SELECT ip.id, ip.id_presentacion, np.denominacion AS pres,
       ip.cantidad_inicial, ip.cantidad_final,
       ip.origen_cambio, ip.id_conversion, ip.created_at
  FROM app_dat_inventario_productos ip
  LEFT JOIN app_dat_producto_presentacion pp ON pp.id = ip.id_presentacion
  LEFT JOIN app_nom_presentacion np ON np.id = pp.id_presentacion
 WHERE ip.id_producto = 217 AND ip.id_ubicacion = 37
 ORDER BY ip.id DESC
 LIMIT 10;
```

### Códigos que vas a ver

| Código | Qué significa | Dónde aparece |
|--------|---------------|---------------|
| `origen_cambio = 2` | recepción | ledger |
| `origen_cambio = 3` | venta | ledger |
| `origen_cambio = 8` | **conversión de presentación** | ledger |
| `origen_cambio = 20` | conversión (tipo de operación 20) | ledger |
| `id_conversion` no nulo | la fila es parte de una conversión | ledger |
| **23001** | factor congelado (la presentación ya tiene movimientos) | app |
| **22023** | `id_presentacion` inválido o de otro producto | app |
| **23503** | FK de `app_dat_precio_costo` | app |
| `INSUFFICIENT_STOCK_CONVERTIBLE` | no alcanza ni convirtiendo | venta / egreso |

> ⚠️ **Anota los ids que te devuelvan las operaciones** (recepción, venta, ajuste).
> El tutorial los llama `<ID_OPERACION>`, `<ID_CONVERSION>`, etc.

---

## § 0 · Arranque de las apps

Esto no se hizo en la sesión de desarrollo (solo `dart analyze`), así que es el primer
paso real.

### 0.1 Admin

```bash
cd ventiq_admin_app
flutter pub get        # ⚠️ pídelo tú: no se ejecutó en desarrollo
flutter run -d windows # o el dispositivo que uses
```

**Debe:** compilar y abrir. `dart analyze lib` daba **0 errores**.

### 0.2 Vendedor

```bash
cd ventiq_app
flutter pub get
flutter run
```

**Debe:** compilar y abrir. `dart analyze lib` daba **1 error preexistente y ajeno**:
`dart:js_util` en `utils/package_image_picker_web.dart`, que solo existe al compilar
para web. Si compilas para web, ese archivo ya estaba así antes de este trabajo.

### 0.3 Comprobar que las funciones nuevas están vivas

```sql
SELECT p.proname, pg_get_function_result(p.oid) AS devuelve
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_cantidad_en_base', 'fn_stock_mixto_almacen',
                     'get_product_movements_v4', 'obtener_ipv2',
                     'fn_preview_rebalanceo', 'fn_rebalancear_presentaciones',
                     'fn_descontar_con_rebalanceo', 'fn_presentacion_item_json',
                     'fn_presentaciones_producto_editable')
 ORDER BY 1;
```

**Debe:** devolver **9 filas**. Si falta alguna, el archivo correspondiente de
`presentaciones_inventario/` no se aplicó.

---

## § 1 · Fase 0 — La cadena, los saldos y el texto mixto

Solo SQL. Es la base de todo lo demás: si esto no cuadra, nada de la UI va a cuadrar.

### 1.1 La cadena de un producto de tres niveles

```sql
SELECT * FROM public.fn_presentaciones_producto(1073) ORDER BY nivel;
```

**Debe devolver 3 filas**, ordenadas de mayor a menor:

| id_presentacion | nombre | factor | factor_rel | es_base | nivel |
|---|---|---|---|---|---|
| 1191 | Caja | 24 | 24 | false | 1 |
| 1190 | Blister | 12 | 12 | false | 2 |
| 1189 | Unidad | 1 | 1 | **true** | 3 |

### 1.2 ⭐ El factor de la base **no** siempre es 1

Este es el caso que rompía el resumen de inventario (bug del `18`).

```sql
SELECT pp.id, np.denominacion, pp.cantidad AS factor, pp.es_base,
       f.factor_rel
  FROM app_dat_producto_presentacion pp
  JOIN app_nom_presentacion np ON np.id = pp.id_presentacion
  LEFT JOIN LATERAL (SELECT fr.factor_rel
                       FROM public.fn_presentaciones_producto(4380) fr
                      WHERE fr.id_presentacion = pp.id) f ON true
 WHERE pp.id_producto = 4380;
```

**Debe:** `factor = 30`, `es_base = true`, **`factor_rel = 1`**.

**Por qué importa:** el producto 4380 tiene 16 unidades en la tienda 45. Usando el
factor crudo (30) el resumen reportaba **480**. Con `factor_rel` reporta 16. Hay
**131 productos** con la base en factor ≠ 1.

> **Regla:** para equivalentes se usa **siempre `factor_rel`**, nunca `pp.cantidad`.

### 1.3 El caso raro: tres filas `es_base`

```sql
SELECT pp.id, np.denominacion, pp.cantidad, pp.es_base
  FROM app_dat_producto_presentacion pp
  JOIN app_nom_presentacion np ON np.id = pp.id_presentacion
 WHERE pp.id_producto = 9635 ORDER BY pp.id;
```

**Debe:** 4 filas, **tres con `es_base = true`** (9768, 10674, 10695).

```sql
SELECT * FROM public.fn_presentaciones_producto(9635) WHERE es_base;
```

**Debe:** la cascada elige **una sola** (la 9768). No falla, no duplica.

**Por qué importa:** un `firstWhere(es_base)` en Dart reventaba con este producto, y
un `LEFT JOIN ... ON id_producto` multiplicaba las filas de inventario por 3 —
reportaba **15 donde hay 5**.

### 1.4 Saldos y texto mixto

```sql
-- Con incluir_cero = true salen las 2 presentaciones; con false, solo la que tiene saldo.
SELECT s.id_presentacion, s.presentacion_nombre, s.saldo, s.nivel, s.equivalente_base
  FROM public.fn_stock_saldos_presentacion(217, NULL, 37, true) s ORDER BY s.nivel;

SELECT public.fn_stock_mixto_json(217, NULL, 37);
```

**Debe:** con `true`, **2 filas** (Bolsa 100 / Bulto 0); con `false`, **1 fila** (solo la
Bolsa). El texto mixto es **`"100 Bolsas"`**, `texto_corto` **`"100 BOL"`** y
`equivalente_base = 100`.

**Por qué el default es `false`:** el desglose que ve el usuario no debe listar
presentaciones vacías — «100 Bolsas + 0 Bultos» es ruido. Para auditar la cadena
completa se pide `true` explícitamente.

### 1.5 El plural lo sabe el SQL

```sql
SELECT public.fn_plural_presentacion('Bolsa', 1)  AS una,
       public.fn_plural_presentacion('Bolsa', 5)  AS varias,
       public.fn_fmt_cantidad(4.0)                AS entero,
       public.fn_fmt_cantidad(4.5)                AS fraccion,
       public.fn_fmt_cantidad(NULL)               AS nulo;
```

**Debe:** `Bolsa` / `Bolsas` / `4` / `4.5` / `0`.

**Por qué importa:** los mensajes al usuario los arma el servidor a propósito. El
plural de las presentaciones tiene irregularidades del nomenclador y duplicar esa
lógica en Dart es pedir que se desincronice. Los formatters de Dart
(`StockMixtoFormatter`, `FormatoPresentacion`) **replican** este comportamiento y
tienen tests de paridad (32 y 22 casos, todos verdes).

---

## § 2 · Fase 2 — Captura mixta en el admin

App **admin**, tienda 11. Aquí se prueba que una operación con varias presentaciones
guarda **una línea por presentación**, sin aplanar.

### 2.1 Recepción mixta

1. Inventario → **Recepción**.
2. Zona: **Área principal** (ubicación 37).
3. Producto: **azúcar refino** (217).

**Debe aparecer** el widget de captura mixta con **un campo por presentación**:
`Bulto` y `Bolsa`. Si el producto tuviera una sola presentación, aparecería el campo
único de siempre.

4. Escribe **2** en Bulto y **5** en Bolsa.
5. Precio: **un precio por presentación** (el Bulto vale ~10× la Bolsa).
6. Registra.

**Verifica** con la consulta **C**:

```sql
-- Debe haber DOS filas nuevas con origen_cambio = 2 (recepción):
--   id_presentacion 337 (Bulto): cantidad_final = 2
--   id_presentacion 336 (Bolsa): cantidad_final = 105
```

**Debe:** dos filas, cada una con **su** `id_presentacion`. **No** debe haber una sola
fila de 25 Bolsas (2×10 + 5). Eso es exactamente lo que se eliminó en Fase 1.

> ⚠️ Si ves una sola fila con el total aplanado, el `06` no está aplicado.

### 2.2 El equivalente se muestra en la misma línea

En la pantalla, cada línea capturada debe mostrar la cantidad **y** su equivalente:

```
2 Bultos + 5 Bolsas  ·  = 25 Bolsas
```

**Criterio del plan:** siempre mixto **y** equivalente en la misma línea. El usuario
tiene que poder ver las dos lecturas sin cambiar de pantalla.

### 2.3 Extracción con rebalanceo (el aviso, no el bloqueo)

1. Inventario → **Extracción**, zona 37, producto 217.
2. Pide **3 Bultos** cuando solo hay 2.

**Debe:** la pantalla **avisa** que el servidor puede abrir empaques, pero **no
bloquea** el botón. La validación real es del servidor.

**Por qué:** validar en el cliente rechazaría movimientos que el servidor **sí** puede
cumplir abriendo un empaque mayor. El cliente no conoce el saldo completo de la cadena.

3. Registra y mira el ledger (consulta **C**).

**Debe:** aparecen filas de conversión (`origen_cambio` 8 o 20, con `id_conversion`)
**antes** de la fila de extracción.

### 2.4 Transferencia: 2 cajas llegan como 2 cajas

Este es el **criterio central** del plan.

1. Inventario → **Transferencia**. Origen: zona 37. Destino: zona **41** «Cuarentena».
2. Producto 217, **2 Bultos**.
3. Registra.

**Verifica el destino:**

```sql
SELECT * FROM public.fn_stock_saldos_presentacion(217, NULL, 41, true);
```

**Debe:** el destino tiene **2 Bultos**. **No** 20 Bolsas.

> Si el destino muestra 20 Bolsas, el `07` no está aplicado. Esta es la prueba que
> mejor resume para qué existe todo el plan.

### 2.5 Ajuste por presentación

1. Inventario → **Ajuste** (faltante o sobrante).
2. Zona 37, producto 217.

**Debe:** abrir **un diálogo por cada presentación** con saldo, y en cada uno mostrar
el **desglose mixto completo de la zona**.

**Por qué:** ajustar una presentación a ciegas es la vía rápida a un descuadre. Si hay
4 Bultos además de las 100 Bolsas, el operador necesita verlo antes de decidir.

3. Ajusta la Bolsa y confirma.

**Debe:** `status: success`. **Si sale «id_presentacion 0 no existe» (22023)**, el fix
de Fase 5 no está en el binario que estás corriendo.

### 2.6 ⚠️ La lista de Operaciones NO muestra la presentación (pendiente)

Inventario → **Operaciones**. Abre la recepción de §2.1.

**Lo que verás:** cada línea muestra `cantidad`, `precio_unitario`, `sku_producto` y
`producto_nombre`, **sin presentación**. Dos líneas del mismo producto —una de Bultos y
otra de Bolsas— se leen idénticas salvo por el número.

**Por qué:** `fn_listar_operaciones_inventario_new` **no se tocó en este trabajo**.
Compruébalo:

```sql
SELECT (SELECT count(*) FROM regexp_matches(p.prosrc, 'id_presentacion', 'g')) AS menciona_presentacion,
       length(p.prosrc) AS tamano
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'fn_listar_operaciones_inventario_new';
```

**Debe:** `menciona_presentacion = 0` sobre ~32.800 caracteres. Es una función grande que
arma su `detalles` jsonb por tipo de operación (venta, recepción, extracción,
transferencia…), así que añadir la presentación implica tocar cada rama.

**Queda como pendiente.** El detalle por presentación sí está disponible hoy en el
**kardex** (§4) y en el **stock** (§5), que son las pantallas donde se consulta un
producto concreto.

---

## § 3 · Fase 2 — Captura mixta en el vendedor

App **vendedor** (`ventiq_app`), tienda 11. Las pantallas de admin del vendedor
(recepción, extracción, transferencia, ajuste, venta por acuerdo).

### 3.1 Funciona SIN conexión

**Pon el dispositivo en modo avión** antes de empezar.

1. Menú admin → **Recepción**.
2. Producto 217.

**Debe:** aparecer la captura mixta igual que online.

**Por qué importa:** la cadena se resuelve desde el **caché** con
`PresentacionCadenaLocal`, que replica la cascada de `fn_presentaciones_producto`.
Esta app es offline-first y el vendedor mueve mercancía sin conexión: pedirle la cadena
al servidor no era opción.

### 3.2 Producto sin cadena en caché → campo único

Busca un producto que no tenga presentaciones cacheadas (o uno de una sola).

**Debe:** el widget lo avisa y aparece el **campo único** de siempre. Se manda
`id_presentacion: null` y **el servidor resuelve la base**.

> ⚠️ Nunca debe mandar `?? 1` ni `?? 0`. El 1 es el id del nomenclador (otro producto)
> y el 0 no existe: los dos dan **22023**.

### 3.3 El ajuste del vendedor lleva dropdown, no captura mixta

Menú admin → **Ajuste**, producto 217.

**Debe:** un **dropdown** de presentación + un campo de cantidad, con la unidad
etiquetada. **No** captura mixta.

**Por qué (decisión 18 del plan):** un ajuste es *«esta presentación tiene esta
cantidad»*, una afirmación sobre un saldo concreto. Capturar varias a la vez invita a
setear todo el producto de golpe, que es otra operación.

### 3.4 ⭐ Venta por acuerdo (la cuarta ruta de venta)

Menú admin → **Venta por acuerdo**.

1. Producto 217.

**Debe:** captura mixta (antes mandaba **siempre `null`** en `id_presentacion`, así que
toda venta por acuerdo caía a la base sin importar lo que se vendiera).

2. Pon **1** en Bulto y mira el precio de la línea.

**Debe:** el precio del Bulto es **el del catálogo × 10** (el factor). En la lista se
lee «1 Bulto x $…».

**Por qué importa:** el precio del catálogo es **por unidad base**. Sin multiplicar por
el factor, una Caja se vendería al precio de una Unidad — un agujero de caja, no solo
de inventario.

### 3.5 Las líneas se distinguen entre sí

Agrega **1 Bulto** y **3 Bolsas** del mismo producto.

**Debe:** las dos líneas se leen distintas («1 Bulto», «3 Bolsas»). Sin la
presentación en el subtítulo, dos líneas del mismo producto se veían idénticas.

---

## § 4 · Fase 3 — Kardex con presentación

App **admin**. El kardex se resolvió como **función nueva `get_product_movements_v4`**;
la v3 quedó intacta para la app en producción.

### 4.1 La fila muestra la presentación

Producto → **Movimientos** (kardex) del producto 217.

**Debe:** la columna de cantidad dice **«2 Bultos»**, no «2.00».

### 4.2 El detalle muestra el factor solo si ≠ 1

Toca una fila.

**Debe:** `Presentación: Bulto (= 10 base)`. En una fila de Bolsa (factor 1) el
paréntesis **no** aparece.

**Por qué:** «(= 1 base)» es ruido. El factor se muestra solo cuando aporta.

### 4.3 ⭐ Una conversión NO es un «Reajuste de cancelación»

Busca en el kardex una fila de las conversiones que generaste en §2.3.

**Debe:** tipo de movimiento **«Conversión»**, en **índigo**, con icono `unfold_more`.

**El bug que esto arregla:** el `CASE` de `tipo_movimiento` no contemplaba
`id_conversion`, y el brazo de cancelaciones era el `ELSE` de facto — así que **abrir
una caja se mostraba como una corrección de error**. Un movimiento perfectamente normal
aparecía como si alguien hubiera metido mal los datos.

### 4.4 Los totales de la exportación van en equivalente base

Exporta el kardex a **Excel** y a **PDF**.

**Debe:**
- la celda de cantidad dice «2 Bultos»
- el pie dice **`Entradas: X u. base`**

**Por qué:** sumar «4 cajas + 4 unidades = 8» es falso. Los totales solo tienen
sentido en una unidad común, y esa es el equivalente base.

### 4.5 No-regresión: la v3 sigue devolviendo lo mismo

```sql
-- ⚠️ El orden de los dos últimos parámetros es (p_offset, p_limit), NO (limit, offset).
--    Con (100, 0) sale limit 0 → 0 filas y la prueba parece vacía.
SELECT count(*) AS filas,
       bool_and(v3.cantidad = v4.cantidad
                AND v3.tipo_operacion IS NOT DISTINCT FROM v4.tipo_operacion) AS compatible
  FROM public.get_product_movements_v3(217, NULL, NULL, NULL, NULL, 0, 100) v3
  JOIN public.get_product_movements_v4(217, NULL, NULL, NULL, NULL, 0, 100) v4
    ON v4.id = v3.id;
```

**Debe:** `filas = 26`, `compatible = true` — comprobado al escribir este tutorial. La
v4 solo **añade** `id_presentacion`, `presentacion_nombre`, `presentacion_factor`,
`cantidad_formateada` y `es_conversion`.

---

## § 5 · ⭐ Fase 3 — Stock, resumen y valoración

Esta sección prueba **tres bugs de cálculo** que llevaban meses dando números falsos.
Es la más importante del tutorial.

### 5.1 El listado muestra la presentación, no «unidades»

Inventario → **Stock**. Busca el producto 217.

**Debe:** decir «100 Bolsas», no «100 unidades». Seis sitios de esa pantalla escribían
«unidades» en duro.

### 5.2 ⭐ Bug 1 — el factor de la base inflaba el equivalente

```sql
-- Producto 4380, tienda 45: 16 en almacén. La base tiene factor 30.
-- Columnas reales: prod_id, prod_nombre, cant_unidades_base, cant_almacen_total.
SELECT r.prod_id, r.prod_nombre, r.cant_unidades_base, r.cant_almacen_total,
       r.presentaciones_count
  FROM (SELECT set_config('request.jwt.claims',
          json_build_object('sub','7e3507ec-1b29-4901-bf88-e5d77be72100',
                            'role','authenticated')::text, true) c) s,
       LATERAL public.fn_inventario_resumen_por_usuario_almacen2(
         45, NULL, 'Compresor Kia Picanto 2017', true, 'Todos', 20, 1) r;
```

**Debe:** el `prod_id 4380` sale con **16.000** en las dos columnas, no 480.

> Salen **dos** filas porque hay dos productos con el mismo nombre (4380 y 2329). Mira
> el `prod_id`, no el nombre.

**El bug:** el CTE `presentacion_base` tomaba `pp.cantidad` de la fila `es_base` como si
siempre fuera 1. Con la base en factor 30, 16 unidades se reportaban como **480**.
Había **30 productos con stock** en esa situación.

### 5.3 ⭐ Bug 2 — el JOIN multiplicaba las filas

```sql
-- Producto 9635 (el de las 3 filas es_base). Tiene 5 unidades reales.
SELECT r.prod_id, r.prod_nombre, r.cant_unidades_base, r.cant_almacen_total
  FROM (SELECT set_config('request.jwt.claims',
          json_build_object('sub','ef045859-8741-44a0-99da-999e5392e09e',
                            'role','authenticated')::text, true) c) s,
       LATERAL public.fn_inventario_resumen_por_usuario_almacen2(
         174, NULL, 'Pizza de Queso Gouda', true, 'Todos', 20, 1) r;
```

**Debe:** **5.000**, no 15. Comprobado al escribir este tutorial.

**El bug:** el `LEFT JOIN ... ON id_producto` casaba cada fila de inventario con las
**tres** filas `es_base`, y el `SUM` las contaba todas. Y esto inflaba
`cant_almacen_total`, que es la cantidad **física** — no solo un equivalente.

> El `DO` block del `18` **aborta si no parchea las dos ramas** de la función (tiene el
> bloque duplicado con-almacén / sin-almacén). Parchear una sola dejaba el bug vivo al
> filtrar por almacén.

### 5.4 ⭐ Bug 3 — el 88 % del inventario estaba mal valorado

El más caro de los tres.

```sql
-- Producto 6841, tienda 189: 12 Bolsas.
--   Bolsa (fila 6946) cuesta 186,64
--   Bulto (fila 6947) cuesta   9,80
SELECT v.id_presentacion, v.cantidad,
       v.precio_costo_usd, v.valor_costo_usd,
       v.precio_costo_cup, v.valor_costo_cup
  FROM public.fn_inventory_valuation_rows(189) v
 WHERE v.id_producto = 6841;
```

**Debe:** las filas salen con `id_presentacion = 6946` (la **Bolsa**) y
`precio_costo_usd = 186.64`. La de 12 unidades da **`valor_costo_usd = 2239.68`**.
Antes daba **117,60** (12 × 9,80, el costo del **Bulto**).

> Ojo con los nombres de columna: son `precio_costo_usd` / `valor_costo_usd` (y sus
> gemelas `_cup`), no `costo_unitario` / `valor_total`.

**El bug:** choque de nombres. `app_dat_producto_presentacion.id` es la **fila**
(producto + presentación + factor, lo que el ledger guarda en `id_presentacion`), y
`app_dat_producto_presentacion.id_presentacion` es la **FK al nomenclador** (1=Unidad,
3=Caja…). El JOIN de costo comparaba **nomenclador (1..20) contra fila (miles)**:

```
0 de 6.647 filas casaban
```

Y siendo `LEFT JOIN` no fallaba: **todo** caía al fallback «cualquier presentación del
producto, la más reciente por `created_at`» — y como las presentaciones se crean juntas,
ese `created_at` es idéntico, así que `DISTINCT ON` elegía **una arbitraria**.

**5.861 de 6.647 filas con stock mal valoradas: el 88 %.**

Por qué llevaba tanto tiempo oculto: el error es **asimétrico**. El producto 4485 pasaba
de 0,0525 a 0,048 — el valor *baja* un poco. Números plausibles, no absurdos. Nadie
mira una valoración y piensa «esto está 19× mal» cuando el total parece razonable.

### 5.5 La corrección aplica a toda la pantalla

```sql
SELECT p.proname
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.prosrc LIKE '%fn_inventory_valuation_rows%'
 ORDER BY 1;
```

**Debe:** las tres funciones de la pantalla de valoración
(`fn_warehouses_valuation_summary`, `fn_warehouse_valuation_zones`,
`fn_zone_valuation_products`). Todas heredan el arreglo.

### 5.6 Las 6 filas con presentación de otro producto

```sql
-- Filas de inventario cuyo id_presentacion pertenece a OTRO producto.
SELECT ip.id_producto, p.denominacion, ip.id_presentacion,
       pp.id_producto AS producto_de_la_presentacion
  FROM app_dat_inventario_productos ip
  JOIN app_dat_producto_presentacion pp ON pp.id = ip.id_presentacion
  JOIN app_dat_producto p ON p.id = ip.id_producto
 WHERE pp.id_producto <> ip.id_producto
 LIMIT 10;
```

**Debe:** aparecer el producto **4720 «Pqt Pechuga De Pollo 2 Kg»** apuntando a una
presentación del **4623 «BLOWER FAN Peugeot 206»**. Son **6 filas** de datos sucios.

El JOIN de costo lleva `AND lc.id_producto = li.id_producto` justo por esto: sin esa
condición, esas filas heredarían el costo de un producto ajeno. Con ella caen al
fallback de **su** producto. Verificado: 4720 sigue en 9,39 y 3046 en 17,329.

### 5.7 Los 14 productos sin costo en su presentación

```sql
-- V5 del archivo 19: dato sucio, no un bug de lógica.
SELECT ip.id_producto, p.denominacion, ip.id_presentacion, ip.cantidad_final
  FROM app_dat_inventario_productos ip
  JOIN app_dat_producto p ON p.id = ip.id_producto
  JOIN app_dat_producto_presentacion pp ON pp.id = ip.id_presentacion
 WHERE ip.cantidad_final > 0
   AND COALESCE(pp.precio_promedio, 0) = 0
 LIMIT 25;
```

**Debe:** unas **20 filas / 14 productos**. Estos siguen dependiendo del fallback.
**No es lógica: es dato.** Hay que cargar el costo en la presentación donde está el
stock. Queda anotado como pendiente.

---

## § 6 · ⭐ Fase 3 — Costo promedio e IPV

### 6.1 ⭐ La RPC del costo promedio fallaba en el 100 % de las llamadas

Esto llevaba meses roto sin que nadie lo notara.

```sql
-- Antes del arreglo, CUALQUIER llamada devolvía esto:
--   success = false
--   mensaje = 'column reference "cantidad" is ambiguous'
SELECT * FROM public.fn_actualizar_precio_promedio_recepcion_v2(
  999999999,
  jsonb_build_array(jsonb_build_object(
    'id_presentacion', 6946, 'precio_unitario', 200, 'cantidad', 3))
);
```

**Debe:** `success = true`.

**Dos capas de silencio lo tapaban:**
1. El `EXCEPTION WHEN OTHERS` de la RPC convertía el fallo en `success = false` con
   mensaje, no en una excepción.
2. El Dart leía `resultRow['message']` y `resultRow['tiempo_ejecucion_ms']` — nombres
   que **no existen** en el `RETURNS TABLE` (son `mensaje` y `tiempo_ms`). El log decía
   siempre «Sin mensaje» y 0 ms.

Un fallo permanente disfrazado de aviso.

**Y había un cálculo duplicado:** el mismo promedio se hacía **dos veces**, en Dart y en
la RPC. La versión Dart era la que realmente escribía, y ponderaba cantidades de
presentaciones distintas como si fueran la misma unidad. Se eliminó; ahora delega en el
servidor.

### 6.2 El costo se escribe en la presentación BASE

Haz una recepción mixta del producto 217 (§2.1) con precios distintos por presentación.

```sql
SELECT pp.id, np.denominacion, pp.precio_promedio
  FROM app_dat_producto_presentacion pp
  JOIN app_nom_presentacion np ON np.id = pp.id_presentacion
 WHERE pp.id_producto = 217;
```

**Debe:** el `precio_promedio` cambió en la fila **336 (Bolsa, la base)**. La 337
(Bulto) **no se toca**.

Ensayo de desarrollo con el 6841: 14 Bolsas a 186,64 + 2 Bultos a 100 (= 20 Bolsas a
10) → **10,6667** en la fila base, exacto.

### 6.3 No mete filas espurias en el historial de costo

Recibe **al mismo precio** que ya tiene el producto.

```sql
SELECT count(*) FROM app_dat_precio_costo;   -- antes y después
```

**Debe:** **+0 filas**. El costo no se movió, así que no hay nada que historiar.

**El bug que esto tuvo (mío, al escribir el `20`):** la guarda era
`WHERE COALESCE(precio_promedio, -1) <> v_costo_nuevo`, y `precio_promedio` es **`real`**
(float4) mientras `v_costo_nuevo` es `numeric`. Postgres promociona a numeric y
`61.8971 <> 61.89710000000000001` es **siempre TRUE** — la guarda no filtraba nada.
Dos llamadas idénticas metían **dos** filas. Corregido con `::real`.

### 6.4 Cuántos costos son inconsistentes hoy

```sql
WITH c AS (
  SELECT pp.id_producto, pp.id, pp.precio_promedio, f.factor_rel,
         pp.precio_promedio / NULLIF(f.factor_rel, 0) AS costo_por_base
    FROM app_dat_producto_presentacion pp
    CROSS JOIN LATERAL public.fn_presentaciones_producto(pp.id_producto) f
   WHERE f.id_presentacion = pp.id
     AND COALESCE(pp.precio_promedio, 0) > 0
     AND pp.id_producto IN (SELECT id_producto FROM app_dat_producto_presentacion
                             GROUP BY 1 HAVING count(*) > 1))
SELECT count(DISTINCT id_producto) AS productos_multi_con_costo,
       count(DISTINCT id_producto) FILTER (
         WHERE id_producto IN (
           SELECT id_producto FROM c GROUP BY id_producto
            HAVING max(costo_por_base) / NULLIF(min(costo_por_base),0) > 2)
       ) AS con_desvio_mayor_a_2x
  FROM c;
```

**Debe:** unos **40 productos** con costo, de los cuales **~21 inconsistentes** y
**~11 con desvío mayor a 2×**. Ejemplo extremo: el 6841, Bulto a 9,80 (= 0,98 por
Bolsa) contra Bolsa a 186,64 — factor **190×**.

Esto es **dato histórico**, no un bug de la fórmula nueva. Se corrige recibiendo o
ajustando el costo.

### 6.5 IPV con presentación (`obtener_ipv2`)

Reportes → **IPV**.

**Debe:** la columna **UM** muestra la presentación de la fila, con el factor cuando
≠ 1: **`Caja ×12`**. En pantalla, PDF y Excel.

### 6.6 Los totales del IPV van en equivalente base

**Debe:** el pie suma en **equivalente base**, no cantidades crudas.

**Por qué:** en la tienda 165, sumar 1.667 **Cajas** del producto 4502 con 794
**Unidades** del 4485 daba un total que no es ninguna cantidad real.

### 6.7 No-regresión de `obtener_ipv`

```sql
-- ⚠️ Hay que casar también por UBICACIÓN y cantidad_inicial. Casar solo por
--    (id_producto, nombre_producto) cruza en aspa las filas que un mismo producto
--    tiene en ubicaciones distintas y da diferencias FALSAS.
SELECT count(*) AS filas,
       count(*) FILTER (WHERE v1.cantidad_final IS DISTINCT FROM v2.cantidad_final) AS dif_cant,
       count(*) FILTER (WHERE v1.costo_inventario_usd IS DISTINCT FROM v2.costo_inventario_usd) AS dif_costo,
       count(*) FILTER (WHERE v1.cantidad_ventas IS DISTINCT FROM v2.cantidad_ventas) AS dif_ventas
  FROM public.obtener_ipv(189, NULL, NULL, NULL, false) v1
  JOIN public.obtener_ipv2(189, NULL, NULL, NULL, false) v2
    ON v2.id_producto = v1.id_producto
   AND v2.nombre_producto = v1.nombre_producto
   AND COALESCE(v2.id_ubicacion, 0)      = COALESCE(v1.id_ubicacion, 0)
   AND COALESCE(v2.cantidad_inicial, 0)  = COALESCE(v1.cantidad_inicial, 0);
```

**Debe:** `dif_cant = 0`, `dif_costo = 0`, `dif_ventas = 0`. Comprobado al escribir este
tutorial en la tienda 189 (**6 filas en las dos funciones**). En la verificación de
desarrollo, sobre 4 tiendas: **1.189 filas, 0 diferencias**.

Y comprueba que ninguna función pierde filas:

```sql
SELECT (SELECT count(*) FROM public.obtener_ipv(189, NULL, NULL, NULL, false))  AS v1,
       (SELECT count(*) FROM public.obtener_ipv2(189, NULL, NULL, NULL, false)) AS v2;
```

**Debe:** los dos números iguales.

### 6.8 Dos límites conocidos del IPV (no son bugs)

**a) Rotación y días de inventario no son interpretables en productos partidos.**
Al agrupar por presentación, un producto comprado en Cajas y vendido en Unidades sale
en **dos filas**: una con todo el stock y 0 ventas, otra con las ventas y 0 stock. Como
`rotacion = stock / ventas` se calcula dentro de la fila, en una el numerador es 0 y en
la otra el denominador.

```sql
-- Caso real: CALDO SABOR CARNE
SELECT nombre_producto, cantidad_final, cantidad_ventas, rotacion_anual
  FROM public.obtener_ipv2(165, NULL, NULL, NULL, false)
 WHERE nombre_producto ILIKE '%CALDO SABOR CARNE%';
```

**Debe:** `(Paquete)` con stock 0 / ventas 18, y `(Unidad)` con stock 794 / ventas 52.
Con `equivalente_base` la app **puede** sumar las filas del producto; decidirlo en SQL
obliga a elegir si el IPV se reporta por presentación o por producto, y hoy se usa para
las dos cosas.

**b) 514 productos con stock y costo 0.** El CTE de costo del IPV solo lee recepciones
con precio > 0, así que el stock que entró por conteo inicial o importación no tiene
costo ahí — aunque sí lo tenga en `precio_promedio`. Explica por qué IPV y valoración
pueden discrepar para el mismo producto.

---

## § 7 · Fase 4 — TPV: el carrito y el diálogo de empaque

App **vendedor**, tienda 11, TPV 18. Aquí empieza lo que ve el cajero.

### 7.1 ⭐ El carrito ya NO aplana a unidades base

Este es el cambio central de la Fase 4.

1. Abre el TPV y busca **azúcar refino** (217).
2. Elige la presentación **Bulto** y cantidad **2**.
3. Agrégalo al carrito.

**Debe:** la línea dice **«2 Bultos»**, y el precio unitario es el de la Bolsa × 10.

**Verifica el importe:** el total de la línea **no cambia** respecto a antes. Antes se
mandaba `2 × 10 = 20` unidades a precio de Bolsa; ahora `2` Bultos a precio de Bulto.
Es el mismo producto de los dos números.

> ⚠️ Si la línea dice «20» en vez de «2 Bultos», estás corriendo un binario viejo.

### 7.2 Cobra y comprueba el ledger

Cobra la venta y mira el ledger (consulta **C**):

**Debe:** la fila de venta tiene `id_presentacion = 337` (Bulto) y `cantidad = 2`.
**No** una fila de 20 Bolsas.

**Por qué importa:** el ledger es la fuente de verdad del kardex, del IPV y de la
valoración. Si la venta aplana ahí, todo lo de la Fase 3 se queda sin datos que leer.

### 7.3 Hay DOS rutas de venta, prueba las dos

El TPV tiene dos pantallas distintas y **las dos** aplanaban:

1. **Detalle de producto** (`product_details_screen`) — la ruta normal.
2. **Modo fluido** (`fluid_product_details_widget`) — la venta rápida.

**Debe:** las dos guardan la presentación. Repite §7.1 y §7.2 en modo fluido.

> Si solo se hubiera arreglado la primera, el modo fluido seguiría guardando unidades
> base **en silencio**.

Y cada una tiene rama **con** y **sin** variantes: si el producto tiene variantes,
pruébalo también con una.

### 7.4 ⭐ El diálogo de empaque (Fase 4.1)

Producto 217 en la ubicación 37: hay **100 Bolsas y 0 Bultos**.

1. Elige **Bulto**, cantidad **1**.
2. Agrégalo al carrito.

**Debe aparecer un diálogo** con este texto exacto:

```
Faltan 1 Bulto. ¿Armar 1 Bulto con 10 Bolsas?
```

3. Confirma.

**Debe:** el ítem entra al carrito.

**Cuándo se consulta:** **antes** de tocar el carrito. Con cocina activa
`addItemToCurrentOrder` ya descuenta inventario, así que preguntar después sería
preguntar por algo ya hecho.

### 7.5 Cuando alcanza, no molesta

Elige **Bolsa**, cantidad **5** (hay 100).

**Debe:** **ningún diálogo**. El ítem entra directo.

```sql
SELECT public.fn_preview_rebalanceo(217, 37, 336, 5) ->> 'mensaje_usuario' AS msg,
       public.fn_preview_rebalanceo(217, 37, 336, 5) ->> 'estrategia'     AS estrategia;
```

**Debe:** `msg = NULL`, `estrategia = ninguna`. El servidor decide cuándo hay algo que
avisar; la app no adivina.

### 7.6 Cuando es imposible, lo dice con números

Elige **Bulto**, cantidad **99999**.

**Debe:**

```
No alcanza: se piden 99999 Bultos y como máximo se pueden servir 10.
```

**Debe:** el ítem **no** entra al carrito.

### 7.7 «No volver a preguntar» NO silencia la falta de stock

1. En el diálogo de §7.4, marca **«no volver a preguntar»** y confirma.
2. Repite §7.4 → **no** debe preguntar (abre el empaque directo).
3. Repite §7.6 (99999) → **sí** debe avisar.

**Por qué:** esa casilla silencia la confirmación de *abrir empaques*, que es una
operación normal. La *falta de stock* es información que el cajero necesita siempre.

### 7.8 La preferencia es por TPV, no global

La casilla de §7.7 se guarda **por TPV**.

**Por qué:** una clave global apagaría el aviso en todos los mostradores de la cadena
porque un cajero lo marcó una vez. Y si no hay TPV identificado, **no se guarda nada**.

### 7.9 La cadena de tres niveles (tienda 47)

Cambia a la tienda **47**, TPV **56**, producto **1073 «ala»** en la ubicación **63**.
Hay **2.400 Unidades**, 0 Blísters, 0 Cajas.

Pide **5 Cajas**.

**Debe:**

```
Faltan 5 Cajas. ¿Armar 5 Cajas con 120 Unidades?
```

El servidor calcula la cadena completa (Unidad → Blister → Caja) y lo resume en una
sola pregunta.

---

## § 8 · ⭐ Fase 4 — La venta abre y arma empaques

La sección que prueba el `25`, el último tramo de la Fase 4. **Tienda 47** (la que
**no** permite vender en negativo).

### 8.1 ⭐ Rebalanceo encadenado en una venta real

Producto **1073**, ubicación **63**: 2.400 Unidades, nada más.

1. Vende **5 Cajas** desde el TPV 56.

**Debe:** la venta pasa.

2. Mira el ledger:

```sql
SELECT ip.id_presentacion, np.denominacion AS pres,
       ip.cantidad_inicial, ip.cantidad_final,
       ip.origen_cambio, ip.id_conversion
  FROM app_dat_inventario_productos ip
  JOIN app_dat_producto_presentacion pp ON pp.id = ip.id_presentacion
  JOIN app_nom_presentacion np ON np.id = pp.id_presentacion
 WHERE ip.id_producto = 1073 AND ip.id_ubicacion = 63
 ORDER BY ip.id DESC LIMIT 6;
```

**Debe devolver exactamente esta cadena** (medido en el ensayo de desarrollo):

| pres | inicial | final | origen_cambio | id_conversion |
|---|---|---|---|---|
| Unidad | 2400 | 2280 | 20 | 20 |
| Blister | 0 | 10 | 20 | 20 |
| Blister | 10 | 0 | 20 | 21 |
| Caja | 0 | 5 | 20 | 21 |
| Caja | 5 | 0 | **3** (venta) | — |

120 Unidades → 10 Blísters → 5 Cajas → vendidas. **Dos conversiones encadenadas**, cada
una con su `id_conversion` propio.

**Por qué el `id_conversion` separado importa:** sin él, el IPV leería estas filas como
ajustes sueltos y el kardex las mostraría como correcciones de error.

### 8.2 Cuando no alcanza ni convirtiendo, rechaza con números

Pide **500 Cajas** del 1073 (solo hay 2.400 Unidades = 100 Cajas).

**Debe:** la venta **falla** con:

```
error_code: INSUFFICIENT_STOCK_CONVERTIBLE
message:    Stock insuficiente de Caja: se piden 500 y el convertible alcanza para 95
```

**El error viaja en el mismo `jsonb`** con `status: 'error'` que la app ya sabe manejar.
No es una excepción nueva.

### 8.3 ⭐⭐ Guarda 1 — producto de UNA sola presentación pasa igual que antes

Esta es la primera guarda de compatibilidad. **Es la prueba más importante de la
sección.**

Producto **10474 «PETROLEO»** en la tienda 45 (una sola presentación).

1. Intenta vender **más de lo que hay**.

**Debe:** el error de **CHECK constraint**, exactamente el mismo que daba antes de todo
este trabajo:

```
Error al registrar venta: new row for relation "app_dat_inventario_productos"
violates check constraint "chk_cantidad_final_conditional"
```

**No** debe salir `INSUFFICIENT_STOCK_CONVERTIBLE`. El rebalanceo **se salta** por
completo.

**Por qué existe esta guarda:** medición sobre ventas reales de 30 días —

```
ventas de barra ................................ 17.374
el saldo previo NO alcanzaba ...................     20  (0,12 %)
de esas 20, con otra presentación que convertir      0
```

Las 20 son de **4 productos de una sola presentación** (PETROLEO ×17, plancha cubana,
Compresor Hyundai, PUNTA DE RABO DE GATO). Sin la guarda, la Fase 4 habría empezado a
rechazar 20 ventas que hoy pasan.

### 8.4 ⭐⭐ Guarda 2 — la tienda que vende en negativo sigue pudiendo

La segunda guarda. **Tienda 11**, que tiene
`permite_vender_aun_sin_disponibilidad = true`.

Producto 217, ubicación 37. Pide **50 Bultos** (solo se pueden servir 10).

**Debe:** la venta **pasa** y deja el saldo negativo — exactamente como antes del `25`.

**Por qué existe:** esas tiendas encendieron la bandera **a propósito**. Bloquearlas
rompería lo que pidieron.

```sql
-- Exposición de esta guarda
WITH multi AS (
  SELECT pp.id_producto, p.id_tienda
    FROM app_dat_producto_presentacion pp
    JOIN app_dat_producto p ON p.id = pp.id_producto
   GROUP BY 1,2 HAVING count(*) > 1)
SELECT ct.permite_vender_aun_sin_disponibilidad AS permite_negativo,
       count(DISTINCT ct.id_tienda)  AS tiendas,
       count(DISTINCT m.id_producto) AS productos_multipresentacion
  FROM app_dat_configuracion_tienda ct
  LEFT JOIN multi m ON m.id_tienda = ct.id_tienda
 GROUP BY 1 ORDER BY 1;
```

**Debe:** `false → 66 tiendas / 59 productos` y `true → 2 tiendas / 31 productos`.
Esos 31 productos en 2 tiendas son los que esta guarda protege.

> ⚠️ **Corrección de un diagnóstico equivocado.** Durante el desarrollo se creyó que la
> venta *no validaba stock*, porque el INSERT resta sin comprobar. Es **falso**: la
> validación vive en el CHECK `chk_cantidad_final_conditional`, que llama a
> `fn_validar_cantidad_final_inventario` y esa función lee la bandera **por tienda**.
> Los 5 saldos negativos vivos del ledger no son falta de validación: son las 2 tiendas
> con la bandera encendida.

### 8.5 El rebalanceo solo aplica a barra no elaborada

```sql
SELECT p.proname,
       (SELECT count(*) FROM regexp_matches(p.prosrc, 'fn_rebalancear_presentaciones\(', 'g')) AS rebal,
       (SELECT count(*) FROM regexp_matches(p.prosrc, 'v_n_pres', 'g'))      AS guarda_1,
       (SELECT count(*) FROM regexp_matches(p.prosrc, 'v_permite_neg', 'g')) AS guarda_2,
       (SELECT count(*) FROM regexp_matches(p.prosrc, 'fn_cantidad_en_base\(', 'g')) AS bom_24,
       p.prosecdef, pg_get_function_result(p.oid) AS devuelve
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_registrar_venta', 'fn_registrar_venta_mesa')
 ORDER BY 1;
```

**Debe:** `1 / 3 / 3 / 1` en **las dos** funciones, `prosecdef = false`,
`devuelve = jsonb`.

**Por qué solo barra no elaborada:** en las otras tres rutas el `CASE` del INSERT deja
el saldo del SKU igual — el descuento lo hace `fn_descontar_venta_enrutada` sobre la
receta o la porción. Rebalancear el SKU ahí duplicaría movimientos.

### 8.6 ⭐ Bug 5 — la venta leía el saldo de otra presentación

El bug que arregló el `22`, latente pero grave.

```sql
-- Producto 217, ubicación 37: Bolsa(336) = 100, Bulto(337) = 0.
-- El subselect VIEJO ordenaba por "id DESC" sin filtrar presentación:
SELECT ip.id_presentacion, ip.cantidad_final
  FROM app_dat_inventario_productos ip
 WHERE ip.id_producto = 217 AND ip.id_ubicacion = 37
 ORDER BY ip.id DESC, ip.created_at DESC
 LIMIT 1;
```

**Devuelve:** `id_presentacion 336, cantidad_final 100` — **la Bolsa**, por tener el id
más alto.

**Qué pasaba:** al vender **1 Bulto**, la venta leía ese 100 y escribía
`cantidad_inicial 100 / cantidad_final 99` en una fila marcada como **Bulto**.
**99 Bultos inventados = 990 Bolsas.**

Con el filtro correcto devuelve **0**, el saldo real del Bulto.

**Detalle del arreglo:** el filtro es
`AND COALESCE(id_presentacion, 0) = COALESCE(v_producto_presentacion_id, 0)`. El
`COALESCE` a los **dos** lados es imprescindible: hay filas históricas con
`id_presentacion IS NULL`, y con `=` a secas (`NULL = NULL` → NULL) no casarían nunca —
toda venta de un producto sin presentación empezaría a leer saldo 0 y a escribir
negativos.

Estaba latente porque solo hay **3 combinaciones producto+ubicación con más de una
presentación** en 309.092 filas del ledger. Y este plan es justo lo que las multiplica.

---

## § 9 · ⭐ Fase 4 — BOM de cocina y porciones

Un riesgo que **introducía la propia Fase 4** y se cerró antes de que llegara a
producción.

### 9.1 El problema

Al hacer que el TPV mande la cantidad **en la presentación elegida**, esa cantidad
llegaba igual a `fn_descontar_venta_enrutada`, que la usa como **unidades base** para:

- la receta de elaborados (`fn_descontar_ingredientes_bom_almacen`)
- las porciones por tanda

Vender **1 Caja de 24 croquetas** habría descontado los ingredientes de **1** croqueta.

Es invisible: la venta sale bien, el ticket cuadra, y el inventario de materia prima
simplemente se queda alto.

### 9.2 Los productos afectados

```sql
WITH pres AS (
  SELECT pp.id_producto, count(*) n_pres, max(pp.cantidad) max_factor
    FROM app_dat_producto_presentacion pp GROUP BY 1)
SELECT p.id, p.denominacion, p.id_tienda, pr.n_pres, pr.max_factor
  FROM app_dat_producto p JOIN pres pr ON pr.id_producto = p.id
 WHERE p.es_elaborado AND (pr.n_pres > 1 OR pr.max_factor <> 1)
 ORDER BY p.id;
```

**Debe:** **3 productos** — 219 «croqueta» y 220 «pan de la casa» (factor 24), y
9925 «Pan Boom 40g» (factor 50).

### 9.3 El helper de conversión

```sql
SELECT public.fn_cantidad_en_base(340, 1) AS una_caja_de_24,   -- croqueta Caja
       public.fn_cantidad_en_base(339, 5) AS cinco_unidades,   -- croqueta Unidad (base)
       public.fn_cantidad_en_base(4445, 2) AS base_factor_30,  -- base con factor 30
       public.fn_cantidad_en_base(NULL, 7) AS sin_presentacion,
       public.fn_cantidad_en_base(99999999, 7) AS inexistente;
```

**Debe:** `24` / `5` / **`2`** / `7` / `7`.

El tercero es la prueba de que usa **`factor_rel`** y no `pp.cantidad`: la presentación
4445 es base con factor 30, y 2 unidades base son **2**, no 60.

Los dos últimos son la compatibilidad: presentación nula o inexistente → **devuelve la
cantidad sin tocar**, nunca 0 ni error.

### 9.4 ⭐ Compatibilidad exacta con la app vieja

```sql
SELECT count(*) AS bases_probadas,
       count(*) FILTER (WHERE public.fn_cantidad_en_base(pp.id, 7) = 7) AS devuelven_7,
       count(*) FILTER (WHERE public.fn_cantidad_en_base(pp.id, 7) <> 7) AS cambian
  FROM app_dat_producto_presentacion pp
 WHERE pp.es_base;
```

**Debe:** `cambian = 0` sobre **8.785 presentaciones base**.

La app vieja manda la base o `null`; en los dos casos la conversión es la identidad.
**Cero cambio de comportamiento para ella.**

### 9.5 Solo se convierte el BOM, no el ledger

Vende **1 Caja de croquetas** (presentación 340, factor 24) con cocina activa.

**Debe:**
- la fila del **SKU** en el ledger guarda **1 Caja** (la presentación, sin convertir)
- el descuento de **harina** corresponde a **24** croquetas (40 × 24 = 960)

Las dos cosas a la vez: la línea del SKU conserva la presentación —que es el objetivo de
la Fase 4— y el BOM recibe unidades base, que es lo que la receta necesita.

### 9.6 Pendiente conocido: `fn_stock_producto_almacen`

```sql
-- Suma cantidad_final de presentaciones DISTINTAS sin aplicar factor.
SELECT p.proname
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.prosrc LIKE '%fn_stock_producto_almacen(%'
 ORDER BY 1;
```

**Debe:** unas **13 funciones** la usan (disponibilidad de platos, tandas, enrutamiento
de venta).

**Hoy no afecta a nadie:** hay **1 sola** combinación producto+almacén con más de una
presentación con stock en todo el ledger, y es el producto de prueba 3046 con dos filas
base de factor 1 (reporta 2.939 = 1.469 + 1.470, que en ese caso es correcto).

**Es el próximo bug** en cuanto se configure un empaque real en un elaborado o en un
producto por tanda. Queda anotado, no resuelto.

---

## § 10 · ⭐ Fase 5 — Offline: deltas por presentación y fracciones

App **vendedor**. Dos bugs del caché local, y uno de ellos **afecta a todas las
tiendas**, no solo a las multipresentación.

### 10.1 ⭐ El delta se aplicaba a la presentación equivocada

**Pon el dispositivo en modo avión.**

1. Foto del caché **antes**. Con el producto 217 en el TPV, anota el stock que muestra
   cada presentación (Bolsa y Bulto).
2. Vende **2 Bultos** offline.
3. Mira el stock que muestra la app ahora.

**Debe:** bajaron los **Bultos** en 2. Las **Bolsas** quedan igual.

**El bug:** `updateProductInventoryInCache` no sabía de presentaciones. Aplicaba el
delta a la primera fila del caché que casara, que normalmente es la base. Desde la
Fase 4 `item.cantidad` viene en la presentación elegida, así que vender **2 Bultos
descontaba 2 Bolsas** del caché local.

**Por qué es grave offline:** el vendedor veía un stock que no existía hasta la
siguiente sincronización, y offline eso puede ser **todo un turno**.

### 10.2 ⭐ Las ventas fraccionadas se perdían (afecta a todas las tiendas)

Este no tiene nada que ver con presentaciones.

1. Sigue en modo avión.
2. Vende **0,5** de un producto que se venda por peso o fracción.
3. Mira el stock en la app.

**Debe:** bajó **0,5**.

**El bug:** la firma era `int quantityToSubtract` y los **5** llamadores hacían
`.toInt()`. Vender 0,5 kg descontaba **0** — el caché local no se movía. Cualquier
producto vendido en fracciones, en cualquier tienda.

Ahora el parámetro es `num`.

### 10.3 No hay fallback silencioso cuando se pide presentación

Con presentación explícita, si **no existe** fila de esa presentación en el caché:

**Debe:** ajustarse solo el total del producto y quedar un aviso en el log:

```
⚠️ Sin fila de inventario para la presentación <id> (producto <id>):
   solo se ajustó el total del producto
```

**No** debe tocar `inventarioList.first`.

**Por qué:** tocar otra fila es escribir un saldo falso. Es mejor un total aproximado y
un aviso que un desglose incorrecto que parece exacto.

### 10.4 La orden pendiente guarda la presentación

1. En modo avión, arma una venta con **1 Bulto** y **3 Bolsas** del 217.
2. Ciérrala (queda como orden pendiente).
3. **Sin salir del modo avión**, ve a la lista de órdenes pendientes y ábrela.

**Debe:** las dos líneas conservan su presentación.

**Por qué se guardan los tres campos** (`id_presentacion`, `presentacion_nombre`,
`presentacion_factor`) y no solo el id: el cierre de turno se arma offline, cuando ya no
se puede consultar la cadena para saber cómo se llamaba la presentación ni cuánto valía.

### 10.5 ⭐ La sincronización no aplana

1. **Quita el modo avión.**
2. Espera (o fuerza) la sincronización.
3. Mira el ledger del servidor (consulta **C**).

**Debe:** dos filas — `id_presentacion 337` con 1, y `336` con 3.

**El hueco que esto tenía:** la orden pendiente no guardaba la presentación, así que una
venta hecha sin conexión se subía horas después con `id_presentacion` nulo y el servidor
la interpretaba como base. **«2» pasaba de 2 Bultos a 2 Bolsas.**

Se tocaron **cinco** puntos de sincronización: `checkout_screen`, `preorder_screen`,
`auto_sync_service` y los **3** caminos de sync de `settings_screen` (había tres, no
uno), más la reconstrucción en `order_service`.

### 10.6 El wrapper offline del servidor no necesitaba cambios

```sql
SELECT p.oid::regprocedure
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'fn_registrar_venta_offline';
```

`fn_registrar_venta_offline` solo hace idempotencia por `client_uuid` y delega en
`fn_registrar_venta` pasando el `jsonb` **tal cual**. Hereda todo lo del `22`, `24` y
`25` sin tocarla.

### 10.7 Idempotencia: reintentar no duplica

Sincroniza **dos veces** la misma orden pendiente (mismo `client_uuid`).

**Debe:** una sola venta en el servidor y el stock movido **una sola vez**.

---

## § 11 · Fase 5 — Conteo y ajuste por presentación

### 11.1 ⭐ El ajuste estaba roto por un `?? 0`

App **admin** → Inventario → **Ajuste**.

1. Zona 37, producto 217, ajusta la Bolsa.

**Debe:** `status: success`.

**El bug:** la pantalla mandaba `idPresentacion: row.idPresentacion ?? 0`, y
`fn_insertar_ajuste_inventario2` valida el id contra `app_dat_producto_presentacion`:

```sql
-- Los tres casos, medidos contra la función viva:
SELECT public.fn_insertar_ajuste_inventario2(
  217, 37, 0::bigint, 100, 95, 'Conteo', 'x',
  '0a6886f2-ac36-416a-bfba-bd08d0671568'::uuid, 3::bigint) AS con_cero;
-- → {"status": "error", "message": "id_presentacion 0 no existe en app_dat_producto_presentacion"}
```

| `id_presentacion` | resultado |
|---|---|
| `0` | **error 22023** «no existe» |
| `null` | success (100 → 95) |
| `337` (Bulto, saldo 0) → setear 3 | success, `diferencia 3.0` |

**Por qué nadie lo vio:** el error viaja **dentro del `jsonb`** con `status: 'error'`, no
como excepción. La pantalla lo contaba en `errorCount` y mostraba «N ajuste(s) con
error» sin decir el motivo.

El mismo `?? 0` estaba en `productos_zona_destino_screen.dart`. Los dos corregidos: ahora
mandan `null` y el servidor resuelve la base.

### 11.2 El ajuste lee el saldo real, no le cree al cliente

```sql
-- Declara un saldo anterior FALSO a propósito:
SELECT public.fn_insertar_ajuste_inventario2(
  217, 37, 336::bigint, 999, 95, 'Conteo', 'prueba desfase',
  '0a6886f2-ac36-416a-bfba-bd08d0671568'::uuid, 3::bigint);
```

**Debe:** `status: success`, y en la respuesta:
- `saldo_anterior` = el saldo **real** (100), no el declarado
- `saldo_declarado` = 999
- `desfase: true`
- la observación incluye `[saldo declarado 999, saldo real 100]`

**Por qué:** el cliente puede tener el caché viejo. Creerle rompía la cadena de saldos —
**202 casos en producción** antes de este arreglo.

### 11.3 El ajuste negativo rebalancea

Setea el **Bulto** (337, saldo 0) a **3** cuando solo hay Bolsas.

**Debe:** `success` y, en el ledger, filas de conversión antes del ajuste.

Esto **ya estaba resuelto en el `08`** desde la Fase 1: cuando la diferencia es negativa,
`fn_insertar_ajuste_inventario2` llama a `fn_descontar_con_rebalanceo`.

### 11.4 Un diálogo por presentación, con el desglose a la vista

Ya probado en §2.5. Repítelo si vas por orden.

### 11.5 Pendiente conocido: el conteo de apertura de turno

**No implementado por decisión explícita.** Queda documentado.

`apertura_screen.dart` indexa los `TextEditingController` por **`product.id`**, y
`InventoryService.buildFromOfflineCache()` **suma `cantidad_disponible` de todas las
presentaciones** en un solo `InventoryProduct`, quedándose con la **primera** como
`id_presentacion` (`bestRow ??= inv`).

Consecuencia: **contar «4 Cajas + 4 Unidades» en la apertura es imposible.** Hay un solo
campo por producto y lo que se cuenta se atribuye a una presentación arbitraria.

```sql
-- Exposición hoy:
WITH saldos AS (
  SELECT DISTINCT ON (ip.id_producto, ip.id_ubicacion, COALESCE(ip.id_presentacion,0))
         ip.id_producto, ip.id_ubicacion, ip.id_presentacion, ip.cantidad_final
    FROM app_dat_inventario_productos ip
   WHERE ip.id_ubicacion IS NOT NULL
   ORDER BY ip.id_producto, ip.id_ubicacion, COALESCE(ip.id_presentacion,0), ip.id DESC)
SELECT count(*) AS combinaciones, count(DISTINCT id_producto) AS productos
  FROM (SELECT id_producto, id_ubicacion FROM saldos
         WHERE COALESCE(cantidad_final,0) > 0
         GROUP BY 1,2 HAVING count(*) > 1) x;
```

**Debe:** **2 combinaciones / 2 productos** (4 filas). Es poco, y arreglarlo toca el
modelo, el builder del caché offline y la UI de la pantalla de apertura — que es la
primera cosa que ve un vendedor al abrir turno y hoy funciona.

**Nota sobre `fn_registrar_control_inventario`:** parece la vía natural para el conteo
(acepta `id_presentacion` y valida `APERTURA`/`CIERRE`/`CONTEO`), pero **está muerta**:

```sql
-- Falla con 2D000 invalid transaction termination
SELECT public.fn_registrar_control_inventario(11, '...'::uuid, 'CONTEO', '[]'::jsonb);
```

Tiene `COMMIT`/`ROLLBACK` dentro de un bloque PL/pgSQL, e inserta en
`app_dat_control_productos_detalle`, tabla que **no existe** (la real es
`app_dat_control_productos`, con las columnas de detalle dentro). Ningún Dart la llama.
El conteo real de apertura pasa por `registrar_apertura_turno_v3`, que sí escribe
`id_presentacion`.

---

## § 12 · Congelado de factores y la marca `es_base`

Qué se puede cambiar de una presentación y qué no.

### 12.1 Cambiar el factor de una presentación con movimientos se rechaza

App **admin** → Producto → Presentaciones. Intenta cambiar el factor del **Bulto** del
217 (que ya tiene movimientos).

**Debe:** un mensaje amable, no un error crudo. El código es **23001**:

```
No se puede cambiar el factor de "Bulto" (id 337) del producto 217:
ya tiene movimientos de inventario. El factor se interpreta al leer, así que
cambiarlo reinterpreta TODO el historico de esa presentación (saldos, IPV,
valoración y costos de meses cerrados cambiarían solos, sin dejar traza).
```

**Por qué:** el factor no se guarda en cada fila del ledger, se **interpreta al leer**.
Cambiarlo de 10 a 12 reescribe la historia: los saldos, el IPV, la valoración y los
costos de meses cerrados cambian solos, sin dejar rastro de que alguien tocó algo.

### 12.2 Qué se bloquea y qué no

```sql
SELECT pg_get_triggerdef(t.oid)
  FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
 WHERE c.relname = 'app_dat_producto_presentacion'
   AND t.tgname = 'trg_congelar_factor_presentacion';
```

**Debe:** `BEFORE DELETE OR UPDATE OF cantidad, id_presentacion, id_producto`.

| Cambio | Con movimientos |
|---|---|
| `cantidad` (el factor) | **rechazado 23001** |
| `id_presentacion` (apuntar a otro nombre) | **rechazado 23001** |
| `id_producto` (mover a otro producto) | **rechazado 23001** |
| **borrar** la presentación | **rechazado 23001** |
| `es_base` | **permitido** ✅ |
| `precio_promedio` | permitido |
| `sku_codigo`, etc. | permitido |

### 12.3 ⭐ `es_base` SÍ se puede cambiar (corrección de un bloqueo mío)

Este bloqueo estaba mal y se quitó en el `23`.

1. Abre un producto con **una sola** presentación que tenga movimientos.
2. Cambia la marca de base.

**Debe:** guardar sin error.

**Por qué estaba mal:** `es_base` es un **puntero reversible**, no un dato irreversible.
La cascada lo usa solo como primer criterio de desempate, y volver atrás es poner el
booleano de nuevo. Las otras tres columnas sí son irreversibles: cambias el factor y
pierdes el valor viejo.

**Y rompía el patrón normal de la app:** cambiar de base son **dos pasos** —apagar la
marca en todas las filas del producto, luego prender una—. El guard rompía el **primer**
paso, así que los tres métodos de `presentation_service.dart` (`setBasePresentation`,
`addPresentationToProduct`, `updateProductPresentation`) estaban **muertos** para
cualquier producto con movimientos.

En el caso reportado además rechazaba una operación **sin ningún efecto**: el producto
10798 «Harina 1» tiene una sola presentación, así que apagar la marca no cambia nada.

```sql
-- Verificación: apagar todas las marcas es no-op en casi todo el catálogo.
SELECT count(*) FILTER (WHERE n_base = 1) AS una_sola_base,
       count(*) AS productos
  FROM (SELECT id_producto, count(*) FILTER (WHERE es_base) AS n_base
          FROM app_dat_producto_presentacion GROUP BY 1) x;
```

**Debe:** apagar la marca es no-op en **8.781 de 8.792** productos.

### 12.4 El escape para corregir un factor mal cargado

Si el factor se cargó mal **y el histórico también está mal**, hay una vía consciente:

```sql
BEGIN;
SET LOCAL ventiq.permitir_cambio_factor = 'on';
UPDATE app_dat_producto_presentacion SET cantidad = 12 WHERE id = <id>;
COMMIT;
```

**Debe:** pasar. Es deliberadamente incómodo: no se puede hacer desde la app.

El mensaje del 23001 sugiere primero la vía correcta: **crear una presentación nueva con
el factor correcto y dejar de usar la vieja.**

### 12.5 Una presentación con movimientos no se borra

Intenta borrar el Bulto del 217.

**Debe:** **23001**. Hay **7.498 presentaciones congeladas** (con movimientos) en
producción.

### 12.6 El 23503 de `app_dat_precio_costo`

87 presentaciones tienen filas en `app_dat_precio_costo` que las hacen imborrables por
FK. Al intentarlo, la app debe traducir el **23503** a un mensaje entendible, no mostrar
el error de Postgres.

---

## § 13 · ⭐ No-regresión: la app vieja sigue viva

**La sección que más importa si tienes usuarios en producción sin actualizar.**

### 13.1 Ninguna firma cambió, ninguna sobrecarga duplicada

```sql
SELECT p.proname, p.oid::regprocedure AS firma,
       pg_get_function_result(p.oid) AS devuelve,
       p.prosecdef,
       count(*) OVER (PARTITION BY p.proname) AS sobrecargas
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_registrar_venta', 'fn_registrar_venta_mesa',
                     'fn_registrar_venta_offline',
                     'fn_actualizar_precio_promedio_recepcion_v2',
                     'fn_inventario_resumen_por_usuario_almacen2',
                     'fn_inventory_valuation_rows',
                     'fn_insertar_ajuste_inventario2',
                     'obtener_ipv', 'obtener_ipv2',
                     'get_product_movements_v3', 'get_product_movements_v4',
                     'fn_listar_inventario_productos_paged2')
 ORDER BY 1;
```

**Debe:** **`sobrecargas = 1`** en todas. Una firma duplicada haría que Postgres no
sepa cuál llamar y la app vieja fallaría con `42725 function is not unique`.

### 13.2 Las funciones viejas siguen existiendo

`obtener_ipv` y `get_product_movements_v3` **están intactas**. La app vieja las llama y
recibe exactamente lo de siempre.

**Por qué se hicieron funciones nuevas en vez de reemplazarlas:** cambiar el
`RETURNS TABLE` de una función existente da **42P13**, y hacer `DROP` + `CREATE` deja la
lectura de **todas** las tiendas rota entre las dos sentencias.

### 13.3 ⭐ Las claves viejas del JSON siguen ahí

Ninguna clave se renombró ni se eliminó. Si alguna se hubiera renombrado, la app vieja
mostraría campos **vacíos sin fallar** — el peor tipo de rotura, porque no da error.

```sql
-- ⚠️ Detalles: la columna del jsonb es `detalles` (con `detalles->'items'`),
--    no `productos`. Y el 4.º/5.º parámetros son p_estados / p_fecha_desde.
SELECT r.id, r.tipo_operacion_nombre,
       (item ? 'importe')         AS tiene_importe,
       (item ? 'cantidad')        AS tiene_cantidad,
       (item ? 'id_producto')     AS tiene_id_producto,
       (item ? 'sku_producto')    AS tiene_sku,
       (item ? 'precio_unitario') AS tiene_precio,
       (item ? 'producto_nombre') AS tiene_nombre
  FROM (SELECT set_config('request.jwt.claims',
          json_build_object('sub','7e3507ec-1b29-4901-bf88-e5d77be72100',
                            'role','authenticated')::text, true) c) s,
       LATERAL public.fn_listar_operaciones_inventario_new(
         45, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 30, 1) r,
       LATERAL jsonb_array_elements(COALESCE(r.detalles->'items', '[]'::jsonb)) item
 LIMIT 15;
```

**Debe:** `tiene_cantidad`, `tiene_id_producto`, `tiene_sku`, `tiene_precio` y
`tiene_nombre` en **`true`** en todas las filas. Comprobado al escribir este tutorial en
la tienda 45.

> `tiene_importe` sale **`false` en las recepciones** y `true` en las ventas. Eso **ya
> era así antes** de este trabajo: la recepción no lleva importe por línea. No es una
> regresión.

Y en las funciones que sí se ampliaron, comprueba que las claves nuevas **se añadieron**
sin quitar nada:

```sql
-- El helper de item mixto: trae factor_rel además de lo de siempre.
SELECT public.fn_presentacion_item_json(336, 100) AS item;
```

**Debe:** exactamente estas 7 claves (comprobado):

```json
{
  "id_presentacion": 336,
  "presentacion_nombre": "Bolsa",
  "presentacion_factor": 1.0,
  "presentacion_factor_rel": 1.000000,
  "presentacion_sku": "BOL",
  "cantidad_formateada": "100 Bolsas",
  "equivalente_base": 100.000000
}
```

`presentacion_factor_rel` es la que se añadió en el `15`: `presentacion_factor` es el
factor crudo y **no sirve** para calcular equivalentes cuando la base tiene factor ≠ 1
(§1.2).

### 13.4 `id_presentacion: null` sigue funcionando en todas las rutas

La app vieja **no manda** `id_presentacion`. Cada RPC debe resolver la base:

| Ruta | Prueba |
|---|---|
| Venta | §8 caso «app vieja» → `success` |
| Ajuste | §11.1 con `null` → `success` |
| Recepción | recepción sin presentación → fila con la base |
| Extracción | egreso sin presentación → descuenta la base |
| BOM | `fn_cantidad_en_base(NULL, 7)` → **7** |

### 13.5 Ninguna firma ganó parámetros obligatorios

La regla del plan era: parámetros nuevos **con `DEFAULT` y al final**. En la práctica
**no hizo falta añadir ninguno** — todo se resolvió con el `jsonb` que ya se pasaba y con
funciones nuevas.

```sql
SELECT p.proname, pg_get_function_arguments(p.oid) AS args
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_registrar_venta', 'fn_registrar_venta_mesa',
                     'fn_insertar_ajuste_inventario2',
                     'fn_actualizar_precio_promedio_recepcion_v2',
                     'fn_stock_saldos_presentacion', 'fn_cantidad_en_base')
 ORDER BY 1;
```

**Debe:** las firmas de las cuatro primeras son idénticas a las de antes del trabajo. Los
parámetros opcionales de las funciones **nuevas** (`p_incluir_cero`, `p_id_almacen`)
llevan `DEFAULT` y van al final.

**Por qué importa:** un parámetro nuevo en medio de la lista, o sin default, rompe toda
llamada posicional existente — y Supabase RPC llama por nombre, pero PL/pgSQL interno
llama posicional.

### 13.6 La app vieja no depende del arreglo del costo

Dato útil: `updateAveragePriceAfterReception` **está definido pero no se llama desde
ningún sitio** en la versión en producción — el costo lo escribía el bloque Dart inline.
Y la RPC fallaba en el 100 % de las llamadas (§6.1). O sea: **a la app vieja el `20` le
da igual**.

### 13.7 Cifras de no-regresión medidas en desarrollo

| Verificación | Resultado |
|---|---|
| Kardex v3 vs v4 | **26/26 filas** `compatible = true` |
| `obtener_ipv` vs `obtener_ipv2` | **1.189 filas / 4 tiendas / 0 diferencias** |
| Saldo de venta (200 productos de una presentación) | **0 discrepancias** |
| Costos tras aplicar el `20` | huella `md5` **idéntica**, 8.331 filas sin cambio |
| `fn_cantidad_en_base` en presentaciones base | **8.785 / 8.785** devuelven la cantidad sin tocar |
| Resumen de inventario (7 tiendas) | **1.056 = 1.056** |
| Ventas de barra que cambiarían de comportamiento | **0 de 17.374** |

---

## § 14 · Checklist final

### Las 12 pruebas que no pueden fallar

Si solo tienes una hora, haz estas.

1. **§2.4** — Transferir 2 Bultos deja **2 Bultos** en el destino, no 20 Bolsas.
   *(Si falla: el plan entero no sirve.)*
2. **§7.1** — El carrito guarda «2 Bultos», no 20 unidades.
   *(Si falla: el ledger se queda sin los datos que lee toda la Fase 3.)*
3. **§8.1** — Vender 5 Cajas con solo Unidades encadena Unidad → Blister → Caja.
   *(Si falla: el rebalanceo no está enganchado.)*
4. **§8.3** — Producto de una sola presentación falla con el **CHECK**, no con
   `INSUFFICIENT_STOCK_CONVERTIBLE`. *(Si falla: se rechazan ventas que hoy pasan.)*
5. **§8.4** — La tienda con `permite_negativo = true` sigue vendiendo en negativo.
   *(Si falla: se rompieron 2 tiendas que lo pidieron a propósito.)*
6. **§9.4** — `fn_cantidad_en_base` devuelve la cantidad intacta en las 8.785 bases.
   *(Si falla: la app vieja empieza a descontar mal el BOM.)*
7. **§5.4** — El producto 6841 se valora a 186,64, no a 9,80.
   *(Si falla: el 88 % del inventario sigue mal valorado.)*
8. **§6.1** — La RPC del costo promedio devuelve `success = true`.
   *(Si falla: sigue rota como llevaba meses.)*
9. **§10.1** — Vender 2 Bultos offline baja **Bultos**, no Bolsas.
   *(Si falla: el vendedor ve stock inexistente todo el turno.)*
10. **§10.2** — Vender 0,5 offline descuenta 0,5.
    *(Si falla: afecta a todas las tiendas, no solo a las multipresentación.)*
11. **§13.1** — Ninguna función tiene sobrecargas duplicadas.
    *(Si falla: `42725` y la app vieja no arranca.)*
12. **§13.3** — Las claves viejas del JSON siguen presentes (`cantidad`,
    `id_producto`, `sku_producto`, `precio_unitario`, `producto_nombre`).
    *(Si falla: la app vieja muestra campos vacíos sin dar error.)*

### Pendientes conocidos (no son bugs)

| # | Qué falta | Estado |
|---|-----------|--------|
| 1 | `flutter pub get` / `build` | No ejecutados: verificación solo con `dart analyze` (0 errores en admin, 1 preexistente y ajeno en vendedor) |
| 2 | Ninguna UI probada en dispositivo | Es justo lo que cubre este tutorial |
| 3 | Conteo mixto en **apertura de turno** | Documentado en §11.5; decisión explícita de no implementarlo ahora (2 productos afectados) |
| 4 | `fn_stock_producto_almacen` suma sin factor | §9.6. Hoy no afecta a nadie; próximo bug al configurar un empaque en un elaborado |
| 5 | **21 productos** con costos inconsistentes | §6.4. Dato histórico; el `20` no los arregla retroactivamente |
| 6 | **14 productos** con stock y sin costo en su presentación | §5.7. Dato, no lógica |
| 7 | **514 productos** con stock y costo 0 en el IPV | §6.8b |
| 8 | Rotación / días de inventario en productos partidos | §6.8a. Decisión de negocio: ¿el IPV se reporta por presentación o por producto? |
| 9 | Formatters duplicados (`FormatoPresentacion` vs `StockMixtoFormatter`) | Uno por app, con tests de paridad; unificarlos exige un paquete compartido |
| 10 | **Lista de Operaciones sin presentación** | §2.6. `fn_listar_operaciones_inventario_new` (~32.800 chars) no se tocó: arma su `detalles` por tipo de operación, así que hay que ampliar cada rama |

### Cómo reportar un fallo

Dame estos cuatro datos y lo localizo rápido:

1. **Qué sección** (ej. §8.3).
2. **Qué esperabas y qué pasó.**
3. **Los ids**: producto, ubicación, presentación, operación.
4. **El estado antes y después:**

```sql
SELECT * FROM public.fn_stock_saldos_presentacion(<producto>, NULL, <ubicacion>, true);

SELECT ip.id, ip.id_presentacion, ip.cantidad_inicial, ip.cantidad_final,
       ip.origen_cambio, ip.id_conversion, ip.created_at
  FROM app_dat_inventario_productos ip
 WHERE ip.id_producto = <producto> AND ip.id_ubicacion = <ubicacion>
 ORDER BY ip.id DESC LIMIT 10;
```

Y si es un error de una RPC, el **JSON completo** que devolvió: trae `status`,
`error_code` y `message`.

### Limpiar después de las pruebas

Las ventas y movimientos de prueba **no se borran**: se corrigen por la vía normal
(ajuste con trazabilidad).

```sql
-- Ver qué generaron las pruebas
SELECT ip.id_producto, ip.id_presentacion, count(*) AS filas,
       min(ip.created_at) AS desde, max(ip.created_at) AS hasta
  FROM app_dat_inventario_productos ip
 WHERE ip.created_at > CURRENT_DATE
   AND ip.id_producto IN (217, 1073, 219)
 GROUP BY 1, 2 ORDER BY 1, 2;
```

Para dejar los saldos como estaban, usa la pantalla de **ajuste** (§11) sobre cada
presentación. Anota el motivo «pruebas de presentaciones» para que quede en el kardex.

> ⚠️ **No borres a mano filas de `app_dat_inventario_productos`.** Además de perder la
> traza, la tabla tiene **3 triggers vivos** (sincronización a `carnavalapp.Productos` y
> notificaciones de disponible/agotado): un `DELETE` directo dispara efectos fuera de
> esta base.

---

## Resumen de archivos

**SQL** (`presentaciones_inventario/`, **25 archivos, todos aplicados**):

| Archivo | Fase | Qué trae |
|---------|------|----------|
| `01`–`02` | 0 | Contrato de `id_presentacion`, helpers de lectura mixta |
| `03`–`05` | 0 | Rebalanceo, conversión auditada, ingresos |
| `06`–`08` | 1 | Recepción / egresos / ajuste sin aplanar |
| `09`–`11` | 1 | Transferencias, preview del rebalanceo |
| `12` | 2 | **Trigger de congelado de factores** (23001) |
| `13`–`14` | 2 | Presentaciones editables para la UI |
| `15`–`16` | 3 | `fn_presentacion_item_json` con `factor_rel`, alias de stock mixto |
| `17` | 3 | **Kardex `get_product_movements_v4`** |
| `18` | 3 | **Resumen: 2 bugs de factor y JOIN** |
| `19` | 3 | **Valoración: el bug del 88 %** |
| `20` | 3 | **Costo promedio en base** (y la RPC que estaba rota) |
| `21` | 3 | **IPV `obtener_ipv2`** |
| `22` | 4 | **Saldo de venta por presentación** |
| `23` | — | **Compatibilidad: liberar `es_base`** |
| `24` | 4 | **BOM en unidades base** |
| `25` | 4 | **La venta abre y arma empaques** |

**Dart nuevo** (`ventiq_app/lib/`):

`utils/presentacion_cadena_local.dart` · `widgets/captura_mixta_presentacion.dart` ·
`services/preview_rebalanceo_service.dart` · `test/presentacion_cadena_local_test.dart`

**Dart nuevo** (`ventiq_admin_app/lib/`):

`services/presentacion_cadena_service.dart` · `widgets/cantidad_mixta_input.dart` ·
`utils/stock_mixto_formatter.dart` · `services/presentacion_editable_service.dart` ·
`test/stock_mixto_formatter_test.dart`

**Tests:** 32 casos de `StockMixtoFormatter` + 22 de `PresentacionCadenaLocal`, todos
verdes.

**Documentos:** `docs/PLAN_PRESENTACIONES_INVENTARIO.md` (el plan, con las 6 fases y los
pendientes) · `docs/REFERENCIA_INDUSTRIA_PRESENTACIONES.md` (cómo lo resuelven Odoo,
Square y otros) · `presentaciones_inventario/README.md` (estado de cada archivo SQL con
sus cifras de verificación).

---

## Apéndice · Trampas de las firmas (para no perder tiempo)

Las encontré ejecutando las consultas de este tutorial. Si una prueba «sale vacía» o da
error de columna, mira aquí primero.

| Función | Trampa |
|---|---|
| `get_product_movements_v3/v4` | Los dos últimos parámetros son **`(p_offset, p_limit)`**, en ese orden. Pasar `(100, 0)` da `limit 0` → **0 filas** y parece que la prueba falla. |
| `fn_stock_saldos_presentacion` | El 4.º es **`p_incluir_cero`** (default `false`). Con `false` las presentaciones en 0 **no salen**; para auditar la cadena hay que pasar `true`. |
| `fn_inventario_resumen_por_usuario_almacen2` | Las columnas son **`prod_id` / `prod_nombre`**, no `id_producto` / `nombre_producto`. Y los parámetros 4 y 5 son `p_mostrar_sin_stock boolean` y `p_filtro_stock text`. |
| `fn_inventory_valuation_rows` | Los costos son **`precio_costo_usd` / `valor_costo_usd`** (y `_cup`), no `costo_unitario` / `valor_total`. |
| `fn_listar_operaciones_inventario_new` | El jsonb es **`detalles`**, y los ítems van en **`detalles->'items'`**. No hay columna `productos`. |
| `obtener_ipv` / `obtener_ipv2` | Para comparar filas hay que casar **también por `id_ubicacion` y `cantidad_inicial`**. Casar solo por producto+nombre cruza en aspa las filas del mismo producto en ubicaciones distintas y da **diferencias falsas**. |
| `fn_presentacion_item_json` | Las claves son `presentacion_nombre` / `presentacion_factor` / **`presentacion_factor_rel`** / `presentacion_sku` / `cantidad_formateada` / `equivalente_base`. |
| `fn_registrar_control_inventario` | **Está muerta**: `COMMIT`/`ROLLBACK` dentro de PL/pgSQL → `2D000`, e inserta en una tabla que no existe. No la uses. |

Y dos del lado de los datos:

- **`pp.id` ≠ `pp.id_presentacion`.** `id` es la **fila** producto+presentación+factor (lo
  que el ledger guarda); `id_presentacion` es la **FK al nomenclador** (1=Unidad, 3=Caja).
  Confundirlas fue el bug del 88 % de la valoración (§5.4).
- **`pp.cantidad` ≠ `factor_rel`.** Para equivalentes usa siempre `factor_rel`; hay
  **131 productos** con la base en factor ≠ 1 (§1.2).



