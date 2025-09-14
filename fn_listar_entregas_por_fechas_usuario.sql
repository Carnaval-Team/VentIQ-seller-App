CREATE OR REPLACE FUNCTION fn_listar_entregas_por_fechas_usuario(
    p_fecha_inicio TIMESTAMP,
    p_fecha_fin TIMESTAMP,
    p_uuid_usuario UUID DEFAULT NULL
) RETURNS TABLE (
    id BIGINT,
    monto_entrega NUMERIC,
    motivo_entrega TEXT,
    nombre_recibe TEXT,
    nombre_autoriza TEXT,
    fecha_entrega TIMESTAMP,
    estado INTEGER,
    id_turno BIGINT,
    creado_por UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_uuid_usuario UUID;
BEGIN
    -- Establecer contexto
    SET search_path = public;
    
    -- Obtener el usuario autenticado si no se proporciona
    v_uuid_usuario := COALESCE(p_uuid_usuario, auth.uid());
    
    -- Verificar permisos
    PERFORM check_user_has_access_to_any_tienda();
    
    RETURN QUERY
    SELECT 
        epc.id,
        epc.monto_entrega,
        epc.motivo_entrega,
        epc.nombre_recibe,
        epc.nombre_autoriza,
        epc.fecha_entrega,
        ct.estado,
        epc.id_turno,
        epc.creado_por
    FROM app_dat_entregas_parciales_caja epc
    INNER JOIN app_dat_caja_turno ct ON epc.id_turno = ct.id
    WHERE (epc.fecha_entrega AT TIME ZONE 'America/Havana') BETWEEN p_fecha_inicio AND p_fecha_fin
      AND (p_uuid_usuario IS NULL OR epc.creado_por = v_uuid_usuario)
    ORDER BY epc.fecha_entrega DESC;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error en fn_listar_entregas_por_fechas_usuario: %', SQLERRM;
END;
$$;
