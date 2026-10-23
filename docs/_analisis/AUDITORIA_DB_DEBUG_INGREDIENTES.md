# Auditoría DB DEBUG — objetos nuevos del plan de ingredientes elaborados

**Fecha:** 2026-10-23 · **Auditor:** `db-auditor` (task-1) · **Entregable único:** este archivo.
**Proyecto auditado:** DEBUG `qhprswhhfasrikhawjoz` (MCP `mcp__supabase-debug__*`).
**Referencia de no-regresión:** PRODUCCIÓN `vsieeihstajlrdvpuooh` (MCP `mcp__supabase__*`, **solo SELECT**; todas las consultas a producción fueron `select ... from pg_proc` / `select <fn STABLE>`, nunca DDL/DML).
**Plan:** `docs/PLAN_CONSUMO_INGREDIENTES_ELABORADOS_PRESENTACIONES.md` · **Runbook:** `docs/APLICACION_PRESENTACIONES_INGREDIENTES.md` · **Antecedente:** `docs/_analisis/VERIFICACION_IMPLEMENTACION.md`.
**Regla aplicada:** si duda → `NO VERIFICABLE` antes que suponer. Las escrituras de prueba se hicieron **solo** dentro de bloques `DO` que terminan en `RAISE EXCEPTION` (rollback automático de la transacción implícita); ninguna prueba podía persistir.

---

## 0 · Resumen ejecutivo

| Fase | Objeto | Veredicto |
|---|---|---|
| 0.5 (C9) | `45_guard_search_path.sql` + `46_patch_guard_en_sitio.sql` | **CONFIRMADO aplicada en debug** (opción (a)+(b)); 42P01 **ya no se reproduce** en debug. En producción sigue vivo (evidencia estática). |
| 1 | `30`, `31` (cadena `_v2` por equivalente base) | **CONFIRMADO**: 8/8 objetos; caso 0 y end-to-end pasan; insuficiencia atómica. |
| 2 | `33` (rutas cocina en base) | **CONFIRMADO existencia** de las 3 funciones; prueba funcional "1 Caja" **NO VERIFICABLE** (no ejecutada, fuera del caso 0). |
| 3 | `34` (venta `_v3`) | **CONFIRMADO**: 3/3 objetos; `_v3` llama exactamente 1× a `fn_descontar_venta_enrutada_v2` y 1× a `fn_ejecutar_entrega_fisica_v3`, 0× a las vivas. |
| 4 | `35` (devoluciones) | **CONFIRMADO existencia** de las 3 funciones; prueba funcional de devolución **NO VERIFICABLE** (no ejecutada). |
| 5 | `36_alcance_ingredientes.sql` | **INCORRECTO/NO VERIFICABLE**: el archivo **no existe** en el repo; el `p_alcance` sí está implementado en `30` con default `'almacen'`. |

**Datos clave:** los **18/18** objetos nuevos existen en debug con las firmas declaradas. Las funciones vivas **no** están todas intactas debug↔producción: **4/6 md5 idénticos**; difieren `check_user_has_access_to_tienda` (por el patch `46`, intencional) y `fn_descontar_venta_enrutada` (**no** atribuible al plan: debug tiene una familia FEFO que producción no tiene). Pruebas funcionales: **caso 0 OK**, **insuficiencia atómica OK**, y tras todas las pruebas el ledger quedó **70 → 70 filas** (nada persistió).

---

## 1 · Existencia y firma exacta de los 18 objetos nuevos

Consulta (debug):

```sql
select p.proname, pg_get_function_identity_arguments(p.oid) as ident,
       pg_get_function_result(p.oid) as ret, p.provolatile, p.prosecdef,
       coalesce(array_to_string(p.proconfig, ','), '(null)') as proconfig,
       md5(pg_get_functiondef(p.oid)) as md5
from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
where ns.nspname = 'public' and p.proname in (…18 nombres…)
order by p.proname;
```

Resultado: **18 filas** (ningún `NULL`) ⇒ **CONFIRMADO, existen los 18**.

| # | Función | Identidad real en debug `(args)` | Ret | Vol | Sec | `proconfig` | md5 (debug) |
|---|---|---|---|---|---|---|---|
| 1 | `fn_check_user_has_access_to_tienda_safe` | `(id_tienda_param bigint)` | void | v | def | `public, pg_catalog` | `e89d1f879e8d695937bd7ac5b627fe17` |
| 2 | `fn_ejecutar_entrega_fisica_v3` | `(bigint,bigint,bigint,numeric,integer,bigint,bigint,bigint,bigint,uuid,text)` | jsonb | v | inv | `public, pg_catalog` | `d63e2416622ae87bc0c6c8eb756d7dbc` |
| 3 | `fn_preview_entrega_fisica_v3` | `(bigint,bigint,bigint,numeric,bigint,bigint)` | jsonb | s | inv | `public, pg_catalog` | `7ee86cca813c63c8f9997869ac878338` |
| 4 | `fn_ingrediente_base_alcanzable` | `(p_id_producto bigint, p_id_almacen bigint DEFAULT NULL, p_alcance text DEFAULT 'almacen', p_cantidad_base numeric DEFAULT NULL)` | jsonb | s | inv | `public, pg_catalog` | `830cd9789176f8957803f22c3225fb81` |
| 5 | `fn_ingredientes_elaborado_base` | `(bigint,numeric,bigint,text)` — `p_alcance DEFAULT 'almacen'` | jsonb | s | inv | `public, pg_catalog` | `4d5ec850307da1c5a405ee421ac15f0c` |
| 6 | `fn_consumir_ingrediente_base_v2` | `(bigint,bigint,numeric,integer,bigint,bigint,uuid,text)` | jsonb | v | inv | `public, pg_catalog` | `964ac5393ff5f798670727fb81490417` |
| 7 | `fn_validar_ingredientes_elaborado_v2` | `(bigint,numeric,bigint)` | jsonb | s | inv | `public, pg_catalog` | `e3cb0a0a1eec7503927f348008b6bbed` |
| 8 | `fn_descontar_ingredientes_elaborado_v2` | `(bigint,numeric,bigint,bigint,integer)` | jsonb | v | inv | `public, pg_catalog` | `23aa50fc721eea0e2f76fcc1429a2120` |
| 9 | `fn_descontar_venta_enrutada_v2` | `(bigint,numeric,bigint,bigint,integer,boolean)` | jsonb | v | def | `public, pg_catalog` | `6dd32ac3aeb6fdd293165ff28855d1bb` |
| 10 | `fn_pedir_item_cuenta_v2` | `(bigint,bigint,numeric,numeric,bigint,bigint,bigint,bigint,numeric,bigint,jsonb,jsonb,text,varchar,varchar,uuid,boolean)` | jsonb | v | def | `public, pg_catalog` | `7454ab1fe1b401974aa96749937f8d77` |
| 11 | `fn_agregar_producto_orden_pendiente_v2` | `(bigint,jsonb,uuid)` | jsonb | v | def | `public, pg_catalog` | `6bb4d98aae8b304d76a43aaf3fa489d1` |
| 12 | `fn_actualizar_cantidad_producto_orden_v2` | `(bigint,numeric,uuid)` | jsonb | v | def | `public, pg_catalog` | `ce47aabef37a17c7f9cfd4cdd9b5d72e` |
| 13 | `fn_registrar_venta_v3` | `(bigint,uuid,jsonb,text,text,text,smallint,bigint)` | jsonb | v | inv | **`(null)`** | `d387e0d08ca86e9cc6fce83d237def76` |
| 14 | `fn_registrar_venta_mesa_v3` | `(bigint,uuid,jsonb,text,text,text,smallint,bigint,bigint)` | jsonb | v | inv | **`(null)`** | `adfdab97f3bd46f4633951fe222b61c3` |
| 15 | `fn_registrar_venta_offline_v4` | `(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint,timestamptz,jsonb)` | jsonb | v | def | `public, pg_catalog` | `ef1dc813ab9c825d32a19a22b7ff7736` |
| 16 | `fn_devolver_ingredientes_elaborado_v2` | `(bigint,numeric,bigint,bigint,integer)` | jsonb | v | def | `public, pg_catalog` | `e351218893d5b35e18f1d32e3e35387d` |
| 17 | `fn_cancelar_item_pedido_v2` | `(bigint,text)` | jsonb | v | def | `public, pg_catalog` | `b0660dbc3a0045e9e6d6efa3d84fe015` |
| 18 | `fn_eliminar_producto_orden_v2` | `(bigint,uuid)` | jsonb | v | def | `public, pg_catalog` | `95dcabfe04a5d12ab182ce38da58158c` |

**Cruce con lo declarado en el repo/plan (donde hay firma documentada):**

| Afirmación | Evidencia | Veredicto |
|---|---|---|
| Firma `fn_descontar_venta_enrutada_v2` = `(bigint,numeric,bigint,bigint,integer,boolean)` (`31:284-291`) | Identidad real idéntica | **CONFIRMADO** |
| Firma `fn_descontar_ingredientes_elaborado_v2` = `(bigint,numeric,bigint,bigint,integer)` (`31:163-169`) | Idéntica (y sin `_v2` la viva, mismo ident) | **CONFIRMADO** |
| Firma `fn_ejecutar_entrega_fisica_v3` = 11 args (`30:124-136`, `34:48`) | Idéntica | **CONFIRMADO** |
| Firma `fn_ingredientes_elaborado_base` con `p_alcance DEFAULT 'almacen'` (plan §Fase 1) | `pg_get_function_arguments` lo confirma | **CONFIRMADO** |
| `fn_consumir_ingrediente_base_v2` / `fn_ingrediente_base_alcanzable` (referenciadas en `37:88,190`) | `to_regprocedure` con esas firmas ≠ NULL | **CONFIRMADO** |
| `fn_devolver_ingredientes_elaborado_v2` = `(bigint,numeric,bigint,bigint,integer)` (`35:125`) | Identidad real idéntica | **CONFIRMADO** |
| `fn_validar_ingredientes_elaborado_v2` = `(bigint,numeric,bigint)` | Idéntica | **CONFIRMADO** |

**Nota (paridad de `search_path`):** `fn_registrar_venta_v3` y `fn_registrar_venta_mesa_v3` se crearon con `proconfig = null` (heredan el del clon vivo `_v2`). Se verificó que **todos** sus callees directos ponen su propio `search_path` (`fn_cantidad_en_base` = `public`; `fn_resolver_origen_venta` = `public`; `fn_pedir_item_cuenta` = `public`; `fn_descontar_venta_enrutada_v2` y `fn_ejecutar_entrega_fisica_v3` = `public, pg_catalog`; `fn_registrar_pago_venta_v2` = `public`) y ninguno usa tablas `app_dat_*` sin calificar ⇒ **no hay 42P01 por herencia en la cadena `_v3`** (recomendación no bloqueante: añadir `SET search_path` explícito).

---

## 2 · Fase 0.5 / C9 — relación rota por `search_path`

**2.1 Guard vivo `check_user_has_access_to_tienda(bigint)`**

| Proyecto | md5 `pg_get_functiondef` | `proconfig` | `len(prosrc)` | Tablas en el cuerpo |
|---|---|---|---|---|
| DEBUG | `f55ff162cbbaaa64c2aa24b8397ef1cc` | `search_path=public, pg_catalog` | 1467 | **calificadas** (`public.app_dat_vendedor`, `public.app_dat_tpv`, `public.app_dat_almacenero`, `public.app_dat_almacen`, `public.app_dat_supervisor`, `public.auditor`, `public.app_dat_gerente`, `public.app_dat_jefe_cocina`, `public.app_dat_cocina`) |
| PRODUCCIÓN | `438dbaec6f0fe94c23d4cb414cc41d89` | `(null)` | 1404 | sin calificar (documentado en `VERIFICACION_IMPLEMENTACION.md`) |

El cuerpo leído en debug **coincide literalmente** con `presentaciones_inventario/46_patch_guard_en_sitio.sql` (califica las 7 fuentes de rol + `SET search_path = public, pg_catalog`, misma firma/mensaje `P0001`, `SECURITY INVOKER`). Además existe `fn_check_user_has_access_to_tienda_safe(bigint)` (archivo `45`, `e89d1f87…`).

⇒ **CONFIRMADO: en debug se aplicaron la opción (a) [guard endurecido en sitio, archivo 46] y la opción (b) [`_safe`, archivo 45].**

**2.2 Los 4 llamadores "rotos" siguen con `search_path` vacío (debug = producción)**

Consulta: `select proname, md5(pg_get_functiondef(oid)), proconfig, prosrc ~ 'check_user_has_access_to_tienda' from pg_proc where proname in (…)` en ambos proyectos.

| Llamador | `proconfig` (debug y prod) | md5 debug | md5 prod | ¿menciona el guard? |
|---|---|---|---|---|
| `fn_ejecutar_entrega_fisica_v2` | `search_path=""` | `9edf415b400a467a1d6627a628fd3376` | `9edf415b…` (igual) | sí |
| `fn_preview_entrega_fisica_v2` | `search_path=""` | `c46c5d977095057a7f33b8f7b360e254` | `c46c5d97…` (igual) | sí |
| `fn_registrar_venta_offline_v2` | `search_path=""` | `230d6307501a4b861a99d7297d856cde` | `230d6307…` (igual) | sí |
| `fn_registrar_venta_offline_v3` | `search_path=""` | `84a83b7e60511f7185d558df8d905971` | `84a83b7e…` (igual) | sí |

⇒ **CONFIRMADO**: los 4 siguen declarando `search_path = ''` en debug **y** en producción. El arreglo no vino de ellos sino del guard.

**2.3 ¿Sigue vivo el 42P01?**

- **DEBUG — NO (CONFIRMADO por ejecución).** Dos pruebas reales:
  - `select public.check_user_has_access_to_tienda(4);` → `ERROR P0001: Acceso denegado: No tienes permisos para acceder a esta tienda` … `line 32 at RAISE`. Es decir, **resolvió las 7 tablas** con `auth.uid()` NULL y llegó al `RAISE` del guard: si el `search_path` vacío siguiera mordiendo, habría muerto antes con `42P01 relation "app_dat_vendedor" does not exist`.
  - `select public.fn_preview_entrega_fisica_v2(3,3,4,1,null,null);` (el llamador con `search_path=''`) → `ERROR P0001 … PL/pgSQL function public.fn_preview_entrega_fisica_v2(...) line 5 at PERFORM` ⇒ **ya no da 42P01**.
- **PRODUCCIÓN — SÍ, evidencia estática (CONFIRMADO como riesgo latente).** Guard con `proconfig = (null)` y tablas sin calificar (`438dbaec…`) + los 4 llamadores con `search_path=''`. **Reproducción directa en producción: `NO VERIFICABLE`** — el MCP de producción devolvió `42501 permission denied for function fn_preview_entrega_fisica_v2` al intentar el `select` de la prueba (no se insistió; una sola tentativa, sin DDL).
- **Censo (debug):** `31` funciones con `search_path=""` (coincide con la medición del plan), de las que `8` mencionan el guard. Las 4 que rompían ya no rompen por ejecución del guard; las otras 4 se auto-corrigen con `set_config` (patrón medido antes).
- **Residuo de pruebas del archivo `47`:** `to_regprocedure('public._probe_guard_safe(bigint)')` = **NULL** ⇒ los tests no dejaron objetos.

---

## 3 · No-regresión — md5 de las funciones vivas (debug ↔ producción ↔ doc)

Consulta: `md5(pg_get_functiondef(oid))` filtrada por nombre, en cada proyecto; comparada con los md5 citados en `VERIFICACION_IMPLEMENTACION.md:17-19`.

| Función viva | md5 DEBUG | md5 PRODUCCIÓN | md5 citado en el doc | Veredicto |
|---|---|---|---|---|
| `fn_registrar_venta` | `371402e5622517270563ef7f73aa8bc3` | `371402e5622517270563ef7f73aa8bc3` | `371402e5…` | **CONFIRMADO intacta y en paridad** |
| `fn_registrar_venta_v2` | `253d9d1636f252fe01108a7c52615180` | `253d9d1636f252fe01108a7c52615180` | `253d9d16…` | **CONFIRMADO intacta y en paridad** |
| `fn_descontar_ingredientes_elaborado` | `47be3a93f8d026eba2f5fbfc31b0cd4a` | `47be3a93f8d026eba2f5fbfc31b0cd4a` | `47be3a93…` | **CONFIRMADO intacta y en paridad** |
| `fn_validar_ingredientes_elaborado` | `c23f85d245c97f89c33e508574fd1aa0` | `c23f85d245c97f89c33e508574fd1aa0` | `c23f85d2…` | **CONFIRMADO intacta y en paridad** |
| `check_user_has_access_to_tienda` | `f55ff162cbbaaa64c2aa24b8397ef1cc` | `438dbaec6f0fe94c23d4cb414cc41d89` | `438dbaec…` (prod) | **DIVERGENCIA INTENCIONAL** (patch `46` aplicado en debug, Fase 0.5(a)); en prod sigue el original |
| `fn_descontar_venta_enrutada` | `81319b55a5f0a0c3ec4db1532ea81009` (`len=8301`) | `d56b117f2c9307a8c6bfaac29ce5e1e8` (`len=6401`) | `d56b117f…` (prod) | **DIVERGENCIA NO ATRIBUIBLE AL PLAN** (ver hallazgo H1) |

Otras vivas relevantes (mismo md5 en ambos proyectos, no las toca ningún archivo 30–35/45/46): `fn_ejecutar_entrega_fisica_v2` `9edf415b…`, `fn_preview_entrega_fisica_v2` `c46c5d97…`, `fn_registrar_venta_offline_v2` `230d6307…`, `fn_registrar_venta_offline_v3` `84a83b7e…`.

**Conclusión del punto:** la afirmación "las funciones vivas mantienen su md5" se cumple para **4/6** de las citadas; las 2 diferencias son (i) el guard por decisión de Fase 0.5(a) y (ii) `fn_descontar_venta_enrutada`, que **no** proviene de los archivos del plan (ningún archivo `30..35/45/46/47` la redefine: `grep 'CREATE OR REPLACE FUNCTION public.fn_descontar_venta_enrutada('` solo aparece en `funcionalidad_cocina/10_enrutamiento_venta_cocina.sql`). Los archivos nuevos **no pisaron** ninguna función viva.

---

## 4 · Semántica de la cadena nueva (leída del cuerpo real en debug)

| # | Claim | Evidencia (consulta + resultado) | Veredicto |
|---|---|---|---|
| 4.1 | `fn_registrar_venta_v3` llama a `fn_descontar_venta_enrutada_v2` y a `fn_ejecutar_entrega_fisica_v3` | `regexp_matches(prosrc,'fn_descontar_venta_enrutada_v2\s*\(')` = **1**; `'fn_ejecutar_entrega_fisica_v3\s*\('` = **1**; llamadas a las vivas `fn_descontar_venta_enrutada(` = **0** y `fn_ejecutar_entrega_fisica_v2(` = **0**. Idéntico en `fn_registrar_venta_mesa_v3`. | **CONFIRMADO** |
| 4.2 | `fn_descontar_venta_enrutada_v2` hace **RAISE** (no RETURN) si queda pendiente | Snapshot del cuerpo: `-- Defensa (C10): si quedara pendiente, abortar en vez de confirmar parcial.` `IF COALESCE((v_resultado->>'equivalente_consumido')::numeric,0) <> p_cantidad THEN RAISE EXCEPTION 'DESCUENTO_SKU_INCOMPLETO: …' USING ERRCODE='P0001', HINT='La transaccion debe revertirse para no dejar descu…'` | **CONFIRMADO** |
| 4.3 | `fn_consumir_ingrediente_base_v2` **no** usa `LEAST` mixto: equivalente base | 2 `LEAST`, operandos extraídos: `LEAST(v_ubic.convertible_usable, v_pendiente)` y `LEAST(v_ubic.saldo, v_pendiente)` — los tres operandos están en **base** (`saldo`/`convertible_usable` de `fn_stock_saldos_presentacion` y el pendiente base), sin `factor_rel` dentro del `LEAST`. Consume con `fn_ejecutar_entrega_fisica_v3` (2 llamadas) en dos pasadas. | **CONFIRMADO** |
| 4.4 | `fn_ingredientes_elaborado_base` usa alcance `'almacen'` por defecto | `pg_get_function_arguments` = `… p_alcance text DEFAULT 'almacen'::text`; la llamada `(5,10,3)` devolvió `"alcance":"almacen"`, `"unidad_cuenta":"unidad_base"`, `"tiene_receta":true`, `"maximo_producible":3314`. Igual en `fn_ingrediente_base_alcanzable` (`'almacen'`). | **CONFIRMADO** |
| 4.5 | `fn_descontar_ingredientes_elaborado_v2` valida con el helper base y descuenta con `fn_consumir_ingrediente_base_v2` | Referencias del cuerpo: `fn_consumir_ingrediente_base_v2`, `fn_validar_ingredientes_elaborado_v2`, `fn_obtener_ingredientes_recursivos`. **Matiz vs texto del plan:** valida vía `fn_validar_ingredientes_elaborado_v2` (que a su vez delega en `fn_ingrediente_base_alcanzable`/base), no invocando `fn_ingredientes_elaborado_base` directamente. | **CONFIRMADO con matiz** |
| 4.6 | `fn_registrar_venta_offline_v4` encadena a la venta nueva | Referencias: `fn_registrar_venta_v3`, `fn_registrar_pago_venta_v2`; 0 llamadas a las vivas. | **CONFIRMADO** |
| 4.7 | `fn_ejecutar_entrega_fisica_v3` / `fn_preview_entrega_fisica_v3` usan el guard nuevo | No referencian `fn_check_user_has_access_to_tienda_safe` en su `prosrc` (usan `fn_preview_entrega_fisica_v3`, `fn_registrar_conversion_presentacion`, `fn_stock_saldos_presentacion`) y tienen `search_path` propio. | **NO VERIFICABLE** si el guard `_safe` se usa realmente en esta ruta (el nombre no aparece en el cuerpo); sin impacto: `search_path` correcto. |
| 4.8 | Conteo exacto de sustituciones del `DO`-block de `34` | `v3` y `mesa_v3`: 1/1/0/0 (enrutada_v2/entrega_v3/enrutada_viva/entrega_v2). | **CONFIRMADO** |

---

## 5 · Migraciones aplicadas y archivos locales correspondientes

Consultas (debug):

```sql
select version, name from supabase_migrations.schema_migrations order by version desc limit 60;
select count(*) as total, max(version) as version_max,
       count(*) filter (where version >= '20261001000000') as desde_oct_2026
from supabase_migrations.schema_migrations;
```

Resultado: **58 migraciones**, `version_max = 20260924174413`, **0 desde octubre 2026**. La más reciente es `20260924…fix_precio_oficial_venta_fn_crear_operacion_desde_orden2`. **Ninguna** migración corresponde a este plan ⇒ los archivos `30–35/45/46` se aplicaron **por Editor/MCP, no como migración**. Por eso la correspondencia se establece por **existencia de objetos**, no por la tabla de migraciones.

| Archivo local | Objetos esperados | ¿Presentes en debug? | Veredicto |
|---|---|---|---|
| `funcionalidad_cocina/30_ingredientes_por_equivalente_base.sql` | `fn_ejecutar_entrega_fisica_v3`, `fn_preview_entrega_fisica_v3`, `fn_ingrediente_base_alcanzable`, `fn_ingredientes_elaborado_base`, `fn_consumir_ingrediente_base_v2` | 5/5 | **APLICADO** |
| `funcionalidad_cocina/31_ingredientes_v2_rutas.sql` | `fn_validar_ingredientes_elaborado_v2`, `fn_descontar_ingredientes_elaborado_v2`, `fn_descontar_venta_enrutada_v2` | 3/3 | **APLICADO** |
| `funcionalidad_cocina/32_tests_ingredientes_v2.sql` | (suite, sin objetos propios) | — | **NO VERIFICABLE** (no deja residuo; su ejecución no es observable) |
| `funcionalidad_cocina/33_ordenes_cocina_cantidad_en_base.sql` | `fn_pedir_item_cuenta_v2`, `fn_agregar_producto_orden_pendiente_v2`, `fn_actualizar_cantidad_producto_orden_v2` | 3/3 | **APLICADO** |
| `funcionalidad_cocina/34_venta_v3_presentaciones.sql` | `fn_registrar_venta_v3`, `fn_registrar_venta_mesa_v3`, `fn_registrar_venta_offline_v4` | 3/3 | **APLICADO** |
| `funcionalidad_cocina/35_devoluciones_presentacion.sql` | `fn_devolver_ingredientes_elaborado_v2`, `fn_cancelar_item_pedido_v2`, `fn_eliminar_producto_orden_v2` | 3/3 | **APLICADO** |
| `funcionalidad_cocina/36_alcance_ingredientes.sql` (citado en plan §Fase 5) | — | **el archivo no existe en el repo** | **INCORRECTO** (Fase 5 implementada dentro de `30` vía `p_alcance`) |
| `funcionalidad_cocina/37_tests_caso_real_debug.sql` | (tests) | — | **NO VERIFICABLE** (sin residuo) |
| `presentaciones_inventario/45_guard_search_path.sql` | `fn_check_user_has_access_to_tienda_safe` | sí (`e89d1f87…`) | **APLICADO** |
| `presentaciones_inventario/46_patch_guard_en_sitio.sql` | guard vivo endurecido | sí (md5 `f55ff162…`, `proconfig` con `SET`) | **APLICADO** (aunque el archivo se rotula "NO APLICADO POR DEFECTO") |
| `presentaciones_inventario/47_tests_guard_search_path.sql` | (tests; crea/dropea `_probe_guard_safe`) | `_probe_guard_safe` = NULL | **NO VERIFICABLE** (su ejecución no es observable); no dejó residuo |

**Archivos locales SIN aplicar en debug: ninguno de los que crean objetos.** Los únicos no verificables son suites de tests (`32`, `37`, `47`) que no persisten nada por diseño. Hallazgo aparte: falta el `36` que el plan §Fase 5 nombra.

---

## 6 · Pruebas funcionales (dentro de transacciones con ROLLBACK)

**Método (el MCP de debug sí acepta escritura):** no se usó `BEGIN…ROLLBACK` multi-sentencia; cada prueba fue **un único bloque `DO $…$`** que escribe, comprueba y termina en `RAISE EXCEPTION`. Al abortar el bloque se revierte la transacción implícita completa ⇒ **imposible dejar datos**. Se hizo foto del ledger antes y después de **todas** las pruebas.

**6.1 Foto previa y posterior (idénticas ⇒ nada persistió)**

```sql
select (select count(*) from public.app_dat_inventario_productos) as filas_ledger,
       (select count(*) from public.app_dat_conversion_presentacion_evento) as filas_conversiones,
       public.fn_stock_producto_almacen(3,3), public.fn_stock_producto_almacen(4,3),
       (select COALESCE(SUM(saldo),0) from public.fn_stock_saldos_presentacion(3,3,NULL,false) where id_presentacion=8),
       (select COALESCE(SUM(saldo),0) from public.fn_stock_saldos_presentacion(4,3,NULL,false) where id_presentacion=7);
```

| Momento | filas ledger | eventos conversión | equivalente Arroz(3) | equivalente Frijoles(4) | kg Arroz (pp 8) | kg Frijoles (pp 7) |
|---|---|---|---|---|---|---|
| Previa (2026-10-23) | 70 | 2 | 1 988 800 | 2 991 000 | 1 988 | 2 989 |
| Posterior a las 4 pruebas | **70** | **2** | **1 988 800** | **2 991 000** | **1 988** | **2 989** |

⇒ **CONFIRMADO: no se escribió nada de forma persistente** (ledger 70→70, eventos 2→2, stock idéntico).

**6.2 Caso 0 del plan (10 Arroz Moro, elaborado 5, tienda 4 / TPV 3, almacén 3)** — con `request.jwt.claims` del vendedor `d99d3333-83a9-4f33-8b53-3dbe744fb0ec`:

| Llamada | Resultado |
|---|---|
| `fn_consumir_ingrediente_base_v2(p_id_producto:=3, p_id_almacen:=3, p_cantidad_base:=6000, p_origen_cambio:=4, p_motivo:='auditoria_test')` | `status=success`, `equivalente_consumido=6000`; `lineas_fisicas`: Unidad 800 (`saldo_propio`) + Unidad 5200 (`saldo_y_conversion`); `conversiones`: 1×`tipo=abrir` **Kilogramo→Unidad 6 → 6000 u** (`id_conversion` 6/8 según corrida) |
| `fn_consumir_ingrediente_base_v2(… p_id_producto:=4, p_cantidad_base:=5000 …)` | `status=success`, `equivalente_consumido=5000`; `lineas_fisicas`: Kilogramo 2 + Kilogramo 3 (`saldo_intacto`); sin conversión |
| Aserciones del bloque | `eq_arroz 1 988 800 → 1 982 800` (−6000 exacto) ✔; `eq_frijoles 2 991 000 → 2 986 000` (−5000 exacto) ✔; `kg_arroz 1988 → 1982` (**no queda en cero → C2 mitigado**) ✔; `kg_frijoles 2989 → 2984` (**no cero**) ✔; `saldo<0` = 0 ✔; `ledger 70 → 76` dentro de la transacción (revertido al `RAISE`) ✔ |

**6.3 End-to-end de la Fase 1:** `fn_descontar_ingredientes_elaborado_v2(5, 10, 3, NULL, 4)` → `status=success`; equivalente Arroz −6000 y Frijoles −5000 exactos; `kg3=1982`, `kg4=2984` (no cero); `ledger 70→76` revertido. **CONFIRMADO.**

**6.4 Insuficiencia real (caso 5 del plan):** `fn_consumir_ingrediente_base_v2(3, 3, 99999999, 4, …)` → devuelve **jsonb** (sin excepción) `status=error`, `error_code=INSUFFICIENT_STOCK_INGREDIENT`; **ledger 70→70** (0 filas nuevas) y `saldo<0 = 0`. **CONFIRMADO: no hay escritura parcial.**

**6.5 Validadores en solo lectura (los que usará la UI):**
- `fn_ingredientes_elaborado_base(5,10,3)` → `status=success`, `alcance=almacen`, `unidad_cuenta=unidad_base`, `tiene_receta=true`, `alcanza=true`, `maximo_producible=3314`, por ingrediente `cantidad_requerida_base` (6000/5000), `presentacion_base_id` (4/5), `saldo_por_presentacion[]` con `Kilogramo factor_rel=1000` y `Unidad factor_rel=1`.
- `fn_validar_ingredientes_elaborado_v2(5,10,3)` → `status=success`, por ingrediente `equivalente_base` (1 988 800 / 2 991 000), `cantidad_requerida` (6000/5000), `cantidad_disponible` en base, `maximo_producible` y `presentacion` ("Unidad"). **CONFIRMADO.**

**6.6 Traza de conversión:** la conversión del consumo se registra como fila de `app_dat_conversion_presentacion` (existe; el jsonb devuelve `id_conversion` 6 y 8 en corridas sucesivas) y **no** en `app_dat_conversion_presentacion_evento`, cuya cuenta quedó 2→2 en la transacción (sus 2 filas existentes son `tipo='empaquetado'`, `id_producto=6`, motivo `gbch`, del 2026-10-22 14:17/14:21, ajenas a esta ruta). ⇒ **CONFIRMADO que hay traza auditada en la tabla maestra; el destino exacto del "evento" del consumo es NO VERIFICABLE/ajeno a este path** (si el kardex debe leer `…_evento` para estas conversiones, requiere decisión aparte).

**6.7 Nota de fixture (dato, no defecto):** los números del §2-bis del plan **ya no coinciden** con debug: Arroz equivalente 2 002 000 → hoy **1 988 800**; Kilogramo Arroz 2000 → **1988**; Frijoles 2 502 500 → **2 991 000**; Kilogramo Frijoles 2500 → **2989**. Las pruebas siguen siendo válidas (mismo caso, saldos distintos); el plan debería recalibrar el anexo.

---

## 7 · Hallazgos y riesgos

| ID | Hallazgo | Evidencia | Impacto / acción |
|---|---|---|---|
| **H1** | **Debug y producción divergen en una función viva por una funcionalidad FEFO que producción no tiene.** Debug: `fn_descontar_venta_enrutada` `81319b55…` (8301 chars, referencia `fn_fefo_saldos_en_ubicacion`); producción: `d56b117f…` (6401 chars). En debug existen además `fn_fefo_saldos_en_ubicacion`, `fn_descontar_fefo_en_ubicacion`, `fn_transfer_asignar_lote_fefo`; **en producción: 0**. Ninguno aparece en el repo local (grep sin coincidencias). | §3, §1 | **No lo introduce el plan 30–35/45/46**, pero rompe la premisa "debug y producción idénticos" usada para extrapolar md5. **Antes de aplicar a producción**: confirmar de dónde salió la familia FEFO en debug y decidir si producción debe recibirla o si debug debe revertirse a `d56b117f…`. |
| **H2** | **C9 sigue vivo en producción** (guard `438dbaec…`, `proconfig` null, tablas sin calificar) con los 4 llamadores en `search_path=''`, incluida la cola offline (`fn_registrar_venta_offline_v2/v3`, usada por `auto_sync_service.dart:4015`). Reproducción directa en prod: **NO VERIFICABLE** (`42501 permission denied`, no se insistió). | §2.1–2.3 | Aplicar `45`+`46` a producción (o sólo `45` y migrar los 4 llamadores); tratarlo como **P0 del camino offline** hasta comprobar en el dispositivo. |
| **H3** | `fn_registrar_venta_v3`/`_mesa_v3` con `proconfig = null`. | §1 | **Mitigado**: todos sus callees fijan `search_path` y no usan tablas sin calificar (verificado). Recomendación: añadir `SET search_path` explícito para no depender de la convención. |
| **H4** | El plan §Fase 5 cita `funcionalidad_cocina/36_alcance_ingredientes.sql`, que **no existe**. | §5, glob del repo | Actualizar el plan/README: la Fase 5 quedó cubierta por `p_alcance` en `30`. |
| **H5** | El evento del consumo **no** se escribe en `app_dat_conversion_presentacion_evento` (queda en la tabla maestra `app_dat_conversion_presentacion`). | §6.6 | Verificar qué tabla consume el kardex antes de dar por buena la "conversión auditada" en UI. |
| **H6** | Los datos del §2-bis del plan están desactualizados en debug. | §6.7 | Recalibrar el anexo del plan con la foto del 2026-10-23. |
| — | No hay regresión en las vivas por los archivos nuevos: ninguna de `30,31,32,33,34,35,45,46,47` redefine una función viva (el único `CREATE OR REPLACE` sobre un nombre vivo del repo es `10…`, ajeno al plan). | §3 | OK |

---

## 8 · Conteo y trazabilidad

| Punto auditado | CONFIRMADO | INCORRECTO | NO VERIFICABLE |
|---|---|---|---|
| 1 · 18 objetos y firmas | 7 (18/18 existen + 6 cruces de firma) | 0 | 0 |
| 2 · Fase 0.5 / C9 (debug) | 3 (guard endurecido, `_safe`, 42P01 ausente) | 0 | 1 (reproducción del 42P01 en producción: `42501`) |
| 3 · No-regresión md5 | 4 (vivas en paridad) | 1 (paridad global rota por `fn_descontar_venta_enrutada`) + 1 divergencia intencional (guard) | 0 |
| 4 · Semántica de la cadena | 6 | 0 | 1 (uso real de `_safe` en la ruta `_v3`) |
| 5 · Migraciones / archivos | 7 archivos aplicados | 1 (`36` inexistente) | 3 (suites `32`, `37`, `47`) |
| 6 · Pruebas funcionales | 5 (caso 0, end-to-end, insuficiencia, validadores, rollback 70→70) | 0 | 1 (destino del evento de auditoría) |
| **Total** | **32** | **3** | **6** |

### Anexo · consultas exactas usadas (resumen)

1. `select p.proname, pg_get_function_identity_arguments(p.oid), pg_get_function_result(p.oid), p.provolatile, p.prosecdef, coalesce(array_to_string(p.proconfig,','),'(null)'), md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and p.proname in (<18 nombres>)` — debug.
2. Ídem restringida a las 6 vivas + guard + 4 llamadores, con `length(p.prosrc)` y `prosrc ~ 'check_user_has_access_to_tienda'` — debug y producción.
3. `select p.prosrc from pg_proc … where proname='check_user_has_access_to_tienda'` — debug (cuerpo completo).
4. `select public.check_user_has_access_to_tienda(4)` y `select public.fn_preview_entrega_fisica_v2(3,3,4,1,null,null)` — debug (reproducción C9).
5. `select md5(pg_get_functiondef(oid)), md5(replace(pg_get_functiondef(oid), chr(13), ''))` para guard y `fn_descontar_venta_enrutada` — ambos proyectos (descarta que la diferencia sea CRLF: las longitudes 8301 vs 6401 la descartan).
6. `select version, name from supabase_migrations.schema_migrations order by version desc limit 60` y `select count(*), max(version), count(*) filter (where version >= '20261001000000') …` — debug.
7. `select (select string_agg(distinct m[1], ', ') from regexp_matches(p.prosrc,'(fn_[a-z0-9_]+)','g') as m) …` y conteos `regexp_matches(prosrc,'fn_x\s*\(')` — debug.
8. `select substring(prosrc, position('RAISE EXCEPTION' in prosrc)-350, 700)` en `fn_descontar_venta_enrutada_v2` y `position('LEAST'…)-250, 600` en `fn_consumir_ingrediente_base_v2` — debug.
9. `select public.fn_ingredientes_elaborado_base(5,10,3), public.fn_validar_ingredientes_elaborado_v2(5,10,3)` — debug.
10. `DO $…$ … RAISE EXCEPTION … $…$` (rollback): caso 0 Arroz 6000 + Frijoles 5000; end-to-end `fn_descontar_ingredientes_elaborado_v2(5,10,3,NULL,4)`; insuficiencia 99 999 999; y conteo de eventos de conversión. En todos, foto del ledger antes/después.
11. `select count(*) filter (where array_to_string(proconfig,',')='search_path=""') …, to_regprocedure('public._probe_guard_safe(bigint)') …` — censo C9 y residuo de pruebas.
12. `select jsonb_agg(to_jsonb(t)) from (select * from public.app_dat_conversion_presentacion_evento limit 2) t` y columnas vía `information_schema.columns` — debug.
13. `select p.proname, p.provolatile, p.proconfig from pg_proc … where proname in ('fn_preview_entrega_fisica_v2',…)` — producción (STABLE, para intentar la prueba) y `select public.fn_preview_entrega_fisica_v2(...)` → `42501`.
14. `select proname like '%fefo%'` — debug (3 funciones) y producción (0 filas).

**Método y límites:** todo lo ejecutado en debug fueron `SELECT`/`DO` con rollback forzado; en producción, sólo `SELECT` de catálogo y **un** intento de ejecución de una función `STABLE`, rechazado por permisos (`42501`) — no se reintentó ni se ejecutó DDL/DML. Las únicas afirmaciones marcadas `NO VERIFICABLE` son las que no pudieron observarse directamente.
