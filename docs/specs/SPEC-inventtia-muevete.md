# Spec: inventtia-muevete (Muevete)

Línea base as-built de `inventtia_muevete` solamente. Describe lo que la app hace hoy. Cada afirmación lleva una marca:

- **Observado** — está en el código, o en una RPC o policy leída en main el 2026-11-14.
- **Inferido** — se sigue del comportamiento, sin un test que lo fije.
- **Abierto** — el código no decide si ese comportamiento es el deseado.

`inventtia_muevete/docs/PLATFORM_PLAN.md` es un plan de transformación. No es esta línea base. Aquí entra lo que el cliente ejecuta y lo que main aplica cuando ese cliente llama.

El cobro de tienda, el TPV y GoReserva no forman parte de esta spec.

## Objective

**Observado.** Muevete (`pubspec.yaml`: `inventtia_muevete` 1.0.0+1) junta dos oficios en una app: viaje urbano de pasajeros y carga. El título es `Muevete`. Debug (`flutter run`) habla con newa. Release habla con main. Las dos ramas usan el esquema `muevete`.

Quién entra, por `tipo_usuario` del perfil:

| Tipo | Tabla | Home |
|---|---|---|
| `cliente_pasajero` | `muevete.users` | `/client/home` |
| `shipper` | `muevete.users` | `/shipper/home` |
| `conductor_pasajeros` | `muevete.drivers` | `/driver/home` |
| `carrier_carga` | `muevete.drivers` | `/carrier/home` |
| `dispatcher` | `muevete.drivers` | `/dispatcher/home` |

El rol viejo `client` / `driver` se deriva del tipo: los tres de `drivers` son `driver`; pasajero y shipper son `client`. El home lo decide `AuthProvider.homeRoute`. En web la ruta `/` abre el landing. En el resto abre el splash, espera el perfil y entra al home. Si el perfil no carga, va al landing.

Éxito para esta app: un pasajero publica un viaje y acepta una oferta; un shipper publica una carga y la cierra cuando el carrier la entregó; el pago de un viaje en efectivo no acredita al conductor si su saldo no cubre la comisión.

## Tech Stack

**Observado.**

- Flutter / Dart SDK `^3.8.1`. Material. Estado con `provider`. Cliente `supabase_flutter` ^2.8.4.
- Mapas con `flutter_map`, caché de teselas y MBTiles offline (`mbtiles`, `vector_map_tiles`). Ubicación con `geolocator`.
- QR con `qr_flutter` y `mobile_scanner`. Push con Pushy. Segundo plano con `flutter_background_service`.
- No hay catálogo SQLite de negocio. La cola offline de cierres de viaje vive en preferencias locales.

## Commands

Desde `inventtia_muevete`. En Windows, si el wrapper Bash de Flutter no produce salida, usar `flutter.bat`.

```
flutter pub get
flutter analyze
flutter test
flutter run
```

`flutter run` usa newa. Un build release usa main. La suite local es un placeholder: `test/widget_test.dart` comprueba `expect(true, isTrue)` y no arranca Supabase.

## Project Structure

**Observado.** Código en `inventtia_muevete/`.

```
lib/main.dart                 Arranque, temas y rutas con nombre
lib/screens/client/           Viaje del pasajero
lib/screens/driver/           Conductor de pasajeros
lib/screens/shipper/          Quien publica carga
lib/screens/carrier/          Transportista de carga
lib/screens/dispatcher/       Gestor de flota
lib/screens/common/           Perfil y planes
lib/services/                 Auth, viaje, carga, wallet, suscripción
lib/providers/                Estado de sesión, carga, wallet y ubicación
```

## Qué hace la app

### Registro y sesión

**Observado.** El alta pide nombre, email, contraseña, país, provincia, ciudad, teléfono y fotos del documento. Según el tipo, suma empresa (shipper), vehículo (conductor) o carrocerías (carrier). Un dispatcher registra transportistas como filas de `drivers` ligadas por `dispatcher_id`. Esas filas no crean cuenta de auth.

El perfil de conductor, carrier o dispatcher lo escribe `muevete.fn_registrar_perfil_driver`. Pasajero y shipper se insertan en `muevete.users`. Si el alta de auth no deja sesión, el registro se detiene: hay que confirmar el email o entrar y completar el perfil.

Shipper, carrier y dispatcher piden además una suscripción de primer mes. El cliente llama `fn_crear_suscripcion_trial` y, si falla, `fn_crear_suscripcion_gratis`, las dos en el esquema `public`. En main esas dos funciones están en `muevete`, no en `public`. El servicio traga el error y el alta sigue. El pasajero no pide plan.

### Viaje urbano

**Observado.** El pasajero crea una fila en `muevete.solicitudes_transporte`. El conductor inserta en `muevete.ofertas_chofer` con estado `pendiente`. Si ya tiene oferta para esa solicitud, el cliente lanza «Ya enviaste una oferta para esta solicitud». Aceptar una oferta la marca `aceptada`, marca la solicitud `aceptada`, rechaza las demás ofertas de esa solicitud y las ofertas pendientes de ese conductor con otros clientes. El viaje activo es una fila de `muevete.viajes` con `completado = false`.

El cliente no llama `fn_tomar_viaje`, `fn_cotizar_viaje`, `fn_viajes_disponibles` ni `fn_completar_viaje`. Esas funciones están en main y no corren en este flujo. Las reglas de zona, deuda, aprobación y vehículo que viven ahí no se aplican a la oferta que inserta la app.

Al cerrar, `complete_ride_payment` (esquema `public`, `search_path = muevete`) mueve los saldos de `muevete`. La comisión es el 15 % del precio final.

- Pago `wallet`: si el final supera la base, descuenta solo la diferencia del saldo del pasajero. El conductor recibe el precio final menos el 15 %.
- Cualquier otro método se trata como efectivo: descuenta el 15 % del saldo del conductor. Si el saldo no alcanza, devuelve `success: false` y el texto «Saldo del conductor insuficiente para comisión». No acredita el viaje.

`WalletService` también calcula el 15 % en el cliente antes de llamar. La función es la que escribe el saldo. Hay una cola local de cierres pendientes que se reintenta al abrir la app.

### Carga

**Observado.** El shipper publica en `muevete.cargas`. El carrier ve las que están en `publicada`, `en_matching` u `ofertada`. La primera oferta pasa la carga a `ofertada` con `fn_cambiar_estado_carga`. Aceptar una oferta la marca `aceptada`, rechaza las otras pendientes de esa carga y llama la misma función con estado `aceptada`. Asignar un carrier del directorio usa `fn_marcar_carga_tomada` y deja la carga en `tomada`.

El carrier confirma recogida (`en_transito`) y entrega (`completada_carrier`). El shipper cierra con `completada`. La función solo acepta un código que exista y esté activo en `muevete.app_nom_estado`. No impone un orden de estados. Escribe la bitácora `app_dat_estado_carga` y copia el código a `cargas.estado`.

`fn_marcar_carga_tomada` asigna `carrier_driver_id` y `carrier_uuid` y registra `tomada`. No comprueba el estado previo ni que quien llama sea el shipper.

### Planes, mapa y avisos

**Observado.** Los planes salen de `muevete.planes` filtrados por tipo. La suscripción activa es la fila de `muevete.suscripciones` con estado `activa` más reciente. Cambiar de plan cancela la fila actual e inserta otra desde el cliente.

El mapa usa teselas con caché y, fuera de web, un MBTiles local. La posición de conductores en segundo plano se guarda en `track_place_history`. El aviso de versión llama `public.fn_check_update`, la misma función que el resto de apps Inventtia.

## Reglas que impone el servidor

**Verificado el 2026-11-14 en main.**

### Perfil y suscripción

`muevete.fn_registrar_perfil_driver` exige sesión. Sin `p_perfil` responde que es obligatorio. Solo acepta `conductor_pasajeros`, `carrier_carga` y `dispatcher`. Si ese uuid ya tiene fila en `drivers`, no duplica. Un email o uuid repetido responde que ya existe.

`muevete.fn_crear_suscripcion_trial` elige `shipper_plan`, `carrier_basico_v2` o `dispatcher_plan` si ese código está activo. Si no, usa `tipo_gratis`. El vencimiento es el próximo día 2 a partir de un mes. Si ya hay una suscripción `activa`, no inserta otra. `fn_crear_suscripcion_gratis` inserta `tipo_gratis` con el mismo vencimiento y `ON CONFLICT DO NOTHING`. El cliente de esta app no las alcanza: las llama en `public`.

### Viaje

`public.complete_ride_payment`, la firma que envía `p_precio_base`, corre con `search_path = muevete`. La comisión es `precio_final * 0.15`. En wallet acredita al conductor el neto y, si el final pasa la base, descuenta el exceso al pasajero. En efectivo exige saldo del conductor mayor o igual a la comisión. Si no hay fila de wallet, la crea al acreditar.

`muevete.fn_tomar_viaje` rechaza a quien no es chofer, a un chofer offline, no aprobado, con viaje activo, con perfil incompleto, con vehículo incompatible o sin capacidad, fuera de zona, con la solicitud vencida, ya tomada, o sin saldo para la comisión. `fn_viajes_disponibles` exige que quien llama sea chofer. Esta app no las llama. El camino vivo inserta la oferta y deja que RLS y el cliente decidan.

RLS en main, sobre el esquema `muevete`:

- `solicitudes_transporte`: el pasajero lee las suyas. Un conductor lee las `pendiente` sin conductor asignado y las suyas. Escribir todo es de superadmin.
- `ofertas_chofer`: el pasajero lee las de sus solicitudes. El conductor lee las suyas. Escribir todo es de superadmin.
- `viajes`: el pasajero y el conductor leen los propios. Escribir todo es de superadmin.
- `wallet_drivers`: el conductor lee la suya. Escribir todo es de superadmin.

El build release lleva una clave con rol `service_role`. Ese rol no pasa por RLS. La clave no se copia aquí. El build debug usa la clave anónima de newa y sí pasa por RLS. Con las policies de main, un conductor autenticado no tiene policy de `INSERT` sobre `ofertas_chofer`.

### Carga

RLS de `cargas`: el shipper opera las suyas (`shipper_id = auth.uid()`). Un carrier lee las `publicada`, `en_matching` y `ofertada`, y también las que ya le asignaron. `ofertas_carga` la opera el driver dueño de la fila.

`fn_cambiar_estado_carga` rechaza un código que no esté activo en `app_nom_estado` con `Estado no válido`. No mira transiciones. `fn_marcar_carga_tomada` no mira quién llama.

## Code Style

**Observado.** Servicios sobre `Supabase.instance.client` con `.schema('muevete')` en las tablas del oficio. Las RPC de suscripción y de pago se llaman sin esquema, así que PostgREST las busca en `public`. UI en español. Rutas con nombre. El tipo de usuario manda el home; el rol `client`/`driver` queda por compatibilidad.

## Testing Strategy

**Observado.** Una prueba placeholder. No cubre una oferta, un cambio de estado de carga ni el pago con comisión.

## Boundaries

- **Always:** Leer y escribir viaje y carga en el esquema `muevete`. Cerrar un viaje de pago con `complete_ride_payment`. Cambiar el estado de una carga con `fn_cambiar_estado_carga` y un código activo del nomenclador. Registrar un conductor con `fn_registrar_perfil_driver`.
- **Ask first:** Hacer que el cliente llame `fn_tomar_viaje` en lugar del insert directo. Mover las suscripciones al esquema `muevete`. Cambiar la comisión del 15 %.
- **Never:** Documentar aquí el TPV, Gestión o GoReserva. Copiar a docs o logs la clave embebida en `supabase_config.dart`. Tratar `PLATFORM_PLAN.md` como comportamiento ya desplegado. Reescribir viajes o cargas históricas al cambiar un plan.

## Success Criteria

1. Un pasajero autenticado entra a `/client/home`. Un shipper entra a `/shipper/home`. Un conductor de pasajeros entra a `/driver/home`. Un carrier entra a `/carrier/home`. Un dispatcher entra a `/dispatcher/home`.
2. `fn_registrar_perfil_driver` rechaza un tipo que no sea conductor, carrier o dispatcher, y no duplica el perfil del mismo uuid.
3. Aceptar una oferta de viaje deja esa oferta en `aceptada`, la solicitud en `aceptada` y el resto de ofertas de esa solicitud en `rechazada`.
4. Un cierre en efectivo con saldo del conductor por debajo del 15 % del precio final no acredita el viaje.
5. `fn_cambiar_estado_carga` rechaza un código que no esté activo en `app_nom_estado` y, si el código vale, deja la bitácora y `cargas.estado` con ese mismo código.
6. El alta de un shipper no falla cuando la suscripción trial no encuentra la función en `public`.

## Open Questions

1. **Abierto.** El camino de oferta de viaje no usa `fn_tomar_viaje`. Las restricciones de esa función (zona, deuda, aprobación, capacidad) no corren. Falta decidir si el cliente debe empezar a llamarla.
