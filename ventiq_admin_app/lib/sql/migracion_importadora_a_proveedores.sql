-- ============================================================================
-- MIGRACIÓN: Pagos a Importadora (imp_*) → Pago a proveedores (prv_*)
--
-- Requisitos previos:
--   1) Ejecutar pago_proveedores_schema.sql
--   2) Completar v_id_tienda y v_id_proveedor abajo
--
-- Qué hace:
--   - Migra, para la tienda y proveedor indicados, saldo, recargas,
--     historial de saldo, estados, facturas, fotos e historial de estados
--     desde las tablas imp_* hacia las tablas prv_*.
--   - NO borra ni modifica imp_* (Importadora sigue intacta).
--
-- Idempotente: se puede re-ejecutar; no duplica facturas ni recargas ya migradas
-- (columna temporal id_imp_origen + observaciones con ID origen).
-- ============================================================================

DO $$
DECLARE
    -- >>> EDITAR: IDs reales de tienda y proveedor destino <<<
    v_id_tienda     INTEGER := 177;      -- poner aquí el id de la tienda
    v_id_proveedor  BIGINT  := 58;      -- poner aquí el id del proveedor
    v_moneda_codigo TEXT    := 'USD';  -- moneda por defecto del módulo

    v_id_moneda        BIGINT;
    v_facturas_ins     INTEGER := 0;
    v_recargas_ins     INTEGER := 0;
    v_nombre_proveedor TEXT;
BEGIN
    IF v_id_tienda IS NULL OR v_id_tienda <= 0 THEN
        RAISE EXCEPTION 'Define v_id_tienda con el ID real de la tienda antes de migrar.';
    END IF;

    IF v_id_proveedor IS NULL OR v_id_proveedor <= 0 THEN
        RAISE EXCEPTION 'Define v_id_proveedor con el ID real del proveedor antes de migrar.';
    END IF;

    -- Verificar que el proveedor exista y pertenezca a la tienda
    SELECT denominacion INTO v_nombre_proveedor
    FROM public.app_dat_proveedor
    WHERE id = v_id_proveedor AND idtienda = v_id_tienda;

    IF v_nombre_proveedor IS NULL THEN
        RAISE EXCEPTION 'No existe el proveedor % para la tienda %.', v_id_proveedor, v_id_tienda;
    END IF;

    IF to_regclass('public.prv_dat_saldo') IS NULL THEN
        RAISE EXCEPTION 'No existe prv_dat_saldo. Ejecuta primero pago_proveedores_schema.sql.';
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

    -- Config moneda
    INSERT INTO public.prv_dat_proveedor_config (idtienda, id_proveedor, id_moneda)
    VALUES (v_id_tienda, v_id_proveedor, v_id_moneda)
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
    WHERE s.idtienda = v_id_tienda
    ON CONFLICT (idtienda, id_proveedor) DO UPDATE
    SET saldo_disponible = EXCLUDED.saldo_disponible,
        updated_at = EXCLUDED.updated_at;

    -- Si no había fila de saldo pero sí movimientos, crear saldo 0
    INSERT INTO public.prv_dat_saldo (idtienda, id_proveedor, saldo_disponible, updated_at)
    VALUES (v_id_tienda, v_id_proveedor, 0, now())
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
    WHERE r.idtienda = v_id_tienda
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
    WHERE f.idtienda = v_id_tienda
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
    WHERE p.idtienda = v_id_tienda
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
    WHERE p.idtienda = v_id_tienda
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
    WHERE h.idtienda = v_id_tienda
      AND NOT EXISTS (
          SELECT 1
          FROM public.prv_hist_saldo x
          WHERE x.idtienda = h.idtienda
            AND x.id_proveedor = v_id_proveedor
            AND x.referencia LIKE '%[migrado Importadora saldo#' || h.id || ']%'
      );

    RAISE NOTICE
      'Tienda % → proveedor id=% ("%") | facturas nuevas=% | recargas nuevas=%',
      v_id_tienda, v_id_proveedor, v_nombre_proveedor, v_facturas_ins, v_recargas_ins;

    RAISE NOTICE
      'Migración OK. Proveedor: "%". Importadora (imp_*) no se modificó.',
      v_nombre_proveedor;
END $$;


-- ============================================================================
-- Verificación rápida (ejecutar después)
-- ============================================================================
-- SELECT p.idtienda, p.id AS id_proveedor, p.denominacion AS proveedor,
--        s.saldo_disponible, (SELECT COUNT(*) FROM prv_dat_factura f WHERE f.id_proveedor = p.id AND f.idtienda = p.idtienda) AS facturas
-- FROM app_dat_proveedor p
-- LEFT JOIN prv_dat_saldo s ON s.id_proveedor = p.id AND s.idtienda = p.idtienda
-- WHERE p.id = 0 AND p.idtienda = 0;  -- ajustar IDs
--
-- SELECT COUNT(*) AS facturas_migradas FROM prv_dat_factura WHERE id_imp_origen IS NOT NULL;
