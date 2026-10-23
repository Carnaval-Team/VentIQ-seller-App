# Verificación adversarial #2 — plan actualizado de consumo de ingredientes y presentaciones

**Verificador:** `verifier2` (contexto propio; sin compartir contexto con el resto del equipo).
**Fecha de la verificación:** 2026-10-21 (misma jornada que la medición de §2-bis).
**Objeto:** `docs/PLAN_CONSUMO_INGREDIENTES_ELABORADOS_PRESENTACIONES.md` — revisión con **§0 reescrito**, **§2-bis** (mediciones del proyecto debug) y **Fases 0.5 / 1 / 3** nuevas.
**Regla:** este documento **no modifica el plan**. Solo dictamina y propone correcciones exactas.

## 0 · Cómo se verificó (reproducible)

| Fuente | Acceso |
|---|---|
| Debug `qhprswhhfasrikhawjoz` | MCP HTTP `https://mcp.supabase.com/mcp?project_ref=qhprswhhfasrikhawjoz&read_only=true&features=…`, flujo `initialize` → `notifications/initialized` → `tools/call` `execute_sql`. **Body JSON escrito a fichero + `curl.exe --data-binary "@ruta"`** (nunca inline). Solo `SELECT` y funciones de lectura. |
| Producción `vsieeihstajlrdvpuooh` | MCP de la sesión (`execute_sql`, solo lectura) para md5 agregados; el mismo endpoint HTTP con `project_ref=vsieeihstajlrdvpuooh` para leer `prosrc` largos a fichero. |
| Código Dart | Lectura directa de `ventiq_app/lib/**` en el repo. |
| SQL del repo | Lectura directa de `funcionalidad_cocina/01_helpers_bom_almacen.sql`, `presentaciones_inventario/25_venta_con_rebalanceo.sql`, etc. |

No se ejecutó ninguna escritura ni DDL. No se invocó ninguna función de escritura.

## 1 · Resumen

**46 afirmaciones comprobadas: 40 CONFIRMADO · 5 INCORRECTO · 1 NO VERIFICABLE** (2 de las CONFIRMADO llevan matiz de rango de líneas).

**Hallazgos graves (3):**

1. **§2-bis / Fase 0.5 (C9) — el «inventario exacto» de 5 funciones es falso: hay 31 funciones `public` con `search_path=''` en *ambos* proyectos; 8 llaman al guard, y 4 de ellas rompen de verdad con 42P01.** Dos de las que rompen (`fn_registrar_venta_offline_v2/v3`) **no están en la lista del plan**, y `fn_registrar_venta_offline_v3` **la app ya la llama hoy** (`auto_sync_service.dart:4015`, con fallback). Las 3 funciones «cumplimiento» que el plan sí lista (`fn_aplicar_cumplimiento_v2`, `fn_crear_extraccion_con_movimiento_v2`, `fn_preview_cumplimiento_v2`) **no llaman al guard y usan nombres calificados**, así que no fallan por C9.
2. **§0, fila Frijoles del «desastre»: INCORRECTA.** Dice «no cubre 5000 base (consume 5000 “unidades” = 5000 base, correcto por casualidad)». En realidad el bucle **cierra el pendiente en 0 y no devuelve error**, y lo que escribe es **dos filas a cero que representan 2500 base + 2.500.000 base** (la fila `Kilogramo` de Frijoles se queda en 0 igual que la de Arroz). La fila oculta el segundo saqueo, que es justo lo que §8 y §9.1 quieren evitar.
3. **Cita de C10 mal atribuida.** `INGREDIENTES_SQL.md §11` es la tabla «`file:line` del repo local utilizado», no la prueba del commit parcial. La evidencia correcta es `VERIFICACION_PLAN.md` H3/F7/F8 + `prosrc` de `fn_registrar_venta` L364-371 (que sí existe y está confirmada).

**Correcciones menores:** fuente de `factor_rel` (no es columna), rango de líneas de `_checkInventoryAvailability`, rango del diálogo, y la caracterización de C6 («`_v2` no abre empaques»).

---

## 2 · Bloque A · Mediciones de §2-bis contra el proyecto debug

Todas las consultas son `SELECT` sobre `qhprswhhfasrikhawjoz`.

| # | Afirmación del plan | Veredicto | Evidencia (consulta recortada / resultado) |
|---|---|---|---|
| A1 | Producto 3 Arroz: fila pp **8** `Kilogramo` `cantidad=1000`, fila pp **4** `Unidad` `es_base=true` | **CONFIRMADO** | `select pp.id_producto, pp.id, pp.id_presentacion, pr.denominacion, pp.cantidad, pp.es_base from app_dat_producto_presentacion pp join app_nom_presentacion pr on pr.id=pp.id_presentacion where pp.id_producto in (3,4,5)` → `3|4|1|Unidad|1.0|true`, `3|8|15|Kilogramo|1000.0|false` |
| A2 | Producto 4 Frijoles: fila pp **7** `Kilogramo` `cantidad=1000`, fila pp **5** `Unidad` base | **CONFIRMADO** | misma consulta → `4|5|1|Unidad|1.0|true`, `4|7|15|Kilogramo|1000.0|false` |
| A3 | Producto 5 Arroz Moro: presentación `Unidad` fila pp **6**, `es_base=true`, `factor_rel=1` | **CONFIRMADO** | misma consulta → `5|6|1|Unidad|1.0|true`; `fn_presentaciones_producto(5)` → `id_presentacion 6, factor 1.0, factor_rel 1.000000, es_base true` |
| A4 | `factor_rel` = **1000** (Kilogramo 3 y 4) y **1** (Unidad 3, 4 y 5) | **CONFIRMADO** | `select * from fn_presentaciones_producto(3) union all …(4)… union all …(5)` → `id_presentacion 8 factor_rel 1000.000000`, `4 → 1.000000`, `7 → 1000.000000`, `5 → 1.000000`, `6 → 1.000000`. **Matiz:** `factor_rel` **no es columna** de `app_dat_producto_presentacion` (esa tabla sólo tiene `id, id_producto, id_presentacion, cantidad, es_base, created_at, precio_promedio`, y **no existe ninguna columna `factor_rel` en toda la BD**: `information_schema.columns … where column_name ilike '%factor%'` → ninguna en `public`). `factor_rel` lo **calcula** `fn_presentaciones_producto` (y `fn_stock_saldos_presentacion`). El encabezado de la tabla de §2-bis atribuye `factor_rel` a `app_dat_producto_presentacion`: ver corrección **A-1**. |
| A5 | Producto 5 `es_elaborado = true`, tienda 4, `id_cocina = null` | **CONFIRMADO** | `select id,denominacion,es_elaborado,id_tienda,id_cocina,modo_elaboracion from app_dat_producto where id in (3,4,5)` → `5|Arroz Moro|true|4|null|al_pedido`; 3 y 4 → `es_elaborado=false`, tienda 4 |
| A6 | Receta del 5: Frijoles (4) × **500** y Arroz (3) × **600**, `unidad_medida = null` | **CONFIRMADO** | `select id_producto_elaborado,id_ingrediente,cantidad_necesaria,unidad_medida from app_dat_producto_ingredientes where id_producto_elaborado=5` → `5|4|500.0|NULL`, `5|3|600.0|NULL` |
| A7 | Saldo vigente ubicación 3 / almacén 3: 3-`Unidad` **2000** `13:58:03`, 3-`Kilogramo` **2000** `13:54:37`, 4-`Unidad` **2500** `13:58:03`, 4-`Kilogramo` **2500** `13:54:37` | **CONFIRMADO** | `select distinct on (id_producto,id_presentacion) id,id_producto,id_ubicacion,id_presentacion,cantidad_final,created_at from app_dat_inventario_productos where id_producto in (3,4) and id_ubicacion=3 order by id_producto,id_presentacion,created_at desc,id desc` → `23|3|3|4|2000.00000000|2026-10-21 13:58:03.936063+00`, `20|3|3|8|2000.00|13:54:37.730231`, `22|4|3|5|2500.00000000|13:58:03.936063`, `19|4|3|7|2500.00|13:54:37.730231` |
| A8 | «las filas `Kilogramo` tienen 2000 y 2500» | **CONFIRMADO** | A7: `id_presentacion 8 → 2000.00` y `7 → 2500.00` (unidades de la presentación `Kilogramo` ⇒ 2000 kg y 2500 kg) |
| A9 | El cliente ve «En stock 2000 / 2500» porque `getProductIngredients` lee la fila **más reciente sin filtro de presentación** | **CONFIRMADO** | Datos A7 (la más reciente del producto 3 es la `Unidad`=2000; del 4 es `Unidad`=2500) + `product_detail_service.dart:549-554` (ver C5) |
| A10 | `fn_stock_producto_almacen(3, 3) = 2002000` | **CONFIRMADO** | `select fn_stock_producto_almacen(3,3)` → `2002000.00000000000000` = 2000·1 + 2000·1000 |
| A11 | `fn_stock_producto_almacen(4, 3) = 2502500` | **CONFIRMADO** | → `2502500.00000000000000` = 2500·1 + 2500·1000 |
| A12 | `fn_stock_producto_almacen(3, NULL)` / `(4, NULL)` idénticos | **CONFIRMADO** | → `2002000` y `2502500` respectivamente; y `select distinct on (id_producto,id_ubicacion,id_presentacion) … from app_dat_inventario_productos where id_producto in (3,4)` devuelve **solo 4 filas, todas con `id_ubicacion=3`** |
| A13 | `fn_validar_ingredientes_elaborado(5, 10, 3)` = `success`, disponible 2502500 / 2002000 | **CONFIRMADO** | → `{"status":"success","id_almacen":3,"ingredientes":[{"ingrediente":"Frijoles","id_ingrediente":4,"cantidad_requerida":5000.0,"cantidad_disponible":2502500.0…},{"ingrediente":"Arroz","id_ingrediente":3,"cantidad_requerida":6000.0,"cantidad_disponible":2002000.0…}],"tiene_receta":true}` |
| A14 | `fn_stock_producto_almacen_detalle(3,3)` y `(4,3)` → **dos filas con el mismo número** (empate) | **CONFIRMADO** | `select * from fn_stock_producto_almacen_detalle(3,3)` → `(id_ubicacion 3, id_presentacion 4, 2000.00000000)` y `(3, 8, 2000.00)`; `(4,3)` → `(3, 5, 2500.00000000)` y `(3, 7, 2500.00)`. Ambos pares empatan en `cantidad_final` **y** en `id_ubicacion` (=3), luego el `ORDER BY v.cantidad_final DESC, v.id_ubicacion` (con `01_helpers_bom_almacen.sql:101` confirmado) **no tiene desempate efectivo** |
| A15 | md5 de `pg_get_functiondef`: `check_user_has_access_to_tienda = 438dbaec…`, `fn_ejecutar_entrega_fisica_v2 = 9edf415b…`, `fn_preview_entrega_fisica_v2 = c46c5d97…` **idénticos en debug y producción** | **CONFIRMADO** | Debug: `438dbaec6f0fe94c23d4cb414cc41d89`, `9edf415b400a467a1d6627a628fd3376`, `c46c5d977095057a7f33b8f7b360e254`. Producción (`vsieeihstajlrdvpuooh`, MCP de sesión): **los tres md5 idénticos** |
| A16 | `fn_descontar_ingredientes_elaborado` «sigue con el `LEAST` mixto (**len 3909**, igual que producción)» y está activo en el camino de descuento | **CONFIRMADO** | Debug `length(prosrc)=3909`, md5 `47be3a93f8d026eba2f5fbfc31b0cd4a`; producción `length(prosrc)=3909`, **mismo md5**. `LEAST` en `prosrc` **línea 33** (calculado con `regexp_matches` de saltos de línea) y `pg_get_functiondef` lo muestra como `v_a_descontar := LEAST(v_ubic.cantidad_final, v_pendiente);` dentro del bucle sobre `fn_stock_producto_almacen_detalle`. Activo: `fn_descontar_venta_enrutada` lo llama en la rama `ingredientes` (prosrc L45) |
| A17 | §0(a): al debug no le faltan migraciones — «27 aplicada», 24/22/25, pack v2 y tablas de eventos | **CONFIRMADO (con matiz de prueba)** | El **registro** `supabase_migrations.schema_migrations` **no** contiene 22/24/25/27 (se aplicaron por SQL directo), así que la prueba es **por efecto**: `fn_rebalancear_presentaciones`, `fn_registrar_conversion_v2`, `fn_ejecutar_entrega_fisica_v2`, `fn_registrar_venta_v2`, `fn_descontar_con_rebalanceo_almacen` existen; `app_dat_conversion_presentacion`, `app_dat_conversion_presentacion_evento`, `app_dat_conversion_presentacion_pata` existen; y los totales base sólo salen con `factor_rel` (A10/A11). La afirmación se sostiene |
| A18 | §0(b) el catálogo está bien: `Kilogramo` fila 8/7 `cantidad=1000` `factor_rel=1000`, `Unidad` fila 4/5 base `factor_rel=1` | **CONFIRMADO** | A1/A2/A4 |
| A19 | §0(c) no es multi-almacén: todo el stock está en ubicación 3 / almacén 3 | **CONFIRMADO** | A7/A12 (4 filas de ledger en total, todas `id_ubicacion=3`); `app_dat_layout_almacen` id 3 → `id_almacen=3` |
| A20 | §0: «tienda 4, TPV «Caja 1», almacén 3» | **CONFIRMADO** | `select id,denominacion,id_tienda,id_almacen from app_dat_tpv where id=3` → `3|Caja 1|4|3`; `fn_resolver_origen_venta(5,3)` → `{"origen":"barra","descontar":"ingredientes","id_cocina":null,"id_almacen":3,"id_producto":5}`, y `fn_resolver_origen_venta(3,3)` → `descontar:"sku"`. Esto además **confirma la «ruta barra»** que §2-bis infiere de `id_cocina = null` |

**Bloque A: 20 CONFIRMADO · 0 INCORRECTO.**

---

## 3 · Bloque A2 · C9 (`search_path` + guard) y su inventario

| # | Afirmación | Veredicto | Evidencia |
|---|---|---|---|
| C9-1 | `proconfig` con `search_path` vacío en `fn_ejecutar_entrega_fisica_v2`, `fn_preview_entrega_fisica_v2`, `fn_aplicar_cumplimiento_v2`, `fn_crear_extraccion_con_movimiento_v2`, `fn_preview_cumplimiento_v2` | **CONFIRMADO** | `select proname, proconfig, md5(pg_get_functiondef(oid)) from pg_proc …` → las cinco con `proconfig = ["search_path=\"\""]` y md5 `9edf415b…`, `c46c5d97…`, `96654b7d…`, `745fb752…`, `2a67058d…`; **los mismos md5 en producción** |
| C9-2 | `check_user_has_access_to_tienda` no tiene `SET` propio (`proconfig` null) y usa tablas sin calificar | **CONFIRMADO** | `proconfig = null`, md5 `438dbaec…` (idéntico en producción). `prosrc`: `SELECT EXISTS (SELECT 1 FROM app_dat_vendedor WHERE uuid = auth.uid() … UNION … FROM app_dat_tpv … FROM app_dat_almacenero … FROM app_dat_almacen … FROM app_dat_supervisor … FROM auditor … FROM app_dat_gerente … FROM app_dat_jefe_cocina jc JOIN app_dat_cocina c …)` — **todas sin `public.`** |
| C9-3 | Llamar `fn_preview_entrega_fisica_v2` da **42P01** `relation "app_dat_vendedor" does not exist` | **CONFIRMADO (exacto)** | `select public.fn_preview_entrega_fisica_v2(3, 3, 4, 1, null, null)` → `ERROR: 42P01: relation "app_dat_vendedor" does not exist … CONTEXT: PL/pgSQL function public.check_user_has_access_to_tienda(bigint) line 5 at SQL statement … PL/pgSQL function public.fn_preview_entrega_fisica_v2(bigint,bigint,bigint,numeric,bigint,bigint) line 5 at PERFORM` |
| C9-4 | «la tabla existe; es el `search_path` vacío heredado» | **CONFIRMADO** | Las 7 tablas del guard existen en `public`: `count(*) = 7` para `app_dat_vendedor, app_dat_tpv, app_dat_almacenero, app_dat_supervisor, app_dat_gerente, app_dat_jefe_cocina, app_dat_cocina`. Mecanismo reproducido en aislamiento: `do $do$ begin perform set_config('search_path','',false); select count(*) into n from app_dat_vendedor; end $do$` → `42P01: relation "app_dat_vendedor" does not exist` |
| C9-5 | «el mismo fallo está en producción, latente porque hoy nadie llama a la ruta `_v2`» — primera mitad | **CONFIRMADO (por equivalencia)** | `fn_ejecutar_entrega_fisica_v2` (prosrc L9 `PERFORM public.check_user_has_access_to_tienda(v_id_tienda);`) y `check_user_has_access_to_tienda` tienen **md5 idénticos** en ambos proyectos, luego la definición es la misma. **Matiz:** la ejecución 42P01 la hice **en debug**; en producción no ejecuté la llamada (no hizo falta: md5 igual ⇒ mismo comportamiento) |
| C9-6 | «latente porque hoy nadie llama a la ruta `_v2`» — segunda mitad | **INCORRECTO** | El endpoint roto **ya se llama**: `ventiq_app/lib/services/auto_sync_service.dart:4015` invoca `'fn_registrar_venta_offline_v3'`, que tiene `search_path=''` (proconfig confirmado), **no** hace `set_config` y ejecuta `PERFORM public.check_user_has_access_to_tienda(v_id_tienda);` en **prosrc L10** de forma incondicional ⇒ 42P01. Igual `fn_registrar_venta_offline_v2` (L10). La app tiene fallback (a `fn_registrar_venta_offline` y luego a `fn_registrar_venta`), por eso el síntoma no es obvio, pero el plan no puede afirmar que la ruta rota está inerte. Ver corrección **C9-a** |
| C9-7 | «**Inventario exacto** a revisar (los dos proyectos): funciones con `proconfig` de `search_path` vacío → [las 5 de C9-1]» | **INCORRECTO** | `select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and array_to_string(p.proconfig,',') = 'search_path=' || chr(34)||chr(34)` → **31 en debug y 31 en producción**. De esas 31, **8 llaman al guard**, y sólo **4 rompen** (no restauran `search_path`): `fn_ejecutar_entrega_fisica_v2`, `fn_preview_entrega_fisica_v2`, **`fn_registrar_venta_offline_v2`**, **`fn_registrar_venta_offline_v3`**. Las otras 4 se auto-corrigen con `set_config('search_path','public, pg_catalog', false)`: `fn_inventario_resumen_por_usuario_almacen3`, `fn_stock_mixto_producto_por_ubicacion`, `get_productos_by_categoria_tpv_search_meta_v3` (con comentario explícito en el cuerpo: «check_user_has_access_to_tienda resuelve tablas SIN calificar… Se restaura public, pg_catalog ANTES de la guarda»), `get_productos_by_categoria_tpv_v2`. Y las otras **3 de la lista del plan** (`fn_aplicar_cumplimiento_v2`, `fn_crear_extraccion_con_movimiento_v2`, `fn_preview_cumplimiento_v2`) **no aparecen entre los que llaman al guard** y no usan tablas sin calificar (`position('FROM app_' in prosrc)=false`, etc.) ⇒ **no fallan por C9**. Ver corrección **C9-b** |

**Bloque A2: 5 CONFIRMADO · 2 INCORRECTO.**

---

## 4 · Bloque B · Diseño 1B, secuencia obligatoria y C10

| # | Afirmación | Veredicto | Evidencia |
|---|---|---|---|
| B1 | «la app usa los nombres **sin** `_v2`» (`order_service.dart:1442-1443`) | **CONFIRMADO (exacto)** | `ventiq_app/lib/services/order_service.dart:1442-1443`: `final rpcName = useMesaRpc ? 'fn_registrar_venta_mesa' : 'fn_registrar_venta';` |
| B2 | Con 1B hay que crear `fn_registrar_venta_v3` / `_mesa_v3` (y no existen hoy) | **CONFIRMADO** | Producción: existen `fn_registrar_venta`, `fn_registrar_venta_mesa`, `…_v2`, `…_mesa_v2`; **no existen `fn_registrar_venta_v3` ni `fn_registrar_venta_mesa_v3`** (tampoco `fn_registrar_venta_offline_v4`; sólo `offline_v2` y `offline_v3`). Como la decisión 1B prohíbe tocar los cuerpos vivos y B1 fija el nombre que llama la app, **la única vía para que la app nueva use la cadena corregida es un nombre nuevo (`_v3`) + migrar el Dart**. El razonamiento del plan es correcto |
| B3 | `fn_registrar_venta` **RETURNA** el jsonb de error del BOM **sin `RAISE`** ⇒ un fallo del descuento confirma escrituras parciales | **CONFIRMADO** | `prosrc` de producción L364-371: `IF (v_descuento_bom->>'status') <> 'success' THEN … RETURN v_descuento_bom \|\| jsonb_build_object(…)`. La cadena no lanza: `fn_descontar_venta_enrutada` rama `ingredientes` (prosrc L44-62) hace `RETURN v_resultado \|\| …` cuando el helper falla; `fn_descontar_ingredientes_elaborado` hace `RETURN jsonb_build_object('status','error','error_code','INSUFFICIENT_STOCK_INGREDIENT', …)` (prosrc L81-95) **después** de haber insertado en `app_dat_inventario_productos` (L38-64). Sin excepción no hay rollback ⇒ los `INSERT` previos quedan y, al ser una llamada RPC normal, **se confirman**. También confirma el matiz de `VERIFICACION_PLAN.md` H3/F7/F8 |
| B4 | Cita de B3: «(`INGREDIENTES_SQL.md` §11)» | **INCORRECTO** | `INGREDIENTES_SQL.md:991` = `## 11. file:line del repo local utilizado` (tabla de referencias), **no** contiene la afirmación del commit parcial. La evidencia real: `docs/_analisis/VERIFICACION_PLAN.md:47`, `:160-161`, `:175` (H3/F7/F8) y `prosrc L364-371`. Ver corrección **B-1** |
| B5 | §0: con los saldos de debug, la venta de Arroz 3 (pendiente 6000) «descuenta 2000 de una, 2000 de la otra, pendiente 2000», deja **las dos filas de 2000 en cero** y responde `(faltan 2000)` | **CONFIRMADO** | `fn_obtener_ingredientes_recursivos(5,10)` → `(4, 5000.0)`, `(3, 6000.0)`. `fn_stock_producto_almacen_detalle(3,3)` (A14) → 2000 y 2000. Bucle `LEAST(cantidad_final, pendiente)`: 2000 → pendiente 4000; 2000 → pendiente 2000; `v_pendiente > 0` ⇒ `RETURN` con `'message' = 'Stock insuficiente para el ingrediente: Arroz (faltan 2000)'` y `'cantidad_disponible' = 6000-2000 = 4000`. Ambas filas se insertan con `cantidad_final = 0` |
| B6 | §0, fila **Frijoles**: «descuenta 2500 + 2500, pendiente 0 → **no** cubre 5000 base (consume 5000 «unidades» = 5000 base, **correcto por casualidad**)» | **INCORRECTO** | Frijoles se procesa **primero** (`fn_obtener_ingredientes_recursivos` lo devuelve en la posición 1) y con las dos filas de **2500** (A14) el bucle hace 2500 → pendiente 2500, 2500 → pendiente 0, `EXIT` sin error: **el bucle considera cubierto** el requerimiento (la frase «no cubre 5000 base» contradice el propio mecanismo). El efecto real en el ledger es **dos filas a cero**: la `Unidad` (2500 base) **y la `Kilogramo` (2500 kg = 2.500.000 base)** — es decir, no «consume 5000 base», destruye 2.502.500 base. La fila omite el segundo saqueo y contradice el criterio de §8.1/§9.1. Ver corrección **B-2** |
| B7 | §0: «esos movimientos **se confirman** en la misma transacción» | **CONFIRMADO** | B3 + A16. Además, el orden real (Frijoles 1.º, Arroz 2.º) implica que **cuando se lanza el error ya hay 4 escrituras** (2 de Frijoles + 2 de Arroz) en el ledger |
| B8 | §0: «el servidor valida bien y el cliente bloquea con un número falso» | **CONFIRMADO** | A13 (validación `success`, disponible 2.502.500 / 2.002.000 ≥ 5.000 / 6.000) frente a A9/A8 (el cliente compara 2.500 y 2.000) |
| B9 | §0/§2-bis: el **empate** explica el «a veces gramo, a veces kg» porque `ORDER BY v.cantidad_final DESC, v.id_ubicacion` (`01_helpers_bom_almacen.sql:101`) no tiene desempate | **CONFIRMADO** | A14 (empate en `cantidad_final` **y** en `id_ubicacion`) + `funcionalidad_cocina/01_helpers_bom_almacen.sql:101` = `ORDER BY v.cantidad_final DESC, v.id_ubicacion;` (y `pg_get_functiondef` coincide). Con las dos filas idénticas en ambos criterios, el orden es indeterminado |
| B10 | §3.1 C2: `LEAST` mixto en `fn_descontar_ingredientes_elaborado:33` y `fn_descontar_venta_enrutada:118` | **CONFIRMADO (exacto)** | `select proname, (select count(*) from regexp_matches(left(prosrc, position('LEAST(' in prosrc)-1), E'\n','g'))+1 …` → `fn_descontar_ingredientes_elaborado: 33`, `fn_descontar_venta_enrutada: 118` |
| B11 | §4.4: el `RAISE` de la rama SKU de `fn_descontar_venta_enrutada` está en **L160-163** (no L159-162) | **CONFIRMADO** | `prod_fn_descontar_venta_enrutada` L158-163: comentario en L158, `RAISE EXCEPTION` en **L160**, argumentos L161-162, `END IF` en L163. Coincide con `VERIFICACION_PLAN.md` S17 |

**Bloque B: 9 CONFIRMADO · 2 INCORRECTO.**

### 4-bis · Hallazgo secundario (no encargado, pero comprobado)

| # | Afirmación | Veredicto | Evidencia |
|---|---|---|---|
| B12 | §3.1 C6 + `INGREDIENTES_SQL.md` §8.7: «`_v2` de venta **sin el `25`** (no abren empaques)» | **INCORRECTO (impreciso)** | `fn_registrar_venta_v2` (prosrc L255-271) **sí** ejecuta la apertura/armado de empaques: llama a `public.fn_ejecutar_entrega_fisica_v2(...)` y aborta si no es `success`. Lo que le falta es **el `25`** tal cual (la pareja `fn_rebalancear_presentaciones` + guardas `v_n_pres`/`v_permite_neg` que sí tiene `fn_registrar_venta` en L256-285), y sobre todo **está rota por C9** (llama al ejecutor `_v2` ⇒ 42P01, y en L265-269 lo convierte en `RAISE EXCEPTION`). La conclusión práctica del plan (no apoyarse en la cadena `_v2`; crear `_v3`) no cambia, pero la frase «no abren empaques» es falsa. Ver corrección **B-3** |

---

## 5 · Bloque C · Código Dart del emisor del cartel

| # | Afirmación | Veredicto | Evidencia (`ruta:línea`) |
|---|---|---|---|
| D1 | El diálogo `Problema de Inventario` es `_checkInventoryAvailability` (`preorder_screen.dart` ~1271-1594) | **CONFIRMADO (con matiz de rango)** | `preorder_screen.dart:1271` = `Future<List<Map<String, dynamic>>> _checkInventoryAvailability(`. **Matiz:** el cuerpo termina en **:1576** (`return problems;` en 1575, `}` en 1576); 1578-1592 es otra función (`_isNetworkError`) y 1594 es el doc-comment de `_showStockNetworkErrorDialog`. El rango exacto del método es **1271-1576**. Ver corrección **D-1** |
| D2 | Chips `Pedido` / `En stock` / `Faltante` en ~1655-1760 | **CONFIRMADO (con matiz de rango)** | Título `'Problema de Inventario'` en **:1657**; `_showStockProblemsDialog` abre en **:1642** y cierra en **:1750**; los chips se construyen en **:1700-1724** (`_buildStockChip('Pedido'…)`, `'En stock'`, `'Faltante'`) dentro del `Row` **:1697-1726**; `_buildStockChip` va de **:1752-1787**. El rango 1655-1760 cubre el título y los chips, pero la función empieza antes y `_buildStockChip` acaba después |
| D3 | Corta la venta en `_finalizeOrder` (~932-935) | **CONFIRMADO (exacto)** | `_finalizeOrder()` se declara en **:848**; en **:932-935**: `if (stockProblems.isNotEmpty) { _showStockProblemsDialog(stockProblems); return; }` (cierre en 935). Es el único punto donde el cartel bloquea la venta |
| D4 | Para elaborados online la fuente es `getProductIngredients` (**:1355-1356**) y se compara en **:1367-1380** | **CONFIRMADO (exacto)** | `:1355-1356` = `final ingredientes = await _productDetailService.getProductIngredients(item.producto.id);` (rama `// ONLINE` en :1353). `:1367-1370` calcula `cantidadNecesaria = cantidad_necesaria × item.cantidad`; `:1371-1373` toma `cantidadDisponible = ingrediente['cantidad_disponible']`; **:1380** = `if (cantidadDisponible < cantidadNecesaria) { problems.add({…'presentacion': ' (ingrediente)'}) }` |
| D5 | `product_detail_service.dart:549-559` es **exactamente** la consulta del curl del usuario | **CONFIRMADO (exacto)** | `:549-554`: `_supabase.from('app_dat_inventario_productos').select('cantidad_final').eq('id_producto', idIngrediente).order('created_at', ascending: false).limit(1);` — **sin** filtro de `id_presentacion`, **sin** factor, **sin** suma. `:556-559` lee `inventoryResponse.first['cantidad_final']`. El `debugPrint` de :560-562 documenta el «cantidad disponible» que acaba en el cartel |
| D6 | `getProductIngredients` ocupa `product_detail_service.dart:506-593` | **CONFIRMADO** | La firma está en **:506** y el `catch`/`return []` cierra en **:593** |
| D7 | §1: los otros emisores «`⚠️ Stock Insuficiente` con `Necesario/Disponible <unidad>`» están en `:2700-2706` y `:2824-2828` (no bloqueantes) | **NO VERIFICABLE en esta pasada** | No formaba parte del encargo (A/B/C) y no se abrió ese rango. Queda pendiente para otra pasada |

**Bloque C: 6 CONFIRMADO (2 con matiz de rango) · 1 NO VERIFICABLE.**

---

## 6 · Correcciones exactas propuestas (no aplicadas)

> Solo texto; el plan **no** ha sido modificado.

**A-1 · §2-bis, encabezado de la tabla de presentaciones (línea 95).**
Sustituir:
`**Productos y presentaciones** (`app_dat_producto` + `app_dat_producto_presentacion` + `app_nom_presentacion`)`
por:
`**Productos y presentaciones** (`app_dat_producto` + `app_dat_producto_presentacion` + `app_nom_presentacion`; la columna `factor_rel` **no está almacenada** — la calcula `fn_presentaciones_producto(p_id_producto)`, y `id_presentacion` en el ledger es el `id` de `app_dat_producto_presentacion`, p. ej. 4/8/5/7).`

**B-1 · §0 (línea 58) y §3.1 C10 (línea 152) y §12 (línea 403): cita de C10.**
Sustituir `(`INGREDIENTES_SQL.md` §11)` por:
`(`docs/_analisis/VERIFICACION_PLAN.md` H3/F7/F8; `prosrc` de `fn_registrar_venta` L364-371: `RETURN v_descuento_bom || jsonb_build_object(…)` sin `RAISE`)`.
Y en §12: `| C10 commit parcial | `VERIFICACION_PLAN.md` H3/F7/F8; `prosrc` L364-371 |`.

**B-2 · §0, fila Frijoles de la tabla del «desastre» (línea 56).**
Sustituir la fila por:

| Ingrediente | pendiente base | filas del detalle (`ORDER BY cantidad_final DESC`) | qué haría el bucle | resultado |
|---|---|---|---|---|
| Frijoles 4 | 5000 | Unidad 2500 y Kilogramo 2500 (**empate**) | 1.º de los dos ingredientes; descuenta 2500 + 2500, pendiente 0 ⇒ **sin error** | deja **la Unidad (2500 base) y el `Kilogramo` (2500 kg = 2.500.000 base) en cero** sin reportar nada |

Y añadir tras la tabla: «Frijoles se procesa **primero** (`fn_obtener_ingredientes_recursivos` lo devuelve en la posición 1), así que cuando Arroz lanza `(faltan 2000)` ya hay **4 escrituras** en el ledger; el total destruido es 2.502.500 base de Frijoles + las dos filas de Arroz a cero.»

**C9-a · §2-bis (línea 151) y §9 (línea 359): «latente porque hoy nadie llama a la ruta `_v2`».**
Sustituir por:
«latente en la venta de barra/mesa (la app usa los nombres vivos), **pero ya activo en la cola offline**: `fn_registrar_venta_offline_v3` (y `_v2`) tienen `search_path=''`, no restauran `search_path` y llaman al guard en `prosrc` L10; la app ya invoca `fn_registrar_venta_offline_v3` (`auto_sync_service.dart:4015`) con fallback a `fn_registrar_venta_offline`/`fn_registrar_venta`».

**C9-b · Fase 0.5, tercer punto (línea 232).**
Sustituir la lista «→ `fn_ejecutar_entrega_fisica_v2`, `fn_preview_entrega_fisica_v2`, `fn_aplicar_cumplimiento_v2`, `fn_crear_extraccion_con_movimiento_v2`, `fn_preview_cumplimiento_v2`. Más `check_user_has_access_to_tienda` (config `null`, tablas sin calificar).»
por:
«**No son 5: son 31** funciones `public` con `proconfig` de `search_path` vacío en **cada** proyecto (`array_to_string(proconfig,',') = 'search_path=""'`). De ellas, **4 rompen** con 42P01 (tienen `search_path=''`, llaman a `check_user_has_access_to_tienda` y **no** restauran el `search_path`): `fn_ejecutar_entrega_fisica_v2`, `fn_preview_entrega_fisica_v2`, `fn_registrar_venta_offline_v2`, `fn_registrar_venta_offline_v3`. Otras 4 llaman al guard pero se auto-corrigen con `set_config('search_path','public, pg_catalog',false)` (`fn_inventario_resumen_por_usuario_almacen3`, `fn_stock_mixto_producto_por_ubicacion`, `get_productos_by_categoria_tpv_search_meta_v3`, `get_productos_by_categoria_tpv_v2`) ⇒ no tocar. `fn_aplicar_cumplimiento_v2`, `fn_crear_extraccion_con_movimiento_v2` y `fn_preview_cumplimiento_v2` tienen el `search_path` vacío pero **no llaman al guard** y usan nombres calificados ⇒ no fallan por C9 (quitar de la lista de culpables). Más el propio `check_user_has_access_to_tienda` (`config null`, tablas sin calificar).»

**C9-c · Fase 0.5, criterio de aceptación (línea 235).**
Añadir: «y ninguna de las 4 que rompen (incluidas las dos `fn_registrar_venta_offline_v2/v3`, que la app ya llama) falla con `42P01`; las 31 deben quedar auditadas (no solo las 5).»

**B-3 · §3.1 C6 (línea 148) y `INGREDIENTES_SQL.md` §8.7.**
Sustituir «(no abren empaques)» por «(sustituyen `fn_rebalancear_presentaciones` + guardas del `25` por `fn_ejecutar_entrega_fisica_v2`, que **sí** intenta abrir/armar empaques pero está roto por C9: 42P01 convertido en `RAISE EXCEPTION` en `fn_registrar_venta_v2` L265-269)».

**D-1 · §1 (línea 72), §3.2 D1 (línea 158), Fase 7 (línea 301) y §12 (línea 396).**
Sustituir el rango `:1271-1594` por **`:1271-1576`** (el método termina en 1576; 1578-1592 es `_isNetworkError`).

**D-2 · §1 (línea 72), §3.2 D1 y §12: rango del diálogo.**
Sustituir `:1655-1760` por **`:1642-1750`** (función `_showStockProblemsDialog`), indicando que el título está en `:1657` y los chips `Pedido/En stock/Faltante` en `:1700-1724` (`_buildStockChip` en `:1752-1787`).

---

## 7 · Lo que NO se pudo verificar aquí (honestidad de alcance)

1. **§1, otros emisores Dart** (`preorder_screen.dart:2700-2706`, `:2824-2828`): no revisados (fuera del encargo A/B/C).
2. **Producción: ejecución directa del 42P01**: la llamada se ejecutó solo en debug. La equivalencia con producción se apoya en `md5(pg_get_functiondef)` idéntico para `fn_preview_entrega_fisica_v2`, `fn_ejecutar_entrega_fisica_v2` y `check_user_has_access_to_tienda`. Es una inferencia fuerte, no una ejecución.
3. **Censos de §10** (124 elaborados / 14 tiendas, 35 elaborados / 7 tiendas, 6 combos / 9 filas): no recalculados en esta pasada (los cubre `VERIFICACION_PLAN.md`).
4. **Fase 0.5(a) vs (b)**: es una decisión, no una afirmación verificable.
5. **`fn_producir_tanda` (C8) y `fn_disponibilidad_plato` (C4)**: no revisados.

## 8 · Conteo final

| Bloque | CONFIRMADO | INCORRECTO | NO VERIFICABLE |
|---|---|---|---|
| A · §2-bis + §0 (debug) | 20 | 0 | 0 |
| A2 · C9 y su inventario | 5 | 2 | 0 |
| B · 1B, secuencia, C10, desastre | 9 | 2 | 0 |
| B-bis · C6 (secundario) | 0 | 1 | 0 |
| C · Dart | 6 | 0 | 1 |
| **Total** | **40** | **5** | **1** |

**Veredicto global:** el núcleo del plan actualizado es correcto — **las mediciones de §2-bis son exactas** (20/20), **C9 existe y está medido con precisión** en lo que respecta a `_v2`, **C10 (commit parcial) es real y está en el `prosrc` de producción**, y **el diseño 1B exige `_v3` porque la app llama a los nombres vivos** (`order_service.dart:1442-1443`). Los 5 errores son **de inventario/cita/redacción**, no de mecanismo: el más importante es que **el número de funciones afectadas por C9 es 31 (4 rotas), no 5**, y que **la fila Frijoles de §0 esconde un segundo saqueo de 2.500.000 base**.