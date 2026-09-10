-- ============================================================================
-- MIGRACIÓN: Pagos a Importadora (imp_*) → Pago a proveedores (prv_*)
--
-- Requisitos previos:
--   1) Ejecutar pago_proveedores_schema.sql
--   2) Completar v_nombre_proveedor abajo (nombre que verás en el selector)
--
-- Qué hace:
--   - Por cada tienda con datos en Importadora, crea (o reutiliza) un
--     proveedor en app_dat_proveedor con ese nombre.
--   - Copia saldo, recargas, historial de saldo, estados, facturas,
--     fotos e historial de estados a prv_*.
--   - NO borra ni modifica imp_* (Importadora sigue intacta).
--
-- Idempotente: se puede re-ejecutar; no duplica facturas ya migradas
-- (columna temporal id_imp_origen).
-- ============================================================================

DO $$
DECLARE
    -- >>> EDITAR: nombre del proveedor destino (ej. 'Importadora XYZ') <<<
    v_nombre_proveedor TEXT := 'Pucara';
    v_moneda_codigo    TEXT := 'USD';  -- moneda por defecto del módulo

    v_id_moneda        BIGINT;
    v_tienda           INTEGER;
    v_id_proveedor     BIGINT;
    v_sku              TEXT;
    v_facturas_ins     INTEGER := 0;
    v_recargas_ins     INTEGER := 0;
    v_tiendas          INTEGER := 0;
BEGIN
    IF v_nombre_proveedor IS NULL
       OR btrim(v_nombre_proveedor) = ''
       OR upper(btrim(v_nombre_proveedor)) = 'NOMBRE_DEL_PROVEEDOR' THEN
        RAISE EXCEPTION
          'Define v_nombre_proveedor con el nombre real del proveedor antes de migrar.';
    END IF;

    IF to_regclass('public.prv_dat_saldo') IS NULL THEN
        RAISE EXCEPTION
          'No existe prv_dat_saldo. Ejecuta primero pago_proveedores_schema.sql.';
    END IF;

    SELECT id INTO v_id_moneda
    FROM public.prv_nom_moneda
    WHERE codigo = v_moneda_codigo
    LIMIT 1;

    IF v_id_moneda IS NULL THEN
        RAISE EXCEPTION 'Moneda % no existe en prv_nom_moneda.', v_moneda_codigo;
    END IF;

    -- Columna temporal para mapear facturas imp → prv (idempotencia)
    ALTER TABLE public.prv_dat_factura
        ADD COLUMN IF NOT EXISTS id_imp_origen BIGINT;

    CREATE UNIQUE INDEX IF NOT EXISTS uq_prv_dat_factura_id_imp_origen
        ON public.prv_dat_factura (id_imp_origen)
        WHERE id_imp_origen IS NOT NULL;

    -- Alinear estados (incluye rename Importadora → Proveedor)
    INSERT INTO public.prv_nom_estado_factura (denominacion, descripcion, color, orden, activo)
    SELECT
        CASE
            WHEN lower(e.denominacion) = lower('Pagado a Importadora')
                THEN 'Pagado a Proveedor'
            ELSE e.denominacion
        END,
        e.descripcion,
        e.color,
        e.orden,
        e.activo
    FROM public.imp_nom_estado_factura e
    WHERE NOT EXISTS (
        SELECT 1
        FROM public.prv_nom_estado_factura p
        WHERE lower(p.denominacion) = lower(
            CASE
                WHEN lower(e.denominacion) = lower('Pagado a Importadora')
                    THEN 'Pagado a Proveedor'
                ELSE e.denominacion
            END
        )
    );

    -- Tiendas con cualquier dato de Importadora
    FOR v_tienda IN
        SELECT DISTINCT idtienda FROM (
            SELECT idtienda FROM public.imp_dat_saldo
            UNION
            SELECT idtienda FROM public.imp_dat_factura
            UNION
            SELECT idtienda FROM public.imp_dat_recarga_saldo
            UNION
            SELECT idtienda FROM public.imp_hist_saldo
        ) t
        ORDER BY idtienda
    LOOP
        v_tiendas := v_tiendas + 1;
        v_sku := 'IMP-MIG-' || v_tienda::text;

        -- Reutilizar si ya existe proveedor con ese nombre o SKU en la tienda
        SELECT id INTO v_id_proveedor
        FROM public.app_dat_proveedor
        WHERE idtienda = v_tienda
          AND (
              lower(btrim(denominacion)) = lower(btrim(v_nombre_proveedor))
              OR sku_codigo = v_sku
          )
        ORDER BY id
        LIMIT 1;

        IF v_id_proveedor IS NULL THEN
            INSERT INTO public.app_dat_proveedor (
                denominacion, sku_codigo, idtienda, created_at
            )
            VALUES (
                btrim(v_nombre_proveedor),
                v_sku,
                v_tienda,
                now()
            )
            RETURNING id INTO v_id_proveedor;
        ELSE
            UPDATE public.app_dat_proveedor
            SET denominacion = btrim(v_nombre_proveedor)
            WHERE id = v_id_proveedor
              AND lower(btrim(denominacion)) <> lower(btrim(v_nombre_proveedor));
        END IF;

        -- Config moneda
        INSERT INTO public.prv_dat_proveedor_config (idtienda, id_proveedor, id_moneda)
        VALUES (v_tienda, v_id_proveedor, v_id_moneda)
        ON CONFLICT (idtienda, id_proveedor) DO UPDATE
        SET id_moneda = EXCLUDED.id_moneda,
            updated_at = now();

        -- Saldo
        INSERT INTO public.prv_dat_saldo (idtienda, id_proveedor, saldo_disponible, updated_at)
        SELECT
            s.idtienda,
            v_id_proveedor,
            GREATEST(COALESCE(s.saldo_disponible, 0), 0),
            COALESCE(s.updated_at, now())
        FROM public.imp_dat_saldo s
        WHERE s.idtienda = v_tienda
        ON CONFLICT (idtienda, id_proveedor) DO UPDATE
        SET saldo_disponible = EXCLUDED.saldo_disponible,
            updated_at = EXCLUDED.updated_at;

        -- Si no había fila de saldo pero sí movimientos, crear saldo 0
        INSERT INTO public.prv_dat_saldo (idtienda, id_proveedor, saldo_disponible, updated_at)
        VALUES (v_tienda, v_id_proveedor, 0, now())
        ON CONFLICT (idtienda, id_proveedor) DO NOTHING;

        -- Recargas (evitar duplicados por observación de migración)
        INSERT INTO public.prv_dat_recarga_saldo (
            idtienda, id_proveedor, monto, fecha_pago, observacion, created_at
        )
        SELECT
            r.idtienda,
            v_id_proveedor,
            r.monto,
            r.fecha_pago,
            trim(both FROM
                COALESCE(r.observacion, '') ||
                ' [migrado Importadora recarga#' || r.id || ']'
            ),
            r.created_at
        FROM public.imp_dat_recarga_saldo r
        WHERE r.idtienda = v_tienda
          AND NOT EXISTS (
              SELECT 1
              FROM public.prv_dat_recarga_saldo x
              WHERE x.idtienda = r.idtienda
                AND x.id_proveedor = v_id_proveedor
                AND x.observacion LIKE '%[migrado Importadora recarga#' || r.id || ']%'
          );
        GET DIAGNOSTICS v_recargas_ins = ROW_COUNT;

        -- Facturas
        INSERT INTO public.prv_dat_factura (
            idtienda, id_proveedor, numero_factura, valor,
            fecha_procesamiento, foto_url, id_estado, created_at, id_imp_origen
        )
        SELECT
            f.idtienda,
            v_id_proveedor,
            f.numero_factura,
            f.valor,
            f.fecha_procesamiento,
            f.foto_url,
            COALESCE(
                (
                    SELECT p.id
                    FROM public.prv_nom_estado_factura p
                    JOIN public.imp_nom_estado_factura i ON i.id = f.id_estado
                    WHERE lower(p.denominacion) = lower(
                        CASE
                            WHEN lower(i.denominacion) = lower('Pagado a Importadora')
                                THEN 'Pagado a Proveedor'
                            ELSE i.denominacion
                        END
                    )
                    LIMIT 1
                ),
                (SELECT id FROM public.prv_nom_estado_factura ORDER BY orden ASC LIMIT 1)
            ),
            f.created_at,
            f.id
        FROM public.imp_dat_factura f
        WHERE f.idtienda = v_tienda
          AND NOT EXISTS (
              SELECT 1
              FROM public.prv_dat_factura x
              WHERE x.id_imp_origen = f.id
          );
        GET DIAGNOSTICS v_facturas_ins = ROW_COUNT;

        -- Fotos
        INSERT INTO public.prv_dat_factura_foto (
            id_factura, foto_url, numero_pagina, nombre_archivo, mime_type, created_at
        )
        SELECT
            p.id,
            fo.foto_url,
            fo.numero_pagina,
            fo.nombre_archivo,
            fo.mime_type,
            fo.created_at
        FROM public.imp_dat_factura_foto fo
        JOIN public.prv_dat_factura p ON p.id_imp_origen = fo.id_factura
        WHERE p.idtienda = v_tienda
          AND p.id_proveedor = v_id_proveedor
          AND NOT EXISTS (
              SELECT 1
              FROM public.prv_dat_factura_foto x
              WHERE x.id_factura = p.id
                AND x.foto_url = fo.foto_url
                AND x.numero_pagina = fo.numero_pagina
          );

        -- Historial de estados de factura
        INSERT INTO public.prv_hist_estado_factura (
            id_factura, id_estado_anterior, id_estado_nuevo, observacion, created_at
        )
        SELECT
            p.id,
            COALESCE(
                (
                    SELECT np.id
                    FROM public.prv_nom_estado_factura np
                    JOIN public.imp_nom_estado_factura ni ON ni.id = h.id_estado_anterior
                    WHERE lower(np.denominacion) = lower(
                        CASE
                            WHEN lower(ni.denominacion) = lower('Pagado a Importadora')
                                THEN 'Pagado a Proveedor'
                            ELSE ni.denominacion
                        END
                    )
                    LIMIT 1
                ),
                (SELECT id FROM public.prv_nom_estado_factura ORDER BY orden ASC LIMIT 1)
            ),
            COALESCE(
                (
                    SELECT np.id
                    FROM public.prv_nom_estado_factura np
                    JOIN public.imp_nom_estado_factura ni ON ni.id = h.id_estado_nuevo
                    WHERE lower(np.denominacion) = lower(
                        CASE
                            WHEN lower(ni.denominacion) = lower('Pagado a Importadora')
                                THEN 'Pagado a Proveedor'
                            ELSE ni.denominacion
                        END
                    )
                    LIMIT 1
                ),
                (SELECT id FROM public.prv_nom_estado_factura ORDER BY orden ASC LIMIT 1)
            ),
            trim(both FROM
                COALESCE(h.observacion, '') ||
                ' [migrado Importadora hist#' || h.id || ']'
            ),
            h.created_at
        FROM public.imp_hist_estado_factura h
        JOIN public.prv_dat_factura p ON p.id_imp_origen = h.id_factura
        WHERE p.idtienda = v_tienda
          AND p.id_proveedor = v_id_proveedor
          AND NOT EXISTS (
              SELECT 1
              FROM public.prv_hist_estado_factura x
              WHERE x.id_factura = p.id
                AND x.observacion LIKE '%[migrado Importadora hist#' || h.id || ']%'
          );

        -- Historial de saldo
        INSERT INTO public.prv_hist_saldo (
            idtienda, id_proveedor, monto_anterior, monto_nuevo, diferencia,
            tipo_operacion, referencia, created_at
        )
        SELECT
            h.idtienda,
            v_id_proveedor,
            h.monto_anterior,
            h.monto_nuevo,
            h.diferencia,
            h.tipo_operacion,
            trim(both FROM
                COALESCE(h.referencia, '') ||
                ' [migrado Importadora saldo#' || h.id || ']'
            ),
            h.created_at
        FROM public.imp_hist_saldo h
        WHERE h.idtienda = v_tienda
          AND NOT EXISTS (
              SELECT 1
              FROM public.prv_hist_saldo x
              WHERE x.idtienda = h.idtienda
                AND x.id_proveedor = v_id_proveedor
                AND x.referencia LIKE '%[migrado Importadora saldo#' || h.id || ']%'
          );

        RAISE NOTICE
          'Tienda % → proveedor id=% ("%") | facturas nuevas=% | recargas nuevas=%',
          v_tienda, v_id_proveedor, v_nombre_proveedor, v_facturas_ins, v_recargas_ins;
    END LOOP;

    RAISE NOTICE
      'Migración OK. Tiendas procesadas: %. Proveedor: "%". Importadora (imp_*) no se modificó.',
      v_tiendas, v_nombre_proveedor;
END $$;


-- ============================================================================
-- Verificación rápida (ejecutar después)
-- ============================================================================
-- SELECT p.idtienda, t.denominacion AS tienda, p.denominacion AS proveedor, p.sku_codigo
-- FROM app_dat_proveedor p
-- LEFT JOIN app_dat_tienda t ON t.id = p.idtienda
-- WHERE p.sku_codigo LIKE 'IMP-MIG-%'
-- ORDER BY p.idtienda;
--
-- SELECT s.idtienda, s.id_proveedor, s.saldo_disponible AS prv_saldo,
--        i.saldo_disponible AS imp_saldo
-- FROM prv_dat_saldo s
-- JOIN app_dat_proveedor p ON p.id = s.id_proveedor AND p.sku_codigo LIKE 'IMP-MIG-%'
-- LEFT JOIN imp_dat_saldo i ON i.idtienda = s.idtienda;
--
-- SELECT COUNT(*) AS facturas_migradas FROM prv_dat_factura WHERE id_imp_origen IS NOT NULL;
