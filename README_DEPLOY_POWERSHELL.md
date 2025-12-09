# Script de Build y Deploy - PowerShell

## 🚀 Uso Rápido

```powershell
# Ejemplo para VentIQ App (vendedor)
.\build_and_deploy.ps1 -AppFolder "ventiq_app" -ApkName "vendedor cuba"

# Ejemplo para VentIQ Admin
.\build_and_deploy.ps1 -AppFolder "ventiq_admin_app" -ApkName "admin cuba"

# Ejemplo para VentIQ SuperAdmin
.\build_and_deploy.ps1 -AppFolder "ventiq_superadmin" -ApkName "superadmin cuba"
```

## ✨ Características

### 🔧 Automatización Completa
- ✅ Build de APK en modo release
- ✅ Renombrado automático
- ✅ Lectura de configuración de Supabase desde `lib/config/supabase_config.dart`
- ✅ Upload a Supabase Storage
- ✅ **Eliminación automática del archivo antiguo**
- ✅ **Renombrado automático del archivo nuevo**
- ✅ Lectura y reporte de `changelog.json`

### 📊 Diferencias con la Versión Bash

| Característica | Bash | PowerShell |
|----------------|------|------------|
| Plataforma | Git Bash (Windows/Linux/Mac) | Windows PowerShell |
| Lectura Config | Manual | **Automática desde .dart** |
| Upload | Supabase CLI | **API REST directa** |
| Eliminación | Manual | **Automática** |
| Renombrado | Manual | **Automático** |
| Progreso | CLI progress | PowerShell progress |

## 🔑 Configuración de Supabase

### Opción 1: Lectura Automática (Recomendada)
El script lee automáticamente la configuración de:
```
[carpeta_app]/lib/config/supabase_config.dart
```

Debe contener:
```dart
const String supabaseUrl = 'https://tu-proyecto.supabase.co';
const String supabaseAnonKey = 'tu-anon-key';
```

### Opción 2: Variables de Entorno (Fallback)
Si no encuentra el archivo de configuración, usa variables de entorno:
```powershell
$env:SUPABASE_URL = "https://tu-proyecto.supabase.co"
$env:SUPABASE_ANON_KEY = "tu-anon-key"
```

## 📋 Requisitos

1. **Flutter instalado** y en el PATH
2. **PowerShell 5.1+** (incluido en Windows 10/11)
3. **Acceso a Internet** para upload a Supabase
4. **Configuración de Supabase** (ver arriba)

## 🎯 Proceso del Script

### Paso 1: Build del APK ⚙️
```
Compilando APK en modo release...
✅ APK compilado exitosamente
```

### Paso 2: Renombrar APK 📝
```
Renombrando APK...
✅ APK renombrado a: vendedor cuba.apk
```

### Paso 3: Leer Configuración 🔑
```
Leyendo configuración de Supabase...
✅ URL de Supabase encontrada
✅ Anon Key de Supabase encontrada
```

### Paso 4: Subir a Supabase ☁️
```
Subiendo APK a Supabase bucket 'apk'...
ℹ️  Tamaño del archivo: 45.23 MB
✅ APK subido exitosamente a Supabase
```

### Paso 5: Gestionar Archivos 🗂️
```
Gestionando archivos en el bucket...
✅ Archivo antiguo eliminado
✅ Archivo renombrado correctamente
```

### Paso 6: Reporte Final 📊
```
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
ℹ️  APK disponible en Supabase Storage: apk/vendedor cuba.apk
```

## 🛠️ Solución de Problemas

### Error: "No se puede ejecutar el script"
Habilitar ejecución de scripts en PowerShell:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Error: "No se encontró la carpeta"
Verifica que el nombre de la carpeta sea exacto:
- `ventiq_app` (no ~~VentIQ-App~~)
- `ventiq_admin_app`
- `ventiq_superadmin`

### Error: "No se pudo obtener la configuración de Supabase"
1. Verifica que existe `lib/config/supabase_config.dart`
2. O configura variables de entorno:
```powershell
$env:SUPABASE_URL = "https://tu-proyecto.supabase.co"
$env:SUPABASE_ANON_KEY = "tu-anon-key"
```

### Error durante la subida
- Verifica tu conexión a Internet
- Asegúrate de que el bucket `apk` existe en Supabase
- Verifica que la Anon Key tiene permisos de escritura

### Advertencia: "No se encontró archivo antiguo"
Esto es normal si es la primera vez que subes esa APK. El script continúa normalmente.

## 📝 Notas Importantes

### Permisos del Bucket Supabase
Asegúrate de que el bucket `apk` en Supabase tenga los permisos correctos:

**Políticas RLS recomendadas:**
```sql
-- INSERT policy
CREATE POLICY "Allow public uploads" ON storage.objects
FOR INSERT TO public
WITH CHECK (bucket_id = 'apk');

-- DELETE policy
CREATE POLICY "Allow public deletes" ON storage.objects
FOR DELETE TO public
USING (bucket_id = 'apk');

-- UPDATE policy (para rename)
CREATE POLICY "Allow public updates" ON storage.objects
FOR UPDATE TO public
USING (bucket_id = 'apk');
```

### Limpieza de Builds
Para limpiar builds antiguos y liberar espacio:
```powershell
cd ventiq_app
flutter clean
```

### Tamaño del APK
El APK típicamente tiene:
- **Sin ofuscación**: 40-60 MB
- **Con ofuscación**: 20-30 MB

Para reducir tamaño, en `build.gradle`:
```gradle
buildTypes {
    release {
        minifyEnabled true
        shrinkResources true
    }
}
```

## 🔄 Comparación con Bash Script

| Aspecto | Bash (build_and_deploy.sh) | PowerShell (build_and_deploy.ps1) |
|---------|---------------------------|-----------------------------------|
| **Plataforma** | Cross-platform (Git Bash) | Windows nativo |
| **Sintaxis** | `./script.sh arg1 arg2` | `-AppFolder "..." -ApkName "..."` |
| **Config Supabase** | Manual en script | Auto desde .dart |
| **API Supabase** | CLI (requiere instalación) | REST (built-in) |
| **Gestión archivos** | Manual | **Totalmente automática** |
| **Progreso** | Texto | Progress bars nativos |
| **Dependencias** | Supabase CLI, jq | Ninguna extra |

## ✅ Ventajas del Script PowerShell

1. **No requiere Supabase CLI** - Usa API REST directamente
2. **Config automática** - Lee desde `supabase_config.dart`
3. **Totalmente automatizado** - Elimina y renombra archivos
4. **Nativo en Windows** - No necesita Git Bash
5. **Mejor manejo de errores** - Try-catch robusto
6. **Progress nativo** - Mejor visualización

## 🎓 Ejemplos de Uso

### Build simple
```powershell
.\build_and_deploy.ps1 -AppFolder "ventiq_app" -ApkName "test"
```

### Build para producción
```powershell
.\build_and_deploy.ps1 -AppFolder "ventiq_app" -ApkName "vendedor cuba v1.7.9"
```

### Build con nombre largo
```powershell
.\build_and_deploy.ps1 -AppFolder "ventiq_admin_app" -ApkName "Admin Panel Cuba December 2025"
```

## 📞 Soporte

Si encuentras problemas:
1. Verifica que Flutter esté instalado: `flutter --version`
2. Verifica configuración de Supabase en `lib/config/supabase_config.dart`
3. Revisa los permisos del bucket en Supabase Dashboard
4. Verifica tu conexión a Internet

## 🎉 ¡Listo para Usar!

El script está completo y listo para automatizar tus builds. Solo ejecuta:

```powershell
.\build_and_deploy.ps1 -AppFolder "ventiq_app" -ApkName "vendedor cuba"
```
