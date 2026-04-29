-- ============================================================
-- buscar_producto_por_codigo_barras_v3
-- ============================================================
-- Busca productos por código de barras con datos completos:
--   1. Match exacto en app_dat_producto.codigo_barras
--   2. Match exacto en app_dat_codigos_barras (múltiples códigos por producto)
--   3. Match exacto en codigo_producto (tabla nueva con desglose)
--   4. Similitud por fabricante (mismo codigo_fabricante en codigo_producto)
--
-- Retorna: producto completo con precio, stock, categoría, presentaciones,
--          variantes, y productos similares por fabricante.
-- ============================================================

CREATE OR REPLACE FUNCTION buscar_producto_por_codigo_barras_v3(
    p_barcode TEXT
) RETURNS jsonb AS $$
DECLARE
    v_producto_id BIGINT;
    v_tienda_id BIGINT;
    v_codigo_fabricante TEXT;
    v_prefijo_pais TEXT;
    resultado jsonb;
BEGIN

    -- ═══════════════════════════════════════════════════════
    -- PASO 1: Buscar match exacto
    -- ═══════════════════════════════════════════════════════

    -- 1a. Buscar en app_dat_producto.codigo_barras
    SELECT id, id_tienda INTO v_producto_id, v_tienda_id
    FROM app_dat_producto
    WHERE codigo_barras = p_barcode
    LIMIT 1;

    -- 1b. Si no encontró, buscar en app_dat_codigos_barras
    IF v_producto_id IS NULL THEN
        SELECT cb.id_producto, p.id_tienda INTO v_producto_id, v_tienda_id
        FROM app_dat_codigos_barras cb
        JOIN app_dat_producto p ON cb.id_producto = p.id
        WHERE cb.codigo_barras = p_barcode
        LIMIT 1;
    END IF;

    -- 1c. Si no encontró, buscar en codigo_producto
    IF v_producto_id IS NULL THEN
        SELECT cp.id_producto, p.id_tienda INTO v_producto_id, v_tienda_id
        FROM codigo_producto cp
        JOIN app_dat_producto p ON cp.id_producto = p.id
        WHERE cp.codigo_barras = p_barcode
        LIMIT 1;
    END IF;

    -- ═══════════════════════════════════════════════════════
    -- PASO 2: Extraer dígitos para búsqueda de similitud
    -- ═══════════════════════════════════════════════════════

    -- Intentar obtener el desglose del código de la tabla codigo_producto
    SELECT cp.codigo_fabricante, cp.prefijo_pais
    INTO v_codigo_fabricante, v_prefijo_pais
    FROM codigo_producto cp
    WHERE cp.codigo_barras = p_barcode
    LIMIT 1;

    -- Si no hay desglose guardado y es EAN-13, parsear en vivo
    IF v_codigo_fabricante IS NULL AND length(regexp_replace(p_barcode, '[^0-9]', '', 'g')) = 13 THEN
        v_prefijo_pais := substring(p_barcode from 1 for 3);
        v_codigo_fabricante := substring(p_barcode from 4 for 4);
    END IF;

    -- Si es UPC-A (12 dígitos), parsear en vivo
    IF v_codigo_fabricante IS NULL AND length(regexp_replace(p_barcode, '[^0-9]', '', 'g')) = 12 THEN
        v_prefijo_pais := '000';
        v_codigo_fabricante := substring(p_barcode from 2 for 5);
    END IF;

    -- ═══════════════════════════════════════════════════════
    -- PASO 3: Construir respuesta
    -- ═══════════════════════════════════════════════════════

    WITH
    -- Stock: último inventario por producto/variante/presentación/ubicación
    ultimo_inventario AS (
        SELECT DISTINCT ON (
            id_producto,
            COALESCE(id_variante, 0),
            COALESCE(id_opcion_variante, 0),
            COALESCE(id_presentacion, 0),
            COALESCE(id_ubicacion, 0)
        )
            id_producto,
            id_variante,
            id_opcion_variante,
            id_presentacion,
            id_ubicacion,
            cantidad_final,
            id_proveedor,
            created_at,
            id AS inventario_id
        FROM app_dat_inventario_productos
        ORDER BY id_producto, COALESCE(id_variante, 0), COALESCE(id_opcion_variante, 0),
                 COALESCE(id_presentacion, 0), COALESCE(id_ubicacion, 0), id DESC
    ),
    stock_productos AS (
        SELECT
            id_producto,
            ROUND(SUM(cantidad_final))::integer AS stock_total,
            SUM(cantidad_final) > 0 AS tiene_stock
        FROM ultimo_inventario
        GROUP BY id_producto
    ),
    -- Precio actual (sin variante = precio base)
    precios_actuales AS (
        SELECT DISTINCT ON (id_producto)
            id_producto,
            precio_venta_cup,
            precio_venta_usd
        FROM app_dat_precio_venta
        WHERE (id_variante IS NULL OR id_variante = 0)
          AND (fecha_hasta IS NULL OR fecha_hasta >= CURRENT_DATE)
        ORDER BY id_producto, fecha_desde DESC
    ),
    -- Producto exacto encontrado
    producto_exacto AS (
        SELECT
            p.id,
            p.sku,
            p.denominacion,
            p.nombre_comercial,
            p.descripcion,
            p.descripcion_corta,
            p.um,
            p.codigo_barras,
            p.imagen,
            p.es_refrigerado,
            p.es_fragil,
            p.es_peligroso,
            p.es_vendible,
            p.es_comprable,
            p.es_inventariable,
            p.es_por_lotes,
            p.es_elaborado,
            p.es_servicio,
            -- Categoría
            jsonb_build_object(
                'id', c.id,
                'denominacion', c.denominacion,
                'sku_codigo', c.sku_codigo
            ) AS categoria,
            -- Precio
            COALESCE(pa.precio_venta_cup, 0) AS precio_venta,
            COALESCE(pa.precio_venta_usd, 0) AS precio_venta_usd,
            -- Stock
            COALESCE(sp.stock_total, 0) AS stock_disponible,
            COALESCE(sp.tiene_stock, false) AS tiene_stock,
            -- Presentaciones
            COALESCE((
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', pp.id,
                        'presentacion', np.denominacion,
                        'cantidad', pp.cantidad,
                        'es_base', pp.es_base,
                        'sku_codigo', np.sku_codigo
                    )
                )
                FROM app_dat_producto_presentacion pp
                JOIN app_nom_presentacion np ON pp.id_presentacion = np.id
                WHERE pp.id_producto = p.id
            ), '[]'::jsonb) AS presentaciones,
            -- Subcategorías
            COALESCE((
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', sc.id,
                        'denominacion', sc.denominacion,
                        'sku_codigo', sc.sku_codigo
                    )
                )
                FROM app_dat_productos_subcategorias ps
                JOIN app_dat_subcategorias sc ON ps.id_sub_categoria = sc.id
                WHERE ps.id_producto = p.id
            ), '[]'::jsonb) AS subcategorias,
            -- Variantes con precios
            COALESCE((
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', v.id,
                        'atributo', jsonb_build_object(
                            'id', a.id,
                            'denominacion', a.denominacion,
                            'label', a.label
                        ),
                        'opcion', jsonb_build_object(
                            'id', ao.id,
                            'valor', ao.valor,
                            'sku_codigo', ao.sku_codigo
                        ),
                        'precio', pv.precio_venta_cup,
                        'stock', COALESCE((
                            SELECT ROUND(SUM(ui2.cantidad_final))::integer
                            FROM ultimo_inventario ui2
                            WHERE ui2.id_producto = p.id
                              AND ui2.id_variante = v.id
                        ), 0)
                    )
                )
                FROM app_dat_precio_venta pv
                JOIN app_dat_variantes v ON pv.id_variante = v.id
                JOIN app_dat_atributos a ON v.id_atributo = a.id
                LEFT JOIN app_dat_atributo_opcion ao ON ao.id_atributo = a.id
                WHERE pv.id_producto = p.id
                  AND pv.id_variante IS NOT NULL
                  AND (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= CURRENT_DATE)
            ), '[]'::jsonb) AS variantes,
            -- Proveedor
            CASE WHEN pr.id IS NOT NULL THEN
                jsonb_build_object(
                    'id', pr.id,
                    'denominacion', pr.denominacion
                )
            ELSE NULL END AS proveedor
        FROM app_dat_producto p
        JOIN app_dat_categoria c ON p.id_categoria = c.id
        LEFT JOIN stock_productos sp ON p.id = sp.id_producto
        LEFT JOIN precios_actuales pa ON p.id = pa.id_producto
        LEFT JOIN app_dat_proveedor pr ON p.id_proveedor = pr.id
        WHERE p.id = v_producto_id
    ),
    -- Productos similares (mismo fabricante, distinto producto)
    productos_similares AS (
        SELECT
            p.id,
            p.denominacion,
            p.nombre_comercial,
            p.imagen,
            COALESCE(pa.precio_venta_cup, 0) AS precio_venta,
            COALESCE(sp.stock_total, 0) AS stock_disponible,
            c.denominacion AS categoria_nombre
        FROM codigo_producto cp
        JOIN app_dat_producto p ON cp.id_producto = p.id
        JOIN app_dat_categoria c ON p.id_categoria = c.id
        LEFT JOIN stock_productos sp ON p.id = sp.id_producto
        LEFT JOIN precios_actuales pa ON p.id = pa.id_producto
        WHERE cp.codigo_fabricante = v_codigo_fabricante
          AND v_codigo_fabricante IS NOT NULL
          AND cp.id_producto != COALESCE(v_producto_id, 0)
          AND p.es_vendible = true
        GROUP BY p.id, p.denominacion, p.nombre_comercial, p.imagen,
                 pa.precio_venta_cup, sp.stock_total, c.denominacion
        LIMIT 10
    )
    -- Armar JSON final
    SELECT jsonb_build_object(
        'encontrado', v_producto_id IS NOT NULL,
        'codigo_barras', p_barcode,
        -- Desglose del código
        'desglose', jsonb_build_object(
            'prefijo_pais', v_prefijo_pais,
            'codigo_fabricante', v_codigo_fabricante,
            'codigo_producto', CASE
                WHEN length(regexp_replace(p_barcode, '[^0-9]', '', 'g')) = 13
                    THEN substring(p_barcode from 8 for 5)
                WHEN length(regexp_replace(p_barcode, '[^0-9]', '', 'g')) = 12
                    THEN substring(p_barcode from 7 for 5)
                ELSE NULL
            END,
            'digito_control', CASE
                WHEN length(regexp_replace(p_barcode, '[^0-9]', '', 'g')) IN (8, 12, 13)
                    THEN right(regexp_replace(p_barcode, '[^0-9]', '', 'g'), 1)
                ELSE NULL
            END
        ),
        -- Producto exacto (null si no se encontró)
        'producto', (SELECT row_to_json(pe)::jsonb FROM producto_exacto pe),
        -- Productos del mismo fabricante
        'similares', COALESCE(
            (SELECT jsonb_agg(
                jsonb_build_object(
                    'id', ps.id,
                    'denominacion', ps.denominacion,
                    'nombre_comercial', ps.nombre_comercial,
                    'imagen', ps.imagen,
                    'precio_venta', ps.precio_venta,
                    'stock_disponible', ps.stock_disponible,
                    'categoria', ps.categoria_nombre
                )
            ) FROM productos_similares ps),
            '[]'::jsonb
        ),
        'total_similares', (SELECT count(*) FROM productos_similares)
    ) INTO resultado;

    RETURN resultado;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
