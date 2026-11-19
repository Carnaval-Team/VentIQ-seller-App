CREATE OR REPLACE FUNCTION public.fn_tasas_ingerir()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rec record;
  v_res jsonb;
  v_n   int := 0;
  v_ok  int := 0;
BEGIN
  IF NOT public.fn_is_superadmin_full_access() THEN
    RAISE EXCEPTION 'Solo un superadministrador puede ingerir las tasas';
  END IF;

  BEGIN
    FOR v_rec IN
      SELECT request_id
      FROM flow.tasa_cambio_sondeo
      WHERE NOT ingerido
        AND creado_at <= now() - interval '2 seconds'
      ORDER BY request_id
      LIMIT 5
    LOOP
      v_n := v_n + 1;
      BEGIN
        v_res := flow.tasas_ingest(v_rec.request_id);
        IF coalesce(v_res->>'estado','') = 'ingerido' THEN
          v_ok := v_ok + 1;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        NULL;  -- una respuesta rota no debe tumbar el resto
      END;
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'disponible', false,
      'error', 'El esquema flow no está disponible en este entorno.'
    );
  END;

  RETURN public.fn_tasa_automatica_estado()
         || jsonb_build_object(
              'pendientes_procesados', v_n,
              'ingeridos', v_ok
            );
END;
$function$

