-- ============================================================================
-- Trigger BEFORE INSERT en carnavalapp."OrderDetails":
-- Valida stock del producto, EXCEPTO cuando la orden padre es de paquetería
-- (carnavalapp."Orders".paqueteria IS NOT NULL). En ese caso se omite la
-- validación y la cantidad se conserva tal cual.
-- ============================================================================

CREATE OR REPLACE FUNCTION carnavalapp.fn_orderdetails_check_stock()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock      BIGINT;
    v_paqueteria JSONB;
BEGIN
    -- Verificar si la orden padre es de paquetería
    SELECT paqueteria INTO v_paqueteria
      FROM carnavalapp."Orders"
     WHERE id = NEW.order_id;

    IF v_paqueteria IS NOT NULL AND v_paqueteria <> 'null'::jsonb THEN
        -- Paquetería: no validar stock ni recortar quantity
        RETURN NEW;
    END IF;

    -- Flujo normal: validar stock
    SELECT stock INTO v_stock
      FROM carnavalapp."Productos"
     WHERE id = NEW.product_id;

    IF v_stock <= 0 THEN
        RAISE EXCEPTION 'No hay stock disponible para el producto %', NEW.product_id;
    END IF;

    NEW.quantity := LEAST(NEW.quantity, v_stock)::smallint;

    RETURN NEW;
END;
$$;
