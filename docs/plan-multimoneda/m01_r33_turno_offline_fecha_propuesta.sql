BEGIN;

-- BORRADOR M01-R33 turno offline: fecha de apertura, carrera y fechas futuras. NO EJECUTAR.
-- Enmienda de los scripts 14 (venta offline v4) y 17 (caja y cocina), ya vivos en newa.
-- Conserva firmas, retornos y la evidencia de idempotencia de M01.
--
-- Problema (docs/issues/ventas_offline_desaparecen_tras_sync.md, main 16-17/11):
--   el sync crea o reutiliza el turno con fecha_apertura = hora del sync.
--   Las ventas offline conservan su hora real y quedan ANTES de la apertura:
--   el vendedor deja de verlas y el turno cuadra en 0.
--
-- Cambios:
--   1. fn_turno_alinear_fecha_apertura (interna): mueve la apertura de un turno
--      ABIERTO solo hacia atrás, nunca al futuro, sin pisar el cierre del turno
--      anterior del mismo TPV + vendedor y con un tope de 72 h.
--   2. fn_alinear_apertura_turno_offline (cliente): la misma alineación cuando el
--      sync reutiliza un turno abierto sin pasar por la apertura con clave.
--   3. fn_apertura_turno_offline:
--      - candado por TPV + vendedor además del candado por client_uuid: dos claves
--        distintas del mismo turno ya no abren en paralelo;
--      - alinea la apertura en las tres ramas: replay, reutilizar y crear.
--        Hoy solo la aplica al crear, sin límites.
--   4. fn_cerrar_turno_offline: fecha_cierre acotada a [fecha_apertura, now()].
--   5. fn_registrar_venta_offline_v4: created_at = LEAST(p_fecha_creacion, now()).
--   6. La huella del replay ignora la fecha (fecha_apertura / fecha_cierre /
--      fecha_creacion). El cliente pasa a enviar UTC con Z (antes, hora local sin
--      offset, que newa lee como UTC porque su TimeZone es UTC). Una clave ya
--      registrada con la lectura vieja tendría otra fecha y el replay caería en
--      42501. La fecha no define el efecto, y además se acota en servidor.
--
-- No crea tablas: no aplica la regla de RLS. Las funciones nuevas son DEFINER con
-- search_path = pg_catalog, igual que las del script 17.

SET LOCAL app.m01_r33_turno_fecha_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r33_turno_fecha_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador R33-turno-fecha: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF has_schema_privilege('anon', 'public', 'CREATE')
       OR has_schema_privilege('authenticated', 'public', 'CREATE') THEN
        RAISE EXCEPTION 'public permite CREATE a roles no confiables';
    END IF;
    -- Cuerpos que dejan los scripts 14 y 17 al aplicarlos sobre el baseline
    -- main (md5 del CREATE de esos borradores; verificados 2026-11-23).
    -- Orden en main: 14 → 17 → 56. No aplicar 56 sobre el cuerpo pre-M01.
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE oid = to_regprocedure('public.fn_apertura_turno_offline(uuid,numeric,bigint,bigint,uuid,boolean,jsonb,text,timestamptz)')
          AND md5(prosrc) = '5cd6609728edb2e6527f9462fa606f4e'
          AND prosecdef AND proowner = 'postgres'::regrole
    ) THEN
        RAISE EXCEPTION 'fn_apertura_turno_offline difiere del cuerpo del script 17 (post-baseline main)';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE oid = to_regprocedure('public.fn_cerrar_turno_offline(uuid,bigint,numeric,uuid,jsonb,text,timestamptz)')
          AND md5(prosrc) = '2e210273ee61a636320a6a1953fde2cb'
          AND prosecdef AND proowner = 'postgres'::regrole
    ) THEN
        RAISE EXCEPTION 'fn_cerrar_turno_offline difiere del cuerpo del script 17 (post-baseline main)';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE oid = to_regprocedure('public.fn_registrar_venta_offline_v4(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint,timestamptz,jsonb)')
          AND md5(prosrc) = 'c67288f94f66356018b68b3da4dbf600'
          AND prosecdef AND proowner = 'postgres'::regrole
    ) THEN
        RAISE EXCEPTION 'fn_registrar_venta_offline_v4 difiere del cuerpo del script 14 (post-baseline main)';
    END IF;
    IF to_regprocedure('public.fn_turno_alinear_fecha_apertura(bigint,timestamptz)') IS NOT NULL
       OR to_regprocedure('public.fn_alinear_apertura_turno_offline(bigint,timestamptz)') IS NOT NULL THEN
        RAISE EXCEPTION 'R33 ya aplicado (existen las funciones de alineacion)';
    END IF;
    IF to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL
       OR to_regprocedure('public.registrar_apertura_turno_v3(numeric,bigint,bigint,uuid,boolean,jsonb,text)') IS NULL
       OR to_regprocedure('public.fn_cerrar_turno_tpv(bigint,numeric,uuid,jsonb,text)') IS NULL
       OR to_regprocedure('public.fn_registrar_venta_v3(bigint,uuid,jsonb,text,text,text,smallint,bigint)') IS NULL
       OR to_regprocedure('public.fn_registrar_pago_venta_v2(bigint,jsonb)') IS NULL THEN
        RAISE EXCEPTION 'Falta una funcion de efecto o el predicado S01';
    END IF;
END;
$preflight$;

-- 1. Interna: alinear la apertura hacia atrás con límites ------------------------

CREATE OR REPLACE FUNCTION public.fn_turno_alinear_fecha_apertura(
    p_id_turno bigint,
    p_fecha_apertura timestamptz
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_turno record;
    v_cierre_previo timestamptz;
    v_fecha timestamptz;
BEGIN
    IF p_id_turno IS NULL OR p_fecha_apertura IS NULL THEN
        RETURN false;
    END IF;

    SELECT ct.id, ct.id_tpv, ct.id_vendedor, ct.estado, ct.fecha_apertura
    INTO v_turno
    FROM public.app_dat_caja_turno ct
    WHERE ct.id = p_id_turno
    FOR UPDATE;
    IF NOT FOUND OR v_turno.estado IS DISTINCT FROM 1 OR v_turno.fecha_apertura IS NULL THEN
        RETURN false;
    END IF;

    -- Nunca en el futuro (reloj o zona horaria del dispositivo).
    v_fecha := LEAST(p_fecha_apertura, now());
    -- Solo hacia atrás.
    IF v_fecha >= v_turno.fecha_apertura THEN
        RETURN false;
    END IF;
    -- Tope de cordura: más de 3 días offline se revisa a mano.
    IF v_turno.fecha_apertura - v_fecha > interval '72 hours' THEN
        RAISE WARNING 'fn_turno_alinear_fecha_apertura: turno % salto % rechazado',
            p_id_turno, v_turno.fecha_apertura - v_fecha;
        RETURN false;
    END IF;

    -- No solapar con el turno anterior del mismo TPV + vendedor.
    SELECT max(COALESCE(p.fecha_cierre, p.fecha_apertura))
    INTO v_cierre_previo
    FROM public.app_dat_caja_turno p
    WHERE p.id_tpv = v_turno.id_tpv
      AND p.id_vendedor = v_turno.id_vendedor
      AND p.id <> v_turno.id
      AND p.fecha_apertura < v_turno.fecha_apertura;
    IF v_cierre_previo IS NOT NULL AND v_fecha <= v_cierre_previo THEN
        v_fecha := v_cierre_previo + interval '1 millisecond';
    END IF;
    IF v_fecha >= v_turno.fecha_apertura THEN
        RETURN false;
    END IF;

    UPDATE public.app_dat_caja_turno
    SET fecha_apertura = v_fecha
    WHERE id = p_id_turno;
    RETURN true;
END;
$function$;

-- 2. Cliente: alinear al reutilizar un turno sin pasar por la apertura con clave ---

CREATE OR REPLACE FUNCTION public.fn_alinear_apertura_turno_offline(
    p_id_turno bigint,
    p_fecha_apertura timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_store bigint;
    v_tpv bigint;
    v_vendedor bigint;
    v_ok boolean;
BEGIN
    IF v_actor IS NULL OR p_id_turno IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    SELECT t.id_tienda, ct.id_tpv, ct.id_vendedor
    INTO v_store, v_tpv, v_vendedor
    FROM public.app_dat_caja_turno ct
    JOIN public.app_dat_tpv t ON t.id = ct.id_tpv
    WHERE ct.id = p_id_turno;
    IF v_store IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    -- Administrador de la tienda o el propio vendedor del turno.
    IF public.fn_config_tienda_puede_escribir(v_store) IS DISTINCT FROM true
       AND NOT EXISTS (
            SELECT 1
            FROM public.app_dat_vendedor s
            JOIN public.app_dat_trabajadores w ON w.id = s.id_trabajador
            WHERE s.id = v_vendedor
              AND s.uuid = v_actor AND w.uuid = v_actor
              AND w.deleted_at IS NULL
              AND w.id_tienda = v_store
       ) THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtextextended(format('apertura_turno:%s:%s', v_tpv, v_vendedor), 0)
    );
    v_ok := public.fn_turno_alinear_fecha_apertura(p_id_turno, p_fecha_apertura);

    RETURN jsonb_build_object(
        'status', 'success',
        'alineado', v_ok,
        'fecha_apertura', (SELECT fecha_apertura FROM public.app_dat_caja_turno WHERE id = p_id_turno)
    );
END;
$function$;

-- 3. Apertura: candado TPV + vendedor y alineación en las tres ramas --------------
--    Diferencias con el script 17 marcadas con "R33".

CREATE OR REPLACE FUNCTION public.fn_apertura_turno_offline(
    p_client_uuid uuid,
    p_efectivo_inicial numeric,
    p_id_tpv bigint,
    p_id_vendedor bigint,
    p_usuario uuid,
    p_maneja_inventario boolean DEFAULT false,
    p_productos jsonb DEFAULT '[]'::jsonb,
    p_observaciones text DEFAULT NULL,
    p_fecha_apertura timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_request jsonb;
    v_existing public.app_dat_operacion_offline_idempotencia%ROWTYPE;
    v_store bigint;
    v_open bigint;
    v_new_id bigint;
    v_allowed boolean;
    v_extra text;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL
       OR p_id_tpv IS NULL OR p_id_vendedor IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_extra := current_setting('app.m01_caja_extra', true);
    PERFORM set_config('app.m01_caja_extra', '', true);
    v_request := jsonb_build_object(
        'version', 1,
        'efectivo_inicial', p_efectivo_inicial,
        'id_tpv', p_id_tpv,
        'id_vendedor', p_id_vendedor,
        'usuario', p_usuario,
        'maneja_inventario', p_maneja_inventario,
        'productos', COALESCE(p_productos, '[]'::jsonb),
        'observaciones', p_observaciones,
        'fecha_apertura', p_fecha_apertura,
        'extra', CASE
            WHEN v_extra IS NULL OR btrim(v_extra) = '' THEN '{}'::jsonb
            ELSE v_extra::jsonb
        END
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    -- R33: dos claves distintas del mismo TPV + vendedor se serializan.
    PERFORM pg_advisory_xact_lock(
        hashtextextended(format('apertura_turno:%s:%s', p_id_tpv, p_id_vendedor), 0)
    );
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'apertura_turno'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           -- R33: la fecha no entra en la comparación (ver cabecera, punto 6).
           OR (v_existing.m01_solicitud - 'fecha_apertura') IS DISTINCT FROM (v_request - 'fecha_apertura')
           OR v_existing.m01_id_tienda IS NULL THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        IF public.fn_config_tienda_puede_escribir(v_existing.m01_id_tienda) IS DISTINCT FROM true
           AND NOT EXISTS (
                SELECT 1
                FROM public.app_dat_vendedor s
                JOIN public.app_dat_trabajadores w ON w.id = s.id_trabajador
                WHERE s.uuid = v_actor AND w.uuid = v_actor
                  AND w.deleted_at IS NULL
                  AND w.id_tienda = v_existing.m01_id_tienda
           ) THEN
            RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
        END IF;
        -- R33: si el turno sigue abierto, recuperar la apertura real.
        PERFORM public.fn_turno_alinear_fecha_apertura(v_existing.id_operacion, p_fecha_apertura);
        RETURN jsonb_build_object(
            'status', 'success', 'idempotent', true,
            'id_turno', v_existing.id_operacion,
            'message', 'Apertura ya procesada'
        );
    END IF;

    SELECT t.id_tienda INTO v_store
    FROM public.app_dat_tpv t
    WHERE t.id = p_id_tpv
    FOR SHARE;
    IF NOT FOUND OR v_store IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_allowed := public.fn_config_tienda_puede_escribir(v_store) IS TRUE
        OR EXISTS (
            SELECT 1
            FROM public.app_dat_vendedor s
            JOIN public.app_dat_trabajadores w ON w.id = s.id_trabajador
            WHERE s.uuid = v_actor AND s.id_tpv = p_id_tpv
              AND w.uuid = v_actor AND w.deleted_at IS NULL
              AND w.id_tienda = v_store
        );
    IF v_allowed IS DISTINCT FROM true
       OR (p_usuario IS NOT NULL AND p_usuario IS DISTINCT FROM v_actor
           AND public.fn_config_tienda_puede_escribir(v_store) IS DISTINCT FROM true) THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    SELECT id INTO v_open
    FROM public.app_dat_caja_turno
    WHERE id_tpv = p_id_tpv AND id_vendedor = p_id_vendedor AND estado = 1
    ORDER BY fecha_apertura DESC NULLS LAST
    LIMIT 1;
    IF v_open IS NOT NULL THEN
        INSERT INTO public.app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
        VALUES (p_client_uuid, v_open, 'apertura_turno', v_actor, v_request, v_store);
        -- R33: antes se reutilizaba sin fecha → apertura = hora del sync.
        PERFORM public.fn_turno_alinear_fecha_apertura(v_open, p_fecha_apertura);
        RETURN jsonb_build_object(
            'status', 'success', 'idempotent', false,
            'id_turno', v_open,
            'message', 'Turno ya estaba abierto; reutilizado'
        );
    END IF;

    v_new_id := public.registrar_apertura_turno_v3(
        p_efectivo_inicial := p_efectivo_inicial,
        p_id_tpv := p_id_tpv,
        p_id_vendedor := p_id_vendedor,
        p_usuario := COALESCE(p_usuario, v_actor),
        p_maneja_inventario := COALESCE(p_maneja_inventario, false),
        p_productos := p_productos,
        p_observaciones := p_observaciones
    );
    IF v_new_id IS NULL THEN
        RAISE EXCEPTION 'El servidor rechazó la apertura' USING ERRCODE = '42501';
    END IF;
    -- R33: mismos límites que al reutilizar (antes: UPDATE sin acotar).
    PERFORM public.fn_turno_alinear_fecha_apertura(v_new_id, p_fecha_apertura);
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, v_new_id, 'apertura_turno', v_actor, v_request, v_store);
    RETURN jsonb_build_object(
        'status', 'success', 'id_turno', v_new_id, 'idempotent', false
    );
END;
$function$;

-- 4. Cierre: fecha acotada ---------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_cerrar_turno_offline(
    p_client_uuid uuid,
    p_id_tpv bigint,
    p_efectivo_real numeric,
    p_usuario uuid,
    p_productos jsonb DEFAULT '[]'::jsonb,
    p_observaciones text DEFAULT NULL,
    p_fecha_cierre timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_request jsonb;
    v_existing public.app_dat_operacion_offline_idempotencia%ROWTYPE;
    v_store bigint;
    v_open bigint;
    v_ok boolean;
    v_extra text;
    v_fecha_apertura timestamptz;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_tpv IS NULL OR p_usuario IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_extra := current_setting('app.m01_caja_extra', true);
    PERFORM set_config('app.m01_caja_extra', '', true);
    v_request := jsonb_build_object(
        'version', 1,
        'id_tpv', p_id_tpv,
        'efectivo_real', p_efectivo_real,
        'usuario', p_usuario,
        'productos', COALESCE(p_productos, '[]'::jsonb),
        'observaciones', p_observaciones,
        'fecha_cierre', p_fecha_cierre,
        'extra', CASE
            WHEN v_extra IS NULL OR btrim(v_extra) = '' THEN '{}'::jsonb
            ELSE v_extra::jsonb
        END
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'cierre_turno'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           -- R33: la fecha no entra en la comparación.
           OR (v_existing.m01_solicitud - 'fecha_cierre') IS DISTINCT FROM (v_request - 'fecha_cierre')
           OR v_existing.m01_id_tienda IS NULL THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        IF public.fn_config_tienda_puede_escribir(v_existing.m01_id_tienda) IS DISTINCT FROM true
           AND NOT EXISTS (
                SELECT 1
                FROM public.app_dat_vendedor s
                JOIN public.app_dat_trabajadores w ON w.id = s.id_trabajador
                WHERE s.uuid = v_actor AND w.uuid = v_actor
                  AND w.deleted_at IS NULL
                  AND w.id_tienda = v_existing.m01_id_tienda
           ) THEN
            RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object(
            'status', 'success', 'idempotent', true,
            'message', 'Cierre ya procesado'
        );
    END IF;

    SELECT t.id_tienda, ct.id
    INTO v_store, v_open
    FROM public.app_dat_tpv t
    LEFT JOIN public.app_dat_caja_turno ct
      ON ct.id_tpv = t.id AND ct.estado = 1 AND ct.creado_por = p_usuario
    WHERE t.id = p_id_tpv
    ORDER BY ct.fecha_apertura DESC NULLS LAST
    LIMIT 1;
    IF v_store IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF public.fn_config_tienda_puede_escribir(v_store) IS DISTINCT FROM true
       AND NOT EXISTS (
            SELECT 1
            FROM public.app_dat_vendedor s
            JOIN public.app_dat_trabajadores w ON w.id = s.id_trabajador
            WHERE s.uuid = v_actor AND s.id_tpv = p_id_tpv
              AND w.uuid = v_actor AND w.deleted_at IS NULL
              AND w.id_tienda = v_store
       ) THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF v_open IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'success', 'idempotent', true,
            'message', 'No hay turno abierto; nada que cerrar'
        );
    END IF;
    SELECT fecha_apertura INTO v_fecha_apertura
    FROM public.app_dat_caja_turno
    WHERE id = v_open;

    v_ok := public.fn_cerrar_turno_tpv(
        p_id_tpv := p_id_tpv,
        p_efectivo_real := p_efectivo_real,
        p_usuario := p_usuario,
        p_productos := p_productos,
        p_observaciones := p_observaciones
    );
    IF v_ok IS DISTINCT FROM true THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El servidor rechazó el cierre del turno'
        );
    END IF;
    IF p_fecha_cierre IS NOT NULL THEN
        -- R33: nunca futura ni anterior a la apertura (antes: sin acotar).
        UPDATE public.app_dat_caja_turno
        SET fecha_cierre = GREATEST(v_fecha_apertura, LEAST(p_fecha_cierre, now()))
        WHERE id = v_open;
    END IF;
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, v_open, 'cierre_turno', v_actor, v_request, v_store);
    RETURN jsonb_build_object('status', 'success', 'idempotent', false);
END;
$function$;

-- 5. Venta offline v4: created_at nunca futura --------------------------------------

CREATE OR REPLACE FUNCTION public.fn_registrar_venta_offline_v4(
    p_client_uuid uuid,
    p_id_tpv bigint,
    p_uuid uuid,
    p_productos jsonb,
    p_codigo_promocion text DEFAULT NULL,
    p_denominacion text DEFAULT NULL,
    p_observaciones text DEFAULT NULL,
    p_estado_inicial smallint DEFAULT 1,
    p_id_cliente bigint DEFAULT NULL,
    p_fecha_creacion timestamp with time zone DEFAULT NULL,
    p_pagos jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
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

-- Privilegios ------------------------------------------------------------------------

REVOKE ALL ON FUNCTION public.fn_turno_alinear_fecha_apertura(bigint,timestamptz)
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_alinear_apertura_turno_offline(bigint,timestamptz)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_alinear_apertura_turno_offline(bigint,timestamptz)
    TO authenticated;
REVOKE ALL ON FUNCTION public.fn_apertura_turno_offline(uuid,numeric,bigint,bigint,uuid,boolean,jsonb,text,timestamptz)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_apertura_turno_offline(uuid,numeric,bigint,bigint,uuid,boolean,jsonb,text,timestamptz)
    TO authenticated;
REVOKE ALL ON FUNCTION public.fn_cerrar_turno_offline(uuid,bigint,numeric,uuid,jsonb,text,timestamptz)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_cerrar_turno_offline(uuid,bigint,numeric,uuid,jsonb,text,timestamptz)
    TO authenticated;
REVOKE ALL ON FUNCTION public.fn_registrar_venta_offline_v4(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint,timestamptz,jsonb)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_registrar_venta_offline_v4(uuid,bigint,uuid,jsonb,text,text,text,smallint,bigint,timestamptz,jsonb)
    TO authenticated;

COMMIT;
