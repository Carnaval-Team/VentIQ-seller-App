# Paginación en Store Detail Screen - Marketplace VentIQ

## 📋 Resumen

Se implementó la carga de productos reales con paginación en `StoreDetailScreen`, reemplazando los datos mock por productos reales de la base de datos usando `MarketplaceService`.

## 🎯 Problema Resuelto

### Antes:
- ❌ Productos mock hardcodeados
- ❌ Solo 5 productos de ejemplo
- ❌ No se conectaba a la base de datos
- ❌ Datos no reales de la tienda

### Después:
- ✅ Productos reales de la base de datos
- ✅ Paginación con infinite scroll
- ✅ Filtrado por ID de tienda
- ✅ Pull-to-refresh
- ✅ Presentaciones dinámicas
- ✅ Indicador de carga al final

## 📱 Cambios Implementados

### 1. Imports Agregados

```dart
import '../services/marketplace_service.dart';
```

### 2. Variables de Estado

**Antes:**
```dart
List<Map<String, dynamic>> _storeProducts = [];
bool _isLoading = true;
```

**Después:**
```dart
final MarketplaceService _marketplaceService = MarketplaceService();
final ScrollController _scrollController = ScrollController();

List<Map<String, dynamic>> _storeProducts = [];
bool _isLoading = true;
bool _isLoadingMore = false;

// Paginación
final int _pageSize = 20;
int _currentOffset = 0;
bool _hasMoreProducts = true;
```

### 3. Ciclo de Vida

**Agregado dispose():**
```dart
@override
void dispose() {
  _scrollController.dispose();
  super.dispose();
}
```

**Actualizado initState():**
```dart
@override
void initState() {
  super.initState();
  _loadStoreProducts();
  _scrollController.addListener(_onScroll);  // ✅ NUEVO
}
```

### 4. Método _loadStoreProducts()

**Antes (Mock):**
```dart
Future<void> _loadStoreProducts() async {
  await Future.delayed(const Duration(milliseconds: 500));
  
  setState(() {
    _storeProducts = _getMockStoreProducts();
    _isLoading = false;
  });
}
```

**Después (Real con Paginación):**
```dart
Future<void> _loadStoreProducts({bool reset = false}) async {
  if (reset) {
    setState(() {
      _isLoading = true;
      _currentOffset = 0;
      _storeProducts = [];
      _hasMoreProducts = true;
    });
  }

  if (!_hasMoreProducts && !reset) return;

  try {
    // Obtener ID de la tienda
    final storeId = widget.store['id'] as int?;
    
    if (storeId == null) {
      print('❌ Error: ID de tienda no disponible');
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
      return;
    }

    print('📍 Cargando productos de tienda ID: $storeId');
    
    final newProducts = await _marketplaceService.getProducts(
      idTienda: storeId,  // ✅ Filtrar por tienda
      idCategoria: null,
      soloDisponibles: true,
      searchQuery: null,
      limit: _pageSize,
      offset: _currentOffset,
    );

    setState(() {
      if (reset) {
        _storeProducts = newProducts;
      } else {
        _storeProducts.addAll(newProducts);
      }
      
      _currentOffset += newProducts.length;
      _hasMoreProducts = newProducts.length == _pageSize;
      _isLoading = false;
      _isLoadingMore = false;
    });
  } catch (e) {
    print('❌ Error cargando productos de la tienda: $e');
    setState(() {
      _isLoading = false;
      _isLoadingMore = false;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar productos: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
```

### 5. Infinite Scroll

**Nuevo método _onScroll():**
```dart
void _onScroll() {
  if (_scrollController.position.pixels >=
      _scrollController.position.maxScrollExtent * 0.8) {
    if (!_isLoadingMore && _hasMoreProducts) {
      setState(() => _isLoadingMore = true);
      _loadStoreProducts();
    }
  }
}
```

### 6. Pull-to-Refresh

**Nuevo método:**
```dart
Future<void> _refreshProducts() async {
  await _loadStoreProducts(reset: true);
}
```

**Agregado al build():**
```dart
return Scaffold(
  body: RefreshIndicator(
    onRefresh: _refreshProducts,  // ✅ NUEVO
    child: CustomScrollView(
      controller: _scrollController,  // ✅ NUEVO
      slivers: [
        // ...
      ],
    ),
  ),
);
```

### 7. Indicador de Carga al Final

**Agregado en slivers:**
```dart
// Indicador de carga al final
if (_isLoadingMore)
  SliverToBoxAdapter(
    child: Container(
      padding: const EdgeInsets.all(AppTheme.paddingM),
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    ),
  ),
```

### 8. Lista de Productos Actualizada

**Antes (Mock):**
```dart
Widget _buildProductsList() {
  return SliverList(
    delegate: SliverChildBuilderDelegate(
      (context, index) {
        final product = _storeProducts[index];
        return ProductListCard(
          productName: product['nombre'],
          price: product['precio'],
          imageUrl: product['imageUrl'],
          storeName: product['tienda'],
          availableStock: product['stock'],
          rating: product['rating'],
          presentations: List<String>.from(product['presentaciones']),
          onTap: () => _openProductDetails(product),
        );
      },
      childCount: _storeProducts.length,
    ),
  );
}
```

**Después (Real con Presentaciones):**
```dart
Widget _buildProductsList() {
  return SliverList(
    delegate: SliverChildBuilderDelegate(
      (context, index) {
        final product = _storeProducts[index];
        final metadata = product['metadata'] as Map<String, dynamic>?;
        
        // Extraer presentaciones del metadata
        final presentacionesData = metadata?['presentaciones'] as List<dynamic>?;
        final presentaciones = presentacionesData?.map((p) {
          final presentacion = p as Map<String, dynamic>;
          final denominacion = presentacion['denominacion'] as String? ?? '';
          final cantidad = presentacion['cantidad'] ?? 1;
          final esBase = presentacion['es_base'] as bool? ?? false;
          
          // Formato: "Unidad" o "Caja x24" con indicador de base
          if (cantidad == 1) {
            return esBase ? '$denominacion ⭐' : denominacion;
          } else {
            return esBase ? '$denominacion x$cantidad ⭐' : '$denominacion x$cantidad';
          }
        }).toList() ?? [];
        
        return ProductListCard(
          productName: product['denominacion'] ?? 'Sin nombre',
          price: (product['precio_venta'] ?? 0).toDouble(),
          imageUrl: product['imagen'],
          storeName: metadata?['denominacion_tienda'] ?? 'Sin tienda',
          availableStock: (product['stock_disponible'] ?? 0).toInt(),
          rating: (metadata?['rating_promedio'] ?? 0.0).toDouble(),
          presentations: presentaciones,
          onTap: () => _openProductDetails(product),
        );
      },
      childCount: _storeProducts.length,
    ),
  );
}
```

## 🔄 Flujo de Funcionamiento

### Carga Inicial:
1. Usuario abre `StoreDetailScreen` con datos de tienda
2. `initState()` llama a `_loadStoreProducts()`
3. Se obtiene el `id` de la tienda del widget
4. Se llama a `MarketplaceService.getProducts(idTienda: storeId)`
5. Se cargan los primeros 20 productos
6. Se muestran en la lista

### Infinite Scroll:
1. Usuario hace scroll hacia abajo
2. Cuando llega al 80% del contenido
3. `_onScroll()` detecta y activa `_isLoadingMore`
4. Se llama a `_loadStoreProducts()` sin reset
5. Se cargan los siguientes 20 productos
6. Se agregan a la lista existente
7. Se muestra indicador de carga al final

### Pull-to-Refresh:
1. Usuario arrastra hacia abajo desde el inicio
2. `RefreshIndicator` activa `_refreshProducts()`
3. Se llama a `_loadStoreProducts(reset: true)`
4. Se resetean offset y productos
5. Se cargan los primeros 20 productos frescos
6. Se actualiza la lista

## 📊 Estructura de Datos

### Datos de Entrada (widget.store):
```dart
{
  'id': 1,  // ✅ REQUERIDO para filtrar productos
  'nombre': 'Bodega Central',
  'ubicacion': 'Centro',
  'municipio': 'Plaza',
  'provincia': 'La Habana',
  'direccion': 'Calle 23 #456',
  'productCount': 150,
  'logoUrl': null,
}
```

### Datos de Salida (productos del RPC):
```dart
{
  'id_producto': 100,
  'denominacion': 'Cerveza Cristal',
  'precio_venta': 2.50,
  'imagen': 'https://...',
  'stock_disponible': 45,
  'metadata': {
    'denominacion_tienda': 'Bodega Central',
    'rating_promedio': 4.5,
    'presentaciones': [
      {
        'denominacion': 'Unidad',
        'cantidad': 1,
        'es_base': true
      },
      {
        'denominacion': 'Six Pack',
        'cantidad': 6,
        'es_base': false
      }
    ]
  }
}
```

## ⚡ Optimizaciones

### 1. Paginación Eficiente
- Carga solo 20 productos a la vez
- Reduce uso de memoria
- Mejora tiempo de respuesta inicial

### 2. Infinite Scroll
- Carga automática al hacer scroll
- Trigger al 80% del contenido
- Evita múltiples cargas simultáneas

### 3. Pull-to-Refresh
- Actualización manual de datos
- Reset completo de la lista
- Feedback visual al usuario

### 4. Manejo de Errores
- Try-catch en carga de productos
- SnackBar con mensaje de error
- Estados de loading correctos

## 🎯 Beneficios

1. **Datos Reales**: Productos de la base de datos
2. **Performance**: Paginación reduce carga inicial
3. **UX Mejorada**: Infinite scroll fluido
4. **Actualización**: Pull-to-refresh para datos frescos
5. **Presentaciones**: Muestra todas las presentaciones disponibles
6. **Filtrado**: Solo productos de la tienda específica
7. **Escalable**: Funciona con miles de productos

## 🧪 Testing

### Casos de Prueba:

1. **Carga Inicial**:
   - Abrir tienda con productos
   - Debe cargar primeros 20 productos
   - Debe mostrar loading state

2. **Infinite Scroll**:
   - Hacer scroll hasta el final
   - Debe cargar más productos automáticamente
   - Debe mostrar indicador de carga al final

3. **Pull-to-Refresh**:
   - Arrastrar hacia abajo desde el inicio
   - Debe recargar productos
   - Debe mostrar indicador de refresh

4. **Tienda sin Productos**:
   - Abrir tienda sin productos
   - Debe mostrar estado vacío
   - No debe mostrar errores

5. **Error de Red**:
   - Simular error de conexión
   - Debe mostrar SnackBar con error
   - No debe crashear la app

## 📝 Archivos Modificados

1. ✅ `ventiq_marketplace/lib/screens/store_detail_screen.dart`

## 🔗 Integración

### Dependencias:
- `MarketplaceService` - Servicio de productos
- `ProductListCard` - Widget de tarjeta de producto
- `ProductDetailScreen` - Pantalla de detalles

### RPC Utilizado:
- `get_productos_marketplace` con parámetro `id_tienda_param`

---

**Fecha de Implementación**: 2025-11-10  
**Versión**: 1.0.0  
**Autor**: VentIQ Development Team
