class Expense {
  final int idEgreso;
  final double montoEntrega;
  final String motivoEntrega;
  final String nombreRecibe;
  final String nombreAutoriza;
  final DateTime fechaEntrega;
  final int? idMedioPago;
  final int turnoEstado;
  final String? medioPago; // Nombre del medio de pago (se enriquece después)
  final bool? esDigital; // Se enriquece después

  Expense({
    required this.idEgreso,
    required this.montoEntrega,
    required this.motivoEntrega,
    required this.nombreRecibe,
    required this.nombreAutoriza,
    required this.fechaEntrega,
    this.idMedioPago,
    required this.turnoEstado,
    this.medioPago,
    this.esDigital,
  });

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      idEgreso: json['id_egreso'] ?? 0,
      montoEntrega: (json['monto_entrega'] ?? 0.0).toDouble(),
      motivoEntrega: json['motivo_entrega'] ?? '',
      nombreRecibe: json['nombre_recibe'] ?? '',
      nombreAutoriza: json['nombre_autoriza'] ?? '',
      fechaEntrega: DateTime.parse(json['fecha_entrega']),
      idMedioPago: json['id_medio_pago'],
      turnoEstado: json['turno_estado'] ?? 0,
      medioPago: json['medio_pago'],
      esDigital: json['es_digital'],
    );
  }

  // Método para crear una copia con datos enriquecidos
  Expense copyWith({String? medioPago, bool? esDigital}) {
    return Expense(
      idEgreso: idEgreso,
      montoEntrega: montoEntrega,
      motivoEntrega: motivoEntrega,
      nombreRecibe: nombreRecibe,
      nombreAutoriza: nombreAutoriza,
      fechaEntrega: fechaEntrega,
      idMedioPago: idMedioPago,
      turnoEstado: turnoEstado,
      medioPago: medioPago ?? this.medioPago,
      esDigital: esDigital ?? this.esDigital,
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
      'id_medio_pago': idMedioPago,
      'turno_estado': turnoEstado,
      'medio_pago': medioPago,
      'es_digital': esDigital,
    };
  }

  String get formattedTime {
    return '${fechaEntrega.hour.toString().padLeft(2, '0')}:${fechaEntrega.minute.toString().padLeft(2, '0')}';
  }

  String get formattedAmount {
    return '\$${montoEntrega.toStringAsFixed(2)}';
  }
}
