class Customer {
  final int id;
  final String codigoCliente;
  final int tipoCliente; // 1=Regular, 2=VIP, 3=Corporativo
  final String nombreCompleto;
  final String? documentoIdentidad;
  final String? email;
  final String? telefono;
  final Map<String, dynamic>? direccion;
  final DateTime? fechaNacimiento;
  final String? genero;
  final int puntosAcumulados;
  final int nivelFidelidad;
  final double? limiteCredito;
  final DateTime fechaRegistro;
  final DateTime? ultimaCompra;
  final double totalCompras;
  final int? frecuenciaCompra;
  final Map<String, dynamic>? preferencias;
  final String? notas;
  final bool activo;
  final bool aceptaMarketing;
  final DateTime? fechaOptin;
  final DateTime? fechaOptout;
  final Map<String, dynamic>? preferenciasComunicacion;

  // Campos calculados (no en BD)
  final int? totalOrders;
  final double? averageOrderValue;

  Customer({
    required this.id,
    required this.codigoCliente,
    required this.tipoCliente,
    required this.nombreCompleto,
    this.documentoIdentidad,
    this.email,
    this.telefono,
    this.direccion,
    this.fechaNacimiento,
    this.genero,
    this.puntosAcumulados = 0,
    this.nivelFidelidad = 1,
    this.limiteCredito,
    required this.fechaRegistro,
    this.ultimaCompra,
    this.totalCompras = 0.0,
    this.frecuenciaCompra,
    this.preferencias,
    this.notas,
    this.activo = true,
    this.aceptaMarketing = true,
    this.fechaOptin,
    this.fechaOptout,
    this.preferenciasComunicacion,
    this.totalOrders,
    this.averageOrderValue,
  }) : assert(id != null, 'Customer ID cannot be null'),
       assert(puntosAcumulados != null, 'puntosAcumulados cannot be null'),
       assert(nivelFidelidad != null, 'nivelFidelidad cannot be null');

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id:
          (json['id'] ?? 0) is int
              ? json['id'] ?? 0
              : int.tryParse(json['id'].toString()) ?? 0,
      codigoCliente: json['codigo_cliente']?.toString() ?? '',
      tipoCliente:
          (json['tipo_cliente'] ?? 1) is int
              ? json['tipo_cliente'] ?? 1
              : int.tryParse(json['tipo_cliente'].toString()) ?? 1,
      nombreCompleto: json['nombre_completo']?.toString() ?? '',
      documentoIdentidad: json['documento_identidad']?.toString(),
      email: json['email']?.toString(),
      telefono: json['telefono']?.toString(),
      direccion:
          json['direccion'] != null
              ? Map<String, dynamic>.from(json['direccion'])
              : null,
      fechaNacimiento:
          json['fecha_nacimiento'] != null
              ? DateTime.parse(json['fecha_nacimiento'])
              : null,
      genero: json['genero'],
      puntosAcumulados:
          (json['puntos_acumulados'] ?? 0) is int
              ? json['puntos_acumulados'] ?? 0
              : int.tryParse(json['puntos_acumulados'].toString()) ?? 0,
      nivelFidelidad:
          (json['nivel_fidelidad'] ?? 1) is int
              ? json['nivel_fidelidad'] ?? 1
              : int.tryParse(json['nivel_fidelidad'].toString()) ?? 1,
      limiteCredito: json['limite_credito']?.toDouble(),
      fechaRegistro: DateTime.parse(
        json['fecha_registro'] ?? DateTime.now().toIso8601String(),
      ),
      ultimaCompra:
          json['ultima_compra'] != null
              ? DateTime.parse(json['ultima_compra'])
              : null,
      totalCompras: (json['total_compras'] ?? 0.0).toDouble(),
      frecuenciaCompra: json['frecuencia_compra'],
      preferencias:
          json['preferencias'] != null
              ? Map<String, dynamic>.from(json['preferencias'])
              : null,
      notas: json['notas'],
      activo: json['activo'] ?? true,
      aceptaMarketing: json['acepta_marketing'] ?? true,
      fechaOptin:
          json['fecha_optin'] != null
              ? DateTime.parse(json['fecha_optin'])
              : null,
      fechaOptout:
          json['fecha_optout'] != null
              ? DateTime.parse(json['fecha_optout'])
              : null,
      preferenciasComunicacion:
          json['preferencias_comunicacion'] != null
              ? Map<String, dynamic>.from(json['preferencias_comunicacion'])
              : null,
      totalOrders: json['total_orders'],
      averageOrderValue: json['average_order_value']?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'codigo_cliente': codigoCliente,
      'tipo_cliente': tipoCliente,
      'nombre_completo': nombreCompleto,
      'documento_identidad': documentoIdentidad,
      'email': email,
      'telefono': telefono,
      'direccion': direccion,
      'fecha_nacimiento': fechaNacimiento?.toIso8601String().split('T')[0],
      'genero': genero,
      'puntos_acumulados': puntosAcumulados,
      'nivel_fidelidad': nivelFidelidad,
      'limite_credito': limiteCredito,
      'fecha_registro': fechaRegistro.toIso8601String(),
      'ultima_compra': ultimaCompra?.toIso8601String(),
      'total_compras': totalCompras,
      'frecuencia_compra': frecuenciaCompra,
      'preferencias': preferencias,
      'notas': notas,
      'activo': activo,
      'acepta_marketing': aceptaMarketing,
      'fecha_optin': fechaOptin?.toIso8601String(),
      'fecha_optout': fechaOptout?.toIso8601String(),
      'preferencias_comunicacion': preferenciasComunicacion,
    };
  }

  // Helper methods
  String get displayName => nombreCompleto;

  String get tipoClienteDisplay {
    switch (tipoCliente) {
      case 1:
        return 'Regular';
      case 2:
        return 'VIP';
      case 3:
        return 'Corporativo';
      default:
        return 'Regular';
    }
  }

  String get nivelFidelidadDisplay {
    switch (nivelFidelidad) {
      case 1:
        return 'Bronce';
      case 2:
        return 'Plata';
      case 3:
        return 'Oro';
      case 4:
        return 'Platino';
      default:
        return 'Bronce';
    }
  }

  bool get isVIP => tipoCliente == 2;
  bool get isCorporativo => tipoCliente == 3;

  String get contactInfo {
    final parts = <String>[];
    if (telefono != null && telefono!.isNotEmpty) parts.add(telefono!);
    if (email != null && email!.isNotEmpty) parts.add(email!);
    return parts.join(' • ');
  }
}
