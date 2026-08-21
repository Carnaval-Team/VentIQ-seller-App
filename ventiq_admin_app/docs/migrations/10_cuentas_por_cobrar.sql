-- ============================================================================
-- 10_cuentas_por_cobrar.sql
-- ----------------------------------------------------------------------------
-- Módulo de Cuentas por Cobrar (ventas a "pago pendiente" / fiado).
--
-- Diseño (acordado con el negocio):
--   * Los clientes NO tienen límite de crédito numérico. Se crean "al vuelo"
--     la primera vez que se les hace una venta que queda como cuenta por
--     cobrar (igual que ya ocurre hoy en la pantalla de Venta por Acuerdo).
--   * Un cliente puede ser BLOQUEADO manualmente por un gerente/supervisor
--     para impedir que se le sigan generando nuevas cuentas por cobrar,
--     sin importar el monto que ya deba.
--   * Una venta a crédito es una fila normal de app_dat_operacion_venta con
--     es_pagada = false. El saldo de esa venta es
--     importe_total - SUM(app_dat_pago_venta.monto).
--   * Los abonos/liquidaciones se registran como filas normales en
--     app_dat_pago_venta (igual patrón que un pago parcial), para conservar
--     el historial completo de qué se debía y cuándo se fue liquidando.
--   * Cuando un cobro cubre varias ventas de un mismo cliente en un solo
--     recibo, se agrupan bajo una fila de app_dat_liquidacion_cxc.
--
-- Idempotente: usa IF NOT EXISTS / CREATE OR REPLACE en todo.
-- ============================================================================

-- ── 0. Configuración de tienda: quién puede crear ventas a pago pendiente ──
ALTER TABLE public.app_dat_configuracion_tienda
  ADD COLUMN IF NOT EXISTS vendedores_pueden_crear_cxc boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.app_dat_configuracion_tienda.vendedores_pueden_crear_cxc IS
  'Si es true, cualquier vendedor puede registrar ventas a pago pendiente (cuenta por cobrar) desde el TPV. Si es false, solo gerente/supervisor pueden hacerlo.';

-- ── 1. Columna de bloqueo manual en clientes ────────────────────────────────
ALTER TABLE public.app_dat_clientes
  ADD COLUMN IF NOT EXISTS bloqueado_cxc boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.app_dat_clientes.bloqueado_cxc IS
  'Si es true, no se le pueden crear nuevas ventas a pago pendiente (cuentas por cobrar). No afecta ventas ya existentes.';

-- ── 2. Tabla de liquidaciones (recibos de cobro que agrupan uno o varios
--       pagos aplicados a distintas ventas del mismo cliente) ───────────────
CREATE TABLE IF NOT EXISTS public.app_dat_liquidacion_cxc (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_cliente bigint NOT NULL REFERENCES public.app_dat_clientes(id),
  id_tienda bigint NOT NULL REFERENCES public.app_dat_tienda(id),
  monto_total numeric NOT NULL CHECK (monto_total > 0),
  id_medio_pago smallint NOT NULL REFERENCES public.app_nom_medio_pago(id),
  referencia_pago character varying,
  observaciones text,
  creado_por uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.app_dat_liquidacion_cxc IS
  'Recibo de cobro de cuentas por cobrar: agrupa los abonos (app_dat_pago_venta) generados al liquidar deuda de un cliente, posiblemente repartidos entre varias ventas.';

-- ── 3. Relacionar cada abono de CxC con su liquidación (recibo) ────────────
ALTER TABLE public.app_dat_pago_venta
  ADD COLUMN IF NOT EXISTS id_liquidacion bigint
    REFERENCES public.app_dat_liquidacion_cxc(id);

-- ── 4. RLS de las tablas nuevas: mismo criterio que pago_venta (gerente/
--       supervisor/auditor de la tienda) ───────────────────────────────────
ALTER TABLE public.app_dat_liquidacion_cxc ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS liquidacion_cxc_admin_all ON public.app_dat_liquidacion_cxc;
CREATE POLICY liquidacion_cxc_admin_all
  ON public.app_dat_liquidacion_cxc
  FOR ALL
  TO authenticated
  USING (public.fn_user_can_access_tienda(id_tienda))
  WITH CHECK (public.fn_user_can_access_tienda(id_tienda));

-- ── 5. Saldo pendiente de un cliente (todas las tiendas) ───────────────────
CREATE OR REPLACE FUNCTION public.fn_cxc_saldo_cliente(p_id_cliente bigint)
RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT COALESCE(SUM(
    ov.importe_total - COALESCE((
      SELECT SUM(pv.monto) FROM public.app_dat_pago_venta pv
      WHERE pv.id_operacion_venta = ov.id_operacion
    ), 0)
  ), 0)
  FROM public.app_dat_operacion_venta ov
  WHERE ov.id_cliente = p_id_cliente
    AND ov.es_pagada = false;
$$;

-- ── 6. Listado de clientes con saldo pendiente en una tienda ───────────────
CREATE OR REPLACE FUNCTION public.fn_cxc_listar_clientes(p_id_tienda bigint)
RETURNS TABLE (
  id_cliente bigint,
  nombre_completo character varying,
  telefono character varying,
  codigo_cliente character varying,
  bloqueado_cxc boolean,
  saldo_pendiente numeric,
  ordenes_pendientes bigint,
  fecha_mas_antigua timestamp with time zone
)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT
    c.id,
    c.nombre_completo,
    c.telefono,
    c.codigo_cliente,
    c.bloqueado_cxc,
    SUM(ov.importe_total - COALESCE(pv.abonado, 0)) AS saldo_pendiente,
    COUNT(DISTINCT ov.id_operacion) AS ordenes_pendientes,
    MIN(o.created_at) AS fecha_mas_antigua
  FROM public.app_dat_operacion_venta ov
  JOIN public.app_dat_operaciones o ON o.id = ov.id_operacion
  JOIN public.app_dat_clientes c ON c.id = ov.id_cliente
  LEFT JOIN LATERAL (
    SELECT SUM(pv.monto) AS abonado
    FROM public.app_dat_pago_venta pv
    WHERE pv.id_operacion_venta = ov.id_operacion
  ) pv ON true
  WHERE o.id_tienda = p_id_tienda
    AND ov.es_pagada = false
    AND ov.id_cliente IS NOT NULL
  GROUP BY c.id, c.nombre_completo, c.telefono, c.codigo_cliente, c.bloqueado_cxc
  HAVING SUM(ov.importe_total - COALESCE(pv.abonado, 0)) > 0
  ORDER BY saldo_pendiente DESC;
$$;

-- ── 7. Historial de ventas a crédito de un cliente (pagadas y pendientes) ──
CREATE OR REPLACE FUNCTION public.fn_cxc_historial_cliente(p_id_cliente bigint)
RETURNS TABLE (
  id_operacion bigint,
  fecha timestamp with time zone,
  denominacion character varying,
  importe_total numeric,
  abonado numeric,
  saldo numeric,
  es_pagada boolean
)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT
    ov.id_operacion,
    o.created_at AS fecha,
    ov.denominacion,
    ov.importe_total,
    COALESCE(pv.abonado, 0) AS abonado,
    ov.importe_total - COALESCE(pv.abonado, 0) AS saldo,
    ov.es_pagada
  FROM public.app_dat_operacion_venta ov
  JOIN public.app_dat_operaciones o ON o.id = ov.id_operacion
  LEFT JOIN LATERAL (
    SELECT SUM(pv.monto) AS abonado
    FROM public.app_dat_pago_venta pv
    WHERE pv.id_operacion_venta = ov.id_operacion
  ) pv ON true
  WHERE ov.id_cliente = p_id_cliente
  ORDER BY o.created_at DESC;
$$;

-- ── 8. Bloquear/desbloquear un cliente para nuevas cuentas por cobrar ──────
CREATE OR REPLACE FUNCTION public.fn_cxc_set_bloqueo_cliente(
  p_id_cliente bigint,
  p_bloqueado boolean
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.app_dat_clientes
  SET bloqueado_cxc = p_bloqueado
  WHERE id = p_id_cliente;
END;
$$;

-- ── 9. Registrar una liquidación (cobro) aplicada a una o varias ventas ────
-- Si p_distribucion es NULL, el monto se aplica automáticamente en modo
-- FIFO: primero a la venta pendiente más antigua, hasta agotar el monto.
-- Si p_distribucion viene informado, es un jsonb con la forma:
--   [{"id_operacion_venta": 123, "monto": 50.00}, ...]
-- y se aplica exactamente esa distribución (debe sumar <= p_monto).
CREATE OR REPLACE FUNCTION public.fn_cxc_registrar_liquidacion(
  p_id_cliente bigint,
  p_id_tienda bigint,
  p_monto numeric,
  p_id_medio_pago smallint,
  p_referencia character varying,
  p_creado_por uuid,
  p_observaciones text DEFAULT NULL,
  p_distribucion jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_id_liquidacion bigint;
  v_restante numeric := p_monto;
  v_aplicado numeric;
  v_item jsonb;
  v_id_operacion bigint;
  v_monto_item numeric;
  v_saldo_venta numeric;
  v_total_aplicado numeric := 0;
  rec record;
BEGIN
  IF p_monto IS NULL OR p_monto <= 0 THEN
    RAISE EXCEPTION 'El monto a liquidar debe ser mayor que 0';
  END IF;

  INSERT INTO public.app_dat_liquidacion_cxc (
    id_cliente, id_tienda, monto_total, id_medio_pago,
    referencia_pago, observaciones, creado_por
  ) VALUES (
    p_id_cliente, p_id_tienda, p_monto, p_id_medio_pago,
    p_referencia, p_observaciones, p_creado_por
  ) RETURNING id INTO v_id_liquidacion;

  IF p_distribucion IS NOT NULL THEN
    -- ── Modo manual: aplicar exactamente lo indicado por el admin ──────────
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_distribucion) LOOP
      v_id_operacion := (v_item->>'id_operacion_venta')::bigint;
      v_monto_item := (v_item->>'monto')::numeric;
      IF v_monto_item IS NULL OR v_monto_item <= 0 THEN
        CONTINUE;
      END IF;

      INSERT INTO public.app_dat_pago_venta (
        id_operacion_venta, id_medio_pago, monto, referencia_pago,
        creado_por, importe_sin_descuento, id_liquidacion
      ) VALUES (
        v_id_operacion, p_id_medio_pago, v_monto_item, p_referencia,
        p_creado_por, v_monto_item, v_id_liquidacion
      );

      v_total_aplicado := v_total_aplicado + v_monto_item;

      UPDATE public.app_dat_operacion_venta ov
      SET es_pagada = (
        ov.importe_total <= (
          SELECT SUM(pv.monto) FROM public.app_dat_pago_venta pv
          WHERE pv.id_operacion_venta = ov.id_operacion
        )
      )
      WHERE ov.id_operacion = v_id_operacion;
    END LOOP;
  ELSE
    -- ── Modo FIFO: aplicar a las ventas pendientes más antiguas primero ────
    FOR rec IN
      SELECT ov.id_operacion,
             ov.importe_total - COALESCE((
               SELECT SUM(pv.monto) FROM public.app_dat_pago_venta pv
               WHERE pv.id_operacion_venta = ov.id_operacion
             ), 0) AS saldo
      FROM public.app_dat_operacion_venta ov
      JOIN public.app_dat_operaciones o ON o.id = ov.id_operacion
      WHERE ov.id_cliente = p_id_cliente
        AND ov.es_pagada = false
        AND o.id_tienda = p_id_tienda
      ORDER BY o.created_at ASC
    LOOP
      EXIT WHEN v_restante <= 0;
      v_saldo_venta := rec.saldo;
      IF v_saldo_venta <= 0 THEN
        CONTINUE;
      END IF;

      v_aplicado := LEAST(v_saldo_venta, v_restante);

      INSERT INTO public.app_dat_pago_venta (
        id_operacion_venta, id_medio_pago, monto, referencia_pago,
        creado_por, importe_sin_descuento, id_liquidacion
      ) VALUES (
        rec.id_operacion, p_id_medio_pago, v_aplicado, p_referencia,
        p_creado_por, v_aplicado, v_id_liquidacion
      );

      UPDATE public.app_dat_operacion_venta ov
      SET es_pagada = (v_aplicado >= v_saldo_venta)
      WHERE ov.id_operacion = rec.id_operacion;

      v_restante := v_restante - v_aplicado;
      v_total_aplicado := v_total_aplicado + v_aplicado;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'id_liquidacion', v_id_liquidacion,
    'monto_total', p_monto,
    'monto_aplicado', v_total_aplicado,
    'sobrante_sin_aplicar', p_monto - v_total_aplicado
  );
END;
$$;

-- ── Permisos ────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION public.fn_cxc_saldo_cliente(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_cxc_listar_clientes(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_cxc_historial_cliente(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_cxc_set_bloqueo_cliente(bigint, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_cxc_registrar_liquidacion(bigint, bigint, numeric, smallint, character varying, uuid, text, jsonb) TO authenticated;
