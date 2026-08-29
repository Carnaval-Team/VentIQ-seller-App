-- ============================================================================
-- 03 · Fase 0 · Rebalanceo (abrir / empaquetar) y descuento con rebalanceo
-- ============================================================================
-- Plan: docs/PLAN_PRESENTACIONES_INVENTARIO.md  (Fase 0.1, parte de escritura)
-- Proyecto Supabase: vsieeihstajlrdvpuooh
-- Aplicar en: SQL Editor del dashboard. Idempotente (CREATE OR REPLACE).
-- Depende de: 01_schema_conversion.sql y 02_helpers_lectura_mixta.sql
--
-- Este archivo NO modifica ninguna funcion existente. Solo agrega:
--
--   fn_rebalancear_presentaciones      abre o empaqueta en cadena hasta cubrir
--   fn_descontar_con_rebalanceo        rebalancea + descuenta (una ubicacion)
--   fn_descontar_con_rebalanceo_almacen  igual pero recorre las ubicaciones
--   fn_ingresar_presentacion           entrada en la presentacion tal cual
--
-- ORDEN OBLIGATORIO: aplicar el 04 (guard del trigger de Carnaval) ANTES de
-- llamar a estas funciones sobre un producto sincronizado con carnavalapp.
-- El motivo esta explicado en el 04.
--
--
-- ALGORITMO (dos pasadas, sin recursion)
-- --------------------------------------
-- La cadena viene de fn_presentaciones_producto: nivel 1 = la mas grande.
-- s[i] = saldo vigente en el nivel i, en esa ubicacion.
-- f[i] = cuantas unidades del nivel i+1 salen de UNA del nivel i (factor_hijo).
-- t    = nivel de la presentacion pedida, q = cantidad pedida.
--
-- ABRIR (subir): falta = max(0, q - s[t]).
--   Pasada 1 (planificar, de t-1 hacia 1):
--       abrir[i] = ceil(req[i+1] / f[i])          unidades del nivel i a abrir
--       req[i]   = max(0, abrir[i] - s[i])        cuantas hacen falta DE ARRIBA
--       si req[i] = 0 -> ese nivel se auto-abastece, ahi termina la cadena
--   Si se llega al nivel 1 con req[1] > 0 -> abrir no alcanza.
--   Pasada 2 (ejecutar, del nivel mas alto hacia t): abrir abrir[i] unidades.
--   Se demuestra que en cada paso el saldo alcanza porque
--   abrir[i-1] * f[i-1] >= req[i].
--
-- EMPAQUETAR (bajar): simetrico.
--       consumo[j+1] = falta[j] * f[j]
--       falta[j+1]   = max(0, consumo[j+1] - s[j+1])
--   Se ejecuta del nivel mas profundo hacia t.
--
-- Se intenta ABRIR primero y solo si no alcanza se intenta EMPAQUETAR. Abrir es
-- la operacion normal de un almacen (romper un bulto); empaquetar es el caso
-- raro de "me piden una caja y solo tengo sueltas".
--
-- NO SE SALTAN NIVELES: abrir un Cajon produce Cajas, nunca Unidades. Para
-- llegar de Cajon a Unidad se abren dos escalones, con DOS conversiones
-- registradas. Es lo que pide el plan y es lo que pasa fisicamente.
--
-- Todo pasa en UNA transaccion: si el rebalanceo no alcanza, no queda ninguna
-- conversion a medias.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 3.1 fn_registrar_conversion_presentacion
-- Escribe UNA conversion: la cabecera + las DOS patas del ledger.
-- Es de bajo nivel; el rebalanceo la llama en bucle. No valida saldo: eso lo
-- hace quien planifica.
--
-- Devuelve el id de la conversion.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_registrar_conversion_presentacion(
    p_id_producto             bigint,
    p_id_ubicacion            bigint,
    p_id_presentacion_origen  bigint,
    p_id_presentacion_destino bigint,
    p_cantidad_origen         numeric,
    p_cantidad_destino        numeric,
    p_tipo                    text,
    p_saldo_origen_antes      numeric,
    p_saldo_destino_antes     numeric,
    p_id_variante             bigint DEFAULT NULL,
    p_id_opcion_variante      bigint DEFAULT NULL,
    p_id_operacion            bigint DEFAULT NULL,
    p_uuid                    uuid   DEFAULT NULL,
    p_motivo                  text   DEFAULT NULL,
    p_sku_producto            varchar DEFAULT NULL,
    p_sku_ubicacion           varchar DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_conversion bigint;
BEGIN
    INSERT INTO public.app_dat_conversion_presentacion (
        id_operacion, id_producto, id_variante, id_opcion_variante,
        id_ubicacion, id_presentacion_origen, id_presentacion_destino,
        cantidad_origen, cantidad_destino, tipo, motivo, uuid, created_at
    ) VALUES (
        p_id_operacion, p_id_producto, p_id_variante, p_id_opcion_variante,
        p_id_ubicacion, p_id_presentacion_origen, p_id_presentacion_destino,
        p_cantidad_origen, p_cantidad_destino, p_tipo, p_motivo, p_uuid, NOW()
    ) RETURNING id INTO v_id_conversion;

    -- Pata de SALIDA: se consume la presentacion origen.
    INSERT INTO public.app_dat_inventario_productos (
        id_producto, id_variante, id_opcion_variante, id_ubicacion,
        id_presentacion, cantidad_inicial, cantidad_final,
        sku_producto, sku_ubicacion, origen_cambio, id_conversion, created_at
    ) VALUES (
        p_id_producto, p_id_variante, p_id_opcion_variante, p_id_ubicacion,
        p_id_presentacion_origen,
        p_saldo_origen_antes,
        p_saldo_origen_antes - p_cantidad_origen,
        p_sku_producto, p_sku_ubicacion, 20, v_id_conversion, NOW()
    );

    -- Pata de ENTRADA: aparece la presentacion destino.
    INSERT INTO public.app_dat_inventario_productos (
        id_producto, id_variante, id_opcion_variante, id_ubicacion,
        id_presentacion, cantidad_inicial, cantidad_final,
        sku_producto, sku_ubicacion, origen_cambio, id_conversion, created_at
    ) VALUES (
        p_id_producto, p_id_variante, p_id_opcion_variante, p_id_ubicacion,
        p_id_presentacion_destino,
        p_saldo_destino_antes,
        p_saldo_destino_antes + p_cantidad_destino,
        p_sku_producto, p_sku_ubicacion, 20, v_id_conversion, NOW()
    );

    RETURN v_id_conversion;
END;
$$;

COMMENT ON FUNCTION public.fn_registrar_conversion_presentacion(
    bigint, bigint, bigint, bigint, numeric, numeric, text, numeric, numeric,
    bigint, bigint, bigint, uuid, text, varchar, varchar) IS
    'Escribe una conversion de presentacion: cabecera en '
    'app_dat_conversion_presentacion + las dos patas en el ledger con '
    'origen_cambio = 20. No valida saldo; lo hace fn_rebalancear_presentaciones.';

GRANT EXECUTE ON FUNCTION public.fn_registrar_conversion_presentacion(
    bigint, bigint, bigint, bigint, numeric, numeric, text, numeric, numeric,
    bigint, bigint, bigint, uuid, text, varchar, varchar)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 3.2 fn_rebalancear_presentaciones
-- Deja al menos p_cantidad disponible en p_id_presentacion, abriendo o
-- empaquetando en cadena dentro de UNA ubicacion.
--
-- No descuenta nada: solo mueve stock entre presentaciones. El descuento lo
-- hace fn_descontar_con_rebalanceo.
--
-- Devuelve jsonb:
--   status            'success' | 'error'
--   saldo_antes       saldo de la presentacion pedida antes de rebalancear
--   saldo_despues     saldo tras las conversiones
--   conversiones      [] o lista de conversiones hechas (para el kardex)
--   estrategia        'ninguna' | 'abrir' | 'empaquetar'
-- En error: error_code = 'INSUFFICIENT_STOCK_CONVERTIBLE' + el equivalente base
-- disponible, para que el cliente pueda decir cuanto SI se puede.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_rebalancear_presentaciones(
    p_id_producto        bigint,
    p_id_ubicacion       bigint,
    p_id_presentacion    bigint,
    p_cantidad           numeric,
    p_id_variante        bigint DEFAULT NULL,
    p_id_opcion_variante bigint DEFAULT NULL,
    p_id_operacion       bigint DEFAULT NULL,
    p_uuid               uuid   DEFAULT NULL,
    p_motivo             text   DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_n              integer;          -- cantidad de niveles de la cadena
    v_t              integer;          -- nivel de la presentacion pedida
    v_ids            bigint[]  := '{}';   -- id_presentacion por nivel
    v_nombres        text[]    := '{}';
    v_factor_rel     numeric[] := '{}';
    v_fhijo          numeric[] := '{}';   -- hijos por unidad del nivel (NULL en el ultimo)
    v_s              numeric[] := '{}';   -- saldo de trabajo por nivel
    v_abrir          numeric[] := '{}';
    v_req            numeric[] := '{}';
    v_falta          numeric[] := '{}';
    v_consumo        numeric[] := '{}';
    v_i              integer;
    v_j              integer;
    v_nivel_top      integer;
    v_nivel_deep     integer;
    v_pendiente      numeric;
    v_viable         boolean;
    v_conversiones   jsonb := '[]'::jsonb;
    v_id_conv        bigint;
    v_prod_hijos     numeric;
    v_consumo_hijos  numeric;
    v_sku_producto   varchar;
    v_sku_ubicacion  varchar;
    v_equiv          numeric;
    v_estrategia     text := 'ninguna';
    v_saldo_antes    numeric;
    r                RECORD;
BEGIN
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La cantidad a rebalancear debe ser mayor que cero',
            'error_code', 'INVALID_QUANTITY'
        );
    END IF;

    IF p_id_ubicacion IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El rebalanceo necesita una ubicacion concreta',
            'error_code', 'MISSING_LOCATION'
        );
    END IF;

    -- Valida el contrato de IDs (lanza excepcion con mensaje explicito).
    PERFORM public.fn_validar_id_presentacion(p_id_producto, p_id_presentacion);

    -- ── Cargar la cadena de presentaciones a arrays indexados por nivel ─────
    FOR r IN
        SELECT c.nivel, c.id_presentacion, c.nombre, c.factor_rel, c.factor_hijo
          FROM public.fn_presentaciones_producto(p_id_producto) c
         ORDER BY c.nivel
    LOOP
        v_ids[r.nivel]        := r.id_presentacion;
        v_nombres[r.nivel]    := r.nombre;
        v_factor_rel[r.nivel] := r.factor_rel;
        v_fhijo[r.nivel]      := r.factor_hijo;
        v_s[r.nivel]          := 0;
        IF r.id_presentacion = p_id_presentacion THEN
            v_t := r.nivel;
        END IF;
    END LOOP;

    v_n := COALESCE(array_length(v_ids, 1), 0);

    IF v_n = 0 OR v_t IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', format('El producto %s no tiene la presentacion %s en su cadena',
                              p_id_producto, p_id_presentacion),
            'error_code', 'PRESENTATION_NOT_IN_CHAIN'
        );
    END IF;

    -- ── Cargar saldos vigentes de ESA ubicacion (incluyendo ceros) ──────────
    FOR r IN
        SELECT s.id_presentacion, SUM(s.saldo) AS saldo,
               MIN(s.sku_producto) AS sku_producto, MIN(s.sku_ubicacion) AS sku_ubicacion
          FROM public.fn_stock_saldos_presentacion(
                   p_id_producto, NULL, p_id_ubicacion, true) s
         WHERE (p_id_variante        IS NULL OR s.id_variante        IS NOT DISTINCT FROM p_id_variante)
           AND (p_id_opcion_variante IS NULL OR s.id_opcion_variante IS NOT DISTINCT FROM p_id_opcion_variante)
         GROUP BY s.id_presentacion
    LOOP
        FOR v_i IN 1 .. v_n LOOP
            IF v_ids[v_i] = r.id_presentacion THEN
                v_s[v_i] := COALESCE(r.saldo, 0);
                v_sku_producto  := COALESCE(v_sku_producto,  r.sku_producto);
                v_sku_ubicacion := COALESCE(v_sku_ubicacion, r.sku_ubicacion);
            END IF;
        END LOOP;
    END LOOP;

    -- ── Ya alcanza: no se toca nada ────────────────────────────────────────
    v_saldo_antes := v_s[v_t];

    IF v_s[v_t] >= p_cantidad THEN
        RETURN jsonb_build_object(
            'status',        'success',
            'estrategia',    'ninguna',
            'saldo_antes',   v_s[v_t],
            'saldo_despues', v_s[v_t],
            'conversiones',  '[]'::jsonb
        );
    END IF;

    -- ========================================================================
    -- INTENTO 1 · ABRIR (consumir presentaciones mas grandes)
    -- ========================================================================
    v_viable := false;

    IF v_t > 1 THEN
        v_req   := '{}';
        v_abrir := '{}';
        v_req[v_t] := p_cantidad - v_s[v_t];     -- > 0 por el IF de arriba

        v_nivel_top := NULL;
        FOR v_i IN REVERSE (v_t - 1) .. 1 LOOP
            IF COALESCE(v_fhijo[v_i], 0) <= 0 THEN
                EXIT;                             -- cadena rota, no se puede subir
            END IF;
            v_abrir[v_i] := CEIL(v_req[v_i + 1] / v_fhijo[v_i]);
            v_req[v_i]   := GREATEST(0, v_abrir[v_i] - v_s[v_i]);
            IF v_req[v_i] = 0 THEN
                v_nivel_top := v_i;               -- este nivel se auto-abastece
                EXIT;
            END IF;
        END LOOP;

        IF v_nivel_top IS NOT NULL THEN
            v_viable     := true;
            v_estrategia := 'abrir';

            -- Ejecutar de arriba hacia abajo. En cada paso el saldo alcanza:
            -- abrir[i-1] * fhijo[i-1] >= req[i] por construccion del CEIL.
            FOR v_i IN v_nivel_top .. (v_t - 1) LOOP
                v_prod_hijos := v_abrir[v_i] * v_fhijo[v_i];

                v_id_conv := public.fn_registrar_conversion_presentacion(
                    p_id_producto             := p_id_producto,
                    p_id_ubicacion            := p_id_ubicacion,
                    p_id_presentacion_origen  := v_ids[v_i],
                    p_id_presentacion_destino := v_ids[v_i + 1],
                    p_cantidad_origen         := v_abrir[v_i],
                    p_cantidad_destino        := v_prod_hijos,
                    p_tipo                    := 'abrir',
                    p_saldo_origen_antes      := v_s[v_i],
                    p_saldo_destino_antes     := v_s[v_i + 1],
                    p_id_variante             := p_id_variante,
                    p_id_opcion_variante      := p_id_opcion_variante,
                    p_id_operacion            := p_id_operacion,
                    p_uuid                    := p_uuid,
                    p_motivo                  := p_motivo,
                    p_sku_producto            := v_sku_producto,
                    p_sku_ubicacion           := v_sku_ubicacion
                );

                v_s[v_i]     := v_s[v_i]     - v_abrir[v_i];
                v_s[v_i + 1] := v_s[v_i + 1] + v_prod_hijos;

                v_conversiones := v_conversiones || jsonb_build_object(
                    'id_conversion',    v_id_conv,
                    'tipo',             'abrir',
                    'origen_nombre',    v_nombres[v_i],
                    'destino_nombre',   v_nombres[v_i + 1],
                    'cantidad_origen',  v_abrir[v_i],
                    'cantidad_destino', v_prod_hijos
                );
            END LOOP;
        END IF;
    END IF;

    -- ========================================================================
    -- INTENTO 2 · EMPAQUETAR (armar desde presentaciones mas chicas)
    -- ========================================================================
    IF NOT v_viable AND v_t < v_n THEN
        v_falta   := '{}';
        v_consumo := '{}';
        v_falta[v_t] := p_cantidad - v_s[v_t];

        v_nivel_deep := NULL;
        FOR v_j IN v_t .. (v_n - 1) LOOP
            IF COALESCE(v_fhijo[v_j], 0) <= 0 THEN
                EXIT;
            END IF;
            v_consumo[v_j + 1] := v_falta[v_j] * v_fhijo[v_j];
            v_falta[v_j + 1]   := GREATEST(0, v_consumo[v_j + 1] - v_s[v_j + 1]);
            IF v_falta[v_j + 1] = 0 THEN
                v_nivel_deep := v_j + 1;          -- este nivel cubre el consumo
                EXIT;
            END IF;
        END LOOP;

        IF v_nivel_deep IS NOT NULL THEN
            v_viable     := true;
            v_estrategia := 'empaquetar';

            -- Ejecutar de abajo hacia arriba.
            FOR v_j IN REVERSE (v_nivel_deep - 1) .. v_t LOOP
                v_consumo_hijos := v_falta[v_j] * v_fhijo[v_j];

                v_id_conv := public.fn_registrar_conversion_presentacion(
                    p_id_producto             := p_id_producto,
                    p_id_ubicacion            := p_id_ubicacion,
                    p_id_presentacion_origen  := v_ids[v_j + 1],
                    p_id_presentacion_destino := v_ids[v_j],
                    p_cantidad_origen         := v_consumo_hijos,
                    p_cantidad_destino        := v_falta[v_j],
                    p_tipo                    := 'empaquetar',
                    p_saldo_origen_antes      := v_s[v_j + 1],
                    p_saldo_destino_antes     := v_s[v_j],
                    p_id_variante             := p_id_variante,
                    p_id_opcion_variante      := p_id_opcion_variante,
                    p_id_operacion            := p_id_operacion,
                    p_uuid                    := p_uuid,
                    p_motivo                  := p_motivo,
                    p_sku_producto            := v_sku_producto,
                    p_sku_ubicacion           := v_sku_ubicacion
                );

                v_s[v_j + 1] := v_s[v_j + 1] - v_consumo_hijos;
                v_s[v_j]     := v_s[v_j]     + v_falta[v_j];

                v_conversiones := v_conversiones || jsonb_build_object(
                    'id_conversion',    v_id_conv,
                    'tipo',             'empaquetar',
                    'origen_nombre',    v_nombres[v_j + 1],
                    'destino_nombre',   v_nombres[v_j],
                    'cantidad_origen',  v_consumo_hijos,
                    'cantidad_destino', v_falta[v_j]
                );
            END LOOP;
        END IF;
    END IF;

    -- ========================================================================
    -- No alcanza ni abriendo ni empaquetando
    -- ========================================================================
    IF NOT v_viable THEN
        v_equiv := 0;
        FOR v_i IN 1 .. v_n LOOP
            v_equiv := v_equiv + (v_s[v_i] * COALESCE(v_factor_rel[v_i], 1));
        END LOOP;

        RETURN jsonb_build_object(
            'status',              'error',
            'message',             format(
                'Stock insuficiente de %s: se piden %s y el convertible alcanza para %s',
                v_nombres[v_t], p_cantidad,
                TRUNC(v_equiv / NULLIF(v_factor_rel[v_t], 0), 3)),
            'error_code',          'INSUFFICIENT_STOCK_CONVERTIBLE',
            'id_producto',         p_id_producto,
            'id_ubicacion',        p_id_ubicacion,
            'id_presentacion',     p_id_presentacion,
            'cantidad_solicitada', p_cantidad,
            'saldo_propio',        v_s[v_t],
            'equivalente_base',    v_equiv,
            'maximo_convertible',  TRUNC(v_equiv / NULLIF(v_factor_rel[v_t], 0), 3)
        );
    END IF;

    RETURN jsonb_build_object(
        'status',        'success',
        'estrategia',    v_estrategia,
        'saldo_antes',   v_saldo_antes,
        'saldo_despues', v_s[v_t],
        'conversiones',  v_conversiones
    );
END;
$$;

COMMENT ON FUNCTION public.fn_rebalancear_presentaciones(
    bigint, bigint, bigint, numeric, bigint, bigint, bigint, uuid, text) IS
    'Abre o empaqueta en cadena hasta dejar p_cantidad disponible en '
    'p_id_presentacion dentro de una ubicacion. No descuenta. Intenta abrir '
    '(desde presentaciones mayores) y solo si no alcanza empaqueta (desde menores).';

GRANT EXECUTE ON FUNCTION public.fn_rebalancear_presentaciones(
    bigint, bigint, bigint, numeric, bigint, bigint, bigint, uuid, text)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 3.3 fn_descontar_con_rebalanceo
-- Rebalancea si hace falta y DESCUENTA p_cantidad de p_id_presentacion en UNA
-- ubicacion. Es la funcion que deben llamar venta, extraccion, transferencia
-- (pata de salida), BOM y ajuste parcial.
--
-- PROHIBIDO el patron viejo "ultimo movimiento del producto sin filtrar
-- presentacion": esta funcion filtra ubicacion Y presentacion, que es
-- exactamente el bug que arreglo el archivo 03 de funcionalidad_cocina para
-- almacen y que aqui se cierra tambien para presentacion.
--
-- p_origen_cambio: el codigo que corresponde al motivo real del egreso
--   2 = extraccion, 3 = venta, 4 = consumo por elaborado, 7 = transferencia
-- (son los valores que ya usa produccion; ver 21_tandas_produccion.sql).
--
-- p_id_extraccion se pasa cuando el egreso ya creo su fila en
-- app_dat_extraccion_productos, para que el kardex y el IPV lo enlacen igual
-- que hoy.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_descontar_con_rebalanceo(
    p_id_producto        bigint,
    p_id_ubicacion       bigint,
    p_id_presentacion    bigint,
    p_cantidad           numeric,
    p_origen_cambio      integer DEFAULT 2,
    p_id_extraccion      bigint  DEFAULT NULL,
    p_id_variante        bigint  DEFAULT NULL,
    p_id_opcion_variante bigint  DEFAULT NULL,
    p_id_operacion       bigint  DEFAULT NULL,
    p_uuid               uuid    DEFAULT NULL,
    p_motivo             text    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_rebal        jsonb;
    v_saldo        numeric;
    v_sku_producto  varchar;
    v_sku_ubicacion varchar;
BEGIN
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La cantidad a descontar debe ser mayor que cero',
            'error_code', 'INVALID_QUANTITY'
        );
    END IF;

    -- 1. Asegurar saldo en la presentacion pedida (puede abrir o empaquetar).
    v_rebal := public.fn_rebalancear_presentaciones(
        p_id_producto        := p_id_producto,
        p_id_ubicacion       := p_id_ubicacion,
        p_id_presentacion    := p_id_presentacion,
        p_cantidad           := p_cantidad,
        p_id_variante        := p_id_variante,
        p_id_opcion_variante := p_id_opcion_variante,
        p_id_operacion       := p_id_operacion,
        p_uuid               := p_uuid,
        p_motivo             := COALESCE(p_motivo, 'egreso')
    );

    IF (v_rebal->>'status') <> 'success' THEN
        RETURN v_rebal;   -- el caller aborta la transaccion sin descuento parcial
    END IF;

    -- 2. Releer el saldo DESPUES del rebalanceo. No se confia en el jsonb:
    --    el ledger es la fuente de verdad.
    SELECT COALESCE(SUM(s.saldo), 0),
           MIN(s.sku_producto), MIN(s.sku_ubicacion)
      INTO v_saldo, v_sku_producto, v_sku_ubicacion
      FROM public.fn_stock_saldos_presentacion(
               p_id_producto, NULL, p_id_ubicacion, true) s
     WHERE s.id_presentacion = p_id_presentacion
       AND (p_id_variante        IS NULL OR s.id_variante        IS NOT DISTINCT FROM p_id_variante)
       AND (p_id_opcion_variante IS NULL OR s.id_opcion_variante IS NOT DISTINCT FROM p_id_opcion_variante);

    IF v_saldo < p_cantidad THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    format('El rebalanceo no dejo saldo suficiente: hay %s, se piden %s',
                                 v_saldo, p_cantidad),
            'error_code', 'REBALANCE_INCONSISTENT',
            'rebalanceo', v_rebal
        );
    END IF;

    -- 3. Descontar: una fila nueva de snapshot, como hace todo el sistema.
    INSERT INTO public.app_dat_inventario_productos (
        id_producto, id_variante, id_opcion_variante, id_ubicacion,
        id_presentacion, cantidad_inicial, cantidad_final,
        sku_producto, sku_ubicacion, origen_cambio, id_extraccion, created_at
    ) VALUES (
        p_id_producto, p_id_variante, p_id_opcion_variante, p_id_ubicacion,
        p_id_presentacion, v_saldo, v_saldo - p_cantidad,
        v_sku_producto, v_sku_ubicacion, p_origen_cambio, p_id_extraccion, NOW()
    );

    RETURN jsonb_build_object(
        'status',         'success',
        'id_producto',    p_id_producto,
        'id_ubicacion',   p_id_ubicacion,
        'id_presentacion',p_id_presentacion,
        'descontado',     p_cantidad,
        'saldo_previo',   v_saldo,
        'saldo_nuevo',    v_saldo - p_cantidad,
        'estrategia',     v_rebal->>'estrategia',
        'conversiones',   COALESCE(v_rebal->'conversiones', '[]'::jsonb)
    );
END;
$$;

COMMENT ON FUNCTION public.fn_descontar_con_rebalanceo(
    bigint, bigint, bigint, numeric, integer, bigint, bigint, bigint, bigint, uuid, text) IS
    'Descuenta una cantidad en la presentacion pedida, abriendo o empaquetando '
    'antes si el saldo propio no alcanza. Filtra SIEMPRE por ubicacion y '
    'presentacion. Unica ruta de egreso valida para venta/extraccion/transfer/BOM.';

GRANT EXECUTE ON FUNCTION public.fn_descontar_con_rebalanceo(
    bigint, bigint, bigint, numeric, integer, bigint, bigint, bigint, bigint, uuid, text)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 3.4 fn_descontar_con_rebalanceo_almacen
-- Igual que la anterior pero cuando el caller solo sabe el ALMACEN.
--
-- Recorre las ubicaciones del almacen y va descontando. Estrategia:
--   1. Primero las ubicaciones que YA tienen saldo propio en la presentacion
--      pedida, de mayor a menor. Asi el caso normal no abre ninguna caja.
--   2. Solo si todavia falta, las ubicaciones donde hay convertible.
-- Es el mismo espiritu de fn_descontar_ingredientes_elaborado (consumir de
-- mayor a menor) pero respetando presentaciones.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_descontar_con_rebalanceo_almacen(
    p_id_producto        bigint,
    p_id_almacen         bigint,
    p_id_presentacion    bigint,
    p_cantidad           numeric,
    p_origen_cambio      integer DEFAULT 2,
    p_id_extraccion      bigint  DEFAULT NULL,
    p_id_variante        bigint  DEFAULT NULL,
    p_id_opcion_variante bigint  DEFAULT NULL,
    p_id_operacion       bigint  DEFAULT NULL,
    p_uuid               uuid    DEFAULT NULL,
    p_motivo             text    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_pendiente    numeric := p_cantidad;
    v_factor_t     numeric;
    v_equiv_total  numeric := 0;
    v_res          jsonb;
    v_movimientos  jsonb := '[]'::jsonb;
    v_a_descontar  numeric;
    v_disponible   numeric;
    r              RECORD;
BEGIN
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La cantidad a descontar debe ser mayor que cero',
            'error_code', 'INVALID_QUANTITY'
        );
    END IF;

    SELECT c.factor_rel INTO v_factor_t
      FROM public.fn_presentaciones_producto(p_id_producto) c
     WHERE c.id_presentacion = p_id_presentacion;

    IF v_factor_t IS NULL OR v_factor_t <= 0 THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', format('La presentacion %s no pertenece al producto %s',
                              p_id_presentacion, p_id_producto),
            'error_code', 'PRESENTATION_NOT_IN_CHAIN'
        );
    END IF;

    -- Validacion previa GLOBAL del almacen: mismo criterio que usa
    -- fn_validar_ingredientes_elaborado (validar todo antes de tocar nada).
    SELECT COALESCE(SUM(s.equivalente_base), 0) INTO v_equiv_total
      FROM public.fn_stock_saldos_presentacion(p_id_producto, p_id_almacen, NULL, false) s
     WHERE (p_id_variante        IS NULL OR s.id_variante        IS NOT DISTINCT FROM p_id_variante)
       AND (p_id_opcion_variante IS NULL OR s.id_opcion_variante IS NOT DISTINCT FROM p_id_opcion_variante);

    IF v_equiv_total < (p_cantidad * v_factor_t) THEN
        RETURN jsonb_build_object(
            'status',              'error',
            'message',             format(
                'Stock insuficiente en el almacen %s: se piden %s (equivalente %s) y hay %s en unidades base',
                p_id_almacen, p_cantidad, p_cantidad * v_factor_t, v_equiv_total),
            'error_code',          'INSUFFICIENT_STOCK_WAREHOUSE',
            'id_producto',         p_id_producto,
            'id_almacen',          p_id_almacen,
            'cantidad_solicitada', p_cantidad,
            'equivalente_base',    v_equiv_total,
            'maximo_convertible',  TRUNC(v_equiv_total / v_factor_t, 3)
        );
    END IF;

    -- Pasada 1: ubicaciones con saldo propio en la presentacion pedida.
    FOR r IN
        SELECT s.id_ubicacion, SUM(s.saldo) AS saldo
          FROM public.fn_stock_saldos_presentacion(p_id_producto, p_id_almacen, NULL, false) s
         WHERE s.id_presentacion = p_id_presentacion
           AND (p_id_variante        IS NULL OR s.id_variante        IS NOT DISTINCT FROM p_id_variante)
           AND (p_id_opcion_variante IS NULL OR s.id_opcion_variante IS NOT DISTINCT FROM p_id_opcion_variante)
         GROUP BY s.id_ubicacion
        HAVING SUM(s.saldo) > 0
         ORDER BY SUM(s.saldo) DESC, s.id_ubicacion
    LOOP
        EXIT WHEN v_pendiente <= 0;

        v_a_descontar := LEAST(r.saldo, v_pendiente);

        v_res := public.fn_descontar_con_rebalanceo(
            p_id_producto        := p_id_producto,
            p_id_ubicacion       := r.id_ubicacion,
            p_id_presentacion    := p_id_presentacion,
            p_cantidad           := v_a_descontar,
            p_origen_cambio      := p_origen_cambio,
            p_id_extraccion      := p_id_extraccion,
            p_id_variante        := p_id_variante,
            p_id_opcion_variante := p_id_opcion_variante,
            p_id_operacion       := p_id_operacion,
            p_uuid               := p_uuid,
            p_motivo             := p_motivo
        );

        IF (v_res->>'status') <> 'success' THEN
            RETURN v_res;
        END IF;

        v_movimientos := v_movimientos || v_res;
        v_pendiente   := v_pendiente - v_a_descontar;
    END LOOP;

    -- Pasada 2: ubicaciones donde solo hay convertible (hay que abrir o empaquetar).
    IF v_pendiente > 0 THEN
        FOR r IN
            SELECT s.id_ubicacion,
                   TRUNC(SUM(s.equivalente_base) / v_factor_t, 3) AS convertible
              FROM public.fn_stock_saldos_presentacion(p_id_producto, p_id_almacen, NULL, false) s
             WHERE (p_id_variante        IS NULL OR s.id_variante        IS NOT DISTINCT FROM p_id_variante)
               AND (p_id_opcion_variante IS NULL OR s.id_opcion_variante IS NOT DISTINCT FROM p_id_opcion_variante)
             GROUP BY s.id_ubicacion
            HAVING SUM(s.equivalente_base) > 0
             ORDER BY SUM(s.equivalente_base) DESC, s.id_ubicacion
        LOOP
            EXIT WHEN v_pendiente <= 0;

            v_disponible := r.convertible;
            CONTINUE WHEN v_disponible <= 0;

            v_a_descontar := LEAST(v_disponible, v_pendiente);

            v_res := public.fn_descontar_con_rebalanceo(
                p_id_producto        := p_id_producto,
                p_id_ubicacion       := r.id_ubicacion,
                p_id_presentacion    := p_id_presentacion,
                p_cantidad           := v_a_descontar,
                p_origen_cambio      := p_origen_cambio,
                p_id_extraccion      := p_id_extraccion,
                p_id_variante        := p_id_variante,
                p_id_opcion_variante := p_id_opcion_variante,
                p_id_operacion       := p_id_operacion,
                p_uuid               := p_uuid,
                p_motivo             := p_motivo
            );

            -- En esta pasada un fallo puntual de una ubicacion no es fatal:
            -- puede que ahi el convertible no forme una unidad entera de la
            -- presentacion pedida. Se sigue con la siguiente.
            IF (v_res->>'status') = 'success' THEN
                v_movimientos := v_movimientos || v_res;
                v_pendiente   := v_pendiente - v_a_descontar;
            END IF;
        END LOOP;
    END IF;

    IF v_pendiente > 0 THEN
        RETURN jsonb_build_object(
            'status',     'error',
            'message',    format(
                'No se pudo cubrir %s de %s en el almacen %s: el stock esta repartido '
                'en fracciones que no forman una unidad completa de esa presentacion',
                v_pendiente, p_cantidad, p_id_almacen),
            'error_code', 'INSUFFICIENT_STOCK_FRAGMENTED',
            'pendiente',  v_pendiente,
            'movimientos', v_movimientos
        );
    END IF;

    RETURN jsonb_build_object(
        'status',      'success',
        'descontado',  p_cantidad,
        'id_almacen',  p_id_almacen,
        'movimientos', v_movimientos
    );
END;
$$;

COMMENT ON FUNCTION public.fn_descontar_con_rebalanceo_almacen(
    bigint, bigint, bigint, numeric, integer, bigint, bigint, bigint, bigint, uuid, text) IS
    'Descuenta una cantidad de un producto en un almacen, recorriendo sus '
    'ubicaciones: primero las que tienen saldo propio, luego las que solo tienen '
    'convertible. Valida el equivalente base del almacen antes de tocar nada.';

GRANT EXECUTE ON FUNCTION public.fn_descontar_con_rebalanceo_almacen(
    bigint, bigint, bigint, numeric, integer, bigint, bigint, bigint, bigint, uuid, text)
    TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 3.5 fn_ingresar_presentacion
-- Entrada de stock EN LA PRESENTACION TAL CUAL. Sin conversion a base.
--
-- Es el contrapunto de fn_descontar_con_rebalanceo: la usan recepcion,
-- transferencia (pata de entrada), devolucion y produccion. Una llamada por
-- linea: 4 cajas -> una llamada; 4 unidades -> otra llamada. Asi entra
-- "4 cajas y 4 unidades" como dos saldos y no como 52 unidades.
--
-- p_origen_cambio: 1 = entrada de inventario (recepcion / transferencia entrada),
-- 5 = devolucion cliente. Se usan los codigos que ya existen.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_ingresar_presentacion(
    p_id_producto        bigint,
    p_id_ubicacion       bigint,
    p_id_presentacion    bigint,
    p_cantidad           numeric,
    p_origen_cambio      integer DEFAULT 1,
    p_id_recepcion       bigint  DEFAULT NULL,
    p_id_proveedor       bigint  DEFAULT NULL,
    p_id_variante        bigint  DEFAULT NULL,
    p_id_opcion_variante bigint  DEFAULT NULL,
    p_sku_producto       varchar DEFAULT NULL,
    p_sku_ubicacion      varchar DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_saldo numeric;
BEGIN
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'La cantidad a ingresar debe ser mayor que cero',
            'error_code', 'INVALID_QUANTITY'
        );
    END IF;

    PERFORM public.fn_validar_id_presentacion(p_id_producto, p_id_presentacion);

    -- Saldo vigente de ESA presentacion en ESA ubicacion (0 si nunca hubo).
    SELECT COALESCE(SUM(s.saldo), 0) INTO v_saldo
      FROM public.fn_stock_saldos_presentacion(
               p_id_producto, NULL, p_id_ubicacion, true) s
     WHERE s.id_presentacion = p_id_presentacion
       AND (p_id_variante        IS NULL OR s.id_variante        IS NOT DISTINCT FROM p_id_variante)
       AND (p_id_opcion_variante IS NULL OR s.id_opcion_variante IS NOT DISTINCT FROM p_id_opcion_variante);

    INSERT INTO public.app_dat_inventario_productos (
        id_producto, id_variante, id_opcion_variante, id_ubicacion,
        id_presentacion, cantidad_inicial, cantidad_final,
        sku_producto, sku_ubicacion, origen_cambio,
        id_recepcion, id_proveedor, created_at
    ) VALUES (
        p_id_producto, p_id_variante, p_id_opcion_variante, p_id_ubicacion,
        p_id_presentacion, v_saldo, v_saldo + p_cantidad,
        p_sku_producto, p_sku_ubicacion, p_origen_cambio,
        p_id_recepcion, p_id_proveedor, NOW()
    );

    RETURN jsonb_build_object(
        'status',          'success',
        'id_producto',     p_id_producto,
        'id_ubicacion',    p_id_ubicacion,
        'id_presentacion', p_id_presentacion,
        'ingresado',       p_cantidad,
        'saldo_previo',    v_saldo,
        'saldo_nuevo',     v_saldo + p_cantidad
    );
END;
$$;

COMMENT ON FUNCTION public.fn_ingresar_presentacion(
    bigint, bigint, bigint, numeric, integer, bigint, bigint, bigint, bigint, varchar, varchar) IS
    'Ingresa stock en la presentacion indicada SIN convertir a base. Una llamada '
    'por linea de presentacion: asi 4 cajas + 4 unidades quedan como dos saldos.';

GRANT EXECUTE ON FUNCTION public.fn_ingresar_presentacion(
    bigint, bigint, bigint, numeric, integer, bigint, bigint, bigint, bigint, varchar, varchar)
    TO anon, authenticated, service_role;


-- ============================================================================
-- VERIFICACION
-- ============================================================================
-- Los 5 tests del plan estan en 05_tests_fase0.sql, que los corre completos
-- dentro de un BEGIN/ROLLBACK sobre datos reales. Correr ese archivo despues
-- de aplicar este.

