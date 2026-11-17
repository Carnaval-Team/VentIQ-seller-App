# Spec: ventiq-superadmin (Inventtia Super Admin)

Línea base as-built de `ventiq_superadmin` solamente. Describe lo que esta app hace hoy. Cada afirmación lleva una marca:

- **Observado** — está en el código o en una RPC leída en main el 2026-11-14.
- **Inferido** — se sigue del comportamiento, sin un test que lo fije.
- **Abierto** — el código no decide si ese comportamiento es el deseado.

Esta app opera por encima de Caja, Gestión, Muevete, GoReserva y Carnaval. No sustituye el spec de cada una: aquí entra lo que el superadmin lee o escribe.

## Objective

**Observado.** Inventtia Super Admin (`pubspec.yaml`: `ventiq_superadmin` 1.0.0+1) administra la plataforma: tiendas, usuarios, licencias, monedas, versiones, carnaval, Muevete y los planes de GoReserva. El título es `Inventtia Super Admin`.

El login exige una fila activa en `app_dat_superadmin` para el uuid de la sesión. Si no existe, cierra la sesión y responde «No tienes permisos de superadministrador». Cada ruta pasa por `RouteGuard`. Si el superadmin no tiene rol y su `nivel_acceso` es 1, entra a todas. Si tiene rol, solo entra a las rutas de `permisos_rutas`. Sin permiso, la pantalla dice «No tienes permiso para acceder a esta sección» y ofrece volver al dashboard.

`nivel_acceso` 1 es acceso total. Hasta 2 puede escribir (`canWrite`). Hasta 3 puede leer (`canRead`). Esas tres banderas viven en el cliente. Varias RPC de main vuelven a exigir superadmin por su cuenta.

Éxito para esta app: un superadmin activo abre el dashboard, y una moneda, una tasa global o una versión de app no se guardan si quien llama no es superadmin.

## Tech Stack

**Observado.**

- Flutter / Dart SDK `^3.7.0`. Material, locale `es`. Estado con `provider`. Cliente `supabase_flutter` ^2.3.4.
- Gráficos con `fl_chart` y Syncfusion. Mapas con `flutter_map`. Preferencias con `shared_preferences`.
- Habla con los esquemas `public`, `flow`, `muevete` y `carnavalapp` según la pantalla.

## Commands

Desde `ventiq_superadmin`. En Windows, si el wrapper Bash de Flutter no produce salida, usar `flutter.bat`.

```
flutter pub get
flutter analyze
flutter test
flutter run
```

## Project Structure

**Observado.** Código en `ventiq_superadmin/`.

```
lib/main.dart            Rutas con RouteGuard
lib/screens/             Tiendas, usuarios, licencias, monedas, carnaval, flow, muevete
lib/services/            Una RPC por oficio
lib/widgets/route_guard.dart
```

Rutas de negocio, todas guardadas: `/dashboard`, `/tiendas`, `/usuarios`, `/administradores`, `/licencias`, `/consignacion`, `/fondo-inversion`, `/eliminacion-tiendas`, `/control-flota`, `/movimientos`, `/referral-payments`, carnaval (`/carnaval-tiendas`, `/productos-carnaval-inventtia`), Muevete (`/muevete/dashboard`, conductores, viajes, mapa, billeteras, kyc) y GoReserva (planes, suscripciones, categorías, fidelidad, campañas, colecciones, versiones).

## Qué hace la app

### Plataforma Inventtia

**Observado.** El dashboard llama `get_dashboard_ventas_stats`. Usuarios salen de `get_users_count_summary` y `get_paginated_users_summary`. Cambiar una contraseña llama `admin_change_user_password`. Un gerente nuevo sale de `create_gerente_from_email`. Trabajadores de una tienda reutilizan `fn_listar_trabajadores_tienda` y `fn_insertar_trabajador_completo`. Borrar una tienda llama `delete_tienda_completa`. Borrar un proveedor de carnaval llama `carnavalapp.delete_proveedor_completo`.

Monedas: `fn_crear_moneda`, `fn_actualizar_moneda`, `fn_guardar_denominaciones`, `fn_guardar_tasa_global`, `fn_tasa_cambio` y la ingesta automática `fn_tasas_refrescar` / `fn_tasas_ingerir`. Versiones de Caja, Gestión, Catálogo, GoReserva y Muevete se guardan con `fn_app_version_guardar`.

### GoReserva, Muevete y Carnaval

**Observado.** Planes y suscripciones de GoReserva usan el esquema `flow`: `admin_plan_guardar`, `admin_suscripcion_aprobar_pago`, `admin_suscripcion_rechazar_pago`, `admin_suscripcion_acreditar`, suspender y reactivar. Fidelidad, campañas, colecciones y categorías usan las RPC `admin_*` de `flow`.

Muevete aprueba o rechaza una solicitud de plan con `muevete.fn_aprobar_solicitud_plan` y `fn_rechazar_solicitud_plan`. Un cambio de estado de carga reutiliza `fn_cambiar_estado_carga`. El mapa escucha `muevete.place`.

Carnaval actualiza precio y stock con `fn_carnaval_update_product_prices` y `fn_carnaval_update_product_stock`, recalcula con `rpc_recalc_carnaval_prices_for_store` y desbloquea un carrito con `carnavalapp.fn_desbloquear_carrito`. Los banners del home se listan, guardan y borran en `carnavalapp`.

El fondo de inversión se consulta con `fn_fdi_saldos`, `fn_fdi_inversiones` y `fn_fdi_movimientos`. Esta pantalla no liquida: eso sigue en Gestión.

## Reglas que impone el servidor

**Verificado el 2026-11-14 en main.**

`fn_crear_moneda` solo la ejecuta un superadministrador. El código tiene que ser ISO-4217 de 3 letras y no puede repetirse. `fn_actualizar_moneda` exige lo mismo. No deja desactivar la moneda base ni una moneda que ya tiene pagos. `fn_guardar_tasa_global` exige superadmin, monedas que existan y una tasa mayor que cero.

`fn_app_version_guardar` exige superadmin, nombre de app, versión, versión mínima, build mayor que 0 y una URL de descarga que empiece por `http://` o `https://`. Las novedades tienen que ser un array JSON.

`flow.admin_plan_guardar` solo la ejecuta un superadmin. La modalidad es `pago` o `contacto`. Los límites son un objeto JSON. Crear un plan pide nombre y duración en días. Un código repetido se rechaza. El id de entidad 0 es el plan público.

`flow.admin_suscripcion_aprobar_pago` y `admin_suscripcion_rechazar_pago` exigen superadmin. No reprocesan un pago ya cerrado. Rechazar pide motivo. Aprobar exige que el intento y el plan sigan existiendo.

`muevete.fn_aprobar_solicitud_plan` solo aprueba una solicitud pendiente. El vencimiento tiene que ser el día 2 de un mes. `fn_rechazar_solicitud_plan` rechaza una solicitud que no exista o que ya fue procesada.

`carnavalapp.fn_desbloquear_carrito` exige `p_user_id` y `p_id_producto`.

`admin_change_user_password` exige un correo no vacío, una contraseña de al menos 6 caracteres y un usuario que exista. El cuerpo leído en main no vuelve a comprobar `app_dat_superadmin`. La puerta de esa pantalla es el login y `RouteGuard`.

`delete_tienda_completa` no es `SECURITY DEFINER` y no comprueba superadmin. Si la tienda existe, borra supervisores, gerentes, trabajadores y TPV de esa tienda, y sigue con el resto de filas ligadas. Si la tienda no existe, no hace nada. La pantalla que la llama está guardada por ruta.

`create_gerente_from_email` exige que el correo ya exista en `auth.users`.

## Code Style

**Observado.** Servicios sobre `Supabase.instance.client`. Las de GoReserva fijan el esquema `flow`. Las de Muevete y Carnaval fijan `muevete` o `carnavalapp`. El resto va a `public`. UI en español. Rutas con nombre y `RouteGuard`.

## Testing Strategy

**Observado.** No hay un contrato de estas RPC en `test/` de esta app. Un borrado de tienda o un cambio de contraseña no los cubre una prueba local.

## Boundaries

- **Always:** Exigir fila activa en `app_dat_superadmin` antes de abrir el dashboard. Respetar `permisos_rutas` cuando el superadmin tiene rol. Crear monedas, tasas y versiones solo por las RPC que ya exigen superadmin. Aprobar un plan de Muevete con vencimiento en día 2.
- **Ask first:** Ampliar `delete_tienda_completa` o `admin_change_user_password`. Bajar el mínimo de 6 caracteres de la contraseña. Dar nivel 1 a un rol que no deba ver todas las rutas.
- **Never:** Documentar aquí el cobro del TPV ni la reserva de GoReserva como si esta app las ejecutara. Copiar claves a docs o logs. Tratar el fondo de inversión de esta pantalla como la liquidación de Gestión.

## Success Criteria

1. Quien no tiene fila activa en `app_dat_superadmin` no pasa del login.
2. Un superadmin con rol solo abre las rutas de `permisos_rutas`. Nivel 1 sin rol abre todas.
3. `fn_crear_moneda` rechaza a quien no es superadmin y un código que no tiene 3 letras.
4. `fn_app_version_guardar` rechaza un build en 0 y una URL que no es http o https.
5. Aprobar un pago de suscripción de GoReserva o un plan de Muevete que ya fue procesado no lo vuelve a aplicar.
6. `delete_tienda_completa` no borra nada si el id de tienda no existe.

## Open Questions

Ninguna que bloquee esta línea base.
