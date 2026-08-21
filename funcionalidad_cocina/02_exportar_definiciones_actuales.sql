-- ============================================================================
-- 02 · Fase 0 · Exportar definiciones actuales (NO MODIFICA NADA)
-- ============================================================================
-- Proyecto Supabase: vsieeihstajlrdvpuooh
--
-- POR QUE ESTE PASO EXISTE
-- ------------------------
-- Los .sql que hay en la raiz del repo (registrarventa_ok.sql,
-- registrar_venta_mesa.sql, registrar_venta_reworked.sql,
-- ventiq_admin_app/lib/sql/registrar_venta.sql) son copias de trabajo y NO
-- coinciden entre si:
--
--   - registrar_venta_mesa.sql        -> si resuelve la ubicacion por el almacen
--                                        del TPV (tiene v_id_almacen).
--   - registrarventa_ok.sql           -> NO tiene v_id_almacen; toma id_ubicacion
--                                        del payload del cliente.
--   - lib/sql/registrar_venta.sql     -> igual que el anterior, sin almacen.
--
-- Reemplazar una funcion de produccion con una copia local desactualizada
-- borraria cambios que si esten aplicados en la base. Asi que primero se
-- exporta el codigo REAL y sobre ese se aplica el parche (archivo 03).
--
-- COMO USARLO
-- -----------
-- 1. Correr la consulta 2.1 en el SQL Editor.
-- 2. Copiar el resultado completo de la columna `definicion` de cada funcion.
-- 3. Pegarmelo (o guardarlo en funcionalidad_cocina/_dump_funciones_venta.sql).
-- 4. Con eso se escribe el 03 parcheando solo el bloque de ingredientes.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 2.1 Definicion completa de las funciones de venta que descuentan receta
-- ----------------------------------------------------------------------------
SELECT
    p.oid::regprocedure                        AS firma,
    pg_get_functiondef(p.oid)                  AS definicion
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN (
        'fn_registrar_venta',
        'fn_registrar_venta_mesa',
        'fn_registrar_venta_offline',
        'fn_obtener_ingredientes_recursivos'
   )
 ORDER BY p.proname, p.oid;


-- ----------------------------------------------------------------------------
-- 2.2 Que otras funciones descuentan receta y habria que revisar tambien
-- Busca cualquier funcion cuyo cuerpo llame a fn_obtener_ingredientes_recursivos.
-- Si aparece algo fuera de la lista de 2.1, tambien necesita el fix.
-- ----------------------------------------------------------------------------
SELECT
    p.oid::regprocedure AS firma,
    length(p.prosrc)    AS largo_cuerpo
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.prosrc ILIKE '%fn_obtener_ingredientes_recursivos%'
 ORDER BY p.proname;


-- ----------------------------------------------------------------------------
-- 2.3 Y cuales replican el patron roto directamente (sin llamar al helper)
-- El sintoma del bug: leer app_dat_inventario_productos filtrando solo por
-- id_producto y quedarse con la ultima fila global.
-- ----------------------------------------------------------------------------
SELECT
    p.oid::regprocedure AS firma
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.prosrc ILIKE '%app_dat_inventario_productos%'
   AND p.prosrc ILIKE '%id_ingrediente%'
 ORDER BY p.proname;


-- ============================================================================
-- 2.4 DIAGNOSTICO DE IMPACTO (opcional pero recomendado)
-- ============================================================================
-- Cuantos ingredientes tienen stock repartido en MAS DE UN almacen. Esos son
-- los que hoy pueden descontarse del almacen equivocado.
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
),
ingredientes AS (
    SELECT DISTINCT id_ingrediente FROM public.app_dat_producto_ingredientes
)
SELECT
    pr.id                              AS id_ingrediente,
    pr.denominacion                    AS ingrediente,
    COUNT(DISTINCT sv.id_almacen)      AS almacenes_con_stock,
    SUM(sv.cantidad_final)             AS stock_total,
    string_agg(DISTINCT sv.id_almacen::text, ', ' ORDER BY sv.id_almacen::text) AS almacenes
  FROM ingredientes i
  JOIN public.app_dat_producto pr ON pr.id = i.id_ingrediente
  JOIN stock_vigente sv ON sv.id_producto = i.id_ingrediente
 WHERE sv.cantidad_final > 0
 GROUP BY pr.id, pr.denominacion
HAVING COUNT(DISTINCT sv.id_almacen) > 1
 ORDER BY almacenes_con_stock DESC, stock_total DESC;


-- ----------------------------------------------------------------------------
-- 2.5 Ingredientes con stock repartido en varias UBICACIONES del mismo almacen
-- Estos son los que hoy dan "stock insuficiente" en falso, porque la logica
-- actual solo mira una ubicacion.
-- Caso verificado: producto 216 -> ubicaciones 37 (4.0) y 41 (1.0), almacen 12.
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
           ip.id_ubicacion,
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
    pr.id                            AS id_ingrediente,
    pr.denominacion                  AS ingrediente,
    sv.id_almacen,
    COUNT(*)                         AS ubicaciones_con_stock,
    SUM(sv.cantidad_final)           AS stock_total_almacen,
    MAX(sv.cantidad_final)           AS stock_mayor_ubicacion
  FROM stock_vigente sv
  JOIN public.app_dat_producto pr ON pr.id = sv.id_producto
 WHERE sv.cantidad_final > 0
   AND sv.id_producto IN (SELECT DISTINCT id_ingrediente FROM public.app_dat_producto_ingredientes)
 GROUP BY pr.id, pr.denominacion, sv.id_almacen
HAVING COUNT(*) > 1
 ORDER BY ubicaciones_con_stock DESC, stock_total_almacen DESC;
