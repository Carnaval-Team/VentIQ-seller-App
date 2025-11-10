class SubscriptionPlan {
  final int id;
  final String denominacion;
  final String? descripcion;
  final double precioMensual;
  final int duracionTrialDias;
  final int limiteTiendas;
  final int limiteUsuarios;
  final Map<String, dynamic>? funcionesHabilitadas;
  final bool esActivo;
  final DateTime createdAt;

  SubscriptionPlan({
    required this.id,
    required this.denominacion,
    this.descripcion,
    required this.precioMensual,
    required this.duracionTrialDias,
    required this.limiteTiendas,
    required this.limiteUsuarios,
    this.funcionesHabilitadas,
    required this.esActivo,
    required this.createdAt,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      id: json['id'],
      denominacion: json['denominacion'],
      descripcion: json['descripcion'],
      precioMensual: json['precio_mensual'].toDouble(),
      duracionTrialDias: json['duracion_trial_dias'],
      limiteTiendas: json['limite_tiendas'],
      limiteUsuarios: json['limite_usuarios'],
      funcionesHabilitadas: json['funciones_habilitadas'],
      esActivo: json['es_activo'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'denominacion': denominacion,
      'descripcion': descripcion,
      'precio_mensual': precioMensual,
      'duracion_trial_dias': duracionTrialDias,
      'limite_tiendas': limiteTiendas,
      'limite_usuarios': limiteUsuarios,
      'funciones_habilitadas': funcionesHabilitadas,
      'es_activo': esActivo,
      'created_at': createdAt.toIso8601String(),
    };
  }

  // Getters útiles
  bool get isBasic => id == 1;
  bool get isPremium => id == 2;
  bool get isEnterprise => id == 3;

  String get precioFormateado => '\$${precioMensual.toStringAsFixed(2)}';

  List<String> get funcionesLista {
    if (funcionesHabilitadas == null) return [];
    
    List<String> funciones = [];
    funcionesHabilitadas!.forEach((key, value) {
      if (value == true) {
        funciones.add(_getFuncionNombre(key));
      }
    });
    return funciones;
  }

  String _getFuncionNombre(String key) {
    switch (key) {
      case 'inventario':
        return 'Gestión de Inventario';
      case 'ventas':
        return 'Punto de Venta';
      case 'reportes':
        return 'Reportes Avanzados';
      case 'usuarios_ilimitados':
        return 'Usuarios Ilimitados';
      case 'tiendas_multiples':
        return 'Múltiples Tiendas';
      case 'integraciones':
        return 'Integraciones';
      case 'soporte_prioritario':
        return 'Soporte Prioritario';
      case 'backup_automatico':
        return 'Backup Automático';
      case 'analytics':
        return 'Analytics Avanzado';
      case 'api_access':
        return 'Acceso API';
      default:
        return key.replaceAll('_', ' ').toUpperCase();
    }
  }
}
