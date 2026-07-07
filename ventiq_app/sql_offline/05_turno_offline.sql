-- ============================================================================
-- 05_turno_offline.sql
-- ----------------------------------------------------------------------------
-- Apertura y cierre de turno IDEMPOTENTES por client_uuid.
--
-- Problema que resuelve:
--   - Al sincronizar un turno abierto offline, un reintento podía crear un
--     turno DUPLICADO.
--   - El cierre podía ejecutarse más de una vez.
--
-- Requiere la tabla de idempotencia creada en 04_fn_registrar_venta_offline.sql
-- (app_dat_operacion_offline_idempotencia). Subir el 04 antes que el 05.
--
-- IMPORTANTE (regla de negocio): el cierre de turno NO se realiza
-- automáticamente en la sincronización. La app solo llama a
-- fn_cerrar_turno_offline cuando el usuario mandó a cerrar explícitamente
-- (existe una operación 'cierre_turno' pendiente). La apertura sí se asegura
-- de forma idempotente.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Apertura de turno idempotente.
-- Devuelve el id del turno (nuevo o el ya creado para ese client_uuid).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_apertura_turno_offline(
    p_client_uuid uuid,
    p_efectivo_inicial numeric,
    p_id_tpv bigint,
    p_id_vendedor bigint,
    p_usuario uuid,
    p_maneja_inventario boolean DEFAULT false,
    p_productos jsonb DEFAULT '[]'::jsonb,
    p_observaciones text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_existing bigint;
    v_turno_abierto bigint;
    v_new_id bigint;
BEGIN
    -- 1) ¿Ya se procesó esta apertura offline?
    SELECT id_operacion INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid AND tipo = 'apertura_turno';

    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object(
            'status', 'success', 'id_turno', v_existing, 'idempotent', true
        );
    END IF;

    -- 2) Si ya hay un turno abierto para este TPV/vendedor, reutilizarlo en vez
    --    de crear otro (evita duplicados aunque no haya client_uuid previo).
    SELECT id INTO v_turno_abierto
    FROM app_dat_caja_turno
    WHERE id_tpv = p_id_tpv AND id_vendedor = p_id_vendedor AND estado = 1
    ORDER BY fecha_apertura DESC NULLS LAST
    LIMIT 1;

    IF v_turno_abierto IS NOT NULL THEN
        INSERT INTO public.app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario)
        VALUES (p_client_uuid, v_turno_abierto, 'apertura_turno', p_usuario)
        ON CONFLICT (client_uuid) DO NOTHING;

        RETURN jsonb_build_object(
            'status', 'success', 'id_turno', v_turno_abierto, 'idempotent', true,
            'message', 'Turno ya estaba abierto; reutilizado'
        );
    END IF;

    -- 3) Crear el turno usando la función existente.
    v_new_id := public.registrar_apertura_turno_v3(
        p_efectivo_inicial := p_efectivo_inicial,
        p_id_tpv := p_id_tpv,
        p_id_vendedor := p_id_vendedor,
        p_usuario := p_usuario,
        p_maneja_inventario := p_maneja_inventario,
        p_productos := p_productos,
        p_observaciones := p_observaciones
    );

    IF v_new_id IS NOT NULL THEN
        INSERT INTO public.app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario)
        VALUES (p_client_uuid, v_new_id, 'apertura_turno', p_usuario)
        ON CONFLICT (client_uuid) DO NOTHING;
    END IF;

    RETURN jsonb_build_object(
        'status', 'success', 'id_turno', v_new_id, 'idempotent', false
    );
END;
$function$;

-- ----------------------------------------------------------------------------
-- Cierre de turno idempotente.
-- Solo debe invocarse cuando el usuario mandó a cerrar (operación explícita).
-- Si ya se cerró con ese client_uuid, no vuelve a cerrar.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_cerrar_turno_offline(
    p_client_uuid uuid,
    p_id_tpv bigint,
    p_efectivo_real numeric,
    p_usuario uuid,
    p_productos jsonb DEFAULT '[]'::jsonb,
    p_observaciones text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_existing bigint;
    v_ok boolean;
    v_turno_abierto bigint;
BEGIN
    -- 1) ¿Ya se procesó este cierre offline?
    SELECT id_operacion INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid AND tipo = 'cierre_turno';

    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object(
            'status', 'success', 'idempotent', true,
            'message', 'Cierre ya procesado'
        );
    END IF;

    -- 2) Si no hay turno abierto, considerar ya cerrado (idempotente).
    SELECT id INTO v_turno_abierto
    FROM app_dat_caja_turno
    WHERE id_tpv = p_id_tpv AND estado = 1
    ORDER BY fecha_apertura DESC NULLS LAST
    LIMIT 1;

    IF v_turno_abierto IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'success', 'idempotent', true,
            'message', 'No hay turno abierto; nada que cerrar'
        );
    END IF;

    -- 3) Cerrar usando la función existente.
    v_ok := public.fn_cerrar_turno_tpv(
        p_id_tpv := p_id_tpv,
        p_efectivo_real := p_efectivo_real,
        p_usuario := p_usuario,
        p_productos := p_productos,
        p_observaciones := p_observaciones
    );

    IF v_ok THEN
        INSERT INTO public.app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario)
        VALUES (p_client_uuid, v_turno_abierto, 'cierre_turno', p_usuario)
        ON CONFLICT (client_uuid) DO NOTHING;

        RETURN jsonb_build_object('status', 'success', 'idempotent', false);
    END IF;

    RETURN jsonb_build_object(
        'status', 'error', 'message', 'El servidor rechazó el cierre del turno'
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_apertura_turno_offline(uuid, numeric, bigint, bigint, uuid, boolean, jsonb, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_apertura_turno_offline(uuid, numeric, bigint, bigint, uuid, boolean, jsonb, text) TO anon;
GRANT EXECUTE ON FUNCTION public.fn_cerrar_turno_offline(uuid, bigint, numeric, uuid, jsonb, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_cerrar_turno_offline(uuid, bigint, numeric, uuid, jsonb, text) TO anon;
