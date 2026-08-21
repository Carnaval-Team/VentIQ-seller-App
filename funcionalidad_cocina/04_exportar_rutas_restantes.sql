-- ============================================================================
-- 04 · Fase 0 · Exportar las rutas de inventario que faltan (NO MODIFICA NADA)
-- ============================================================================
-- Proyecto Supabase: vsieeihstajlrdvpuooh
--
-- CONTEXTO
-- --------
-- El archivo 03 arregla las dos funciones de VENTA. Pero la consulta 2.2 mostro
-- que hay mas funciones que descuentan o devuelven materia prima con el mismo
-- patron roto (lookup global del ingrediente, una sola ubicacion, sin filtrar
-- almacen):
--
--   fn_actualizar_cantidad_producto_orden(bigint,numeric,uuid)   prosrc 9311
--   fn_agregar_producto_orden_pendiente(bigint,jsonb,uuid)       prosrc 9176
--   fn_eliminar_producto_orden(bigint,uuid)                      prosrc 5586
--
-- Son la edicion de ordenes pendientes (subir/bajar cantidad, agregar y quitar
-- productos de una orden ya creada). Viven en ventiq_app/supabase/pending_order_edit.sql.
--
-- POR QUE NO SE PARCHEAN JUNTO CON EL 03
-- --------------------------------------
-- Se comparo el largo del cuerpo local contra el de produccion:
--
--   fn_eliminar_producto_orden             local 5586 == prod 5586  -> IGUAL
--   fn_actualizar_cantidad_producto_orden  local 9298 vs prod 9311  -> +13 chars
--   fn_agregar_producto_orden_pendiente    local 9155 vs prod 9176  -> +21 chars
--
-- Dos de las tres tienen cambios en produccion que no estan en el repo. Mismo
-- criterio que en el 02: no se reemplaza una funcion con una copia local que ya
-- sabemos desactualizada.
--
-- Ademas la consulta 2.3 lista funciones que tocan inventario y mencionan
-- ingredientes SIN llamar al helper recursivo. Se exportan tambien para
-- descartar que reviertan stock de MP por su cuenta:
--
--   cambiar_estado_operacion(bigint,integer,uuid)
--   fn_registrar_cambio_estado_operacion(bigint,smallint,uuid)
--   fn_registrar_cambio_estado_operacion_mejorado(bigint,smallint,uuid)
--
-- (Las get_productos_* / get_categorias_* de 2.3 solo LEEN para calcular
-- disponibilidad; se revisan en la Fase 1 al montar el catalogo dual, no aqui.)
--
-- COMO USARLO
-- -----------
-- Correr 4.1 y pasar el resultado. Con las definiciones reales se escribe el 05.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 4.1 Definicion real de las rutas de edicion de orden pendiente
-- ----------------------------------------------------------------------------
SELECT
    p.oid::regprocedure       AS firma,
    pg_get_functiondef(p.oid) AS definicion
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN (
        'fn_actualizar_cantidad_producto_orden',
        'fn_agregar_producto_orden_pendiente',
        'fn_eliminar_producto_orden',
        '_fn_distribuir_pagos_orden'
   )
 ORDER BY p.proname;


-- ----------------------------------------------------------------------------
-- 4.2 Definicion de los cambios de estado (para descartar reversion de MP)
-- ----------------------------------------------------------------------------
SELECT
    p.oid::regprocedure       AS firma,
    pg_get_functiondef(p.oid) AS definicion
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN (
        'cambiar_estado_operacion',
        'fn_registrar_cambio_estado_operacion',
        'fn_registrar_cambio_estado_operacion_mejorado'
   )
 ORDER BY p.proname;


-- ----------------------------------------------------------------------------
-- 4.3 Confirmar que el 03 quedo aplicado correctamente
-- Correr DESPUES de aplicar el 03.
-- ----------------------------------------------------------------------------

-- (a) Las funciones de venta ya NO deben tener el patron roto -> 0 filas
SELECT p.oid::regprocedure AS aun_roto
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_registrar_venta', 'fn_registrar_venta_mesa')
   AND p.prosrc ILIKE '%v_inventario_ingrediente%';

-- (b) Y SI deben delegar en el helper -> 2 filas
SELECT p.oid::regprocedure AS delega_ok
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('fn_registrar_venta', 'fn_registrar_venta_mesa')
   AND p.prosrc ILIKE '%fn_descontar_ingredientes_elaborado%';

-- (c) Los helpers del 01 deben existir -> 4 filas
SELECT p.oid::regprocedure AS helper
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN (
        'fn_stock_producto_almacen_detalle',
        'fn_stock_producto_almacen',
        'fn_validar_ingredientes_elaborado',
        'fn_descontar_ingredientes_elaborado'
   )
 ORDER BY p.proname;

-- (d) El bloque de pago monto 0 debe seguir vivo en fn_registrar_venta -> 1 fila
SELECT p.oid::regprocedure AS conserva_pago_cero
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname = 'fn_registrar_venta'
   AND p.prosrc LIKE '%Venta mostrador - monto 0%';

-- (e) Las validaciones de mesa deben seguir vivas -> 1 fila
SELECT p.oid::regprocedure AS conserva_validacion_mesa
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname = 'fn_registrar_venta_mesa'
   AND p.prosrc LIKE '%MESA_WRONG_TIENDA%'
   AND p.prosrc LIKE '%MESA_NOT_FOUND%';


-- ----------------------------------------------------------------------------
-- 4.4 Prueba funcional del caso que antes fallaba en falso
-- harina de trigo (216) tiene 4.0 en la ubicacion 37 y 1.0 en la 41, ambas del
-- almacen 12. La logica vieja solo veia 4.0.
-- ----------------------------------------------------------------------------

-- Desglose por ubicacion: esperado 2 filas (37 y 41)
SELECT * FROM public.fn_stock_producto_almacen_detalle(216, 12);

-- Total en el almacen 12: esperado 5.0
SELECT public.fn_stock_producto_almacen(216, 12) AS total_almacen_12;

-- Mismo chequeo para azucar refino (217): esperado 103.0 (100.0 + 3.0)
SELECT public.fn_stock_producto_almacen(217, 12) AS azucar_refino_almacen_12;

-- Validacion completa del elaborado 219 (consume 40 g de 216 + 10 g de 218)
SELECT public.fn_validar_ingredientes_elaborado(219, 1, 12) AS validacion_plato_219;

-- Contraste: el mismo ingrediente visto SIN filtro de almacen.
-- Si estos numeros difieren del de arriba, ahi estaba la fuga de inventario.
SELECT public.fn_stock_producto_almacen(216, NULL) AS harina_todos_los_almacenes,
       public.fn_stock_producto_almacen(217, NULL) AS azucar_todos_los_almacenes;


-- ----------------------------------------------------------------------------
-- 4.5 Ingredientes en riesgo, con nombre de almacen
-- Version legible de la consulta 2.4, para saber que productos revisar despues
-- de aplicar el fix.
-- ----------------------------------------------------------------------------
WITH stock_vigente AS (
    SELECT DISTINCT ON (
               ip.id_producto,
               ip.id_ubicacion,
               COALESCE(ip.id_variante, 0),
               COALESCE(ip.id_opcion_variante, 0),
               COALESCE(ip.id_presentacion, 0)
           )
           ip.id_producto,
           la.id_almacen,
           ip.cantidad_final
      FROM public.app_dat_inventario_productos ip
      JOIN public.app_dat_layout_almacen la ON la.id = ip.id_ubicacion
     WHERE la.deleted_at IS NULL
     ORDER BY
           ip.id_producto,
           ip.id_ubicacion,
           COALESCE(ip.id_variante, 0),
           COALESCE(ip.id_opcion_variante, 0),
           COALESCE(ip.id_presentacion, 0),
           ip.id DESC
)
SELECT
    pr.denominacion                AS ingrediente,
    al.id                          AS id_almacen,
    al.denominacion                AS almacen,
    t.denominacion                 AS tienda,
    SUM(sv.cantidad_final)         AS stock
  FROM stock_vigente sv
  JOIN public.app_dat_producto pr ON pr.id = sv.id_producto
  JOIN public.app_dat_almacen  al ON al.id = sv.id_almacen
  LEFT JOIN public.app_dat_tienda t ON t.id = al.id_tienda
 WHERE sv.cantidad_final > 0
   AND sv.id_producto IN (
        SELECT DISTINCT id_ingrediente FROM public.app_dat_producto_ingredientes
   )
 GROUP BY pr.denominacion, al.id, al.denominacion, t.denominacion
 ORDER BY pr.denominacion, al.id;
