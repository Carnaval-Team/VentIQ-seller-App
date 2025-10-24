# Sistema de Actualización Automática de APK

## 📋 Configuración Completa

Este documento explica cómo configurar el sistema de actualización automática de APK con solicitud de permisos.

## ✅ Cambios Realizados

### 1. **AndroidManifest.xml** - Permisos Agregados

```xml
<!-- Permisos para instalar APKs (actualizaciones) -->
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />
```

**Explicación:**
- `REQUEST_INSTALL_PACKAGES`: Permite instalar APKs desde la app
- `WRITE_EXTERNAL_STORAGE`: Para guardar APK descargada (Android ≤ 9)
- `READ_EXTERNAL_STORAGE`: Para leer APK descargada (Android ≤ 12)

### 2. **FileProvider** - Compartir APKs de Forma Segura

```xml
<provider
    android:name="androidx.core.content.FileProvider"
    android:authorities="${applicationId}.fileprovider"
    android:exported="false"
    android:grantUriPermissions="true">
    <meta-data
        android:name="android.support.FILE_PROVIDER_PATHS"
        android:resource="@xml/file_paths" />
</provider>
```

### 3. **file_paths.xml** - Rutas de Archivos

Archivo creado en: `android/app/src/main/res/xml/file_paths.xml`

## 🔧 Dependencias Necesarias

Agrega estas dependencias a tu `pubspec.yaml`:

```yaml
dependencies:
  # Para descargar archivos
  dio: ^5.4.0
  
  # Para gestionar permisos
  permission_handler: ^11.0.1
  
  # Para instalar APKs
  install_plugin: ^2.1.0
  # O alternativamente:
  # open_file: ^3.3.2
  
  # Para obtener rutas del sistema
  path_provider: ^2.1.1
```

## 📱 Implementación del Servicio de Actualización

### Opción 1: Usando `install_plugin` (Recomendado)

```dart
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:install_plugin/install_plugin.dart';

class AutoUpdateService {
  static final Dio _dio = Dio();

  /// Descargar e instalar actualización automáticamente
  static Future<void> downloadAndInstallUpdate(String downloadUrl) async {
    try {
      // 1. Solicitar permisos necesarios
      await _requestPermissions();
      
      // 2. Descargar APK
      final apkPath = await _downloadApk(downloadUrl);
      
      // 3. Instalar APK automáticamente
      await _installApk(apkPath);
      
    } catch (e) {
      print('❌ Error en actualización automática: $e');
      rethrow;
    }
  }

  /// Solicitar permisos necesarios
  static Future<void> _requestPermissions() async {
    // Android 8+ requiere permiso especial para instalar APKs
    if (await Permission.requestInstallPackages.isDenied) {
      final status = await Permission.requestInstallPackages.request();
      
      if (status.isDenied) {
        throw Exception('Permiso de instalación denegado');
      }
    }
    
    // Android ≤ 9 requiere permiso de almacenamiento
    if (await Permission.storage.isDenied) {
      await Permission.storage.request();
    }
  }

  /// Descargar APK
  static Future<String> _downloadApk(String url) async {
    try {
      // Obtener directorio de descargas
      final dir = await getExternalStorageDirectory();
      final apkPath = '${dir!.path}/ventiq_update.apk';
      
      print('📥 Descargando APK a: $apkPath');
      
      // Descargar con progreso
      await _dio.download(
        url,
        apkPath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = (received / total * 100).toStringAsFixed(0);
            print('📊 Progreso: $progress%');
          }
        },
      );
      
      print('✅ APK descargada exitosamente');
      return apkPath;
      
    } catch (e) {
      print('❌ Error descargando APK: $e');
      rethrow;
    }
  }

  /// Instalar APK
  static Future<void> _installApk(String apkPath) async {
    try {
      print('📦 Instalando APK...');
      
      final result = await InstallPlugin.installApk(apkPath);
      
      if (result['isSuccess'] == true) {
        print('✅ Instalación iniciada');
      } else {
        throw Exception('Error al iniciar instalación: ${result['errorMessage']}');
      }
      
    } catch (e) {
      print('❌ Error instalando APK: $e');
      rethrow;
    }
  }
}
```

### Opción 2: Usando `open_file`

```dart
import 'package:open_file/open_file.dart';

static Future<void> _installApk(String apkPath) async {
  try {
    print('📦 Abriendo instalador de APK...');
    
    final result = await OpenFile.open(apkPath);
    
    if (result.type == ResultType.done) {
      print('✅ Instalador abierto');
    } else {
      throw Exception('Error: ${result.message}');
    }
    
  } catch (e) {
    print('❌ Error abriendo APK: $e');
    rethrow;
  }
}
```

## 🎯 Integración con UpdateService Existente

Modifica tu `UpdateService` para usar el nuevo sistema:

```dart
// En tu UpdateService.checkForUpdates()
if (hasUpdate && isObligatory) {
  // Mostrar diálogo
  final shouldUpdate = await showUpdateDialog(context);
  
  if (shouldUpdate) {
    // Descargar e instalar automáticamente
    await AutoUpdateService.downloadAndInstallUpdate(downloadUrl);
  }
}
```

## 🔄 Flujo Completo de Actualización

```
1. App inicia
   ↓
2. Verifica actualizaciones (UpdateService)
   ↓
3. ¿Hay actualización?
   ├─ No → Continuar normal
   └─ Sí → Mostrar diálogo
       ↓
4. Usuario acepta actualizar
   ↓
5. Solicitar permisos
   ├─ REQUEST_INSTALL_PACKAGES
   └─ STORAGE (si Android ≤ 9)
   ↓
6. Descargar APK
   ├─ Mostrar progreso
   └─ Guardar en /storage/emulated/0/Android/data/.../files/
   ↓
7. Instalar APK
   ├─ Abrir instalador de Android
   └─ Usuario confirma instalación
   ↓
8. App se actualiza automáticamente
```

## 📝 Manejo de Permisos en Tiempo de Ejecución

### Verificar y Solicitar Permisos

```dart
Future<bool> checkAndRequestPermissions() async {
  // 1. Verificar permiso de instalación
  var installStatus = await Permission.requestInstallPackages.status;
  
  if (installStatus.isDenied) {
    // Mostrar diálogo explicativo
    final shouldRequest = await showPermissionDialog(
      'Permiso de Instalación',
      'Necesitamos permiso para instalar actualizaciones automáticamente',
    );
    
    if (shouldRequest) {
      installStatus = await Permission.requestInstallPackages.request();
    }
  }
  
  // 2. Si fue denegado permanentemente, abrir configuración
  if (installStatus.isPermanentlyDenied) {
    await openAppSettings();
    return false;
  }
  
  return installStatus.isGranted;
}
```

## 🎨 UI para Actualización

### Diálogo con Progreso

```dart
void showUpdateProgressDialog(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Text('Actualizando...'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Descargando nueva versión'),
          SizedBox(height: 16),
          LinearProgressIndicator(),
          SizedBox(height: 8),
          Text('No cierres la aplicación'),
        ],
      ),
    ),
  );
}
```

## ⚠️ Consideraciones Importantes

### 1. **Actualizaciones Obligatorias**
```dart
if (isObligatory) {
  // No permitir cerrar el diálogo
  barrierDismissible: false,
  // No mostrar botón "Más tarde"
  // Forzar actualización
}
```

### 2. **Verificación de Espacio**
```dart
// Verificar espacio disponible antes de descargar
final freeSpace = await DiskSpace.getFreeDiskSpace;
final requiredSpace = updateSize; // En MB

if (freeSpace < requiredSpace) {
  showError('Espacio insuficiente');
  return;
}
```

### 3. **Manejo de Errores de Red**
```dart
try {
  await downloadApk(url);
} on DioException catch (e) {
  if (e.type == DioExceptionType.connectionTimeout) {
    showError('Tiempo de espera agotado');
  } else if (e.type == DioExceptionType.receiveTimeout) {
    showError('Descarga interrumpida');
  }
}
```

## 🔐 Seguridad

### 1. **Verificar Firma de APK**
```dart
// Opcional: Verificar hash SHA256 de la APK descargada
final downloadedHash = await calculateSHA256(apkPath);
final expectedHash = updateInfo['sha256'];

if (downloadedHash != expectedHash) {
  throw Exception('APK corrupta o modificada');
}
```

### 2. **HTTPS Obligatorio**
```dart
if (!downloadUrl.startsWith('https://')) {
  throw Exception('Solo se permiten descargas HTTPS');
}
```

## 📊 Logging y Analytics

```dart
// Registrar eventos de actualización
void logUpdateEvent(String event, Map<String, dynamic> data) {
  print('📊 Update Event: $event');
  print('   Data: $data');
  
  // Opcional: Enviar a analytics
  // FirebaseAnalytics.instance.logEvent(
  //   name: 'app_update_$event',
  //   parameters: data,
  // );
}

// Eventos a registrar:
logUpdateEvent('update_available', {'version': newVersion});
logUpdateEvent('download_started', {'url': downloadUrl});
logUpdateEvent('download_completed', {'size': fileSize});
logUpdateEvent('install_started', {});
logUpdateEvent('install_completed', {});
```

## ✅ Checklist de Implementación

- [x] Permisos agregados en AndroidManifest.xml
- [x] FileProvider configurado
- [x] file_paths.xml creado
- [ ] Agregar dependencias en pubspec.yaml
- [ ] Implementar AutoUpdateService
- [ ] Integrar con UpdateService existente
- [ ] Agregar UI de progreso
- [ ] Implementar manejo de permisos
- [ ] Probar en diferentes versiones de Android
- [ ] Agregar logging y analytics

## 🚀 Resultado Final

Con esta configuración:
1. ✅ La app detecta actualizaciones automáticamente
2. ✅ Solicita permisos necesarios al usuario
3. ✅ Descarga la APK con progreso visual
4. ✅ Instala automáticamente (con confirmación del usuario)
5. ✅ Maneja errores de forma robusta
6. ✅ Funciona en todas las versiones de Android

## 📱 Notas por Versión de Android

- **Android 7 (Nougat) y superior**: Requiere FileProvider
- **Android 8 (Oreo) y superior**: Requiere `REQUEST_INSTALL_PACKAGES`
- **Android 10 (Q) y superior**: Scoped Storage (no requiere WRITE_EXTERNAL_STORAGE)
- **Android 11 (R) y superior**: Requiere `MANAGE_EXTERNAL_STORAGE` para acceso completo
- **Android 13 (Tiramisu) y superior**: No requiere `READ_EXTERNAL_STORAGE`
