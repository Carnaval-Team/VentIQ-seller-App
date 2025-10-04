# Sistema de Reautenticación Automática

## 📋 Descripción

Se ha implementado un sistema de reautenticación automática que resuelve el problema de errores de autenticación de Supabase cuando el usuario vuelve del modo offline al modo online.

## 🚨 Problema Resuelto

**Problema**: Cuando el usuario trabaja en modo offline y luego vuelve al modo online, en ciertas ocasiones al navegar se producen errores de autenticación de Supabase porque la sesión ha expirado o se ha perdido.

**Solución**: Sistema de reautenticación automática que detecta cuando se necesita reautenticar y lo hace automáticamente usando las credenciales guardadas, replicando exactamente el proceso de login completo.

## 🏗️ Arquitectura de la Solución

### 1. ReauthenticationService (`lib/services/reauthentication_service.dart`)

**Propósito**: Servicio especializado en reautenticar automáticamente al usuario

**Funcionalidades principales**:

#### `reauthenticateUser()` 
Replica exactamente el proceso de login del `login_screen.dart`:
1. **Autenticación con Supabase**: `authService.signInWithEmailAndPassword()`
2. **Guardar datos del usuario**: `saveUserData()`
3. **Verificar perfil del vendedor**: `sellerService.verifySellerAndGetProfile()`
4. **Guardar datos del vendedor**: `saveSellerData()`, `saveIdSeller()`
5. **Guardar perfil del trabajador**: `saveWorkerProfile()`
6. **Actualizar promoción global**: `promotionService.getGlobalPromotion()`
7. **Actualizar usuario offline**: `saveOfflineUser()`

#### `needsReauthentication()`
Verifica si es necesario reautenticar:
- ✅ No hay sesión activa en Supabase
- ✅ Sesión expirada
- ✅ Token próximo a expirar (< 5 minutos)
- ✅ Datos locales incompletos o en modo offline

#### `ensureAuthenticated()`
Verifica y reautentica solo si es necesario

#### `getAuthenticationStatus()`
Proporciona información detallada del estado de autenticación

### 2. Integración en SmartOfflineManager

**Modificaciones realizadas**:

#### Método `_handleConnectionRestored()`
Ahora incluye reautenticación automática:
```dart
// 1. Verificar si necesita reautenticación
final needsReauth = await _reauthService.needsReauthentication();

// 2. Reautenticar si es necesario
if (needsReauth) {
  final reauthSuccess = await _reauthService.reauthenticateUser();
  // Notificar resultado
}

// 3. Iniciar sincronización automática
await _autoSyncService.startAutoSync();
```

#### Nuevos Eventos
- `reauthenticationStarted`: Inicia reautenticación
- `reauthenticationSuccess`: Reautenticación exitosa  
- `reauthenticationFailed`: Error en reautenticación

### 3. Integración en AutoSyncService

**Modificaciones realizadas**:

#### Método `_performSync()`
Ahora verifica autenticación antes de cada sincronización:
```dart
// Verificar y asegurar autenticación
final isAuthenticated = await _reauthService.ensureAuthenticated();

if (!isAuthenticated) {
  throw Exception('No se pudo autenticar al usuario para sincronización');
}
```

### 4. Notificaciones en SettingsScreen

**Nuevas notificaciones agregadas**:
- 🔐 **Reautenticando usuario...** (naranja, 2s)
- ✅ **Usuario reautenticado correctamente** (verde, 3s)  
- ⚠️ **Error en reautenticación - Puede requerir login manual** (naranja, 5s)

## 🔄 Flujos de Funcionamiento

### Flujo 1: Restauración de Conexión (Modo Online)
```
1. ConnectivityService detecta conexión restaurada
2. SmartOfflineManager verifica si modo offline está desactivado
3. Si está desactivado:
   a. Verifica si necesita reautenticación
   b. Si necesita: reautentica automáticamente
   c. Inicia sincronización automática
4. Usuario recibe notificaciones del proceso
```

### Flujo 2: Sincronización Automática Periódica
```
1. AutoSyncService inicia sincronización (cada minuto)
2. Verifica autenticación con ensureAuthenticated()
3. Si necesita reautenticación: la hace automáticamente
4. Procede con sincronización normal
5. Usuario trabaja sin interrupciones
```

### Flujo 3: Detección de Necesidad de Reautenticación
```
1. Verificar sesión actual de Supabase
2. Verificar expiración de token
3. Verificar completitud de datos locales
4. Si alguna falla: marcar como necesaria reautenticación
```

## 🎯 Beneficios

### Para el Usuario
- **Sin interrupciones**: No más errores de autenticación inesperados
- **Transparente**: El proceso es automático e invisible
- **Informativo**: Notificaciones claras de lo que está pasando
- **Confiable**: Siempre mantiene sesión válida

### Para el Desarrollo
- **Modular**: Servicio independiente y reutilizable
- **Robusto**: Manejo completo de errores
- **Logging**: Información detallada para debugging
- **Consistente**: Replica exactamente el proceso de login original

## 🔧 Configuración y Parámetros

### Timeouts y Umbrales
```dart
// Tiempo antes de expiración para reautenticar
const Duration tokenExpiryThreshold = Duration(minutes: 5);

// Timeout para operaciones de autenticación
const Duration authTimeout = Duration(seconds: 30);
```

### Estados de Autenticación
```dart
class AuthenticationStatus {
  final bool hasSupabaseSession;      // Sesión activa en Supabase
  final bool hasLocalUserData;        // Datos locales completos
  final bool hasCredentials;          // Credenciales guardadas
  final bool isOfflineMode;           // En modo offline
  final DateTime? sessionExpiresAt;   // Cuándo expira la sesión
  
  // Propiedades calculadas
  bool get isFullyAuthenticated;      // Totalmente autenticado
  bool get canReauthenticate;         // Puede reautenticar
  bool get needsReauthentication;     // Necesita reautenticar
}
```

## 📝 Logging y Debugging

El sistema incluye logging detallado:

```
🔐 Verificando autenticación tras restauración de conexión...
🔍 No hay sesión activa en Supabase - Reautenticación necesaria
🔄 Reautenticando usuario automáticamente...
📧 Reautenticando usuario: usuario@ejemplo.com
✅ Autenticación con Supabase exitosa
  - User ID: 12345678-1234-1234-1234-123456789012
  - Email: usuario@ejemplo.com
🔍 Perfil del vendedor obtenido:
  - ID TPV: 1
  - ID Tienda: 1
  - ID Seller: 1
✅ Reautenticación completa exitosa
🌐 Usuario listo para trabajar online
```

## 🚨 Manejo de Errores

### Errores Manejados
1. **Credenciales inválidas**: Usuario debe hacer login manual
2. **Usuario no es vendedor**: Se limpia sesión y se requiere login
3. **Error de red**: Se reintenta automáticamente
4. **Sesión expirada**: Se reautentica automáticamente
5. **Datos incompletos**: Se reautentica para completar

### Estrategias de Recuperación
- **Reintento automático**: Para errores temporales
- **Fallback a modo offline**: Si la reautenticación falla
- **Notificación al usuario**: Para errores que requieren acción manual
- **Logging detallado**: Para debugging y soporte

## ✅ Casos de Uso Cubiertos

1. ✅ **Usuario trabaja offline y vuelve online**
2. ✅ **Sesión expira durante uso normal**
3. ✅ **Token próximo a expirar**
4. ✅ **Datos locales corruptos o incompletos**
5. ✅ **Pérdida temporal de conexión**
6. ✅ **Cambio de credenciales en servidor**
7. ✅ **Sincronización automática periódica**
8. ✅ **Restauración de conexión tras modo offline automático**

## 🔮 Uso Recomendado

### Para Desarrolladores
```dart
// Verificar si necesita reautenticación
final reauthService = ReauthenticationService();
final needsReauth = await reauthService.needsReauthentication();

// Asegurar autenticación antes de operaciones críticas
final isAuthenticated = await reauthService.ensureAuthenticated();

// Obtener estado detallado
final status = await reauthService.getAuthenticationStatus();
```

### Para Monitoreo
```dart
// Escuchar eventos de reautenticación
smartOfflineManager.eventStream.listen((event) {
  if (event.type == SmartOfflineEventType.reauthenticationFailed) {
    // Manejar error de reautenticación
    showLoginScreen();
  }
});
```

Este sistema asegura que los usuarios de VentIQ Seller App nunca experimenten errores de autenticación inesperados al cambiar entre modo offline y online, proporcionando una experiencia fluida y confiable.
