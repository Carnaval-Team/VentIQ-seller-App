# 01 · Análisis técnico — Flujo actual del taxi y qué cambia con el precio fijo

> **Rol:** analista técnico del equipo de rediseño.
> **Alcance:** apps `inventtia_muevete/` (pasajeros + carga) y `ventiq_superadmin/` (consola admin), esquema `muevete` en Supabase.
> **Modo:** solo lectura de código. El único archivo escrito por este análisis es este documento.
> **Fecha de análisis:** 2026-11-12.
> **Referencias:** todas las rutas son relativas a `C:\Users\cesar\Documents\VentIQ-seller-App\`. Los `archivo:línea` se refieren a la versión leída en esa fecha; si el código cambia, los números pueden desplazarse.

---

## 0. Resumen ejecutivo (lo que hay que saber antes de tocar nada)

1. **La negociación es doble y está repartida en 4 sitios**: el cliente fija un precio editable (`route_preview_screen.dart:490-546`), el chofer responde con contraoferta (`incoming_requests_screen.dart:305-445` y una copia en `driver_home_screen.dart:537-792`), el cliente elige oferta (`driver_offers_screen.dart:79-115`) y la aceptación se materializa en dos UPDATE más un INSERT de viaje (`transport_request_service.dart:221-289`, `transport_provider.dart:341-380`).
2. **El precio no lo calcula el backend**: se calcula en el cliente Dart (`transport_provider.dart:149-164`) con un círculo hardcodeado de Santa Clara (`utils/constants.dart:71-74`). El servidor solo guarda `solicitudes_transporte.precio_oferta` y `ofertas_chofer.precio` tal cual llegan. Cualquier cliente puede escribir el precio que quiera.
3. **La comisión 15% está hardcodeada en 4 lugares** (Dart ×2 + RPC SQL ×2) y **la recarga 11% en otros 2**. No hay tabla de configuración de tarifas ni de comisión.
4. **No existe ninguna tabla de zonas ni de tarifas** en el esquema `muevete`, ni en la app, ni en superadmin. `muevete.vehicle_type` (precio por km / precio “inside SC”) y `muevete.configuracion_navegacion.precio_x_km` son lo más parecido, y `configuracion_navegacion` **no se lee en ningún punto del código** (grep sin resultados de `precio_x_km`/`configuracion_navegacion` en `lib/`).
5. **El vínculo solicitud ↔ viaje hoy pasa por `ofertas_chofer`** (`ride_confirmed_screen.dart:147-200`, `home_map_screen.dart:204-231`). Si se elimina la oferta, `viajes` se queda sin ninguna FK a la solicitud: **hay que añadir `viajes.solicitud_id`** o el flujo se rompe.
6. **El superadmin tiene 10 pantallas `muevete_*` con un patrón muy repetible** (StatefulWidget + `MueveteService` estático + tabla/cards + `AppDrawer` + `RouteGuard`), y `flutter_map ^7.0.2` ya está en `pubspec.yaml:40-41`, pero **no hay editor de geometrías** (la pantalla `carnaval_geo_admin_screen.dart` es un stub “en construcción”). Para dibujar polígonos hay que construir el editor desde cero, reutilizando `muevete_map_screen.dart` como base.
7. **Las políticas RLS actuales son incompatibles con el modelo nuevo**: `drivers_see_solicitudes` es `USING (true)` (`003_enable_realtime.sql:27-28`), el cliente conserva `FOR ALL` sobre su solicitud (`003_enable_realtime.sql:24-25`) y por tanto puede seguir haciendo UPDATE de `precio_oferta`/`estado`; y hay operaciones que el código hace hoy (INSERT de `viajes` desde el cliente, UPDATE de `solicitudes` desde el chofer) que **no tienen política** en las migraciones del repo → o la BD real tiene políticas no versionadas, o esos caminos fallan silenciosamente. **Verificar contra la BD real antes de diseñar.**

---

## 1. Inventario del flujo actual

### 1.1 Mapa de navegación (rutas registradas en `inventtia_muevete/lib/main.dart`)

| Ruta | Pantalla | Línea |
|---|---|---|
| `/client/home` | `HomeMapScreen` | `main.dart:139` |
| `/client/route-preview` | `RoutePreviewScreen` | `main.dart:140` |
| `/client/driver-offers` | `DriverOffersScreen` | `main.dart:141` |
| `/client/ride-confirmed` | `RideConfirmedScreen` | `main.dart:142-143` |
| `/client/request-history` | `RequestHistoryScreen` | `main.dart:148-149` |
| `/driver/home` | `DriverHomeScreen` | `main.dart:150` |
| `/driver/requests` | `IncomingRequestsScreen` | `main.dart:151-152` |
| `/driver/active-ride` | `ActiveRideScreen` | `main.dart:153` |
| `/dispatcher/home` | `DispatcherHomeScreen` | `main.dart:161` |

Estado global: `MultiProvider` con `TransportProvider`, `WalletProvider`, `AuthProvider`, `LocationProvider`, etc. (`main.dart:102-115`).

### 1.2 Cliente (pasajero)

#### `lib/screens/client/home_map_screen.dart` (2 038 líneas)
- **Hace:** mapa principal, marcadores de choferes cercanos, banner de viaje activo, sugerencias de direcciones.
- **Lee:** `muevete.place` (posiciones online) vía `TransportRequestService.getNearbyDrivers()` (`home_map_screen.dart:386-403` → `transport_request_service.dart:52-95`, filtro Haversine en cliente con radio 50 km, `constants.dart:59`); solicitud activa `pendiente|aceptada` del usuario (`home_map_screen.dart:158-165`); oferta aceptada para recuperar al chofer (`home_map_screen.dart:204-231`); `muevete.viajes` del chofer+usuario para saber si el viaje arrancó (`home_map_screen.dart:233-257`, 352-370).
- **Escribe:** nada de negocio; solo navegación (`pushNamed('/client/route-preview')` en `home_map_screen.dart:1222`).
- **Relevante para el rediseño:** el marcador “chofer aceptado” depende de `ofertas_chofer.estado='aceptada'`; el banner y el tracking del chofer deben pasar a `solicitudes_transporte.driver_id`/`viajes`.

#### `lib/screens/client/route_preview_screen.dart` (825 líneas) — **aquí nace la negociación**
- **Hace:** muestra la ruta, deja elegir tipo de vehículo, edita el precio (“Tu Oferta”), elige método de pago, envía la solicitud.
- **Lee:** tipos de vehículo activos (`route_preview_screen.dart:30-39` → `loadVehicleTypes()`, `transport_provider.dart:82-108`); ruta calculada (`calculateRoute()`, `transport_provider.dart:192-211`); saldo de wallet (`route_preview_screen.dart:73-94`).
- **Escribe:** `muevete.solicitudes_transporte` (INSERT vía `sendRequest()`, `transport_provider.dart:249`), con `precio_oferta` (`transport_provider.dart:240`).
- **Puntos clave:** controlador del precio `route_preview_screen.dart:25`; sincronización con el precio calculado `:37` y `:119-126`; validación de mínimo `:54-71`; campo “Tu Oferta” `:490-497`; `TextFormField` editable `:499-546`; `onChanged` que llama `setOfferPrice()` `:539-545`; botón muerto “Ver tarifas promedio” `:548-570`.

#### `lib/screens/client/driver_offers_screen.dart` (550 líneas) — **selector de ofertas**
- **Hace:** lista de contraofertas de choferes con filtros (`Menor Precio`, `Mas Rapido`) y “Aceptar”.
- **Lee:** `TransportProvider.driverOffers` (realtime, `transport_provider.dart:298-303`; carga inicial `transport_request_service.dart:174-190`).
- **Escribe:** al aceptar → `ofertas_chofer.estado='aceptada'` + `solicitudes_transporte.estado='aceptada'` + rechazo de las demás + notificación al chofer (`transport_request_service.dart:221-289`); retiene saldo wallet (`transport_provider.dart:350-353`); crea `viajes` (`transport_provider.dart:356-368`).
- **Puntos clave:** filtros `driver_offers_screen.dart:60-77`; aceptación `:79-115`; cancelar viaje `:117-178`. **Pantalla completa a deprecar/eliminar.**

#### `lib/screens/client/ride_confirmed_screen.dart` (1 720 líneas)
- **Hace:** seguimiento del chofer en mapa, inicio/fin del viaje, cobro de espera por paradas, cierre con valoración y fallback offline por QR.
- **Lee:** `vehicle_type.precio_espera_min` (`:117-144`); `ofertas_chofer` aceptada (`:147-160`); `place` del chofer (`:203-236`); `paradas_viaje` (servicio de paradas, `stop_service.dart:65-83`).
- **Escribe:** `solicitudes_transporte.estado='completada'` (`:547-551`); `viajes.completado/estado/tiempo_espera_segundos/cobro_espera` (`:553-564`); RPC `complete_ride_payment` (`:545` → `transport_provider.dart:489-510`); `valoraciones_viaje` (`:566-583`); cola offline/QR (`:592-649`).
- **Puntos clave:** el precio final sale de `acceptedOffer?.precio` (`:539`), no de una tarifa de plataforma.

#### `lib/screens/client/request_history_screen.dart` (506 líneas)
- **Hace:** historial de solicitudes; reanudar pendiente (push a `/client/driver-offers`, `:125-130`), abrir viaje aceptado (`:132-141`), cancelar (`:143-178`).
- **Escribe:** `solicitudes_transporte.estado='cancelada'` (`:165-169`).
- **Nota:** muestra y reanuda el flujo de ofertas; al eliminarlo debe pasar a “viaje publicado / chofer asignado”.

### 1.3 Chofer

#### `lib/screens/driver/driver_home_screen.dart` (1 857 líneas)
- **Hace:** mapa del chofer, toggle online/offline, lista de solicitudes cercanas y bandeja de solicitudes entrantes, **diálogo de contraoferta duplicado**.
- **Escribe:** online offline en `drivers.estado` y `place.estado` (`driver_service.dart:14-28`); ubicación en `place` (`:31-44`, `driver_service.dart:248-265`); `ofertas_chofer` INSERT (`:794-845` → `driver_service.dart:103-151`).
- **Lee:** solicitudes pendientes cercanas (`driver_home_screen.dart:211-260` → `driver_service.dart:270-314`); realtime INSERT de solicitudes (`:264-292`); aceptación de sus ofertas (`:294-365` → `driver_service.dart:370-393`); viaje activo (`:378-391`, `driver_service.dart:154-172`).
- **Puntos clave:** estado online `:52`, `:136`, toggle `:446-514`; diálogo contraoferta `:537-792` (título “Hacer Oferta” `:578`, “Precio del cliente” `:597`, validación `:738-758`); `_submitOffer` `:794-845`; tarjeta con botón “Hacer Oferta” `:1843`; navegación a `ActiveRideScreen` `:367-375` y `:909`.

#### `lib/screens/driver/incoming_requests_screen.dart` (1 413 líneas) — **segunda implementación de la negociación**
- **Hace:** dos tabs (pendientes / aceptadas), realtime de solicitudes y ofertas, polling 30 s.
- **Escribe:** `ofertas_chofer` INSERT con `precio`, `tiempo_estimado`, `mensaje` (`:515-551` → `driver_service.dart:103-151`); `solicitudes_transporte.estado='completada'` en `_completeRide` (`:577`, UPDATE en `:629`).
- **Lee:** solicitudes pendientes (`:187-227`), ofertas propias aceptadas (`:228-291`, consulta `ofertas_chofer.estado='aceptada'` en `:235-241`).
- **Puntos clave:** realtime 3 canales `:63-134`; polling `:53-56`; diálogo contraoferta `:305-445` (precio precargado con `precio_oferta` `:307-309`, mínimo validado contra `precio_oferta` `:393-402`); **chequeo de saldo para comisión 15%** `:527-543`; `_openActiveTrip` `:674-726`.

#### `lib/screens/driver/active_ride_screen.dart` (2 100 líneas)
- **Hace:** navegación giro-a-giro, paradas, inicio/fin de viaje, cobro de espera.
- **Lee:** `vehicle_type.precio_espera_min` (`:553-559`, `:874-889`); `paradas_viaje`; `viajes`.
- **Escribe:** `viajes.estado/completado`, `paradas_viaje`.
- **Impacto:** sigue siendo válido; solo cambia de dónde sale el precio del viaje (snapshot de la solicitud) y el esquema de comisión.

#### `lib/screens/driver/driver_wallet_screen.dart` (500+ líneas)
- Muestra saldo y transacciones; textos con **11% hardcodeado** (`:78`, `:176`, `:310`). Debe mostrar también la **deuda de efectivo** (D6).

### 1.4 Servicios transversales

| Servicio | Qué hace | Líneas clave |
|---|---|---|
| `services/transport_request_service.dart` | CRUD de solicitudes, ofertas, realtime de ofertas/solicitud, aceptación | INSERT solicitud `15-24`; cancelar `27-33`; cercanos `52-95`; enriquecer oferta `100-159`; ofertas existentes `174-190`; canal INSERT ofertas `194-216`; aceptar oferta `221-289` (rechazos `243-260`, notificación `262-284`); canal UPDATE solicitud `293-314`; canal UPDATE ofertas `318-338`; unsubscribe `341-360` |
| `services/driver_service.dart` | online/posición, solicitudes cercanas, ofertas, viajes, valoraciones | toggle `14-28`; ubicación `31-44`; realtime solicitudes `49-87`; `hasExistingOffer` `90-99`; `makeOffer` `103-151`; viaje activo `154-172`; UPDATE viaje `175-196`; `createViaje` `318-342`; realtime viaje `346-366`; realtime aceptación `370-393`; `fetchSolicitudById` `396-403`; `updateSolicitudEstado` `417-423`; valoraciones `438-466`; Haversine `496-516` |
| `services/wallet_service.dart` | saldos, recargas, retención, reembolso, comisión, RPC de cierre | saldo cliente `8-25`; saldo chofer `28-38`; recarga 11% `43-64` y `81-114`; retener saldo `181-193`; pago confirmado `197-208`; reembolso `211-229`; comisión 15% `233-256`; abono neto 15% `260-298`; chequeo comisión `301-305`; RPC `309-330` |
| `services/background_service.dart` (708 líneas) | foreground service con GPS, canales realtime y polling | suscripción solicitudes chofer `~300-338`; updates de solicitud `341-356`; INSERT de ofertas (quita solicitud de la cola) `359-374`; expansión de radio `377-407`; **cliente escucha INSERT de `ofertas_chofer`** `442-465`; heartbeat `468-490`; polling (chofer pendientes `500-520`; **cliente ofertas `521-537`**) |
| `services/completion_sync_service.dart` | cola offline de cierres en SharedPreferences | encolar `18-43`; sincronizar `64-88`; `_syncOne` RPC `99-111`, marcar solicitud `113-118`, viaje `120-125`, rama chofer `126-141` |
| `services/trip_completion_qr_service.dart` | QR firmado HMAC para cierre offline | secreto hardcodeado `11`; payload con `precio/precio_base/metodo` `15-39`; validación `43-65`; expiración 10 min `12` |
| `services/notification_service.dart` | notificaciones DB + overlay local | subscribe `25-47`; `pushLocal` `51-66`; `createNotification` `69-91` |
| `services/pushy_service.dart` | push Pushy.me; al tocar, abre pantalla | `~100-110` (`showDriverOffer`) |
| `services/offline_queue_service.dart` | cola de posiciones GPS offline | usado por `background_service` |
| `services/stop_service.dart` | paradas y tiempo de espera | crear/cerrar parada `7-41`; total espera `65-83` |

**Tipos de notificación existentes** (`models/notification_model.dart:1-10`): `nuevaSolicitud`, `nuevaOferta`, `ofertaAceptada`, `viajeIniciado`, `driverEsperando`, `viajeCompletado`, `paradaIniciada`, `paradaFinalizada`. Con el flujo nuevo sobra `nuevaOferta` y `ofertaAceptada`; falta un `nuevoViajeDisponible`.

### 1.5 Dispatcher

- `lib/screens/dispatcher/dispatcher_home_screen.dart` (2 055 líneas) y `services/dispatcher_service.dart` (162 líneas) son **exclusivamente de carga**: gestionan “transportistas” (`drivers` con `tipo_usuario='carrier_carga'`, `dispatcher_id`) y `carrocerias` (`dispatcher_service.dart:27-161`; consultas en `dispatcher_home_screen.dart:62-64`, `:625`). **No participan en el flujo de taxi de pasajeros**; el rediseño no debe tocarlos.
- El dispatcher **no** ve ni gestiona `solicitudes_transporte`/`ofertas_chofer`.

### 1.6 Superadmin (`ventiq_superadmin`)

10 pantallas en `lib/screens/muevete/`:

| Pantalla | Archivo | Qué consume |
|---|---|---|
| Panel | `muevete_dashboard_screen.dart` (360) | `MueveteService.getStats()` (`muevete_service.dart:360-416`) |
| Conductores | `muevete_drivers_screen.dart` (393) | `getDrivers()` `:10-19`, `updateDriver()` `:22-28` |
| Viajes | `muevete_trips_screen.dart` (188) | `getTrips()` `:33-57` |
| Solicitudes y Ofertas | `muevete_requests_screen.dart` (284) | `getRequests()` `:62-86`, `getOffers()` `:91-102` |
| Mapa en vivo | `muevete_map_screen.dart` (748) | `getDriverPositions()` `:123-139`, `place` realtime, rutas |
| Subir mapa offline | `muevete_map_upload_screen.dart` (?) | subida MBTiles |
| Valoraciones | `muevete_ratings_screen.dart` (?) | `getRatings()` `:107-118` |
| Billeteras | `muevete_wallets_screen.dart` (500) | `getClientWallets()` `:159-182`, `getDriverWallets()` `:185-192`, `getTransactions()` `:195-206`, `approveRecarga()` `:220-268` |
| KYC | `muevete_kyc_screen.dart` (?) | `getPendingKycDrivers()` `:282-292`, `approveDriverKyc()` `:295-301` |
| Solicitudes de Plan | `muevete_planes_screen.dart` (?) | `getSolicitudesPlan()` `:422-496` |
| Gestión de Cargas | `muevete_cargas_screen.dart` (?) | `getCargas()` `:562-621` |

**No existe ninguna pantalla de zonas ni de tarifas.**

### 1.7 Tablas del esquema `muevete` implicadas (según `muevete_schema.sql`)

| Tabla | Columnas relevantes | Líneas |
|---|---|---|
| `solicitudes_transporte` | `id`, `user_id uuid`, coords origen/destino, `tipo_vehiculo varchar`, `precio_oferta numeric`, `estado varchar`, direcciones, `distancia_km`, `expires_at`, `id_tipo_vehiculo`, `metodo_pago` | `190-209` |
| `ofertas_chofer` | `solicitud_id`, `driver_id`, `precio`, `tiempo_estimado`, `estado`, `mensaje` | `210-222` |
| `viajes` | `driver_id smallint`, `user varchar`, `estado bool`, `completado bool`, `latitud_cliente/longitud_cliente text`, `cobro_espera`, `tiempo_espera_segundos` | `173-189` |
| `drivers` | `id bigint`, `uuid uuid→auth.users`, `province`, `municipality`, `categoria`, `estado`, `kyc`, `tipo_usuario`, `dispatcher_id`, `vehiculo` | `40-87` |
| `place` | `driver bigint UNIQUE`, `latitude`, `longitude`, `estado`, `vehiculo_id`, `categoria` | `88-104` |
| `wallet_drivers` | `driver_id UNIQUE`, `balance` | `223-230` |
| `transacciones_wallet` | `user_id`, `driver_id`, `tipo` (CHECK 5 valores), `monto`, `balance_despues`, `viaje_id`, `estado` (CHECK 4 valores) | `231-246` |
| `vehicle_type` | `tipo`, `precio_km_default`, `status`, `tiempo_min_por_km`, `precio_inside_sc`, `precio_espera_min` | `247-257` |
| `configuracion_navegacion` | `precio_x_km`, `tiempo_espera_driver` | `4-10` |
| `valoraciones_viaje` | `viaje_id UNIQUE`, `driver_id`, `user_id`, `rating 1-5`, `comentario` | `291-303` |
| `paradas_viaje` | `id_viaje`, `driver_id`, coords, `tiempo_detenido`, `salida_at` | `321-334` |
| `suscription_user` | `user_id uuid`, `balance`, `current_balance`, `active_until` | `124-132` |
| `users` | `uuid`, `name`, `phone`, `tipo_usuario` | `133-172` |
| `notificaciones`, `push_tokens`, `track_place_history` | soporte de notificaciones y tracking | `270-290`, `304-311` |

---

## 2. Dónde vive exactamente la negociación (qué eliminar y qué deprecar)

### 2.1 Puntos de código

| # | Archivo:línea | Qué hace | Acción |
|---|---|---|---|
| N1 | `inventtia_muevete/lib/screens/client/route_preview_screen.dart:25,37,119-126,490-546,539-545` | Campo “Tu Oferta” editable y sincronización de precio | **Eliminar** (sustituir por desglose de tarifa calculada) |
| N2 | `route_preview_screen.dart:53-71` | Validación de precio mínimo en cliente | **Eliminar** (lo valida el backend) |
| N3 | `route_preview_screen.dart:99-106` | Navegación a `DriverOffersScreen` tras enviar | **Cambiar** a pantalla “buscando chofer” |
| N4 | `inventtia_muevete/lib/providers/transport_provider.dart:139-142` | `setOfferPrice()` | **Eliminar** |
| N5 | `transport_provider.dart:149-190` | `_calculatePrice()`, `_isInsideCityZone()`, Haversine con círculo SC | **Eliminar** (precio lo devuelve RPC de cotización) |
| N6 | `transport_provider.dart:213-275` (`sendRequest`) | Crea solicitud con `precio_oferta` y se suscribe a ofertas | **Reescribir**: llamar RPC `crear_solicitud`, suscribirse a la propia solicitud y a `viajes` |
| N7 | `transport_provider.dart:278-290` (`resubscribeRealtime`) | Re-suscripción a ofertas | **Reescribir** |
| N8 | `transport_provider.dart:293-339` (`declineOffer`, `_onNewOffer`, `_onOfertaUpdate`) | Lógica de ofertas | **Eliminar** |
| N9 | `transport_provider.dart:341-380` (`acceptOffer`) | El cliente acepta oferta y crea el viaje | **Eliminar** (el chofer toma el viaje; el cliente solo recibe el evento) |
| N10 | `transport_provider.dart:383-410` (`restoreActiveRequest`) | Reanuda “buscando ofertas” | **Reescribir** |
| N11 | `transport_provider.dart:414-461` (`restoreAcceptedRide`) | Recupera oferta aceptada | **Reescribir** con `solicitud.driver_id`/`viaje` |
| N12 | `transport_provider.dart:463-484` (`cancelRequest`) | Reembolso basado en `acceptedOffer.precio` | **Reescribir** con precio congelado de la solicitud |
| N13 | `transport_provider.dart:489-510` (`completeRideWithPayment`) | Envía `precio_final`/`precio_base` al RPC | **Cambiar firma**: el RPC deriva el precio en servidor |
| N14 | `transport_provider.dart:539-548` (`pollOffers`) | Polling de ofertas | **Eliminar** |
| N15 | `lib/screens/client/driver_offers_screen.dart` (completa, 550 líneas) | Selección de ofertas | **Eliminar** archivo + ruta `main.dart:141` + import `main.dart:31` + push `route_preview_screen.dart:100-105` + `request_history_screen.dart:129` |
| N16 | `lib/services/transport_request_service.dart:174-216` | `getExistingOffers`, `subscribeToOffers` | **Eliminar** |
| N17 | `transport_request_service.dart:221-289` (`acceptOffer`) | Aceptación + rechazo en cascada + notificación “Oferta aceptada” | **Eliminar** (sustituir por RPC `tomar_viaje`) |
| N18 | `transport_request_service.dart:318-338` | Canal UPDATE de ofertas | **Eliminar** |
| N19 | `lib/screens/driver/driver_home_screen.dart:537-792` | **Diálogo contraoferta duplicado** | **Eliminar**; unificar en una sola pantalla de viajes disponibles |
| N20 | `driver_home_screen.dart:794-845` (`_submitOffer`) | INSERT de oferta | **Eliminar** |
| N21 | `driver_home_screen.dart:294-365` | Realtime de “mi oferta aceptada” | **Eliminar** (el chofer ya sabe que tomó el viaje) |
| N22 | `inventtia_muevete/lib/screens/driver/incoming_requests_screen.dart:305-445,515-574` | Diálogo + envío de contraoferta | **Eliminar**; sustituir por botón “Tomar viaje” |
| N23 | `incoming_requests_screen.dart:228-291` (`_loadAccepted`) | Carga ofertas aceptadas | **Reescribir** con `solicitudes.driver_id`/`viajes` |
| N24 | `incoming_requests_screen.dart:63-134` | Canales realtime de solicitudes/ofertas | **Reescribir**: canal de solicitudes pendientes de la zona + canal de la solicitud tomada |
| N25 | `lib/services/driver_service.dart:90-151` (`hasExistingOffer`, `makeOffer`) | Creación de ofertas | **Eliminar** |
| N26 | `driver_service.dart:370-393` (`subscribeToMyOfferAcceptances`) | Realtime de aceptación de oferta | **Eliminar** |
| N27 | `lib/services/background_service.dart:359-374` | INSERT de ofertas quita solicitud de la cola | **Eliminar** |
| N28 | `background_service.dart:442-465` | Cliente escucha INSERT de `ofertas_chofer` | **Eliminar**; sustituir por UPDATE de solicitud (chofer asignado) |
| N29 | `background_service.dart:521-537` | Polling de ofertas del cliente | **Reescribir** (estado de solicitud/viaje) |
| N30 | `lib/models/driver_offer_model.dart`, `lib/widgets/driver_offer_card.dart` | Modelo y card de oferta | **Deprecar/eliminar** |
| N31 | `lib/utils/constants.dart:71-74` | Círculo hardcodeado SC | **Eliminar** (sustituido por polígonos en BD) |
| N32 | Superadmin `muevete_requests_screen.dart:74,92-120` | Tab “Ofertas” | **Deprecar** (histórico) o dejar solo lectura |

### 2.2 Efectos secundarios de quitar la negociación (por subsistema)

- **Realtime — `ofertas_chofer`**: hoy hay 6 canales activos sobre esa tabla (`transport_request_service.dart:194-216,318-338`; `driver_service.dart:370-393`; `driver_home_screen.dart:294-304`; `incoming_requests_screen.dart:97-132`; `background_service.dart:359-374,442-465`). El disparador nuevo pasa a ser **INSERT de `solicitudes_transporte`** (viaje publicado) y **UPDATE de `solicitudes_transporte`** (tomado/completado/cancelado), más **INSERT/UPDATE de `viajes`**. Hay que revisar las suscripciones y la publicación `supabase_realtime` (`003_enable_realtime.sql:8-13` + `004_notifications.sql:18`); `vehicle_type` **no está en la publicación** aunque el código se suscribe (`vehicle_type_service.dart:36-47`) → suscripción muerta hoy; si las zonas/tarifas se editan desde superadmin, hay que publicarlas o forzar refresco.
- **Notificaciones**: hoy el chofer recibe “Nueva solicitud” (`driver_home_screen.dart:283-289`, `background_service.dart:~335`/`514-518`, push `pushy_service.dart:104`) y el cliente “Nueva oferta de conductor” (`background_service.dart:453-457,531-535`, DB `driver_service.dart:136-148`) y “Oferta aceptada” (`transport_request_service.dart:262-284`). Nuevo: chofer → “Nuevo viaje disponible en tu zona: se cobra $X, te toca $Y (Z%)”; cliente → “Chofer asignado / en camino”. Requiere nuevos `NotificationType` (`notification_model.dart:1-10,14-29`), textos en `notification_service.dart` y en el `background_service`, y push del nuevo evento.
- **`background_service.dart`**: la rama chofer escucha INSERT de solicitudes y filtra por radio creciente (`:300-338,377-407,500-520`). Pasa a filtrar por **zona del chofer** (o a consumir un RPC de disponibilidad) y a mostrar el **precio neto y %** en la notificación. La rama cliente (`:442-465,521-537`) se sustituye por seguimiento de su solicitud.
- **`completion_sync_service.dart`**: `_syncOne` reenvía `p_precio_final`/`p_precio_base` desde el cliente (`:99-111`); con precio fijo el servidor **no debe aceptar precios del cliente**: el RPC debe leer la tarifa congelada en `solicitudes`/`viajes`. La rama chofer (`:126-141`) sigue aplicando, pero `solicitudes`/`viajes` necesitan políticas o RPC (ver §4.3).
- **`trip_completion_qr_service.dart`**: el payload incluye `precio` y `precio_base` (`:26-34`) y el secreto HMAC está hardcodeado (`:11`). Con precio fijo el QR debe transportar `solicitud_id`/`viaje_id` y el **precio congelado** (no editable) y verificarse contra BD cuando haya red; el secreto debe moverse a secreto de servidor o rotarse.
- **Historial (`request_history_screen.dart`)**: reanudar (`:125-130`) y “abrir viaje aceptado” (`:132-141`) dependen de ofertas; debe mostrar estado “buscando chofer / chofer asignado / en curso / completado” y el desglose de tarifa.
- **`driver_offers_screen.dart`**: se elimina completa (ver N15); su `MapWidget` y `DriverOfferCard` dejan de usarse.
- **Valoraciones**: `valoraciones_viaje` no cambia de esquema, pero el `driver_id` ya no se obtiene de `acceptedOffer` (`ride_confirmed_screen.dart:405,566-583`) sino de la solicitud/viaje.
- **Wallet/comisión**: los cierres salen de `acceptedOffer.precio` (`transport_provider.dart:348,494,498`; `ride_confirmed_screen.dart:539`). Debe pasar a `solicitud.precio_plataforma`/`precio_chofer` congelados; y el % de comisión deja de ser `0.15` literal (ver §3).
- **Superadmin**: el tab “Ofertas” (`muevete_requests_screen.dart:74`) queda histórico; `MueveteService.getOffers()` (`:91-102`) se mantiene solo para consulta de datos legacy.
- **Datos legacy**: `ofertas_chofer` seguirá teniendo filas históricas; no se debe `DROP` la tabla en la primera migración (rompe consultas de historial, superadmin y `transport_request_service.dart:145-157` que cuenta viajes completados desde ofertas). Estrategia: dejar de escribir, mantener lectura, y planificar archivo/limpieza después de un periodo de gracia.

---

## 3. Cálculo de precio actual

### 3.1 Fórmula exacta (cliente Dart, `transport_provider.dart:149-164`)

```
si no hay tipo de vehículo o distancia == 0 → no calcula
precio_km   = vehicle_type.precio_km_default
min_price   = vehicle_type.precio_inside_sc  (si es NULL → distancia_km * precio_km)
pickup_in   = haversine(centro_SC, pickup) <= 2.53 km
dropoff_in  = haversine(centro_SC, dropoff) <= 2.53 km

si pickup_in Y dropoff_in:
    oferta = redondear(min_price, 2)
si no:
    oferta = redondear(min_price + distancia_km * precio_km, 2)
```

- Centro y radio: `utils/constants.dart:72-74` (`22.40689, -79.96450`, `2.53 km`).
- `distancia_km` viene del routing (`transport_provider.dart:199-204`, `routing_service.getRoute`), no de Haversine.
- La UI además muestra por tarjeta `precio_inside_sc ?? precio_km_default * distancia` (`route_preview_screen.dart:466-470`).
- El precio viaja al servidor en `sendRequest()` (`transport_provider.dart:240`) y se guarda en `solicitudes_transporte.precio_oferta`.
- `vehicle_type.precio_espera_min` se cobra aparte al completar: `minutos_espera = ceil(segundos/60)`, `cobro_espera = minutos * precio_espera_min` (`ride_confirmed_screen.dart:428-445`; `CAMBIOS_PARADAS_ESPERA.md:48-55`).

### 3.2 Dónde se usan `precio_inside_sc` / `precio_km_default` / `precio_x_km`

| Campo | Usos |
|---|---|
| `precio_inside_sc` | `transport_provider.dart:153`; `route_preview_screen.dart:58,466`; `vehicle_type_model.dart:10,40-42` |
| `precio_km_default` | `transport_provider.dart:152`; `route_preview_screen.dart:59,467,470`; `vehicle_type_model.dart:7,35`; mostrado en perfil del chofer (`auth_service.dart:76`) |
| `tiempo_min_por_km` | `vehicle_type_model.dart:36-38,54-63` (ETA) |
| `precio_espera_min` | `ride_confirmed_screen.dart:126,140`; `active_ride_screen.dart:554,559,875,889` |
| `configuracion_navegacion.precio_x_km` | **Sin uso** (grep sin resultados en `lib/`) |
| `vehicle_type.categoria` | **No existe en el esquema volcado** (`muevete_schema.sql:247-257`) pero el modelo lo lee (`vehicle_type_model.dart:24-34`) y `VehicleTypeService` filtra por él en cliente (`vehicle_type_service.dart:30-31`) |

### 3.3 Incoherencias y deuda detectadas

| # | Incoherencia | Evidencia | Efecto |
|---|---|---|---|
| I1 | El modelo Dart lee `precio_espera_minuto`, la columna real es `precio_espera_min` | `vehicle_type_model.dart:43-45` vs `muevete_schema.sql:255` (y `CAMBIOS_PARADAS_ESPERA.md:37`) | `precioEsperaMinuto` siempre 0 en la app; el cobro real se hace con consultas ad-hoc (`ride_confirmed_screen.dart:126`, `active_ride_screen.dart:554,875`) |
| I2 | `wallet_drivers.current_balance` (migración) vs `balance` (real) | `001_new_tables.sql:49` vs `muevete_schema.sql:226`; `wallet_service.dart:30-33` usa `balance` | Migración 001 desfasada; quien la replique rompe la wallet |
| I3 | `viajes.driver_id` es `smallint`, `drivers.id` es `bigint` | `muevete_schema.sql:176` vs `:41` | Límite 32 767 (irrelevante hoy, pero incompatible con secuencias bigint y con FKs de otras tablas) |
| I4 | `viajes` no tiene `solicitud_id`; el vínculo es vía `ofertas_chofer` | `muevete_schema.sql:173-189`; `ride_confirmed_screen.dart:147-160`; `home_map_screen.dart:204-231` | **Bloqueante** para eliminar ofertas: hay que añadir la FK |
| I5 | `viajes.user` es `varchar` sin FK; se compara con `auth.uid()::text` | `muevete_schema.sql:177`; `003_enable_realtime.sql:58` | Sin integridad referencial; posibles huérfanos |
| I6 | `solicitudes_transporte` no tiene `driver_id`, ni `precio_plataforma`, ni `comision_pct`, ni `zona_id` | `muevete_schema.sql:190-209` | No hay dónde congelar la tarifa ni auditar la comisión |
| I7 | Comisión 15% hardcodeada en 4 sitios | `transport_provider.dart:487`; `wallet_service.dart:231,254,262,296,304`; `complete_ride_payment_rpc.sql:55,71,89` | Cambiar comisión exige desplegar apps + recrear RPC |
| I8 | Recarga 11% hardcodeada en UI y servicio | `wallet_service.dart:48,58,98,108`; `wallet_screen.dart:73,171,299`; `driver_wallet_screen.dart:78,176,310` | Idem; además el 11% no se registra como transacción separada |
| I9 | `solicitudes.precio_oferta` es NOT NULL en 001 (`:14`) y nullable en el esquema real (`:198`) | Divergencia migración/BD | El nuevo flujo necesitará nullable o renombrar el campo |
| I10 | CHECK de `transacciones_wallet.tipo` tiene 3 valores en 001 (`:67`) y 5 en la BD (`:235`) | Divergencia | Replicar migraciones produce errores |
| I11 | `transport_request_service.dart:145-157` cuenta viajes completados leyendo `ofertas_chofer` | — | Si se deja de escribir ofertas, el `trip_count` del chofer se congela |
| I12 | El precio del cierre viene del cliente (`precio_final`, `precio_base`) | `transport_provider.dart:494-508`; `completion_sync_service.dart:99-111`; `complete_ride_payment_rpc.sql:5-12` | Cualquier cliente modificado puede pagar menos (hoy la única barrera es la UI) |
| I13 | `vehicle_type` se suscribe en realtime pero no está en la publicación | `vehicle_type_service.dart:36-47` vs `003_enable_realtime.sql:8-13` | Los cambios de tarifa no llegan en vivo |
| I14 | El precio “inside SC” usa un círculo, no el municipio real | `constants.dart:71-74` | Un punto a 2.6 km del centro paga km completo aunque esté en Santa Clara |

---

## 4. Esquema real de BD, RLS y qué habrá que crear

### 4.1 Constraints que ya existen (lo que el diseño nuevo debe respetar)

- `solicitudes_transporte`: PK `id`; FK `user_id → auth.users(id)` (`muevete_schema.sql:208`); en la migración 001: `user_id NOT NULL`, coords `NOT NULL`, `tipo_vehiculo` default `'auto'` y CHECK `moto|auto|microbus`, `precio_oferta NOT NULL`, `estado` CHECK `pendiente|aceptada|cancelada|expirada` (`001_new_tables.sql:6-25`) — el estado `completada` que usa el código **no está en ese CHECK** (la BD real sí lo admite; otra divergencia).
- `ofertas_chofer`: FK `solicitud_id → solicitudes_transporte ON DELETE CASCADE`, FK `driver_id → drivers`, CHECK estado `pendiente|aceptada|rechazada` (`001_new_tables.sql:29-42`).
- `viajes`: FK `driver_id → drivers` (`muevete_schema.sql:188`); sin FK de usuario; `id` identity.
- `wallet_drivers`: `driver_id UNIQUE` + FK (`muevete_schema.sql:223-230`).
- `transacciones_wallet`: FK `user_id → auth.users`, `driver_id → drivers`, `viaje_id → viajes`; CHECK de `tipo` (5 valores) y `estado` (4 valores) (`:231-246`).
- `vehicle_type`: PK identity; sin CHECKs de valores (`:247-257`).
- `valoraciones_viaje`: `viaje_id UNIQUE` (una valoración por viaje), FK driver/user, CHECK rating 1..5 (`:291-303`).
- `place`: PK compuesta `(id, driver)` con `driver UNIQUE` (`:88-104`).
- Índices existentes para el flujo: `idx_solicitudes_estado`, `idx_solicitudes_user`, `idx_solicitudes_expires`, `idx_ofertas_solicitud`, `idx_ofertas_driver`, `idx_transacciones_user/driver` (`001_new_tables.sql:72-78`).

### 4.2 RLS existente (según migraciones del repo)

| Tabla | Políticas | Líneas |
|---|---|---|
| `solicitudes_transporte` | `clients_own_solicitudes FOR ALL USING(auth.uid()=user_id)`; `drivers_see_solicitudes FOR SELECT USING(true)`; `superadmin_all_solicitudes_transporte` | `003:24-25,27-28`; `006:27-32` |
| `ofertas_chofer` | `drivers_own_ofertas FOR ALL`; `clients_see_their_ofertas FOR SELECT`; `superadmin_all_ofertas_chofer`; además `Drivers can create offers WITH CHECK(true)` y `Users can view offers ... USING(true)` de 001 | `003:33-45`; `006:37-42`; `001:109-118` |
| `viajes` | `driver_own_viajes FOR ALL (driver_id IN (select id from drivers where uuid=auth.uid()))`; `client_own_viajes FOR SELECT (auth.uid()::text = "user")`; `superadmin_all_viajes` | `003:50-58`; `006:47-52` |
| `place` | `authenticated_read_place`; `drivers_upsert_own_place FOR ALL`; `superadmin_all_place` | `003:63-71`; `006:97-102` |
| `drivers` | `superadmin_all_drivers`; `drivers_own_row FOR ALL` | `006:79-92` |
| `vehicle_type` | `superadmin_all_vehicle_type`; `authenticated_read_vehicle_type` | `006:126-140` |
| `users` | `superadmin_all_users`; `users_own_row` | `006:145-160` |
| `valoraciones_viaje` | `superadmin_all...`; `users_insert_own_valoraciones`; `authenticated_read_valoraciones` | `006:195-216` |
| `configuracion_navegacion` | `superadmin_all...`; `authenticated_read_configuracion` | `006:221-235` |
| `suscription_user` | `superadmin_all...`; `users_own_suscription FOR SELECT` | `006:240-254` |
| `wallet_drivers` | `superadmin_all_wallet_drivers`; `Drivers can view own wallet FOR SELECT USING(true)` | `006:57-62`; `001:131-134` |
| `transacciones_wallet` | `superadmin_all...`; `Users can view own transactions`; `Service can insert transactions WITH CHECK(true)` | `006:67-72`; `001:120-129` |
| `paradas_viaje` | `Drivers can manage their own stops`; `Clients can read stops for their trips` | `fix_rls_paradas.sql:5-22` |
| `notificaciones` | lectura/update propias; insert autenticado | `004_notifications.sql:23-31` |
| Función helper | `muevete.is_superadmin()` SECURITY DEFINER consultando `public.app_dat_superadmin` | `006:9-22` |

Publicación realtime actual: `solicitudes_transporte`, `ofertas_chofer`, `viajes`, `place` (`003:8-13`) + `notificaciones` (`004:18`).

### 4.3 Brechas de RLS que el rediseño debe cerrar

1. **El cliente puede seguir editando el precio.** `clients_own_solicitudes` es `FOR ALL` sin restricción de columnas (`003:24-25`): con el campo eliminado de la UI, un cliente modificado puede seguir haciendo `UPDATE precio_oferta`. → **Revocar UPDATE de tabla y exponer solo RPCs** (`crear_solicitud`, `cancelar_solicitud`), o `GRANT UPDATE (estado)` a nivel de columna. Requisito explícito del Lead.
2. **`drivers_see_solicitudes USING(true)`** (`003:27-28`): cualquier autenticado ve todas las solicitudes pendientes (direcciones y coordenadas). Con zonas, debe pasar a “solicitudes pendientes de mi zona” — y el cálculo de polígono no es viable dentro de una política RLS por coste; recomendación: **RPC `SECURITY DEFINER` `muevete.viajes_disponibles()`** que filtre por zona en servidor, y **eliminar la política global**.
3. **`Drivers can create offers WITH CHECK(true)`** (`001:109-112`): permite insertar una oferta con cualquier `driver_id`. Se elimina junto con la tabla lógica, pero mientras exista es un agujero de suplantación.
4. **INSERT de `viajes` desde el cliente**: `createViaje` se llama en `transport_provider.dart:361` con la sesión del cliente, pero la única política de INSERT es `driver_own_viajes` (`003:50-55`) → **falla si la BD real no tiene una política extra**. En el flujo nuevo el viaje lo crea el servidor (`tomar_viaje`), lo que resuelve el problema de raíz.
5. **UPDATE de `solicitudes` desde el chofer**: `completion_sync_service.dart:136-140` e `incoming_requests_screen.dart:629` actualizan `estado='completada'` con sesión de chofer; no hay política que lo permita (`003:22-28`, `001:92-106`). → mover a RPC de cierre.
6. **`wallet_service.holdClientFunds` / `refundClientFunds`** hacen UPDATE directo de `suscription_user.balance` (`wallet_service.dart:188-192,216-220`) y solo existe política SELECT (`006:250-254`) → **falla bajo RLS** salvo políticas no versionadas. Todo movimiento de wallet debe ir por RPC `SECURITY DEFINER`.
7. **`wallet_drivers` visible por cualquier autenticado** (`001:131-134`): expone saldos de todos los choferes.
8. **`transacciones_wallet` INSERT libre** (`001:126-129`): cualquier autenticado puede insertar transacciones.
9. **`ofertas_chofer` SELECT libre** (`001:115-118`): cualquier autenticado ve todas las ofertas.
10. **`place`**: `drivers_upsert_own_place FOR ALL` (`003:66-71`) sin `WITH CHECK` explícito usa `USING` para INSERT; funciona, pero conviene declararlo.

> **Supuesto A1:** las migraciones de `inventtia_muevete/docs/migrations/` no reflejan necesariamente la BD de producción (hay operaciones del código que no tendrían política). Antes de escribir la migración del rediseño hay que volcar `pg_policies` y `pg_publication_tables` reales.

### 4.4 Objetos a crear para zonas/tarifas (propuesta alineada con D1–D6)

```text
muevete.zonas_tarifa
  id            bigint identity PK
  nombre        text NOT NULL
  provincia     text
  municipio     text
  geometria     jsonb NOT NULL            -- GeoJSON Polygon (anillo exterior), dibujado en mapa
  modo          text NOT NULL CHECK (modo IN ('fijo','fijo_mas_km','por_km'))
  monto_fijo    numeric                    -- CUP; requerido si modo <> 'por_km'
  precio_km     numeric                    -- CUP/km; requerido si modo <> 'fijo'
  prioridad     integer NOT NULL DEFAULT 0 -- mayor gana cuando hay solape
  activo        boolean NOT NULL DEFAULT true
  vigente_desde timestamptz, vigente_hasta timestamptz
  created_at/updated_at

muevete.tarifas_municipio        -- fallback D4 (fuera de toda zona)
  id, provincia, municipio, monto_fijo DEFAULT 1500, precio_km, activo
  UNIQUE (provincia, municipio)

muevete.configuracion_tarifas    -- fila única global
  id, moneda text DEFAULT 'CUP',
  comision_pct numeric DEFAULT 15,          -- D5
  recarga_pct numeric DEFAULT 11,           -- centraliza el 11% actual
  limite_deuda_efectivo numeric DEFAULT 500, -- D6
  multiplicadores jsonb,                    -- opcional; o columna en vehicle_type
  updated_at

ALTER TABLE muevete.vehicle_type
  ADD COLUMN multiplicador_tarifa numeric NOT NULL DEFAULT 1;  -- D2 (moto 0.6, auto 1, microbus 1.5)

ALTER TABLE muevete.solicitudes_transporte
  ADD COLUMN driver_id bigint REFERENCES muevete.drivers(id),
  ADD COLUMN aceptada_at timestamptz,
  ADD COLUMN zona_id bigint REFERENCES muevete.zonas_tarifa(id),
  ADD COLUMN tarifa_modo text,
  ADD COLUMN precio_plataforma numeric,   -- lo que paga el cliente (congelado)
  ADD COLUMN comision_pct numeric,        -- copia del % vigente al crear
  ADD COLUMN precio_chofer numeric,       -- neto para el chofer (congelado)
  ADD COLUMN moneda text DEFAULT 'CUP',
  ADD COLUMN tarifa_detalle jsonb;        -- snapshot: distancia, zona, multiplicador, desglose

ALTER TABLE muevete.viajes
  ADD COLUMN solicitud_id bigint REFERENCES muevete.solicitudes_transporte(id),
  ADD COLUMN precio_plataforma numeric,
  ADD COLUMN precio_chofer numeric,
  ADD COLUMN comision_pct numeric,
  ADD COLUMN metodo_pago text;
```

Funciones recomendadas (todas `SECURITY DEFINER`, `search_path = muevete`):

- `fn_punto_en_poligono(lat, lon, geojson) → boolean` — ray casting en PL/pgSQL (el repo asume que el plan Free no tiene PostGIS, `driver_service.dart:287`); si la BD real sí tiene PostGIS, usar `ST_Contains` y `geometry(Polygon,4326)` es preferible.
- `fn_zona_de_punto(lat, lon) → zonas_tarifa` — la zona activa de mayor `prioridad` que contiene el punto; si no hay, `tarifas_municipio`.
- `fn_cotizar_viaje(p_lat_o, p_lon_o, p_lat_d, p_lon_d, p_vehicle_type_id) → json` — implementa D2+D3:
  - zona origen y zona destino; si coinciden y `modo='fijo'` → `monto_fijo`.
  - `modo='fijo_mas_km'` → `monto_fijo + km_total * precio_km`.
  - `modo='por_km'` → `km_total * precio_km`.
  - si el viaje cruza zonas o sale de toda zona → D4: fijo del municipio del origen + `km_total * precio_km` del municipio (o solo fijo si `precio_km` es 0 — decidir en diseño).
  - aplicar `multiplicador_tarifa` del `vehicle_type` (D2) al resultado.
  - `comision = precio_plataforma * comision_pct/100`; `precio_chofer = precio_plataforma - comision`.
  - devolver desglose completo (para mostrarlo al cliente y al chofer).
- `fn_crear_solicitud(...) → solicitud` — calcula y congela la tarifa en servidor (el cliente no envía precio).
- `fn_tomar_viaje(p_solicitud_id) → viaje` — D6 + atomicidad: `UPDATE solicitudes SET estado='aceptada', driver_id=... WHERE id=p AND estado='pendiente'` con `RETURNING`; si no devuelve fila → “ya tomado”; validar deuda del chofer (`wallet_drivers.balance >= -limite_deuda_efectivo`); crear `viajes` en la misma transacción; notificar al cliente.
- `fn_completar_viaje(p_viaje_id)` — deriva precio/comisión de la solicitud/viaje (no del cliente), aplica comisión, registra transacción, cierra.
- Índices: `solicitudes (estado, created_at)`, `solicitudes (driver_id)`, `zonas_tarifa USING gin (geometria jsonb_path_ops)` (no acelera point-in-polygon, pero sirve para filtrar), `viajes (solicitud_id) UNIQUE`.

Políticas RLS a añadir (patrón 006):

- `zonas_tarifa`, `tarifas_municipio`, `configuracion_tarifas`: `superadmin_all_*` con `muevete.is_superadmin()`; `SELECT` para `authenticated` (el cliente necesita ver el desglose; el chofer también).
- `solicitudes_transporte`: sustituir `clients_own_solicitudes FOR ALL` por `SELECT` propio + `INSERT` bloqueado (solo vía RPC; o `WITH CHECK` que no permita precio: imposible asegurar columnas → RPC); añadir `SELECT` de pendientes **solo vía RPC** o política con zona calculada por función `fn_zona_de_punto` (coste alto; preferible RPC).
- `viajes`: `SELECT` para cliente dueño (`auth.uid()::text = "user"`) y chofer (`driver_id`); INSERT/UPDATE solo por RPC `SECURITY DEFINER` (revocar escritura directa).
- `wallet_drivers`: quitar `USING(true)`; `SELECT` propio; escrituras solo por RPC.
- `transacciones_wallet`: quitar INSERT libre; solo RPC y `SELECT` propio.
- Publicación realtime: añadir `zonas_tarifa`/`tarifas_municipio` solo si se quiere refresco en vivo de tarifas; **`solicitudes_transporte` y `viajes` ya están publicadas**.

---

## 5. Estado del superadmin y qué reutilizar

### 5.1 Patrón de las pantallas `muevete_*`

Todas siguen el mismo molde (ejemplo canónico: `lib/screens/muevete/muevete_trips_screen.dart`):

1. `StatefulWidget` con `_isLoading`, lista `List<Map<String,dynamic>>`, filtro local y `initState() → _loadData()` (`muevete_trips_screen.dart:12-29`).
2. Datos vía `MueveteService` **estático** (`muevete_service.dart:4-5`), que usa `Supabase.instance.client` con `.schema('muevete')`.
3. UI: `Scaffold` + `AppDrawer` + `CustomScrollView`/`SliverAppBar`; `_statCard` de resumen; chips de filtro; `DataTable` en desktop y cards en móvil según `PlatformUtils.shouldUseDesktopLayout` (`muevete_trips_screen.dart:40-71,74-112,114-170`).
4. Sin estado global ni provider: todo local a la pantalla.
5. Estilo: colores literales (`0xFF6366F1` primario, `0xFFF0F2F5` fondo, `0xFF1E293B` texto), sin `AppTheme` en estas pantallas.

### 5.2 Registro de rutas y permisos (3 sitios + permisos)

1. **Ruta en `main.dart`** dentro de `routes:` con `RouteGuard`: `'/muevete/...': (context) => const RouteGuard(route: '/muevete/...', child: MueveteXScreen())` (`main.dart:194-244`; import de las pantallas `:31-41`; `RouteGuard` importado en `:59`).
2. **Metadatos en `AppRoutes.protected`**: `AppRoute(route: '/muevete/...', label: '...', group: 'Muévete')` (`config/app_routes.dart:21,96-142`) — alimenta la UI de permisos por rol.
3. **Menú lateral**: sección “Inventtia Muévete” con `_DrawerItem` (`widgets/app_drawer.dart:159-219`).
4. **Permisos**: `RouteGuard` consulta `AuthService.canAccessRoute(route)` (`widgets/route_guard.dart:19`), que compara contra `admin.permisosRutas` y `AppRoutes.alwaysAllowed` (`services/auth_service.dart:240-252`). Las rutas nuevas deben añadirse a `AppRoutes.protected` y asignarse a los roles (`superadmin_role_service.dart:43,65` gestiona `permisos`). **Sin esto, el superadmin verá “Acceso denegado”.**

### 5.3 `lib/services/muevete_service.dart` (648 líneas)

- Métodos estáticos agrupados por dominio: conductores `10-28`, viajes `33-57`, solicitudes `62-86`, ofertas `91-102`, valoraciones `107-118`, posiciones `123-139`, historial GPS `142-154`, wallets `159-277`, KYC `282-310`, viaje activo `315-355`, stats `360-416`, planes `422-557`, cargas `562-647`.
- No hay métodos para `vehicle_type`, `zonas`, `tarifas` ni `configuracion_tarifas`.
- Patrón de escritura: UPDATE directo (`.from('drivers').update(...)`, `:22-28`) y RPC para operaciones sensibles (`fn_aprobar_solicitud_plan`, `:537-543`). Para zonas/tarifas: **lectura directa + escritura directa** (superadmin tiene `ALL` vía `is_superadmin()`), y RPCs solo para operaciones transaccionales (cotizar, simular).

### 5.4 Qué reutilizar para la pantalla de zonas

| Reutilizable | Dónde | Uso |
|---|---|---|
| `flutter_map` + `latlong2` ya en dependencias | `ventiq_superadmin/pubspec.yaml:40-41` | Dibujar polígonos con `PolygonLayer` + `MapController` |
| Base de mapa, capas, estilos | `muevete_map_screen.dart:1-59` | Copiar estructura (mapa + panel + realtime) |
| Patrón lista/tabla/cards + filtros + stats | `muevete_trips_screen.dart:40-170` | Listado de zonas y municipios |
| `MueveteService` estático | `muevete_service.dart` | Añadir `getZonas()`, `upsertZona()`, `deleteZona()`, `getTarifasMunicipio()`, `getConfiguracionTarifas()`, `updateConfiguracionTarifas()` |
| Registro de ruta + permiso | `main.dart:194-244`, `app_routes.dart:96-142`, `app_drawer.dart:159-219`, `route_guard.dart:19` | Nueva entrada `/muevete/zonas` |
| RPC como patrón de operación sensible | `muevete_service.dart:537-557` | `fn_cotizar_viaje` para previsualizar tarifa desde el admin |

**Lo que no existe y hay que construir:** editor de polígonos (tocar mapa → vértices → cerrar → guardar GeoJSON), validación de auto-intersección, previsualización de tarifa para un origen/destino de prueba, gestión de multiplicadores por `vehicle_type`, y pantalla de configuración global (comisión %, recargo recarga, límite de deuda, fijo municipal por defecto 1500 CUP).

---

## 6. Riesgos y trampas

1. **Doble aceptación (D6/“primero gana”)**: sin una operación atómica, dos choferes pueden “tomar” el mismo viaje entre el SELECT y el UPDATE. Mitigación obligatoria: `UPDATE ... WHERE estado='pendiente'` + `RETURNING` en RPC, o `unique index` parcial + manejo del error; nunca “comprobar y luego escribir” desde el cliente.
2. **Datos legacy**: `ofertas_chofer` con filas históricas, solicitudes con `precio_oferta` del modelo anterior, `viajes` sin `solicitud_id` y wallets con comisiones del 15% registradas. El histórico debe seguir siendo legible (superadmin, `request_history`); no borrar tablas/columnas en el primer despliegue.
3. **Dispositivos con versiones viejas**: la app se distribuye fuera de tiendas (hay `update_service.dart`/`update_checker`); clientes/choferes con builds antiguos seguirán creando ofertas y leyendo `precio_oferta`. Hay que decidir: (a) forzar actualización, (b) mantener doble escritura temporal, o (c) que el backend ignore ofertas y el viaje se publique igual. **Riesgo alto de incoherencia durante la transición.**
4. **RLS y RPC**: casi todo el flujo nuevo depende de RPCs `SECURITY DEFINER`. Un `SECURITY DEFINER` mal escrito (sin `search_path`, sin validar `auth.uid()`, sin comprobar estado) es equivalente a un agujero de escritura total. Revisar `SET search_path`, `SET row_security` y permisos `REVOKE ALL ... FROM PUBLIC`.
5. **Realtime**: si se elimina `ofertas_chofer` de los canales pero no se publica/actualiza `solicitudes_transporte` con los nuevos estados, el cliente no verá “chofer asignado” y el chofer no verá “viaje tomado” (el heartbeat no arregla un evento que nunca se publica). Además, el canal de `vehicle_type` ya está muerto (`I13`) y las zonas/tarifas probablemente tengan el mismo problema.
6. **Rendimiento**: point-in-polygon en PL/pgSQL para cada solicitud es aceptable a la escala de Santa Clara (decenas de zonas, no miles), pero **no** lo es hacerlo en RLS por fila en un SELECT global; y hoy ya hay patrones caros en cliente: `getNearbyDrivers` descarga **todos** los `place` online y filtra Haversine en Dart (`transport_request_service.dart:52-95`), y `_loadNearbyRequests` trae 50 solicitudes y filtra por radio (`driver_service.dart:270-314`). El nuevo “viajes disponibles por zona” debe resolverse en servidor.
7. **Precio congelado y auditoría**: si el precio se recalcula al cerrar, un cambio de tarifa entre la creación y el cierre altera el importe. Debe guardarse el snapshot (precio, %, comisión, zona, distancia, multiplicador) al crear la solicitud y usarse al cerrar.
8. **Deuda de efectivo (D6)**: permitir saldo negativo cambia la semántica de `wallet_drivers.balance` (hoy tratado como “saldo disponible” en `driverHasEnoughForCommission`, `wallet_service.dart:301-305`). Hay que distinguir “saldo” y “deuda”, definir qué pasa al llegar al tope (bloqueo del botón “Tomar viaje”) y cómo se cobra la deuda (recarga posterior). También afecta a la UI del chofer y al superadmin (billeteras).
9. **Multiplicador por tipo (D2)**: si el multiplicador vive en `vehicle_type`, el cliente necesita leerlo (hoy `authenticated_read_vehicle_type` ya lo permite) y el superadmin necesita una pantalla para editarlo (no existe). Si el multiplicador se aplica en servidor, la UI debe mostrar el desglose para que el chofer entienda “te toca tanto %”.
10. **`driver_id smallint` (I3)**: cualquier tabla nueva que referencie `viajes`/`drivers` debe usar `bigint`; si se “arregla” `viajes.driver_id` a `bigint` habrá que migrar con cuidado (FK, índices, datos).
11. **Moneda**: todo el código formatea con `$` y `Helpers.formatCurrency` sin moneda (`driver_service.dart:144` muestra “Gs.”!). Asumir CUP y mostrar `$` es decisión de producto; debe centralizarse para no repetir el bug.
12. **Fallback municipal (D4)**: “fijo del municipio” requiere que el origen tenga municipio resoluble. Hoy el chofer/cliente no envían provincia/municipio en la solicitud (`muevete_schema.sql:190-209`); habrá que resolverlo por polígono municipal o por el municipio de la zona; si no, el fallback aplicará a todo lo que no caiga en una zona (incluido un punto remoto), lo que puede dar un fijo de 1500 CUP para un viaje de 40 km.

---

## 7. Tabla de impacto (archivo → cambio → riesgo)

| Archivo | Cambio requerido | Riesgo |
|---|---|---|
| `inventtia_muevete/lib/providers/transport_provider.dart` | Eliminar `setOfferPrice/_calculatePrice/_isInsideCityZone/acceptOffer/declineOffer/_onNewOffer/_onOfertaUpdate/pollOffers`; reescribir `sendRequest` (RPC cotizar/crear), `restore*`, `cancelRequest`, `completeRideWithPayment` | Alto: es el corazón del flujo; toca 8 pantallas |
| `inventtia_muevete/lib/screens/client/route_preview_screen.dart` | Quitar campo “Tu Oferta” y validaciones locales; mostrar desglose; navegar a “buscando chofer” | Medio: UI y textos de precio |
| `inventtia_muevete/lib/screens/client/driver_offers_screen.dart` | **Eliminar** | Bajo (código muerto) pero rompe imports/rutas |
| `inventtia_muevete/lib/screens/client/ride_confirmed_screen.dart` | Precio desde solicitud/viaje; chofer desde `solicitud.driver_id`; cierre vía RPC sin precio del cliente | Alto: dinero y valoraciones |
| `inventtia_muevete/lib/screens/client/home_map_screen.dart` | Tracking del chofer vía `solicitudes.driver_id`/`viajes`; quitar consulta a `ofertas_chofer` | Medio |
| `inventtia_muevete/lib/screens/client/request_history_screen.dart` | Estados nuevos; quitar “reanudar ofertas” | Bajo |
| `inventtia_muevete/lib/screens/driver/driver_home_screen.dart` | Eliminar diálogo/oferta duplicados; lista de viajes disponibles con neto y % | Alto: pantalla principal del chofer |
| `inventtia_muevete/lib/screens/driver/incoming_requests_screen.dart` | Quitar contraoferta y chequeo 15%; “Tomar viaje” con deuda; canales nuevos | Alto |
| `inventtia_muevete/lib/screens/driver/active_ride_screen.dart` | Sin cambio funcional; precio/comisión desde snapshot | Bajo |
| `inventtia_muevete/lib/services/transport_request_service.dart` | Eliminar ofertas; añadir RPCs de cotización/creación/toma; canales de solicitud | Alto |
| `inventtia_muevete/lib/services/driver_service.dart` | Eliminar `makeOffer/hasExistingOffer/subscribeToMyOfferAcceptances`; añadir `viajesDisponibles()`/`tomarViaje()`; corregir `trip_count` | Medio |
| `inventtia_muevete/lib/services/wallet_service.dart` | Comisión desde config; deuda/negativo; RPC de cierre sin precios del cliente; centralizar 11% | Alto: dinero |
| `inventtia_muevete/lib/services/background_service.dart` | Canales de ofertas → canales de solicitud; notificación de viaje disponible con neto/%; polling de ofertas del cliente fuera | Alto: notificaciones y foreground |
| `inventtia_muevete/lib/services/completion_sync_service.dart` | `_syncOne` sin `precio_final/precio_base`; cerrar vía RPC | Medio |
| `inventtia_muevete/lib/services/trip_completion_qr_service.dart` | Payload con snapshot y sin precios editables; secreto fuera del código | Medio |
| `inventtia_muevete/lib/services/notification_service.dart` + `models/notification_model.dart` | Nuevos tipos (`nuevo_viaje_disponible`, `viaje_tomado`); retirar `nueva_oferta`/`oferta_aceptada` | Bajo |
| `inventtia_muevete/lib/models/driver_offer_model.dart`, `widgets/driver_offer_card.dart` | Deprecar/eliminar | Bajo |
| `inventtia_muevete/lib/utils/constants.dart` | Quitar círculo SC y radios de ofertas; conservar centro de mapa | Bajo |
| `inventtia_muevete/lib/main.dart` | Quitar ruta `/client/driver-offers` e import; posible nueva ruta “buscando chofer” | Bajo |
| `inventtia_muevete/muevete_schema.sql` + `docs/migrations/*` | Nueva migración: tablas de zonas/tarifas/config, columnas en solicitudes/viajes/vehicle_type, RPCs, RLS, publicación | **Crítico** |
| `docs/migrations/complete_ride_payment_rpc.sql` | Rehacer firma (sin precios del cliente), comisión configurable, deuda | **Crítico** (dinero) |
| `docs/migrations/003_enable_realtime.sql` | Revisar publicación y políticas (quitar global de solicitudes) | Alto |
| `docs/migrations/006_superadmin_rls.sql` | Añadir políticas para las tablas nuevas | Medio |
| `ventiq_superadmin/lib/services/muevete_service.dart` | Añadir CRUD de zonas, tarifas municipales y configuración global | Medio |
| `ventiq_superadmin/lib/screens/muevete/muevete_zonas_screen.dart` (nuevo) | Editor de polígonos + tarifas + multiplicadores + simulación | Alto (nuevo desarrollo) |
| `ventiq_superadmin/lib/main.dart` | Registrar `/muevete/zonas` con `RouteGuard` | Bajo (si falta el permiso, “Acceso denegado”) |
| `ventiq_superadmin/lib/config/app_routes.dart` | Añadir `AppRoute` en `protected` | Bajo |
| `ventiq_superadmin/lib/widgets/app_drawer.dart` | Añadir entrada de menú | Bajo |
| `ventiq_superadmin/lib/screens/muevete/muevete_requests_screen.dart` | Tab “Ofertas” → histórico o retirar | Bajo |
| `inventtia_muevete/lib/screens/client/wallet_screen.dart`, `driver_wallet_screen.dart` | Centralizar 11% y mostrar deuda (D6) | Medio |

---

## Supuestos

- **S1.** El backend de producción es el Supabase del repo (`config/supabase_config.dart`) y las migraciones de `inventtia_muevete/docs/migrations/` están total o parcialmente aplicadas; hay políticas/objetos no versionados (ver §4.3). **Debe verificarse con `pg_policies` y `pg_publication_tables` antes de migrar.**
- **S2.** Moneda única CUP mostrada como `$` (decisión del Lead); no hay conversión ni multimoneda en taxi.
- **S3.** Alcance solo taxi de pasajeros (`vehicle_type` con `categoria` efectiva ‘pasajero’); `cargas`, `ofertas_carga`, `dispatcher` y `carrier` **no** se tocan.
- **S4.** El proveedor de mapas/routing actual (OSM + `routing_service`) sigue disponible; `distancia_km` seguirá siendo la distancia de ruta, no Haversine.
- **S5.** El plan de Supabase no tiene PostGIS (supuesto del propio repo, `driver_service.dart:287`), por lo que el point-in-polygon se implementará en PL/pgSQL; si hay PostGIS, se sustituye por `ST_Contains` sin cambiar el contrato de la función.
- **S6.** Las zonas se definen con un único anillo exterior (sin agujeros ni multipolígonos) en la primera versión; el modelo `jsonb` permite evolucionar a `MultiPolygon`.
- **S7.** “Zona que ofrece viajes” = zona activa cuyo polígono contiene el origen de la solicitud y en la que el chofer está online (`place.estado=true` + `drivers.estado=true`); la pertenencia del chofer se calcula por su posición actual, no por un campo de perfil.
- **S8.** La deuda de efectivo se mide sobre `wallet_drivers.balance` (negativo) con tope `limite_deuda_efectivo`; no se crea una tabla de deudas separada en la primera versión.
- **S9.** Los clientes/choferes con versiones antiguas de la app no se pueden actualizar de forma forzosa desde el backend en el corto plazo; la transición requiere una ventana de compatibilidad.
- **S10.** Los números de línea citados son de la versión del repo leída el 2026-11-12; cambios posteriores pueden desplazarlos.

---

## Riesgos

1. **Dinero**: comisión/deuda/precio congelado tocan `wallet_service`, el RPC de cierre y el QR offline. Un error aquí produce cobros incorrectos o saldos negativos no controlados. Prioridad máxima de pruebas.
2. **Carrera de aceptación**: sin RPC atómico hay doble asignación; es el fallo más visible para el usuario y el más difícil de reparar después.
3. **Transición con apps viejas**: convivencia de ofertas y viajes publicados; sin una estrategia explícita (forzar update o doble escritura) habrá solicitudes que nunca reciban chofer o choferes que contraoferten a un viaje ya tomado.
4. **RLS/RPC mal cerrados**: `SECURITY DEFINER` sin validaciones permite a un cliente manipular precios, comisiones o aceptar viajes ajenos.
5. **Realtime silencioso**: canales que dejan de emitir (o que nunca emitieron, como `vehicle_type`) producen pantallas congeladas sin error visible.
6. **Editor de polígonos**: es desarrollo nuevo en superadmin (no hay precedente útil; `carnaval_geo_admin_screen.dart` es un stub). Sin validación de geometría, una zona inválida puede romper la cotización de toda una ciudad.

---

## Recomendación

1. **Cerrar primero el contrato de datos y el servidor** (fase 1): migración con `zonas_tarifa`, `tarifas_municipio`, `configuracion_tarifas`, columnas snapshot en `solicitudes`/`viajes`, `vehicle_type.multiplicador_tarifa`, y los RPCs `fn_cotizar_viaje`, `fn_crear_solicitud`, `fn_tomar_viaje`, `fn_completar_viaje`. Sin esto, cualquier cambio de UI se hará dos veces.
2. **Congelar la tarifa al crear la solicitud** y no recalcularla al cerrar; guardar `precio_plataforma`, `comision_pct`, `precio_chofer`, `zona_id`, `tarifa_modo`, `tarifa_detalle`. El cierre (online, offline y QR) debe leer ese snapshot, nunca precios enviados por el cliente.
3. **Cerrar RLS antes de publicar el flujo nuevo**: eliminar `drivers_see_solicitudes USING(true)`, revocar UPDATE del cliente sobre `solicitudes`, mover escrituras de `viajes`/`wallet` a RPCs `SECURITY DEFINER`, y sustituir la visibilidad de viajes disponibles por un RPC scoped a la zona. Verificar contra la BD real (§4.3).
4. **Implementar la toma de viaje como operación atómica** (`UPDATE ... WHERE estado='pendiente' RETURNING`) con validación de deuda (D6) y creación del `viaje` + `solicitud.driver_id` en la misma transacción; el cliente solo se suscribe a su solicitud.
5. **Construir el editor de zonas en superadmin** reutilizando `muevete_map_screen.dart` (flutter_map ya disponible): tocar mapa → vértices → cerrar polígono → guardar GeoJSON; pestañas para tarifas municipales (fallback 1500 CUP), multiplicadores por tipo y configuración global (comisión 15%, recargo 11%, tope de deuda).
6. **Plan de transición explícito**: mantener `ofertas_chofer` en solo-lectura, ignorar ofertas nuevas en el servidor, publicar el viaje igualmente y mostrar en las apps viejas un aviso de actualización obligatoria; retirar la tabla/columnas en una migración posterior.
7. **Pruebas mínimas antes de liberar**: cotización con 0/1/2 zonas y solape, viaje que cruza zona, fallback municipal, multiplicadores, doble aceptación concurrente, cierre online/offline/QR con precios manipulados, cancelación con reembolso, y RLS (cliente no puede UPDATE precio; chofer solo ve su zona).