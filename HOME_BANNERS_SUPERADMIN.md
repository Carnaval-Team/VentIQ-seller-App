# Home banners — gestión desde Superadmin

Banners del **carrusel del inicio** en la app Carnaval (`carnavalAPP`). Independientes de `configuraciones_admin.banner_principal*`.

## 1. Aplicar SQL (Supabase)

Ejecutar en el proyecto Supabase (schema `carnavalapp`):

`carnavalAPP/sql_updates/rpc-api/20_home_banners.sql`

Crea:

| Objeto | Uso |
|--------|-----|
| Tabla `carnavalapp.home_banners` | Datos del carrusel |
| `fn_home_banners_list()` | App cliente (solo `activo=true`) |
| `fn_admin_home_banners_list()` | Superadmin: listar todos |
| `fn_admin_home_banners_upsert(...)` | Superadmin: crear / editar |
| `fn_admin_home_banners_delete(id, hard?)` | Soft (`activo=false`) o hard delete |

RLS: sin acceso directo a la tabla; lectura/escritura vía RPCs.

## 2. Modelo de datos

| Campo | Tipo | Obligatorio | Notas |
|-------|------|-------------|-------|
| `id` | bigint | auto | PK |
| `image_url` | text | sí | URL pública de la imagen |
| `link` | text | no | Ruta interna o `https://…` |
| `descripcion` | text | no | Texto / accesibilidad / overlay |
| `orden` | int | sí (default 0) | Menor = primero en el carrusel |
| `activo` | bool | sí (default true) | `false` = oculto en la app |
| `created_at` / `updated_at` | timestamptz | auto | |

## 3. Imágenes (Storage)

Recomendado:

1. Bucket público existente (p. ej. `imagenes` / `productos`) o uno nuevo `home-banners`.
2. Upload desde superadmin → obtener URL pública → guardar en `image_url`.
3. Relación de aspecto del carrusel en app: **16:7** (aprox. landscape). Preferir ~1200×525 o similar.

## 4. Campo `link` (ejemplos)

| Valor | Comportamiento en app |
|-------|------------------------|
| vacío / null | No navega (o se ignora el tap) |
| `https://…` | Abre URL externa |
| `/search?categoryId=14` | Búsqueda filtrada por categoría |
| `/search?proveedorId=3` | Búsqueda filtrada por tienda |
| `/regalos` | Pantalla de regalos |
| `/listadoTiendas` | Listado de tiendas |
| `/novedades` | Novedades |
| `/categories` | Lista de categorías |
| `/vistaCafeterias` | Cafeterías |

## 5. UI Superadmin (checklist)

Pantalla sugerida: **Marketing → Banners inicio**

- [ ] Listado ordenable (drag o campo `orden`)
- [ ] Toggle `activo`
- [ ] Form create/edit: upload imagen → `image_url`, `link`, `descripcion`, `orden`
- [ ] Preview de la imagen
- [ ] Soft-delete (desactivar) + opción hard-delete
- [ ] Llamadas RPC (schema `carnavalapp`):
  - `fn_admin_home_banners_list`
  - `fn_admin_home_banners_upsert` con params `p_id`, `p_image_url`, `p_link`, `p_descripcion`, `p_orden`, `p_activo`
  - `fn_admin_home_banners_delete` con `p_id`, `p_hard`

### Ejemplo upsert (crear)

```json
{
  "p_id": null,
  "p_image_url": "https://….supabase.co/storage/v1/object/public/imagenes/banners/promo1.jpg",
  "p_link": "/search?categoryId=14",
  "p_descripcion": "Ofertas de la semana",
  "p_orden": 10,
  "p_activo": true
}
```

### Ejemplo upsert (editar)

```json
{
  "p_id": 1,
  "p_image_url": null,
  "p_link": "/novedades",
  "p_descripcion": "Novedades",
  "p_orden": 5,
  "p_activo": true
}
```

(`p_image_url` null en update = no cambia la imagen.)

## 6. Seguridad

- Hoy los grants admin van a `authenticated`. En prod, el superadmin debe:
  - validar rol admin en la app, **o**
  - restringir grants a `service_role` / rol DB específico y llamar desde backend.
- No exponer hard-delete a usuarios no admin.

## 7. App cliente

- RPC: `fn_home_banners_list`
- Widget: carrusel encima de los 4 botones del inicio
- Tap: `openBannerLink(context, link)`

## 8. Smoke test

1. Insertar 2–3 banners activos con `orden` distinto.
2. Abrir app → inicio → ver carrusel en el orden esperado.
3. Tap con link interno → navega.
4. `activo=false` → desaparece del carrusel tras refresh.
