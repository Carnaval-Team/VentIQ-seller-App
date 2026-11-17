# Spec: ventiq-marketplace (Inventtia Catálogo)

Línea base as-built de `ventiq_marketplace` solamente. Describe lo que el catálogo hace hoy. Cada afirmación lleva una marca:

- **Observado** — está en el código o en una RPC leída en main el 2026-11-14.
- **Inferido** — se sigue del comportamiento, sin un test que lo fije.
- **Abierto** — el código no decide si ese comportamiento es el deseado.

El catálogo lee productos y tiendas que Gestión publica. No cobra en el mostrador y no edita el precio vigente.

## Objective

**Observado.** Inventtia Marketplace (`pubspec.yaml`: `ventiq_marketplace` 1.6.0+15, descripción «Aplicación de catalogo de la suite Inventtia») muestra el catálogo público de tiendas y productos. El título de la app es `Inventtia Marketplace`.

El arranque es `/` (splash) y de ahí `/home`. Entrar, la ficha de tienda, el centro de avisos y los ajustes tienen ruta propia: `/auth`, `/store-management`, `/notification-hub`, `/notification-settings`, `/settings`.

Éxito para esta app: el home lista productos con `get_productos_marketplace`, una ficha abre `get_detalle_producto_marketplace`, y las recomendaciones no aceptan el id de otro usuario.

## Tech Stack

**Observado.**

- Flutter / Dart SDK `^3.8.1`. Material, tema claro y oscuro. Cliente `supabase_flutter` ^2.5.6.
- Preferencias con `shared_preferences`. Fotos con `image_picker`. Direcciones con `geocoding`.
- No hay catálogo SQLite. Lee el mismo Postgres que Caja y Gestión.

## Commands

Desde `ventiq_marketplace`. En Windows, si el wrapper Bash de Flutter no produce salida, usar `flutter.bat`.

```
flutter pub get
flutter analyze
flutter test
flutter run
```

## Project Structure

**Observado.** Código en `ventiq_marketplace/`.

```
lib/main.dart                         Rutas
lib/services/marketplace_service.dart Listado, TPV de la tienda y recomendaciones
lib/services/product_service.dart     Más vendidos y más recientes
lib/services/product_detail_service.dart  Ficha y relacionados
lib/services/store_service.dart       Tiendas destacadas
lib/services/user_activity_service.dart   Presencia
lib/services/update_service.dart      fn_check_update
```

## Qué hace la app

**Observado.** El listado llama `get_productos_marketplace` con tienda, categoría, solo disponibles, texto, límite y desplazamiento. La página trae 50. La ficha llama `get_detalle_producto_marketplace` y espera un objeto con `producto` e `inventario`. Los relacionados salen de `fn_productos_relacionados`. Los más vendidos, de `fn_get_productos_mas_vendidos`. Los más recientes, de `fn_get_productos_mas_recientes`. Las tiendas destacadas, de `fn_get_tiendas_destacadas` con límite 10. Las recomendaciones, de `fn_get_productos_recomendados_v2`, pasando el uuid de la sesión si hay una. El estado abierto o cerrado de los TPV de una tienda sale de `get_tienda_estado_tpvs`.

Al abrir, `fn_upsert_actividad_usuario` registra un token y el nombre de la app. Si falla, el catálogo sigue. La versión se comprueba con `fn_check_update`.

`soloDisponibles` pide stock mayor que cero. La búsqueda del listado es la que implementa la RPC.

## Reglas que impone el servidor

**Verificado el 2026-11-14 en main.**

`fn_get_productos_recomendados_v2` usa el usuario de la sesión. Si además llega un `id_usuario_param` distinto de esa sesión, lanza `No autorizado`. Sin sesión, acepta el id que mande el cliente.

`fn_productos_relacionados` lanza si el producto no existe o no tiene tienda ni categoría.

`get_detalle_producto_marketplace` conserva, comentado, un chequeo de «Acceso denegado: No tienes permisos para ver este producto». En el cuerpo desplegado ese chequeo no corre. La ficha la devuelve la función tal como está.

`get_productos_marketplace`, `fn_get_productos_mas_vendidos` y `fn_get_tiendas_destacadas` están desplegadas. No exigen superadmin ni un rol de tienda.

`fn_upsert_actividad_usuario` es `SECURITY DEFINER`. El cliente la llama con el token local y el nombre de la app.

## Code Style

**Observado.** Servicios sobre `Supabase.instance.client` y RPC de `public`. Si una lectura falla, varias pantallas devuelven lista vacía y siguen. UI en español. Rutas con nombre.

## Testing Strategy

**Observado.** No hay un contrato de estas RPC en la suite de esta app. Un listado real y el stock que ve el TPV no los cubre la prueba local.

## Boundaries

- **Always:** Listar con `get_productos_marketplace`. Abrir la ficha con `get_detalle_producto_marketplace`. Pedir recomendaciones con el uuid de la sesión cuando hay sesión. Dejar el precio y el stock como los publica Gestión.
- **Ask first:** Volver a activar el chequeo de acceso comentado en la ficha. Inventar un segundo catálogo offline.
- **Never:** Documentar aquí el cobro del TPV ni el alta de productos de Gestión. Escribir precios o inventario desde esta app. Copiar claves a docs o logs.

## Success Criteria

1. El splash abre `/home` y el listado sale de `get_productos_marketplace`.
2. `fn_get_productos_recomendados_v2` rechaza un id de usuario distinto del de la sesión.
3. `fn_productos_relacionados` no arma relacionados de un producto sin tienda ni categoría.
4. Un fallo de `fn_upsert_actividad_usuario` no impide ver el catálogo.
5. Esta app no guarda un precio ni mueve stock.

## Open Questions

Ninguna que bloquee esta línea base.
