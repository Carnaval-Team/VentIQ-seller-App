# 08 — Costos adicionales: contrato real en `newa` y veredicto para la fase 6

Verificado contra `newa` = `qhprswhhfasrikhawjoz` (MCP `supabase-debug`) y `Main` = `vsieeihstajlrdvpuooh` (MCP `supabase`) el
2026-11-20, solo lectura.

**Resumen:** el andamiaje ya **está aplicado en `newa`** (2 tablas + trigger + `v2` con `costos[]`), pero está **vacío de datos y
sin uso real**: `app_cont_tipo_costo` tiene **0 filas**, y por tanto las 2 tablas nuevas también **0 filas**. En `Main` no existe
nada. La fase 6 construye de cero lo que ya está en dev y no cubre lo que falta.

## 1. Contrato real de las tablas nuevas en `newa`

**`app_dat_producto_costo`** (7 columnas): `id bigint PK identity`, `id_producto bigint NOT NULL`, `id_tipo_costo bigint NOT NULL`,
`monto_usd numeric NOT NULL DEFAULT 0`, `monto_promedio_usd numeric NOT NULL DEFAULT 0`, `activo bool NOT NULL DEFAULT true`,
`created_at timestamptz NOT NULL DEFAULT now()`. Constraints: `PK (id)`, `UNIQUE (id_producto, id_tipo_costo)`, `FK id_producto →
app_dat_producto(id) ON DELETE CASCADE`, `FK id_tipo_costo → app_cont_tipo_costo(id)` sin cascade. RLS con **4 políticas**. **0
filas.**

**`app_dat_recepcion_producto_costo`** (6 columnas): `id bigint PK`, `id_recepcion_producto bigint NOT NULL`, `id_tipo_costo bigint
NOT NULL`, `monto_usd numeric NOT NULL`, `monto_promedio_anterior numeric NOT NULL`, `created_at timestamptz`. FKs `→
app_dat_recepcion_productos(id) ON DELETE CASCADE` y `→ app_cont_tipo_costo(id)`. RLS con 4 políticas. **0 filas.**

**Quién las escribe:** un solo escritor en toda la BD. El barrido de `pg_proc.prosrc` devuelve **una única** función que menciona
cualquiera de las dos: `fn_actualizar_precio_promedio_recepcion_v2` (`sql_updates/costos_adicionales_producto.sql:346-436`). En
cliente, `CostosAdicionalesService` (`costos_adicionales_service.dart:57-179`). `fn_registrar_recepcion_con_inventario` y
`fn_insertar_recepcion_completa` **no** las tocan.

**Diferencias script ↔ aplicado:** la DDL es **idéntica** (columnas, defaults, nullabilidad, FKs, UNIQUE, RLS). Solo difiere el
estado: el `DO $$ … DROP EXPRESSION` (`:177-193`) es no-op porque `costo_real` ya es `NEVER`; el trigger está **idéntico** salvo
`\r\n`; el script asume el catálogo poblado y no lo está. *No comprobé* el índice `idx_recepcion_producto_costo_rp` (`:97-98`).

## 2. `app_cont_tipo_costo` — el nomenclador está VACÍO

Columnas: `id bigint`, `denominacion varchar NOT NULL`, `descripcion text`, `naturaleza smallint NOT NULL`, `afecta_margen bool NOT
NULL DEFAULT true`, `created_at timestamptz`. **Sin `id_tienda`** → **global**. **Sin moneda**: el USD es convención del código, no
constraint. No hay `afecta_inventario`; lo más cercano es **`afecta_margen`**, que es margen comercial, no valoración de inventario.

**Filas: 0.** No existe "importadora", ni "flete", ni "aduana", ni nada. `naturaleza` apunta a `app_nom_naturaleza_costo`, con **2
filas**: `1 = Gasto`, `2 = Ingreso` — dos valores que tampoco distinguen un flete de un arancel. Consecuencia: el módulo es **inerte
por datos**; la UI pide costos activos, recibe vacío y nunca envía `costos[]`.

## 3. Fórmula real de `costo_real` en `newa`

`pg_get_functiondef('trg_fn_recepcion_productos_costo_real')`, idéntica a `costos_adicionales_producto.sql:195-208`:

```sql
IF NEW.costo_real IS NULL THEN
  NEW.costo_real :=
    (COALESCE(NEW.precio_unitario, 0) - COALESCE(NEW.descuento_monto, 0))
    - ((COALESCE(NEW.precio_referencia, 0) * COALESCE(NEW.descuento_porcentaje, 0)) / 100);
END IF;
```

Trigger `BEFORE INSERT OR UPDATE OF precio_unitario, descuento_monto, descuento_porcentaje, precio_referencia, costo_real`,
`tgenabled = 'O'`.

- **No divide por cantidad:** es costo **por presentación recibida**; el unitario base sale al ponderar dividiendo por `factor_rel`.
- **No suma adicionales:** solo costo puro de factura; los adicionales los pone `v2` después, `costo_real = puro + adicionales × factor_rel` (`:433-435`).
- **No trata recepción parcial:** no existe el concepto "por asignar" en el esquema.
- Es **NULL-safe** en `precio_referencia` y `descuento_porcentaje`, y **solo escribe si viene NULL** (un valor explícito del llamador manda).

Empírico: 12 de 12 líneas muestreadas cuadran exacto. De 21 líneas, **4 con `costo_real` NULL** (ids 2, 13, 14, 15): anteriores al
trigger (`DROP EXPRESSION` no reescribe filas); las 17 posteriores tienen valor.

**Contraste con `Main`:** allí sigue `GENERATED ALWAYS` con `((precio_unitario - COALESCE(descuento_monto,0)) - ((precio_referencia
* descuento_porcentaje)/100))` — **sin** `COALESCE` sobre `precio_referencia`. Por eso Main tiene **30.036 de 30.331 líneas con
`costo_real` NULL**, exactamente las que tienen `precio_referencia` NULL. El trigger de `newa` corrige eso; Main **no tiene** el
trigger.

## 4. `precio_promedio`: la viva es `_v2`, y está bien

- **Ninguna función de BD llama a `v2` ni a `v3`** (barrido de `prosrc` vacío): las llama el cliente. **Flutter llama a `v2`** (`inventory_service.dart:4171-4174`, comentario en `:4162-4170`). `v3` **existe en ambos entornos y no tiene llamadores**: código muerto. `v2` en `newa` es `SECURITY DEFINER`; en `Main` **no** (versión previa, sin `costos[]`).

**Fórmula real de `v2`** (`:498-531`), agrupando líneas por producto:

```
cant_base     = cantidad × factor_rel
costo_base_ln = precio_unitario / factor_rel + Σ monto_usd    -- aterrizado por u. base
saldo_previo  = GREATEST(Σ fn_stock_saldos_presentacion(...) − Σ cant_base, 0)
nuevo = (precio_promedio_previo × saldo_previo + Σ(cant_base × costo_base_ln))
        / (saldo_previo + Σ cant_base)
```

Si `precio_promedio_previo <= 0` o `saldo_previo <= 0` → `nuevo = Σimporte / Σcantidad`. Escribe **solo la presentación base** y
propaga `costo_base × factor_rel` al resto (`:524-531`).

**El defecto documentado (`02-contabilidad.md:156-157`) NO existe en la viva.** Ese defecto es de `v3`, que toma `cantidad_anterior`
de `app_dat_inventario_productos.cantidad_inicial WHERE id_recepcion = p_id_operacion` — la cantidad de **esa misma recepción**, con
lo que degenera en media simple. `v2` usa **stock previo real**, que es justo la corrección que pide `:157`. La fase 6 debe
**verificarlo y cerrarlo**, no arreglarlo.

Matiz: `v2` resta la cantidad recibida del stock actual, lo que asume que el inventario **ya fue contabilizado**. El orden real lo
respeta (`completeOperation` contabiliza y luego llama, `inventory_service.dart:3443-3446`); si se llamara antes, el stock previo
saldría inflado.

## 5. `asignacion_costos` / `centro_costo` / `historial` / `log`: otro módulo

Las cuatro son **prorrateo contable por centro de costo**, no costo unitario. `app_cont_centro_costo` (`id, id_padre, id_tienda,
denominacion, descripcion, codigo, sku_codigo, created_at`) es un árbol de centros por tienda; `app_cont_asignacion_costos` (`id,
id_tipo_costo, id_producto, id_tienda, id_centro_costo, porcentaje_asignacion numeric, metodo_asignacion smallint`) reparte un
concepto **en %** entre centros; historial y log auditan esa asignación (`id_asignacion*`, `cambios text`, `realizado_por uuid`).
Todas tienen `id_tienda` y `id_centro_costo`; **ninguna tiene `id_recepcion` ni `id_recepcion_producto`**, así que **no pueden**
guardar el valor aplicado en una línea de recepción → **no sirven para este plan** (ya lo dice `PLAN_COSTOS_ADICIONALES.md:28`). **0
filas en las cuatro.**

Sí se reutiliza `app_nom_naturaleza_costo` (2 filas) como dominio de `naturaleza`, y `app_dat_precio_costo` (46 filas;
`precio_costo_usd`, `precio_costo_anterior`, `origen`) como historial de costo, alimentado por `trg_registrar_precio_costo` sobre
`precio_promedio`.

## 6. Cómo captura hoy la UI y qué se pierde

El flujo está **completo en código**, pero muerto por falta de catálogo. `product_quantity_dialog.dart:106-142` llama
`listarActivosPorProducto`, sugiere `monto_promedio_usd` si `> 0` (si no `monto_usd`) y marca **`aplica: true` por defecto** con
monto editable; `_costosPayload()` (`:144-150`) arma `[{id_tipo_costo, monto_usd}]` de los tildados y se inyecta en el jsonb de la
línea (`:576` simple, `:665` mixto — en mixto **solo la primera línea** lo recibe, `:648`, para no duplicar descuentos);
`presentation_converter.dart:78,130` copia `baseProductData` con `Map.from`, así que `costos` sobrevive la conversión a presentación
base. `insertInventoryReception` (`inventory_service.dart:1361-1375`) llama `fn_registrar_recepcion_con_inventario` — que **ignora**
`costos` — y **después**, fuera de la transacción, llama `persistirCostosRecepcion` (`:1394-1399`). Al completar,
`completeOperation` relee líneas, adjunta los costos ya persistidos por `id_recepcion_producto`
(`costos_adicionales_service.dart:187-205`) y los manda a `v2` (`inventory_service.dart:4133-4174`).

**Lo que se pierde — el `catch { print }`** (`inventory_service.dart:1400-1402`): `catch (e) { print('⚠️ No se pudieron persistir
costos adicionales: $e'); }`. Si falla, la recepción queda registrada **sin auditoría de costos**, sin aviso, y la operación se
reporta exitosa. Es lo que la fase 6 manda eliminar (`PLAN.md:651`). Agravante: el persistido va **fuera** de la transacción de la
RPC → hay una ventana en la que la línea existe con `costo_real` sin adicionales. Y con el catálogo en 0 filas, `_costosPayload()`
devuelve `[]`, no se envía `costos` y **ese camino nunca corre**.

## 7. Veredicto operativo para la fase 6

**Sobra por ya construido en `newa`** (pasa a "promover a Main", no a build): crear las 2 tablas con RLS; `DROP EXPRESSION` de
`costo_real` + backfill `= precio_unitario − descuentos`; crear el trigger y su fórmula; el rollback que restaura la expresión;
"verificar cuál función está viva" (`PLAN.md:654-656`) — resuelto: `v2` con stock previo, solo queda documentarlo y **borrar `v3`**.

**Se reutiliza tal cual:** las 2 tablas con su UNIQUE/FK/RLS; el trigger; `v2` con `costos[]`; el camino UI
(`product_quantity_dialog` + `CostosAdicionalesService` + `product_costos_adicionales_section.dart`); `app_dat_precio_costo`.

**Se extiende:** `app_dat_recepcion_producto_costo` necesita `origen_pago` (no existe), y el cargo de importadora (`pct`, `base`
congelada, `reembolso`, `id_compra`, `moneda`) no cabe en `monto_usd` + `id_tipo_costo`.

**Se crea de verdad:** sembrado del nomenclador; reparto del costo global **por valor** (hoy es "por cantidad" implícito vía
`monto_usd` por producto, `02-contabilidad.md:148`); recepción parcial con "por asignar" (`02-contabilidad.md:159-164` — no existe
columna ni tabla); reversión al cancelar; regla de un solo origen.

**Diff `newa` vs `Main`:** Main no tiene las 2 tablas, tiene `costo_real` `GENERATED ALWAYS` con 30.036 NULLs por
`precio_referencia` NULL, no tiene el trigger, `v2` es la versión vieja sin `costos[]`, y el nomenclador también está en 0 filas. El
script sirve para Main **pero necesita backfill explícito de esos 30.036 NULLs**, que el `DO $$` no hace (solo condiciona el `DROP
EXPRESSION`).

### Los 3 cambios a la fase 6

1. **Sustituir los "prerequisitos ausentes" (`PLAN.md:627-633`) por "promover `newa` → `Main`".** No se crea nada desde cero ni se hace `DROP EXPRESSION` a ciegas: en `newa` ya está. En `Main` hace falta además el **backfill de 30.036 `costo_real` NULL** (causados por `precio_referencia` NULL), que el script no contempla.
2. **Sembrar `app_cont_tipo_costo` antes que cualquier otra cosa.** Está en 0 filas en ambos entornos y no tiene moneda ni `afecta_inventario`; sin filas, el módulo entero (UI, `costos[]`, `v2`, promedios) no ejecuta ni una vez. Es prerrequisito de **datos**, no de esquema.
3. **Mover el foco de "crear el andamiaje" a "modelar el reparto que falta":** añadir `origen_pago` (y el cargo de importadora con `pct`/`base`/`reembolso`) a `app_dat_recepcion_producto_costo`, e implementar reparto **por valor** y el remanente "por asignar" de la recepción parcial. Nada de eso existe: hoy solo hay un monto fijo por unidad base y por producto.

**HECHO VERIFICADO:** columnas, tipos, defaults, nullabilidad, FKs, UNIQUE, PK y RLS de las 2 tablas; conteos (tipos_costo 0,
naturalezas 2, producto_costo 0, rp_costo 0, asignacion 0, centro 0, historial 0, log 0, precio_costo 46, recepción 21 en newa /
30.331 en Main); `costo_real` `NEVER` en newa y `ALWAYS` con su expresión en Main; `pg_get_functiondef` del trigger y de `v2`/`v3`;
lista de triggers y `tgenabled`; ausencia de llamadores en `prosrc`; los 30.036 NULLs coincidentes con `precio_referencia` NULL en
Main; las 12 líneas de newa que cuadran con la fórmula.

**SUPOSICIÓN / no verificado:** que exista el índice `idx_recepcion_producto_costo_rp` en newa; la semántica de `naturaleza` en
`app_cont_gastos` (fuera de alcance); el efecto en reportes de `costo_real` NULL en Main más allá de
`fn_reporte_ventas_con_proveedor_por_turno` (no re-ejecuté reportes).
