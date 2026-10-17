import 'package:intl/intl.dart';
import '../models/notificacion.dart';

/// Orden y agrupación de la lista de notificaciones (F1, decisión D2).
///
/// Vive aparte de `NotificacionService` y del provider porque es lógica pura:
/// no habla con Supabase y se puede testear sin tocar la red. El cliente y el
/// admin comparten esta misma pantalla y este mismo provider, así que las dos
/// caras de la app ven exactamente el mismo orden.

/// Devuelve una **lista nueva** con las notificaciones más recientes primero.
///
/// Criterio: `createdAt` descendente y, si empatan, `id` descendente.
///
/// ¿Por qué hace falta el desempate por `id`? Porque `created_at` se rellena con
/// `current_timestamp`, que en PostgreSQL es la hora de **inicio de la
/// transacción**, no la de cada sentencia. Varios inserts hechos por un mismo
/// CTE (o por un trigger que inserta en bucle) comparten el mismo `created_at`
/// al microsegundo. Sin desempate, el orden entre esos avisos lo decide el
/// algoritmo de ordenación y puede cambiar entre la carga inicial y el
/// realtime; con el desempate, "más reciente primero" queda determinista.
///
/// No muta la lista recibida: devuelve una copia ordenada.
List<Notificacion> ordenarPorFecha(List<Notificacion> items) {
  final copia = List<Notificacion>.of(items);
  copia.sort((a, b) {
    final porFecha = b.createdAt.compareTo(a.createdAt);
    if (porFecha != 0) return porFecha;
    // Mismo `created_at` (típico de un CTE): gana el id más alto.
    return b.id.compareTo(a.id);
  });
  return copia;
}

/// Etiqueta del día de una notificación: `'Hoy'`, `'Ayer'` o `dd/MM/yyyy`.
///
/// Compara **días de calendario**, no diferencias de 24 h: un aviso de ayer a
/// las 23:00 es "Ayer" aunque hayan pasado pocas horas. `ahora` se inyecta para
/// poder testear sin depender del reloj.
String etiquetaDiaNotificacion(DateTime fecha, {DateTime? ahora}) {
  final referencia = ahora ?? DateTime.now();
  final dias = _numeroDeDia(_soloFecha(referencia)) - _numeroDeDia(_soloFecha(fecha));
  if (dias == 0) return 'Hoy';
  if (dias == 1) return 'Ayer';
  return DateFormat('dd/MM/yyyy').format(fecha);
}

DateTime _soloFecha(DateTime d) => DateTime(d.year, d.month, d.day);

/// Número de día absoluto en UTC: evita que un cambio de horario (DST) deje la
/// resta de medianoches en 23 h y rompa el `inDays`.
int _numeroDeDia(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;