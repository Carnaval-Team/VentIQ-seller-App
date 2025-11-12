# 🚀 Configuración del Ícono de Launcher - Inventtia

Este documento explica cómo configurar el ícono de launcher de la aplicación Inventtia Marketplace.

## 📋 Requisitos

- Flutter instalado
- Archivo `assets/launcher.png` presente en el proyecto

## 🔧 Pasos para Configurar el Ícono

### 1. Instalar las dependencias

Primero, ejecuta este comando para instalar el paquete `flutter_launcher_icons`:

```bash
flutter pub get
```

### 2. Generar los íconos

Ejecuta el siguiente comando para generar automáticamente todos los íconos en las diferentes resoluciones:

```bash
flutter pub run flutter_launcher_icons
```

Este comando:
- ✅ Genera íconos para todas las densidades de Android (mdpi, hdpi, xhdpi, xxhdpi, xxxhdpi)
- ✅ Crea íconos adaptativos con el fondo azul (#4A90E2)
- ✅ Usa `assets/launcher.png` como imagen fuente

### 3. Verificar los cambios

Después de ejecutar el comando, deberías ver mensajes como:

```
✓ Successfully generated launcher icons
```

Los íconos se generarán en:
- `android/app/src/main/res/mipmap-mdpi/ic_launcher.png`
- `android/app/src/main/res/mipmap-hdpi/ic_launcher.png`
- `android/app/src/main/res/mipmap-xhdpi/ic_launcher.png`
- `android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png`
- `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png`

### 4. Probar la aplicación

Para ver el nuevo ícono en tu dispositivo:

```bash
# Limpiar el proyecto
flutter clean

# Reinstalar la app
flutter run
```

**⚠️ Importante**: Si ya tenías la app instalada, es posible que necesites desinstalarla primero para ver el nuevo ícono:

```bash
# Desinstalar la app anterior
adb uninstall com.example.ventiq_marketplace

# Instalar con el nuevo ícono
flutter run
```

## 🎨 Configuración Actual

El archivo `pubspec.yaml` está configurado con:

```yaml
flutter_launcher_icons:
  android: true
  ios: false
  image_path: "assets/launcher.png"
  adaptive_icon_background: "#4A90E2"  # Color azul del tema
  adaptive_icon_foreground: "assets/launcher.png"
```

### Opciones de Configuración:

- **android**: `true` - Genera íconos para Android
- **ios**: `false` - No genera íconos para iOS (por ahora)
- **image_path**: Ruta al archivo de imagen fuente
- **adaptive_icon_background**: Color de fondo para íconos adaptativos de Android 8.0+
- **adaptive_icon_foreground**: Imagen de primer plano para íconos adaptativos

## 📱 Resultado

Después de seguir estos pasos, tu app mostrará:
- ✅ El logo de Inventtia como ícono en el launcher
- ✅ Ícono adaptativo con fondo azul en Android 8.0+
- ✅ Íconos optimizados para todas las densidades de pantalla

## 🔄 Actualizar el Ícono en el Futuro

Si necesitas cambiar el ícono más adelante:

1. Reemplaza el archivo `assets/launcher.png`
2. Ejecuta nuevamente: `flutter pub run flutter_launcher_icons`
3. Reinstala la app

## 📚 Más Información

- [Documentación de flutter_launcher_icons](https://pub.dev/packages/flutter_launcher_icons)
- [Guía de íconos adaptativos de Android](https://developer.android.com/guide/practices/ui_guidelines/icon_design_adaptive)
