# 🚀 Guía de Despliegue en Appwrite - VentIQ Admin App

## Problema
Error: `router_path_not_found` - La aplicación Flutter Web no carga en el dominio de Appwrite.

## Causa
Appwrite no está configurado para servir aplicaciones SPA (Single Page Application). Cuando navegas a rutas como `/dashboard` o `/products`, el servidor intenta buscar archivos físicos en lugar de servir `index.html`.

## Soluciones

### ✅ Solución 1: Usar `.htaccess` (Si Appwrite usa Apache)

1. **Verificar que `.htaccess` existe:**
   ```
   ventiq_admin_app/web/.htaccess
   ```

2. **Contenido del archivo:**
   ```apache
   <IfModule mod_rewrite.c>
     RewriteEngine On
     RewriteCond %{REQUEST_FILENAME} !-f
     RewriteCond %{REQUEST_FILENAME} !-d
     RewriteRule ^ index.html [QSA,L]
   </IfModule>
   ```

3. **Pasos en Appwrite:**
   - Ir a Storage → Buckets
   - Crear un bucket llamado `ventiq-admin-web`
   - Subir todos los archivos de `build/web/`
   - **Importante:** Incluir el archivo `.htaccess`

### ✅ Solución 2: Usar Nginx (Si Appwrite usa Nginx)

1. **Verificar que `nginx.conf` existe:**
   ```
   ventiq_admin_app/nginx.conf
   ```

2. **En Appwrite:**
   - Ir a Settings → Domains
   - Crear un nuevo dominio personalizado
   - Configurar el servidor Nginx con el archivo `nginx.conf`

3. **Configuración clave:**
   ```nginx
   location / {
       try_files $uri $uri/ /index.html;
   }
   ```

### ✅ Solución 3: Configurar en Appwrite Console

1. **Crear una función Appwrite:**
   - Ir a Functions → Create Function
   - Seleccionar Node.js
   - Crear una función que sirva archivos estáticos

2. **O usar Static Files:**
   - Ir a Storage → Buckets
   - Crear bucket `ventiq-admin-web`
   - Habilitar "Public Access"
   - Subir carpeta `build/web/`

## 🔧 Pasos Recomendados

### Paso 1: Preparar el Build
```bash
cd ventiq_admin_app
flutter clean
flutter pub get
flutter build web --release
```

### Paso 2: Verificar Archivos
```
build/web/
├── index.html          ✅ Principal
├── flutter_bootstrap.js
├── main.dart.js
├── assets/
├── icons/
└── .htaccess           ✅ Agregar si no existe
```

### Paso 3: Subir a Appwrite

**Opción A: Via Appwrite Console**
1. Storage → Buckets → Create Bucket
2. Nombre: `ventiq-admin-web`
3. Permissions: Public
4. Upload folder: `build/web/`

**Opción B: Via Appwrite CLI**
```bash
appwrite storage createBucket \
  --bucketId ventiq-admin-web \
  --name "VentIQ Admin Web" \
  --permission file \
  --encrypt false

appwrite storage uploadFile \
  --bucketId ventiq-admin-web \
  --file build/web/
```

### Paso 4: Configurar Dominio

1. Ir a Settings → Domains
2. Crear nuevo dominio personalizado
3. Apuntar DNS a Appwrite
4. Esperar validación SSL

### Paso 5: Probar

```
https://tu-dominio.com/          ✅ Debe cargar
https://tu-dominio.com/dashboard ✅ Debe cargar
https://tu-dominio.com/products  ✅ Debe cargar
https://tu-dominio.com/login     ✅ Debe cargar
```

## 🐛 Troubleshooting

### Error: "Page not found"
- ✅ Verificar que `.htaccess` está en `build/web/`
- ✅ Verificar que `index.html` existe
- ✅ Verificar permisos del bucket

### Error: "router_path_not_found"
- ✅ Configurar rewrite rules
- ✅ Reiniciar servidor Appwrite
- ✅ Limpiar caché del navegador

### Error: "404 Not Found"
- ✅ Verificar que todos los archivos se subieron
- ✅ Verificar permisos de lectura
- ✅ Verificar que el dominio apunta correctamente

## 📋 Checklist Final

- [ ] `flutter build web --release` ejecutado
- [ ] `.htaccess` o `nginx.conf` configurado
- [ ] Archivos subidos a Appwrite Storage
- [ ] Dominio personalizado configurado
- [ ] DNS apuntando a Appwrite
- [ ] SSL certificado válido
- [ ] Prueba de ruta raíz: `/`
- [ ] Prueba de ruta con parámetros: `/dashboard`
- [ ] Prueba de recarga de página (F5)
- [ ] Prueba en navegador privado

## 🔗 Recursos

- [Appwrite Docs - Static Files](https://appwrite.io/docs/products/storage)
- [Flutter Web Deployment](https://flutter.dev/docs/deployment/web)
- [SPA Routing Configuration](https://developer.mozilla.org/en-US/docs/Glossary/SPA)

## 💡 Notas

- Flutter Web es una SPA, necesita rewrite rules
- Todos los archivos deben estar en `build/web/`
- El archivo `.htaccess` debe estar en la raíz
- Limpiar caché después de cambios
- Usar HTTPS en producción
