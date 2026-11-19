CREATE OR REPLACE FUNCTION public.fn_cambiar_estado_comanda_item_offline(p_client_uuid uuid, p_id_item bigint, p_nuevo_estado smallint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_existing bigint;
    v_res      jsonb;
BEGIN
    IF p_client_uuid IS NULL THEN
        RETURN jsonb_build_object('status','error','message','Falta el client_uuid','error_code','CLIENT_UUID_REQUERIDO');
    END IF;

    SELECT id_operacion INTO v_existing
      FROM app_dat_operacion_offline_idempotencia
     WHERE client_uuid = p_client_uuid AND tipo = 'estado_comanda_item';

    IF v_existing IS NOT NULL THEN
        RETURN (
            SELECT jsonb_build_object('status','success','idempotent',true,
                     'id_item',ci.id,'plato',ci.denominacion,'estado',ci.estado,
                     'id_comanda',ci.id_comanda,'message','Este cambio ya se habia aplicado')
              FROM app_dat_comanda_item ci WHERE ci.id = v_existing
        );
    END IF;

    v_res := fn_cambiar_estado_comanda_item(p_id_item, p_nuevo_estado);

    IF (v_res->>'status') = 'success' THEN
        INSERT INTO app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario)
        VALUES (p_client_uuid, p_id_item, 'estado_comanda_item', auth.uid())
        ON CONFLICT (client_uuid) DO NOTHING;

        v_res := v_res || jsonb_build_object('idempotent', false);
    END IF;

    RETURN v_res;
END;
$function$

