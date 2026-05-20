class EstadoFactura {
  final int id;
  final String denominacion;
  final String? descripcion;
  final String? color;
  final int orden;
  final bool activo;

  EstadoFactura({
    required this.id,
    required this.denominacion,
    this.descripcion,
    this.color,
    required this.orden,
    this.activo = true,
  });

  factory EstadoFactura.fromJson(Map<String, dynamic> json) {
    return EstadoFactura(
      id: json['id'] ?? 0,
      denominacion: json['denominacion'] ?? '',
      descripcion: json['descripcion'],
      color: json['color'],
      orden: json['orden'] ?? 0,
      activo: json['activo'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'denominacion': denominacion,
      'descripcion': descripcion,
      'color': color,
      'orden': orden,
      'activo': activo,
    };
  }
}

class ImportadoraFactura {
  final int? id;
  final String numeroFactura;
  final double valor;
  final DateTime fechaProcesamiento;
  final String? fotoUrl;
  final int idEstado;
  final String? denominacionEstado;
  final String? colorEstado;
  final int idtienda;
  final DateTime createdAt;

  ImportadoraFactura({
    this.id,
    required this.numeroFactura,
    required this.valor,
    required this.fechaProcesamiento,
    this.fotoUrl,
    required this.idEstado,
    this.denominacionEstado,
    this.colorEstado,
    required this.idtienda,
    required this.createdAt,
  });

  factory ImportadoraFactura.fromJson(Map<String, dynamic> json) {
    return ImportadoraFactura(
      id: json['id'],
      numeroFactura: json['numero_factura'] ?? '',
      valor: (json['valor'] ?? 0.0).toDouble(),
      fechaProcesamiento: DateTime.parse(
        json['fecha_procesamiento'] ?? DateTime.now().toIso8601String(),
      ),
      fotoUrl: json['foto_url'],
      idEstado: json['id_estado'] ?? 0,
      denominacionEstado: json['estado']?['denominacion'],
      colorEstado: json['estado']?['color'],
      idtienda: json['idtienda'] ?? 0,
      createdAt: DateTime.parse(
        json['created_at'] ?? DateTime.now().toIso8601String(),
      ),
    );
  }
}

class RecargaSaldo {
  final int? id;
  final double monto;
  final DateTime fechaPago;
  final String? observacion;
  final int idtienda;
  final DateTime createdAt;

  RecargaSaldo({
    this.id,
    required this.monto,
    required this.fechaPago,
    this.observacion,
    required this.idtienda,
    required this.createdAt,
  });

  factory RecargaSaldo.fromJson(Map<String, dynamic> json) {
    return RecargaSaldo(
      id: json['id'],
      monto: (json['monto'] ?? 0.0).toDouble(),
      fechaPago: DateTime.parse(
        json['fecha_pago'] ?? DateTime.now().toIso8601String(),
      ),
      observacion: json['observacion'],
      idtienda: json['idtienda'] ?? 0,
      createdAt: DateTime.parse(
        json['created_at'] ?? DateTime.now().toIso8601String(),
      ),
    );
  }
}

class HistorialSaldo {
  final int? id;
  final double montoAnterior;
  final double montoNuevo;
  final double diferencia;
  final String tipoOperacion; // 'recarga', 'descuento_factura'
  final String? referencia;
  final int idtienda;
  final DateTime createdAt;

  HistorialSaldo({
    this.id,
    required this.montoAnterior,
    required this.montoNuevo,
    required this.diferencia,
    required this.tipoOperacion,
    this.referencia,
    required this.idtienda,
    required this.createdAt,
  });

  factory HistorialSaldo.fromJson(Map<String, dynamic> json) {
    return HistorialSaldo(
      id: json['id'],
      montoAnterior: (json['monto_anterior'] ?? 0.0).toDouble(),
      montoNuevo: (json['monto_nuevo'] ?? 0.0).toDouble(),
      diferencia: (json['diferencia'] ?? 0.0).toDouble(),
      tipoOperacion: json['tipo_operacion'] ?? '',
      referencia: json['referencia'],
      idtienda: json['idtienda'] ?? 0,
      createdAt: DateTime.parse(
        json['created_at'] ?? DateTime.now().toIso8601String(),
      ),
    );
  }
}

class HistorialEstadoFactura {
  final int? id;
  final int idFactura;
  final int idEstadoAnterior;
  final int idEstadoNuevo;
  final String? denominacionAnterior;
  final String? denominacionNuevo;
  final String? observacion;
  final DateTime createdAt;

  HistorialEstadoFactura({
    this.id,
    required this.idFactura,
    required this.idEstadoAnterior,
    required this.idEstadoNuevo,
    this.denominacionAnterior,
    this.denominacionNuevo,
    this.observacion,
    required this.createdAt,
  });

  factory HistorialEstadoFactura.fromJson(Map<String, dynamic> json) {
    return HistorialEstadoFactura(
      id: json['id'],
      idFactura: json['id_factura'] ?? 0,
      idEstadoAnterior: json['id_estado_anterior'] ?? 0,
      idEstadoNuevo: json['id_estado_nuevo'] ?? 0,
      denominacionAnterior: json['estado_anterior']?['denominacion'],
      denominacionNuevo: json['estado_nuevo']?['denominacion'],
      observacion: json['observacion'],
      createdAt: DateTime.parse(
        json['created_at'] ?? DateTime.now().toIso8601String(),
      ),
    );
  }
}
