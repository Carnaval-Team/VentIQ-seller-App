# Implementación de RPC para Marketplace

## Resumen

Se creó una nueva función RPC `get_productos_marketplace` específica para el marketplace de VentIQ, basada en `get_productos_by_categoria_tpv_meta` pero con modificaciones importantes para permitir acceso global a productos de todas las tiendas.

---

## Archivos Creados

### 1. SQL - Función RPC
**Archivo**: `ventiq_marketplace/sql/get_productos_marketplace.sql`

**Función**: `get_productos_marketplace(id_tienda_param, id_categoria_param, solo_disponibles_param)`

**Características principales**:
- ✅ Parámetros opcionales (id_tienda y id_categoria pueden ser NULL)
- ✅ Sin restricción de TPV - todos los usuarios ven todos los productos
- ✅ Stock calculado de TODOS los almacenes (no solo del TPV)
- ✅ Metadatos extendidos con información de tienda y rating

### 2. Documentación
**Archivo**: `ventiq_marketplace/docs/GET_PRODUCTOS_MARKETPLACE.md`

**Contenido**:
- Descripción completa de la función
- Comparación con función original
- Estructura de parámetros y respuesta
- Ejemplos de uso
- Guía de integración con Flutter
- Consideraciones de rendimiento

### 3. Servicio Flutter
**Archivo**: `ventiq_marketplace/lib/services/marketplace_service.dart`

**Clase**: `MarketplaceService`

**Métodos implementados**:
- `getProducts()` - Método base con filtros opcionales
- `getAllProducts()` - Todos los productos
- `getProductsByStore()` - Productos por tienda
- `getProductsByCategory()` - Productos por categoría
- `getProductsByStoreAndCategory()` - Filtro combinado
- `getTopRatedProducts()` - Productos mejor calificados
- `searchProducts()` - Búsqueda por texto
- `getLowStockProducts()` - Productos con bajo stock
- `getStoreStatistics()` - Estadísticas por tienda
- `getRecommendedProducts()` - Productos recomendados

**Extension**: `ProductMetadata` para acceso fácil a metadatos

---

## Diferencias Clave con get_productos_by_categoria_tpv_meta

| Aspecto | Original (TPV) | Nuevo (Marketplace) |
|---------|----------------|---------------------|
| **id_tienda** | Requerido | Opcional (NULL = todas) |
| **id_categoria** | Requerido | Opcional (NULL = todas) |
| **id_tpv** | Requerido | No existe |
| **Filtro de almacén** | Solo almacén del TPV | Todos los almacenes |
| **Stock calculado** | Del almacén del TPV | De todos los almacenes |
| **Visibilidad** | Restringida por TPV | Global (todas las tiendas) |
| **Metadatos** | Básicos | Extendidos (tienda + rating) |

---

## Modificaciones Implementadas

### 1. ✅ Parámetros Opcionales

```sql
-- ANTES (requeridos)
id_tienda_param bigint,
id_categoria_param bigint,
id_tpv_param bigint

-- DESPUÉS (opcionales)
id_tienda_param bigint DEFAULT NULL,
id_categoria_param bigint DEFAULT NULL,
solo_disponibles_param boolean DEFAULT false
```

### 2. ✅ Sin Restricción de TPV

```sql
-- ANTES: Filtro por TPV
JOIN app_dat_tpv tpv ON tpv.id = id_tpv_param

-- DESPUÉS: Sin filtro de TPV
-- Cualquier usuario puede ver todos los productos
```

### 3. ✅ Stock de Todos los Almacenes

```sql
-- ANTES: Solo almacén del TPV
FROM app_dat_inventario_productos ip 
JOIN app_dat_layout_almacen la ON ip.id_ubicacion = la.id
JOIN app_dat_tpv tpv ON la.id_almacen = tpv.id_almacen
WHERE tpv.id = id_tpv_param

-- DESPUÉS: Todos los almacenes
FROM app_dat_inventario_productos ip 
WHERE ip.id_producto = p.id 
AND ip.cantidad_final > 0
```

### 4. ✅ Metadatos Extendidos

```sql
-- ANTES: Metadatos básicos
jsonb_build_object(
    'es_elaborado', p.es_elaborado,
    'es_servicio', p.es_servicio
)

-- DESPUÉS: Metadatos extendidos
jsonb_build_object(
    'es_elaborado', p.es_elaborado,
    'es_servicio', p.es_servicio,
    'denominacion_tienda', t.denominacion,  -- ✅ NUEVO
    'id_tienda', t.id,                      -- ✅ NUEVO
    'rating_promedio', COALESCE(            -- ✅ NUEVO
        (SELECT ROUND(AVG(pr.rating), 1)
         FROM app_dat_producto_rating pr
         WHERE pr.id_producto = p.id),
        0.0
    ),
    'total_ratings', COALESCE(              -- ✅ NUEVO
        (SELECT COUNT(*)
         FROM app_dat_producto_rating pr
         WHERE pr.id_producto = p.id),
        0
    )
)
```

---

## Estructura de Metadatos

### Campos Agregados

```json
{
  "es_elaborado": boolean,
  "es_servicio": boolean,
  "denominacion_tienda": "Nombre de la Tienda",
  "id_tienda": 123,
  "rating_promedio": 4.5,
  "total_ratings": 42
}
```

### Tabla de Rating

```sql
create table public.app_dat_producto_rating (
  id bigserial not null,
  id_producto bigint not null,
  id_usuario uuid not null,
  rating numeric(2, 1) not null,
  comentario text null,
  created_at timestamp with time zone null default now(),
  updated_at timestamp with time zone null default now(),
  constraint app_dat_producto_rating_rating_check check (
    (rating >= 1.0 and rating <= 5.0)
  )
)
```

**Cálculo del rating promedio**:
```sql
SELECT ROUND(AVG(pr.rating), 1)
FROM app_dat_producto_rating pr
WHERE pr.id_producto = p.id
```

---

## Ejemplos de Uso

### SQL Directo

```sql
-- Todos los productos
SELECT * FROM get_productos_marketplace();

-- Productos de una tienda
SELECT * FROM get_productos_marketplace(id_tienda_param := 1);

-- Productos de una categoría
SELECT * FROM get_productos_marketplace(id_categoria_param := 5);

-- Productos con stock de una categoría
SELECT * FROM get_productos_marketplace(
    id_categoria_param := 5, 
    solo_disponibles_param := true
);
```

### Flutter Service

```dart
final marketplaceService = MarketplaceService();

// Todos los productos con stock
final products = await marketplaceService.getAllProducts();

// Productos de una tienda
final storeProducts = await marketplaceService.getProductsByStore(1);

// Productos mejor calificados
final topRated = await marketplaceService.getTopRatedProducts(
  minRating: 4.5,
  limit: 10,
);

// Buscar productos
final searchResults = await marketplaceService.searchProducts(
  'aceite',
  idCategoria: 5,
);

// Usar extensión de metadatos
for (var product in products) {
  print('Tienda: ${product.storeName}');
  print('Rating: ${product.rating} (${product.totalRatings} reviews)');
  print('Stock: ${product.stockDisponible}');
}
```

---

## Integración con products_screen.dart

### Modificar el método _loadProducts()

```dart
import '../services/marketplace_service.dart';

class _ProductsScreenState extends State<ProductsScreen> {
  final MarketplaceService _marketplaceService = MarketplaceService();
  
  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    
    try {
      final products = await _marketplaceService.getAllProducts();
      
      setState(() {
        _products = products.map((p) => {
          'id': p['id_producto'],
          'nombre': p['denominacion'],
          'precio': p['precio_venta'],
          'imageUrl': p['imagen'],
          'tienda': p.storeName,
          'stock': p.stockDisponible,
          'rating': p.rating,
          'categoria': p['categoria_nombre'],
        }).toList();
        
        _filteredProducts = _products;
        _isLoading = false;
      });
    } catch (e) {
      print('Error cargando productos: $e');
      setState(() => _isLoading = false);
    }
  }
}
```

---

## Índices Recomendados

Para optimizar el rendimiento de la función:

```sql
-- Índice en app_dat_producto
CREATE INDEX IF NOT EXISTS idx_producto_tienda_vendible 
ON app_dat_producto(id_tienda, es_vendible);

-- Índice en app_dat_inventario_productos
CREATE INDEX IF NOT EXISTS idx_inventario_producto_cantidad 
ON app_dat_inventario_productos(id_producto, cantidad_final);

-- Índice en app_dat_producto_rating
CREATE INDEX IF NOT EXISTS idx_rating_producto 
ON app_dat_producto_rating(id_producto);

-- Índice en app_dat_productos_subcategorias
CREATE INDEX IF NOT EXISTS idx_productos_subcategorias 
ON app_dat_productos_subcategorias(id_producto, id_sub_categoria);
```

---

## Pasos para Implementar

### 1. Ejecutar SQL en Supabase

```bash
# Conectar a Supabase SQL Editor
# Copiar y ejecutar el contenido de:
ventiq_marketplace/sql/get_productos_marketplace.sql
```

### 2. Crear Índices

```sql
-- Ejecutar los índices recomendados
-- (Ver sección "Índices Recomendados")
```

### 3. Integrar Servicio en Flutter

```dart
// Agregar import en products_screen.dart
import '../services/marketplace_service.dart';

// Usar el servicio para cargar productos
final marketplaceService = MarketplaceService();
final products = await marketplaceService.getAllProducts();
```

### 4. Actualizar UI

```dart
// Adaptar el mapeo de datos según la estructura de respuesta
// Ver sección "Integración con products_screen.dart"
```

---

## Beneficios

1. **✅ Acceso Global**: Todos los usuarios pueden ver productos de todas las tiendas
2. **✅ Flexibilidad**: Filtros opcionales permiten búsquedas específicas
3. **✅ Información Rica**: Metadatos extendidos con tienda y rating
4. **✅ Stock Completo**: Visibilidad de inventario total, no solo de un almacén
5. **✅ Escalabilidad**: Diseño preparado para crecimiento del marketplace
6. **✅ Rendimiento**: Índices optimizados para consultas rápidas

---

## Consideraciones

### Rendimiento
- Usar filtros cuando sea posible para reducir resultados
- Implementar paginación en el cliente para grandes volúmenes
- Los índices son críticos para rendimiento óptimo

### Seguridad
- La función es pública por diseño (marketplace)
- No expone información sensible de inventario interno
- Los ratings son públicos y auditables

### Mantenimiento
- Documentación completa disponible
- Código bien comentado
- Ejemplos de uso incluidos

---

## Próximos Pasos

1. ✅ Ejecutar función SQL en Supabase
2. ✅ Crear índices recomendados
3. ⏳ Integrar MarketplaceService en products_screen.dart
4. ⏳ Implementar UI para mostrar ratings
5. ⏳ Agregar filtros avanzados en la UI
6. ⏳ Implementar paginación
7. ⏳ Testing completo

---

## Soporte

**Equipo**: VentIQ Development Team  
**Fecha**: 2025-11-10  
**Versión**: 1.0.0
