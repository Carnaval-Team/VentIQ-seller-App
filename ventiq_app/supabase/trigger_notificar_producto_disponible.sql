CREATE OR REPLACE FUNCTION public.fn_notificar_producto_disponible()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notificar_producto_disponible ON public.app_dat_inventario_productos;

CREATE TRIGGER trg_notificar_producto_disponible
AFTER INSERT OR UPDATE OF cantidad_final ON public.app_dat_inventario_productos
FOR EACH ROW
EXECUTE FUNCTION public.fn_notificar_producto_disponible();
