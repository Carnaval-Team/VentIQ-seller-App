# Funciones para Gestión de Presentaciones en Recepciones

Este conjunto de funciones SQL permite identificar y corregir operaciones de recepción de productos que no tienen presentación asignada, asignándoles automáticamente la primera presentación disponible del producto.

## Problema que Resuelve

En el sistema VentIQ, las operaciones de recepción de productos pueden quedar sin presentación asignada (`id_presentacion = NULL`), lo cual puede causar inconsistencias en el inventario y reportes. Estas funciones identifican estos casos y los corrigen automáticamente.

## Funciones Disponibles

### 1. `fn_consultar_recepciones_sin_presentacion`

**Propósito**: Consulta (sin modificar) las recepciones que no tienen presentación asignada.

**Parámetros**:
- `p_id_tienda` (BIGINT): ID de la tienda (requerido)
- `p_id_producto` (BIGINT): ID del producto específico (opcional)

**Retorna**:
- `id_recepcion`: ID de la recepción sin presentación
- `id_operacion`: ID de la operación asociada
- `fecha_recepcion`: Fecha de la recepción
- `id_producto`: ID del producto
- `nombre_producto`: Nombre del producto
- `sku_producto`: SKU del producto
- `cantidad_recibida`: Cantidad recibida
- `precio_unitario`: Precio unitario
- `presentacion_actual`: Presentación actual (NULL)
- `primera_presentacion_disponible`: ID de la primera presentación disponible
- `nombre_primera_presentacion`: Nombre de la presentación que se asignaría
- `es_presentacion_base`: Si es la presentación base del producto
- `tiene_presentaciones_disponibles`: Si el producto tiene presentaciones configuradas

### 2. `fn_estadisticas_recepciones_sin_presentacion`

**Propósito**: Proporciona estadísticas generales del problema.

**Parámetros**:
- `p_id_tienda` (BIGINT): ID de la tienda (requerido)

**Retorna**:
- `total_recepciones_sin_presentacion`: Total de recepciones afectadas
- `total_productos_afectados`: Total de productos únicos afectados
- `productos_con_presentaciones_disponibles`: Productos que tienen presentaciones configuradas
- `productos_sin_presentaciones_disponibles`: Productos sin presentaciones configuradas
- `valor_total_recepciones_afectadas`: Valor monetario total de las recepciones afectadas

### 3. `fn_actualizar_presentaciones_recepciones`

**Propósito**: Actualiza las recepciones asignándoles la primera presentación disponible.

**Parámetros**:
- `p_id_tienda` (BIGINT): ID de la tienda (requerido)

**Retorna**:
- `id_recepcion`: ID de la recepción procesada
- `id_producto`: ID del producto
- `nombre_producto`: Nombre del producto
- `sku_producto`: SKU del producto
- `presentacion_anterior`: Presentación anterior (NULL)
- `presentacion_nueva`: ID de la presentación asignada
- `nombre_presentacion_nueva`: Nombre de la presentación asignada
- `actualizado`: Si se pudo actualizar (true/false)

## Flujo de Trabajo Recomendado

### Paso 1: Revisar Estadísticas Generales
```sql
-- Ver el panorama general del problema
SELECT * FROM fn_estadisticas_recepciones_sin_presentacion(1);
```

**Ejemplo de resultado**:
```
total_recepciones_sin_presentacion | total_productos_afectados | productos_con_presentaciones_disponibles | productos_sin_presentaciones_disponibles | valor_total_recepciones_afectadas
-----------------------------------|---------------------------|------------------------------------------|------------------------------------------|----------------------------------
                               45  |                        12 |                                       10 |                                        2 |                          15750.50
```

### Paso 2: Revisar Detalles Específicos
```sql
-- Ver todas las recepciones sin presentación
SELECT * FROM fn_consultar_recepciones_sin_presentacion(1);

-- Ver solo las que SÍ se pueden corregir
SELECT * FROM fn_consultar_recepciones_sin_presentacion(1) 
WHERE tiene_presentaciones_disponibles = true;

-- Ver las que NO se pueden corregir (productos sin presentaciones configuradas)
SELECT * FROM fn_consultar_recepciones_sin_presentacion(1) 
WHERE tiene_presentaciones_disponibles = false;
```

### Paso 3: Ejecutar la Corrección
```sql
-- Actualizar todas las recepciones de la tienda
SELECT * FROM fn_actualizar_presentaciones_recepciones(1);

-- Ver solo las actualizaciones exitosas
SELECT * FROM fn_actualizar_presentaciones_recepciones(1) 
WHERE actualizado = true;

-- Contar cuántas se actualizaron
SELECT 
    COUNT(*) as total_procesadas,
    COUNT(CASE WHEN actualizado THEN 1 END) as total_actualizadas,
    COUNT(CASE WHEN NOT actualizado THEN 1 END) as total_no_actualizadas
FROM fn_actualizar_presentaciones_recepciones(1);
```

## Ejemplos de Uso Específicos

### Consultar un Producto Específico
```sql
-- Ver recepciones sin presentación del producto ID 123
SELECT * FROM fn_consultar_recepciones_sin_presentacion(1, 123);
```

### Identificar Productos Problemáticos
```sql
-- Productos que no tienen presentaciones configuradas
SELECT DISTINCT 
    id_producto,
    nombre_producto,
    sku_producto
FROM fn_consultar_recepciones_sin_presentacion(1)
WHERE tiene_presentaciones_disponibles = false
ORDER BY nombre_producto;
```

### Validar Resultados Después de la Actualización
```sql
-- Verificar que no queden recepciones sin presentación (después de la corrección)
SELECT COUNT(*) as recepciones_pendientes
FROM app_dat_recepcion_productos rp
INNER JOIN app_dat_operaciones o ON rp.id_operacion = o.id
WHERE o.id_tienda = 1 
  AND rp.id_presentacion IS NULL;
```

## Consideraciones Importantes

### Criterio de Selección de Presentación
La función selecciona la presentación usando este criterio:
1. **Prioridad 1**: Presentación marcada como base (`es_base = true`)
2. **Prioridad 2**: Primera presentación por ID (la más antigua)

### Productos Afectados
Solo se procesan productos que cumplan:
- Pertenecen a la tienda especificada
- No están eliminados (`deleted_at IS NULL`)
- Son comprables (`es_comprable = true`)

### Recepciones Procesadas
Solo se procesan recepciones que:
- No tienen presentación asignada (`id_presentacion IS NULL`)
- Pertenecen a operaciones de la tienda especificada

### Transaccionalidad
- Las funciones de consulta son de solo lectura
- La función de actualización modifica datos, úsala con precaución
- Se recomienda hacer backup antes de ejecutar actualizaciones masivas

## Instalación

1. Ejecutar el archivo `fn_consultar_recepciones_sin_presentacion.sql` en la base de datos
2. Ejecutar el archivo `fn_actualizar_presentaciones_recepciones.sql` en la base de datos
3. Verificar que las funciones se crearon correctamente:

```sql
-- Verificar que las funciones existen
SELECT routine_name, routine_type 
FROM information_schema.routines 
WHERE routine_name LIKE '%presentacion%' 
  AND routine_schema = 'public';
```

## Solución de Problemas

### Error: "Función no existe"
- Verificar que las funciones se ejecutaron correctamente
- Verificar permisos de ejecución

### Error: "No se encontraron presentaciones"
- Verificar que los productos tengan presentaciones configuradas en `app_dat_producto_presentacion`
- Usar la función de consulta para identificar productos sin presentaciones

### Rendimiento
- Para tiendas con muchos productos, la función puede tardar varios minutos
- Se recomienda ejecutar en horarios de baja actividad
- Monitorear el log de PostgreSQL durante la ejecución

## Mantenimiento

Se recomienda ejecutar estas funciones periódicamente para mantener la integridad de los datos, especialmente después de:
- Importaciones masivas de datos
- Migraciones de sistemas
- Actualizaciones que afecten la estructura de productos o presentaciones
