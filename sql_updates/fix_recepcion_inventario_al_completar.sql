-- ============================================================================
-- Recepción: inventario SOLO al COMPLETAR (estado=2), con saldo REAL
-- ============================================================================
-- Problema (ejemplo):
--   Stock real = 3
--   Recepción pendiente +7 → (mal) insertaba inventario 3→10 en estado=1
--   Se vende 1 → stock real queda en 2
--   Al confirmar la recepción, el movimiento congelado decía 10 (incorrecto);
--   lo correcto es 2+7 = 9
--
-- Solución:
--   1) Al CREAR la recepción (pendiente): NO insertar en inventario.
--      Solo guardan app_dat_operaciones + recepción + productos + estado=1.
--   2) Al COMPLETAR (estado=2): insertar movimiento con
--        cantidad_inicial = stock actual real
--        cantidad_final   = stock actual + cantidad recibida
--   3) Al CANCELAR/DEVOLVER recepción pendiente: borrar filas prematuras
--      legacy (si existían de la versión anterior).
--   4) El listado de venta NO filtra filas: usa MAX(id) normal.
--      Con (1)+(2) no hay movimientos prematuros que contaminen el stock.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Helper: ¿el movimiento de inventario es usable para stock de venta?
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_inventario_movimiento_contabilizado(
  p_id_recepcion bigint,
  p_id_extraccion bigint,
  p_id_control bigint
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    (
      p_id_recepcion IS NULL
      AND p_id_extraccion IS NULL
      AND p_id_control IS NULL
    )
    OR (
      p_id_recepcion IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM app_dat_recepcion_productos rp
        JOIN app_dat_estado_operacion eo ON eo.id_operacion = rp.id_operacion
        WHERE rp.id = p_id_recepcion
          AND eo.estado = 2
          AND eo.id = (
            SELECT MAX(eo2.id)
            FROM app_dat_estado_operacion eo2
            WHERE eo2.id_operacion = rp.id_operacion
          )
      )
    )
    OR (
      p_id_extraccion IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM app_dat_extraccion_productos ep
        JOIN app_dat_estado_operacion eo ON eo.id_operacion = ep.id_operacion
        WHERE ep.id = p_id_extraccion
          AND eo.estado = 2
          AND eo.id = (
            SELECT MAX(eo2.id)
            FROM app_dat_estado_operacion eo2
            WHERE eo2.id_operacion = ep.id_operacion
          )
      )
    )
    OR (
      p_id_control IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM app_dat_control_productos cp
        JOIN app_dat_estado_operacion eo ON eo.id_operacion = cp.id_operacion
        WHERE cp.id = p_id_control
          AND eo.estado = 2
          AND eo.id = (
            SELECT MAX(eo2.id)
            FROM app_dat_estado_operacion eo2
            WHERE eo2.id_operacion = cp.id_operacion
          )
      )
    );
$$;

COMMENT ON FUNCTION public.fn_inventario_movimiento_contabilizado(bigint, bigint, bigint) IS
  'True si el movimiento cuenta para stock de venta (op completada estado=2 o sin vínculo).';

GRANT EXECUTE ON FUNCTION public.fn_inventario_movimiento_contabilizado(bigint, bigint, bigint)
  TO PUBLIC, anon, authenticated, service_role;


-- ---------------------------------------------------------------------------
-- 1) Crear recepción PENDIENTE: sin tocar inventario
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_registrar_recepcion_con_inventario(
  p_entregado_por    TEXT,
  p_id_tienda        BIGINT,
  p_monto_total      NUMERIC  DEFAULT NULL,
  p_motivo           INTEGER  DEFAULT NULL,
  p_observaciones    TEXT     DEFAULT NULL,
  p_productos        JSONB    DEFAULT '[]'::JSONB,
  p_recibido_por     TEXT     DEFAULT NULL,
  p_uuid             UUID     DEFAULT NULL,
  p_moneda_factura   TEXT     DEFAULT 'USD'
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_id_operacion          BIGINT;
  v_id_tipo_operacion     BIGINT;
  v_producto_record       JSONB;
  v_cantidad_total        NUMERIC := 0;
  v_tienda_exists         BOOLEAN;
  v_moneda_factura        TEXT;
  v_id_recepcion_producto BIGINT;
  v_id_producto           BIGINT;
  v_id_variante           BIGINT;
  v_id_opcion_variante    BIGINT;
  v_id_ubicacion          BIGINT;
  v_id_presentacion       BIGINT;
  v_id_proveedor          BIGINT;
  v_cantidad              NUMERIC;
  v_precio_unitario       NUMERIC;
  v_err_message           TEXT;
  v_err_detail            TEXT;
  v_err_hint              TEXT;
  v_err_context           TEXT;
BEGIN
  SELECT EXISTS(SELECT 1 FROM app_dat_tienda WHERE id = p_id_tienda)
  INTO v_tienda_exists;

  IF NOT v_tienda_exists THEN
    RETURN jsonb_build_object(
      'status',   'error',
      'message',  format('La tienda con ID %s no existe', p_id_tienda),
      'sqlstate', 'V0001',
      'etapa',    'validacion_tienda'
    );
  END IF;

  IF p_productos IS NULL OR jsonb_array_length(p_productos) = 0 THEN
    RETURN jsonb_build_object(
      'status',   'error',
      'message',  'Debe incluir al menos un producto',
      'sqlstate', 'V0002',
      'etapa',    'validacion_productos'
    );
  END IF;

  v_moneda_factura := COALESCE(NULLIF(TRIM(p_moneda_factura), ''), 'USD');
  IF v_moneda_factura NOT IN ('USD', 'EUR', 'CUP') THEN
    RETURN jsonb_build_object(
      'status',   'error',
      'message',  format('Moneda no válida: "%s". Use USD, EUR o CUP', v_moneda_factura),
      'sqlstate', 'V0003',
      'etapa',    'validacion_moneda'
    );
  END IF;

  SELECT id_tipo_operacion
  INTO v_id_tipo_operacion
  FROM app_nom_motivo_recepcion
  WHERE id = p_motivo::BIGINT;

  IF v_id_tipo_operacion IS NULL THEN
    RETURN jsonb_build_object(
      'status',   'error',
      'message',  format('No se encontró tipo de operación para el motivo %s', p_motivo),
      'sqlstate', 'V0004',
      'etapa',    'validacion_motivo'
    );
  END IF;

  INSERT INTO app_dat_operaciones (
    id_tipo_operacion, uuid, id_tienda, observaciones, created_at
  ) VALUES (
    v_id_tipo_operacion, p_uuid, p_id_tienda, p_observaciones, NOW()
  ) RETURNING id INTO v_id_operacion;

  INSERT INTO app_dat_operacion_recepcion (
    id_operacion, entregado_por, recibido_por, monto_total,
    observaciones, motivo, created_at, moneda_factura
  ) VALUES (
    v_id_operacion, p_entregado_por, p_recibido_por, p_monto_total,
    p_observaciones, p_motivo, NOW(), v_moneda_factura
  );

  -- Solo detalle de productos. El inventario se aplica al COMPLETAR.
  FOR v_producto_record IN SELECT * FROM jsonb_array_elements(p_productos)
  LOOP
    IF v_producto_record->>'id_producto' IS NULL
    OR v_producto_record->>'cantidad'    IS NULL THEN
      RETURN jsonb_build_object(
        'status',               'error',
        'message',              'Cada producto debe tener id_producto y cantidad',
        'sqlstate',             'V0005',
        'etapa',                'validacion_producto_item',
        'producto_recibido',    v_producto_record,
        'id_operacion_parcial', v_id_operacion
      );
    END IF;

    v_id_producto        := (v_producto_record->>'id_producto')::BIGINT;
    v_id_variante        := NULLIF(v_producto_record->>'id_variante',        '')::BIGINT;
    v_id_opcion_variante := NULLIF(v_producto_record->>'id_opcion_variante', '')::BIGINT;
    v_id_proveedor       := NULLIF(v_producto_record->>'id_proveedor',       '')::BIGINT;
    v_id_ubicacion       := NULLIF(v_producto_record->>'id_ubicacion',       '')::BIGINT;
    v_id_presentacion    := NULLIF(v_producto_record->>'id_presentacion',    '')::BIGINT;
    v_cantidad           := (v_producto_record->>'cantidad')::NUMERIC;
    v_precio_unitario    := NULLIF(v_producto_record->>'precio_unitario',    '')::NUMERIC;

    INSERT INTO app_dat_recepcion_productos (
      id_operacion, id_producto, id_variante, id_opcion_variante,
      id_proveedor, id_ubicacion, id_presentacion, cantidad,
      precio_unitario, sku_producto, sku_ubicacion, created_at
    ) VALUES (
      v_id_operacion, v_id_producto, v_id_variante, v_id_opcion_variante,
      v_id_proveedor, v_id_ubicacion, v_id_presentacion, v_cantidad,
      v_precio_unitario,
      v_producto_record->>'sku_producto',
      v_producto_record->>'sku_ubicacion',
      NOW()
    ) RETURNING id INTO v_id_recepcion_producto;

    v_cantidad_total := v_cantidad_total + (v_cantidad * COALESCE(v_precio_unitario, 0));
  END LOOP;

  INSERT INTO app_dat_estado_operacion (id_operacion, estado, uuid, created_at)
  VALUES (v_id_operacion, 1, p_uuid, NOW());

  IF p_monto_total IS NULL THEN
    UPDATE app_dat_operacion_recepcion
    SET monto_total = v_cantidad_total
    WHERE id_operacion = v_id_operacion;
  END IF;

  RETURN jsonb_build_object(
    'status',           'success',
    'id_operacion',     v_id_operacion,
    'total_productos',  jsonb_array_length(p_productos),
    'monto_total',      COALESCE(p_monto_total, v_cantidad_total),
    'moneda_utilizada', v_moneda_factura,
    'mensaje',          'Recepción pendiente registrada. El inventario se aplicará al completar.'
  );

EXCEPTION
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      v_err_message = MESSAGE_TEXT,
      v_err_detail  = PG_EXCEPTION_DETAIL,
      v_err_hint    = PG_EXCEPTION_HINT,
      v_err_context = PG_EXCEPTION_CONTEXT;

    RETURN jsonb_build_object(
      'status',               'error',
      'message',              v_err_message,
      'detail',               COALESCE(v_err_detail,  ''),
      'hint',                 COALESCE(v_err_hint,    ''),
      'context',              COALESCE(v_err_context, ''),
      'id_operacion_parcial', v_id_operacion
    );
END;
$$;


-- ---------------------------------------------------------------------------
-- 2) Cambio de estado: al completar recepción, aplicar inventario con saldo real
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_registrar_cambio_estado_operacion_mejorado(
    p_id_operacion BIGINT,
    p_nuevo_estado SMALLINT,
    p_uuid_usuario UUID DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_productos_extraidos RECORD;
    v_existente_estado RECORD;
    v_inventario_actual RECORD;
    v_ingrediente RECORD;
    v_cantidad_ingrediente_devolver NUMERIC;
    v_ultimo_inventario RECORD;
    v_es_recepcion BOOLEAN := FALSE;
    v_rp RECORD;
    v_stock_actual NUMERIC;
    v_inv_prematuro_id BIGINT;
    v_response jsonb;
BEGIN
    v_response := jsonb_build_object(
        'success', false,
        'message', '',
        'operation_id', p_id_operacion,
        'new_state', p_nuevo_estado
    );

    IF p_nuevo_estado NOT IN (1, 2, 3, 4) THEN
        v_response := jsonb_set(v_response, '{success}', 'false');
        v_response := jsonb_set(
          v_response,
          '{message}',
          '"Estado de operación inválido. Solo se permiten 1 (Pendiente), 2 (Completada), 3 (Devuelta), 4 (Cancelada)"'
        );
        RETURN v_response;
    END IF;

    SELECT * INTO v_existente_estado
    FROM app_dat_estado_operacion
    WHERE id_operacion = p_id_operacion
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_existente_estado.estado = p_nuevo_estado THEN
        v_response := jsonb_set(v_response, '{success}', 'true');
        v_response := jsonb_set(v_response, '{message}', '"La operación ya tiene este estado"');
        RETURN v_response;
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM app_dat_operacion_recepcion orp
        WHERE orp.id_operacion = p_id_operacion
    ) INTO v_es_recepcion;

    -- ── COMPLETAR RECEPCIÓN: aplicar inventario sobre el stock REAL actual ──
    -- Ejemplo: había 3, pendiente +7, se vendió 1 → queda 2; al completar → 9.
    IF v_es_recepcion AND p_nuevo_estado = 2 THEN
        FOR v_rp IN
            SELECT
                rp.id AS id_recepcion_producto,
                rp.id_producto,
                rp.id_variante,
                rp.id_opcion_variante,
                rp.id_presentacion,
                rp.id_ubicacion,
                rp.id_proveedor,
                rp.cantidad,
                rp.sku_producto,
                rp.sku_ubicacion
            FROM app_dat_recepcion_productos rp
            WHERE rp.id_operacion = p_id_operacion
        LOOP
            -- Stock actual = último movimiento EXCLUYENDO filas prematuras
            -- de ESTA recepción (legacy de cuando se insertaba al crear).
            SELECT COALESCE((
                SELECT ip.cantidad_final
                FROM app_dat_inventario_productos ip
                WHERE ip.id_producto = v_rp.id_producto
                  AND (ip.id_variante        IS NOT DISTINCT FROM v_rp.id_variante)
                  AND (ip.id_opcion_variante IS NOT DISTINCT FROM v_rp.id_opcion_variante)
                  AND (ip.id_presentacion    IS NOT DISTINCT FROM v_rp.id_presentacion)
                  AND (ip.id_ubicacion       IS NOT DISTINCT FROM v_rp.id_ubicacion)
                  AND (ip.id_recepcion IS DISTINCT FROM v_rp.id_recepcion_producto)
                ORDER BY ip.id DESC
                LIMIT 1
            ), 0) INTO v_stock_actual;

            -- Eliminar movimiento prematuro legacy (si existe) para no contaminar MAX(id)
            DELETE FROM app_dat_inventario_productos
            WHERE id_recepcion = v_rp.id_recepcion_producto;

            INSERT INTO app_dat_inventario_productos (
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
                id_proveedor,
                created_at
            ) VALUES (
                v_rp.id_producto,
                v_rp.id_variante,
                v_rp.id_opcion_variante,
                v_rp.id_ubicacion,
                v_rp.id_presentacion,
                v_stock_actual,
                v_stock_actual + v_rp.cantidad,
                v_rp.sku_producto,
                v_rp.sku_ubicacion,
                1,
                v_rp.id_recepcion_producto,
                v_rp.id_proveedor,
                NOW()
            );
        END LOOP;
    END IF;

    -- ── CANCELAR / DEVOLVER RECEPCIÓN PENDIENTE: limpiar filas prematuras ──
    IF v_es_recepcion AND p_nuevo_estado IN (3, 4) THEN
        DELETE FROM app_dat_inventario_productos ip
        WHERE ip.id_recepcion IN (
            SELECT rp.id
            FROM app_dat_recepcion_productos rp
            WHERE rp.id_operacion = p_id_operacion
        );
    END IF;

    INSERT INTO app_dat_estado_operacion (
        id_operacion, estado, uuid, created_at
    ) VALUES (
        p_id_operacion, p_nuevo_estado, p_uuid_usuario, NOW()
    );

    -- Cancelar/devolver EXTRACCIÓN: devolver stock (igual que antes)
    IF p_nuevo_estado IN (3, 4) AND NOT v_es_recepcion THEN
        FOR v_productos_extraidos IN (
            SELECT
                id_producto,
                id_variante,
                id_opcion_variante,
                id_presentacion,
                id_ubicacion,
                cantidad,
                sku_producto,
                sku_ubicacion
            FROM app_dat_extraccion_productos
            WHERE id_operacion = p_id_operacion
        ) LOOP
            SELECT * INTO v_inventario_actual
            FROM app_dat_inventario_productos
            WHERE id_producto = v_productos_extraidos.id_producto
              AND COALESCE(id_variante, 0) = COALESCE(v_productos_extraidos.id_variante, 0)
              AND COALESCE(id_opcion_variante, 0) = COALESCE(v_productos_extraidos.id_opcion_variante, 0)
              AND COALESCE(id_presentacion, 0) = COALESCE(v_productos_extraidos.id_presentacion, 0)
              AND COALESCE(id_ubicacion, 0) = COALESCE(v_productos_extraidos.id_ubicacion, 0)
            ORDER BY created_at DESC
            LIMIT 1;

            IF v_inventario_actual.cantidad_final IS NULL THEN
                v_inventario_actual.cantidad_final := 0;
            END IF;

            INSERT INTO app_dat_inventario_productos (
                id_producto, id_variante, id_opcion_variante, id_presentacion,
                id_ubicacion, cantidad_inicial, cantidad_final,
                sku_producto, sku_ubicacion, origen_cambio, created_at
            ) VALUES (
                v_productos_extraidos.id_producto,
                v_productos_extraidos.id_variante,
                v_productos_extraidos.id_opcion_variante,
                v_productos_extraidos.id_presentacion,
                v_productos_extraidos.id_ubicacion,
                v_inventario_actual.cantidad_final,
                v_inventario_actual.cantidad_final + v_productos_extraidos.cantidad,
                v_productos_extraidos.sku_producto,
                v_productos_extraidos.sku_ubicacion,
                CASE
                    WHEN p_nuevo_estado = 3 THEN 4
                    WHEN p_nuevo_estado = 4 THEN 5
                END,
                NOW()
            );
        END LOOP;

        FOR v_productos_extraidos IN (
            SELECT ep.id_producto, ep.cantidad
            FROM app_dat_extraccion_productos ep
            INNER JOIN app_dat_producto p ON ep.id_producto = p.id
            WHERE ep.id_operacion = p_id_operacion
              AND p.es_elaborado = true
        ) LOOP
            FOR v_ingrediente IN (
                SELECT id_ingrediente, cantidad_necesaria
                FROM app_dat_producto_ingredientes
                WHERE id_producto_elaborado = v_productos_extraidos.id_producto
            ) LOOP
                v_cantidad_ingrediente_devolver :=
                    v_ingrediente.cantidad_necesaria * v_productos_extraidos.cantidad;

                SELECT * INTO v_ultimo_inventario
                FROM app_dat_inventario_productos
                WHERE id_producto = v_ingrediente.id_ingrediente
                ORDER BY created_at DESC
                LIMIT 1;

                IF v_ultimo_inventario IS NULL THEN
                    v_ultimo_inventario.cantidad_final := 0;
                    v_ultimo_inventario.id_presentacion := NULL;
                    v_ultimo_inventario.id_ubicacion := NULL;
                    v_ultimo_inventario.sku_producto := NULL;
                    v_ultimo_inventario.sku_ubicacion := NULL;
                END IF;

                INSERT INTO app_dat_inventario_productos (
                    id_producto, id_variante, id_opcion_variante, id_presentacion,
                    id_ubicacion, cantidad_inicial, cantidad_final,
                    sku_producto, sku_ubicacion, origen_cambio, created_at
                ) VALUES (
                    v_ingrediente.id_ingrediente,
                    COALESCE(v_ultimo_inventario.id_variante, NULL),
                    COALESCE(v_ultimo_inventario.id_opcion_variante, NULL),
                    v_ultimo_inventario.id_presentacion,
                    COALESCE(v_ultimo_inventario.id_ubicacion, NULL),
                    COALESCE(v_ultimo_inventario.cantidad_final, 0),
                    COALESCE(v_ultimo_inventario.cantidad_final, 0)
                      + v_cantidad_ingrediente_devolver,
                    COALESCE(v_ultimo_inventario.sku_producto, NULL),
                    COALESCE(v_ultimo_inventario.sku_ubicacion, NULL),
                    CASE
                        WHEN p_nuevo_estado = 3 THEN 6
                        WHEN p_nuevo_estado = 4 THEN 7
                    END,
                    NOW()
                );
            END LOOP;
        END LOOP;
    END IF;

    v_response := jsonb_set(v_response, '{success}', 'true');
    v_response := jsonb_set(v_response, '{message}', '"Operación actualizada exitosamente"');
    RETURN v_response;
EXCEPTION WHEN OTHERS THEN
    v_response := jsonb_set(v_response, '{success}', 'false');
    v_response := jsonb_set(v_response, '{message}', to_jsonb(SQLERRM));
    RETURN v_response;
END;
$$;

COMMENT ON FUNCTION public.fn_registrar_recepcion_con_inventario IS
  'Crea recepción en estado Pendiente SIN mover inventario. El stock se aplica al completar.';

COMMENT ON FUNCTION public.fn_registrar_cambio_estado_operacion_mejorado IS
  'Al completar recepción (estado=2) inserta inventario con saldo real actual + cantidad recibida.';
