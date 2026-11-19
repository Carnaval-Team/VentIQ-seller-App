CREATE OR REPLACE FUNCTION public.fn_obtener_licencia_firmada(p_id_tienda bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_secreto text;
    v_suscripcion RECORD;
    v_config RECORD;
    v_emitido_en timestamptz := now();
    v_fecha_fin_epoch bigint;
    v_emitido_en_epoch bigint;
    v_dias_max integer;
    v_permitir_offline boolean;
    v_canonico text;
    v_firma text;
BEGIN
    SELECT secreto INTO v_secreto
    FROM app_dat_licencia_offline_secreto
    WHERE id = 1;

    IF v_secreto IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Secreto de licencia no configurado en el servidor'
        );
    END IF;

    SELECT s.id, s.id_plan, s.estado, s.fecha_fin, p.denominacion AS plan_nombre
    INTO v_suscripcion
    FROM app_suscripciones s
    LEFT JOIN app_suscripciones_plan p ON p.id = s.id_plan
    WHERE s.id_tienda = p_id_tienda
      AND s.estado = 1
    ORDER BY s.created_at DESC
    LIMIT 1;

    IF v_suscripcion.id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'No existe suscripción activa para la tienda'
        );
    END IF;

    IF v_suscripcion.fecha_fin IS NOT NULL AND v_suscripcion.fecha_fin < now() THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'La suscripción de la tienda está vencida'
        );
    END IF;

    SELECT
        COALESCE(cambiar.permitir_modo_offline_completo, false) AS permitir_offline,
        COALESCE(cambiar.dias_max_sin_validar_licencia, 7) AS dias_max
    INTO v_config
    FROM (
        SELECT permitir_modo_offline_completo, dias_max_sin_validar_licencia
        FROM app_dat_configuracion_tienda
        WHERE id_tienda = p_id_tienda
    ) AS cambiar;

    v_permitir_offline := COALESCE(v_config.permitir_offline, false);
    v_dias_max := COALESCE(v_config.dias_max, 7);

    v_fecha_fin_epoch := COALESCE(EXTRACT(EPOCH FROM v_suscripcion.fecha_fin)::bigint, 0);
    v_emitido_en_epoch := EXTRACT(EPOCH FROM v_emitido_en)::bigint;

    v_canonico := p_id_tienda::text
        || '|' || v_fecha_fin_epoch::text
        || '|' || v_emitido_en_epoch::text
        || '|' || v_dias_max::text
        || '|' || COALESCE(v_suscripcion.id_plan::text, '0')
        || '|' || CASE WHEN v_permitir_offline THEN '1' ELSE '0' END;

    v_firma := encode(
        extensions.hmac(v_canonico::bytea, v_secreto::bytea, 'sha256'),
        'hex'
    );

    RETURN jsonb_build_object(
        'success', true,
        'licencia', jsonb_build_object(
            'id_tienda', p_id_tienda,
            'id_plan', v_suscripcion.id_plan,
            'plan_nombre', v_suscripcion.plan_nombre,
            'fecha_fin', v_suscripcion.fecha_fin,
            'fecha_fin_epoch', v_fecha_fin_epoch,
            'emitido_en', v_emitido_en,
            'emitido_en_epoch', v_emitido_en_epoch,
            'dias_max_sin_validar', v_dias_max,
            'permitir_modo_offline_completo', v_permitir_offline
        ),
        'firma', v_firma
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'message', SQLERRM
    );
END;
$function$

