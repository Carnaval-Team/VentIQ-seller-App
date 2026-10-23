# Verificación de la implementación (Fases 0.5–7) — verifier2

**Fecha:** 2026-10-22 · **Verificador:** `verifier2` · **Entregable único:** este archivo.
**Alcance:** el acordado con el lead (4 puntos: firmas cruzadas, no pisar funciones vivas, Dart sin errores, `34` aplicable en orden).
**Acceso:** lectura de repo + MCP Supabase de producción `vsieeihstajlrdvpuooh` **solo lectura** (sin DDL). No se aplicó nada.

## Punto 0 · Estado real de los objetos nuevos (contexto)

`to_regprocedure(...)` para **los 18 objetos nuevos** de `45`, `30`, `31`, `33`, `34` y `35`
(`fn_check_user_has_access_to_tienda_safe`, `fn_ejecutar_entrega_fisica_v3`, `fn_preview_entrega_fisica_v3`,
`fn_ingrediente_base_alcanzable`, `fn_ingredientes_elaborado_base`, `fn_consumir_ingrediente_base_v2`,
`fn_validar_ingredientes_elaborado_v2`, `fn_descontar_ingredientes_elaborado_v2`, `fn_descontar_venta_enrutada_v2`,
`fn_pedir_item_cuenta_v2`, `fn_agregar_producto_orden_pendiente_v2`, `fn_actualizar_cantidad_producto_orden_v2`,
`fn_registrar_venta_v3`, `fn_registrar_venta_mesa_v3`, `fn_registrar_venta_offline_v4`,
`fn_devolver_ingredientes_elaborado_v2`, `fn_cancelar_item_pedido_v2`, `fn_eliminar_producto_orden_v2`)
→ **NULL en producción** ⇒ **CONFIRMADO: nada aplicado todavía**.
Y las vivas conservan su md5 (`check_user_has_access_to_tienda 438dbaec…`, `fn_registrar_venta 371402e5…`,
`fn_registrar_venta_v2 253d9d16…`, `fn_descontar_ingredientes_elaborado 47be3a93…`,
`fn_descontar_venta_enrutada d56b117f…`, `fn_validar_ingredientes_elaborado c23f85d2…`) ⇒ el patch opcional `46` **no** está aplicado.

---

## a) Firmas cruzadas `_v2` vs vivas — **CONFIRMADO**

Consulta: `select proname, pg_get_function_identity_arguments(oid), pg_get_function_arguments(oid) from pg_proc …` (producción, solo lectura).

| Nueva (repo) | Firma declarada | Viva (producción) | Veredicto |
|---|---|---|---|
| `fn_descontar_venta_enrutada_v2` — `funcionalidad_cocina/31_ingredientes_v2_rutas.sql:284-291` | `(p_id_producto bigint, p_cantidad numeric, p_id_tpv bigint, p_id_extraccion bigint DEFAULT NULL, p_origen_cambio integer DEFAULT 4, p_ya_descontado_sku boolean DEFAULT true)` | `fn_descontar_venta_enrutada` → ident `(bigint, numeric, bigint, bigint, integer, boolean)`; defaults `NULL, 4, true` | **CONFIRMADO: idénticas** |
| `fn_descontar_ingredientes_elaborado_v2` — `funcionalidad_cocina/31_ingredientes_v2_rutas.sql:163-169` | `(p_id_producto_elaborado bigint, p_cantidad numeric, p_id_almacen bigint, p_id_extraccion bigint DEFAULT NULL, p_origen_cambio integer DEFAULT 4)` | `fn_descontar_ingredientes_elaborado` → ident `(bigint, numeric, bigint, bigint, integer)`; defaults `NULL, 4` | **CONFIRMADO: idénticas** |

Consecuencia para `34`: la sustitución de nombre que hace el `DO`-block (`34:55-60`) conserva los argumentos, así que
`fn_registrar_venta_v3`/`_mesa_v3` reciben exactamente los mismos parámetros que las vivas `_v2` que clona.

Extra comprobado con la misma consulta: `fn_validar_ingredientes_elaborado` viva = `(bigint, numeric, bigint)`
= `31:55-59` ✓; `fn_devolver_ingredientes_elaborado` viva = `(bigint, numeric, bigint, bigint, integer)` = `35:125-131` ✓.

## b) Ninguna función viva pisada — **CONFIRMADO**

`grep '^CREATE OR REPLACE FUNCTION'` sobre `funcionalidad_cocina/{30,31,33,34,35}`: 15 coincidencias, **todas** con sufijo nuevo o helper nuevo:

- `30`: `fn_ejecutar_entrega_fisica_v3:124`, `fn_preview_entrega_fisica_v3:225`, `fn_ingrediente_base_alcanzable:280`, `fn_ingredientes_elaborado_base:560`, `fn_consumir_ingrediente_base_v2:696`.
- `31`: `fn_validar_ingredientes_elaborado_v2:55`, `fn_descontar_ingredientes_elaborado_v2:163`, `fn_descontar_venta_enrutada_v2:284`.
- `33`: `fn_pedir_item_cuenta_v2:121`, `fn_agregar_producto_orden_pendiente_v2:366`, `fn_actualizar_cantidad_producto_orden_v2:611`.
- `34`: **solo** `fn_registrar_venta_offline_v4:145` por `CREATE`; `_v3`/`_mesa_v3` se crean por `DO $do$` con `EXECUTE` de la definición viva **renombrando la cabecera** (`34:37-81`, `34:92-126`) — no hay `CREATE OR REPLACE` sobre un nombre vivo.
- `35`: `fn_devolver_ingredientes_elaborado_v2:125`, `fn_cancelar_item_pedido_v2:388`, `fn_eliminar_producto_orden_v2:636`.

`presentaciones_inventario/47_tests_guard_search_path.sql` (497 líneas): **todo** el DDL está entre `BEGIN`/`ROLLBACK`
— `BEGIN:106` → `CREATE` guard `_safe:109`, `CREATE` guard viva:154, `CREATE` `_probe_guard_safe:193`, `DROP:268`, `ROLLBACK:279`;
`BEGIN:292` → `CREATE:295/334/344`, `DROP:450/451`, `ROLLBACK:453`. Los bloques `39-58` y `67-97` no tienen DDL.
**No hay ningún `COMMIT` en el archivo.** ⇒ nada queda aplicado tras correrlo.

## c) Dart sin errores — **CONFIRMADO**

`mcp__dart__analyze_files` (root `file:///C:/Users/cesar/Documents/VentIQ-seller-App/ventiq_app`).

- **Errores (`error •`) en todo el proyecto: 1**, y **no** está en los 5 archivos del encargo:
  `lib\utils\package_image_picker_web.dart:13:8 • Target of URI doesn't exist: 'dart:js_util'` (archivo web-only con import condicional; preexistente).
- **0 errores** en `services/{product_detail_service,order_service,auto_sync_service,mesa_cuenta_service}.dart` y `screens/preorder_screen.dart`.
- La corrección del lead en `auto_sync_service.dart:4011` **compila**: el `try` de `4010` tiene su `catch` en `4053`. Residuo (no error): `warning • lib\services\auto_sync_service.dart:4009:9 • The value of the local variable 'usedAtomicPagos' isn't used` (queda muerta tras el arreglo).

## d) `34` es aplicable tras `30`/`31` en orden — **CONFIRMADO**

Las dos precondiciones de `34:45` y `34:48` coinciden exactamente con lo declarado:

| `to_regprocedure` en `34` | Declarado en | Veredicto |
|---|---|---|
| `fn_descontar_venta_enrutada_v2(bigint,numeric,bigint,bigint,integer,boolean)` (`34:45`) | `31:284-291` | **CONFIRMADO** |
| `fn_ejecutar_entrega_fisica_v3(bigint,bigint,bigint,numeric,integer,bigint,bigint,bigint,bigint,uuid,text)` (`34:48`) | `30:124-136` | **CONFIRMADO** |

Además, el `DO`-block de `34` exige **1** ocurrencia de cada token, y en producción se cumple:
`pg_get_functiondef` de `fn_registrar_venta_v2` y de `fn_registrar_venta_mesa_v2` →
`FUNCTION public.<propia>(` = **1**, `fn_ejecutar_entrega_fisica_v2(` = **1**, `fn_descontar_venta_enrutada(` = **1**
(en `prosrc` los conteos son 1 y 1; el nombre sin paréntesis aparece 3 veces, pero siempre en comentarios, y el token sustituido lleva paréntesis).
⇒ los tres `IF v_n <> 1` no abortan.

---

## Corrección obligatoria detectada (fuera de los 4 puntos, pero bloquea la aplicación)

**`33` no se puede aplicar antes que `35`.** `funcionalidad_cocina/33_ordenes_cocina_cantidad_en_base.sql:110-112`
aborta si falta `fn_devolver_ingredientes_elaborado_v2`, que **crea `35`** (`35:125`); y `APLICACION_PRESENTACIONES_INGREDIENTES.md:56-57`
lista `33` (paso 6) **antes** de `35` (paso 7) ⇒ con ese orden el paso 6 falla con
`Falta fn_devolver_ingredientes_elaborado_v2: aplica antes funcionalidad_cocina/35_devoluciones_presentacion.sql`.
Arreglo: invertir los pasos 6 y 7 (35 antes que 33) — `35` solo depende de `45` (`35:113`), así que el intercambio es seguro.

## Conteo

| Punto | CONFIRMADO | INCORRECTO | NO VERIFICABLE |
|---|---|---|---|
| a) firmas cruzadas | 2 (+2 extra) | 0 | 0 |
| b) vivas intactas (30/31/33/34/35 + 47) | 2 | 0 | 0 |
| c) Dart | 1 | 0 | 0 |
| d) `34` aplicable en orden | 2 (+1 de conteos) | 0 | 0 |
| **Total** | **8** | **0** | **0** |

**No verificado (fuera del alcance acordado):** semántica profunda del consumo, tests de `32`/`47` en ejecución (imposible: sin DDL),
y coherencia global del runbook más allá del cruce `33`/`35`.