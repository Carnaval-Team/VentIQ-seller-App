# Changelog

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
