# Auditoría de vigencia · `VERIFICACION_PLAN.md` y `VERIFICACION_PLAN_2.md`

**Auditor:** teammate `docs-auditor` (task-3) · **Fecha de la auditoría:** 2026-10-23
**Objeto:** validez *actual* (no coetánea) de los dos documentos de verificación adversarial del plan de ingredientes.
**Entregable único:** este archivo. No se modificó ningún otro.

## 0 · Alcance y método (lo que sí y lo que no se pudo comprobar)

| Fuente | Uso en esta auditoría |
|---|---|
| `mcp__supabase-debug__execute_sql` (proyecto **debug** `qhprswhhfasrikhawjoz`, rama de prueba) | **Única base consultada** (regla de la tarea). Solo `SELECT`/catálogo y una función `preview` de lectura. |
| Producción `vsieeihstajlrdvpuooh` | **NO consultada** (la tarea lo prohíbe). Todo lo "de producción" queda **NO VERIFICABLE** aquí. |
| Repo (`docs/`, `funcionalidad_cocina/`, `presentaciones_inventario/`) | Lectura directa (grep/read). |
| `docs/PLAN_CONSUMO_INGREDIENTES_ELABORADOS_PRESENTACIONES.md` (412 líneas hoy; las verificaciones citan 373) | Comprobación corrección→plan con `archivo:línea`. |

**Aviso de numeración:** el plan **creció de 373 → 412 líneas** (mtime 2026-10-21 11:52, posterior a ambos verificadores). Por eso **todas** las citas de línea "del plan" que hacen `VERIFICACION_PLAN.md`/`VERIFICACION_PLAN_2.md` (§0.1 línea 26, línea 145, 172, 174, 184, 243-244, 278, 336, 361…) son **direcciones desfasadas**, aunque el **contenido** que señalaban sí fue corregido (se comprueba abajo por texto, no por línea).

---

## 1 · Veredicto global

| Documento | Veredicto | Motivo en una línea |
|---|---|---|
| `docs/_analisis/VERIFICACION_PLAN.md` | **OK con reservas** | Sus hallazgos de mecanismo (H1–H3, S5/S6/S13, F2/F5/F7/F8) son correctos y **sus 10 INCORRECTO están incorporados al plan** (11 de 12 correcciones de §5 aplicadas; 1 parcial). Reserva: sus censos son de **producción** y las citas de línea del plan ya no apuntan a donde dicen. |
| `docs/_analisis/VERIFICACION_PLAN_2.md` | **OK con reservas** | Sus 5 INCORRECTO eran reales y 7 de sus 9 correcciones están en el plan. Reserva grave: **todo el bloque C9 describe un estado pre-parche**; en debug el guard ya está endurecido y el **42P01 ya no se reproduce**. |
| `docs/APLICACION_PRESENTACIONES_INGREDIENTES.md` | **Desfasado (columna debug)** | Su tabla dice que en debug faltan `33` y `35`, pero **los 18 objetos existen ya en debug** y el guard vivo está parcheado. |
| `docs/_analisis/VERIFICACION_IMPLEMENTACION.md` | **OK con reservas** | Correcto para producción (md5 vivos intactos); su "falta `35`→`33` en debug" ya no es cierto. |

---

## 2 · Prioridad 1 · ¿Están aplicadas las 10 correcciones (las 10 INCORRECTO) en el plan actual?

`VERIFICACION_PLAN.md` declara 76 afirmaciones → **62 CONFIRMADO · 10 INCORRECTO · 4 NO VERIFICABLE** (suma correcta) y el plan afirma en `:4` y `:410` "10 de 76 incorrectas, ya aplicadas". Comprobación una a una:

| # | Afirmación INCORRECTO (fuente) | Corrección pedida | Comprobación en el plan actual (2026-10-23) | Veredicto |
|---|---|---|---|---|
| 1 | **S5** — "`TRUNC(equiv/factor,3)` no produce fracciones" | Eliminarla | Plan `:178` (decisión 4): "**Sin fracciones de empaque**: la exactitud entera la da el planificador v2; `TRUNC(equiv/factor, 3)` **no** es garantía de enteros (contraejemplo vivo 1,25/0,75 Cajas)". `:365` lo repite como riesgo. | **APLICADA** |
| 2 | **S6** — `fn_descontar_con_rebalanceo_almacen` es "viva, ya probada" | Añadir que tiene **0 llamadores** | Riesgo `:365`: "`fn_descontar_con_rebalanceo_almacen` (**0 callers**) produce fracciones". **Verificado hoy en debug: 0 callers.** Pero **Fase 1 "Dependencias" `:270` no lo menciona** (solo cita Fase 0.5). | **PARCIAL** |
| 3 | **S13** — caller falso `fn_validar_ingredientes_elaborado ← fn_descontar_con_rebalanceo_almacen` | Borrarlo | Plan `:214`: "**sólo** `fn_descontar_ingredientes_elaborado` (en `fn_descontar_con_rebalanceo_almacen` el nombre está en un **comentario**)". Confirmado en debug: la única ocurrencia con paréntesis es `-- fn_validar_ingredientes_elaborado (...)` dentro de un comentario. | **APLICADA** |
| 4 | **P2** — "160 del ingrediente 239 en otro almacén de la misma tienda" para el 240 | Reescribir como **inter-tienda** | Plan `:149`: "el caso `240` es **inter-tienda** (el rechazo es correcto)"; `:378`; `:294`. El texto falso ya no existe. | **APLICADA** |
| 5 | **P7** — "toda la tienda" = `fn_stock_producto_almacen(ing, NULL)` = toda la plataforma | Recalcular el censo por almacenes de la propia tienda | Plan Fase 5 `:293`: "nunca `fn_stock_producto_almacen(ing, NULL)`; producción **35 elaborados / 7 tiendas**"; `:378`. | **APLICADA** |
| 6 | **P8** — "tienda 25 con 0 producible en 6 elaborados" | Sustituir por los valores medidos | **0 coincidencias** de "tienda 25"/"6 elaborados" en el plan; §10 ya solo da 35/7. | **APLICADA** |
| 7 | **F2** — "los dos `LEAST`" vs "las tres in-place" | Unificar 2 vs 3 y justificar el de `fn_validar…` | Plan `:197` (§4.3): "corregir **los tres** cuerpos: `fn_descontar_ingredientes_elaborado`, `fn_validar_ingredientes_elaborado`, `fn_descontar_venta_enrutada` L118"; §4.4 `:201` añade `GRANT`/`REVOKE`/`search_path` y `RAISE` (**L160-163**, no L159-162). | **APLICADA** |
| 8 | **F5** — "sin fracciones" con la función viva | Igual que S5 + planificador de enteros | `:178` + decisión 13 `:187` (`fn_ejecutar_entrega_fisica_v3` con "planificador en enteros") + caso 4 `:261`. | **APLICADA** |
| 9 | **F7** — "validación sí / descuento no" | Pre-validar o `RAISE` | Decisión 12 `:186` (atomicidad + `RAISE EXCEPTION`); `:248` ("comprobar… **antes** de la primera escritura"); `:252` (`RAISE` si queda pendiente); riesgo `:362`. | **APLICADA** |
| 10 | **F8** — el `RAISE` de `fn_descontar_venta_enrutada` "se conserva" | Explicitar re-lanzarlo | `:252` y `:201` (`RAISE` en la rama SKU, L160-163). | **APLICADA** |

**Resultado: 9 APLICADA · 1 PARCIAL (S6/Fase 1 dependencias).** La afirmación del plan "10 de 76 incorrectas, ya aplicadas" es **sustancialmente cierta**.

### 2-bis · Las 12 correcciones de §5 de `VERIFICACION_PLAN.md`

| §5 | Corrección | Plan actual | Veredicto |
|---|---|---|---|
| 1 | Reescribir la evidencia del 240 en §0.1/§12 | `:149`, `:294`, `:378` | APLICADA |
| 2 | Cambiar el elaborado de prueba de la Fase 5 y recalcular el censo | `:294` "no el 240, inter-tienda"; `:293` | APLICADA |
| 3 | Corregir "tienda 25 … 6 elaborados" | eliminado | APLICADA |
| 4 | Borrar el caller falso | `:214` | APLICADA |
| 5 | Eliminar "y no produce fracciones" | `:178` | APLICADA |
| 6 | Tratar el fallo parcial / commit parcial | `:186`, `:248`, `:252` | APLICADA |
| 7 | Unificar 2 vs 3 in-place y justificar el tercero | `:197`, `:201` | APLICADA |
| 8 | Explicitar re-emisión del `RAISE` | `:252` | APLICADA |
| 9 | Citas `L` menores (L160-163; C5 L83/L135/L117) | `:150` (`→L83/L135/L117`), `:201` (`L160-163`) | APLICADA (la cita `10_enrutamiento…:103-342` ya no se usa) |
| 10 | Ajustar "tienen el 22/24" | `:150` "(m22=false, m24=false)" | APLICADA |
| 11 | Fase 1: añadir los **0 llamadores** de `fn_descontar_con_rebalanceo_almacen` | solo en riesgos `:365`, **no** en dependencias `:270` | **PARCIAL** |
| 12 | Precisar D5 (elaborados excluidos del caché) y el fallback de `_getStockFromCache` | `:165` (D5) y `:166` (D6, ":1132") | APLICADA |

---

## 3 · Prioridad 2 · ¿Siguen siendo ciertos los censos?

| Censo | Fuente que lo afirma | Comprobación 2026-10-23 (debug) | Veredicto |
|---|---|---|---|
| **31** funciones `public` con `search_path=''` | PLAN_2 (C9-7), plan `:154`/`:235` | `count(*) … array_to_string(proconfig,',')='search_path=""'` → **31** | **CONFIRMADO** |
| **8** llaman a `check_user_has_access_to_tienda` | PLAN_2 (C9-7) | **8**, lista exacta: `fn_ejecutar_entrega_fisica_v2`, `fn_preview_entrega_fisica_v2`, `fn_registrar_venta_offline_v2`, `fn_registrar_venta_offline_v3`, `fn_inventario_resumen_por_usuario_almacen3`, `fn_stock_mixto_producto_por_ubicacion`, `get_productos_by_categoria_tpv_search_meta_v3`, `get_productos_by_categoria_tpv_v2` | **CONFIRMADO** |
| **4 rompen** (no restauran `search_path`) | PLAN_2 (C9-7), plan `:154`/`:235` | **4** exactas: `fn_ejecutar_entrega_fisica_v2`, `fn_preview_entrega_fisica_v2`, `fn_registrar_venta_offline_v2`, `fn_registrar_venta_offline_v3`; las otras 4 sí tienen `set_config` | **CONFIRMADO (estructuralmente) — pero ver §5: el síntoma 42P01 ya NO se reproduce en debug** |
| **35 elaborados / 7 tiendas** (intra-tienda) | `VERIFICACION_PLAN` H2/P7, plan `:293`/`:378` | Producción, no consultable; en debug solo hay **1 elaborado / 1 tienda** ⇒ sin contraste posible | **NO VERIFICABLE (fuera de alcance)** |
| **124 elaborados / 14 tiendas** (producción) | `VERIFICACION_PLAN` P3, plan `:377` | Íd. producción | **NO VERIFICABLE** |
| **36 elaborados / 8 tiendas** (métrica §7.4, `p_id_almacen=NULL`) | `VERIFICACION_PLAN` P6 | Íd. producción | **NO VERIFICABLE** |
| **6 combos / 9 filas / 6 productos / 3 tiendas** | `VERIFICACION_PLAN` P5, plan `:379` | Íd. producción | **NO VERIFICABLE** |
| Caso **240** (`fn_validar_ingredientes_elaborado(240,1,12)`) | `VERIFICACION_PLAN` P1/P2/H1 | En debug **no existe el producto 240** (0 filas, 0 receta) | **NO VERIFICABLE** |
| **76 afirmaciones / 10 corregidas** | `VERIFICACION_PLAN` `:9`, plan `:4`/`:410` | Interno: 62+10+4 = 76 ✓; las 10 están en el plan según §2 de este informe | **CONFIRMADO (consistencia interna)** |

**Matiz estructural que los documentos no recogen:** en debug el guard **ya está endurecido** (`proconfig = search_path=public, pg_catalog`, tablas calificadas `public.app_dat_vendedor`, `md5 = f55ff162`), de modo que los 4 "que rompen" **ya no rompen por C9**; `select public.fn_preview_entrega_fisica_v2(3,3,4,1,null,null)` devuelve hoy `P0001 Acceso denegado` (comportamiento correcto del guard sin `auth.uid()`), **no** `42P01`. El censo 31/8/4 sigue siendo válido como **criterio estructural**, pero la frase "hoy 42P01" (plan `:237`) y "42P01 reproducido en debug" (plan `:154`) son **DESFASADAS**.

---

## 4 · Prioridad 3 · `VERIFICACION_PLAN_2.md`: ¿aporta algo aún sin resolver?

Sus correcciones exactas (§6) y su estado en el plan actual:

| Corr. | Contenido | Plan actual | Veredicto |
|---|---|---|---|
| A-1 | `factor_rel` no es columna (la calcula `fn_presentaciones_producto`) | Plan `:129` "Notas de método: `factor_rel` **no es una columna**"; tabla `:97` mantiene la columna como resultado | APLICADA |
| B-1 | Cita de C10 mal atribuida a `INGREDIENTES_SQL.md §11` | §3.1 C10 `:155` corregido (H3/F7/F8 + `prosrc` L364-371). **Pero §12 `:408` sigue diciendo `INGREDIENTES_SQL.md §11; VERIFICACION_PLAN.md hallazgo 3`** | **PARCIAL (la cita falsa sobrevive en §12)** |
| B-2 | Fila Frijoles: no "5000 base por casualidad" sino 2.500.000 base destruidos en silencio | Plan `:56` lo dice ya; `:58` añade las 4 escrituras previas y el `RETURN` sin `RAISE` | APLICADA |
| C9-a | C9 no es latente: la cola offline llama `fn_registrar_venta_offline_v3` | Plan C9 `:154`, Fase 0.5 `:236`, riesgo `:364` | APLICADA |
| C9-b | No son 5 funciones: son **31** (8 guard, 4 rompen) | Plan `:235` con la lista exacta de las 4 y las 3 de "cumplimiento" degradadas | APLICADA |
| C9-c | Criterio de aceptación: **auditar las 31**, no solo las 4 | Plan `:239` solo exige "ninguna función del stack falla con 42P01"; **no** pide auditar las 31 | **PARCIAL** |
| B-3 | C6: `_v2` **sí** abre empaques (vía `fn_ejecutar_entrega_fisica_v2`), lo que falta es el `25` | Plan C6 `:151` con esa redacción y el `RAISE` L265-269 | APLICADA |
| D-1 | `_checkInventoryAvailability` = `:1271-1576` (no 1594) | Plan `:33`, `:305` | APLICADA |
| D-2 | Diálogo `:1642-1750`, título `:1657`, chips `:1700-1724` | Plan `:33`, `:72` | APLICADA |

**Lo que `VERIFICACION_PLAN_2.md` aporta y sigue vivo (no resuelto en los docs):**
1. **C9-c (criterio de auditoría de las 31)** — el plan no obliga a auditar las 27 que no rompen; quedan sin cobertura comprometida.
2. **B-1** — la trazabilidad de C10 en §12 sigue citando `INGREDIENTES_SQL.md §11`, que PLAN_2 demostró que no contiene esa prueba.
3. **El propio C9 ya está obsoleto como descripción del debug**: su premisa "idénticos en debug y producción" (`:53`, `:68`, `:127`) y "42P01 reproducido en debug" (`:70`) **no describen el debug actual**. Sigue siendo válido para producción **solo si** producción no se parcheó (no verificable aquí).
4. **A16/B10 (len 3909 y L118)**: `fn_descontar_ingredientes_elaborado` sigue **len 3909 / md5 `47be3a93` / `LEAST` en L33** ✓. Pero **`fn_descontar_venta_enrutada` ya no es la función medida**: en debug tiene **len 8301, md5 `81319b55`** (≠ `d56b117f` de producción citado) y una **rama nueva de lotes/FEFO** (`-- FEFO por ubicaciones`, `fn_fefo_saldos_en_ubicacion`) que **no existe en el repo**; su primer `LEAST` está en **L125**, no en L118. Todas las citas "L118" (plan `:147`, PLAN_2 B10, VERIFICACION_PLAN S15) describen la versión **antigua**.

---

## 5 · Discrepancias que importan

1. **El debug ya no está en el estado que describen los documentos (la más importante).**
   `VERIFICACION_IMPLEMENTACION.md` (2026-10-22) declara "**nada aplicado todavía**" y el runbook marca en debug `33` ❌ y `35` ❌. Hoy, en debug, **existen los 18 objetos nuevos** (`30, 31, 33, 34, 35, 45` aplicados) y el **guard vivo está parcheado**. Consecuencia práctica: el criterio de Fase 0.5 (`:237`: "hoy 42P01; después success") **ya no se puede usar como prueba**: hoy da `Acceso denegado`, no `42P01`.
2. **El guard vivo de debug no es el que citan los documentos:** `proconfig = ["search_path=public, pg_catalog"]`, tablas `public.` y `md5 f55ff162`, frente al `438dbaec` "idéntico en debug y producción" (PLAN_2 `:53/:69`, plan `:127`). El único archivo del repo que parchea la función viva es `presentaciones_inventario/46_patch_guard_en_sitio.sql:90`, cuyo encabezado dice **"NO APLICADO POR DEFECTO"** (`46:2`) y el runbook lo da como "decisión pendiente": **está aplicado de facto en debug sin que ningún documento lo registre**. Esto rompe la afirmación de no-regresión por md5 de `VERIFICACION_IMPLEMENTACION.md:17-19` para debug.
3. **`fn_descontar_venta_enrutada` divergió:** versión nueva con FEFO/lotes en debug, sin archivo fuente en el repo (`fn_fefo_saldos_en_ubicacion` no aparece en `funcionalidad_cocina/`). Todas las citas `L118`/md5 `d56b117f` quedan **desfasadas**; si producción evolucionó igual, S15/B10/C2 apuntan a líneas equivocadas.
4. **Censos de producción sin re-medición:** 124/14, 35/7, 36/8 y 6/9/6/3 son de 2026-10-21, no se han vuelto a medir y **no son contrastables desde debug** (que solo tiene 1 elaborado / 1 tienda y **no tiene el producto 240**). Si la implementación tocó producción, podrían haber cambiado; hoy son "correctos pero no re-verificados".
5. **Citas de línea del plan obsoletas:** el plan pasó de 373 a 412 líneas; las 12 correcciones de §5 y los hallazgos citan líneas que ya no existen como tales (p. ej. §5-1 "línea 26"/"línea 361"). El contenido está corregido; la trazabilidad por línea, no.
6. **Residuos menores sin cerrar:** (a) §12 `:408` conserva la cita falsa de C10 (`INGREDIENTES_SQL.md §11`, discrepancia B-1 ya demostrada); (b) Fase 1 "Dependencias" `:270` no menciona los 0 llamadores de `fn_descontar_con_rebalanceo_almacen` (corrección 11, parcial); (c) el criterio de Fase 0.5 `:239` no exige auditar las 31 funciones (corrección C9-c, parcial).
7. **Contradicción interna menor del runbook:** `APLICACION_PRESENTACIONES_INGREDIENTES.md:12` dice "NADA aplicado en **ningún** proyecto" mientras su propia tabla `:27-35` marca ✅ en debug para `45`, `30`, `31` y `34`.

## 6 · Conteo de esta auditoría

| Bloque | CONFIRMADO | APLICADA | PARCIAL | DESFASADO / INCORRECTO | NO VERIFICABLE |
|---|---|---|---|---|---|
| 10 INCORRECTO de `VERIFICACION_PLAN.md` incorporadas al plan | — | 9 | 1 | 0 | 0 |
| 12 correcciones §5 de `VERIFICACION_PLAN.md` | — | 11 | 1 | 0 | 0 |
| Censos | 4 (31/8/4 + 76) | — | — | 1 (42P01 "hoy") | 5 (240, 35/7, 124/14, 36/8, 6/9/6/3) |
| Correcciones de `VERIFICACION_PLAN_2.md` | — | 7 | 2 (B-1, C9-c) | 3 (md5 guard, 42P01 debug, L118/FEFO de `fn_descontar_venta_enrutada`) | 0 |
| Coherencia con runbook / implementación | — | — | — | 2 (runbook: columna debug; "nada aplicado") | 0 |

**Conclusión:** los dos documentos **cumplieron su función** y sus correcciones **están aplicadas al plan** (con 2 flecos parciales). Lo que ya **no es cierto** es su fotografía del estado: ambos describen un debug **sin parchear** y un `fn_descontar_venta_enrutada` **sin la rama de lotes**. Antes de seguir usándolos como guía hay que (i) actualizar el runbook y `VERIFICACION_IMPLEMENTACION.md` con el estado real de debug, (ii) cerrar B-1/C9-c/§5-11 en el plan, y (iii) re-medir en producción los censos 124/14 y 35/7.
