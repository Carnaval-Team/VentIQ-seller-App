-- ============================================================================
-- 11_cuentas_por_cobrar_clientes_independientes.sql
-- ----------------------------------------------------------------------------
-- Desacopla los clientes de Cuentas por Cobrar de `app_dat_clientes`.
--
-- Motivo: `app_dat_clientes` acumula un registro por cada nombre distinto
-- escrito en CUALQUIER venta normal (vía fn_insertar_cliente_con_contactos,
-- llamada desde el checkout de cada venta), lo que la convierte en una tabla
-- enorme y ruidosa, inadecuada para buscar/gestionar clientes con deuda.
--
-- Cambio: se crea `app_dat_cliente_cxc`, una tabla pequeña y dedicada, con
-- alcance por tienda (`id_tienda`), donde solo entran los clientes que
-- realmente participan en una venta a "Pago Pendiente". Las ventas normales
-- (efectivo/transferencia/etc.) siguen usando `app_dat_clientes` exactamente
-- igual que antes, sin ningún cambio.
--
-- Idempotente: usa IF NOT EXISTS / CREATE OR REPLACE en todo.
-- ============================================================================

-- ── 1. Tabla dedicada de clientes de Cuentas por Cobrar ────────────────────
CREATE TABLE IF NOT EXISTS public.app_dat_cliente_cxc (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_tienda bigint NOT NULL REFERENCES public.app_dat_tienda(id),
  codigo_cliente character varying NOT NULL,
  nombre_completo character varying NOT NULL,
  telefono character varying,
  documento_identidad character varying,
  bloqueado_cxc boolean NOT NULL DEFAULT false,
  notas text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_dat_cliente_cxc_tienda_codigo_uk UNIQUE (id_tienda, codigo_cliente)
);

COMMENT ON TABLE public.app_dat_cliente_cxc IS
  'Clientes de Cuentas por Cobrar, independientes de app_dat_clientes. Uno por tienda + código (hash del nombre), para poder encontrar/crear de forma idempotente desde el checkout sin duplicar ni ensuciar la tabla general de clientes.';

CREATE INDEX IF NOT EXISTS idx_cliente_cxc_tienda ON public.app_dat_cliente_cxc (id_tienda);
CREATE INDEX IF NOT EXISTS idx_cliente_cxc_nombre ON public.app_dat_cliente_cxc (nombre_completo);

ALTER TABLE public.app_dat_cliente_cxc ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cliente_cxc_tienda_all ON public.app_dat_cliente_cxc;
CREATE POLICY cliente_cxc_tienda_all
  ON public.app_dat_cliente_cxc
  FOR ALL
  TO authenticated
  USING (public.fn_user_can_access_tienda(id_tienda))
  WITH CHECK (public.fn_user_can_access_tienda(id_tienda));

-- ── 2. Vincular la venta al cliente CxC (columna nueva, independiente de
--       id_cliente que sigue apuntando a app_dat_clientes para otros flujos) ─
ALTER TABLE public.app_dat_operacion_venta
  ADD COLUMN IF NOT EXISTS id_cliente_cxc bigint
    REFERENCES public.app_dat_cliente_cxc(id);

CREATE INDEX IF NOT EXISTS idx_operacion_venta_cliente_cxc
  ON public.app_dat_operacion_venta (id_cliente_cxc);

-- ── 3. Migración de datos: si ya hay ventas es_pagada=false creadas con la
--       primera versión (usando id_cliente -> app_dat_clientes), se
--       "adoptan" en app_dat_cliente_cxc para no perder la trazabilidad. ────
DO $$
DECLARE
  rec record;
  v_codigo character varying;
  v_id_cliente_cxc bigint;
BEGIN
  FOR rec IN
    SELECT ov.id_operacion, ov.id_cliente, o.id_tienda, c.nombre_completo,
           c.telefono, c.codigo_cliente
    FROM public.app_dat_operacion_venta ov
    JOIN public.app_dat_operaciones o ON o.id = ov.id_operacion
    JOIN public.app_dat_clientes c ON c.id = ov.id_cliente
    WHERE ov.es_pagada = false
      AND ov.id_cliente IS NOT NULL
      AND ov.id_cliente_cxc IS NULL
  LOOP
    v_codigo := COALESCE(rec.codigo_cliente, 'CXC' || rec.id_cliente::text);

    INSERT INTO public.app_dat_cliente_cxc (id_tienda, codigo_cliente, nombre_completo, telefono)
    VALUES (rec.id_tienda, v_codigo, rec.nombre_completo, rec.telefono)
    ON CONFLICT (id_tienda, codigo_cliente) DO UPDATE
      SET nombre_completo = EXCLUDED.nombre_completo
    RETURNING id INTO v_id_cliente_cxc;

    UPDATE public.app_dat_operacion_venta
    SET id_cliente_cxc = v_id_cliente_cxc
    WHERE id_operacion = rec.id_operacion;
  END LOOP;
END $$;

-- ── 4. Encontrar-o-crear un cliente CxC de forma idempotente ───────────────
CREATE OR REPLACE FUNCTION public.fn_insertar_cliente_cxc(
  p_id_tienda bigint,
  p_codigo_cliente character varying,
  p_nombre_completo character varying,
  p_telefono character varying DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_id bigint;
BEGIN
  INSERT INTO public.app_dat_cliente_cxc (id_tienda, codigo_cliente, nombre_completo, telefono)
  VALUES (p_id_tienda, p_codigo_cliente, p_nombre_completo, p_telefono)
  ON CONFLICT (id_tienda, codigo_cliente) DO UPDATE
    SET nombre_completo = EXCLUDED.nombre_completo,
        telefono = COALESCE(EXCLUDED.telefono, public.app_dat_cliente_cxc.telefono),
        updated_at = now()
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('status', 'success', 'id_cliente_cxc', v_id);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('status', 'error', 'message', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_insertar_cliente_cxc(bigint, character varying, character varying, character varying) TO authenticated;

-- ── 4b. La liquidación (recibo de cobro) también pasa a referenciar al
--        cliente CxC independiente en vez de app_dat_clientes ─────────────
ALTER TABLE public.app_dat_liquidacion_cxc
  ALTER COLUMN id_cliente DROP NOT NULL;

ALTER TABLE public.app_dat_liquidacion_cxc
  ADD COLUMN IF NOT EXISTS id_cliente_cxc bigint
    REFERENCES public.app_dat_cliente_cxc(id);

COMMENT ON COLUMN public.app_dat_liquidacion_cxc.id_cliente IS
  'DEPRECADO: reemplazado por id_cliente_cxc. Se mantiene solo por histórico.';

-- ── 5. Re-apuntar las funciones de Cuentas por Cobrar a la tabla nueva ─────
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
  WHERE ov.id_cliente_cxc = p_id_cliente
    AND ov.es_pagada = false;
$$;

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
  JOIN public.app_dat_cliente_cxc c ON c.id = ov.id_cliente_cxc
  LEFT JOIN LATERAL (
    SELECT SUM(pv.monto) AS abonado
    FROM public.app_dat_pago_venta pv
    WHERE pv.id_operacion_venta = ov.id_operacion
  ) pv ON true
  WHERE c.id_tienda = p_id_tienda
    AND ov.es_pagada = false
    AND ov.id_cliente_cxc IS NOT NULL
  GROUP BY c.id, c.nombre_completo, c.telefono, c.codigo_cliente, c.bloqueado_cxc
  HAVING SUM(ov.importe_total - COALESCE(pv.abonado, 0)) > 0
  ORDER BY saldo_pendiente DESC;
$$;

GRANT EXECUTE ON FUNCTION public.fn_cxc_listar_clientes(bigint) TO authenticated;

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
  WHERE ov.id_cliente_cxc = p_id_cliente
  ORDER BY o.created_at DESC;
$$;

GRANT EXECUTE ON FUNCTION public.fn_cxc_historial_cliente(bigint) TO authenticated;

-- El tipo de retorno cambia de void (migración 10) a jsonb, así que hace
-- falta DROP explícito: CREATE OR REPLACE no permite cambiar el tipo de
-- retorno de una función existente.
DROP FUNCTION IF EXISTS public.fn_cxc_set_bloqueo_cliente(bigint, boolean);
CREATE FUNCTION public.fn_cxc_set_bloqueo_cliente(
  p_id_cliente bigint,
  p_bloqueado boolean
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.app_dat_cliente_cxc
  SET bloqueado_cxc = p_bloqueado, updated_at = now()
  WHERE id = p_id_cliente;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Cliente no encontrado');
  END IF;

  RETURN jsonb_build_object('status', 'success');
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('status', 'error', 'message', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_cxc_set_bloqueo_cliente(bigint, boolean) TO authenticated;

-- ── 5b. Registrar liquidación (cobro) usando el cliente CxC independiente ──
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
    id_cliente_cxc, id_tienda, monto_total, id_medio_pago,
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
      WHERE ov.id_cliente_cxc = p_id_cliente
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

GRANT EXECUTE ON FUNCTION public.fn_cxc_registrar_liquidacion(bigint, bigint, numeric, smallint, character varying, uuid, text, jsonb) TO authenticated;

-- ── 6. app_dat_clientes.bloqueado_cxc queda en desuso ──────────────────────
-- No se elimina para no perder datos ya escritos, pero el flujo de negocio
-- de CxC pasa a usar exclusivamente app_dat_cliente_cxc.bloqueado_cxc.
COMMENT ON COLUMN public.app_dat_clientes.bloqueado_cxc IS
  'DEPRECADO: reemplazado por app_dat_cliente_cxc.bloqueado_cxc. Se mantiene la columna solo para no perder el histórico.';
