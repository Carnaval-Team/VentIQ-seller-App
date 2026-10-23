BEGIN;

DO $validate$
DECLARE
    v_firma text;
BEGIN
    FOREACH v_firma IN ARRAY ARRAY[
        'public.fn_ejecutar_entrega_fisica_v3(bigint,bigint,bigint,numeric,integer,bigint,bigint,bigint,bigint,uuid,text)',
        'public.fn_fefo_saldos_en_ubicacion(bigint,bigint,bigint,bigint,bigint)',
        'public.fn_saldo_lote_presentacion(bigint,bigint,bigint,bigint,bigint,bigint)',
        'public.fn_registrar_conversion_presentacion(bigint,bigint,bigint,bigint,numeric,numeric,text,numeric,numeric,bigint,bigint,bigint,uuid,text,character varying,character varying,bigint)',
        'public.fn_planificar_entrega_fisica_v2(jsonb,jsonb,bigint,numeric)'
    ]
    LOOP
        IF to_regprocedure(v_firma) IS NULL THEN
            RAISE EXCEPTION 'Falta la dependencia: %', v_firma;
        END IF;
    END LOOP;

    FOREACH v_firma IN ARRAY ARRAY[
        'public.fn_registrar_venta_v3(bigint,uuid,jsonb,text,text,text,smallint,bigint)',
        'public.fn_registrar_venta_mesa_v3(bigint,uuid,jsonb,text,text,text,smallint,bigint,bigint)'
    ]
    LOOP
        IF to_regprocedure(v_firma) IS NULL THEN
            RAISE EXCEPTION 'Falta la función: %', v_firma;
        END IF;
        IF position(
            'IF NOT COALESCE(v_stock_v2, false) THEN'
            IN pg_get_functiondef(to_regprocedure(v_firma))
        ) = 0 THEN
            RAISE EXCEPTION
                'Aplica primero fix_venta_v3_movimiento_inventario_duplicado.sql: %',
                v_firma;
        END IF;
    END LOOP;
END;
$validate$;

CREATE OR REPLACE FUNCTION public.fn_ejecutar_entrega_fisica_v3(
    p_id_producto bigint,
    p_id_ubicacion bigint,
    p_id_presentacion bigint,
    p_cantidad numeric,
    p_origen_cambio integer DEFAULT 3,
    p_id_extraccion bigint DEFAULT NULL::bigint,
    p_id_variante bigint DEFAULT NULL::bigint,
    p_id_opcion_variante bigint DEFAULT NULL::bigint,
    p_id_operacion bigint DEFAULT NULL::bigint,
    p_uuid uuid DEFAULT NULL::uuid,
    p_motivo text DEFAULT 'venta'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
    v_plan jsonb;
    v_conv jsonb;
    v_entrega jsonb;
    v_id_tienda bigint;
    v_es_por_lotes boolean;
    v_saldo_origen numeric;
    v_saldo_destino numeric;
    v_saldo numeric;
    v_sku_producto varchar;
    v_sku_ubicacion varchar;
    v_id_conv bigint;
    v_conversiones_ejecutadas jsonb := '[]'::jsonb;
    v_entregas_lotes jsonb := '[]'::jsonb;
    v_cadena jsonb;
    v_saldos jsonb;
    v_lote record;
    v_pendiente numeric;
    v_tomar numeric;
    v_cantidad_destino numeric;
    v_fraccionable boolean;
    v_id_lote_solicitado bigint;
BEGIN
    SELECT p.id_tienda, COALESCE(p.es_por_lotes, false)
    INTO v_id_tienda, v_es_por_lotes
    FROM public.app_dat_producto p
    WHERE p.id = p_id_producto;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El producto % no existe', p_id_producto;
    END IF;
    PERFORM public.check_user_has_access_to_tienda(v_id_tienda);
    PERFORM public.fn_validar_id_presentacion(p_id_producto, p_id_presentacion);

    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RAISE EXCEPTION 'La cantidad debe ser mayor que cero';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM public.app_dat_layout_almacen la
        JOIN public.app_dat_almacen a ON a.id = la.id_almacen
        WHERE la.id = p_id_ubicacion
          AND la.deleted_at IS NULL
          AND a.id_tienda = v_id_tienda
    ) THEN
        RAISE EXCEPTION 'La ubicación no pertenece a la tienda del producto';
    END IF;

    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            format('%s|%s|%s|%s', p_id_producto, p_id_ubicacion,
                   COALESCE(p_id_variante, 0), COALESCE(p_id_opcion_variante, 0)),
            0
        )
    );

    IF v_es_por_lotes THEN
        PERFORM pg_catalog.pg_advisory_xact_lock(
            pg_catalog.hashtextextended(
                format('entrega_lotes|%s|%s', p_id_producto, p_id_ubicacion), 0
            )
        );

        IF p_id_extraccion IS NOT NULL THEN
            SELECT ep.id_lote INTO v_id_lote_solicitado
            FROM public.app_dat_extraccion_productos ep
            WHERE ep.id = p_id_extraccion
              AND ep.id_producto = p_id_producto
              AND (p_id_operacion IS NULL OR ep.id_operacion = p_id_operacion);
            IF NOT FOUND THEN
                RAISE EXCEPTION 'La extracción no corresponde al producto y operación';
            END IF;
        END IF;

        SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'nivel', c.nivel,
            'id_presentacion', c.id_presentacion,
            'nombre', c.nombre,
            'factor_rel', c.factor_rel,
            'es_fraccionable', c.es_fraccionable
        ) ORDER BY c.nivel), '[]'::jsonb)
        INTO v_cadena
        FROM public.fn_presentaciones_producto(p_id_producto) c;

        SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id_presentacion', s.id_presentacion,
            'cantidad', s.saldo
        )), '[]'::jsonb)
        INTO v_saldos
        FROM (
            SELECT f.id_presentacion, SUM(
                CASE WHEN COALESCE(c.es_fraccionable, false)
                     THEN f.cantidad_final ELSE floor(f.cantidad_final) END
            ) AS saldo
            FROM public.fn_fefo_saldos_en_ubicacion(
                p_id_producto, p_id_ubicacion, NULL,
                p_id_variante, p_id_opcion_variante
            ) f
            JOIN public.fn_presentaciones_producto(p_id_producto) c
              ON c.id_presentacion = f.id_presentacion
            WHERE v_id_lote_solicitado IS NULL
               OR f.id_lote = v_id_lote_solicitado
            GROUP BY f.id_presentacion
        ) s;

        v_plan := public.fn_planificar_entrega_fisica_v2(
            v_cadena, v_saldos, p_id_presentacion, p_cantidad
        ) || jsonb_build_object(
            'presentacion_nombre', (
                SELECT c.nombre
                FROM public.fn_presentaciones_producto(p_id_producto) c
                WHERE c.id_presentacion = p_id_presentacion
            )
        );
    ELSE
        v_plan := public.fn_preview_entrega_fisica_v3(
            p_id_producto, p_id_ubicacion, p_id_presentacion,
            p_cantidad, p_id_variante, p_id_opcion_variante
        );
    END IF;

    IF v_plan->>'status' IS DISTINCT FROM 'success' THEN
        RETURN v_plan;
    END IF;

    SELECT MIN(s.sku_producto), MIN(s.sku_ubicacion)
    INTO v_sku_producto, v_sku_ubicacion
    FROM public.fn_stock_saldos_presentacion(
        p_id_producto, NULL, p_id_ubicacion, true
    ) s
    WHERE (p_id_variante IS NULL OR s.id_variante IS NOT DISTINCT FROM p_id_variante)
      AND (p_id_opcion_variante IS NULL OR s.id_opcion_variante IS NOT DISTINCT FROM p_id_opcion_variante);

    FOR v_conv IN SELECT value FROM jsonb_array_elements(v_plan->'conversiones')
    LOOP
        IF v_es_por_lotes THEN
            v_pendiente := (v_conv->>'cantidad_origen')::numeric;
            SELECT COALESCE(c.es_fraccionable, false)
            INTO v_fraccionable
            FROM public.fn_presentaciones_producto(p_id_producto) c
            WHERE c.id_presentacion = (v_conv->>'id_presentacion_origen')::bigint;

            FOR v_lote IN
                SELECT f.*
                FROM public.fn_fefo_saldos_en_ubicacion(
                    p_id_producto, p_id_ubicacion,
                    (v_conv->>'id_presentacion_origen')::bigint,
                    p_id_variante, p_id_opcion_variante
                ) f
                WHERE v_id_lote_solicitado IS NULL
                   OR f.id_lote = v_id_lote_solicitado
                ORDER BY f.fecha_vencimiento ASC NULLS LAST, f.id_lote,
                         f.id_variante NULLS FIRST, f.id_opcion_variante NULLS FIRST
            LOOP
                EXIT WHEN v_pendiente <= 0;
                v_tomar := LEAST(v_pendiente, v_lote.cantidad_final);
                IF NOT COALESCE(v_fraccionable, false) THEN
                    v_tomar := floor(v_tomar);
                END IF;
                CONTINUE WHEN v_tomar <= 0;
                v_cantidad_destino := v_tomar *
                    (v_conv->>'cantidad_destino')::numeric /
                    NULLIF((v_conv->>'cantidad_origen')::numeric, 0);
                IF v_cantidad_destino IS NULL OR v_cantidad_destino <= 0 THEN
                    RAISE EXCEPTION 'El plan contiene una conversión inválida';
                END IF;
                v_saldo_destino := public.fn_saldo_lote_presentacion(
                    p_id_producto, p_id_ubicacion,
                    (v_conv->>'id_presentacion_destino')::bigint,
                    v_lote.id_lote, v_lote.id_variante, v_lote.id_opcion_variante
                );
                v_id_conv := public.fn_registrar_conversion_presentacion(
                    p_id_producto, p_id_ubicacion,
                    (v_conv->>'id_presentacion_origen')::bigint,
                    (v_conv->>'id_presentacion_destino')::bigint,
                    v_tomar, v_cantidad_destino, 'abrir',
                    v_lote.cantidad_final, v_saldo_destino,
                    v_lote.id_variante, v_lote.id_opcion_variante,
                    p_id_operacion, p_uuid, p_motivo,
                    v_lote.sku_producto::varchar, v_lote.sku_ubicacion::varchar,
                    v_lote.id_lote
                );
                v_conversiones_ejecutadas := v_conversiones_ejecutadas ||
                    (v_conv || jsonb_build_object(
                        'id_conversion', v_id_conv,
                        'id_lote', v_lote.id_lote,
                        'cantidad_origen', v_tomar,
                        'cantidad_destino', v_cantidad_destino
                    ));
                v_pendiente := v_pendiente - v_tomar;
            END LOOP;
            IF v_pendiente > 0 THEN
                RAISE EXCEPTION 'PLAN_STALE: saldo por lote insuficiente durante conversión';
            END IF;
            CONTINUE;
        END IF;

        SELECT COALESCE(SUM(s.saldo), 0) INTO v_saldo_origen
        FROM public.fn_stock_saldos_presentacion(p_id_producto, NULL, p_id_ubicacion, true) s
        WHERE s.id_presentacion = (v_conv->>'id_presentacion_origen')::bigint
          AND (p_id_variante IS NULL OR s.id_variante IS NOT DISTINCT FROM p_id_variante)
          AND (p_id_opcion_variante IS NULL OR s.id_opcion_variante IS NOT DISTINCT FROM p_id_opcion_variante);
        SELECT COALESCE(SUM(s.saldo), 0) INTO v_saldo_destino
        FROM public.fn_stock_saldos_presentacion(p_id_producto, NULL, p_id_ubicacion, true) s
        WHERE s.id_presentacion = (v_conv->>'id_presentacion_destino')::bigint
          AND (p_id_variante IS NULL OR s.id_variante IS NOT DISTINCT FROM p_id_variante)
          AND (p_id_opcion_variante IS NULL OR s.id_opcion_variante IS NOT DISTINCT FROM p_id_opcion_variante);
        IF v_saldo_origen < (v_conv->>'cantidad_origen')::numeric THEN
            RAISE EXCEPTION 'PLAN_STALE: saldo insuficiente durante conversión';
        END IF;
        v_id_conv := public.fn_registrar_conversion_presentacion(
            p_id_producto, p_id_ubicacion,
            (v_conv->>'id_presentacion_origen')::bigint,
            (v_conv->>'id_presentacion_destino')::bigint,
            (v_conv->>'cantidad_origen')::numeric,
            (v_conv->>'cantidad_destino')::numeric, 'abrir',
            v_saldo_origen, v_saldo_destino,
            p_id_variante, p_id_opcion_variante, p_id_operacion, p_uuid,
            p_motivo, v_sku_producto, v_sku_ubicacion
        );
        v_conversiones_ejecutadas := v_conversiones_ejecutadas ||
            (v_conv || jsonb_build_object('id_conversion', v_id_conv));
    END LOOP;

    FOR v_entrega IN SELECT value FROM jsonb_array_elements(v_plan->'entregas_fisicas')
    LOOP
        IF v_es_por_lotes THEN
            v_pendiente := (v_entrega->>'cantidad')::numeric;
            SELECT COALESCE(c.es_fraccionable, false)
            INTO v_fraccionable
            FROM public.fn_presentaciones_producto(p_id_producto) c
            WHERE c.id_presentacion = (v_entrega->>'id_presentacion')::bigint;
            FOR v_lote IN
                SELECT f.*
                FROM public.fn_fefo_saldos_en_ubicacion(
                    p_id_producto, p_id_ubicacion,
                    (v_entrega->>'id_presentacion')::bigint,
                    p_id_variante, p_id_opcion_variante
                ) f
                WHERE v_id_lote_solicitado IS NULL
                   OR f.id_lote = v_id_lote_solicitado
                ORDER BY f.fecha_vencimiento ASC NULLS LAST, f.id_lote,
                         f.id_variante NULLS FIRST, f.id_opcion_variante NULLS FIRST
            LOOP
                EXIT WHEN v_pendiente <= 0;
                v_tomar := LEAST(v_pendiente, v_lote.cantidad_final);
                IF NOT COALESCE(v_fraccionable, false) THEN
                    v_tomar := floor(v_tomar);
                END IF;
                CONTINUE WHEN v_tomar <= 0;
                INSERT INTO public.app_dat_inventario_productos (
                    id_producto, id_variante, id_opcion_variante,
                    id_ubicacion, id_presentacion, id_lote,
                    cantidad_inicial, cantidad_final,
                    sku_producto, sku_ubicacion, origen_cambio,
                    id_extraccion, created_at
                ) VALUES (
                    p_id_producto, v_lote.id_variante, v_lote.id_opcion_variante,
                    p_id_ubicacion, (v_entrega->>'id_presentacion')::bigint,
                    v_lote.id_lote, v_lote.cantidad_final,
                    v_lote.cantidad_final - v_tomar,
                    v_lote.sku_producto, v_lote.sku_ubicacion,
                    p_origen_cambio, p_id_extraccion, pg_catalog.now()
                );
                v_entregas_lotes := v_entregas_lotes || jsonb_build_object(
                    'id_lote', v_lote.id_lote,
                    'id_presentacion', (v_entrega->>'id_presentacion')::bigint,
                    'id_variante', v_lote.id_variante,
                    'id_opcion_variante', v_lote.id_opcion_variante,
                    'cantidad', v_tomar
                );
                v_pendiente := v_pendiente - v_tomar;
            END LOOP;
            IF v_pendiente > 0 THEN
                RAISE EXCEPTION 'PLAN_STALE: saldo por lote insuficiente durante entrega';
            END IF;
            CONTINUE;
        END IF;

        SELECT COALESCE(SUM(s.saldo), 0), MIN(s.sku_producto), MIN(s.sku_ubicacion)
        INTO v_saldo, v_sku_producto, v_sku_ubicacion
        FROM public.fn_stock_saldos_presentacion(p_id_producto, NULL, p_id_ubicacion, true) s
        WHERE s.id_presentacion = (v_entrega->>'id_presentacion')::bigint
          AND (p_id_variante IS NULL OR s.id_variante IS NOT DISTINCT FROM p_id_variante)
          AND (p_id_opcion_variante IS NULL OR s.id_opcion_variante IS NOT DISTINCT FROM p_id_opcion_variante);
        IF v_saldo < (v_entrega->>'cantidad')::numeric THEN
            RAISE EXCEPTION 'PLAN_STALE: saldo insuficiente durante entrega';
        END IF;
        INSERT INTO public.app_dat_inventario_productos (
            id_producto, id_variante, id_opcion_variante, id_ubicacion,
            id_presentacion, cantidad_inicial, cantidad_final,
            sku_producto, sku_ubicacion, origen_cambio, id_extraccion, created_at
        ) VALUES (
            p_id_producto, p_id_variante, p_id_opcion_variante, p_id_ubicacion,
            (v_entrega->>'id_presentacion')::bigint, v_saldo,
            v_saldo - (v_entrega->>'cantidad')::numeric,
            v_sku_producto, v_sku_ubicacion, p_origen_cambio,
            p_id_extraccion, pg_catalog.now()
        );
    END LOOP;

    IF v_es_por_lotes AND p_id_extraccion IS NOT NULL THEN
        UPDATE public.app_dat_extraccion_productos ep
        SET id_lote = (
            SELECT CASE WHEN COUNT(DISTINCT (x->>'id_lote')::bigint) = 1
                        THEN MIN((x->>'id_lote')::bigint) ELSE NULL END
            FROM jsonb_array_elements(v_entregas_lotes) x
        )
        WHERE ep.id = p_id_extraccion AND ep.id_producto = p_id_producto;
    END IF;

    RETURN v_plan || jsonb_build_object(
        'conversiones', v_conversiones_ejecutadas,
        'entregas_por_lote', v_entregas_lotes,
        'executed', true
    );
END;
$function$;

COMMIT;

SELECT
    p.oid::regprocedure AS funcion,
    position('v_entregas_lotes' IN p.prosrc) > 0 AS descuento_por_lotes,
    position('fn_fefo_saldos_en_ubicacion' IN p.prosrc) > 0 AS usa_fefo,
    p.prosecdef AS security_definer
FROM pg_proc p
WHERE p.oid = 'public.fn_ejecutar_entrega_fisica_v3(bigint,bigint,bigint,numeric,integer,bigint,bigint,bigint,bigint,uuid,text)'::regprocedure;
