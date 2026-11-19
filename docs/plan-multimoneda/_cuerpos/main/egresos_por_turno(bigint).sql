CREATE OR REPLACE FUNCTION public.egresos_por_turno(p_id_turno bigint)
 RETURNS TABLE(id_egreso bigint, monto_entrega numeric, motivo_entrega text, nombre_recibe character varying, nombre_autoriza character varying, fecha_entrega timestamp with time zone, id_medio_pago smallint, turno_estado smallint, moneda character varying)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        epc.id,
        epc.monto_entrega,
        epc.motivo_entrega,
        epc.nombre_recibe,
        epc.nombre_autoriza,
        epc.fecha_entrega,
        epc.id_medio_pago,
        ct.estado,
        epc.moneda::character varying
    FROM app_dat_entregas_parciales_caja epc
    INNER JOIN app_dat_caja_turno ct ON epc.id_turno = ct.id
    WHERE ct.id = p_id_turno
      and auth.uid() = coalesce(epc.uuid_vendedor, ct.creado_por)
    ORDER BY epc.fecha_entrega;
END;
$function$

