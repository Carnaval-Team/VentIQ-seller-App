class CarnavalProviderResumen {
  final int ordenesCount;
  final int ordenesCompletadas;
  final double productosVendidos;
  final double montoTotal;
  final double ticketPromedio;

  CarnavalProviderResumen({
    required this.ordenesCount,
    required this.ordenesCompletadas,
    required this.productosVendidos,
    required this.montoTotal,
    required this.ticketPromedio,
  });

  factory CarnavalProviderResumen.fromJson(Map<String, dynamic> json) {
    return CarnavalProviderResumen(
      ordenesCount: (json['ordenes_count'] as num?)?.toInt() ?? 0,
      ordenesCompletadas: (json['ordenes_completadas'] as num?)?.toInt() ?? 0,
      productosVendidos: (json['productos_vendidos'] as num?)?.toDouble() ?? 0,
      montoTotal: (json['monto_total'] as num?)?.toDouble() ?? 0,
      ticketPromedio: (json['ticket_promedio'] as num?)?.toDouble() ?? 0,
    );
  }
}

class CarnavalProviderEstado {
  final String status;
  final int count;

  CarnavalProviderEstado({required this.status, required this.count});

  factory CarnavalProviderEstado.fromJson(Map<String, dynamic> json) {
    return CarnavalProviderEstado(
      status: (json['status'] as String?) ?? 'Desconocido',
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}

class CarnavalProviderMetodoPago {
  final String metodoPago;
  final int ordenesCount;
  final double monto;

  CarnavalProviderMetodoPago({
    required this.metodoPago,
    required this.ordenesCount,
    required this.monto,
  });

  factory CarnavalProviderMetodoPago.fromJson(Map<String, dynamic> json) {
    return CarnavalProviderMetodoPago(
      metodoPago: (json['metodo_pago'] as String?) ?? 'Otro',
      ordenesCount: (json['ordenes_count'] as num?)?.toInt() ?? 0,
      monto: (json['monto'] as num?)?.toDouble() ?? 0,
    );
  }
}

class CarnavalProviderDia {
  final String fecha;
  final int ordenesCount;
  final double productosVendidos;
  final double monto;

  CarnavalProviderDia({
    required this.fecha,
    required this.ordenesCount,
    required this.productosVendidos,
    required this.monto,
  });

  factory CarnavalProviderDia.fromJson(Map<String, dynamic> json) {
    return CarnavalProviderDia(
      fecha: (json['fecha'] as String?) ?? '',
      ordenesCount: (json['ordenes_count'] as num?)?.toInt() ?? 0,
      productosVendidos: (json['productos_vendidos'] as num?)?.toDouble() ?? 0,
      monto: (json['monto'] as num?)?.toDouble() ?? 0,
    );
  }
}

class CarnavalProviderTopProducto {
  final int id;
  final String nombre;
  final double cantidad;
  final double monto;

  CarnavalProviderTopProducto({
    required this.id,
    required this.nombre,
    required this.cantidad,
    required this.monto,
  });

  factory CarnavalProviderTopProducto.fromJson(Map<String, dynamic> json) {
    return CarnavalProviderTopProducto(
      id: (json['id'] as num?)?.toInt() ?? 0,
      nombre: (json['nombre'] as String?) ?? 'Producto sin nombre',
      cantidad: (json['cantidad'] as num?)?.toDouble() ?? 0,
      monto: (json['monto'] as num?)?.toDouble() ?? 0,
    );
  }
}

class CarnavalProviderDashboardData {
  final int? idProveedorCarnaval;
  final DateTime? desde;
  final DateTime? hasta;
  final CarnavalProviderResumen resumen;
  final List<CarnavalProviderEstado> porEstado;
  final List<CarnavalProviderMetodoPago> porMetodoPago;
  final List<CarnavalProviderDia> evolucionDiaria;
  final List<CarnavalProviderTopProducto> topProductos;
  final String? error;

  CarnavalProviderDashboardData({
    this.idProveedorCarnaval,
    this.desde,
    this.hasta,
    required this.resumen,
    required this.porEstado,
    required this.porMetodoPago,
    required this.evolucionDiaria,
    required this.topProductos,
    this.error,
  });

  bool get hasError => error != null && error!.isNotEmpty;

  factory CarnavalProviderDashboardData.fromJson(Map<String, dynamic> json) {
    if (json['error'] != null) {
      return CarnavalProviderDashboardData(
        resumen: CarnavalProviderResumen.fromJson({}),
        porEstado: const [],
        porMetodoPago: const [],
        evolucionDiaria: const [],
        topProductos: const [],
        error: json['error'] as String?,
      );
    }

    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is DateTime) return value;
      return DateTime.tryParse(value.toString());
    }

    return CarnavalProviderDashboardData(
      idProveedorCarnaval: (json['id_proveedor_carnaval'] as num?)?.toInt(),
      desde: parseDate(json['desde']),
      hasta: parseDate(json['hasta']),
      resumen: CarnavalProviderResumen.fromJson(
        (json['resumen'] as Map?)?.cast<String, dynamic>() ?? {},
      ),
      porEstado: (json['por_estado'] as List?)
              ?.map((e) => CarnavalProviderEstado.fromJson(
                  (e as Map).cast<String, dynamic>()))
              .toList() ??
          const [],
      porMetodoPago: (json['por_metodo_pago'] as List?)
              ?.map((e) => CarnavalProviderMetodoPago.fromJson(
                  (e as Map).cast<String, dynamic>()))
              .toList() ??
          const [],
      evolucionDiaria: (json['evolucion_diaria'] as List?)
              ?.map((e) => CarnavalProviderDia.fromJson(
                  (e as Map).cast<String, dynamic>()))
              .toList() ??
          const [],
      topProductos: (json['top_productos'] as List?)
              ?.map((e) => CarnavalProviderTopProducto.fromJson(
                  (e as Map).cast<String, dynamic>()))
              .toList() ??
          const [],
    );
  }
}
