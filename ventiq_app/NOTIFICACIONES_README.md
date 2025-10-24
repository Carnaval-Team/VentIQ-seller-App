# Sistema de Notificaciones VentIQ

Sistema completo de notificaciones en tiempo real para VentIQ Seller App con **notificaciones push locales** en Android.

## ✨ Características

- ✅ **Notificaciones en tiempo real** desde Supabase
- ✅ **Notificaciones push en barra de Android** 
- ✅ **Notificaciones emergentes** (heads-up)
- ✅ **Widget de notificaciones** en la app
- ✅ **10 tipos de notificación** con colores e iconos
- ✅ **4 niveles de prioridad**
- ✅ **Vibración y sonido** configurables

## 📋 Archivos Creados

### 1. Base de Datos (Supabase)
- **`supabase/notifications_table.sql`**: Script SQL completo para crear la tabla de notificaciones con realtime

### 2. Modelos
- **`lib/models/notification_model.dart`**: Modelo de datos de notificaciones

### 3. Servicios
- **`lib/services/notification_service.dart`**: Servicio para gestionar notificaciones en tiempo real
- **`lib/services/local_notification_service.dart`**: Servicio para notificaciones push locales

### 4. Widgets
- **`lib/widgets/notification_widget.dart`**: Widget de notificaciones con panel deslizable

### 5. Configuración Android
- **`android/app/src/main/AndroidManifest.xml`**: Permisos y receivers configurados

## 🚀 Instalación

### Paso 1: Ejecutar Script SQL en Supabase

1. Ir a tu proyecto en Supabase
2. Navegar a **SQL Editor**
3. Copiar y ejecutar el contenido de `supabase/notifications_table.sql`
4. Verificar que la tabla `app_dat_notificaciones` se haya creado correctamente

El script crea:
- ✅ Tabla `app_dat_notificaciones` con todos los campos necesarios
- ✅ Índices para optimizar consultas
- ✅ Triggers para actualizar timestamps
- ✅ Habilitación de Realtime
- ✅ Row Level Security (RLS) policies
- ✅ Funciones RPC para gestión de notificaciones

### Paso 2: Instalar Dependencias

```bash
cd ventiq_app
flutter pub get
```

Paquetes agregados:
- `timeago: ^3.7.0` - Formato de fechas relativas
- `flutter_local_notifications: ^17.2.3` - Notificaciones push locales

### Paso 3: Limpiar y Reconstruir (IMPORTANTE para Android)

```bash
flutter clean
flutter pub get
cd android
./gradlew clean
cd ..
flutter run
```

**⚠️ IMPORTANTE**: Debes ejecutar `flutter clean` para que los permisos de Android se apliquen correctamente.

### Paso 4: Integración en Pantallas

El sistema ya está integrado en `CategoriesScreen`. Para agregar en otras pantallas:

```dart
// 1. Importar
import '../widgets/notification_widget.dart';
import '../services/notification_service.dart';

// 2. Agregar instancia del servicio
final NotificationService _notificationService = NotificationService();

// 3. Inicializar en initState
@override
void initState() {
  super.initState();
  _notificationService.initialize();
}

// 4. Limpiar en dispose
@override
void dispose() {
  _notificationService.dispose();
  super.dispose();
}

// 5. Agregar widget en AppBar
AppBar(
  actions: [
    const NotificationWidget(),
    // ... otros botones
  ],
)
```

## 📱 Características

### Tipos de Notificación
- **alerta**: Alertas importantes (naranja)
- **info**: Información general (azul)
- **warning**: Advertencias (amarillo)
- **success**: Éxito (verde)
- **error**: Errores (rojo)
- **promocion**: Promociones (púrpura)
- **sistema**: Sistema (gris)
- **pedido**: Pedidos (cyan)
- **inventario**: Inventario (naranja profundo)
- **venta**: Ventas (verde claro)

### Prioridades
- **baja**: Prioridad baja
- **normal**: Prioridad normal (por defecto)
- **alta**: Prioridad alta
- **urgente**: Prioridad urgente (badge rojo)

### Funcionalidades del Widget

#### Botón de Notificaciones
- Ícono que cambia según haya notificaciones no leídas
- Badge con contador de notificaciones no leídas
- Al hacer clic abre el panel de notificaciones

#### Panel de Notificaciones
- **Deslizable**: Panel que se puede arrastrar
- **Filtro**: Opción para mostrar solo no leídas
- **Marcar todas como leídas**: Botón para marcar todas
- **Swipe to dismiss**: Deslizar para eliminar notificaciones
- **Timeago**: Muestra tiempo relativo en español ("hace 5 minutos")
- **Estado vacío**: Mensaje cuando no hay notificaciones

#### Items de Notificación
- **Icono**: Según tipo de notificación
- **Color**: Según tipo de notificación
- **Badge urgente**: Para notificaciones urgentes
- **Indicador de no leída**: Punto de color
- **Tiempo relativo**: "hace X minutos/horas/días"

## 🔔 Uso del Servicio

### Crear Notificación (Solo Administradores)

```dart
final notificationService = NotificationService();

await notificationService.createNotification(
  userId: 'uuid-del-usuario',
  tipo: 'info',
  titulo: 'Nueva venta',
  mensaje: 'Se ha registrado una nueva venta de \$150.00',
  data: {
    'orden_id': 123,
    'monto': 150.00,
  },
  prioridad: 'normal',
  accion: '/orders/123', // Opcional: ruta de navegación
  icono: 'shopping_bag', // Opcional
  color: '#2196F3', // Opcional
  fechaExpiracion: DateTime.now().add(Duration(days: 7)), // Opcional
);
```

### Marcar como Leída

```dart
await notificationService.markAsRead(notificationId);
```

### Marcar Todas como Leídas

```dart
await notificationService.markAllAsRead();
```

### Eliminar Notificación

```dart
await notificationService.deleteNotification(notificationId);
```

### Escuchar Notificaciones

```dart
// Stream de notificaciones
notificationService.notificationsStream.listen((notifications) {
  print('Notificaciones: ${notifications.length}');
});

// Stream de contador de no leídas
notificationService.unreadCountStream.listen((count) {
  print('No leídas: $count');
});
```

## 🔐 Seguridad (RLS)

Las políticas de seguridad implementadas:

1. **SELECT**: Los usuarios solo pueden ver sus propias notificaciones
2. **UPDATE**: Los usuarios solo pueden actualizar sus propias notificaciones
3. **INSERT**: Solo administradores pueden crear notificaciones (o auto-notificaciones)
4. **DELETE**: Los usuarios pueden eliminar sus propias notificaciones

## 📡 Realtime

El sistema usa Supabase Realtime para actualizaciones en tiempo real:

- **INSERT**: Nueva notificación → Se agrega automáticamente a la lista
- **UPDATE**: Notificación actualizada → Se actualiza en la lista
- **DELETE**: Notificación eliminada → Se elimina de la lista

## 🎨 Personalización

### Colores por Tipo

Los colores se definen en `NotificationModel.getColor()`:

```dart
switch (tipo) {
  case NotificationType.alerta:
    return const Color(0xFFFF9800); // Naranja
  case NotificationType.info:
    return const Color(0xFF2196F3); // Azul
  // ... etc
}
```

### Iconos por Tipo

Los iconos se definen en `NotificationModel.getIcon()`:

```dart
switch (tipo) {
  case NotificationType.alerta:
    return Icons.warning_amber_rounded;
  case NotificationType.info:
    return Icons.info_outline_rounded;
  // ... etc
}
```

## 🧹 Mantenimiento

### Limpiar Notificaciones Expiradas

```dart
await notificationService.cleanExpiredNotifications();
```

Se recomienda ejecutar esto periódicamente (ej: diariamente) para eliminar notificaciones expiradas.

### Función RPC en Supabase

También puedes crear un cron job en Supabase para ejecutar automáticamente:

```sql
SELECT fn_limpiar_notificaciones_expiradas();
```

## 📊 Funciones RPC Disponibles

### `fn_crear_notificacion`
Crea una nueva notificación.

### `fn_marcar_notificacion_leida`
Marca una notificación como leída.

### `fn_marcar_todas_notificaciones_leidas`
Marca todas las notificaciones del usuario como leídas.

### `fn_obtener_notificaciones`
Obtiene notificaciones del usuario con paginación y filtros.

### `fn_limpiar_notificaciones_expiradas`
Elimina notificaciones expiradas.

## 🐛 Troubleshooting

### Las notificaciones no aparecen en tiempo real

1. Verificar que Realtime esté habilitado en Supabase:
   ```sql
   ALTER PUBLICATION supabase_realtime ADD TABLE public.app_dat_notificaciones;
   ```

2. Verificar que el servicio esté inicializado:
   ```dart
   _notificationService.initialize();
   ```

### Error de permisos al crear notificaciones

Verificar las políticas RLS en Supabase. El usuario debe tener rol de administrador o estar creando una auto-notificación.

### El contador no se actualiza

Verificar que el stream esté siendo escuchado correctamente:
```dart
StreamBuilder<int>(
  stream: _notificationService.unreadCountStream,
  // ...
)
```

## 📝 Ejemplos de Uso

### Notificación de Venta
```dart
await notificationService.createNotification(
  userId: userId,
  tipo: 'venta',
  titulo: 'Nueva venta registrada',
  mensaje: 'Venta de \$${monto} completada exitosamente',
  prioridad: 'normal',
  accion: '/orders/${orderId}',
);
```

### Notificación de Inventario Bajo
```dart
await notificationService.createNotification(
  userId: userId,
  tipo: 'inventario',
  titulo: 'Stock bajo',
  mensaje: 'El producto "${productName}" tiene solo ${cantidad} unidades',
  prioridad: 'alta',
  accion: '/inventory/${productId}',
);
```

### Notificación Urgente
```dart
await notificationService.createNotification(
  userId: userId,
  tipo: 'alerta',
  titulo: 'Acción requerida',
  mensaje: 'Se requiere tu aprobación para procesar el pedido #${orderId}',
  prioridad: 'urgente',
  accion: '/orders/${orderId}/approve',
);
```

## 📱 Notificaciones Push Locales (Android)

### Características:
- ✅ **Aparecen en la barra de notificaciones** de Android
- ✅ **Notificaciones emergentes** (heads-up) para prioridad alta/urgente
- ✅ **Vibración y sonido** automáticos
- ✅ **Colores personalizados** según tipo de notificación
- ✅ **Texto expandible** con BigTextStyle
- ✅ **Permisos solicitados automáticamente** en Android 13+

### Permisos Configurados:
```xml
POST_NOTIFICATIONS - Mostrar notificaciones
VIBRATE - Vibración
RECEIVE_BOOT_COMPLETED - Persistencia después de reinicio
SCHEDULE_EXACT_ALARM - Alarmas exactas
USE_EXACT_ALARM - Uso de alarmas exactas
```

### Funcionamiento Automático:
1. Nueva notificación llega desde Supabase (Realtime)
2. `NotificationService` la recibe y procesa
3. `LocalNotificationService` muestra notificación push automáticamente
4. Usuario ve la notificación en:
   - Barra de notificaciones de Android
   - Como emergente (si es urgente/alta)
   - En el widget de notificaciones de la app

### Primera Ejecución:
- La app solicitará permiso de notificaciones
- El usuario debe **ACEPTAR** para ver notificaciones push
- Si se rechaza, solo verán notificaciones dentro de la app

### Prueba Rápida:
```sql
-- Crear notificación urgente (aparecerá como emergente)
SELECT fn_crear_notificacion(
  'TU_USER_UUID'::UUID,
  'alerta',
  '⚠️ Prueba de Notificación',
  'Esta es una notificación push de prueba',
  '{}'::jsonb,
  'urgente'
);
```

📖 **Documentación Completa**: Ver `NOTIFICACIONES_PUSH_SETUP.md` para detalles técnicos.

## 🎯 Próximos Pasos

1. **Ejecutar el script SQL** en Supabase
2. **Ejecutar `flutter clean && flutter pub get`** para instalar dependencias
3. **Compilar y ejecutar** en dispositivo Android
4. **Aceptar permisos** de notificaciones cuando se soliciten
5. **Probar el sistema** creando notificaciones de prueba
6. **Integrar en más pantallas** según necesidad
7. **Configurar cron job** para limpiar notificaciones expiradas

## ✅ Checklist de Implementación

### Base de Datos:
- [ ] Script SQL ejecutado en Supabase
- [ ] Tabla `app_dat_notificaciones` creada
- [ ] Realtime habilitado
- [ ] RLS policies configuradas

### Dependencias:
- [ ] Ejecutado `flutter pub get`
- [ ] Ejecutado `flutter clean`
- [ ] Dependencia `timeago` instalada
- [ ] Dependencia `flutter_local_notifications` instalada

### Configuración Android:
- [ ] Permisos agregados en AndroidManifest.xml
- [ ] Receivers configurados en AndroidManifest.xml
- [ ] Ejecutado `./gradlew clean` en carpeta android

### Integración:
- [ ] Servicio inicializado en pantallas
- [ ] Widget agregado en AppBar
- [ ] App compilada y ejecutada en dispositivo Android

### Pruebas:
- [ ] Permisos de notificaciones aceptados
- [ ] Probado crear notificación
- [ ] Notificación aparece en barra de Android ✨
- [ ] Notificación aparece como emergente (urgente) ✨
- [ ] Probado marcar como leída
- [ ] Probado eliminar notificación
- [ ] Verificado realtime funcionando

## 📚 Recursos

- [Supabase Realtime Docs](https://supabase.com/docs/guides/realtime)
- [Supabase RLS Docs](https://supabase.com/docs/guides/auth/row-level-security)
- [Flutter StreamBuilder](https://api.flutter.dev/flutter/widgets/StreamBuilder-class.html)
- [Timeago Package](https://pub.dev/packages/timeago)
- [Flutter Local Notifications](https://pub.dev/packages/flutter_local_notifications)
- [Android Notifications Guide](https://developer.android.com/develop/ui/views/notifications)

---

**Sistema de Notificaciones con Push Locales - VentIQ Seller App** 🔔🚀
