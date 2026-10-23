# Verificación adversarial del plan de consumo de ingredientes de elaborados

**Verificador:** teammate `verifier` · **Fecha:** 2026-10-21 · **Tarea:** `task-4`
**Objeto:** `docs/PLAN_CONSUMO_INGREDIENTES_ELABORADOS_PRESENTACIONES.md` (373 líneas)
**Fuentes secundarias (comprobadas, no confiadas):** `docs/_analisis/INGREDIENTES_SQL.md`, `docs/_analisis/INGREDIENTES_DART.md`

**Método.** Solo lectura. Producción `vsieeihstajlrdvpuooh` vía MCP: `pg_proc`, `pg_get_functiondef`, `prosrc` (numeración de líneas **1-based sobre `prosrc`**, que es la convención que usa el propio repo en `presentaciones_inventario/27_stock_almacen_en_base.sql:31`), `to_regprocedure`, censos con `SELECT`, y funciones `STABLE` de lectura (`fn_validar_ingredientes_elaborado`, `fn_stock_producto_almacen`, `fn_stock_saldos_presentacion`, `fn_presentaciones_producto`, `fn_obtener_ingredientes_recursivos`). **No se ejecutó ninguna función que escriba.** Código Dart leído con `read`. Las trazas aritméticas que requerirían escritura se describen, no se ejecutan.

**Recuento final: 76 afirmaciones verificadas → 62 CONFIRMADO · 10 INCORRECTO · 4 NO VERIFICABLE.**
(Sustantivas INCORRECTO: S5, S6, S13, P2, P7, P8, F2, F5, F7, F8; las 4 NO VERIFICABLE son P10-P11 —debug— y F10-F11 —bordes no cubiertos por el plan, no comprobables sin datos de debug—.)

---

## 0 · Los 3 hallazgos más graves (resumen)

### H1 · El caso «240» que sostiene todo el diagnóstico **no es multi-almacén intra-tienda: es inter-tienda**, y el ingrediente que falla no es el 239

`fn_validar_ingredientes_elaborado(240,1,12)` devuelve exactamente el texto que dice el plan (`disponible: 0, requerido: 1.0`, `INSUFFICIENT_STOCK_INGREDIENT`), **pero el ingrediente que la aborta es el 238 «pan solo»**, no el 239. La receta real de 240 es `238 ×1.0 + 239 ×2.0`.

Y la afirmación del plan «con **160** del ingrediente 239 en **otro almacén de la misma tienda**» es **falsa**:

| producto | presentación | saldo | almacén | tienda |
|---|---|---|---|---|
| 238 pan solo | Unidad (factor_rel 1) | 980 | 1 | **1** |
| 238 pan solo | Unidad | 0 | 15 | 11 |
| 239 perro caliente | Unidad (factor_rel 1) | **160** | **1** | **1** |
| 239 perro caliente | Unidad | 0 | 15 | 11 |

Elaborado 240 → `id_tienda = 11`; sus almacenes son **12** («La Estrella warehouse», el del TPV 18) y **15** («contenedor refrigerado»), y **ambos están a 0** para 238 y 239. Los 160 están en el **almacén 1 de la tienda 1**. Consecuencia directa: el prompt de la Fase 5 (`"elegir ... 240 ... y verificar que con 'tienda' da success"`, líneas 243-244) **no puede pasar** — «toda la tienda» (tienda 11) sigue siendo 0. Este caso pertenece a la opción (a) de la Fase 5 (corregir configuración), no a la (b).

### H2 · El censo multi-almacén 36/8 se reproduce, pero su «toda la tienda» es en realidad **toda la plataforma** (`p_id_almacen = NULL`)

`INGREDIENTES_SQL.md` §7.4 (y el plan §10) calculan «producible con toda la tienda» con `fn_stock_producto_almacen(ing.id_ingrediente, NULL)` → **todos los almacenes de todas las tiendas**. Reproducido tal cual: **36 elaborados / 8 tiendas** ✓. Pero al restringir «toda la tienda» a los almacenes de la tienda del elaborado, siguen siendo **35 / 7** — es decir, el fenómeno intra-tienda existe, pero **240 es la única fila de la tienda 11 y entra en el 36 por stock de la tienda 1**. El plan debe (i) reescribir la métrica para no mezclar tiendas y (ii) dejar de usar 240 como prueba de la Fase 5. Igual de grave: el «tienda 25 con **0** producible en **6** elaborados» del §10 es **irreproducible**: medido 21 filas de tienda 25 dentro de los 36 (20 con mejor almacén = 0) y 32 elaborados de tienda 25 con mejor almacén = 0 en total.

### H3 · La Fase 1 **no garantiza empaques enteros** y puede dejar un descuento parcial *commiteado* con la venta fallida

`fn_descontar_con_rebalanceo_almacen` **no tiene un solo llamador vivo** en producción (0 callers vía `pg_proc`), así que el plan lo usaría por primera vez. Su pasada 2 es:

```
v_disponible  := r.convertible;                                  -- TRUNC(SUM(equivalente_base)/v_factor_t, 3)
v_a_descontar := LEAST(v_disponible, v_pendiente);               -- ¡fraccionario!
v_res := public.fn_descontar_con_rebalanceo(... p_cantidad := v_a_descontar ...);
```

`TRUNC(x,3)` **conserva 3 decimales**, no redondea a enteros. `fn_rebalancear_presentaciones` usa ese `p_cantidad` tal cual (`v_falta[v_t] := p_cantidad - v_s[v_t]`; `v_consumo[v_j+1] := v_falta[v_j] * v_fhijo[v_j]`) y `fn_validar_cantidad_final_inventario` solo exige `>= 0` (y **no tiene ningún trigger** en producción: 0 filas en `pg_trigger`). Contraejemplo trazado sobre el código vivo (sin escribir): petición de 2 Cajas (48 base) con la ubicación A = 5 Unidades de un empaque ×6 (30 base) y B = 20 base → validación global 50 ≥ 48 pasa; pasada 2 A → `convertible = TRUNC(30/24,3) = 1.25` < pendiente 2 → consumo **1.25 empaques** (7.5 Unidades), B → `TRUNC(20/24,3) = 0.833` → 0.75 Caja (18 base). El equivalente total cuadra (48), pero el kardex queda con **cantidades fraccionarias de empaque** — exactamente lo que prohíbe la decisión 4 del plan (líneas 114 y 326). Esto es alcanzable en la rama que el plan reutiliza para el SKU propio (`fn_descontar_venta_enrutada` L118) y en el caso 4 de la Fase 1 (línea 184).

Además, `INSUFFICIENT_STOCK_FRAGMENTED` se devuelve **después** de insertar movimientos parciales (la pasada 2 acumula `movimientos` y no aborta), y `fn_registrar_venta` **RETURNA** el error sin `RAISE` (`prosrc` L364-367: `IF (v_descuento_bom->>'status') <> 'success' THEN RETURN v_descuento_bom || ...`). Sin excepción no hay rollback → **descuento parcial persistido con la venta rechazada**. El plan no lo menciona y su decisión 2 («nunca más la validación dice que sí y el descuento dice que no») queda sin cumplir en ese camino.

---

## 1 · Afirmaciones de Dart (`file:line`)

| # | Afirmación del plan | Veredicto | Evidencia |
|---|---|---|---|
| D1 | `product_detail_service.dart:549-559` pide **una** fila (`.select('cantidad_final').order('created_at', asc:false).limit(1)`) | **CONFIRMADO** | L549-554 exacto (`:556-559` es el `if`/cast) |
| D2 | La app llama a los RPC **sin** `_v2` (`order_service.dart:1442-1443`) | **CONFIRMADO** | L1442-1443: `useMesaRpc ? 'fn_registrar_venta_mesa' : 'fn_registrar_venta'` |
| D3 | `order_service.dart:1360-1385` = bloque de ingredientes comentado | **CONFIRMADO** | L1360-1385 comentado íntegro (`// if (decompositionData != null ...`) |
| D4 | `preorder_screen.dart:1367-1380` compara crudo `disponible < necesaria × cantidad` | **CONFIRMADO** | L1371-1373 lee `cantidad_disponible` crudo; L1380 compara |
| D5 | `preorder_screen.dart:1125-1131` `_getStockFromCache` devuelve la **primera** fila que casa | **CONFIRMADO con matiz** | L1125-1128 `matched = qty; break;`; **L1132** sí devuelve la suma como *fallback* si no hay match |
| D6 | `preorder_screen.dart:2700-2706` cartel «Los siguientes ingredientes no tienen stock suficiente» | **CONFIRMADO** | L2700-2706 literal |
| D7 | `preorder_screen.dart:2824-2828` «Necesario / Disponible **+ unidad**» | **CONFIRMADO** | L2824 y L2828 interpolan `$unidad` |
| D8 | `product_details_screen.dart:3680-3736` desarme sin guarda `esElaborado` | **CONFIRMADO** | bloque L3680-3736 sin `esElaborado`; los únicos `esElaborado` del archivo están en 121-122, 889-890, 1581-1582, 2096-2097, 2280-2281, 2608-2609, 2617-2618, 3112 (ninguno dentro del bloque) |
| D9 | `product_details_screen.dart:3912-3925` `error_code` perdido (sin `on PedidoException`) | **CONFIRMADO** | L3912 `} catch (e) {` + snackbar genérico L3914-3924 |
| D10 | `admin_inventory_service.dart:1229-1238` no excluye elaborados del delta local | **CONFIRMADO** | L1229-1238: `_applyStockDeltaLocally(-qty)` sin comprobar `es_elaborado`; contraste real en `checkout_screen.dart:2183-2190` (`if (item.producto.esElaborado \|\| esServicio) continue;`) |
| D11 | `inventory_service.dart:125-203` indexa por `productId`, **suma** presentaciones y se queda con la primera | **CONFIRMADO** | L186-195: `sumQty += qty; bestRow ??= inv;` y L204-215 usa `bestRow` para ubicación/presentación. Matiz: L165-169 `if (esElaborado \|\| esServicio) return null;` → los elaborados **no** entran a este caché |
| D12 | `fluid_mode_screen.dart:66-106` no-op: `finalizeCurrentOrder` sin `await`, ítems no agregados | **CONFIRMADO** | L94 `_orderService.finalizeCurrentOrder(...)` sin `await`; `_orderItems` (L68) nunca se usa |
| D13 | `mesa_cuenta_service.dart:282-303` = `fn_pedir_item_cuenta` (incluye `p_id_presentacion`) | **CONFIRMADO** | L282-303 |
| D14 | La app espera `INSUFFICIENT_STOCK` / `_PORTIONS` / `_STOCK_INGREDIENT` (`pedido_resultado.dart:180-183`) y `titulo`/`esFaltaDeStock` (`:189-199`) | **CONFIRMADO** | L180-183 exacto; L189-199 `titulo` |
| D15 | `supabase_config.dart:5` debug `qhprswhhfasrikhawjoz`, `:10` release `vsieeihstajlrdvpuooh` | **CONFIRMADO** | L5 y L10 literales |
| D16 | `apertura_screen.dart:781-799` agrupa solo por `id_producto` | **CONFIRMADO** | L781-782 y L789-799 |
| D17 | `auto_sync_service.dart:457-614` `_syncProducts` no manda `ingredientes` | **CONFIRMADO** | `_syncProducts` en L457; la palabra `ingredientes` **no aparece** en todo el archivo (grep 0 coincidencias) |
| D18 | `auto_sync_service.dart:4010-4072` cadena offline | **CONFIRMADO** | L4015 `fn_registrar_venta_offline_v3`, L4023/4035/4046 `fn_registrar_venta_offline`, L4052 fallback a `fn_registrar_venta` |
| D19 | `desarme_bulto_local.dart:96-102` «ya está bien» | **CONFIRMADO** | L96-102: equivalente total = Σ `saldo × factorRel/factorRel_pedida` |
| D20 | `presentacion_cadena_local.dart:111-196` replica `fn_presentaciones_producto` | **CONFIRMADO** | L154-166 cascada `es_base DESC, cantidad ASC, id ASC`; L168-174 orden `cantidad DESC, id ASC`; L184-186 `factorRel = cantidad/base` |
| D21 | `preorder_screen.dart:1271-1594` = validación de inventario; `:2643-2718` = `_checkIngredientsAvailability` | **CONFIRMADO** | L1271 `_checkInventoryAvailability`; L2643 `_checkIngredientsAvailability` (el cartel de L2700 está dentro) |
| D22 | `preorder_screen.dart:2411-2476` guarda `decomposition_data` y el envío lo ignora | **CONFIRMADO** | L2411 `_updateOrderWithDecomposedProducts` |
| D23 | `product_details_screen.dart:506-593` es el rango de `getProductIngredients` | **CONFIRMADO** | el bloque de una fila está en 549-559, dentro del rango |
| D24 | `PLAN_PRESENTACIONES_INVENTARIO.md:845-847` (unidad + equivalente base en gris) y `:523` (colapso de apertura) | **CONFIRMADO** | L845-847 regla de UI; L523 describe `buildFromOfflineCache` + `bestRow ??= inv` |
| D25 | `TUTORIAL_PRUEBAS_PRESENTACIONES.md:1254-1273` afirma que `fn_stock_producto_almacen` «suma sin factor» (desactualizado) | **CONFIRMADO** | L1257 `-- Suma cantidad_final de presentaciones DISTINTAS sin aplicar factor`; la definición viva **sí** aplica `factor_rel` |

---

## 2 · Afirmaciones SQL (funciones vivas de producción)

### 2.1 `fn_descontar_con_rebalanceo_almacen`

| # | Afirmación | Veredicto | Evidencia |
|---|---|---|---|
| S1 | Existe y devuelve `jsonb` | **CONFIRMADO** | `fn_descontar_con_rebalanceo_almacen(bigint,bigint,bigint,numeric,integer,bigint,bigint,bigint,bigint,uuid,text) → jsonb`, md5 `d5740ca01bc2f846e94d0e35aacf03b2` |
| S2 | «Ya valida el equivalente del almacén completo» | **CONFIRMADO** | `SELECT COALESCE(SUM(s.equivalente_base),0) ... FROM fn_stock_saldos_presentacion(p_id_producto, p_id_almacen, NULL, false)` → `IF v_equiv_total < (p_cantidad * v_factor_t) THEN ... 'INSUFFICIENT_STOCK_WAREHOUSE'` |
| S3 | Pasada 1 = saldo propio de la presentación pedida | **CONFIRMADO** | `WHERE s.id_presentacion = p_id_presentacion ... HAVING SUM(s.saldo) > 0 ORDER BY SUM(s.saldo) DESC, s.id_ubicacion`; `v_a_descontar := LEAST(r.saldo, v_pendiente)` |
| S4 | Pasada 2 = «convertir» | **CONFIRMADO** | `TRUNC(SUM(s.equivalente_base) / v_factor_t, 3) AS convertible`; fallo puntual no fatal; si sobra pendiente → `INSUFFICIENT_STOCK_FRAGMENTED` con `movimientos` ya acumulados |
| S5 | «…y **no produce fracciones**: `TRUNC(equiv/factor,3)`» (línea 172 del plan) | **INCORRECTO** | `TRUNC(x,3)` deja 3 decimales, no enteros. Ver **H3**. La garantía de enteros solo existe en `fn_rebalancear_presentaciones` **INTENTO 1** (`CEIL(v_req/v_fhijo)`), no en INTENTO 2 (usa `p_cantidad` fraccionario tal cual) |
| S6 | Es una función «viva, ya probada» | **INCORRECTO (matiz sustantivo)** | **0 llamadores** en producción (`pg_proc.prosrc`, excluyendo comentarios). Nadie la ejercita hoy; `fn_descontar_con_rebalanceo` (la de 1 ubicación) sí la llaman `fn_crear_extraccion_con_movimiento`, `fn_insertar_ajuste_inventario2` y ella misma |

### 2.2 `fn_presentaciones_producto`, marcadores y callers

| # | Afirmación | Veredicto | Evidencia |
|---|---|---|---|
| S7 | Resuelve la base con `es_base DESC, cantidad ASC, id ASC`; `factor_rel = cantidad/base`; **base = 1 por construcción** | **CONFIRMADO** | CTE `base` = `ORDER BY pp.es_base DESC, pp.cantidad ASC, pp.id ASC LIMIT 1`; `round(pp.cantidad / NULLIF(b.cantidad,0), 6)`; la fila base se divide por sí misma → `factor_rel = 1`. Borde no cubierto por el plan: si `base.cantidad` es 0/NULL, `factor_rel` es NULL →
`PRESENTATION_NOT_IN_CHAIN` |
| S8 | `fn_descontar_ingredientes_elaborado` valida con `fn_stock_producto_almacen` (base, 1 almacén) y descuenta con `fn_stock_producto_almacen_detalle` (física) — **C1** | **CONFIRMADO** | Definición viva: `v_disponible := fn_stock_producto_almacen(v_ing.id_ingrediente, p_id_almacen)` vs `FOR v_ubic IN SELECT * FROM fn_stock_producto_almacen_detalle(...)` |
| S9 | Marcadores 22/24/25: `fn_registrar_venta` y `_mesa` tienen `m22/m24/m25=true`; los `_v2` **no** tienen el 25 — **C6** | **CONFIRMADO** | `m25=false` solo en `fn_registrar_venta_v2` (md5 `253d9d16…`) y `fn_registrar_venta_mesa_v2` (`6d34466b…`); `m22=m24=m10=true` en los cuatro. (Extras: `fn_registrar_venta_offline`, `_v2`, `_v3`, `fn_registrar_venta_old` tienen todos los marcadores en `false`) |
| S10 | Callers de `fn_descontar_ingredientes_elaborado` = `fn_descontar_venta_enrutada`, `fn_agregar_producto_orden_pendiente`, `fn_actualizar_cantidad_producto_orden` | **CONFIRMADO** | Consulta de callers sobre `prosrc` sin comentarios: exactamente esos 3 |
| S11 | Callers de `fn_descontar_venta_enrutada` = `fn_registrar_venta`, `_mesa`, `_v2`, `_mesa_v2`, `fn_pedir_item_cuenta` | **CONFIRMADO** | exactamente esos 5 |
| S12 | Callers de `fn_devolver_ingredientes_elaborado` = `fn_cancelar_item_pedido`, `fn_actualizar_cantidad_producto_orden`, `fn_eliminar_producto_orden` | **CONFIRMADO** | exactamente esos 3 |
| S13 | Callers de `fn_validar_ingredientes_elaborado` = `fn_descontar_ingredientes_elaborado`, **`fn_descontar_con_rebalanceo_almacen`** | **INCORRECTO** | El único llamador real es `fn_descontar_ingredientes_elaborado`. En `fn_descontar_con_rebalanceo_almacen` el nombre aparece **solo en un comentario** («mismo criterio que usa `fn_validar_ingredientes_elaborado`»), no en una llamada |
| S14 | `fn_descontar_ingredientes_elaborado` **no llama a ningún rebalanceo** — C3 | **CONFIRMADO** | En su `prosrc` solo aparecen `fn_stock_producto_almacen_detalle` (L29) y `LEAST` (L33); 0 referencias a `fn_descontar_con_rebalanceo(_almacen)` |
| S15 | El `LEAST` mixto está en `fn_descontar_ingredientes_elaborado` **L33** y `fn_descontar_venta_enrutada` **L118** — C2 | **CONFIRMADO** | `prosrc`: L33 y L118 son literalmente `v_a_descontar := LEAST(v_ubic.cantidad_final, v_pendiente);` (misma convención que `27_stock_almacen_en_base.sql:31`) |
| S16 | El bucle a sustituir es **L29-L72** | **CONFIRMADO** | `prosrc` L29 = `FROM fn_stock_producto_almacen_detalle(...)`, L73 = `END LOOP;` |
| S17 | `RAISE EXCEPTION` de `fn_descontar_venta_enrutada` en **L159-162** | **CONFIRMADO con matiz** | `prosrc` L160 = `RAISE EXCEPTION`, L161-163 = mensaje/argumentos (`L159` es la línea en blanco/comentario) |
| S18 | El mensaje «(faltan N)» del bucle está en `01_helpers_bom_almacen.sql:325-329` y la validación se llama primero (`:256-262`) | **CONFIRMADO** | L256-262 y L325-329 literales; el texto del usuario (`disponible:/requerido:`) está en `:184-187` |
| S19 | `fn_stock_producto_almacen_detalle` es física y **no se toca**; `fn_stock_producto_almacen` es base | **CONFIRMADO** | `detalle` devuelve `v.cantidad_final` sin factor (y filtra `cantidad_final > 0`); el escalar vivo es `SUM(d.cantidad_final * COALESCE(f.factor_rel,1))` (`27_stock_almacen_en_base.sql:115-118`) |
| S20 | Tres rutas de cocina sin `fn_cantidad_en_base` — C5 — en `fn_pedir_item_cuenta:85`, `fn_agregar_producto_orden_pendiente:137`, `fn_actualizar_cantidad_producto_orden:119` | **CONFIRMADO con matices** | `fn_cantidad_en_base` **ausente** en las tres ✓. Pero el marcador `m22` es `false` en las tres (el plan dice «tienen el 22/24»; el «22» no se verifica con ese marcador, aunque las tres sí reciben `p_id_presentacion`). Líneas reales del `prosrc`: `fn_pedir_item_cuenta` → `fn_descontar_venta_enrutada` en **L83** (plan dice 85); `fn_agregar_producto_orden_pendiente` → `fn_descontar_ingredientes_elaborado` en **L135** (plan 137); `fn_actualizar_cantidad_producto_orden` → **L117** (plan 119). `fn_pedir_item_cuenta` **no** llama a `fn_descontar_ingredientes_elaborado` (0 ocurrencias) |
| S21 | Devoluciones: `fn_devolver_ingredientes_elaborado` devuelve la cantidad **en base** a una presentación por cascada — C7 | **CONFIRMADO** | `prosrc`: `v_actual + v_ing.cantidad_total_necesaria` (L103/L116); `id_presentacion` por cascada: última de la ubicación (`ORDER BY ip2.id DESC`), última del almacén (`ip3.id DESC`), primera de `app_dat_producto_presentacion` (L92-99); el helper `fn_ubicacion_destino_devolucion` = `detalle ORDER BY cantidad_final DESC` → último `ip.id DESC` del almacén → primer `la.id ASC` |
| S22 | `fn_producir_tanda` resta base de física sin `LEAST` ni factor — C8 | **CONFIRMADO** | `prosrc` L130 `v_actual, v_actual - v_cant_mp` (con `v_cant_mp = cantidad_total_necesaria * ajuste`, L59/L93); no hay `LEAST` en el archivo; `fn_validar_cantidad_final_inventario` **no tiene triggers**, así que el negativo no lo frena la tabla |
| S23 | Código muerto `app_rest_*`: 0 tablas, 0 triggers — §1.8 | **CONFIRMADO** | `pg_namespace` sin esquemas `app_rest%`; 0 tablas. Las 4 funciones citadas existen (5 variantes) y todas contienen `app_rest` en `prosrc` |
| S24 | `fn_resolver_origen_venta` vive en `funcionalidad_cocina/10_enrutamiento_venta_cocina.sql:103-300` | **CONFIRMADO con matiz** | Empieza en L103 ✓; la función termina en **L342** (el siguiente `CREATE OR REPLACE` está en L343) |

### 2.3 Contrato y firmas

| # | Afirmación | Veredicto | Evidencia |
|---|---|---|---|
| S25 | Ninguna firma viva cambia; lo nuevo va a `_vX` | **CONFIRMADO** (diseño) | No existen aún `fn_ingredientes_elaborado_base`, `fn_consumir_ingrediente_base`, `fn_pedir_item_cuenta_v2`, `fn_agregar_producto_orden_pendiente_v2`, `fn_actualizar_cantidad_producto_orden_v2`, `fn_devolver_ingredientes_elaborado_v2`, `fn_cancelar_item_pedido_v2`, `fn_eliminar_producto_orden_v2`, `fn_registrar_venta_v3`, `fn_registrar_venta_mesa_v3` → sin colisión. Sí existen `fn_registrar_venta_offline`, `_v2`, `_v3` → el `_v4` de la Fase 1B es correcto |
| S26 | Códigos nuevos `INSUFFICIENT_STOCK_WAREHOUSE` / `INSUFFICIENT_STOCK_FRAGMENTED` «que ya devuelve» la función viva | **CONFIRMADO** | Ambos literales presentes en la definición viva |
| S27 | La app no se rompe con el cambio in-place | **CONFIRMADO** | Ningún `.dart` del repo llama a `fn_validar_ingredientes_elaborado`, `fn_descontar_ingredientes_elaborado`, `fn_devolver_ingredientes_elaborado` ni `fn_producir_tanda` directamente (0 coincidencias); `fn_disponibilidad_plato` sí lo llama `ventiq_admin_app` (`cocina_service.dart:281`) y el plan no la toca ✓ |
| S28 | El patrón de test `BEGIN … ROLLBACK` de `presentaciones_inventario/05_tests_fase0.sql` existe y no es destructivo | **CONFIRMADO** | `BEGIN` L51 → `ROLLBACK` L370; segundo bloque `BEGIN` L386 → `ROLLBACK` L462; el propio archivo documenta que solo avanza secuencias |
| S29 | La numeración de archivos nuevos (`30…36` en `funcionalidad_cocina/`) está libre | **CONFIRMADO** | El directorio solo tiene `01…25` |

---

## 3 · Números de producción (censo y multi-almacén)

| # | Afirmación | Veredicto | Evidencia (consulta + resultado recortado) |
|---|---|---|---|
| P1 | `fn_validar_ingredientes_elaborado(240,1,12)` → `INSUFFICIENT_STOCK_INGREDIENT`, `disponible: 0, requerido: 1.0` | **CONFIRMADO** (el texto) | `{"status":"error","message":"Stock insuficiente para el ingrediente: pan solo (disponible: 0, requerido: 1.0)","error_code":"INSUFFICIENT_STOCK_INGREDIENT","id_ingrediente":238,"cantidad_requerida":1.0,"cantidad_disponible":0}` |
| P2 | … «con **160** del ingrediente **239** en otro almacén de **la misma tienda**» | **INCORRECTO** | El que falla es el **238** (no el 239); 239 tiene 160 ✓ pero en **almacén 1 / tienda 1**; los almacenes de tienda 11 (12 y 15) están a 0. Ver **H1** |
| P3 | Elaborados en producción: **124** en **14 tiendas** | **CONFIRMADO** | `count(*) = 124`, `count(distinct id_tienda) = 14` (`es_elaborado AND deleted_at IS NULL`) |
| P4 | **0** elaborados con ingrediente de `factor_rel <> 1` con saldo | **CONFIRMADO** | `elaborados_con_ingrediente_fx = 0` y `elaborados_propios = 0` |
| P5 | Factores ≠ 1 con saldo: **6 combos / 9 filas / 6 productos / 3 tiendas**, 0 elaborados | **CONFIRMADO** (definición §7.2: «combo» = producto+almacén) | 9 filas = 4545 (Caja ×24, 533), 4558 (Caja ×24, 15), 11001 (Caja ×24, 49; Bulto ×5, 2.8), 11007 (Caja/Blister/Cajón ×24/6/30, 30/23/13), 11151 (×12, 218), 11152 (×12, 185); 6 `distinct (producto, almacén)`; 6 productos; tiendas 25, 223, 227; **0 elaborados**. (Nota metodológica propia: la primera medición dio 0 porque uní por `app_dat_producto_presentacion.id_presentacion` (nominal) en vez de `pp.id`; el `id_presentacion` que usan el ledger y `fn_presentaciones_producto` es `pp.id`) |
| P6 | Multi-almacén: **36 elaborados / 8 tiendas** con «mejor almacén < total de la tienda» | **CONFIRMADO** con la métrica de §7.4 | Reproducido 36/8. Reparto por tienda: 25→21, 47→3, 223→3, 221→3, 224→3, 57→1, 69→1, 11→1 |
| P7 | …pero «total de la tienda» = `fn_stock_producto_almacen(ing, NULL)` = **toda la plataforma** | **INCORRECTO** (metodología) | Con «toda la tienda» restringido a los almacenes del propio `id_tienda`: **35 / 7**; el único caso de tienda 11 es 240 y su «80 producible» viene de la tienda 1. Ver **H2** |
| P8 | «tienda 25 con **0** producible en **6** elaborados» | **INCORRECTO** | Medido: dentro de los 36, tienda 25 aporta **21** filas (20 con `mejor_almacen = 0`); en total, **32** elaborados de tienda 25 con `mejor_almacen = 0` (49 con receta). Ninguna métrica reproducida da 6 |
| P9 | «tienda 25 con 0 producible» (agregado del §11 de la fuente) | **CONFIRMADO con matiz** | El fenómeno es real (20-32 elaborados según el subconjunto), pero el número exacto del plan (6) no |
| P10 | Debug: migraciones/marcadores D0-D10 y arroz moro 3/4/5 | **NO VERIFICABLE** | El MCP apunta a producción; `qhprswhhfasrikhawjoz` no es accesible en esta sesión |
| P11 | «Simulado sobre filas reales del 11007: para 1000 base el bucle vacía 68 piezas = 1250 base y responde `(faltan 932)`» | **NO VERIFICABLE** | Requiere ejecutar la escritura; no se ejecuta. Las filas base del 11007 sí existen (Caja ×24, Blister ×6, Cajón ×30 con 30/23/13 en la ubicación 349) |

---

## 4 · Fase 1: retrocompatibilidad y el caso gramos + Kilogramo (punto crítico)

| # | Aspecto | Veredicto | Detalle |
|---|---|---|---|
| F1 | Misma firma y mismo `jsonb` en `fn_descontar_ingredientes_elaborado` | **CONFIRMADO** | Firma `(bigint,numeric,bigint,bigint,integer)` intacta; los 3 llamadores solo miran `status` y propagan el jsonb |
| F2 | «La única excepción son **los dos** `LEAST`» (§4.3) | **INCORRECTO (inconsistencia)** | La Fase 1 también reescribe **en sitio** `fn_validar_ingredientes_elaborado` (línea 174), y la Fase 8 (línea 278) habla de «**las tres** in-place». El plan debe unificar el criterio y justificar el tercer cambio, que **no** es un `LEAST` |
| F3 | Cambiar `cantidad_disponible` de física → equivalente base «mantiene el contrato jsonb» | **CONFIRMADO con riesgo** | Los campos se conservan, pero **cambia el valor** y aparece `maximo_producible`; hoy el único consumidor SQL es `fn_descontar_ingredientes_elaborado` y no hay consumidor Dart directo (S27), así que es seguro *si* se documenta como cambio de semántica y se re-afirman los GRANT |
| F4 | Delegar el consumo en `fn_descontar_con_rebalanceo_almacen` cubre «receta en gramos + stock en Kilogramo» | **CONFIRMADO como mecanismo** | Con base = Gramo (`factor_rel = 1`) y kg (`factor_rel = 1000`): validación global `Σ equivalente_base ≥ cantidad` ✓; pasada 1 consume gramos; pasada 2 `TRUNC(3000/1,3) = 3000` y `fn_rebalancear_presentaciones` abre el kg (INTENTO 1, `CEIL`) en 1000 g enteros ✓ |
| F5 | …**sin fracciones** | **INCORRECTO** | Ver **H3**. `TRUNC(…,3)` no garantiza enteros y la rama SKU/non-base del plan cae directamente en el caso fraccionario. La regla 4 y el «caso 4» de la Fase 1 no están soportados por la función viva; haría falta el planificador de enteros (`fn_planificar_cumplimiento_presentaciones_v2` / `presentaciones_inventario/38_…`) o validar `p_cantidad` entero por nivel |
| F6 | …**y sin negativos** | **CONFIRMADO** | `fn_descontar_con_rebalanceo` relee el ledger y exige `v_saldo >= p_cantidad` (`REBALANCE_INCONSISTENT` antes de escribir); no se observó camino que deje negativo en esta ruta |
| F7 | «Validar y consumir con la misma medida → nunca más “la validación dice sí y el descuento no”» | **INCORRECTO** | Reproducible: la validación global puede pasar y la pasada 2 devolver `INSUFFICIENT_STOCK_FRAGMENTED` (o el fallo puntual de una ubicación), y encima el error llega **después** de escrituras parciales y `fn_registrar_venta` lo devuelve sin `RAISE` (L364-367) → commit parcial. La decisión 2 necesita (a) pre-validar «hay combinación entera» o (b) `RAISE`/rollback explícito |
| F8 | El `RAISE EXCEPTION` de `fn_descontar_venta_enrutada` L160 «se conserva» | **INCORRECTO (hueco)** | Si la rama SKU se sustituye por el helper, este devuelve `jsonb` de error, no lanza. Para conservar el rollback hay que **re-lanzar** explícitamente cuando el helper falla; el plan no lo dice |
| F9 | `fn_descontar_ingredientes_elaborado` y la validación nueva medirán lo mismo | **CONFIRMADO con matiz** | Ambas usan `saldo × factor_rel` con la misma cascada de base. Divergencia de filtros: `fn_stock_producto_almacen_detalle` descarta `cantidad_final <= 0`, mientras `fn_stock_saldos_presentacion(..., p_incluir_cero := false)` descarta **solo `= 0`** e incluye negativos → con saldos negativos la «misma medida» no es idéntica |
| F10 | Presentación base con `factor_rel <> 1` | **NO APLICABLE / borde no cubierto** | Imposible por construcción (`base` se divide por sí misma → 1). El borde real es `base.cantidad = 0/NULL` → `factor_rel` NULL → `PRESENTATION_NOT_IN_CHAIN`; el plan no lo trata. La R11 (kg y gramo ambos `cantidad = 1`) sí está cubierta por la Fase 0/D3 |
| F11 | Variantes/opciones | **NO CUBIERTO (no es regresión)** | `fn_descontar_con_rebalanceo_almacen` con `p_id_variante = NULL` **suma y consume todas las variantes**; el consumo de receta de hoy tampoco distingue variante. El plan no menciona el comportamiento |

---

## 5 · Correcciones concretas que el lead debe aplicar

1. **§0.1 (línea 26) y §12 (línea 361) — reescribir la evidencia de 240.** Sustituir «con **160** del ingrediente **239** en otro almacén de la misma tienda» por: «elaborado 240 (tienda 11) falla en el ingrediente **238** (`disponible 0, requerido 1.0`); el 238 tiene 980 y el 239 tiene 160 **en el almacén 1 de la tienda 1**; los almacenes 12 y 15 de la tienda 11 están a 0. Es un caso **inter-tienda**, no multi-almacén intra-tienda».
2. **Fase 5, prueba (líneas 243-244) — cambiar el elaborado de prueba.** 240 **no** puede pasar con `'tienda'`. Usar uno del subconjunto intra-tienda (35/7). Y corregir la afirmación «por tienda» del §10/§12: la métrica §7.4 usa `p_id_almacen = NULL` (toda la plataforma); hay que recalcular el censo con «almacenes del propio `id_tienda`».
3. **§10 (línea 336) — corregir «tienda 25 con 0 producible en 6 elaborados»** por los valores medidos: 20 de las 21 filas de tienda 25 en el censo tienen mejor almacén = 0 (32 elaborados de tienda 25 en total).
4. **§5 (línea 145) — borrar el caller falso** `fn_validar_ingredientes_elaborado ← fn_descontar_con_rebalanceo_almacen`; el nombre aparece solo en un comentario. Dejar `fn_descontar_ingredientes_elaborado` como único caller (y anotar que `fn_descontar_venta_enrutada` es el único camino de venta hacia él).
5. **Fase 1, línea 172 — eliminar «y no produce fracciones: `TRUNC(equiv/factor,3)`».** Es falso (H3). O bien (a) el helper exige `p_cantidad_base` entero y `factor_rel` del destino = 1, o (b) se usa el planificador de enteros (`fn_planificar_cumplimiento_presentaciones_v2`, `presentaciones_inventario/38_…`), o (c) se acepta y documenta la fracción — pero entonces la decisión 4 (línea 114) y el «caso 4» de la Fase 1 (línea 184) deben reescribirse.
6. **Decisión 2 / criterio de aceptación 5 (líneas 112 y 185) — añadir el tratamiento del fallo parcial.** Con la función viva, `INSUFFICIENT_STOCK_FRAGMENTED` llega con `movimientos` ya escritos y `fn_registrar_venta` **RETURNA** el error (prosrc L364-367) sin rollback. El plan debe pre-validar la existencia de una combinación entera **antes** de tocar el ledger, o re-lanzar excepción para forzar el rollback.
7. **§4.3 (línea 124) vs Fase 1 (línea 174) vs Fase 8 (línea 278) — unificar el número de cambios in-place (2 vs 3)** y justificar aparte el de `fn_validar_ingredientes_elaborado`, que cambia el **valor** de `cantidad_disponible` (no solo el cálculo): documentarlo como cambio de semántica visible en los mensajes de error y re-afirmar los GRANT.
8. **Fase 1, línea 176 — explicitar que el `RAISE EXCEPTION` de `fn_descontar_venta_enrutada` (prosrc L160) hay que re-emitirlo** cuando el helper devuelva `jsonb` de error, so pena de cambiar el contrato (hoy excepción/rollback; después, error devuelto y commit parcial).
9. **Citas `L` menores a corregir**: `RAISE EXCEPTION` = prosrc **L160-163** (no 159-162); C5 = `fn_pedir_item_cuenta` ruta en **L83**, `fn_agregar…` BOM en **L135**, `fn_actualizar…` BOM en **L117**; `10_enrutamiento_venta_cocina.sql` la función va de L103 a **L342**.
10. **§3.1 C5 — ajustar «tienen el 22/24»**: el marcador `m22` es `false` en las tres rutas (manejan `id_presentacion`, pero no con el patrón del marcador). Redactarlo como «reciben `p_id_presentacion` pero no llaman a `fn_cantidad_en_base`».
11. **Fase 1, dependencia (línea 190) — añadir** que `fn_descontar_con_rebalanceo_almacen` tiene **0 llamadores** en producción: es funcionalidad nueva de facto y necesita pruebas propias, no «ya está viva».
12. **Fase 7 P2 (línea 270) / D5** — precisar que `inventory_service.dart:165-169` **excluye elaborados** del caché offline; el colapso afecta a productos con presentaciones (no a elaborados), y `_getStockFromCache` sí tiene un *fallback* de suma (L1132).

---

## 6 · Afirmaciones NO VERIFICABLES en esta sesión

1. Todo el paquete de debug `qhprswhhfasrikhawjoz` (D0-D10, marcadores D1/D2, catálogo real de arroz/frijoles/arroz moro y los ids 3/4/5): el MCP apunta a producción. Fuente del síntoma del usuario, no comprobable aquí.
2. La simulación aritmética del §4.3 de la fuente (`faltan 932`, «vacía el estante»): requeriría escritura; descartada por regla.
3. La afirmación «los builds ya instalados siguen con el bug» (base de la discusión Fase 1 vs 1B): no hay forma de inspeccionar builds desplegados desde aquí. Lo que sí se comprobó es que el código actual de la app llama a los RPC **sin** `_v2` (D2).
4. Las pruebas de UI de §8 (dispositivo) y «que el cartel desaparece»: no ejecutables aquí.
5. `orders` / `advisors` tras aplicar: no aplica (nada aplicado).

---

## 7 · Lo que el plan acierta (para no reabrir)

Verificados y correctos, y por tanto **no** deben cambiarse salvo lo listado en §5: C1, C2 (L33/L118), C3, C4 (36/8 como métrica), C6, C7, C8, D1-D25 (salvo los matices anotados), S1-S4, S7, S19, S26-S29, P1 (texto), P3-P6, F1, F4, F6, y el diseño de «no tocar firmas vivas» con `_vX` (S25).