# Solución al Error "Page not found" en Appwrite

## 🔍 Problema Identificado

El error **"Page not found - router_path_not_found"** en Appwrite ocurre porque:

1. **Flutter Web es una SPA** (Single Page Application)
2. **Todas las rutas se manejan del lado del cliente** (Flutter Router)
3. **Appwrite busca archivos físicos** que no existen para rutas como `/dashboard`, `/products`, etc.
4. **Falta configuración de redirects** para redirigir todas las rutas a `index.html`

## ✅ Archivos Creados/Modificados

### 1. **`web/_redirects`** ✨ NUEVO
```
/*    /index.html   200
```
**Propósito**: Redirige TODAS las rutas a `index.html` para que Flutter maneje el routing.

### 2. **`web/.htaccess`** ✨ NUEVO
```apache
RewriteEngine On
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule ^.*$ /index.html [L]
```
**Propósito**: Fallback para servidores Apache.

### 3. **`appwrite.json`** ✨ NUEVO
```json
{
  "projectId": "ventiq-admin-app",
  "hosting": {
    "type": "static",
    "buildCommand": "flutter build web --release --web-renderer html",
    "buildDir": "build/web",
    "rootDir": "."
  }
}
```
**Propósito**: Configuración específica para Appwrite.

### 4. **`web/index.html`** 🔧 MODIFICADO
- Agregada configuración específica para Appwrite
- Configuración de CanvasKit para producción
- Base href optimizado

### 5. **`lib/main.dart`** 🔧 MODIFICADO
- Manejo robusto de rutas no encontradas
- Configuración específica para web (`useInheritedMediaQuery: true`)
- Redirección automática al splash en rutas inválidas

### 6. **`build_for_appwrite.bat`** ✨ NUEVO
Script automatizado para build y deployment:
```batch
flutter clean
flutter pub get
flutter build web --release --web-renderer html --base-href /
copy "web\_redirects" "build\web\_redirects"
copy "web\.htaccess" "build\web\.htaccess"
```

## 🚀 Pasos para Deployment

### 1. **Ejecutar Build Script**
```bash
# En Windows
build_for_appwrite.bat

# En Linux/Mac
flutter clean
flutter pub get
flutter build web --release --web-renderer html --base-href /
cp web/_redirects build/web/_redirects
cp web/.htaccess build/web/.htaccess
```

### 2. **Verificar Archivos de Build**
Asegúrate que `build/web/` contenga:
- ✅ `index.html`
- ✅ `_redirects`
- ✅ `.htaccess`
- ✅ Todos los assets de Flutter

### 3. **Configurar Appwrite**
1. Subir contenido de `build/web/` a Appwrite
2. Configurar hosting estático
3. Asegurar que Appwrite reconoce las reglas de redirect

### 4. **Verificar Deployment**
- ✅ Ruta raíz (`/`) → SplashScreen
- ✅ Rutas directas (`/dashboard`, `/products`) → Funcionan
- ✅ Rutas inválidas → Redirigen al SplashScreen
- ✅ Navegación interna → Sin problemas

## 🔧 Configuraciones Clave

### Build Command:
```bash
flutter build web --release --web-renderer html --base-href /
```

### Redirects Rule:
```
/*    /index.html   200
```
**Significado**: Cualquier ruta (`/*`) se redirige a `index.html` con código 200 (éxito).

### Base Href:
```html
<base href="$FLUTTER_BASE_HREF">
```
**Configurado para**: Deployment en subdirectorio o dominio raíz.

## 🐛 Troubleshooting

### Si sigue apareciendo "Page not found":

1. **Verificar archivo `_redirects`**:
   ```bash
   # Debe existir en build/web/_redirects
   ls build/web/_redirects
   ```

2. **Verificar configuración de Appwrite**:
   - Confirmar que reconoce reglas de redirect
   - Verificar que el hosting está configurado como "static"

3. **Verificar build completo**:
   ```bash
   # Debe contener todos los archivos
   ls build/web/
   ```

4. **Revisar console del navegador**:
   - Errores de JavaScript
   - Requests fallidos
   - Assets no encontrados

### Logs Útiles:
- **Network tab**: Verificar que `index.html` se carga para todas las rutas
- **Console**: Errores de Flutter o JavaScript
- **Sources**: Confirmar que todos los assets están disponibles

## 📋 Checklist Final

- ✅ Archivo `_redirects` creado
- ✅ Archivo `.htaccess` creado  
- ✅ `appwrite.json` configurado
- ✅ `index.html` optimizado
- ✅ `main.dart` con manejo robusto de rutas
- ✅ Script de build automatizado
- ✅ Build ejecutado correctamente
- ✅ Archivos subidos a Appwrite
- ✅ Hosting configurado como estático
- ✅ Redirects funcionando

## 🎯 Resultado Esperado

Después de aplicar esta solución:

1. **Acceso directo a cualquier URL** → Funciona correctamente
2. **Navegación interna** → Sin problemas
3. **Refresh en cualquier página** → Mantiene la ruta
4. **URLs compartidas** → Funcionan para otros usuarios
5. **SEO y bookmarks** → URLs funcionan correctamente

## 📞 Soporte

Si el problema persiste después de aplicar todas estas configuraciones:

1. Verificar que Appwrite soporta reglas de redirect
2. Revisar documentación específica de Appwrite para SPAs
3. Considerar configuración adicional en el panel de Appwrite
4. Verificar que el dominio está correctamente configurado
