# Comparación de funciones newa vs main

Medido el 18/11/2026 leyendo las definiciones vivas de los dos proyectos (solo SELECT).

- newa = `qhprswhhfasrikhawjoz` (debug). main = `vsieeihstajlrdvpuooh` (release).
- Se excluyen las funciones de extensiones.
- Firma = `oid::regprocedure`. Cuerpo = `md5(prosrc)`.

| Conjunto | Cantidad |
|---|---|
| Funciones en main | 887 |
| Funciones en newa | 970 |
| En las dos con la misma firma | 880 |
| En las dos pero con cuerpo distinto | **81** |
| Solo en newa | 90 |
| Solo en main | **7** |

Convención de los diffs: se comparó ignorando espacios, líneas en blanco, comentarios y los
comentarios con codificación rota de main (`â”€`). "newa" y "main" son lo que hace cada una hoy.

Resumen de los 81 cuerpos distintos:

| Veredicto | Cantidad | Qué hacer |
|---|---|---|
| A. newa más nueva | 21 | Llevar el cuerpo de newa a main (con sus dependencias) |
| B. Sin cambio lógico | 40 | Nada. Solo formato, comentarios o `search_path` |
| C. main más nueva | 12 | No copiar newa. Al contrario, newa tiene que recoger lo de main |
| D. Hay que combinar a mano | 8 | Decidir criterio antes de promover |

Dependencias que los cuerpos de newa necesitan y main no tiene todavía:
`fn_config_tienda_exigir_lectura`, `fn_config_tienda_puede_escribir`,
`fn_turno_alinear_fecha_apertura`, la columna `permitir_moneda_por_producto`,
`fdi_dat_liquidacion.repartir_igual`, las tablas `app_dat_producto_costo` y
`app_dat_recepcion_producto_costo`, y las columnas `m01_solicitud`/`m01_id_tienda` de
`app_dat_operacion_offline_idempotencia`.

---

## A. newa más nueva (21)

El patrón común del bloque offline (M01): evidencia de idempotencia en
`app_dat_operacion_offline_idempotencia`, `pg_advisory_xact_lock(hashtextextended(client_uuid::text,0))`,
actor = `auth.uid()`, permiso con `fn_config_tienda_puede_escribir`, `SET search_path TO 'pg_catalog'`.
Main tiene la versión anterior, sin esas defensas.

| Función | Qué cambia de main a newa |
|---|---|
| `fn_apertura_turno_offline` | Idempotencia M01, lock por `client_uuid`, actor `auth.uid()`, fecha de apertura alineada con `fn_turno_alinear_fecha_apertura` (R33). |
| `fn_apertura_turno_offline_monedas` | Igual que la anterior, con desglose por moneda. |
| `fn_apertura_turno_offline_usd` | Igual, variante USD. |
| `fn_cerrar_turno_offline` | Idempotencia M01 y `fecha_cierre = GREATEST(apertura, LEAST(p_fecha_cierre, now()))`: ya no acepta cierres en el futuro ni antes de la apertura. |
| `fn_cerrar_turno_offline_monedas` | Igual. |
| `fn_cerrar_turno_offline_usd` | Igual. |
| `fn_cambiar_estado_comanda_item_offline` | Idempotencia M01 (rechaza con 42501 si la clave no coincide con la solicitud o con el usuario) y resuelve la tienda por la cocina de la comanda, con bloqueo `FOR SHARE`. Sin `auth.uid()` rechaza. |
| `fn_registrar_cambio_estado_offline` | Idempotencia M01, lock por `client_uuid`. |
| `fn_pedir_item_cuenta_offline` | Delega en `fn_pedir_item_cuenta_v2`; en main duplica la lógica. |
| `fn_registrar_egreso_offline` | Idempotencia M01. |
| `fn_registrar_egreso_offline_v2` | Valida la moneda contra `monedas` y llama a `registrar_egreso_parcial_v2`. |
| `fn_registrar_pago_venta_offline` | Idempotencia M01 y actor `auth.uid()`. Además resuelve tienda, TPV y autor de la venta, y exige que quien cobra sea quien puede escribir en la tienda o el vendedor de esa tienda. |
| `fn_registrar_venta_offline_v4` | `LEAST(p_fecha_creacion, now())`, valida vendedor/TPV/trabajador, clave de idempotencia `venta_v4`. |
| `fn_registrar_cambio_estado_operacion` | Al devolver, si no hay presentación indicada usa la presentación `es_base` (`v_presentacion_devolver`). |
| `fn_moneda_consolidacion` | Guarda de lectura `fn_config_tienda_exigir_lectura`. |
| `fn_obtener_licencia_firmada` | Guarda de lectura `fn_config_tienda_exigir_lectura`. |
| `sync_bundle` | Guarda de lectura y comprueba que el TPV pertenece a la tienda. |
| `fn_validar_moneda_forzada` | Rechaza forzar moneda cuando el producto tiene `permitir_moneda_por_producto`. |
| `fn_fdi_repartir_ganancia` | Soporta `repartir_igual` (columna que main no tiene). |
| `fn_actualizar_precio_promedio_recepcion_v2` | Costos adicionales por tipo, promedio ponderado y `costo_real`. `SECURITY DEFINER`. |
| `fn_listar_ordenes` | Acota por `v_tiendas`, usa joins LATERAL y devuelve campos v1. **Bug**: la clave JSON sale como `'tipo_paago'` en lugar de `'tipo_pago'`. Corregir antes de promover. |

## B. Sin cambio lógico (40)

Misma lógica en las dos. Las diferencias son formato, comentarios o `search_path`.

`fn_actualizar_moneda`, `fn_crear_moneda`, `fn_desglose_monedas_turno`, `fn_desglose_monedas_usuario`,
`fn_esperado_turno_por_moneda`, `fn_sync_turno_moneda`, `fn_resumen_diario_cierre_v4`,
`fn_resumen_turno_kpi_v2`, `fn_resumen_turno_por_id_v2`, `fn_registrar_pago_venta`,
`fn_registrar_pago_venta_v2`, `fn_registrar_pago_venta_v3` (solo `search_path 'pg_catalog','public'`),
`fn_pago_venta_equivalente`, `fn_tasa_automatica`, `fn_tasa_automatica_estado`, `fn_tasa_cambio`,
`fn_tasas_ingerir`, `fn_tasas_refrescar`, `fn_guardar_denominaciones`, `fn_guardar_monedas_tienda`,
`fn_guardar_tasa_global`, `fn_jsonb_monto`, `fn_seed_tienda_monedas`, `registrar_apertura_turno_monedas`,
`registrar_egreso_parcial_v3`, `egresos_por_turno`, `fn_subcategoria_general_especial`,
`fn_reporte_ventas_por_turno_v2`, `fn_reporte_ventas_con_proveedor_por_turno_v2`,
`fn_reporte_ventas_por_moneda`, `fn_cancelar_item_pedido_v2`, `fn_devolver_ingredientes_elaborado_v2`,
`fn_pedir_item_cuenta_v2`, `fn_actualizar_operacion_contabilizada` (3 parámetros),
`get_product_movements_v5`, `fn_cerrar_turno_tpv_monedas`.

Casos con matiz:

| Función | Diferencia |
|---|---|
| `fn_obtener_ingredientes_recursivos` | Misma lógica. Main fija `search_path = public, pg_catalog`; newa no lo fija. Conviene fijarlo en newa. |
| `fn_actualizar_cantidad_producto_orden_v2` | Los dos devuelven `status = error` con "Extracción no encontrada" y "Solo se pueden editar órdenes en estado Pendiente". En main los mensajes están guardados con la codificación rota (`ExtracciÃ³n`, `Ã³rdenes`); newa los tiene bien. Solo cambia el texto. |
| `fn_agregar_producto_orden_pendiente_v2` | Igual que la anterior (diferencia de codificación en los mensajes). |
| `fn_eliminar_producto_orden_v2` | Igual que la anterior (diferencia de codificación en los mensajes). |

## C. main más nueva (12): no copiar newa

| Función | Qué tiene main que newa no |
|---|---|
| `fn_check_update` | Devuelve `titulo`, `novedades`, `url_descarga`, `id_version`, `build_disponible`. Es `STABLE SECURITY DEFINER` y usa `fn_version_menor` para `obligatoria`. |
| `fn_listar_motivos_extraccion` | Cualquier `authenticated` puede listar, `search_path = public, pg_temp`. newa sigue exigiendo almacenero/supervisor/gerente. |
| `fn_update_carnaval_product_prices` | Usa `fn_carnaval_precio_base_vigente` y omite si el precio no cambió. newa lee `precio_venta_cup` directo. |
| `sync_price_to_carnaval` | Igual que la anterior. |
| `get_productos_completos_by_tienda_optimized` | Precio vigente por `ORDER BY id_producto, id DESC` (regla de AGENTS.md). newa ordena por `fecha_desde DESC`, que contradice la regla. |
| `get_productos_completos_by_tienda_optimized_provider` | Igual. |
| `get_productos_completos_by_tienda_optimized_provider2` (4 parámetros) | Igual. |
| `get_productos_completos_by_tienda_optimized_provider2` (5 parámetros) | Igual. |
| `get_productos_completos_by_tienda_optimized_v2` | Igual. |
| `get_productos_completos_by_tienda_optimized2` | Igual. |
| `get_productos_completos_by_tienda_with_supplier` | Igual. |
| `buscar_producto_por_codigo_barras_v3` | Igual. |

Acción: corregir las 8 funciones de precio en newa para que usen `id DESC`, y volver a traer los
cuerpos de main de `fn_check_update`, `fn_listar_motivos_extraccion` y las dos de Carnaval.
**Hecho en newa el 20/11/2026** con `sql_updates/newa_traer_12_funciones_main.sql`: las 12 tienen el mismo
`md5(prosrc)` que main.

## D. Hay que combinar a mano (8)

> **Actualización 19/11/2026.** Tras leer a fondo estas 8 (ver `analisis_8_funciones_pendientes.md`), la clasificación
> cambia: `get_detalle_producto` y `get_detalles_productos_batch` pasan a **B** (la vista de precio base ya filtra la
> variante, el filtro de newa es redundante); `fn_dashboard_carnaval_proveedor`, `fn_stock_producto_almacen_detalle`,
> `fn_stock_saldos_presentacion` y `fn_reporte_ventas_con_proveedor_por_turno` pasan a **C** (main gana). Solo quedan
> por decidir `fn_reporte_ventas_por_turno` y `fn_registrar_cambio_estado_operacion_mejorado`. Cuentas finales:
> A = 21, B = 42, C = 16, D = 2. Las filas de abajo son el análisis inicial y quedan superadas por ese archivo.

| Función | main | newa | Qué decidir |
|---|---|---|---|
| `get_detalle_producto` | Sin filtro de variante base. | Añade `AND COALESCE(id_variante,0)=0` para el precio base. | newa está bien (NULL y 0 son la variante base). Llevarlo a main. |
| `get_detalles_productos_batch` | Igual que arriba. | Igual que arriba. | Igual. |
| `fn_reporte_ventas_por_turno` | Rango por id de operación entre apertura y cierre efectivo. | Ventana por `created_at`; quita la guarda de `v_id_tipo_venta` NULL. | Elegir un único criterio de turno. |
| `fn_reporte_ventas_con_proveedor_por_turno` | Ventana por `created_at`. | CTE `turnos` + `max_op`, rango por id de operación. | Dirección opuesta a la anterior. Usar el mismo criterio en las dos. |
| `fn_dashboard_carnaval_proveedor` | Totales con `FILTER status='Completado'`, monto por estado y top 10 por estado. | Suma todos los estados y quita el desglose por estado. | newa cambia el significado del total. Confirmar si es intencional. |
| `fn_registrar_cambio_estado_operacion_mejorado` | Revierte inventario de recepción al pasar a estado 2/3/4. | Quita esa reversión y añade `created_at = NOW()` opcional al cerrar (`cambiar_fecha_creacion_operacion_al_cierre`). | Posible regresión: confirmar que quitar la reversión fue deliberado. |
| `fn_stock_producto_almacen_detalle` | Escaneo recursivo (loose index scan) con rama de lotes (`hay_lotes`, `vigente_lote`). | Reescrita con `DISTINCT ON` y sin rama de lotes. | Equivalencia no confirmada. Ver `ventiq_admin_app/lib/sql/06_lotes_stock_sum_fefo.sql` ("aplicar solo en newa") y `sql_updates/optimizar_saldos_vigentes_skip_scan.sql`. |
| `fn_stock_saldos_presentacion` | Igual que la anterior. | Igual que la anterior. | Igual. |

---

## Hay que corregir antes de promover

1. ~~`fn_listar_ordenes` en newa: `'tipo_paago'` → `'tipo_pago'`.~~ Hecho.
2. ~~8 funciones de newa con `fecha_desde DESC`: pasar a `id DESC` (regla de AGENTS.md).~~ Hecho el 20/11.
3. Un solo criterio de turno en `fn_reporte_ventas_por_turno` y `fn_reporte_ventas_con_proveedor_por_turno`.
4. Decidir `fn_registrar_cambio_estado_operacion_mejorado` (reversión de inventario de recepción).
5. Decidir `fn_dashboard_carnaval_proveedor` (total con o sin filtro de estado).
6. Confirmar que las funciones de stock con lotes son equivalentes.
7. newa debe recoger lo de main: `fn_check_update`, `fn_listar_motivos_extraccion`, Carnaval.

---

# Las 7 firmas que solo existen en main

Dónde se usan, qué hace cada una hoy en main y qué hacer.

| # | Firma en main | Tipo de caso |
|---|---|---|
| 1 | `fn_actualizar_operacion_contabilizada(bigint, boolean)` | Sobrecarga vieja. En newa ya se eliminó |
| 2 | `fn_info_contabilizacion_ordenes_carnaval(bigint[])` | Sobrecarga vieja. En newa ya se eliminó |
| 3 | `fn_historial_contabilizacion_operacion(bigint)` | Sobrecarga vieja. En newa ya se eliminó |
| 4 | `fn_desvincular_usuario_trabajador(bigint, bigint)` | La sustituye una función M01 |
| 5 | `fn_fdi_crear_liquidacion(... 10 parámetros)` | Firma vieja, newa tiene la de 11 |
| 6 | `fn_trg_bloquear_operaciones_usuario()` | Trigger puntual de main |
| 7 | `match_ai_kb(extensions.vector, integer, double precision)` | Es la misma función, distinto esquema del tipo |

## 1 a 3. Contabilización (3 sobrecargas viejas)

En main conviven las dos firmas de cada función (la vieja y la de `p_id_tienda`). Las 6 tienen `EXECUTE`
para `PUBLIC` y `anon`.

Dónde se usan:

| Archivo | Uso |
|---|---|
| `ventiq_admin_app/lib/services/inventory_service.dart:429` (`updateOperationAccountingStatus`) | Llama `fn_actualizar_operacion_contabilizada` con solo `p_id_operacion` y `p_contabilizada`. Esto resuelve a la sobrecarga de 2 parámetros. |
| `ventiq_admin_app/lib/services/carnaval_service.dart:2517` (`getCarnavalOrdersAccountingInfo`) | `fn_info_contabilizacion_ordenes_carnaval`. Manda `p_id_tienda` solo si hay `ventiqStoreId`; si no, usa la sobrecarga de 1 parámetro. |
| `ventiq_admin_app/lib/services/carnaval_service.dart:2537` (`getOperationAccountingHistory`) | `fn_historial_contabilizacion_operacion`, igual. |
| `ventiq_admin_app/lib/services/carnaval_service.dart:2562` (`updateCarnavalOrderAccountingStatus`) | `fn_actualizar_operacion_contabilizada`, igual. |

Las sobrecargas viejas nacieron en `ventiq_admin_app/docs/migrations/fn_listar_operaciones_inventario_new_apertura_cierre.sql`
y `sql_updates/fix_contabilizacion_supervisor_uuid_typo.sql`. Las de `p_id_tienda` vienen de
`sql_updates/fix_fn_actualizar_operacion_contabilizada_tienda_actual.sql`, cuyo motivo es validar el permiso
contra la tienda actual y no contra una sola.

Estado: en newa ya se aplicó `sql_updates/newa_contabilizacion_firmas.sql`. Dejó una sola firma de cada función,
con `p_id_tienda DEFAULT NULL`, así que las llamadas con y sin `p_id_tienda` siguen funcionando, y sin `anon`.

Acción: al promover, ejecutar el mismo script en main. Las 3 sobrecargas viejas se pueden quitar porque el
cliente las cubre con la firma con `DEFAULT`. Tener las dos firmas a la vez en main también arriesga
ambigüedad de resolución en las llamadas con nombres de parámetros.

## 4. `fn_desvincular_usuario_trabajador(bigint, bigint)`

Dónde se usa: `ventiq_admin_app/lib/services/worker_service.dart:370` (`removeWorkerUser`). La app llama primero
a `fn_m01_personal_desvincular_usuario_trabajador` y, solo si no existe, a esta función. En main la de M01 no
existe todavía, así que main usa esta.

Qué hace en main (cuerpo vivo): `SECURITY INVOKER`, sin guarda de rol, `EXECUTE` para `anon`. Borra las filas de
rol (`app_dat_dueno`, gerente, supervisor, vendedor, almacenero, RH, auditor) y pone `uuid`, `id_roll` y
`user_mail` del trabajador en NULL. El `app_dat_dueno` lo añadió `sql_updates/rol_dueno.sql:389` con un `replace`
sobre la definición. El fuente base está en `ventiq_admin_app/lib/sql/desvincular_usuario_trabajador.sql`.

Diferencia con la sustituta M01 (según `docs/plan-multimoneda/m01_orden_aplicacion.md:117`): la de M01 quita el
`uuid` del trabajador y de sus filas de rol, y **no borra las filas de rol**. El comportamiento es distinto:
main elimina los roles, M01 los conserva.

Otras menciones: `docs/plan-multimoneda/m01_r0b_desvincular_usuario_propuesta.sql` y `tasks/plan_admin_multimoneda.md`
(confirma que no existe en newa).

Acción: no crearla en newa. Mantenerla en main mientras el cliente la use como respaldo. Retirarla cuando el
script 24 de M01 esté en main. Decidir antes si desvincular debe seguir borrando roles o conservarlos.

## 5. `fn_fdi_crear_liquidacion` de 10 parámetros

Dónde se usa: `ventiq_admin_app/lib/services/fondo_inversion_service.dart:263` (`crearLiquidacion`). Ese
cliente **manda siempre `p_repartir_igual`**, así que con la firma de 10 parámetros de main la llamada no
coincide con ninguna función. El cliente actual necesita la de 11.

Otras referencias: `ventiq_admin_app/lib/sql/fondo_inversion_schema.sql:620`, que hace
`DROP FUNCTION IF EXISTS` de esta firma de 10 y crea la de 11 (para no dejar dos firmas ambiguas);
`ventiq_admin_app/docs/fondo_inversion_plan.md:159` (documenta la de 10); y
`ventiq_admin_app/test/fdi_liquidacion_dialog_test.dart:87`.

Acción: llevar a main `fondo_inversion_schema.sql` junto con la columna `fdi_dat_liquidacion.repartir_igual`
y `fn_fdi_repartir_ganancia`. El `DROP` del script quita la firma de 10. Es el Task 4 de `tasks/plan_sync_newa_main.md`.

## 6. `fn_trg_bloquear_operaciones_usuario()`

Es una función de trigger. En main alimenta el trigger activo `trg_bloquear_operaciones_maria`: `CONSTRAINT TRIGGER`,
`AFTER INSERT` sobre `app_dat_operaciones`, `DEFERRABLE INITIALLY DEFERRED`.

Qué hace: si `NEW.uuid` es el de `maria@inventtia.com` (`f9c73481-89b9-4b98-8dd2-3aaa5330dac3`), relee la fila y
lanza `check_violation` si el tipo final es 4 (Ajuste Negativo) o 18 (Extracción). Va diferido para no bloquear
las transferencias, que se insertan como 18 y se reclasifican a 7 en la misma transacción.

Dónde se define: `sql_updates/restringir_extraccion_ajuste_negativo_maria.sql` ("Proyecto: Main"). Ningún código de las
apps la llama. Es solo del servidor.

Acción: dejarla en main y no copiarla a newa (la usuaria solo existe en main). Cuidar que la promoción no
sustituya ni borre esta función ni el trigger. Sigue abierta la decisión de si ese bloqueo debe permanecer.

## 7. `match_ai_kb(extensions.vector, integer, double precision)`

Dónde se usa: `supabase/functions/ai-assistant/index.ts:384`, con `admin.rpc('match_ai_kb', { query_embedding,
match_count: 6, min_similarity: 0.2 })`, para recuperar los fragmentos de la base de conocimiento del asistente.
No la llama ninguna app Flutter.

No es una función que falte. newa tiene `match_ai_kb(vector, integer, double precision)`: la misma función con
el tipo `vector` sin calificar. La diferencia es el esquema de la extensión `vector`: `extensions` en main.

Acción: nada. No copiar cuerpos entre los dos proyectos. En main tiene `EXECUTE` para `anon`; revisarlo al hacer el
repaso de permisos del asistente.
