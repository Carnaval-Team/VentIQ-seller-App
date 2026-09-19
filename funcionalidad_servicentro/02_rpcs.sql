-- ============================================================================
-- 02 · Fase 1 · RPCs modo servicentro
-- ============================================================================
-- Proyecto Supabase: vsieeihstajlrdvpuooh
-- Aplicar en: SQL Editor / MCP. Idempotente (CREATE OR REPLACE).
-- REQUISITOS: 01_schema.sql aplicado.
-- Plan: docs/PLAN_SERVICENTRO.md
--
-- CONTENIDO
--   2.1  fn_require_gerente_tienda          helper escritura (gerente | superadmin)
--   2.2  fn_set_modo_servicentro           activa/desactiva + columnas (exclusión)
--   2.3  fn_get_servicentro_config         lectura completa para admin/vendedor
--   2.4  fn_listar_servicentro_productos   grid del vendedor (orden + color + precio)
--   2.5  fn_upsert_servicentro_producto    agregar/actualizar color/orden
--   2.6  fn_eliminar_servicentro_producto
--   2.7  fn_reordenar_servicentro_productos  array de ids en orden deseado
--
-- Seguridad: escritura exige gerente de la tienda (o superadmin activo).
-- Lectura usa check_user_has_access_to_tienda (vendedor incluido).
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 2.1 Helper: exige gerente de la tienda o superadmin activo
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_require_gerente_tienda(p_id_tienda bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_ok boolean;
BEGIN
    SELECT EXISTS (
        SELECT 1
          FROM public.app_dat_gerente g
         WHERE g.uuid = auth.uid()
           AND g.id_tienda = p_id_tienda
    )
    OR EXISTS (
        SELECT 1
          FROM public.app_dat_superadmin sa
         WHERE sa.uuid = auth.uid()
           AND COALESCE(sa.activo, true) = true
    )
    INTO v_ok;

    IF NOT COALESCE(v_ok, false) THEN
        RAISE EXCEPTION 'Acceso denegado: se requiere rol gerente (o superadmin) en esta tienda'
            USING ERRCODE = '42501';
    END IF;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_require_gerente_tienda(bigint)
    TO authenticated, anon, service_role;


-- ----------------------------------------------------------------------------
-- 2.2 fn_set_modo_servicentro
-- Activa/desactiva el modo y opcionalmente actualiza columnas.
-- La exclusión con restaurante/cocina la refuerza el trigger del 01.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_set_modo_servicentro(
    p_id_tienda           bigint,
    p_activo              boolean,
    p_servicentro_columnas smallint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_modo_restaurante boolean;
    v_cocina_activa    boolean;
    v_columnas         smallint;
    v_row_id           bigint;
BEGIN
    PERFORM public.fn_require_gerente_tienda(p_id_tienda);

    SELECT ct.modo_restaurante, ct.cocina_activa, ct.servicentro_columnas, ct.id
      INTO v_modo_restaurante, v_cocina_activa, v_columnas, v_row_id
      FROM public.app_dat_configuracion_tienda ct
     WHERE ct.id_tienda = p_id_tienda;

    IF v_row_id IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La tienda no tiene fila en app_dat_configuracion_tienda',
            'error_code', 'CONFIG_NOT_FOUND'
        );
    END IF;

    IF p_activo AND (COALESCE(v_modo_restaurante, false) OR COALESCE(v_cocina_activa, false)) THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'No se puede activar modo servicentro mientras modo restaurante o cocina estén activos. Desactívalos primero.',
            'error_code', 'MODO_EXCLUYENTE',
            'modo_restaurante', v_modo_restaurante,
            'cocina_activa', v_cocina_activa
        );
    END IF;

    IF p_servicentro_columnas IS NOT NULL THEN
        IF p_servicentro_columnas < 1 OR p_servicentro_columnas > 4 THEN
            RETURN jsonb_build_object(
                'status', 'error',
                'message', 'servicentro_columnas debe estar entre 1 y 4',
                'error_code', 'COLUMNAS_INVALIDAS'
            );
        END IF;
        v_columnas := p_servicentro_columnas;
    END IF;

    UPDATE public.app_dat_configuracion_tienda
       SET modo_servicentro = p_activo,
           servicentro_columnas = v_columnas,
           updated_at = now()
     WHERE id_tienda = p_id_tienda;

    RETURN jsonb_build_object(
        'status', 'success',
        'modo_servicentro', p_activo,
        'servicentro_columnas', v_columnas
    );
EXCEPTION
    WHEN check_violation THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', SQLERRM,
            'error_code', 'MODO_EXCLUYENTE'
        );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_set_modo_servicentro(bigint, boolean, smallint)
    TO authenticated, anon, service_role;


-- ----------------------------------------------------------------------------
-- 2.3 fn_get_servicentro_config
-- Config + lista (para admin y para hidratar cache del vendedor).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_get_servicentro_config(
    p_id_tienda bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_modo      boolean := false;
    v_columnas  smallint := 2;
    v_productos jsonb;
BEGIN
    PERFORM public.check_user_has_access_to_tienda(p_id_tienda);

    SELECT COALESCE(ct.modo_servicentro, false),
           COALESCE(ct.servicentro_columnas, 2)
      INTO v_modo, v_columnas
      FROM public.app_dat_configuracion_tienda ct
     WHERE ct.id_tienda = p_id_tienda;

    SELECT COALESCE(jsonb_agg(row_to_json(x)::jsonb ORDER BY x.orden, x.id), '[]'::jsonb)
      INTO v_productos
      FROM (
        SELECT sp.id,
               sp.id_producto,
               sp.orden,
               sp.color,
               p.denominacion,
               p.sku,
               p.um,
               p.imagen,
               p.es_combustible,
               p.es_vendible,
               COALESCE(pv.precio_venta_cup, 0) AS precio_venta
          FROM public.app_dat_servicentro_producto sp
          JOIN public.app_dat_producto p ON p.id = sp.id_producto
          LEFT JOIN LATERAL (
              SELECT pv_inner.precio_venta_cup
                FROM public.app_dat_precio_venta pv_inner
               WHERE pv_inner.id_producto = p.id
                 AND (pv_inner.id_variante IS NULL OR pv_inner.id_variante = 0)
                 AND (pv_inner.fecha_hasta IS NULL OR pv_inner.fecha_hasta >= CURRENT_DATE)
               ORDER BY pv_inner.fecha_desde DESC
               LIMIT 1
          ) pv ON TRUE
         WHERE sp.id_tienda = p_id_tienda
           AND p.deleted_at IS NULL
      ) x;

    RETURN jsonb_build_object(
        'status', 'success',
        'id_tienda', p_id_tienda,
        'modo_servicentro', v_modo,
        'servicentro_columnas', v_columnas,
        'productos', v_productos
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_get_servicentro_config(bigint)
    TO authenticated, anon, service_role;


-- ----------------------------------------------------------------------------
-- 2.4 fn_listar_servicentro_productos
-- Grid del vendedor: solo productos válidos, ordenados.
-- p_id_tpv opcional: si viene, incluye stock_disponible del almacén del TPV.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_listar_servicentro_productos(
    p_id_tienda bigint,
    p_id_tpv    bigint DEFAULT NULL
)
RETURNS TABLE (
    id                bigint,
    id_producto       bigint,
    orden             smallint,
    color             text,
    denominacion      text,
    sku               text,
    um                text,
    imagen            text,
    precio_venta      numeric,
    stock_disponible  numeric,
    tiene_stock       boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_id_almacen bigint;
BEGIN
    PERFORM public.check_user_has_access_to_tienda(p_id_tienda);

    IF p_id_tpv IS NOT NULL THEN
        SELECT tpv.id_almacen
          INTO v_id_almacen
          FROM public.app_dat_tpv tpv
         WHERE tpv.id = p_id_tpv
           AND tpv.id_tienda = p_id_tienda;
    END IF;

    RETURN QUERY
    SELECT
        sp.id,
        sp.id_producto,
        sp.orden,
        sp.color,
        p.denominacion::text,
        p.sku::text,
        p.um::text,
        p.imagen::text,
        COALESCE(pv.precio_venta_cup, 0)::numeric AS precio_venta,
        CASE
            WHEN v_id_almacen IS NULL THEN 0::numeric
            ELSE COALESCE((
                SELECT SUM(ip.cantidad_final)
                  FROM public.app_dat_inventario_productos ip
                  JOIN public.app_dat_layout_almacen la ON ip.id_ubicacion = la.id
                 WHERE ip.id_producto = p.id
                   AND la.id_almacen = v_id_almacen
                   AND ip.cantidad_final > 0
                   AND ip.id = (
                       SELECT MAX(ip2.id)
                         FROM public.app_dat_inventario_productos ip2
                        WHERE ip2.id_producto = ip.id_producto
                          AND COALESCE(ip2.id_variante, 0) = COALESCE(ip.id_variante, 0)
                          AND COALESCE(ip2.id_opcion_variante, 0) = COALESCE(ip.id_opcion_variante, 0)
                          AND COALESCE(ip2.id_presentacion, 0) = COALESCE(ip.id_presentacion, 0)
                          AND COALESCE(ip2.id_ubicacion, 0) = COALESCE(ip.id_ubicacion, 0)
                   )
            ), 0)::numeric
        END AS stock_disponible,
        CASE
            WHEN v_id_almacen IS NULL THEN false
            ELSE COALESCE((
                SELECT SUM(ip.cantidad_final) > 0
                  FROM public.app_dat_inventario_productos ip
                  JOIN public.app_dat_layout_almacen la ON ip.id_ubicacion = la.id
                 WHERE ip.id_producto = p.id
                   AND la.id_almacen = v_id_almacen
                   AND ip.cantidad_final > 0
                   AND ip.id = (
                       SELECT MAX(ip2.id)
                         FROM public.app_dat_inventario_productos ip2
                        WHERE ip2.id_producto = ip.id_producto
                          AND COALESCE(ip2.id_variante, 0) = COALESCE(ip.id_variante, 0)
                          AND COALESCE(ip2.id_opcion_variante, 0) = COALESCE(ip.id_opcion_variante, 0)
                          AND COALESCE(ip2.id_presentacion, 0) = COALESCE(ip.id_presentacion, 0)
                          AND COALESCE(ip2.id_ubicacion, 0) = COALESCE(ip.id_ubicacion, 0)
                   )
            ), false)
        END AS tiene_stock
    FROM public.app_dat_servicentro_producto sp
    JOIN public.app_dat_producto p ON p.id = sp.id_producto
    LEFT JOIN LATERAL (
        SELECT pv_inner.precio_venta_cup
          FROM public.app_dat_precio_venta pv_inner
         WHERE pv_inner.id_producto = p.id
           AND (pv_inner.id_variante IS NULL OR pv_inner.id_variante = 0)
           AND (pv_inner.fecha_hasta IS NULL OR pv_inner.fecha_hasta >= CURRENT_DATE)
         ORDER BY pv_inner.fecha_desde DESC
         LIMIT 1
    ) pv ON TRUE
    WHERE sp.id_tienda = p_id_tienda
      AND p.deleted_at IS NULL
      AND p.es_combustible = true
      AND p.es_vendible = true
    ORDER BY sp.orden ASC, sp.id ASC;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_listar_servicentro_productos(bigint, bigint)
    TO authenticated, anon, service_role;


-- ----------------------------------------------------------------------------
-- 2.5 fn_upsert_servicentro_producto
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_upsert_servicentro_producto(
    p_id_tienda   bigint,
    p_id_producto bigint,
    p_orden       smallint DEFAULT NULL,
    p_color       text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_id     bigint;
    v_orden  smallint;
    v_color  text;
BEGIN
    PERFORM public.fn_require_gerente_tienda(p_id_tienda);

    v_color := COALESCE(NULLIF(trim(p_color), ''), '#64748B');
    IF v_color !~ '^#[0-9A-Fa-f]{6}$' THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'color debe ser hex #RRGGBB',
            'error_code', 'COLOR_INVALIDO'
        );
    END IF;

    IF p_orden IS NULL THEN
        SELECT COALESCE(MAX(sp.orden), -1) + 1
          INTO v_orden
          FROM public.app_dat_servicentro_producto sp
         WHERE sp.id_tienda = p_id_tienda;
    ELSE
        v_orden := p_orden;
    END IF;

    INSERT INTO public.app_dat_servicentro_producto (id_tienda, id_producto, orden, color)
    VALUES (p_id_tienda, p_id_producto, v_orden, v_color)
    ON CONFLICT (id_tienda, id_producto) DO UPDATE
        SET orden = COALESCE(p_orden, public.app_dat_servicentro_producto.orden),
            color = CASE
                      WHEN NULLIF(trim(p_color), '') IS NULL
                        THEN public.app_dat_servicentro_producto.color
                      ELSE v_color
                    END,
            updated_at = now()
    RETURNING id, orden, color INTO v_id, v_orden, v_color;

    RETURN jsonb_build_object(
        'status', 'success',
        'id', v_id,
        'id_tienda', p_id_tienda,
        'id_producto', p_id_producto,
        'orden', v_orden,
        'color', v_color
    );
EXCEPTION
    WHEN check_violation OR foreign_key_violation THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', SQLERRM,
            'error_code', 'SERVICENTRO_PRODUCTO_INVALIDO'
        );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_upsert_servicentro_producto(bigint, bigint, smallint, text)
    TO authenticated, anon, service_role;


-- ----------------------------------------------------------------------------
-- 2.6 fn_eliminar_servicentro_producto
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_eliminar_servicentro_producto(
    p_id_tienda   bigint,
    p_id_producto bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_deleted int;
BEGIN
    PERFORM public.fn_require_gerente_tienda(p_id_tienda);

    DELETE FROM public.app_dat_servicentro_producto
     WHERE id_tienda = p_id_tienda
       AND id_producto = p_id_producto;

    GET DIAGNOSTICS v_deleted = ROW_COUNT;

    IF v_deleted = 0 THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El producto no está en la lista servicentro de la tienda',
            'error_code', 'NOT_FOUND'
        );
    END IF;

    RETURN jsonb_build_object(
        'status', 'success',
        'id_tienda', p_id_tienda,
        'id_producto', p_id_producto
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_eliminar_servicentro_producto(bigint, bigint)
    TO authenticated, anon, service_role;


-- ----------------------------------------------------------------------------
-- 2.7 fn_reordenar_servicentro_productos
-- p_ids_producto: array en el orden deseado (posición 0 = orden 0).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_reordenar_servicentro_productos(
    p_id_tienda     bigint,
    p_ids_producto  bigint[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_i int;
    v_updated int := 0;
BEGIN
    PERFORM public.fn_require_gerente_tienda(p_id_tienda);

    IF p_ids_producto IS NULL OR array_length(p_ids_producto, 1) IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'p_ids_producto no puede estar vacío',
            'error_code', 'EMPTY_ORDER'
        );
    END IF;

    FOR v_i IN 1 .. array_length(p_ids_producto, 1) LOOP
        UPDATE public.app_dat_servicentro_producto
           SET orden = (v_i - 1),
               updated_at = now()
         WHERE id_tienda = p_id_tienda
           AND id_producto = p_ids_producto[v_i];
        IF FOUND THEN
            v_updated := v_updated + 1;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'status', 'success',
        'actualizados', v_updated,
        'orden', to_jsonb(p_ids_producto)
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_reordenar_servicentro_productos(bigint, bigint[])
    TO authenticated, anon, service_role;
