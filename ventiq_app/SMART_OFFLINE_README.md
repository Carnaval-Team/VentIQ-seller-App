# Sistema Inteligente de Sincronización y Modo Offline

## 📋 Descripción

Este sistema implementa una solución inteligente para VentIQ Seller App que:

1. **Sincroniza automáticamente** los datos cada minuto cuando el modo offline NO está activado
2. **Activa automáticamente el modo offline** cuando se pierde la conexión de datos móviles
3. **Mantiene los datos actualizados** para que no tome por sorpresa la falta de conexión

## 🏗️ Arquitectura

### Servicios Principales

#### 1. ConnectivityService (`lib/services/connectivity_service.dart`)
- **Propósito**: Monitorea el estado de conectividad de red
- **Funcionalidades**:
  - Detecta cambios de conectividad del sistema
  - Verifica acceso real a internet (no solo conexión WiFi/móvil)
  - Verificación periódica cada 30 segundos
  - Streams para notificar cambios en tiempo real

#### 2. AutoSyncService (`lib/services/auto_sync_service.dart`)
- **Propósito**: Sincronización automática periódica de datos
- **Funcionalidades**:
  - Sincronización cada 1 minuto cuando modo offline está desactivado
  - Sincroniza credenciales, promociones, categorías, productos, órdenes
  - Productos completos cada 3 sincronizaciones (para no sobrecargar)
  - Órdenes cada 2 sincronizaciones
  - Guarda datos para uso offline futuro

#### 3. SmartOfflineManager (`lib/services/smart_offline_manager.dart`)
- **Propósito**: Coordinador inteligente del sistema
- **Funcionalidades**:
  - Coordina ConnectivityService y AutoSyncService
  - Activa automáticamente modo offline al perder conexión
  - Inicia sincronización automática al restaurar conexión
  - Cooldown de 5 minutos para evitar activaciones frecuentes

#### 4. SettingsIntegrationService (`lib/services/settings_integration_service.dart`)
- **Propósito**: Integración con la interfaz de usuario
- **Funcionalidades**:
  - Maneja cambios manuales del modo offline
  - Proporciona estado unificado para la UI
  - Permite forzar sincronización inmediata

### Widget de UI

#### ConnectionStatusWidget (`lib/widgets/connection_status_widget.dart`)
- **Propósito**: Indicador visual del estado de conexión
- **Variantes**:
  - Compacto: Para AppBar (chip pequeño con estado)
  - Detallado: Para diálogos (información completa)
  - Solo ícono: Para espacios reducidos

## 🚀 Cómo Funciona

### Flujo Normal (Online)
1. Usuario trabaja normalmente con conexión
2. **AutoSyncService** sincroniza datos cada minuto automáticamente
3. Datos se guardan para uso offline futuro
4. Usuario tiene datos actualizados sin intervención

### Flujo de Pérdida de Conexión
1. **ConnectivityService** detecta pérdida de conexión
2. Espera 10 segundos para confirmar (evita falsos positivos)
3. **SmartOfflineManager** verifica que hay datos offline disponibles
4. **Activa automáticamente modo offline**
5. Usuario puede seguir trabajando sin interrupción
6. Se muestra notificación informativa

### Flujo de Restauración de Conexión
1. **ConnectivityService** detecta conexión restaurada
2. Si modo offline está activo, informa al usuario pero no cambia nada
3. Si modo offline no está activo, inicia **AutoSyncService**
4. Datos se sincronizan automáticamente

### Flujo Manual
1. Usuario puede activar/desactivar modo offline manualmente
2. Sistema respeta decisiones manuales
3. Al desactivar manualmente, inicia sincronización automática si hay conexión

## 🔧 Integración en SettingsScreen

### Nuevas Funcionalidades Agregadas

#### 1. Indicador de Estado en AppBar
```dart
// Muestra chip compacto con estado actual
ConnectionStatusWidget(
  showDetails: true,
  compact: true,
)
```

#### 2. Sección "Estado de Sincronización Inteligente"
- Muestra estado actual del sistema
- Información de última sincronización
- Botón para ver detalles completos

#### 3. Botón "Forzar Sincronización"
- Permite sincronización inmediata
- Útil para actualizar datos manualmente

#### 4. Notificaciones Automáticas
- Modo offline activado automáticamente
- Conexión restaurada
- Sincronización automática iniciada
- Errores del sistema

## 📱 Estados Visuales

### Indicadores de Estado
- 🟢 **Verde + Sync**: Sincronizando automáticamente
- 🔵 **Azul + WiFi**: Conectado, listo para sincronizar
- 🟠 **Naranja + Cloud Off**: Modo offline activo
- 🔴 **Rojo + WiFi Off**: Sin conexión

### Notificaciones
- 🔌 Modo offline activado automáticamente por pérdida de conexión
- 📶 Conexión restaurada - Datos sincronizándose automáticamente
- 🔄 Sincronización automática iniciada
- ❌ Errores del sistema

## ⚙️ Configuración

### Parámetros Ajustables

#### ConnectivityService
```dart
static const Duration _checkInterval = Duration(seconds: 30);
static const Duration _timeoutDuration = Duration(seconds: 60);
```

#### AutoSyncService
```dart
static const Duration _syncInterval = Duration(minutes: 1);
static const Duration _syncTimeout = Duration(minutes: 5);
```

#### SmartOfflineManager
```dart
static const Duration _connectionLostThreshold = Duration(seconds: 10);
static const Duration _autoActivationCooldown = Duration(minutes: 5);
```

## 🔄 Ciclo de Sincronización

### Cada Minuto (si modo offline desactivado):
1. **Credenciales**: Actualiza datos del usuario
2. **Promociones**: Sincroniza promociones globales
3. **Métodos de pago**: Actualiza métodos activos
4. **Categorías**: Sincroniza categorías
5. **Turno**: Sincroniza turno actual y resumen

### Cada 2 Minutos:
6. **Órdenes**: Sincroniza órdenes recientes (últimas 50)

### Cada 3 Minutos:
7. **Productos**: Sincroniza productos con detalles completos (limitado a 3 categorías, 10 productos por subcategoría)

## 🛠️ Dependencias Agregadas

```yaml
# Connectivity monitoring
connectivity_plus: ^6.0.5
http: ^1.2.2

# Crypto for hashing
crypto: ^3.0.3
```

## 📝 Logging

El sistema incluye logging detallado para debugging:

```
🚀 Iniciando servicios inteligentes...
📡 Cambio de conectividad detectado: wifi
🔍 Verificando acceso real a internet...
🌐 Verificación de internet: ✅ Conectado
📶 CONEXIÓN RESTAURADA: Conexión a internet restaurada
🔄 Sincronización automática iniciada
✅ Credenciales sincronizadas
✅ Promociones sincronizadas
💾 Datos guardados para uso offline futuro
```

## 🎯 Beneficios

1. **Experiencia Fluida**: Usuario nunca se queda sin datos
2. **Automático**: No requiere intervención manual
3. **Inteligente**: Detecta y responde a cambios de conectividad
4. **Eficiente**: Sincronización optimizada para no sobrecargar
5. **Transparente**: Funciona en segundo plano
6. **Informativo**: Usuario siempre sabe el estado del sistema

## 🚨 Consideraciones

1. **Batería**: La sincronización automática consume batería
2. **Datos**: Sincronización usa datos móviles (optimizada)
3. **Almacenamiento**: Los datos offline ocupan espacio local
4. **Rendimiento**: Verificaciones periódicas usan recursos

## 🔮 Uso Recomendado

1. **Activar al iniciar la app**: Llamar a `SettingsIntegrationService.initialize()` en el main
2. **Mostrar indicador**: Usar `ConnectionStatusWidget` en AppBars importantes
3. **Monitorear eventos**: Escuchar `SettingsIntegrationService.eventStream` para logging
4. **Configurar según necesidad**: Ajustar intervalos según uso de la app

## 📚 Ejemplo de Inicialización

```dart
// En main.dart o en la pantalla principal
final settingsIntegration = SettingsIntegrationService();
await settingsIntegration.initialize();

// Escuchar eventos (opcional)
settingsIntegration.eventStream.listen((event) {
  print('Evento: ${event.type} - ${event.message}');
});
```

Este sistema asegura que los usuarios de VentIQ Seller App siempre tengan datos actualizados y puedan trabajar sin interrupciones, incluso cuando la conectividad es inestable.
