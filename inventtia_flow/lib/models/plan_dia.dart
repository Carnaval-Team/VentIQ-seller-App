/// Resumen de capacidad de un día para el calendario del admin, devuelto por
/// flow.admin_get_plan_dias. Unifica servicios con y sin recursos:
///   • Sin recursos: [recursos] vacío; [cantidad]/[agendados] vienen de
///     plan_servicios.
///   • Con recursos: [recursos] trae el detalle por recurso; [agendados] es el
///     conteo real de agendas (Reservado/Completado), no el MAX de tramos.
class PlanDia {
  final DateTime fecha;
  final int cantidad;
  final int agendados;
  final int disponibles;
  final List<RecursoDia> recursos;

  PlanDia({
    required this.fecha,
    required this.cantidad,
    required this.agendados,
    required this.disponibles,
    List<RecursoDia>? recursos,
  }) : recursos = recursos ?? [];

  bool get estaLleno => cantidad > 0 && disponibles <= 0;

  factory PlanDia.fromJson(Map<String, dynamic> json) => PlanDia(
        fecha: DateTime.parse(json['fecha'] as String),
        cantidad: (json['cantidad'] as num?)?.toInt() ?? 0,
        agendados: (json['agendados'] as num?)?.toInt() ?? 0,
        disponibles: (json['disponibles'] as num?)?.toInt() ?? 0,
        recursos: (json['recursos'] as List?)
                ?.map((e) => RecursoDia.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

/// Capacidad de un recurso en un día concreto.
class RecursoDia {
  final int idRecurso;
  final String recurso;
  final int cantidad;

  /// Reservas reales (agenda) del recurso ese día.
  final int agendados;

  /// Pico de ocupación en un tramo (piso al bajar la capacidad planificada).
  final int ocupacionMax;

  /// Plazas libres sumadas sobre los tramos del recurso.
  final int disponibles;

  RecursoDia({
    required this.idRecurso,
    required this.recurso,
    required this.cantidad,
    required this.agendados,
    int? ocupacionMax,
    int? disponibles,
  })  : ocupacionMax = ocupacionMax ?? agendados,
        disponibles = disponibles ?? (cantidad - agendados);

  /// Mínimo de capacidad que se puede configurar sin romper cupos de tramo.
  int get minimoCapacidad => ocupacionMax;

  factory RecursoDia.fromJson(Map<String, dynamic> json) {
    final agendados = (json['agendados'] as num?)?.toInt() ?? 0;
    final cantidad = (json['cantidad'] as num?)?.toInt() ?? 0;
    return RecursoDia(
      idRecurso: (json['id_recurso'] as num).toInt(),
      recurso: json['recurso'] as String? ?? '',
      cantidad: cantidad,
      agendados: agendados,
      ocupacionMax: (json['ocupacion_max'] as num?)?.toInt() ?? agendados,
      disponibles: (json['disponibles'] as num?)?.toInt() ??
          (cantidad - agendados),
    );
  }
}
