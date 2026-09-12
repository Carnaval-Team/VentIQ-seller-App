-- ============================================================================
-- 38 · Planificador puro de cumplimiento físico por presentaciones v2
-- ============================================================================
-- Requiere 35. No escribe inventario ni toma locks: calcula líneas físicas,
-- conversiones necesarias y saldos proyectados sobre un snapshot vigente.
-- El ejecutor posterior volverá a planificar dentro de la transacción bloqueada.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_combinar_factores_presentacion_v2(
    p_factores       numeric[],
    p_disponibles    numeric[],
    p_fraccionables  boolean[],
    p_objetivo       numeric,
    p_indice         integer DEFAULT 1
)
RETURNS numeric[]
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
    v_n          integer := COALESCE(array_length(p_factores, 1), 0);
    v_factor     numeric;
    v_disponible numeric;
    v_cantidad   numeric;
    v_resto      numeric;
    v_resultado  numeric[];
BEGIN
    IF p_objetivo < 0 OR p_indice < 1 THEN
        RETURN NULL;
    END IF;

    IF p_objetivo = 0 THEN
        RETURN array_fill(0::numeric, ARRAY[v_n]);
    END IF;

    IF p_indice > v_n THEN
        RETURN NULL;
    END IF;

    v_factor := p_factores[p_indice];
    v_disponible := GREATEST(COALESCE(p_disponibles[p_indice], 0), 0);

    IF v_factor IS NULL OR v_factor <= 0 THEN
        RETURN NULL;
    END IF;

    IF COALESCE(p_fraccionables[p_indice], false) THEN
        v_cantidad := p_objetivo / v_factor;
        IF v_cantidad <= v_disponible THEN
            v_resultado := array_fill(0::numeric, ARRAY[v_n]);
            v_resultado[p_indice] := v_cantidad;
            RETURN v_resultado;
        END IF;
        RETURN NULL;
    END IF;

    v_cantidad := LEAST(floor(v_disponible), floor(p_objetivo / v_factor));
    WHILE v_cantidad >= 0 LOOP
        v_resto := p_objetivo - (v_cantidad * v_factor);
        v_resultado := public.fn_combinar_factores_presentacion_v2(
            p_factores, p_disponibles, p_fraccionables, v_resto, p_indice + 1
        );
        IF v_resultado IS NOT NULL THEN
            v_resultado[p_indice] := v_cantidad;
            RETURN v_resultado;
        END IF;
        v_cantidad := v_cantidad - 1;
    END LOOP;

    RETURN NULL;
END;
$function$;

COMMENT ON FUNCTION public.fn_combinar_factores_presentacion_v2(
    numeric[], numeric[], boolean[], numeric, integer
) IS
    'Solver interno exacto y lexicográfico. Busca una combinación acotada en el '
    'orden recibido, maximizando primero los factores mayores.';

REVOKE ALL ON FUNCTION public.fn_combinar_factores_presentacion_v2(
    numeric[], numeric[], boolean[], numeric, integer
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_combinar_factores_presentacion_v2(
    numeric[], numeric[], boolean[], numeric, integer
) TO service_role;


CREATE OR REPLACE FUNCTION public.fn_descomponer_equivalente_presentacion_v2(
    p_factores       numeric[],
    p_fraccionables  boolean[],
    p_objetivo       numeric,
    p_indice         integer DEFAULT 1
)
RETURNS numeric[]
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
    v_n         integer := COALESCE(array_length(p_factores, 1), 0);
    v_factor    numeric;
    v_cantidad  numeric;
    v_resto     numeric;
    v_resultado numeric[];
BEGIN
    IF p_objetivo < 0 OR p_indice < 1 THEN
        RETURN NULL;
    END IF;

    IF p_objetivo = 0 THEN
        RETURN array_fill(0::numeric, ARRAY[v_n]);
    END IF;

    IF p_indice > v_n THEN
        RETURN NULL;
    END IF;

    v_factor := p_factores[p_indice];
    IF v_factor IS NULL OR v_factor <= 0 THEN
        RETURN NULL;
    END IF;

    IF COALESCE(p_fraccionables[p_indice], false) THEN
        v_resultado := array_fill(0::numeric, ARRAY[v_n]);
        v_resultado[p_indice] := p_objetivo / v_factor;
        RETURN v_resultado;
    END IF;

    v_cantidad := floor(p_objetivo / v_factor);
    WHILE v_cantidad >= 0 LOOP
        v_resto := p_objetivo - (v_cantidad * v_factor);
        v_resultado := public.fn_descomponer_equivalente_presentacion_v2(
            p_factores, p_fraccionables, v_resto, p_indice + 1
        );
        IF v_resultado IS NOT NULL THEN
            v_resultado[p_indice] := v_cantidad;
            RETURN v_resultado;
        END IF;
        v_cantidad := v_cantidad - 1;
    END LOOP;

    RETURN NULL;
END;
$function$;

COMMENT ON FUNCTION public.fn_descomponer_equivalente_presentacion_v2(
    numeric[], boolean[], numeric, integer
) IS
    'Descompone un equivalente exacto en cantidades físicas válidas, priorizando '
    'los factores mayores y permitiendo fracción solo en presentaciones declaradas.';

REVOKE ALL ON FUNCTION public.fn_descomponer_equivalente_presentacion_v2(
    numeric[], boolean[], numeric, integer
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_descomponer_equivalente_presentacion_v2(
    numeric[], boolean[], numeric, integer
) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_planificar_cumplimiento_presentaciones_v2(
    p_id_producto        bigint,
    p_id_ubicacion       bigint,
    p_id_presentacion    bigint,
    p_cantidad           numeric,
    p_id_variante        bigint DEFAULT NULL,
    p_id_opcion_variante bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
    v_n                   integer;
    v_t                   integer;
    v_i                   integer;
    v_k                   integer;
    v_j                   integer;
    v_id_presentacion     bigint;
    v_factor_solicitado   numeric;
    v_equiv_solicitado    numeric;
    v_equiv_total         numeric := 0;
    v_equiv_cumplido      numeric := 0;
    v_residuo             numeric;
    v_abierto             numeric;
    v_id_abierto          bigint;
    v_nombre_abierto      text;
    v_factor_abierto      numeric;
    v_cantidad_abierta    numeric;
    v_estrategia          text;
    v_ids                 bigint[] := '{}';
    v_nombres             text[] := '{}';
    v_factores            numeric[] := '{}';
    v_saldos              numeric[] := '{}';
    v_saldos_iniciales    numeric[] := '{}';
    v_fraccionables       boolean[] := '{}';
    v_entrega             numeric[] := '{}';
    v_lineas              jsonb := '[]'::jsonb;
    v_conversiones        jsonb := '[]'::jsonb;
    v_saldos_json         jsonb := '[]'::jsonb;
    v_cerrados_ids        bigint[] := '{}';
    v_cerrados_factores   numeric[] := '{}';
    v_cerrados_saldos     numeric[] := '{}';
    v_cerrados_fracc      boolean[] := '{}';
    v_exacta              numeric[];
    v_outputs_ids         bigint[];
    v_outputs_factores    numeric[];
    v_outputs_fracc       boolean[];
    v_outputs_saldos      numeric[];
    v_descomposicion      numeric[];
    v_patas               jsonb;
    v_origen              text[] := '{}';
    v_entrega_origen      jsonb := '{}'::jsonb;
    r                      record;
BEGIN
    IF p_id_producto IS NULL OR p_id_ubicacion IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error', 'error_code', 'INVALID_ARGUMENT',
            'message', 'Producto y ubicación son obligatorios'
        );
    END IF;

    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RETURN jsonb_build_object(
            'status', 'error', 'error_code', 'INVALID_QUANTITY',
            'message', 'La cantidad solicitada debe ser mayor que cero'
        );
    END IF;

    IF p_id_presentacion IS NULL THEN
        SELECT c.id_presentacion
          INTO v_id_presentacion
          FROM public.fn_presentaciones_producto_v2(p_id_producto) AS c
         WHERE c.es_base
         LIMIT 1;
    ELSE
        SELECT c.id_presentacion
          INTO v_id_presentacion
          FROM public.fn_presentaciones_producto_v2(p_id_producto) AS c
         WHERE c.id_presentacion = p_id_presentacion;
    END IF;

    IF v_id_presentacion IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error', 'error_code', 'PRESENTATION_NOT_IN_CHAIN',
            'message', format('La presentación %s no pertenece al producto %s',
                              p_id_presentacion, p_id_producto)
        );
    END IF;

    FOR r IN
        SELECT c.*
          FROM public.fn_presentaciones_producto_v2(p_id_producto) AS c
         ORDER BY c.factor_entero DESC, c.id_presentacion
    LOOP
        v_ids := array_append(v_ids, r.id_presentacion);
        v_nombres := array_append(v_nombres, r.nombre::text);
        v_factores := array_append(v_factores, r.factor_entero);
        v_fraccionables := array_append(v_fraccionables, r.es_fraccionable);
        v_saldos := array_append(v_saldos, 0::numeric);
        v_entrega := array_append(v_entrega, 0::numeric);
        v_origen := array_append(v_origen, NULL::text);
        IF r.id_presentacion = v_id_presentacion THEN
            v_t := array_length(v_ids, 1);
            v_factor_solicitado := r.factor_entero;
        END IF;
    END LOOP;

    v_n := COALESCE(array_length(v_ids, 1), 0);
    IF v_n = 0 OR v_t IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error', 'error_code', 'CATALOGO_PRESENTACIONES_INVALIDO',
            'message', 'No se pudo resolver el catálogo de presentaciones'
        );
    END IF;

    FOR r IN
        SELECT s.id_presentacion, sum(s.saldo) AS saldo
          FROM public.fn_stock_saldos_presentacion(
                   p_id_producto, NULL, p_id_ubicacion, true
               ) AS s
         WHERE s.id_variante IS NOT DISTINCT FROM p_id_variante
           AND s.id_opcion_variante IS NOT DISTINCT FROM p_id_opcion_variante
         GROUP BY s.id_presentacion
    LOOP
        FOR v_i IN 1 .. v_n LOOP
            IF v_ids[v_i] = r.id_presentacion THEN
                v_saldos[v_i] := COALESCE(r.saldo, 0);
                EXIT;
            END IF;
        END LOOP;
    END LOOP;

    v_saldos_iniciales := v_saldos;

    FOR v_i IN 1 .. v_n LOOP
        IF NOT v_fraccionables[v_i]
           AND trunc(v_saldos[v_i]) <> v_saldos[v_i] THEN
            RETURN jsonb_build_object(
                'status', 'error',
                'error_code', 'SALDO_FISICO_INVALIDO',
                'message', format(
                    'La presentación %s tiene saldo físico no entero: %s',
                    v_nombres[v_i], v_saldos[v_i]
                ),
                'id_presentacion', v_ids[v_i]
            );
        END IF;
        v_equiv_total := v_equiv_total + v_saldos[v_i] * v_factores[v_i];
    END LOOP;

    IF NOT v_fraccionables[v_t] AND trunc(p_cantidad) <> p_cantidad THEN
        RETURN jsonb_build_object(
            'status', 'error', 'error_code', 'INVALID_PHYSICAL_QUANTITY',
            'message', 'La presentación solicitada no admite cantidades fraccionarias'
        );
    END IF;

    v_equiv_solicitado := p_cantidad * v_factor_solicitado;
    IF v_equiv_total < v_equiv_solicitado THEN
        RETURN jsonb_build_object(
            'status', 'error', 'error_code', 'INSUFFICIENT_STOCK',
            'message', 'Stock equivalente insuficiente',
            'equivalente_solicitado', v_equiv_solicitado,
            'equivalente_disponible', v_equiv_total,
            'maximo_servible', v_equiv_total / v_factor_solicitado
        );
    END IF;
    IF v_t > 1 THEN
        FOR v_i IN 1 .. (v_t - 1) LOOP
            v_cerrados_ids := array_append(v_cerrados_ids, v_ids[v_i]);
            v_cerrados_factores := array_append(v_cerrados_factores, v_factores[v_i]);
            v_cerrados_saldos := array_append(v_cerrados_saldos, v_saldos[v_i]);
            v_cerrados_fracc := array_append(v_cerrados_fracc, false);
        END LOOP;
    END IF;

    IF array_length(v_cerrados_ids, 1) IS NOT NULL THEN
        v_exacta := public.fn_combinar_factores_presentacion_v2(
            v_cerrados_factores,
            v_cerrados_saldos,
            v_cerrados_fracc,
            v_equiv_solicitado,
            1
        );
    END IF;

    IF v_exacta IS NOT NULL THEN
        v_estrategia := 'empaques_cerrados_exactos';
        FOR v_i IN 1 .. array_length(v_exacta, 1) LOOP
            IF v_exacta[v_i] > 0 THEN
                v_entrega[v_i] := v_exacta[v_i];
                v_origen[v_i] := 'empaque_cerrado';
                v_entrega_origen := v_entrega_origen || jsonb_build_object(
                    format('%s:empaque_cerrado', v_i), v_exacta[v_i]
                );
                v_saldos[v_i] := v_saldos[v_i] - v_exacta[v_i];
            END IF;
        END LOOP;
    ELSE
        v_estrategia := 'mixto_con_apertura';
        v_residuo := v_equiv_solicitado;

        IF v_saldos[v_t] > 0 THEN
            v_cantidad_abierta := LEAST(
                v_saldos[v_t],
                v_residuo / v_factor_solicitado
            );
            IF NOT v_fraccionables[v_t] THEN
                v_cantidad_abierta := floor(v_cantidad_abierta);
            END IF;
            IF v_cantidad_abierta > 0 THEN
                v_entrega[v_t] := v_cantidad_abierta;
                v_origen[v_t] := 'propio';
                v_entrega_origen := v_entrega_origen || jsonb_build_object(
                    format('%s:propio', v_t), v_cantidad_abierta
                );
                v_saldos[v_t] := v_saldos[v_t] - v_cantidad_abierta;
                v_residuo := v_residuo
                             - v_cantidad_abierta * v_factor_solicitado;
            END IF;
        END IF;

        v_cerrados_saldos := '{}';
        IF v_t > 1 THEN
            FOR v_i IN 1 .. (v_t - 1) LOOP
                v_cerrados_saldos := array_append(v_cerrados_saldos, v_saldos[v_i]);
            END LOOP;
        END IF;
        v_exacta := NULL;
        IF v_residuo > 0 AND array_length(v_cerrados_ids, 1) IS NOT NULL THEN
            v_exacta := public.fn_combinar_factores_presentacion_v2(
                v_cerrados_factores,
                v_cerrados_saldos,
                v_cerrados_fracc,
                v_residuo,
                1
            );
        END IF;

        IF v_exacta IS NOT NULL THEN
            FOR v_i IN 1 .. array_length(v_exacta, 1) LOOP
                IF v_exacta[v_i] > 0 THEN
                    v_entrega[v_i] := v_entrega[v_i] + v_exacta[v_i];
                    v_origen[v_i] := 'empaque_cerrado';
                    v_entrega_origen := v_entrega_origen || jsonb_build_object(
                        format('%s:empaque_cerrado', v_i), v_exacta[v_i]
                    );
                    v_saldos[v_i] := v_saldos[v_i] - v_exacta[v_i];
                    v_residuo := v_residuo
                                 - v_exacta[v_i] * v_factores[v_i];
                END IF;
            END LOOP;
        END IF;

        IF v_residuo > 0 AND v_t > 1 THEN
            FOR v_i IN 1 .. (v_t - 1) LOOP
                v_cantidad_abierta := LEAST(
                    floor(v_saldos[v_i]),
                    floor(v_residuo / v_factores[v_i])
                );
                IF v_cantidad_abierta > 0 THEN
                    v_entrega[v_i] := v_entrega[v_i] + v_cantidad_abierta;
                    v_origen[v_i] := 'empaque_cerrado';
                    v_entrega_origen := v_entrega_origen || jsonb_build_object(
                        format('%s:empaque_cerrado', v_i),
                        COALESCE((v_entrega_origen->>format('%s:empaque_cerrado', v_i))::numeric, 0)
                        + v_cantidad_abierta
                    );
                    v_saldos[v_i] := v_saldos[v_i] - v_cantidad_abierta;
                    v_residuo := v_residuo
                                 - v_cantidad_abierta * v_factores[v_i];
                END IF;
            END LOOP;
        END IF;

        IF v_residuo > 0 AND v_t > 1 THEN
            FOR v_i IN REVERSE (v_t - 1) .. 1 LOOP
                IF v_saldos[v_i] >= 1 AND v_factores[v_i] >= v_residuo THEN
                    v_outputs_ids := '{}';
                    v_outputs_factores := '{}';
                    v_outputs_fracc := '{}';
                    FOR v_k IN (v_i + 1) .. v_n LOOP
                        v_outputs_ids := array_append(v_outputs_ids, v_ids[v_k]);
                        v_outputs_factores := array_append(v_outputs_factores, v_factores[v_k]);
                        v_outputs_fracc := array_append(v_outputs_fracc, v_fraccionables[v_k]);
                    END LOOP;
                    v_descomposicion := public.fn_descomponer_equivalente_presentacion_v2(
                        v_outputs_factores,
                        v_outputs_fracc,
                        v_factores[v_i],
                        1
                    );
                    IF v_descomposicion IS NOT NULL THEN
                        v_abierto := v_i;
                        EXIT;
                    END IF;
                END IF;
            END LOOP;

            IF v_abierto IS NOT NULL THEN
                v_id_abierto := v_ids[v_abierto];
                v_nombre_abierto := v_nombres[v_abierto];
                v_factor_abierto := v_factores[v_abierto];
                v_saldos[v_abierto] := v_saldos[v_abierto] - 1;

                v_outputs_ids := '{}';
                v_outputs_factores := '{}';
                v_outputs_fracc := '{}';
                FOR v_j IN (v_abierto + 1) .. v_n LOOP
                    v_outputs_ids := array_append(v_outputs_ids, v_ids[v_j]);
                    v_outputs_factores := array_append(v_outputs_factores, v_factores[v_j]);
                    v_outputs_fracc := array_append(v_outputs_fracc, v_fraccionables[v_j]);
                END LOOP;

                v_descomposicion := public.fn_descomponer_equivalente_presentacion_v2(
                    v_outputs_factores,
                    v_outputs_fracc,
                    v_factor_abierto,
                    1
                );
                IF v_descomposicion IS NULL THEN
                    RETURN jsonb_build_object(
                        'status', 'error',
                        'error_code', 'CATALOGO_PRESENTACIONES_INVALIDO',
                        'message', format(
                            'No se puede abrir %s sin producir fracciones físicas inválidas',
                            v_nombre_abierto
                        )
                    );
                END IF;

                v_patas := jsonb_build_array(jsonb_build_object(
                    'tipo', 'salida',
                    'id_presentacion', v_id_abierto,
                    'cantidad', 1,
                    'factor_entero', v_factor_abierto,
                    'equivalente', v_factor_abierto
                ));
                FOR v_j IN 1 .. array_length(v_descomposicion, 1) LOOP
                    IF v_descomposicion[v_j] > 0 THEN
                        v_saldos[v_abierto + v_j]
                            := v_saldos[v_abierto + v_j] + v_descomposicion[v_j];
                        v_patas := v_patas || jsonb_build_object(
                            'tipo', 'entrada',
                            'id_presentacion', v_outputs_ids[v_j],
                            'cantidad', v_descomposicion[v_j],
                            'factor_entero', v_outputs_factores[v_j],
                            'equivalente', v_descomposicion[v_j]
                                           * v_outputs_factores[v_j]
                        );
                    END IF;
                END LOOP;

                v_conversiones := v_conversiones || jsonb_build_object(
                    'tipo', 'apertura',
                    'id_presentacion_origen', v_id_abierto,
                    'cantidad_origen', 1,
                    'patas', v_patas
                );

                FOR v_j IN (v_abierto + 1) .. v_n LOOP
                    v_cantidad_abierta := LEAST(
                        v_saldos[v_j],
                        v_residuo / v_factores[v_j]
                    );
                    IF NOT v_fraccionables[v_j] THEN
                        v_cantidad_abierta := floor(v_cantidad_abierta);
                    END IF;
                    IF v_cantidad_abierta > 0 THEN
                        v_entrega[v_j] := v_entrega[v_j] + v_cantidad_abierta;
                        v_origen[v_j] := 'apertura';
                        v_entrega_origen := v_entrega_origen || jsonb_build_object(
                            format('%s:apertura', v_j),
                            COALESCE((v_entrega_origen->>format('%s:apertura', v_j))::numeric, 0)
                            + v_cantidad_abierta
                        );
                        v_saldos[v_j] := v_saldos[v_j] - v_cantidad_abierta;
                        v_residuo := v_residuo
                                     - v_cantidad_abierta * v_factores[v_j];
                    END IF;
                    EXIT WHEN v_residuo = 0;
                END LOOP;
            END IF;
        END IF;

        IF v_residuo > 0 THEN
            v_outputs_ids := '{}';
            v_outputs_factores := '{}';
            v_outputs_fracc := '{}';
            v_outputs_saldos := '{}';
            IF v_t < v_n THEN
                FOR v_i IN (v_t + 1) .. v_n LOOP
                    v_outputs_ids := array_append(v_outputs_ids, v_ids[v_i]);
                    v_outputs_factores := array_append(v_outputs_factores, v_factores[v_i]);
                    v_outputs_fracc := array_append(v_outputs_fracc, v_fraccionables[v_i]);
                    v_outputs_saldos := array_append(v_outputs_saldos, v_saldos[v_i]);
                END LOOP;
            END IF;

            IF array_length(v_outputs_ids, 1) IS NOT NULL THEN
                v_descomposicion := public.fn_combinar_factores_presentacion_v2(
                    v_outputs_factores,
                    v_outputs_saldos,
                    v_outputs_fracc,
                    v_residuo,
                    1
                );
            ELSE
                v_descomposicion := NULL;
            END IF;

            IF v_descomposicion IS NULL THEN
                RETURN jsonb_build_object(
                    'status', 'error',
                    'error_code', 'INSUFFICIENT_STOCK_FRAGMENTED',
                    'message', 'El equivalente existe, pero no forma cantidades físicas exactas'
                );
            END IF;

            v_patas := '[]'::jsonb;
            FOR v_j IN 1 .. array_length(v_descomposicion, 1) LOOP
                IF v_descomposicion[v_j] > 0 THEN
                    v_saldos[v_t + v_j]
                        := v_saldos[v_t + v_j] - v_descomposicion[v_j];
                    v_patas := v_patas || jsonb_build_object(
                        'tipo', 'salida',
                        'id_presentacion', v_outputs_ids[v_j],
                        'cantidad', v_descomposicion[v_j],
                        'factor_entero', v_outputs_factores[v_j],
                        'equivalente', v_descomposicion[v_j]
                                       * v_outputs_factores[v_j]
                    );
                END IF;
            END LOOP;

            v_entrega[v_t] := v_entrega[v_t] + v_residuo / v_factor_solicitado;
            v_origen[v_t] := 'empaquetado';
            v_entrega_origen := v_entrega_origen || jsonb_build_object(
                format('%s:empaquetado', v_t),
                COALESCE((v_entrega_origen->>format('%s:empaquetado', v_t))::numeric, 0)
                + v_residuo / v_factor_solicitado
            );
            v_patas := v_patas || jsonb_build_object(
                'tipo', 'entrada',
                'id_presentacion', v_ids[v_t],
                'cantidad', v_residuo / v_factor_solicitado,
                'factor_entero', v_factor_solicitado,
                'equivalente', v_residuo
            );
            v_conversiones := v_conversiones || jsonb_build_object(
                'tipo', 'empaquetado',
                'id_presentacion_destino', v_ids[v_t],
                'cantidad_destino', v_residuo / v_factor_solicitado,
                'patas', v_patas
            );
            v_residuo := 0;
        END IF;
    END IF;
    FOR v_i IN 1 .. v_n LOOP
        FOR r IN
            SELECT split_part(e.key, ':', 2) AS origen,
                   e.value::numeric AS cantidad
              FROM jsonb_each_text(v_entrega_origen) AS e
             WHERE split_part(e.key, ':', 1)::integer = v_i
               AND e.value::numeric > 0
             ORDER BY e.key
        LOOP
            v_equiv_cumplido := v_equiv_cumplido
                                + r.cantidad * v_factores[v_i];
            v_lineas := v_lineas || jsonb_build_object(
                'id_presentacion', v_ids[v_i],
                'nombre', v_nombres[v_i],
                'cantidad', r.cantidad,
                'factor_entero', v_factores[v_i],
                'equivalente', r.cantidad * v_factores[v_i],
                'origen', r.origen
            );
        END LOOP;

        IF v_saldos[v_i] < 0 THEN
            RETURN jsonb_build_object(
                'status', 'error', 'error_code', 'PLAN_INCONSISTENT',
                'message', format('El saldo proyectado de %s quedó negativo',
                                  v_nombres[v_i])
            );
        END IF;

        v_saldos_json := v_saldos_json || jsonb_build_object(
            'id_presentacion', v_ids[v_i],
            'nombre', v_nombres[v_i],
            'cantidad', v_saldos[v_i],
            'factor_entero', v_factores[v_i],
            'equivalente', v_saldos[v_i] * v_factores[v_i]
        );
    END LOOP;

    IF v_equiv_cumplido <> v_equiv_solicitado THEN
        RETURN jsonb_build_object(
            'status', 'error', 'error_code', 'PLAN_INCONSISTENT',
            'message', 'El cumplimiento físico no conserva el equivalente solicitado',
            'equivalente_solicitado', v_equiv_solicitado,
            'equivalente_cumplido', v_equiv_cumplido
        );
    END IF;

    v_residuo := 0;
    FOR v_i IN 1 .. v_n LOOP
        v_residuo := v_residuo
                     + (v_saldos_iniciales[v_i] - v_saldos[v_i]) * v_factores[v_i];
    END LOOP;
    IF v_residuo <> v_equiv_solicitado THEN
        RETURN jsonb_build_object(
            'status', 'error', 'error_code', 'PLAN_INCONSISTENT',
            'message', 'Los saldos proyectados no conservan el equivalente',
            'equivalente_solicitado', v_equiv_solicitado,
            'variacion_saldos', v_residuo
        );
    END IF;

    RETURN jsonb_build_object(
        'status', 'success',
        'id_producto', p_id_producto,
        'id_ubicacion', p_id_ubicacion,
        'id_variante', p_id_variante,
        'id_opcion_variante', p_id_opcion_variante,
        'id_presentacion_solicitada', v_id_presentacion,
        'cantidad_solicitada', p_cantidad,
        'equivalente_solicitado', v_equiv_solicitado,
        'equivalente_cumplido', v_equiv_cumplido,
        'estrategia', v_estrategia,
        'lineas_fisicas', v_lineas,
        'conversiones', v_conversiones,
        'saldos_proyectados', v_saldos_json,
        'mensaje_usuario', format(
            'Solicitud de %s %s cubierta con %s línea(s) físicas',
            p_cantidad, v_nombres[v_t], jsonb_array_length(v_lineas)
        )
    );
EXCEPTION
    WHEN SQLSTATE '22023' THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'error_code', 'CATALOGO_PRESENTACIONES_INVALIDO',
            'message', SQLERRM
        );
END;
$function$;

COMMENT ON FUNCTION public.fn_planificar_cumplimiento_presentaciones_v2(
    bigint, bigint, bigint, numeric, bigint, bigint
) IS
    'Planificador puro de cumplimiento físico exacto. Prefiere combinaciones '
    'cerradas, evita fracciones no físicas y describe conversiones N→N sin escribir.';

REVOKE ALL ON FUNCTION public.fn_planificar_cumplimiento_presentaciones_v2(
    bigint, bigint, bigint, numeric, bigint, bigint
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_planificar_cumplimiento_presentaciones_v2(
    bigint, bigint, bigint, numeric, bigint, bigint
) TO service_role;
