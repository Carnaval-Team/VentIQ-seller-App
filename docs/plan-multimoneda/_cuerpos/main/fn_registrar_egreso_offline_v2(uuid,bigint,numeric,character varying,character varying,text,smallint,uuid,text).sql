CREATE OR REPLACE FUNCTION public.fn_registrar_egreso_offline_v2(p_client_uuid uuid, p_id_turno bigint, p_monto_entrega numeric, p_nombre_recibe character varying, p_nombre_autoriza character varying, p_motivo_entrega text, p_id_medio_pago smallint DEFAULT NULL::smallint, p_uuid_usuario uuid DEFAULT NULL::uuid, p_moneda text DEFAULT 'CUP'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_res    jsonb;
  v_id     bigint;
  v_moneda text;
begin
  v_moneda := upper(trim(coalesce(nullif(p_moneda, ''), 'CUP')));

  if not exists (select 1 from public.monedas m where m.codigo = v_moneda and m.activo) then
    raise exception 'La moneda % no existe o no está activa en el catálogo', v_moneda;
  end if;

  -- Toda la lógica (idempotencia por client_uuid, validaciones, alta) la sigue
  -- haciendo la vigente: aquí no se duplica nada.
  v_res := public.fn_registrar_egreso_offline(
             p_client_uuid, p_id_turno, p_monto_entrega,
             p_nombre_recibe, p_nombre_autoriza, p_motivo_entrega,
             p_id_medio_pago, p_uuid_usuario);

  -- En un replay idempotente `egreso_id` es el de la fila ya existente y la
  -- divisa es la misma, así que este UPDATE es inocuo.
  if coalesce((v_res->>'success')::boolean, false) then
    v_id := nullif(v_res->>'egreso_id', '')::bigint;
    if v_id is not null then
      update public.app_dat_entregas_parciales_caja
      set moneda = v_moneda
      where id = v_id;
    end if;
  end if;

  return v_res;
end $function$

