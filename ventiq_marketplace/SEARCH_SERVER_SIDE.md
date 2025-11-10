# Búsqueda del Lado del Servidor - Marketplace VentIQ

## 📋 Resumen

Se movió la lógica de búsqueda del cliente (Flutter) al servidor (PostgreSQL) para permitir búsquedas en toda la base de datos, no solo en los productos paginados. Incluye búsqueda fonética y normalización de texto.

## 🎯 Problema Resuelto

### Antes:
- ❌ Búsqueda solo en productos ya cargados (paginación limitada)
- ❌ Si el producto buscado está en página 5, no se encuentra
- ❌ Filtrado en el cliente consume recursos
- ❌ No aprovecha índices de base de datos

### Después:
- ✅ Búsqueda en TODA la base de datos
- ✅ Encuentra productos sin importar la página
- ✅ Búsqueda fonética (sin acentos)
- ✅ Búsqueda en múltiples campos
- ✅ Optimizada con índices de PostgreSQL

## 🗄️ Cambios en Base de Datos

### Función RPC Actualizada

**Archivo**: `ventiq_marketplace/sql/get_productos_marketplace.sql`

#### Nuevo Parámetro:
```sql
CREATE OR REPLACE FUNCTION get_productos_marketplace(
    id_tienda_param bigint DEFAULT NULL,
    id_categoria_param bigint DEFAULT NULL,
    solo_disponibles_param boolean DEFAULT false,
    search_query_param text DEFAULT NULL,  -- ✅ NUEVO
    limit_param integer DEFAULT 50,
    offset_param integer DEFAULT 0
)
```

#### Filtro de Búsqueda Fonética:
```sql
-- Filtro de búsqueda flexible (búsqueda fonética en múltiples campos)
(search_query_param IS NULL OR search_query_param = '' OR (
    -- Normalizar texto para búsqueda fonética (sin acentos, minúsculas)
    unaccent(LOWER(p.denominacion)) LIKE '%' || unaccent(LOWER(search_query_param)) || '%' OR
    unaccent(LOWER(p.descripcion)) LIKE '%' || unaccent(LOWER(search_query_param)) || '%' OR
    unaccent(LOWER(p.sku)) LIKE '%' || unaccent(LOWER(search_query_param)) || '%' OR
    unaccent(LOWER(p.codigo_barras)) LIKE '%' || unaccent(LOWER(search_query_param)) || '%' OR
    unaccent(LOWER(c.denominacion)) LIKE '%' || unaccent(LOWER(search_query_param)) || '%' OR
    unaccent(LOWER(sc.denominacion)) LIKE '%' || unaccent(LOWER(search_query_param)) || '%' OR
    unaccent(LOWER(t.denominacion)) LIKE '%' || unaccent(LOWER(search_query_param)) || '%'
))
```

#### Campos Buscados:
1. **p.denominacion** - Nombre del producto
2. **p.descripcion** - Descripción del producto
3. **p.sku** - Código SKU
4. **p.codigo_barras** - Código de barras
5. **c.denominacion** - Nombre de la categoría
6. **sc.denominacion** - Nombre de la subcategoría
7. **t.denominacion** - Nombre de la tienda

### Función unaccent()

**Requisito**: Extensión `unaccent` de PostgreSQL

```sql
-- Habilitar la extensión (ejecutar una vez)
CREATE EXTENSION IF NOT EXISTS unaccent;
```

**Funcionalidad**:
- Elimina acentos: `"Piña"` → `"Pina"`
- Normaliza ñ: `"Niño"` → `"Nino"`
- Case-insensitive con `LOWER()`

## 📱 Cambios en Flutter

### 1. MarketplaceService

**Archivo**: `lib/services/marketplace_service.dart`

#### Método getProducts() Actualizado:
```dart
Future<List<Map<String, dynamic>>> getProducts({
  int? idTienda,
  int? idCategoria,
  bool soloDisponibles = false,
  String? searchQuery,  // ✅ NUEVO
  int limit = 50,
  int offset = 0,
}) async {
  final response = await _supabase.rpc(
    'get_productos_marketplace',
    params: {
      'id_tienda_param': idTienda,
      'id_categoria_param': idCategoria,
      'solo_disponibles_param': soloDisponibles,
      'search_query_param': searchQuery,  // ✅ NUEVO
      'limit_param': limit,
      'offset_param': offset,
    },
  );
  // ...
}
```

#### Método searchProducts() Simplificado:
```dart
Future<List<Map<String, dynamic>>> searchProducts(
  String searchText, {
  int? idCategoria,
  int limit = 100,
}) async {
  // La búsqueda ahora se hace en el servidor
  final products = await getProducts(
    idCategoria: idCategoria,
    soloDisponibles: true,
    searchQuery: searchText.trim(),
    limit: limit,
  );
  return products;
}
```

### 2. ProductsScreen

**Archivo**: `lib/screens/products_screen.dart`

#### Código Eliminado:
- ❌ `_filteredProducts` - Ya no se necesita
- ❌ `_normalizeText()` - Normalización en servidor
- ❌ `_matchesQuery()` - Búsqueda en servidor
- ❌ `_applyFilters()` - Filtrado en servidor

#### Código Agregado:

**Debounce para búsqueda:**
```dart
// Debounce para búsqueda
Timer? _debounceTimer;

void _onSearchChanged(String query) {
  // Cancelar el timer anterior si existe
  _debounceTimer?.cancel();
  
  // Crear nuevo timer de 500ms
  _debounceTimer = Timer(const Duration(milliseconds: 500), () {
    // Recargar productos con la nueva búsqueda
    _loadProducts(reset: true);
  });
}
```

**Búsqueda en _loadProducts():**
```dart
Future<void> _loadProducts({bool reset = false}) async {
  // ...
  
  // Obtener query de búsqueda
  final searchQuery = _searchController.text.trim();
  
  final newProducts = await _marketplaceService.getProducts(
    idTienda: null,
    idCategoria: _selectedCategoryId,
    soloDisponibles: true,
    searchQuery: searchQuery.isEmpty ? null : searchQuery,  // ✅ NUEVO
    limit: _pageSize,
    offset: _currentOffset,
  );
  
  // ...
}
```

## 🔍 Ejemplos de Búsqueda

### Búsqueda Fonética:
```dart
// Usuario escribe: "camaron"
// Encuentra: "Camarón", "camarones", "CAMARON"

// Usuario escribe: "pina colada"
// Encuentra: "Piña Colada", "PIÑA COLADA"

// Usuario escribe: "nino"
// Encuentra: "Niño", "niños"
```

### Búsqueda por SKU:
```dart
// Usuario escribe: "SKU-123"
// Encuentra productos con ese SKU exacto
```

### Búsqueda por Código de Barras:
```dart
// Usuario escribe: "7501234567890"
// Encuentra el producto con ese código de barras
```

### Búsqueda por Categoría:
```dart
// Usuario escribe: "bebidas"
// Encuentra todos los productos de la categoría Bebidas
```

### Búsqueda por Tienda:
```dart
// Usuario escribe: "bodega central"
// Encuentra todos los productos de esa tienda
```

## ⚡ Optimizaciones

### 1. Debounce de 500ms
- Evita búsquedas en cada tecla
- Reduce carga en el servidor
- Mejora UX con menos parpadeos

### 2. Índices Recomendados

```sql
-- Índice para búsqueda por denominación
CREATE INDEX IF NOT EXISTS idx_producto_denominacion_trgm 
ON app_dat_producto USING gin (denominacion gin_trgm_ops);

-- Índice para búsqueda por SKU
CREATE INDEX IF NOT EXISTS idx_producto_sku 
ON app_dat_producto (sku);

-- Índice para búsqueda por código de barras
CREATE INDEX IF NOT EXISTS idx_producto_codigo_barras 
ON app_dat_producto (codigo_barras);

-- Habilitar extensión pg_trgm para búsquedas más rápidas
CREATE EXTENSION IF NOT EXISTS pg_trgm;
```

### 3. Límite de Resultados
- Búsquedas retornan máximo 100 resultados por defecto
- Paginación sigue funcionando normalmente
- Evita sobrecargar el cliente con miles de resultados

## 📊 Comparación de Performance

### Antes (Búsqueda en Cliente):
```
1. Cargar 20 productos (página 1)
2. Buscar "cerveza" en 20 productos
3. Resultado: 2 productos encontrados
4. Producto en página 5 NO se encuentra ❌
```

### Después (Búsqueda en Servidor):
```
1. Buscar "cerveza" en TODA la BD
2. PostgreSQL usa índices optimizados
3. Resultado: 45 productos encontrados ✅
4. Incluye productos de todas las páginas
```

## 🚀 Para Aplicar los Cambios

### 1. Habilitar Extensiones en PostgreSQL:
```sql
-- Ejecutar en tu base de datos
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
```

### 2. Actualizar Función RPC:
```bash
psql -U postgres -d tu_base_datos -f ventiq_marketplace/sql/get_productos_marketplace.sql
```

### 3. Crear Índices (Opcional pero Recomendado):
```sql
-- Ejecutar en tu base de datos
CREATE INDEX IF NOT EXISTS idx_producto_denominacion_trgm 
ON app_dat_producto USING gin (denominacion gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_producto_sku 
ON app_dat_producto (sku);

CREATE INDEX IF NOT EXISTS idx_producto_codigo_barras 
ON app_dat_producto (codigo_barras);
```

### 4. Hot Reload en Flutter:
- Los cambios en Flutter se aplican automáticamente
- No requiere reinstalación de la app

## 🧪 Testing

### Casos de Prueba:

1. **Búsqueda sin acentos**:
   - Buscar: `"pina"`
   - Debe encontrar: `"Piña Colada"`

2. **Búsqueda parcial**:
   - Buscar: `"cerv"`
   - Debe encontrar: `"Cerveza Cristal"`, `"Cerveza Corona"`

3. **Búsqueda por SKU**:
   - Buscar: `"SKU-123"`
   - Debe encontrar el producto con ese SKU

4. **Búsqueda en categoría**:
   - Buscar: `"bebidas"`
   - Debe encontrar todos los productos de esa categoría

5. **Búsqueda con debounce**:
   - Escribir rápido: `"cerveza"`
   - Solo debe hacer 1 búsqueda después de 500ms

## 📝 Archivos Modificados

1. ✅ `ventiq_marketplace/sql/get_productos_marketplace.sql`
2. ✅ `ventiq_marketplace/lib/services/marketplace_service.dart`
3. ✅ `ventiq_marketplace/lib/screens/products_screen.dart`

## 🎯 Beneficios

1. **Búsqueda Completa**: Encuentra productos en toda la BD
2. **Búsqueda Fonética**: Sin preocuparse por acentos
3. **Múltiples Campos**: Busca en 7 campos diferentes
4. **Performance**: Usa índices de PostgreSQL
5. **Menos Código**: Eliminado código de filtrado en cliente
6. **Debounce**: Menos llamadas al servidor
7. **Escalable**: Funciona con millones de productos

---

**Fecha de Implementación**: 2025-11-10  
**Versión**: 1.2.0  
**Autor**: VentIQ Development Team
