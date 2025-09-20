# 🍽️ Módulo de Restaurante VentIQ - Documentación Completa

## 📋 Índice
1. [Resumen Ejecutivo](#resumen-ejecutivo)
2. [Arquitectura del Sistema](#arquitectura-del-sistema)
3. [Base de Datos](#base-de-datos)
4. [Funciones SQL](#funciones-sql)
5. [Servicios Dart](#servicios-dart)
6. [Modelos de Datos](#modelos-de-datos)
7. [Pantallas de Usuario](#pantallas-de-usuario)
8. [Guía de Instalación](#guía-de-instalación)
9. [Guía de Uso](#guía-de-uso)
10. [Casos de Uso](#casos-de-uso)
11. [Mantenimiento](#mantenimiento)

---

## 🎯 Resumen Ejecutivo

El **Módulo de Restaurante VentIQ** es una extensión completa del sistema VentIQ que permite la gestión integral de restaurantes con productos elaborados. Incluye gestión avanzada de unidades de medida, control de costos de producción, verificación automática de disponibilidad y descuento automático de inventario.

### ✨ Características Principales

- **🔧 Gestión Avanzada de Unidades de Medida**: Sistema completo de conversiones entre unidades
- **💰 Control de Costos de Producción**: Cálculo automático de costos por plato
- **📊 Verificación de Disponibilidad**: Control en tiempo real de ingredientes disponibles
- **🔄 Descuento Automático de Inventario**: Integración completa con sistema de inventario
- **📈 Análisis de Rentabilidad**: Reportes de márgenes y eficiencia por plato
- **🗂️ Gestión de Desperdicios**: Control y seguimiento de mermas

### 🎯 Beneficios

- **Operacionales**: Control preciso de inventario y costos
- **Financieros**: Optimización de márgenes y reducción de pérdidas
- **Estratégicos**: Toma de decisiones basada en datos reales

---

## 🏗️ Arquitectura del Sistema

### Diagrama de Arquitectura

```
┌─────────────────────────────────────────────────────────────┐
│                    MÓDULO RESTAURANTE                        │
├─────────────────────────────────────────────────────────────┤
│  Frontend (Flutter)                                        │
│  ┌─────────────────┐  ┌─────────────────┐                  │
│  │ Units Management│  │ Cost Management │                  │
│  │     Screen      │  │     Screen      │                  │
│  └─────────────────┘  └─────────────────┘                  │
├─────────────────────────────────────────────────────────────┤
│  Services Layer (Dart)                                     │
│  ┌─────────────────────────────────────────────────────────┐│
│  │            RestaurantService                            ││
│  └─────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────┤
│  Database Layer (PostgreSQL)                               │
│  ┌─────────────────┐  ┌─────────────────┐                  │
│  │ Tablas Nuevas   │  │ Funciones SQL   │                  │
│  │ - Unidades      │  │ - Conversiones  │                  │
│  │ - Conversiones  │  │ - Disponibilidad│                  │
│  │ - Costos        │  │ - Descuentos    │                  │
│  │ - Desperdicios  │  │                 │                  │
│  └─────────────────┘  └─────────────────┘                  │
└─────────────────────────────────────────────────────────────┘
```

### Componentes Principales

1. **Capa de Presentación**: Pantallas Flutter para gestión
2. **Capa de Servicios**: RestaurantService para lógica de negocio
3. **Capa de Datos**: Tablas y funciones SQL especializadas
4. **Capa de Integración**: Conexión con módulos existentes

---

## 🗄️ Base de Datos

### Nuevas Tablas Implementadas

#### 1. Sistema de Unidades de Medida

```sql
-- Catálogo de unidades de medida
app_nom_unidades_medida
├── id (PK)
├── denominacion (VARCHAR, UNIQUE)
├── abreviatura (VARCHAR, UNIQUE)
├── tipo_unidad (SMALLINT) -- 1=Peso, 2=Volumen, 3=Longitud, 4=Unidad
├── es_base (BOOLEAN)
├── factor_base (NUMERIC)
├── descripcion (TEXT)
└── created_at (TIMESTAMP)

-- Conversiones entre unidades
app_nom_conversiones_unidades
├── id (PK)
├── id_unidad_origen (FK → app_nom_unidades_medida)
├── id_unidad_destino (FK → app_nom_unidades_medida)
├── factor_conversion (NUMERIC)
├── es_aproximada (BOOLEAN)
├── observaciones (TEXT)
└── created_at (TIMESTAMP)

-- Unidades específicas por producto
app_dat_producto_unidades
├── id (PK)
├── id_producto (FK → app_dat_producto)
├── id_unidad_medida (FK → app_nom_unidades_medida)
├── factor_producto (NUMERIC)
├── es_unidad_compra (BOOLEAN)
├── es_unidad_venta (BOOLEAN)
├── es_unidad_inventario (BOOLEAN)
├── observaciones (TEXT)
└── created_at (TIMESTAMP)
```

#### 2. Gestión de Costos y Producción

```sql
-- Costos de producción por plato
app_rest_costos_produccion
├── id (PK)
├── id_plato (FK → app_rest_platos_elaborados)
├── fecha_calculo (DATE)
├── costo_ingredientes (NUMERIC)
├── costo_mano_obra (NUMERIC)
├── costo_indirecto (NUMERIC)
├── costo_total (COMPUTED)
├── margen_deseado (NUMERIC)
├── precio_sugerido (COMPUTED)
├── calculado_por (FK → auth.users)
├── observaciones (TEXT)
└── created_at (TIMESTAMP)

-- Control de disponibilidad de platos
app_rest_disponibilidad_platos
├── id (PK)
├── id_plato (FK → app_rest_platos_elaborados)
├── id_tienda (FK → app_dat_tienda)
├── fecha_revision (DATE)
├── stock_disponible (INTEGER)
├── ingredientes_suficientes (BOOLEAN)
├── motivo_no_disponible (TEXT)
├── revisado_por (FK → auth.users)
├── proxima_revision (TIMESTAMP)
└── created_at (TIMESTAMP)
```

#### 3. Control de Operaciones

```sql
-- Registro de desperdicios y mermas
app_rest_desperdicios
├── id (PK)
├── id_producto_inventario (FK → app_dat_producto)
├── id_plato (FK → app_rest_platos_elaborados, OPTIONAL)
├── cantidad_desperdiciada (NUMERIC)
├── id_unidad_medida (FK → app_nom_unidades_medida)
├── motivo_desperdicio (TEXT)
├── costo_desperdicio (NUMERIC)
├── fecha_desperdicio (TIMESTAMP)
├── registrado_por (FK → auth.users)
├── observaciones (TEXT)
└── created_at (TIMESTAMP)

-- Log de descuentos automáticos de inventario
app_rest_descuentos_inventario
├── id (PK)
├── id_venta_plato (FK → app_rest_venta_platos)
├── id_producto_inventario (FK → app_dat_producto)
├── cantidad_descontada (NUMERIC)
├── id_unidad_medida (FK → app_nom_unidades_medida)
├── id_ubicacion (FK → app_dat_layout_almacen)
├── precio_costo (NUMERIC)
├── fecha_descuento (TIMESTAMP)
├── procesado_por (FK → auth.users)
└── observaciones (TEXT)

-- Estados de preparación de platos
app_rest_estados_preparacion
├── id (PK)
├── id_venta_plato (FK → app_rest_venta_platos)
├── estado (SMALLINT) -- 1=Pendiente, 2=En preparación, 3=Listo, 4=Entregado
├── tiempo_estimado (INTEGER)
├── tiempo_real (INTEGER)
├── asignado_a (FK → auth.users, OPTIONAL)
├── observaciones_cocina (TEXT)
├── fecha_cambio_estado (TIMESTAMP)
└── cambiado_por (FK → auth.users)
```

---

## ⚙️ Funciones SQL

### 1. Conversión de Unidades

```sql
fn_convertir_unidades(
  p_cantidad NUMERIC,
  p_id_unidad_origen BIGINT,
  p_id_unidad_destino BIGINT,
  p_id_producto BIGINT DEFAULT NULL
) RETURNS NUMERIC
```

**Funcionalidad**: Convierte cantidades entre diferentes unidades de medida, considerando factores específicos por producto.

**Características**:
- Conversión directa e inversa
- Factores base automáticos
- Factores específicos por producto
- Validación de tipos de unidad
- Logging de auditoría

### 2. Verificación de Disponibilidad

```sql
fn_verificar_disponibilidad_plato(
  p_id_plato BIGINT,
  p_id_tienda BIGINT,
  p_cantidad INTEGER DEFAULT 1
) RETURNS JSONB
```

**Funcionalidad**: Verifica si hay suficientes ingredientes para preparar un plato.

**Retorna**:
```json
{
  "disponible": true,
  "ingredientes_faltantes": [],
  "costo_total": 15.50,
  "cantidad_solicitada": 2
}
```

### 3. Descuento Automático de Inventario

```sql
fn_descontar_inventario_plato(
  p_id_venta_plato BIGINT,
  p_id_tienda BIGINT,
  p_uuid_usuario UUID
) RETURNS JSONB
```

**Funcionalidad**: Descuenta automáticamente los ingredientes del inventario al vender un plato.

**Características**:
- Descuento FIFO (First In, First Out)
- Conversión automática de unidades
- Registro completo de trazabilidad
- Manejo de stock insuficiente
- Integración con operaciones de inventario

---

## 🔧 Servicios Dart

### RestaurantService

Servicio principal que encapsula toda la lógica de negocio del módulo de restaurante.

#### Métodos Principales

```dart
class RestaurantService {
  // Gestión de Unidades de Medida
  static Future<List<UnidadMedida>> getUnidadesMedida()
  static Future<List<ConversionUnidad>> getConversiones()
  static Future<double> convertirUnidades({...})
  static Future<void> configurarUnidadesProducto({...})
  
  // Gestión de Platos Elaborados
  static Future<List<PlatoElaborado>> getPlatosElaborados({...})
  static Future<DisponibilidadPlato> verificarDisponibilidadPlato({...})
  static Future<void> actualizarDisponibilidadPlato({...})
  
  // Gestión de Costos de Producción
  static Future<CostoProduccion> calcularCostoProduccion(int idPlato)
  static Future<void> guardarCostoProduccion(CostoProduccion costo)
  static Future<List<CostoProduccion>> getCostosProduccion(int idPlato)
  
  // Descuento Automático de Inventario
  static Future<ResultadoDescuento> procesarVentaPlato({...})
  static Future<List<DescuentoInventario>> getDescuentosInventario({...})
  
  // Gestión de Desperdicios
  static Future<void> registrarDesperdicio({...})
  static Future<List<Desperdicio>> getDesperdicios({...})
  
  // Estados de Preparación
  static Future<void> actualizarEstadoPreparacion({...})
  static Future<List<EstadoPreparacion>> getEstadosPreparacion({...})
}
```

---

## 📱 Pantallas de Usuario

### 1. UnitsManagementScreen

**Funcionalidad**: Gestión completa de unidades de medida y conversiones.

**Características**:
- ✅ Dos pestañas: Unidades y Conversiones
- ✅ CRUD completo para unidades de medida
- ✅ CRUD completo para conversiones
- ✅ Filtros por tipo de unidad
- ✅ Búsqueda por texto
- ✅ Validaciones de entrada
- ✅ Interfaz intuitiva con colores por tipo

**Navegación**:
```
UnitsManagementScreen
├── Tab: Unidades
│   ├── Filtros (Búsqueda + Tipo)
│   ├── Lista de Unidades
│   └── FAB: Nueva Unidad
└── Tab: Conversiones
    ├── Lista de Conversiones
    └── FAB: Nueva Conversión
```

### 2. RestaurantCostManagementScreen

**Funcionalidad**: Gestión de costos de producción y análisis de rentabilidad.

**Características**:
- ✅ Dos pestañas: Platos y Análisis
- ✅ Cálculo automático de costos
- ✅ Configuración de márgenes
- ✅ Historial de costos por plato
- ✅ Análisis de rentabilidad
- ✅ Indicadores visuales de rentabilidad

**Navegación**:
```
RestaurantCostManagementScreen
├── Tab: Platos
│   ├── Filtro de búsqueda
│   ├── Lista expandible de platos
│   │   ├── Información del plato
│   │   ├── Lista de ingredientes
│   │   └── Botones: Calcular | Historial
│   └── Dialogs: Costo | Historial
└── Tab: Análisis
    ├── Resumen General
    ├── Top Platos Rentables
    └── Platos con Problemas
```

---

## 🚀 Guía de Instalación

### Prerrequisitos

- ✅ VentIQ base instalado y funcionando
- ✅ PostgreSQL con estructura base de VentIQ
- ✅ Flutter SDK configurado
- ✅ Acceso a la base de datos

### Pasos de Instalación

#### 1. Ejecutar Scripts SQL

```bash
# 1. Ejecutar creación de tablas (ya incluidas en contex.sql)
psql -d ventiq_db -f contex.sql

# 2. Ejecutar funciones SQL
psql -d ventiq_db -f fn_convertir_unidades.sql
psql -d ventiq_db -f fn_verificar_disponibilidad_plato.sql
psql -d ventiq_db -f fn_descontar_inventario_plato.sql

# 3. Ejecutar datos de inicialización
psql -d ventiq_db -f init_restaurant_data.sql
```

#### 2. Integrar Código Dart

```bash
# Copiar archivos al proyecto
cp restaurant_models.dart ventiq_admin_app/lib/models/
cp restaurant_service.dart ventiq_admin_app/lib/services/
cp units_management_screen.dart ventiq_admin_app/lib/screens/
cp restaurant_cost_management_screen.dart ventiq_admin_app/lib/screens/
```

#### 3. Actualizar Dependencias

```yaml
# pubspec.yaml
dependencies:
  intl: ^0.18.0  # Para formateo de números y fechas
```

#### 4. Agregar Rutas de Navegación

```dart
// main.dart o routes.dart
'/units-management': (context) => const UnitsManagementScreen(),
'/restaurant-costs': (context) => const RestaurantCostManagementScreen(),
```

---

## 📖 Guía de Uso

### Configuración Inicial

#### 1. Configurar Unidades de Medida

1. Navegar a **Gestión → Unidades de Medida**
2. Revisar unidades preconfiguradas
3. Agregar unidades específicas si es necesario
4. Configurar conversiones adicionales

#### 2. Configurar Productos para Restaurante

1. Ir a **Productos → Gestión de Productos**
2. Para cada producto de cocina:
   - Configurar unidades de compra, venta e inventario
   - Establecer factores de conversión específicos
   - Definir unidades culinarias (tazas, cucharadas, etc.)

#### 3. Configurar Platos y Recetas

1. Crear categorías de platos
2. Agregar platos elaborados con:
   - Precio de venta
   - Tiempo de preparación
   - Instrucciones de preparación
3. Definir recetas con ingredientes y cantidades exactas

### Operación Diaria

#### Verificar Disponibilidad de Platos

```dart
// Verificar antes de tomar pedidos
final disponibilidad = await RestaurantService.verificarDisponibilidadPlato(
  idPlato: 1,
  cantidad: 2,
);

if (!disponibilidad.disponible) {
  // Mostrar ingredientes faltantes
  // Sugerir platos alternativos
}
```

#### Procesar Venta de Plato

```dart
// Al confirmar venta de plato elaborado
final resultado = await RestaurantService.procesarVentaPlato(
  idVentaPlato: ventaId,
);

if (resultado.success) {
  // Inventario descontado automáticamente
  // Plato en estado "En preparación"
} else {
  // Manejar error de stock insuficiente
}
```

#### Calcular Costos de Producción

1. Ir a **Restaurante → Gestión de Costos**
2. Seleccionar plato
3. Hacer clic en **Calcular Costo**
4. Revisar costo de ingredientes (automático)
5. Configurar costos de mano de obra e indirectos
6. Ajustar margen deseado
7. Guardar cálculo

---

## 📊 Casos de Uso

### Caso de Uso 1: Nuevo Plato en el Menú

**Escenario**: El chef quiere agregar "Pasta Carbonara" al menú.

**Pasos**:
1. **Crear el plato** en `app_rest_platos_elaborados`
2. **Definir la receta** en `app_rest_recetas`:
   - 200g pasta
   - 100g panceta
   - 2 huevos
   - 50g queso parmesano
3. **Calcular costo** usando `RestaurantService.calcularCostoProduccion()`
4. **Establecer precio** basado en margen deseado
5. **Verificar disponibilidad** antes de activar en menú

**Resultado**: Plato listo para venta con costo calculado y disponibilidad verificada.

### Caso de Uso 2: Control de Inventario en Tiempo Real

**Escenario**: Durante el servicio, verificar si se puede preparar una pizza.

**Pasos**:
1. **Cliente ordena** Pizza Margherita
2. **Sistema verifica** disponibilidad automáticamente
3. **Si disponible**: Confirma pedido y descuenta inventario
4. **Si no disponible**: Muestra ingredientes faltantes y sugiere alternativas

**Resultado**: Control automático de inventario sin intervención manual.

### Caso de Uso 3: Análisis de Rentabilidad

**Escenario**: Revisar qué platos son más rentables.

**Pasos**:
1. **Ir a análisis** en pantalla de costos
2. **Revisar resumen general** de márgenes
3. **Identificar platos** con baja rentabilidad
4. **Tomar acciones**:
   - Ajustar precios
   - Optimizar recetas
   - Cambiar proveedores
   - Retirar platos no rentables

**Resultado**: Decisiones informadas para optimizar rentabilidad.

---

## 🔧 Mantenimiento

### Tareas Regulares

#### Diarias
- ✅ Verificar disponibilidad de platos
- ✅ Revisar desperdicios registrados
- ✅ Monitorear estados de preparación

#### Semanales
- ✅ Analizar costos de producción
- ✅ Revisar márgenes por plato
- ✅ Actualizar precios si es necesario

#### Mensuales
- ✅ Análisis completo de rentabilidad
- ✅ Optimización de recetas
- ✅ Revisión de conversiones de unidades
- ✅ Limpieza de datos históricos

### Monitoreo del Sistema

#### Consultas de Monitoreo

```sql
-- Verificar integridad de conversiones
SELECT COUNT(*) FROM app_nom_conversiones_unidades 
WHERE factor_conversion <= 0;

-- Platos sin costo calculado
SELECT p.nombre 
FROM app_rest_platos_elaborados p
LEFT JOIN app_rest_costos_produccion c ON p.id = c.id_plato
WHERE c.id IS NULL AND p.es_activo = true;

-- Productos con unidades mal configuradas
SELECT p.denominacion 
FROM app_dat_producto p
LEFT JOIN app_dat_producto_unidades pu ON p.id = pu.id_producto
WHERE pu.id IS NULL;
```

#### Métricas Clave

- **Disponibilidad promedio de platos**: > 95%
- **Tiempo de cálculo de costos**: < 2 segundos
- **Precisión de conversiones**: 100%
- **Margen promedio**: > 25%

### Solución de Problemas

#### Problema: Conversión de unidades incorrecta

**Síntomas**: Cantidades erróneas en recetas
**Solución**:
1. Verificar factores de conversión
2. Revisar unidades base por tipo
3. Validar factores específicos por producto

#### Problema: Costo de producción muy alto

**Síntomas**: Márgenes negativos o muy bajos
**Solución**:
1. Revisar precios de ingredientes
2. Optimizar cantidades en recetas
3. Evaluar proveedores alternativos

#### Problema: Stock insuficiente frecuente

**Síntomas**: Platos no disponibles constantemente
**Solución**:
1. Ajustar niveles mínimos de inventario
2. Mejorar planificación de compras
3. Implementar alertas tempranas

---

## 📈 Métricas y KPIs

### Indicadores de Rendimiento

#### Operacionales
- **Disponibilidad de Platos**: % de tiempo que los platos están disponibles
- **Tiempo de Preparación**: Tiempo real vs. estimado
- **Precisión de Inventario**: Diferencia entre teórico y real

#### Financieros
- **Margen Bruto por Plato**: (Precio - Costo) / Precio * 100
- **Costo de Desperdicios**: Valor monetario de mermas
- **ROI por Plato**: Retorno de inversión por plato

#### Calidad
- **Consistencia de Recetas**: Variación en cantidades
- **Satisfacción del Cliente**: Relacionada con disponibilidad
- **Eficiencia de Cocina**: Platos preparados por hora

---

## 🔮 Roadmap Futuro

### Próximas Funcionalidades

#### Corto Plazo (1-3 meses)
- 🔄 **Integración con POS**: Descuento automático desde punto de venta
- 📱 **App de Cocina**: Pantalla dedicada para estados de preparación
- 🔔 **Alertas Inteligentes**: Notificaciones de stock bajo

#### Mediano Plazo (3-6 meses)
- 🤖 **IA para Predicción**: Predicción de demanda por plato
- 📊 **Dashboard Avanzado**: Métricas en tiempo real
- 🔗 **API Externa**: Integración con proveedores

#### Largo Plazo (6-12 meses)
- 🌐 **Multi-tienda**: Gestión centralizada de múltiples restaurantes
- 📈 **Analytics Avanzado**: Machine learning para optimización
- 🔄 **Automatización Completa**: Procesos autónomos

---

## 📞 Soporte

### Contacto Técnico
- **Desarrollador**: Equipo VentIQ
- **Email**: soporte@ventiq.com
- **Documentación**: [docs.ventiq.com/restaurant](https://docs.ventiq.com/restaurant)

### Recursos Adicionales
- 📚 **Manual de Usuario**: Guía paso a paso para usuarios finales
- 🎥 **Videos Tutoriales**: Capacitación visual
- 💬 **Comunidad**: Foro de usuarios y desarrolladores

---

**© 2024 VentIQ - Módulo de Restaurante**
*Versión 1.0 - Documentación Completa*
