-- ============================================================================
-- 01 · Lotes / vencimientos — schema + RLS + fn_obtener_o_crear_lote
-- ============================================================================
-- Plan: docs/PLAN_VENCIMIENTOS_LOTES.md  (Fase 0)
-- Aplicar en: SQL Editor de **newa** durante todo el desarrollo.
-- Main: solo al cerrar el proyecto completo (fases 0–7). Idempotente.
--
-- Qué hace:
--   1) Crea app_dat_lote (maestro de lote por tienda+producto+código)
--   2) Añade id_lote nullable a recepción / inventario / extracción
--   3) RLS + policies acotadas por tienda (no USING true)
--   4) RPC fn_obtener_o_crear_lote (idempotente)
--
-- No toca aún las RPCs de recepción ni la UI (Fase 1).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Tabla app_dat_lote
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_dat_lote (
    id                 bigserial PRIMARY KEY,
    id_tienda          bigint NOT NULL REFERENCES public.app_dat_tienda (id),
    id_producto        bigint NOT NULL REFERENCES public.app_dat_producto (id),
    codigo             text   NOT NULL,
    fecha_vencimiento   date   NOT NULL,
    fecha_fabricacion  date   NULL,
    observaciones      text   NULL,
    created_at         timestamptz NOT NULL DEFAULT now(),
    created_by         uuid NULL,
    CONSTRAINT app_dat_lote_fab_lte_venc_chk
        CHECK (
            fecha_fabricacion IS NULL
            OR fecha_fabricacion <= fecha_vencimiento
        ),
    CONSTRAINT app_dat_lote_codigo_not_blank_chk
        CHECK (length(trim(codigo)) > 0)
);

-- Unicidad: mismo código de lote por producto en la tienda (case-insensitive)
CREATE UNIQUE INDEX IF NOT EXISTS app_dat_lote_tienda_producto_codigo_uidx
    ON public.app_dat_lote (id_tienda, id_producto, lower(codigo));

CREATE INDEX IF NOT EXISTS app_dat_lote_producto_idx
    ON public.app_dat_lote (id_producto);

CREATE INDEX IF NOT EXISTS app_dat_lote_tienda_venc_idx
    ON public.app_dat_lote (id_tienda, fecha_vencimiento);

CREATE INDEX IF NOT EXISTS app_dat_lote_venc_idx
    ON public.app_dat_lote (fecha_vencimiento);

COMMENT ON TABLE public.app_dat_lote IS
    'Lote de inventario con fecha de vencimiento. '
    'Se enlaza a recepción/inventario/extracción vía id_lote. '
    'Solo aplica operativamente cuando app_dat_producto.es_por_lotes = true.';

COMMENT ON COLUMN public.app_dat_lote.codigo IS
    'Identificador del lote (proveedor o interno). Único por tienda+producto.';

COMMENT ON COLUMN public.app_dat_lote.fecha_vencimiento IS
    'Fecha de caducidad del lote. Base para alertas con dias_alert_caducidad.';

-- RLS inmediato (misma transacción / mismo script)
ALTER TABLE public.app_dat_lote ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_dat_lote FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS app_dat_lote_select ON public.app_dat_lote;
CREATE POLICY app_dat_lote_select ON public.app_dat_lote
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.app_dat_gerente g
            WHERE g.uuid = auth.uid() AND g.id_tienda = app_dat_lote.id_tienda
        )
        OR EXISTS (
            SELECT 1 FROM public.app_dat_supervisor s
            WHERE s.uuid = auth.uid() AND s.id_tienda = app_dat_lote.id_tienda
        )
        OR EXISTS (
            SELECT 1 FROM public.auditor a
            WHERE a.uuid = auth.uid() AND a.id_tienda = app_dat_lote.id_tienda
        )
        OR EXISTS (
            SELECT 1
            FROM public.app_dat_almacenero al
            JOIN public.app_dat_almacen alm ON alm.id = al.id_almacen
            WHERE al.uuid = auth.uid() AND alm.id_tienda = app_dat_lote.id_tienda
        )
        OR EXISTS (
            SELECT 1
            FROM public.app_dat_vendedor v
            JOIN public.app_dat_tpv tpv ON tpv.id = v.id_tpv
            WHERE v.uuid = auth.uid() AND tpv.id_tienda = app_dat_lote.id_tienda
        )
    );

DROP POLICY IF EXISTS app_dat_lote_insert ON public.app_dat_lote;
CREATE POLICY app_dat_lote_insert ON public.app_dat_lote
    FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.app_dat_gerente g
            WHERE g.uuid = auth.uid() AND g.id_tienda = app_dat_lote.id_tienda
        )
        OR EXISTS (
            SELECT 1 FROM public.app_dat_supervisor s
            WHERE s.uuid = auth.uid() AND s.id_tienda = app_dat_lote.id_tienda
        )
        OR EXISTS (
            SELECT 1
            FROM public.app_dat_almacenero al
            JOIN public.app_dat_almacen alm ON alm.id = al.id_almacen
            WHERE al.uuid = auth.uid() AND alm.id_tienda = app_dat_lote.id_tienda
        )
    );

DROP POLICY IF EXISTS app_dat_lote_update ON public.app_dat_lote;
CREATE POLICY app_dat_lote_update ON public.app_dat_lote
    FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.app_dat_gerente g
            WHERE g.uuid = auth.uid() AND g.id_tienda = app_dat_lote.id_tienda
        )
        OR EXISTS (
            SELECT 1 FROM public.app_dat_supervisor s
            WHERE s.uuid = auth.uid() AND s.id_tienda = app_dat_lote.id_tienda
        )
        OR EXISTS (
            SELECT 1
            FROM public.app_dat_almacenero al
            JOIN public.app_dat_almacen alm ON alm.id = al.id_almacen
            WHERE al.uuid = auth.uid() AND alm.id_tienda = app_dat_lote.id_tienda
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.app_dat_gerente g
            WHERE g.uuid = auth.uid() AND g.id_tienda = app_dat_lote.id_tienda
        )
        OR EXISTS (
            SELECT 1 FROM public.app_dat_supervisor s
            WHERE s.uuid = auth.uid() AND s.id_tienda = app_dat_lote.id_tienda
        )
        OR EXISTS (
            SELECT 1
            FROM public.app_dat_almacenero al
            JOIN public.app_dat_almacen alm ON alm.id = al.id_almacen
            WHERE al.uuid = auth.uid() AND alm.id_tienda = app_dat_lote.id_tienda
        )
    );

-- Sin DELETE policy: lotes no se borran desde cliente (histórico / stock).
-- Si hace falta, RPC SECURITY DEFINER con gerente.

GRANT SELECT, INSERT, UPDATE ON public.app_dat_lote TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.app_dat_lote_id_seq TO authenticated;


-- ----------------------------------------------------------------------------
-- 2. FKs en tablas de movimiento (nullable = productos sin lotes)
-- ----------------------------------------------------------------------------
ALTER TABLE public.app_dat_recepcion_productos
    ADD COLUMN IF NOT EXISTS id_lote bigint
        REFERENCES public.app_dat_lote (id);

ALTER TABLE public.app_dat_inventario_productos
    ADD COLUMN IF NOT EXISTS id_lote bigint
        REFERENCES public.app_dat_lote (id);

ALTER TABLE public.app_dat_extraccion_productos
    ADD COLUMN IF NOT EXISTS id_lote bigint
        REFERENCES public.app_dat_lote (id);

CREATE INDEX IF NOT EXISTS app_dat_recepcion_productos_id_lote_idx
    ON public.app_dat_recepcion_productos (id_lote)
    WHERE id_lote IS NOT NULL;

CREATE INDEX IF NOT EXISTS app_dat_inventario_productos_id_lote_idx
    ON public.app_dat_inventario_productos (id_lote)
    WHERE id_lote IS NOT NULL;

CREATE INDEX IF NOT EXISTS app_dat_extraccion_productos_id_lote_idx
    ON public.app_dat_extraccion_productos (id_lote)
    WHERE id_lote IS NOT NULL;

COMMENT ON COLUMN public.app_dat_recepcion_productos.id_lote IS
    'Lote asociado a la línea de recepción (null si el producto no es por lotes).';
COMMENT ON COLUMN public.app_dat_inventario_productos.id_lote IS
    'Lote del snapshot de inventario. Particiona el saldo junto a producto/ubicación/presentación.';
COMMENT ON COLUMN public.app_dat_extraccion_productos.id_lote IS
    'Lote descontado en la extracción/venta (FEFO o elección manual).';


-- ----------------------------------------------------------------------------
-- 3. fn_obtener_o_crear_lote — idempotente
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_obtener_o_crear_lote(
    p_id_tienda         bigint,
    p_id_producto       bigint,
    p_codigo            text,
    p_fecha_vencimiento date,
    p_fecha_fabricacion date DEFAULT NULL,
    p_observaciones     text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_codigo     text := trim(COALESCE(p_codigo, ''));
    v_id_lote    bigint;
    v_created    boolean := false;
    v_prod_tienda bigint;
    v_es_por_lotes boolean;
    v_row        public.app_dat_lote%ROWTYPE;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'Usuario no autenticado');
    END IF;

    IF p_id_tienda IS NULL OR p_id_producto IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'id_tienda e id_producto son obligatorios'
        );
    END IF;

    IF v_codigo = '' THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'codigo de lote vacío');
    END IF;

    IF p_fecha_vencimiento IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'fecha_vencimiento es obligatoria'
        );
    END IF;

    IF p_fecha_fabricacion IS NOT NULL
       AND p_fecha_fabricacion > p_fecha_vencimiento THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'fecha_fabricacion no puede ser posterior a fecha_vencimiento'
        );
    END IF;

    -- Acceso a la tienda (incluye almacenero / vendedor / auditor / etc.)
    BEGIN
        PERFORM public.check_user_has_access_to_tienda(p_id_tienda);
    EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', SQLERRM
        );
    END;

    SELECT p.id_tienda, COALESCE(p.es_por_lotes, false)
      INTO v_prod_tienda, v_es_por_lotes
      FROM public.app_dat_producto p
     WHERE p.id = p_id_producto
       AND p.deleted_at IS NULL;

    IF v_prod_tienda IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', format('Producto %s no encontrado', p_id_producto)
        );
    END IF;

    IF v_prod_tienda <> p_id_tienda THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El producto no pertenece a la tienda indicada'
        );
    END IF;

    -- Buscar existente (mismo código, case-insensitive)
    SELECT l.id
      INTO v_id_lote
      FROM public.app_dat_lote l
     WHERE l.id_tienda = p_id_tienda
       AND l.id_producto = p_id_producto
       AND lower(l.codigo) = lower(v_codigo)
     LIMIT 1;

    IF v_id_lote IS NOT NULL THEN
        SELECT * INTO v_row FROM public.app_dat_lote WHERE id = v_id_lote;
        -- Si ya existe con otra fecha, no pisar en silencio: avisar
        IF v_row.fecha_vencimiento IS DISTINCT FROM p_fecha_vencimiento THEN
            RETURN jsonb_build_object(
                'status', 'error',
                'message', format(
                    'Ya existe el lote "%s" con fecha_vencimiento %s (recibido %s)',
                    v_row.codigo, v_row.fecha_vencimiento, p_fecha_vencimiento
                ),
                'id_lote', v_id_lote,
                'fecha_vencimiento_existente', v_row.fecha_vencimiento
            );
        END IF;

        RETURN jsonb_build_object(
            'status', 'success',
            'created', false,
            'id_lote', v_id_lote,
            'codigo', v_row.codigo,
            'fecha_vencimiento', v_row.fecha_vencimiento,
            'es_por_lotes_producto', v_es_por_lotes
        );
    END IF;

    INSERT INTO public.app_dat_lote (
        id_tienda,
        id_producto,
        codigo,
        fecha_vencimiento,
        fecha_fabricacion,
        observaciones,
        created_by
    ) VALUES (
        p_id_tienda,
        p_id_producto,
        v_codigo,
        p_fecha_vencimiento,
        p_fecha_fabricacion,
        NULLIF(trim(COALESCE(p_observaciones, '')), ''),
        auth.uid()
    )
    RETURNING id INTO v_id_lote;

    v_created := true;
    SELECT * INTO v_row FROM public.app_dat_lote WHERE id = v_id_lote;

    RETURN jsonb_build_object(
        'status', 'success',
        'created', v_created,
        'id_lote', v_id_lote,
        'codigo', v_row.codigo,
        'fecha_vencimiento', v_row.fecha_vencimiento,
        'es_por_lotes_producto', v_es_por_lotes
    );

EXCEPTION WHEN unique_violation THEN
    -- Carrera: otro request creó el mismo código
    SELECT l.id INTO v_id_lote
      FROM public.app_dat_lote l
     WHERE l.id_tienda = p_id_tienda
       AND l.id_producto = p_id_producto
       AND lower(l.codigo) = lower(v_codigo)
     LIMIT 1;

    RETURN jsonb_build_object(
        'status', 'success',
        'created', false,
        'id_lote', v_id_lote,
        'message', 'Lote creado concurrentemente; reutilizado'
    );
WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'status', 'error',
        'message', 'Error en fn_obtener_o_crear_lote: ' || SQLERRM,
        'error_detail', SQLSTATE
    );
END;
$$;

COMMENT ON FUNCTION public.fn_obtener_o_crear_lote(
    bigint, bigint, text, date, date, text
) IS
    'Obtiene o crea un lote (tienda+producto+código). Idempotente. '
    'Si el código ya existe con otra fecha_vencimiento, retorna error.';

GRANT EXECUTE ON FUNCTION public.fn_obtener_o_crear_lote(
    bigint, bigint, text, date, date, text
) TO authenticated, service_role;
