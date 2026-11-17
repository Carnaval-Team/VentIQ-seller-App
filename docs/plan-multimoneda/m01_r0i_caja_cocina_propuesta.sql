BEGIN;

-- BORRADOR M01-R0i caja y cocina. NO EJECUTAR.
-- Endurece las funciones con clave que el TPV ya llama: apertura, cierre,
-- egreso, pedido de mesa y estado de plato. Conserva las firmas.
-- El actor es auth.uid(). El replay compara tipo, actor, solicitud y tienda
-- y no repite el efecto. Una clave vieja sin evidencia se retiene.
-- No crea columnas: usa la evidencia del script 13. No toca Admin Lite.
--
-- El pedido pasa a fn_pedir_item_cuenta_v2. Hasta aplicar este script el
-- cliente sigue llamando v2 primero: la función viva todavía delega en la
-- versión anterior. En el mismo despliegue, pedirItem debe probar primero
-- fn_pedir_item_cuenta_offline.
--
-- La apertura y el cierre con mapa de monedas graban ese mapa en la huella
-- (app.m01_caja_extra, local a la transacción). La misma clave con otro
-- desglose se rechaza. El replay no repite el arqueo.

SET LOCAL app.m01_r0i_caja_cocina_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r0i_caja_cocina_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador R0i-caja-cocina: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF has_schema_privilege('anon', 'public', 'CREATE')
       OR has_schema_privilege('authenticated', 'public', 'CREATE') THEN
        RAISE EXCEPTION 'public permite CREATE a roles no confiables';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE oid = to_regprocedure('public.fn_apertura_turno_offline(uuid,numeric,bigint,bigint,uuid,boolean,jsonb,text,timestamptz)')
          AND md5(prosrc) = '8c7ddcbfb2dccd447754b2722d5d33af'
          AND prosecdef AND proowner = 'postgres'::regrole
    ) THEN
        RAISE EXCEPTION 'fn_apertura_turno_offline difiere del baseline newa';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE oid = to_regprocedure('public.fn_cerrar_turno_offline(uuid,bigint,numeric,uuid,jsonb,text,timestamptz)')
          AND md5(prosrc) = '5ba47aac84e2f8fcac8bffdf67199558'
          AND prosecdef AND proowner = 'postgres'::regrole
    ) THEN
        RAISE EXCEPTION 'fn_cerrar_turno_offline difiere del baseline newa';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE oid = to_regprocedure('public.fn_registrar_egreso_offline(uuid,bigint,numeric,character varying,character varying,text,smallint,uuid)')
          AND md5(prosrc) = '548113889a72572ca1c3c851f21cf174'
          AND prosecdef AND proowner = 'postgres'::regrole
    ) THEN
        RAISE EXCEPTION 'fn_registrar_egreso_offline difiere del baseline newa';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE oid = to_regprocedure('public.fn_pedir_item_cuenta_offline(uuid,bigint,bigint,numeric,numeric,bigint,bigint,bigint,bigint,numeric,bigint,jsonb,jsonb,text,text,text,uuid,boolean)')
          AND md5(prosrc) = '637e84dfae7d78c14e8cb02357be5104'
          AND prosecdef AND proowner = 'postgres'::regrole
    ) THEN
        RAISE EXCEPTION 'fn_pedir_item_cuenta_offline difiere del baseline newa';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE oid = to_regprocedure('public.fn_cambiar_estado_comanda_item_offline(uuid,bigint,smallint)')
          AND md5(prosrc) = 'ffbb357d8b223c2589fc37d441723b78'
          AND prosecdef AND proowner = 'postgres'::regrole
    ) THEN
        RAISE EXCEPTION 'fn_cambiar_estado_comanda_item_offline difiere del baseline newa';
    END IF;
    IF to_regprocedure('public.fn_pedir_item_cuenta_v2(bigint,bigint,numeric,numeric,bigint,bigint,bigint,bigint,numeric,bigint,jsonb,jsonb,text,character varying,character varying,uuid,boolean)') IS NULL
       OR to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL
       OR to_regprocedure('public.registrar_apertura_turno_v3(numeric,bigint,bigint,uuid,boolean,jsonb,text)') IS NULL
       OR to_regprocedure('public.fn_cerrar_turno_tpv(bigint,numeric,uuid,jsonb,text)') IS NULL
       OR to_regprocedure('public.registrar_egreso_parcial_v2(bigint,numeric,character varying,character varying,text,smallint)') IS NULL
       OR to_regprocedure('public.fn_cambiar_estado_comanda_item(bigint,smallint)') IS NULL THEN
        RAISE EXCEPTION 'Falta una funcion de efecto o el predicado S01';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'public.app_dat_operacion_offline_idempotencia'::regclass
          AND attname = 'm01_solicitud' AND atttypid = 'jsonb'::regtype AND NOT attisdropped
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'public.app_dat_operacion_offline_idempotencia'::regclass
          AND attname = 'm01_id_tienda' AND atttypid = 'bigint'::regtype AND NOT attisdropped
    ) THEN
        RAISE EXCEPTION 'Falta la evidencia compartida de idempotencia';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_class
        WHERE oid = 'public.app_dat_operacion_offline_idempotencia'::regclass
          AND (NOT relrowsecurity OR relowner <> 'postgres'::regrole)
    ) OR has_any_column_privilege('authenticated', 'public.app_dat_operacion_offline_idempotencia', 'INSERT')
       OR has_any_column_privilege('authenticated', 'public.app_dat_operacion_offline_idempotencia', 'UPDATE')
       OR has_table_privilege('authenticated', 'public.app_dat_operacion_offline_idempotencia', 'DELETE') THEN
        RAISE EXCEPTION 'Falta el aislamiento M01 de idempotencia';
    END IF;
    IF to_regprocedure('public.fn_registrar_egreso_offline_v2(uuid,bigint,numeric,character varying,character varying,text,smallint,uuid,text)') IS NULL
       OR to_regprocedure('public.fn_apertura_turno_offline_usd(uuid,numeric,bigint,bigint,uuid,boolean,jsonb,text,timestamptz,numeric)') IS NULL
       OR to_regprocedure('public.fn_cerrar_turno_offline_usd(uuid,bigint,numeric,uuid,jsonb,text,timestamptz,numeric)') IS NULL
       OR to_regprocedure('public.fn_apertura_turno_offline_monedas(uuid,bigint,bigint,uuid,boolean,jsonb,jsonb,text,timestamptz)') IS NULL
       OR to_regprocedure('public.fn_cerrar_turno_offline_monedas(uuid,bigint,uuid,jsonb,jsonb,text,timestamptz)') IS NULL THEN
        RAISE EXCEPTION 'Falta un envoltorio de divisa';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_proc
        WHERE proname IN (
            'fn_registrar_egreso_offline_v2',
            'fn_apertura_turno_offline_usd',
            'fn_cerrar_turno_offline_usd',
            'fn_apertura_turno_offline_monedas',
            'fn_cerrar_turno_offline_monedas'
        )
          AND prosrc LIKE '%m01_solicitud%'
    ) THEN
        RAISE EXCEPTION 'Un envoltorio de divisa ya fue endurecido';
    END IF;
    IF to_regprocedure('public.fn_m01_cerrar_turno_residual(uuid,bigint,text)') IS NOT NULL THEN
        RAISE EXCEPTION 'fn_m01_cerrar_turno_residual ya existe';
    END IF;
END;
$preflight$;

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
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'apertura_turno'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
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
    IF p_fecha_apertura IS NOT NULL THEN
        UPDATE public.app_dat_caja_turno
        SET fecha_apertura = p_fecha_apertura
        WHERE id = v_new_id;
    END IF;
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, v_new_id, 'apertura_turno', v_actor, v_request, v_store);
    RETURN jsonb_build_object(
        'status', 'success', 'id_turno', v_new_id, 'idempotent', false
    );
END;
$function$;

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
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
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
        UPDATE public.app_dat_caja_turno
        SET fecha_cierre = p_fecha_cierre
        WHERE id = v_open;
    END IF;
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, v_open, 'cierre_turno', v_actor, v_request, v_store);
    RETURN jsonb_build_object('status', 'success', 'idempotent', false);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_registrar_egreso_offline(
    p_client_uuid uuid,
    p_id_turno bigint,
    p_monto_entrega numeric,
    p_nombre_recibe character varying,
    p_nombre_autoriza character varying,
    p_motivo_entrega text,
    p_id_medio_pago smallint DEFAULT NULL,
    p_uuid_usuario uuid DEFAULT NULL
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
    v_result jsonb;
    v_new_id bigint;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_turno IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_request := jsonb_build_object(
        'version', 1,
        'id_turno', p_id_turno,
        'monto_entrega', p_monto_entrega,
        'nombre_recibe', p_nombre_recibe,
        'nombre_autoriza', p_nombre_autoriza,
        'motivo_entrega', p_motivo_entrega,
        'id_medio_pago', p_id_medio_pago,
        'uuid_usuario', p_uuid_usuario,
        'moneda', 'CUP'
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'egreso'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
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
            'success', true, 'idempotent', true,
            'egreso_id', v_existing.id_operacion,
            'message', 'Egreso ya registrado previamente (idempotente)'
        );
    END IF;

    SELECT t.id_tienda INTO v_store
    FROM public.app_dat_caja_turno ct
    JOIN public.app_dat_tpv t ON t.id = ct.id_tpv
    WHERE ct.id = p_id_turno
    FOR SHARE OF ct;
    IF NOT FOUND OR v_store IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF (p_uuid_usuario IS NOT NULL AND p_uuid_usuario IS DISTINCT FROM v_actor
        AND public.fn_config_tienda_puede_escribir(v_store) IS DISTINCT FROM true)
       OR (public.fn_config_tienda_puede_escribir(v_store) IS DISTINCT FROM true
           AND NOT EXISTS (
                SELECT 1
                FROM public.app_dat_vendedor s
                JOIN public.app_dat_trabajadores w ON w.id = s.id_trabajador
                WHERE s.uuid = v_actor AND w.uuid = v_actor
                  AND w.deleted_at IS NULL AND w.id_tienda = v_store
           )) THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    v_result := public.registrar_egreso_parcial_v2(
        p_id_turno := p_id_turno,
        p_monto_entrega := p_monto_entrega,
        p_nombre_recibe := p_nombre_recibe,
        p_nombre_autoriza := p_nombre_autoriza,
        p_motivo_entrega := p_motivo_entrega,
        p_id_medio_pago := p_id_medio_pago
    );
    IF v_result IS NULL OR (v_result->>'success') IS DISTINCT FROM 'true' THEN
        RETURN COALESCE(v_result, jsonb_build_object(
            'success', false, 'message', 'El servidor rechazó el egreso'
        ));
    END IF;
    v_new_id := NULLIF(v_result->>'egreso_id', '')::bigint;
    IF v_new_id IS NULL THEN
        RAISE EXCEPTION 'El servidor rechazó el egreso' USING ERRCODE = '42501';
    END IF;
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, v_new_id, 'egreso', v_actor, v_request, v_store);
    RETURN v_result || jsonb_build_object('idempotent', false, 'client_uuid', p_client_uuid);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_registrar_egreso_offline_v2(
    p_client_uuid uuid,
    p_id_turno bigint,
    p_monto_entrega numeric,
    p_nombre_recibe character varying,
    p_nombre_autoriza character varying,
    p_motivo_entrega text,
    p_id_medio_pago smallint DEFAULT NULL,
    p_uuid_usuario uuid DEFAULT NULL,
    p_moneda text DEFAULT 'CUP'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_moneda text := upper(btrim(COALESCE(NULLIF(p_moneda, ''), 'CUP')));
    v_request jsonb;
    v_existing public.app_dat_operacion_offline_idempotencia%ROWTYPE;
    v_store bigint;
    v_result jsonb;
    v_new_id bigint;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_turno IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.monedas m WHERE m.codigo = v_moneda AND m.activo
    ) THEN
        RAISE EXCEPTION 'La moneda % no existe o no está activa en el catálogo', v_moneda;
    END IF;
    v_request := jsonb_build_object(
        'version', 1,
        'id_turno', p_id_turno,
        'monto_entrega', p_monto_entrega,
        'nombre_recibe', p_nombre_recibe,
        'nombre_autoriza', p_nombre_autoriza,
        'motivo_entrega', p_motivo_entrega,
        'id_medio_pago', p_id_medio_pago,
        'uuid_usuario', p_uuid_usuario,
        'moneda', v_moneda
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'egreso'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR v_existing.m01_id_tienda IS NULL THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object(
            'success', true, 'idempotent', true,
            'egreso_id', v_existing.id_operacion,
            'message', 'Egreso ya registrado previamente (idempotente)'
        );
    END IF;

    SELECT t.id_tienda INTO v_store
    FROM public.app_dat_caja_turno ct
    JOIN public.app_dat_tpv t ON t.id = ct.id_tpv
    WHERE ct.id = p_id_turno;
    IF NOT FOUND OR v_store IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    v_result := public.registrar_egreso_parcial_v2(
        p_id_turno := p_id_turno,
        p_monto_entrega := p_monto_entrega,
        p_nombre_recibe := p_nombre_recibe,
        p_nombre_autoriza := p_nombre_autoriza,
        p_motivo_entrega := p_motivo_entrega,
        p_id_medio_pago := p_id_medio_pago
    );
    IF v_result IS NULL OR (v_result->>'success') IS DISTINCT FROM 'true' THEN
        RETURN COALESCE(v_result, jsonb_build_object(
            'success', false, 'message', 'El servidor rechazó el egreso'
        ));
    END IF;
    v_new_id := NULLIF(v_result->>'egreso_id', '')::bigint;
    IF v_new_id IS NULL THEN
        RAISE EXCEPTION 'El servidor rechazó el egreso' USING ERRCODE = '42501';
    END IF;
    UPDATE public.app_dat_entregas_parciales_caja
    SET moneda = v_moneda
    WHERE id = v_new_id;
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, v_new_id, 'egreso', v_actor, v_request, v_store);
    RETURN v_result || jsonb_build_object('idempotent', false, 'client_uuid', p_client_uuid);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_pedir_item_cuenta_offline(
    p_client_uuid uuid,
    p_id_cuenta bigint,
    p_id_producto bigint,
    p_cantidad numeric,
    p_precio_unitario numeric,
    p_id_variante bigint DEFAULT NULL,
    p_id_opcion_variante bigint DEFAULT NULL,
    p_id_presentacion bigint DEFAULT NULL,
    p_id_ubicacion bigint DEFAULT NULL,
    p_precio_base numeric DEFAULT NULL,
    p_id_metodo_pago bigint DEFAULT NULL,
    p_promotion_data jsonb DEFAULT NULL,
    p_inventory_data jsonb DEFAULT NULL,
    p_notas text DEFAULT NULL,
    p_sku_producto text DEFAULT NULL,
    p_sku_ubicacion text DEFAULT NULL,
    p_uuid_vendedor uuid DEFAULT NULL,
    p_forzar_sin_stock boolean DEFAULT false
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
    v_res jsonb;
    v_id_item bigint;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_cuenta IS NULL OR p_id_producto IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_request := jsonb_build_object(
        'version', 1,
        'id_cuenta', p_id_cuenta,
        'id_producto', p_id_producto,
        'cantidad', p_cantidad,
        'precio_unitario', p_precio_unitario,
        'id_variante', p_id_variante,
        'id_opcion_variante', p_id_opcion_variante,
        'id_presentacion', p_id_presentacion,
        'id_ubicacion', p_id_ubicacion,
        'precio_base', p_precio_base,
        'id_metodo_pago', p_id_metodo_pago,
        'promotion_data', p_promotion_data,
        'inventory_data', p_inventory_data,
        'notas', p_notas,
        'sku_producto', p_sku_producto,
        'sku_ubicacion', p_sku_ubicacion,
        'uuid_vendedor', p_uuid_vendedor,
        'forzar_sin_stock', COALESCE(p_forzar_sin_stock, false)
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'pedir_item'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR v_existing.m01_id_tienda IS NULL THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        RETURN (
            SELECT jsonb_build_object(
                'status', 'success', 'idempotent', true,
                'id_item', i.id, 'id_cuenta', i.id_cuenta,
                'origen', COALESCE(i.origen_stock, 'barra'),
                'origen_stock', i.origen_stock,
                'id_cocina', i.id_cocina, 'cocina', ck.denominacion,
                'stock_movido', i.stock_movido,
                'id_comanda_item', i.id_comanda_item,
                'id_comanda', ci.id_comanda, 'numero_comanda', co.numero,
                'estado_servicio', i.estado_servicio,
                'message', 'Este pedido ya se habia registrado'
            )
            FROM public.app_dat_mesa_cuenta_item i
            LEFT JOIN public.app_dat_cocina ck ON ck.id = i.id_cocina
            LEFT JOIN public.app_dat_comanda_item ci ON ci.id = i.id_comanda_item
            LEFT JOIN public.app_dat_comanda co ON co.id = ci.id_comanda
            WHERE i.id = v_existing.id_operacion
        );
    END IF;

    SELECT c.id_tienda INTO v_store
    FROM public.app_dat_mesa_cuenta_abierta c
    WHERE c.id = p_id_cuenta
    FOR SHARE;
    IF NOT FOUND OR v_store IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    v_res := public.fn_pedir_item_cuenta_v2(
        p_id_cuenta, p_id_producto, p_cantidad, p_precio_unitario,
        p_id_variante, p_id_opcion_variante, p_id_presentacion, p_id_ubicacion,
        p_precio_base, p_id_metodo_pago, p_promotion_data, p_inventory_data,
        p_notas, p_sku_producto, p_sku_ubicacion, p_uuid_vendedor,
        COALESCE(p_forzar_sin_stock, false)
    );
    IF (v_res->>'status') IS DISTINCT FROM 'success' THEN
        RETURN v_res;
    END IF;
    v_id_item := NULLIF(v_res->>'id_item', '')::bigint;
    IF v_id_item IS NULL THEN
        RAISE EXCEPTION 'El servidor rechazó el pedido' USING ERRCODE = '42501';
    END IF;
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, v_id_item, 'pedir_item', v_actor, v_request, v_store);
    RETURN v_res || jsonb_build_object('idempotent', false);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_cambiar_estado_comanda_item_offline(
    p_client_uuid uuid,
    p_id_item bigint,
    p_nuevo_estado smallint
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

CREATE OR REPLACE FUNCTION public.fn_apertura_turno_offline_usd(
    p_client_uuid uuid,
    p_efectivo_inicial numeric,
    p_id_tpv bigint,
    p_id_vendedor bigint,
    p_usuario uuid,
    p_maneja_inventario boolean DEFAULT false,
    p_productos jsonb DEFAULT '[]'::jsonb,
    p_observaciones text DEFAULT NULL,
    p_fecha_apertura timestamptz DEFAULT NULL,
    p_efectivo_inicial_usd numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_result jsonb;
    v_turno_id bigint;
BEGIN
    IF NULLIF(btrim(COALESCE(current_setting('app.m01_caja_extra', true), '')), '') IS NULL THEN
        PERFORM set_config(
            'app.m01_caja_extra',
            jsonb_build_object('efectivo_usd', p_efectivo_inicial_usd)::text,
            true
        );
    END IF;
    v_result := public.fn_apertura_turno_offline(
        p_client_uuid, p_efectivo_inicial, p_id_tpv, p_id_vendedor, p_usuario,
        p_maneja_inventario, p_productos, p_observaciones, p_fecha_apertura
    );
    IF COALESCE((v_result->>'idempotent')::boolean, false) THEN
        RETURN v_result;
    END IF;
    v_turno_id := NULLIF(v_result->>'id_turno', '')::bigint;
    IF v_turno_id IS NOT NULL THEN
        UPDATE public.app_dat_caja_turno
        SET efectivo_inicial_usd = COALESCE(p_efectivo_inicial_usd, 0)
        WHERE id = v_turno_id;
    END IF;
    RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_cerrar_turno_offline_usd(
    p_client_uuid uuid,
    p_id_tpv bigint,
    p_efectivo_real numeric,
    p_usuario uuid,
    p_productos jsonb DEFAULT '[]'::jsonb,
    p_observaciones text DEFAULT NULL,
    p_fecha_cierre timestamptz DEFAULT NULL,
    p_efectivo_real_usd numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_result jsonb;
    v_turno_id bigint;
    v_efectivo_esperado_usd numeric := 0;
BEGIN
    IF NULLIF(btrim(COALESCE(current_setting('app.m01_caja_extra', true), '')), '') IS NULL THEN
        PERFORM set_config(
            'app.m01_caja_extra',
            jsonb_build_object('efectivo_usd', p_efectivo_real_usd)::text,
            true
        );
    END IF;
    SELECT id INTO v_turno_id
    FROM public.app_dat_caja_turno
    WHERE id_tpv = p_id_tpv AND estado = 1
    ORDER BY fecha_apertura DESC NULLS LAST
    LIMIT 1;

    v_result := public.fn_cerrar_turno_offline(
        p_client_uuid, p_id_tpv, p_efectivo_real, p_usuario,
        p_productos, p_observaciones, p_fecha_cierre
    );
    IF COALESCE((v_result->>'idempotent')::boolean, false) THEN
        RETURN v_result;
    END IF;

    SELECT COALESCE(SUM(pv.monto), 0) INTO v_efectivo_esperado_usd
    FROM public.app_dat_pago_venta pv
    JOIN public.app_dat_operacion_venta ov ON ov.id_operacion = pv.id_operacion_venta
    JOIN public.app_nom_medio_pago mp ON mp.id = pv.id_medio_pago
    WHERE pv.moneda = 'USD' AND mp.es_efectivo IS TRUE
      AND ov.id_turno_apertura = v_turno_id;

    IF v_turno_id IS NOT NULL AND (v_result->>'status') = 'success' THEN
        UPDATE public.app_dat_caja_turno
        SET efectivo_real_usd = p_efectivo_real_usd,
            diferencia_usd = CASE
                WHEN p_efectivo_real_usd IS NULL THEN NULL
                ELSE p_efectivo_real_usd
                     - (COALESCE(efectivo_inicial_usd, 0) + v_efectivo_esperado_usd)
            END
        WHERE id = v_turno_id;
    END IF;
    RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_apertura_turno_offline_monedas(
    p_client_uuid uuid,
    p_id_tpv bigint,
    p_id_vendedor bigint,
    p_usuario uuid,
    p_maneja_inventario boolean,
    p_productos jsonb,
    p_efectivo_inicial_por_moneda jsonb,
    p_observaciones text DEFAULT NULL,
    p_fecha_apertura timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_res jsonb;
    v_turno_id bigint;
    v_cup numeric;
    v_usd numeric;
BEGIN
    IF p_efectivo_inicial_por_moneda IS NULL
       OR jsonb_typeof(p_efectivo_inicial_por_moneda) <> 'object' THEN
        RAISE EXCEPTION 'Se esperaba un objeto {"MONEDA": monto} de efectivo inicial';
    END IF;
    v_cup := COALESCE(public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, 'CUP'), 0);
    v_usd := COALESCE(public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, 'USD'), 0);
    PERFORM set_config(
        'app.m01_caja_extra',
        jsonb_build_object(
            'efectivo_por_moneda', p_efectivo_inicial_por_moneda,
            'efectivo_usd', v_usd
        )::text,
        true
    );
    v_res := public.fn_apertura_turno_offline_usd(
        p_client_uuid := p_client_uuid,
        p_efectivo_inicial := v_cup,
        p_id_tpv := p_id_tpv,
        p_id_vendedor := p_id_vendedor,
        p_usuario := p_usuario,
        p_maneja_inventario := p_maneja_inventario,
        p_productos := p_productos,
        p_observaciones := p_observaciones,
        p_fecha_apertura := p_fecha_apertura,
        p_efectivo_inicial_usd := v_usd
    );
    IF COALESCE((v_res->>'idempotent')::boolean, false) THEN
        RETURN v_res;
    END IF;
    IF (v_res->>'status') = 'success' THEN
        v_turno_id := NULLIF(v_res->>'id_turno', '')::bigint;
        IF v_turno_id IS NOT NULL THEN
            INSERT INTO public.app_dat_caja_turno_moneda (id_turno, moneda, efectivo_inicial)
            SELECT v_turno_id, upper(btrim(e.key)),
                   public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, e.key)
            FROM jsonb_each(p_efectivo_inicial_por_moneda) e
            WHERE public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, e.key) IS NOT NULL
              AND EXISTS (
                  SELECT 1 FROM public.monedas m WHERE m.codigo = upper(btrim(e.key))
              )
            ON CONFLICT (id_turno, moneda) DO UPDATE
                SET efectivo_inicial = excluded.efectivo_inicial,
                    updated_at = now();
        END IF;
    END IF;
    RETURN v_res;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_cerrar_turno_offline_monedas(
    p_client_uuid uuid,
    p_id_tpv bigint,
    p_usuario uuid,
    p_productos jsonb,
    p_efectivo_real_por_moneda jsonb,
    p_observaciones text DEFAULT NULL,
    p_fecha_cierre timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_res jsonb;
    v_turno_id bigint;
    v_cup numeric;
    v_usd numeric;
    v_esperado record;
BEGIN
    IF p_efectivo_real_por_moneda IS NULL
       OR jsonb_typeof(p_efectivo_real_por_moneda) <> 'object' THEN
        RAISE EXCEPTION 'Se esperaba un objeto {"MONEDA": monto} de efectivo real';
    END IF;
    v_cup := COALESCE(public.fn_jsonb_monto(p_efectivo_real_por_moneda, 'CUP'), 0);
    v_usd := COALESCE(public.fn_jsonb_monto(p_efectivo_real_por_moneda, 'USD'), 0);
    PERFORM set_config(
        'app.m01_caja_extra',
        jsonb_build_object(
            'efectivo_por_moneda', p_efectivo_real_por_moneda,
            'efectivo_usd', v_usd
        )::text,
        true
    );
    SELECT ct.id INTO v_turno_id
    FROM public.app_dat_caja_turno ct
    WHERE ct.id_tpv = p_id_tpv AND ct.estado = 1 AND ct.creado_por = p_usuario
    ORDER BY ct.fecha_apertura DESC
    LIMIT 1;
    v_res := public.fn_cerrar_turno_offline_usd(
        p_client_uuid := p_client_uuid,
        p_id_tpv := p_id_tpv,
        p_efectivo_real := v_cup,
        p_usuario := p_usuario,
        p_productos := p_productos,
        p_observaciones := p_observaciones,
        p_fecha_cierre := p_fecha_cierre,
        p_efectivo_real_usd := v_usd
    );
    IF COALESCE((v_res->>'idempotent')::boolean, false) THEN
        RETURN v_res;
    END IF;
    IF (v_res->>'status') = 'success' AND v_turno_id IS NOT NULL THEN
        FOR v_esperado IN
            SELECT moneda, esperado FROM public.fn_esperado_turno_por_moneda(v_turno_id)
        LOOP
            INSERT INTO public.app_dat_caja_turno_moneda
                (id_turno, moneda, efectivo_inicial, efectivo_esperado, efectivo_real)
            VALUES (
                v_turno_id, v_esperado.moneda,
                COALESCE((
                    SELECT m.efectivo_inicial
                    FROM public.app_dat_caja_turno_moneda m
                    WHERE m.id_turno = v_turno_id AND m.moneda = v_esperado.moneda
                ), 0),
                v_esperado.esperado,
                public.fn_jsonb_monto(p_efectivo_real_por_moneda, v_esperado.moneda)
            )
            ON CONFLICT (id_turno, moneda) DO UPDATE
                SET efectivo_esperado = excluded.efectivo_esperado,
                    efectivo_real = COALESCE(
                        excluded.efectivo_real,
                        public.app_dat_caja_turno_moneda.efectivo_real
                    ),
                    updated_at = now();
        END LOOP;
    END IF;
    RETURN v_res;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_m01_cerrar_turno_residual(
    p_client_uuid uuid,
    p_id_turno bigint,
    p_observaciones text DEFAULT NULL
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
    v_tpv bigint;
    v_estado integer;
    v_inventario boolean;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_turno IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_request := jsonb_build_object(
        'version', 1,
        'id_turno', p_id_turno,
        'observaciones', p_observaciones
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'cierre_residual'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR v_existing.m01_id_tienda IS NULL
           OR v_existing.id_operacion IS DISTINCT FROM p_id_turno THEN
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
            'message', 'Turno residual ya cerrado'
        );
    END IF;

    SELECT t.id_tienda, ct.estado, ct.maneja_inventario, ct.id_tpv
    INTO v_store, v_estado, v_inventario, v_tpv
    FROM public.app_dat_caja_turno ct
    JOIN public.app_dat_tpv t ON t.id = ct.id_tpv
    WHERE ct.id = p_id_turno
    FOR UPDATE OF ct;
    IF NOT FOUND OR v_store IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF public.fn_config_tienda_puede_escribir(v_store) IS DISTINCT FROM true
       AND NOT EXISTS (
            SELECT 1
            FROM public.app_dat_vendedor s
            JOIN public.app_dat_trabajadores w ON w.id = s.id_trabajador
            WHERE s.uuid = v_actor AND s.id_tpv = v_tpv
              AND w.uuid = v_actor AND w.deleted_at IS NULL
              AND w.id_tienda = v_store
       ) THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF v_estado IS DISTINCT FROM 1 THEN
        RETURN jsonb_build_object(
            'status', 'success', 'idempotent', true,
            'message', 'El turno ya no estaba abierto'
        );
    END IF;
    IF v_inventario IS TRUE THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El turno maneja inventario; no se cierra como residual'
        );
    END IF;
    UPDATE public.app_dat_caja_turno
    SET estado = 2,
        fecha_cierre = now(),
        cerrado_por = v_actor,
        observaciones = COALESCE(
            p_observaciones,
            'Cierre de turno duplicado'
        )
    WHERE id = p_id_turno AND estado = 1;
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, p_id_turno, 'cierre_residual', v_actor, v_request, v_store);
    RETURN jsonb_build_object('status', 'success', 'idempotent', false);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_apertura_turno_offline(uuid,numeric,bigint,bigint,uuid,boolean,jsonb,text,timestamptz)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_apertura_turno_offline(uuid,numeric,bigint,bigint,uuid,boolean,jsonb,text,timestamptz)
    TO authenticated;
REVOKE ALL ON FUNCTION public.fn_cerrar_turno_offline(uuid,bigint,numeric,uuid,jsonb,text,timestamptz)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_cerrar_turno_offline(uuid,bigint,numeric,uuid,jsonb,text,timestamptz)
    TO authenticated;
REVOKE ALL ON FUNCTION public.fn_registrar_egreso_offline(uuid,bigint,numeric,character varying,character varying,text,smallint,uuid)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_registrar_egreso_offline(uuid,bigint,numeric,character varying,character varying,text,smallint,uuid)
    TO authenticated;
REVOKE ALL ON FUNCTION public.fn_registrar_egreso_offline_v2(uuid,bigint,numeric,character varying,character varying,text,smallint,uuid,text)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_registrar_egreso_offline_v2(uuid,bigint,numeric,character varying,character varying,text,smallint,uuid,text)
    TO authenticated;
REVOKE ALL ON FUNCTION public.fn_pedir_item_cuenta_offline(uuid,bigint,bigint,numeric,numeric,bigint,bigint,bigint,bigint,numeric,bigint,jsonb,jsonb,text,text,text,uuid,boolean)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_pedir_item_cuenta_offline(uuid,bigint,bigint,numeric,numeric,bigint,bigint,bigint,bigint,numeric,bigint,jsonb,jsonb,text,text,text,uuid,boolean)
    TO authenticated;
REVOKE ALL ON FUNCTION public.fn_cambiar_estado_comanda_item_offline(uuid,bigint,smallint)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_cambiar_estado_comanda_item_offline(uuid,bigint,smallint)
    TO authenticated;
REVOKE ALL ON FUNCTION public.fn_m01_cerrar_turno_residual(uuid,bigint,text)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_cerrar_turno_residual(uuid,bigint,text)
    TO authenticated;

COMMIT;
