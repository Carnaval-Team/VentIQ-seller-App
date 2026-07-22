class TransporteTurnoDisponible {
  final int idTurno;
  final int idRecurso;
  final String recurso;
  final String turno;
  final Map<String, double> precios;
  final String tipoTrayecto;
  final int cantidad;
  final int agendados;
  final int disponibles;

  /// True si el turno cubre ida y vuelta (paquete combinado).
  final bool esCombinado;

  /// Cantidad de tramos que ocupa el turno (1 = solo ida o solo vuelta).
  final int numTramos;

  const TransporteTurnoDisponible({
    required this.idTurno,
    required this.idRecurso,
    required this.recurso,
    required this.turno,
    Map<String, double>? precios,
    required this.tipoTrayecto,
    required this.cantidad,
    required this.agendados,
    required this.disponibles,
    this.esCombinado = false,
    this.numTramos = 1,
  }) : precios = precios ?? const {};

  /// Paquete / multi-tramo: no usar para pasaje solo ida o solo vuelta.
  bool get esPaquete => esCombinado || numTramos > 1;

  factory TransporteTurnoDisponible.fromJson(Map<String, dynamic> json) {
    final numTramos = (json['num_tramos'] as num?)?.toInt() ?? 1;
    final combinadoRaw = json['es_combinado'];
    final combinadoFlag = combinadoRaw == true ||
        combinadoRaw == 1 ||
        combinadoRaw == 'true' ||
        combinadoRaw == 't';
    return TransporteTurnoDisponible(
      idTurno: (json['id_turno'] as num).toInt(),
      idRecurso: (json['id_recurso'] as num).toInt(),
      recurso: json['recurso'] as String? ?? '',
      turno: json['turno'] as String? ?? '',
      precios:
          (json['precios'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), (value as num).toDouble()),
          ) ??
          const {},
      tipoTrayecto: json['tipo_trayecto'] as String? ?? '',
      cantidad: (json['cantidad'] as num?)?.toInt() ?? 0,
      agendados: (json['agendados'] as num?)?.toInt() ?? 0,
      disponibles: (json['disponibles'] as num?)?.toInt() ?? 0,
      esCombinado: combinadoFlag || numTramos > 1,
      numTramos: numTramos,
    );
  }
}

class DisponibilidadTransporte {
  final DateTime fecha;
  final List<TransporteTurnoDisponible> turnos;

  const DisponibilidadTransporte({required this.fecha, required this.turnos});

  factory DisponibilidadTransporte.fromJson(Map<String, dynamic> json) {
    return DisponibilidadTransporte(
      fecha: DateTime.parse(json['fecha'] as String),
      turnos: ((json['turnos'] as List?) ?? const [])
          .map(
            (item) => TransporteTurnoDisponible.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
  }
}
