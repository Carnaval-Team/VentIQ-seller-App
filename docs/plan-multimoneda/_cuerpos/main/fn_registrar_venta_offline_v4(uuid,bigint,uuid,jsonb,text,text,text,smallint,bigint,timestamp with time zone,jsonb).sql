CREATE OR REPLACE FUNCTION public.fn_registrar_venta_offline_v4(p_client_uuid uuid, p_id_tpv bigint, p_uuid uuid, p_productos jsonb, p_codigo_promocion text DEFAULT NULL::text, p_denominacion text DEFAULT NULL::text, p_observaciones text DEFAULT NULL::text, p_estado_inicial smallint DEFAULT 1, p_id_cliente bigint DEFAULT NULL::bigint, p_fecha_creacion timestamp with time zone DEFAULT NULL::timestamp with time zone, p_pagos jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
DECLARE
  v_existing_op bigint; v_result jsonb; v_op bigint; v_ok boolean;
  v_id_tienda bigint;
BEGIN
  SELECT t.id_tienda INTO v_id_tienda FROM public.app_dat_tpv t WHERE t.id = p_id_tpv;
  IF v_id_tienda IS NULL THEN
    RETURN jsonb_build_object('status','error','error_code','TPV_NOT_FOUND','message','El TPV no existe');
  END IF;
  PERFORM public.check_user_has_access_to_tienda(v_id_tienda);

  SELECT i.id_operacion INTO v_existing_op
  FROM public.app_dat_operacion_offline_idempotencia i
  WHERE i.client_uuid = p_client_uuid;
  IF v_existing_op IS NOT NULL THEN
    v_op := v_existing_op;
    v_result := jsonb_build_object('status','success','id_operacion',v_op,'idempotent',true,
                                   'message','OperaciÃ³n ya registrada previamente (idempotente)');
  ELSE
    v_result := public.fn_registrar_venta_v3(p_id_tpv, p_uuid, p_productos, p_codigo_promocion,
                                             p_denominacion, p_observaciones, p_estado_inicial, p_id_cliente);
    IF v_result IS NULL OR v_result->>'status' IS DISTINCT FROM 'success' THEN RETURN v_result; END IF;
    v_op := NULLIF(v_result->>'id_operacion','')::bigint;
    IF v_op IS NULL THEN RAISE EXCEPTION 'fn_registrar_venta_v3 no devolviÃ³ id_operacion'; END IF;
    INSERT INTO public.app_dat_operacion_offline_idempotencia(client_uuid, id_operacion, tipo, uuid_usuario)
    VALUES (p_client_uuid, v_op, 'venta_v4', p_uuid) ON CONFLICT(client_uuid) DO NOTHING;
    IF p_fecha_creacion IS NOT NULL THEN
      UPDATE public.app_dat_operaciones SET created_at = p_fecha_creacion WHERE id = v_op;
      UPDATE public.app_dat_operacion_venta SET created_at = p_fecha_creacion WHERE id_operacion = v_op;
    END IF;
    v_result := v_result || jsonb_build_object('idempotent', false, 'client_uuid', p_client_uuid);
  END IF;

  -- Pagos: fn_registrar_pago_venta_v2 es idempotente (reescribe los no liquidados),
  -- asÃ­ que se reparan tambiÃ©n los desgloses parciales de intentos anteriores.
  IF p_pagos IS NOT NULL AND jsonb_typeof(p_pagos) = 'array' AND jsonb_array_length(p_pagos) > 0 THEN
    v_ok := public.fn_registrar_pago_venta_v2(v_op, p_pagos);
    IF NOT COALESCE(v_ok, false) THEN
      RAISE EXCEPTION 'No se pudieron registrar los pagos de la operaciÃ³n %', v_op;
    END IF;
    v_result := v_result || jsonb_build_object('pagos_registrados', true);
  END IF;

  RETURN v_result;
END;
$function$

