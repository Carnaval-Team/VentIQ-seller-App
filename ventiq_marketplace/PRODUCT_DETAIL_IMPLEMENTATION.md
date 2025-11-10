# Product Detail Screen - Marketplace VentIQ

## 📋 Resumen

Se implementó completamente la pantalla de detalles de producto del marketplace usando el mismo RPC `get_detalle_producto` que usa la app de vendedores, pero adaptado para el marketplace: acumulando cantidades de diferentes ubicaciones/almacenes y sin mostrar información de ubicación ni elaboración.

## 🎯 Diferencias con VentIQ Seller App

### VentIQ Seller App (ventiq_app):
- ✅ Muestra ubicaciones/almacenes por separado
- ✅ Agrupa variantes por ubicación
- ✅ Muestra información de elaboración
- ✅ Muestra vendedor y almacén
- ✅ Gestión de inventario por ubicación

### VentIQ Marketplace (ventiq_marketplace):
- ✅ **Acumula cantidades** de todas las ubicaciones
- ✅ **Agrupa por variante+presentación** (sin ubicación)
- ❌ **NO muestra** ubicaciones/almacenes
- ❌ **NO muestra** información de elaboración
- ❌ **NO muestra** vendedor
- ✅ **Enfoque en compra**: Selección simple de cantidad

## 🔧 Implementación

### 1. ProductDetailService

**Archivo**: `lib/services/product_detail_service.dart`

**Funcionalidad principal:**
```dart
Future<Map<String, dynamic>> getProductDetail(int productId) async {
  // Llama al RPC get_detalle_producto
  final response = await _supabase.rpc(
    'get_detalle_producto',
    params: {'id_producto_param': productId},
  );
  
  // Transforma agrupando por variante+presentación
  return _transformToMarketplaceProduct(response);
}
```

**Lógica de agrupación:**
1. Recibe inventario con múltiples ubicaciones
2. Crea clave única: `{id_variante}_{id_presentacion}`
3. Acumula cantidades de la misma variante+presentación
4. Ordena: presentaciones base primero, luego alfabéticamente

**Ejemplo de agrupación:**
```
Entrada (del RPC):
- Cerveza Cristal - Unidad (Almacén A): 50 unidades
- Cerveza Cristal - Unidad (Almacén B): 30 unidades
- Cerveza Cristal - Six Pack (Almacén A): 20 unidades

Salida (agrupada):
- Cerveza Cristal - Unidad: 80 unidades (50+30)
- Cerveza Cristal - Six Pack: 20 unidades
```

### 2. ProductDetailScreen

**Archivo**: `lib/screens/product_detail_screen.dart`

**Estructura:**
```
┌─────────────────────────────────┐
│ AppBar                          │
│ - Título del producto           │
│ - Botones: compartir, favorito  │
├─────────────────────────────────┤
│ Header del Producto             │
│ - Imagen (120x120)              │
│ - Nombre                        │
│ - Categoría                     │
│ - Stock total                   │
├─────────────────────────────────┤
│ Descripción (si existe)         │
├─────────────────────────────────┤
│ Presentaciones Disponibles      │
│                                 │
│ ┌───────────────────────────┐  │
│ │ Variante Card             │  │
│ │ - Nombre + Badge (⭐Base)  │  │
│ │ - Descripción             │  │
│ │ - Precio + Stock          │  │
│ │ - Selector de cantidad    │  │
│ │ - Subtotal                │  │
│ └───────────────────────────┘  │
│                                 │
│ [Más variantes...]              │
├─────────────────────────────────┤
│ Botón Agregar al Carrito        │
│ (Solo visible si hay selección) │
│ - Total de productos            │
│ - Precio total                  │
└─────────────────────────────────┘
```

**Estados:**
- **Loading**: CircularProgressIndicator
- **Error**: Mensaje + botón reintentar
- **Success**: Contenido completo

**Selección múltiple:**
```dart
// Map de cantidades seleccionadas
Map<String, int> _selectedQuantities = {};

// Key = variant id (ej: "123_456")
// Value = cantidad seleccionada
```

### 3. Variant Card

**Características:**
- ✅ Nombre de la variante
- ✅ Badge "⭐ Base" para presentación base
- ✅ Descripción (si existe)
- ✅ Precio unitario
- ✅ Stock disponible (acumulado)
- ✅ Selector de cantidad (- / cantidad / +)
- ✅ Subtotal dinámico
- ✅ Borde destacado cuando está seleccionada

**Diseño:**
```
┌─────────────────────────────────────┐
│ Cerveza Cristal - Unidad    [⭐Base]│
│ Presentación: 1 unidad              │
│                                     │
│ $2.50              80 disponibles   │
│                                     │
│ [−]    5    [+]    Subtotal: $12.50│
└─────────────────────────────────────┘
```

## 📊 Flujo de Datos

### 1. Carga Inicial:
```
Usuario abre producto
    ↓
ProductDetailScreen.initState()
    ↓
_loadProductDetails()
    ↓
ProductDetailService.getProductDetail(productId)
    ↓
Supabase RPC: get_detalle_producto
    ↓
_transformToMarketplaceProduct()
    ↓
Agrupa por variante+presentación
    ↓
Acumula cantidades
    ↓
Ordena (base primero)
    ↓
setState() → UI actualizada
```

### 2. Selección de Cantidad:
```
Usuario presiona [+] o [−]
    ↓
_updateQuantity(variantId, newQuantity)
    ↓
Actualiza _selectedQuantities
    ↓
setState() → Card se actualiza
    ↓
Si hay selecciones → Muestra botón carrito
```

### 3. Agregar al Carrito:
```
Usuario presiona "Agregar al Carrito"
    ↓
_addToCart()
    ↓
Valida que haya selecciones
    ↓
Calcula total de items y precio
    ↓
TODO: Enviar al carrito real
    ↓
Muestra SnackBar de confirmación
    ↓
Limpia selecciones
```

## 🎨 Diseño Visual

### Colores:
- **Primario**: AppTheme.primaryColor (azul)
- **Acento**: AppTheme.accentColor (precio)
- **Éxito**: AppTheme.successColor (stock disponible)
- **Error**: AppTheme.errorColor (sin stock)
- **Warning**: AppTheme.warningColor (badge base)

### Estados Visuales:

**Variante NO seleccionada:**
- Borde gris claro (1px)
- Sin sombra
- Fondo blanco

**Variante seleccionada:**
- Borde azul primario (2px)
- Sombra azul suave
- Fondo blanco

**Sin stock:**
- Texto rojo
- Botones deshabilitados

## 🔄 Comparación de Transformación

### Datos del RPC (raw):
```json
{
  "producto": {
    "id": 100,
    "denominacion": "Cerveza Cristal",
    "precio_actual": 2.50
  },
  "inventario": [
    {
      "id_inventario": 1,
      "cantidad_disponible": 50,
      "variante": {"id": 1, "opcion": {"valor": "Botella"}},
      "presentacion": {"id": 1, "denominacion": "Unidad", "es_base": true},
      "ubicacion": {"denominacion": "Almacén A"}
    },
    {
      "id_inventario": 2,
      "cantidad_disponible": 30,
      "variante": {"id": 1, "opcion": {"valor": "Botella"}},
      "presentacion": {"id": 1, "denominacion": "Unidad", "es_base": true},
      "ubicacion": {"denominacion": "Almacén B"}
    }
  ]
}
```

### Datos transformados (marketplace):
```json
{
  "id": 100,
  "denominacion": "Cerveza Cristal",
  "precio": 2.50,
  "cantidad_total": 80,
  "variantes": [
    {
      "id": "1_1",
      "nombre": "Tipo: Botella - Unidad",
      "precio": 2.50,
      "cantidad_total": 80,
      "es_base": true
    }
  ]
}
```

## ⚡ Optimizaciones

### 1. Agrupación Eficiente
```dart
// Usa Map para agrupar en O(n)
final Map<String, Map<String, dynamic>> groupedVariants = {};

for (final item in inventoryData) {
  final key = '${varianteId}_$presentacionId';
  
  if (groupedVariants.containsKey(key)) {
    // Acumular
    groupedVariants[key]!['cantidad_total'] += cantidad;
  } else {
    // Crear nuevo
    groupedVariants[key] = {...};
  }
}
```

### 2. Ordenamiento
```dart
variants.sort((a, b) {
  // Primero por es_base
  final baseCompare = (b['es_base'] ? 1 : 0).compareTo(a['es_base'] ? 1 : 0);
  if (baseCompare != 0) return baseCompare;
  
  // Luego por nombre
  return a['nombre'].compareTo(b['nombre']);
});
```

### 3. Cálculos Reactivos
```dart
// Total de items seleccionados
final totalItems = _selectedQuantities.values.fold<int>(
  0, 
  (sum, qty) => sum + qty
);

// Precio total
final totalPrice = _selectedQuantities.entries.fold<double>(
  0.0, 
  (sum, entry) {
    final variant = _variants.firstWhere((v) => v['id'] == entry.key);
    return sum + (variant['precio'] * entry.value);
  }
);
```

## 🎯 Beneficios

1. **Simplicidad**: Usuario no ve complejidad de ubicaciones
2. **Stock Unificado**: Cantidad total de todos los almacenes
3. **Compra Fácil**: Selección simple de cantidad
4. **Performance**: Agrupación eficiente en O(n)
5. **Reutilización**: Usa mismo RPC que seller app
6. **Escalable**: Funciona con cualquier cantidad de ubicaciones
7. **Visual Claro**: Diseño limpio y moderno

## 📝 Archivos Creados

1. ✅ `lib/services/product_detail_service.dart` - Servicio de detalles
2. ✅ `lib/screens/product_detail_screen.dart` - Pantalla de detalles

## 🚀 Próximos Pasos

1. **Integrar con carrito real**: Implementar `_addToCart()`
2. **Favoritos**: Implementar botón de favoritos
3. **Compartir**: Implementar botón de compartir
4. **Imágenes múltiples**: Galería de imágenes del producto
5. **Reviews**: Sección de calificaciones y comentarios
6. **Productos relacionados**: Sugerencias de productos similares

## 🧪 Testing

### Casos de Prueba:

1. **Producto con múltiples ubicaciones**:
   - Debe acumular cantidades correctamente
   - No debe mostrar información de ubicación

2. **Producto con múltiples presentaciones**:
   - Debe mostrar todas las presentaciones
   - Presentación base debe aparecer primero

3. **Selección de cantidades**:
   - Botón [+] debe incrementar
   - Botón [−] debe decrementar
   - No debe permitir cantidad > stock

4. **Agregar al carrito**:
   - Debe calcular total correctamente
   - Debe mostrar confirmación
   - Debe limpiar selecciones

5. **Estados de error**:
   - Debe mostrar mensaje de error
   - Debe permitir reintentar

---

**Fecha de Implementación**: 2025-11-10  
**Versión**: 1.0.0  
**Autor**: VentIQ Development Team
