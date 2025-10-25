# Implementación de Control de Recursos Humanos - Salarios

## Resumen
Se implementó un sistema completo de control de recursos humanos con gestión de salarios por hora en VentIQ Admin App.

## 1. Base de Datos

### Script SQL Creado: `add_salario_horas_column.sql`
```sql
ALTER TABLE public.app_dat_trabajadores
ADD COLUMN IF NOT EXISTS salario_horas numeric NOT NULL DEFAULT 0;
```

**Instrucciones:**
1. Ejecutar el script en Supabase para agregar la columna `salario_horas` a la tabla `app_dat_trabajadores`
2. La columna tiene valor por defecto 0 para trabajadores existentes

### ~~Actualización de RPCs Requerida~~ - NO NECESARIO ✅

**Estrategia Implementada**: En lugar de modificar los RPCs existentes, se utiliza un enfoque de dos pasos:

1. **Crear/Editar trabajador**: Se llama al RPC existente sin modificar
2. **Actualizar salario**: Se hace un UPDATE directo a `app_dat_trabajadores.salario_horas`

**Ventajas**:
- ✅ No requiere modificar RPCs existentes
- ✅ Funciona inmediatamente sin cambios en BD
- ✅ Más simple de mantener
- ✅ Menor riesgo de romper funcionalidad existente

**Verificar**:
- `fn_listar_trabajadores_tienda` debe incluir `salario_horas` en el SELECT
- Permisos de UPDATE en `app_dat_trabajadores.salario_horas`

## 2. Modelos Actualizados

### `worker_models.dart`
```dart
class WorkerData {
  final double salarioHoras; // 💰 Salario por hora del trabajador
  
  WorkerData({
    // ... otros campos
    this.salarioHoras = 0.0,
  });
  
  factory WorkerData.fromJson(Map<String, dynamic> json) {
    return WorkerData(
      // ... otros campos
      salarioHoras: (json['salario_horas'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
```

### Nuevos Modelos: `hr_models.dart`
- **`ShiftWithWorkers`**: Representa un turno con sus trabajadores
- **`ShiftWorkerHours`**: Horas trabajadas y salario de un trabajador en un turno
- **`HRSummary`**: Resumen de horas y salarios por período

## 3. Servicios

### `worker_service.dart` - Actualizado
Métodos actualizados para incluir `salarioHoras`:
- `createWorker()`: Parámetro `double salarioHoras = 0.0`
  - **Estrategia**: Llama al RPC existente + actualización directa de `salario_horas` en tabla
- `createWorkerBasic()`: Parámetro `double salarioHoras = 0.0`
  - **Estrategia**: Llama al RPC existente + actualización directa de `salario_horas` en tabla
- `editWorker()`: Parámetro `double? salarioHoras` (opcional)
  - **Estrategia**: Llama al RPC existente + actualización directa de `salario_horas` en tabla

**Nota**: No se modifican los RPCs existentes. El salario se actualiza directamente en `app_dat_trabajadores` después de la creación/edición.

### `hr_service.dart` - Nuevo
Servicio completo para gestión de RR.HH.:
- `getShiftsWithWorkers()`: Obtiene turnos con trabajadores y horas trabajadas
- `getHRSummary()`: Calcula resumen de horas y salarios por período

## 4. Interfaz de Usuario

### Tab "Personal" - Modificaciones

#### Visualización en Worker Card
- Muestra salario por hora si es mayor a 0
- Formato: `$X.XX/h` en color verde
- Ubicado debajo de las etiquetas de roles

#### Diálogo de Agregar Trabajador
- Nuevo campo: "Salario por Hora"
- Input numérico con decimales
- Valor por defecto: 0
- Helper text explicativo

#### Pantalla de Editar Trabajador (`edit_worker_multi_role_screen.dart`)
- ✅ Campo de salario por hora editable
- ✅ Ubicado en el tab "Datos Personales"
- ✅ Muestra el valor actual del trabajador
- ✅ Se actualiza al guardar cambios
- ✅ Validación numérica con decimales

### Tab "Rec. Hum." - Nuevo

#### Filtros de Fecha
- **Desde**: Selector de fecha inicial
- **Hasta**: Selector de fecha final
- **Botón Buscar**: Carga datos del período seleccionado
- Validación automática de rango de fechas

#### Resumen del Período
Card con gradiente mostrando:
- **Total Turnos**: Número de turnos en el período
- **Total Trabajadores**: Trabajadores únicos que trabajaron
- **Total Horas**: Suma de horas trabajadas
- **Total Salarios**: Suma de salarios calculados

#### Lista de Turnos (Acordeón)
Cada turno muestra:
- **Header**:
  - Estado (abierto/cerrado)
  - Número de turno y TPV
  - Vendedor responsable
  - Fechas de apertura/cierre
  - Cantidad de trabajadores
  - Duración del turno

- **Contenido Expandible**:
  - Lista de trabajadores del turno
  - Para cada trabajador:
    - Nombre y rol
    - Hora de entrada/salida
    - Horas trabajadas
    - Salario por hora
    - Salario total calculado

#### Características Visuales
- **Estados de carga**: Loading spinner con mensaje
- **Estado vacío**: Mensaje informativo si no hay turnos
- **Colores diferenciados**: Verde para turnos abiertos, gris para cerrados
- **Badges informativos**: Cantidad de trabajadores, horas trabajadas
- **Diseño responsivo**: Se adapta al tamaño de pantalla

## 5. Cálculo de Salarios

### Fórmula
```
Salario Total = Horas Trabajadas × Salario por Hora
```

### Horas Trabajadas
Calculadas automáticamente en la base de datos:
```sql
horas_trabajadas = EXTRACT(epoch FROM (hora_salida - hora_entrada)) / 3600
```

### Casos Especiales
- **Trabajador en turno**: Muestra "En turno" en lugar de horas
- **Sin salario configurado**: Muestra $0.00/h
- **Sin trabajadores en turno**: Mensaje informativo

## 6. Estructura de Consultas

### Obtener Turnos con Trabajadores
```sql
SELECT 
  turno.*,
  trabajadores.*,
  trabajadores.salario_horas,
  turno_trabajadores.horas_trabajadas
FROM app_dat_caja_turno turno
JOIN app_dat_turno_trabajadores ON turno.id = id_turno
JOIN app_dat_trabajadores ON id_trabajador = trabajadores.id
WHERE turno.id_tpv IN (SELECT id FROM app_dat_tpv WHERE id_tienda = ?)
  AND fecha_apertura BETWEEN ? AND ?
```

## 7. Flujo de Uso

### Configurar Salario de Trabajador
1. Ir a tab "Personal"
2. Agregar nuevo trabajador o editar existente
3. Ingresar salario por hora en el campo correspondiente
4. Guardar

### Consultar Horas y Salarios
1. Ir a tab "Rec. Hum."
2. Seleccionar rango de fechas (Desde/Hasta)
3. Presionar "Buscar"
4. Ver resumen del período
5. Expandir turnos para ver detalle de trabajadores
6. Ver horas trabajadas y salarios calculados

## 8. Archivos Creados/Modificados

### Creados
- `add_salario_horas_column.sql`
- `ventiq_admin_app/lib/models/hr_models.dart`
- `ventiq_admin_app/lib/services/hr_service.dart`
- `HR_SALARY_IMPLEMENTATION.md` (este archivo)

### Modificados
- `ventiq_admin_app/lib/models/worker_models.dart`
- `ventiq_admin_app/lib/services/worker_service.dart`
- `ventiq_admin_app/lib/screens/workers_screen.dart`
- `ventiq_admin_app/lib/screens/edit_worker_multi_role_screen.dart` ✅

## 9. Próximos Pasos

### Requerido (Base de Datos)
1. ✅ Ejecutar `add_salario_horas_column.sql` en Supabase
2. ✅ ~~Actualizar RPCs de creación~~ - **NO NECESARIO**: Se actualiza directamente en la tabla
3. ⏳ **IMPORTANTE**: Ejecutar `update_fn_listar_trabajadores_salario.sql` para que el RPC devuelva el campo
4. ⏳ Verificar permisos de UPDATE en `app_dat_trabajadores.salario_horas` para los roles correspondientes

### Opcional (Mejoras Futuras)
- Exportar reportes de salarios a PDF/Excel
- Gráficos de evolución de costos de personal
- Alertas de presupuesto de salarios
- Comparativas por período
- Filtros adicionales (por rol, por trabajador, etc.)

## 10. Notas Importantes

### Permisos
- Solo gerentes y supervisores pueden ver el tab "Rec. Hum."
- Los datos de salarios son sensibles y deben manejarse con cuidado

### Performance
- Las consultas están optimizadas con índices en:
  - `app_dat_caja_turno.fecha_apertura`
  - `app_dat_turno_trabajadores.id_turno`
  - `app_dat_trabajadores.id`

### Validaciones
- Salario por hora debe ser >= 0
- Fechas de filtro: desde <= hasta
- Turnos sin trabajadores muestran mensaje informativo

### Logging
- Todos los servicios incluyen logging detallado
- Formato: emoji + mensaje descriptivo
- Útil para debugging y auditoría

## 11. Testing

### Casos de Prueba
1. **Crear trabajador con salario**
   - Verificar que se guarda correctamente
   - Verificar que se muestra en el card

2. **Editar salario de trabajador**
   - Cambiar valor
   - Verificar actualización en UI

3. **Consultar turnos sin trabajadores**
   - Verificar mensaje informativo
   - No debe mostrar errores

4. **Consultar turnos con trabajadores**
   - Verificar cálculo de horas
   - Verificar cálculo de salarios
   - Verificar resumen del período

5. **Trabajador en turno activo**
   - Debe mostrar "En turno"
   - Salario debe ser $0.00 hasta que salga

## 12. Soporte

Para problemas o dudas:
1. Revisar logs en consola (emoji + mensaje)
2. Verificar que los RPCs estén actualizados
3. Verificar permisos de usuario
4. Verificar que la columna `salario_horas` exista en la BD
