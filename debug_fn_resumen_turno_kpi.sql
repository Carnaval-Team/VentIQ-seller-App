-- =====================================================
-- CONSULTAS DE DIAGNÓSTICO PARA fn_resumen_turno_kpi
-- =====================================================
-- Ejecutar estas consultas paso a paso para identificar el problema

-- 1. VERIFICAR SI EXISTEN REGISTROS EN app_dat_caja_turno
SELECT 
  COUNT(*) as total_turnos,
  COUNT(CASE WHEN estado = 1 THEN 1 END) as turnos_abiertos,
  COUNT(CASE WHEN estado = 2 THEN 1 END) as turnos_cerrados,
  COUNT(CASE WHEN estado = 3 THEN 1 END) as turnos_revision,
  COUNT(CASE WHEN fecha_apertura IS NULL THEN 1 END) as sin_fecha_apertura
FROM app_dat_caja_turno;

-- 2. VERIFICAR REGISTROS CON TODOS LOS ESTADOS (no solo 2,3)
SELECT 
  ct.id,
  ct.estado,
  ct.fecha_apertura,
  ct.fecha_cierre,
  ct.id_tpv,
  ct.id_vendedor,
  ct.efectivo_inicial
FROM app_dat_caja_turno ct
ORDER BY ct.id DESC
LIMIT 10;

-- 3. VERIFICAR SI EXISTEN TPVs Y VENDEDORES RELACIONADOS
SELECT 
  ct.id as turno_id,
  ct.id_tpv,
  ct.id_vendedor,
  tpv.denominacion as tpv_nombre,
  ven.id as vendedor_existe
FROM app_dat_caja_turno ct
LEFT JOIN app_dat_tpv tpv ON ct.id_tpv = tpv.id
LEFT JOIN app_dat_vendedor ven ON ct.id_vendedor = ven.id
WHERE ct.id_tpv IS NOT NULL OR ct.id_vendedor IS NOT NULL
ORDER BY ct.id DESC
LIMIT 10;

-- 4. PROBAR LA CONSULTA SIN FILTROS RESTRICTIVOS
SELECT
  ct.id AS turno_id,
  ct.estado,
  ct.fecha_apertura,
  ct.fecha_cierre,
  ct.efectivo_inicial,
  tpv.denominacion AS tpv,
  ven.id as vendedor_id
FROM app_dat_caja_turno ct
LEFT JOIN app_dat_tpv tpv ON ct.id_tpv = tpv.id
LEFT JOIN app_dat_vendedor ven ON ct.id_vendedor = ven.id
-- SIN FILTROS DE ESTADO NI FECHA
ORDER BY ct.id DESC
LIMIT 5;

-- 5. VERIFICAR PARÁMETROS QUE SE ESTÁN PASANDO A LA FUNCIÓN
-- (Ejecutar esto cuando llames a la función)
/*
SELECT 
  'Parámetros pasados:' as info,
  p_id_tpv,
  p_id_vendedor, 
  p_fecha_desde,
  p_fecha_hasta;
*/

-- 6. CONSULTA SIMPLIFICADA PARA PROBAR PASO A PASO
SELECT
  ct.id AS turno_id,
  ct.estado,
  ct.fecha_apertura,
  ct.efectivo_inicial
FROM app_dat_caja_turno ct
WHERE ct.fecha_apertura IS NOT NULL
  -- Comentar esta línea para probar sin filtro de estado:
  -- AND ct.estado IN (2, 3)
ORDER BY ct.fecha_apertura DESC
LIMIT 10;

-- =====================================================
-- RECOMENDACIONES DE SOLUCIÓN:
-- =====================================================

/*
PASOS PARA SOLUCIONAR:

1. Ejecutar consulta #1 para ver si hay datos en app_dat_caja_turno
2. Ejecutar consulta #2 para ver qué estados existen realmente
3. Si no hay turnos con estado 2 o 3, cambiar el filtro a:
   AND ct.estado IN (1, 2, 3) -- Incluir turnos abiertos también

4. Verificar que los parámetros p_id_tpv y p_id_vendedor no sean demasiado restrictivos
5. Considerar usar LEFT JOIN en lugar de JOIN para tpv y vendedor si pueden faltar datos

CONSULTA MODIFICADA SUGERIDA:
- Cambiar: AND ct.estado IN (2, 3)
- Por: AND ct.estado IN (1, 2, 3) -- O eliminar este filtro completamente

- Cambiar: JOIN app_dat_tpv tpv ON ct.id_tpv = tpv.id
- Por: LEFT JOIN app_dat_tpv tpv ON ct.id_tpv = tpv.id

- Cambiar: JOIN app_dat_vendedor ven ON ct.id_vendedor = ven.id  
- Por: LEFT JOIN app_dat_vendedor ven ON ct.id_vendedor = ven.id
*/
