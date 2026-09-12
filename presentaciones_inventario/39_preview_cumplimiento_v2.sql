-- ============================================================================
-- 39 · Preview pública de cumplimiento físico v2
-- ============================================================================
-- Wrapper autenticado del planificador puro del paso 38. No reserva ni escribe.
-- La autorización se expresa con relaciones totalmente calificadas porque el
-- helper legado check_user_has_access_to_tienda no fija search_path.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_preview_cumplimiento_v2(
    p_id_producto        bigint,
    p_id_ubicacion       bigint,
    p_id_presentacion    bigint,
    p_cantidad           numeric,
    p_id_variante        bigint DEFAULT NULL,
    p_id_opcion_variante bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_uuid                 uuid := auth.uid();
    v_id_tienda            bigint;
    v_autorizado           boolean;
    v_plan                 jsonb;
    v_factor_solicitado    numeric;
    v_es_fraccionable      boolean;
    v_equiv_disponible     numeric;
    v_maximo_servible      numeric;
BEGIN
    IF v_uuid IS NULL THEN
        RAISE EXCEPTION 'Se requiere un usuario autenticado'
            USING ERRCODE = '42501';
    END IF;

    SELECT p.id_tienda
      INTO v_id_tienda
      FROM public.app_dat_producto AS p
     WHERE p.id = p_id_producto
       AND p.deleted_at IS NULL;

    IF v_id_tienda IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error', 'error_code', 'PRODUCT_NOT_FOUND',
            'message', 'El producto no existe o está eliminado'
        );
    END IF;

    SELECT EXISTS (
        SELECT 1
          FROM public.app_dat_vendedor AS v
          JOIN public.app_dat_tpv AS t ON t.id = v.id_tpv
         WHERE v.uuid = v_uuid AND t.id_tienda = v_id_tienda
        UNION ALL
        SELECT 1
          FROM public.app_dat_almacenero AS al
          JOIN public.app_dat_almacen AS a ON a.id = al.id_almacen
         WHERE al.uuid = v_uuid AND a.id_tienda = v_id_tienda
        UNION ALL
        SELECT 1 FROM public.app_dat_supervisor AS s
         WHERE s.uuid = v_uuid AND s.id_tienda = v_id_tienda
        UNION ALL
        SELECT 1 FROM public.auditor AS au
         WHERE au.uuid = v_uuid AND au.id_tienda = v_id_tienda
        UNION ALL
        SELECT 1 FROM public.app_dat_gerente AS g
         WHERE g.uuid = v_uuid AND g.id_tienda = v_id_tienda
        UNION ALL
        SELECT 1
          FROM public.app_dat_jefe_cocina AS jc
          JOIN public.app_dat_cocina AS c ON c.id = jc.id_cocina
         WHERE jc.uuid = v_uuid
           AND c.id_tienda = v_id_tienda
           AND c.deleted_at IS NULL
    ) INTO v_autorizado;

    IF NOT COALESCE(v_autorizado, false) THEN
        RAISE EXCEPTION 'Acceso denegado a la tienda %', v_id_tienda
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM public.app_dat_layout_almacen AS la
          JOIN public.app_dat_almacen AS a ON a.id = la.id_almacen
         WHERE la.id = p_id_ubicacion
           AND la.deleted_at IS NULL
           AND a.deleted_at IS NULL
           AND a.id_tienda = v_id_tienda
    ) THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'error_code', 'LOCATION_NOT_IN_PRODUCT_STORE',
            'message', 'La ubicación no pertenece a la tienda del producto'
        );
    END IF;

    v_plan := public.fn_planificar_cumplimiento_presentaciones_v2(
        p_id_producto, p_id_ubicacion, p_id_presentacion, p_cantidad,
        p_id_variante, p_id_opcion_variante
    );

    IF v_plan->>'status' = 'success' THEN
        v_equiv_disponible := (v_plan->>'equivalente_solicitado')::numeric;
        SELECT v_equiv_disponible
               + COALESCE(sum((saldo->>'equivalente')::numeric), 0)
          INTO v_equiv_disponible
          FROM jsonb_array_elements(v_plan->'saldos_proyectados') AS saldo;
    ELSIF v_plan->>'error_code' = 'INSUFFICIENT_STOCK' THEN
        v_equiv_disponible := (v_plan->>'equivalente_disponible')::numeric;
    ELSE
        RETURN v_plan;
    END IF;

    SELECT c.factor_entero, c.es_fraccionable
      INTO v_factor_solicitado, v_es_fraccionable
      FROM public.fn_presentaciones_producto_v2(p_id_producto) AS c
     WHERE (p_id_presentacion IS NOT NULL
            AND c.id_presentacion = p_id_presentacion)
        OR (p_id_presentacion IS NULL AND c.es_base)
     ORDER BY c.es_base DESC
     LIMIT 1;

    IF v_factor_solicitado IS NOT NULL AND v_factor_solicitado > 0 THEN
        v_maximo_servible := v_equiv_disponible / v_factor_solicitado;
        IF NOT v_es_fraccionable THEN
            v_maximo_servible := floor(v_maximo_servible);
        END IF;
    END IF;

    RETURN v_plan
        || jsonb_build_object('equivalente_disponible', v_equiv_disponible)
        || jsonb_build_object('maximo_servible', v_maximo_servible);
END;
$function$;

COMMENT ON FUNCTION public.fn_preview_cumplimiento_v2(
    bigint, bigint, bigint, numeric, bigint, bigint
) IS 'Preview autenticada del cumplimiento físico v2; valida tienda y ubicación, no escribe ni reserva.';

REVOKE ALL ON FUNCTION public.fn_preview_cumplimiento_v2(
    bigint, bigint, bigint, numeric, bigint, bigint
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_preview_cumplimiento_v2(
    bigint, bigint, bigint, numeric, bigint, bigint
) TO authenticated, service_role;
