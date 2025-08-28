-- =====================================================
-- DIAGNÓSTICO PARA fn_cerrar_turno_tpv
-- =====================================================
-- Consultas para identificar por qué no se actualiza app_dat_caja_turno

-- 1. VERIFICAR SI EXISTE UN TURNO ABIERTO
SELECT 
  ct.id,
  ct.estado,
  ct.id_tpv,
  ct.fecha_apertura,
  ct.fecha_cierre,
  ct.id_operacion_apertura
FROM app_dat_caja_turno ct
WHERE ct.estado = 1  -- Solo turnos abiertos
ORDER BY ct.id DESC;

-- 2. VERIFICAR LA CONSULTA EXACTA QUE USA LA FUNCIÓN
-- (Reemplazar 1 con el p_id_tpv que estás usando)
SELECT 
  ct.id, 
  ct.id_operacion_apertura, 
  op.id_tienda,
  ct.estado,
  ct.id_tpv
FROM app_dat_caja_turno ct
JOIN app_dat_operaciones op ON ct.id_operacion_apertura = op.id
WHERE ct.id_tpv = 1 AND ct.estado = 1;

-- 3. VERIFICAR SI LA OPERACIÓN DE APERTURA EXISTE
SELECT 
  ct.id as turno_id,
  ct.id_operacion_apertura,
  op.id as operacion_id,
  op.id_tienda,
  op.id_tipo_operacion
FROM app_dat_caja_turno ct
LEFT JOIN app_dat_operaciones op ON ct.id_operacion_apertura = op.id
WHERE ct.estado = 1;

-- 4. VERIFICAR EL TIPO DE OPERACIÓN DE CIERRE
SELECT id, denominacion 
FROM app_nom_tipo_operacion 
WHERE denominacion = 'Cierre de Caja' OR id = 17;

-- 5. PROBAR EL UPDATE MANUALMENTE
-- (Reemplazar los valores con los reales)
/*
UPDATE app_dat_caja_turno
SET
  efectivo_real = 100.0,
  fecha_cierre = now(),
  estado = 2,
  observaciones = 'Prueba manual'
WHERE id = 1;  -- Reemplazar con el ID del turno abierto
*/

-- =====================================================
-- POSIBLES PROBLEMAS Y SOLUCIONES:
-- =====================================================

/*
PROBLEMA 1: NO ENCUENTRA TURNO ABIERTO
- La consulta JOIN con app_dat_operaciones puede fallar
- Verificar que id_operacion_apertura no sea NULL
- Verificar que la operación de apertura exista

PROBLEMA 2: TRANSACCIÓN NO SE CONFIRMA
- Si hay un error en cualquier parte, toda la transacción se revierte
- Verificar que no haya errores en los INSERT anteriores

PROBLEMA 3: PERMISOS RLS
- Las políticas de seguridad pueden estar bloqueando el UPDATE
- Verificar que el usuario tenga permisos de UPDATE en app_dat_caja_turno

PROBLEMA 4: CONSTRAINT VIOLATIONS
- Verificar que todos los campos requeridos estén presentes
- Verificar que los tipos de datos sean correctos

SOLUCIÓN SUGERIDA - FUNCIÓN MEJORADA:
*/
