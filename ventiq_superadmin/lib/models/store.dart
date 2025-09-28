class Store {
  final int id;
  final String denominacion;
  final String? direccion;
  final String? ubicacion;
  final DateTime createdAt;
  final int? totalVentas;
  final int? totalProductos;
  final int? totalTrabajadores;
  final double? ventasDelMes;
  final bool? activa;
  final String? planSuscripcion;
  final DateTime? fechaVencimientoSuscripcion;

  Store({
    required this.id,
    required this.denominacion,
    this.direccion,
    this.ubicacion,
    required this.createdAt,
    this.totalVentas,
    this.totalProductos,
    this.totalTrabajadores,
    this.ventasDelMes,
    this.activa,
    this.planSuscripcion,
    this.fechaVencimientoSuscripcion,
  });

  factory Store.fromJson(Map<String, dynamic> json) {
    return Store(
      id: json['id'],
      denominacion: json['denominacion'],
      direccion: json['direccion'],
      ubicacion: json['ubicacion'],
      createdAt: DateTime.parse(json['created_at']),
      totalVentas: json['total_ventas'],
      totalProductos: json['total_productos'],
      totalTrabajadores: json['total_trabajadores'],
      ventasDelMes: json['ventas_del_mes']?.toDouble(),
      activa: json['activa'] ?? true,
      planSuscripcion: json['plan_suscripcion'],
      fechaVencimientoSuscripcion: json['fecha_vencimiento_suscripcion'] != null
          ? DateTime.parse(json['fecha_vencimiento_suscripcion'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'denominacion': denominacion,
      'direccion': direccion,
      'ubicacion': ubicacion,
      'created_at': createdAt.toIso8601String(),
      'total_ventas': totalVentas,
      'total_productos': totalProductos,
      'total_trabajadores': totalTrabajadores,
      'ventas_del_mes': ventasDelMes,
      'activa': activa,
      'plan_suscripcion': planSuscripcion,
      'fecha_vencimiento_suscripcion': fechaVencimientoSuscripcion?.toIso8601String(),
    };
  }

  String get ubicacionCompleta {
    if (direccion != null && ubicacion != null) {
      return '$direccion, $ubicacion';
    } else if (direccion != null) {
      return direccion!;
    } else if (ubicacion != null) {
      return ubicacion!;
    }
    return 'Sin ubicación';
  }

  String get estadoSuscripcion {
    if (fechaVencimientoSuscripcion == null) return 'Sin suscripción';
    
    final ahora = DateTime.now();
    if (fechaVencimientoSuscripcion!.isAfter(ahora)) {
      final diasRestantes = fechaVencimientoSuscripcion!.difference(ahora).inDays;
      if (diasRestantes <= 7) {
        return 'Por vencer ($diasRestantes días)';
      }
      return 'Activa';
    }
    return 'Vencida';
  }
}
