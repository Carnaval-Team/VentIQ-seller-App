BEGIN;

-- BORRADOR MC-026. NO EJECUTAR en main.
-- Registra el cobro nativo y su atribución a cada línea. Un sobrante en CUP
-- no cubre una línea en USD. Una línea pendiente no queda como ingreso.
-- No vuelve a restar el descuento ni crea una segunda fila de cobro.

SET LOCAL app.m01_r15_pagos_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r15_pagos_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador MC-026: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF to_regprocedure('public.fn_m01_registrar_venta_v1(jsonb)') IS NULL
       OR to_regclass('public.app_dat_pago_aplicacion') IS NULL THEN
        RAISE EXCEPTION 'Falta el alta v1 o la atribucion de pago';
    END IF;
    IF to_regprocedure('public.fn_m01_registrar_pagos_v1(jsonb)') IS NOT NULL THEN
        RAISE EXCEPTION 'El cobro producto-v1 ya existe';
    END IF;
END;
$preflight$;

CREATE FUNCTION public.fn_m01_registrar_pagos_v1(p_solicitud jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_uuid uuid;
    v_venta uuid;
    v_tienda bigint;
    v_operacion bigint;
    v_existente public.app_dat_operacion_offline_idempotencia%ROWTYPE;
    v_pago jsonb;
    v_aplicacion jsonb;
    v_linea record;
    v_monto numeric;
    v_suma numeric;
    v_id_pago bigint;
    v_cubiertas integer;
    v_exigidas integer;
BEGIN
    IF v_actor IS NULL OR p_solicitud->>'version_monetaria' IS DISTINCT FROM 'producto-v1' THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_uuid := (p_solicitud->>'client_uuid')::uuid;
    v_venta := (p_solicitud->>'client_uuid_venta')::uuid;
    IF v_uuid IS NULL OR v_venta IS NULL
       OR jsonb_typeof(p_solicitud->'pagos') IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_uuid::text, 0));
    SELECT * INTO v_existente
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = v_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existente.tipo IS DISTINCT FROM 'pago_v1'
           OR v_existente.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existente.m01_solicitud IS DISTINCT FROM p_solicitud THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object(
            'status', 'success', 'idempotent', true,
            'client_uuid', v_uuid, 'id_operacion', v_existente.id_operacion
        );
    END IF;

    SELECT o.id, o.id_tienda INTO v_operacion, v_tienda
    FROM public.app_dat_operaciones o
    JOIN public.app_dat_operacion_venta v ON v.id_operacion = o.id
    WHERE o.uuid = v_venta
      AND v.version_monetaria = 'producto-v1';
    IF NOT FOUND
       OR public.fn_config_tienda_puede_leer(v_tienda) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    PERFORM pg_catalog.set_config('app.m01_venta_v1_interna', 'yes', true);
    FOR v_pago IN SELECT value FROM jsonb_array_elements(p_solicitud->'pagos')
    LOOP
        IF v_pago->>'moneda' IS DISTINCT FROM 'CUP' AND v_pago->>'moneda' IS DISTINCT FROM 'USD' THEN
            RAISE EXCEPTION 'UNSUPPORTED_CURRENCY' USING ERRCODE = '22023';
        END IF;
        IF jsonb_typeof(v_pago->'monto_nativo') IS DISTINCT FROM 'string' THEN
            RAISE EXCEPTION 'DECIMAL_STRING_REQUIRED' USING ERRCODE = '22P02';
        END IF;
        v_monto := (v_pago->>'monto_nativo')::numeric;
        SELECT COALESCE(sum((a->>'monto_nativo')::numeric), 0) INTO v_suma
        FROM jsonb_array_elements(COALESCE(v_pago->'aplicaciones', '[]'::jsonb)) a;
        IF v_monto IS NULL OR v_monto <> v_monto OR v_monto <= 0 OR v_suma IS DISTINCT FROM v_monto THEN
            RAISE EXCEPTION 'El cobro no cuadra con sus lineas' USING ERRCODE = '23514';
        END IF;
        INSERT INTO public.app_dat_pago_venta (
            id_operacion_venta, id_medio_pago, monto, creado_por, moneda,
            tasa_cambio, monto_cup_equivalente
        ) VALUES (
            v_operacion,
            (v_pago->>'id_medio_pago')::smallint,
            v_monto,
            v_actor,
            v_pago->>'moneda',
            NULL,
            NULL
        ) RETURNING id INTO v_id_pago;

        FOR v_aplicacion IN
            SELECT value FROM jsonb_array_elements(v_pago->'aplicaciones')
        LOOP
            SELECT e.id, e.id_linea_cliente, e.moneda_venta, e.importe_neto_nativo,
                   e.tasa_cambio_cup, e.seleccion_pendiente, e.id_medio_pago_seleccionado
              INTO v_linea
            FROM public.app_dat_extraccion_productos e
            WHERE e.id_operacion = v_operacion
              AND e.id_linea_cliente = (v_aplicacion->>'id_linea_cliente')::uuid
              AND e.version_monetaria = 'producto-v1';
            IF NOT FOUND THEN
                RAISE EXCEPTION 'PAYMENT_SELECTION_MISMATCH' USING ERRCODE = '23514';
            END IF;
            IF v_linea.seleccion_pendiente
               OR v_linea.moneda_venta IS DISTINCT FROM v_pago->>'moneda'
               OR v_linea.id_medio_pago_seleccionado IS DISTINCT FROM (v_pago->>'id_medio_pago')::smallint THEN
                RAISE EXCEPTION 'PAYMENT_SELECTION_MISMATCH' USING ERRCODE = '23514';
            END IF;
            IF (
                SELECT COALESCE(sum(a.monto_nativo), 0)
                FROM public.app_dat_pago_aplicacion a
                WHERE a.id_extraccion = v_linea.id
            ) + (v_aplicacion->>'monto_nativo')::numeric > v_linea.importe_neto_nativo THEN
                RAISE EXCEPTION 'El cobro supera la obligacion de la linea'
                    USING ERRCODE = '23514';
            END IF;
            INSERT INTO public.app_dat_pago_aplicacion (
                id_pago, id_extraccion, id_linea_cliente, moneda,
                monto_nativo, tasa_cambio_cup, importe_cup_equivalente
            ) VALUES (
                v_id_pago, v_linea.id, v_linea.id_linea_cliente, v_linea.moneda_venta,
                (v_aplicacion->>'monto_nativo')::numeric, v_linea.tasa_cambio_cup,
                round((v_aplicacion->>'monto_nativo')::numeric * v_linea.tasa_cambio_cup, 2)
            );
        END LOOP;
        UPDATE public.app_dat_pago_venta p
        SET monto_cup_equivalente = (
                SELECT COALESCE(sum(a.importe_cup_equivalente), 0)
                FROM public.app_dat_pago_aplicacion a
                WHERE a.id_pago = p.id
            ),
            tasa_cambio = (
                SELECT CASE
                    WHEN count(DISTINCT a.tasa_cambio_cup) = 1 THEN min(a.tasa_cambio_cup)
                    ELSE NULL
                END
                FROM public.app_dat_pago_aplicacion a
                WHERE a.id_pago = p.id
            )
        WHERE p.id = v_id_pago;
    END LOOP;

    SELECT count(*) INTO v_exigidas
    FROM public.app_dat_extraccion_productos e
    WHERE e.id_operacion = v_operacion
      AND e.version_monetaria = 'producto-v1'
      AND NOT e.seleccion_pendiente
      AND e.importe_neto_nativo > 0;
    SELECT count(*) INTO v_cubiertas
    FROM public.app_dat_extraccion_productos e
    WHERE e.id_operacion = v_operacion
      AND e.version_monetaria = 'producto-v1'
      AND NOT e.seleccion_pendiente
      AND e.importe_neto_nativo > 0
      AND (
          SELECT COALESCE(sum(a.monto_nativo), 0)
          FROM public.app_dat_pago_aplicacion a
          WHERE a.id_extraccion = e.id
      ) = e.importe_neto_nativo;
    UPDATE public.app_dat_operacion_venta
    SET es_pagada = (v_exigidas = v_cubiertas)
    WHERE id_operacion = v_operacion;

    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (v_uuid, v_operacion, 'pago_v1', v_actor, p_solicitud, v_tienda);
    RETURN jsonb_build_object(
        'status', 'success', 'idempotent', false,
        'client_uuid', v_uuid, 'id_operacion', v_operacion,
        'es_pagada', v_exigidas = v_cubiertas
    );
END;
$function$;

-- H9 (2026-11-23): IF anidados por TG_TABLE_NAME — plpgsql no corta AND
-- antes de resolver NEW.version_monetaria en app_dat_pago_venta.
CREATE FUNCTION public.fn_m01_venta_v1_pago_directo()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
    IF pg_catalog.current_setting('app.m01_venta_v1_interna', true) = 'yes' THEN
        RETURN NEW;
    END IF;
    IF TG_TABLE_NAME = 'app_dat_pago_venta' THEN
        IF EXISTS (
            SELECT 1 FROM public.app_dat_operacion_venta v
            WHERE v.id_operacion = NEW.id_operacion_venta
              AND v.version_monetaria = 'producto-v1'
        ) THEN
            RAISE EXCEPTION 'El cobro producto-v1 no se escribe directo'
                USING ERRCODE = '42501';
        END IF;
    ELSIF TG_TABLE_NAME = 'app_dat_operacion_venta' THEN
        IF NEW.version_monetaria = 'producto-v1'
           AND OLD.es_pagada IS DISTINCT FROM NEW.es_pagada THEN
            RAISE EXCEPTION 'El estado de cobro producto-v1 no se escribe directo'
                USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS m01_pago_v1_directo ON public.app_dat_pago_venta;
CREATE TRIGGER m01_pago_v1_directo
    BEFORE INSERT OR UPDATE ON public.app_dat_pago_venta
    FOR EACH ROW EXECUTE FUNCTION public.fn_m01_venta_v1_pago_directo();

DROP TRIGGER IF EXISTS m01_venta_v1_pagada_directa ON public.app_dat_operacion_venta;
CREATE TRIGGER m01_venta_v1_pagada_directa
    BEFORE UPDATE OF es_pagada ON public.app_dat_operacion_venta
    FOR EACH ROW EXECUTE FUNCTION public.fn_m01_venta_v1_pago_directo();

REVOKE ALL ON FUNCTION public.fn_m01_registrar_pagos_v1(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_registrar_pagos_v1(jsonb) TO authenticated;

COMMIT;
