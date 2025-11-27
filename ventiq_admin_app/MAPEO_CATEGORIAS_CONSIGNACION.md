# 🔗 Mapeo de Categorías para Productos de Consignación

## 🎯 Problema Identificado

Cuando recibes productos de consignación de otra tienda:
- ✅ Entran al inventario
- ❌ Tienen categorías/subcategorías que **no existen en tu tienda**
- ❌ No aparecen en los listados de venta (filtrados por categoría)
- ❌ **No puedes venderlos**

## 💡 Solución Implementada

Sistema de **mapeo automático de categorías** que permite:
1. **Detectar** productos sin categoría mapeada
2. **Asignar** categorías de tu tienda a productos de consignación
3. **Vender** productos usando las categorías mapeadas

## 🗄️ Estructura de Base de Datos

### Tabla 1: `app_dat_mapeo_categoria_tienda`
Almacena mapeos entre categorías de diferentes tiendas:
```
- id (PK)
- id_tienda_origen: Tienda que envía
- id_categoria_origen: Categoría en tienda origen
- id_tienda_destino: Tu tienda
- id_categoria_destino: Categoría en tu tienda
- id_subcategoria_origen (nullable)
- id_subcategoria_destino (nullable)
- activo: true/false
```

### Tabla 2: `app_dat_producto_consignacion_categoria_tienda`
Registra qué categoría se asignó a cada producto:
```
- id (PK)
- id_producto_consignacion: Producto de consignación
- id_tienda_destino: Tu tienda
- id_categoria_destino: Categoría asignada
- id_subcategoria_destino (nullable)
- asignado_por: Usuario que asignó
- asignado_en: Fecha de asignación
```

## 🔧 Funciones RPC Creadas

### 1. `get_productos_consignacion_sin_mapeo(p_id_tienda_destino)`
Obtiene productos de consignación sin categoría mapeada:
```sql
SELECT 
  id_producto_consignacion,
  denominacion_producto,
  sku_producto,
  categoria_origen,
  subcategoria_origen,
  tienda_origen,
  cantidad_disponible
```

### 2. `asignar_categoria_producto_consignacion(...)`
Asigna categoría a un producto:
```sql
INSERT INTO app_dat_producto_consignacion_categoria_tienda
VALUES (...)
ON CONFLICT UPDATE
```

### 3. `get_productos_consignacion_para_venta(p_id_tienda_destino, p_id_categoria_destino)`
Obtiene productos de consignación listos para vender:
```sql
SELECT 
  id_producto_consignacion,
  denominacion_producto,
  categoria_destino,
  subcategoria_destino,
  cantidad_disponible,
  precio_venta_sugerido
```

### 4. `get_categoria_mapeada(...)`
Obtiene categoría mapeada para un producto:
```sql
SELECT 
  id_categoria_destino,
  id_subcategoria_destino,
  categoria_nombre,
  subcategoria_nombre
```

## 📱 Servicio Dart: `ConsignacionCategoriaService`

### Métodos Principales

**`getProductosSinMapeo()`**
- Obtiene productos sin categoría mapeada
- Retorna lista con detalles de tienda origen

**`getCategoriasTienda()`**
- Obtiene todas las categorías de tu tienda
- Retorna lista de categorías disponibles

**`getSubcategorias(idCategoria)`**
- Obtiene subcategorías de una categoría
- Retorna lista de subcategorías

**`asignarCategoriaProducto(...)`**
- Asigna categoría a un producto de consignación
- Retorna bool indicando éxito

**`getProductosParaVenta(idCategoria)`**
- Obtiene productos listos para vender
- Filtra por categoría si se especifica
- Retorna lista de productos con categoría mapeada

**`getMapeosCategorias(idTiendaOrigen)`**
- Obtiene mapeos de categorías existentes
- Retorna lista de mapeos

**`crearMapeoCategoria(...)`**
- Crea mapeo entre categorías de tiendas
- Retorna bool indicando éxito

## 🎨 Pantalla: `MapeoCategoriesConsignacionScreen`

### Funcionalidad

1. **Listar productos sin mapeo**
   - Muestra todos los productos de consignación sin categoría
   - Información: nombre, SKU, tienda origen, categoría origen
   - Cantidad disponible

2. **Asignar categoría**
   - Diálogo para seleccionar categoría de tu tienda
   - Opción de seleccionar subcategoría
   - Botón "Asignar"

3. **Actualización automática**
   - Recarga lista después de asignar
   - Muestra mensaje de éxito/error

### UI

```
┌─────────────────────────────────┐
│ Mapear Categorías de Consignación│
├─────────────────────────────────┤
│                                 │
│ [Producto 1 - Sin Mapeo]        │
│ ├─ De: Tienda A                 │
│ ├─ Categoría origen: Alimentos  │
│ ├─ Disponible: 50 unidades      │
│ └─ [Asignar Categoría]          │
│                                 │
│ [Producto 2 - Sin Mapeo]        │
│ ├─ De: Tienda B                 │
│ ├─ Categoría origen: Bebidas    │
│ ├─ Disponible: 30 unidades      │
│ └─ [Asignar Categoría]          │
│                                 │
└─────────────────────────────────┘
```

### Diálogo de Asignación

```
┌──────────────────────────────────┐
│ Asignar Categoría                │
├──────────────────────────────────┤
│                                  │
│ Producto: Producto 1             │
│ De: Tienda A                     │
│ Categoría origen: Alimentos      │
│                                  │
│ Selecciona categoría en tu tienda│
│ [Dropdown: Seleccionar...]       │
│                                  │
│ Subcategoría (opcional)          │
│ [Dropdown: Seleccionar...]       │
│                                  │
│ [Cancelar]  [Asignar]            │
│                                  │
└──────────────────────────────────┘
```

## 🚀 Pasos de Implementación

### Paso 1: Crear Tablas en Supabase
1. Abre **Supabase Dashboard → SQL Editor**
2. Copia contenido de `mapeo_categorias_consignacion.sql`
3. Ejecuta el SQL
4. Verifica que se crearon las tablas y funciones

### Paso 2: Verificar Funciones RPC
```sql
-- Verifica que existen las funciones
SELECT * FROM pg_proc WHERE proname LIKE 'get_productos_consignacion%';
SELECT * FROM pg_proc WHERE proname LIKE 'asignar_categoria%';
```

### Paso 3: Agregar Servicio a Proyecto
- Archivo: `lib/services/consignacion_categoria_service.dart`
- Ya incluido en el proyecto

### Paso 4: Agregar Pantalla a Proyecto
- Archivo: `lib/screens/mapeo_categorias_consignacion_screen.dart`
- Ya incluido en el proyecto

### Paso 5: Integrar en Navegación
Agregar botón en `ConsignacionScreen`:

```dart
// En AppBar o FAB
ElevatedButton.icon(
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MapeoCategoriesConsignacionScreen(),
      ),
    );
  },
  icon: const Icon(Icons.link),
  label: const Text('Mapear Categorías'),
)
```

### Paso 6: Probar Flujo Completo
1. Recibir productos de consignación
2. Abrir "Mapear Categorías"
3. Ver productos sin mapeo
4. Asignar categoría a cada producto
5. Verificar que aparecen en listados de venta
6. Vender productos

## 📊 Flujo Completo

```
1. Recibir Productos de Consignación
   ├─ Tienda A envía productos
   ├─ Tienen categoría "Alimentos"
   └─ Tu tienda no tiene esa categoría

2. Abrir "Mapear Categorías"
   ├─ Ver productos sin mapeo
   └─ Mostrar: Producto 1, Tienda A, Categoría: Alimentos

3. Asignar Categoría
   ├─ Seleccionar: "Alimentos" (de tu tienda)
   ├─ Seleccionar: "Frutas" (subcategoría)
   └─ Guardar mapeo

4. Producto Mapeado
   ├─ Se registra en app_dat_producto_consignacion_categoria_tienda
   └─ Ahora aparece en listados de venta

5. Vender Producto
   ├─ Aparece en categoría "Alimentos > Frutas"
   ├─ Se puede vender normalmente
   └─ Se registra venta en app_dat_producto_consignacion
```

## 🔍 Consultas Útiles

### Ver productos sin mapeo
```sql
SELECT * FROM get_productos_consignacion_sin_mapeo(1);
```

### Ver productos listos para vender
```sql
SELECT * FROM get_productos_consignacion_para_venta(1, NULL);
```

### Ver mapeos existentes
```sql
SELECT * FROM app_dat_mapeo_categoria_tienda 
WHERE id_tienda_destino = 1 AND activo = true;
```

### Ver asignaciones de productos
```sql
SELECT * FROM app_dat_producto_consignacion_categoria_tienda 
WHERE id_tienda_destino = 1;
```

## ✅ Validaciones

✅ Solo productos de consignación confirmados
✅ Solo categorías de tu tienda
✅ Subcategorías opcionales
✅ Mapeo único por producto
✅ Actualización automática de asignaciones
✅ Logs de depuración completos

## 🎯 Beneficios

- ✅ **Flexibilidad**: Mapea categorías según necesites
- ✅ **Automatización**: Asignación rápida y fácil
- ✅ **Venta**: Productos disponibles en listados
- ✅ **Trazabilidad**: Registro de mapeos y asignaciones
- ✅ **Escalabilidad**: Funciona con múltiples tiendas

## 📝 Próximas Mejoras (Opcionales)

- Mapeo automático por similitud de nombres
- Sugerencias de categorías basadas en IA
- Historial de mapeos
- Reportes de productos mapeados
- Sincronización de categorías entre tiendas

---

**Estado:** ✅ Listo para implementar
**Complejidad:** Media
**Tiempo de implementación:** 30 minutos
