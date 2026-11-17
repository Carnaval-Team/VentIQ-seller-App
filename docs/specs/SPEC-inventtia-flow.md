# Spec: inventtia-flow (GoReserva)

Línea base as-built de `inventtia_flow` solamente. Describe lo que la app hace hoy. Cada afirmación lleva una marca:

- **Observado** — está en el código, en un test de esta app, o en una RPC leída en main el 2026-11-14.
- **Inferido** — se sigue del comportamiento, sin un test que lo fije.
- **Abierto** — el código no decide si ese comportamiento es el deseado.

El TPV, Gestión y Muevete no forman parte de esta spec. El plan `PLAN_PRECIOS_PAGOS_CALENDARIO.md` y los docs de monetización describen trabajo de producto. Aquí manda lo que el cliente llama y lo que main aplica.

## Objective

**Observado.** GoReserva (`pubspec.yaml`: `inventtia_flow` 1.5.0+16, descripción «Gestión de colas y turnos de servicios») publica locales y servicios, reserva turnos y cobra por adelantado. El título de la app es `GoReserva`. Debug habla con newa. Release habla con main. Las dos usan el esquema `flow` y la clave anónima. Los datos de negocio no viven en SQLite.

Quién entra:

| Quién | De dónde sale | Qué ve |
|---|---|---|
| Cliente | Sesión con perfil y sin entidades a cargo | Home, catálogo, listas, tickets y perfil |
| Vendedor | Fila de vendedor en al menos una entidad | El panel de vendedor de esas entidades |
| Admin | Fila de administrador en al menos una entidad | Gestión de esas entidades. Puede «ver como cliente» y volver |

`isAdmin` es verdadero si `getMisEntidades` devuelve algo. `isVendedor` es verdadero si `getMisEntidadesComoVendedor` devuelve algo. Una persona puede ser las dos. Sin perfil, el splash manda a `/perfil-setup`. Sin sesión, a `/login`. Con perfil, a `/home`.

Éxito para esta app: un cliente reserva un turno que el servicio ofrece, paga por adelantado solo si el local lo activó, y el admin solo verifica ese pago mientras la reserva sigue en Reservado.

## Tech Stack

**Observado.**

- Flutter / Dart SDK `^3.8.1`. Material, locale `es`. Estado con `provider`. Cliente `supabase_flutter` ^2.8.4.
- Preferencias locales con `shared_preferences`. Imágenes con `cached_network_image`. Avisos locales con `flutter_local_notifications`.
- El SQL canónico de las RPC de `flow` vive en `inventtia_flow/docs/flow_schema/`.

## Commands

Desde `inventtia_flow`. En Windows, si el wrapper Bash de Flutter no produce salida, usar `flutter.bat`.

```
flutter pub get
flutter analyze
flutter test
flutter run
```

Contratos de esta línea base, sin red:

```
flutter test --no-pub test/pago_reserva_bloqueo_test.dart test/estado_pago_test.dart test/motivo_cancelacion_test.dart test/precio_config_test.dart test/conversion_precio_test.dart test/verificacion_precios_test.dart
```

Esos tests fijan reglas del cliente. No sustituyen ejecutar la RPC en PostgreSQL.

## Project Structure

**Observado.** Código en `inventtia_flow/`.

```
lib/main.dart                 Arranque y rutas
lib/screens/home_shell.dart   Pestañas según cliente, vendedor o admin
lib/screens/admin/            Gestión, reservas, precios, cobros
lib/screens/vendedor/         Agenda del vendedor
lib/services/                 Una RPC de flow por oficio
lib/utils/                    Estado de pago, motivo de cancelación, precios
test/                         Contratos sin Supabase
docs/flow_schema/             SQL canónico de las RPC
```

Rutas con nombre: `/splash`, `/login`, `/register`, `/perfil-setup`, `/home`, `/notificaciones`, `/mi-suscripcion`. El resto del oficio se abre desde el shell.

## Qué hace la app

### Catálogo y reserva

**Observado.** El cliente explora con `cliente_home_feed`, `cliente_categorias_resumen`, `cliente_locales_publicos` y `cliente_obtener_servicios`. La disponibilidad sale de `cliente_obtener_disponibilidad`. Reservar llama `cliente_reservar_directo`. Un pasaje de ómnibus usa `cliente_reservar_pasaje_omnibus` y la disponibilidad de transporte. La sala de espera entra con `cliente_entrar_sala_espera_reserva`.

El admin crea la misma reserva con `admin_crear_reserva_directa` o `admin_reservar_pasaje_omnibus`. El staff cambia el estado con `staff_marcar_estado_agenda`. El precio de una reserva lo calcula `calcular_precio_reserva`, que delega en `flow.calcular_precio_con_reglas`. La cotización con promoción llama `cotizar_reserva`.

### Pago por adelantado

**Observado.** Los estados del pago, en `agenda.pago_estado`, son `pendiente`, `reportado`, `verificado`, `rechazado` y `expirado`. Un valor desconocido no se pinta. El cliente crea el intento con `cliente_crear_pago_reserva`, lo reporta con `cliente_reportar_pago_reserva` y lo consulta con `cliente_pago_reserva`. El admin lista, verifica o rechaza. `reserva_pago_expirar` recorre los vencidos usando los estados Reservado y Cancelado.

La pantalla de pagos no deja verificar un pago cuya reserva está Cancelada o Completada (`motivoNoVerificablePago`). En main, `admin_verificar_pago_reserva` también lo rechaza: solo sigue si el estado de la agenda es el de nombre `Reservado`.

### Precio, cobro y reseña

**Observado.** `admin_precio_config_set` guarda moneda de origen y redondeo de 0 a 2 decimales, y exige permiso sobre la entidad. `admin_cobro_config_set` exige el mismo permiso. El plazo de pago queda entre 1 y 720 horas. Activar el pago por adelantado exige el número de proveedor. La moneda de cobro tiene que estar soportada.

Una reseña exige sesión, puntuación de 1 a 5 y comentario de hasta 1000 caracteres. Solo la publica quien tuvo la reserva y ya fue atendido. Borrar la propia llama `eliminar_mi_resena`.

El aviso de versión usa `public.fn_check_update` y `public.fn_app_versiones`.

## Reglas que impone el servidor

**Verificado el 2026-11-14 en main**, esquema `flow`.

### Reservar

`cliente_reservar_directo` exige parámetros, el estado `Reservado` en el nomenclador, un servicio que exista, la reserva directa habilitada, un turno de ese servicio, cantidad de al menos 1 y no mayor que el máximo, y turnos suficientes. Si el servicio no permite reservar para terceros, lo rechaza. Sin turnos responde que no hay disponibles.

`admin_crear_reserva_directa` repite cantidad, turno y cupo, y exige permiso de administrador sobre el servicio.

`cliente_reservar_pasaje_omnibus` exige usuario autorizado, un servicio que admita pasajes, tipo de viaje válido, fecha y vehículo de cada trayecto, cantidad de al menos 1 y capacidad en la vuelta. El vehículo de ida o de vuelta inválido se rechaza. Tampoco deja reservar para terceros si el servicio no lo permite.

`cliente_entrar_sala_espera_reserva` exige usuario y local-servicio. Rechaza un local-servicio inexistente, un turno que no es del servicio, reservar para terceros cuando no está permitido, y demasiados intentos seguidos.

`cliente_cancelar_reserva` solo cancela reservas activas del propio usuario. Si falta menos tiempo que las horas de anticipación del servicio, responde «Solo puedes cancelar hasta N horas antes de la reserva».

`staff_cancelar_reserva` exige un motivo y una reserva que exista. El cliente, además, no acepta un motivo vacío ni uno de menos de 3 o más de 500 caracteres. El servidor exige que el motivo no llegue vacío.

`staff_marcar_estado_agenda` comprueba permiso sobre esa reserva antes de cambiarla.

### Pagar

`cliente_crear_pago_reserva` exige sesión, reserva existente, permiso sobre ella, reserva activa, pago por adelantado activado en el servicio, un precio configurado y tasa si se cobra en otra moneda. Un pago ya en curso bloquea otro: hay que revisar el estado antes de crear uno nuevo.

`cliente_reportar_pago_reserva` exige sesión y permiso. Rechaza un pago que ya cambió de estado, uno cuyo plazo venció y uno cuya reserva ya no está activa.

`admin_verificar_pago_reserva` exige permiso sobre la entidad y un pago que exista y no esté ya cerrado. Si la agenda no está en `Reservado`, responde «La reserva ya no esta activa; no se puede verificar este pago».

`admin_rechazar_pago_reserva` exige permiso, un pago existente que no esté cerrado y un motivo de rechazo.

`admin_cobro_config_set` y `admin_precio_config_set` exigen permiso sobre la entidad. El plazo de cobro queda entre 1 y 720 horas. El redondeo queda entre 0 y 2 decimales. Sin número de proveedor no se activa el pago por adelantado.

### Reseña y alta de usuario

`publicar_resena` exige sesión, puntuación de 1 a 5, comentario de hasta 1000 caracteres, una reserva propia y que el servicio ya haya atendido. `cotizar_reserva` exige sesión válida y un servicio que exista.

`admin_create_user` corre como `SECURITY DEFINER` y mira quién llama. El alta de un admin o un vendedor de la entidad pasa por las RPC `admin_listar_admins` y `admin_listar_vendedores` para leer, y por el flujo de la pantalla de la entidad para escribir.

## Code Style

**Observado.** Cada servicio fija `static const String _schema = 'flow'` y llama `.schema('flow').rpc(...)`. Las de versión y `get_uuid_by_email` van a `public`. Reglas de pantalla que se pueden probar sin red viven en `lib/utils/` (`EstadoPago`, `validarMotivo`). UI en español.

## Testing Strategy

**Observado.** `flutter_test` sin Supabase. `pago_reserva_bloqueo_test` fija que la pantalla bloquea verificar un pago de reserva Cancelada o Completada, y deja pasar Reservado. `estado_pago_test` fija las cinco etiquetas del pago. `motivo_cancelacion_test` fija el motivo de 3 a 500 caracteres. El comentario de ese test de pagos dice que la RPC no miraba el estado. En main, el 2026-11-14, `admin_verificar_pago_reserva` sí exige `Reservado`. La pantalla sigue siendo la segunda puerta.

## Boundaries

- **Always:** Leer y escribir reservas, pagos y catálogo en el esquema `flow`. Verificar un pago solo con la reserva en Reservado. Exigir motivo al cancelar desde el staff. Resolver el precio con `calcular_precio_reserva` / `calcular_precio_con_reglas`. Dejar el SQL de una RPC de `flow` en `docs/flow_schema/` cuando se cambie.
- **Ask first:** Cambiar la comisión, el plazo de 1 a 720 horas, las horas de anticipación de cancelación o el conjunto de estados de pago. Hacer que un admin verifique un pago de una reserva que ya no está Reservada.
- **Never:** Documentar aquí el TPV, Gestión o Muevete. Copiar claves de `supabase_config.dart` a docs o logs. Tratar un doc de monetización como comportamiento ya desplegado. Usar la clave `service_role` en este cliente.

## Success Criteria

1. Con perfil, el splash abre `/home`. Sin perfil, `/perfil-setup`. Sin sesión, `/login`.
2. Quien administra al menos una entidad ve Gestión y puede pasar a la vista de cliente y volver. Quien solo es cliente no ve ese acceso.
3. `cliente_reservar_directo` no crea la reserva si el servicio no tiene reserva directa, el turno no es de ese servicio, la cantidad está fuera de rango o no quedan turnos.
4. `cliente_crear_pago_reserva` no abre un segundo pago mientras hay uno en curso, ni uno sobre una reserva que no está activa, ni uno si el servicio no cobra por adelantado.
5. `admin_verificar_pago_reserva` no verifica si la agenda no está en Reservado. La pantalla tampoco verifica Cancelado ni Completado.
6. Un cierre en efectivo del TPV no entra en esta app. El pago de GoReserva es el de `reserva_pago`.
7. `flutter test --no-pub test/pago_reserva_bloqueo_test.dart test/estado_pago_test.dart test/motivo_cancelacion_test.dart` pasa.

## Open Questions

Ninguna que bloquee esta línea base.
