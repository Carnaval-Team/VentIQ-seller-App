-- ============================================================================
-- VentIQ - Modo Restaurante: Mesas y Comensales
-- ============================================================================
-- Este archivo contiene:
--   1. Tabla `app_dat_mesas`
--   2. ALTER `app_dat_operacion_venta` para añadir `id_mesa`
--   3. ALTER `app_dat_configuracion_tienda` para añadir `modo_restaurante`
--   4. Funciones (RPCs):
--        - fn_listar_mesas_con_stats
--        - fn_resumen_mesas
--        - fn_insertar_mesa
--        - fn_actualizar_mesa
--        - fn_eliminar_mesa
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. TABLA: app_dat_mesas
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_dat_mesas
(
    id          bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_tienda   bigint      NOT NULL,
    numero      text        NOT NULL,                       -- "Mesa 1", "T-3", "Barra 2"
    capacidad   smallint    NOT NULL DEFAULT 4,
    zona        text,                                       -- "Terraza", "Salón A", "Barra"
    notas       text,
    activa      boolean     NOT NULL DEFAULT true,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT  app_dat_mesas_id_tienda_fkey FOREIGN KEY (id_tienda)
        REFERENCES public.app_dat_tienda (id) ON DELETE CASCADE,
    CONSTRAINT  app_dat_mesas_tienda_numero_unique UNIQUE (id_tienda, numero)
);

CREATE INDEX IF NOT EXISTS idx_mesas_tienda_activa
    ON public.app_dat_mesas (id_tienda, activa);

COMMENT ON TABLE  public.app_dat_mesas IS 'Mesas / puestos de comensales para tiendas en modo restaurante.';
COMMENT ON COLUMN public.app_dat_mesas.numero    IS 'Etiqueta visible de la mesa (Mesa 1, T-3, Barra 2). Único por tienda.';
COMMENT ON COLUMN public.app_dat_mesas.capacidad IS 'Capacidad de comensales máxima de la mesa.';
COMMENT ON COLUMN public.app_dat_mesas.zona      IS 'Zona/sala donde está la mesa (Terraza, Salón A, etc.).';
COMMENT ON COLUMN public.app_dat_mesas.activa    IS 'Si está inactiva no aparece en la grilla operativa pero preserva histórico.';


-- ----------------------------------------------------------------------------
-- 2. ALTER: app_dat_operacion_venta - vincular orden con mesa
-- ----------------------------------------------------------------------------
ALTER TABLE public.app_dat_operacion_venta
    ADD COLUMN IF NOT EXISTS id_mesa bigint;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
         WHERE constraint_name = 'app_dat_operacion_venta_id_mesa_fkey'
    ) THEN
        ALTER TABLE public.app_dat_operacion_venta
            ADD CONSTRAINT app_dat_operacion_venta_id_mesa_fkey
            FOREIGN KEY (id_mesa) REFERENCES public.app_dat_mesas (id)
            ON DELETE SET NULL;
    END IF;
END$$;

CREATE INDEX IF NOT EXISTS idx_op_venta_mesa
    ON public.app_dat_operacion_venta (id_mesa)
    WHERE id_mesa IS NOT NULL;

COMMENT ON COLUMN public.app_dat_operacion_venta.id_mesa
    IS 'Mesa asociada a la venta (NULL para ventas de mostrador).';


-- ----------------------------------------------------------------------------
-- 3. ALTER: app_dat_configuracion_tienda - toggle modo restaurante
-- ----------------------------------------------------------------------------
ALTER TABLE public.app_dat_configuracion_tienda
    ADD COLUMN IF NOT EXISTS modo_restaurante boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.app_dat_configuracion_tienda.modo_restaurante
    IS 'Si true, la tienda opera como restaurante: aparece módulo de mesas y el checkout pide mesa en lugar de cliente.';


-- ============================================================================
-- 4. FUNCIONES (RPCs)
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 4.1 fn_listar_mesas_con_stats
-- Lista todas las mesas (activas e inactivas) con contadores de órdenes.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_listar_mesas_con_stats(
    p_id_tienda bigint
)
RETURNS TABLE (
    id                                bigint,
    numero                            text,
    capacidad                         smallint,
    zona                              text,
    notas                             text,
    activa                            boolean,
    ordenes_abiertas                  integer,
    ordenes_completadas_historicas    integer,
    comensales_activos                integer,
    created_at                        timestamptz,
    updated_at                        timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        m.id,
        m.numero,
        m.capacidad,
        m.zona,
        m.notas,
        m.activa,
        COALESCE(stats.ordenes_abiertas, 0)::integer,
        COALESCE(stats.ordenes_completadas, 0)::integer,
        COALESCE(stats.ordenes_abiertas, 0)::integer AS comensales_activos,
        m.created_at,
        m.updated_at
    FROM public.app_dat_mesas m
    LEFT JOIN LATERAL (
        SELECT
            SUM(CASE WHEN ult_estado.estado IN (1, 4) THEN 1 ELSE 0 END) AS ordenes_abiertas,
            SUM(CASE WHEN ult_estado.estado = 2          THEN 1 ELSE 0 END) AS ordenes_completadas
        FROM public.app_dat_operacion_venta ov
        LEFT JOIN LATERAL (
            SELECT eo.estado
              FROM public.app_dat_estado_operacion eo
             WHERE eo.id_operacion = ov.id_operacion
             ORDER BY eo.id DESC
             LIMIT 1
        ) ult_estado ON TRUE
        WHERE ov.id_mesa = m.id
    ) stats ON TRUE
    WHERE m.id_tienda = p_id_tienda
    ORDER BY m.activa DESC, m.zona NULLS LAST, m.numero;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_listar_mesas_con_stats(bigint) TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 4.2 fn_resumen_mesas
-- Métricas globales del módulo de mesas para el header de la pantalla.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_resumen_mesas(
    p_id_tienda bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_total                 integer := 0;
    v_ocupadas              integer := 0;
    v_libres                integer := 0;
    v_ordenes_pendientes    integer := 0;
    v_top                   jsonb   := NULL;
BEGIN
    WITH mesas_stats AS (
        SELECT
            m.id,
            m.numero,
            COALESCE((
                SELECT COUNT(*)
                  FROM public.app_dat_operacion_venta ov
                  JOIN LATERAL (
                      SELECT eo.estado FROM public.app_dat_estado_operacion eo
                       WHERE eo.id_operacion = ov.id_operacion
                       ORDER BY eo.id DESC LIMIT 1
                  ) ult ON TRUE
                 WHERE ov.id_mesa = m.id
                   AND ult.estado IN (1, 4)
            ), 0)::integer AS ordenes_abiertas
        FROM public.app_dat_mesas m
        WHERE m.id_tienda = p_id_tienda AND m.activa = true
    )
    SELECT
        COUNT(*)::integer,
        SUM(CASE WHEN ordenes_abiertas > 0 THEN 1 ELSE 0 END)::integer,
        SUM(CASE WHEN ordenes_abiertas = 0 THEN 1 ELSE 0 END)::integer,
        COALESCE(SUM(ordenes_abiertas), 0)::integer
      INTO v_total, v_ocupadas, v_libres, v_ordenes_pendientes
      FROM mesas_stats;

    SELECT jsonb_build_object(
        'id',         ms.id,
        'numero',     ms.numero,
        'comensales', ms.ordenes_abiertas
    )
      INTO v_top
      FROM (
          SELECT
              m.id, m.numero,
              COALESCE((
                  SELECT COUNT(*)
                    FROM public.app_dat_operacion_venta ov
                    JOIN LATERAL (
                        SELECT eo.estado FROM public.app_dat_estado_operacion eo
                         WHERE eo.id_operacion = ov.id_operacion
                         ORDER BY eo.id DESC LIMIT 1
                    ) ult ON TRUE
                   WHERE ov.id_mesa = m.id
                     AND ult.estado IN (1, 4)
              ), 0)::integer AS ordenes_abiertas
            FROM public.app_dat_mesas m
           WHERE m.id_tienda = p_id_tienda AND m.activa = true
      ) ms
      WHERE ms.ordenes_abiertas > 0
      ORDER BY ms.ordenes_abiertas DESC
      LIMIT 1;

    RETURN jsonb_build_object(
        'total',                   COALESCE(v_total, 0),
        'ocupadas',                COALESCE(v_ocupadas, 0),
        'libres',                  COALESCE(v_libres, 0),
        'ordenes_pendientes_total',COALESCE(v_ordenes_pendientes, 0),
        'mesa_top_comensales',     v_top
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_resumen_mesas(bigint) TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 4.3 fn_insertar_mesa
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_insertar_mesa(
    p_id_tienda bigint,
    p_numero    text,
    p_capacidad smallint DEFAULT 4,
    p_zona      text     DEFAULT NULL,
    p_notas     text     DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_id_mesa bigint;
BEGIN
    -- Validar tienda
    IF NOT EXISTS (SELECT 1 FROM public.app_dat_tienda WHERE id = p_id_tienda) THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'La tienda no existe');
    END IF;

    -- Validar duplicado
    IF EXISTS (
        SELECT 1 FROM public.app_dat_mesas
         WHERE id_tienda = p_id_tienda AND lower(numero) = lower(p_numero)
    ) THEN
        RETURN jsonb_build_object(
            'status',  'error',
            'message', 'Ya existe una mesa con ese número en esta tienda',
            'error_code', 'DUPLICATE_NUMERO'
        );
    END IF;

    INSERT INTO public.app_dat_mesas (id_tienda, numero, capacidad, zona, notas)
    VALUES (p_id_tienda, p_numero, COALESCE(p_capacidad, 4), p_zona, p_notas)
    RETURNING id INTO v_id_mesa;

    RETURN jsonb_build_object(
        'status',  'success',
        'id_mesa', v_id_mesa,
        'message', 'Mesa creada correctamente'
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'status',  'error',
            'message', 'Error al crear mesa: ' || SQLERRM,
            'sqlstate', SQLSTATE
        );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_insertar_mesa(bigint, text, smallint, text, text) TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 4.4 fn_actualizar_mesa
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_actualizar_mesa(
    p_id_mesa   bigint,
    p_numero    text     DEFAULT NULL,
    p_capacidad smallint DEFAULT NULL,
    p_zona      text     DEFAULT NULL,
    p_notas     text     DEFAULT NULL,
    p_activa    boolean  DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_id_tienda bigint;
BEGIN
    SELECT id_tienda INTO v_id_tienda FROM public.app_dat_mesas WHERE id = p_id_mesa;

    IF v_id_tienda IS NULL THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'La mesa no existe');
    END IF;

    -- Verificar conflicto de numero si se cambia
    IF p_numero IS NOT NULL THEN
        IF EXISTS (
            SELECT 1 FROM public.app_dat_mesas
             WHERE id_tienda = v_id_tienda
               AND lower(numero) = lower(p_numero)
               AND id <> p_id_mesa
        ) THEN
            RETURN jsonb_build_object(
                'status',     'error',
                'message',    'Ya existe otra mesa con ese número',
                'error_code', 'DUPLICATE_NUMERO'
            );
        END IF;
    END IF;

    UPDATE public.app_dat_mesas
       SET numero     = COALESCE(p_numero,    numero),
           capacidad  = COALESCE(p_capacidad, capacidad),
           zona       = COALESCE(p_zona,      zona),
           notas      = COALESCE(p_notas,     notas),
           activa     = COALESCE(p_activa,    activa),
           updated_at = now()
     WHERE id = p_id_mesa;

    RETURN jsonb_build_object('status', 'success', 'message', 'Mesa actualizada');
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'status',  'error',
            'message', 'Error al actualizar mesa: ' || SQLERRM,
            'sqlstate', SQLSTATE
        );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_actualizar_mesa(bigint, text, smallint, text, text, boolean) TO anon, authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 4.5 fn_eliminar_mesa
-- Soft-delete (activa=false) si tiene órdenes asociadas; hard-delete si no.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_eliminar_mesa(
    p_id_mesa bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_tiene_ordenes boolean;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.app_dat_mesas WHERE id = p_id_mesa) THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'La mesa no existe');
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.app_dat_operacion_venta WHERE id_mesa = p_id_mesa
    ) INTO v_tiene_ordenes;

    IF v_tiene_ordenes THEN
        UPDATE public.app_dat_mesas
           SET activa     = false,
               updated_at = now()
         WHERE id = p_id_mesa;

        RETURN jsonb_build_object(
            'status',  'success',
            'message', 'Mesa marcada como inactiva (preserva histórico)',
            'mode',    'soft_delete'
        );
    ELSE
        DELETE FROM public.app_dat_mesas WHERE id = p_id_mesa;
        RETURN jsonb_build_object(
            'status',  'success',
            'message', 'Mesa eliminada',
            'mode',    'hard_delete'
        );
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'status',  'error',
            'message', 'Error al eliminar mesa: ' || SQLERRM,
            'sqlstate', SQLSTATE
        );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_eliminar_mesa(bigint) TO anon, authenticated, service_role;


-- ============================================================================
-- FIN
-- ============================================================================
