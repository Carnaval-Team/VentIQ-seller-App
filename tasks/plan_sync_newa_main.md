# Plan: sincronizar newa con main

> Cómo y en qué orden aplicar esto en main sin romper a clientes sin actualizar: `tasks/plan_promocion_main.md` (nombres nuevos `_m01`, expansión → clientes → contrato).

## Overview

Igualar `qhprswhhfasrikhawjoz` (newa) y `vsieeihstajlrdvpuooh` (main) cuando se cierre el trabajo que está en curso. No se aplica ahora. No se copia un proyecto entero encima del otro: en cada diferencia manda la versión más nueva, y hay cambios en las dos direcciones.

Medido el 2026-11-14 leyendo `pg_proc`, tablas y políticas. 922 funciones públicas en main, 894 en newa. 72 comparten firma y tienen el cuerpo distinto.

Actualizado el 2026-11-19: 922 en main y 1005 en newa en `public` (887 y 970 sin las de extensiones); 880 comparten firma y **81** tienen el cuerpo distinto; 90 existen solo en newa y 7 solo en main. Clasificación: 21 newa más nueva, 42 sin cambio lógico, 16 main más nueva y 2 combinadas a mano. Detalle en `docs/plan-multimoneda/comparacion_funciones_newa_main.md`. newa usa `America/Havana` desde el 18/11, como main. Estado de cada tarea abajo, verificado por lectura de `prosrc` en las dos bases.

## Architecture Decisions

- El pase espera a que cierren moneda de producto, precio vigente y el resto del trabajo en curso. Hasta entonces este plan solo se actualiza.
- Cada objeto viaja en una sola dirección. Main no pisa lo que newa tiene más nuevo, y newa no pisa lo que main tiene más nuevo.
- Las 72 funciones con el mismo nombre y distinto cuerpo se revisan una a una. Un hash distinto no dice cuál lado va delante.
- `tasks/plan.md` sigue siendo el plan de fondo de caja. Este archivo no lo sustituye.
- La spec del TPV ya describe la regla más nueva que esa app usa: `p_ruta` en el descuento (main) y el RLS de configuración de tienda (newa). Ver `docs/specs/SPEC-ventiq-app.md`.

## Qué va de newa a main

1. RLS de `app_dat_configuracion_tienda`, hoy apagado y sin políticas en main. En newa hay RLS y `config_tienda_select`, `insert`, `update`, `delete`, con `fn_config_tienda_puede_leer`, `fn_config_tienda_puede_escribir` y `fn_config_tienda_exigir_lectura`.
2. `app_dat_producto_costo` y `app_dat_recepcion_producto_costo`, con RLS y políticas de lectura y escritura, más `trg_fn_recepcion_productos_costo_real`.
3. `fn_fdi_gasto` y la columna `fdi_dat_liquidacion.repartir_igual`, junto con la firma de `fn_fdi_crear_liquidacion` que recibe `p_repartir_igual`.

## Qué va de main a newa

1. `fn_descontar_venta_enrutada_v2` con el argumento `p_ruta`, y `lock_timeout = '3s'` en la venta v3. Si `p_ruta` ya trae éxito para el mismo producto, no se vuelve a resolver el origen. El script es `sql_updates/optimizar_venta_v3_ruta_y_lock_timeout.sql`: parchea `fn_registrar_venta_v3_impl` y `fn_registrar_venta_mesa_v3_impl` (la función pública es solo la envoltura de `fix_venta_rollback_parcial.sql`) y pone el límite de bloqueo en el `_impl` y en la envoltura. Aplicado en newa el 18/11. La primera corrida abortó porque el ancla se buscaba en la envoltura; la segunda, ya sobre los `_impl`, dejó `p_ruta` en el descuento y en los dos `_impl`, y `lock_timeout=3s` en `_impl` y envolturas. `usa_p_ruta = false` en las envolturas es lo correcto.
2. La columna `app_dat_configuracion_tienda.reporte_tpvs_modo_turno`.
3. Tablas de aviso de agotado WAPI (`app_wapi_agotado_config`, `app_wapi_agotado_destinatario`, `app_wapi_agotado_estado`, `app_wapi_agotado_log`) y sus funciones (`fn_wapi_agotado_check`, `fn_wapi_agotado_stock_total`).
4. Referidos: `referral_capture_config`, `referral_user_attributions`, `referral_visits` y las funciones `fn_referral_*`.

## Task List

### Phase 1: Cerrar el trabajo en curso

- [ ] Task 1: Confirmar que moneda de producto, precio vigente y el resto en curso están cerrados en el código y en las specs de TPV y admin
  - Acceptance: `docs/specs/SPEC-ventiq-app.md` y la spec de admin citan el comportamiento cerrado, no el de `tasks/SPEC-product-currency-*` como trabajo abierto
  - Verify: lectura de ambas specs y de las RPC de pago en main
  - Files: `docs/specs/SPEC-ventiq-app.md`, spec de admin cuando exista

### Checkpoint: se puede empezar el pase

- [ ] No queda un cambio de esquema a medias entre los dos proyectos para el trabajo que este plan espera

### Phase 2: Newa hacia main

- [ ] Task 2: Llevar a main las tres funciones de acceso a configuración de tienda y activar RLS con las cuatro políticas de newa
  - Acceptance: un vendedor de la tienda sigue leyendo `app_dat_configuracion_tienda`; un usuario de otra tienda no; dueño y gerente escriben
  - Verify: `SELECT` con un JWT de vendedor de la tienda y con uno ajeno, en una transacción de prueba que se revierta
  - Files: script SQL nuevo en `sql_updates/`, copiado del cuerpo desplegado en newa

- [ ] Task 3: Crear en main las tablas de costo de producto y de recepción, su RLS y el trigger de `costo_real`
  - Acceptance: las dos tablas existen con RLS y políticas; una recepción sin `costo_real` lo calcula como en newa
  - Verify: comparar columnas y políticas con newa; insert de prueba revertido
  - Files: script SQL nuevo en `sql_updates/`

- [ ] Task 4: Llevar `fn_fdi_gasto`, la columna `repartir_igual` y la firma nueva de `fn_fdi_crear_liquidacion`
  - Acceptance: main acepta `p_repartir_igual` y registra un gasto de fondo con las mismas validaciones que newa
  - Verify: firma en `pg_proc` de main igual a la de newa; un gasto de monto 0 sigue fallando
  - Files: script SQL nuevo en `sql_updates/`

### Checkpoint: main tiene lo que newa tenía de más

- [ ] Las tres piezas de la fase 2 existen en main y un vendedor de prueba sigue leyendo la config de su tienda

### Phase 3: Main hacia newa

- [x] Task 5: Correr en newa `sql_updates/optimizar_venta_v3_ruta_y_lock_timeout.sql`
  - Acceptance: `fn_descontar_venta_enrutada_v2` acepta `p_ruta` y, si no viene, resuelve el origen; `fn_registrar_venta_v3_impl` y `fn_registrar_venta_mesa_v3_impl` pasan `p_ruta := v_ruta`; esas dos y sus envolturas públicas tienen `lock_timeout = 3s`
  - Verify: la consulta final del script muestra `usa_p_ruta` en el descuento y en los `_impl`, y `proconfig` con `lock_timeout=3s` en `_impl` y envoltura. Una venta de prueba en newa descuenta una línea
  - Files: `sql_updates/optimizar_venta_v3_ruta_y_lock_timeout.sql`
  - La venta v1, la preorden, el cierre y el ajuste no resuelven la ruta antes, así que no se les agrega una consulta. El pedido de mesa y el `lock_timeout` de las cuatro funciones M01 están en la tarea 5b

- [x] Task 5b: Correr en newa `sql_updates/m01_mesa_ruta_y_lock_timeout.sql`
  - Acceptance: `fn_m01_pedir_item_mesa_v1` pasa `p_ruta := v_origen` al descuento; `fn_m01_registrar_venta_v1`, `fn_m01_pedir_item_mesa_v1`, `fn_m01_finalizar_cuenta_v1` y `fn_m01_ajustar_linea_v1` tienen `lock_timeout=3s`. Las otras tres no ganan una llamada nueva a `fn_resolver_origen_venta`
  - Verify: la consulta final del script muestra `pasa_ruta` solo en el pedido de mesa y `proconfig` con `lock_timeout=3s` en las cuatro
  - Files: `sql_updates/m01_mesa_ruta_y_lock_timeout.sql`

- [x] Task 6b: Correr en newa `sql_updates/newa_contabilizacion_firmas.sql`
  - Acceptance: una sola firma de `fn_actualizar_operacion_contabilizada(bigint, boolean, bigint)`, y una sola de 2 parámetros en info e historial. anon sin EXECUTE
  - Verify: la consulta final del script devuelve 3 filas
  - Files: `sql_updates/newa_contabilizacion_firmas.sql`

- [x] Task 6: Añadir en newa `reporte_tpvs_modo_turno` y las tablas y funciones de WAPI agotado y de referidos que están en main
  - Acceptance: newa tiene la columna y los cuatro objetos `app_wapi_agotado_*` más las tres tablas `referral_*`
  - Verify: lista de relaciones de `pg_class` en newa contiene esos nombres
  - Files: script SQL tomado del esquema de main

### Checkpoint: newa tiene lo que main tenía de más

- [ ] Firma de descuento, columna de reporte y tablas de WAPI y referidos coinciden con main

### Phase 4: Cuerpos que no coinciden

- [~] Task 7 y 8 (decididas el 19/11/2026; ver `docs/plan-multimoneda/comparacion_funciones_newa_main.md` y `analisis_8_funciones_pendientes.md`). Estado verificado el 19/11 comparando `prosrc` en newa y en main:
  - [x] Newa: `sql_updates/newa_traer_funciones_main.sql` aplicado (índice parcial `idx_inv_prod_lote_producto` y 4 cuerpos con el mismo hash que main: `8734944d`, `1f2ef38a`, `8005bbfa`, `f6f60db6`). En main ya existía el índice
  - [x] Newa: `sql_updates/fix_reporte_ventas_por_turno_sin_cierre.sql` aplicado (`op_siguiente_apertura` presente). [ ] Main pendiente
  - [x] Newa: `sql_updates/fix_cambio_estado_operacion_mejorado_recepcion.sql` aplicado (`RECEPCION_INVENTARIO_USADO` presente). [ ] Main pendiente, y publicar Admin con el aviso de recepción solo después
  - [x] Newa: `sql_updates/fix_listar_ordenes_tipo_pago.sql` efectivo (comprobado el 20/11: `fn_listar_ordenes` ya no contiene `'tipo_paago'`). Main ya emite `'tipo_pago'`
  - [ ] Llevar a main las 21 funciones "newa más nueva"
  - [x] Newa: traídas las otras 12 de main con `sql_updates/newa_traer_12_funciones_main.sql` (20/11). Las 8 de catálogo (`buscar_producto_por_codigo_barras_v3` y las 7 `get_productos_completos_by_tienda_*`) solo diferían en `fecha_desde DESC` → `id DESC` y se parchearon sobre la definición viva; `fn_check_update`, `fn_listar_motivos_extraccion`, `fn_update_carnaval_product_prices` y `sync_price_to_carnaval` se copiaron enteras. Las 12 quedan con el mismo `md5(prosrc)` que main (el script lo comprueba y aborta si no) y `fn_check_update` sin `EXECUTE` a PUBLIC, igual que main
  - Contrato estático de los scripts: `ventiq_admin_app/test/sync_newa_main_sql_contract_test.dart` (15 casos, pasan). No sustituye correrlos en PostgreSQL
- Texto original de la tarea 7 (superado por lo anterior): Revisar las funciones que el TPV llama y cuyo `md5(prosrc)` difiere, y quedarse con el cuerpo más nuevo de cada una
  - Acceptance: cada función de la lista queda anotada con el lado que manda y, si hace falta, aplicada al otro lado
  - Verify: `md5(prosrc)` igual en los dos proyectos para las que se decidieron
  - Files: lista en `tasks/todo_sync_newa_main.md`
  - Lista inicial: `fn_registrar_venta_v3_impl`, `fn_registrar_venta_mesa_v3_impl`, `fn_registrar_venta_offline_v4`, `fn_registrar_pago_venta`, `fn_registrar_pago_venta_v2`, `fn_registrar_pago_venta_v3`, `fn_pedir_item_cuenta_v2`, `fn_cancelar_item_pedido_v2`, `fn_actualizar_cantidad_producto_orden_v2`, `fn_agregar_producto_orden_pendiente_v2`, `fn_eliminar_producto_orden_v2`, `fn_cerrar_turno_tpv_monedas`, `fn_cerrar_turno_offline_monedas`, `fn_apertura_turno_offline_monedas`, `registrar_apertura_turno_monedas`, `registrar_egreso_parcial_v3`, `fn_registrar_egreso_offline_v2`, `fn_resumen_diario_cierre_v4`, `fn_resumen_turno_kpi_v2`, `fn_resumen_turno_por_id_v2`, `fn_listar_ordenes`, `fn_stock_producto_almacen_detalle`, `fn_obtener_licencia_firmada`, `fn_tasa_cambio`, `get_detalle_producto`, `sync_bundle`, `buscar_producto_por_codigo_barras_v3`

- [ ] Task 8: Revisar el resto de las 72 firmas con cuerpo distinto que no usa el TPV
  - Acceptance: cada una tiene lado ganador o queda explícitamente fuera de este pase
  - Verify: no queda una función del TPV en la lista sin decisión
  - Files: el mismo todo

### Checkpoint: los dos proyectos coinciden en lo decidido

- [ ] Un inventario de firmas del TPV devuelve el mismo `md5(prosrc)` en main y en newa
- [ ] En main: contabilización con una sola firma por función (con `p_id_tienda DEFAULT NULL`) y sin EXECUTE para `anon`; `fn_fdi_crear_liquidacion` solo con la firma de 11 parámetros; `trg_bloquear_operaciones_maria` intacto; `fn_desvincular_usuario_trabajador` sustituida por la de M01 al promover M01
- [x] Baselines `md5` de los preflight M01 14, 17 y 56 regenerados contra main (2026-11-23)

## Risks

- Activar RLS de configuración en main puede dejar al TPV sin flags si la política no cubre al vendedor o si el cliente lee con un rol que newa no probó. La tarea 2 no cierra sin esa lectura.
- Reemplazar `fn_descontar_venta_enrutada_v2` en newa rompe cualquier llamada que no acepte el argumento nuevo. El script dropea la firma de 6 parámetros y deja la de 7 con `p_ruta` por defecto, así que una llamada posicional de 6 argumentos sigue resolviendo el origen. No dejar las dos firmas.
- Copiar referidos o WAPI desde main mete datos de producción si el script incluye `INSERT`. El pase es solo de esquema y funciones.
- Las 72 diferencias pueden incluir hotfixes de main que newa no tiene y experimentos de newa que no deben subir. Por eso la fase 4 es revisión, no un volcado.

## Fuera de este pase

- No se toca `tasks/plan.md` (fondo de caja).
- No se redespliegan edge functions en este plan.
- `match_ai_kb` difiere solo en el esquema del tipo `vector` (`extensions.vector` en main). No es una función pendiente.
