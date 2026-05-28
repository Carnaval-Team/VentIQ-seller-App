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

class FacturaFoto {
  final int? id;
  final int idFactura;
  final String fotoUrl;
  final int numeroPagina;
  final String? nombreArchivo;
  final String mimeType;
  final DateTime createdAt;

  FacturaFoto({
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
    if (lower.endsWith('.pdf'))  return 'application/pdf';
    if (lower.endsWith('.doc'))  return 'application/msword';
    if (lower.endsWith('.docx')) return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    if (lower.endsWith('.xls'))  return 'application/vnd.ms-excel';
    if (lower.endsWith('.xlsx')) return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    if (lower.endsWith('.png'))  return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif'))  return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  factory FacturaFoto.fromJson(Map<String, dynamic> json) {
    final url = json['foto_url'] as String? ?? '';
    final mimeRaw = json['mime_type'] as String?;
    final mime = (mimeRaw != null && mimeRaw.isNotEmpty)
        ? mimeRaw
        : _mimeFromUrl(url);
    return FacturaFoto(
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
  final List<FacturaFoto> fotos;

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
    this.fotos = const [],
  });

  factory ImportadoraFactura.fromJson(Map<String, dynamic> json) {
    final fotosRaw = json['fotos'] as List<dynamic>?;
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
      fotos: fotosRaw != null
          ? fotosRaw.map((f) => FacturaFoto.fromJson(f)).toList()
          : [],
    );
  }

  ImportadoraFactura copyWith({List<FacturaFoto>? fotos}) {
    return ImportadoraFactura(
      id: id,
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
  final String? observacion;
  final int idtienda;
  final DateTime createdAt;

  HistorialSaldo({
    this.id,
    required this.montoAnterior,
    required this.montoNuevo,
    required this.diferencia,
    required this.tipoOperacion,
    this.referencia,
    this.observacion,
    required this.idtienda,
    required this.createdAt,
  });

  factory HistorialSaldo.fromJson(Map<String, dynamic> json) {
    // observacion puede venir del join con imp_dat_recarga_saldo
    final recargaJoin = json['recarga'] as Map<String, dynamic>?;
    return HistorialSaldo(
      id: json['id'],
      montoAnterior: (json['monto_anterior'] ?? 0.0).toDouble(),
      montoNuevo: (json['monto_nuevo'] ?? 0.0).toDouble(),
      diferencia: (json['diferencia'] ?? 0.0).toDouble(),
      tipoOperacion: json['tipo_operacion'] ?? '',
      referencia: json['referencia'],
      observacion: recargaJoin?['observacion'] as String?,
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
