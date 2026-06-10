# VentIQ Marketplace — Referencia completa de Backend (Supabase)

> Documento generado a partir del código fuente de la app `ventiq_marketplace`.
> Recoge **todas** las peticiones a Supabase (RPC, consultas a tablas, storage, realtime, auth),
> los parámetros que se envían y lo que devuelven, las credenciales, los servicios externos
> y el catálogo completo de funciones públicas de cada servicio de la app.

---

## 1. Credenciales y configuración

### 1.1 Supabase
| Clave | Valor |
|-------|-------|
| **URL** | `https://vsieeihstajlrdvpuooh.supabase.co` |
| **REST base** | `https://vsieeihstajlrdvpuooh.supabase.co/rest/v1` |
| **RPC base** | `https://vsieeihstajlrdvpuooh.supabase.co/rest/v1/rpc` |
| **Project ref** | `vsieeihstajlrdvpuooh` |
| **API Key (anonKey en código)** | `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZzaWVlaWhzdGFqbHJkdnB1b29oIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1NDUzMjIwNiwiZXhwIjoyMDcwMTA4MjA2fQ.d9fKCcunP_J0tdlZF8eg0vAD-bsK3XfemavnZWT3Ro8` |

> ⚠️ **ALERTA DE SEGURIDAD CRÍTICA:** El JWT incluido en `lib/config/supabase_config.dart` tiene
> `"role": "service_role"`, **no** `anon`. La `service_role` key **omite todas las políticas RLS**
> y otorga acceso administrativo total a la base de datos. Está embebida en una app cliente (incluida
> en builds web/APK), por lo que es **públicamente extraíble**. Debe reemplazarse por la `anon` key
> y rotarse la `service_role` cuanto antes.

**Headers usados en peticiones REST directas (curl/HTTP):**
```
apikey: <SUPABASE_KEY>
Authorization: Bearer <SUPABASE_KEY>
Content-Type: application/json
```

Fuente: `lib/config/supabase_config.dart`, `lib/main.dart` (`Supabase.initialize`).

### 1.2 Storage
| Recurso | Valor |
|---------|-------|
| **Bucket de imágenes** | `images_back` (público) |
| **URL de descarga APK** | `https://vsieeihstajlrdvpuooh.supabase.co/storage/v1/object/public/apk/inventtia%20catalogo.apk` |

### 1.3 Schema alternativo
- Tabla de repartidores vive en el schema **`carnavalapp`** (no `public`): `carnavalapp.posicion_repartidor`.

### 1.4 Servicio externo: WhatsApp (Whapi.cloud)
| Clave | Valor |
|-------|-------|
| **Base URL** | `https://gate.whapi.cloud` |
| **Token (Bearer)** | `YPte4ulIx1BMjjlYP3msg3XkfKVvDcBv` |

> ⚠️ El token de Whapi también está hardcodeado en `lib/services/whapi_service.dart` y es extraíble del cliente.

### 1.5 Identificadores fijos en código
| Constante | Valor | Dónde |
|-----------|-------|-------|
| `_fixedUserId` (usuario por defecto para ratings) | `9c7afeaa-6135-44c5-a943-42cad8f81b05` | `rating_service.dart` |
| `appName` (actividad usuario) | `inventtia_catalgo` | `user_activity_service.dart` |
| `app_name` (changelog/updates) | `ventiq_marketplace` | `update_service.dart` |
| `_defaultTpvId` | `1` | `store_management_service.dart` |
| `_defaultPresentacionId` | `1` | `store_management_service.dart` |

---

## 2. Funciones RPC de Supabase

Total: **10 RPC** distintas invocadas desde la app.

### 2.1 `get_productos_marketplace`
- **Servicio:** `MarketplaceService.getProducts()` (`marketplace_service.dart:37`)
- **Descripción:** Búsqueda/listado principal de productos del marketplace con filtros y búsqueda fonética (sin acentos).
- **Parámetros enviados:**
  | Param | Tipo | Default | Descripción |
  |-------|------|---------|-------------|
  | `id_tienda_param` | bigint \| null | null | Filtra por tienda (null = todas) |
  | `id_categoria_param` | bigint \| null | null | Filtra por categoría (null = todas) |
  | `solo_disponibles_param` | bool | false | true = solo con stock > 0 |
  | `search_query_param` | text \| null | null | Texto de búsqueda (nombre, desc, SKU, código barras, categoría, subcategoría, tienda) |
  | `limit_param` | int | 50 | Máx. resultados (hasta 500) |
  | `offset_param` | int | 0 | Paginación |
- **Devuelve:** `List<Map>` de productos. Campos:
  `id_producto, sku, denominacion, descripcion, um, es_refrigerado, es_fragil, es_vendible, codigo_barras, id_subcategoria, subcategoria_nombre, id_categoria, categoria_nombre, precio_venta, imagen, stock_disponible, tiene_stock, metadata{ es_elaborado, es_servicio, denominacion_tienda, id_tienda, ubicacion, direccion, provincia, municipio, rating_promedio, total_ratings, presentaciones[] }`

### 2.2 `get_detalle_producto_marketplace`
- **Servicio:** `ProductDetailService.getProductDetail()` (`product_detail_service.dart:49`)
- **Descripción:** Detalle completo de un producto (datos, inventario por ubicación, presentaciones, multimedia).
- **Parámetros:**
  | Param | Tipo | Requerido |
  |-------|------|-----------|
  | `id_producto_param` | bigint | sí |
- **Devuelve:** `jsonb` objeto: `{ producto{ id, denominacion, descripcion, foto, precio_actual, es_refrigerado, es_fragil, es_peligroso, es_elaborado, es_servicio, id_tienda, categoria{id,denominacion}, multimedias[], presentaciones[] }, inventario[]{ id_inventario, sku_producto, cantidad_disponible, precio, variante, presentacion, ubicacion } }`
- **Nota:** Si `producto.id_tienda` viene null, la app lo recupera con un SELECT a `app_dat_producto`.

### 2.3 `get_tienda_estado_tpvs`
- **Servicio:** `MarketplaceService.getStoreTPVsStatus()` (`marketplace_service.dart:220`)
- **Descripción:** Estado abierto/cerrado de las cajas (TPV) de una tienda.
- **Parámetros:**
  | Param | Tipo | Requerido |
  |-------|------|-----------|
  | `id_tienda_param` | bigint | sí |
- **Devuelve:** `List<Map>`: `id_tpv, denominacion_tpv, esta_abierto, fecha_apertura, fecha_cierre`

### 2.4 `fn_get_productos_recomendados_v2`
- **Servicio:** `MarketplaceService.getRecommendedProducts()` (`marketplace_service.dart:302`)
- **Descripción:** Recomendaciones personalizadas según suscripciones, rating, reseñas y stock.
- **Parámetros:**
  | Param | Tipo | Default | Descripción |
  |-------|------|---------|-------------|
  | `id_usuario_param` | uuid | — | UUID del usuario autenticado (`auth.currentUser.id`) |
  | `limit_param` | int | 50 (la app pasa 20) | Máx. productos |
  | `offset_param` | int | 0 | Paginación |
- **Devuelve:** `List<Map>` con la misma estructura que `get_productos_marketplace`.

### 2.5 `fn_get_productos_mas_vendidos`
- **Servicio:** `ProductService.getMostSoldProducts()` (`product_service.dart:22`)
- **Parámetros:**
  | Param | Tipo | Default |
  |-------|------|---------|
  | `p_limit` | int | 10 |
  | `p_id_categoria` | bigint \| null | null |
- **Devuelve:** `List<Map>` de productos más vendidos.

### 2.6 `fn_get_productos_mas_recientes`
- **Servicio:** `ProductService.getMostRecent()` (`product_service.dart:57`)
- **Parámetros:**
  | Param | Tipo | Default |
  |-------|------|---------|
  | `p_limit` | int | 10 |
  | `p_id_categoria` | bigint \| null | null |
- **Devuelve:** `List<Map>` de productos más recientes.

### 2.7 `fn_productos_relacionados`
- **Servicio:** `ProductDetailService.getRelatedProducts()` (`product_detail_service.dart:18`)
- **Parámetros:**
  | Param | Tipo | Default |
  |-------|------|---------|
  | `id_producto_param` | bigint | — |
  | `limit_param` | int | 10 |
  | `offset_param` | int | 0 |
- **Devuelve:** `List<Map>` de productos relacionados.

### 2.8 `fn_get_tiendas_destacadas`
- **Servicio:** `StoreService.getFeaturedStores()` (`store_service.dart:17`)
- **Parámetros:**
  | Param | Tipo | Default |
  |-------|------|---------|
  | `p_limit` | int | 10 |
- **Devuelve:** `List<Map>` de tiendas destacadas.

### 2.9 `fn_check_update`
- **Servicio:** `UpdateService.checkForUpdates()` (`update_service.dart:35`)
- **Parámetros:**
  | Param | Tipo | Descripción |
  |-------|------|-------------|
  | `p_app_name` | text | Nombre app (de `assets/changelog.json`, default `ventiq_marketplace`) |
  | `p_version_actual` | text | Versión actual |
  | `p_build_actual` | int | Build actual |
- **Devuelve:** `Map` con info de actualización; incluye `hay_actualizacion` (bool) y la app agrega `current_version`, `current_build`, `app_name`.

### 2.10 `fn_upsert_actividad_usuario`
- **Servicio:** `UserActivityService.registerAccess()` (`user_activity_service.dart:91`)
- **Descripción:** Registra/actualiza la actividad de acceso del usuario (incluye invitados con token UUID generado localmente).
- **Parámetros:**
  | Param | Tipo | Descripción |
  |-------|------|-------------|
  | `p_token` | text | UUID del usuario autenticado o token de invitado |
  | `p_app` | text | `inventtia_catalgo` |
- **Devuelve:** (sin uso del retorno).

---

## 3. Consultas directas a tablas (PostgREST)

### 3.1 Lectura

| Tabla | Operación | Servicio / línea | Select / filtros | Devuelve |
|-------|-----------|------------------|------------------|----------|
| `app_dat_producto` | SELECT single | `ProductService.getProductDetails` `:88` | `id, denominacion, descripcion, imagen, es_vendible, id_tienda, app_dat_tienda!inner(id,denominacion,ubicacion)`; `eq(id)`, `mostrar_en_catalogo=true`, `deleted_at is null` | Producto con tienda |
| `app_dat_producto` | SELECT | `ProductService.searchProducts` `:216` | `id, denominacion, descripcion, imagen, app_dat_precio_venta!left(precio_venta,precio_oferta,tiene_oferta)`; `ilike denominacion`, `deleted_at is null`, `es_vendible=true`, `limit` | Productos buscados |
| `app_dat_producto` | SELECT | `StoreService.getStoreProducts` `:88` | igual a anterior + `eq(id_tienda)`, `range(offset)` | Productos de tienda |
| `app_dat_producto` | SELECT | `StoreService.getStoreCategories` `:178` | `app_dat_categoria!inner(id,denominacion,descripcion,image)`; `eq(id_tienda)`, `mostrar_en_catalogo=true`, `deleted_at is null` | Categorías de tienda |
| `app_dat_producto` | SELECT | `StoreService.getStoreStats` `:217` | `id`; `eq(id_tienda)`, `deleted_at is null` | Conteo productos |
| `app_dat_producto` | SELECT (id_tienda) | `ProductDetailService` `:67` | `id_tienda`; `eq(id)` | Fallback id_tienda |
| `app_dat_producto` | SELECT count | `main_screen` `:206` | `id`; `eq(id_tienda)`, `deleted_at is null`, `es_vendible=true`, `count(exact)` | Nº productos vendibles |
| `app_dat_producto_presentacion` | SELECT | `ProductService.getProductPresentations` `:123` | `id, id_producto, id_presentacion, cantidad, es_base, app_nom_presentacion!inner(id,denominacion,descripcion,sku_codigo)`; `eq(id_producto)`, `order es_base desc` | Presentaciones |
| `app_dat_precio_venta` | SELECT maybeSingle | `ProductService.getProductPrice` `:154` | `*`; `eq(id_producto)`, `order created_at desc`, `limit 1` | Precio vigente |
| `app_dat_producto_rating` | SELECT | `ProductService.getProductRating` `:180` / `ProductDetailService._getProductRating` `:97` | `rating`; `eq(id_producto)` | Ratings para promediar |
| `app_dat_inventario_productos` | SELECT | `ProductService.getProductStock` `:247` | `cantidad_final`; `eq(id_producto)`, `gt(cantidad_final,0)` | Stock sumado |
| `app_dat_categoria` | SELECT | `CategoryService.getAllCategories` `:13` | `id, denominacion, descripcion, image, app_dat_categoria_tienda!inner(app_dat_tienda!inner(mostrar_en_catalogo))`; filtro `mostrar_en_catalogo=true`, `order denominacion` | Categorías visibles |
| `app_dat_categoria` | SELECT single | `CategoryService.getCategoryById` `:63` | `id, denominacion, descripcion, imagen`; `eq(id)` | Categoría por id |
| `app_dat_categoria` | SELECT | `StoreManagementService.getCatalogCategories` `:206` | `id, denominacion, image`; `para_catalogo=true`, `order denominacion` | Categorías de catálogo |
| `app_dat_tienda` | SELECT | `StoreService.getStoresWithLocation` `:46` | `id, denominacion, ubicacion, imagen_url, direccion, phone`; `mostrar_en_catalogo=true`, `ubicacion not null` | Tiendas para el mapa |
| `app_dat_tienda` | SELECT single | `StoreService.getStoreDetails` `:65` | `*`; `eq(id)` | Detalle tienda |
| `app_dat_tienda` | SELECT | `StoreService.searchStores` `:158` | `*`; `mostrar_en_catalogo=true`, `or(denominacion.ilike, ubicacion.ilike)`, `limit` | Búsqueda tiendas |
| `app_dat_tienda` | SELECT | `StoreManagementService.getStoresByIds` `:32` | `*`; `inFilter(id, ids)`, `order id` | Tiendas gestionadas |
| `app_dat_tienda` | SELECT maybeSingle | `store_detail_screen` `:251` | `phone`; `eq(id)` | Teléfono tienda |
| `app_dat_tienda_rating` | SELECT | `StoreService.getStoreRating` `:120` | `rating`; `eq(id_tienda)` | Ratings tienda |
| `app_dat_gerente` | SELECT | `StoreManagementService.getManagedStoreIds` `:11` | `id_tienda`; `eq(uuid)` | Tiendas que gestiona el usuario |
| `app_dat_gerente` | SELECT maybeSingle | `StoreManagementService.ensureGerenteLink` `:190` | `id`; `eq(uuid)`, `eq(id_tienda)` | Verifica vínculo gerente |
| `app_suscripciones` | SELECT maybeSingle | `StoreManagementService.createDefaultSubscription` `:88` | `id`; `eq(id_tienda)`, `limit 1` | Suscripción existente |
| `app_dat_subcategorias` | SELECT maybeSingle | `StoreManagementService.getFirstSubcategoryId` `:216` | `id`; `eq(idcategoria)`, `order id`, `limit 1` | Primera subcategoría |
| `app_dat_categoria_tienda` | SELECT maybeSingle | `StoreManagementService.ensureCategoriaTiendaLink` `:236` | `id`; `eq(id_tienda)`, `eq(id_categoria)` | Verifica vínculo categoría-tienda |
| `app_dat_producto` (overview) | SELECT | `StoreManagementService.getStoreProductsOverview` `:255` | `id, denominacion, imagen, mostrar_en_catalogo`; `eq(id_tienda)`, `deleted_at is null`, `order denominacion` | Listado productos gestión |
| `app_dat_precio_venta` (overview) | SELECT | `:275` | `id_producto, precio_venta_cup, fecha_desde`; `inFilter(id_producto)`, `order fecha_desde desc` | Precios por producto |
| `app_dat_producto_presentacion` (overview) | SELECT | `:295` | `id, id_producto`; `inFilter(id_producto)`, `es_base=true` | Presentación base |
| `app_dat_inventario_productos` (overview) | SELECT | `:317` | `id_producto, cantidad_final, created_at`; `inFilter(id_producto)`, `order created_at desc`, `limit 2000` | Stock por producto |
| `app_dat_producto` (detalle gestión) | SELECT single | `StoreManagementService.getProductManagementDetail` `:363` | `id, id_tienda, id_categoria, denominacion, imagen, mostrar_en_catalogo`; `eq(id)` | Detalle gestión |
| `app_dat_producto_presentacion` | SELECT maybeSingle | `:373` / `ensureBasePresentationId` `:419` | `id`; `eq(id_producto)`, `es_base=true`, `limit 1` | Presentación base |
| `app_dat_precio_venta` | SELECT maybeSingle | `:386` | `precio_venta_cup, fecha_desde`; `eq(id_producto)`, `order fecha_desde desc`, `limit 1` | Precio actual |
| `app_dat_inventario_productos` | SELECT maybeSingle | `:398` | `cantidad_final, created_at`; `eq(id_producto)`, `order created_at desc`, `limit 1` | Cantidad actual |
| `app_dat_productos_subcategorias` | SELECT maybeSingle | `:474` | `id`; `eq(id_producto)` | Subcategoría del producto |
| `app_dat_precio_venta` | SELECT maybeSingle | `upsertProductPriceForToday` `:620` | `id`; `eq(id_producto)`, `eq(fecha_desde)` | Precio del día |
| `app_dat_suscripcion_catalogo` | SELECT maybeSingle | `store_management_screen` `:667` | `id, created_at, tiempo_suscripcion, vencido`; `eq(id_tienda)`, `order created_at desc`, `limit 1` | Suscripción catálogo |
| `app_dat_preferencias_notificaciones` | SELECT maybeSingle | `NotificationService.syncNotificationConsentWithSupabase` `:446` | `estado, created_at, updated_at`; `eq(id_usuario)` | Consentimiento notif. |
| `app_dat_notificaciones` | SELECT | `NotificationService.loadNotifications` `:729` | `*`; `eq(user_id)`, opc. `eq(leida,false)`, `order created_at desc`, `range` | Notificaciones |
| `app_dat_suscripcion_notificaciones_tienda` | SELECT | `getStoreSubscriptions` `:887` / `isStoreSubscriptionActive` `:916` | `id, id_tienda, activo, app_dat_tienda(id,denominacion)` / `activo`; `eq(id_usuario)`, `eq(id_tienda)` | Suscripciones a tiendas |
| `app_dat_suscripcion_notificaciones_producto` | SELECT | `getProductSubscriptions` `:902` / `isProductSubscriptionActive` `:971` | `id, id_producto, activo, app_dat_producto(id,denominacion)` / `activo`; `eq(id_usuario)`, `eq(id_producto)` | Suscripciones a productos |
| `app_dat_tienda_rating` | SELECT maybeSingle | `RatingService.getUserStoreRating` `:78` | `*`; `eq(id_tienda)`, `eq(id_usuario)` | Rating previo del usuario |
| `app_dat_producto_rating` | SELECT maybeSingle | `RatingService.getUserProductRating` `:95` | `*`; `eq(id_producto)`, `eq(id_usuario)` | Rating previo del usuario |
| `carnavalapp.posicion_repartidor` | SELECT (schema `carnavalapp`) | `RepartidorService.getRepartidoresActivos` `:13` | `id, uuid, repartidor_id, nombre, latitud, longitud, ultima_actualizacion`; `order ultima_actualizacion desc` | Repartidores activos |

### 3.2 Escritura (INSERT / UPDATE / UPSERT / DELETE)

| Tabla | Operación | Servicio / línea | Datos |
|-------|-----------|------------------|-------|
| `app_dat_application_rating` | INSERT | `RatingService.submitAppRating` `:16` | `id_usuario, rating, comentario` |
| `app_dat_tienda_rating` | INSERT | `RatingService.submitStoreRating` `:36` | `id_tienda, id_usuario, rating, comentario` |
| `app_dat_producto_rating` | INSERT | `RatingService.submitProductRating` `:57` | `id_producto, id_usuario, rating, comentario` |
| `app_dat_tienda` | INSERT | `StoreManagementService.createStore` `:73` | `denominacion, direccion, ubicacion, imagen_url, phone, pais, estado, nombre_pais, nombre_estado, hora_apertura, hora_cierre, latitude, longitude, mostrar_en_catalogo=false, only_catalogo=true` → `select *` |
| `app_dat_tienda` | UPDATE | `StoreManagementService.updateStore` `:165` | mismos campos editables (sin flags catálogo) → `select *` |
| `app_dat_tienda` | UPDATE | `updateMostrarEnCatalogo` `:179` | `mostrar_en_catalogo`; `eq(id)` |
| `app_suscripciones` | INSERT | `createDefaultSubscription` `:108` | `id_tienda, id_plan=1, estado=2, creado_por, renovacion_automatica=false, observaciones` → `select *, app_suscripciones_plan(...)` |
| `app_dat_gerente` | INSERT | `ensureGerenteLink` `:198` | `uuid, id_tienda` |
| `app_dat_categoria_tienda` | INSERT | `ensureCategoriaTiendaLink` `:244` | `id_tienda, id_categoria` |
| `app_dat_producto` | INSERT | `createProductComplete` `:514` | `id_tienda, id_categoria, denominacion, nombre_comercial, denominacion_corta, um='u', es_vendible=true, imagen, mostrar_en_catalogo` → `select id` |
| `app_dat_producto` | UPDATE | `updateProductCategory` `:462` | `id_categoria`; `eq(id)` |
| `app_dat_producto` | UPDATE | `updateProductMostrarEnCatalogo` `:582` | `mostrar_en_catalogo`; `eq(id)` |
| `app_dat_producto` | UPDATE | `updateProductBasicInfo` `:592` | `denominacion, nombre_comercial, denominacion_corta`; `eq(id)` |
| `app_dat_producto` | UPDATE | `updateProductImage` `:606` | `imagen`; `eq(id)` |
| `app_dat_productos_subcategorias` | INSERT/UPDATE | `updateProductCategory` `:481/487`, `createProductComplete` `:535` | `id_producto, id_sub_categoria` |
| `app_dat_producto_presentacion` | INSERT | `ensureBasePresentationId` `:434`, `createProductComplete` `:541` | `id_producto, id_presentacion=1, cantidad=1, es_base=true` → `select id` |
| `app_dat_precio_venta` | INSERT | `createProductComplete` `:560`, `upsertProductPriceForToday` `:634` | `id_producto, fecha_desde (YYYY-MM-DD), precio_venta_cup` |
| `app_dat_precio_venta` | UPDATE | `upsertProductPriceForToday` `:627` | `precio_venta_cup`; `eq(id)` |
| `app_dat_inventario_productos` | INSERT | `createProductComplete` `:566`, `insertInventorySnapshot` `:647` | `id_producto, id_presentacion, cantidad_inicial, cantidad_final, origen_cambio=2` |
| `app_dat_preferencias_notificaciones` | UPSERT | `NotificationService._syncConsentToSupabase` `:861` | `id_usuario, estado`; `onConflict id_usuario` → `select created_at, updated_at` |
| `app_dat_notificaciones` | UPDATE | `markAsRead` `:758` | `leida=true`; `eq(id)` |
| `app_dat_notificaciones` | UPDATE | `markAllAsRead` `:785` | `leida=true`; `eq(user_id)`, `eq(leida,false)` |
| `app_dat_notificaciones` | DELETE | `deleteNotification` `:808` | `eq(id)` |
| `app_dat_suscripcion_notificaciones_tienda` | UPSERT | `toggleStoreSubscription` `:939` / `setStoreSubscriptionActive` `:957` | `id_usuario, id_tienda, activo`; `onConflict id_usuario,id_tienda` |
| `app_dat_suscripcion_notificaciones_producto` | UPSERT | `toggleProductSubscription` `:994` / `setProductSubscriptionActive` `:1012` | `id_usuario, id_producto, activo`; `onConflict id_usuario,id_producto` |

---

## 4. Storage

| Operación | Bucket | Servicio / pantalla | Detalle |
|-----------|--------|---------------------|---------|
| `uploadBinary` | `images_back` | `create_product_screen.dart:164`, `product_management_detail_screen.dart:222`, `store_management_screen.dart:1232` | Sube `product_<storeId>_<timestamp>.jpg`, `contentType image/jpeg, upsert true` |
| `getPublicUrl` | `images_back` | mismas pantallas (`:175 / :232 / :242`) | Devuelve URL pública de la imagen subida |

---

## 5. Realtime

- **Canal:** `marketplace_notifications_<userId>` (`NotificationService._subscribeToRealtimeUpdates` `:608`)
- **Tabla observada:** `public.app_dat_notificaciones`
- **Eventos:** `INSERT`, `UPDATE`, `DELETE` filtrados por `user_id = <uuid>`
- **Efecto:** Mantiene en memoria la lista de notificaciones y el contador de no leídas; muestra notificación local en INSERT.

---

## 6. Autenticación (Supabase Auth)

Servicio: `AuthService` (`auth_service.dart`).

| Método | Llamada Supabase | Parámetros | Notas |
|--------|------------------|------------|-------|
| `signInWithEmail` | `auth.signInWithPassword` | `email, password` | Guarda usuario en sesión local (`UserSessionService`) |
| `signUpWithEmail` | `auth.signUp` (+ `signInWithPassword` si no hay sesión) | `email, password, data{nombres, apellidos, telefono}` | Requiere desactivar confirmación de email en Supabase |
| `signOut` | `auth.signOut` | — | Limpia sesión local |
| `syncLocalUserFromSupabaseIfNeeded` | `auth.currentUser` | — | Rellena sesión local desde el usuario autenticado |
| `currentUser` (getter) | `auth.currentUser` | — | Usuario actual |

`auth.currentUser?.id` también se usa en `MarketplaceService.getRecommendedProducts`, `UserActivityService` y `NotificationService` para resolver el UUID.

---

## 7. Catálogo completo de funciones de la app (por servicio)

### `MarketplaceService` (`marketplace_service.dart`)
- `getProducts({idTienda, idCategoria, soloDisponibles, searchQuery, limit, offset})` — RPC `get_productos_marketplace`.
- `getAllProducts({soloDisponibles})` — atajo de `getProducts`.
- `getProductsByStore(storeId, {soloDisponibles})`
- `getProductsByCategory(categoryId, {soloDisponibles})`
- `getProductsByStoreAndCategory(storeId, categoryId, {soloDisponibles})`
- `getTopRatedProducts({minRating=4.0, limit=10})` — filtra/ordena en cliente por `metadata.rating_promedio`.
- `searchProducts(searchText, {idCategoria, limit=100})`
- `getLowStockProducts({maxStock=10})` — filtra en cliente.
- `getStoreTPVsStatus(storeId)` — RPC `get_tienda_estado_tpvs`.
- `getStoreStatistics(storeId)` — agrega totales/ratings en cliente.
- `getRecommendedProducts({limit=20, offset=0})` — RPC `fn_get_productos_recomendados_v2`.
- **Extension `ProductMetadata`:** getters `metadata, storeName, storeId, rating, totalRatings, isElaborado, isServicio, hasStock, stockDisponible`.

### `ProductService` (`product_service.dart`)
- `getMostSoldProducts({limit=10, categoryId})` — RPC `fn_get_productos_mas_vendidos`.
- `getMostRecent({limit=10, categoryId})` — RPC `fn_get_productos_mas_recientes`.
- `getProductDetails(productId)` — SELECT `app_dat_producto`.
- `getProductPresentations(productId)` — SELECT `app_dat_producto_presentacion`.
- `getProductPrice(productId)` — SELECT `app_dat_precio_venta`.
- `getProductRating(productId)` — SELECT `app_dat_producto_rating` (promedio + count).
- `searchProducts(query, {limit=20})` — SELECT `app_dat_producto`.
- `getProductStock(productId)` — SELECT `app_dat_inventario_productos`.

### `ProductDetailService` (`product_detail_service.dart`) — singleton
- `getRelatedProducts(productId, {limit=10, offset=0})` — RPC `fn_productos_relacionados`.
- `getProductDetail(productId)` — RPC `get_detalle_producto_marketplace` + transformación a modelo marketplace (calcula stock, presentaciones→variantes, rating).
- `_getProductRating(productId)` (privado) — SELECT `app_dat_producto_rating`.
- `_transformToMarketplaceProduct(...)` (privado) — normaliza el resultado.

### `StoreService` (`store_service.dart`)
- `getFeaturedStores({limit=10})` — RPC `fn_get_tiendas_destacadas`.
- `getStoresWithLocation()` — SELECT `app_dat_tienda` (para mapa).
- `getStoreDetails(storeId)` — SELECT `app_dat_tienda`.
- `getStoreProducts(storeId, {limit=20, offset=0})` — SELECT `app_dat_producto`.
- `getStoreRating(storeId)` — SELECT `app_dat_tienda_rating`.
- `searchStores(query, {limit=20})` — SELECT `app_dat_tienda`.
- `getStoreCategories(storeId)` — SELECT `app_dat_producto` join `app_dat_categoria`.
- `getStoreStats(storeId)` — conteo productos + rating.

### `CategoryService` (`category_service.dart`)
- `getAllCategories()` — SELECT `app_dat_categoria` (solo de tiendas visibles).
- `getCategoryById(categoryId)` — SELECT `app_dat_categoria`.

### `RatingService` (`rating_service.dart`)
- `submitAppRating({rating, comentario, userId})` — INSERT `app_dat_application_rating`.
- `submitStoreRating({storeId, rating, comentario, userId})` — INSERT `app_dat_tienda_rating`.
- `submitProductRating({productId, rating, comentario, userId})` — INSERT `app_dat_producto_rating`.
- `getUserStoreRating(storeId, {userId})` — SELECT `app_dat_tienda_rating`.
- `getUserProductRating(productId, {userId})` — SELECT `app_dat_producto_rating`.
- Usa `_fixedUserId = 9c7afeaa-6135-44c5-a943-42cad8f81b05` si no se pasa `userId`.

### `StoreManagementService` (`store_management_service.dart`)
- `getManagedStoreIds({uuid})` — SELECT `app_dat_gerente`.
- `getStoresByIds(storeIds)` — SELECT `app_dat_tienda`.
- `createStore({...})` — INSERT `app_dat_tienda`.
- `createDefaultSubscription(idTienda, creadoPor)` — verifica + INSERT `app_suscripciones`.
- `updateStore({...})` — UPDATE `app_dat_tienda`.
- `updateMostrarEnCatalogo({storeId, mostrarEnCatalogo})` — UPDATE.
- `ensureGerenteLink({uuid, storeId})` — INSERT condicional `app_dat_gerente`.
- `getCatalogCategories()` — SELECT `app_dat_categoria`.
- `getFirstSubcategoryId({categoryId})` — SELECT `app_dat_subcategorias`.
- `ensureCategoriaTiendaLink({storeId, categoryId})` — INSERT condicional `app_dat_categoria_tienda`.
- `getStoreProductsOverview({storeId, tpvId})` — combina productos + precios + presentaciones + stock.
- `getProductManagementDetail({productId, tpvId})` — detalle para gestión.
- `ensureBasePresentationId({productId})` — obtiene/crea presentación base.
- `updateProductCategory({productId, storeId, categoryId})` — UPDATE + vínculos.
- `createProductComplete({storeId, categoryId, name, imageUrl, priceCup, initialQuantity, storeAllowsCatalog})` — flujo completo de alta de producto.
- `updateProductMostrarEnCatalogo({productId, mostrarEnCatalogo})`
- `updateProductBasicInfo({productId, name})`
- `updateProductImage({productId, imageUrl})`
- `upsertProductPriceForToday({productId, priceCup, tpvId})`
- `insertInventorySnapshot({productId, basePresentationId, currentQuantity, newQuantity})`

### `NotificationService` (`notification_service.dart`) — singleton
- `initialize()` / `requestSystemNotificationPermission()`
- `saveNotificationConsent({status})`
- `initializeUserNotifications({force})`
- `syncNotificationConsentWithSupabase()` — SELECT/UPSERT `app_dat_preferencias_notificaciones`.
- `clearUserNotifications()`
- `loadNotifications({limit=50, offset=0, onlyUnread=false})` — SELECT `app_dat_notificaciones`.
- `markAsRead(notificationId)` / `markAllAsRead()` — UPDATE.
- `deleteNotification(notificationId)` — DELETE.
- `getStoreSubscriptions()` / `getProductSubscriptions()` — SELECT.
- `isStoreSubscriptionActive({storeId})` / `isProductSubscriptionActive({productId})`
- `toggleStoreSubscription({storeId})` / `setStoreSubscriptionActive({storeId, active})`
- `toggleProductSubscription({productId})` / `setProductSubscriptionActive({productId, active})`
- `showTestNotification({title, body})`
- Realtime: `_subscribeToRealtimeUpdates(userId)` + streams `notificationsStream`, `unreadCountStream`.

### `RepartidorService` (`repartidor_service.dart`) — singleton
- `getRepartidoresActivos()` — SELECT `carnavalapp.posicion_repartidor`.
- Consumido por `RepartidorMapMixin` (refresca cada 30 s al activar el toggle en el mapa).

### `UpdateService` (`update_service.dart`) — estático
- `getCurrentVersionInfo()` — lee `assets/changelog.json`.
- `checkForUpdates()` — RPC `fn_check_update`.
- `downloadUrl` (const) — APK pública.

### `UserActivityService` (`user_activity_service.dart`)
- `resolveAccessMode()` — determina usuario auth / sesión / invitado (genera token UUID local).
- `registerAccess()` — RPC `fn_upsert_actividad_usuario`.
- Clase auxiliar `AccessModeInfo` (`token, isLoggedIn, displayName, email, friendlyName`).

### `AuthService` (`auth_service.dart`)
- Ver sección 6.

### `UserSessionService` (`user_session_service.dart`) — solo local (SharedPreferences, clave `marketplace_user`)
- `saveUser({uuid, email, nombres, apellidos, telefono})`
- `getUser()` / `getUserId()` / `isLoggedIn()` / `clear()`

### `ChangelogService` (`changelog_service.dart`) — solo local
- `loadChangelogs()` / `getLatestChangelog()` — lee `assets/changelog.json`.

### `WhapiService` (`whapi_service.dart`) — API externa WhatsApp
- `acceptGroupInvite(inviteCode)` — `PUT /groups`.
- `getGroups({count=100, offset=0})` — `GET /groups`.
- `sendImageMessage({to, caption, mediaUrl})` — `POST /messages/image`.
- `sendTextMessage({to, body})` — `POST /messages/text`.
- `dispose()`

### Otros servicios (sin acceso a red / utilitarios)
- `CartService` — carrito local.
- `RoutingService` — cálculo de rutas (OpenRouteService, según memoria del proyecto).
- `UserPreferencesService` — preferencias locales (incl. estado de consentimiento de notificaciones).
- `AppNavigationService` — navegación global (`navigatorKey`).
- `CatalogQrPrintService` (+ stub/web) — impresión de QR del catálogo.

---

## 8. Resumen de tablas referenciadas

`app_dat_producto`, `app_dat_producto_presentacion`, `app_nom_presentacion`, `app_dat_precio_venta`,
`app_dat_inventario_productos`, `app_dat_producto_rating`, `app_dat_categoria`, `app_dat_subcategorias`,
`app_dat_categoria_tienda`, `app_dat_productos_subcategorias`, `app_dat_tienda`, `app_dat_tienda_rating`,
`app_dat_application_rating`, `app_dat_gerente`, `app_suscripciones`, `app_suscripciones_plan`,
`app_dat_suscripcion_catalogo`, `app_dat_preferencias_notificaciones`, `app_dat_notificaciones`,
`app_dat_suscripcion_notificaciones_tienda`, `app_dat_suscripcion_notificaciones_producto`,
`carnavalapp.posicion_repartidor`.
