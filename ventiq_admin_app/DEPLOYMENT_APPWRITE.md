# Deployment en Appwrite - VentIQ Admin App

## Problema Solucionado: "Page not found"

El error "Page not found" en Appwrite ocurre porque las aplicaciones Flutter web son Single Page Applications (SPA) que manejan el routing del lado del cliente. Cuando un usuario navega directamente a una URL como `/dashboard` o `/products`, el servidor busca un archivo físico que no existe.

## Archivos Creados para Solucionar el Problema:

### 1. `web/_redirects` (Para Netlify/Appwrite)
```
/*    /index.html   200
```
Este archivo redirige todas las rutas al `index.html` para que Flutter pueda manejar el routing.

### 2. `web/.htaccess` (Para servidores Apache)
```apache
RewriteEngine On
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule ^.*$ /index.html [L]
```

### 3. `appwrite.json` (Configuración de proyecto)
Configuración específica para Appwrite con:
- Configuración de hosting estático
- Comando de build optimizado
- Directorio de build correcto
- Patrones de archivos a ignorar

### 4. Mejoras en `index.html`
- Configuración específica para Appwrite
- Manejo de CanvasKit para producción
- Base href configurado correctamente

### 5. Mejoras en `main.dart`
- Manejo robusto de rutas no encontradas
- Configuración específica para web
- Redirección automática al splash en rutas inválidas

## Pasos para Deployment en Appwrite:

### 1. Build de la Aplicación
```bash
flutter build web --release --web-renderer html
```

### 2. Configurar Appwrite CLI
```bash
npm install -g appwrite-cli
appwrite login
```

### 3. Inicializar Proyecto
```bash
appwrite init project
```

### 4. Deploy
```bash
appwrite deploy
```

## Configuraciones Importantes:

### Build Command:
```bash
flutter build web --release --web-renderer html
```

### Build Directory:
```
build/web
```

### Redirects Configuration:
Asegúrate de que Appwrite esté configurado para redirigir todas las rutas a `index.html`.

## Verificación Post-Deployment:

1. **Ruta raíz (`/`)**: Debe cargar el SplashScreen
2. **Rutas directas** (`/dashboard`, `/products`): Deben funcionar correctamente
3. **Rutas inválidas**: Deben redirigir al SplashScreen
4. **Navegación interna**: Debe funcionar sin problemas

## Troubleshooting:

### Si sigue apareciendo "Page not found":
1. Verificar que el archivo `_redirects` esté en `build/web/_redirects`
2. Confirmar que Appwrite reconoce las reglas de redirect
3. Revisar la configuración de hosting en Appwrite
4. Verificar que el build se completó correctamente

### Logs útiles:
- Revisar console del navegador para errores de JavaScript
- Verificar Network tab para requests fallidos
- Confirmar que todos los assets se cargan correctamente

## Archivos Modificados:
- ✅ `web/index.html`: Configuración para Appwrite
- ✅ `lib/main.dart`: Manejo robusto de rutas
- ✅ `web/_redirects`: Reglas de redirect
- ✅ `web/.htaccess`: Fallback para Apache
- ✅ `appwrite.json`: Configuración de proyecto
