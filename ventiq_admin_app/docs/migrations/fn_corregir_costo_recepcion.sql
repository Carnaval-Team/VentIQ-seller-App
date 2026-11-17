-- =============================================================================
-- Corrección de costo de una recepción — SOLO dueño de la tienda
--
-- El diálogo «Historial de costos» del admin (rol Dueño) permite reemplazar
-- un costo introducido erróneamente. La autorización no puede quedar en el
-- cliente: esta RPC SECURITY DEFINER verifica en servidor que el caller es
-- dueño (app_dat_dueno) de la tienda del producto y ejecuta las tres
-- escrituras en una sola transacción:
--   1. app_dat_recepcion_productos: precio_unitario y costo_real de la línea.
--   2. app_dat_precio_costo: reemplaza el evento histórico erróneo, así la
--      valoración retroactiva (LAG sobre esa tabla) también queda corregida.
--   3. app_dat_producto_presentacion.precio_promedio: costo vigente; el
--      trigger registra el cambio como evento nuevo auditable.
--
-- No hace falta GRANT UPDATE sobre app_dat_precio_costo: la función corre
-- como definer. La política FOR ALL USING(true) existente no se toca.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_corregir_costo_recepcion(
    p_id_recepcion_producto BIGINT,
    p_nuevo_costo NUMERIC,
    p_evento_fecha TIMESTAMPTZ DEFAULT NULL,
    p_id_producto BIGINT DEFAULT NULL,
    p_id_presentacion BIGINT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id_producto     BIGINT;
    v_id_presentacion BIGINT;
    v_cantidad        NUMERIC;
    v_id_tienda       BIGINT;
    v_evento_id       BIGINT;
    v_diff            DOUBLE PRECISION;
BEGIN
    IF p_nuevo_costo IS NULL OR p_nuevo_costo <= 0 THEN
        RETURN jsonb_build_object('success', false,
            'message', 'El nuevo costo debe ser mayor que cero');
    END IF;

    -- La corrección también aplica a eventos sin recepción asociada: en ese
    -- caso se pasa p_id_producto y solo se corrigen historial y promedio.
    IF p_id_recepcion_producto IS NOT NULL THEN
        SELECT r.id_producto, r.id_presentacion, r.cantidad
          INTO v_id_producto, v_id_presentacion, v_cantidad
          FROM public.app_dat_recepcion_productos r
         WHERE r.id = p_id_recepcion_producto;

        IF NOT FOUND THEN
            RETURN jsonb_build_object('success', false,
                'message', 'No existe la línea de recepción indicada');
        END IF;
    ELSE
        v_id_producto := p_id_producto;
        v_id_presentacion := p_id_presentacion;
    END IF;

    IF v_id_producto IS NULL THEN
        RETURN jsonb_build_object('success', false,
            'message', 'Falta el producto a corregir');
    END IF;

    -- Autorización: solo el dueño de la tienda del producto.
    SELECT p.id_tienda INTO v_id_tienda
      FROM public.app_dat_producto p
     WHERE p.id = v_id_producto;

    IF NOT EXISTS (
        SELECT 1 FROM public.app_dat_dueno d
         WHERE d.id_tienda = v_id_tienda
           AND d.uuid = auth.uid()
    ) THEN
        RETURN jsonb_build_object('success', false,
            'message', 'Solo el dueño de la tienda puede corregir costos');
    END IF;

    -- Presentación cuyo promedio quedó mal; fallback a la base del producto.
    IF v_id_presentacion IS NULL OR v_id_presentacion <= 0 THEN
        SELECT pp.id INTO v_id_presentacion
          FROM public.app_dat_producto_presentacion pp
         WHERE pp.id_producto = v_id_producto
           AND pp.es_base = TRUE
         ORDER BY pp.id
         LIMIT 1;
    END IF;

    -- 1. Línea de recepción (solo si la corrección vino de una): precio_unitario
    --    es costo por unidad y costo_real el total. En algunos proyectos
    --    costo_real es columna GENERADA (se recalcula sola con el
    --    precio_unitario) y rechaza el UPDATE directo; en otros ya es columna
    --    normal. Se decide por catálogo para soportar ambos.
    IF p_id_recepcion_producto IS NOT NULL AND EXISTS (
        SELECT 1 FROM pg_attribute
         WHERE attrelid = 'public.app_dat_recepcion_productos'::regclass
           AND attname  = 'costo_real'
           AND attgenerated = ''
    ) THEN
        UPDATE public.app_dat_recepcion_productos
           SET precio_unitario = p_nuevo_costo,
               costo_real      = CASE WHEN v_cantidad IS NOT NULL
                                      THEN p_nuevo_costo * v_cantidad
                                      ELSE costo_real END
         WHERE id = p_id_recepcion_producto;
    ELSIF p_id_recepcion_producto IS NOT NULL THEN
        UPDATE public.app_dat_recepcion_productos
           SET precio_unitario = p_nuevo_costo
         WHERE id = p_id_recepcion_producto;
    END IF;

    -- 2. Reemplazar el evento erróneo del historial (fila más cercana a
    --    p_evento_fecha, con tolerancia por el redondeo de la RPC).
    IF p_evento_fecha IS NOT NULL AND v_id_presentacion IS NOT NULL THEN
        SELECT pc.id,
               ABS(EXTRACT(EPOCH FROM (pc.created_at - p_evento_fecha)))
          INTO v_evento_id, v_diff
          FROM public.app_dat_precio_costo pc
         WHERE pc.id_presentacion = v_id_presentacion
         ORDER BY ABS(EXTRACT(EPOCH FROM (pc.created_at - p_evento_fecha)))
         LIMIT 1;

        IF v_evento_id IS NOT NULL AND v_diff <= 10 THEN
            UPDATE public.app_dat_precio_costo
               SET precio_costo_usd = p_nuevo_costo
             WHERE id = v_evento_id;
        ELSE
            v_evento_id := NULL;
        END IF;
    END IF;

    -- 3. Costo vigente de la presentación (el trigger anota el evento nuevo).
    IF v_id_presentacion IS NOT NULL THEN
        UPDATE public.app_dat_producto_presentacion
           SET precio_promedio = p_nuevo_costo
         WHERE id = v_id_presentacion;
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'id_presentacion', v_id_presentacion,
        'evento_reemplazado', v_evento_id IS NOT NULL
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_corregir_costo_recepcion(
    BIGINT, NUMERIC, TIMESTAMPTZ, BIGINT, BIGINT
) TO authenticated;

-- Refresca el schema cache de PostgREST para que la nueva firma sea visible
-- sin esperar al reload periódico.
NOTIFY pgrst, 'reload schema';
