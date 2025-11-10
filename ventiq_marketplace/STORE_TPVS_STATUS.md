# Estado de TPVs en Store Detail Screen - Marketplace VentIQ

## 📋 Resumen

Se implementó un sistema real para verificar si una tienda está abierta basándose en el estado de los turnos de caja de sus TPVs (Puntos de Venta). Muestra una lista de todos los TPVs con su estado actual (abierto/cerrado).

## 🎯 Problema Resuelto

### Antes:
- ❌ Estado de tienda basado en hora del día (8am-8pm)
- ❌ No reflejaba el estado real de los TPVs
- ❌ No mostraba información de los puntos de venta
- ❌ Lógica hardcodeada sin conexión a BD

### Después:
- ✅ Estado real basado en turnos de caja activos
- ✅ Muestra lista de todos los TPVs de la tienda
- ✅ Indica cuáles TPVs están abiertos/cerrados
- ✅ Muestra vendedor y hora de apertura
- ✅ Contador de TPVs abiertos vs totales

## 🗄️ Base de Datos

### Tablas Utilizadas:

#### 1. app_dat_caja_turno
Registra los turnos de caja de cada TPV:
- `id_tpv`: FK al TPV
- `fecha_apertura`: Timestamp de apertura del turno
- `fecha_cierre`: Timestamp de cierre (NULL si está abierto)
- `id_vendedor`: FK al vendedor del turno
- `estado`: Estado del turno

#### 2. app_dat_tpv
Catálogo de TPVs:
- `id`: ID del TPV
- `id_tienda`: FK a la tienda
- `denominacion`: Nombre del TPV
- `id_almacen`: FK al almacén asociado

### Lógica de Estado:

```sql
-- Un TPV está ABIERTO si:
-- Su último turno (ORDER BY fecha_apertura DESC LIMIT 1) tiene fecha_cierre = NULL

-- Un TPV está CERRADO si:
-- Su último turno tiene fecha_cierre != NULL
-- O no tiene ningún turno registrado
```

## 🔧 Implementación

### 1. Función RPC PostgreSQL

**Archivo**: `ventiq_marketplace/sql/get_tienda_estado_tpvs.sql`

```sql
CREATE OR REPLACE FUNCTION get_tienda_estado_tpvs(
    id_tienda_param bigint
)
RETURNS TABLE (
    id_tpv bigint,
    denominacion_tpv text,
    esta_abierto boolean,
    ultimo_turno_id bigint,
    fecha_apertura timestamp with time zone,
    fecha_cierre timestamp with time zone,
    vendedor_nombre text
)
```

**Características:**
- ✅ Usa `LEFT JOIN LATERAL` para obtener el último turno de cada TPV
- ✅ Ordena por `fecha_apertura DESC` para obtener el más reciente
- ✅ Verifica si `fecha_cierre IS NULL` para determinar si está abierto
- ✅ Incluye información del vendedor del turno
- ✅ Retorna todos los TPVs de la tienda

### 2. MarketplaceService

**Archivo**: `lib/services/marketplace_service.dart`

**Nuevo método:**
```dart
Future<List<Map<String, dynamic>>> getStoreTPVsStatus(int storeId) async {
  final response = await _supabase.rpc(
    'get_tienda_estado_tpvs',
    params: {
      'id_tienda_param': storeId,
    },
  );

  final tpvs = List<Map<String, dynamic>>.from(response);
  
  final abiertos = tpvs.where((tpv) => tpv['esta_abierto'] == true).length;
  final cerrados = tpvs.length - abiertos;
  
  print('✅ ${tpvs.length} TPVs obtenidos');
  print('  - Abiertos: $abiertos');
  print('  - Cerrados: $cerrados');

  return tpvs;
}
```

### 3. StoreDetailScreen

**Archivo**: `lib/screens/store_detail_screen.dart`

#### Variables Agregadas:
```dart
List<Map<String, dynamic>> _tpvs = [];
bool _isLoadingTPVs = true;
```

#### Método de Carga:
```dart
Future<void> _loadTPVsStatus() async {
  final storeId = widget.store['id'] as int?;
  
  if (storeId == null) return;

  final tpvs = await _marketplaceService.getStoreTPVsStatus(storeId);

  setState(() {
    _tpvs = tpvs;
    _isLoadingTPVs = false;
  });
}
```

#### Verificación de Estado:
```dart
bool _isStoreOpen() {
  if (_isLoadingTPVs || _tpvs.isEmpty) {
    return false;
  }
  
  // Tienda abierta si al menos un TPV está abierto
  return _tpvs.any((tpv) => tpv['esta_abierto'] == true);
}

int _getOpenTPVsCount() {
  if (_isLoadingTPVs || _tpvs.isEmpty) {
    return 0;
  }
  
  return _tpvs.where((tpv) => tpv['esta_abierto'] == true).length;
}
```

#### UI de TPVs:
```dart
Widget _buildTPVCard(Map<String, dynamic> tpv) {
  final isOpen = tpv['esta_abierto'] as bool? ?? false;
  final tpvName = tpv['denominacion_tpv'] as String? ?? 'TPV';
  final vendorName = tpv['vendedor_nombre'] as String?;
  final fechaApertura = tpv['fecha_apertura'] as String?;
  
  return Container(
    // Card con diseño diferenciado por estado
    decoration: BoxDecoration(
      color: isOpen 
          ? AppTheme.successColor.withOpacity(0.05)
          : Colors.grey.withOpacity(0.05),
      border: Border.all(
        color: isOpen 
            ? AppTheme.successColor.withOpacity(0.3)
            : Colors.grey.withOpacity(0.3),
      ),
    ),
    child: Row(
      children: [
        // Icono de estado
        Icon(
          isOpen ? Icons.check_circle : Icons.cancel,
          color: isOpen ? AppTheme.successColor : Colors.grey,
        ),
        
        // Información del TPV
        Column(
          children: [
            Text(tpvName),
            if (vendorName != null) Text(vendorName),
            if (fechaApertura != null && isOpen) 
              Text('Abierto desde ${_formatTime(fechaApertura)}'),
          ],
        ),
        
        // Badge de estado
        Container(
          child: Text(isOpen ? 'Abierto' : 'Cerrado'),
        ),
      ],
    ),
  );
}
```

## 📊 Estructura de Datos

### Respuesta del RPC:
```json
[
  {
    "id_tpv": 1,
    "denominacion_tpv": "TPV Principal",
    "esta_abierto": true,
    "ultimo_turno_id": 45,
    "fecha_apertura": "2025-11-10T08:30:00Z",
    "fecha_cierre": null,
    "vendedor_nombre": "Juan Pérez"
  },
  {
    "id_tpv": 2,
    "denominacion_tpv": "TPV Secundario",
    "esta_abierto": false,
    "ultimo_turno_id": 44,
    "fecha_apertura": "2025-11-09T08:00:00Z",
    "fecha_cierre": "2025-11-09T20:00:00Z",
    "vendedor_nombre": "María García"
  }
]
```

## 🎨 Diseño UI

### Estado de la Tienda:
```
┌─────────────────────────────────────┐
│ [✓] Abierto ahora                   │
│     2 de 3 TPVs abiertos            │
└─────────────────────────────────────┘
```

### Lista de TPVs:

**TPV Abierto:**
```
┌─────────────────────────────────────┐
│ [✓] TPV Principal        [Abierto]  │
│     👤 Juan Pérez                   │
│     🕐 Abierto desde 08:30          │
└─────────────────────────────────────┘
```

**TPV Cerrado:**
```
┌─────────────────────────────────────┐
│ [✗] TPV Secundario       [Cerrado]  │
│     👤 María García                 │
└─────────────────────────────────────┘
```

## 🔄 Flujo de Funcionamiento

### Carga Inicial:
1. Usuario abre `StoreDetailScreen`
2. `initState()` llama a `_loadTPVsStatus()`
3. Se obtiene el `id` de la tienda
4. Se llama al RPC `get_tienda_estado_tpvs`
5. Se recibe lista de TPVs con su estado
6. Se actualiza UI mostrando estado de la tienda

### Actualización:
1. Usuario hace pull-to-refresh
2. Se llama a `_refreshProducts()` que ejecuta:
   - `_loadStoreProducts(reset: true)`
   - `_loadTPVsStatus()`
3. Se actualizan productos y estado de TPVs
4. UI se actualiza con datos frescos

### Determinación de Estado:
1. Se verifica si `_tpvs` tiene elementos
2. Se busca si algún TPV tiene `esta_abierto == true`
3. Si al menos uno está abierto → Tienda ABIERTA
4. Si todos están cerrados → Tienda CERRADA
5. Si no hay TPVs → Tienda CERRADA

## ⚡ Optimizaciones

### 1. LEFT JOIN LATERAL
```sql
LEFT JOIN LATERAL (
    SELECT ct.id, ct.fecha_apertura, ct.fecha_cierre, ct.id_vendedor
    FROM app_dat_caja_turno ct
    WHERE ct.id_tpv = tpv.id
    ORDER BY ct.fecha_apertura DESC
    LIMIT 1
) ultimo_turno ON true
```
- Obtiene solo el último turno de cada TPV
- Más eficiente que subconsultas múltiples
- Usa índice `idx_caja_turno_filtros`

### 2. Índice Optimizado
```sql
CREATE INDEX idx_caja_turno_filtros 
ON app_dat_caja_turno (id_tpv, id_vendedor, fecha_apertura, estado);
```
- Acelera búsqueda por TPV
- Optimiza ordenamiento por fecha
- Mejora performance de la query

### 3. Carga Paralela
```dart
await Future.wait([
  _loadStoreProducts(reset: true),
  _loadTPVsStatus(),
]);
```
- Carga productos y TPVs simultáneamente
- Reduce tiempo de espera total
- Mejora UX en refresh

## 🎯 Beneficios

1. **Estado Real**: Basado en turnos de caja activos
2. **Información Completa**: Muestra todos los TPVs
3. **Transparencia**: Usuario ve qué TPVs están operando
4. **Vendedor Visible**: Sabe quién está atendiendo
5. **Hora de Apertura**: Información de cuándo abrió
6. **Actualizable**: Pull-to-refresh para datos frescos
7. **Performance**: Query optimizada con índices

## 🧪 Testing

### Casos de Prueba:

1. **Tienda con Todos los TPVs Abiertos**:
   - Debe mostrar "Abierto ahora"
   - Contador: "3 de 3 TPVs abiertos"
   - Todos los cards en verde

2. **Tienda con Algunos TPVs Abiertos**:
   - Debe mostrar "Abierto ahora"
   - Contador: "2 de 3 TPVs abiertos"
   - Cards mixtos (verde y gris)

3. **Tienda con Todos los TPVs Cerrados**:
   - Debe mostrar "Cerrado"
   - Contador: "0 de 3 TPVs abiertos"
   - Todos los cards en gris

4. **Tienda sin TPVs**:
   - Debe mostrar "Cerrado"
   - No mostrar sección de TPVs

5. **Pull-to-Refresh**:
   - Debe actualizar estado de TPVs
   - Debe reflejar cambios recientes

## 📝 Archivos Creados/Modificados

1. ✅ `ventiq_marketplace/sql/get_tienda_estado_tpvs.sql` - Función RPC
2. ✅ `ventiq_marketplace/lib/services/marketplace_service.dart` - Método getStoreTPVsStatus
3. ✅ `ventiq_marketplace/lib/screens/store_detail_screen.dart` - UI de TPVs

## 🚀 Para Aplicar los Cambios

### 1. Crear la función RPC:
```bash
psql -U postgres -d tu_base_datos -f ventiq_marketplace/sql/get_tienda_estado_tpvs.sql
```

### 2. Verificar el índice:
```sql
-- Verificar que existe el índice
SELECT indexname FROM pg_indexes 
WHERE tablename = 'app_dat_caja_turno' 
AND indexname = 'idx_caja_turno_filtros';

-- Si no existe, crearlo
CREATE INDEX IF NOT EXISTS idx_caja_turno_filtros 
ON app_dat_caja_turno (id_tpv, id_vendedor, fecha_apertura, estado);
```

### 3. Hot reload en Flutter
- Los cambios en Flutter se aplican automáticamente

## 📚 Ejemplo de Query

```sql
-- Ver estado de TPVs de una tienda
SELECT * FROM get_tienda_estado_tpvs(1);

-- Resultado:
-- id_tpv | denominacion_tpv | esta_abierto | fecha_apertura      | vendedor_nombre
-- -------|------------------|--------------|---------------------|----------------
-- 1      | TPV Principal    | true         | 2025-11-10 08:30:00 | Juan Pérez
-- 2      | TPV Secundario   | false        | 2025-11-09 08:00:00 | María García
```

---

**Fecha de Implementación**: 2025-11-10  
**Versión**: 1.0.0  
**Autor**: VentIQ Development Team
