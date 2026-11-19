# Desincronización newa ↔ main (estado al 2026-11-18)

Comparación de solo lectura del esquema `public` de los dos proyectos: funciones (firma +
md5 del cuerpo), tablas y vistas (columnas, RLS, policies, triggers) y migraciones
registradas. No incluye los esquemas `auth` ni `storage`, ni otros esquemas, ni datos.

- **newa** (`qhprswhhfasrikhawjoz`): multimoneda + M01. Lo usa el build debug.
  `TimeZone = UTC`.
- **main**: producción. Lo usa el build release. `TimeZone = America/Havana`.

> La promoción de multimoneda a main **no es solo aplicar lo de newa**. Main tiene
> trabajo de producción que newa no tiene (secciones 3 y 4). Si se copian los cuerpos de
> newa encima, ese trabajo se pierde. Además, los preflight de los scripts M01 validan md5
> **de newa** y fallan en main.

## 1. Resumen

| | newa | main |
|---|---|---|
| Funciones propias (sin extensiones) | 942 | ~887 |
| Funciones solo en este proyecto | **91** (79 `fn_m01_*`) | **36** |
| Funciones en ambos con cuerpo distinto | **86** | |
| Tablas/vistas solo en este proyecto | **9** | **7** |
| Tablas en ambos con diferencias | **31** | |
| Migraciones registradas solo aquí | **12** | **10** |

## 2. Lo que está en newa y falta en main (lo que hay que promover)

### 2.1 Migraciones registradas solo en newa

| Versión | Nombre |
|---|---|
| 20261104142943 | multimoneda_fase1_catalogo_monedas |
| 20261104145451 | multimoneda_fase1b_tasa_automatica |
| 20261104150223 | multimoneda_fase1c_refresco_no_bloqueante |
| 20261104150603 | multimoneda_fase1d_cron_tasas |
| 20261104151812 | multimoneda_fase2_monedas_por_tienda |
| 20261104153406 | multimoneda_fase3_1_pago_generico |
| 20261104154317 | multimoneda_fase3_1b_seed_tienda_monedas |
| 20261104154912 | multimoneda_fase3_1c_v1_v2_rechazan_monedas_nuevas |
| 20261116145808 | tarifa_sc_base_1500_120km (Muévete) |
| 20261116152036 | 054_tarifa_sc_base_config_y_matching (Muévete) |
| 20261117185311 | m01_alta_tienda_usuario_nuevo |
| 20261117190814 | m01_alta_tienda_search_path |

> Main ya tiene las tablas `monedas` y `app_dat_tienda_moneda`, y funciones como
> `fn_seed_tienda_monedas`, `fn_tasa_automatica` o `fn_jsonb_monto`, pero con **otro
> cuerpo** y sin esas migraciones registradas. Alguien aplicó a mano una versión
> anterior de las fases 1–3 en main. Antes de correr las migraciones hay que diferenciar
> cuerpo por cuerpo (sección 5).

La mayoría de los scripts M01 (`m01_orden_aplicacion.md`, filas 1–56) **no están
registrados como migración** en ningún proyecto: en newa se corrieron a mano en el SQL
Editor. Ninguno está en main.

### 2.2 Tablas solo en newa

| Tabla | Origen |
|---|---|
| `app_dat_politica_moneda_revision`, `app_dat_politica_moneda_constancia` | M01 25–26 (MC-006/007) |
| `app_dat_pago_aplicacion` | M01 33 (MC-023) |
| `app_dat_ajuste_linea_v1` | M01 44 (MC-044) |
| `app_dat_obligacion_linea_v1` | M01 43 (CxC v1) |
| `app_dat_mesa_v1_idempotencia`, `app_dat_mesa_linea_v1_historial` | M01 40 (MC-039) |
| `app_dat_producto_costo`, `app_dat_recepcion_producto_costo` | Costo real de recepción (trigger `trg_recepcion_productos_costo_real`). **No figura en la spec M01**: verificar su script |

### 2.3 Columnas solo en newa

| Tabla | Columnas | Origen |
|---|---|---|
| `app_dat_extraccion_productos` | `version_monetaria`, `moneda_venta`, `precio_unitario_nativo`, `precio_unitario_neto_nativo`, `importe_bruto_nativo`, `importe_neto_nativo`, `importe_bruto_cup_equivalente`, `importe_neto_cup_equivalente`, `tasa_cambio_cup`, `descuento_manual_unitario_nativo`, `id_linea_cliente`, `id_medio_pago_seleccionado`, `seleccion_pendiente`, `snapshot_precio`, `snapshot_tasa`, `snapshot_descuentos` | M01 32 (MC-022) |
| `app_dat_mesa_cuenta_item` | `version_monetaria`, `moneda_venta`, `precio_unitario_nativo`, `importe_neto_nativo`, `importe_neto_cup_equivalente`, `tasa_cambio_cup`, `descuento_manual_unitario_nativo`, `id_linea_cliente`, `seleccion_pendiente`, `snapshot_precio`, `snapshot_tasa`, `snapshot_ajustes` | M01 40 |
| `app_dat_mesa_cuenta_abierta` | `version_monetaria`, `id_revision_politica`, `id_constancia_politica` | M01 40 |
| `app_dat_operacion_venta` | `version_monetaria`, `id_revision_politica`, `id_constancia_politica` | M01 26/35 |
| `app_dat_operacion_offline_idempotencia` | `m01_solicitud`, `m01_id_tienda` | M01 13 |
| `app_dat_configuracion_tienda` | `permitir_moneda_por_producto` | M01 25 |
| `app_dat_precio_tpv` | `precio_venta_usd` | M01 29 (MC-010) |
| `fdi_dat_liquidacion` | `repartir_igual` | FDI (no es M01) |

### 2.4 RLS y policies (endurecimiento M01, filas 1–24)

En newa, estas tablas tienen RLS **activado** y policies `m01_*`. En main están **sin
RLS**: `app_dat_cocina`, `app_dat_configuracion_tienda` (S01), `app_dat_jefe_cocina`,
`app_dat_operacion_offline_idempotencia`, `app_dat_precio_tpv`,
`app_dat_recursos_humanos`, `app_dat_supervisor`, `auditor`.

En estas, main conserva policies abiertas que newa reemplazó por `m01_*`:

| Tabla | Policies de main que M01 quita |
|---|---|
| `app_dat_almacen` | `almacne` |
| `app_dat_almacenero` | `almacenero` |
| `app_dat_gerente` | `geneente` |
| `app_dat_operaciones` | `Open access to operaciones`, `operaciones permitidas` |
| `app_dat_tienda` | `tienda policy` |
| `app_dat_tpv` | `Open access to tpv`, `all on tpv` |
| `app_dat_trabajadores` | `worker police select`, `all workers` |
| `app_dat_vendedor` | `select all`, `Open access to vendedor`, `all vednedor` |
| `seg_roll` | `seg_toll` |

`app_dat_dueno` tiene las mismas policies, pero con otra expresión (M01 R0a).

### 2.5 Triggers solo en newa

`m01_extraccion_v1_directa` (extracción) · `m01_venta_legacy_con_flag`,
`m01_venta_v1_pagada_directa`, `m01_venta_v1_uuid` (operacion_venta) ·
`m01_pago_v1_directo` (pago_venta) · `m01_politica_config_revision`,
`m01_politica_flag_solo_publicacion` (configuracion_tienda) ·
`m01_politica_moneda_revision_{ins,upd,del}` (tienda_moneda) ·
`trg_recepcion_productos_costo_real` (recepcion_productos).

### 2.6 Funciones solo en newa (no `fn_m01_*`)

`fn_alinear_apertura_turno_offline`, `fn_turno_alinear_fecha_apertura` (R33, fila 56) ·
`fn_config_tienda_puede_leer/escribir/exigir_lectura` (S01) ·
`fn_reporte_ventas_por_moneda_v2` (fila 55) · `reporte_ordenes_json_v2` (fila 54) ·
`fn_descontar_venta_enrutada_v2(…,boolean)` · `fn_fdi_gasto`,
`fn_fdi_crear_liquidacion(…,boolean)` (FDI) · `trg_fn_recepcion_productos_costo_real` ·
`fn_listar_entregas_por_fechas_usuario(timestamp, timestamp, uuid)` (**firma vieja**; ver
sección 3).

Más 79 `fn_m01_*` (wrappers de personal y roles, política de moneda, alta y cobro v1,
mesa v1, CxC v1, precio de TPV, idempotencia, anotaciones, foto, notificaciones).

## 3. Lo que está en main y falta en newa (producción que no hay que pisar)

### 3.1 Migraciones registradas solo en main

| Versión | Nombre |
|---|---|
| 20260926153611 | ai_assistant_kb_schema |
| 20260927090859 | fix_fn_listar_motivos_extraccion_permisos |
| 20260929112213 | carrito_historial_eliminaciones_y_triggers |
| 20260929112335 | orden_carnaval_marca_motivo_orden |
| 20260929114431 | carrito_bloqueos_escalado_y_notif |
| 20260929114653 | carrito_antiabuse_bloqueo_delete_side |
| 20260929124836 | carrito_notif_incluye_soporte |
| 20260929125125 | carrito_vista_soporte_y_desbloqueo |
| 20260929143311 | fix_inventario_resumen_v2_dedup_presentaciones |
| 20261012150148 | fix_precio_venta_order_by_id |

Las del carrito no crean tablas en `public` (probablemente van en otro esquema): no
salen en la comparación de tablas, pero hay que llevarlas a newa.

### 3.2 Tablas solo en main

`app_wapi_agotado_config`, `app_wapi_agotado_destinatario`, `app_wapi_agotado_estado`,
`app_wapi_agotado_log` (aviso de producto agotado por WhatsApp) · `referral_capture_config`,
`referral_user_attributions`, `referral_visits` (migración
`supabase/migrations/20261112150000_referral_capture_auto_attribution.sql`, que vino de
main en el merge).

### 3.3 Columnas, policies y triggers solo en main

| Tabla | Solo en main |
|---|---|
| `app_dat_configuracion_tienda` | columna `reporte_tpvs_modo_turno` |
| `app_versiones` | columnas `titulo`, `novedades`, `url_descarga`; policy `app_versiones_select_authenticated` (newa tiene otra: `app_versiones_authenticated_all`) |
| `app_wapi_sesion` | `watchdog_enabled`, `recovery_attempts`, `last_recovery_at`, `last_error_code`, `last_error_message`, `raw_status` |
| `app_wapi_programacion` | `solo_disponibles` |
| `app_dat_inventario_productos` | trigger `trg_wapi_agotado_notificar` |
| `app_dat_precio_general_tienda` | trigger `trg_recalc_carnaval_on_store_pricing` |
| `app_dat_operaciones` | trigger `trg_bloquear_operaciones_maria` (bloqueo puntual de un usuario: revisar si debe seguir) |

### 3.4 Funciones solo en main (36)

| Tema | Funciones |
|---|---|
| WhatsApp (sesión y agotados) | `fn_wapi_session_watchdog()`, `fn_wapi_session_recovery_report(bigint)`, `fn_wapi_agotado_stock_total(bigint,bigint)`, `fn_wapi_agotado_check()` |
| Referidos | `fn_referral_request_ip()`, `fn_referral_ip_hash()`, `fn_referral_phone_norm(text)`, `fn_referral_phone_hash(text)`, `fn_referral_visit_register(…)`, `fn_referral_visit_attach_phone(text,text)`, `fn_referral_visits_purge(integer)` |
| Versiones de app | `fn_app_versiones(…)`, `fn_app_version_guardar(…)`, `fn_app_version_eliminar(integer)`, `fn_version_menor(text,text)` |
| Carnaval / precios | `fn_carnaval_precio_base_vigente(bigint)`, `rpc_recalc_carnaval_prices_for_store(bigint)`, `fn_trg_recalc_carnaval_on_store_pricing()`, `fn_fix_precio_venta_created_at_order(…)`, `fn_verify_precio_venta_duplicate_versions(…)`, `fn_cerrar_precios_venta_activos_duplicados(…)`, `fn_cancelar_orden_carnaval_v2(bigint,text)`, `fn_eliminar_order_detail_con_devolucion_v2(…)` |
| Contabilización | `fn_actualizar_operacion_contabilizada(bigint,boolean,bigint)`, `fn_info_contabilizacion_ordenes_carnaval(bigint[],bigint)`, `fn_historial_contabilizacion_operacion(bigint,bigint)` |
| Costos e inventario | `fn_corregir_costo_recepcion(bigint,numeric,timestamptz)` y su sobrecarga de 5 parámetros, `get_product_movements_v5(…)`, `fn_descontar_venta_enrutada_v2(…,boolean,jsonb)` |
| Reportes por turno | `fn_reporte_ventas_por_turno_vendedor(uuid,date,date,bigint)`, `fn_reporte_ventas_turno_vendedor(uuid,date,date,bigint)` |
| Egresos por turno | `fn_listar_entregas_por_fechas_usuario(timestamptz,timestamptz,uuid,bigint)`: la versión con `p_id_turno` que usa el admin (`egresos_por_turno_main.sql`). **newa tiene la firma vieja** `(timestamp, timestamp, uuid)` |
| Otros | `fn_trg_bloquear_operaciones_usuario()`, `fn_desvincular_usuario_trabajador(bigint,bigint)` (M01 24 la sustituye por `fn_m01_personal_desvincular_usuario_trabajador`), `fn_fdi_crear_liquidacion(…10 params)` (newa tiene la de 11) |

## 4. Funciones en ambos con cuerpo distinto (86)

Hay que decidir caso por caso cuál gana. Para cada una: comparar
`pg_get_functiondef` de los dos lados y el script de la spec que la toca. En la mayoría
gana newa (M01/multimoneda), pero en varias main tiene hotfixes de producción posteriores
al fork (desde el 24/09).

| Grupo | Funciones | Quién debería ganar |
|---|---|---|
| Turno offline y caja (M01 17 + R33) | `fn_apertura_turno_offline{,_usd,_monedas}`, `fn_cerrar_turno_offline{,_usd,_monedas}`, `fn_cerrar_turno_tpv_monedas`, `registrar_apertura_turno_monedas`, `fn_registrar_egreso_offline{,_v2}`, `registrar_egreso_parcial_v3`, `fn_pedir_item_cuenta_offline`, `fn_pedir_item_cuenta_v2`, `fn_cambiar_estado_comanda_item_offline` | newa (17 + 56). En main, mientras M01 no llegue, aplicar el hotfix S1–S5 del diagnóstico |
| Venta y pago offline (M01 14–16) | `fn_registrar_venta_offline_v4`, `fn_registrar_pago_venta{,_v2,_v3,_offline}`, `fn_registrar_cambio_estado_offline`, `fn_registrar_cambio_estado_operacion{,_mejorado}`, `fn_registrar_venta_v3_impl`, `fn_registrar_venta_mesa_v3_impl`, `fn_pago_venta_equivalente` | newa |
| Multimoneda (fases 1–5) | `fn_crear_moneda`, `fn_actualizar_moneda`, `fn_guardar_monedas_tienda`, `fn_guardar_denominaciones`, `fn_guardar_tasa_global`, `fn_tasa_automatica{,_estado}`, `fn_tasa_cambio`, `fn_tasas_ingerir`, `fn_tasas_refrescar`, `fn_seed_tienda_monedas`, `fn_sync_turno_moneda`, `fn_jsonb_monto`, `fn_moneda_consolidacion`, `fn_validar_moneda_forzada`, `fn_desglose_monedas_{turno,usuario}`, `fn_esperado_turno_por_moneda`, `fn_reporte_ventas_por_moneda` | newa |
| Reportes y cierres | `fn_reporte_ventas_por_turno{,_v2}`, `fn_reporte_ventas_con_proveedor_por_turno{,_v2}`, `fn_resumen_diario_cierre_v4`, `fn_resumen_turno_kpi_v2`, `fn_resumen_turno_por_id_v2`, `egresos_por_turno`, `fn_dashboard_carnaval_proveedor` | **Revisar**: main tiene el fix de egresos por turno (merge del 18/11) y newa el desglose por moneda. Combinar los dos |
| Órdenes pendientes y mesa | `fn_listar_ordenes`, `fn_agregar_producto_orden_pendiente_v2`, `fn_actualizar_cantidad_producto_orden_v2`, `fn_eliminar_producto_orden_v2`, `fn_cancelar_item_pedido_v2` | newa (M01 52), salvo hotfix de main: comparar |
| Catálogo y productos | `get_detalle_producto`, `get_detalles_productos_batch`, `get_productos_completos_by_tienda_*` (8 variantes), `buscar_producto_por_codigo_barras_v3`, `fn_stock_producto_almacen_detalle`, `fn_stock_saldos_presentacion`, `fn_subcategoria_general_especial` | **Revisar**: main tiene `get_detalle_producto_incluir_base_cero` y `fix_precio_venta_order_by_id`, y newa precio USD |
| Elaborados e inventario | `fn_devolver_ingredientes_elaborado_v2`, `fn_obtener_ingredientes_recursivos`, `fn_actualizar_precio_promedio_recepcion_v2`, `fn_listar_motivos_extraccion` | **Revisar**: main tiene `fix_fn_listar_motivos_extraccion_permisos` |
| Carnaval | `fn_update_carnaval_product_prices`, `sync_price_to_carnaval` | **Revisar**: main tiene el recálculo por tienda |
| Otros | `fn_check_update`, `fn_obtener_licencia_firmada`, `fn_fdi_repartir_ganancia`, `sync_bundle`, `match_ai_kb` | Revisar uno a uno (`match_ai_kb` viene de la migración de IA de main) |

## 5. Plan para sincronizar

**Paso 0. Llevar lo de main a newa** (para que newa sea un superconjunto de main y sus
baselines md5 sigan valiendo):
1. Aplicar en newa las 10 migraciones de la sección 3.1, en orden.
2. Crear en newa lo de 3.2–3.4 con **`sync_main_a_newa_generador.sql`**. Se ejecuta en
   main (solo lectura) y devuelve el script para newa: 9 tablas con RLS, policies,
   índices y GRANT; 11 columnas; 34 funciones con sus GRANT; la vista del carrito; 4
   triggers; y el cambio a la firma de egresos con `p_id_turno`. Probado en main el
   18/11: 137 KB. Quedan fuera, a mano: las 3 sobrecargas que chocan con newa, el
   bloqueo puntual de usuario y los cron jobs (ver la cabecera del generador).
3. `fn_descontar_venta_enrutada_v2(…, jsonb)` no se copia de main. En newa se aplica
   `sql_updates/optimizar_venta_v3_ruta_y_lock_timeout.sql`, que agrega `p_ruta` al
   descuento vivo, hace que `fn_registrar_venta_v3_impl` y
   `fn_registrar_venta_mesa_v3_impl` lo pasen, y pone `lock_timeout = 3s` en esos
   `_impl` y en las envolturas públicas. Aplicado en newa el 18/11: `p_ruta` quedó
   en el descuento y en los dos `_impl`; `lock_timeout=3s` en `_impl` y envolturas.
   La envoltura sigue sin `p_ruta` en el cuerpo, porque solo delega.
3b. `sql_updates/m01_mesa_ruta_y_lock_timeout.sql` hace que
   `fn_m01_pedir_item_mesa_v1` pase `p_ruta := v_origen` (la ruta de antes del
   INSERT; la comanda y el inventario dejan de poder divergir) y pone
   `lock_timeout = 3s` en `fn_m01_registrar_venta_v1`, `fn_m01_pedir_item_mesa_v1`,
   `fn_m01_finalizar_cuenta_v1` y `fn_m01_ajustar_linea_v1`. Aplicado en newa el
   18/11: `pasa_ruta` solo en el pedido de mesa; las cuatro conservan
   `search_path=pg_catalog` y tienen `lock_timeout=3s`. No se vuelve a correr
   `m01_r19` ni `m01_r24`. La venta v1, el cierre y el ajuste no resuelven la ruta
   antes, y el script no les agrega esa consulta.
3c. `sql_updates/newa_contabilizacion_firmas.sql` deja una sola firma por función.
   Aplicado en newa el 18/11: `fn_actualizar_operacion_contabilizada(bigint, boolean, bigint)`
   y las de 2 parámetros de `fn_info_contabilizacion_ordenes_carnaval` y
   `fn_historial_contabilizacion_operacion`. Quedan fuera anon. El guardar sigue
   siendo gerente o supervisor.
4. Para las funciones de la sección 4 marcadas **Revisar**: combinar a mano el hotfix de
   main con el cuerpo de newa, aplicarlo en newa y **regenerar los md5** de los preflight
   de los scripts M01 que las tocan.
5. Correr los verificadores M01 en newa: nada debe romperse.

**Paso 1. Congelar** cambios manuales en main durante la ventana (o registrarlos y
llevarlos a newa antes de promover).

**Paso 2. Promover a main**, en el orden de `m01_orden_aplicacion.md`:
1. Migraciones multimoneda fase 1–3.1c. Antes, diferenciar contra las versiones a mano
   que ya hay en main.
2. S01 (configuración de tienda con RLS) y M01 filas 1–56, con preflight con
   **baselines de main**. Los de newa no valen.
3. Las dos migraciones `m01_alta_tienda_*` y la fila 56 (R33).
4. Verificadores de cada corte en main.
5. Zona horaria: newa quedó en `America/Havana` el 18/11, igual que main. El cliente
   sigue enviando fechas UTC con `Z`. Los timestamps offline guardados sin offset
   mientras newa era UTC siguen 5 horas adelantados.

**Paso 3. Hotfix de turnos en main**, solo si M01 tarda en llegar: S1–S6 de
`docs/issues/ventas_offline_desaparecen_tras_sync.md`, más la reparación de los turnos
3522 y 3533. Si se aplica, el paso 2 tiene que partir de esos cuerpos.

**Paso 4. Clientes.** Release de `ventiq_app` y `ventiq_admin_app` desde `multimoneda`
**después** del paso 2. El admin ya hace fallback cuando falta `fn_m01_*`, pero el TPV
espera R33 y las RPC v1.

## 6. Cómo repetir esta comparación

Huella por grupos (ejecutar en los dos proyectos y comparar):

```sql
with f as (
  select left(md5(p.proname),2) b, p.oid::regprocedure::text || md5(p.prosrc) s
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind in ('f','p')
    and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e'))
select string_agg(b || '=' || h, ',' order by b)
from (select b, left(md5(string_agg(s, '|' order by s)),4) h from f group by b) x;
```

Los grupos con huella distinta se bajan al detalle por función
(`left(md5(oid::regprocedure::text),6) = left(md5(prosrc),4)`). El mismo método sirve
para tablas: huella por tabla de columnas + RLS + policies + triggers.
