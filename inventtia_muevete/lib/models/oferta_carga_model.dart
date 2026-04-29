class OfertaCargaModel {
  final int id;
  final int cargaId;
  final int driverId;
  final double precio;
  final double? tarifaPorMilla;
  final int? tiempoEstimadoDias;
  final DateTime? fechaRecogidaProp;
  final DateTime? fechaEntregaProp;
  final int? vehiculoId;
  final bool incluyeSeguro;
  final String? notas;
  final String estado;
  // estados: 'pendiente','aceptada','rechazada','retirada','expirada'
  final double? matchingScore;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // Datos enriquecidos (JOIN)
  final String? driverNombre;
  final String? driverTipoUsuario;
  final double? driverRating;
  final bool? driverMcDotVerificado;
  final String? vehiculoDescripcion;

  const OfertaCargaModel({
    required this.id,
    required this.cargaId,
    required this.driverId,
    required this.precio,
    this.tarifaPorMilla,
    this.tiempoEstimadoDias,
    this.fechaRecogidaProp,
    this.fechaEntregaProp,
    this.vehiculoId,
    this.incluyeSeguro = false,
    this.notas,
    required this.estado,
    this.matchingScore,
    required this.createdAt,
    this.updatedAt,
    this.driverNombre,
    this.driverTipoUsuario,
    this.driverRating,
    this.driverMcDotVerificado,
    this.vehiculoDescripcion,
  });

  factory OfertaCargaModel.fromJson(Map<String, dynamic> json) {
    return OfertaCargaModel(
      id: json['id'] as int,
      cargaId: json['carga_id'] as int,
      driverId: json['driver_id'] as int,
      precio: (json['precio'] as num).toDouble(),
      tarifaPorMilla: (json['tarifa_por_milla'] as num?)?.toDouble(),
      tiempoEstimadoDias: json['tiempo_estimado_dias'] as int?,
      fechaRecogidaProp: json['fecha_recogida_prop'] != null
          ? DateTime.tryParse(json['fecha_recogida_prop'] as String)
          : null,
      fechaEntregaProp: json['fecha_entrega_prop'] != null
          ? DateTime.tryParse(json['fecha_entrega_prop'] as String)
          : null,
      vehiculoId: json['vehiculo_id'] as int?,
      incluyeSeguro: json['incluye_seguro'] as bool? ?? false,
      notas: json['notas'] as String?,
      estado: json['estado'] as String? ?? 'pendiente',
      matchingScore: (json['matching_score'] as num?)?.toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      driverNombre: json['driver_nombre'] as String?,
      driverTipoUsuario: json['driver_tipo_usuario'] as String?,
      driverRating: (json['driver_rating'] as num?)?.toDouble(),
      driverMcDotVerificado: json['driver_mc_dot_verificado'] as bool?,
      vehiculoDescripcion: json['vehiculo_descripcion'] as String?,
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'carga_id': cargaId,
      'driver_id': driverId,
      'precio': precio,
      if (tarifaPorMilla != null) 'tarifa_por_milla': tarifaPorMilla,
      if (tiempoEstimadoDias != null)
        'tiempo_estimado_dias': tiempoEstimadoDias,
      if (fechaRecogidaProp != null)
        'fecha_recogida_prop':
            fechaRecogidaProp!.toIso8601String().split('T').first,
      if (fechaEntregaProp != null)
        'fecha_entrega_prop':
            fechaEntregaProp!.toIso8601String().split('T').first,
      if (vehiculoId != null) 'vehiculo_id': vehiculoId,
      'incluye_seguro': incluyeSeguro,
      if (notas != null && notas!.isNotEmpty) 'notas': notas,
      'estado': estado,
    };
  }

  String get estadoLabel {
    const labels = {
      'pendiente': 'Pendiente',
      'aceptada': 'Aceptada',
      'rechazada': 'Rechazada',
      'retirada': 'Retirada',
      'expirada': 'Expirada',
    };
    return labels[estado] ?? estado;
  }
}
