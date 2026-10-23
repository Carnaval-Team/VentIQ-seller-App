-- ============================================================================
-- 05 · Lotes — bulk_import persiste es_por_lotes + dias_alert_caducidad
-- ============================================================================
-- Plan: docs/PLAN_VENCIMIENTOS_LOTES.md  (Fase 7)
-- Basado en SQL_OPTIMIZATION/bulk_import_productos_excel.sql + flags de lote.
-- Prerrequisito: 01 en newa. NO aplicar en main hasta cerrar el proyecto.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.bulk_import_productos_excel(
    p_id_tienda BIGINT,
    p_productos JSONB[]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_producto JSONB;
    v_producto_existente RECORD;
    v_id_proveedor BIGINT;
    v_id_producto BIGINT;
    v_resultado JSONB;
    v_mapeo JSONB := '{}'::JSONB;
    v_insertados INT := 0;
    v_actualizados INT := 0;
    v_errores JSONB := '[]'::JSONB;
    v_denominacion TEXT;
    v_nombre_proveedor TEXT;
    v_insert_result JSONB;
    v_producto_data JSONB;
    v_precios_data JSONB[];
    v_presentaciones_data JSONB[];
    v_subcategorias_data JSONB[];
BEGIN
    RAISE NOTICE '📦 Iniciando importación masiva de % productos para tienda %',
      array_length(p_productos, 1), p_id_tienda;

    FOR v_producto IN SELECT * FROM unnest(p_productos)
    LOOP
        BEGIN
            v_denominacion := v_producto->>'denominacion';
            RAISE NOTICE '🔍 Procesando: %', v_denominacion;

            SELECT id INTO v_producto_existente
            FROM app_dat_producto
            WHERE id_tienda = p_id_tienda
              AND denominacion = v_denominacion
            LIMIT 1;

            IF FOUND THEN
                v_id_producto := v_producto_existente.id;
                RAISE NOTICE '   ♻️ Producto existente ID: %', v_id_producto;

                IF v_producto->>'precio_costo_usd' IS NOT NULL AND
                   (v_producto->>'precio_costo_usd')::NUMERIC > 0 THEN
                    UPDATE app_dat_producto_presentacion
                    SET precio_promedio = (v_producto->>'precio_costo_usd')::NUMERIC
                    WHERE id_producto = v_id_producto
                      AND id_presentacion = 1;
                    RAISE NOTICE '   💰 Precio de costo actualizado: $%',
                      (v_producto->>'precio_costo_usd')::NUMERIC;
                END IF;

                -- Flags de lote (Fase 7)
                IF (v_producto ? 'es_por_lotes') OR (v_producto ? 'dias_alert_caducidad') THEN
                  UPDATE app_dat_producto
                  SET
                    es_por_lotes = CASE
                      WHEN v_producto ? 'es_por_lotes'
                        THEN COALESCE((v_producto->>'es_por_lotes')::BOOLEAN, false)
                      ELSE es_por_lotes
                    END,
                    dias_alert_caducidad = CASE
                      WHEN v_producto ? 'dias_alert_caducidad'
                        THEN NULLIF(v_producto->>'dias_alert_caducidad', '')::NUMERIC
                      ELSE dias_alert_caducidad
                    END
                  WHERE id = v_id_producto;
                END IF;

                v_actualizados := v_actualizados + 1;

            ELSE
                v_id_proveedor := NULL;
                v_nombre_proveedor := v_producto->>'nombre_proveedor';

                IF v_nombre_proveedor IS NOT NULL AND v_nombre_proveedor != '' THEN
                    SELECT id INTO v_id_proveedor
                    FROM app_dat_proveedor
                    WHERE idtienda = p_id_tienda
                      AND denominacion ILIKE '%' || v_nombre_proveedor || '%'
                    LIMIT 1;

                    IF FOUND THEN
                        RAISE NOTICE '   📦 Proveedor encontrado: ID=%', v_id_proveedor;
                    ELSE
                        INSERT INTO app_dat_proveedor (
                            denominacion, sku_codigo, idtienda
                        ) VALUES (
                            v_nombre_proveedor,
                            'P' || p_id_tienda || '-' ||
                                UPPER(LEFT(REGEXP_REPLACE(v_nombre_proveedor, '[^A-Za-z0-9]', '', 'g'), 6)) ||
                                RIGHT(EXTRACT(EPOCH FROM now())::BIGINT::TEXT, 6),
                            p_id_tienda
                        ) RETURNING id INTO v_id_proveedor;
                        RAISE NOTICE '   🆕 Proveedor creado: "%" (ID=%)',
                          v_nombre_proveedor, v_id_proveedor;
                    END IF;
                END IF;

                v_producto_data := jsonb_build_object(
                    'id_tienda', p_id_tienda,
                    'sku', v_producto->>'sku',
                    'id_categoria', (v_producto->>'id_categoria')::BIGINT,
                    'denominacion', v_denominacion,
                    'descripcion', COALESCE(v_producto->>'descripcion', v_denominacion),
                    'denominacion_corta', v_producto->>'denominacion_corta',
                    'nombre_comercial', v_producto->>'nombre_comercial',
                    'codigo_barras', v_producto->>'codigo_barras',
                    'um', v_producto->>'um',
                    'es_refrigerado', COALESCE((v_producto->>'es_refrigerado')::BOOLEAN, false),
                    'es_fragil', COALESCE((v_producto->>'es_fragil')::BOOLEAN, false),
                    'es_peligroso', COALESCE((v_producto->>'es_peligroso')::BOOLEAN, false),
                    'es_vendible', COALESCE((v_producto->>'es_vendible')::BOOLEAN, true),
                    'es_comprable', COALESCE((v_producto->>'es_comprable')::BOOLEAN, true),
                    'es_inventariable', COALESCE((v_producto->>'es_inventariable')::BOOLEAN, true),
                    'es_servicio', COALESCE((v_producto->>'es_servicio')::BOOLEAN, false),
                    'es_por_lotes', COALESCE((v_producto->>'es_por_lotes')::BOOLEAN, false),
                    'dias_alert_caducidad',
                      NULLIF(v_producto->>'dias_alert_caducidad', '')::NUMERIC,
                    'id_proveedor', v_id_proveedor
                );

                v_precios_data := NULL;
                IF (v_producto->>'precio_venta_cup' IS NOT NULL AND
                    (v_producto->>'precio_venta_cup')::NUMERIC > 0) OR
                   (v_producto->>'precio_venta_usd' IS NOT NULL AND
                    (v_producto->>'precio_venta_usd')::NUMERIC > 0) THEN
                    v_precios_data := ARRAY[jsonb_build_object(
                        'precio_venta_cup', COALESCE((v_producto->>'precio_venta_cup')::NUMERIC, 0),
                        'precio_venta_usd', (v_producto->>'precio_venta_usd')::NUMERIC,
                        'fecha_desde', CURRENT_DATE
                    )];
                END IF;

                IF v_producto->>'precio_costo_usd' IS NOT NULL AND
                   (v_producto->>'precio_costo_usd')::NUMERIC > 0 THEN
                    v_presentaciones_data := ARRAY[jsonb_build_object(
                        'id_presentacion', 1,
                        'cantidad', 1.0,
                        'es_base', true,
                        'precio_promedio', (v_producto->>'precio_costo_usd')::NUMERIC
                    )];
                ELSE
                    v_presentaciones_data := ARRAY[jsonb_build_object(
                        'id_presentacion', 1,
                        'cantidad', 1.0,
                        'es_base', true
                    )];
                END IF;

                v_subcategorias_data := NULL;
                IF v_producto->>'id_categoria' IS NOT NULL THEN
                    v_subcategorias_data := ARRAY[jsonb_build_object(
                        'id_sub_categoria', (v_producto->>'id_categoria')::BIGINT
                    )];
                END IF;

                v_insert_result := insert_producto_completo_v3(
                    v_producto_data,
                    v_subcategorias_data,
                    v_presentaciones_data,
                    NULL,
                    NULL,
                    NULL,
                    v_precios_data
                );

                IF (v_insert_result->>'success')::BOOLEAN = true THEN
                    v_id_producto := (v_insert_result->>'id_producto')::BIGINT;
                    v_insertados := v_insertados + 1;
                    RAISE NOTICE '   ✅ Producto insertado: ID=%', v_id_producto;
                ELSE
                    RAISE EXCEPTION 'Error insertando producto: %',
                      v_insert_result->>'message';
                END IF;
            END IF;

            v_mapeo := jsonb_set(
                v_mapeo,
                ARRAY[v_denominacion],
                to_jsonb(v_id_producto)
            );

        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE '   ❌ Error procesando "%": %', v_denominacion, SQLERRM;
            v_errores := v_errores || jsonb_build_object(
                'denominacion', v_denominacion,
                'error', SQLERRM,
                'sqlstate', SQLSTATE
            );
        END;
    END LOOP;

    v_resultado := jsonb_build_object(
        'success', true,
        'productos_insertados', v_insertados,
        'productos_actualizados', v_actualizados,
        'total_procesados', v_insertados + v_actualizados,
        'mapeo', v_mapeo,
        'errores', v_errores
    );

    RAISE NOTICE '✅ Importación completada: % insertados, % actualizados',
      v_insertados, v_actualizados;

    RETURN v_resultado;

EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '❌ Error crítico en importación masiva: %', SQLERRM;
    RETURN jsonb_build_object(
        'success', false,
        'message', 'Error en importación masiva: ' || SQLERRM,
        'error_code', SQLSTATE,
        'productos_insertados', v_insertados,
        'productos_actualizados', v_actualizados,
        'mapeo', v_mapeo,
        'errores', v_errores
    );
END;
$$;

COMMENT ON FUNCTION public.bulk_import_productos_excel(BIGINT, JSONB[]) IS
'Importa productos masivamente desde Excel; persiste es_por_lotes y dias_alert_caducidad (Fase 7 lotes).';

GRANT EXECUTE ON FUNCTION public.bulk_import_productos_excel(BIGINT, JSONB[])
  TO authenticated, service_role;
