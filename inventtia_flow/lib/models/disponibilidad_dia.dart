/// Un día con disponibilidad para reserva directa, devuelto por la RPC
/// flow.cliente_obtener_disponibilidad.
class DisponibilidadDia {
  final DateTime fecha;
  final int cantidad;
  final int agendados;
  final int disponibles;

  DisponibilidadDia({
    required this.fecha,
    required this.cantidad,
    required this.agendados,
    required this.disponibles,
  });

  factory DisponibilidadDia.fromJson(Map<String, dynamic> json) =>
      DisponibilidadDia(
        fecha: DateTime.parse(json['fecha'] as String),
        cantidad: (json['cantidad'] as num?)?.toInt() ?? 0,
        agendados: (json['agendados'] as num?)?.toInt() ?? 0,
        disponibles: (json['disponibles'] as num?)?.toInt() ?? 0,
      );
}
