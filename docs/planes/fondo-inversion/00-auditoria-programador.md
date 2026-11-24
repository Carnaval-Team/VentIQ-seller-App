# 00 · Auditoría de programador — Fondo de Inversión → Compra → Recepción → Consumo

> Alcance: auditoría de código y esquema. **No** propone UI ni criterios contables.
> Leyenda: **[V]** hecho verificado (repo y/o BD en solo-lectura) · **[S]** suposición mía.
> Fecha de auditoría: 2026-11-19. Repo: `VentIQ-seller-App`.

---

## 1. Inventario de lo existente

| Artefacto | Qué hace | Estado |
|---|---|---|
| `ventiq_admin_app/lib/sql/fondo_inversion_schema.sql` (1744 líneas) | 15 tablas `fdi_*` + 18 RPC `fn_fdi_*` + `_fdi_aplicar_movimiento` + `_fdi_ops_elegibles`; RLS en todas | **[V]** coincide con la BD: 15 tablas `fdi_%`, todas `relrowsecurity=true` |
| `fondo_inversion_inversores.sql` (9936 B) | `fdi_dat_inversor`, `fdi_dat_inversor_reparto`, trigger `fn_fdi_repartir_ganancia`, RPC `fn_fdi_guardar_inversor` / `fn_fdi_pagar_inversor` / `fn_fdi_historial_inversores` | **[V]** tablas existen en BD; escritura solo por RPC (`policy … USING (false)`, `fondo_inversion_inversores.sql:16-20`) |
| `fondo_inversion_recepcion_patch.sql` (351 líneas) | Extiende `fn_registrar_recepcion_con_inventario` con `p_id_inversion/p_tasa_inversion/p_confirmar_exceso_inversion` + trigger de desvinculación | **[V]** RPC en BD tiene exactamente esos 12 argumentos |
| `fondo_inversion_gasto.sql` (3198 B) | Añade tipo `gasto` al CHECK de `fdi_dat_movimiento` y la RPC `fn_fdi_gasto` | **[V]** `:1-2`, `:6-20` |
| `lib/models/fondo_inversion.dart`, `services/fondo_inversion_service.dart`, `screens/fondo_inversion_screen.dart`, `widgets/fdi_*.dart` | Cliente Flutter del módulo; 33 métodos en el service | **[V]** `listConceptos … vincularRecepcion` |
| `lib/screens/inventory_reception_screen.dart` | Selector opcional de inversión + tasa manual | **[V]** `:58`, `:102`, `:468-489`, `:494-527` |
| `lib/services/inventory_service.dart` → `insertInventoryReception` | Envuelve `fn_registrar_recepcion_con_inventario` | **[V]** `:1336-1411`; params en `:1360-1375` |
| `lib/sql/0*_lotes_*.sql` (13 archivos) | Lotes, FEFO, egresos, rebalanceo | **[V]** tabla `app_dat_lote` sin columna de stock; el stock por lote vive en `app_dat_inventario_productos.id_lote` |
| `lib/services/costos_adicionales_service.dart` + `docs/PLAN_COSTOS_ADICIONALES.md` | Costos adicionales **por producto** en `app_dat_producto_costo` | **[V]** `:7-21`; no existe vínculo a la operación de recepción |
| `lib/models/importadora_factura.dart`, `services/importadora_facturas_service.dart`, `lib/sql/importadora_facturas_schema.sql` | Facturas de importadora (`imp_*`) y saldo por tienda | **[V]** tablas en BD |
| `lib/sql/pago_proveedores_schema.sql` | Facturas + saldo por proveedor (`prv_*`) | **[V]** tablas en BD |
| `docs/plan-multimoneda/` (29 archivos) | Monedas por tienda, tasas, caja multimoneda, reportes | **[V]** SQL suelto, sin migraciones |
| Proveedores: `models/supplier.dart`, `services/supplier_service.dart` | CRUD `app_dat_proveedor` | **[V]** |
| **"Compra" / orden de compra** | **No existe** | **[V]** Cero tablas con `%compra%`/`%purchase%` en `public`. Lo único análogo: `app_dat_operacion_recepcion` (factura + `observaciones_compra`) — confirma la afirmación del encargo |

---

## 2. Contrato de datos `fdi_*`

| Tabla | Columnas clave | Constraints relevantes |
|---|---|---|
| `fdi_dat_concepto` `:16-25` | `id_tienda, denominacion, activo` | `UNIQUE(id_tienda, denominacion)` |
| `fdi_dat_cuenta` `:45-55` | `id_concepto, id_tienda, nombre, activo` | `UNIQUE(id_concepto, nombre)` |
| `fdi_dat_config` `:75-80` | `id_tienda (PK), dias_alerta_revision` | solo umbral de alerta |
| **`fdi_dat_saldo`** `:100-109` | `id_tienda, id_cuenta, id_medio_pago, moneda, saldo` | **`UNIQUE(id_cuenta, id_medio_pago, moneda)`** + `CHECK(saldo>=0)`; **sin policies de escritura** (`:115`) |
| **`fdi_dat_movimiento`** `:117-136` | `monto, saldo_anterior, saldo_nuevo, tipo, id_liquidacion, id_transferencia, id_inversion, observacion` | `tipo ∈ {liquidacion, transferencia_salida, transferencia_entrada, comision_transferencia, extraccion_inversion, ingreso_manual, ajuste, ajuste_correccion, gasto}` (`:126-129`); `id_liquidacion/id_transferencia/id_inversion` **sin FK** |
| `fdi_dat_liquidacion` `:152-171` | `idempotency_key UNIQUE, id_cuenta_destino, venta/costo/ganancia, diferencia_ganancia, confirmada_con_diferencia, repartir_igual` | `idempotency_key` único real |
| `fdi_dat_liquidacion_detalle` `:182-190` | `id_medio_pago, moneda, monto_vendido, monto_ganancia_retirada, monto_inversion` | `CHECK(monto_inversion>=0)` |
| `fdi_dat_liquidacion_orden` `:200-204` | `id_operacion_venta` | **`UNIQUE` = candado anti doble liquidación** |
| `fdi_dat_transferencia` `:218-243` | `idempotency_key UNIQUE, moneda_origen/destino, tasa, monto_base_origen, monto_comision, monto_total_origen` | `CHECK(tasa>0)`, no origen==destino |
| **`fdi_dat_inversion`** `:254-277` | `idempotency_key UNIQUE, identificador, moneda_referencia, monto_total_ref, monto_recibido_ref, estado, estado_manual, requiere_revision, motivo_revision, monto_faltante_ref, revision_*` | `estado ∈ {pendiente,parcial,completado}` (`:264-265`); `motivo_revision ∈ {completado_con_faltante,vencida}` (`:268`); `UNIQUE(id_tienda, identificador)` |
| `fdi_dat_inversion_fuente` `:284-293` | `id_cuenta, id_medio_pago, moneda, monto, tasa_a_ref, monto_ref` | `CHECK(monto>0)`, `CHECK(tasa_a_ref>0)`; **sin constraint de que Σ`monto_ref` = `monto_total_ref`** |
| `fdi_hist_estado_inversion` `:303-312` | `estado_anterior/nuevo, origen, motivo` | `origen ∈ {automatico,manual}` |
| `fdi_dat_inversion_recepcion` `:322-333` | `id_inversion, id_operacion, monto_recepcion, moneda_recepcion, tasa_a_ref, monto_ref, confirmada_con_exceso` | **`id_operacion UNIQUE`** (idempotencia de vínculo), FK a `app_dat_operaciones` |
| `fdi_dat_inversor(_reparto)` (inversores.sql) | `porcentaje`, `monto, pagado_at, referencia_pago` | `CHECK(porcentaje>0 AND <=100)`; trigger valida suma 100 % |

RLS: SELECT para `authenticated` con `fn_user_can_access_tienda(id_tienda)`; escritura directa solo en estructura (`fn_user_is_gerente_or_superadmin`). **Tablas de dinero sin policy de INSERT/UPDATE/DELETE** → pasan obligatoriamente por RPC `SECURITY DEFINER` (`:5-9`, `:115`).

---

## 3. RPCs: firma, validaciones, efectos

Todas `SECURITY DEFINER SET search_path=public`. En BD hay **22** `fn_fdi_*` (el encargo decía ~19); los 3 extra son `fn_fdi_ajuste(_correccion_liquidacion)`, `fn_fdi_detalle_inversion`, `fn_fdi_inversiones`… **[V]** `pg_proc`.

**`_fdi_aplicar_movimiento(p_id_tienda,p_id_cuenta,p_id_medio_pago,p_moneda,p_delta,p_tipo,p_id_liquidacion,p_id_transferencia,p_id_inversion,p_observacion)` → void** `:349-407`
- `SELECT … FOR UPDATE` del saldo por `(id_cuenta,id_medio_pago,moneda)`; si no existe, lo **INSERTA en 0** (`:377-382`).
- Calcula `saldo_nuevo`; si `<0` lanza `P0002` con el disponible (`:385-389`).
- `UPDATE fdi_dat_saldo` + `INSERT fdi_dat_movimiento` con `saldo_anterior`/`saldo_nuevo`/`created_by=auth.uid()`.
- **No valida** que `p_id_tienda` corresponda a la cuenta, ni que el `p_id_medio_pago`/`p_moneda` existan o pertenezcan a la tienda. **No es idempotente** por sí sola.

**`fn_fdi_crear_inversion(p_id_tienda,p_identificador,p_detalles,p_descripcion,p_moneda_referencia,p_fuentes jsonb,p_idempotency_key)` → jsonb** `:1242-1339`
- Exige gerente/superadmin (`:1267`), identificador no vacío, `p_fuentes` no vacío.
- Idempotencia por `idempotency_key` → devuelve `duplicada:true` (`:1277-1283`).
- Por cada fuente: valida `monto>0`, `tasa>0`, cuenta de la tienda (`:1304-1311`); fuerza `tasa=1` si `moneda=moneda_referencia` (`:1300-1302`).
- **Efecto monetario inmediato**: `_fdi_aplicar_movimiento(… -v_monto, 'extraccion_inversion', p_id_inversion)`, es decir **el dinero sale del fondo al crear la inversión, no al comprar** (`:1317-1321`).
- `p_fuentes` = `[{id_cuenta,id_medio_pago,moneda,monto,tasa_a_ref}]` (`:1241`). Sin validación de medio↔moneda ni de saldo previo (lo cubre el delta).

**`fn_fdi_vincular_recepcion(p_id_operacion,p_id_inversion,p_monto,p_moneda,p_tasa_a_ref=1,p_confirmar_exceso=false)` → jsonb** `:1388-1451`
- Lee la inversión **sin `FOR UPDATE`** (`:1405`); valida tienda de la operación (`:1410-1414`), `monto>0`, `tasa>0`; `tasa=1` si la moneda es la de referencia.
- Si `recibido + monto_ref > total_ref` y no hay confirmación → `{status:'requires_confirmation', code:'exceso_recepcion', …}` sin escribir.
- `INSERT fdi_dat_inversion_recepcion` + `fn_fdi_recalcular_inversion`.
- **No valida que la operación sea una recepción** (`app_dat_operacion_recepcion`) ni su estado; solo la tienda.

**`fn_fdi_desvincular_recepcion(p_id_operacion)` → void** `:1454-1471` — `DELETE … RETURNING id_inversion` + recalcular. Sin comprobar quién llama (expuesta a `authenticated`, `:1738`).

**`fn_fdi_recalcular_inversion(p_id_inversion)` → void** `:1193-1239`
- `FOR UPDATE` de la inversión; `monto_recibido_ref = Σ fdi_dat_inversion_recepcion.monto_ref`.
- `estado` derivado: `<=0 → pendiente`, `< total → parcial`, `>= total → completado`; inserta historial si cambia.
- **Fuerza `estado_manual=false`** (`:1228`) → pisa cualquier cambio manual previo.
- Si `recibido >= total`, limpia `requiere_revision/motivo_revision/monto_faltante_ref`.

**`fn_fdi_cambiar_estado_inversion(p_id_inversion,p_estado,p_motivo)` → jsonb** `:1341-1386` — `FOR UPDATE`, exige gerente, `estado` válido. Permite **cualquier** transición (incluso `completado→pendiente`). Marca `estado_manual=true`; si se completa con faltante setea `requiere_revision='completado_con_faltante'` y `monto_faltante_ref` (`:1372-1380`).

**`fn_fdi_saldos(p_id_tienda)` → jsonb** `:1512-1544` — `STABLE`, exige acceso; devuelve `saldos[]` (concepto/cuenta/medio/moneda/saldo) y `totales_por_moneda` (suma **sin conversión**, agrupada por moneda).

**`fn_fdi_ingreso_manual(p_id_tienda,p_id_cuenta,p_id_medio_pago,p_moneda,p_monto,p_fecha,p_motivo,p_idempotency_key)`** `:968-1010` — gerente; `monto>0`; cuenta activa de la tienda; **idempotencia por texto**: `EXISTS(... tipo='ingreso_manual' AND observacion='idem:'||key)` (`:993-998`) y el `idem:` se concatena al final de la observación (`:1003-1006`).

**`fn_fdi_gasto(p_id_tienda,p_id_cuenta,p_id_medio_pago,p_moneda,p_monto,p_destino,p_motivo,p_idempotency_key)`** `:1058-1115` — gerente; `monto>0`; `p_destino` obligatorio (texto libre); cuenta activa; idempotencia por `LIKE '%idem:'||key`; aplica `-p_monto` con `observacion='Destino: …'`. **Es el único puente actual "fondo → pago a proveedor/importadora", y es texto libre sin FK**.

**`fn_fdi_transferir(...13 params)`** `:857-962` — gerente; `monto_destino>0`, `tasa>0`; corrección solo con costo 0 % (`:892-895`); cuentas de la tienda; idempotencia por `idempotency_key`; `base_origen = monto_destino*tasa`, `comision = round(base*%/100, 2)` (`:918-920`); tres movimientos (salida, comisión, entrada).

Resto (menos crítico para el encargo): `fn_fdi_ajuste` (solo positivo, `:1029-1031`), `fn_fdi_ajuste_correccion_liquidacion` (tope = ingresado − corregido, `:1155-1168`), `fn_fdi_resolver_revision`, `fn_fdi_crear_liquidacion` (`:623-851`), `fn_fdi_ventas_por_medio_moneda`, `fn_fdi_movimientos`, `fn_fdi_liquidaciones`, `fn_fdi_inversiones` (calcula `en_revision` por días al vuelo, `:1651-1666`), `fn_fdi_detalle_inversion`, `fn_fdi_guardar_inversor`, `fn_fdi_pagar_inversor`, `fn_fdi_historial_inversores`.

Detalle no obvio: `fn_fdi_repartir_ganancia` es **trigger** de `fdi_dat_liquidacion_detalle` (`inversores.sql:88-131`) y sobrescribe `monto_ganancia_retirada` con la suma de `fdi_dat_inversor_reparto` (schema `:813-818`); lanza excepción si no hay inversores activos (`inversores.sql:105-107`).

---

## 4. Ciclo de vida actual

**Inversión** ([V] `:254-277`, `:1193-1239`, `:1341-1386`):
`pendiente` (creada, `monto_recibido_ref=0`) → `parcial` (alguna recepción vinculada) → `completado` (`recibido>=total`). `estado_manual` indica que un humano forzó el estado y **se borra en el siguiente recálculo**. `requiere_revision` + `motivo_revision` existen para dos casos: completado a mano con faltante (persistido) y vencimiento (calculado al leer, `:1651-1666`, umbral `fdi_dat_config.dias_alerta_revision`). No hay estado `anulado/cancelado`: **una inversión no se puede revertir** y el `extraccion_inversion` ya descontó el saldo.

**Amortización**: `fn_fdi_vincular_recepcion` acumula `monto_ref = monto * tasa_a_ref` en `fdi_dat_inversion_recepcion`; el recálculo **suma**, nunca compara contra lo que realmente entró al inventario (no hay vínculo cantidad↔monto). `confirmada_con_exceso` marca las que excedieron el total.

**Recepción** ([V] `fondo_inversion_recepcion_patch.sql:26-40`, BD `pg_proc`):
1. `fn_registrar_recepcion_con_inventario(p_entregado_por,p_id_tienda,p_monto_total,p_motivo,p_observaciones,p_productos jsonb,p_recibido_por,p_uuid,p_moneda_factura,p_id_inversion,p_tasa_inversion,p_confirmar_exceso_inversion)`.
2. Valida tienda, ≥1 producto, moneda ∈ {USD,EUR,CUP} (`:93-101`), `motivo` → `app_nom_motivo_recepcion`. Inserta `app_dat_operaciones` + `app_dat_operacion_recepcion` con `moneda_factura char(3)`, `tasa_cambio_aplicada`, `fecha_tasa_aplicada` (`:117-133`).
3. Por producto: `id_producto`, `cantidad`, `precio_unitario`, `id_presentacion`, `id_ubicacion`, `id_proveedor`, `id_variante`, `id_opcion_variante`, y lote (`codigo_lote|lote|nro_lote`, `fecha_vencimiento`, `fecha_fabricacion`) → `fn_obtener_o_crear_lote` si `app_dat_producto.es_por_lotes` (`:158-222`). Inserta en **`app_dat_recepcion_productos`** … `:224-236`.
4. Estado inicial `1` (pendiente). **El stock no se toca aquí**: el comentario de retorno lo dice explícitamente (`:284`).
5. Si `p_id_inversion` → `fn_fdi_vincular_recepcion` en la **misma transacción** (`:257-275`). Si falta confirmar exceso, devuelve `requires_confirmation` **con la recepción ya creada**; el cliente reintenta solo el vínculo (`inventory_reception_screen.dart:494-527`).
6. **`EXCEPTION WHEN OTHERS` devuelve JSON de error** en vez de propagar (`:287-303`) → un fallo posterior al `INSERT` de la operación **no revierte** nada.

**Aplicación de stock** — hay **dos caminos que compiten** [V] `pg_proc`:
- `fn_registrar_cambio_estado_operacion_mejorado(p_id_operacion, p_nuevo_estado, p_uuid_usuario)`: al pasar a `2` inserta en `app_dat_inventario_productos` con `cantidad_inicial = último cantidad_final` y `origen_cambio=1`; **no copia `id_lote`**. Al pasar a `3/4` borra las filas. Acepta solo estados `1..4` (**rechaza `5` anulada**).
- `fn_contabilizar_recepcion_inventario(p_id_operacion, p_solo_faltantes, p_atomico)` + `fn_contabilizar_linea_recepcion_inventario(p_id_recepcion_producto)`: **sí** propaga `id_lote`, es idempotente por `id_recepcion` (devuelve `OMITIDO`) y soporta modo atómico.
- Ninguno de los dos toca costo: `precio_costo` se alimenta aparte (`trg_registrar_precio_costo` sobre `app_dat_producto_presentacion`; el cliente llama `fn_actualizar_precio_promedio_recepcion_v2`, `inventory_service.dart:4172`).

**Desvinculación**: trigger `trg_fdi_desvincular_recepcion` `AFTER INSERT` en `app_dat_estado_operacion` para estados `3,4,5` de operaciones que son recepción y están vinculadas (`patch:329-351`) → borra el vínculo y recalcula. El stock se borra solo en `3/4` (camino `mejorado`).

---

## 5. Gaps técnicos (compra → recepción → consumo)

1. **[CRÍTICO] No existe la entidad compra/orden de compra.** Cero tablas `%compra%` [V]. Falta: cabecera (proveedor, moneda, tasa, estado, idempotency), detalle (producto/presentación/cantidad/costo unitario/costo total), y `id_compra` en recepción.
2. **[CRÍTICO] El costo real de recepción no se persiste desde el flujo del fondo.** `app_dat_recepcion_productos` tiene `costo_real, precio_referencia, descuento_porcentaje, descuento_monto, bonificacion_cantidad` [V information_schema], pero `fn_registrar_recepcion_con_inventario` solo escribe `precio_unitario` (`patch:224-236`). El "costo real" (pago importadora + adicionales) no entra por ninguna RPC.
3. **[CRÍTICO] "Pago a importadora" y "pago a proveedores" no se conectan a la inversión.** `imp_dat_saldo`/`prv_dat_saldo` son `(idtienda, saldo_disponible)` **sin moneda**; `imp_dat_factura`/`prv_dat_factura` guardan `valor` **sin moneda** [V]. No hay `id_inversion` en `imp_*`/`prv_*` ni `id_factura` en recepción. El único puente es `fn_fdi_gasto` con `p_destino` texto libre.
4. **[CRÍTICO] "Una sola fuente de liquidación" no está modelado.** Nada impide crear una inversión (que extrae del fondo, `:1317-1321`) **y** además pagar el mismo proveedor con `fn_fdi_gasto` del mismo saldo. No hay constraint de exclusividad ni flag `fuente_liquidacion`.
5. **[ALTO] Entrega parcial solo a nivel de monto.** `fdi_dat_inversion_recepcion` guarda **un** `monto_recepcion` por operación; no hay cantidades por producto ni comparación contra lo pedido. Imposible saber si la entrega parcial corresponde a las líneas 1-3 o a 4-5.
6. **[ALTO] Lote perdido al completar.** `fn_registrar_cambio_estado_operacion_mejorado` no copia `id_lote` (vs. `fn_contabilizar_linea_recepcion_inventario`, que sí) [V `pg_proc`]. Completar una recepción por cambio de estado deja stock sin lote → FEFO roto.
7. **[ALTO] Costos adicionales fuera de transacción y a nivel producto.** `persistirCostosRecepcion` se ejecuta después del RPC y en `try/catch` que solo imprime (`inventory_service.dart:1394-1402`); escribe `app_dat_producto_costo.monto_usd/monto_promedio_usd` promediando por producto+tipo, no por línea de recepción.
8. **[ALTO] Sin reserva/bloqueo de saldo.** No existe `saldo_comprometido` ni tabla de reservas [V: sin `reserva` en los `.sql`]. El saldo solo se descuenta al aplicar.
9. **[MEDIO] Idempotencia heterogénea.** Tablas con `idempotency_key UUID UNIQUE` (inversión, liquidación, transferencia) vs. `observacion LIKE '%idem:<uuid>'` (ingreso, ajuste, gasto), que no tiene índice único y es vulnerable a carrera.
10. **[MEDIO] Recepción huérfana si falla después del INSERT.** El `EXCEPTION WHEN OTHERS` (`patch:287-303`) devuelve `status:'error'` con la operación ya creada; el cliente puede reintentar y duplicar la recepción.
11. **[MEDIO] `fn_fdi_vincular_recepcion` acepta cualquier operación** de la tienda, no solo recepciones, y no mira el estado (`:1410-1414`).
12. **[MEDIO] Estado `5` (anulada) rechazado** por `fn_registrar_cambio_estado_operacion_mejorado` pero cubierto por el trigger FDI (`patch:336`): si se anula por otra ruta, el vínculo se borra pero el stock puede quedar aplicado.
13. **[MEDIO] No hay anulación de inversión** (`estado` sin `anulado`, `:264-265`) ni RPC de devolución del `extraccion_inversion`.
14. **[BAJO] `fn_fdi_recalcular_inversion` solo tiene GRANT a `service_role`** (`:1734`) mientras `fn_fdi_vincular_recepcion` (que lo invoca) es `authenticated`; funciona por `SECURITY DEFINER`, pero impide recálculos manuales desde la app.
15. **[BAJO] `_fdi_aplicar_movimiento` no valida `p_id_tienda`** contra la cuenta (`:370-375`).

---

## 6. Riesgos de integridad del dinero

- **R1 · Descuadre invisible por `id_tienda` erróneo.** `_fdi_aplicar_movimiento` localiza el saldo por `(cuenta, medio, moneda)` pero escribe `fdi_dat_movimiento.id_tienda = p_id_tienda`. Un RPC que pase una tienda distinta a la de la cuenta mueve el saldo correcto y registra el movimiento en la tienda equivocada → `fn_fdi_movimientos`/`fn_fdi_saldos` no lo muestran y el arqueo no cuadra. **[V]** `:370-405`.
- **R2 · Dinero irrecuperable.** `fn_fdi_crear_inversion` debita al crear (`:1317-1321`) y no hay anulación ni devolución. Una inversión creada por error deja el saldo descontado para siempre; el único remedio es `fn_fdi_ingreso_manual`/`fn_fdi_ajuste`, que **no** quedan ligados a la inversión.
- **R3 · Sobre-recepción por carrera.** `fn_fdi_vincular_recepcion` lee la inversión sin `FOR UPDATE` (`:1405`) y decide el exceso con `monto_recibido_ref` leído antes; dos recepciones concurrentes contra la misma inversión pueden ambas pasar sin `confirmar_exceso`. El `UNIQUE(id_operacion)` evita el duplicado exacto, **no** el exceso agregado.
- **R4 · Doble financiamiento (fondo + inversores).** Con R2 y el gap 4: se extrae del fondo al crear la inversión y, si además se paga al proveedor con `fn_fdi_gasto` o se liquida con aportes, el mismo costo se financia dos veces sin que ninguna constraint lo detecte.
- **R5 · Duplicado por reintento en ingreso/gasto.** `fn_fdi_ingreso_manual` comprueba `EXISTS` y luego inserta (`:993-1006`); dos llamadas concurrentes con la misma key pasan ambas por el `EXISTS` (no hay lock ni índice único) → **ingreso duplicado**. Igual en `fn_fdi_ajuste` (`:1039-1044`) y `fn_fdi_gasto` (`:1093-1099`).
- **R6 · Redondeo sin escala.** Todas las columnas monetarias son `numeric` sin precisión declarada; `monto_ref = monto*tasa` no se redondea (`:1313`, `:1425`) y solo las comisiones usan `round(…,2)` (`:919`). Comparaciones con tolerancia fija `0.01` (`:768`) sobre acumulados multimoneda → diferencias de centavos que reaparecen en el recálculo y en `diferencia_ganancia`.
- **R7 · Liquidación bloqueada por configuración ajena.** `fn_fdi_repartir_ganancia` lanza excepción si no hay inversores activos (`inversores.sql:105-107`); cualquier `fn_fdi_crear_liquidacion` falla en ese estado, incluidas liquidaciones cuyo retiro el usuario ya definió. Además ese trigger **sobrescribe** `monto_ganancia_retirada` (`:813-818`), así que lo que el cliente pidió puede no ser lo que se registra.
- **R8 · Total por moneda sin consolidar.** `fn_fdi_saldos` devuelve `totales_por_moneda` sumando cuentas y medios de distinta naturaleza (`:1538-1540`); no hay tipo de cambio por tienda aplicado en la lectura, y `fn_fdi_crear_inversion` acepta `tasa_a_ref` **tipeada por el usuario** sin contrastarla con `tasa_cambio_extraoficial` ni `tasas_conversion` (que sí usa la liquidación, `:524-528`).
- **R9 · Stock y billete divergen.** La recepción aplica inventario por cambio de estado (camino A, sin lote) o por contabilización (camino B, con lote), y el vínculo a la inversión es independiente. Completar la recepción sin contabilizar deja la inversión "recibida" con stock no aplicado — y al revés.

---

## 7. Convención real de migración/despliegue

**[V] No hay una convención única; hoy manda el script manual.**

- `supabase/migrations/` existe pero contiene **10 migraciones** (2026-09-27 → 2026-11-12), ninguna del fondo de inversión, recepción, importadora ni pago a proveedores. Formato `YYYYMMDDHHMMSS_descripcion.sql` + carpeta `supabase/rollback/` con 1 rollback.
- **No hay `supabase/config.toml`** y ningún script del repo invoca `supabase db push` / `migration up` (grep sobre `build_and_deploy.*`, `README_DEPLOY*`, `scripts/`). El CLI no está operativo en este repo.
- La vía real es pegar SQL en el editor de Supabase: `-- Ejecutar en el SQL Editor de Supabase` (`lib/sql/importadora_facturas_schema.sql:2`, `lib/sql/pago_proveedores_schema.sql:4`), y `-- Ejecutar DESPUÉS de fondo_inversion_schema.sql` (`fondo_inversion_recepcion_patch.sql:3`). Orden implícito, sin runner.
- Hay **62 archivos** en `sql_updates/` (parches sueltos, p. ej. `costos_adicionales_producto.sql`, `auditar_recepcion_inventario.sql`) y ~70 en `ventiq_admin_app/lib/sql/`. Los `.sql` de `docs/plan-multimoneda/` también son scripts sueltos.
- Consecuencia: el esquema de la BD **no es reproducible** desde el repo. Un plan de compra→recepción→consumo debe decidir si introduce migraciones versionadas **o** sigue el patrón manual; hoy no hay rollback ni verificación de idempotencia de los scripts (`CREATE TABLE IF NOT EXISTS` convive con `DROP FUNCTION` + `CREATE OR REPLACE` en `patch:23-24`).

---

## 8. Diez preguntas técnicas que el plan debe responder

1. ¿La compra es una entidad nueva (`fdi_dat_compra` + detalle) o se modela como extensión de `app_dat_operacion_recepcion` con `numero_factura`/`monto_factura`?
2. ¿El dinero sale del fondo **al crear la compra** (reserva), al **recibir**, o al **pagar la factura**? Hoy sale al crear la inversión (`:1317-1321`).
3. ¿Dónde vive la tasa de cambio de cada documento: columna por documento, tabla de tasas por fecha, o ambas? ¿Quién la valida contra `tasa_cambio_extraoficial`?
4. ¿El costo real por línea se guarda en `app_dat_recepcion_productos.costo_real` (ya existe) o en una tabla nueva de costos por recepción?
5. ¿Cómo se impone "una sola fuente" a nivel de constraint (flag + índice único parcial, trigger de exclusividad, o validación en RPC) y qué pasa si ya existe una inversión liquidada?
6. ¿Se formaliza reserva/bloqueo de saldo (`saldo_comprometido`, tabla de reservas) o se mantiene descuento puro al aplicar?
7. ¿Se unifican los dos caminos de aplicación de stock (`mejorado` vs `contabilizar`) o el de compras usa solo `fn_contabilizar_recepcion_inventario` (el único que propaga `id_lote`)?
8. ¿La idempotencia pasa a `idempotency_key UUID UNIQUE` en todas las RPC de dinero, con migración de los `observacion LIKE '%idem:%'` existentes?
9. ¿Cómo se hace atómica la recepción (quitar el `EXCEPTION WHEN OTHERS` que devuelve JSON, o envolver en savepoint) y qué contrato de error adopta el cliente Flutter?
10. ¿Se adopta `supabase/migrations/` para este módulo (con `config.toml` y `db push`) o se documenta el orden manual de los `.sql`? Sin esto el plan no es reproducible.

---

### No verificado / límites de esta auditoría
- **[S]** No ejecuté ni probé ninguna RPC (solo lectura). Los efectos descritos salen del código SQL y de `pg_get_functiondef`, no de una corrida.
- No pude determinar el **orden histórico** real de aplicación de los scripts en la BD de producción (no hay tabla de migraciones que lo registre); deduje el estado actual comparando `information_schema`/`pg_proc` contra el repo.
- No revisé `widgets/fdi_*.dart` (no aportan al contrato de datos) ni la lógica contable de `fn_fdi_crear_liquidacion` más allá de lo necesario para el encargo.
- La afirmación "no existe compra" se verificó por nombre de tabla (`%compra%`, `%purchase%`) y por ausencia de modelo/servicio `compra_*.dart`; si existiera con otro nombre, se me escapó.