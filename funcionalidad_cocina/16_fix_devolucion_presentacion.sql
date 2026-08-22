-- ============================================================================
-- 16 · FIX · fn_devolver_ingredientes_elaborado nunca pudo ejecutarse
-- ============================================================================
-- Proyecto Supabase: vsieeihstajlrdvpuooh
--
-- EL BUG
-- ------
-- app_dat_inventario_productos.id_presentacion es NOT NULL (verificado:
-- attnotnull = true). El INSERT de fn_devolver_ingredientes_elaborado, aplicada
-- con el 05 en la Fase 0, omite esa columna:
--
--   INSERT INTO app_dat_inventario_productos (
--       id_producto, id_ubicacion, cantidad_inicial, cantidad_final,
--       sku_producto, sku_ubicacion, origen_cambio, id_extraccion, created_at
--   ) VALUES (...)
--          ^ falta id_presentacion
--
-- Consecuencia: la funcion falla SIEMPRE con
--   23502: null value in column "id_presentacion" violates not-null constraint
--
-- No es un caso borde, es el 100% de las llamadas. Se aplico en Fase 0 pero
-- nunca se ejecuto contra datos reales, asi que el fallo quedo latente hasta
-- correr la prueba del 14 (paso 10: cancelar item no servido y devolver la MP).
--
-- Mismo patron que el 15: SQL sintacticamente valido, semantica rota, invisible
-- hasta ejecutarlo. Validar con pglast no detecta ninguno de los dos.
--
-- POR QUE UN FIX POR REGEXP Y NO UN CREATE OR REPLACE COMPLETO
-- ------------------------------------------------------------
-- La funcion en produccion tiene logica que NO conviene reescribir a mano:
--
--   * una PRIMERA PASADA que valida que todos los ingredientes tengan ubicacion
--     destino ANTES de escribir nada (mismo criterio de "validar todo primero"
--     que el resto de los helpers de la Fase 0)
--   * usa el helper fn_ubicacion_destino_devolucion (no fn_ubicacion_devolucion)
--   * mensajes de error que resuelven la denominacion del producto
--
-- Reescribirla entera arriesga perder esa primera pasada. Se cambia solo el
-- INSERT, anadiendo la columna y un valor con tres niveles de respaldo:
--
--   1. presentacion de la ultima fila de ese producto EN ESA UBICACION
--   2. presentacion de cualquier fila de ese producto EN EL ALMACEN
--      (cubre devolver a una ubicacion nueva del mismo almacen)
--   3. primera presentacion definida del producto — el mismo criterio que usa
--      fn_registrar_venta cuando el cliente no manda presentacion
--
-- Al ser un COALESCE de subconsultas no hace falta declarar variables nuevas,
-- asi que el cambio es una sola sustitucion textual.
--
-- ORDEN DE APLICACION
-- -------------------
--   1. Correr 16.1 (diagnostico).
--   2. Aplicar 16.2.
--   3. Correr 16.3 y la prueba funcional.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 16.1 Diagnostico (NO MODIFICA NADA)
--
-- Esperado antes del fix:
--   id_presentacion_es_not_null = true
--   inserta_presentacion        = false   <- la causa
--   conserva_primera_pasada     = true    <- lo que hay que preservar
-- ----------------------------------------------------------------------------
SELECT
    (SELECT a.attnotnull FROM pg_attribute a
       JOIN pg_class c ON c.oid = a.attrelid
       JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relname = 'app_dat_inventario_productos'
        AND a.attname = 'id_presentacion'
    ) AS id_presentacion_es_not_null,
    (SELECT p.prosrc LIKE '%id_presentacion%' FROM pg_proc p
       JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'fn_devolver_ingredientes_elaborado'
    ) AS inserta_presentacion,
    (SELECT p.prosrc LIKE '%Primera pasada%' FROM pg_proc p
       JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'fn_devolver_ingredientes_elaborado'
    ) AS conserva_primera_pasada;


-- ----------------------------------------------------------------------------
-- 16.2 Anadir id_presentacion al INSERT
--
-- Sustitucion textual sobre pg_get_functiondef, exigiendo exactamente una
-- coincidencia. Si el cuerpo cambio, no toca nada y avisa.
-- ----------------------------------------------------------------------------
DO $do$
DECLARE
    v_def    text;
    v_nueva  text;
    v_ocurr  integer;
    v_cols   text := 'id_producto,' || chr(13) || chr(10)
                  || '            id_ubicacion,';
    v_vals   text := 'v_ing.id_ingrediente,' || chr(13) || chr(10)
                  || '            v_id_ubicacion,';
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_def
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'fn_devolver_ingredientes_elaborado';

    IF v_def IS NULL THEN
        RAISE EXCEPTION 'fn_devolver_ingredientes_elaborado no existe: aplicar primero el 05';
    END IF;

    IF v_def LIKE '%id_presentacion%' THEN
        RAISE NOTICE 'fn_devolver_ingredientes_elaborado ya inserta id_presentacion: no se toca';
        RETURN;
    END IF;

    -- Lista de columnas
    v_ocurr := (length(v_def) - length(replace(v_def, v_cols, ''))) / length(v_cols);
    IF v_ocurr <> 1 THEN
        RAISE EXCEPTION 'Se esperaba 1 lista de columnas, se encontraron %', v_ocurr;
    END IF;

    v_nueva := replace(
        v_def,
        v_cols,
        'id_producto,' || chr(13) || chr(10)
        || '            id_ubicacion,' || chr(13) || chr(10)
        || '            id_presentacion,'
    );

    -- Lista de valores
    v_ocurr := (length(v_nueva) - length(replace(v_nueva, v_vals, ''))) / length(v_vals);
    IF v_ocurr <> 1 THEN
        RAISE EXCEPTION 'Se esperaba 1 lista de valores, se encontraron %', v_ocurr;
    END IF;

    v_nueva := replace(
        v_nueva,
        v_vals,
        'v_ing.id_ingrediente,' || chr(13) || chr(10)
        || '            v_id_ubicacion,' || chr(13) || chr(10)
        -- Tres niveles de respaldo para una columna NOT NULL.
        || '            COALESCE(' || chr(13) || chr(10)
        || '                (SELECT ip2.id_presentacion' || chr(13) || chr(10)
        || '                   FROM public.app_dat_inventario_productos ip2' || chr(13) || chr(10)
        || '                  WHERE ip2.id_producto = v_ing.id_ingrediente' || chr(13) || chr(10)
        || '                    AND ip2.id_ubicacion = v_id_ubicacion' || chr(13) || chr(10)
        || '                    AND ip2.id_presentacion IS NOT NULL' || chr(13) || chr(10)
        || '                  ORDER BY ip2.id DESC LIMIT 1),' || chr(13) || chr(10)
        || '                (SELECT ip3.id_presentacion' || chr(13) || chr(10)
        || '                   FROM public.app_dat_inventario_productos ip3' || chr(13) || chr(10)
        || '                   JOIN public.app_dat_layout_almacen la3 ON la3.id = ip3.id_ubicacion' || chr(13) || chr(10)
        || '                  WHERE ip3.id_producto = v_ing.id_ingrediente' || chr(13) || chr(10)
        || '                    AND la3.id_almacen = p_id_almacen' || chr(13) || chr(10)
        || '                    AND ip3.id_presentacion IS NOT NULL' || chr(13) || chr(10)
        || '                  ORDER BY ip3.id DESC LIMIT 1),' || chr(13) || chr(10)
        || '                (SELECT pp.id' || chr(13) || chr(10)
        || '                   FROM public.app_dat_producto_presentacion pp' || chr(13) || chr(10)
        || '                  WHERE pp.id_producto = v_ing.id_ingrediente' || chr(13) || chr(10)
        || '                  ORDER BY pp.id ASC LIMIT 1)' || chr(13) || chr(10)
        || '            ),'
    );

    EXECUTE v_nueva;
    RAISE NOTICE 'fn_devolver_ingredientes_elaborado corregida';
END
$do$;


-- ----------------------------------------------------------------------------
-- 16.3 Verificacion
--
-- Esperado: inserta_presentacion = true, tiene_respaldo_presentacion = true,
--           conserva_primera_pasada = true (no se perdio la validacion previa)
-- ----------------------------------------------------------------------------
SELECT
    p.oid::regprocedure AS firma,
    (p.prosrc LIKE '%id_presentacion,%')                  AS inserta_presentacion,
    (p.prosrc LIKE '%app_dat_producto_presentacion%')     AS tiene_respaldo_presentacion,
    (p.prosrc LIKE '%Primera pasada%')                    AS conserva_primera_pasada,
    (p.prosrc LIKE '%fn_ubicacion_destino_devolucion%')   AS usa_helper_correcto
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname = 'fn_devolver_ingredientes_elaborado';


-- ----------------------------------------------------------------------------
-- PRUEBA FUNCIONAL (transaccion revertida)
--
-- Devolver la receta de una croqueta (216 x40 g + 218 x10 g) al almacen 12.
-- Presentaciones reales: harina 335, sal 338.
-- ----------------------------------------------------------------------------
/*
BEGIN;

    SELECT public.fn_stock_producto_almacen(216, 12) AS harina_antes,
           public.fn_stock_producto_almacen(218, 12) AS sal_antes;

    SELECT public.fn_devolver_ingredientes_elaborado(
        p_id_producto_elaborado := 219,
        p_cantidad              := 1,
        p_id_almacen            := 12
    ) AS devolucion;
    -- esperado: status success, lineas_afectadas 2

    SELECT public.fn_stock_producto_almacen(216, 12) AS harina_despues,
           public.fn_stock_producto_almacen(218, 12) AS sal_despues;
    -- esperado: harina +40, sal +10

    -- Las filas nuevas deben tener id_presentacion resuelto (335 / 338)
    SELECT id_producto, id_ubicacion, id_presentacion,
           cantidad_inicial, cantidad_final, origen_cambio
      FROM app_dat_inventario_productos
     WHERE id_producto IN (216, 218)
     ORDER BY id DESC LIMIT 2;

    -- Casos borde
    SELECT public.fn_devolver_ingredientes_elaborado(219, 0, 12)   AS cantidad_cero;
    SELECT public.fn_devolver_ingredientes_elaborado(219, 1, NULL) AS sin_almacen;

ROLLBACK;
*/
