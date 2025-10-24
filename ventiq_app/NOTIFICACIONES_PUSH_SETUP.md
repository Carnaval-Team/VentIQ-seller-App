# Configuración de Notificaciones Push Locales - VentIQ

## ✅ Implementación Completada

Se ha implementado un sistema completo de **notificaciones push locales** que muestra notificaciones en la barra de Android y como emergentes.

## 📦 Archivos Creados/Modificados

### Nuevos Archivos:
1. **`lib/services/local_notification_service.dart`**: Servicio de notificaciones push locales
2. **`NOTIFICACIONES_PUSH_SETUP.md`**: Este archivo de documentación

### Archivos Modificados:
1. **`pubspec.yaml`**: Agregado `flutter_local_notifications: ^17.2.3`
2. **`lib/services/notification_service.dart`**: Integración con notificaciones locales
3. **`android/app/src/main/AndroidManifest.xml`**: Permisos y receivers configurados

## 🚀 Instalación

### Paso 1: Instalar Dependencias

```bash
cd ventiq_app
flutter pub get
```

### Paso 2: Limpiar y Reconstruir (IMPORTANTE)

```bash
flutter clean
flutter pub get
cd android
./gradlew clean
cd ..
flutter run
```

## 📱 Permisos Configurados en Android

### AndroidManifest.xml - Permisos Agregados:

```xml
<!-- Permisos para notificaciones push locales -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.VIBRATE" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
<uses-permission android:name="android.permission.USE_EXACT_ALARM" />
```

### Receivers Configurados:

```xml
<!-- Receiver para notificaciones locales -->
<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED"/>
        <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
        <action android:name="android.intent.action.QUICKBOOT_POWERON" />
        <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
    </intent-filter>
</receiver>
```

## 🎯 Funcionamiento

### Flujo Automático:

1. **Nueva notificación llega desde Supabase** (Realtime)
2. **NotificationService la recibe** y procesa
3. **LocalNotificationService muestra notificación push** en Android
4. **Usuario ve la notificación** en:
   - ✅ Barra de notificaciones de Android
   - ✅ Como emergente (heads-up notification)
   - ✅ En el widget de notificaciones de la app

### Características de las Notificaciones Push:

#### Prioridad Automática:
- **Urgente** → `Priority.max` + `Importance.max` (aparece como emergente)
- **Alta** → `Priority.high` + `Importance.high`
- **Normal/Baja** → `Priority.default` + `Importance.default`

#### Estilos Visuales:
- **Color**: Según tipo de notificación (alerta=naranja, info=azul, etc.)
- **Icono**: Icono de la app
- **BigTextStyle**: Muestra el mensaje completo expandible
- **Vibración**: Activada para notificaciones importantes
- **Sonido**: Sonido de notificación del sistema

#### Información Mostrada:
- **Título**: Título de la notificación
- **Mensaje**: Contenido completo (expandible)
- **Tipo**: Texto descriptivo (Alerta, Información, etc.)
- **Badge**: Número para notificaciones urgentes

## 🔔 Solicitud de Permisos

### Android 13+ (API 33+):
El servicio **solicita automáticamente** los permisos necesarios:

```dart
// Se ejecuta automáticamente al inicializar
await _requestPermissions();
```

Permisos solicitados:
1. **POST_NOTIFICATIONS**: Para mostrar notificaciones
2. **SCHEDULE_EXACT_ALARM**: Para alarmas exactas (opcional)

### Primera Ejecución:
- La app solicitará permiso de notificaciones al usuario
- El usuario debe **ACEPTAR** para ver notificaciones push
- Si se rechaza, solo verán notificaciones dentro de la app

## 🧪 Pruebas

### Crear Notificación de Prueba en Supabase:

```sql
-- Notificación urgente (aparecerá como emergente)
SELECT fn_crear_notificacion(
  '2db8b27d-0f52-4aed-a6ce-206ff4651f41'::UUID,
  'alerta',
  '⚠️ Producto Agotado',
  'El producto "Arroz Blanco 5kg" se ha agotado completamente',
  '{"producto_id": 123}'::jsonb,
  'urgente'
);

-- Notificación normal
SELECT fn_crear_notificacion(
  '2db8b27d-0f52-4aed-a6ce-206ff4651f41'::UUID,
  'info',
  'Nueva Actualización',
  'Hay una nueva versión disponible de VentIQ',
  '{}'::jsonb,
  'normal'
);

-- Notificación de venta
SELECT fn_crear_notificacion(
  '2db8b27d-0f52-4aed-a6ce-206ff4651f41'::UUID,
  'venta',
  'Nueva Venta Registrada',
  'Se ha registrado una venta de $150.00',
  '{"orden_id": 456, "monto": 150.00}'::jsonb,
  'alta'
);
```

### Verificar Funcionamiento:

1. **Ejecutar la app** en un dispositivo Android
2. **Aceptar permisos** de notificaciones cuando se soliciten
3. **Ejecutar el SQL** en Supabase para crear notificación
4. **Verificar que aparece**:
   - ✅ En la barra de notificaciones de Android
   - ✅ Como emergente (si es urgente/alta prioridad)
   - ✅ En el widget de notificaciones de la app

## 🎨 Personalización

### Colores por Tipo de Notificación:

El color se asigna automáticamente según el tipo:

```dart
// En NotificationModel.getColor()
alerta → Naranja (#FF9800)
info → Azul (#2196F3)
warning → Amarillo (#FFC107)
success → Verde (#4CAF50)
error → Rojo (#F44336)
promocion → Púrpura (#9C27B0)
sistema → Gris (#607D8B)
pedido → Cyan (#00BCD4)
inventario → Naranja Profundo (#FF5722)
venta → Verde Claro (#8BC34A)
```

### Crear Canal Personalizado:

```dart
final localNotificationService = LocalNotificationService();

await localNotificationService.createNotificationChannel(
  id: 'ventas_urgentes',
  name: 'Ventas Urgentes',
  description: 'Notificaciones urgentes de ventas',
  importance: Importance.max,
);
```

## 🔧 Métodos Disponibles

### LocalNotificationService:

```dart
// Mostrar notificación
await localNotificationService.showNotification(notification);

// Cancelar notificación específica
await localNotificationService.cancelNotification(notificationId);

// Cancelar todas las notificaciones
await localNotificationService.cancelAllNotifications();

// Obtener notificaciones activas
final active = await localNotificationService.getActiveNotifications();
```

## 📊 Logging

El sistema proporciona logs detallados:

```
📱 Inicializando LocalNotificationService...
📱 Permiso de notificaciones: Concedido
⏰ Permiso de alarmas exactas: Concedido
✅ LocalNotificationService inicializado correctamente
🔔 Inicializando NotificationService...
👤 Usuario autenticado: 2db8b27d-0f52-4aed-a6ce-206ff4651f41
✅ Notificaciones cargadas: 5
📊 No leídas: 2
🆕 Nueva notificación recibida: {...}
✅ Notificación local mostrada: Producto Agotado
✅ Nueva notificación agregada: Producto Agotado
```

## ⚠️ Troubleshooting

### Las notificaciones no aparecen en Android:

1. **Verificar permisos**:
   ```
   Configuración → Apps → VentIQ → Notificaciones → Activar
   ```

2. **Verificar que se ejecutó flutter clean**:
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```

3. **Verificar logs**:
   - Buscar "Permiso de notificaciones: Concedido"
   - Si dice "Denegado", ir a configuración y activar manualmente

### Las notificaciones no son emergentes:

1. **Verificar prioridad**: Solo `urgente` y `alta` aparecen como emergentes
2. **Verificar configuración del sistema**:
   ```
   Configuración → Apps → VentIQ → Notificaciones → Comportamiento → Emergente
   ```

### Error al compilar:

1. **Limpiar proyecto**:
   ```bash
   flutter clean
   cd android
   ./gradlew clean
   cd ..
   flutter pub get
   ```

2. **Verificar AndroidManifest.xml**: Asegurar que los receivers estén dentro de `<application>`

## 🎯 Checklist de Implementación

- [x] Paquete `flutter_local_notifications` agregado
- [x] Servicio `LocalNotificationService` creado
- [x] Integración con `NotificationService`
- [x] Permisos agregados en AndroidManifest.xml
- [x] Receivers configurados en AndroidManifest.xml
- [x] Solicitud automática de permisos implementada
- [x] Colores y prioridades configurados
- [x] Logging detallado implementado
- [ ] Ejecutar `flutter pub get`
- [ ] Ejecutar `flutter clean`
- [ ] Probar en dispositivo Android
- [ ] Verificar permisos concedidos
- [ ] Crear notificación de prueba
- [ ] Verificar aparición en barra de Android

## 📚 Recursos

- [flutter_local_notifications Package](https://pub.dev/packages/flutter_local_notifications)
- [Android Notifications Guide](https://developer.android.com/develop/ui/views/notifications)
- [Supabase Realtime Docs](https://supabase.com/docs/guides/realtime)

---

**Sistema de Notificaciones Push Locales - VentIQ Seller App** 🔔
