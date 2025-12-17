CREATE OR REPLACE FUNCTION fn_sincronizar_producto_carnaval()
RETURNS TRIGGER AS $$
BEGIN
  -- Actualizar la tabla carnavalapp.Productos
  -- Se asume que app_dat_producto.id_vendedor_app corresponde a carnavalapp.Productos.id
  -- Solo se ejecuta si id_vendedor_app no es nulo
  IF NEW.id_vendedor_app IS NOT NULL THEN
      UPDATE carnavalapp."Productos"
      SET 
        name = NEW.denominacion,
        image = NEW.imagen,
        updated_at = NOW()
      WHERE id = NEW.id_vendedor_app;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sincronizar_producto_carnaval ON public.app_dat_producto;

CREATE TRIGGER trg_sincronizar_producto_carnaval
AFTER UPDATE ON public.app_dat_producto
FOR EACH ROW
WHEN ((OLD.denominacion IS DISTINCT FROM NEW.denominacion) OR (OLD.imagen IS DISTINCT FROM NEW.imagen))
EXECUTE FUNCTION fn_sincronizar_producto_carnaval();
