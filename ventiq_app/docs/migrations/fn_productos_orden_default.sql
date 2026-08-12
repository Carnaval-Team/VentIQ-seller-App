-- Productos por defecto en orden (por usuario auth + tienda)
-- Aplicar en Supabase SQL Editor.

CREATE TABLE IF NOT EXISTS public.app_dat_vendedor_productos_default (
  id            bigserial PRIMARY KEY,
  uuid          uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  id_tienda     bigint NOT NULL REFERENCES public.app_dat_tienda(id),
  id_producto   bigint NOT NULL REFERENCES public.app_dat_producto(id),
  cantidad      numeric NOT NULL DEFAULT 1 CHECK (cantidad > 0),
  orden         int NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_vendedor_productos_default
    UNIQUE (uuid, id_tienda, id_producto)
);

CREATE INDEX IF NOT EXISTS idx_vpd_uuid_tienda
  ON public.app_dat_vendedor_productos_default (uuid, id_tienda);

CREATE INDEX IF NOT EXISTS idx_vpd_tienda_producto
  ON public.app_dat_vendedor_productos_default (id_tienda, id_producto);

COMMENT ON TABLE public.app_dat_vendedor_productos_default IS
  'Productos por defecto al crear una orden: por usuario (auth.uid) + tienda.';

ALTER TABLE public.app_dat_vendedor_productos_default ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS vpd_select_own ON public.app_dat_vendedor_productos_default;
CREATE POLICY vpd_select_own
  ON public.app_dat_vendedor_productos_default
  FOR SELECT TO authenticated
  USING (uuid = auth.uid());

DROP POLICY IF EXISTS vpd_insert_own ON public.app_dat_vendedor_productos_default;
CREATE POLICY vpd_insert_own
  ON public.app_dat_vendedor_productos_default
  FOR INSERT TO authenticated
  WITH CHECK (uuid = auth.uid());

DROP POLICY IF EXISTS vpd_update_own ON public.app_dat_vendedor_productos_default;
CREATE POLICY vpd_update_own
  ON public.app_dat_vendedor_productos_default
  FOR UPDATE TO authenticated
  USING (uuid = auth.uid())
  WITH CHECK (uuid = auth.uid());

DROP POLICY IF EXISTS vpd_delete_own ON public.app_dat_vendedor_productos_default;
CREATE POLICY vpd_delete_own
  ON public.app_dat_vendedor_productos_default
  FOR DELETE TO authenticated
  USING (uuid = auth.uid());

-- ---------------------------------------------------------------------------
-- GET: lista del usuario actual para una tienda (+ datos mínimos de producto)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_get_productos_orden_default(
  p_id_tienda bigint
)
RETURNS TABLE (
  id_producto bigint,
  cantidad numeric,
  orden int,
  denominacion text,
  sku text,
  imagen text,
  precio_venta numeric,
  es_vendible boolean,
  es_elaborado boolean,
  es_servicio boolean,
  es_paquete boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;
  IF p_id_tienda IS NULL THEN
    RAISE EXCEPTION 'id_tienda requerido';
  END IF;

  RETURN QUERY
  SELECT
    d.id_producto,
    d.cantidad,
    d.orden,
    p.denominacion::text,
    p.sku::text,
    p.imagen::text,
    COALESCE(pv.precio_venta_cup, 0)::numeric AS precio_venta,
    COALESCE(p.es_vendible, true) AS es_vendible,
    COALESCE(p.es_elaborado, false) AS es_elaborado,
    COALESCE(p.es_servicio, false) AS es_servicio,
    COALESCE(p.es_paquete, false) AS es_paquete
  FROM public.app_dat_vendedor_productos_default d
  JOIN public.app_dat_producto p ON p.id = d.id_producto
  LEFT JOIN LATERAL (
    SELECT pv0.precio_venta_cup
    FROM public.app_dat_precio_venta pv0
    WHERE pv0.id_producto = d.id_producto
      AND (pv0.fecha_hasta IS NULL OR pv0.fecha_hasta >= CURRENT_DATE)
      AND (pv0.fecha_desde IS NULL OR pv0.fecha_desde <= CURRENT_DATE)
    ORDER BY pv0.fecha_desde DESC NULLS LAST, pv0.id DESC
    LIMIT 1
  ) pv ON TRUE
  WHERE d.uuid = v_uid
    AND d.id_tienda = p_id_tienda
  ORDER BY d.orden ASC, d.id ASC;
END;
$$;

COMMENT ON FUNCTION public.fn_get_productos_orden_default(bigint) IS
  'Productos por defecto del usuario autenticado para una tienda.';

-- ---------------------------------------------------------------------------
-- SET: replace-all atómico para usuario actual + tienda
-- p_items: [{ "id_producto": 1, "cantidad": 2, "orden": 0 }, ...]
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_set_productos_orden_default(
  p_id_tienda bigint,
  p_items jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_item jsonb;
  v_orden int := 0;
  v_count int := 0;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;
  IF p_id_tienda IS NULL THEN
    RAISE EXCEPTION 'id_tienda requerido';
  END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RAISE EXCEPTION 'p_items debe ser un array JSON';
  END IF;

  DELETE FROM public.app_dat_vendedor_productos_default
  WHERE uuid = v_uid
    AND id_tienda = p_id_tienda;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO public.app_dat_vendedor_productos_default (
      uuid, id_tienda, id_producto, cantidad, orden, updated_at
    ) VALUES (
      v_uid,
      p_id_tienda,
      (v_item->>'id_producto')::bigint,
      COALESCE((v_item->>'cantidad')::numeric, 1),
      COALESCE((v_item->>'orden')::int, v_orden),
      now()
    )
    ON CONFLICT (uuid, id_tienda, id_producto) DO UPDATE
      SET cantidad = EXCLUDED.cantidad,
          orden = EXCLUDED.orden,
          updated_at = now();

    v_orden := v_orden + 1;
    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'count', v_count,
    'id_tienda', p_id_tienda
  );
END;
$$;

COMMENT ON FUNCTION public.fn_set_productos_orden_default(bigint, jsonb) IS
  'Reemplaza los productos por defecto del usuario autenticado para una tienda.';

GRANT EXECUTE ON FUNCTION public.fn_get_productos_orden_default(bigint)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_set_productos_orden_default(bigint, jsonb)
  TO authenticated, service_role;
