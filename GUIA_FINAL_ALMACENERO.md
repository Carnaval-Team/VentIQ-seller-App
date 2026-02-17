# 🚀 Guía Final - Implementación Rol Almacenero

## ✅ Archivos SQL - SOLO FUNCIONES NUEVAS

### Archivos a Ejecutar (en orden):

#### 1. `SQL_OPTIMIZATION/crear_tabla_almacenero.sql`
**Qué hace:**
- Crea tabla `app_dat_almacenero`
- Crea índices
- Crea 3 funciones RPC básicas:
  - `fn_crear_almacenero`
  - `fn_eliminar_almacenero`
  - `fn_obtener_almacen_almacenero`

#### 2. `SQL_OPTIMIZATION/rpcs_almacenero_completas.sql` ⭐ PRINCIPAL
**Qué hace:**
- Crea 5 funciones RPC **COMPLETAMENTE NUEVAS**:
  - `fn_crear_trabajador_almacenero` - Crear trabajador + almacenero
  - `fn_asignar_rol_almacenero` - Asignar rol a trabajador existente
  - `fn_cambiar_almacen_almacenero` - Cambiar almacén asignado
  - `fn_listar_trabajadores_completo` - Listar trabajadores (NUEVA)
  - `fn_estadisticas_trabajadores_completo` - Estadísticas (NUEVA)

**IMPORTANTE:** Estas funciones NO actualizan las existentes, son completamente nuevas.

## 📋 Orden de Ejecución SQL

```sql
-- 1. Ejecutar primero (crea tabla)
SQL_OPTIMIZATION/crear_tabla_almacenero.sql

-- 2. Ejecutar segundo (crea funciones nuevas)
SQL_OPTIMIZATION/rpcs_almacenero_completas.sql
```

## ✅ Servicios Actualizados

### `worker_service.dart` - Cambios Aplicados

**Funciones que ahora usan RPCs NUEVAS:**

1. **`getWorkersByStore()`**
   - Antes: `fn_listar_trabajadores_tienda`
   - Ahora: `fn_listar_trabajadores_completo` ✅

2. **`getWorkerStatistics()`**
   - Antes: `fn_estadisticas_trabajadores_tienda`
   - Ahora: `fn_estadisticas_trabajadores_completo` ✅

3. **`createAlmacenero()`**
   - Antes: `fn_crear_almacenero`
   - Ahora: `fn_asignar_rol_almacenero` ✅

**Funciones que mantienen RPCs existentes:**
- `getAlmaceneroWarehouse()` - Usa `fn_obtener_almacen_almacenero` (creada en paso 1)
- `deleteAlmacenero()` - Usa `fn_eliminar_almacenero` (creada en paso 1)

## 🎯 Implementación UI Pendiente

### 1. workers_screen.dart (30 minutos)

#### A. Agregar dropdown de almacenes en diálogo de creación

Buscar donde se selecciona el `tipoRol` y agregar después:

```dart
// Después del selector de rol
if (_selectedTipoRol == 'almacenero') {
  const SizedBox(height: 16),
  Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.orange.shade50,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.orange.shade200),
    ),
    child: Row(
      children: [
        Icon(Icons.warehouse, color: Colors.orange.shade700, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Selecciona el almacén que gestionará',
            style: TextStyle(fontSize: 13, color: Colors.orange.shade700),
          ),
        ),
      ],
    ),
  ),
  const SizedBox(height: 12),
  DropdownButtonFormField<int>(
    decoration: const InputDecoration(
      labelText: 'Almacén *',
      prefixIcon: Icon(Icons.warehouse),
      border: OutlineInputBorder(),
    ),
    value: _selectedAlmacenId,
    items: _almacenes.map((almacen) {
      return DropdownMenuItem<int>(
        value: almacen.id,
        child: Text(almacen.denominacion),
      );
    }).toList(),
    onChanged: (value) => setState(() => _selectedAlmacenId = value),
    validator: (value) {
      if (_selectedTipoRol == 'almacenero' && value == null) {
        return 'Selecciona un almacén';
      }
      return null;
    },
  ),
}
```

#### B. Mostrar almacén en tarjeta de trabajador

En el método `_buildWorkerCard()`, después del nombre del trabajador:

```dart
if (worker.esAlmacenero && worker.almacenDenominacion != null) {
  const SizedBox(height: 4),
  Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.orange.shade50,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: Colors.orange.shade200),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.warehouse, size: 14, color: Colors.orange.shade700),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            worker.almacenDenominacion!,
            style: TextStyle(
              fontSize: 12,
              color: Colors.orange.shade700,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  ),
}
```

### 2. inventory_screen.dart (20 minutos)

Agregar al inicio de la clase:

```dart
bool _isAlmacenero = false;
int? _assignedWarehouseId;
final PermissionsService _permissionsService = PermissionsService();
```

En `initState()`:

```dart
@override
void initState() {
  super.initState();
  _checkUserRole();
  _tabController = TabController(length: 4, vsync: this);
  _loadInitialData();
}

Future<void> _checkUserRole() async {
  final role = await _permissionsService.getUserRole();
  if (role == UserRole.almacenero) {
    final warehouseId = await _permissionsService.getAssignedWarehouse();
    if (mounted) {
      setState(() {
        _isAlmacenero = true;
        _assignedWarehouseId = warehouseId;
      });
    }
  }
}
```

Pasar datos a los tabs:

```dart
InventoryStockScreen(
  storeId: _storeId,
  isAlmacenero: _isAlmacenero,
  assignedWarehouseId: _assignedWarehouseId,
)
```

### 3. inventory_stock_screen.dart (25 minutos)

Actualizar constructor:

```dart
class InventoryStockScreen extends StatefulWidget {
  final int storeId;
  final bool isAlmacenero;
  final int? assignedWarehouseId;

  const InventoryStockScreen({
    Key? key,
    required this.storeId,
    this.isAlmacenero = false,
    this.assignedWarehouseId,
  }) : super(key: key);
}
```

Agregar variables de estado:

```dart
int? _selectedWarehouseId;
List<Warehouse> _warehouses = [];
```

En `initState()`:

```dart
@override
void initState() {
  super.initState();
  _loadWarehouses();
  
  if (widget.isAlmacenero && widget.assignedWarehouseId != null) {
    _selectedWarehouseId = widget.assignedWarehouseId;
  }
  
  _loadStock();
}
```

Agregar filtro de almacén en el UI:

```dart
Row(
  children: [
    Expanded(
      child: DropdownButton<int?>(
        isExpanded: true,
        value: _selectedWarehouseId,
        hint: const Text('Todos los almacenes'),
        items: [
          const DropdownMenuItem<int?>(
            value: null,
            child: Text('Todos los almacenes'),
          ),
          ..._warehouses.map((w) {
            return DropdownMenuItem<int?>(
              value: w.id,
              child: Text(w.denominacion),
            );
          }),
        ],
        onChanged: widget.isAlmacenero ? null : (value) {
          setState(() {
            _selectedWarehouseId = value;
            _loadStock();
          });
        },
      ),
    ),
    if (widget.isAlmacenero) ...[
      const SizedBox(width: 8),
      Tooltip(
        message: 'Filtro bloqueado - Solo tu almacén',
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Icon(Icons.lock, size: 18, color: Colors.orange.shade700),
        ),
      ),
    ],
  ],
)
```

### 4. products_screen.dart (15 minutos)

Agregar variables:

```dart
bool _isAlmacenero = false;
bool _canEdit = true;
bool _canCreate = true;
final PermissionsService _permissionsService = PermissionsService();
```

En `initState()`:

```dart
@override
void initState() {
  super.initState();
  _checkPermissions();
  _loadProducts();
}

Future<void> _checkPermissions() async {
  final role = await _permissionsService.getUserRole();
  if (mounted) {
    setState(() {
      _isAlmacenero = role == UserRole.almacenero;
      _canEdit = role != UserRole.almacenero;
      _canCreate = role != UserRole.almacenero;
    });
  }
}
```

Modificar FloatingActionButton:

```dart
floatingActionButton: _canCreate
  ? FloatingActionButton(
      onPressed: _showAddProductDialog,
      child: const Icon(Icons.add),
    )
  : null,
```

Condicionar botones en tarjeta:

```dart
if (_canEdit)
  IconButton(
    icon: const Icon(Icons.edit),
    onPressed: () => _editProduct(product),
  ),
if (_canEdit)
  IconButton(
    icon: const Icon(Icons.delete),
    onPressed: () => _deleteProduct(product),
  ),
```

## 📊 Resumen de Cambios

### SQL
- ✅ 2 archivos SQL a ejecutar
- ✅ 8 funciones RPC nuevas en total
- ✅ 0 funciones existentes modificadas

### Dart
- ✅ `worker_service.dart` - Actualizado para usar funciones nuevas
- ⏳ `workers_screen.dart` - Pendiente (30 min)
- ⏳ `inventory_screen.dart` - Pendiente (20 min)
- ⏳ `inventory_stock_screen.dart` - Pendiente (25 min)
- ⏳ `products_screen.dart` - Pendiente (15 min)

### Tiempo Total Estimado
- SQL: 5 minutos
- UI: 90 minutos
- Testing: 30 minutos
- **Total: ~2 horas**

## 🎯 Checklist Final

### Fase 1: SQL (5 minutos)
- [ ] Ejecutar `crear_tabla_almacenero.sql`
- [ ] Ejecutar `rpcs_almacenero_completas.sql`
- [ ] Verificar que las funciones se crearon

### Fase 2: UI (90 minutos)
- [ ] Actualizar `workers_screen.dart`
- [ ] Actualizar `inventory_screen.dart`
- [ ] Actualizar `inventory_stock_screen.dart`
- [ ] Actualizar `products_screen.dart`

### Fase 3: Testing (30 minutos)
- [ ] Crear almacenero desde UI
- [ ] Verificar asignación de almacén
- [ ] Iniciar sesión como almacenero
- [ ] Verificar filtros bloqueados
- [ ] Verificar modo solo lectura

## 📝 Notas Importantes

1. **Las funciones SQL son NUEVAS**, no actualizan existentes
2. **El servicio ya está actualizado** para usar las funciones nuevas
3. **Los permisos ya están configurados** en `permissions_service.dart`
4. **Los modelos ya tienen soporte** en `worker_models.dart`
5. **Solo falta implementar la UI** en las 4 pantallas

## 🔗 Archivos de Referencia

- `DOCUMENTACION_ROL_ALMACENERO.md` - Documentación técnica completa
- `IMPLEMENTACION_UI_ALMACENERO.dart` - Ejemplos de código (archivo de referencia)
- `RESUMEN_IMPLEMENTACION_ALMACENERO.md` - Resumen general
