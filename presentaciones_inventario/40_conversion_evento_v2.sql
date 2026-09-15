-- ============================================================================
-- 40 · Registro de conversiones físicas N→N v2
-- ============================================================================
-- Requiere 35. Crea una cabecera por evento y patas físicas inmutables.
-- No mueve inventario: el ejecutor del paso 41 enlazará sus filas del ledger.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.app_dat_conversion_presentacion_evento (
    id                       bigserial PRIMARY KEY,
    id_operacion             bigint NULL
        REFERENCES public.app_dat_operaciones(id) ON DELETE SET NULL,
    id_producto              bigint NOT NULL
        REFERENCES public.app_dat_producto(id),
    id_variante              bigint NULL
        REFERENCES public.app_dat_variantes(id),
    id_opcion_variante       bigint NULL
        REFERENCES public.app_dat_atributo_opcion(id),
    id_ubicacion             bigint NOT NULL
        REFERENCES public.app_dat_layout_almacen(id),
    tipo                     text NOT NULL
        CHECK (tipo IN ('apertura', 'empaquetado')),
    motivo                   text NULL,
    uuid                     uuid NULL,
    created_at               timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.app_dat_conversion_presentacion_pata (
    id                       bigserial PRIMARY KEY,
    id_conversion_evento     bigint NOT NULL
        REFERENCES public.app_dat_conversion_presentacion_evento(id)
        ON DELETE RESTRICT,
    orden                    integer NOT NULL CHECK (orden > 0),
    tipo                     text NOT NULL CHECK (tipo IN ('salida', 'entrada')),
    id_presentacion          bigint NOT NULL
        REFERENCES public.app_dat_producto_presentacion(id),
    cantidad                 numeric NOT NULL CHECK (cantidad > 0),
    factor_entero            numeric NOT NULL CHECK (factor_entero > 0),
    equivalente              numeric NOT NULL CHECK (equivalente > 0),
    created_at               timestamptz NOT NULL DEFAULT now(),
    UNIQUE (id_conversion_evento, orden)
);

ALTER TABLE public.app_dat_inventario_productos
    ADD COLUMN IF NOT EXISTS id_conversion_evento bigint NULL;

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conname = 'app_dat_inventario_productos_conversion_evento_fkey'
           AND conrelid = 'public.app_dat_inventario_productos'::regclass
    ) THEN
        ALTER TABLE public.app_dat_inventario_productos
            ADD CONSTRAINT app_dat_inventario_productos_conversion_evento_fkey
            FOREIGN KEY (id_conversion_evento)
            REFERENCES public.app_dat_conversion_presentacion_evento(id)
            ON DELETE RESTRICT;
    END IF;
END;
$block$;

CREATE INDEX IF NOT EXISTS idx_conversion_evento_producto_ubicacion
    ON public.app_dat_conversion_presentacion_evento
       (id_producto, id_ubicacion, id DESC);
CREATE INDEX IF NOT EXISTS idx_conversion_evento_operacion
    ON public.app_dat_conversion_presentacion_evento (id_operacion)
    WHERE id_operacion IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_conversion_pata_evento
    ON public.app_dat_conversion_presentacion_pata (id_conversion_evento, orden);
CREATE INDEX IF NOT EXISTS idx_conversion_pata_presentacion
    ON public.app_dat_conversion_presentacion_pata (id_presentacion);
CREATE INDEX IF NOT EXISTS idx_inventario_conversion_evento
    ON public.app_dat_inventario_productos (id_conversion_evento)
    WHERE id_conversion_evento IS NOT NULL;

COMMENT ON TABLE public.app_dat_conversion_presentacion_evento IS
    'Cabecera inmutable de una conversión física N→N de presentaciones.';
COMMENT ON TABLE public.app_dat_conversion_presentacion_pata IS
    'Patas de entrada y salida de una conversión v2; conservan factor y equivalente.';
COMMENT ON COLUMN public.app_dat_inventario_productos.id_conversion_evento IS
    'Evento N→N que originó esta pata de ledger; no representa venta ni ajuste.';

ALTER TABLE public.app_dat_conversion_presentacion_evento ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_dat_conversion_presentacion_pata ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.app_dat_conversion_presentacion_evento FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.app_dat_conversion_presentacion_pata FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE public.app_dat_conversion_presentacion_evento_id_seq
    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE public.app_dat_conversion_presentacion_pata_id_seq
    FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON TABLE public.app_dat_conversion_presentacion_evento TO service_role;
GRANT SELECT, INSERT ON TABLE public.app_dat_conversion_presentacion_pata TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.app_dat_conversion_presentacion_evento_id_seq TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.app_dat_conversion_presentacion_pata_id_seq TO service_role;

CREATE OR REPLACE FUNCTION public.fn_registrar_conversion_v2(
    p_id_producto        bigint,
    p_id_ubicacion       bigint,
    p_tipo               text,
    p_patas              jsonb,
    p_id_variante        bigint DEFAULT NULL,
    p_id_opcion_variante bigint DEFAULT NULL,
    p_id_operacion       bigint DEFAULT NULL,
    p_uuid               uuid DEFAULT NULL,
    p_motivo             text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
    v_id_evento       bigint;
    v_orden           integer := 0;
    v_tipo_pata       text;
    v_id_presentacion bigint;
    v_cantidad        numeric;
    v_factor_enviado  numeric;
    v_factor_catalogo numeric;
    v_es_fraccionable boolean;
    v_equivalente     numeric;
    v_salidas         numeric := 0;
    v_entradas        numeric := 0;
    v_total_salidas   integer := 0;
    v_total_entradas  integer := 0;
    v_pata            jsonb;
BEGIN
    IF p_id_producto IS NULL OR p_id_ubicacion IS NULL THEN
        RAISE EXCEPTION 'Producto y ubicación son obligatorios'
            USING ERRCODE = '22023';
    END IF;
    IF p_tipo IS NULL OR p_tipo NOT IN ('apertura', 'empaquetado') THEN
        RAISE EXCEPTION 'Tipo de conversión inválido: %', p_tipo
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
    IF p_patas IS NULL OR jsonb_typeof(p_patas) <> 'array'
       OR jsonb_array_length(p_patas) < 2 THEN
        RAISE EXCEPTION 'La conversión requiere al menos dos patas'
            USING ERRCODE = '22023';
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

    FOR v_pata IN SELECT value FROM jsonb_array_elements(p_patas)
    LOOP
        v_orden := v_orden + 1;
        v_tipo_pata := v_pata->>'tipo';
        v_id_presentacion := NULLIF(v_pata->>'id_presentacion', '')::bigint;
        v_cantidad := NULLIF(v_pata->>'cantidad', '')::numeric;
        v_factor_enviado := NULLIF(v_pata->>'factor_entero', '')::numeric;

        IF v_tipo_pata NOT IN ('salida', 'entrada')
           OR v_id_presentacion IS NULL
           OR v_cantidad IS NULL OR v_cantidad <= 0 THEN
            RAISE EXCEPTION 'Pata % inválida: %', v_orden, v_pata
                USING ERRCODE = '22023';
        END IF;

        SELECT c.factor_entero, c.es_fraccionable
          INTO v_factor_catalogo, v_es_fraccionable
          FROM public.fn_presentaciones_producto_v2(p_id_producto) c
         WHERE c.id_presentacion = v_id_presentacion;
        IF v_factor_catalogo IS NULL THEN
            RAISE EXCEPTION 'La presentación % no pertenece al producto %',
                v_id_presentacion, p_id_producto USING ERRCODE = '22023';
        END IF;
        IF NOT v_es_fraccionable AND trunc(v_cantidad) <> v_cantidad THEN
            RAISE EXCEPTION 'La presentación % no admite cantidades fraccionarias',
                v_id_presentacion USING ERRCODE = '22023';
        END IF;
        IF v_factor_enviado IS NOT NULL
           AND v_factor_enviado <> v_factor_catalogo THEN
            RAISE EXCEPTION 'El factor enviado para la presentación % no coincide con el catálogo',
                v_id_presentacion USING ERRCODE = '22023';
        END IF;

        v_equivalente := v_cantidad * v_factor_catalogo;
        IF v_tipo_pata = 'salida' THEN
            v_salidas := v_salidas + v_equivalente;
            v_total_salidas := v_total_salidas + 1;
        ELSE
            v_entradas := v_entradas + v_equivalente;
            v_total_entradas := v_total_entradas + 1;
        END IF;
    END LOOP;

    IF v_total_salidas = 0 OR v_total_entradas = 0 THEN
        RAISE EXCEPTION 'La conversión requiere patas de salida y de entrada'
            USING ERRCODE = '22023';
    END IF;
    IF v_salidas <> v_entradas THEN
        RAISE EXCEPTION 'Conversión no neutral: salidas %, entradas %',
            v_salidas, v_entradas USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.app_dat_conversion_presentacion_evento (
        id_operacion, id_producto, id_variante, id_opcion_variante,
        id_ubicacion, tipo, motivo, uuid
    ) VALUES (
        p_id_operacion, p_id_producto, p_id_variante, p_id_opcion_variante,
        p_id_ubicacion, p_tipo, p_motivo, p_uuid
    ) RETURNING id INTO v_id_evento;

    v_orden := 0;
    FOR v_pata IN SELECT value FROM jsonb_array_elements(p_patas)
    LOOP
        v_orden := v_orden + 1;
        v_tipo_pata := v_pata->>'tipo';
        v_id_presentacion := (v_pata->>'id_presentacion')::bigint;
        v_cantidad := (v_pata->>'cantidad')::numeric;
        SELECT c.factor_entero
          INTO STRICT v_factor_catalogo
          FROM public.fn_presentaciones_producto_v2(p_id_producto) c
         WHERE c.id_presentacion = v_id_presentacion;
        v_equivalente := v_cantidad * v_factor_catalogo;

        INSERT INTO public.app_dat_conversion_presentacion_pata (
            id_conversion_evento, orden, tipo, id_presentacion,
            cantidad, factor_entero, equivalente
        ) VALUES (
            v_id_evento, v_orden, v_tipo_pata, v_id_presentacion,
            v_cantidad, v_factor_catalogo, v_equivalente
        );
    END LOOP;

    RETURN v_id_evento;
END;
$function$;

COMMENT ON FUNCTION public.fn_registrar_conversion_v2(
    bigint, bigint, text, jsonb, bigint, bigint, bigint, uuid, text
) IS 'Registra una conversión física N→N después de validar catálogo y neutralidad exacta.';

REVOKE ALL ON FUNCTION public.fn_registrar_conversion_v2(
    bigint, bigint, text, jsonb, bigint, bigint, bigint, uuid, text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_registrar_conversion_v2(
    bigint, bigint, text, jsonb, bigint, bigint, bigint, uuid, text
) TO service_role;

-- Los triggers de sincronización/notificación deben ignorar cualquier conversión.
CREATE OR REPLACE FUNCTION public.fn_conversion_inventario_es_interna_v2(
    p_id_conversion bigint,
    p_id_conversion_evento bigint
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
    SELECT p_id_conversion IS NOT NULL OR p_id_conversion_evento IS NOT NULL;
$function$;

REVOKE ALL ON FUNCTION public.fn_conversion_inventario_es_interna_v2(bigint, bigint)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_conversion_inventario_es_interna_v2(bigint, bigint)
    TO service_role;

-- IMPORTANTE: antes de que el paso 41 escriba patas en el ledger, las funciones
-- fn_sincronizar_stock_producto y fn_notificar_producto_disponible deben ampliar
-- su guarda actual a:
--   IF NEW.id_conversion IS NOT NULL
--      OR NEW.id_conversion_evento IS NOT NULL THEN RETURN NEW; END IF;
-- Se deja esa mutación para el paso 41, junto con la primera escritura real.
