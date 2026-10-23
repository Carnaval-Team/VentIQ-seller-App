# Auditoría final · ¿Está implementado el plan de ingredientes/presentaciones?

**Fecha:** 2026-10-23 · **Lead** · **Alcance pedido:** revisar en el **debug** y en el **código** si
`docs/PLAN_CONSUMO_INGREDIENTES_ELABORADOS_PRESENTACIONES.md` está implementado, siguiendo
`docs/_analisis/VERIFICACION_PLAN.md` y `docs/_analisis/VERIFICACION_PLAN_2.md`.

**Proyectos (MCP):** debug `qhprswhhfasrikhawjoz` (`mcp__supabase-debug__*`, clave de escritura de la rama
de prueba) · producción `vsieeihstajlrdvpuooh` (`mcp__supabase__*`, default, **solo SELECT**, intacto).

**Informes de origen (evidencia detallada):**

- `docs/_analisis/AUDITORIA_DB_DEBUG_INGREDIENTES.md` (db-auditor, 32 CONFIRMADO · 3 INCORRECTO · 6 NO VERIFICABLE).
- `docs/_analisis/AUDITORIA_DART_INGREDIENTES.md` (dart-auditor).
- `docs/_analisis/AUDITORIA_VERIFICACIONES_INGREDIENTES.md` (docs-auditor).

---

## 0 · Respuesta corta

| Pregunta | Respuesta |
|---|---|
| ¿El plan está implementado en **debug**? | **Sí, en lo esencial**: Fases 0.5, 1, 2, 3 y 4 aplicadas; la Fase 5 no existe como archivo. El caso real (§8.1) **pasa**. |
| ¿Está implementado en **producción**? | **No.** Solo 7 de los 18 objetos (parte de `30`/`31`) y `30` está en una revisión anterior. C9 sigue vivo. |
| ¿El código de `ventiq_app` está conforme al plan? | **Parcial**: el P0 del cartel y el cableado a `_v3`/`_v4`/`_v2` están hechos; quedan P0(c), todo P1 y todo P2. |
| ¿`VERIFICACION_PLAN.md` y `VERIFICACION_PLAN_2.md` están ok? | **Sí, ok con reservas**: sus correcciones están incorporadas al plan, pero algunas de sus premisas ya están desfasadas para debug y hay 2 flecos sin cerrar. |

---

## 1 · Estado SQL por fase (con evidencia)

| Fase | Objeto | Debug | Producción (medido hoy, SELECT) |
|---|---|---|---|
| 0.5 | `45` guard `_safe` | ✅ existe | ❌ falta |
| 0.5 | `46` patch del guard **vivo** | ⚠️ **aplicado de facto** (md5 `f55ff162…`, `search_path=public, pg_catalog`, tablas calificadas) aunque el encabezado del archivo y el runbook lo dan por «NO APLICADO POR DEFECTO» | ❌ no aplicado (md5 `438dbaec…`, `proconfig` null) |
| 1 | `30` (`_v3` ejecutor/preview, `fn_ingrediente_base_alcanzable`, `fn_ingredientes_elaborado_base`, `fn_consumir_ingrediente_base_v2`) | ✅ 5/5 | ⚠️ 4/5: **falta `fn_ingrediente_base_alcanzable`** ⇒ el `30` de producción es una revisión anterior |
| 1 | `31` (`_v2` de rutas BOM) | ✅ 3/3 | ✅ 3/3 |
| 2 | `33` (cocina `_v2`) | ✅ 3/3 | ❌ falta |
| 3 | `34` (`fn_registrar_venta_v3`, `_mesa_v3`, `offline_v4`) | ✅ 3/3 | ❌ falta |
| 4 | `35` (devoluciones `_v2`) | ✅ 3/3 | ❌ falta |
| 5 | `36_alcance_ingredientes.sql` | ❌ **no existe**; `p_alcance` (DEFAULT `'almacen'`) vive en `30` | — |

**Total debug: 18/18 objetos nuevos existen con la firma declarada.** En producción **faltan 11**: guard
`_safe`, `fn_ingrediente_base_alcanzable`, las 3 de `33`, las 3 de `34` y las 3 de `35`.

### Pruebas funcionales (debug)

- **Caso 0 del plan (§8.1) PASA** (`fn_descontar_ingredientes_elaborado_v2(5,10,3,NULL,4)`): descuenta
  6000/5000 **en base exacta**, abre el `Kilogramo` en vez de vaciarlo (1988→1982 kg y 2989→2984 kg),
  **0 negativos**, conversión auditada (`app_dat_conversion_presentacion`) y **no deja ninguna fila en cero**.
- **Insuficiencia atómica**: con 99999999 devuelve `INSUFFICIENT_STOCK_INGREDIENT` y el ledger queda **70→70** (sin escritura parcial). Mitiga C10.
- **Ledger/eventos/stock pre y post idénticos** ⇒ las pruebas con `RAISE`+rollback no persistieron nada.
- **Validación `_v2` (comprobación del lead, solo lectura)**: `fn_validar_ingredientes_elaborado_v2(5,10,3)`
  = `success`, `alcanza: true`, `maximo_producible: 3314`, con desglose por presentación
  (Arroz: Kilogramo 1988 kg = 1 988 000 base + Unidad 800; Frijoles: Kilogramo 2989 = 2 989 000 + Unidad 2000).
  Coherente con el escalar vivo `fn_stock_producto_almacen(3,3) = 1 988 800` y `(4,3) = 2 991 000`.
- **Sin prueba funcional**: Fase 2 («1 Caja descuenta ×24») y Fase 4 (devolución → neto 0). **NO VERIFICABLE** por ahora.
- **Migraciones**: 58, `max = 20260924`, **0 desde octubre 2026** ⇒ el plan se aplicó por el SQL Editor, **no** como migración.

---

## 2 · Estado de `ventiq_app` (Fase 7)

| Punto | Veredicto | Evidencia |
|---|---|---|
| **P0(a)** `getProductIngredients` en equivalente base | **IMPLEMENTADO ~90 %** | `product_detail_service.dart:811-844` suma Σ(`cantidad_final`×`factor_rel`) vía `fn_stock_producto_almacen_detalle`; expone `cantidad_disponible`, `cantidad_disponible_fisica`, `presentacion_base`, `desglose_presentaciones` (`:719-723`). **No** usa las RPC del plan (`fn_ingredientes_elaborado_base` / `_v2`); el fallback de 1 fila `created_at DESC LIMIT 1` queda solo si no hay cadena/falla la RPC (`:677-688`), etiquetado `alcanceDesconocido` |
| **P0(b)** preorden compara en base | **IMPLEMENTADO ~90 % (online)** | `preorder_screen.dart:1391-1420` y `:2831-2854` comparan base/base con el almacén de `fn_resolver_origen_venta` (`:1659-1695`). Offline es inerte (la receta no se cachea) |
| **P0(c)** no desarmar presentaciones en elaborados | **NO IMPLEMENTADO** | `product_details_screen.dart:3680-3736` sin guarda `!esElaborado/!esServicio` (la guarda sí existe en `:118-122`, `:886-890`) |
| **P0(d)** unidad/presentación y equivalente base en carteles | **PARCIAL ~70 %** | «Unidad base: X» + alcance (`:1826-1831`, `:3008-3012`); `desglose_presentaciones` **nunca se pinta** |
| **P1** `on PedidoException` en `_addToCart` | **NO IMPLEMENTADO** | `product_details_screen.dart:3912-3925` (catch genérico; sin `forzarSinStock`) |
| **P1** `_getStockFromCache` prioriza suma | **PARCIAL ~50 %** | la suma existe pero como respaldo (`preorder_screen.dart:1131-1132`) |
| **P1** venta por acuerdo excluye elaborados | **NO IMPLEMENTADO** | `admin_inventory_service.dart:1229-1238` y `:1367-1379` sin filtro de elaborados |
| **P1** receta en caché offline | **NO IMPLEMENTADO** | `get_detalle_producto`/batch no devuelven `ingredientes` (`sql_offline/01:250-251`) ⇒ la rama de `preorder_screen.dart:1327` es inerte |
| **P2** modo fluido / `cocina_offline_queue` / conteo mixto en apertura | **NO IMPLEMENTADO** | los 3 |
| **Fase 3/4 Dart** | **IMPLEMENTADO** | `order_service.dart:1447-1450` (`fn_registrar_venta_v3`/`_mesa_v3` con fallback a las vivas); `auto_sync_service.dart:4016-4051` (`offline_v4`→`offline_v3`→viva); `mesa_cuenta_service.dart:285-286`, `:377-389`; `order_service.dart:2960-2970` (`fn_eliminar_producto_orden_v2`) |

**Calidad:** `mcp__dart__analyze_files` sobre los 7 archivos clave ⇒ **«No errors»**, sin errores nuevos
(el único error del proyecto sigue siendo el preexistente `package_image_picker_web.dart:13` con `dart:js_util`).

---

## 3 · ¿Están ok los dos documentos de verificación?

| Documento | Veredicto | Detalle |
|---|---|---|
| `VERIFICACION_PLAN.md` | **OK con reservas** | Sus **10 INCORRECTO están incorporados** al plan (9 aplicadas, 1 parcial: S6/0 llamadores solo en riesgos) y 11/12 de sus correcciones de §5. Flecos: §5-11 y S6 |
| `VERIFICACION_PLAN_2.md` | **OK con reservas** | 7/9 correcciones aplicadas; **B-1 sigue vivo** (el plan §12 todavía cita `INGREDIENTES_SQL.md §11`, cita falsa) y **C9-c** (el criterio de Fase 0.5 no obliga a auditar las 31 funciones) |
| `VERIFICACION_IMPLEMENTACION.md` | **OK para producción, punto 0 desfasado** | «nada aplicado» ya no es cierto: producción tiene 7 objetos de `30`/`31` |
| `APLICACION_PRESENTACIONES_INGREDIENTES.md` | **DESFASADO en la columna debug** | dice que `33`/`35` faltan en debug (ya están) y su `:12` («NADA aplicado en ningún proyecto») contradice su propia tabla `:27-35` |

Además, las **citas de línea «del plan»** en ambos verificadores apuntan a un plan de 373 líneas; el actual
tiene **412** ⇒ son direcciones obsoletas (el contenido sí quedó corregido).

---

## 4 · Divergencias y riesgos que hay que mirar

1. **`fn_descontar_venta_enrutada` (función VIVA) difiere debug↔producción**: debug `81319b55…` (8301 chars,
   2 `LEAST`, rama FEFO/lotes con `fn_fefo_saldos_en_ubicacion`, `LEAST` en L125) vs producción/repo
   `d56b117f…` (6401 chars, 1 `LEAST`, L118). **Debug tiene una familia FEFO/lotes (3 funciones `%fefo%`,
   6 `%lote%`) que producción no tiene y que no está en el repo.** No la introdujo este plan, pero:
   las copias `_v2`/`_v3` se hicieron de la versión **sin FEFO**, así que la cadena nueva **no hace FEFO**.
   Decidir esto antes de promover a producción.
2. **C9 sigue vivo en producción**: guard en `438dbaec…` (sin `search_path`), y `auto_sync_service.dart` llama
   `fn_registrar_venta_offline_v3` con fallbacks que **no reconocen un 42P01** ⇒ es un **P0 de offline** real.
   En debug está resuelto por el patch `46`.
3. **Producción tiene un `30` anterior** (sin `fn_ingrediente_base_alcanzable`) ⇒ no basta con «aplicar lo que falta»:
   hay que **reaplicar `30` en su versión actual** y decidir `46`.
4. **Fase 5 sin archivo propio** (`36` no existe): el alcance `'tienda'` está soportado en `30` pero nadie lo usa todavía.
5. **P0(c)**: el desarme puede dispararse sobre un elaborado con presentación (`_buildInventoryData` no filtra por
   `esElaborado`; `_presentacionElegidaId` cae a la presentación del inventario).
6. **Paridad archivo↔base NO VERIFICADA** byte a byte ni en debug ni en producción (los md5 vivos sí están comprobados).
7. **Censos de producción** del plan (124/14 elaborados, 35/7 intra-tienda, caso 240, 6/9/6/3) **no re-medidos**:
   desde debug no son contrastables (1 elaborado, 1 tienda, el producto 240 no existe).

---

## 5 · Para cerrar (orden sugerido)

**Debug (ramas de prueba)** — ya está casi cerrado:
1. Correr y registrar las pruebas que faltan: Fase 2 («1 Caja de elaborado → receta ×24») y Fase 4 (cancelar 1 Caja → neto 0).
2. Decidir y **documentar** el patch `46` (está aplicado sin registro; rompe la no-regresión por md5 del guard).

**Producción** — nada hasta que debug cierre:
3. `45` → (`46`?) → reaplicar `30` (versión actual) → `31` (reaplicar) → `35` → `33` → `34`; luego `32`/`47`.
4. Resolver antes la divergencia FEFO/lotes (`fn_descontar_venta_enrutada`).

**`ventiq_app`** — pendientes del plan (los cambios van aquí):
5. P0(c) guarda de elaborados/servicios en el desarme; P1 completo (PedidoException, `_getStockFromCache`,
   venta por acuerdo, receta offline); P2 (modo fluido, cola de cocina, conteo mixto en apertura).
6. Analizar el P0(d) (`desglose_presentaciones` sin pintar).

**Gate de release (del plan):** no publicar el APK del P0 si `30`/`31`/`34` no están aplicados **en el proyecto
al que apunta ese build**.
