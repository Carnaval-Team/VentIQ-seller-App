# Trigger: Notificación de Producto Agotado

## 📋 Descripción

Trigger automático que **notifica a todos los usuarios relevantes** cuando un producto se agota completamente en el inventario.

## 🎯 Condición de Activación

El trigger se ejecuta cuando:
- ✅ `cantidad_final = 0` (producto agotado)
- ✅ `cantidad_inicial > 0` (había stock previo)
- ✅ Se actualiza el campo `cantidad_final` en `app_dat_inventario_productos`

## 👥 Usuarios Notificados

### 1. **Vendedores** (Prioridad: Alta)
- Se obtienen a través de `app_dat_vendedor` → `app_dat_tpv`
- Filtrados por `id_tienda` del producto
- Condición: `tpv.id_tienda = producto.id_tienda`

### 2. **Supervisores** (Prioridad: Alta)
- Se obtienen de `app_dat_supervisor`
- Filtrados por `id_tienda` del producto
- Condición: `supervisor.id_tienda = producto.id_tienda`

### 3. **Gerentes** (Prioridad: Alta)
- Se obtienen de `app_dat_gerente`
- Filtrados por `id_tienda` del producto
- Condición: `gerente.id_tienda = producto.id_tienda`

### 4. **Almaceneros** (Prioridad: Urgente ⚡)
- Se obtienen de `app_dat_almacenero`
- Filtrados por `id_almacen` de la ubicación
- Condición: `almacenero.id_almacen = ubicacion.id_almacen`
- **Nota**: Reciben prioridad URGENTE para acción inmediata

## 📊 Información en la Notificación

### Título:
```
⚠️ Producto Agotado
```

### Mensaje:
```
El producto "[NOMBRE][ - VARIANTE][: OPCIÓN]" se ha agotado completamente[ en UBICACIÓN][ (Almacén: ALMACÉN)]
```

### Ejemplos de Mensajes:

**Producto simple:**
```
El producto "Coca Cola 2L" se ha agotado completamente en Estante A1 (Almacén: Principal)
```

**Producto con variante:**
```
El producto "Camisa - Talla: XL" se ha agotado completamente en Zona Textil (Almacén: Ropa)
```

**Producto con variante y opción:**
```
El producto "Zapatos - Color: Rojo" se ha agotado completamente en Pasillo 3 (Almacén: Calzado)
```

### Data JSON:
```json
{
  "id_producto": 123,
  "id_variante": 45,
  "id_opcion_variante": 67,
  "id_ubicacion": 89,
  "id_almacen": 10,
  "producto_nombre": "Coca Cola 2L",
  "cantidad_anterior": 50
}
```

## 🔄 Flujo del Trigger

```
┌─────────────────────────────────────┐
│  UPDATE cantidad_final = 0          │
│  WHERE cantidad_inicial > 0         │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Trigger: trg_notificar_producto_   │
│           agotado                    │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Función: fn_notificar_producto_    │
│           agotado()                  │
└──────────────┬──────────────────────┘
               │
               ├─────────────────────────────┐
               │                             │
               ▼                             ▼
┌──────────────────────┐    ┌──────────────────────┐
│ Obtener información  │    │ Construir mensaje    │
│ - Producto           │    │ y data JSON          │
│ - Variante           │    │                      │
│ - Opción             │    │                      │
│ - Ubicación          │    │                      │
│ - Almacén            │    │                      │
│ - Tienda             │    │                      │
└──────────┬───────────┘    └──────────┬───────────┘
           │                           │
           └───────────┬───────────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │  Notificar a usuarios:       │
        │  1. Vendedores (Alta)        │
        │  2. Supervisores (Alta)      │
        │  3. Gerentes (Alta)          │
        │  4. Almaceneros (Urgente)    │
        └──────────────────────────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │  fn_crear_notificacion()     │
        │  para cada usuario           │
        └──────────────────────────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │  Notificaciones creadas      │
        │  + Push en Android           │
        └──────────────────────────────┘
```

## 📝 Estructura de Tablas Involucradas

### Tabla Principal:
- **`app_dat_inventario_productos`**: Donde se actualiza `cantidad_final`

### Tablas de Información:
- **`app_dat_producto`**: Nombre del producto y `id_tienda`
- **`app_dat_variantes`**: Información de variante
- **`app_dat_atributo_opcion`**: Opciones de variante
- **`app_dat_layout_almacen`**: Ubicación y `id_almacen`
- **`app_dat_almacen`**: Nombre del almacén

### Tablas de Usuarios:
- **`app_dat_vendedor`**: Vendedores (via `app_dat_tpv`)
- **`app_dat_tpv`**: Puntos de venta con `id_tienda`
- **`app_dat_supervisor`**: Supervisores por tienda
- **`app_dat_gerente`**: Gerentes por tienda
- **`app_dat_almacenero`**: Almaceneros por almacén

## 🚀 Instalación

### Paso 1: Ejecutar Script SQL

```bash
# En Supabase SQL Editor, ejecutar:
supabase/trigger_notificar_producto_agotado.sql
```

### Paso 2: Verificar Creación

```sql
-- Verificar función
SELECT proname, prosrc 
FROM pg_proc 
WHERE proname = 'fn_notificar_producto_agotado';

-- Verificar trigger
SELECT tgname, tgtype, tgenabled 
FROM pg_trigger 
WHERE tgname = 'trg_notificar_producto_agotado';
```

## 🧪 Pruebas

### Prueba 1: Agotar un Producto

```sql
-- 1. Encontrar un producto con stock
SELECT id, id_producto, cantidad_inicial, cantidad_final
FROM app_dat_inventario_productos
WHERE cantidad_inicial > 0 
  AND cantidad_final > 0
LIMIT 1;

-- 2. Actualizar cantidad_final a 0
UPDATE app_dat_inventario_productos
SET cantidad_final = 0
WHERE id = <ID_DEL_REGISTRO>;

-- 3. Verificar notificaciones creadas
SELECT 
    n.id,
    n.user_id,
    n.tipo,
    n.titulo,
    n.mensaje,
    n.prioridad,
    n.data,
    n.created_at
FROM app_dat_notificaciones n
WHERE n.tipo = 'inventario'
  AND n.titulo LIKE '%Producto Agotado%'
ORDER BY n.created_at DESC
LIMIT 10;
```

### Prueba 2: Verificar Usuarios Notificados

```sql
-- Ver qué usuarios fueron notificados
SELECT 
    n.user_id,
    u.email,
    n.prioridad,
    n.mensaje,
    n.created_at
FROM app_dat_notificaciones n
JOIN auth.users u ON n.user_id = u.id
WHERE n.tipo = 'inventario'
  AND n.titulo = '⚠️ Producto Agotado'
  AND n.created_at > NOW() - INTERVAL '1 hour'
ORDER BY n.created_at DESC;
```

### Prueba 3: Verificar por Rol

```sql
-- Vendedores notificados
SELECT DISTINCT v.uuid, v.id, 'Vendedor' as rol
FROM app_dat_notificaciones n
JOIN app_dat_vendedor v ON n.user_id = v.uuid
WHERE n.titulo = '⚠️ Producto Agotado'
  AND n.created_at > NOW() - INTERVAL '1 hour';

-- Supervisores notificados
SELECT DISTINCT s.uuid, s.id, 'Supervisor' as rol
FROM app_dat_notificaciones n
JOIN app_dat_supervisor s ON n.user_id = s.uuid
WHERE n.titulo = '⚠️ Producto Agotado'
  AND n.created_at > NOW() - INTERVAL '1 hour';

-- Gerentes notificados
SELECT DISTINCT g.uuid, g.id, 'Gerente' as rol
FROM app_dat_notificaciones n
JOIN app_dat_gerente g ON n.user_id = g.uuid
WHERE n.titulo = '⚠️ Producto Agotado'
  AND n.created_at > NOW() - INTERVAL '1 hour';

-- Almaceneros notificados
SELECT DISTINCT a.uuid, a.id, 'Almacenero' as rol
FROM app_dat_notificaciones n
JOIN app_dat_almacenero a ON n.user_id = a.uuid
WHERE n.titulo = '⚠️ Producto Agotado'
  AND n.created_at > NOW() - INTERVAL '1 hour';
```

## 📱 Resultado en la App

Cuando se agota un producto:

1. **Notificación Push** aparece en Android (barra de notificaciones)
2. **Notificación Emergente** si es urgente (almaceneros)
3. **Badge actualizado** en el botón de notificaciones
4. **Lista actualizada** en el panel de notificaciones
5. **Vibración y sonido** según configuración

## ⚙️ Configuración

### Cambiar Prioridades:

```sql
-- Editar función para cambiar prioridades
-- Línea ~120: Vendedores
'alta'  -- Cambiar a 'urgente', 'normal', o 'baja'

-- Línea ~135: Supervisores
'alta'  -- Cambiar a 'urgente', 'normal', o 'baja'

-- Línea ~150: Gerentes
'alta'  -- Cambiar a 'urgente', 'normal', o 'baja'

-- Línea ~168: Almaceneros
'urgente'  -- Cambiar a 'alta', 'normal', o 'baja'
```

### Deshabilitar Trigger Temporalmente:

```sql
-- Deshabilitar
ALTER TABLE app_dat_inventario_productos 
DISABLE TRIGGER trg_notificar_producto_agotado;

-- Habilitar
ALTER TABLE app_dat_inventario_productos 
ENABLE TRIGGER trg_notificar_producto_agotado;
```

### Eliminar Trigger:

```sql
-- Eliminar trigger
DROP TRIGGER IF EXISTS trg_notificar_producto_agotado 
ON app_dat_inventario_productos;

-- Eliminar función
DROP FUNCTION IF EXISTS fn_notificar_producto_agotado();
```

## 🔍 Debugging

### Ver Logs del Trigger:

```sql
-- Habilitar logging en PostgreSQL
SET client_min_messages TO NOTICE;

-- Ejecutar update y ver logs
UPDATE app_dat_inventario_productos
SET cantidad_final = 0
WHERE id = <ID>;

-- Los logs aparecerán con:
-- NOTICE: Notificaciones enviadas para producto agotado: [NOMBRE] (ID: [ID])
```

### Verificar Ejecución:

```sql
-- Ver última ejecución del trigger
SELECT 
    schemaname,
    tablename,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables
WHERE tablename = 'app_dat_inventario_productos';
```

## 📊 Estadísticas

### Notificaciones por Tipo de Usuario:

```sql
SELECT 
    CASE 
        WHEN EXISTS (SELECT 1 FROM app_dat_vendedor WHERE uuid = n.user_id) THEN 'Vendedor'
        WHEN EXISTS (SELECT 1 FROM app_dat_supervisor WHERE uuid = n.user_id) THEN 'Supervisor'
        WHEN EXISTS (SELECT 1 FROM app_dat_gerente WHERE uuid = n.user_id) THEN 'Gerente'
        WHEN EXISTS (SELECT 1 FROM app_dat_almacenero WHERE uuid = n.user_id) THEN 'Almacenero'
        ELSE 'Otro'
    END as tipo_usuario,
    COUNT(*) as total_notificaciones,
    COUNT(CASE WHEN n.leida THEN 1 END) as leidas,
    COUNT(CASE WHEN NOT n.leida THEN 1 END) as no_leidas
FROM app_dat_notificaciones n
WHERE n.tipo = 'inventario'
  AND n.titulo = '⚠️ Producto Agotado'
  AND n.created_at > NOW() - INTERVAL '7 days'
GROUP BY tipo_usuario
ORDER BY total_notificaciones DESC;
```

## ✅ Checklist de Implementación

- [ ] Script SQL ejecutado en Supabase
- [ ] Función `fn_notificar_producto_agotado()` creada
- [ ] Trigger `trg_notificar_producto_agotado` creado
- [ ] Trigger habilitado y activo
- [ ] Prueba realizada con producto de prueba
- [ ] Notificaciones verificadas en tabla
- [ ] Notificaciones push verificadas en Android
- [ ] Usuarios correctos notificados por rol
- [ ] Prioridades correctas asignadas
- [ ] Mensajes legibles y descriptivos

## 🚨 Consideraciones Importantes

1. **Performance**: El trigger se ejecuta por cada UPDATE. Si hay muchas actualizaciones simultáneas, puede generar muchas notificaciones.

2. **Duplicados**: Si se actualiza `cantidad_final` múltiples veces a 0, se generarán múltiples notificaciones. Considerar agregar lógica para evitar duplicados.

3. **Usuarios sin UUID**: El trigger solo notifica a usuarios con `uuid IS NOT NULL`. Verificar que todos los usuarios tengan UUID asignado.

4. **Almaceneros**: Solo se notifica a almaceneros del almacén específico donde se agotó el producto.

5. **Vendedores**: Se obtienen a través de TPV, asegurarse de que los vendedores estén correctamente asignados a TPVs.

## 📚 Recursos

- [PostgreSQL Triggers](https://www.postgresql.org/docs/current/sql-createtrigger.html)
- [Supabase Realtime](https://supabase.com/docs/guides/realtime)
- [Sistema de Notificaciones VentIQ](./NOTIFICACIONES_README.md)

---

**Trigger de Notificación de Producto Agotado - VentIQ** ⚠️🔔
