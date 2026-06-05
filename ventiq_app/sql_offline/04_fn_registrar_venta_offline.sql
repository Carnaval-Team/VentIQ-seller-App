-- ============================================================================
-- 04_fn_registrar_venta_offline.sql
-- ----------------------------------------------------------------------------
-- Registro de ventas offline IDEMPOTENTE por client_uuid.
--
-- Problema que resuelve: al sincronizar ventas creadas offline, si la conexión
-- se cae DESPUÉS de registrar la venta en el servidor pero ANTES de marcarla
-- como sincronizada en el dispositivo, el siguiente reintento volvía a llamar
-- a fn_registrar_venta y creaba una operación DUPLICADA. Además, el id de orden
-- offline era un timestamp (riesgo de colisión).
--
-- Solución: el cliente genera un client_uuid (UUID v4) único por orden offline
-- y lo envía al sincronizar. Esta función:
--   1. Si el client_uuid YA fue registrado -> devuelve el id_operacion existente
--      (idempotente, no duplica).
--   2. Si es nuevo -> llama a fn_registrar_venta, guarda el mapeo
--      client_uuid -> id_operacion y devuelve el resultado.
--
-- Requiere una tabla de control de idempotencia (se crea aquí).
-- ============================================================================

-- Tabla de control de idempotencia de operaciones offline.
CREATE TABLE IF NOT EXISTS public.app_dat_operacion_offline_idempotencia (
    client_uuid   uuid PRIMARY KEY,
    id_operacion  bigint NOT NULL,
    tipo          text NOT NULL DEFAULT 'venta',  -- 'venta' | 'apertura_turno' | 'cierre_turno'
    uuid_usuario  uuid,
    created_at    timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.app_dat_operacion_offline_idempotencia IS
    'Mapeo client_uuid (generado en el dispositivo offline) -> id_operacion, '
    'para evitar duplicados al reintentar la sincronización de ventas/turnos.';

-- ----------------------------------------------------------------------------
-- Wrapper idempotente de fn_registrar_venta.
-- Mantiene los mismos parámetros que fn_registrar_venta y agrega p_client_uuid.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_registrar_venta_offline(
    p_client_uuid uuid,
    p_id_tpv bigint,
    p_uuid uuid,
    p_productos jsonb,
    p_codigo_promocion text DEFAULT NULL,
    p_denominacion text DEFAULT NULL,
    p_observaciones text DEFAULT NULL,
    p_estado_inicial smallint DEFAULT 1,
    p_id_cliente bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_existing_op bigint;
    v_result jsonb;
    v_new_op bigint;
BEGIN
    -- 1) ¿Ya se registró esta orden offline? -> devolver la operación existente.
    SELECT id_operacion INTO v_existing_op
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid;

    IF v_existing_op IS NOT NULL THEN
        RETURN jsonb_build_object(
            'status', 'success',
            'id_operacion', v_existing_op,
            'idempotent', true,
            'message', 'Operación ya registrada previamente (idempotente)'
        );
    END IF;

    -- 2) Registrar la venta usando la función existente, sin duplicar lógica.
    v_result := public.fn_registrar_venta(
        p_id_tpv := p_id_tpv,
        p_uuid := p_uuid,
        p_productos := p_productos,
        p_codigo_promocion := p_codigo_promocion,
        p_denominacion := p_denominacion,
        p_observaciones := p_observaciones,
        p_estado_inicial := p_estado_inicial,
        p_id_cliente := p_id_cliente
    );

    -- 3) Si fue exitosa, persistir el mapeo de idempotencia.
    IF v_result IS NOT NULL AND (v_result->>'status') = 'success' THEN
        v_new_op := (v_result->>'id_operacion')::bigint;
        IF v_new_op IS NOT NULL THEN
            INSERT INTO public.app_dat_operacion_offline_idempotencia
                (client_uuid, id_operacion, tipo, uuid_usuario)
            VALUES (p_client_uuid, v_new_op, 'venta', p_uuid)
            ON CONFLICT (client_uuid) DO NOTHING;
        END IF;

        -- Incluir client_uuid e idempotent=false en la respuesta.
        v_result := v_result || jsonb_build_object(
            'idempotent', false,
            'client_uuid', p_client_uuid
        );
    END IF;

    RETURN v_result;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_registrar_venta_offline(uuid, bigint, uuid, jsonb, text, text, text, smallint, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_registrar_venta_offline(uuid, bigint, uuid, jsonb, text, text, text, smallint, bigint) TO anon;
