# Configuración de Control de Inventario en Turnos

## Descripción General

Se implementó una nueva configuración global en VentIQ Admin App que permite controlar si los vendedores deben hacer control de inventario al abrir y cerrar turnos.

## Estructura de Base de Datos

### Tabla: `app_dat_configuracion_tienda`

```sql
create table public.app_dat_configuracion_tienda (
  id bigint generated always as identity not null,
  id_tienda bigint not null,
  need_master_password_to_cancel boolean not null default false,
  need_all_orders_completed_to_continue boolean not null default false,
  maneja_inventario boolean null default false,  -- NUEVO CAMPO
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  master_password text null,
  constraint app_dat_configuracion_tienda_pkey primary key (id),
  constraint app_dat_configuracion_tienda_id_tienda_unique unique (id_tienda),
  constraint app_dat_configuracion_tienda_id_tienda_fkey foreign KEY (id_tienda) 
    references app_dat_tienda (id) on delete CASCADE
) TABLESPACE pg_default;
```

### Campo: `maneja_inventario`
- **Tipo**: `boolean`
- **Nullable**: `true`
- **Default**: `false`
- **Descripción**: Indica si los vendedores deben hacer control de inventario al abrir y cerrar turno

## Implementación en Admin App

### 1. StoreConfigService

#### Métodos Agregados:

**getManejaInventario(int storeId)**
```dart
/// Obtiene solo el valor de maneja_inventario
static Future<bool> getManejaInventario(int storeId) async {
  try {
    final config = await getStoreConfig(storeId);
    return config['maneja_inventario'] ?? false;
  } catch (e) {
    print('❌ Error al obtener maneja_inventario: $e');
    return false; // Valor por defecto en caso de error
  }
}
```

**updateManejaInventario(int storeId, bool value)**
```dart
/// Actualiza solo maneja_inventario
static Future<void> updateManejaInventario(int storeId, bool value) async {
  await updateStoreConfig(storeId, manejaInventario: value);
}
```

#### Método Actualizado:

**updateStoreConfig()**
- Agregado parámetro opcional: `bool? manejaInventario`
- Actualiza el campo en la base de datos cuando se proporciona

### 2. GlobalConfigTabView

#### Variables de Estado:
```dart
bool _manejaInventario = false;
```

#### Método de Actualización:
```dart
Future<void> _updateInventoryManagementSetting(bool value) async {
  if (_storeId == null) return;

  try {
    print('🔧 Actualizando configuración de manejo de inventario: $value');
    
    await StoreConfigService.updateManejaInventario(_storeId!, value);
    
    setState(() {
      _manejaInventario = value;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value 
              ? 'Control de inventario activado - Los vendedores deberán hacer control al abrir/cerrar turno'
              : 'Control de inventario desactivado - Los vendedores no harán control al abrir/cerrar turno'
          ),
          backgroundColor: AppColors.success,
        ),
      );
    }

    print('✅ Configuración de manejo de inventario actualizada');
  } catch (e) {
    print('❌ Error al actualizar configuración de manejo de inventario: $e');
    
    // Revertir el cambio en caso de error
    setState(() {
      _manejaInventario = !value;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al actualizar configuración: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
```

#### UI - Switch de Configuración:
```dart
_buildConfigCard(
  icon: Icons.inventory_2_outlined,
  iconColor: Colors.blue,
  title: 'Control de Inventario en Turnos',
  subtitle: _manejaInventario
      ? 'Los vendedores deben hacer control de inventario al abrir y cerrar turno'
      : 'Los vendedores no hacen control de inventario al abrir y cerrar turno',
  value: _manejaInventario,
  onChanged: _updateInventoryManagementSetting,
),
```

## Ubicación en la UI

**Admin App → Configuración → Tab "Global"**

La nueva configuración se encuentra entre:
- "Completar Todas las Órdenes" (arriba)
- "Información" (abajo)

## Características Visuales

### Switch Card:
- **Icono**: `Icons.inventory_2_outlined` (azul)
- **Título**: "Control de Inventario en Turnos"
- **Subtítulo Dinámico**:
  - Activado: "Los vendedores deben hacer control de inventario al abrir y cerrar turno"
  - Desactivado: "Los vendedores no hacen control de inventario al abrir y cerrar turno"

### Feedback Visual:
- **SnackBar de Confirmación**: Verde con mensaje específico según el estado
- **Reversión Automática**: Si hay error, el switch vuelve al estado anterior

## Flujo de Funcionamiento

### Carga Inicial:
1. `GlobalConfigTabView` se inicializa
2. `_loadStoreConfig()` obtiene configuración de la tienda
3. Se carga el valor de `maneja_inventario` desde la BD
4. Se actualiza el estado del switch

### Cambio de Configuración:
1. Usuario cambia el switch
2. `_updateInventoryManagementSetting()` se ejecuta
3. Se actualiza la BD mediante `StoreConfigService.updateManejaInventario()`
4. Se actualiza el estado local
5. Se muestra SnackBar de confirmación

### Manejo de Errores:
1. Si falla la actualización en BD
2. Se revierte el estado del switch
3. Se muestra SnackBar de error con detalles

## Logging Implementado

### Carga de Configuración:
```
✅ Configuración cargada:
  - Contraseña maestra para cancelar: false
  - Completar todas las órdenes: false
  - Maneja inventario: true
  - Tiene contraseña maestra: false
```

### Actualización:
```
🔧 Actualizando configuración de manejo de inventario: true
  - maneja_inventario: true
✅ Configuración de manejo de inventario actualizada
```

### Errores:
```
❌ Error al actualizar configuración de manejo de inventario: [error details]
```

## Integración con Seller App

### Uso en Apertura/Cierre de Turno:

El Seller App debe consultar esta configuración para determinar si mostrar o no los controles de inventario:

```dart
// En AperturaScreen o CierreScreen
final config = await StoreConfigService.getStoreConfig(storeId);
final manejaInventario = config['maneja_inventario'] ?? false;

if (manejaInventario) {
  // Mostrar controles de inventario
  // Requerir conteo de productos
} else {
  // Ocultar controles de inventario
  // Permitir apertura/cierre sin conteo
}
```

## Migración de Datos

### Script SQL:
Ejecutar `add_maneja_inventario_column.sql` para:
1. Agregar la columna si no existe
2. Establecer valor por defecto `false` para registros existentes
3. Agregar comentario de documentación

### Idempotencia:
El script puede ejecutarse múltiples veces sin causar errores.

## Beneficios

1. **Control Centralizado**: Configuración global desde Admin App
2. **Flexibilidad**: Cada tienda decide si requiere control de inventario
3. **UX Mejorada**: Feedback visual claro y mensajes específicos
4. **Robustez**: Manejo de errores con reversión automática
5. **Logging Detallado**: Trazabilidad completa de cambios
6. **Persistencia**: Configuración se mantiene en la base de datos

## Archivos Modificados

### Admin App:
- `lib/services/store_config_service.dart`: Métodos para maneja_inventario
- `lib/widgets/global_config_tab_view.dart`: UI y lógica del switch

### Scripts SQL:
- `add_maneja_inventario_column.sql`: Migración de base de datos

## Estado Actual

- ✅ Campo agregado a la tabla
- ✅ Métodos de servicio implementados
- ✅ UI del switch implementada
- ✅ Logging completo
- ✅ Manejo de errores robusto
- ⏳ Pendiente: Integración en Seller App (AperturaScreen/CierreScreen)

## Próximos Pasos

1. Integrar en `AperturaScreen` del Seller App
2. Integrar en `CierreScreen` del Seller App
3. Mostrar/ocultar controles de inventario según configuración
4. Agregar validaciones según el estado de la configuración
