CREATE OR REPLACE FUNCTION public.fn_tasa_automatica_estado()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v jsonb;
BEGIN
  BEGIN
    v := flow.tasas_actuales();
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'disponible', false,
      'error', 'El esquema flow no está disponible en este entorno.'
    );
  END;

  IF v IS NULL OR coalesce((v->>'ok')::boolean, false) IS NOT TRUE THEN
    RETURN jsonb_build_object(
      'disponible', true,
      'ok', false,
      'error', coalesce(v->>'error', 'Sin tasas en caché')
    );
  END IF;

  RETURN jsonb_build_object(
    'disponible', true,
    'ok', true,
    'fecha', v->'fecha',
    'hora', v->'hora',
    'fuente', v->'fuente',
    'actualizado', v->'actualizado',
    'vigente', v->'vigente',
    'tasas_cup', jsonb_build_object(
      'USD', nullif(v->'conversiones'->'USD'->>'CUP','')::numeric,
      'EUR', nullif(v->'conversiones'->'EUR'->>'CUP','')::numeric,
      'MLC', nullif(v->'conversiones'->'MLC'->>'CUP','')::numeric
    ),
    'monedas_cubiertas', (
      SELECT jsonb_agg(k ORDER BY k)
      FROM jsonb_object_keys(v->'conversiones') AS k
    )
  );
END;
$function$

