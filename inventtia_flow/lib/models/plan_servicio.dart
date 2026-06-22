class PlanServicio {
  final int id;
  final int? idLocalServicio;
  final DateTime? fecha;
  final int cantidad;
  final int agendados;
  final DateTime createdAt;

  PlanServicio({
    required this.id,
    this.idLocalServicio,
    this.fecha,
    required this.cantidad,
    required this.agendados,
    required this.createdAt,
  });

  int get disponibles => cantidad - agendados;

  bool get estaLleno => disponibles <= 0;

  factory PlanServicio.fromJson(Map<String, dynamic> json) => PlanServicio(
        id: (json['id'] as num).toInt(),
        idLocalServicio: json['id_local_servicio'] as int?,
        fecha: json['fecha'] != null
            ? DateTime.parse(json['fecha'] as String)
            : null,
        cantidad: (json['cantidad'] as num?)?.toInt() ?? 0,
        agendados: (json['agendados'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toInsert({required int idLocalServicio}) => {
        'id_local_servicio': idLocalServicio,
        'fecha': fecha?.toIso8601String(),
        'cantidad': cantidad,
        'agendados': agendados,
      };
}
