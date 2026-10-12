# Changelog

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
