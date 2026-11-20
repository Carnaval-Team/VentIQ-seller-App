# Deriva newa (dev) vs Main (prod) vs repo

**Auditoría de entornos** · 2026-11-20 · `newa = qhprswhhfasrikhawjoz` (MCP `supabase-debug`) vs
`Main = vsieeihstajlrdvpuooh` (MCP `supabase`). Solo lectura. Repo: `ventiq_admin_app/lib/sql/` y
`sql_updates/`. Complementa `00-auditoria-programador.md`, que se hizo **solo contra Main**.

**Veredicto:** `newa` está por delante de Main en el módulo de costos y en el del fondo, y por detrás en
datos. Las fases 2 y 6 del plan ya están hechas en newa y no en Main.

## 1. Matriz

Leyenda: **S** = existe · **N** = no existe · entre paréntesis, filas reales.

### 1.1 Las 15 `fdi_*`

| Objeto | newa | Main | repo | Implicación |
|---|---|---|---|---|
| `fdi_dat_concepto` | S (4) | S (0) | `fondo_inversion_schema.sql:16` | igual; solo newa tiene nomenclador |
| `fdi_dat_config` | S (0) | S (0) | `:75` | igual |
| `fdi_dat_cuenta` | S (6) | S (0) | `:45` | igual estructura; newa con 6 cuentas |
| `fdi_dat_saldo` | S (10) | S (0) | `:100` | igual; **Main vacío** |
| `fdi_dat_movimiento` | S (16) | S (0) | `:117` | igual columnas; **CHECK distinto** (§1.5) |
| `fdi_dat_liquidacion` | S (3) | S (0) | `:152` | igual |
| `fdi_dat_liquidacion_detalle` | S (6) | S (0) | `:182` | igual |
| `fdi_dat_liquidacion_orden` | S (26) | S (0) | `:200` | igual |
| `fdi_dat_transferencia` | S (0) | S (0) | `:218` | igual |
| `fdi_dat_inversion` | S (0) | S (0) | `:254` | igual; nadie la usó nunca |
| `fdi_dat_inversion_fuente` | S (0) | S (0) | `:284` | igual |
| `fdi_dat_inversion_recepcion` | S (0) | S (0) | `:322` | igual; es el vínculo que fase 5 reemplaza |
| `fdi_hist_estado_inversion` | S (0) | S (0) | `:303` | igual |
| `fdi_dat_inversor` | S (3) | S (0) | `fondo_inversion_inversores.sql:3` | igual |
| `fdi_dat_inversor_reparto` | S (12) | S (0) | `fondo_inversion_inversores.sql:22` | igual |

15/15 en ambos entornos → el punto (a) de `verify/00_linea_base.sql` pasa en los dos.
**El módulo FDI está en uso solo en newa** (3 liquidaciones + 16 movimientos + 10 saldos); en Main nunca
se usó. Consecuencia: producción arranca con el libro en cero, no hay histórico que migrar.

### 1.2 Tablas operativas que toca el plan

| Objeto | newa | Main | repo | Implicación |
|---|---|---|---|---|
| `app_dat_recepcion_productos` | S (21) | S (30.331) | `VentiQ.sql:456` | recepción viva en producción |
| `app_dat_operacion_recepcion` | S (7) | S (14.531) | `VentiQ.sql` | 2025-08-29 → 2026-11-20, uso diario |
| `app_dat_operaciones` | S (58) | S (163.145) | — | núcleo operativo |
| `app_dat_precio_costo` | S (46) | S (9.757) | **sin DDL** (uso: `fondo_inversion_schema.sql:574`) | ya existe; el plan no la toca |
| `%compra%` / `cmp_%` | **N** | **N** | **N** | fase 3 crea de cero, sin colisión |

### 1.3 Módulo de costos (`sql_updates/costos_adicionales_producto.sql`)

| Objeto | newa | Main | repo | Implicación |
|---|---|---|---|---|
| `app_dat_producto_costo` | **S** (0) | **N** | `costos_adicionales_producto.sql:17` | script **aplicado en newa, no en Main** |
| `app_dat_recepcion_producto_costo` | **S** (0) | **N** | `:87` | ídem |
| `app_cont_tipo_costo` | S (0) | S (0) | `limpiar_modulo_costos.sql:51` | ver §4: **nomenclador vacío en ambos** |
| `app_nom_naturaleza_costo` | S (2) | S (2) | `limpiar_modulo_costos.sql:54` | igual (Gasto=1, Ingreso=2) |
| `app_cont_centro_costo` | S (0) | S (110) | — | Main con 110 centros; newa vacío |
| `app_cont_asignacion_costos` | S (0) | S (0) | — | igual estructura, sin uso |
| `app_cont_historial_asignacion_costos` | S (0) | S (0) | — | igual |
| `app_cont_log_costos` | S (0) | S (0) | — | igual |

Columnas de `app_dat_producto_costo` / `_recepcion_producto_costo` en newa = **exactamente** las del
script (`monto_usd`, `monto_promedio_usd`, `activo` / `monto_usd`, `monto_promedio_anterior`). Fase 6
puede leer el esquema real, no el del script a ciegas.

### 1.4 Facturas y saldos de terceros

| Objeto | newa | Main | repo | Implicación |
|---|---|---|---|---|
| `imp_dat_factura` | S (0) | S (26) | `importadora_facturas_schema.sql` | mismo esquema |
| `prv_dat_factura` | S (0) | S (48) | `pago_proveedores_schema.sql` | mismo esquema |
| `imp_dat_saldo` / `prv_dat_saldo` / `dep_dat_saldo` | S (0) | S (3 / 5 / 2) | `depositos_bancarios_schema.sql` | saldos vivos solo en Main |

`imp_dat_factura` es **idéntica** en ambos: `id, idtienda, numero_factura, valor numeric(14,2),
fecha_procesamiento date, foto_url, id_estado, created_at`. **No tiene `moneda` ni `id_compra`** en
ninguno de los dos → X8 y la vinculación documental siguen siendo ALTER puro en fase 6.

### 1.5 Columnas que importan

| Columna | newa | Main | Implicación |
|---|---|---|---|
| `app_dat_recepcion_productos.costo_real` | `numeric`, `is_generated = NEVER` | `numeric`, **`GENERATED ALWAYS`**: `(precio_unitario − COALESCE(descuento_monto,0)) − (precio_referencia × descuento_porcentaje / 100)` | fase 6: en newa **ya está hecho**; en Main hay que aplicar el script |
| trigger en `app_dat_recepcion_productos` | `trg_recepcion_productos_costo_real` (BEFORE INSERT OR UPDATE OF precio_unitario, descuento_monto, descuento_porcentaje, precio_referencia, costo_real) → `trg_fn_recepcion_productos_costo_real()`, que **solo rellena si es NULL** | **no hay trigger** | deja pasar un costo aterrizado escrito por RPC: es lo que fase 6 necesita |
| `app_dat_operacion_recepcion.moneda_factura` | `char(3)` DEFAULT `'USD'` | idéntica | igual |
| `...monto_factura` / `...tasa_cambio_aplicada` / `...fecha_tasa_aplicada` | `numeric` / `numeric` / `timestamp` | idénticas | igual: no hay columna que crear |
| `...origen` | **no** | **no** | fase 5 lo añade en ambos |
| `imp_dat_factura.moneda` / `.id_compra` | **no** | **no** | ALTER en fase 6, ambos entornos |
| `fdi_dat_movimiento.tipo` CHECK | **9** valores: incluye `'gasto'` | **8** valores, **sin `'gasto'`** | newa ya aplicó `fondo_inversion_gasto.sql` |
| `fdi_dat_movimiento.idempotency_key` | **no** | **no** | la clave vive en `fdi_dat_inversion`, `fdi_dat_liquidacion`, `fdi_dat_transferencia`; **falta en el ledger** → fase 2 intacta |
| `fdi_dat_movimiento.id_compra` / `.tasa` | **no** / **no** | **no** / **no** | fase 4 intacta |
| `fdi_dat_saldo.saldo` | `numeric` sin typmod (escala libre) | `numeric` sin typmod | **iguales**: la escala no existe en ninguno |
| `app_dat_operaciones` fecha | **solo `created_at`** (+ `contabilizada_at`) | idéntica | no hay `fecha_operacion`; fase 5 la crea en ambos |

### 1.6 Funciones (nombre + pronargs)

| Función | newa | Main | repo | Implicación |
|---|---|---|---|---|
| `fn_fdi_gasto` | **8 args** | **ausente** | `fondo_inversion_gasto.sql:22` | fase 2 "crear si falta" = **crear en Main**; newa ya la tiene |
| `fn_fdi_transferir` | 13 | 13, idéntica | `fondo_inversion_schema.sql` | igual → la v2 sigue siendo necesaria |
| `fn_fdi_crear_inversion` | 7 | 7 | — | igual |
| `fn_fdi_vincular_recepcion` | 6 | 6 | — | igual (R3 abierto en ambos) |
| `fn_fdi_recalcular_inversion` | 1 | 1 | — | igual |
| `fn_fdi_saldos` | 1 | 1 | — | igual |
| `fn_fdi_ingreso_manual` | 8 | 8 | — | igual |
| `fn_fdi_ajuste` | 7 | 7 | — | igual |
| `fn_fdi_crear_liquidacion` | **11** (incluye `p_repartir_igual`) | **10** | — | deriva no listada en el plan: newa evolucionó |
| `fn_registrar_recepcion_con_inventario` | **1 sobrecarga, 12 args** | **1 sobrecarga, 12 args** | 9 args en `presentaciones_inventario/06_recepcion_sin_conversion.sql:61` y `sql_updates/fix_recepcion_inventario_al_completar.sql:100`; `fondo_inversion_recepcion_patch.sql:23` hace DROP de la de 9 | **el overload de 9 args no existe en ninguna BD**: solo en el repo |
| `fn_contabilizar_recepcion_inventario` | 2 sobrecargas (2 y 3 args) | 2 sobrecargas (2 y 3 args) | `sql_updates/fn_contabilizar_recepcion_inventario.sql` | igual |
| `fn_contabilizar_linea_recepcion_inventario` | 1 | 1 | ídem | igual |
| `fn_registrar_cambio_estado_operacion_mejorado` | 3 | 3 | `SQL_OPTIMIZATION/` | igual; R9 abierto en ambos |
| `fn_stock_saldos_presentacion` | 4 | 4 | — | igual |
| `fn_actualizar_precio_promedio_recepcion_v2` | 2 · **13.540 car.** · **usa `monto_usd`** (costos adicionales) | 2 · 6.405 car. · **no** usa costos | `costos_adicionales_producto.sql:225` | **dos funciones distintas con la misma firma** |
| `fn_actualizar_precio_promedio_recepcion_v3` | 2 | 2 | — | sin llamadores en ambas |
| `trg_fn_recepcion_productos_costo_real` | **S** (`trigger`) | **N** | `costos_adicionales_producto.sql:195` | ver §1.5 |

## 2. Diferencias que OBLIGAN a cambiar el plan

1. **Fase 6 arranca a medias según el entorno.** `costos_adicionales_producto.sql` está aplicado
   **completo** en newa (2 tablas, `costo_real` no generada, trigger, `v2` con `costos[]`) y **nada** en
   Main. El plan dice "se aplica adaptado y se prueba en dev": en dev ya está; falta **replicarlo en Main**.
2. **La `v2` de `precio_promedio` no es la misma función en los dos entornos.** En newa pesa `monto_usd`
   de costos adicionales (13,5 KB); en Main no (6,4 KB). Fase 6 dice "arreglar la viva" — la viva
   **difiere por entorno**, y la de newa ya incorpora los adicionales.
3. **`fn_fdi_gasto` falta solo en Main.** El plan lo trata como "crear si la fase 0 confirmó que falta"
   en singular: es **una** creación (Main) y **cero** en newa. El CHECK de 9 tipos, igual: 9 en newa,
   8 en Main.
4. **El "overload de 9 args" de la recepción no existe.** Fase 5 asigna trabajo a `DROP` de sobrecargas
   de 9 y a verificar `pronargs`, pero hay **una sola** de 12 args en ambos entornos. El riesgo se
   invierte: el peligro es **aplicar** los `.sql` viejos del repo que sí la crean.
5. **`app_cont_tipo_costo` está vacío en los dos entornos (0 filas).** No hay ningún tipo "importadora"
   ni otro equivalente: fase 6 usa `id_tipo_costo = importadora` como si existiera. Falta sembrarlo, y
   el nomenclador se administra desde superadmin, no desde el admin.
6. **El fondo nunca se usó en producción (0 filas en las 15 `fdi_*`) y en newa sí** (3 liquidaciones,
   16 movimientos, 10 saldos, 6 cuentas). Fase 1 ("que el fondo no pueda descuadrar por los caminos que
   ya existen") **no tiene datos productivos que proteger**, y su E2E puede montarse sobre las cuentas
   que ya existen en newa.
7. **`fn_fdi_crear_liquidacion` tiene 11 args en newa y 10 en Main** (`p_repartir_igual`). El plan no la
   menciona; si un script la reescribe con la firma de Main, **borra** esa capacidad en dev.
8. **`app_cont_centro_costo`: 110 filas en Main, 0 en newa.** Si el plan reutiliza centro de costo para
   el reparto del costo aterrizado, el nomenclador existe en producción y **no** en dev.

## 3. Lo que está igual y por tanto no cambia

- **Las 15 tablas `fdi_*` existen en ambos**, con las mismas columnas y el mismo `CHECK (saldo >= 0)`.
  `verify/00` punto (a) pasa en los dos.
- **`fdi_dat_saldo.saldo` es `numeric` sin escala en ambos**: no hay deriva de escala que descubrir; el
  ALTER de la fase 1 es el mismo en dev y en prod.
- **`fdi_dat_movimiento` no tiene `idempotency_key`, ni `id_compra`, ni `tasa` en ninguno de los dos.**
  Las fases 2 y 4 no cambian.
- **`fn_fdi_transferir` (13), `fn_fdi_ingreso_manual` (8), `fn_fdi_ajuste` (7),
  `fn_fdi_crear_inversion` (7), `fn_fdi_vincular_recepcion` (6), `fn_fdi_saldos` (1) y
  `fn_fdi_recalcular_inversion` (1) son idénticas en firma.** El plan de las fases 1-2 se sostiene.
- **`app_dat_operacion_recepcion` es idéntica**: `moneda_factura`, `monto_factura` y
  `tasa_cambio_aplicada` ya existen en ambos; no hay columna que crear ahí, solo `origen`.
- **`app_dat_operaciones` no tiene fecha de operación en ninguno** y **`imp_dat_factura` no tiene
  `moneda` ni `id_compra` en ninguno**: los ALTER de las fases 5 y 6 son iguales en dev y prod.
- **`fn_registrar_recepcion_con_inventario` = 12 args con una sola sobrecarga en ambos**, y
  `fn_contabilizar_recepcion_inventario` = 2 sobrecargas (2 y 3 args) en ambos.
- **No existe ninguna tabla de compras (`%compra%`, `cmp_%`) en newa, ni en Main, ni en el repo.**
  Fase 3 no colisiona con nada.
- **`app_nom_naturaleza_costo` = Gasto(1), Ingreso(2) en los dos**, y `app_dat_precio_costo` existe con
  datos en ambos (46 / 9.757): fase 6 puede apoyarse en `precio_costo_usd` sin crearla.

## 4. Nomenclador y reutilización

- `app_cont_tipo_costo` (newa): **0 filas**. Columnas reales: `id, denominacion, descripcion,
  naturaleza smallint, afecta_margen boolean, created_at`. No hay tipo "importadora", "flete" ni
  "aduana": el nomenclador quedó vacío tras `limpiar_modulo_costos.sql:51`.
- `app_nom_naturaleza_costo` (newa): `1 Gasto`, `2 Ingreso`.
- **Reutilizable en newa** (y también en Main salvo lo indicado): `fn_calcular_costo_promedio`,
  `fn_corregir_costo_recepcion` (3 y 5 args), `obtener_precio_promedio_presentacion`,
  `fn_inicializar_precio_promedio_desde_primera_recepcion`,
  `fn_es_operacion_sin_actualizar_precio_costo`, `bulk_update_precios_costo`,
  `fn_crear_asignacion_costo`, `fn_modificar_asignacion_costo`, `fn_insertar_asignacion_costos`,
  `fn_insertar_centro_costo`, `fn_listar_centros_costo[_con_jerarquia]`, `fn_costo_ingredientes_producto`.
- **Trigger reutilizable en newa** (no en Main): `trg_recepcion_productos_costo_real`. En ambos:
  `trg_registrar_precio_costo` sobre `app_dat_producto_presentacion` (`fn_trg_registrar_precio_costo`).
- El plan **no debería crear** un mecanismo de costo aterrizado desde cero:
  `app_dat_recepcion_producto_costo` + `costo_real` escribible + `v2` con `costos[]` ya existen en newa
  y son exactamente el molde de la fase 6.

## Consultas usadas (BD)

`information_schema.columns` por lista de tablas (y `where is_generated <> 'NEVER'`); `count(*)` +
`pg_class.reltuples`; `pg_constraint where contype='c'`; `pg_proc` + `pg_get_function_arguments`;
`pg_trigger` + `pg_get_triggerdef`; `pg_get_functiondef` de `trg_fn_recepcion_productos_costo_real` y
`fn_actualizar_precio_promedio_recepcion_v2`; `select * from app_cont_tipo_costo` /
`app_nom_naturaleza_costo`. Solo `SELECT`.