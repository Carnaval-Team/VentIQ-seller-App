-- ============================================================================
-- 14_diagnostico_costos.sql — comparar sin recostear
--
-- Entorno: `newa` (qhprswhhfasrikhawjoz). NO aplicar en main.
-- Fecha: 2026-11-26 · Plan: docs/planes/fondo-inversion/15-plan-compras-costos.md
--
-- Decisión del dueño: NO se reescribe ningún costo histórico. Para poder
-- comparar antes/después se expone una vista de solo lectura con:
--   · el precio promedio vigente del producto (presentación base),
--   · el último costo de factura recibido,
--   · el precio de venta CUP vigente,
--   · cuántas veces el promedio supera la factura,
--   · una marca `sospechoso` cuando lo supera por 10×.
--
-- No escribe ni corrige nada.
-- ============================================================================

CREATE OR REPLACE VIEW public.app_v_diagnostico_costo_producto AS
WITH base AS (
    SELECT DISTINCT ON (pp.id_producto)
           pp.id_producto,
           pp.id AS id_presentacion,
           COALESCE(pp.precio_promedio, 0) AS precio_promedio
      FROM public.app_dat_producto_presentacion pp
     WHERE pp.es_base IS TRUE
     ORDER BY pp.id_producto, pp.id
),
ultima AS (
    SELECT DISTINCT ON (rp.id_producto)
           rp.id_producto,
           rp.precio_unitario AS ultimo_costo_factura,
           rp.created_at      AS ultima_recepcion
      FROM public.app_dat_recepcion_productos rp
     ORDER BY rp.id_producto, rp.id DESC
),
venta AS (
    SELECT DISTINCT ON (v.id_producto)
           v.id_producto,
           v.precio_venta_cup
      FROM public.app_v_precio_venta_base_vigente v
     WHERE v.id_variante IS NULL
     ORDER BY v.id_producto, v.id DESC
)
SELECT p.id           AS id_producto,
       p.id_tienda,
       p.denominacion,
       b.precio_promedio,
       u.ultimo_costo_factura,
       u.ultima_recepcion,
       v.precio_venta_cup,
       CASE WHEN COALESCE(u.ultimo_costo_factura, 0) > 0
            THEN round((b.precio_promedio::numeric) / u.ultimo_costo_factura, 2) END
           AS veces_factura,
       (COALESCE(u.ultimo_costo_factura, 0) > 0
        AND b.precio_promedio::numeric > 10 * u.ultimo_costo_factura) AS sospechoso
  FROM public.app_dat_producto p
  LEFT JOIN base b   ON b.id_producto = p.id
  LEFT JOIN ultima u ON u.id_producto = p.id
  LEFT JOIN venta v  ON v.id_producto = p.id;

COMMENT ON VIEW public.app_v_diagnostico_costo_producto IS
    'Solo lectura: promedio vs última factura vs precio de venta. No corrige nada.';

GRANT SELECT ON public.app_v_diagnostico_costo_producto TO authenticated, service_role;
REVOKE ALL ON public.app_v_diagnostico_costo_producto FROM anon;

NOTIFY pgrst, 'reload schema';
