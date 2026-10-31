# Changelog

## Sin publicar

### Suscripción en la cabecera y cobros por adelantado con pantalla propia

- **La suscripción pasa al AppBar**: «Mi suscripción» deja de ser un cuadrito del
  grid de Gestión y pasa a un **icono en la cabecera**, con un badge que solo se
  enciende cuando toca avisar: rojo con «!» si hay un pago pendiente o el plan está
  vencido, ámbar con los días que quedan cuando son **7 o menos**. El tooltip explica
  el estado («Tu suscripción vence en 3 días»).
- **Pagos por adelantado, con pantalla propia**: todo lo relacionado con el cobro por
  adelantado de los servicios sale de «Mi suscripción» y pasa a
  `lib/screens/admin/cobros_screen.dart` («Pagos por adelantado»): estado del cobro
  (número de proveedor, moneda, plazo, WhatsApp de verificación), bandeja de
  **pagos por verificar** con su contador, acceso a la configuración y un resumen del
  circuito en 3 pasos. Se entra desde el cuadrito **«Pagos por adelantado»** del grid
  de Gestión.
- **La ruedita ⚙ vuelve a abrir la ficha de la entidad** (el cobro ya no cuelga de
  ahí). Dos circuitos separados, cada uno en su sitio: el plan del negocio con el
  superadmin y el pago del cliente con el admin de la entidad.
- **Tutorial del admin actualizado** al nuevo recorrido: 4 pasos (icono de
  suscripción con su badge, «Mi suscripción», cuadrito «Pagos por adelantado» y
  verificación de pagos) y 2 destinos nuevos en la navegación del tutorial
  (`suscripcion`, `cobros`) para que «Siguiente» abra la pantalla correcta.

### La suscripción se cobra siempre en CUP

- **Transfermóvil solo cobra en CUP**, así que el intent de la suscripción deja de
  usar la moneda del plan: el servidor convierte el precio con la **tasa del día**
  (`flow.tasa_factor` sobre la caché de `flow.tasa_cambio`) y redondea a pesos
  enteros, exactamente como ya hacía el pago por adelantado de un servicio. Si no
  hay tasa para esa moneda, **no se crea el intent** y se avisa con un mensaje
  claro en lugar de mandar a Transfermóvil un importe que no puede cobrar.
- La app muestra el **precio del plan en su moneda** y, debajo, el **equivalente en
  CUP** que se va a transferir («≈ 2535 CUP al cambio de hoy» + «El cobro con
  Transfermóvil se hace en CUP»), tanto en la tarjeta del plan como en el paso de
  pago. El panel del superadmin avisa de lo mismo en el editor y en las tarjetas
  que no están en CUP.
- Requiere la migración **74** (`docs/flow_schema/migraciones/74_suscripcion_cobro_en_cup.sql`),
  que añade `flow._monto_en_cup(...)` y redefine el intent y el listado de planes
  (`precio_cup`). Los importes los calcula **siempre el servidor**: la app no
  convierte nada.

### Actualizaciones con changelog e historial de novedades

- **El aviso de versión nueva enseña lo que cambia**: diálogo con la versión y su
  fecha, el título de la versión y el **changelog completo** (cada cambio con su
  icono: Novedad, Mejora o Corrección), botón **Descargar ahora** y enlace al
  **historial de cambios**. Si la actualización es **obligatoria**, el aviso no se
  puede cerrar (puedes abrir el historial, pero no saltarte la actualización).
- **Pantalla «Novedades»**: historial de todas las versiones publicadas, con la
  **instalada marcada**, y un botón para buscar actualizaciones. Sin conexión, cae al
  historial que viaja dentro de la app. Se entra desde Perfil y desde el propio aviso.
- **La app reporta la versión realmente instalada** (`package_info_plus`) en lugar de
  la de `assets/changelog.json`: el asset iba por delante de la base de datos y por eso
  el aviso **nunca saltaba**. Se detectó el desfase (asset 1.4.8/16 · `pubspec` 1.4.0+8 ·
  BD 1.4.7/15) y queda documentado en `docs/ACTUALIZACIONES.md`.
- **El changelog se publica desde el panel** (Superadmin → *Versiones de las apps*):
  versión, build, versión mínima, obligatoria, título, cambios estructurados y URL de
  descarga opcional, con **vista previa** de cómo lo verá el usuario en el móvil.
- Requiere la migración **75** (`docs/flow_schema/migraciones/75_app_versiones_novedades.sql`),
  que añade `titulo`, `novedades` y `url_descarga` a `public.app_versiones`, amplía
  `fn_check_update` (sin romper a las otras apps), crea el historial y **endurece la
  seguridad**: antes cualquier usuario autenticado podía publicar versiones por
  PostgREST; ahora solo se escribe por los RPC del superadmin.

## 1.4.0+8 - 2026-10-12

### Suscripciones por entidad (nueva funcionalidad)

Cada entidad pasa a tener una suscripción que decide si se muestra en la app y
si admite reservas. Requiere las migraciones **43 → 46** del schema `flow`
(`docs/flow_schema/migraciones/`), que se aplican a mano en el SQL Editor.

- **Prueba gratuita automática**: al crear una entidad se le otorgan los meses
  configurados por el superadmin (por defecto 1). Pasada la prueba, la entidad
  entra en un margen de gracia (por defecto 7 días) y después deja de mostrarse.
- **Aviso permanente de impago**: una banda sobre el shell avisa en todo momento
  del estado (prueba por terminar, por vencer, en gracia, vencida, suspendida) y
  lleva a *Mi suscripción*.
- **Pantalla "Mi suscripción"**: estado, planes publicados, pago por
  Transfermóvil, botón *Ya he pagado* con código de confirmación obligatorio y
  comprobante opcional, e historial de pagos y movimientos.
- **Pago por Transfermóvil** mediante el deep link del intent generado en el
  servidor. Transfermóvil no devuelve ningún callback, así que el botón
  *Ya he pagado* aparece al volver la app a primer plano; si el usuario cerró la
  app después de pagar, la pantalla reanuda el intento que quedó vivo.
  El id de transacción del link es siempre el literal `ESTATICO` (bug de la app
  de Transfermóvil, que ignora el id que se le mande); la referencia `FLW-…`
  que muestra la app es interna, para que soporte localice el pago en el panel.
- **Reporte a soporte por WhatsApp** con el mensaje ya redactado por el servidor
  (plan, entidad, importe, id de transacción y código de confirmación).
- **Ninguna suscripción se activa desde la app**: el pago se verifica a mano en
  el panel del superadmin, que acredita el tiempo. Es deliberado.
- **Sin conexión o sin migraciones**: si el módulo todavía no está aplicado en el
  servidor, la app lo detecta y sigue funcionando como antes (nada se bloquea).

### Notas de despliegue
- Aplicar 43 → 46 **en orden**. Mientras no se apliquen, la app funciona igual
  que la versión anterior: el aviso de suscripción no se pinta y el catálogo no
  filtra por suscripción.
- Las entidades que ya existían **no se desactivan** al aplicar las migraciones:
  sin fila de suscripción el predicado de visibilidad las considera activas. Para
  empezar a contabilizarlas hay que usar *Inicializar suscripciones* en el panel.
- Los 3 planes de ejemplo nacen **desactivados y con precio 0**: hay que poner
  precio y activarlos antes de que se puedan comprar.

## 1.1.0+2 - 2026-07-01

### Nuevas funcionalidades
- **Cancelación de reservas por cliente**: el cliente puede cancelar sus reservas desde *Mis Tickets*. Si la entidad no configuró horas de anticipación, la cancelación está permitida en cualquier momento.
- **Configuración de anticipación de cancelación**: las entidades pueden definir `horas_anticipacion_cancelacion`.
- **Capacidad por reserva**: configuración de `cantidad_default` y `cantidad_max_capacidad` en la vinculación local-servicio.
- **Polish UI en detalle de servicio**: botones de *Reservar ahora* y *Anotarme en la lista* con feedback de escala al presionar, transiciones suaves y mejor jerarquía visual.

### Correcciones
- El listado de reservas del admin ahora incluye teléfono, cantidad, tercero y las columnas dinámicas de **información adicional** de cada reserva, alineado con los reportes PDF/Excel.
- El reporte de reservas (PDF/Excel) ya exporta las columnas dinámicas de datos adicionales.

### Backend
- Nuevos/actualizados RPCs: `cliente_cancelar_reserva`, `cliente_reservar_directo`, `cliente_obtener_servicios`, `cliente_obtener_agendas`, `admin_listar_agendas`.
- Actualización de modelos Dart: `Entidad`, `LocalServicio`, `Agenda`.
