# Función RPC: get_productos_marketplace

## Descripción
Función PostgreSQL para obtener productos del marketplace con filtros opcionales. Esta función permite a cualquier usuario ver productos de todas las tiendas sin restricciones de TPV.

## Diferencias con get_productos_by_categoria_tpv_meta

| Característica | get_productos_by_categoria_tpv_meta | get_productos_marketplace |
|----------------|-------------------------------------|---------------------------|
| **id_tienda** | Requerido | Opcional (NULL = todas) |
| **id_categoria** | Requerido | Opcional (NULL = todas) |
| **Filtro TPV** | Solo almacén del TPV | Todos los almacenes |
| **Stock** | Solo del almacén del TPV | De todos los almacenes |
| **Visibilidad** | Restringida por TPV | Global (todas las tiendas) |
| **Metadatos** | Básicos | Extendidos (tienda + rating) |

## Parámetros

### Entrada

```sql
get_productos_marketplace(
    id_tienda_param bigint DEFAULT NULL,
    id_categoria_param bigint DEFAULT NULL,
    solo_disponibles_param boolean DEFAULT false
)
```

| Parámetro | Tipo | Requerido | Default | Descripción |
|-----------|------|-----------|---------|-------------|
| `id_tienda_param` | bigint | No | NULL | ID de la tienda (NULL = todas las tiendas) |
| `id_categoria_param` | bigint | No | NULL | ID de la categoría (NULL = todas las categorías) |
| `solo_disponibles_param` | boolean | No | false | Filtrar solo productos con stock > 0 |

### Salida

```sql
RETURNS TABLE (
    id_producto bigint,
    sku text,
    denominacion text,
    descripcion text,
    um text,
    es_refrigerado boolean,
    es_fragil boolean,
    es_vendible boolean,
    codigo_barras text,
    id_subcategoria bigint,
    subcategoria_nombre text,
    id_categoria bigint,
    categoria_nombre text,
    precio_venta numeric,
    imagen text,
    stock_disponible numeric,
    tiene_stock boolean,
    metadata jsonb
)
```

## Estructura de Metadatos (metadata)

El campo `metadata` es un objeto JSONB con la siguiente estructura:

```json
{
  "es_elaborado": boolean,
  "es_servicio": boolean,
  "denominacion_tienda": string,
  "id_tienda": bigint,
  "rating_promedio": numeric(2,1),
  "total_ratings": bigint,
  "presentaciones": [
    {
      "id": bigint,
      "id_presentacion": bigint,
      "denominacion": string,
      "descripcion": string,
      "sku_codigo": string,
      "cantidad": numeric,
      "es_base": boolean
    }
  ]
}
```

### Campos de Metadata

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `es_elaborado` | boolean | Indica si el producto es elaborado |
| `es_servicio` | boolean | Indica si el producto es un servicio |
| `denominacion_tienda` | string | Nombre de la tienda que vende el producto |
| `id_tienda` | bigint | ID de la tienda |
| `rating_promedio` | numeric(2,1) | Promedio de calificaciones (1.0 - 5.0) |
| `total_ratings` | bigint | Cantidad total de calificaciones |
| `presentaciones` | array | Lista de presentaciones disponibles del producto |

### Estructura de Presentaciones

Cada elemento en el array `presentaciones` contiene:

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | bigint | ID de la relación producto-presentación |
| `id_presentacion` | bigint | ID de la presentación |
| `denominacion` | string | Nombre de la presentación (ej: "Unidad", "Caja", "Six Pack") |
| `descripcion` | string | Descripción de la presentación |
| `sku_codigo` | string | Código SKU de la presentación |
| `cantidad` | numeric | Cantidad de unidades que representa (ej: 1, 6, 24) |
| `es_base` | boolean | Indica si es la presentación base del producto |

## Cálculo de Rating

El rating promedio se calcula desde la tabla `app_dat_producto_rating`:

```sql
SELECT ROUND(AVG(pr.rating), 1)
FROM app_dat_producto_rating pr
WHERE pr.id_producto = p.id
```

- **Rango**: 1.0 - 5.0
- **Precisión**: 1 decimal
- **Default**: 0.0 si no hay ratings

## Cálculo de Stock

El stock se calcula sumando TODOS los almacenes (sin restricción de TPV):

```sql
SELECT SUM(ip.cantidad_final) 
FROM app_dat_inventario_productos ip 
WHERE ip.id_producto = p.id 
AND ip.cantidad_final > 0
AND ip.id = (
    SELECT MAX(ip2.id) 
    FROM app_dat_inventario_productos ip2 
    WHERE ip2.id_producto = ip.id_producto 
    AND COALESCE(ip2.id_variante, 0) = COALESCE(ip.id_variante, 0)
    AND COALESCE(ip2.id_opcion_variante, 0) = COALESCE(ip.id_opcion_variante, 0)
    AND COALESCE(ip2.id_presentacion, 0) = COALESCE(ip.id_presentacion, 0)
    AND COALESCE(ip2.id_ubicacion, 0) = COALESCE(ip.id_ubicacion, 0)
)
```

## Ejemplos de Uso

### 1. Obtener todos los productos de todas las tiendas

```sql
SELECT * FROM get_productos_marketplace();
```

**Resultado**: Todos los productos vendibles de todas las tiendas

---

### 2. Obtener productos de una tienda específica

```sql
SELECT * FROM get_productos_marketplace(id_tienda_param := 1);
```

**Resultado**: Solo productos de la tienda con ID = 1

---

### 3. Obtener productos de una categoría específica

```sql
SELECT * FROM get_productos_marketplace(id_categoria_param := 5);
```

**Resultado**: Productos de la categoría 5 de todas las tiendas

---

### 4. Obtener productos de una tienda y categoría específicas

```sql
SELECT * FROM get_productos_marketplace(
    id_tienda_param := 1, 
    id_categoria_param := 5
);
```

**Resultado**: Productos de la tienda 1 en la categoría 5

---

### 5. Obtener solo productos con stock disponible

```sql
SELECT * FROM get_productos_marketplace(solo_disponibles_param := true);
```

**Resultado**: Solo productos con stock > 0

---

### 6. Productos con stock de una categoría específica

```sql
SELECT * FROM get_productos_marketplace(
    id_categoria_param := 5, 
    solo_disponibles_param := true
);
```

**Resultado**: Productos con stock de la categoría 5

---

### 7. Productos con rating alto (usando metadata)

```sql
SELECT 
    denominacion,
    precio_venta,
    (metadata->>'rating_promedio')::numeric AS rating,
    (metadata->>'total_ratings')::bigint AS num_ratings,
    metadata->>'denominacion_tienda' AS tienda
FROM get_productos_marketplace(solo_disponibles_param := true)
WHERE (metadata->>'rating_promedio')::numeric >= 4.5
ORDER BY (metadata->>'rating_promedio')::numeric DESC;
```

**Resultado**: Productos con rating ≥ 4.5, ordenados por rating

---

## Filtros Aplicados

### Filtros Automáticos (siempre aplicados)

1. **es_vendible = true**: Solo productos marcados como vendibles
2. **pri.id IS NULL**: Excluye ingredientes de productos elaborados
3. **Registros más recientes**: Solo el inventario más actualizado por combinación única

### Filtros Opcionales

1. **id_tienda_param**: Filtra por tienda específica
2. **id_categoria_param**: Filtra por categoría específica
3. **solo_disponibles_param**: Filtra solo productos con stock > 0

## Tablas Involucradas

| Tabla | Alias | Propósito |
|-------|-------|-----------|
| `app_dat_producto` | p | Datos principales del producto |
| `app_dat_tienda` | t | Información de la tienda |
| `app_dat_productos_subcategorias` | ps | Relación producto-subcategoría |
| `app_dat_subcategorias` | sc | Datos de subcategorías |
| `app_dat_categoria` | c | Datos de categorías |
| `app_dat_producto_ingredientes` | pri | Excluir ingredientes |
| `app_dat_precio_venta` | pv | Precios de venta |
| `app_dat_inventario_productos` | ip | Stock disponible |
| `app_dat_producto_rating` | pr | Calificaciones de productos |

## Permisos Requeridos

Para ejecutar esta función, el usuario debe tener:

- **SELECT** en todas las tablas involucradas
- **EXECUTE** en la función RPC

## Índices Recomendados

Para optimizar el rendimiento:

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

## Consideraciones de Rendimiento

1. **Cálculo de Rating**: Se ejecuta una subconsulta por cada producto
2. **Cálculo de Stock**: Se ejecuta una subconsulta por cada producto
3. **Filtros Opcionales**: Usar filtros reduce significativamente el tiempo de respuesta
4. **Índices**: Asegurar que los índices recomendados estén creados

### Recomendaciones

- Usar `id_tienda_param` cuando sea posible para limitar resultados
- Usar `id_categoria_param` para búsquedas específicas
- Usar `solo_disponibles_param := true` para marketplace activo
- Implementar paginación en el cliente para grandes volúmenes

## Integración con Flutter

### Ejemplo de Servicio

```dart
class MarketplaceService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getProducts({
    int? idTienda,
    int? idCategoria,
    bool soloDisponibles = false,
  }) async {
    try {
      final response = await _supabase.rpc(
        'get_productos_marketplace',
        params: {
          'id_tienda_param': idTienda,
          'id_categoria_param': idCategoria,
          'solo_disponibles_param': soloDisponibles,
        },
      );

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo productos: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getProductsByStore(int storeId) async {
    return await getProducts(idTienda: storeId, soloDisponibles: true);
  }

  Future<List<Map<String, dynamic>>> getProductsByCategory(int categoryId) async {
    return await getProducts(idCategoria: categoryId, soloDisponibles: true);
  }

  Future<List<Map<String, dynamic>>> getTopRatedProducts() async {
    final products = await getProducts(soloDisponibles: true);
    
    products.sort((a, b) {
      final ratingA = a['metadata']['rating_promedio'] ?? 0.0;
      final ratingB = b['metadata']['rating_promedio'] ?? 0.0;
      return ratingB.compareTo(ratingA);
    });
    
    return products.take(10).toList();
  }
}
```

## Changelog

### Versión 1.1.0 (2025-11-10)
- ✅ Agregado de presentaciones del producto en metadata
- ✅ Incluye denominación, cantidad y si es presentación base
- ✅ Ordenado por presentación base primero, luego alfabéticamente

### Versión 1.0.0 (2025-11-10)
- ✅ Creación inicial de la función
- ✅ Parámetros opcionales para tienda y categoría
- ✅ Eliminación de restricción de TPV
- ✅ Cálculo de stock de todos los almacenes
- ✅ Agregado de denominación de tienda en metadata
- ✅ Agregado de rating promedio en metadata
- ✅ Agregado de total de ratings en metadata

## Soporte

Para reportar problemas o sugerencias:
- **Equipo**: VentIQ Development Team
- **Fecha**: 2025-11-10
