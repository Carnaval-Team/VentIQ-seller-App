-- ============================================================================
-- 42 · Extracción administrativa atómica con cumplimiento físico v2
-- ============================================================================
-- Requiere 35, 38, 39, 40 y 41. Conserva intacta la RPC heredada.
-- Planifica todas las claves bajo locks canónicos antes de crear la operación.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.app_dat_extraccion_v2_solicitud (
    id                       bigserial PRIMARY KEY,
    client_request_uuid      uuid NOT NULL UNIQUE,
    payload_hash             text NOT NULL CHECK (length(payload_hash) = 32),
    actor_uuid               uuid NOT NULL REFERENCES auth.users(id),
    id_tienda                bigint NOT NULL REFERENCES public.app_dat_tienda(id),
    estado                   text NOT NULL DEFAULT 'procesando'
        CHECK (estado IN ('procesando', 'completado')),
    id_operacion             bigint NULL REFERENCES public.app_dat_operaciones(id),
    respuesta                jsonb NULL,
    created_at               timestamptz NOT NULL DEFAULT now(),
    completed_at             timestamptz NULL
);

CREATE INDEX IF NOT EXISTS idx_extraccion_v2_solicitud_tienda
    ON public.app_dat_extraccion_v2_solicitud (id_tienda, id DESC);
CREATE INDEX IF NOT EXISTS idx_extraccion_v2_solicitud_actor
    ON public.app_dat_extraccion_v2_solicitud (actor_uuid);
CREATE INDEX IF NOT EXISTS idx_extraccion_v2_solicitud_operacion
    ON public.app_dat_extraccion_v2_solicitud (id_operacion);

COMMENT ON TABLE public.app_dat_extraccion_v2_solicitud IS
    'Idempotencia y respuesta persistida de la extracción administrativa física v2.';

ALTER TABLE public.app_dat_extraccion_v2_solicitud ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.app_dat_extraccion_v2_solicitud
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE public.app_dat_extraccion_v2_solicitud_id_seq
    FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.app_dat_extraccion_v2_solicitud
    TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.app_dat_extraccion_v2_solicitud_id_seq
    TO service_role;

-- Los triggers heredados se ejecutan con el search_path del INSERT llamador.
-- Se califican solo sus dependencias conocidas y se fija un path vacío,
-- preservando cuerpo, propietario, SECURITY y ACL instalados.
DO $compatibilidad_estado_operacion$
DECLARE
    v_item        jsonb;
    v_oid         oid;
    v_def         text;
    v_dependencia text;
BEGIN
    FOR v_item IN SELECT value FROM jsonb_array_elements(jsonb_build_array(
        jsonb_build_object('firma', 'public.validar_recepcion_consignacion_antes_completar(bigint)', 'deps', jsonb_build_array('app_dat_producto_consignacion', 'app_dat_estado_operacion')),
        jsonb_build_object('firma', 'public.trigger_validar_recepcion_consignacion()', 'deps', '[]'::jsonb),
        jsonb_build_object('firma', 'public.actualizar_estado_envio_aceptado()', 'deps', jsonb_build_array('app_dat_operaciones', 'app_dat_consignacion_envio', 'app_dat_consignacion_envio_producto', 'app_dat_contrato_consignacion')),
        jsonb_build_object('firma', 'public.actualizar_estado_envio_en_transito()', 'deps', jsonb_build_array('app_dat_operaciones', 'app_dat_consignacion_envio')),
        jsonb_build_object('firma', 'public.fn_actualizar_eliminar_pre_asignacion()', 'deps', jsonb_build_array('app_dat_operaciones', 'app_nom_tipo_operacion', 'app_dat_operacion_transferencia', 'app_dat_extraccion_productos', 'app_dat_pre_asignaciones', 'app_dat_historial_pre_asignaciones')),
        jsonb_build_object('firma', 'public.fn_registrar_gasto_por_recepcion()', 'deps', jsonb_build_array('app_dat_operaciones', 'app_nom_tipo_operacion', 'app_dat_operacion_recepcion', 'app_dat_recepcion_productos', 'app_cont_tipo_costo', 'app_nom_subcategoria_gasto', 'app_nom_categoria_gasto', 'app_cont_gastos')),
        jsonb_build_object('firma', 'public.fn_sincronizar_estado_orden_inverso()', 'deps', jsonb_build_array('app_dat_operaciones'))
    ))
    LOOP
        v_oid := to_regprocedure(v_item->>'firma');
        IF v_oid IS NULL THEN
            RAISE EXCEPTION 'No existe la dependencia heredada %', v_item->>'firma';
        END IF;
        v_def := pg_get_functiondef(v_oid);
        IF v_item->>'firma' = 'public.trigger_validar_recepcion_consignacion()' THEN
            v_def := replace(v_def,
                'FROM validar_recepcion_consignacion_antes_completar(',
                'FROM public.validar_recepcion_consignacion_antes_completar(');
        END IF;
        FOR v_dependencia IN SELECT jsonb_array_elements_text(v_item->'deps')
        LOOP
            v_def := replace(v_def, 'public.' || v_dependencia, v_dependencia);
            v_def := replace(v_def, v_dependencia, 'public.' || v_dependencia);
        END LOOP;
        EXECUTE v_def;
        EXECUTE format('ALTER FUNCTION %s SET search_path = %L', v_item->>'firma', '');
    END LOOP;
END;
$compatibilidad_estado_operacion$;

-- Aplica un plan ya calculado bajo lock. El mapa recibido enlaza cada salida
-- física con su fila real de app_dat_extraccion_productos.
CREATE OR REPLACE FUNCTION public.fn_aplicar_plan_extraccion_v2(
    p_plan                         jsonb,
    p_extracciones_por_presentacion jsonb,
    p_id_operacion                 bigint,
    p_uuid                         uuid,
    p_motivo                       text
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
    v_conversion      jsonb;
    v_pata            jsonb;
    v_saldo           jsonb;
    v_id_evento       bigint;
    v_id_presentacion bigint;
    v_id_extraccion   bigint;
    v_id_ledger       bigint;
    v_tipo_pata       text;
    v_cantidad        numeric;
    v_saldo_antes     numeric;
    v_saldo_despues   numeric;
    v_saldo_esperado  numeric;
    v_sku_producto    varchar;
    v_sku_ubicacion   varchar;
    v_eventos         jsonb := '[]'::jsonb;
    v_ledger_ids      jsonb := '[]'::jsonb;
BEGIN
    IF p_plan IS NULL OR p_plan->>'status' <> 'success' THEN
        RAISE EXCEPTION 'El plan de extracción no es aplicable'
            USING ERRCODE = '22023';
    END IF;

    FOR v_conversion IN
        SELECT value FROM jsonb_array_elements(p_plan->'conversiones')
    LOOP
        v_id_evento := public.fn_registrar_conversion_v2(
            (p_plan->>'id_producto')::bigint,
            (p_plan->>'id_ubicacion')::bigint,
            v_conversion->>'tipo',
            v_conversion->'patas',
            NULLIF(p_plan->>'id_variante', '')::bigint,
            NULLIF(p_plan->>'id_opcion_variante', '')::bigint,
            p_id_operacion,
            p_uuid,
            p_motivo
        );
        v_eventos := v_eventos || jsonb_build_object(
            'id_conversion_evento', v_id_evento,
            'tipo', v_conversion->>'tipo'
        );

        FOR v_pata IN
            SELECT value FROM jsonb_array_elements(v_conversion->'patas')
        LOOP
            v_id_presentacion := (v_pata->>'id_presentacion')::bigint;
            v_tipo_pata := v_pata->>'tipo';
            v_cantidad := (v_pata->>'cantidad')::numeric;

            SELECT COALESCE(sum(s.saldo), 0),
                   min(s.sku_producto), min(s.sku_ubicacion)
              INTO v_saldo_antes, v_sku_producto, v_sku_ubicacion
              FROM public.fn_stock_saldos_presentacion(
                       (p_plan->>'id_producto')::bigint, NULL,
                       (p_plan->>'id_ubicacion')::bigint, true
                   ) s
             WHERE s.id_presentacion = v_id_presentacion
               AND s.id_variante IS NOT DISTINCT FROM
                   NULLIF(p_plan->>'id_variante', '')::bigint
               AND s.id_opcion_variante IS NOT DISTINCT FROM
                   NULLIF(p_plan->>'id_opcion_variante', '')::bigint;

            IF v_sku_producto IS NULL THEN
                SELECT p.sku INTO v_sku_producto
                  FROM public.app_dat_producto p
                 WHERE p.id = (p_plan->>'id_producto')::bigint;
            END IF;
            IF v_tipo_pata = 'salida' THEN
                v_saldo_despues := v_saldo_antes - v_cantidad;
            ELSE
                v_saldo_despues := v_saldo_antes + v_cantidad;
            END IF;
            IF v_saldo_despues < 0 THEN
                RAISE EXCEPTION 'Conversión % deja saldo negativo en presentación %',
                    v_id_evento, v_id_presentacion USING ERRCODE = 'P0001';
            END IF;

            INSERT INTO public.app_dat_inventario_productos (
                id_producto, id_variante, id_opcion_variante, id_ubicacion,
                id_presentacion, cantidad_inicial, cantidad_final,
                sku_producto, sku_ubicacion, origen_cambio,
                id_conversion_evento, created_at
            ) VALUES (
                (p_plan->>'id_producto')::bigint,
                NULLIF(p_plan->>'id_variante', '')::bigint,
                NULLIF(p_plan->>'id_opcion_variante', '')::bigint,
                (p_plan->>'id_ubicacion')::bigint,
                v_id_presentacion, v_saldo_antes, v_saldo_despues,
                v_sku_producto, v_sku_ubicacion, 20, v_id_evento, now()
            ) RETURNING id INTO v_id_ledger;
            v_ledger_ids := v_ledger_ids || to_jsonb(v_id_ledger);
        END LOOP;
    END LOOP;

    FOR v_pata IN
        SELECT value FROM jsonb_array_elements(p_plan->'lineas_fisicas')
    LOOP
        v_id_presentacion := (v_pata->>'id_presentacion')::bigint;
        v_cantidad := (v_pata->>'cantidad')::numeric;
        v_id_extraccion := NULLIF(
            p_extracciones_por_presentacion->>v_id_presentacion::text, ''
        )::bigint;
        IF v_id_extraccion IS NULL THEN
            RAISE EXCEPTION 'No existe detalle de extracción para presentación %',
                v_id_presentacion USING ERRCODE = '22023';
        END IF;

        SELECT COALESCE(sum(s.saldo), 0),
               min(s.sku_producto), min(s.sku_ubicacion)
          INTO v_saldo_antes, v_sku_producto, v_sku_ubicacion
          FROM public.fn_stock_saldos_presentacion(
                   (p_plan->>'id_producto')::bigint, NULL,
                   (p_plan->>'id_ubicacion')::bigint, true
               ) s
         WHERE s.id_presentacion = v_id_presentacion
           AND s.id_variante IS NOT DISTINCT FROM
               NULLIF(p_plan->>'id_variante', '')::bigint
           AND s.id_opcion_variante IS NOT DISTINCT FROM
               NULLIF(p_plan->>'id_opcion_variante', '')::bigint;

        v_saldo_despues := v_saldo_antes - v_cantidad;
        IF v_saldo_despues < 0 THEN
            RAISE EXCEPTION 'La extracción deja saldo negativo en presentación %',
                v_id_presentacion USING ERRCODE = 'P0001';
        END IF;
        IF v_sku_producto IS NULL THEN
            SELECT p.sku INTO v_sku_producto
              FROM public.app_dat_producto p
             WHERE p.id = (p_plan->>'id_producto')::bigint;
        END IF;

        INSERT INTO public.app_dat_inventario_productos (
            id_producto, id_variante, id_opcion_variante, id_ubicacion,
            id_presentacion, cantidad_inicial, cantidad_final,
            sku_producto, sku_ubicacion, origen_cambio,
            id_extraccion, created_at
        ) VALUES (
            (p_plan->>'id_producto')::bigint,
            NULLIF(p_plan->>'id_variante', '')::bigint,
            NULLIF(p_plan->>'id_opcion_variante', '')::bigint,
            (p_plan->>'id_ubicacion')::bigint,
            v_id_presentacion, v_saldo_antes, v_saldo_despues,
            v_sku_producto, v_sku_ubicacion, 2, v_id_extraccion, now()
        ) RETURNING id INTO v_id_ledger;
        v_ledger_ids := v_ledger_ids || to_jsonb(v_id_ledger);
    END LOOP;

    FOR v_saldo IN
        SELECT value FROM jsonb_array_elements(p_plan->'saldos_proyectados')
    LOOP
        SELECT COALESCE(sum(s.saldo), 0)
          INTO v_saldo_despues
          FROM public.fn_stock_saldos_presentacion(
                   (p_plan->>'id_producto')::bigint, NULL,
                   (p_plan->>'id_ubicacion')::bigint, true
               ) s
         WHERE s.id_presentacion = (v_saldo->>'id_presentacion')::bigint
           AND s.id_variante IS NOT DISTINCT FROM
               NULLIF(p_plan->>'id_variante', '')::bigint
           AND s.id_opcion_variante IS NOT DISTINCT FROM
               NULLIF(p_plan->>'id_opcion_variante', '')::bigint;
        v_saldo_esperado := (v_saldo->>'cantidad')::numeric;
        IF v_saldo_despues <> v_saldo_esperado OR v_saldo_despues < 0 THEN
            RAISE EXCEPTION 'Saldo final inconsistente para presentación %: esperado %, real %',
                v_saldo->>'id_presentacion', v_saldo_esperado, v_saldo_despues
                USING ERRCODE = 'P0001';
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'eventos_conversion', v_eventos,
        'ledger_ids', v_ledger_ids
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_aplicar_plan_extraccion_v2(
    jsonb, jsonb, bigint, uuid, text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_aplicar_plan_extraccion_v2(
    jsonb, jsonb, bigint, uuid, text
) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_crear_extraccion_con_movimiento_v2(
    p_autorizado_por       text,
    p_id_motivo_operacion  bigint,
    p_id_tienda            bigint,
    p_observaciones        text,
    p_productos            jsonb,
    p_client_request_uuid  uuid
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_actor_uuid       uuid := auth.uid();
    v_payload          jsonb;
    v_payload_hash     text;
    v_solicitud        public.app_dat_extraccion_v2_solicitud%ROWTYPE;
    v_autorizado       boolean;
    v_id_tipo_operacion bigint;
    v_id_operacion     bigint;
    v_producto         jsonb;
    v_linea            jsonb;
    v_plan             jsonb;
    v_aplicacion       jsonb;
    v_planes           jsonb := '[]'::jsonb;
    v_lineas_logicas   jsonb := '[]'::jsonb;
    v_lineas_fisicas   jsonb := '[]'::jsonb;
    v_eventos          jsonb := '[]'::jsonb;
    v_ledger_ids       jsonb := '[]'::jsonb;
    v_mapa_extracciones jsonb;
    v_id_producto      bigint;
    v_id_variante      bigint;
    v_id_opcion        bigint;
    v_id_ubicacion     bigint;
    v_id_presentacion  bigint;
    v_cantidad         numeric;
    v_precio_unitario  numeric;
    v_precio_fisico    numeric;
    v_sku_producto     varchar;
    v_sku_ubicacion    varchar;
    v_id_extraccion    bigint;
    v_total_cantidad   numeric := 0;
    v_respuesta        jsonb;
BEGIN
    IF v_actor_uuid IS NULL THEN
        RAISE EXCEPTION 'Se requiere un usuario autenticado'
            USING ERRCODE = '42501';
    END IF;
    IF p_client_request_uuid IS NULL THEN
        RAISE EXCEPTION 'client_request_uuid es obligatorio'
            USING ERRCODE = '22023';
    END IF;
    IF p_id_tienda IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.app_dat_tienda t WHERE t.id = p_id_tienda
    ) THEN
        RAISE EXCEPTION 'La tienda % no existe', p_id_tienda
            USING ERRCODE = '22023';
    END IF;
    IF p_id_motivo_operacion IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.app_nom_motivo_extraccion m
         WHERE m.id = p_id_motivo_operacion
    ) THEN
        RAISE EXCEPTION 'El motivo de extracción % no existe', p_id_motivo_operacion
            USING ERRCODE = '22023';
    END IF;
    IF p_productos IS NULL OR jsonb_typeof(p_productos) <> 'array'
       OR jsonb_array_length(p_productos) = 0 THEN
        RAISE EXCEPTION 'Debe incluir al menos un producto'
            USING ERRCODE = '22023';
    END IF;

    SELECT EXISTS (
        SELECT 1
          FROM public.app_dat_vendedor v
          JOIN public.app_dat_tpv t ON t.id = v.id_tpv
         WHERE v.uuid = v_actor_uuid AND t.id_tienda = p_id_tienda
        UNION ALL
        SELECT 1
          FROM public.app_dat_almacenero al
          JOIN public.app_dat_almacen a ON a.id = al.id_almacen
         WHERE al.uuid = v_actor_uuid AND a.id_tienda = p_id_tienda
        UNION ALL
        SELECT 1 FROM public.app_dat_supervisor s
         WHERE s.uuid = v_actor_uuid AND s.id_tienda = p_id_tienda
        UNION ALL
        SELECT 1 FROM public.auditor au
         WHERE au.uuid = v_actor_uuid AND au.id_tienda = p_id_tienda
        UNION ALL
        SELECT 1 FROM public.app_dat_gerente g
         WHERE g.uuid = v_actor_uuid AND g.id_tienda = p_id_tienda
        UNION ALL
        SELECT 1
          FROM public.app_dat_jefe_cocina jc
          JOIN public.app_dat_cocina c ON c.id = jc.id_cocina
         WHERE jc.uuid = v_actor_uuid
           AND c.id_tienda = p_id_tienda
           AND c.deleted_at IS NULL
    ) INTO v_autorizado;
    IF NOT COALESCE(v_autorizado, false) THEN
        RAISE EXCEPTION 'Acceso denegado a la tienda %', p_id_tienda
            USING ERRCODE = '42501';
    END IF;

    -- Serializa por UUID antes de normalizar y consultar su solicitud persistida.
    PERFORM pg_advisory_xact_lock(
        hashtextextended(p_client_request_uuid::text, 0)
    );

    -- Primero valida todas las líneas. Las claves se bloquean después en orden
    -- canónico, independientemente del orden recibido desde el cliente.
    FOR v_producto IN SELECT value FROM jsonb_array_elements(p_productos)
    LOOP
        BEGIN
            v_id_producto := NULLIF(v_producto->>'id_producto', '')::bigint;
            v_id_variante := NULLIF(v_producto->>'id_variante', '')::bigint;
            v_id_opcion := NULLIF(v_producto->>'id_opcion_variante', '')::bigint;
            v_id_ubicacion := NULLIF(v_producto->>'id_ubicacion', '')::bigint;
            v_id_presentacion := NULLIF(v_producto->>'id_presentacion', '')::bigint;
            v_cantidad := NULLIF(v_producto->>'cantidad', '')::numeric;
            v_precio_unitario := NULLIF(v_producto->>'precio_unitario', '')::numeric;
        EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
            RAISE EXCEPTION 'Una línea contiene identificadores o cantidades inválidos'
                USING ERRCODE = '22023';
        END;

        IF v_id_producto IS NULL OR v_id_ubicacion IS NULL
           OR v_cantidad IS NULL OR v_cantidad <= 0
           OR v_cantidad::text IN ('NaN', 'Infinity', '-Infinity') THEN
            RAISE EXCEPTION 'Cada línea requiere producto, ubicación y cantidad positiva finita'
                USING ERRCODE = '22023';
        END IF;
        IF v_precio_unitario IS NOT NULL
           AND (v_precio_unitario < 0
                OR v_precio_unitario::text IN ('NaN', 'Infinity', '-Infinity')) THEN
            RAISE EXCEPTION 'El precio unitario debe ser finito y no negativo'
                USING ERRCODE = '22023';
        END IF;

        SELECT p.sku, la.sku_codigo
          INTO v_sku_producto, v_sku_ubicacion
          FROM public.app_dat_producto p
          JOIN public.app_dat_layout_almacen la ON la.id = v_id_ubicacion
          JOIN public.app_dat_almacen a ON a.id = la.id_almacen
         WHERE p.id = v_id_producto
           AND p.id_tienda = p_id_tienda
           AND p.deleted_at IS NULL
           AND la.deleted_at IS NULL
           AND a.deleted_at IS NULL
           AND a.id_tienda = p_id_tienda;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Producto % o ubicación % no pertenecen a la tienda %',
                v_id_producto, v_id_ubicacion, p_id_tienda
                USING ERRCODE = '22023';
        END IF;
        IF v_id_opcion IS NOT NULL AND v_id_variante IS NULL THEN
            RAISE EXCEPTION 'Una opción de variante requiere id_variante'
                USING ERRCODE = '22023';
        END IF;
        IF v_id_variante IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM public.app_dat_variantes v
             WHERE v.id = v_id_variante
        ) THEN
            RAISE EXCEPTION 'La variante % no existe', v_id_variante
                USING ERRCODE = '22023';
        END IF;
        IF v_id_opcion IS NOT NULL AND NOT EXISTS (
            SELECT 1
              FROM public.app_dat_variantes v
              JOIN public.app_dat_atributo_opcion ao
                ON ao.id_atributo = v.id_atributo
             WHERE v.id = v_id_variante AND ao.id = v_id_opcion
        ) THEN
            RAISE EXCEPTION 'La opción % no pertenece a la variante %',
                v_id_opcion, v_id_variante USING ERRCODE = '22023';
        END IF;

        IF v_id_presentacion IS NULL THEN
            SELECT c.id_presentacion INTO v_id_presentacion
              FROM public.fn_presentaciones_producto_v2(v_id_producto) c
             WHERE c.es_base LIMIT 1;
        ELSE
            PERFORM 1
              FROM public.fn_presentaciones_producto_v2(v_id_producto) c
             WHERE c.id_presentacion = v_id_presentacion;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'La presentación % no pertenece al producto %',
                    v_id_presentacion, v_id_producto USING ERRCODE = '22023';
            END IF;
        END IF;
        IF v_id_presentacion IS NULL THEN
            RAISE EXCEPTION 'El producto % no tiene presentación base', v_id_producto
                USING ERRCODE = '22023';
        END IF;

        v_lineas_logicas := v_lineas_logicas || jsonb_build_object(
            'id_producto', v_id_producto,
            'id_variante', v_id_variante,
            'id_opcion_variante', v_id_opcion,
            'id_ubicacion', v_id_ubicacion,
            'id_presentacion', v_id_presentacion,
            'cantidad', v_cantidad,
            'precio_unitario', v_precio_unitario,
            'sku_producto', v_sku_producto,
            'sku_ubicacion', v_sku_ubicacion
        );
        v_total_cantidad := v_total_cantidad + v_cantidad;
    END LOOP;

    -- El hash usa únicamente el contrato normalizado que gobierna la operación:
    -- el orden original se conserva, pero NULL/base y SKU derivados son canónicos.
    v_payload := jsonb_build_object(
        'autorizado_por', COALESCE(p_autorizado_por, ''),
        'id_motivo_operacion', p_id_motivo_operacion,
        'id_tienda', p_id_tienda,
        'observaciones', COALESCE(p_observaciones, ''),
        'productos', v_lineas_logicas,
        'actor_uuid', v_actor_uuid
    );
    v_payload_hash := md5(v_payload::text);

    SELECT s.* INTO v_solicitud
      FROM public.app_dat_extraccion_v2_solicitud s
     WHERE s.client_request_uuid = p_client_request_uuid;
    IF FOUND THEN
        IF v_solicitud.payload_hash <> v_payload_hash THEN
            RAISE EXCEPTION 'IDEMPOTENCY_KEY_REUSED: el UUID ya fue usado con otro payload'
                USING ERRCODE = '22023';
        END IF;
        IF v_solicitud.estado = 'completado' AND v_solicitud.respuesta IS NOT NULL THEN
            RETURN v_solicitud.respuesta
                   || jsonb_build_object('idempotent_replay', true);
        END IF;
        RAISE EXCEPTION 'La solicitud idempotente quedó en un estado inconsistente'
            USING ERRCODE = '55000';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM (
              SELECT (value->>'id_producto')::bigint id_producto,
                     NULLIF(value->>'id_variante', '')::bigint id_variante,
                     NULLIF(value->>'id_opcion_variante', '')::bigint id_opcion,
                     (value->>'id_ubicacion')::bigint id_ubicacion,
                     count(*) total
                FROM jsonb_array_elements(v_lineas_logicas)
               GROUP BY 1, 2, 3, 4
          ) d
         WHERE d.total > 1
    ) THEN
        RAISE EXCEPTION 'No se permiten líneas lógicas duplicadas; agrupe sus cantidades'
            USING ERRCODE = '22023';
    END IF;

    FOR v_linea IN
        SELECT value
          FROM jsonb_array_elements(v_lineas_logicas)
         ORDER BY (value->>'id_producto')::bigint,
                  COALESCE(NULLIF(value->>'id_variante', '')::bigint, 0),
                  COALESCE(NULLIF(value->>'id_opcion_variante', '')::bigint, 0),
                  (value->>'id_ubicacion')::bigint
    LOOP
        PERFORM pg_advisory_xact_lock(
            hashtextextended(
                format('%s:%s:%s:%s',
                    v_linea->>'id_producto',
                    COALESCE(NULLIF(v_linea->>'id_variante', ''), '0'),
                    COALESCE(NULLIF(v_linea->>'id_opcion_variante', ''), '0'),
                    v_linea->>'id_ubicacion'),
                41002
            )
        );
    END LOOP;

    -- Planifica el lote completo antes de la primera escritura persistente.
    FOR v_linea IN SELECT value FROM jsonb_array_elements(v_lineas_logicas)
    LOOP
        v_plan := public.fn_planificar_cumplimiento_presentaciones_v2(
            (v_linea->>'id_producto')::bigint,
            (v_linea->>'id_ubicacion')::bigint,
            (v_linea->>'id_presentacion')::bigint,
            (v_linea->>'cantidad')::numeric,
            NULLIF(v_linea->>'id_variante', '')::bigint,
            NULLIF(v_linea->>'id_opcion_variante', '')::bigint
        );
        IF v_plan->>'status' <> 'success' THEN
            RAISE EXCEPTION 'No se pudo cumplir una línea: %',
                COALESCE(v_plan->>'message', v_plan::text)
                USING ERRCODE = 'P0001';
        END IF;
        v_planes := v_planes || jsonb_build_object(
            'linea_logica', v_linea,
            'plan', v_plan
        );
    END LOOP;

    INSERT INTO public.app_dat_extraccion_v2_solicitud (
        client_request_uuid, payload_hash, actor_uuid, id_tienda
    ) VALUES (
        p_client_request_uuid, v_payload_hash, v_actor_uuid, p_id_tienda
    ) RETURNING * INTO v_solicitud;

    SELECT t.id INTO v_id_tipo_operacion
      FROM public.app_nom_tipo_operacion t
     WHERE lower(t.accion) = 'salida'
       AND (t.denominacion ILIKE '%extracción%'
            OR t.denominacion ILIKE '%extraccion%')
     ORDER BY t.id LIMIT 1;
    IF v_id_tipo_operacion IS NULL THEN
        RAISE EXCEPTION 'No se encontró tipo de operación para extracción'
            USING ERRCODE = '55000';
    END IF;

    INSERT INTO public.app_dat_operaciones (
        id_tipo_operacion, uuid, id_tienda, observaciones, contabilizada,
        contabilizada_at, contabilizada_por, created_at
    ) VALUES (
        v_id_tipo_operacion, v_actor_uuid, p_id_tienda, p_observaciones,
        true, now(), v_actor_uuid, now()
    ) RETURNING id INTO v_id_operacion;

    INSERT INTO public.app_dat_operacion_extraccion (
        id_operacion, id_motivo_operacion, observaciones,
        autorizado_por, created_at
    ) VALUES (
        v_id_operacion, p_id_motivo_operacion, p_observaciones,
        p_autorizado_por, now()
    );

    FOR v_producto IN SELECT value FROM jsonb_array_elements(v_planes)
    LOOP
        v_linea := v_producto->'linea_logica';
        v_plan := v_producto->'plan';
        v_mapa_extracciones := '{}'::jsonb;

        FOR v_linea IN
            SELECT jsonb_build_object(
                       'id_presentacion', (value->>'id_presentacion')::bigint,
                       'nombre', min(value->>'nombre'),
                       'cantidad', sum((value->>'cantidad')::numeric),
                       'factor_entero', min((value->>'factor_entero')::numeric),
                       'equivalente', sum((value->>'equivalente')::numeric),
                       'origenes', jsonb_agg(value->>'origen' ORDER BY value->>'origen')
                   )
              FROM jsonb_array_elements(v_plan->'lineas_fisicas')
             GROUP BY (value->>'id_presentacion')::bigint
             ORDER BY (value->>'id_presentacion')::bigint
        LOOP
            v_id_presentacion := (v_linea->>'id_presentacion')::bigint;
            v_cantidad := (v_linea->>'cantidad')::numeric;
            v_precio_unitario := NULLIF(
                (v_producto->'linea_logica')->>'precio_unitario', ''
            )::numeric;
            v_precio_fisico := CASE
                WHEN v_precio_unitario IS NULL THEN NULL
                ELSE v_precio_unitario
                     * (v_linea->>'factor_entero')::numeric
                     * (v_plan->>'cantidad_solicitada')::numeric
                     / NULLIF((v_plan->>'equivalente_solicitado')::numeric, 0)
            END;
            v_sku_producto := (v_producto->'linea_logica')->>'sku_producto';
            v_sku_ubicacion := (v_producto->'linea_logica')->>'sku_ubicacion';

            INSERT INTO public.app_dat_extraccion_productos (
                id_operacion, id_producto, id_variante, id_opcion_variante,
                id_ubicacion, id_presentacion, cantidad, precio_unitario,
                sku_producto, sku_ubicacion, importe, importe_real, created_at
            ) VALUES (
                v_id_operacion,
                (v_plan->>'id_producto')::bigint,
                NULLIF(v_plan->>'id_variante', '')::bigint,
                NULLIF(v_plan->>'id_opcion_variante', '')::bigint,
                (v_plan->>'id_ubicacion')::bigint,
                v_id_presentacion, v_cantidad, v_precio_fisico,
                v_sku_producto, v_sku_ubicacion,
                CASE WHEN v_precio_fisico IS NULL THEN NULL
                     ELSE v_precio_fisico * v_cantidad END,
                NULL, now()
            ) RETURNING id INTO v_id_extraccion;

            v_mapa_extracciones := v_mapa_extracciones
                || jsonb_build_object(v_id_presentacion::text, v_id_extraccion);
            v_lineas_fisicas := v_lineas_fisicas || (
                v_linea || jsonb_build_object(
                    'id_extraccion', v_id_extraccion,
                    'id_producto', (v_plan->>'id_producto')::bigint,
                    'id_variante', NULLIF(v_plan->>'id_variante', '')::bigint,
                    'id_opcion_variante',
                        NULLIF(v_plan->>'id_opcion_variante', '')::bigint,
                    'id_ubicacion', (v_plan->>'id_ubicacion')::bigint,
                    'id_presentacion_solicitada',
                        (v_plan->>'id_presentacion_solicitada')::bigint,
                    'cantidad_solicitada',
                        (v_plan->>'cantidad_solicitada')::numeric
                )
            );
        END LOOP;

        v_aplicacion := public.fn_aplicar_plan_extraccion_v2(
            v_plan, v_mapa_extracciones, v_id_operacion, v_actor_uuid,
            COALESCE(NULLIF(p_observaciones, ''), 'extracción administrativa v2')
        );
        v_eventos := v_eventos || COALESCE(
            v_aplicacion->'eventos_conversion', '[]'::jsonb
        );
        v_ledger_ids := v_ledger_ids || COALESCE(
            v_aplicacion->'ledger_ids', '[]'::jsonb
        );
    END LOOP;

    INSERT INTO public.app_dat_estado_operacion (
        id_operacion, estado, uuid, comentario, created_at
    ) VALUES (
        v_id_operacion, 2, v_actor_uuid,
        'Extracción física v2 contabilizada atómicamente', now()
    );

    v_respuesta := jsonb_build_object(
        'status', 'success',
        'id_operacion', v_id_operacion,
        'client_request_uuid', p_client_request_uuid,
        'total_productos', jsonb_array_length(v_lineas_logicas),
        'cantidad_total', v_total_cantidad,
        'lineas_logicas', v_lineas_logicas,
        'lineas_fisicas', v_lineas_fisicas,
        'eventos_conversion', v_eventos,
        'ledger_ids', v_ledger_ids,
        'idempotent_replay', false,
        'mensaje', 'Extracción registrada, contabilizada y aplicada atómicamente'
    );

    UPDATE public.app_dat_extraccion_v2_solicitud
       SET estado = 'completado', id_operacion = v_id_operacion,
           respuesta = v_respuesta, completed_at = now()
     WHERE id = v_solicitud.id;

    RETURN v_respuesta;
END;
$function$;

COMMENT ON FUNCTION public.fn_crear_extraccion_con_movimiento_v2(
    text, bigint, bigint, text, jsonb, uuid
) IS 'Crea y contabiliza una extracción administrativa multilínea usando el cumplimiento físico v2 e idempotencia de operación.';

REVOKE ALL ON FUNCTION public.fn_crear_extraccion_con_movimiento_v2(
    text, bigint, bigint, text, jsonb, uuid
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_crear_extraccion_con_movimiento_v2(
    text, bigint, bigint, text, jsonb, uuid
) TO authenticated, service_role;
