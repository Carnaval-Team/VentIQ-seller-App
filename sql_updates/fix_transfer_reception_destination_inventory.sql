DO $migration$
DECLARE
  v_definition TEXT;
  v_original TEXT;
BEGIN
  SELECT pg_get_functiondef(p.oid)
  INTO v_definition
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'fn_transferir_inventario_entre_layouts';

  IF v_definition IS NULL THEN
    RAISE EXCEPTION 'No existe public.fn_transferir_inventario_entre_layouts';
  END IF;

  v_original := v_definition;
  v_definition := regexp_replace(
    v_definition,
    E'(  v_rec_result[[:space:]]+JSONB;\\r?\\n)',
    E'\\1  v_cont_result            JSONB;\n'
  );

  v_definition := regexp_replace(
    v_definition,
    E'  -- 4\\. Completar operaciones\\r?\\n  IF p_completar_operaciones THEN.*?\\r?\\n  END IF;',
    E'  -- 4. Completar operaciones\n  IF p_completar_operaciones THEN\n    INSERT INTO public.app_dat_estado_operacion (\n      id_operacion, estado, uuid, created_at\n    ) VALUES (\n      v_id_extraccion, 2, p_uuid, NOW()\n    );\n\n    v_cont_result := public.fn_contabilizar_operacion(\n      p_id_operacion => v_id_recepcion,\n      p_uuid          => p_uuid,\n      p_comentario    => ''Recepción completada automáticamente por transferencia''\n    );\n\n    IF COALESCE(v_cont_result->>''status'', '''') <> ''success'' THEN\n      RAISE EXCEPTION ''Error contabilizando recepción: %'',\n        COALESCE(v_cont_result->>''message'', v_cont_result::TEXT);\n    END IF;\n\n    INSERT INTO public.app_dat_estado_operacion (\n      id_operacion, estado, uuid, created_at\n    ) VALUES (\n      v_id_operacion_padre, 2, p_uuid, NOW()\n    );\n  END IF;',
    'ns'
  );

  IF v_definition = v_original THEN
    RAISE EXCEPTION 'No se encontró el bloque esperado para actualizar';
  END IF;

  EXECUTE v_definition;
END;
$migration$;
