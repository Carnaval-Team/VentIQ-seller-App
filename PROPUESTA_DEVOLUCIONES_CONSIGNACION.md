# 📋 PROPUESTA: Sistema Completo de Devoluciones en Consignación

## 🎯 Problema Identificado

Actualmente, el sistema de devoluciones **NO guarda la información de la presentación original** del producto, lo que causa:

❌ **Problema 1:** Al devolver productos, se genera un nuevo inventario con una nueva presentación
❌ **Problema 2:** Los productos no retornan a su ubicación original (almacén y zona)
❌ **Problema 3:** No se mantiene la trazabilidad del producto original y su presentación
❌ **Problema 4:** Las operaciones de extracción/recepción en devoluciones no siguen la misma lógica que los envíos
❌ **Problema 5:** Las recepciones de devolución actualizan incorrectamente el precio promedio (debe ignorarse)

---

## 📊 Análisis de Tablas Actuales

### 1. `app_dat_consignacion_envio_producto`
**Campos actuales:**
```sql
- id_producto_consignacion (FK) ✅
- id_inventario (FK) ✅
- id_producto (FK) ✅
- cantidad_propuesta ✅
- precio_costo_usd ✅
- precio_costo_cup ✅
```

**❌ FALTA:**
- `id_presentacion_original` - Presentación del producto en la tienda consignadora
- `id_variante_original` - Variante del producto original
- `id_ubicacion_original` - Ubicación (zona) original del producto
- `id_inventario_original` - Referencia al inventario original

### 2. `app_dat_producto_consignacion`
**Campos actuales:**
```sql
- id_presentacion (FK) 
- id_variante (FK) 
- id_ubicacion_origen (FK) 
```

**✅ TIENE:** La información necesaria, pero NO se está usando correctamente en devoluciones

### 3. Verificación de operaciones de devolución

**✅ ENFOQUE RECOMENDADO (Sin redundancia):**
- **NO agregar** campo `es_devolucion_consignacion` a `app_dat_operaciones`
- Verificar directamente en `app_dat_consignacion_envio` usando FK existente
- Consulta: `WHERE id_operacion_recepcion = p_id_operacion AND tipo_envio = 2`

**Ventajas:**
- ✅ Sin redundancia de datos
- ✅ Sin ALTER TABLE necesario
- ✅ Usa índice existente en FK `id_operacion_recepcion`
- ✅ Fuente única de verdad (`tipo_envio`)
- ✅ Más mantenible

---

## 🔧 Cambios Necesarios en Base de Datos

### 1. Modificar `app_dat_consignacion_envio_producto`

```sql
-- Agregar columnas para mantener referencia al producto original
ALTER TABLE app_dat_consignacion_envio_producto
ADD COLUMN id_presentacion_original bigint,
ADD COLUMN id_variante_original bigint,
ADD COLUMN id_ubicacion_original bigint,
ADD COLUMN id_inventario_original bigint;

-- Agregar foreign keys
ALTER TABLE app_dat_consignacion_envio_producto
ADD CONSTRAINT fk_envio_producto_presentacion_original 
  FOREIGN KEY (id_presentacion_original) 
  REFERENCES app_dat_producto_presentacion(id),
ADD CONSTRAINT fk_envio_producto_variante_original 
  FOREIGN KEY (id_variante_original) 
  REFERENCES app_dat_variantes(id),
ADD CONSTRAINT fk_envio_producto_ubicacion_original 
  FOREIGN KEY (id_ubicacion_original) 
  REFERENCES app_dat_layout_almacen(id),
ADD CONSTRAINT fk_envio_producto_inventario_original 
  FOREIGN KEY (id_inventario_original) 
  REFERENCES app_dat_inventario_productos(id);

-- Agregar índices para mejorar performance
CREATE INDEX idx_envio_producto_presentacion_original 
  ON app_dat_consignacion_envio_producto(id_presentacion_original);
CREATE INDEX idx_envio_producto_ubicacion_original 
  ON app_dat_consignacion_envio_producto(id_ubicacion_original);
```

**Propósito:**
- `id_presentacion_original`: Mantener la presentación exacta del producto en la tienda consignadora
- `id_variante_original`: Mantener la variante exacta del producto original
- `id_ubicacion_original`: Saber a qué zona debe regresar el producto en caso de devolución
- `id_inventario_original`: Referencia directa al registro de inventario original

### 2. Verificación de devoluciones en función de precio promedio

**✅ ENFOQUE RECOMENDADO - Verificar por relación (Sin redundancia):**

```sql
-- En la función/trigger que actualiza precio promedio:
DECLARE
  v_es_devolucion BOOLEAN;
BEGIN
  -- Verificar si la operación es de devolución
  SELECT EXISTS (
    SELECT 1 
    FROM app_dat_consignacion_envio
    WHERE id_operacion_recepcion = p_id_operacion
      AND tipo_envio = 2  -- Devolución
  ) INTO v_es_devolucion;
  
  -- Si es devolución, NO actualizar precio promedio
  IF v_es_devolucion THEN
    RETURN;  -- O RETURN NEW en trigger
  END IF;
  
  -- Continuar con actualización normal...
END;
```

**Ventajas:**
- ✅ Sin modificar estructura de `app_dat_operaciones`
- ✅ Usa FK e índice existente
- ✅ Fuente única de verdad
- ✅ Performance O(1) con índice

---

## 📝 Cambios en RPCs (Funciones SQL)

### 1. Modificar `crear_envio_consignacion()`

**Cambio:** Guardar información del producto original al crear el envío

```sql
-- ANTES (línea ~80-100 del RPC)
INSERT INTO app_dat_consignacion_envio_producto (
  id_envio,
  id_producto,
  id_inventario,
  cantidad_propuesta,
  precio_costo_usd,
  precio_costo_cup
) VALUES (...);

-- DESPUÉS (AGREGAR CAMPOS)
INSERT INTO app_dat_consignacion_envio_producto (
  id_envio,
  id_producto,
  id_inventario,
  cantidad_propuesta,
  precio_costo_usd,
  precio_costo_cup,
  id_presentacion_original,      -- ⭐ NUEVO
  id_variante_original,           -- ⭐ NUEVO
  id_ubicacion_original,          -- ⭐ NUEVO
  id_inventario_original          -- ⭐ NUEVO
) VALUES (
  v_id_envio,
  v_id_producto,
  v_id_inventario,
  v_cantidad,
  v_precio_costo_usd,
  v_precio_costo_cup,
  v_id_presentacion,              -- ⭐ Obtener del producto original
  v_id_variante,                  -- ⭐ Obtener del producto original
  v_id_ubicacion,                 -- ⭐ Obtener del inventario original
  v_id_inventario                 -- ⭐ Guardar referencia al inventario original
);
```

**Obtener datos del producto original:**
```sql
-- Dentro del loop de productos
SELECT 
  ip.id_presentacion,
  ip.id_variante,
  ip.id_ubicacion,
  ip.id
INTO 
  v_id_presentacion,
  v_id_variante,
  v_id_ubicacion,
  v_id_inventario
FROM app_dat_inventario_productos ip
WHERE ip.id = (v_producto->>'id_inventario')::BIGINT;
```

---

### 2. Crear `crear_devolucion_consignacion()` (NUEVO RPC)

**Propósito:** Crear devolución manteniendo la trazabilidad del producto original

```sql
CREATE OR REPLACE FUNCTION crear_devolucion_consignacion(
  p_id_contrato BIGINT,
  p_id_almacen_origen BIGINT,  -- Almacén del consignatario
  p_id_usuario UUID,
  p_productos JSONB,
  p_descripcion TEXT DEFAULT NULL
) RETURNS TABLE (
  id_envio BIGINT,
  numero_envio VARCHAR,
  id_operacion_extraccion BIGINT
) AS $$
DECLARE
  v_id_envio BIGINT;
  v_numero_envio VARCHAR;
  v_id_operacion_extraccion BIGINT;
  v_producto JSONB;
  v_id_tienda_consignadora BIGINT;
  v_id_tienda_consignataria BIGINT;
  v_id_almacen_destino BIGINT;
BEGIN
  -- 1. Obtener tiendas del contrato
  SELECT id_tienda_consignadora, id_tienda_consignataria
  INTO v_id_tienda_consignadora, v_id_tienda_consignataria
  FROM app_dat_contrato_consignacion
  WHERE id = p_id_contrato;

  -- 2. Obtener almacén destino (primer almacén del consignador)
  SELECT id INTO v_id_almacen_destino
  FROM app_dat_almacen
  WHERE id_tienda = v_id_tienda_consignadora
  LIMIT 1;

  -- 3. Generar número de envío
  v_numero_envio := 'DEV-' || p_id_contrato || '-' || 
                    TO_CHAR(NOW(), 'YYYYMMDD-HH24MISS');

  -- 4. Crear envío de devolución (tipo_envio = 2)
  INSERT INTO app_dat_consignacion_envio (
    id_contrato_consignacion,
    numero_envio,
    tipo_envio,
    estado_envio,
    id_almacen_origen,
    id_almacen_destino,
    descripcion,
    fecha_propuesta
  ) VALUES (
    p_id_contrato,
    v_numero_envio,
    2,  -- ⭐ TIPO_ENVIO_DEVOLUCION
    1,  -- ESTADO_PROPUESTO
    p_id_almacen_origen,
    v_id_almacen_destino,
    COALESCE(p_descripcion, 'Devolución de productos en consignación'),
    NOW()
  ) RETURNING id INTO v_id_envio;

  -- 5. Crear operación de extracción (PENDIENTE)
  INSERT INTO app_dat_operaciones (
    id_tienda,
    id_tipo_operacion,
    observaciones
  ) VALUES (
    v_id_tienda_consignataria,
    7,  -- Tipo: Extracción de consignación
    'Extracción por devolución - ' || v_numero_envio
  ) RETURNING id INTO v_id_operacion_extraccion;

  -- 6. Insertar productos en el envío
  FOR v_producto IN SELECT * FROM jsonb_array_elements(p_productos)
  LOOP
    -- ⭐ CLAVE: Obtener información del producto ORIGINAL desde el envío inicial
    INSERT INTO app_dat_consignacion_envio_producto (
      id_envio,
      id_producto,
      id_inventario,
      cantidad_propuesta,
      precio_costo_usd,
      precio_costo_cup,
      id_presentacion_original,     -- ⭐ Del envío original
      id_variante_original,          -- ⭐ Del envío original
      id_ubicacion_original,         -- ⭐ Del envío original
      id_inventario_original         -- ⭐ Del envío original
    )
    SELECT
      v_id_envio,
      cep.id_producto,
      (v_producto->>'id_inventario')::BIGINT,
      (v_producto->>'cantidad')::NUMERIC,
      cep.precio_costo_usd,
      cep.precio_costo_cup,
      cep.id_presentacion_original,  -- ⭐ COPIAR del envío original
      cep.id_variante_original,      -- ⭐ COPIAR del envío original
      cep.id_ubicacion_original,     -- ⭐ COPIAR del envío original
      cep.id_inventario_original     -- ⭐ COPIAR del envío original
    FROM app_dat_consignacion_envio_producto cep
    INNER JOIN app_dat_consignacion_envio ce ON ce.id = cep.id_envio
    WHERE ce.id_contrato_consignacion = p_id_contrato
      AND ce.tipo_envio = 1  -- Solo del envío original
      AND cep.id_producto = (v_producto->>'id_producto')::BIGINT
    LIMIT 1;
  END LOOP;

  -- 7. Registrar movimiento
  INSERT INTO app_dat_consignacion_envio_movimiento (
    id_envio,
    tipo_movimiento,
    id_usuario,
    descripcion
  ) VALUES (
    v_id_envio,
    1,  -- MOVIMIENTO_CREACION
    p_id_usuario,
    'Devolución creada'
  );

  RETURN QUERY SELECT v_id_envio, v_numero_envio, v_id_operacion_extraccion;
END;
$$ LANGUAGE plpgsql;
```

---

### 3. Crear `aprobar_devolucion_consignacion()` (NUEVO RPC)

**Propósito:** Aprobar devolución y crear operación de recepción en almacén original

**⚠️ IMPORTANTE:** Esta operación de recepción **NO debe actualizar el precio promedio** del producto

```sql
CREATE OR REPLACE FUNCTION aprobar_devolucion_consignacion(
  p_id_envio BIGINT,
  p_id_almacen_recepcion BIGINT,
  p_id_usuario UUID
) RETURNS TABLE (
  success BOOLEAN,
  id_operacion_recepcion BIGINT,
  mensaje TEXT
) AS $$
DECLARE
  v_id_operacion_recepcion BIGINT;
  v_id_tienda_consignadora BIGINT;
  v_numero_envio VARCHAR;
  v_producto RECORD;
BEGIN
  -- 1. Validar que el envío es de tipo devolución
  IF NOT EXISTS (
    SELECT 1 FROM app_dat_consignacion_envio
    WHERE id = p_id_envio AND tipo_envio = 2
  ) THEN
    RETURN QUERY SELECT FALSE, NULL::BIGINT, 'El envío no es una devolución';
    RETURN;
  END IF;

  -- 2. Obtener información del envío
  SELECT ce.numero_envio, cc.id_tienda_consignadora
  INTO v_numero_envio, v_id_tienda_consignadora
  FROM app_dat_consignacion_envio ce
  INNER JOIN app_dat_contrato_consignacion cc ON cc.id = ce.id_contrato_consignacion
  WHERE ce.id = p_id_envio;

  -- 3. Crear operación de recepción en tienda consignadora
  INSERT INTO app_dat_operaciones (
    id_tienda,
    id_tipo_operacion,
    observaciones
  ) VALUES (
    v_id_tienda_consignadora,
    1,  -- Tipo: Recepción
    'Recepción de devolución - ' || v_numero_envio
  ) RETURNING id INTO v_id_operacion_recepcion;

  -- 4. Crear operación de extracción en tienda consignataria
  -- (Se completa cuando el consignatario confirme la extracción)

  -- 5. Para cada producto, restaurar al inventario ORIGINAL
  FOR v_producto IN 
    SELECT 
      cep.id_producto,
      cep.cantidad_propuesta,
      cep.id_presentacion_original,
      cep.id_variante_original,
      cep.id_ubicacion_original,
      cep.id_inventario_original,
      cep.precio_costo_usd
    FROM app_dat_consignacion_envio_producto cep
    WHERE cep.id_envio = p_id_envio
  LOOP
    -- ⭐ CLAVE: Restaurar al inventario ORIGINAL con presentación ORIGINAL
    INSERT INTO app_dat_recepcion_productos (
      id_operacion,
      id_producto,
      id_presentacion,           -- ⭐ Presentación ORIGINAL
      id_variante,               -- ⭐ Variante ORIGINAL
      id_ubicacion,              -- ⭐ Ubicación ORIGINAL
      cantidad,
      precio_unitario
    ) VALUES (
      v_id_operacion_recepcion,
      v_producto.id_producto,
      v_producto.id_presentacion_original,  -- ⭐ USAR ORIGINAL
      v_producto.id_variante_original,      -- ⭐ USAR ORIGINAL
      v_producto.id_ubicacion_original,     -- ⭐ USAR ORIGINAL
      v_producto.cantidad_propuesta,
      v_producto.precio_costo_usd
    );

    -- Actualizar inventario en la ubicación ORIGINAL
    UPDATE app_dat_inventario_productos
    SET cantidad_final = cantidad_final + v_producto.cantidad_propuesta
    WHERE id_producto = v_producto.id_producto
      AND id_presentacion = v_producto.id_presentacion_original
      AND id_ubicacion = v_producto.id_ubicacion_original
      AND COALESCE(id_variante, 0) = COALESCE(v_producto.id_variante_original, 0);
  END LOOP;

  -- 6. Actualizar estado del envío
  UPDATE app_dat_consignacion_envio
  SET estado_envio = 4,  -- ESTADO_ACEPTADO
      fecha_aceptacion = NOW()
  WHERE id = p_id_envio;

  -- 7. Completar operación de recepción
  INSERT INTO app_dat_estado_operacion (id_operacion, estado, comentario)
  VALUES (v_id_operacion_recepcion, 2, 'Devolución recibida');

  -- 8. Registrar movimiento
  INSERT INTO app_dat_consignacion_envio_movimiento (
    id_envio,
    tipo_movimiento,
    id_usuario,
    descripcion
  ) VALUES (
    p_id_envio,
    4,  -- MOVIMIENTO_ACEPTACION
    p_id_usuario,
    'Devolución aprobada y recibida'
  );

  RETURN QUERY SELECT TRUE, v_id_operacion_recepcion, 'Devolución aprobada exitosamente';
END;
$$ LANGUAGE plpgsql;
```

---

## 🔄 Cambios en Servicios Dart

### 1. Modificar `ConsignacionEnvioService.crearEnvio()`

**Archivo:** `lib/services/consignacion_envio_service.dart`

```dart
// ANTES (línea ~64-78)
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

// DESPUÉS (AGREGAR CAMPOS ORIGINALES)
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
    'id_presentacion': p['id_presentacion'],      // ⭐ NUEVO
    'id_variante': p['id_variante'],              // ⭐ NUEVO
    'id_ubicacion': p['id_ubicacion'],            // ⭐ NUEVO
  };
}).toList();
```

---

### 2. Modificar `ConsignacionEnvioService.crearDevolucion()`

**Archivo:** `lib/services/consignacion_envio_service.dart`

```dart
// ANTES (línea ~141-148)
final productosJson = productos.map((p) => {
  'id_inventario': p['id_inventario'],
  'id_producto': p['id_producto'],
  'cantidad': p['cantidad'],
  'precio_costo_usd': p['precio_costo_usd'] ?? 0.0,
  'precio_costo_cup': p['precio_costo_cup'] ?? 0.0,
  'tasa_cambio': p['tasa_cambio'] ?? 440.0,
}).toList();

// DESPUÉS (AGREGAR REFERENCIA AL ENVÍO ORIGINAL)
final productosJson = productos.map((p) => {
  'id_inventario': p['id_inventario'],
  'id_producto': p['id_producto'],
  'cantidad': p['cantidad'],
  'precio_costo_usd': p['precio_costo_usd'] ?? 0.0,
  'precio_costo_cup': p['precio_costo_cup'] ?? 0.0,
  'tasa_cambio': p['tasa_cambio'] ?? 440.0,
  // ⭐ El RPC obtendrá automáticamente los datos originales
  // desde el envío inicial usando el id_producto
}).toList();
```

---

## 🎨 Cambios en Pantallas Flutter

### 1. Modificar `AsignarProductosConsignacionScreen`

**Archivo:** `lib/screens/asignar_productos_consignacion_screen.dart`

**Cambio en `_procederConConfiguracion()` (línea ~147-166):**

```dart
// AGREGAR campos de presentación y variante al obtener productos
final response = await _supabase
    .from('app_dat_inventario_productos')
    .select('''
      id,
      cantidad_final,
      id_producto,
      id_ubicacion,
      id_presentacion,      // ⭐ YA EXISTE
      id_variante,          // ⭐ YA EXISTE
      id_opcion_variante,
      app_dat_producto(
        id,
        denominacion,
        sku
      ),
      app_dat_producto_presentacion(
        precio_promedio
      )
    ''')
    .inFilter('id', productosIds);

// Los datos ya se están pasando correctamente en línea 227-236
// Solo asegurar que se incluyen en el mapa:
final productosParaEnvio = productosData.map((p) => {
  'id_inventario': p['id'],
  'id_producto': p['id_producto'],
  'cantidad': p['cantidad_seleccionada'],
  'id_presentacion': p['id_presentacion'],     // ⭐ YA EXISTE
  'id_variante': p['id_variante'],             // ⭐ YA EXISTE
  'id_ubicacion': p['id_ubicacion'],           // ⭐ YA EXISTE
  'precio_venta': finalPrecio,
  'tasa_cambio': tasaCambio,
}).toList();
```

---

### 2. Modificar `_procederConCreacionDevolucion()`

**Archivo:** `lib/screens/asignar_productos_consignacion_screen.dart` (línea ~287-325)

```dart
Future<void> _procederConCreacionDevolucion(List<Map<String, dynamic>> productos) async {
  try {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Usuario no autenticado');

    final idTiendaConsignataria = widget.contrato['id_tienda_consignataria'] as int;
    final almacenes = await _supabase
        .from('app_dat_almacen')
        .select('id')
        .eq('id_tienda', idTiendaConsignataria)
        .limit(1);
    final idAlmacenOrigen = (almacenes as List).isNotEmpty 
        ? almacenes[0]['id'] as int 
        : 0;

    // ⭐ IMPORTANTE: Los productos ya tienen la información necesaria
    // El RPC obtendrá los datos originales automáticamente
    final productosParaDevolucion = productos.map((p) => {
      'id_inventario': p['id'] as int,
      'id_producto': p['id_producto'],
      'cantidad': p['cantidad_seleccionada'],
      'precio_costo_usd': p['precio_costo_usd'],
      'precio_costo_cup': p['precio_costo_cup'],
      'tasa_cambio': p['tasa_cambio'],
      // ⭐ NO es necesario pasar los datos originales aquí
      // El RPC los obtendrá del envío inicial
    }).toList();

    final result = await ConsignacionEnvioService.crearDevolucion(
      idContrato: widget.idContrato,
      idAlmacenOrigen: idAlmacenOrigen,
      idUsuario: user.id,
      productos: productosParaDevolucion,
      descripcion: 'Devolución de productos - ${widget.contrato['tienda_consignataria']['denominacion']}',
    );

    setState(() => _procediendo = false);
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Devolución solicitada: ${result['numero_envio']}'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    }
  } catch (e) {
    debugPrint('Error creando devolución: $e');
    setState(() => _procediendo = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }
}
```

---

## 📊 Flujo Completo de Devolución

### Flujo Correcto (CON cambios propuestos)

```
1. CONSIGNATARIO crea devolución
   ├─ Selecciona productos a devolver
   ├─ Sistema crea envío tipo DEVOLUCION (tipo_envio = 2)
   ├─ Sistema copia datos ORIGINALES del envío inicial:
   │  ├─ id_presentacion_original
   │  ├─ id_variante_original
   │  ├─ id_ubicacion_original
   │  └─ id_inventario_original
   └─ Crea operación de EXTRACCIÓN (PENDIENTE) en tienda consignataria

2. CONSIGNADOR revisa devolución
   ├─ Ve productos con información ORIGINAL
   ├─ Selecciona almacén de recepción
   └─ Aprueba devolución

3. Sistema ejecuta `aprobar_devolucion_consignacion()`
   ├─ Crea operación de RECEPCIÓN en tienda consignadora
   ├─ Para cada producto:
   │  ├─ Usa id_presentacion_original (NO crea nueva)
   │  ├─ Usa id_variante_original (NO crea nueva)
   │  ├─ Usa id_ubicacion_original (zona original)
   │  └─ Restaura inventario en ubicación ORIGINAL
   ├─ Completa operación de RECEPCIÓN (estado = 2)
   └─ Actualiza estado del envío a ACEPTADO

4. Resultado
   ✅ Producto regresa a su presentación ORIGINAL
   ✅ Producto regresa a su ubicación ORIGINAL
   ✅ Inventario se actualiza correctamente
   ✅ Trazabilidad completa mantenida
```

---

## ✅ Resumen de Cambios

### Base de Datos
1. ✅ Agregar 4 columnas a `app_dat_consignacion_envio_producto`
2. ✅ Crear índices para optimizar consultas
3. ✅ Modificar RPC `crear_envio_consignacion()` para guardar datos originales
4. ✅ Crear RPC `crear_devolucion_consignacion()` para copiar datos originales
5. ✅ Crear RPC `aprobar_devolucion_consignacion()` para restaurar inventario original

### Servicios Dart
1. ✅ Modificar `ConsignacionEnvioService.crearEnvio()` para enviar datos originales
2. ✅ Mantener `ConsignacionEnvioService.crearDevolucion()` (el RPC hace el trabajo)
3. ✅ Mantener `ConsignacionEnvioService.aprobarDevolucion()` (ya existe)

### Pantallas Flutter
1. ✅ Modificar `AsignarProductosConsignacionScreen._procederConConfiguracion()`
2. ✅ Mantener `_procederConCreacionDevolucion()` (el RPC hace el trabajo)
3. ✅ No requiere cambios en `ConfirmarRecepcionConsignacionScreen`
4. ✅ No requiere cambios en `ConsignacionEnvioDetallesScreen`

---

## 🎯 Beneficios de la Solución

✅ **Trazabilidad completa:** Se mantiene la referencia al producto original
✅ **Presentación correcta:** El producto regresa con su presentación original
✅ **Ubicación correcta:** El producto regresa a su zona original
✅ **Inventario correcto:** Se actualiza el inventario original, no se crea uno nuevo
✅ **Operaciones correctas:** Se crean operaciones de extracción/recepción como en envíos
✅ **Auditoría completa:** Se registran todos los movimientos
✅ **Compatibilidad:** No rompe funcionalidad existente de envíos normales
✅ **Precio promedio protegido:** Las devoluciones NO actualizan el precio promedio del producto

---

## 📝 Orden de Implementación

1. **Ejecutar cambios en BD** (archivo SQL adjunto)
2. **Modificar RPC `crear_envio_consignacion()`**
3. **Crear RPC `crear_devolucion_consignacion()`**
4. **Crear RPC `aprobar_devolucion_consignacion()`**
5. **Modificar servicio Dart `ConsignacionEnvioService`**
6. **Modificar pantalla `AsignarProductosConsignacionScreen`**
7. **Probar flujo completo:**
   - Crear envío → Aceptar → Crear devolución → Aprobar devolución
   - Verificar que producto regresa a ubicación y presentación original

---

**Fecha:** 7 de Enero, 2026
**Estado:** 📋 PROPUESTA LISTA PARA IMPLEMENTACIÓN
