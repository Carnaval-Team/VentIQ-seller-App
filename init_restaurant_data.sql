-- ============================================================================
-- SCRIPT DE INICIALIZACIÓN DEL MÓDULO RESTAURANTE
-- VentIQ - Sistema de Gestión de Restaurantes
-- ============================================================================

-- Limpiar datos existentes (opcional - comentar si no se desea)
-- DELETE FROM app_rest_descuentos_inventario;
-- DELETE FROM app_rest_estados_preparacion;
-- DELETE FROM app_rest_desperdicios;
-- DELETE FROM app_rest_disponibilidad_platos;
-- DELETE FROM app_rest_costos_produccion;
-- DELETE FROM app_dat_producto_unidades;
-- DELETE FROM app_nom_conversiones_unidades;
-- DELETE FROM app_nom_unidades_medida;

-- ============================================================================
-- 1. UNIDADES DE MEDIDA BÁSICAS
-- ============================================================================

-- Unidades de Peso (tipo 1)
INSERT INTO app_nom_unidades_medida (denominacion, abreviatura, tipo_unidad, es_base, factor_base, descripcion) VALUES
('Kilogramo', 'kg', 1, true, 1.0, 'Unidad base de peso en el sistema métrico'),
('Gramo', 'g', 1, false, 0.001, 'Unidad de peso - 1000g = 1kg'),
('Libra', 'lb', 1, false, 0.453592, 'Unidad de peso imperial - 1lb ≈ 453.6g'),
('Onza', 'oz', 1, false, 0.0283495, 'Unidad de peso imperial - 1oz ≈ 28.35g'),
('Tonelada', 't', 1, false, 1000.0, 'Unidad de peso - 1t = 1000kg');

-- Unidades de Volumen (tipo 2)
INSERT INTO app_nom_unidades_medida (denominacion, abreviatura, tipo_unidad, es_base, factor_base, descripcion) VALUES
('Litro', 'L', 2, true, 1.0, 'Unidad base de volumen en el sistema métrico'),
('Mililitro', 'ml', 2, false, 0.001, 'Unidad de volumen - 1000ml = 1L'),
('Galón', 'gal', 2, false, 3.78541, 'Unidad de volumen imperial - 1gal ≈ 3.785L'),
('Cuarto', 'qt', 2, false, 0.946353, 'Unidad de volumen imperial - 1qt ≈ 0.946L'),
('Taza', 'cup', 2, false, 0.236588, 'Unidad de volumen culinaria - 1cup ≈ 237ml'),
('Cucharada', 'tbsp', 2, false, 0.0147868, 'Unidad de volumen culinaria - 1tbsp ≈ 15ml'),
('Cucharadita', 'tsp', 2, false, 0.00492892, 'Unidad de volumen culinaria - 1tsp ≈ 5ml');

-- Unidades de Longitud (tipo 3)
INSERT INTO app_nom_unidades_medida (denominacion, abreviatura, tipo_unidad, es_base, factor_base, descripcion) VALUES
('Metro', 'm', 3, true, 1.0, 'Unidad base de longitud en el sistema métrico'),
('Centímetro', 'cm', 3, false, 0.01, 'Unidad de longitud - 100cm = 1m'),
('Milímetro', 'mm', 3, false, 0.001, 'Unidad de longitud - 1000mm = 1m'),
('Pulgada', 'in', 3, false, 0.0254, 'Unidad de longitud imperial - 1in = 2.54cm');

-- Unidades Discretas (tipo 4)
INSERT INTO app_nom_unidades_medida (denominacion, abreviatura, tipo_unidad, es_base, factor_base, descripcion) VALUES
('Unidad', 'un', 4, true, 1.0, 'Unidad base para conteo de elementos'),
('Docena', 'dz', 4, false, 12.0, 'Conjunto de 12 unidades'),
('Ciento', 'ct', 4, false, 100.0, 'Conjunto de 100 unidades'),
('Par', 'pr', 4, false, 2.0, 'Conjunto de 2 unidades'),
('Paquete', 'paq', 4, false, 1.0, 'Unidad de empaque variable'),
('Caja', 'cj', 4, false, 1.0, 'Unidad de empaque variable');

-- ============================================================================
-- 2. CONVERSIONES ENTRE UNIDADES
-- ============================================================================

-- Conversiones de Peso
INSERT INTO app_nom_conversiones_unidades (id_unidad_origen, id_unidad_destino, factor_conversion, es_aproximada, observaciones) VALUES
-- kg a otras unidades
((SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'kg'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'g'), 1000.0, false, 'Conversión exacta'),
((SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'kg'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'lb'), 2.20462, true, 'Conversión aproximada'),
((SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'kg'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'oz'), 35.274, true, 'Conversión aproximada'),

-- g a otras unidades
((SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'g'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'kg'), 0.001, false, 'Conversión exacta'),
((SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'g'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'oz'), 0.035274, true, 'Conversión aproximada'),

-- lb a otras unidades
((SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'lb'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'kg'), 0.453592, true, 'Conversión aproximada'),
((SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'lb'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'g'), 453.592, true, 'Conversión aproximada'),
((SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'lb'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'oz'), 16.0, false, 'Conversión exacta');

-- Conversiones de Volumen
INSERT INTO app_nom_conversiones_unidades (id_unidad_origen, id_unidad_destino, factor_conversion, es_aproximada, observaciones) VALUES
-- L a otras unidades
((SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'L'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'ml'), 1000.0, false, 'Conversión exacta'),
((SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'L'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'gal'), 0.264172, true, 'Conversión aproximada'),
((SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'L'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'qt'), 1.05669, true, 'Conversión aproximada'),
((SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'L'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'cup'), 4.22675, true, 'Conversión aproximada'),

-- ml a otras unidades
((SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'ml'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'L'), 0.001, false, 'Conversión exacta'),
((SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'ml'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'tbsp'), 0.067628, true, 'Conversión aproximada'),
((SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'ml'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'tsp'), 0.202884, true, 'Conversión aproximada'),

-- Conversiones culinarias
((SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'cup'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'ml'), 236.588, true, 'Conversión aproximada'),
((SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'cup'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'tbsp'), 16.0, false, 'Conversión exacta'),
((SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'tbsp'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'ml'), 14.7868, true, 'Conversión aproximada'),
((SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'tbsp'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'tsp'), 3.0, false, 'Conversión exacta'),
((SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'tsp'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'ml'), 4.92892, true, 'Conversión aproximada');

-- Conversiones de Unidades Discretas
INSERT INTO app_nom_conversiones_unidades (id_unidad_origen, id_unidad_destino, factor_conversion, es_aproximada, observaciones) VALUES
((SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'dz'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'un'), 12.0, false, 'Conversión exacta'),
((SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'ct'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'un'), 100.0, false, 'Conversión exacta'),
((SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'pr'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'un'), 2.0, false, 'Conversión exacta'),
((SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'un'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'dz'), 0.083333, true, 'Conversión aproximada'),
((SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'un'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'ct'), 0.01, false, 'Conversión exacta');

-- ============================================================================
-- 3. DATOS DE PRUEBA - PRODUCTOS DE INVENTARIO
-- ============================================================================

-- Insertar productos de prueba si no existen (ajustar según tu estructura de productos)
-- Nota: Estos INSERTs asumen que tienes una tabla app_dat_producto básica
-- Ajusta según tu estructura real de productos

/*
-- Productos básicos para restaurante
INSERT INTO app_dat_producto (denominacion, sku, um, descripcion) VALUES
('Harina de Trigo', 'HAR001', 'kg', 'Harina de trigo todo uso para panadería'),
('Azúcar Blanca', 'AZU001', 'kg', 'Azúcar refinada blanca'),
('Sal de Mesa', 'SAL001', 'kg', 'Sal refinada para cocina'),
('Aceite Vegetal', 'ACE001', 'L', 'Aceite vegetal para cocina'),
('Leche Entera', 'LEC001', 'L', 'Leche entera pasteurizada'),
('Huevos', 'HUE001', 'un', 'Huevos frescos de gallina'),
('Mantequilla', 'MAN001', 'kg', 'Mantequilla sin sal'),
('Pollo Entero', 'POL001', 'kg', 'Pollo entero fresco'),
('Carne de Res', 'CAR001', 'kg', 'Carne de res para guisar'),
('Tomate', 'TOM001', 'kg', 'Tomate fresco'),
('Cebolla', 'CEB001', 'kg', 'Cebolla blanca'),
('Ajo', 'AJO001', 'kg', 'Ajo fresco'),
('Arroz', 'ARR001', 'kg', 'Arroz blanco grano largo'),
('Frijoles', 'FRI001', 'kg', 'Frijoles negros secos'),
('Queso Mozzarella', 'QUE001', 'kg', 'Queso mozzarella para pizza');
*/

-- ============================================================================
-- 4. CONFIGURACIÓN DE UNIDADES POR PRODUCTO
-- ============================================================================

-- Ejemplo de configuración de unidades para productos
-- (Ajustar IDs según los productos reales en tu base de datos)

/*
-- Configurar unidades para Harina de Trigo
INSERT INTO app_dat_producto_unidades (id_producto, id_unidad_medida, factor_producto, es_unidad_compra, es_unidad_venta, es_unidad_inventario, observaciones) VALUES
((SELECT id FROM app_dat_producto WHERE sku = 'HAR001'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'kg'), 1.0, true, false, true, 'Unidad principal de inventario'),
((SELECT id FROM app_dat_producto WHERE sku = 'HAR001'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'g'), 1.0, false, true, false, 'Unidad para recetas'),
((SELECT id FROM app_dat_producto WHERE sku = 'HAR001'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'cup'), 0.125, false, true, false, 'Unidad culinaria - 1 cup ≈ 125g harina');

-- Configurar unidades para Aceite Vegetal
INSERT INTO app_dat_producto_unidades (id_producto, id_unidad_medida, factor_producto, es_unidad_compra, es_unidad_venta, es_unidad_inventario, observaciones) VALUES
((SELECT id FROM app_dat_producto WHERE sku = 'ACE001'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'L'), 1.0, true, false, true, 'Unidad principal de inventario'),
((SELECT id FROM app_dat_producto WHERE sku = 'ACE001'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'ml'), 1.0, false, true, false, 'Unidad para recetas'),
((SELECT id FROM app_dat_producto WHERE sku = 'ACE001'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'tbsp'), 1.0, false, true, false, 'Unidad culinaria');

-- Configurar unidades para Huevos
INSERT INTO app_dat_producto_unidades (id_producto, id_unidad_medida, factor_producto, es_unidad_compra, es_unidad_venta, es_unidad_inventario, observaciones) VALUES
((SELECT id FROM app_dat_producto WHERE sku = 'HUE001'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'un'), 1.0, true, true, true, 'Unidad principal'),
((SELECT id FROM app_dat_producto WHERE sku = 'HUE001'), (SELECT id FROM app_nom_unidades_medida WHERE abreviatura = 'dz'), 1.0, true, false, false, 'Unidad de compra');
*/

-- ============================================================================
-- 5. DATOS DE PRUEBA - CATEGORÍAS Y PLATOS
-- ============================================================================

-- Categorías de platos
INSERT INTO app_rest_categorias_platos (nombre, descripcion, orden_menu, es_activo, imagen) VALUES
('Entradas', 'Aperitivos y entradas', 1, true, NULL),
('Platos Principales', 'Platos fuertes del menú', 2, true, NULL),
('Postres', 'Dulces y postres', 3, true, NULL),
('Bebidas', 'Bebidas frías y calientes', 4, true, NULL),
('Ensaladas', 'Ensaladas frescas', 5, true, NULL);

-- Platos elaborados de ejemplo
INSERT INTO app_rest_platos_elaborados (nombre, descripcion, id_categoria, precio_venta, tiempo_preparacion, es_activo, instrucciones_preparacion) VALUES
('Pizza Margherita', 'Pizza clásica con tomate, mozzarella y albahaca', 
 (SELECT id FROM app_rest_categorias_platos WHERE nombre = 'Platos Principales'), 
 15.99, 25, true, 'Extender masa, agregar salsa, queso y hornear a 220°C por 12-15 min'),

('Ensalada César', 'Ensalada con lechuga, crutones, parmesano y aderezo césar', 
 (SELECT id FROM app_rest_categorias_platos WHERE nombre = 'Ensaladas'), 
 8.99, 10, true, 'Mezclar ingredientes, agregar aderezo y servir fresco'),

('Pollo a la Plancha', 'Pechuga de pollo marinada y cocinada a la plancha', 
 (SELECT id FROM app_rest_categorias_platos WHERE nombre = 'Platos Principales'), 
 12.99, 20, true, 'Marinar pollo, cocinar a la plancha 6-8 min por lado'),

('Tiramisu', 'Postre italiano con café, mascarpone y cacao', 
 (SELECT id FROM app_rest_categorias_platos WHERE nombre = 'Postres'), 
 6.99, 15, true, 'Preparar capas, refrigerar mínimo 4 horas'),

('Sopa de Tomate', 'Sopa cremosa de tomate con albahaca', 
 (SELECT id FROM app_rest_categorias_platos WHERE nombre = 'Entradas'), 
 5.99, 15, true, 'Cocinar tomates, licuar, agregar crema y especias');

-- ============================================================================
-- 6. RECETAS DE EJEMPLO
-- ============================================================================

-- Recetas para Pizza Margherita (ajustar IDs según productos reales)
/*
INSERT INTO app_rest_recetas (id_plato, id_producto_inventario, cantidad_requerida, um, observaciones, orden) VALUES
((SELECT id FROM app_rest_platos_elaborados WHERE nombre = 'Pizza Margherita'), (SELECT id FROM app_dat_producto WHERE sku = 'HAR001'), 200, 'g', 'Para la masa', 1),
((SELECT id FROM app_rest_platos_elaborados WHERE nombre = 'Pizza Margherita'), (SELECT id FROM app_dat_producto WHERE sku = 'TOM001'), 100, 'g', 'Para la salsa', 2),
((SELECT id FROM app_rest_platos_elaborados WHERE nombre = 'Pizza Margherita'), (SELECT id FROM app_dat_producto WHERE sku = 'QUE001'), 150, 'g', 'Queso mozzarella', 3),
((SELECT id FROM app_rest_platos_elaborados WHERE nombre = 'Pizza Margherita'), (SELECT id FROM app_dat_producto WHERE sku = 'ACE001'), 15, 'ml', 'Para la masa y cocción', 4);
*/

-- ============================================================================
-- 7. ÍNDICES PARA OPTIMIZACIÓN
-- ============================================================================

-- Índices para mejorar el rendimiento
CREATE INDEX IF NOT EXISTS idx_unidades_medida_tipo ON app_nom_unidades_medida(tipo_unidad);
CREATE INDEX IF NOT EXISTS idx_unidades_medida_abreviatura ON app_nom_unidades_medida(abreviatura);
CREATE INDEX IF NOT EXISTS idx_conversiones_origen_destino ON app_nom_conversiones_unidades(id_unidad_origen, id_unidad_destino);
CREATE INDEX IF NOT EXISTS idx_producto_unidades_producto ON app_dat_producto_unidades(id_producto);
CREATE INDEX IF NOT EXISTS idx_producto_unidades_tipo ON app_dat_producto_unidades(es_unidad_compra, es_unidad_venta, es_unidad_inventario);
CREATE INDEX IF NOT EXISTS idx_platos_categoria ON app_rest_platos_elaborados(id_categoria);
CREATE INDEX IF NOT EXISTS idx_platos_activo ON app_rest_platos_elaborados(es_activo);
CREATE INDEX IF NOT EXISTS idx_recetas_plato ON app_rest_recetas(id_plato);
CREATE INDEX IF NOT EXISTS idx_costos_plato_fecha ON app_rest_costos_produccion(id_plato, fecha_calculo);
CREATE INDEX IF NOT EXISTS idx_disponibilidad_plato_tienda ON app_rest_disponibilidad_platos(id_plato, id_tienda, fecha_revision);

-- ============================================================================
-- 8. VERIFICACIÓN DE DATOS
-- ============================================================================

-- Consultas para verificar que los datos se insertaron correctamente
SELECT 'Unidades de Medida' as tabla, COUNT(*) as registros FROM app_nom_unidades_medida
UNION ALL
SELECT 'Conversiones de Unidades' as tabla, COUNT(*) as registros FROM app_nom_conversiones_unidades
UNION ALL
SELECT 'Categorías de Platos' as tabla, COUNT(*) as registros FROM app_rest_categorias_platos
UNION ALL
SELECT 'Platos Elaborados' as tabla, COUNT(*) as registros FROM app_rest_platos_elaborados;

-- Mostrar unidades por tipo
SELECT 
    tipo_unidad,
    CASE tipo_unidad 
        WHEN 1 THEN 'Peso'
        WHEN 2 THEN 'Volumen' 
        WHEN 3 THEN 'Longitud'
        WHEN 4 THEN 'Unidad'
        ELSE 'Desconocido'
    END as tipo_descripcion,
    COUNT(*) as cantidad_unidades
FROM app_nom_unidades_medida 
GROUP BY tipo_unidad 
ORDER BY tipo_unidad;

-- Mostrar conversiones disponibles
SELECT 
    uo.denominacion || ' (' || uo.abreviatura || ')' as unidad_origen,
    ud.denominacion || ' (' || ud.abreviatura || ')' as unidad_destino,
    c.factor_conversion,
    CASE WHEN c.es_aproximada THEN 'Aproximada' ELSE 'Exacta' END as precision
FROM app_nom_conversiones_unidades c
JOIN app_nom_unidades_medida uo ON c.id_unidad_origen = uo.id
JOIN app_nom_unidades_medida ud ON c.id_unidad_destino = ud.id
ORDER BY uo.tipo_unidad, uo.denominacion, ud.denominacion;

-- ============================================================================
-- SCRIPT COMPLETADO
-- ============================================================================

-- Mensaje de finalización
SELECT 'Inicialización del módulo restaurante completada exitosamente' as mensaje;
