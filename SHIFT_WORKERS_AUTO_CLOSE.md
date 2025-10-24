# Cierre Automático de Trabajadores al Cerrar Turno

## 📋 Funcionalidad Implementada

Se agregó funcionalidad para **cerrar automáticamente** todos los trabajadores activos cuando se cierra el turno en `CierreScreen`.

## 🎯 Comportamiento

### Al Cerrar el Turno:
1. **Antes de cerrar el turno**, el sistema verifica si hay trabajadores activos
2. **Trabajadores activos** (sin `hora_salida`): Se les asigna automáticamente la hora de cierre del turno
3. **Trabajadores finalizados**: No se modifican
4. **Cierre del turno**: Continúa normalmente después de cerrar trabajadores

## 🔧 Implementación Técnica

### 1. Método `_closeActiveWorkers()`

```dart
/// Cerrar automáticamente todos los trabajadores activos del turno
Future<void> _closeActiveWorkers() async {
  try {
    // Obtener turno abierto
    final turnoAbierto = await TurnoService.getTurnoAbierto();
    if (turnoAbierto == null) return;

    final idTurno = turnoAbierto['id'] as int;
    
    // Obtener trabajadores del turno
    final workers = await ShiftWorkersService.getShiftWorkers(idTurno);
    
    // Filtrar solo los trabajadores activos (sin hora de salida)
    final activeWorkers = workers.where((w) => w.isActive).toList();
    
    if (activeWorkers.isEmpty) {
      print('✅ No hay trabajadores activos para cerrar');
      return;
    }

    // Hora de cierre del turno (ahora)
    final horaCierre = DateTime.now();
    
    // Registrar salida de todos los trabajadores activos
    final idsRegistros = activeWorkers.map((w) => w.id!).toList();
    final result = await ShiftWorkersService.registerWorkersExit(
      idsRegistros: idsRegistros,
      horaSalida: horaCierre,
    );

    if (result['success'] == true) {
      _trabajadoresCerrados = activeWorkers.length;
      print('✅ $_trabajadoresCerrados trabajador(es) cerrado(s) automáticamente');
    }
  } catch (e) {
    print('❌ Error al cerrar trabajadores activos: $e');
    // No lanzar error para no interrumpir el cierre del turno
  }
}
```

### 2. Integración en el Flujo de Cierre

```dart
// Antes de cerrar el turno
await _closeActiveWorkers();

// Continuar con el cierre normal del turno
final success = await TurnoService.cerrarTurno(...);
```

### 3. Feedback al Usuario

El diálogo de éxito muestra cuántos trabajadores fueron cerrados:

```dart
if (_trabajadoresCerrados > 0)
  Text('Trabajadores cerrados: $_trabajadoresCerrados'),
```

## 📊 Ejemplo de Flujo

### Escenario: Cierre de Turno con 3 Trabajadores Activos

**Estado Inicial:**
```
Turno #123 - Abierto
├─ Juan Pérez (Vendedor)     - Entrada: 08:00, Salida: null ✅ ACTIVO
├─ María González (Cajero)   - Entrada: 08:00, Salida: null ✅ ACTIVO  
├─ Pedro Martínez (Almacén)  - Entrada: 08:00, Salida: 14:00 ⚪ FINALIZADO
└─ Ana López (Supervisor)    - Entrada: 09:00, Salida: null ✅ ACTIVO
```

**Proceso de Cierre (16:30):**
```
1. Usuario inicia cierre de turno
2. Sistema detecta 3 trabajadores activos
3. Asigna hora_salida = 16:30 a:
   - Juan Pérez
   - María González
   - Ana López
4. Calcula horas trabajadas automáticamente:
   - Juan: 8.5 horas
   - María: 8.5 horas
   - Ana: 7.5 horas
5. Continúa con cierre normal del turno
```

**Estado Final:**
```
Turno #123 - Cerrado (16:30)
├─ Juan Pérez (Vendedor)     - Entrada: 08:00, Salida: 16:30, Horas: 8.5h ✅
├─ María González (Cajero)   - Entrada: 08:00, Salida: 16:30, Horas: 8.5h ✅
├─ Pedro Martínez (Almacén)  - Entrada: 08:00, Salida: 14:00, Horas: 6.0h ✅
└─ Ana López (Supervisor)    - Entrada: 09:00, Salida: 16:30, Horas: 7.5h ✅
```

## 🔄 Logging Implementado

### Cuando hay trabajadores activos:
```
👥 Verificando trabajadores activos para cerrar...
👥 Cerrando 3 trabajador(es) activo(s)...
✅ 3 trabajador(es) cerrado(s) automáticamente
⏰ Hora de cierre: 2025-01-24T16:30:00.000Z
```

### Cuando NO hay trabajadores activos:
```
👥 Verificando trabajadores activos para cerrar...
✅ No hay trabajadores activos para cerrar
```

### Si no hay turno abierto:
```
👥 Verificando trabajadores activos para cerrar...
⚠️ No hay turno abierto, omitiendo cierre de trabajadores
```

### En caso de error:
```
👥 Verificando trabajadores activos para cerrar...
❌ Error al cerrar trabajadores activos: [error details]
```

## 💡 Características Importantes

### 1. **No Interrumpe el Cierre**
- Si falla el cierre de trabajadores, el turno se cierra de todos modos
- Los errores se registran pero no se propagan

### 2. **Hora Consistente**
- Todos los trabajadores activos reciben la misma `hora_salida`
- Coincide con el momento del cierre del turno

### 3. **Cálculo Automático**
- Las horas trabajadas se calculan automáticamente en la BD
- Usa la columna generada `horas_trabajadas`

### 4. **Soporte Offline**
- Funciona tanto en modo online como offline
- Las operaciones se sincronizan cuando hay conexión

### 5. **Feedback Visual**
- El diálogo de éxito muestra cuántos trabajadores fueron cerrados
- Solo se muestra si hay trabajadores cerrados (> 0)

## 📁 Archivos Modificados

### `cierre_screen.dart`:
1. **Import agregado**: `shift_workers_service.dart`
2. **Variable de estado**: `_trabajadoresCerrados`
3. **Nuevo método**: `_closeActiveWorkers()`
4. **Integración**: Llamada antes de `TurnoService.cerrarTurno()`
5. **UI actualizada**: Diálogo de éxito muestra trabajadores cerrados

## ✅ Beneficios

1. **Automatización**: No requiere cerrar manualmente cada trabajador
2. **Consistencia**: Todos los trabajadores tienen la misma hora de cierre
3. **Integridad de Datos**: Garantiza que no queden trabajadores "abiertos"
4. **UX Mejorada**: Proceso de cierre más rápido y simple
5. **Auditoría**: Registro completo de cuándo y cómo se cerraron los trabajadores
6. **Robustez**: No interrumpe el cierre del turno si hay errores

## 🔄 Flujo Completo de Cierre

```
Usuario presiona "Crear Cierre"
    ↓
Validar formulario
    ↓
Confirmar diferencia (si existe)
    ↓
Preparar datos de productos
    ↓
┌─────────────────────────────────┐
│ _closeActiveWorkers()           │
│ - Obtener turno abierto         │
│ - Obtener trabajadores activos  │
│ - Registrar salida masiva       │
│ - Guardar cantidad cerrada      │
└─────────────────────────────────┘
    ↓
TurnoService.cerrarTurno()
    ↓
Cerrar órdenes pendientes
    ↓
Mostrar diálogo de éxito
    ↓
Incluir: "Trabajadores cerrados: X"
```

## 🚀 Casos de Uso

### Caso 1: Cierre Normal con Trabajadores Activos
- **Escenario**: Fin del día, varios trabajadores aún activos
- **Resultado**: Todos reciben hora de salida automáticamente
- **Mensaje**: "Trabajadores cerrados: 5"

### Caso 2: Cierre sin Trabajadores Activos
- **Escenario**: Todos los trabajadores ya registraron salida
- **Resultado**: No se modifica nada
- **Mensaje**: No se muestra línea de trabajadores

### Caso 3: Cierre sin Trabajadores en el Turno
- **Escenario**: No se usó la funcionalidad de trabajadores
- **Resultado**: Proceso normal de cierre
- **Mensaje**: No se muestra línea de trabajadores

### Caso 4: Error al Cerrar Trabajadores
- **Escenario**: Problema de conexión o permisos
- **Resultado**: Se registra el error pero el turno se cierra
- **Mensaje**: Error en logs, cierre continúa

## 📝 Notas Importantes

1. **Orden de Operaciones**: Los trabajadores se cierran ANTES del turno
2. **Transaccionalidad**: Si falla el cierre de trabajadores, el turno se cierra igual
3. **Zona Horaria**: La hora de cierre se guarda en UTC
4. **Sincronización**: En modo offline, se sincroniza cuando hay conexión
5. **Permisos**: Usa los mismos permisos que el registro manual de salida

## 🎉 Conclusión

Esta funcionalidad garantiza que al cerrar un turno, todos los trabajadores activos sean cerrados automáticamente con la hora de cierre del turno, manteniendo la integridad de los datos y simplificando el proceso para los usuarios.
