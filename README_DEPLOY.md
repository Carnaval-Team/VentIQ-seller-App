# Script de Build y Deploy - Guía de Uso

## Requisitos Previos

### 1. Instalar Supabase CLI
```bash
npm install -g supabase
```

### 2. Instalar jq (opcional, mejora el parsing de JSON)
**Windows (Git Bash):**
```bash
# Descargar desde: https://stedolan.github.io/jq/download/
# O usar chocolatey:
choco install jq
```

**Linux/Mac:**
```bash
sudo apt install jq  # Ubuntu/Debian
brew install jq      # macOS
```

### 3. Configurar Supabase (para automatización completa)
Edita el script y añade tus credenciales:
```bash
SUPABASE_URL="https://tu-proyecto.supabase.co"
SUPABASE_KEY="tu-service-role-key"
```

## Uso del Script

### Sintaxis básica
```bash
./build_and_deploy.sh <carpeta_app> <nombre_apk>
```

### Ejemplos

**Build para VentIQ App (vendedor):**
```bash
./build_and_deploy.sh ventiq_app "vendedor cuba"
```

**Build para VentIQ Admin:**
```bash
./build_and_deploy.sh ventiq_admin_app "admin cuba"
```

**Build para VentIQ SuperAdmin:**
```bash
./build_and_deploy.sh ventiq_superadmin "superadmin cuba"
```

## Proceso del Script

El script realiza los siguientes pasos automáticamente:

### ✅ Paso 1: Build del APK
- Navega a la carpeta de la app
- Ejecuta `flutter build apk --release`
- Valida que el build sea exitoso

### ✅ Paso 2: Renombrar APK
- Copia `app-release.apk` con el nuevo nombre
- Ejemplo: `vendedor cuba.apk`

### ✅ Paso 3: Subir a Supabase
- Sube el APK al bucket `apk` en Supabase
- Muestra el progreso de subida
- Reporta el tamaño del archivo

### ⚠️ Paso 4: Gestión de archivos
**Actualmente requiere pasos manuales:**
1. Ir a Supabase Dashboard > Storage > apk
2. Eliminar el archivo antiguo (mismo nombre)
3. Renombrar `nombre (1).apk` a `nombre.apk`

**Para automatizar (opcional):**
Descomentar y configurar las secciones de API REST en el script:
```bash
SUPABASE_URL="tu-proyecto.supabase.co"
SUPABASE_KEY="tu-service-role-key"
```

### ✅ Paso 5: Reporte final
- Lee `assets/changelog.json`
- Muestra versión, build y detalles del APK

## Ejemplo de Salida

```
ℹ️  Iniciando proceso de build y deploy para ventiq_app

ℹ️  PASO 1/5: Compilando APK en modo release...
✅ APK compilado exitosamente

ℹ️  PASO 2/5: Renombrando APK...
✅ APK renombrado a: vendedor cuba.apk

ℹ️  PASO 3/5: Subiendo APK a Supabase bucket 'apk'...
ℹ️  Tamaño del archivo: 45.23 MB
✅ APK subido exitosamente

ℹ️  PASO 4/5: Gestionando archivos en el bucket...
⚠️  Este paso requiere configuración adicional de Supabase

ℹ️  PASO 5/5: Leyendo información de la versión...

╔════════════════════════════════════════════════════════════╗
║                    BUILD COMPLETADO                        ║
╠════════════════════════════════════════════════════════════╣
║  App:      ventiq_app
║  Versión:  1.7.9
║  Build:    709
║  APK:      vendedor cuba.apk
║  Tamaño:   45.23 MB
╚════════════════════════════════════════════════════════════╝

✅ Proceso completado exitosamente!
```

## Solución de Problemas

### Error: "Supabase CLI no está instalado"
```bash
npm install -g supabase
```

### Error: "jq no está instalado" (advertencia)
El script funciona sin jq, pero es más lento. Instálalo para mejor rendimiento.

### Error: "La carpeta no existe"
Verifica que el nombre de la carpeta sea correcto:
- `ventiq_app`
- `ventiq_admin_app`
- `ventiq_superadmin`

### Permisos en Git Bash (Windows)
```bash
chmod +x build_and_deploy.sh
```

## Notas

- El script valida cada paso antes de continuar
- Si algo falla, se detiene inmediatamente
- Los APK temporales se mantienen en `build/app/outputs/flutter-apk/`
- Para limpiar builds antiguos: `flutter clean`
