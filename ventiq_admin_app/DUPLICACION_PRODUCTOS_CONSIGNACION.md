# 🔄 Duplicación de Productos para Consignación

## 📊 Análisis de Estructura de Productos

### Tablas Relacionadas a Productos

```
app_dat_producto (PRINCIPAL)
├── id_tienda (FK) → app_dat_tienda
├── id_categoria (FK) → app_dat_categoria
│
├─ app_dat_productos_subcategorias
│  └── id_sub_categoria (FK) → app_dat_subcategorias
│
├─ app_dat_producto_presentacion
│  └── id_presentacion (FK) → app_nom_presentacion
│
├─ app_dat_producto_multimedias
│  └── media (URL/ruta)
│
├─ app_dat_producto_etiquetas
│  └── etiqueta (texto)
│
├─ app_dat_producto_unidades
│  └── id_unidad_medida (FK) → app_nom_unidades_medida
│
├─ app_dat_producto_ingredientes (si es elaborado)
│  └── id_ingrediente (FK) → app_dat_producto
│
└─ app_dat_producto_garantia
   └── id_tipo_garantia (FK) → app_nom_tipo_garantia
```

### Campos Principales de app_dat_producto

```
IDENTIFICACIÓN:
- id (PK)
- id_tienda (FK) ← CAMBIAR A TIENDA DESTINO
- sku
- codigo_barras

CATEGORIZACIÓN:
- id_categoria (FK) ← DUPLICAR CATEGORÍA
- (subcategorías en tabla separada)

DESCRIPCIÓN:
- denominacion
- nombre_comercial
- denominacion_corta
- descripcion
- descripcion_corta

PROPIEDADES:
- um (unidad de medida)
- es_refrigerado
- es_fragil
- es_peligroso
- es_vendible
- es_comprable
- es_inventariable
- es_por_lotes
- es_servicio
- es_elaborado
- dias_alert_caducidad

MULTIMEDIA:
- imagen

AUDITORÍA:
- created_at
- deleted_at (soft delete)
```

## 🎯 Estrategia de Duplicación

### Opción A: Duplicación Completa (RECOMENDADA)
```
Producto Original (Tienda A)
    ↓
    Duplicar TODO
    ↓
Producto Nuevo (Tienda B)
├─ Mismo nombre, SKU, descripción
├─ Misma categoría (o crear equivalente)
├─ Mismas subcategorías
├─ Mismas presentaciones
├─ Mismas multimedias
├─ Mismas etiquetas
├─ Mismas propiedades (refrigerado, frágil, etc.)
└─ Misma garantía
```

### Opción B: Duplicación Simplificada
```
Producto Original (Tienda A)
    ↓
    Duplicar SOLO lo esencial
    ↓
Producto Nuevo (Tienda B)
├─ Nombre, SKU, descripción
├─ Categoría (o crear equivalente)
├─ Presentación base
└─ Imagen
```

**Recomendación:** Usar Opción A (Completa) para máxima compatibilidad

## 🔄 Proceso de Duplicación

### Paso 1: Duplicar Categoría (si no existe)
```
1. Obtener categoría del producto original
2. Verificar si existe en tienda destino
   ├─ SI: Usar existente
   └─ NO: Crear nueva con mismo nombre
3. Obtener/crear subcategorías
```

### Paso 2: Duplicar Producto Base
```
1. Copiar todos los campos de app_dat_producto
2. Cambiar:
   - id_tienda → tienda destino
   - id_categoria → categoría destino
3. Insertar nuevo producto
4. Obtener nuevo ID
```

### Paso 3: Duplicar Relaciones
```
Para cada tabla relacionada:
├─ app_dat_productos_subcategorias
├─ app_dat_producto_presentacion
├─ app_dat_producto_multimedias
├─ app_dat_producto_etiquetas
├─ app_dat_producto_unidades
├─ app_dat_producto_ingredientes (si aplica)
└─ app_dat_producto_garantia (si aplica)

Copiar registros con nuevo ID de producto
```

### Paso 4: Crear Registro de Trazabilidad
```
Crear tabla: app_dat_producto_consignacion_duplicado
├─ id_producto_original (tienda origen)
├─ id_producto_duplicado (tienda destino)
├─ id_contrato_consignacion
├─ id_tienda_origen
├─ id_tienda_destino
├─ fecha_duplicacion
└─ duplicado_por (usuario)
```

## 📋 Tablas a Crear en Supabase

### 1. Tabla de Trazabilidad
```sql
CREATE TABLE app_dat_producto_consignacion_duplicado (
  id SERIAL PRIMARY KEY,
  id_producto_original BIGINT NOT NULL,
  id_producto_duplicado BIGINT NOT NULL,
  id_contrato_consignacion INT NOT NULL,
  id_tienda_origen INT NOT NULL,
  id_tienda_destino INT NOT NULL,
  fecha_duplicacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  duplicado_por UUID,
  
  FOREIGN KEY (id_producto_original) REFERENCES app_dat_producto(id),
  FOREIGN KEY (id_producto_duplicado) REFERENCES app_dat_producto(id),
  FOREIGN KEY (id_contrato_consignacion) REFERENCES app_dat_contrato_consignacion(id),
  FOREIGN KEY (id_tienda_origen) REFERENCES app_dat_tienda(id),
  FOREIGN KEY (id_tienda_destino) REFERENCES app_dat_tienda(id),
  
  UNIQUE(id_producto_original, id_tienda_destino)
);

CREATE INDEX idx_producto_consignacion_duplicado_original 
ON app_dat_producto_consignacion_duplicado(id_producto_original);

CREATE INDEX idx_producto_consignacion_duplicado_nuevo 
ON app_dat_producto_consignacion_duplicado(id_producto_duplicado);

CREATE INDEX idx_producto_consignacion_duplicado_contrato 
ON app_dat_producto_consignacion_duplicado(id_contrato_consignacion);
```

### 2. Función RPC para Duplicar Producto
```sql
CREATE OR REPLACE FUNCTION duplicar_producto_consignacion(
  p_id_producto_original BIGINT,
  p_id_tienda_destino BIGINT,
  p_id_contrato_consignacion INT,
  p_id_tienda_origen BIGINT,
  p_uuid_usuario UUID
)
RETURNS TABLE (
  success BOOLEAN,
  id_producto_nuevo BIGINT,
  message VARCHAR
) AS $$
DECLARE
  v_id_categoria_destino BIGINT;
  v_id_producto_nuevo BIGINT;
  v_categoria_origen BIGINT;
  v_categoria_nombre VARCHAR;
BEGIN
  -- 1. Obtener categoría original
  SELECT id_categoria INTO v_categoria_origen
  FROM app_dat_producto
  WHERE id = p_id_producto_original;
  
  -- 2. Obtener nombre de categoría
  SELECT denominacion INTO v_categoria_nombre
  FROM app_dat_categoria
  WHERE id = v_categoria_origen;
  
  -- 1. Verificar si ya existe en tienda destino (buscar por SKU)
  -- IMPORTANTE: Buscar SOLO por SKU, no por ID (el ID es diferente en cada tienda)
  SELECT id INTO v_id_producto_existente
  FROM app_dat_producto
  WHERE id_tienda = p_id_tienda_destino
    AND sku = (SELECT sku FROM app_dat_producto WHERE id = p_id_producto_original)
  LIMIT 1;
  
  -- 4. Si no existe, crear categoría en tienda destino
  IF v_id_categoria_destino IS NULL THEN
    INSERT INTO app_dat_categoria_tienda (id_tienda, id_categoria)
    VALUES (p_id_tienda_destino, v_categoria_origen);
    v_id_categoria_destino := v_categoria_origen;
  END IF;
  
  -- 5. Duplicar producto
  INSERT INTO app_dat_producto (
    id_tienda, sku, id_categoria, denominacion, nombre_comercial,
    denominacion_corta, descripcion, descripcion_corta, um,
    es_refrigerado, es_fragil, es_peligroso, es_vendible, es_comprable,
    es_inventariable, es_por_lotes, dias_alert_caducidad, codigo_barras,
    imagen, es_elaborado, es_servicio
  )
  SELECT
    p_id_tienda_destino, sku, v_id_categoria_destino, denominacion, nombre_comercial,
    denominacion_corta, descripcion, descripcion_corta, um,
    es_refrigerado, es_fragil, es_peligroso, es_vendible, es_comprable,
    es_inventariable, es_por_lotes, dias_alert_caducidad, codigo_barras,
    imagen, es_elaborado, es_servicio
  FROM app_dat_producto
  WHERE id = p_id_producto_original
  RETURNING id INTO v_id_producto_nuevo;
  
  -- 6. Duplicar subcategorías
  INSERT INTO app_dat_productos_subcategorias (id_producto, id_sub_categoria)
  SELECT v_id_producto_nuevo, id_sub_categoria
  FROM app_dat_productos_subcategorias
  WHERE id_producto = p_id_producto_original;
  
  -- 7. Duplicar presentaciones
  INSERT INTO app_dat_producto_presentacion (id_producto, id_presentacion, cantidad, es_base, precio_promedio)
  SELECT v_id_producto_nuevo, id_presentacion, cantidad, es_base, precio_promedio
  FROM app_dat_producto_presentacion
  WHERE id_producto = p_id_producto_original;
  
  -- 8. Duplicar multimedias
  INSERT INTO app_dat_producto_multimedias (id_producto, media)
  SELECT v_id_producto_nuevo, media
  FROM app_dat_producto_multimedias
  WHERE id_producto = p_id_producto_original;
  
  -- 9. Duplicar etiquetas
  INSERT INTO app_dat_producto_etiquetas (id_producto, etiqueta)
  SELECT v_id_producto_nuevo, etiqueta
  FROM app_dat_producto_etiquetas
  WHERE id_producto = p_id_producto_original;
  
  -- 10. Duplicar unidades
  INSERT INTO app_dat_producto_unidades (id_producto, id_unidad_medida, factor_producto, es_unidad_compra, es_unidad_venta, es_unidad_inventario, observaciones)
  SELECT v_id_producto_nuevo, id_unidad_medida, factor_producto, es_unidad_compra, es_unidad_venta, es_unidad_inventario, observaciones
  FROM app_dat_producto_unidades
  WHERE id_producto = p_id_producto_original;
  
  -- 11. Duplicar garantía (si existe)
  INSERT INTO app_dat_producto_garantia (id_producto, id_tipo_garantia, condiciones_especificas, es_activo)
  SELECT v_id_producto_nuevo, id_tipo_garantia, condiciones_especificas, es_activo
  FROM app_dat_producto_garantia
  WHERE id_producto = p_id_producto_original
  ON CONFLICT DO NOTHING;
  
  -- 12. Registrar trazabilidad
  INSERT INTO app_dat_producto_consignacion_duplicado (
    id_producto_original, id_producto_duplicado, id_contrato_consignacion,
    id_tienda_origen, id_tienda_destino, duplicado_por
  ) VALUES (
    p_id_producto_original, v_id_producto_nuevo, p_id_contrato_consignacion,
    p_id_tienda_origen, p_id_tienda_destino, p_uuid_usuario
  );
  
  RETURN QUERY SELECT true::BOOLEAN, v_id_producto_nuevo::BIGINT, 'Producto duplicado exitosamente'::VARCHAR;
  
EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT false::BOOLEAN, NULL::BIGINT, ('Error: ' || SQLERRM)::VARCHAR;
END;
$$ LANGUAGE plpgsql;
```

## 🎨 Servicio Dart: `ConsignacionDuplicacionService`

```dart
class ConsignacionDuplicacionService {
  static final _supabase = Supabase.instance.client;

  /// Duplicar producto de consignación en tienda destino
  static Future<int?> duplicarProductoConsignacion({
    required int idProductoOriginal,
    required int idTiendaDestino,
    required int idContratoConsignacion,
    required int idTiendaOrigen,
  }) async {
    try {
      final userPrefs = UserPreferencesService();
      final userId = await userPrefs.getUserId();
      
      debugPrint('🔄 Duplicando producto $idProductoOriginal en tienda $idTiendaDestino');

      final response = await _supabase.rpc(
        'duplicar_producto_consignacion',
        params: {
          'p_id_producto_original': idProductoOriginal,
          'p_id_tienda_destino': idTiendaDestino,
          'p_id_contrato_consignacion': idContratoConsignacion,
          'p_id_tienda_origen': idTiendaOrigen,
          'p_uuid_usuario': userId,
        },
      ) as List;

      if (response.isNotEmpty) {
        final result = response.first as Map<String, dynamic>;
        if (result['success'] == true) {
          final idProductoNuevo = result['id_producto_nuevo'] as int;
          debugPrint('✅ Producto duplicado: $idProductoNuevo');
          return idProductoNuevo;
        }
      }

      debugPrint('❌ Error duplicando producto');
      return null;
    } catch (e) {
      debugPrint('❌ Error: $e');
      return null;
    }
  }

  /// Duplicar múltiples productos de un contrato
  static Future<List<int>> duplicarProductosContrato({
    required int idContrato,
    required int idTiendaDestino,
    required int idTiendaOrigen,
  }) async {
    try {
      debugPrint('🔄 Duplicando productos del contrato $idContrato');

      // Obtener productos del contrato
      final productos = await _supabase
          .from('app_dat_producto_consignacion')
          .select('id_producto')
          .eq('id_contrato', idContrato)
          .eq('estado', 1);

      final productosNuevos = <int>[];

      for (final item in productos) {
        final idProducto = item['id_producto'] as int;
        final idNuevo = await duplicarProductoConsignacion(
          idProductoOriginal: idProducto,
          idTiendaDestino: idTiendaDestino,
          idContratoConsignacion: idContrato,
          idTiendaOrigen: idTiendaOrigen,
        );

        if (idNuevo != null) {
          productosNuevos.add(idNuevo);
        }
      }

      debugPrint('✅ ${productosNuevos.length} productos duplicados');
      return productosNuevos;
    } catch (e) {
      debugPrint('❌ Error: $e');
      return [];
    }
  }

  /// Obtener registro de duplicación
  static Future<Map<String, dynamic>?> obtenerDuplicacion({
    required int idProductoOriginal,
    required int idTiendaDestino,
  }) async {
    try {
      final response = await _supabase
          .from('app_dat_producto_consignacion_duplicado')
          .select('*')
          .eq('id_producto_original', idProductoOriginal)
          .eq('id_tienda_destino', idTiendaDestino)
          .limit(1);

      if (response.isNotEmpty) {
        return response.first as Map<String, dynamic>;
      }

      return null;
    } catch (e) {
      debugPrint('❌ Error: $e');
      return null;
    }
  }
}
```

## 🔄 Integración en ConsignacionService

### Modificar `confirmarContrato()`

```dart
static Future<bool> confirmarContrato(int idContrato) async {
  try {
    final contrato = await getContratoById(idContrato);
    if (contrato == null) return false;

    // 1. Actualizar estado de confirmación
    await _supabase
        .from('app_dat_contrato_consignacion')
        .update({'estado_confirmacion': 1, 'fecha_confirmacion': DateTime.now()})
        .eq('id', idContrato);

    // 2. NUEVO: Duplicar productos en tienda destino
    final idTiendaDestino = contrato['id_tienda_consignataria'] as int;
    final idTiendaOrigen = contrato['id_tienda_consignadora'] as int;

    await ConsignacionDuplicacionService.duplicarProductosContrato(
      idContrato: idContrato,
      idTiendaDestino: idTiendaDestino,
      idTiendaOrigen: idTiendaOrigen,
    );

    debugPrint('✅ Contrato confirmado y productos duplicados');
    return true;
  } catch (e) {
    debugPrint('❌ Error: $e');
    return false;
  }
}
```

## 📊 Flujo Completo

```
1. CONSIGNADORA crea contrato
   ├─ Asigna productos
   └─ Contrato en estado PENDIENTE

2. CONSIGNATARIA confirma contrato
   ├─ Contrato pasa a CONFIRMADO
   └─ SE DISPARA DUPLICACIÓN:
      ├─ Para cada producto:
      │  ├─ Obtener datos completos
      │  ├─ Crear/verificar categoría en tienda destino
      │  ├─ Duplicar producto base
      │  ├─ Duplicar subcategorías
      │  ├─ Duplicar presentaciones
      │  ├─ Duplicar multimedias
      │  ├─ Duplicar etiquetas
      │  ├─ Duplicar unidades
      │  ├─ Duplicar garantía
      │  └─ Registrar trazabilidad
      └─ Todos los productos listos para vender

3. VENDER productos
   ├─ Aparecen en categoría de tienda destino
   ├─ Se venden como productos normales
   └─ Se registra venta en app_dat_producto_consignacion
```

## ✅ Ventajas de Duplicación

- ✅ **Simplicidad**: Productos independientes
- ✅ **Venta inmediata**: Sin mapeos ni configuraciones
- ✅ **Rendimiento**: Consultas directas sin joins
- ✅ **Independencia**: Cada tienda maneja su copia
- ✅ **Flexibilidad**: Modificar precios/detalles localmente
- ✅ **Trazabilidad**: Registro de qué se duplicó
- ✅ **Escalabilidad**: Funciona con múltiples tiendas

## ⚠️ Consideraciones

- **Datos duplicados**: Ocupan más espacio en BD (aceptable)
- **Sincronización**: Si cambia el original, no se actualiza la copia (por diseño)
- **Precios**: Pueden ser diferentes en cada tienda
- **Stock**: Independiente en cada tienda

## 🎯 Estrategia Optimizada: Duplicación Bajo Demanda

### Concepto
```
NO duplicar todos los productos automáticamente
SOLO duplicar cuando se asignan productos que no existen en tienda destino
```

### Flujo Optimizado

```
1. CONSIGNADORA asigna productos a contrato
   ├─ Producto A existe en tienda destino ✅
   ├─ Producto B NO existe en tienda destino ❌
   └─ Producto C existe en tienda destino ✅

2. CONSIGNATARIA confirma contrato
   ├─ Verificar cada producto
   ├─ Producto A: Ya existe → NO duplicar
   ├─ Producto B: No existe → DUPLICAR
   └─ Producto C: Ya existe → NO duplicar

3. Resultado
   ├─ 1 producto duplicado (solo el necesario)
   ├─ 2 productos reutilizados (sin duplicación)
   └─ Cero duplicados innecesarios
```

### Ventajas de Duplicación Bajo Demanda

- ✅ **Eficiencia**: Solo duplica lo necesario
- ✅ **Menos datos**: Evita duplicados innecesarios
- ✅ **Reutilización**: Aprovecha productos existentes
- ✅ **Espacio en BD**: Optimizado
- ✅ **Rendimiento**: Menos inserciones
- ✅ **Lógica clara**: Duplica solo si no existe

### Función RPC Modificada

```sql
-- Verificar si producto existe en tienda destino
CREATE OR REPLACE FUNCTION producto_existe_en_tienda(
  p_id_producto BIGINT,
  p_id_tienda BIGINT
)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM app_dat_producto
    WHERE id = p_id_producto AND id_tienda = p_id_tienda
  );
END;
$$ LANGUAGE plpgsql;

-- Duplicar SOLO si no existe
CREATE OR REPLACE FUNCTION duplicar_producto_si_necesario(
  p_id_producto_original BIGINT,
  p_id_tienda_destino BIGINT,
  p_id_contrato_consignacion INT,
  p_id_tienda_origen BIGINT,
  p_uuid_usuario UUID DEFAULT NULL
)
RETURNS TABLE (
  success BOOLEAN,
  id_producto_resultado BIGINT,
  fue_duplicado BOOLEAN,
  message VARCHAR
) AS $$
DECLARE
  v_id_producto_nuevo BIGINT;
  v_fue_duplicado BOOLEAN := false;
  v_id_producto_existente BIGINT;
BEGIN
  -- 1. Verificar si ya existe en tienda destino (buscar por SKU)
  SELECT id INTO v_id_producto_existente
  FROM app_dat_producto
  WHERE id_tienda = p_id_tienda_destino
    AND sku = (SELECT sku FROM app_dat_producto WHERE id = p_id_producto_original)
  LIMIT 1;
  
  IF v_id_producto_existente IS NOT NULL THEN
    RETURN QUERY SELECT 
      true::BOOLEAN, 
      v_id_producto_existente::BIGINT,  -- Retornar el ID del producto existente, NO el original
      false::BOOLEAN,
      'Producto ya existe en tienda destino'::VARCHAR;
    RETURN;
  END IF;
  
  -- 2. Si no existe, duplicar
  v_fue_duplicado := true;
  
  -- [Resto del código de duplicación...]
  
  RETURN QUERY SELECT 
    true::BOOLEAN, 
    v_id_producto_nuevo::BIGINT, 
    v_fue_duplicado::BOOLEAN,
    'Producto duplicado exitosamente'::VARCHAR;
  
EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT false::BOOLEAN, NULL::BIGINT, false::BOOLEAN, ('Error: ' || SQLERRM)::VARCHAR;
END;
$$ LANGUAGE plpgsql;
```

### Servicio Dart Modificado

```dart
/// Duplicar producto SOLO si no existe en tienda destino
static Future<int?> duplicarProductoSiNecesario({
  required int idProductoOriginal,
  required int idTiendaDestino,
  required int idContratoConsignacion,
  required int idTiendaOrigen,
}) async {
  try {
    // 1. Verificar si ya existe
    final existe = await _productoExisteEnTienda(
      idProductoOriginal,
      idTiendaDestino,
    );

    if (existe) {
      debugPrint('✅ Producto ya existe en tienda destino');
      return idProductoOriginal; // Retornar el mismo ID
    }

    // 2. Si no existe, duplicar
    debugPrint('🔄 Producto no existe, duplicando...');
    
    final userPrefs = UserPreferencesService();
    final userId = await userPrefs.getUserId();

    final response = await _supabase.rpc(
      'duplicar_producto_si_necesario',
      params: {
        'p_id_producto_original': idProductoOriginal,
        'p_id_tienda_destino': idTiendaDestino,
        'p_id_contrato_consignacion': idContratoConsignacion,
        'p_id_tienda_origen': idTiendaOrigen,
        'p_uuid_usuario': userId,
      },
    ) as List;

    if (response.isNotEmpty) {
      final result = response.first as Map<String, dynamic>;
      if (result['success'] == true) {
        final idProducto = result['id_producto_resultado'] as int;
        final fueDuplicado = result['fue_duplicado'] as bool;
        
        if (fueDuplicado) {
          debugPrint('✅ Producto duplicado: $idProducto');
        } else {
          debugPrint('✅ Producto reutilizado: $idProducto');
        }
        
        return idProducto;
      }
    }

    return null;
  } catch (e) {
    debugPrint('❌ Error: $e');
    return null;
  }
}

/// Verificar si producto existe en tienda
static Future<bool> _productoExisteEnTienda(
  int idProducto,
  int idTienda,
) async {
  try {
    final response = await _supabase
        .from('app_dat_producto')
        .select('id')
        .eq('id', idProducto)
        .eq('id_tienda', idTienda)
        .limit(1);

    return response.isNotEmpty;
  } catch (e) {
    debugPrint('❌ Error verificando producto: $e');
    return false;
  }
}
```

### Integración en ConsignacionService

```dart
static Future<bool> confirmarContrato(int idContrato) async {
  try {
    final contrato = await getContratoById(idContrato);
    if (contrato == null) return false;

    // 1. Actualizar estado de confirmación
    await _supabase
        .from('app_dat_contrato_consignacion')
        .update({'estado_confirmacion': 1, 'fecha_confirmacion': DateTime.now()})
        .eq('id', idContrato);

    // 2. NUEVO: Duplicar SOLO productos que no existen
    final idTiendaDestino = contrato['id_tienda_consignataria'] as int;
    final idTiendaOrigen = contrato['id_tienda_consignadora'] as int;

    // Obtener productos del contrato
    final productos = await _supabase
        .from('app_dat_producto_consignacion')
        .select('id_producto')
        .eq('id_contrato', idContrato)
        .eq('estado', 1);

    int duplicados = 0;
    int reutilizados = 0;

    for (final item in productos) {
      final idProducto = item['id_producto'] as int;
      
      final resultado = await ConsignacionDuplicacionService.duplicarProductoSiNecesario(
        idProductoOriginal: idProducto,
        idTiendaDestino: idTiendaDestino,
        idContratoConsignacion: idContrato,
        idTiendaOrigen: idTiendaOrigen,
      );

      if (resultado != null) {
        // Verificar si fue duplicado o reutilizado
        final duplicacion = await ConsignacionDuplicacionService.obtenerDuplicacion(
          idProductoOriginal: idProducto,
          idTiendaDestino: idTiendaDestino,
        );
        
        if (duplicacion != null) {
          duplicados++;
        } else {
          reutilizados++;
        }
      }
    }

    debugPrint('✅ Contrato confirmado');
    debugPrint('   Productos duplicados: $duplicados');
    debugPrint('   Productos reutilizados: $reutilizados');
    
    return true;
  } catch (e) {
    debugPrint('❌ Error: $e');
    return false;
  }
}
```

### Ejemplo de Resultado

```
Contrato con 5 productos:
├─ Producto A: Existe en tienda destino → REUTILIZAR ✅
├─ Producto B: NO existe en tienda destino → DUPLICAR 🔄
├─ Producto C: Existe en tienda destino → REUTILIZAR ✅
├─ Producto D: NO existe en tienda destino → DUPLICAR 🔄
└─ Producto E: Existe en tienda destino → REUTILIZAR ✅

Resultado:
├─ 2 productos duplicados (B, D)
├─ 3 productos reutilizados (A, C, E)
└─ Cero duplicados innecesarios
```

## 🎯 Próximos Pasos

1. ✅ Crear tabla de trazabilidad
2. ✅ Crear función RPC de duplicación bajo demanda
3. ✅ Crear servicio Dart
4. ✅ Integrar en confirmación de contrato
5. ✅ Probar flujo completo
6. ✅ Vender productos

---

**Estado:** Listo para implementar
**Complejidad:** Media
**Tiempo:** 1-2 horas
**Optimización:** ⭐⭐⭐⭐⭐ (Duplicación bajo demanda)
