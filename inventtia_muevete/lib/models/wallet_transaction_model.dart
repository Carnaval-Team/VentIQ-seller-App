enum TipoTransaccion { recarga, cobro_viaje, pago_viaje, reembolso, comision_viaje }

enum EstadoTransaccion { pendiente, aceptada, cancelada, completada }

class WalletTransactionModel {
  final int? id;
  final String? userId;
  final int? driverId;
  final TipoTransaccion? tipo;
  final double? monto;
  final int? viajeId;
  final String? descripcion;
  final DateTime? createdAt;
  final EstadoTransaccion? estado;

  WalletTransactionModel({
    this.id,
    this.userId,
    this.driverId,
    this.tipo,
    this.monto,
    this.viajeId,
    this.descripcion,
    this.createdAt,
    this.estado,
  });

  factory WalletTransactionModel.fromJson(Map<String, dynamic> json) {
    return WalletTransactionModel(
      id: json['id'] as int?,
      userId: json['user_id']?.toString(),
      driverId: json['driver_id'] as int?,
      tipo: json['tipo'] != null
          ? TipoTransaccion.values.firstWhere(
              (e) => e.name == json['tipo'],
              orElse: () => TipoTransaccion.recarga,
            )
          : null,
      monto: json['monto'] != null
          ? (json['monto'] as num).toDouble()
          : null,
      viajeId: json['viaje_id'] as int?,
      descripcion: json['descripcion'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      estado: json['estado'] != null
          ? EstadoTransaccion.values.firstWhere(
              (e) => e.name == json['estado'],
              orElse: () => EstadoTransaccion.completada,
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'driver_id': driverId,
      'tipo': tipo?.name,
      'monto': monto,
      'viaje_id': viajeId,
      'descripcion': descripcion,
      if (estado != null) 'estado': estado!.name,
    };
  }

  WalletTransactionModel copyWith({
    int? id,
    String? userId,
    int? driverId,
    TipoTransaccion? tipo,
    double? monto,
    int? viajeId,
    String? descripcion,
    DateTime? createdAt,
    EstadoTransaccion? estado,
  }) {
    return WalletTransactionModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      driverId: driverId ?? this.driverId,
      tipo: tipo ?? this.tipo,
      monto: monto ?? this.monto,
      viajeId: viajeId ?? this.viajeId,
      descripcion: descripcion ?? this.descripcion,
      createdAt: createdAt ?? this.createdAt,
      estado: estado ?? this.estado,
    );
  }
}
