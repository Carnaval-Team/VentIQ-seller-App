-- ================================================================
-- fn_inicializar_precio_promedio_desde_primera_recepcion
--
-- Para cada presentacion de cada producto de la tienda indicada,
-- busca la primera recepcion (por fecha de operacion) y asigna su
-- costo (costo_real si no es nulo/0, sino precio_unitario) como
-- precio_promedio en app_dat_producto_presentacion.
--
-- Solo actualiza presentaciones cuyo precio_promedio sea NULL o 0.
--
-- Retorna un resumen con:
--   productos_procesados            - cantidad de productos de la tienda
--   presentaciones_actualizadas     - presentaciones a las que se les asigno precio
--   presentaciones_sin_recepcion    - presentaciones sin ninguna recepcion encontrada
--   presentaciones_ya_tenian_precio - presentaciones omitidas (ya tenian precio > 0)
--
-- Parametros:
--   p_id_tienda   - (obligatorio) id de la tienda
--   p_id_producto - (opcional)    si se indica, solo procesa ese producto (debe pertenecer a la tienda)
--
-- Uso:
--   SELECT * FROM fn_inicializar_precio_promedio_desde_primera_recepcion(1);
--   SELECT * FROM fn_inicializar_precio_promedio_desde_primera_recepcion(1, 42);
-- ================================================================

CREATE OR REPLACE FUNCTION public.fn_inicializar_precio_promedio_desde_primera_recepcion(
    p_id_tienda   BIGINT,
    p_id_producto BIGINT DEFAULT NULL
)
RETURNS TABLE (
    productos_procesados            BIGINT,
    presentaciones_actualizadas     BIGINT,
    presentaciones_sin_recepcion    BIGINT,
    presentaciones_ya_tenian_precio BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_presentacion     RECORD;
    v_primer_costo     NUMERIC;
    v_actualizadas     BIGINT := 0;
    v_sin_recepcion    BIGINT := 0;
    v_ya_tenian_precio BIGINT := 0;
    v_productos_ids    BIGINT[];
BEGIN
    -- 1. Recopilar IDs de productos activos de la tienda
    --    Si p_id_producto se indica, verificar que pertenece a la tienda y usar solo ese
    SELECT ARRAY_AGG(p.id)
    INTO v_productos_ids
    FROM public.app_dat_producto p
    WHERE p.id_tienda = p_id_tienda
      AND p.deleted_at IS NULL
      AND (p_id_producto IS NULL OR p.id = p_id_producto);

    -- Si la tienda no tiene productos, devolver ceros
    IF v_productos_ids IS NULL OR array_length(v_productos_ids, 1) = 0 THEN
        RETURN QUERY SELECT 0::BIGINT, 0::BIGINT, 0::BIGINT, 0::BIGINT;
        RETURN;
    END IF;

    -- 2. Iterar sobre cada presentacion de esos productos
    FOR v_presentacion IN
        SELECT
            pp.id            AS id_presentacion,
            pp.id_producto   AS id_producto,
            pp.precio_promedio
        FROM public.app_dat_producto_presentacion pp
        WHERE pp.id_producto = ANY(v_productos_ids)
    LOOP

        -- 2a. Si ya tiene precio_promedio > 0, omitir
        IF v_presentacion.precio_promedio IS NOT NULL
           AND v_presentacion.precio_promedio > 1 THEN
            v_ya_tenian_precio := v_ya_tenian_precio + 1;
            CONTINUE;
        END IF;

        v_primer_costo := NULL;

        -- 2b. Buscar la primera recepcion para producto + presentacion exacta
        --     El "primero" se determina por la fecha de la operacion vinculada
        SELECT COALESCE(NULLIF(rp.costo_real, 0), rp.precio_unitario)
        INTO v_primer_costo
        FROM public.app_dat_recepcion_productos rp
        JOIN public.app_dat_operaciones op ON op.id = rp.id_operacion
        WHERE rp.id_producto     = v_presentacion.id_producto
          AND rp.id_presentacion = v_presentacion.id_presentacion
          AND (rp.costo_real > 0 OR rp.precio_unitario > 0)
        ORDER BY op.created_at ASC
        LIMIT 1;

        -- 2c. Si no hay recepcion con esa presentacion especifica,
        --     buscar la primera recepcion del producto sin importar presentacion
        IF v_primer_costo IS NULL THEN
            SELECT COALESCE(NULLIF(rp.costo_real, 0), rp.precio_unitario)
            INTO v_primer_costo
            FROM public.app_dat_recepcion_productos rp
            JOIN public.app_dat_operaciones op ON op.id = rp.id_operacion
            WHERE rp.id_producto = v_presentacion.id_producto
              AND (rp.costo_real > 0 OR rp.precio_unitario > 0)
            ORDER BY op.created_at ASC
            LIMIT 1;
        END IF;

        -- 2d. Si sigue sin haber costo, contar como sin recepcion y seguir
        IF v_primer_costo IS NULL OR v_primer_costo <= 0 THEN
            v_sin_recepcion := v_sin_recepcion + 1;
            CONTINUE;
        END IF;

        -- 2e. Actualizar precio_promedio en la presentacion
        UPDATE public.app_dat_producto_presentacion
        SET precio_promedio = v_primer_costo
        WHERE id = v_presentacion.id_presentacion;

        v_actualizadas := v_actualizadas + 1;

    END LOOP;

    -- 3. Devolver resumen
    RETURN QUERY
    SELECT
        array_length(v_productos_ids, 1)::BIGINT,
        v_actualizadas,
        v_sin_recepcion,
        v_ya_tenian_precio;
END;
$$;
