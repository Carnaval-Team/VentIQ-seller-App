class SubscriptionHistory {
  final int id;
  final int idSuscripcion;
  final int? idPlanAnterior;
  final int? idPlanNuevo;
  final int? estadoAnterior;
  final int? estadoNuevo;
  final DateTime fechaCambio;
  final String cambiadoPor;
  final String? motivo;

  SubscriptionHistory({
    required this.id,
    required this.idSuscripcion,
    this.idPlanAnterior,
    this.idPlanNuevo,
    this.estadoAnterior,
    this.estadoNuevo,
    required this.fechaCambio,
    required this.cambiadoPor,
    this.motivo,
  });

  factory SubscriptionHistory.fromJson(Map<String, dynamic> json) {
    return SubscriptionHistory(
      id: json['id'],
      idSuscripcion: json['id_suscripcion'],
      idPlanAnterior: json['id_plan_anterior'],
      idPlanNuevo: json['id_plan_nuevo'],
      estadoAnterior: json['estado_anterior'],
      estadoNuevo: json['estado_nuevo'],
      fechaCambio: DateTime.parse(json['fecha_cambio']),
      cambiadoPor: json['cambiado_por'],
      motivo: json['motivo'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'id_suscripcion': idSuscripcion,
      'id_plan_anterior': idPlanAnterior,
      'id_plan_nuevo': idPlanNuevo,
      'estado_anterior': estadoAnterior,
      'estado_nuevo': estadoNuevo,
      'fecha_cambio': fechaCambio.toIso8601String(),
      'cambiado_por': cambiadoPor,
      'motivo': motivo,
    };
  }

  // Getters útiles
  String get tipoOperacion {
    if (idPlanAnterior != null && idPlanNuevo != null && idPlanAnterior != idPlanNuevo) {
      return 'Cambio de Plan';
    } else if (estadoAnterior != null && estadoNuevo != null && estadoAnterior != estadoNuevo) {
      return 'Cambio de Estado';
    } else {
      return 'Modificación';
    }
  }

  String get descripcionCambio {
    List<String> cambios = [];
    
    if (idPlanAnterior != null && idPlanNuevo != null && idPlanAnterior != idPlanNuevo) {
      cambios.add('Plan: $idPlanAnterior → $idPlanNuevo');
    }
    
    if (estadoAnterior != null && estadoNuevo != null && estadoAnterior != estadoNuevo) {
      cambios.add('Estado: ${_getEstadoText(estadoAnterior!)} → ${_getEstadoText(estadoNuevo!)}');
    }
    
    return cambios.join(', ');
  }

  String _getEstadoText(int estado) {
    switch (estado) {
      case 1:
        return 'Activa';
      case 2:
        return 'Prueba';
      case 3:
        return 'Cancelada';
      case 4:
        return 'Suspendida';
      default:
        return 'Desconocido';
    }
  }
}
