BEGIN;

DO $patch$
DECLARE
    v_def text;
    v_old text;
    v_new text;
BEGIN
    v_def := replace(pg_get_functiondef(
        'public.get_product_movements_v4(bigint,date,date,bigint,bigint,integer,integer)'::regprocedure
    ), E'\r\n', E'\n');

    v_def := replace(v_def, 'public.get_product_movements_v4(', 'public.get_product_movements_v5(');
    v_old := 'es_conversion boolean)';
    IF position(v_old IN v_def) = 0 THEN
        RAISE EXCEPTION 'Firma v4 inesperada';
    END IF;
    v_def := replace(v_def, v_old,
        'es_conversion boolean, movimiento_etiqueta text, motivo_modificacion text, cantidad_orden numeric)');

    v_old := 'ep.cantidad             AS ep_cantidad';
    IF position(v_old IN v_def) = 0 THEN
        RAISE EXCEPTION 'No se encontró cantidad de extracción';
    END IF;
    v_def := regexp_replace(v_def, 'ep\.cantidad\s+AS ep_cantidad',
        'CASE WHEN inv.id_extraccion IS NOT NULL THEN COALESCE(abs(inv.cantidad_final - inv.cantidad_inicial), ep.cantidad) ELSE ep.cantidad END AS ep_cantidad');
    v_old := 'ep.created_at           AS ep_created_at';
    IF position(v_old IN v_def) = 0 THEN
        RAISE EXCEPTION 'No se encontró fecha de extracción';
    END IF;
    v_def := regexp_replace(v_def, 'ep\.created_at\s+AS ep_created_at',
        'CASE WHEN ep.id IS NOT NULL THEN inv.created_at ELSE ep.created_at END AS ep_created_at');

    v_old := '(t.mov_id_conversion IS NOT NULL)::BOOLEAN';
    IF position(v_old IN v_def) = 0 THEN
        RAISE EXCEPTION 'No se encontró SELECT final v4';
    END IF;
    v_new := $sql$(t.mov_id_conversion IS NOT NULL)::BOOLEAN,
    CASE
      WHEN t.tipo_op_nombre NOT ILIKE '%venta%' THEN NULL
      WHEN ml.accion = 'add_product' THEN 'Agregado a orden'
      WHEN ml.accion = 'update_quantity' AND (ml.detalle->>'delta')::numeric > 0 THEN 'Aumento de cantidad'
      WHEN ml.accion = 'update_quantity' AND (ml.detalle->>'delta')::numeric < 0 THEN 'Disminución de cantidad'
      ELSE 'Movimiento de venta'
    END::text,
    CASE WHEN ml.accion = 'update_quantity' THEN
      format('Cantidad modificada de %s a %s', ml.detalle->>'cantidad_anterior', ml.detalle->>'cantidad_nueva')
    END::text,
    CASE WHEN t.tipo_op_nombre ILIKE '%venta%' THEN ep_actual.cantidad END::numeric$sql$;
    v_def := replace(v_def, v_old, v_new);

    v_old := '  FROM todos t';
    IF position(v_old IN v_def) = 0 THEN
        RAISE EXCEPTION 'No se encontró origen del SELECT final';
    END IF;
    v_def := replace(v_def, v_old, $sql$  FROM todos t
  LEFT JOIN public.app_dat_extraccion_productos ep_actual ON ep_actual.id = t.ep_id
  LEFT JOIN LATERAL (
    SELECT l.accion, l.detalle
    FROM public.app_dat_log_modificacion_orden l
    WHERE l.id_operacion = t.id_op
      AND l.detalle->>'id_extraccion' = t.ep_id::text
      AND l.created_at = t.inv_created_at
      AND l.accion IN ('add_product', 'update_quantity')
    ORDER BY l.id DESC
    LIMIT 1
  ) ml ON TRUE$sql$);

    EXECUTE v_def;
END;
$patch$;

REVOKE ALL ON FUNCTION public.get_product_movements_v5(bigint,date,date,bigint,bigint,integer,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_product_movements_v5(bigint,date,date,bigint,bigint,integer,integer) TO authenticated, service_role;
NOTIFY pgrst, 'reload schema';

COMMIT;
