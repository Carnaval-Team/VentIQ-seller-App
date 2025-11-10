-- =====================================================
-- Función RPC: get_tienda_estado_tpvs
-- Descripción: Obtiene el estado de los TPVs de una tienda (abierto/cerrado)
-- Autor: VentIQ Team
-- Fecha: 2025-11-10
-- =====================================================

CREATE OR REPLACE FUNCTION get_tienda_estado_tpvs(
    id_tienda_param bigint
)
RETURNS TABLE (
    id_tpv bigint,
    denominacion_tpv text,
    esta_abierto boolean,
    fecha_apertura timestamp with time zone,
    fecha_cierre timestamp with time zone
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        tpv.id::bigint AS id_tpv,
        tpv.denominacion::text AS denominacion_tpv,
        -- Está abierto si el último turno no tiene fecha de cierre
        CASE 
            WHEN ultimo_turno.fecha_cierre IS NULL THEN true
            ELSE false
        END AS esta_abierto,
        ultimo_turno.fecha_apertura,
        ultimo_turno.fecha_cierre
    FROM 
        app_dat_tpv tpv
    LEFT JOIN LATERAL (
        -- Obtener el último turno de cada TPV
        SELECT 
            ct.fecha_apertura,
            ct.fecha_cierre
        FROM app_dat_caja_turno ct
        WHERE ct.id_tpv = tpv.id
        ORDER BY ct.fecha_apertura DESC
        LIMIT 1
    ) ultimo_turno ON true
    WHERE 
        tpv.id_tienda = id_tienda_param
    ORDER BY 
        tpv.denominacion;
END;
$$;

-- =====================================================
-- Comentarios de la función
-- =====================================================
COMMENT ON FUNCTION get_tienda_estado_tpvs(bigint) IS 
'Obtiene el estado de los TPVs de una tienda específica.
Retorna información sobre si cada TPV está abierto (turno sin cerrar) o cerrado.
Incluye fecha de apertura del último turno.';

-- =====================================================
-- Ejemplos de uso
-- =====================================================

-- Obtener estado de TPVs de una tienda
-- SELECT * FROM get_tienda_estado_tpvs(1);

-- Contar TPVs abiertos de una tienda
-- SELECT COUNT(*) as tpvs_abiertos 
-- FROM get_tienda_estado_tpvs(1) 
-- WHERE esta_abierto = true;

-- Obtener solo TPVs abiertos
-- SELECT * FROM get_tienda_estado_tpvs(1) WHERE esta_abierto = true;

-- Obtener solo TPVs cerrados
-- SELECT * FROM get_tienda_estado_tpvs(1) WHERE esta_abierto = false;
