-- ============================================================================
-- PROMOCION M01 · 05 · Venta v4 / pago / cambio de estado / comanda (_m01)
-- ============================================================================
-- Aditivo: crea
--   fn_registrar_venta_offline_v4_m01
--   fn_registrar_pago_venta_offline_m01
--   fn_registrar_cambio_estado_offline_m01
--   fn_cambiar_estado_comanda_item_offline_m01
-- Los nombres antiguos NO se tocan.
-- Cuerpos: newa vigente (2026-11-23). Ninguna llama a otra función offline
-- (no hay cableado _m01 interno); delegan en funciones de negocio existentes:
--   fn_registrar_venta_v3, fn_registrar_pago_venta_v2, fn_registrar_pago_venta,
--   fn_registrar_cambio_estado_operacion, fn_cambiar_estado_comanda_item.
-- Nota: en newa las tres de venta/pago/estado tienen EXECUTE solo para
-- authenticated; aquí se concede también a service_role (decisión del pase).
-- ============================================================================

DO $preflight$
DECLARE
    v_nombre text;
BEGIN
    IF to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta public.fn_config_tienda_puede_escribir(bigint) en este proyecto';
    END IF;
    FOREACH v_nombre IN ARRAY ARRAY[
        'fn_registrar_venta_v3',
        'fn_registrar_pago_venta_v2',
        'fn_registrar_pago_venta',
        'fn_registrar_cambio_estado_operacion',
        'fn_cambiar_estado_comanda_item'
    ] LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.proname = v_nombre
        ) THEN
            RAISE EXCEPTION 'Falta public.% en este proyecto', v_nombre;
        END IF;
    END LOOP;
    IF (SELECT count(*) FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'app_dat_operacion_offline_idempotencia'
          AND column_name IN ('m01_solicitud', 'm01_id_tienda')) < 2 THEN
        RAISE EXCEPTION 'app_dat_operacion_offline_idempotencia sin columnas m01_solicitud / m01_id_tienda';
    END IF;
END
$preflight$;

-- ---------------------------------------------------------------------------
-- 1) fn_registrar_venta_offline_v4_m01
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_registrar_venta_offline_v4_m01(p_client_uuid uuid, p_id_tpv bigint, p_uuid uuid, p_productos jsonb, p_codigo_promocion text DEFAULT NULL::text, p_denominacion text DEFAULT NULL::text, p_observaciones text DEFAULT NULL::text, p_estado_inicial smallint DEFAULT 1, p_id_cliente bigint DEFAULT NULL::bigint, p_fecha_creacion timestamp with time zone DEFAULT NULL::timestamp with time zone, p_pagos jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_request jsonb;
    v_existing public.app_dat_operacion_offline_idempotencia%ROWTYPE;
    v_matches integer := 0;
    v_seller_id bigint;
    v_store bigint;
    v_result jsonb;
    v_op bigint;
    v_ok boolean;
    v_fecha timestamptz;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_tpv IS NULL OR p_uuid IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    v_request := jsonb_build_object(
        'version', 1,
        'id_tpv', p_id_tpv,
        'uuid_vendedor', p_uuid,
        'productos', p_productos,
        'codigo_promocion', p_codigo_promocion,
        'denominacion', p_denominacion,
        'observaciones', p_observaciones,
        'estado_inicial', p_estado_inicial,
        'id_cliente', p_id_cliente,
        'fecha_creacion', p_fecha_creacion,
        'pagos', p_pagos
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));

    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;

    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'venta_v4'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           -- R33: la fecha no entra en la comparación.
           OR (v_existing.m01_solicitud - 'fecha_creacion') IS DISTINCT FROM (v_request - 'fecha_creacion')
           OR v_existing.m01_id_tienda IS NULL
           OR v_existing.id_operacion IS NULL THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        IF public.fn_config_tienda_puede_escribir(v_existing.m01_id_tienda) IS DISTINCT FROM true
           AND NOT EXISTS (
                SELECT 1
                FROM public.app_dat_vendedor v
                JOIN public.app_dat_trabajadores w ON w.id = v.id_trabajador
                WHERE v.uuid = v_actor
                  AND w.uuid = v_actor
                  AND w.deleted_at IS NULL
                  AND w.id_tienda = v_existing.m01_id_tienda
           ) THEN
            RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object(
            'status', 'success',
            'id_operacion', v_existing.id_operacion,
            'idempotent', true,
            'client_uuid', p_client_uuid,
            'message', 'Operación ya registrada previamente (idempotente)'
        );
    END IF;

    FOR v_seller_id, v_store IN
        SELECT v.id, t.id_tienda
        FROM public.app_dat_vendedor v
        JOIN public.app_dat_trabajadores w ON w.id = v.id_trabajador
        JOIN public.app_dat_tpv t ON t.id = v.id_tpv
        WHERE v.uuid = p_uuid
          AND v.id_tpv = p_id_tpv
          AND t.id = p_id_tpv
          AND w.uuid = p_uuid
          AND w.id_tienda = t.id_tienda
          AND w.deleted_at IS NULL
        FOR SHARE OF v, w, t
    LOOP
        v_matches := v_matches + 1;
    END LOOP;
    IF v_matches IS DISTINCT FROM 1
       OR v_store IS NULL
       OR (p_uuid IS DISTINCT FROM v_actor
           AND public.fn_config_tienda_puede_escribir(v_store) IS DISTINCT FROM true) THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    v_result := public.fn_registrar_venta_v3(
        p_id_tpv, p_uuid, p_productos, p_codigo_promocion,
        p_denominacion, p_observaciones, p_estado_inicial, p_id_cliente
    );
    IF v_result IS NULL OR v_result->>'status' IS DISTINCT FROM 'success' THEN
        RETURN v_result;
    END IF;
    v_op := NULLIF(v_result->>'id_operacion', '')::bigint;
    IF v_op IS NULL THEN
        RAISE EXCEPTION 'Registro de venta incompleto';
    END IF;

    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES
        (p_client_uuid, v_op, 'venta_v4', v_actor, v_request, v_store);

    IF p_fecha_creacion IS NOT NULL THEN
        -- R33: nunca en el futuro (antes: se copiaba tal cual).
        v_fecha := LEAST(p_fecha_creacion, now());
        UPDATE public.app_dat_operaciones
        SET created_at = v_fecha
        WHERE id = v_op;
        UPDATE public.app_dat_operacion_venta
        SET created_at = v_fecha
        WHERE id_operacion = v_op;
    END IF;

    IF p_pagos IS NOT NULL
       AND jsonb_typeof(p_pagos) = 'array'
       AND jsonb_array_length(p_pagos) > 0 THEN
        v_ok := public.fn_registrar_pago_venta_v2(v_op, p_pagos);
        IF NOT COALESCE(v_ok, false) THEN
            RAISE EXCEPTION 'No se pudieron registrar los pagos de la operación %', v_op;
        END IF;
        v_result := v_result || jsonb_build_object('pagos_registrados', true);
    END IF;

    RETURN v_result || jsonb_build_object('idempotent', false, 'client_uuid', p_client_uuid);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_registrar_venta_offline_v4_m01(uuid, bigint, uuid, jsonb, text, text, text, smallint, bigint, timestamp with time zone, jsonb)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_registrar_venta_offline_v4_m01(uuid, bigint, uuid, jsonb, text, text, text, smallint, bigint, timestamp with time zone, jsonb)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) fn_registrar_pago_venta_offline_m01
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_registrar_pago_venta_offline_m01(p_client_uuid uuid, p_id_operacion_venta bigint, p_pagos jsonb, p_uuid_usuario uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_request jsonb;
    v_existing public.app_dat_operacion_offline_idempotencia%ROWTYPE;
    v_store bigint;
    v_sale_actor uuid;
    v_tpv bigint;
    v_seller_ok boolean;
    v_ok boolean;
BEGIN
    IF v_actor IS NULL
       OR p_client_uuid IS NULL
       OR p_id_operacion_venta IS NULL
       OR p_pagos IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    v_request := jsonb_build_object(
        'version', 1,
        'id_operacion_venta', p_id_operacion_venta,
        'uuid_vendedor', p_uuid_usuario,
        'pagos', p_pagos
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));

    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;

    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'pago'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR v_existing.m01_id_tienda IS NULL
           OR v_existing.id_operacion IS DISTINCT FROM p_id_operacion_venta THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        IF public.fn_config_tienda_puede_escribir(v_existing.m01_id_tienda) IS DISTINCT FROM true
           AND NOT EXISTS (
                SELECT 1
                FROM public.app_dat_vendedor s
                JOIN public.app_dat_trabajadores w ON w.id = s.id_trabajador
                WHERE s.uuid = v_actor
                  AND w.uuid = v_actor
                  AND w.deleted_at IS NULL
                  AND w.id_tienda = v_existing.m01_id_tienda
           ) THEN
            RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object(
            'success', true,
            'idempotent', true,
            'id_operacion', v_existing.id_operacion,
            'message', 'Pagos ya registrados previamente (idempotente)'
        );
    END IF;

    SELECT o.id_tienda, o.uuid, ov.id_tpv
    INTO v_store, v_sale_actor, v_tpv
    FROM public.app_dat_operaciones o
    JOIN public.app_dat_operacion_venta ov ON ov.id_operacion = o.id
    WHERE o.id = p_id_operacion_venta
    FOR SHARE OF o, ov;
    IF NOT FOUND OR v_store IS NULL OR v_tpv IS NULL OR v_sale_actor IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    PERFORM 1
    FROM public.app_dat_tpv t
    WHERE t.id = v_tpv AND t.id_tienda = v_store
    FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM public.app_dat_vendedor s
        JOIN public.app_dat_trabajadores w ON w.id = s.id_trabajador
        WHERE s.uuid = v_actor
          AND s.id_tpv = v_tpv
          AND w.uuid = v_actor
          AND w.deleted_at IS NULL
          AND w.id_tienda = v_store
    ) INTO v_seller_ok;

    IF p_uuid_usuario IS NOT NULL AND p_uuid_usuario IS DISTINCT FROM v_actor THEN
        IF p_uuid_usuario IS DISTINCT FROM v_sale_actor
           OR public.fn_config_tienda_puede_escribir(v_store) IS DISTINCT FROM true THEN
            RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
        END IF;
    ELSIF v_actor IS DISTINCT FROM v_sale_actor OR v_seller_ok IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    v_ok := public.fn_registrar_pago_venta(p_id_operacion_venta, p_pagos);
    IF NOT COALESCE(v_ok, false) THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'El servidor rechazó el registro de pagos'
        );
    END IF;

    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES
        (p_client_uuid, p_id_operacion_venta, 'pago', v_actor, v_request, v_store);

    RETURN jsonb_build_object(
        'success', true,
        'idempotent', false,
        'id_operacion', p_id_operacion_venta
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_registrar_pago_venta_offline_m01(uuid, bigint, jsonb, uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_registrar_pago_venta_offline_m01(uuid, bigint, jsonb, uuid)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3) fn_registrar_cambio_estado_offline_m01
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_registrar_cambio_estado_offline_m01(p_client_uuid uuid, p_id_operacion bigint, p_nuevo_estado smallint, p_uuid_usuario uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_request jsonb;
    v_existing public.app_dat_operacion_offline_idempotencia%ROWTYPE;
    v_tipo text;
    v_store bigint;
    v_sale_actor uuid;
    v_tpv bigint;
    v_seller_ok boolean;
BEGIN
    IF v_actor IS NULL
       OR p_client_uuid IS NULL
       OR p_id_operacion IS NULL
       OR p_nuevo_estado IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    v_tipo := 'estado:' || p_nuevo_estado::text;
    v_request := jsonb_build_object(
        'version', 1,
        'id_operacion', p_id_operacion,
        'nuevo_estado', p_nuevo_estado,
        'uuid_vendedor', p_uuid_usuario
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));

    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;

    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM v_tipo
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR v_existing.m01_id_tienda IS NULL
           OR v_existing.id_operacion IS DISTINCT FROM p_id_operacion THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        IF public.fn_config_tienda_puede_escribir(v_existing.m01_id_tienda) IS DISTINCT FROM true
           AND NOT EXISTS (
                SELECT 1
                FROM public.app_dat_vendedor s
                JOIN public.app_dat_trabajadores w ON w.id = s.id_trabajador
                WHERE s.uuid = v_actor
                  AND w.uuid = v_actor
                  AND w.deleted_at IS NULL
                  AND w.id_tienda = v_existing.m01_id_tienda
           ) THEN
            RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object(
            'success', true,
            'idempotent', true,
            'message', 'Cambio de estado ya aplicado (idempotente)'
        );
    END IF;

    SELECT o.id_tienda, o.uuid, ov.id_tpv
    INTO v_store, v_sale_actor, v_tpv
    FROM public.app_dat_operaciones o
    JOIN public.app_dat_operacion_venta ov ON ov.id_operacion = o.id
    WHERE o.id = p_id_operacion
    FOR SHARE OF o, ov;
    IF NOT FOUND OR v_store IS NULL OR v_tpv IS NULL OR v_sale_actor IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    PERFORM 1
    FROM public.app_dat_tpv t
    WHERE t.id = v_tpv AND t.id_tienda = v_store
    FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM public.app_dat_vendedor s
        JOIN public.app_dat_trabajadores w ON w.id = s.id_trabajador
        WHERE s.uuid = v_actor
          AND s.id_tpv = v_tpv
          AND w.uuid = v_actor
          AND w.deleted_at IS NULL
          AND w.id_tienda = v_store
    ) INTO v_seller_ok;

    IF p_uuid_usuario IS NOT NULL AND p_uuid_usuario IS DISTINCT FROM v_actor THEN
        IF p_uuid_usuario IS DISTINCT FROM v_sale_actor
           OR public.fn_config_tienda_puede_escribir(v_store) IS DISTINCT FROM true THEN
            RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
        END IF;
    ELSIF v_actor IS DISTINCT FROM v_sale_actor OR v_seller_ok IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    PERFORM public.fn_registrar_cambio_estado_operacion(
        p_id_operacion, p_nuevo_estado, v_sale_actor
    );

    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES
        (p_client_uuid, p_id_operacion, v_tipo, v_actor, v_request, v_store);

    RETURN jsonb_build_object('success', true, 'idempotent', false);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_registrar_cambio_estado_offline_m01(uuid, bigint, smallint, uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_registrar_cambio_estado_offline_m01(uuid, bigint, smallint, uuid)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4) fn_cambiar_estado_comanda_item_offline_m01
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_cambiar_estado_comanda_item_offline_m01(p_client_uuid uuid, p_id_item bigint, p_nuevo_estado smallint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_request jsonb;
    v_existing public.app_dat_operacion_offline_idempotencia%ROWTYPE;
    v_store bigint;
    v_res jsonb;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_item IS NULL OR p_nuevo_estado IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_request := jsonb_build_object(
        'version', 1,
        'id_item', p_id_item,
        'nuevo_estado', p_nuevo_estado
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'estado_comanda_item'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR v_existing.m01_id_tienda IS NULL
           OR v_existing.id_operacion IS DISTINCT FROM p_id_item THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        RETURN (
            SELECT jsonb_build_object(
                'status', 'success', 'idempotent', true,
                'id_item', ci.id, 'plato', ci.denominacion,
                'estado', ci.estado, 'id_comanda', ci.id_comanda,
                'message', 'Este cambio ya se habia aplicado'
            )
            FROM public.app_dat_comanda_item ci
            WHERE ci.id = v_existing.id_operacion
        );
    END IF;

    SELECT ck.id_tienda INTO v_store
    FROM public.app_dat_comanda_item ci
    JOIN public.app_dat_comanda co ON co.id = ci.id_comanda
    JOIN public.app_dat_cocina ck ON ck.id = co.id_cocina
    WHERE ci.id = p_id_item
    FOR SHARE OF ci;
    IF NOT FOUND OR v_store IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    v_res := public.fn_cambiar_estado_comanda_item(p_id_item, p_nuevo_estado);
    IF (v_res->>'status') IS DISTINCT FROM 'success' THEN
        RETURN v_res;
    END IF;
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, p_id_item, 'estado_comanda_item', v_actor, v_request, v_store);
    RETURN v_res || jsonb_build_object('idempotent', false);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_cambiar_estado_comanda_item_offline_m01(uuid, bigint, smallint)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_cambiar_estado_comanda_item_offline_m01(uuid, bigint, smallint)
  TO authenticated, service_role;
