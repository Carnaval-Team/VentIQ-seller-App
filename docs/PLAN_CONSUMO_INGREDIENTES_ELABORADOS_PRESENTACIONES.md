# Plan: consumo de ingredientes de elaborados y venta con presentaciones (kg ↔ gramos)

**Fecha:** 2026-10-21 · **Owner:** lead · **Estado:** plan listo para ejecutar (nada implementado todavía)
**Revisiones:** verificación adversarial en `docs/_analisis/VERIFICACION_PLAN.md` (76 afirmaciones, 10 corregidas) **+ medición directa del proyecto debug del 2026-10-21** (§2-bis) **+ decisión del usuario: Fase 1 = cadena `_v2`/`_v3` sin tocar funciones vivas (1B)**.

**Proyectos Supabase afectados (los dos):**
debug `qhprswhhfasrikhawjoz` (el que usa `flutter run`, `ventiq_app/lib/config/supabase_config.dart:5`) y
release/producción `vsieeihstajlrdvpuooh` (`:10`).
El plan **no** cambia la configuración MCP: producción sigue siendo la default.

**Documentos de evidencia:**

- `docs/_analisis/INGREDIENTES_SQL.md` (1023 líneas) — definiciones vivas de producción, callers, censo, paquete D0–D10.
- `docs/_analisis/INGREDIENTES_DART.md` (724 líneas) — rutas de venta de `ventiq_app`, origen de cada cartel, caché offline.
- `docs/_analisis/VERIFICACION_PLAN.md` — verificación adversarial de este plan.
- §2-bis de este documento — **medición real del caso del usuario en el proyecto debug**, hecha el 2026-10-21 en modo solo lectura sobre `qhprswhhfasrikhawjoz`.

**Documentos hermanos:** `docs/PLAN_PRESENTACIONES_INVENTARIO.md`, `docs/PLAN_CUMPLIMIENTO_FISICO_PRESENTACIONES.md`, `docs/TUTORIAL_PRUEBAS_PRESENTACIONES.md`.

**Regla de trabajo:** no se cambia la **firma** de ninguna función viva; todo lo nuevo va a `_v2`/`_v3` y el Dart se migra aparte (decisión del usuario, §11 pregunta 1 resuelta).

---

## 0 · Resumen: qué pasa exactamente (confirmado con el cartel y con los datos)

El usuario vendió **10 Arroz Moro** (elaborado 5, tienda 4, TPV «Caja 1», almacén 3; receta: Frijoles 4 × 500 y Arroz 3 × 600, con `unidad_medida = null`). La app mostró el diálogo **«Problema de Inventario»**:

```
Arroz Moro - Variante 1 - Unidad → Frijoles   Pedido: 5000  En stock: 2500  Faltante: 2500
Arroz Moro - Variante 1 - Unidad → Arroz      Pedido: 6000  En stock: 2000  Faltante: 4000
```

**Ese cartel es 100 % del cliente y es el único bloqueo de esa venta.** Es `_checkInventoryAvailability` (`preorder_screen.dart:1271-1576`, diálogo en `:1642-1750`), que para un elaborado online usa `ProductDetailService.getProductIngredients`, y esa consulta pide **una sola fila** por ingrediente:

```dart
// product_detail_service.dart:549-559   (es exactamente la consulta del curl que pegó el usuario)
.from('app_dat_inventario_productos').select('cantidad_final')
.eq('id_producto', idIngrediente)
.order('created_at', ascending: false).limit(1)
```

Medido en debug (§2-bis): para el Arroz la fila más reciente es `Unidad = 2000` (13:58:03) y para los Frijoles `Unidad = 2500` (13:58:03); **las filas `Kilogramo` de 2000 kg y 2500 kg son anteriores (13:54:37) y el cliente jamás las mira**. De ahí «En stock: 2000 / 2500». El equivalente real en el almacén 3 es **2.002.000** y **2.502.500** unidades base, y el **servidor ya lo sabe**:

```
fn_stock_producto_almacen(3, 3)                = 2002000        fn_validar_ingredientes_elaborado(5, 10, 3) = {"status":"success", ...}
fn_stock_producto_almacen(4, 3)                = 2502500        (disponible 2502500 y 2002000 ≥ 5000 y 6000)
```

Conclusión: **el servidor valida bien y el cliente bloquea con un número falso**. Ese es el arreglo que desbloquea al usuario (Dart, Fase 7 P0).

**Pero no se puede desplegar sólo el arreglo del cliente.** En cuanto la venta pase la barrera del cliente, cae en el defecto SQL del `LEAST` mixto (§3.1 C2) y, con los saldos reales que hay hoy en debug, esto es lo que escribiría:

| Ingrediente | pendiente base | filas del detalle (`ORDER BY cantidad_final DESC`; **empate**) | qué hace el bucle (simulado) | resultado **medido** |
|---|---|---|---|---|
| Arroz 3 | 6000 | Unidad 2000 → Kilogramo 2000 | descuenta 2000 (Unidad) y 2000 (kg), pendiente 2000 | deja **2000 u y 2000 kg en cero** y responde `(faltan 2000)` |
| Frijoles 4 | 5000 | Unidad 2500 → Kilogramo 2500 | descuenta 2500 (Unidad) y 2500 (kg), pendiente 0 | **`status: success`** tras consumir 2500 u **+ 2500 kg** (2.500.000 base en vez de 5000); el estante de frijoles queda en cero y la venta se cobra como buena |

La simulación exacta (CTE recursivo que replica el `FOR` del helper, solo lectura, sobre las filas reales de §2-bis) da `pendiente_despues = 2000` para el arroz y `0` para los frijoles: **el caso de los frijoles no falla, destruye inventario en silencio**. Además, `fn_obtener_ingredientes_recursivos` devuelve **Frijoles (4) antes que Arroz (3)**, así que cuando el arroz lanza «(faltan 2000)» **ya hay escrituras de los frijoles** (Unidad 2500 → 0 y Kilogramo 2500 kg → 0). Y como `fn_registrar_venta` **RETURNA** el jsonb de error sin `RAISE` (`VERIFICACION_PLAN.md` H3; `prosrc` L364-371), los movimientos del arroz **se confirman** igual: la venta se reporta fallida y el almacén queda saqueado. Es el riesgo más grave del plan (§4.14 y §9).

**Orden obligatorio:** primero SQL (`_v2`/`_v3` + venta `_v3`, aplicado en ambos proyectos), **después** el release de Dart que arregla el cliente y apunta a las RPC nuevas. Nunca al revés.

**El «empate» explica el «a veces gramo, a veces kg».** Con las dos filas en el mismo número (2000/2000 y 2500/2500) el `ORDER BY v.cantidad_final DESC, v.id_ubicacion` (`01_helpers_bom_almacen.sql:101`) **no tiene desempate** y PostgreSQL elige el orden que quiera en cada plan/ejecución. Antes de este caso, el «a veces» también salía de que cada movimiento **inserta una fila nueva** y el cliente lee «la más reciente».

**Hipótesis descartadas con datos:** (a) al proyecto debug **no** le faltan migraciones — `27` está aplicada (los totales 2.002.000 / 2.502.500 sólo salen aplicando `factor_rel`), `24`, `22`, `25`, el pack v2 y las tablas de eventos existen; (b) el catálogo está bien: `Kilogramo` fila 8/7 con `cantidad = 1000` y `factor_rel = 1000`, `Unidad` fila 4/5 base con `factor_rel = 1`; (c) no es multi-almacén en este caso: todo el stock está en la ubicación 3 / almacén 3.

---

## 1 · El emisor del cartel (confirmado)

| Texto visto por el usuario | Emisor | ¿Bloquea? |
|---|---|---|
| **`Problema de Inventario` + `Pedido / En stock / Faltante`** | **cliente**: `_finalizeOrder` llama `_checkInventoryAvailability` (`preorder_screen.dart:926`) y, si hay problemas, muestra `_showStockProblemsDialog` (`:933`) y **retorna sin cerrar la venta** (`:934`). La comprobación usa `getProductIngredients` (`:1356`) y el diálogo es `:1642-1750` (título `:1657`, chips `Pedido/En stock/Faltante` `:1700-1724`) | **sí**, bloquea la venta |

Otros emisores que existen pero **no** son este caso (se corrigen igual en el plan): `⚠️ Stock Insuficiente` con `Necesario/Disponible <unidad>` (`preorder_screen.dart:2700-2706`, `:2824-2828`, no bloqueante) y los del servidor `INSUFFICIENT_STOCK_INGREDIENT` / `INSUFFICIENT_STOCK` / `INSUFFICIENT_PORTIONS` (`01_helpers_bom_almacen.sql:184-187` y `:325-329`, `10_enrutamiento_venta_cocina.sql`).

---

## 2 · Fase 0 · Diagnóstico (estado 2026-10-21)

- [x] Acceso de solo lectura al proyecto debug disponible (endpoint MCP con `project_ref=qhprswhhfasrikhawjoz&read_only=true`); producción sigue en el MCP default.
- [x] **D1 parcial**: migraciones de presentaciones presentes en debug (`27`, `24`, `22`, `25`, v2 y tablas de eventos). No falta ninguna de las que este plan necesita.
- [x] **D3 parcial**: catálogo de Arroz/Frijoles/Arroz Moro medido (§2-bis).
- [x] **D4 parcial**: `fn_stock_producto_almacen` por almacén = equivalente base correcto; validación del servidor = `success`.
- [ ] **D5**: almacén/TPV ya identificados (TPV 3 «Caja 1» → almacén 3, tienda 4). Falta confirmar si el usuario vende desde otro TPV.
- [ ] **D1/D2 completos en producción** (marcadores) como referencia.
- [ ] Confirmar en debug el estado de `check_user_has_access_to_tienda` (§3.1 C9) y su impacto.
- [ ] Pegar en este documento el anexo del resto de productos elaborados de la tienda 4.

**Criterio de aceptación:** el anexo §2-bis está cerrado y cada decisión de las Fases 1–5 tiene su número real.

---

## 2-bis · Anexo · Medición real del caso (proyecto debug, 2026-10-21, solo lectura)

**Productos y presentaciones** (`app_dat_producto` + `app_dat_producto_presentacion` + `app_nom_presentacion`):

| Producto | Elaborado | Tienda | Cocina | Fila pp | Presentación | `cantidad` | `es_base` | `factor_rel` |
|---|---|---|---|---|---|---|---|---|
| 3 Arroz | no | 4 | — | 8 | Kilogramo | 1000 | false | **1000** |
| 3 Arroz | | | | 4 | Unidad | 1 | **true** | 1 |
| 4 Frijoles | no | 4 | — | 7 | Kilogramo | 1000 | false | **1000** |
| 4 Frijoles | | | | 5 | Unidad | 1 | **true** | 1 |
| 5 Arroz Moro | **sí** | 4 | **null** (ruta barra) | 6 | Unidad | 1 | **true** | 1 |

**Receta** (`app_dat_producto_ingredientes`, `id_producto_elaborado = 5`): Frijoles (4) × **500**, Arroz (3) × **600**, `unidad_medida = null`. Con 10 unidades: 5000 y 6000 — exactamente los «Pedido» del cartel.

**Saldos vigentes** (última fila del ledger por combinación, ubicación 3 / almacén 3):

| Producto | `id_presentacion` | Presentación | `cantidad_final` | `created_at` |
|---|---|---|---|---|
| 3 | 4 | Unidad (base) | **2000** | 13:58:03 |
| 3 | 8 | Kilogramo | **2000** (kg) | 13:54:37 ← *el cliente no la ve* |
| 4 | 5 | Unidad (base) | **2500** | 13:58:03 |
| 4 | 7 | Kilogramo | **2500** (kg) | 13:54:37 ← *el cliente no la ve* |

**Qué devuelve cada capa:**

| Llamada | Resultado |
|---|---|
| `getProductIngredients` (Dart, `created_at DESC LIMIT 1`) | Arroz 2000 · Frijoles 2500 → **el cartel** |
| `fn_stock_producto_almacen(3, 3)` | **2.002.000** base |
| `fn_stock_producto_almacen(4, 3)` | **2.502.500** base |
| `fn_stock_producto_almacen(3, NULL)` / `(4, NULL)` | idénticos (todo el stock está en la tienda 4) |
| `fn_validar_ingredientes_elaborado(5, 10, 3)` | **`success`**, disponible 2502500 / 2002000 |
| `fn_stock_producto_almacen_detalle(3, 3)` / `(4, 3)` | dos filas cada uno, **mismo número** (empate) |

**Fingerprints de ambos proyectos** (md5 de `pg_get_functiondef`): `check_user_has_access_to_tienda` = `438dbaec…`, `fn_ejecutar_entrega_fisica_v2` = `9edf415b…`, `fn_preview_entrega_fisica_v2` = `c46c5d97…` → **idénticos en debug y producción**.

**Notas de método:** `factor_rel` **no es una columna**: lo calcula `fn_presentaciones_producto` (la tabla de presentaciones guarda `cantidad` y `es_base`). Y sobre C9, el censo correcto en cada proyecto es **31 funciones con `search_path` vacío**, de las que **8 llaman al guard** y **solo 4 rompen**; dos de las que rompen (`fn_registrar_venta_offline_v2`, `fn_registrar_venta_offline_v3`) **ya las llama la app** (`auto_sync_service.dart:4015`), así que C9 no es latente: es un fallo vivo del camino offline.

**Lecturas de esta medición:**

1. El bloqueo es del cliente; el servidor está bien en la validación.
2. `fn_descontar_ingredientes_elaborado` sigue con el `LEAST` mixto (len 3909, igual que producción) y **sí** está activo en el camino de descuento: las filas de 2000 kg son la munición del desastre descrito en §0.
   **Simulación del bucle actual** (CTE recursivo con el mismo orden, solo lectura): Arroz 6000 → `2000 (Unidad) → 2000 (kg) → pendiente 2000` ⇒ `(faltan 2000)` con las dos filas a cero; Frijoles 5000 → `2500 (Unidad) → 2500 (kg) → pendiente 0` ⇒ **`success` tras consumir 2500 kg**. Medido el 2026-10-21.
3. El empate de `cantidad_final` documenta la percepción de aleatoriedad.

---

## 3 · Causa raíz

### 3.1 Capa SQL

| # | Defecto | Evidencia |
|---|---|---|
| C1 | **Validación y consumo miden distinto**: la validación usa el escalar (base, con `factor_rel`), el consumo usa el detalle (física de la presentación). | `01_helpers_bom_almacen.sql:175` vs `:271-277` |
| C2 | **`LEAST` mixto** en dos sitios: física vs base. | `fn_descontar_ingredientes_elaborado:33`, `fn_descontar_venta_enrutada:118` |
| C3 | **El consumo de receta nunca pasa por el rebalanceo** (0 referencias): imposible abrir un kg. | `INGREDIENTES_SQL.md` §1.3 |
| C4 | **Alcance de almacén** en la validación (`:175`) y en `fn_disponibilidad_plato`. En producción el caso `240` es **inter-tienda** (el rechazo es correcto); el censo real intra-tienda es **35 elaborados / 7 tiendas**. | `VERIFICACION_PLAN.md` hallazgos 1–2 |
| C5 | **Tres rutas de cocina no convierten la cantidad** (`m22=false`, `m24=false`): `fn_pedir_item_cuenta`→L83, `fn_agregar_producto_orden_pendiente`→L135, `fn_actualizar_cantidad_producto_orden`→L117. | `INGREDIENTES_SQL.md` §1.5 |
| C6 | **`_v2` de venta con huecos**: `fn_registrar_venta_v2`/`_mesa_v2` **sí** llaman a `fn_ejecutar_entrega_fisica_v2` (L259, que abre/arma), pero **no** traen el parche `25` y además su ejecutor está roto por C9 (`RAISE` en L265-269). La app usa los nombres sin `_v2` (`order_service.dart:1442-1443`), así que hoy no se ejerce. | `VERIFICACION_PLAN_2.md` (B/C6) |
| C7 | **Devoluciones**: devuelve base a una presentación elegida por cascada (`pp.id ASC`). | `§1.7` |
| C8 | **Tandas** (`fn_producir_tanda`) restan base de física sin `LEAST` ni factor. | `§1.7` |
| C9 | **Relación rota por `search_path`** (nuevo, medido): `fn_ejecutar_entrega_fisica_v2` y `fn_preview_entrega_fisica_v2` tienen `SET search_path = ''` y llaman a `check_user_has_access_to_tienda`, que **no** tiene `SET` propio y usa tablas **sin calificar** (`app_dat_vendedor`, …). Resultado real en debug: **42P01 `relation "app_dat_vendedor" does not exist`** (la tabla existe; es el `search_path` vacío heredado). Fingerprints idénticos en ambos proyectos ⇒ **el mismo fallo está en producción**. **No es latente**: `auto_sync_service.dart:4015` ya llama a `fn_registrar_venta_offline_v3`. Medido en **cada** proyecto: **31 funciones con `search_path` vacío**, **8 llaman al guard** y **solo 4 rompen** (`fn_ejecutar_entrega_fisica_v2`, `fn_preview_entrega_fisica_v2`, `fn_registrar_venta_offline_v2`, `fn_registrar_venta_offline_v3`); las de «cumplimiento» no llaman al guard y otras 4 se auto-corrigen con `set_config`. | 42P01 reproducido en debug; `VERIFICACION_PLAN_2.md` (C9); md5 idénticos debug↔producción |
| C10 | **Commit parcial**: `fn_registrar_venta` RETURNA el error del BOM sin `RAISE` (`prosrc` L364-371; cadena `fn_descontar_venta_enrutada` L44-62 / `fn_descontar_ingredientes_elaborado` L81-95) ⇒ un fallo del descuento **confirma** lo ya escrito. Con las filas de §2-bis, arreglar sólo el cliente **saquea el almacén**. | `VERIFICACION_PLAN.md` H3/F7/F8; `VERIFICACION_PLAN_2.md` (B) |

### 3.2 Capa cliente (`ventiq_app`)

| # | Defecto | Evidencia |
|---|---|---|
| D1 | **`getProductIngredients` lee UNA fila** (la más reciente, sin presentación, sin factor, sin sumar). **Es el cartel reportado.** | `product_detail_service.dart:549-559`; `preorder_screen.dart:1367-1380`, `:2643-2718`, `:1642-1750` |
| D2 | **El reparto de la receta se calcula y se tira**: `decomposition_data` se guarda y el envío lo ignora. | `preorder_screen.dart:2411-2476`; `order_service.dart:1360-1385` |
| D3 | **El desarme de presentaciones se aplica también a elaborados** en la ficha. | `product_details_screen.dart:3680-3736` vs `:121`, `:1581`, `:2096`, `:2608` |
| D4 | **El `error_code` del servidor se pierde**: sin rama `on PedidoException`. | `product_details_screen.dart:3912-3925`; `pedido_resultado.dart:180-199` |
| D5 | **Caché local colapsa el producto** por `productId`; **los elaborados están excluidos** (`inventory_service.dart:165-169`), así que no afecta a este caso. | `inventory_service.dart:125-203`; `apertura_screen.dart:781-799` |
| D6 | **`_getStockFromCache` devuelve la primera fila que casa**; tiene respaldo de suma en `:1132`. | `preorder_screen.dart:1125-1132` |
| D7 | **Venta por acuerdo no excluye elaborados** del delta local. | `admin_inventory_service.dart:1229-1238` |
| D8 | **Modo fluido es un no-op** (`finalizeCurrentOrder` sin `await`, sin agregar ítems). | `fluid_mode_screen.dart:66-106` |
| D9 | **`cocina_offline_queue.dart`** sin llamadores: pedido de cocina sin red no se encola. | `INGREDIENTES_DART.md` §1.6 |

---

## 4 · Semántica cerrada (decisiones)

1. **Unidad de cuenta = unidad base del ingrediente** (`factor_rel`; la base da 1).
2. **Validar y consumir con la misma medida y el mismo alcance** (cierra C1 y C4). Caveat: `fn_stock_producto_almacen_detalle` descarta `<= 0` y `fn_stock_saldos_presentacion(..., false)` sólo `= 0` (incluye negativos).
3. **Consumo por equivalente base exacto**; cada escritura al ledger en la presentación realmente movida (física − física), con su conversión auditada.
4. **Sin fracciones de empaque**: la exactitud entera la da el planificador v2; `TRUNC(equiv/factor, 3)` **no** es garantía de enteros (contraejemplo vivo 1,25/0,75 Cajas).
5. **`fn_stock_producto_almacen_detalle` NO se toca** (su `cantidad_final` es lo que se persiste).
6. **No se toca ninguna firma viva**, y por decisión del usuario **tampoco el cuerpo de las funciones vivas** (§4.3).
7. **Contrato de error estable**: `INSUFFICIENT_STOCK` / `INSUFFICIENT_STOCK_INGREDIENT` / `INSUFFICIENT_PORTIONS`; los códigos nuevos se traducen en la frontera del BOM.
8. **Alcance por defecto = almacén resuelto** por `fn_resolver_origen_venta`. Pasar a «tienda» es decisión de negocio; consumir de otra tienda, no.
9. **Los precios no se tocan** (`precio base × factor_rel`).
10. **Nada «aplanado» en el caché**; si se cachea la receta, con presentaciones.
11. **Variantes**: la receta no las nombra; el helper acepta `p_id_variante`/`p_id_opcion_variante` y por defecto mantiene el comportamiento actual, registrando qué variantes movió.
12. **Atomicidad**: pre-validar todo antes de la primera escritura **y** `RAISE EXCEPTION` si hubiera que abortar después (por C10).
13. **Nuevo ejecutor `fn_ejecutar_entrega_fisica_v3`** (nuevo, no se toca el `_v2`): copia del `_v2` con `search_path` correcto (`public, pg_catalog` o nombres calificados) para esquivar C9, y con la verificación de plan no-nulo y saldo antes de escribir.
14. **Secuencia obligatoria**: SQL primero, Dart después. El release que arregla el cliente **debe** ir acompañado del cambio a `fn_registrar_venta_v3`.

### 4.3 Decisión: Fase 1 = `_v2`/`_v3`, sin tocar funciones vivas (1B)

Elegido por el usuario. Consecuencias, explícitas:

- **Los builds ya instalados conservan el bug** del `LEAST` mixto (C2) y del cliente (D1). La ventana se cierra cuando el release migre el Dart a las RPC nuevas y a `getProductIngredients` corregido.
- Por lo mismo, **la Fase 3 (`_v3` de venta) deja de ser opcional**: es la única forma de que la app nueva use la cadena corregida sin tocar `fn_registrar_venta`.
- Se conservan los md5 de las funciones vivas como prueba de no-regresión (§6 Fase 8).
- La alternativa in-place (corregir los tres cuerpos: `fn_descontar_ingredientes_elaborado`, `fn_validar_ingredientes_elaborado`, `fn_descontar_venta_enrutada` L118) queda **descartada**, pero documentada en §4.4 por si se quisiera arreglar también a los builds viejos.

### 4.4 Alternativa descartada (in-place) — resumen

Misma firma y contrato en las tres; arreglaría también los builds instalados; el argumento en contra es la decisión explícita del usuario de no tocar funciones vivas. Si se retoma: reafirmar `GRANT`/`REVOKE`/`search_path`, `COMMENT`, y `RAISE` en la rama SKU de `fn_descontar_venta_enrutada` (**L160-163**, no L159-162).

---

## 5 · Alcance: rutas vivas y callers

**Escrituras BOM de elaborados:** `fn_descontar_ingredientes_elaborado` · `fn_descontar_venta_enrutada` (rama SKU) · `fn_producir_tanda` · `fn_devolver_ingredientes_elaborado` · `fn_cancelar_item_pedido` · `fn_pedir_item_cuenta` / `fn_agregar_producto_orden_pendiente` / `fn_actualizar_cantidad_producto_orden`.

| Función | Callers vivos |
|---|---|
| `fn_descontar_ingredientes_elaborado` | `fn_descontar_venta_enrutada`, `fn_agregar_producto_orden_pendiente`, `fn_actualizar_cantidad_producto_orden` |
| `fn_descontar_venta_enrutada` | `fn_registrar_venta`, `fn_registrar_venta_mesa`, `_v2`, `_mesa_v2`, `fn_pedir_item_cuenta` |
| `fn_devolver_ingredientes_elaborado` | `fn_cancelar_item_pedido`, `fn_actualizar_cantidad_producto_orden`, `fn_eliminar_producto_orden` |
| `fn_validar_ingredientes_elaborado` | **sólo** `fn_descontar_ingredientes_elaborado` (en `fn_descontar_con_rebalanceo_almacen` el nombre está en un **comentario**) |

**Código muerto** (no arreglar): `fn_verificar_disponibilidad_plato`, `fn_validar_stock_plato`, `fn_descontar_inventario_plato` (×2), `fn_descontar_modificaciones` → esquema `app_rest_*` inexistente.

**Dart:** detalle de producto, preorden/cobro (el caso), mesa, venta por acuerdo, edición de pendientes. **Modo fluido** no vende hoy (D8).

---

## 6 · Pasos

> Cada paso: SQL local → aplicar (debug por MCP/Editor; producción por MCP) → prueba en `BEGIN … ROLLBACK` → **parada y OK** → Dart → `dart analyze`. Las Fases 1 y 3 van **juntas** antes de cualquier release de Dart.

### Fase 0 · Diagnóstico — ver §2 (parcialmente hecho)

### Fase 0.5 · Reparar la familia `search_path` (C9) — nuevo, previo a todo

**Archivo:** `presentaciones_inventario/45_guard_search_path.sql`.

- [ ] Decidir y aplicar **una** de las dos:
  - **(a) endurecer el guard** `check_user_has_access_to_tienda` en sitio: calificar las tablas (`public.app_dat_vendedor`, …) y añadirle `SET search_path = public, pg_catalog`. Misma firma, mismo `void`; **desbloquea de golpe** los cuatro llamadores con `search_path=''` y no cambia nada para los que ya funcionan. Es un bug puro (42P01), no un contrato.
  - **(b) no tocarlo** y crear `fn_check_user_has_access_to_tienda_safe` (calificado) usada sólo por los objetos nuevos.
- [ ] Inventario exacto a revisar (los dos proyectos): **31 funciones con `search_path` vacío**; **8 llaman al guard**; **rompen 4**: `fn_ejecutar_entrega_fisica_v2`, `fn_preview_entrega_fisica_v2`, `fn_registrar_venta_offline_v2` y `fn_registrar_venta_offline_v3`. Las de «cumplimiento» (`fn_aplicar_cumplimiento_v2`, `fn_crear_extraccion_con_movimiento_v2`, `fn_preview_cumplimiento_v2`) tienen `search_path` vacío pero no llaman al guard y no fallan; otras 4 se auto-corrigen con `set_config`. Guard afectado: `check_user_has_access_to_tienda` (config `null`, tablas sin calificar).
- [ ] **Prioridad alta — camino offline vivo**: `auto_sync_service.dart:4015` llama `fn_registrar_venta_offline_v3` (con fallbacks que **no** reconocen un 42P01, porque `_isRpcUnavailable` sólo busca `pgrst202`/`could not find the function`). Verificar si la sincronización offline de ventas falla hoy en producción y, en su caso, tratarlo como P0 independiente de este plan.
- [ ] Prueba: `select public.fn_preview_entrega_fisica_v2(3, 3, 4, 1, null, null)` desde un usuario autenticado de la tienda 4 → hoy `42P01`; después, `success`.

**Criterio:** ninguna función del stack falla con `42P01 relation "app_dat_*" does not exist`.

### Fase 1 · Cadena `_v2` de ingredientes por equivalente base (1B)

**Archivos nuevos** en `funcionalidad_cocina/`:

- `30_ingredientes_por_equivalente_base.sql`
  - `fn_ingredientes_elaborado_base(p_id_producto_elaborado, p_cantidad, p_id_almacen, p_alcance DEFAULT 'almacen')` → `jsonb`, **STABLE, no escribe**: por ingrediente, `cantidad_requerida_base`, `presentacion_base_id`, `equivalente_base`, `saldo_por_presentacion[]`, `alcanza`, `maximo_producible`. **Misma fuente para validar y para la UI**; con `search_path` correcto y nombres calificados.
  - `fn_consumir_ingrediente_base_v2(...)` → `jsonb`: resuelve la presentación base (`fn_presentaciones_producto`) y consume ubicación por ubicación en dos pasadas (1 = saldo propio; 2 = convertible) con **`fn_ejecutar_entrega_fisica_v3`** (decisión 13, planificador en enteros). Devuelve `lineas_fisicas` + `conversiones` + `movimientos`.
  - **Atomicidad (decisión 12)**: comprobar equivalente y descomposición entera **antes** de la primera escritura; error sin escribir si no cuadra; `RAISE` si hay que abortar después.
- `31_ingredientes_v2_rutas.sql`
  - `fn_descontar_ingredientes_elaborado_v2(...)`: misma firma que la viva; valida con `fn_ingredientes_elaborado_base`, descuenta con `fn_consumir_ingrediente_base_v2`, **mismo contrato jsonb** y traducción de códigos (decisión 7).
  - `fn_validar_ingredientes_elaborado_v2(...)`: `disponible` en base + `maximo_producible` + mensaje con unidad/presentación.
  - `fn_descontar_venta_enrutada_v2(...)`: delega en la v2 para la rama receta y reemplaza el `LEAST` de la rama SKU por el helper; **`RAISE`** si queda pendiente (C10).
- `32_tests_ingredientes_v2.sql`: suite transaccional.

**Casos de prueba (SQL, `ROLLBACK`):**

0. **Caso real de debug** (§2-bis): `fn_consumir_ingrediente_base_v2` para Arroz 3 / almacén 3 / 6000 base → consume sin fracciones, sin negativos, con conversión auditada, y **no** deja el `Kilogramo` en cero por el empate.
1. Receta 5000 base con 3 kg en una ubicación → abre el kg y queda `2 kg + 1000 u`.
2. El kg en otra ubicación del mismo almacén → pasada 2.
3. 2 ubicaciones × 2 presentaciones → base exacta, 0 negativos.
4. Cadena no divisible (`Caja ×24 > Bulto ×5 > Unidad`) → enteros o error explícito; nunca 4,8 Bultos ni 1,25/0,75.
5. Insuficiencia real → `INSUFFICIENT_STOCK_INGREDIENT`, misma unidad, **0 filas nuevas** en el ledger.
6. Producto de una sola presentación → sin regresión.
7. 1 Caja de elaborado → receta ×factor.
8. Presentación base con `cantidad ≠ 1` → no asume `factor = 1`.
9. Saldos negativos preexistentes → validación y consumo deciden igual.
10. **Empate de `cantidad_final`** (dos presentaciones con el mismo número) → resultado determinista y correcto en ejecuciones repetidas.

**Criterio:** con el caso 0, vender 10 Arroz Moro **no** modifica el `Kilogramo` a 0 y consume 6000/5000 base; con el caso 5 no hay escritura parcial.
**Dependencias:** Fase 0.5 (C9) porque el ejecutor `_v3` hereda el guard.

### Fase 2 · Rutas de cocina que no convierten la cantidad (C5)

`funcionalidad_cocina/33_ordenes_cocina_cantidad_en_base.sql`: `fn_pedir_item_cuenta_v2`, `fn_agregar_producto_orden_pendiente_v2`, `fn_actualizar_cantidad_producto_orden_v2` con `fn_cantidad_en_base(p_id_presentacion, p_cantidad)` en la entrada y devoluciones simétricas. Dart: `mesa_cuenta_service.pedirItem` (`:282-303`), `order_service` (`:2827-2959`).
**Prueba:** 1 Caja (×24) de un elaborado baja la harina 24 × la receta (hoy 1 ×).

### Fase 3 · Venta `_v3` — **obligatoria** con 1B

`funcionalidad_cocina/34_venta_v3_presentaciones.sql`:

- [ ] `fn_registrar_venta_v3` / `fn_registrar_venta_mesa_v3`: base de las `_v2` vivas (22+24) **+ el 25** (abrir/armar empaques del SKU) **+ `fn_descontar_venta_enrutada_v2`**.
- [ ] `fn_registrar_venta_offline_v4` para la cola offline.
- [ ] Dart: `order_service._registerSaleInSupabase` (`:1442-1461`) y la cadena de `auto_sync_service` (`:4010-4072`) apuntan a las nuevas. **Sin este paso, la Fase 7 queda sin efecto o es peligrosa** (C10).

### Fase 4 · Devoluciones y cancelaciones (C7)

`funcionalidad_cocina/35_devoluciones_presentacion.sql`: `fn_devolver_ingredientes_elaborado_v2` (devuelve a la presentación base, equivalente exacto, traza) + `fn_cancelar_item_pedido_v2`, `fn_eliminar_producto_orden_v2`. Dart: `mesa_cuenta_service.cancelarItemPedido` (`:357-376`), `order_service` (`:2827-2959`).
**Prueba:** cancelar 1 Caja devuelve lo consumido (no 500 en una fila `Kilogramo`); neto 0.

### Fase 5 · Alcance y coherencia (C4)

`funcionalidad_cocina/36_alcance_ingredientes.sql`: parámetro `p_alcance` **sólo en las funciones nuevas**; por defecto el almacén resuelto. Si el ingrediente está en **otro almacén de la misma tienda**: (a) corregir la configuración y que el cartel lo diga, o (b) `'tienda'`. Si está en **otra tienda**, el rechazo es correcto y el mensaje debe nombrarla.
**Censo de seguimiento con el filtro correcto** (almacenes de la propia tienda, nunca `fn_stock_producto_almacen(ing, NULL)`): producción **35 elaborados / 7 tiendas**.
**Prueba:** un elaborado intra-tienda del censo (no el 240, inter-tienda) pasa de rechazo a `success` con `'tienda'`.

### Fase 6 · Contrato de mensajes

- [ ] `error_code` estables + `ingrediente`, `cantidad_requerida`, `cantidad_disponible`, `maximo_producible`, `presentacion`/`unidad`; no renombrar códigos que la app ya consume (`pedido_resultado.dart:180-183`).

### Fase 7 · Dart `ventiq_app`

**P0 — el cartel (bloqueante hoy; es el caso del usuario):**

- [ ] **`getProductIngredients`** (`product_detail_service.dart:506-593`): **preferido**, dejar de calcular el disponible en el cliente y pedirlo al servidor: llamar `fn_ingredientes_elaborado_base` (o `fn_validar_ingredientes_elaborado_v2`) con el almacén resuelto del TPV y exponer `disponible_base` + desglose por presentación. **Fallback** si la RPC no está: traer **todas** las filas del ingrediente con su `id_presentacion` y sumar `cantidad_final × factor_rel` con `PresentacionCadenaLocal` (`presentacion_cadena_local.dart:111-196`).
- [ ] **`preorder_screen._checkInventoryAvailability`** (`:1271-1576`) y `_checkIngredientsAvailability` (`:2643-2718`): comparar en **unidades base**; si la RPC nueva responde, usarla como fuente única.
- [ ] **No aplicar el desarme de presentaciones a elaborados/servicios** en la ficha (`product_details_screen.dart:3680-3736`).
- [ ] **Unidad/presentación** en los carteles (`preorder_screen.dart:2824-2828`) y equivalente base en gris (regla de UI de `PLAN_PRESENTACIONES_INVENTARIO.md:845-847`). Ojo: la receta de este caso tiene `unidad_medida = null`; la unidad debe salir de la **presentación**, no de ese campo.

**P1:**

- [ ] Rama `on PedidoException` en `_addToCart` (`product_details_screen.dart:3912-3925`) usando `titulo`/`esFaltaDeStock` y `forzarSinStock`.
- [ ] `_getStockFromCache` (`preorder_screen.dart:1060-1144`): priorizar la suma (el respaldo ya existe en `:1132`).
- [ ] Venta por acuerdo: excluir elaborados del delta local (`admin_inventory_service.dart:1229-1238`).
- [ ] Offline: decidir si se cachea la receta (hoy la rama de ingredientes es inerte).

**P2 (fuera del caso):** modo fluido (`fluid_mode_screen.dart:66-106`), `cocina_offline_queue.dart`, conteo mixto en apertura (`apertura_screen.dart:781-799`).

**Gate de release:** no publicar el APK con el P0 si la Fase 1 + Fase 3 no están aplicadas en **ambos** proyectos.

### Fase 8 · Pruebas, despliegue y documentación

- [ ] Suite transaccional de las Fases 1–4 en **debug** y con `ROLLBACK` en producción.
- [ ] Aplicar **debug → probar con el usuario → producción**; Fase 0.5 en los dos.
- [ ] Verificar por md5 que las funciones vivas **no** cambiaron (salvo, si se elige 0.5(a), el guard).
- [ ] `advisors` de seguridad/rendimiento tras aplicar.
- [ ] Actualizar `presentaciones_inventario/README.md`, `funcionalidad_cocina/README.md`, el §«pendiente conocido» del tutorial (`:1254-1273`, ya desfasado) y este documento con el anexo final.

---

## 7 · Cómo debe funcionar la venta de un producto **no elaborado**

1. El vendedor elige presentación y cantidad; esa presentación viaja en el `jsonb`.
2. El servidor mide en **equivalente base** y lo compara con el alcance (decisión 8).
3. **Pasada 1**: saldo propio. **Pasada 2**: abre/arma empaques en combinaciones enteras, con conversión auditada.
4. Si no alcanza: error con `disponible`/`requerido`/`maximo_servible` **en la misma unidad** y **sin escritura parcial** (para la ruta `_v3`; la ruta viva tiene C10).
5. Precio = `precio base × factor_rel`.
6. La UI no valida con un número crudo: `fn_preview_rebalanceo` online; `DesarmeBultoLocal` offline (ya correcto, `desarme_bulto_local.dart:96-102`).

Hoy esto ya funciona en `fn_registrar_venta`/`_mesa` (parche `25`), salvo C6 (latente) y C4/C9/C10.

---

## 8 · Pruebas de aceptación

**SQL:** los 11 casos de la Fase 1 + una por Fase 2–4 (con `ROLLBACK` y foto previa/posterior del ledger).

**UI (dispositivo, ambos proyectos):**

1. **El caso exacto:** 10 Arroz Moro con 2000 kg + 2000 u de Arroz y 2500 kg + 2500 u de Frijoles. **Debe:** no aparecer «Problema de Inventario»; el kardex muestra las conversiones; el saldo de los `Kilogramo` **no** queda en cero; la venta se completa.
2. Insuficiencia real → cartel con unidad y máximo servible, sin cambios en el saldo.
3. Producto no elaborado: 5 Unidades con solo Cajas → abre la Caja.
4. 1 Caja de un elaborado con cocina activa → receta ×factor (Fase 2 incluida).
5. Cancelar/editar una línea → devuelve exactamente lo consumido.
6. Offline → sin cartel inventado; error real al sincronizar.

---

## 9 · No-regresión y riesgos

| Riesgo | Mitigación |
|---|---|
| **Arreglar sólo el cliente saquea el almacén** (C2 + C10, con las filas de 2000 kg reales) | Decisión 14: SQL primero; gate de release en Fase 7 |
| `_v2` ya desplegada en los dos proyectos pero **rota por C9** | Fase 0.5 antes de usar la cadena; prueba de `fn_preview_entrega_fisica_v2` |
| **C9 ya está vivo en el camino offline** (`fn_registrar_venta_offline_v3` llamado por `auto_sync_service.dart:4015`, sin fallback que reconozca 42P01) | Tratarlo como P0 en la Fase 0.5 y comprobar en producción si la sincronización offline falla hoy |
| `fn_descontar_con_rebalanceo_almacen` (0 callers) produce fracciones | Vía preferida = planificador v2 (`_v3`); v1 sólo con pre-validación; prueba 4 |
| Builds viejos con el bug (consecuencia de 1B) | Explícito en §4.3; se cierra al publicar el release migrado |
| Empate de `cantidad_final` ⇒ orden no determinista | Prueba 10; el helper consume por presentación y equivalente, no por orden físico |
| Los dos proyectos divergen | Fase 0.5 + md5; aplicar debug → producción |
| Catálogos con `factor_rel = 1` en kg | Es dato: se censa (D3) y se corrige la presentación |
| `fn_producir_tanda` (C8) | Misma ronda o tarea aparte (§11) |
| Caché offline colapsa productos | No afecta a elaborados (excluidos) |

---

## 10 · Censo y exposición

- Elaborados en producción: **124 / 14 tiendas**; **0** con ingrediente `factor_rel <> 1` con saldo → C2 latente en producción, **activo** en el caso de debug (§2-bis).
- Alcance intra-tienda real: **35 elaborados / 7 tiendas** (el «36/8» barría toda la plataforma; el `240` es inter-tienda).
- Factores ≠ 1 con saldo: 6 combos / 9 filas / 6 productos / 3 tiendas, 0 elaborados.
- Censo correcto: filtrar por `factor_rel <> 1`, **no** por «>1 presentación con saldo».
- Cliente: la validación de elaborados se dispara sólo con red y sin `permiteVenderSinDisponibilidad`; offline es inerte.

---

## 11 · Preguntas abiertas

1. ~~¿1A in-place o 1B?~~ **Resuelto: 1B** (`_v2`/`_v3`, sin tocar funciones vivas).
2. **¿Fase 0.5(a) endurecer el guard en sitio o (b) crear `_safe`?** Recomendación: **(a)**, porque el 42P01 ya rompe la familia `_v2` en los dos proyectos y el cambio es de contrato idéntico.
3. Alcance del consumo: ¿almacén resuelto o tienda? (35 elaborados / 7 tiendas).
4. `fn_producir_tanda` (C8) y `fn_disponibilidad_plato` (C4): ¿esta ronda o tarea aparte?
5. ¿Se cachea la receta en offline?
6. Variantes/opciones del ingrediente y borde `base.cantidad = 0/NULL` (`PRESENTATION_NOT_IN_CHAIN`).
7. ¿Se publica el APK con 1B sabiendo que los builds viejos conservan el bug?

---

## 12 · Trazabilidad

| Afirmación | Evidencia |
|---|---|
| El cartel es del cliente y bloquea | Cartel pegado por el usuario; `preorder_screen.dart:926`, `:933-934`, `:1271-1576`, `:1356`, `:1642-1750` |
| `getProductIngredients` lee una fila | `product_detail_service.dart:549-559`; curl del usuario |
| Saldos/lote y equivalentes reales de debug | §2-bis (mediciones 2026-10-21, solo lectura) |
| El servidor valida `success` | `fn_validar_ingredientes_elaborado(5,10,3)` |
| `LEAST` mixto L33/L118 | `INGREDIENTES_SQL.md` §1.3–1.4; md5 vivos |
| Empate ⇒ orden no determinista | `01_helpers_bom_almacen.sql:101`; §2-bis |
| C9 `search_path` + guard sin calificar | 42P01 en debug; `proconfig` y md5 idénticos en ambos proyectos |
| C10 commit parcial | `INGREDIENTES_SQL.md` §11; `VERIFICACION_PLAN.md` hallazgo 3 |
| Callers y código muerto | `INGREDIENTES_SQL.md` §2; `VERIFICACION_PLAN.md` |
| Censos y correcciones previas | `VERIFICACION_PLAN.md` (10 de 76 incorrectas, ya aplicadas) |

**Rutas citadas:** `funcionalidad_cocina/{01,10,11,14,21}.sql`, `presentaciones_inventario/{02,03,22,24,25,27,35,38,39,40,41,45}.sql`, `ventiq_app/lib/{config/supabase_config.dart,services/{product_detail_service,order_service,mesa_cuenta_service,admin_inventory_service,inventory_service,auto_sync_service}.dart,screens/{preorder_screen,product_details_screen,fluid_mode_screen,apertura_screen}.dart,models/pedido_resultado.dart,utils/{presentacion_cadena_local,desarme_bulto_local}.dart}`.