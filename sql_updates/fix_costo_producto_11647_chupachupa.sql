-- =============================================================================
-- Corrección de costo: producto 11647 (Chupachupa) — tienda 174 — MAIN
-- =============================================================================
-- Objetivo: dejar el costo como si SIEMPRE hubiese sido 70 CUP.
--
--   70 CUP ÷ tasa 900 = 0.0778 USD
--
-- Qué corrige:
--   1. precio_promedio actual (presentación base id 11918)
--   2. historial app_dat_precio_costo (reportes de margen usan created_at)
--   3. líneas de recepción con precio 70 USD erróneo → 0.0778 USD
--
-- Qué NO toca: inventario / cantidades (ajuste aparte de administración).
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 0) Snapshot antes
-- ---------------------------------------------------------------------------
SELECT 'ANTES presentacion' AS etapa, id, precio_promedio
FROM public.app_dat_producto_presentacion
WHERE id_producto = 11647;

SELECT 'ANTES historial' AS etapa, id, precio_costo_usd, precio_costo_anterior, origen, created_at
FROM public.app_dat_precio_costo
WHERE id_producto = 11647
ORDER BY created_at;

SELECT 'ANTES recepcion' AS etapa, rp.id, rp.id_operacion, rp.cantidad, rp.precio_unitario,
       ore.moneda_factura, ore.monto_total
FROM public.app_dat_recepcion_productos rp
LEFT JOIN public.app_dat_operacion_recepcion ore ON ore.id_operacion = rp.id_operacion
WHERE rp.id_producto = 11647
ORDER BY rp.created_at;

-- ---------------------------------------------------------------------------
-- 1) Evitar filas fantasma del trigger mientras reescribimos el historial
-- ---------------------------------------------------------------------------
ALTER TABLE public.app_dat_producto_presentacion
  DISABLE TRIGGER trg_registrar_precio_costo;

-- ---------------------------------------------------------------------------
-- 2) Costo promedio actual = 70 CUP en USD
-- ---------------------------------------------------------------------------
UPDATE public.app_dat_producto_presentacion
SET precio_promedio = 0.0778
WHERE id = 11918
  AND id_producto = 11647;

-- ---------------------------------------------------------------------------
-- 3) Historial: una sola fila desde el alta del producto, siempre 0.0778
--    (así ventas/reportes as-of ven 70 CUP desde el principio)
-- ---------------------------------------------------------------------------
DELETE FROM public.app_dat_precio_costo
WHERE id_producto = 11647;

INSERT INTO public.app_dat_precio_costo (
  id_producto,
  id_presentacion,
  precio_costo_usd,
  precio_costo_anterior,
  origen,
  created_at
)
SELECT
  11647,
  11918,
  0.0778,
  NULL,
  'insert',
  p.created_at
FROM public.app_dat_producto p
WHERE p.id = 11647;

-- ---------------------------------------------------------------------------
-- 4) Recepción(es) con 70.00 mal marcado como USD → equivalente 70 CUP
-- ---------------------------------------------------------------------------
UPDATE public.app_dat_recepcion_productos rp
SET precio_unitario = 0.0778
WHERE rp.id_producto = 11647
  AND rp.precio_unitario = 70;

UPDATE public.app_dat_operacion_recepcion ore
SET monto_total = sub.nuevo_monto
FROM (
  SELECT rp.id_operacion,
         ROUND(SUM(rp.cantidad * rp.precio_unitario)::numeric, 4) AS nuevo_monto
  FROM public.app_dat_recepcion_productos rp
  WHERE rp.id_producto = 11647
  GROUP BY rp.id_operacion
) sub
WHERE ore.id_operacion = sub.id_operacion
  AND ore.id_operacion IN (
    SELECT DISTINCT id_operacion
    FROM public.app_dat_recepcion_productos
    WHERE id_producto = 11647
  );

-- ---------------------------------------------------------------------------
-- 5) Reactivar trigger
-- ---------------------------------------------------------------------------
ALTER TABLE public.app_dat_producto_presentacion
  ENABLE TRIGGER trg_registrar_precio_costo;

-- ---------------------------------------------------------------------------
-- 6) Snapshot después
-- ---------------------------------------------------------------------------
SELECT 'DESPUES presentacion' AS etapa, id, precio_promedio
FROM public.app_dat_producto_presentacion
WHERE id_producto = 11647;

SELECT 'DESPUES historial' AS etapa, id, precio_costo_usd, precio_costo_anterior, origen, created_at
FROM public.app_dat_precio_costo
WHERE id_producto = 11647
ORDER BY created_at;

SELECT 'DESPUES recepcion' AS etapa, rp.id, rp.id_operacion, rp.cantidad, rp.precio_unitario,
       ore.moneda_factura, ore.monto_total
FROM public.app_dat_recepcion_productos rp
LEFT JOIN public.app_dat_operacion_recepcion ore ON ore.id_operacion = rp.id_operacion
WHERE rp.id_producto = 11647
ORDER BY rp.created_at;

COMMIT;
