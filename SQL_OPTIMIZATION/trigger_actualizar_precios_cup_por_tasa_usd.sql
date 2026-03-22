-- ============================================================
-- PASO 1: Agregar columna precio_venta_regido_por_usd a app_dat_configuracion_tienda
-- ============================================================
ALTER TABLE public.app_dat_configuracion_tienda
  ADD COLUMN IF NOT EXISTS precio_venta_regido_por_usd boolean NOT NULL DEFAULT false;


-- ============================================================
-- PASO 2: Función del trigger
-- ============================================================
-- Lógica de conversión:
--   Si moneda_origen = USD y moneda_destino = CUP  →  precio_cup = precio_usd * valor_cambio
--   Si moneda_origen = CUP y moneda_destino = USD  →  precio_cup = precio_usd / valor_cambio
--   Cualquier otra combinación → no se actualiza
-- ============================================================

-- Monedas: 1 = CUP, 2 = USD
CREATE OR REPLACE FUNCTION fn_actualizar_precios_cup_por_tasa()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_tasa           numeric;
    v_id_tienda      bigint;
    v_regido_por_usd boolean;
BEGIN
    -- Solo actuar cuando valor_cambio realmente cambió y la tasa está activa
    IF (NEW.valor_cambio = OLD.valor_cambio) OR (NEW.activo = false) THEN
        RETURN NEW;
    END IF;

    v_tasa      := NEW.valor_cambio;
    v_id_tienda := NEW.id_tienda;

    -- Verificar que la tienda tiene precio_venta_regido_por_usd = TRUE
    SELECT precio_venta_regido_por_usd INTO v_regido_por_usd
    FROM public.app_dat_configuracion_tienda
    WHERE id_tienda = v_id_tienda;

    IF v_regido_por_usd IS NULL OR v_regido_por_usd = false THEN
        RETURN NEW;
    END IF;

    -- Actualizar precio_venta_cup SOLO para productos que tienen precio_venta_usd configurado.
    -- Los productos sin precio_venta_usd (NULL o 0) se IGNORAN completamente.
    -- Monedas: 1 = CUP, 2 = USD
    IF NEW.id_moneda_origen = 2 AND NEW.id_moneda_destino = 1 THEN
        -- USD → CUP: precio_cup = precio_venta_usd * tasa
        UPDATE public.app_dat_precio_venta pv
        SET precio_venta_cup = ROUND(pv.precio_venta_usd * v_tasa, 2)
        FROM public.app_dat_producto p
        WHERE pv.id_producto = p.id
          AND p.id_tienda = v_id_tienda
          AND pv.precio_venta_usd IS NOT NULL
          AND pv.precio_venta_usd > 0
          AND (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= CURRENT_DATE);

    ELSIF NEW.id_moneda_origen = 1 AND NEW.id_moneda_destino = 2 THEN
        -- CUP → USD (tasa invertida): precio_cup = precio_venta_usd / tasa
        UPDATE public.app_dat_precio_venta pv
        SET precio_venta_cup = ROUND(pv.precio_venta_usd / v_tasa, 2)
        FROM public.app_dat_producto p
        WHERE pv.id_producto = p.id
          AND p.id_tienda = v_id_tienda
          AND pv.precio_venta_usd IS NOT NULL
          AND pv.precio_venta_usd > 0
          AND v_tasa > 0
          AND (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= CURRENT_DATE);

    END IF;

    RETURN NEW;
END;
$$;


-- ============================================================
-- PASO 3: Crear el trigger en tasa_cambio_extraoficial
-- ============================================================
DROP TRIGGER IF EXISTS trg_actualizar_precios_cup_por_tasa
  ON public.tasa_cambio_extraoficial;

CREATE TRIGGER trg_actualizar_precios_cup_por_tasa
AFTER UPDATE OF valor_cambio, activo
ON public.tasa_cambio_extraoficial
FOR EACH ROW
EXECUTE FUNCTION fn_actualizar_precios_cup_por_tasa();
