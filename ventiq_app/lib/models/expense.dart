class Expense {
  final int idEgreso;
  final double montoEntrega;
  final String motivoEntrega;
  final String nombreRecibe;
  final String nombreAutoriza;
  final DateTime fechaEntrega;
  final int turnoEstado;
  final String turnoAbiertoPor;
  final String? turnoCerradoPor;

  Expense({
    required this.idEgreso,
    required this.montoEntrega,
    required this.motivoEntrega,
    required this.nombreRecibe,
    required this.nombreAutoriza,
    required this.fechaEntrega,
    required this.turnoEstado,
    required this.turnoAbiertoPor,
    this.turnoCerradoPor,
  });

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      idEgreso: json['id_egreso'] ?? 0,
      montoEntrega: (json['monto_entrega'] ?? 0.0).toDouble(),
      motivoEntrega: json['motivo_entrega'] ?? '',
      nombreRecibe: json['nombre_recibe'] ?? '',
      nombreAutoriza: json['nombre_autoriza'] ?? '',
      fechaEntrega: DateTime.parse(json['fecha_entrega']),
      turnoEstado: json['turno_estado'] ?? 0,
      turnoAbiertoPor: json['turno_abierto_por'] ?? '',
      turnoCerradoPor: json['turno_cerrado_por'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id_egreso': idEgreso,
      'monto_entrega': montoEntrega,
      'motivo_entrega': motivoEntrega,
      'nombre_recibe': nombreRecibe,
      'nombre_autoriza': nombreAutoriza,
      'fecha_entrega': fechaEntrega.toIso8601String(),
      'turno_estado': turnoEstado,
      'turno_abierto_por': turnoAbiertoPor,
      'turno_cerrado_por': turnoCerradoPor,
    };
  }

  String get formattedTime {
    return '${fechaEntrega.hour.toString().padLeft(2, '0')}:${fechaEntrega.minute.toString().padLeft(2, '0')}';
  }

  String get formattedAmount {
    return '\$${montoEntrega.toStringAsFixed(2)}';
  }
}
