BEGIN;

LOCK TABLE public.app_dat_inventario_productos IN SHARE ROW EXCLUSIVE MODE;

CREATE TEMP TABLE tmp_transferencias_hoy_sin_entrada
ON COMMIT DROP
AS
SELECT
  t.id_operacion AS id_transferencia,
  t.id_extraccion,
  t.id_recepcion,
  o.created_at AS fecha_transferencia,
  rp.id AS id_recepcion_producto,
  rp.id_producto,
  rp.id_variante,
  rp.id_opcion_variante,
  rp.id_ubicacion,
  rp.id_presentacion,
  rp.cantidad,
  rp.sku_producto,
  rp.sku_ubicacion
FROM public.app_dat_operacion_transferencia t
JOIN public.app_dat_operaciones o
  ON o.id = t.id_operacion
JOIN public.app_dat_recepcion_productos rp
  ON rp.id_operacion = t.id_recepcion
WHERE (o.created_at AT TIME ZONE 'America/Havana')::DATE =
      (CURRENT_TIMESTAMP AT TIME ZONE 'America/Havana')::DATE
  AND EXISTS (
    SELECT 1
    FROM public.app_dat_estado_operacion eo
    WHERE eo.id_operacion = t.id_recepcion
      AND eo.estado = 2
  )
  AND NOT EXISTS (
    SELECT 1
    FROM public.app_dat_inventario_productos ip
    WHERE ip.id_recepcion = rp.id
  );

DO $repair$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM tmp_transferencias_hoy_sin_entrada
    WHERE id_ubicacion IS NULL
  ) THEN
    RAISE EXCEPTION 'Hay recepciones de transferencia sin ubicación destino; no se realizó ninguna corrección';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM tmp_transferencias_hoy_sin_entrada
    WHERE cantidad IS NULL OR cantidad <= 0
  ) THEN
    RAISE EXCEPTION 'Hay recepciones de transferencia con cantidad inválida; no se realizó ninguna corrección';
  END IF;
END;
$repair$;

WITH movimientos AS (
  SELECT
    r.*,
    COALESCE(saldo.cantidad_final, 0) AS saldo_anterior,
    COALESCE(
      SUM(r.cantidad) OVER (
        PARTITION BY
          r.id_producto,
          r.id_variante,
          r.id_opcion_variante,
          r.id_ubicacion,
          r.id_presentacion
        ORDER BY r.fecha_transferencia, r.id_recepcion_producto
        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
      ),
      0
    ) AS cantidad_previa_reparada
  FROM tmp_transferencias_hoy_sin_entrada r
  LEFT JOIN LATERAL (
    SELECT ip.cantidad_final
    FROM public.app_dat_inventario_productos ip
    WHERE ip.id_producto = r.id_producto
      AND ip.id_variante IS NOT DISTINCT FROM r.id_variante
      AND ip.id_opcion_variante IS NOT DISTINCT FROM r.id_opcion_variante
      AND ip.id_ubicacion = r.id_ubicacion
      AND ip.id_presentacion IS NOT DISTINCT FROM r.id_presentacion
    ORDER BY ip.created_at DESC, ip.id DESC
    LIMIT 1
  ) saldo ON TRUE
)
INSERT INTO public.app_dat_inventario_productos (
  id_producto,
  id_variante,
  id_opcion_variante,
  id_ubicacion,
  id_presentacion,
  cantidad_inicial,
  cantidad_final,
  sku_producto,
  sku_ubicacion,
  origen_cambio,
  id_recepcion,
  id_extraccion,
  created_at
)
SELECT
  m.id_producto,
  m.id_variante,
  m.id_opcion_variante,
  m.id_ubicacion,
  m.id_presentacion,
  m.saldo_anterior + m.cantidad_previa_reparada,
  m.saldo_anterior + m.cantidad_previa_reparada + m.cantidad,
  m.sku_producto,
  m.sku_ubicacion,
  2,
  m.id_recepcion_producto,
  NULL,
  CURRENT_TIMESTAMP + (ROW_NUMBER() OVER (
    ORDER BY m.fecha_transferencia, m.id_recepcion_producto
  ) * INTERVAL '1 microsecond')
FROM movimientos m
WHERE NOT EXISTS (
  SELECT 1
  FROM public.app_dat_inventario_productos ip
  WHERE ip.id_recepcion = m.id_recepcion_producto
);

SELECT
  COUNT(*) AS movimientos_reparados,
  COALESCE(SUM(r.cantidad), 0) AS cantidad_total_repuesta
FROM tmp_transferencias_hoy_sin_entrada r
WHERE EXISTS (
  SELECT 1
  FROM public.app_dat_inventario_productos ip
  WHERE ip.id_recepcion = r.id_recepcion_producto
);

COMMIT;

SELECT
  t.id_operacion AS id_transferencia,
  t.id_extraccion,
  t.id_recepcion,
  rp.id AS id_recepcion_producto,
  rp.id_producto,
  rp.id_ubicacion AS id_layout_destino,
  rp.cantidad,
  ip.cantidad_inicial,
  ip.cantidad_final,
  ip.created_at AS fecha_movimiento_reparado
FROM public.app_dat_operacion_transferencia t
JOIN public.app_dat_operaciones o
  ON o.id = t.id_operacion
JOIN public.app_dat_recepcion_productos rp
  ON rp.id_operacion = t.id_recepcion
LEFT JOIN public.app_dat_inventario_productos ip
  ON ip.id_recepcion = rp.id
WHERE (o.created_at AT TIME ZONE 'America/Havana')::DATE =
      (CURRENT_TIMESTAMP AT TIME ZONE 'America/Havana')::DATE
ORDER BY o.created_at, rp.id;
