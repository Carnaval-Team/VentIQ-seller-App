CREATE OR REPLACE FUNCTION public.fn_notificar_producto_nuevo()
RETURNS TRIGGER AS $$
DECLARE
  v_store_name TEXT;
  v_store_visible BOOLEAN;
  v_store_validada BOOLEAN;
  v_price_cup NUMERIC;
  v_user_id UUID;
  v_mensaje TEXT;
  v_data JSONB;
BEGIN
  SELECT t.denominacion, t.mostrar_en_catalogo, t.validada
  INTO v_store_name, v_store_visible, v_store_validada
  FROM public.app_dat_tienda t
  WHERE t.id = NEW.id_tienda;

  IF COALESCE(v_store_visible, false) IS DISTINCT FROM TRUE THEN
    RETURN NEW;
  END IF;

  SELECT pv.precio_venta_cup
  INTO v_price_cup
  FROM public.app_dat_precio_venta pv
  WHERE pv.id_producto = NEW.id
  ORDER BY pv.fecha_desde DESC
  LIMIT 1;

  v_mensaje := format(
    'Nuevo producto en %s: %s',
    COALESCE(v_store_name, 'Tienda'),
    NEW.denominacion
  );

  v_data := jsonb_build_object(
    'id_producto', NEW.id,
    'id_tienda', NEW.id_tienda,
    'denominacion', NEW.denominacion,
    'imagen', NEW.imagen,
    'denominacion_tienda', v_store_name,
    'precio_venta_cup', v_price_cup
  );

  FOR v_user_id IN
    SELECT s.id_usuario
    FROM public.app_dat_suscripcion_notificaciones_tienda s
    WHERE s.id_tienda = NEW.id_tienda
      AND s.activo = TRUE
  LOOP
    PERFORM public.fn_crear_notificacion(
      p_user_id := v_user_id,
      p_tipo := 'promocion',
      p_titulo := 'Nuevo producto',
      p_mensaje := v_mensaje,
      p_data := v_data,
      p_prioridad := 'normal',
      p_accion := 'ir_a_producto'
    );
  END LOOP;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'fn_notificar_producto_nuevo: %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notificar_producto_nuevo ON public.app_dat_producto;

CREATE TRIGGER trg_notificar_producto_nuevo
AFTER INSERT ON public.app_dat_producto
FOR EACH ROW
WHEN (NEW.es_vendible = true AND NEW.deleted_at IS NULL)
EXECUTE FUNCTION public.fn_notificar_producto_nuevo();
