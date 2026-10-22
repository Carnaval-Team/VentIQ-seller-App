# Runbook · Aplicación de la implementación de ingredientes/presentaciones

**Fecha:** 2026-10-21 · **Owner:** lead · **Alcance:** Fases 0.5, 1, 2, 3 y 4 del plan
`docs/PLAN_CONSUMO_INGREDIENTES_ELABORADOS_PRESENTACIONES.md`, más el P0 de Dart de `ventiq_app`.

**Proyectos (los dos):** debug `qhprswhhfasrikhawjoz` y release/producción `vsieeihstajlrdvpuooh`.

---

## Estado de implementación (2026-10-22)

**Todo está escrito y verificado por lectura; NADA aplicado en ningún proyecto** (`to_regprocedure` de los 18 objetos nuevos = NULL en producción).

| Fase | Entregable | Estado |
|---|---|---|
| 0.5 | `presentaciones_inventario/45` (guard `_safe`), `46` (patch opcional, **no aplicado**), `47` (tests) | listo |
| 1 | `funcionalidad_cocina/30` (ejecutor `_v3`, `fn_ingredientes_elaborado_base`, `fn_ingrediente_base_alcanzable`, `fn_consumir_ingrediente_base_v2`), `31` (rutas BOM `_v2`), `32` (tests) | listo |
| 2 | `funcionalidad_cocina/33` (cocina `_v2` con `fn_cantidad_en_base`) | listo |
| 3 | `funcionalidad_cocina/34` (venta `_v3`/`_mesa_v3`/offline `_v4`) | listo |
| 4 | `funcionalidad_cocina/35` (devoluciones `_v2`) | listo |
| 7 P0 | Dart: `product_detail_service.dart` (`getProductIngredients` en equivalente base), `preorder_screen.dart` (preorden en base) | listo |
| 7 P1 | Dart: alcance al almacén del TPV con etiqueta `alcanceAlmacenTpv`/`alcanceTodosLosAlmacenes` | listo |
| 7 / 2-4 | Dart: `order_service.dart`, `auto_sync_service.dart`, `mesa_cuenta_service.dart` a las RPC `_v2`/`_v3`/`_v4` **con fallback** a las vivas | listo |

### Estado realmente aplicado por proyecto (medido 2026-10-22)

| Archivo / objetos | Debug `qhprswhhfasrikhawjoz` | Producción `vsieeihstajlrdvpuooh` |
|---|---|---|
| `45` guard `_safe` | ✅ aplicado | ❌ falta |
| `46` patch opcional del guard | (decisión pendiente) | (decisión pendiente) |
| `30` (`fn_ejecutar_entrega_fisica_v3`, `fn_preview_entrega_fisica_v3`, `fn_ingrediente_base_alcanzable`, `fn_ingredientes_elaborado_base`, `fn_consumir_ingrediente_base_v2`) | ✅ aplicado (con la comilla corregida) | ✅ aplicado |
| `31` (`fn_validar_ingredientes_elaborado_v2`, `fn_descontar_ingredientes_elaborado_v2`, `fn_descontar_venta_enrutada_v2`) | ✅ aplicado | ✅ aplicado |
| `35` (`fn_devolver_ingredientes_elaborado_v2`, `fn_cancelar_item_pedido_v2`, `fn_eliminar_producto_orden_v2`) | ❌ falta | ❌ falta |
| `33` (`fn_pedir_item_cuenta_v2`, `fn_agregar_producto_orden_pendiente_v2`, `fn_actualizar_cantidad_producto_orden_v2`) | ❌ falta | ❌ falta |
| `34` (`fn_registrar_venta_v3`, `_mesa_v3`, `offline_v4`) | ✅ aplicado | ❌ falta |

**No-regresión verificada en producción:** los md5 de las funciones vivas siguen intactos (`fn_registrar_venta` `371402e5…`, `_mesa` `74b4751f…`, `_v2` `253d9d16…`, `_mesa_v2` `6d34466b…`, `fn_descontar_ingredientes_elaborado` `47be3a93…`, `fn_descontar_venta_enrutada` `d56b117f…`, `fn_validar_ingredientes_elaborado` `c23f85d2…`, `check_user_has_access_to_tienda` `438dbaec…`, `fn_stock_producto_almacen` `ecad724f…`, `_detalle` `0c452407…`). Los 8 objetos aplicados en producción son **aditivos**.

**Falta para cerrar:**
- Debug: `35` → `33` (33 exige `_safe`, ya está) y después correr `37_tests_caso_real_debug.sql` (§ prueba real).
- Producción: `45` → (`46`, decisión) → `35` → `33` → `34`; después `32_tests_ingredientes_v2.sql` (fixtures de producción) y el caso real del §4.

**Cuarta observación (2026-10-22) · el Editor revierte el DDL si un test aborta:** el SQL Editor ejecuta el script completo en **una sola transacción**, así que un `RAISE EXCEPTION` en los tests **deshace también el DDL del mismo archivo**. Medido: el primer intento de `35` abortó en S-B por el fixture de producción y, como consecuencia, **sus tres `_v2` no quedaron creadas** (en debug sólo existían las vivas `fn_devolver_ingredientes_elaborado`, `fn_cancelar_item_pedido`, `fn_eliminar_producto_orden`). Con `30`, `31`, `34` y `45` no pasó porque su script termina sin abortar.

Consecuencias prácticas:
1. Las guardas de test ya **no abortan** (se omiten con `NOTICE`), así que los archivos `33` y `35` se pueden aplicar completos.
2. Aun así, si algún test aborta en el futuro, aplica el archivo **en dos partes**: primero el DDL (hasta el banner `-- TESTS`) y después los tests por separado.
3. Verifica **después de cada archivo** con esta consulta (no hardcodea firmas: `fn_pedir_item_cuenta_v2` tiene 17 parámetros y calca la firma viva):

```sql
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_devolver_ingredientes_elaborado_v2','fn_cancelar_item_pedido_v2','fn_eliminar_producto_orden_v2',
                     'fn_pedir_item_cuenta_v2','fn_agregar_producto_orden_pendiente_v2','fn_actualizar_cantidad_producto_orden_v2')
 ORDER BY 1;
-- Tras aplicar 35: las 3 primeras. Tras aplicar 33: las 3 ultimas. Si no aparece ninguna, el script aborto y revirtio el DDL.
```

**Verificación adversarial** (`docs/_analisis/VERIFICACION_IMPLEMENTACION.md`): **8 CONFIRMADO / 0 INCORRECTO / 0 NO VERIFICABLE**.
- Las firmas de `_v2` son idénticas a las vivas (comparadas con `pg_get_function_identity_arguments`).
- Ninguna función viva se pisa; los `_v3` de venta salen de un `DO`-block que renombra la cabecera viva y **aborta si el conteo de sustituciones no es exacto**.
- `47` sólo contiene DDL dentro de `BEGIN`/`ROLLBACK`, sin `COMMIT`.
- Dart: **0 errores** en los 5 archivos (`dart analyze`). Se corrigió un `error` real que dejó una caída de conexión: `auto_sync_service.dart:4011` (un `try` anidado sin `catch`). Queda un `warning` de `usedAtomicPagos` sin usar que **ya existía en git HEAD** (no es regresión).
- Única corrección aplicada: el orden de aplicación (§2) invierte 33 y 35.

**Pendiente (bloqueante, requiere al usuario):**
1. Aplicar los archivos en el SQL Editor de **debug** siguiendo el §2, ejecutar `47` y `32`, y hacer la prueba del caso real del §4.
2. Sólo después, aplicar en producción y publicar el APK (gate del §5).

**Corrección post-verificación (2026-10-22):** al aplicar el archivo 30, Postgres abortó con `42601 unterminated quoted string` apuntando a `'fuente','fn_ingrediente_base_alcanzable');`. La causa real estaba **antes**: en `30_...sql:648` faltaba la comilla de cierre del operador (`v_kernel->>'motivo,` en vez de `v_kernel->>'motivo',`), y la cadena abierta se "tragaba" el resto del cuerpo hasta EOF, por eso el error se reportaba cientos de líneas después. Corregido en línea (los números de línea del archivo no cambian).
- Lección de método: una comprobación de **paridad global** de comillas da OK aunque haya una comilla descolocada (el desbalance se compensa más adelante). Ahora se validan los 9 archivos con (a) paridad por línea, (b) simulación del lexer en modo SQL plano (estado final `en_string=False`) y (c) balance de paréntesis. Los tres pasan en los 9 archivos.
- La verificación adversarial previa de los archivos (8/8 CONFIRMADO) fue por **lectura estática** y no detectó esto; la validación definitiva sigue siendo aplicar en debug y correr `32`/`47`.

**Segunda corrección (2026-10-22):** en `35_...sql` el bloque de evidencia S-A falló con `42P01 missing FROM-clause entry for table "p"`: las subconsultas usaban `p.prosrc` pero la consulta no traía `pg_proc p`. Añadido `FROM pg_proc p JOIN pg_namespace n ... WHERE p.proname='fn_devolver_ingredientes_elaborado'`.
- **Validado contra producción** (SELECT de solo lectura): devuelve `true | 1 | 2 | 1 | 5 | 103`, exactamente el «esperado» que documenta el archivo.
- También se validó **antes de aplicarla** la sección T-A de `33` (otro bloque de solo lectura): devuelve `24 / 48 / 5 / 5 / [{216,40},{218,10}] / [{216,960},{218,240}] / 0`, su esperado.
- Añadida validación sintáctica con **pglast** (parser real de PostgreSQL): los 9 archivos parsean **OK**. Límite conocido y comprobado: `42P01` es un error **semántico** (resolución de nombres), no sintáctico, y pglast **no** lo detecta; por eso los bloques de solo lectura se validan ejecutándolos contra la base.
- Sin sesión de escritura, quedan **sin poder validarse** el DDL y los bloques `BEGIN…ROLLBACK` (`32`, `47`, `33` T-B, `35` S-B): sólo se validan al aplicarlos.

**Tercera corrección (2026-10-22) · tests que bloqueaban la aplicación:** al aplicar `35` completo en **debug**, el bloque S-B abortó con `P0001: S-B: fn_cantidad_en_base(340,1) deberia ser 24, es 1`: los tests usan **fixtures de producción** (producto 219, presentación 340 = Caja ×24, almacén 12) que no existen en debug, y el `RAISE EXCEPTION` del guarda impedía aplicar el archivo.
- Arreglado: **4 guardas en `35` y 5 en `33`** (dependencia ausente, almacén sin movimiento, stock insuficiente) pasan de `RAISE EXCEPTION` a **`RAISE NOTICE` + `RETURN`**: el archivo se aplica en cualquier proyecto y el test **se ejecuta donde el fixture existe** (producción). Las aserciones reales (descuento falló, neto ≠ 0, etc.) siguen abortando, que es su función.
- Las guardas de **pre-vuelo** (antes del DDL: `_safe` de 45, `fn_cantidad_en_base` de 24, `_v2` de 30/31/35) **se mantienen**: son dependencias reales del orden de aplicación.
- `32_tests_ingredientes_v2.sql` lleva ahora un **aviso**: es un archivo de pruebas con fixtures de producción y **no debe aplicarse en debug** (no tiene DDL; en debug se prueba con el §4).
- Al aplicar `35`/`33` en debug verás **`NOTICE: S-B/T-B OMITIDO: ...`**: es el comportamiento esperado, no un fallo.
- Re-verificados `33` y `35` tras los cambios: pglast OK, lexer plano OK, paréntesis OK.

---

## 0 · Requisito de arranque: sesión de ESCRITURA

Comprobado en esta sesión: el MCP de Supabase de producción está en **transacción de solo lectura**
(`cannot execute DROP FUNCTION in a read-only transaction`, SQLSTATE 25006; el endpoint del debug se
abrió con `read_only=true`). Tampoco hay CLI de Supabase, `psql` ni `.env` con cadena de conexión en el
repo (`supabase/.temp/linked-project.json` sólo guarda `ref` y `name`).

Por tanto, antes de aplicar hace falta **una** de estas dos cosas:

- **(a)** que el usuario aplique los archivos en el **SQL Editor** de cada proyecto, en el orden de §2; o
- **(b)** que el usuario facilite una sesión MCP **sin `read_only`** (primero debug, y producción después)
  para que el equipo aplique y ejecute las pruebas.

Nada de lo que sigue debe ejecutarse en producción antes de que **debug** haya pasado la prueba del caso
real de §4.

---

## 1 · Qué se aplica (objetos nuevos, ninguna función viva se toca)

| Archivo | Objetos | Efecto |
|---|---|---|
| `presentaciones_inventario/45_guard_search_path.sql` | `fn_check_user_has_access_to_tienda_safe(bigint)` | Guard con tablas calificadas y `search_path` propio, para las funciones nuevas. |
| `presentaciones_inventario/46_patch_guard_en_sitio.sql` | `check_user_has_access_to_tienda` (patch **opcional**) | Endurece el guard vivo. **Decisión del usuario**: desbloquea de golpe `fn_registrar_venta_offline_v2/v3` (fallo vivo, `auto_sync_service.dart:4015`). Misma firma y `void`. |
| `presentaciones_inventario/47_tests_guard_search_path.sql` | tests | `BEGIN … ROLLBACK`. |
| `funcionalidad_cocina/30_ingredientes_por_equivalente_base.sql` | `fn_ejecutar_entrega_fisica_v3`, `fn_ingredientes_elaborado_base`, `fn_consumir_ingrediente_base_v2` | Consumo por equivalente base, empaques enteros (planificador v2), `search_path` correcto y pre-validación atómica. |
| `funcionalidad_cocina/31_ingredientes_v2_rutas.sql` | `fn_descontar_ingredientes_elaborado_v2`, `fn_validar_ingredientes_elaborado_v2`, `fn_descontar_venta_enrutada_v2` | Rutas BOM nuevas con el contrato `jsonb` de las vivas. |
| `funcionalidad_cocina/32_tests_ingredientes_v2.sql` | tests | `BEGIN … ROLLBACK` (11 casos del plan). |
| `funcionalidad_cocina/33_ordenes_cocina_cantidad_en_base.sql` | `fn_pedir_item_cuenta_v2`, `fn_agregar_producto_orden_pendiente_v2`, `fn_actualizar_cantidad_producto_orden_v2` | La cantidad se convierte a base en la entrada (vender 1 Caja descuenta ×factor). |
| `funcionalidad_cocina/34_venta_v3_presentaciones.sql` | `fn_registrar_venta_v3`, `fn_registrar_venta_mesa_v3`, `fn_registrar_venta_offline_v4` | Ventas nuevas con el ejecutor `_v3` y la receta `_v2`. Los cuerpos se derivan de las `_v2` vivas con un `DO`-block que **aborta si el conteo de sustituciones no es exacto**. |
| `funcionalidad_cocina/35_devoluciones_presentacion.sql` | `fn_devolver_ingredientes_elaborado_v2`, `fn_cancelar_item_pedido_v2`, `fn_eliminar_producto_orden_v2` | Devoluciones a la presentación base, equivalente exacto. |

**Vivas intactas (deben conservar su md5):** `fn_registrar_venta` `371402e5…`, `fn_registrar_venta_mesa` `74b4751f…`,
`fn_registrar_venta_v2` `253d9d16…`, `fn_registrar_venta_mesa_v2` `6d34466b…`, `fn_descontar_ingredientes_elaborado` `47be3a93…`,
`fn_descontar_venta_enrutada` `d56b117f…`, `fn_validar_ingredientes_elaborado` `c23f85d2…`, `fn_stock_producto_almacen(_detalle)`,
`check_user_has_access_to_tienda` `438dbaec…` (**salvo** que se aplique el patch 46, en cuyo caso el md5 cambia y es lo esperado).

---

## 2 · Orden de aplicación (por proyecto)

1. `presentaciones_inventario/45` → guard `_safe`.
2. `presentaciones_inventario/46` → **sólo si el usuario decide aplicar el patch** (recomendado: sí, es un bug puro de 42P01 con contrato idéntico).
3. `funcionalidad_cocina/30` → ejecutor `_v3` + helpers de ingredientes.
4. `funcionalidad_cocina/31` → rutas BOM `_v2`.
5. `funcionalidad_cocina/35` → **devoluciones `_v2` PRIMERO**: crea `fn_devolver_ingredientes_elaborado_v2`, que `33` exige en su entrada (`33:110-112` aborta si falta). Sólo depende de `45`.
6. `funcionalidad_cocina/33` → rutas de cocina `_v2` (consume la devolución `_v2` del paso 5).
7. `funcionalidad_cocina/32` → pruebas del consumo (deben pasar todas; quedan en `ROLLBACK`).
8. `funcionalidad_cocina/34` → ventas `_v3`/`_v4` (el `DO`-block exige que 30/31 estén aplicados; si no, aborta con mensaje explícito).
9. Repetir `32` y añadir la prueba del caso real de §4.

> **Orden verificado** (`docs/_analisis/VERIFICACION_IMPLEMENTACION.md`, corrección obligatoria): `33` **no** puede ir antes que `35`. El intercambio es seguro porque `35` sólo depende de `45`.

Cada archivo es idempotente (`CREATE OR REPLACE` / `DO`-block con `CREATE OR REPLACE`).

---

## 3 · Verificación post-aplicación (solo lectura)

```sql
-- 3.1 Los objetos nuevos existen
SELECT to_regprocedure('public.fn_check_user_has_access_to_tienda_safe(bigint)'),
       to_regprocedure('public.fn_ejecutar_entrega_fisica_v3(bigint,bigint,bigint,numeric,integer,bigint,bigint,bigint,bigint,uuid,text)'),
       to_regprocedure('public.fn_ingredientes_elaborado_base(bigint,numeric,bigint,text)'),
       to_regprocedure('public.fn_consumir_ingrediente_base_v2(bigint,bigint,numeric,integer,bigint,bigint,uuid,text)'),
       to_regprocedure('public.fn_descontar_ingredientes_elaborado_v2(bigint,numeric,bigint,bigint,integer)'),
       to_regprocedure('public.fn_descontar_venta_enrutada_v2(bigint,numeric,bigint,bigint,integer,boolean)'),
       to_regprocedure('public.fn_registrar_venta_v3(bigint,uuid,jsonb,text,text,text,smallint,bigint)'),
       to_regprocedure('public.fn_registrar_venta_mesa_v3(bigint,uuid,jsonb,text,text,text,smallint,bigint,bigint)'),
       to_regprocedure('public.fn_registrar_venta_offline_v4(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint,timestamptz,jsonb)');
-- (Ajusta las firmas a las que hayan quedado en los archivos; deben devolver no-NULL.)
```

```sql
-- 3.2 No-regresión: las vivas conservan su md5
SELECT p.proname, md5(pg_get_functiondef(p.oid)) AS md5
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public'
   AND p.proname IN ('fn_registrar_venta','fn_registrar_venta_mesa','fn_registrar_venta_v2',
                     'fn_registrar_venta_mesa_v2','fn_descontar_ingredientes_elaborado',
                     'fn_descontar_venta_enrutada','fn_validar_ingredientes_elaborado',
                     'check_user_has_access_to_tienda')
 ORDER BY 1;
```

```sql
-- 3.3 C9 reparado: el preview v2 ya no da 42P01 con el guard sano
--     (si no se aplicó el patch 46, usar fn_ejecutar_entrega_fisica_v3 / _safe en las rutas nuevas)
SELECT public.fn_preview_entrega_fisica_v2(3, 3, 4, 1, NULL, NULL);
```

---

## 4 · Prueba de aceptación del caso real (debug)

Con los saldos medidos (Arroz 3: `Unidad 2000` + `Kilogramo 2000`; Frijoles 4: `Unidad 2500` + `Kilogramo 2500`;
TPV «Caja 1» → tienda 4, almacén 3; receta del Arroz Moro 5: Frijoles 500 + Arroz 600 por unidad):

1. **Foto previa** del ledger de los productos 3 y 4 (por ubicación + presentación) y del kardex.
2. Vender **10 Arroz Moro** en el TPV.
3. **Debe:** sin «Problema de Inventario»; el descuento consume `6000` y `5000` **en unidades base**; las filas
   `Kilogramo` **no** quedan en cero (se abre lo necesario: 6 kg de arroz y 5 kg de frijoles, o su
   descomposición entera); el kardex muestra las conversiones; `0` saldos negativos.
4. **Si falla** (mensaje `INSUFFICIENT_STOCK_INGREDIENT` o saldo incoherente): no seguir a producción; revertir
   apuntando el Dart a las RPC vivas y reportar con la foto del ledger.

**Prueba de que el arreglo del cliente no basta por sí solo:** si se despliega el P0 de Dart **sin** 30/31/34,
el descuento cae en el `LEAST` mixto y, con estos saldos, deja los `Kilogramo` en cero y aun así reporta
«faltan N» o `success` según el ingrediente (simulación medida, §0 del plan). No publicar en ese orden.

---

## 5 · Gate del release de `ventiq_app`

- No publicar el APK con el P0 de Dart hasta que **30/31/34** estén aplicados **en el proyecto al que apunte
  ese build** (debug mientras se prueba, producción al liberar).
- El P0 cambia `getProductIngredients` (todas las filas + `factor_rel`) y la comparación del preorden a unidades base.
- La migración del Dart a `fn_registrar_venta_v3` / `_mesa_v3` / `fn_registrar_venta_offline_v4` y a las rutas
  `_v2` de cocina/devoluciones va **en el mismo release** (si no, la app sigue usando las RPC vivas con el bug).

---

## 6 · Rollback

Por objeto, sin tocar nada vivo:

```sql
DROP FUNCTION IF EXISTS public.fn_registrar_venta_v3(bigint,uuid,jsonb,text,text,text,smallint,bigint);
DROP FUNCTION IF EXISTS public.fn_registrar_venta_mesa_v3(bigint,uuid,jsonb,text,text,text,smallint,bigint,bigint);
DROP FUNCTION IF EXISTS public.fn_registrar_venta_offline_v4(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint,timestamptz,jsonb);
-- …y el resto de objetos _v2/_v3 y fn_check_user_has_access_to_tienda_safe.
-- Si se aplicó 46: restaurar el guard con el cuerpo vivo anterior (md5 438dbaec…) desde
-- el histórico de este repo o desde una copia previa.
```

---

## 7 · Pendiente de decisión del usuario

- **Patch 46 (guard en sitio):** recomendado aplicarlo (arregla el 42P01 vivo de `fn_registrar_venta_offline_v2/v3`),
  pero es una función viva; la alternativa ya está cubierta con `_safe` en las rutas nuevas.
- **Alcance del consumo** (Fase 5): almacén resuelto (por defecto) o tienda, para los 35 elaborados / 7 tiendas.