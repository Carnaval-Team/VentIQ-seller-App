-- ============================================================================
-- 04 · Fase 0 · Guardas de los triggers de app_dat_inventario_productos
-- ============================================================================
-- Plan: docs/PLAN_PRESENTACIONES_INVENTARIO.md  (Fase 0, requisito de seguridad)
-- Proyecto Supabase: vsieeihstajlrdvpuooh
-- Aplicar en: SQL Editor del dashboard. Idempotente (CREATE OR REPLACE).
-- Depende de: 01 y 02. Aplicar ANTES de usar el 03 en produccion.
--
-- POR QUE ESTE ARCHIVO EXISTE
-- ---------------------------
-- app_dat_inventario_productos tiene tres triggers vivos (verificado por MCP):
--
--   trg_sincronizar_stock_inventario   AFTER INSERT        -> fn_sincronizar_stock_producto
--   trg_notificar_producto_disponible  AFTER INSERT/UPDATE -> fn_notificar_producto_disponible
--   trg_notificar_producto_agotado     AFTER UPDATE        -> fn_notificar_producto_agotado
--
-- Los helpers de la Fase 0 escriben en esa tabla, asi que disparan los tres.
-- Dos de ellos hacen algo INCORRECTO con stock mixto. El tercero
-- (producto_agotado) es AFTER UPDATE y la Fase 0 solo hace INSERT, por lo que
-- no se toca.
--
--
-- BUG 1 · fn_sincronizar_stock_producto escribe cantidad_final CRUDA
-- -----------------------------------------------------------------
-- Codigo actual (produccion):
--
--     UPDATE carnavalapp."Productos"
--        SET stock = GREATEST(0, NEW.cantidad_final)
--      WHERE id = v_producto_record.id_vendedor_app;
--
-- Toma el cantidad_final de la fila insertada, sin mirar la presentacion. Con
-- stock mixto eso publica el numero equivocado en el marketplace:
--
--   ingresa 4 Cajas de 24  -> el marketplace dice "stock 4"   (son 96 unidades)
--   abre 1 Caja            -> pata de salida deja 3 Cajas  -> "stock 3"
--                          -> pata de entrada deja 24 U    -> "stock 24"
--   el ultimo INSERT gana, asi que el numero publicado es arbitrario.
--
-- Arreglo: publicar el EQUIVALENTE EN UNIDADES BASE de esa ubicacion, que es lo
-- que el comprador entiende por "hay 96". Para un producto de una sola
-- presentacion el resultado es identico al de hoy (factor_rel = 1 y la suma de
-- la ubicacion es esa misma fila), asi que no hay cambio de comportamiento para
-- el 99.8 % del catalogo.
--
-- Alcance real medido: 1.235 productos estan sincronizados con carnavalapp y
-- solo 2 de ellos tienen mas de una presentacion. El arreglo es preventivo,
-- pero sin el la Fase 2 rompe el marketplace en cuanto alguien reciba cajas.
--
--
-- BUG 2 · fn_notificar_producto_disponible avisa por una conversion
-- ----------------------------------------------------------------
-- Su condicion de disparo es "antes 0, ahora > 0". La pata de ENTRADA de una
-- conversion cumple eso siempre (las unidades sueltas nacen en 0), asi que
-- abrir una caja mandaria un push "ya esta disponible otra vez" a todos los
-- suscriptores, aunque el producto nunca dejo de estar disponible: solo cambio
-- de empaque.
--
-- Arreglo: ignorar las filas con id_conversion IS NOT NULL. El aviso legitimo
-- sigue saliendo cuando entra mercancia de verdad (recepcion, devolucion).
--
--
-- LO QUE NO SE CAMBIA
-- -------------------
-- Se conservan tal cual: el early-return de origen_cambio = 2 con
-- id_proveedor IS NOT NULL, el filtro por relation_products_carnaval.id_ubicacion,
-- el GREATEST(0, ...), el RETURN NEW en todos los caminos y el bloque EXCEPTION
-- de la funcion de notificacion. Este archivo agrega guardas, no reescribe
-- reglas de negocio.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 4.1 fn_sincronizar_stock_producto
-- Se agrega:
--   a) early-return si la fila es una pata de conversion (no cambia el total)
--   b) el stock publicado es el equivalente base de la ubicacion, no la
--      cantidad cruda de la fila
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_sincronizar_stock_producto()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_producto_record    RECORD;
    v_diferencia         NUMERIC;
    v_stock_actual       NUMERIC;
    v_ubicacion_esperada BIGINT;
    v_stock_nuevo        NUMERIC;
BEGIN
    -- NUEVO (Fase 0 presentaciones): una conversion de presentacion no cambia
    -- la cantidad total del producto, solo como esta empaquetada. Publicar algo
    -- en el marketplace por esto siempre da un numero equivocado.
    IF NEW.id_conversion IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- NO PROCESAR si el cambio proviene de una extracción (origen_cambio = 2)
    -- porque ya fue manejado por el trigger de sincronización de órdenes
    IF NEW.origen_cambio = 2 and  NEW.id_proveedor is not null THEN
        RAISE NOTICE 'Cambio de inventario ignorado (origen_cambio = 2 - extracción ya sincronizada)';
        RETURN NEW;
    END IF;

    -- Obtener información del producto incluyendo id_vendedor_app
    SELECT id, id_vendedor_app INTO v_producto_record
    FROM public.app_dat_producto
    WHERE id = NEW.id_producto;

    -- Solo procesar si el producto existe y tiene id_vendedor_app
    IF v_producto_record IS NULL OR v_producto_record.id_vendedor_app IS NULL THEN
        RETURN NEW;
    END IF;

    -- Verificar ubicación específica en relation_products_carnaval
    SELECT id_ubicacion INTO v_ubicacion_esperada
    FROM public.relation_products_carnaval
    WHERE id_producto = NEW.id_producto
      AND id_producto_carnaval = v_producto_record.id_vendedor_app
    LIMIT 1;

    -- Si existe una ubicación esperada y no coincide con la del cambio, no sincronizar
    IF v_ubicacion_esperada IS NOT NULL AND NEW.id_ubicacion != v_ubicacion_esperada THEN
        RAISE NOTICE 'Cambio de inventario ignorado: la ubicación % no coincide con la ubicación esperada % para el producto carnaval %',
            NEW.id_ubicacion, v_ubicacion_esperada, v_producto_record.id_vendedor_app;
        RETURN NEW;
    END IF;

    -- Obtener stock actual de carnavalapp.Productos
    SELECT stock INTO v_stock_actual
    FROM carnavalapp."Productos"
    WHERE id = v_producto_record.id_vendedor_app;

    -- Si no existe el producto en carnavalapp, no hacer nada
    IF v_stock_actual IS NULL THEN
        RAISE NOTICE 'Producto % no encontrado en carnavalapp.Productos', v_producto_record.id_vendedor_app;
        RETURN NEW;
    END IF;

    v_diferencia := NEW.cantidad_final - NEW.cantidad_inicial;

    -- CAMBIADO (Fase 0 presentaciones): antes se publicaba NEW.cantidad_final
    -- crudo, que con stock mixto es "4" cuando hay 4 cajas de 24. Ahora se
    -- publica el equivalente en unidades base de esa ubicacion.
    -- Para un producto de una sola presentacion el valor es el mismo de antes.
    v_stock_nuevo := public.fn_equivalente_base(
        p_id_producto  := NEW.id_producto,
        p_id_almacen   := NULL,
        p_id_ubicacion := NEW.id_ubicacion
    );

    -- Cinturon: si por cualquier razon el helper no devuelve nada, se mantiene
    -- el comportamiento anterior en vez de publicar NULL.
    IF v_stock_nuevo IS NULL THEN
        v_stock_nuevo := NEW.cantidad_final;
    END IF;

    UPDATE carnavalapp."Productos"
    SET stock = GREATEST(0, v_stock_nuevo)
    WHERE id = v_producto_record.id_vendedor_app;

    RAISE NOTICE 'Stock sincronizado para producto %: diferencia = %, stock anterior = %, nuevo stock (equiv. base) = %',
        v_producto_record.id_vendedor_app,
        v_diferencia,
        v_stock_actual,
        GREATEST(0, v_stock_nuevo);

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.fn_sincronizar_stock_producto() IS
    'Sincroniza stock hacia carnavalapp."Productos". Publica el EQUIVALENTE EN '
    'UNIDADES BASE de la ubicacion (no la cantidad cruda de la fila, que con '
    'stock mixto seria el numero de cajas) e ignora las patas de conversion.';


-- ----------------------------------------------------------------------------
-- 4.2 fn_notificar_producto_disponible
-- Se agrega el early-return por id_conversion. El resto es identico al de
-- produccion, incluido el bloque EXCEPTION que evita que un fallo de
-- notificacion tumbe la venta.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_notificar_producto_disponible()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_prev_qty NUMERIC;
  v_new_qty NUMERIC;
  v_store_id BIGINT;
  v_store_name TEXT;
  v_store_visible BOOLEAN;
  v_store_validada BOOLEAN;
  v_product_name TEXT;
  v_product_image TEXT;
  v_product_visible BOOLEAN;
  v_product_vendible BOOLEAN;
  v_product_deleted_at TIMESTAMP;
  v_price_cup NUMERIC;
  v_user_id UUID;
  v_mensaje TEXT;
  v_data JSONB;
BEGIN
  -- NUEVO (Fase 0 presentaciones): abrir una caja crea unidades sueltas que
  -- nacen en 0, lo que dispararia un falso "ya esta disponible". El producto
  -- nunca dejo de estar disponible: solo cambio de empaque.
  IF NEW.id_conversion IS NOT NULL THEN
    RETURN NEW;
  END IF;

  v_new_qty := COALESCE(NEW.cantidad_final, 0);
  IF TG_OP = 'UPDATE' THEN
    v_prev_qty := COALESCE(OLD.cantidad_final, 0);
  ELSE
    v_prev_qty := COALESCE(NEW.cantidad_inicial, 0);
  END IF;

  IF v_prev_qty > 0 OR v_new_qty <= 0 THEN
    RETURN NEW;
  END IF;

  SELECT
    p.denominacion,
    p.imagen,
    p.id_tienda,
    p.mostrar_en_catalogo,
    p.es_vendible,
    p.deleted_at
  INTO
    v_product_name,
    v_product_image,
    v_store_id,
    v_product_visible,
    v_product_vendible,
    v_product_deleted_at
  FROM public.app_dat_producto p
  WHERE p.id = NEW.id_producto;

  IF COALESCE(v_product_visible, false) IS DISTINCT FROM TRUE OR
     COALESCE(v_product_vendible, false) IS DISTINCT FROM TRUE OR
     v_product_deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT t.denominacion, t.mostrar_en_catalogo, t.validada
  INTO v_store_name, v_store_visible, v_store_validada
  FROM public.app_dat_tienda t
  WHERE t.id = v_store_id;

  IF COALESCE(v_store_visible, false) IS DISTINCT FROM TRUE OR
     COALESCE(v_store_validada, false) IS DISTINCT FROM TRUE THEN
    RETURN NEW;
  END IF;

  SELECT pv.precio_venta_cup
  INTO v_price_cup
  FROM public.app_dat_precio_venta pv
  WHERE pv.id_producto = NEW.id_producto
  ORDER BY pv.fecha_desde DESC
  LIMIT 1;

  v_mensaje := format(
    'El producto "%s" ya está disponible nuevamente en %s',
    COALESCE(v_product_name, 'Producto'),
    COALESCE(v_store_name, 'Tienda')
  );

  v_data := jsonb_build_object(
    'id_producto', NEW.id_producto,
    'id_tienda', v_store_id,
    'denominacion', v_product_name,
    'imagen', v_product_image,
    'denominacion_tienda', v_store_name,
    'precio_venta_cup', v_price_cup,
    'cantidad_inicial', v_prev_qty,
    'cantidad_final', v_new_qty
  );

  FOR v_user_id IN
    SELECT s.id_usuario
    FROM public.app_dat_suscripcion_notificaciones_producto s
    WHERE s.id_producto = NEW.id_producto
      AND s.activo = TRUE
  LOOP
    PERFORM public.fn_crear_notificacion(
      p_user_id := v_user_id,
      p_tipo := 'inventario',
      p_titulo := 'Producto disponible',
      p_mensaje := v_mensaje,
      p_data := v_data,
      p_prioridad := 'normal',
      p_accion := 'ir_a_producto'
    );
  END LOOP;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'fn_notificar_producto_disponible: %', SQLERRM;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.fn_notificar_producto_disponible() IS
    'Notifica a los suscriptores cuando un producto vuelve a tener stock. Ignora '
    'las patas de conversion de presentacion (abrir/empaquetar no es reposicion).';


-- ============================================================================
-- VERIFICACION (correr despues de aplicar; no modifica datos)
-- ============================================================================
-- 1. Las guardas quedaron en el cuerpo de las dos funciones.
--
--   SELECT
--     pg_get_functiondef('public.fn_sincronizar_stock_producto'::regproc)
--       ILIKE '%NEW.id_conversion IS NOT NULL%'                AS sync_tiene_guard,
--     pg_get_functiondef('public.fn_sincronizar_stock_producto'::regproc)
--       ILIKE '%fn_equivalente_base%'                          AS sync_usa_equivalente,
--     pg_get_functiondef('public.fn_sincronizar_stock_producto'::regproc)
--       ILIKE '%relation_products_carnaval%'                   AS sync_conserva_filtro_ubicacion,
--     pg_get_functiondef('public.fn_notificar_producto_disponible'::regproc)
--       ILIKE '%NEW.id_conversion IS NOT NULL%'                AS notif_tiene_guard,
--     pg_get_functiondef('public.fn_notificar_producto_disponible'::regproc)
--       ILIKE '%EXCEPTION WHEN OTHERS%'                        AS notif_conserva_exception;
--
-- 2. Los tres triggers siguen habilitados y apuntando a las mismas funciones.
--
--   SELECT t.tgname, t.tgenabled, p.proname
--     FROM pg_trigger t
--     JOIN pg_class c ON c.oid = t.tgrelid
--     JOIN pg_proc  p ON p.oid = t.tgfoid
--    WHERE c.relname = 'app_dat_inventario_productos'
--      AND NOT t.tgisinternal
--    ORDER BY t.tgname;
--   -- esperado: 3 filas, tgenabled = 'O' en todas
--
-- 3. Los 2 productos con carnaval + multipresentacion (a vigilar tras aplicar):
--
--   SELECT p.id, p.denominacion, p.id_vendedor_app,
--          public.fn_equivalente_base(p.id) AS equiv_base,
--          (SELECT stock FROM carnavalapp."Productos" cp WHERE cp.id = p.id_vendedor_app) AS stock_publicado
--     FROM app_dat_producto p
--    WHERE p.id_vendedor_app IS NOT NULL
--      AND (SELECT count(*) FROM app_dat_producto_presentacion pp WHERE pp.id_producto = p.id) > 1;
