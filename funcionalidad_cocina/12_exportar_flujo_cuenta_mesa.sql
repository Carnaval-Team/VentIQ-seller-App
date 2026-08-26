-- ============================================================================
-- 12 · Fase 2 · Exportar el flujo de cuenta de mesa (NO MODIFICA NADA)
-- ============================================================================
-- Proyecto Supabase: vsieeihstajlrdvpuooh
--
-- POR QUE ESTE ARCHIVO EXISTE
-- ---------------------------
-- La Fase 2 ("pedir != cobrar") cambia el momento en que se mueve el
-- inventario: hoy se descuenta al COBRAR (fn_registrar_venta_mesa), y debe
-- pasar a descontarse al PEDIR (fn_agregar_item_cuenta_mesa), dejando el cobro
-- como un acto puramente contable.
--
-- Eso toca la ruta mas delicada que queda: la cuenta abierta. Mismo criterio
-- que en Fase 0 y en el 11: NO se reemplaza una funcion sin leer antes su
-- definicion real en produccion.
--
-- LO QUE YA SE SABE (verificado contra produccion)
-- -----------------------------------------------
--   * app_dat_mesas          existe, tiene datos (tienda 11, "Mesa 1", zona Terraza)
--   * app_dat_mesa_cuenta_item existe, con estas columnas REALES:
--       id, id_cuenta, id_producto, id_variante, id_opcion_variante,
--       id_presentacion, id_ubicacion, cantidad, precio_unitario, precio_base,
--       id_metodo_pago, promotion_data (jsonb), inventory_data (jsonb),
--       notas, sku_producto, sku_ubicacion, created_at, updated_at
--   * NO existe app_dat_comanda ni app_dat_comanda_item -> hay que crearlas (2.1)
--   * La tabla de cabecera de cuenta NO se llama app_dat_mesa_cuenta ni
--     app_dat_cuenta_mesa (ambas dan PGRST205). Hay que descubrir su nombre
--     real: la consulta 12.1 lo resuelve.
--
-- Observacion importante sobre inventory_data
-- -------------------------------------------
-- El item ya guarda un jsonb inventory_data con id_producto / id_variante /
-- id_ubicacion / sku_producto / sku_ubicacion / id_presentacion. Es decir: la
-- cuenta abierta YA memoriza de donde saldria la mercancia. Si Fase 2 descuenta
-- al pedir, ese jsonb es el lugar natural donde registrar el movimiento ya
-- aplicado (y por tanto lo que el cobro NO debe repetir). Conviene mirar como
-- lo usa fn_registrar_venta_mesa antes de disenar la reserva.
--
-- COMO USARLO
-- -----------
-- Correr 12.1 a 12.5 y pasar los resultados. Con eso se escribe el 13 (schema
-- de comandas) y el 14 (logica de pedir/cobrar).
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 12.1 Descubrir las tablas reales del flujo de mesas
--
-- Lista toda tabla cuyo nombre suene a mesa/cuenta/comanda, con su conteo de
-- columnas. Asi se identifica la cabecera de cuenta sin adivinar el nombre.
-- ----------------------------------------------------------------------------
SELECT
    c.relname                                   AS tabla,
    (SELECT count(*) FROM pg_attribute a
      WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped) AS columnas,
    obj_description(c.oid)                      AS comentario
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public'
   AND c.relkind = 'r'
   AND (c.relname ILIKE '%mesa%'
        OR c.relname ILIKE '%cuenta%'
        OR c.relname ILIKE '%comanda%')
 ORDER BY c.relname;


-- ----------------------------------------------------------------------------
-- 12.2 Columnas de esas tablas
--
-- Necesario para saber que campos ya existen antes de proponer los nuevos de
-- 2.1 (origen_stock, id_cocina, id_comanda_item, estado_servicio).
-- ----------------------------------------------------------------------------
SELECT
    c.relname        AS tabla,
    a.attnum         AS pos,
    a.attname        AS columna,
    format_type(a.atttypid, a.atttypmod) AS tipo,
    a.attnotnull     AS not_null,
    pg_get_expr(d.adbin, d.adrelid)      AS default_
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
  LEFT JOIN pg_attrdef d ON d.adrelid = c.oid AND d.adnum = a.attnum
 WHERE n.nspname = 'public'
   AND c.relkind = 'r'
   AND (c.relname ILIKE '%mesa%'
        OR c.relname ILIKE '%cuenta%'
        OR c.relname ILIKE '%comanda%')
 ORDER BY c.relname, a.attnum;


-- ----------------------------------------------------------------------------
-- 12.3 Definicion real de las RPC de cuenta abierta
--
-- Son las que llama mesa_cuenta_service.dart. fn_agregar_item_cuenta_mesa es LA
-- funcion que Fase 2 tiene que cambiar (ahi se decide que pasa al pedir), y
-- fn_registrar_venta_mesa la que debe dejar de re-descontar.
-- ----------------------------------------------------------------------------
SELECT
    p.oid::regprocedure       AS firma,
    length(p.prosrc)          AS largo_cuerpo,
    pg_get_functiondef(p.oid) AS definicion
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN (
        'fn_agregar_item_cuenta_mesa',
        'fn_actualizar_item_cuenta_mesa',
        'fn_eliminar_item_cuenta_mesa'
   )
 ORDER BY p.proname;


-- ----------------------------------------------------------------------------
-- 12.4 Definicion del resto del ciclo de cuenta
--
-- Se exportan aparte para no devolver un solo resultado gigante. Interesa sobre
-- todo si alguna de estas TAMBIEN toca inventario: si el descuento pasa al
-- pedir, cualquier otra que descuente estaria duplicando.
-- ----------------------------------------------------------------------------
SELECT
    p.oid::regprocedure       AS firma,
    length(p.prosrc)          AS largo_cuerpo,
    (p.prosrc ILIKE '%app_dat_inventario_productos%') AS toca_inventario,
    (p.prosrc ILIKE '%fn_descontar%')                 AS descuenta_bom,
    pg_get_functiondef(p.oid) AS definicion
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN (
        'fn_abrir_cuenta_mesa',
        'fn_cerrar_cuenta_mesa',
        'fn_marcar_cuenta_cerrada',
        'fn_cancelar_cuenta_mesa'
   )
 ORDER BY p.proname;


-- ----------------------------------------------------------------------------
-- 12.5 Cualquier OTRA funcion del flujo de mesas que toque inventario
--
-- Red de seguridad: si existe una ruta de descuento que no esta en las listas
-- de arriba (un trigger, un wrapper offline, una variante _v2), aqui aparece.
-- Es el mismo tipo de sorpresa que fue fn_descontar_inventario_plato en el 11.
-- ----------------------------------------------------------------------------
SELECT
    p.oid::regprocedure AS firma,
    length(p.prosrc)    AS largo_cuerpo,
    (p.prosrc ILIKE '%app_dat_inventario_productos%') AS toca_inventario,
    (p.prosrc ILIKE '%app_dat_mesa_cuenta_item%')     AS toca_items_cuenta,
    (p.prosrc ILIKE '%fn_descontar%')                 AS descuenta_bom
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND (p.prosrc ILIKE '%app_dat_mesa_cuenta_item%'
        OR p.prosrc ILIKE '%cuenta_mesa%')
   AND p.proname NOT IN (
        'fn_agregar_item_cuenta_mesa',
        'fn_actualizar_item_cuenta_mesa',
        'fn_eliminar_item_cuenta_mesa',
        'fn_abrir_cuenta_mesa',
        'fn_cerrar_cuenta_mesa',
        'fn_marcar_cuenta_cerrada',
        'fn_cancelar_cuenta_mesa'
   )
 ORDER BY p.proname;


-- ----------------------------------------------------------------------------
-- 12.6 Triggers sobre las tablas de mesa/cuenta
--
-- Un trigger que descuente inventario al insertar un item cambiaria por
-- completo el diseno de la Fase 2. Mejor descartarlo ahora.
-- ----------------------------------------------------------------------------
SELECT
    c.relname   AS tabla,
    t.tgname    AS trigger_,
    p.proname   AS funcion,
    pg_get_triggerdef(t.oid) AS definicion
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_proc p ON p.oid = t.tgfoid
 WHERE NOT t.tgisinternal
   AND n.nspname = 'public'
   AND (c.relname ILIKE '%mesa%'
        OR c.relname ILIKE '%cuenta%'
        OR c.relname ILIKE '%comanda%')
 ORDER BY c.relname, t.tgname;
