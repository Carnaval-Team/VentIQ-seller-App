class Subscription {
  final int id;
  final int idTienda;
  final int idPlan;
  final DateTime fechaInicio;
  final DateTime? fechaFin;
  final int estado;
  final String? metodoPago;
  final String? idPagoExterno;
  final String creadoPor;
  final bool renovacionAutomatica;
  final String? observaciones;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Datos del plan (join)
  final String? planDenominacion;
  final String? planDescripcion;
  final double? planPrecioMensual;
  final int? planDuracionTrialDias;
  final int? planLimiteTiendas;
  final int? planLimiteUsuarios;
  final Map<String, dynamic>? planFuncionesHabilitadas;
  final bool? planEsActivo;

  Subscription({
    required this.id,
    required this.idTienda,
    required this.idPlan,
    required this.fechaInicio,
    this.fechaFin,
    required this.estado,
    this.metodoPago,
    this.idPagoExterno,
    required this.creadoPor,
    required this.renovacionAutomatica,
    this.observaciones,
    required this.createdAt,
    required this.updatedAt,
    this.planDenominacion,
    this.planDescripcion,
    this.planPrecioMensual,
    this.planDuracionTrialDias,
    this.planLimiteTiendas,
    this.planLimiteUsuarios,
    this.planFuncionesHabilitadas,
    this.planEsActivo,
  });

  factory Subscription.fromJson(Map<String, dynamic> json) {
    return Subscription(
      id: json['id'],
      idTienda: json['id_tienda'],
      idPlan: json['id_plan'],
      fechaInicio: DateTime.parse(json['fecha_inicio']),
      fechaFin: json['fecha_fin'] != null ? DateTime.parse(json['fecha_fin']) : null,
      estado: json['estado'],
      metodoPago: json['metodo_pago'],
      idPagoExterno: json['id_pago_externo'],
      creadoPor: json['creado_por'],
      renovacionAutomatica: json['renovacion_automatica'] ?? false,
      observaciones: json['observaciones'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      // Datos del plan si vienen en el join
      planDenominacion: _extractPlanData(json['app_suscripciones_plan'], 'denominacion'),
      planDescripcion: _extractPlanData(json['app_suscripciones_plan'], 'descripcion'),
      planPrecioMensual: _extractPlanData(json['app_suscripciones_plan'], 'precio_mensual')?.toDouble(),
      planDuracionTrialDias: _extractPlanData(json['app_suscripciones_plan'], 'duracion_trial_dias'),
      planLimiteTiendas: _extractPlanData(json['app_suscripciones_plan'], 'limite_tiendas'),
      planLimiteUsuarios: _extractPlanData(json['app_suscripciones_plan'], 'limite_usuarios'),
      planFuncionesHabilitadas: _extractPlanData(json['app_suscripciones_plan'], 'funciones_habilitadas'),
      planEsActivo: _extractPlanData(json['app_suscripciones_plan'], 'es_activo'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'id_tienda': idTienda,
      'id_plan': idPlan,
      'fecha_inicio': fechaInicio.toIso8601String(),
      'fecha_fin': fechaFin?.toIso8601String(),
      'estado': estado,
      'metodo_pago': metodoPago,
      'id_pago_externo': idPagoExterno,
      'creado_por': creadoPor,
      'renovacion_automatica': renovacionAutomatica,
      'observaciones': observaciones,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // Getters útiles
  bool get isActive => estado == 1 && !isExpired;
  bool get isExpired => fechaFin != null && fechaFin!.isBefore(DateTime.now());
  bool get isTrial => estado == 2 && !isExpired;
  bool get isCancelled => estado == 3;
  
  String get estadoText {
    // Si está vencida, mostrar "Vencida" independientemente del estado
    if (isExpired) {
      return 'Vencida';
    }
    
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

  int get diasRestantes {
    if (fechaFin == null) return -1;
    final diferencia = fechaFin!.difference(DateTime.now()).inDays;
    return diferencia > 0 ? diferencia : 0;
  }

  /// Método auxiliar para extraer datos del plan de forma segura
  static dynamic _extractPlanData(dynamic planData, String key) {
    if (planData == null) return null;
    
    // Si es una lista, tomar el primer elemento
    if (planData is List) {
      if (planData.isEmpty) return null;
      final firstPlan = planData.first;
      if (firstPlan is Map<String, dynamic>) {
        return _extractValueFromMap(firstPlan, key);
      }
      return null;
    }
    
    // Si es un mapa, acceder directamente
    if (planData is Map<String, dynamic>) {
      return _extractValueFromMap(planData, key);
    }
    
    return null;
  }

  /// Método auxiliar para extraer valores de un mapa, manejando casos especiales
  static dynamic _extractValueFromMap(Map<String, dynamic> map, String key) {
    final value = map[key];
    
    // Log para debugging
    if (key == 'funciones_habilitadas') {
      print('🔍 Extrayendo funciones_habilitadas: tipo=${value.runtimeType}, valor=$value');
    }
    
    // Manejar funciones_habilitadas que puede ser una lista
    if (key == 'funciones_habilitadas' && value is List) {
      print('🔄 Convirtiendo lista de funciones a mapa');
      // Convertir la lista a un mapa para compatibilidad
      final Map<String, dynamic> functionsMap = {};
      for (final function in value) {
        if (function is String) {
          functionsMap[function] = true;
        }
      }
      print('✅ Funciones convertidas: $functionsMap');
      return functionsMap;
    }
    
    return value;
  }
}
