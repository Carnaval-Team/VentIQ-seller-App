# 📋 Plan de Implementación: Sistema de Devoluciones en Consignación

## ✅ Estado Actual
- ✅ Propuesta completa documentada
- ✅ Scripts SQL creados
- ✅ Enfoque optimizado sin redundancia

---

## 🚀 Pasos de Implementación

### **PASO 1: Ejecutar SQL en Supabase** ⭐ EMPEZAR AQUÍ

#### 1.1 Crear estructura de devoluciones
```bash
Archivo: SQL_OPTIMIZATION/implementar_devoluciones_consignacion.sql
```

**Acciones:**
1. Abrir Supabase SQL Editor
2. Copiar contenido completo del archivo
3. Ejecutar script
4. Verificar mensajes de confirmación

**Resultado esperado:**
```
✅ Columnas agregadas a app_dat_consignacion_envio_producto
✅ Foreign keys y índices creados
✅ RPCs creados: crear_devolucion_consignacion, aprobar_devolucion_consignacion
✅ Vista creada: v_devoluciones_consignacion
```

---

### **PASO 2: Modificar RPC crear_envio_consignacion** ⭐ CRÍTICO

**Archivo a modificar:** RPC existente en Supabase

**Buscar esta sección:**
```sql
INSERT INTO app_dat_consignacion_envio_producto (
  id_envio,
  id_producto,
  id_inventario,
  cantidad_propuesta,
  precio_costo_usd,
  precio_costo_cup,
  tasa_cambio
) VALUES (...)
```

**Cambiar por:**
```sql
-- Primero obtener datos del inventario original
SELECT 
  ip.id_presentacion,
  ip.id_variante,
  ip.id_ubicacion,
  ip.id
INTO 
  v_id_presentacion_original,
  v_id_variante_original,
  v_id_ubicacion_original,
  v_id_inventario_original
FROM app_dat_inventario_productos ip
WHERE ip.id = (v_producto->>'id_inventario')::BIGINT;

-- Luego insertar con datos originales
INSERT INTO app_dat_consignacion_envio_producto (
  id_envio,
  id_producto,
  id_inventario,
  cantidad_propuesta,
  precio_costo_usd,
  precio_costo_cup,
  tasa_cambio,
  id_presentacion_original,  -- ⭐ NUEVO
  id_variante_original,      -- ⭐ NUEVO
  id_ubicacion_original,     -- ⭐ NUEVO
  id_inventario_original     -- ⭐ NUEVO
) VALUES (
  v_id_envio,
  v_id_producto,
  v_id_inventario,
  v_cantidad,
  v_precio_costo_usd,
  v_precio_costo_cup,
  v_tasa_cambio,
  v_id_presentacion_original,  -- ⭐ NUEVO
  v_id_variante_original,      -- ⭐ NUEVO
  v_id_ubicacion_original,     -- ⭐ NUEVO
  v_id_inventario_original     -- ⭐ NUEVO
);
```

**Agregar variables al DECLARE:**
```sql
DECLARE
  -- ... variables existentes ...
  v_id_presentacion_original BIGINT;
  v_id_variante_original BIGINT;
  v_id_ubicacion_original BIGINT;
  v_id_inventario_original BIGINT;
```

---

### **PASO 3: Modificar función de precio promedio** ⭐ IMPORTANTE

**Buscar:** Función o trigger que actualiza `app_dat_producto_presentacion.precio_promedio`

**Opciones comunes:**
- `fn_actualizar_precio_promedio_recepcion`
- `fn_actualizar_precio_promedio_recepcion_v2`
- Trigger en `app_dat_recepcion_productos`

**Agregar al inicio de la función:**
```sql
DECLARE
  v_es_devolucion BOOLEAN;
  -- ... otras variables ...
BEGIN
  -- ⭐ VERIFICAR SI ES DEVOLUCIÓN
  SELECT EXISTS (
    SELECT 1 
    FROM app_dat_consignacion_envio
    WHERE id_operacion_recepcion = p_id_operacion
      AND tipo_envio = 2  -- Devolución
  ) INTO v_es_devolucion;
  
  -- ⭐ SI ES DEVOLUCIÓN, NO ACTUALIZAR PRECIO PROMEDIO
  IF v_es_devolucion THEN
    RAISE NOTICE 'Operación % es devolución - precio promedio NO se actualiza', p_id_operacion;
    RETURN;  -- O RETURN NEW si es trigger
  END IF;
  
  -- Continuar con lógica normal...
```

**Referencia:** Ver ejemplos en `SQL_OPTIMIZATION/ignorar_precio_promedio_devoluciones.sql`

---

### **PASO 4: Modificar servicios Dart**

#### 4.1 Modificar `ConsignacionEnvioService.crearEnvio()`

**Archivo:** `ventiq_admin_app/lib/services/consignacion_envio_service.dart`

**Buscar (línea ~64-78):**
```dart
final productosJson = productos.map((p) {
  return {
    'id_inventario': p['id_inventario'],
    'id_producto': p['id_producto'],
    'cantidad': p['cantidad'],
    'precio_costo_usd': precioCostoUsd,
    'precio_costo_cup': precioVentaCup,
    'precio_venta': precioVentaCup,
    'tasa_cambio': tasaCambio,
  };
}).toList();
```

**Cambiar por:**
```dart
final productosJson = productos.map((p) {
  return {
    'id_inventario': p['id_inventario'],
    'id_producto': p['id_producto'],
    'cantidad': p['cantidad'],
    'precio_costo_usd': precioCostoUsd,
    'precio_costo_cup': precioVentaCup,
    'precio_venta': precioVentaCup,
    'tasa_cambio': tasaCambio,
    // ⭐ AGREGAR INFORMACIÓN ORIGINAL
    'id_presentacion': p['id_presentacion'],
    'id_variante': p['id_variante'],
    'id_ubicacion': p['id_ubicacion'],
  };
}).toList();
```

#### 4.2 Verificar `AsignarProductosConsignacionScreen`

**Archivo:** `ventiq_admin_app/lib/screens/asignar_productos_consignacion_screen.dart`

**Verificar que `_procederConConfiguracion()` ya pasa estos campos:**
- ✅ `id_presentacion`
- ✅ `id_variante`
- ✅ `id_ubicacion`

**Si no los pasa, agregarlos al mapa de productos.**

---

### **PASO 5: Probar flujo completo**

#### 5.1 Crear envío de prueba
1. Ir a pantalla de consignaciones
2. Crear nuevo envío con productos
3. Verificar en BD que se guardaron:
   - `id_presentacion_original`
   - `id_variante_original`
   - `id_ubicacion_original`

**Query de verificación:**
```sql
SELECT 
  id,
  id_producto,
  id_presentacion_original,
  id_variante_original,
  id_ubicacion_original
FROM app_dat_consignacion_envio_producto
WHERE id_envio = [ID_DEL_ENVIO]
```

#### 5.2 Aceptar envío
1. Consignatario acepta el envío
2. Verificar que productos se reciben correctamente

#### 5.3 Crear devolución
1. Consignatario crea devolución
2. Verificar que se copia información original:

**Query de verificación:**
```sql
SELECT 
  ce.numero_envio,
  ce.tipo_envio,
  cep.id_presentacion_original,
  cep.id_variante_original,
  cep.id_ubicacion_original
FROM app_dat_consignacion_envio ce
INNER JOIN app_dat_consignacion_envio_producto cep ON cep.id_envio = ce.id
WHERE ce.tipo_envio = 2  -- Devolución
ORDER BY ce.created_at DESC
LIMIT 5;
```

#### 5.4 Aprobar devolución
1. Consignador aprueba devolución
2. Verificar que productos regresan a ubicación original
3. **VERIFICAR QUE PRECIO PROMEDIO NO SE ACTUALIZA**

**Query de verificación:**
```sql
-- Ver operación de recepción de devolución
SELECT 
  op.id,
  op.observaciones,
  ce.tipo_envio,
  ce.numero_envio
FROM app_dat_operaciones op
INNER JOIN app_dat_consignacion_envio ce ON ce.id_operacion_recepcion = op.id
WHERE ce.tipo_envio = 2
ORDER BY op.created_at DESC
LIMIT 5;

-- Verificar que precio promedio NO cambió
SELECT 
  id_producto,
  id_presentacion,
  precio_promedio,
  updated_at
FROM app_dat_producto_presentacion
WHERE id_producto = [ID_PRODUCTO_DEVUELTO]
ORDER BY updated_at DESC;
```

---

## 🔍 Checklist de Verificación

### Base de Datos
- [ ] Columnas agregadas a `app_dat_consignacion_envio_producto`
- [ ] RPCs creados: `crear_devolucion_consignacion`, `aprobar_devolucion_consignacion`
- [ ] Vista creada: `v_devoluciones_consignacion`
- [ ] RPC `crear_envio_consignacion` modificado
- [ ] Función de precio promedio modificada

### Código Dart
- [ ] `ConsignacionEnvioService.crearEnvio()` modificado
- [ ] `AsignarProductosConsignacionScreen` pasa campos originales

### Pruebas Funcionales
- [ ] Crear envío guarda datos originales
- [ ] Crear devolución copia datos originales
- [ ] Aprobar devolución restaura a ubicación original
- [ ] Precio promedio NO se actualiza en devoluciones
- [ ] Precio promedio SÍ se actualiza en recepciones normales

---

## 📝 Archivos de Referencia

1. **Propuesta completa:** `PROPUESTA_DEVOLUCIONES_CONSIGNACION.md`
2. **SQL principal:** `SQL_OPTIMIZATION/implementar_devoluciones_consignacion.sql`
3. **SQL precio promedio:** `SQL_OPTIMIZATION/ignorar_precio_promedio_devoluciones.sql`

---

## ⚠️ Puntos Críticos

1. **Precio promedio:** Asegurarse de que la función/trigger verifica `tipo_envio = 2`
2. **Datos originales:** RPC `crear_envio_consignacion` DEBE guardar los 4 campos nuevos
3. **Copia correcta:** RPC `crear_devolucion_consignacion` DEBE copiar datos del envío original
4. **Restauración:** RPC `aprobar_devolucion_consignacion` DEBE usar datos originales

---

## 🎯 Resultado Esperado

✅ Productos devueltos regresan a su presentación ORIGINAL
✅ Productos devueltos regresan a su ubicación ORIGINAL
✅ Inventario se actualiza correctamente
✅ Precio promedio NO se modifica en devoluciones
✅ Trazabilidad completa mantenida

---

**Fecha:** 7 de Enero, 2026
**Estado:** 📋 LISTO PARA IMPLEMENTAR
