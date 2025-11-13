-- =====================================================
-- SCRIPT DE PRUEBAS PARA CONSTRAINT CONDICIONAL
-- =====================================================
-- Este script prueba el comportamiento de la nueva constraint condicional
-- en diferentes escenarios de configuración de tienda
-- =====================================================

-- 1. VERIFICAR ESTADO ACTUAL DE LA CONSTRAINT
-- =====================================================
SELECT 
    'VERIFICACIÓN DE CONSTRAINT' as test_type,
    conname as constraint_name,
    contype as constraint_type,
    CASE 
        WHEN conname = 'chk_cantidad_final_conditional' THEN '✅ Constraint aplicada correctamente'
        ELSE '❌ Constraint no encontrada'
    END as status
FROM pg_constraint 
WHERE conrelid = 'public.app_dat_inventario_productos'::regclass
AND conname = 'chk_cantidad_final_conditional';

-- 2. VERIFICAR CONFIGURACIONES DE TIENDA EXISTENTES
-- =====================================================
SELECT 
    'CONFIGURACIONES DE TIENDA' as test_type,
    t.id as tienda_id,
    t.denominacion as tienda_nombre,
    COALESCE(ct.permite_vender_aun_sin_disponibilidad, false) as permite_negativo,
    CASE 
        WHEN ct.permite_vender_aun_sin_disponibilidad = true THEN '✅ Permite cantidades negativas'
        WHEN ct.permite_vender_aun_sin_disponibilidad = false THEN '⚠️ NO permite cantidades negativas'
        ELSE '❓ Sin configuración (default: NO permite)'
    END as comportamiento_esperado
FROM app_dat_tienda t
LEFT JOIN app_dat_configuracion_tienda ct ON t.id = ct.id_tienda
ORDER BY t.id;

-- 3. VERIFICAR PRODUCTOS EXISTENTES POR TIENDA
-- =====================================================
SELECT 
    'PRODUCTOS POR TIENDA' as test_type,
    t.id as tienda_id,
    t.denominacion as tienda_nombre,
    COUNT(p.id) as total_productos,
    COALESCE(ct.permite_vender_aun_sin_disponibilidad, false) as permite_negativo
FROM app_dat_tienda t
LEFT JOIN app_dat_configuracion_tienda ct ON t.id = ct.id_tienda
LEFT JOIN app_dat_producto p ON t.id = p.id_tienda
GROUP BY t.id, t.denominacion, ct.permite_vender_aun_sin_disponibilidad
ORDER BY t.id;

-- 4. PROBAR FUNCIONES AUXILIARES
-- =====================================================
-- Verificar que las funciones auxiliares funcionan correctamente

-- Función de validación principal
SELECT 
    'FUNCIÓN VALIDACIÓN PRINCIPAL' as test_type,
    p.id as producto_id,
    p.denominacion as producto_nombre,
    t.denominacion as tienda_nombre,
    fn_validar_cantidad_final_inventario(p.id, -10) as permite_negativo_menos_10,
    fn_validar_cantidad_final_inventario(p.id, 0) as permite_cero,
    fn_validar_cantidad_final_inventario(p.id, 10) as permite_positivo_10,
    COALESCE(ct.permite_vender_aun_sin_disponibilidad, false) as config_tienda
FROM app_dat_producto p
INNER JOIN app_dat_tienda t ON p.id_tienda = t.id
LEFT JOIN app_dat_configuracion_tienda ct ON t.id = ct.id_tienda
LIMIT 5;

-- Función auxiliar de verificación
SELECT 
    'FUNCIÓN AUXILIAR' as test_type,
    p.id as producto_id,
    p.denominacion as producto_nombre,
    t.denominacion as tienda_nombre,
    fn_puede_tener_cantidad_negativa(p.id) as puede_negativo,
    COALESCE(ct.permite_vender_aun_sin_disponibilidad, false) as config_tienda
FROM app_dat_producto p
INNER JOIN app_dat_tienda t ON p.id_tienda = t.id
LEFT JOIN app_dat_configuracion_tienda ct ON t.id = ct.id_tienda
LIMIT 5;

-- 5. SIMULACIÓN DE INSERCIÓN (SIN EJECUTAR)
-- =====================================================
-- Estas queries muestran qué pasaría al insertar registros con cantidades negativas

-- Ejemplo A: Tienda que PERMITE cantidades negativas
SELECT 
    'SIMULACIÓN - TIENDA PERMITE NEGATIVO' as test_type,
    p.id as producto_id,
    p.denominacion as producto_nombre,
    t.denominacion as tienda_nombre,
    ct.permite_vender_aun_sin_disponibilidad as permite_negativo,
    'INSERT con cantidad_final = -10 → DEBERÍA FUNCIONAR' as resultado_esperado
FROM app_dat_producto p
INNER JOIN app_dat_tienda t ON p.id_tienda = t.id
INNER JOIN app_dat_configuracion_tienda ct ON t.id = ct.id_tienda
WHERE ct.permite_vender_aun_sin_disponibilidad = true
LIMIT 3;

-- Ejemplo B: Tienda que NO PERMITE cantidades negativas
SELECT 
    'SIMULACIÓN - TIENDA NO PERMITE NEGATIVO' as test_type,
    p.id as producto_id,
    p.denominacion as producto_nombre,
    t.denominacion as tienda_nombre,
    COALESCE(ct.permite_vender_aun_sin_disponibilidad, false) as permite_negativo,
    'INSERT con cantidad_final = -10 → DEBERÍA FALLAR' as resultado_esperado
FROM app_dat_producto p
INNER JOIN app_dat_tienda t ON p.id_tienda = t.id
LEFT JOIN app_dat_configuracion_tienda ct ON t.id = ct.id_tienda
WHERE COALESCE(ct.permite_vender_aun_sin_disponibilidad, false) = false
LIMIT 3;

-- 6. VERIFICAR REGISTROS EXISTENTES CON CANTIDAD FINAL
-- =====================================================
SELECT 
    'INVENTARIO EXISTENTE' as test_type,
    COUNT(*) as total_registros,
    COUNT(CASE WHEN cantidad_final < 0 THEN 1 END) as registros_negativos,
    COUNT(CASE WHEN cantidad_final = 0 THEN 1 END) as registros_cero,
    COUNT(CASE WHEN cantidad_final > 0 THEN 1 END) as registros_positivos,
    COUNT(CASE WHEN cantidad_final IS NULL THEN 1 END) as registros_null
FROM app_dat_inventario_productos;

-- 7. ANÁLISIS DETALLADO DE REGISTROS NEGATIVOS (SI EXISTEN)
-- =====================================================
SELECT 
    'REGISTROS NEGATIVOS EXISTENTES' as test_type,
    ip.id,
    p.denominacion as producto,
    t.denominacion as tienda,
    ip.cantidad_final,
    COALESCE(ct.permite_vender_aun_sin_disponibilidad, false) as tienda_permite_negativo,
    CASE 
        WHEN ct.permite_vender_aun_sin_disponibilidad = true THEN '✅ Válido'
        ELSE '❌ Debería ser corregido'
    END as estado_validacion
FROM app_dat_inventario_productos ip
INNER JOIN app_dat_producto p ON ip.id_producto = p.id
INNER JOIN app_dat_tienda t ON p.id_tienda = t.id
LEFT JOIN app_dat_configuracion_tienda ct ON t.id = ct.id_tienda
WHERE ip.cantidad_final < 0
ORDER BY ip.cantidad_final ASC
LIMIT 10;

-- 8. RESUMEN DE VALIDACIÓN
-- =====================================================
SELECT 
    'RESUMEN DE VALIDACIÓN' as test_type,
    'Constraint aplicada' as check_1,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM pg_constraint 
            WHERE conrelid = 'public.app_dat_inventario_productos'::regclass
            AND conname = 'chk_cantidad_final_conditional'
        ) THEN '✅ OK'
        ELSE '❌ FALTA'
    END as status_1,
    
    'Funciones creadas' as check_2,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM pg_proc 
            WHERE proname = 'fn_validar_cantidad_final_inventario'
        ) AND EXISTS (
            SELECT 1 FROM pg_proc 
            WHERE proname = 'fn_puede_tener_cantidad_negativa'
        ) THEN '✅ OK'
        ELSE '❌ FALTA'
    END as status_2,
    
    'Índice de optimización' as check_3,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM pg_indexes 
            WHERE indexname = 'idx_producto_tienda_config_inventario'
        ) THEN '✅ OK'
        ELSE '❌ FALTA'
    END as status_3;

-- =====================================================
-- INSTRUCCIONES PARA PRUEBAS REALES:
-- =====================================================
/*
PASO 1: Ejecuta este script completo para ver el estado actual

PASO 2: Para probar inserción real (CUIDADO - solo en desarrollo):

-- Ejemplo con tienda que PERMITE negativo:
INSERT INTO app_dat_inventario_productos (
    id_producto, 
    id_presentacion, 
    cantidad_inicial, 
    cantidad_final, 
    origen_cambio
) 
SELECT 
    p.id,
    1, -- Asegúrate que existe esta presentación
    10,
    -5, -- Cantidad negativa
    1
FROM app_dat_producto p
INNER JOIN app_dat_tienda t ON p.id_tienda = t.id
INNER JOIN app_dat_configuracion_tienda ct ON t.id = ct.id_tienda
WHERE ct.permite_vender_aun_sin_disponibilidad = true
LIMIT 1;

-- Ejemplo con tienda que NO PERMITE negativo (debería fallar):
INSERT INTO app_dat_inventario_productos (
    id_producto, 
    id_presentacion, 
    cantidad_inicial, 
    cantidad_final, 
    origen_cambio
) 
SELECT 
    p.id,
    1, -- Asegúrate que existe esta presentación
    10,
    -5, -- Cantidad negativa - DEBERÍA FALLAR
    1
FROM app_dat_producto p
INNER JOIN app_dat_tienda t ON p.id_tienda = t.id
LEFT JOIN app_dat_configuracion_tienda ct ON t.id = ct.id_tienda
WHERE COALESCE(ct.permite_vender_aun_sin_disponibilidad, false) = false
LIMIT 1;

PASO 3: Verifica los resultados y ajusta la configuración según necesites
*/

-- =====================================================
PRINT 'Script de pruebas ejecutado completamente';
PRINT 'Revisa los resultados para validar el comportamiento de la constraint';
