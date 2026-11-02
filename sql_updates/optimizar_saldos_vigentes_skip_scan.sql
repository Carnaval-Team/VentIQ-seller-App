-- =============================================================================
-- Saldos vigentes por "skip scan" (corrige timeouts en ventas de elaborados)
-- =============================================================================
-- Causa (Main, 2026-10-29): una venta de 2 pizzas + 1 café (TPV 124) murió por
-- statement_timeout (8s). Cada ingrediente tiene 5–8k filas de ledger y la
-- validación/consumo de la receta llama a fn_ingrediente_base_alcanzable, que
-- a su vez llama 3 veces a fn_stock_saldos_presentacion. Esa función ordenaba
-- TODO el historial del producto para quedarse con la última fila por
-- combinación: ~80 ms por llamada. 9 ingredientes × 3 llamadas × varias pasadas
-- (validar + consumir) × 2 pizzas  →  > 8 s.
--
-- Solución: leer solo la última fila de cada combinación
-- (variante, opción, presentación, ubicación) saltando por el índice existente
-- idx_inv_prod_combo con una CTE recursiva. Medido: 79 ms → 0,3 ms.
--
-- Semántica: idéntica a la versión anterior.
--   * fn_stock_producto_almacen_detalle: nunca distinguió lotes; el skip scan
--     es equivalente exacto.
--   * fn_stock_saldos_presentacion: distingue lotes. Si el producto tiene filas
--     con id_lote se usa la consulta original sin cambios; si no, el skip scan
--     (sin lotes, la clave COALESCE(id_lote,0) es constante y ambas coinciden).
--
-- Misma firma, mismo RETURNS TABLE, CREATE OR REPLACE conserva permisos.
-- =============================================================================


-- ── PASO 1 · Ejecutar SOLO (CONCURRENTLY no admite transacción) ─────────────
-- Índice parcial para saber al instante si un producto maneja lotes.
-- En Main hoy hay 0 filas con lote: el índice es casi vacío.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_inv_prod_lote_producto
    ON public.app_dat_inventario_productos (id_producto)
    WHERE id_lote IS NOT NULL;


-- ── PASO 2 · Funciones ──────────────────────────────────────────────────────
BEGIN;

CREATE OR REPLACE FUNCTION public.fn_stock_producto_almacen_detalle(
    p_id_producto bigint,
    p_id_almacen  bigint DEFAULT NULL::bigint
)
RETURNS TABLE(
    id_ubicacion       bigint,
    id_almacen         bigint,
    id_variante        bigint,
    id_opcion_variante bigint,
    id_presentacion    bigint,
    cantidad_final     numeric,
    sku_producto       character varying,
    sku_ubicacion      character varying
)
LANGUAGE sql
STABLE
AS $function$
    -- Última fila (mayor id) por variante/opción/presentación/ubicación,
    -- recorriendo idx_inv_prod_combo de combinación en combinación.
    WITH RECURSIVE combos AS (
        (SELECT ip.id,
                COALESCE(ip.id_variante, 0)        AS v,
                COALESCE(ip.id_opcion_variante, 0) AS o,
                COALESCE(ip.id_presentacion, 0)    AS p,
                COALESCE(ip.id_ubicacion, 0)       AS u
           FROM public.app_dat_inventario_productos ip
          WHERE ip.id_producto = p_id_producto
          ORDER BY ip.id_producto,
                   COALESCE(ip.id_variante, 0),
                   COALESCE(ip.id_opcion_variante, 0),
                   COALESCE(ip.id_presentacion, 0),
                   COALESCE(ip.id_ubicacion, 0),
                   ip.id DESC
          LIMIT 1)
        UNION ALL
        SELECT n.id, n.v, n.o, n.p, n.u
          FROM combos c
          CROSS JOIN LATERAL (
              SELECT ip.id,
                     COALESCE(ip.id_variante, 0)        AS v,
                     COALESCE(ip.id_opcion_variante, 0) AS o,
                     COALESCE(ip.id_presentacion, 0)    AS p,
                     COALESCE(ip.id_ubicacion, 0)       AS u
                FROM public.app_dat_inventario_productos ip
               WHERE ip.id_producto = p_id_producto
                 AND (COALESCE(ip.id_variante, 0),
                      COALESCE(ip.id_opcion_variante, 0),
                      COALESCE(ip.id_presentacion, 0),
                      COALESCE(ip.id_ubicacion, 0)) > (c.v, c.o, c.p, c.u)
               ORDER BY ip.id_producto,
                        COALESCE(ip.id_variante, 0),
                        COALESCE(ip.id_opcion_variante, 0),
                        COALESCE(ip.id_presentacion, 0),
                        COALESCE(ip.id_ubicacion, 0),
                        ip.id DESC
               LIMIT 1
          ) n
    )
    SELECT ip.id_ubicacion,
           la.id_almacen,
           ip.id_variante,
           ip.id_opcion_variante,
           ip.id_presentacion,
           ip.cantidad_final,
           ip.sku_producto,
           ip.sku_ubicacion
      FROM combos c
      JOIN public.app_dat_inventario_productos ip ON ip.id = c.id
      JOIN public.app_dat_layout_almacen la      ON la.id = ip.id_ubicacion
     WHERE la.deleted_at IS NULL
       AND (p_id_almacen IS NULL OR la.id_almacen = p_id_almacen)
       AND COALESCE(ip.cantidad_final, 0) > 0
     ORDER BY ip.cantidad_final DESC, ip.id_ubicacion;
$function$;


CREATE OR REPLACE FUNCTION public.fn_stock_saldos_presentacion(
    p_id_producto  bigint,
    p_id_almacen   bigint  DEFAULT NULL::bigint,
    p_id_ubicacion bigint  DEFAULT NULL::bigint,
    p_incluir_cero boolean DEFAULT false
)
RETURNS TABLE(
    id_ubicacion        bigint,
    id_almacen          bigint,
    id_variante         bigint,
    id_opcion_variante  bigint,
    id_presentacion     bigint,
    presentacion_nombre character varying,
    sku_codigo          character varying,
    factor_rel          numeric,
    es_base             boolean,
    nivel               integer,
    saldo               numeric,
    equivalente_base    numeric,
    sku_producto        character varying,
    sku_ubicacion       character varying
)
LANGUAGE sql
STABLE
AS $function$
    WITH RECURSIVE
    -- Usa idx_inv_prod_lote_producto (parcial): respuesta inmediata.
    hay_lotes AS (
        SELECT EXISTS (
            SELECT 1
              FROM public.app_dat_inventario_productos x
             WHERE x.id_producto = p_id_producto
               AND x.id_lote IS NOT NULL
        ) AS hay
    ),
    -- Sin lotes: última fila por combinación saltando por idx_inv_prod_combo.
    combos AS (
        (SELECT ip.id,
                COALESCE(ip.id_variante, 0)        AS v,
                COALESCE(ip.id_opcion_variante, 0) AS o,
                COALESCE(ip.id_presentacion, 0)    AS p,
                COALESCE(ip.id_ubicacion, 0)       AS u
           FROM public.app_dat_inventario_productos ip
          WHERE ip.id_producto = p_id_producto
            AND NOT (SELECT hay FROM hay_lotes)
          ORDER BY ip.id_producto,
                   COALESCE(ip.id_variante, 0),
                   COALESCE(ip.id_opcion_variante, 0),
                   COALESCE(ip.id_presentacion, 0),
                   COALESCE(ip.id_ubicacion, 0),
                   ip.id DESC
          LIMIT 1)
        UNION ALL
        SELECT n.id, n.v, n.o, n.p, n.u
          FROM combos c
          CROSS JOIN LATERAL (
              SELECT ip.id,
                     COALESCE(ip.id_variante, 0)        AS v,
                     COALESCE(ip.id_opcion_variante, 0) AS o,
                     COALESCE(ip.id_presentacion, 0)    AS p,
                     COALESCE(ip.id_ubicacion, 0)       AS u
                FROM public.app_dat_inventario_productos ip
               WHERE ip.id_producto = p_id_producto
                 AND (COALESCE(ip.id_variante, 0),
                      COALESCE(ip.id_opcion_variante, 0),
                      COALESCE(ip.id_presentacion, 0),
                      COALESCE(ip.id_ubicacion, 0)) > (c.v, c.o, c.p, c.u)
               ORDER BY ip.id_producto,
                        COALESCE(ip.id_variante, 0),
                        COALESCE(ip.id_opcion_variante, 0),
                        COALESCE(ip.id_presentacion, 0),
                        COALESCE(ip.id_ubicacion, 0),
                        ip.id DESC
               LIMIT 1
          ) n
    ),
    vigente_lote AS (
        SELECT ip.id_ubicacion,
               la.id_almacen,
               ip.id_variante,
               ip.id_opcion_variante,
               ip.id_presentacion,
               ip.id_lote,
               COALESCE(ip.cantidad_final, 0) AS saldo,
               ip.sku_producto,
               ip.sku_ubicacion
          FROM combos c
          JOIN public.app_dat_inventario_productos ip ON ip.id = c.id
          JOIN public.app_dat_layout_almacen la      ON la.id = ip.id_ubicacion
         WHERE la.deleted_at IS NULL
           AND (p_id_ubicacion IS NULL OR ip.id_ubicacion = p_id_ubicacion)
           AND (p_id_almacen   IS NULL OR la.id_almacen   = p_id_almacen)
        UNION ALL
        -- Con lotes: consulta original, sin cambios.
        SELECT o.*
          FROM (
              SELECT DISTINCT ON (
                         ip.id_ubicacion,
                         COALESCE(ip.id_variante, 0),
                         COALESCE(ip.id_opcion_variante, 0),
                         ip.id_presentacion,
                         COALESCE(ip.id_lote, 0)
                     )
                     ip.id_ubicacion,
                     la.id_almacen,
                     ip.id_variante,
                     ip.id_opcion_variante,
                     ip.id_presentacion,
                     ip.id_lote,
                     COALESCE(ip.cantidad_final, 0) AS saldo,
                     ip.sku_producto,
                     ip.sku_ubicacion
                FROM public.app_dat_inventario_productos ip
                JOIN public.app_dat_layout_almacen la ON la.id = ip.id_ubicacion
               WHERE ip.id_producto = p_id_producto
                 AND la.deleted_at IS NULL
                 AND (p_id_ubicacion IS NULL OR ip.id_ubicacion = p_id_ubicacion)
                 AND (p_id_almacen   IS NULL OR la.id_almacen   = p_id_almacen)
               ORDER BY
                     ip.id_ubicacion,
                     COALESCE(ip.id_variante, 0),
                     COALESCE(ip.id_opcion_variante, 0),
                     ip.id_presentacion,
                     COALESCE(ip.id_lote, 0),
                     ip.id DESC
          ) o
         WHERE (SELECT hay FROM hay_lotes)
    ),
    vigente AS (
        SELECT
               v.id_ubicacion,
               v.id_almacen,
               v.id_variante,
               v.id_opcion_variante,
               v.id_presentacion,
               SUM(v.saldo) AS saldo,
               MIN(v.sku_producto) AS sku_producto,
               MIN(v.sku_ubicacion) AS sku_ubicacion
          FROM vigente_lote v
         GROUP BY
               v.id_ubicacion,
               v.id_almacen,
               v.id_variante,
               v.id_opcion_variante,
               v.id_presentacion
    )
    SELECT
        v.id_ubicacion,
        v.id_almacen,
        v.id_variante,
        v.id_opcion_variante,
        v.id_presentacion,
        c.nombre                        AS presentacion_nombre,
        c.sku_codigo,
        c.factor_rel,
        c.es_base,
        c.nivel,
        v.saldo,
        (v.saldo * COALESCE(c.factor_rel, 1)) AS equivalente_base,
        v.sku_producto,
        v.sku_ubicacion
      FROM vigente v
      LEFT JOIN public.fn_presentaciones_producto(p_id_producto) c
             ON c.id_presentacion = v.id_presentacion
     WHERE p_incluir_cero OR v.saldo <> 0
     ORDER BY v.id_ubicacion, COALESCE(c.nivel, 999), v.id_presentacion;
$function$;

COMMIT;


-- ── Verificación ─────────────────────────────────────────────────────────────
-- 1) Índice creado y válido
SELECT indexrelid::regclass, indisvalid
  FROM pg_index
 WHERE indexrelid = 'public.idx_inv_prod_lote_producto'::regclass;

-- 2) Tiempo con el producto de más historial (antes ~80 ms)
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM public.fn_stock_saldos_presentacion(10329, NULL, NULL, false);
