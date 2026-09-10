class EstadoFacturaProveedor {
  final int id;
  final String denominacion;
  final String? descripcion;
  final String? color;
  final int orden;
  final bool activo;

  EstadoFacturaProveedor({
    required this.id,
    required this.denominacion,
    this.descripcion,
    this.color,
    required this.orden,
    this.activo = true,
  });

  factory EstadoFacturaProveedor.fromJson(Map<String, dynamic> json) {
    return EstadoFacturaProveedor(
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

class FacturaFotoProveedor {
  final int? id;
  final int idFactura;
  final String fotoUrl;
  final int numeroPagina;
  final String? nombreArchivo;
  final String mimeType;
  final DateTime createdAt;

  FacturaFotoProveedor({
    this.id,
    required this.idFactura,
    required this.fotoUrl,
    required this.numeroPagina,
    this.nombreArchivo,
    this.mimeType = 'image/jpeg',
    required this.createdAt,
  });

  bool get isImage => mimeType.startsWith('image/');
  bool get isPdf => mimeType == 'application/pdf';

  String get displayName => nombreArchivo ?? 'Página $numeroPagina';

  static String _mimeFromUrl(String url) {
    final lower = url.toLowerCase().split('?').first;
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  factory FacturaFotoProveedor.fromJson(Map<String, dynamic> json) {
    final url = json['foto_url'] as String? ?? '';
    final mimeRaw = json['mime_type'] as String?;
    final mime = (mimeRaw != null && mimeRaw.isNotEmpty)
        ? mimeRaw
        : _mimeFromUrl(url);
    return FacturaFotoProveedor(
      id: json['id'],
      idFactura: json['id_factura'] ?? 0,
      fotoUrl: url,
      numeroPagina: json['numero_pagina'] ?? 1,
      nombreArchivo: json['nombre_archivo'],
      mimeType: mime,
      createdAt: DateTime.parse(
        json['created_at'] ?? DateTime.now().toIso8601String(),
      ),
    );
  }
}

class ProveedorFactura {
  final int? id;
  final int idProveedor;
  final String? nombreProveedor;
  final String numeroFactura;
  final double valor;
  final DateTime fechaProcesamiento;
  final String? fotoUrl;
  final int idEstado;
  final String? denominacionEstado;
  final String? colorEstado;
  final int idtienda;
  final DateTime createdAt;
  final List<FacturaFotoProveedor> fotos;

  ProveedorFactura({
    this.id,
    required this.idProveedor,
    this.nombreProveedor,
    required this.numeroFactura,
    required this.valor,
    required this.fechaProcesamiento,
    this.fotoUrl,
    required this.idEstado,
    this.denominacionEstado,
    this.colorEstado,
    required this.idtienda,
    required this.createdAt,
    this.fotos = const [],
  });

  factory ProveedorFactura.fromJson(Map<String, dynamic> json) {
    final fotosRaw = json['fotos'] as List<dynamic>?;
    return ProveedorFactura(
      id: json['id'],
      idProveedor: json['id_proveedor'] ?? 0,
      nombreProveedor: json['nombre_proveedor'] ??
          json['proveedor']?['denominacion'],
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
      fotos: fotosRaw != null
          ? fotosRaw
              .map((f) => FacturaFotoProveedor.fromJson(f))
              .toList()
          : [],
    );
  }

  ProveedorFactura copyWith({List<FacturaFotoProveedor>? fotos}) {
    return ProveedorFactura(
      id: id,
      idProveedor: idProveedor,
      nombreProveedor: nombreProveedor,
      numeroFactura: numeroFactura,
      valor: valor,
      fechaProcesamiento: fechaProcesamiento,
      fotoUrl: fotoUrl,
      idEstado: idEstado,
      denominacionEstado: denominacionEstado,
      colorEstado: colorEstado,
      idtienda: idtienda,
      createdAt: createdAt,
      fotos: fotos ?? this.fotos,
    );
  }
}

class RecargaSaldoProveedor {
  final int? id;
  final int idProveedor;
  final double monto;
  final DateTime fechaPago;
  final String? observacion;
  final int idtienda;
  final DateTime createdAt;

  RecargaSaldoProveedor({
    this.id,
    required this.idProveedor,
    required this.monto,
    required this.fechaPago,
    this.observacion,
    required this.idtienda,
    required this.createdAt,
  });

  factory RecargaSaldoProveedor.fromJson(Map<String, dynamic> json) {
    return RecargaSaldoProveedor(
      id: json['id'],
      idProveedor: json['id_proveedor'] ?? 0,
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

class HistorialSaldoProveedor {
  final int? id;
  final int idProveedor;
  final double montoAnterior;
  final double montoNuevo;
  final double diferencia;
  final String tipoOperacion; // 'recarga', 'descuento_factura', 'ajuste_factura'
  final String? referencia;
  final String? observacion;
  final int? idRecarga;
  final int idtienda;
  final DateTime createdAt;

  HistorialSaldoProveedor({
    this.id,
    required this.idProveedor,
    required this.montoAnterior,
    required this.montoNuevo,
    required this.diferencia,
    required this.tipoOperacion,
    this.referencia,
    this.observacion,
    this.idRecarga,
    required this.idtienda,
    required this.createdAt,
  });

  bool get esRecarga => tipoOperacion == 'recarga';

  factory HistorialSaldoProveedor.fromJson(Map<String, dynamic> json) {
    final recargaJoin = json['recarga'] as Map<String, dynamic>?;
    return HistorialSaldoProveedor(
      id: json['id'],
      idProveedor: json['id_proveedor'] ?? 0,
      montoAnterior: (json['monto_anterior'] ?? 0.0).toDouble(),
      montoNuevo: (json['monto_nuevo'] ?? 0.0).toDouble(),
      diferencia: (json['diferencia'] ?? 0.0).toDouble(),
      tipoOperacion: json['tipo_operacion'] ?? '',
      referencia: json['referencia'],
      observacion: recargaJoin?['observacion'] as String?,
      idRecarga: json['id_recarga'] as int?,
      idtienda: json['idtienda'] ?? 0,
      createdAt: DateTime.parse(
        json['created_at'] ?? DateTime.now().toIso8601String(),
      ),
    );
  }
}

class HistorialEstadoFacturaProveedor {
  final int? id;
  final int idFactura;
  final int idEstadoAnterior;
  final int idEstadoNuevo;
  final String? denominacionAnterior;
  final String? denominacionNuevo;
  final String? observacion;
  final DateTime createdAt;

  HistorialEstadoFacturaProveedor({
    this.id,
    required this.idFactura,
    required this.idEstadoAnterior,
    required this.idEstadoNuevo,
    this.denominacionAnterior,
    this.denominacionNuevo,
    this.observacion,
    required this.createdAt,
  });

  factory HistorialEstadoFacturaProveedor.fromJson(Map<String, dynamic> json) {
    return HistorialEstadoFacturaProveedor(
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

class MonedaPago {
  final int? id;
  final String codigo;
  final String denominacion;
  final String simbolo;
  final bool activo;
  final DateTime? createdAt;

  MonedaPago({
    this.id,
    required this.codigo,
    required this.denominacion,
    this.simbolo = '\$',
    this.activo = true,
    this.createdAt,
  });

  factory MonedaPago.fromJson(Map<String, dynamic> json) {
    return MonedaPago(
      id: json['id'],
      codigo: json['codigo'] ?? '',
      denominacion: json['denominacion'] ?? '',
      simbolo: json['simbolo'] ?? '\$',
      activo: json['activo'] ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'codigo': codigo,
      'denominacion': denominacion,
      'simbolo': simbolo,
      'activo': activo,
    };
  }
}

class ProveedorConfig {
  final int? id;
  final int idtienda;
  final int idProveedor;
  final int idMoneda;
  final String? monedaCodigo;
  final String? monedaSimbolo;
  final String? monedaDenominacion;

  ProveedorConfig({
    this.id,
    required this.idtienda,
    required this.idProveedor,
    required this.idMoneda,
    this.monedaCodigo,
    this.monedaSimbolo,
    this.monedaDenominacion,
  });

  factory ProveedorConfig.fromJson(Map<String, dynamic> json) {
    final moneda = json['moneda'] as Map<String, dynamic>?;
    return ProveedorConfig(
      id: json['id'],
      idtienda: json['idtienda'] ?? 0,
      idProveedor: json['id_proveedor'] ?? 0,
      idMoneda: json['id_moneda'] ?? 0,
      monedaCodigo: moneda?['codigo'] ?? json['moneda_codigo'],
      monedaSimbolo: moneda?['simbolo'] ?? json['moneda_simbolo'],
      monedaDenominacion: moneda?['denominacion'] ?? json['moneda_denominacion'],
    );
  }
}
