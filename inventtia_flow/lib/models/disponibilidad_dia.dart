/// Un día con disponibilidad para reserva directa, devuelto por la RPC
/// flow.cliente_obtener_disponibilidad.
///
/// Para servicios SIN recursos, [turnos] queda vacío y se usa [disponibles]
/// (cupo agregado del día). Para servicios CON recursos, [turnos] trae la lista
/// de turnos reservables ese día con su disponibilidad individual.
library;

import 'recurso.dart' show etiquetaHoraTurno;

class DisponibilidadDia {
  final DateTime fecha;
  final int cantidad;
  final int agendados;
  final int disponibles;

  /// Turnos reservables ese día (vacío si el servicio no usa recursos).
  final List<TurnoDisponible> turnos;

  DisponibilidadDia({
    required this.fecha,
    required this.cantidad,
    required this.agendados,
    required this.disponibles,
    List<TurnoDisponible>? turnos,
  }) : turnos = turnos ?? [];

  /// true si este día ofrece turnos concretos (servicio con recursos).
  bool get tieneTurnos => turnos.isNotEmpty;

  factory DisponibilidadDia.fromJson(Map<String, dynamic> json) =>
      DisponibilidadDia(
        fecha: DateTime.parse(json['fecha'] as String),
        cantidad: (json['cantidad'] as num?)?.toInt() ?? 0,
        agendados: (json['agendados'] as num?)?.toInt() ?? 0,
        disponibles: (json['disponibles'] as num?)?.toInt() ?? 0,
        turnos:
            (json['turnos'] as List?)
                ?.map(
                  (e) => TurnoDisponible.fromJson(e as Map<String, dynamic>),
                )
                .toList() ??
            [],
      );
}

/// Un turno reservable en un día concreto, con su disponibilidad (mínimo de
/// los tramos que ocupa) y el recurso al que pertenece.
class TurnoDisponible {
  final int idRecurso;
  final String recurso;
  final int idTurno;
  final String turno;
  final int disponibles;

  /// Hora de inicio del turno, `"HH:MM"`, o null (punto 7 del plan).
  final String? horaInicio;

  /// Hora de fin del turno, `"HH:MM"`, o null.
  final String? horaFin;

  TurnoDisponible({
    required this.idRecurso,
    required this.recurso,
    required this.idTurno,
    required this.turno,
    required this.disponibles,
    this.horaInicio,
    this.horaFin,
  });

  /// `"09:00 – 11:00"`, `"09:00"` o null si el turno no tiene horas.
  String? get etiquetaHora => etiquetaHoraTurno(horaInicio, horaFin);

  factory TurnoDisponible.fromJson(Map<String, dynamic> json) =>
      TurnoDisponible(
        idRecurso: (json['id_recurso'] as num).toInt(),
        recurso: json['recurso'] as String? ?? '',
        idTurno: (json['id_turno'] as num).toInt(),
        turno: json['turno'] as String? ?? '',
        disponibles: (json['disponibles'] as num?)?.toInt() ?? 0,
        horaInicio: _horaDe(json['hora_inicio']),
        horaFin: _horaDe(json['hora_fin']),
      );
}

/// Acepta `"09:00"` y `"09:00:00"`; descarta cualquier otra cosa.
String? _horaDe(Object? raw) {
  if (raw is! String) return null;
  final t = raw.trim();
  if (t.length >= 5 && t[2] == ':') return t.substring(0, 5);
  return null;
}
