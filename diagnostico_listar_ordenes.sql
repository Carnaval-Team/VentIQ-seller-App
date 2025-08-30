-- DIAGNÓSTICO: Por qué listar_ordenes viene vacío
-- Ejecutar estas consultas paso a paso para identificar el problema

-- 1. Verificar si existe el tipo de operación 'Venta'
SELECT 'Verificando tipo operación Venta' as paso;
SELECT id, denominacion FROM app_nom_tipo_operacion WHERE denominacion = 'Venta';

-- 2. Verificar permisos del usuario en la tienda 11
SELECT 'Verificando permisos del usuario' as paso;
SELECT 'gerente' as rol, id_tienda FROM app_dat_gerente 
WHERE uuid = '0a6886f2-ac36-416a-bfba-bd08d0671568' AND id_tienda = 11
UNION ALL
SELECT 'supervisor' as rol, id_tienda FROM app_dat_supervisor 
WHERE uuid = '0a6886f2-ac36-416a-bfba-bd08d0671568' AND id_tienda = 11
UNION ALL
SELECT 'almacenero' as rol, a.id_tienda FROM app_dat_almacenero al
JOIN app_dat_almacen a ON al.id_almacen = a.id
WHERE al.uuid = '0a6886f2-ac36-416a-bfba-bd08d0671568' AND a.id_tienda = 11
UNION ALL
SELECT 'vendedor' as rol, tpv.id_tienda FROM app_dat_vendedor v
JOIN app_dat_tpv tpv ON v.id_tpv = tpv.id
WHERE v.uuid = '0a6886f2-ac36-416a-bfba-bd08d0671568' AND tpv.id_tienda = 11;

-- 3. Verificar si existe el TPV 18 en la tienda 11
SELECT 'Verificando TPV' as paso;
SELECT id, denominacion, id_tienda FROM app_dat_tpv WHERE id = 18;

-- 4. Verificar operaciones básicas sin filtros de permisos
SELECT 'Verificando operaciones básicas' as paso;
SELECT 
    o.id,
    o.uuid,
    o.id_tienda,
    o.created_at,
    o.id_tipo_operacion,
    (SELECT denominacion FROM app_nom_tipo_operacion WHERE id = o.id_tipo_operacion) as tipo_op
FROM app_dat_operaciones o
WHERE o.id_tienda = 11
  AND o.created_at >= '2025-08-29'::date
  AND o.created_at <= '2025-08-29'::date + interval '1 day'
ORDER BY o.created_at DESC
LIMIT 5;

-- 5. Verificar operaciones con join a operacion_venta
SELECT 'Verificando operaciones con venta' as paso;
SELECT 
    o.id,
    o.uuid,
    ov.id_tpv,
    tp.denominacion as tpv_nombre
FROM app_dat_operaciones o
INNER JOIN app_dat_operacion_venta ov ON o.id = ov.id_operacion
INNER JOIN app_dat_tpv tp ON ov.id_tpv = tp.id
WHERE o.id_tienda = 11
  AND ov.id_tpv = 18
  AND o.created_at >= '2025-08-29'::date
  AND o.created_at <= '2025-08-29'::date + interval '1 day'
LIMIT 5;

-- 6. Verificar estados de operación
SELECT 'Verificando estados' as paso;
SELECT 
    eo.id_operacion,
    eo.estado,
    eo.created_at
FROM app_dat_estado_operacion eo
WHERE eo.id_operacion IN (
    SELECT o.id FROM app_dat_operaciones o
    WHERE o.id_tienda = 11
      AND o.created_at >= '2025-08-29'::date
      AND o.created_at <= '2025-08-29'::date + interval '1 day'
)
ORDER BY eo.created_at DESC;

-- 7. Verificar auth.uid() actual
SELECT 'Verificando usuario actual' as paso;
SELECT auth.uid() as current_user_uuid;

-- 8. Consulta completa SIN validación de permisos para debug
SELECT 'Consulta sin permisos' as paso;
SELECT 
    o.id,
    o.created_at,
    ov.id_tpv,
    tp.denominacion AS tpv_nombre,
    o.uuid AS uuid_vendedor,
    eo.estado
FROM 
    app_dat_operaciones o
INNER JOIN 
    app_dat_operacion_venta ov ON o.id = ov.id_operacion
INNER JOIN 
    app_dat_tpv tp ON ov.id_tpv = tp.id
LEFT JOIN LATERAL (
    SELECT estado 
    FROM app_dat_estado_operacion 
    WHERE id_operacion = o.id 
    ORDER BY created_at DESC 
    LIMIT 1
) eo ON true
WHERE 
    o.id_tipo_operacion = (SELECT id FROM app_nom_tipo_operacion WHERE denominacion = 'Venta')
    AND ov.id_tpv = 18
    AND o.uuid = '0a6886f2-ac36-416a-bfba-bd08d0671568'
    AND o.id_tienda = 11
    AND o.created_at >= '2025-08-29'::date
    AND o.created_at <= '2025-08-29'::date + interval '1 day'
ORDER BY 
    o.created_at DESC
LIMIT 5;
