-- ============================================================================
-- 41 · Ejecutor atómico de cumplimiento físico por presentaciones v2
-- ============================================================================
-- Requiere 35, 38, 39 y 40. Replanifica bajo locks canónicos, registra las
-- conversiones N→N y escribe snapshots append-only en el ledger.
-- Esta función es interna: los callers versionados posteriores serán la frontera
-- autenticada y aportarán el UUID idempotente de cada operación.
-- ============================================================================

-- El constraint chk_cantidad_final_conditional invoca esta función heredada.
-- Se conserva su semántica y ACL; CREATE OR REPLACE no cambia propietario ni
-- privilegios, pero evita que herede el search_path vacío del ejecutor v2.
CREATE OR REPLACE FUNCTION public.fn_validar_cantidad_final_inventario(
    p_id_producto bigint,
    p_cantidad_final numeric
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
    v_permite_negativo boolean := false;
BEGIN
    IF p_cantidad_final IS NULL THEN
        RETURN true;
    END IF;

    SELECT COALESCE(
        ct.permite_vender_aun_sin_disponibilidad,
        false
    )
      INTO v_permite_negativo
      FROM public.app_dat_producto p
      JOIN public.app_dat_configuracion_tienda ct
        ON p.id_tienda = ct.id_tienda
     WHERE p.id = p_id_producto;

    v_permite_negativo := COALESCE(v_permite_negativo, false);

    IF v_permite_negativo = true THEN
        RETURN true;
    END IF;

    RETURN p_cantidad_final >= 0;
END;
$function$;

-- Las funciones trigger viven fuera de este módulo y pueden haber recibido otros
-- cambios. Se modifica quirúrgicamente solo su guarda conocida, preservando el
-- resto de la definición instalada. Si la forma esperada no existe, se aborta.
DO $guardas$
DECLARE
    v_nombre text;
    v_def    text;
    v_vieja  text := 'IF NEW.id_conversion IS NOT NULL THEN';
    v_nueva  text := 'IF NEW.id_conversion IS NOT NULL' || chr(10)
                     || '       OR NEW.id_conversion_evento IS NOT NULL THEN';
BEGIN
    FOREACH v_nombre IN ARRAY ARRAY[
        'fn_sincronizar_stock_producto',
        'fn_notificar_producto_disponible'
    ]
    LOOP
        SELECT pg_get_functiondef(p.oid)
          INTO v_def
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND p.proname = v_nombre
           AND p.pronargs = 0;

        IF v_def IS NULL THEN
            RAISE EXCEPTION 'No existe public.%()', v_nombre;
        END IF;
        IF v_def LIKE '%NEW.id_conversion_evento IS NOT NULL%' THEN
            CONTINUE;
        END IF;
        IF strpos(v_def, v_vieja) = 0 THEN
            RAISE EXCEPTION 'La guarda esperada no existe en public.%()', v_nombre;
        END IF;

        EXECUTE replace(v_def, v_vieja, v_nueva);
    END LOOP;
END;
$guardas$;

CREATE TABLE IF NOT EXISTS public.app_dat_cumplimiento_inventario_solicitud (
    id                       bigserial PRIMARY KEY,
    client_request_uuid      uuid NOT NULL UNIQUE,
    payload_hash             text NOT NULL CHECK (length(payload_hash) = 32),
    id_producto              bigint NOT NULL
        REFERENCES public.app_dat_producto(id),
    id_variante              bigint NULL
        REFERENCES public.app_dat_variantes(id),
    id_opcion_variante       bigint NULL
        REFERENCES public.app_dat_atributo_opcion(id),
    id_ubicacion             bigint NOT NULL
        REFERENCES public.app_dat_layout_almacen(id),
    id_presentacion          bigint NOT NULL
        REFERENCES public.app_dat_producto_presentacion(id),
    cantidad                 numeric NOT NULL CHECK (cantidad > 0),
    estado                   text NOT NULL DEFAULT 'procesando'
        CHECK (estado IN ('procesando', 'completado')),
    respuesta                jsonb NULL,
    created_at               timestamptz NOT NULL DEFAULT now(),
    completed_at             timestamptz NULL
);

CREATE INDEX IF NOT EXISTS idx_cumplimiento_solicitud_producto_ubicacion
    ON public.app_dat_cumplimiento_inventario_solicitud
       (id_producto, id_ubicacion, id DESC);

COMMENT ON TABLE public.app_dat_cumplimiento_inventario_solicitud IS
    'Idempotencia y respuesta persistida del ejecutor interno de cumplimiento v2.';

ALTER TABLE public.app_dat_cumplimiento_inventario_solicitud
    ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.app_dat_cumplimiento_inventario_solicitud
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE public.app_dat_cumplimiento_inventario_solicitud_id_seq
    FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE
    public.app_dat_cumplimiento_inventario_solicitud TO service_role;
GRANT USAGE, SELECT ON SEQUENCE
    public.app_dat_cumplimiento_inventario_solicitud_id_seq TO service_role;

CREATE OR REPLACE FUNCTION public.fn_aplicar_cumplimiento_v2(
    p_id_producto        bigint,
    p_id_ubicacion       bigint,
    p_id_presentacion    bigint,
    p_cantidad           numeric,
    p_client_request_uuid uuid,
    p_id_variante        bigint DEFAULT NULL,
    p_id_opcion_variante bigint DEFAULT NULL,
    p_id_operacion       bigint DEFAULT NULL,
    p_uuid               uuid DEFAULT NULL,
    p_motivo             text DEFAULT NULL,
    p_origen_cambio      integer DEFAULT 2,
    p_id_recepcion       bigint DEFAULT NULL,
    p_id_extraccion      bigint DEFAULT NULL,
    p_id_control         bigint DEFAULT NULL,
    p_id_proveedor       bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
    v_id_presentacion bigint;
    v_payload         jsonb;
    v_payload_hash    text;
    v_solicitud       public.app_dat_cumplimiento_inventario_solicitud%ROWTYPE;
    v_plan            jsonb;
    v_conversion      jsonb;
    v_pata            jsonb;
    v_saldo           jsonb;
    v_id_evento       bigint;
    v_id_presentacion_pata bigint;
    v_id_ledger       bigint;
    v_tipo_pata       text;
    v_cantidad_pata   numeric;
    v_saldo_antes     numeric;
    v_saldo_despues   numeric;
    v_saldo_esperado  numeric;
    v_sku_producto    varchar;
    v_sku_ubicacion   varchar;
    v_eventos         jsonb := '[]'::jsonb;
    v_ledger_ids      jsonb := '[]'::jsonb;
    v_respuesta       jsonb;
BEGIN
    IF p_client_request_uuid IS NULL THEN
        RAISE EXCEPTION 'client_request_uuid es obligatorio'
            USING ERRCODE = '22023';
    END IF;
    IF p_id_producto IS NULL OR p_id_ubicacion IS NULL
       OR p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RAISE EXCEPTION 'Producto, ubicación y cantidad positiva son obligatorios'
            USING ERRCODE = '22023';
    END IF;
    IF p_id_opcion_variante IS NOT NULL AND p_id_variante IS NULL THEN
        RAISE EXCEPTION 'Una opción de variante requiere id_variante'
            USING ERRCODE = '22023';
    END IF;
    IF p_id_variante IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.app_dat_variantes v WHERE v.id = p_id_variante
    ) THEN
        RAISE EXCEPTION 'La variante % no existe', p_id_variante
            USING ERRCODE = '22023';
    END IF;
    IF p_id_opcion_variante IS NOT NULL AND NOT EXISTS (
        SELECT 1
          FROM public.app_dat_variantes v
          JOIN public.app_dat_atributo_opcion ao
            ON ao.id_atributo = v.id_atributo
         WHERE v.id = p_id_variante
           AND ao.id = p_id_opcion_variante
    ) THEN
        RAISE EXCEPTION 'La opción % no pertenece a la variante %',
            p_id_opcion_variante, p_id_variante USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (
        SELECT 1
          FROM public.app_dat_producto p
          JOIN public.app_dat_layout_almacen la ON la.id = p_id_ubicacion
          JOIN public.app_dat_almacen a ON a.id = la.id_almacen
         WHERE p.id = p_id_producto
           AND p.deleted_at IS NULL
           AND la.deleted_at IS NULL
           AND a.deleted_at IS NULL
           AND a.id_tienda = p.id_tienda
    ) THEN
        RAISE EXCEPTION 'La ubicación % no pertenece a la tienda activa del producto %',
            p_id_ubicacion, p_id_producto USING ERRCODE = '22023';
    END IF;

    IF p_id_presentacion IS NULL THEN
        SELECT c.id_presentacion
          INTO v_id_presentacion
          FROM public.fn_presentaciones_producto_v2(p_id_producto) c
         WHERE c.es_base
         LIMIT 1;
    ELSE
        SELECT c.id_presentacion
          INTO v_id_presentacion
          FROM public.fn_presentaciones_producto_v2(p_id_producto) c
         WHERE c.id_presentacion = p_id_presentacion;
    END IF;

    IF v_id_presentacion IS NULL THEN
        RAISE EXCEPTION 'La presentación % no pertenece al producto %',
            p_id_presentacion, p_id_producto USING ERRCODE = '22023';
    END IF;

    v_payload := jsonb_build_object(
        'id_producto', p_id_producto,
        'id_ubicacion', p_id_ubicacion,
        'id_presentacion', v_id_presentacion,
        'cantidad', p_cantidad,
        'id_variante', p_id_variante,
        'id_opcion_variante', p_id_opcion_variante,
        'id_operacion', p_id_operacion,
        'uuid', p_uuid,
        'motivo', p_motivo,
        'origen_cambio', p_origen_cambio,
        'id_recepcion', p_id_recepcion,
        'id_extraccion', p_id_extraccion,
        'id_control', p_id_control,
        'id_proveedor', p_id_proveedor
    );
    v_payload_hash := md5(v_payload::text);

    PERFORM pg_advisory_xact_lock(
        hashtextextended(p_client_request_uuid::text, 0)
    );

    SELECT s.*
      INTO v_solicitud
      FROM public.app_dat_cumplimiento_inventario_solicitud s
     WHERE s.client_request_uuid = p_client_request_uuid;

    IF FOUND THEN
        IF v_solicitud.payload_hash <> v_payload_hash THEN
            RAISE EXCEPTION 'IDEMPOTENCY_KEY_REUSED: el UUID ya fue usado con otro payload'
                USING ERRCODE = '22023';
        END IF;
        IF v_solicitud.estado = 'completado' AND v_solicitud.respuesta IS NOT NULL THEN
            RETURN v_solicitud.respuesta || jsonb_build_object('idempotent_replay', true);
        END IF;
        RAISE EXCEPTION 'La solicitud idempotente quedó en un estado inconsistente'
            USING ERRCODE = '55000';
    END IF;

    INSERT INTO public.app_dat_cumplimiento_inventario_solicitud (
        client_request_uuid, payload_hash, id_producto, id_variante,
        id_opcion_variante, id_ubicacion, id_presentacion, cantidad
    ) VALUES (
        p_client_request_uuid, v_payload_hash, p_id_producto, p_id_variante,
        p_id_opcion_variante, p_id_ubicacion, v_id_presentacion, p_cantidad
    ) RETURNING * INTO v_solicitud;

    -- Bloquea la clave completa aunque todavía no exista una fila de ledger.
    -- Todos los callers usan la misma codificación y por tanto el mismo orden.
    PERFORM pg_advisory_xact_lock(
        hashtextextended(
            format('%s:%s:%s:%s', p_id_producto,
                   COALESCE(p_id_variante, 0),
                   COALESCE(p_id_opcion_variante, 0), p_id_ubicacion),
            41002
        )
    );

    v_plan := public.fn_planificar_cumplimiento_presentaciones_v2(
        p_id_producto, p_id_ubicacion, v_id_presentacion, p_cantidad,
        p_id_variante, p_id_opcion_variante
    );
    IF v_plan->>'status' <> 'success' THEN
        RAISE EXCEPTION 'No se pudo cumplir la solicitud: %',
            COALESCE(v_plan->>'message', v_plan::text) USING ERRCODE = 'P0001';
    END IF;

    FOR v_conversion IN
        SELECT value FROM jsonb_array_elements(v_plan->'conversiones')
    LOOP
        v_id_evento := public.fn_registrar_conversion_v2(
            p_id_producto,
            p_id_ubicacion,
            v_conversion->>'tipo',
            v_conversion->'patas',
            p_id_variante,
            p_id_opcion_variante,
            p_id_operacion,
            p_uuid,
            COALESCE(p_motivo, 'cumplimiento físico v2')
        );
        v_eventos := v_eventos || jsonb_build_object(
            'id_conversion_evento', v_id_evento,
            'tipo', v_conversion->>'tipo'
        );

        FOR v_pata IN
            SELECT value FROM jsonb_array_elements(v_conversion->'patas')
        LOOP
            v_id_presentacion_pata := (v_pata->>'id_presentacion')::bigint;
            v_tipo_pata := v_pata->>'tipo';
            v_cantidad_pata := (v_pata->>'cantidad')::numeric;

            SELECT COALESCE(sum(s.saldo), 0),
                   min(s.sku_producto), min(s.sku_ubicacion)
              INTO v_saldo_antes, v_sku_producto, v_sku_ubicacion
              FROM public.fn_stock_saldos_presentacion(
                       p_id_producto, NULL, p_id_ubicacion, true
                   ) s
             WHERE s.id_presentacion = v_id_presentacion_pata
               AND s.id_variante IS NOT DISTINCT FROM p_id_variante
               AND s.id_opcion_variante IS NOT DISTINCT FROM p_id_opcion_variante;

            IF v_sku_producto IS NULL THEN
                SELECT p.sku INTO v_sku_producto
                  FROM public.app_dat_producto p
                 WHERE p.id = p_id_producto;
            END IF;
            IF v_tipo_pata = 'salida' THEN
                v_saldo_despues := v_saldo_antes - v_cantidad_pata;
            ELSE
                v_saldo_despues := v_saldo_antes + v_cantidad_pata;
            END IF;
            IF v_saldo_despues < 0 THEN
                RAISE EXCEPTION 'Conversión % deja saldo negativo en presentación %',
                    v_id_evento, v_id_presentacion_pata USING ERRCODE = 'P0001';
            END IF;

            INSERT INTO public.app_dat_inventario_productos (
                id_producto, id_variante, id_opcion_variante, id_ubicacion,
                id_presentacion, cantidad_inicial, cantidad_final,
                sku_producto, sku_ubicacion, origen_cambio,
                id_conversion_evento, created_at
            ) VALUES (
                p_id_producto, p_id_variante, p_id_opcion_variante, p_id_ubicacion,
                v_id_presentacion_pata, v_saldo_antes, v_saldo_despues,
                v_sku_producto, v_sku_ubicacion, 20,
                v_id_evento, now()
            ) RETURNING id INTO v_id_ledger;
            v_ledger_ids := v_ledger_ids || to_jsonb(v_id_ledger);
        END LOOP;
    END LOOP;

    -- Despacha las líneas físicas del plan. Se agrupan por presentación porque
    -- varias procedencias pueden recaer en la misma clave del ledger.
    FOR v_pata IN
        SELECT jsonb_build_object(
                   'id_presentacion', (value->>'id_presentacion')::bigint,
                   'cantidad', sum((value->>'cantidad')::numeric)
               )
          FROM jsonb_array_elements(v_plan->'lineas_fisicas')
         GROUP BY (value->>'id_presentacion')::bigint
         ORDER BY (value->>'id_presentacion')::bigint
    LOOP
        v_id_presentacion_pata := (v_pata->>'id_presentacion')::bigint;
        v_cantidad_pata := (v_pata->>'cantidad')::numeric;

        SELECT COALESCE(sum(s.saldo), 0),
               min(s.sku_producto), min(s.sku_ubicacion)
          INTO v_saldo_antes, v_sku_producto, v_sku_ubicacion
          FROM public.fn_stock_saldos_presentacion(
                   p_id_producto, NULL, p_id_ubicacion, true
               ) s
         WHERE s.id_presentacion = v_id_presentacion_pata
           AND s.id_variante IS NOT DISTINCT FROM p_id_variante
           AND s.id_opcion_variante IS NOT DISTINCT FROM p_id_opcion_variante;

        v_saldo_despues := v_saldo_antes - v_cantidad_pata;
        IF v_saldo_despues < 0 THEN
            RAISE EXCEPTION 'El despacho deja saldo negativo en presentación %',
                v_id_presentacion_pata USING ERRCODE = 'P0001';
        END IF;
        IF v_sku_producto IS NULL THEN
            SELECT p.sku INTO v_sku_producto
              FROM public.app_dat_producto p WHERE p.id = p_id_producto;
        END IF;

        INSERT INTO public.app_dat_inventario_productos (
            id_producto, id_variante, id_opcion_variante, id_ubicacion,
            id_presentacion, cantidad_inicial, cantidad_final,
            sku_producto, sku_ubicacion, origen_cambio,
            id_recepcion, id_extraccion, id_control, id_proveedor, created_at
        ) VALUES (
            p_id_producto, p_id_variante, p_id_opcion_variante, p_id_ubicacion,
            v_id_presentacion_pata, v_saldo_antes, v_saldo_despues,
            v_sku_producto, v_sku_ubicacion, p_origen_cambio,
            p_id_recepcion, p_id_extraccion, p_id_control, p_id_proveedor, now()
        ) RETURNING id INTO v_id_ledger;
        v_ledger_ids := v_ledger_ids || to_jsonb(v_id_ledger);
    END LOOP;

    FOR v_saldo IN
        SELECT value FROM jsonb_array_elements(v_plan->'saldos_proyectados')
    LOOP
        SELECT COALESCE(sum(s.saldo), 0)
          INTO v_saldo_despues
          FROM public.fn_stock_saldos_presentacion(
                   p_id_producto, NULL, p_id_ubicacion, true
               ) s
         WHERE s.id_presentacion = (v_saldo->>'id_presentacion')::bigint
           AND s.id_variante IS NOT DISTINCT FROM p_id_variante
           AND s.id_opcion_variante IS NOT DISTINCT FROM p_id_opcion_variante;
        v_saldo_esperado := (v_saldo->>'cantidad')::numeric;
        IF v_saldo_despues <> v_saldo_esperado OR v_saldo_despues < 0 THEN
            RAISE EXCEPTION 'Saldo final inconsistente para presentación %: esperado %, real %',
                v_saldo->>'id_presentacion', v_saldo_esperado, v_saldo_despues
                USING ERRCODE = 'P0001';
        END IF;
    END LOOP;

    IF EXISTS (
        SELECT 1
          FROM public.app_dat_conversion_presentacion_evento e
          JOIN LATERAL (
              SELECT COALESCE(sum(CASE WHEN p.tipo = 'salida' THEN p.equivalente ELSE 0 END), 0) salidas,
                     COALESCE(sum(CASE WHEN p.tipo = 'entrada' THEN p.equivalente ELSE 0 END), 0) entradas
                FROM public.app_dat_conversion_presentacion_pata p
               WHERE p.id_conversion_evento = e.id
          ) x ON true
         WHERE e.id = ANY (
             SELECT (value->>'id_conversion_evento')::bigint
               FROM jsonb_array_elements(v_eventos)
         )
           AND x.salidas <> x.entradas
    ) THEN
        RAISE EXCEPTION 'Una conversión persistida no conserva el equivalente'
            USING ERRCODE = 'P0001';
    END IF;

    v_respuesta := v_plan || jsonb_build_object(
        'id_solicitud_cumplimiento', v_solicitud.id,
        'client_request_uuid', p_client_request_uuid,
        'eventos_conversion', v_eventos,
        'ledger_ids', v_ledger_ids,
        'idempotent_replay', false
    );

    UPDATE public.app_dat_cumplimiento_inventario_solicitud
       SET estado = 'completado', respuesta = v_respuesta, completed_at = now()
     WHERE id = v_solicitud.id;

    RETURN v_respuesta;
END;
$function$;

COMMENT ON FUNCTION public.fn_aplicar_cumplimiento_v2(
    bigint, bigint, bigint, numeric, uuid, bigint, bigint, bigint, uuid, text,
    integer, bigint, bigint, bigint, bigint
) IS
    'Replanifica bajo lock, persiste conversiones N→N y descuenta las líneas físicas exactas con idempotencia.';

REVOKE ALL ON FUNCTION public.fn_aplicar_cumplimiento_v2(
    bigint, bigint, bigint, numeric, uuid, bigint, bigint, bigint, uuid, text,
    integer, bigint, bigint, bigint, bigint
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_aplicar_cumplimiento_v2(
    bigint, bigint, bigint, numeric, uuid, bigint, bigint, bigint, uuid, text,
    integer, bigint, bigint, bigint, bigint
) TO service_role;
