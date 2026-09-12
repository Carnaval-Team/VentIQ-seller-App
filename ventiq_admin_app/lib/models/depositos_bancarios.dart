class MonedaDeposito {
  final int? id;
  final String codigo;
  final String denominacion;
  final String simbolo;
  final bool activo;

  MonedaDeposito({
    this.id,
    required this.codigo,
    required this.denominacion,
    this.simbolo = '\$',
    this.activo = true,
  });

  factory MonedaDeposito.fromJson(Map<String, dynamic> json) {
    return MonedaDeposito(
      id: json['id'],
      codigo: json['codigo'] ?? '',
      denominacion: json['denominacion'] ?? '',
      simbolo: json['simbolo'] ?? '\$',
      activo: json['activo'] ?? true,
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

class BancoDeposito {
  final int id;
  final int idtienda;
  final String denominacion;
  final int idMoneda;
  final String? nombreMoneda;
  final String? codigoMoneda;
  final String? simboloMoneda;
  final bool activo;
  final bool esPredeterminadaFondoCaja;
  final String? observacion;

  BancoDeposito({
    required this.id,
    required this.idtienda,
    required this.denominacion,
    required this.idMoneda,
    this.nombreMoneda,
    this.codigoMoneda,
    this.simboloMoneda,
    this.activo = true,
    this.esPredeterminadaFondoCaja = false,
    this.observacion,
  });

  String get monedaLabel {
    if (codigoMoneda != null && codigoMoneda!.isNotEmpty) {
      return codigoMoneda!;
    }
    return nombreMoneda ?? '';
  }

  factory BancoDeposito.fromJson(Map<String, dynamic> json) {
    final moneda = json['moneda'] as Map<String, dynamic>?;
    return BancoDeposito(
      id: json['id'] ?? 0,
      idtienda: json['idtienda'] ?? 0,
      denominacion: json['denominacion'] ?? '',
      idMoneda: json['id_moneda'] ?? 0,
      nombreMoneda: moneda?['denominacion'] as String?,
      codigoMoneda: moneda?['codigo'] as String?,
      simboloMoneda: moneda?['simbolo'] as String?,
      activo: json['activo'] ?? true,
      esPredeterminadaFondoCaja: json['es_predeterminada_fondo_caja'] ?? false,
      observacion: json['observacion'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'denominacion': denominacion,
      'id_moneda': idMoneda,
      'activo': activo,
      'es_predeterminada_fondo_caja': esPredeterminadaFondoCaja,
      'observacion': observacion,
    };
  }
}

class EstadoDeposito {
  final int id;
  final String denominacion;
  final String? descripcion;
  final String? color;
  final int orden;
  final bool activo;

  EstadoDeposito({
    required this.id,
    required this.denominacion,
    this.descripcion,
    this.color,
    required this.orden,
    this.activo = true,
  });

  factory EstadoDeposito.fromJson(Map<String, dynamic> json) {
    return EstadoDeposito(
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

class DepositoFoto {
  final int? id;
  final int idDeposito;
  final String fotoUrl;
  final int numeroPagina;
  final String? nombreArchivo;
  final String mimeType;
  final DateTime createdAt;

  DepositoFoto({
    this.id,
    required this.idDeposito,
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

  factory DepositoFoto.fromJson(Map<String, dynamic> json) {
    final url = json['foto_url'] as String? ?? '';
    final mimeRaw = json['mime_type'] as String?;
    final mime = (mimeRaw != null && mimeRaw.isNotEmpty)
        ? mimeRaw
        : _mimeFromUrl(url);
    return DepositoFoto(
      id: json['id'],
      idDeposito: json['id_deposito'] ?? 0,
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

class TipoExtraccion {
  final int? id;
  final String denominacion;
  final String? descripcion;
  final String? color;
  final int orden;
  final bool activo;

  TipoExtraccion({
    this.id,
    required this.denominacion,
    this.descripcion,
    this.color,
    required this.orden,
    this.activo = true,
  });

  factory TipoExtraccion.fromJson(Map<String, dynamic> json) {
    return TipoExtraccion(
      id: json['id'],
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

class DepositoBancario {
  final int? id;
  final String numeroDeposito;
  final double valor;
  final DateTime fechaProcesamiento;
  final String? fotoUrl;
  final int idEstado;
  final String? denominacionEstado;
  final String? colorEstado;
  final int? idTipoExtraccion;
  final String? denominacionTipoExtraccion;
  final String? colorTipoExtraccion;
  final int idBanco;
  final String? nombreBanco;
  final int idtienda;
  final DateTime createdAt;
  final List<DepositoFoto> fotos;

  DepositoBancario({
    this.id,
    required this.numeroDeposito,
    required this.valor,
    required this.fechaProcesamiento,
    this.fotoUrl,
    required this.idEstado,
    this.denominacionEstado,
    this.colorEstado,
    this.idTipoExtraccion,
    this.denominacionTipoExtraccion,
    this.colorTipoExtraccion,
    required this.idBanco,
    this.nombreBanco,
    required this.idtienda,
    required this.createdAt,
    this.fotos = const [],
  });

  factory DepositoBancario.fromJson(Map<String, dynamic> json) {
    final fotosRaw = json['fotos'] as List<dynamic>?;
    final banco = json['banco'] as Map<String, dynamic>?;
    final tipoExtraccion = json['tipo_extraccion'] as Map<String, dynamic>?;
    return DepositoBancario(
      id: json['id'],
      numeroDeposito: json['numero_deposito'] ?? '',
      valor: (json['valor'] ?? 0.0).toDouble(),
      fechaProcesamiento: DateTime.parse(
        json['fecha_procesamiento'] ?? DateTime.now().toIso8601String(),
      ),
      fotoUrl: json['foto_url'],
      idEstado: json['id_estado'] ?? 0,
      denominacionEstado: json['estado']?['denominacion'],
      colorEstado: json['estado']?['color'],
      idTipoExtraccion: json['id_tipo_extraccion'],
      denominacionTipoExtraccion: tipoExtraccion?['denominacion'],
      colorTipoExtraccion: tipoExtraccion?['color'],
      idBanco: json['id_banco'] ?? 0,
      nombreBanco: banco?['denominacion'] as String?,
      idtienda: json['idtienda'] ?? 0,
      createdAt: DateTime.parse(
        json['created_at'] ?? DateTime.now().toIso8601String(),
      ),
      fotos: fotosRaw != null
          ? fotosRaw.map((f) => DepositoFoto.fromJson(f)).toList()
          : [],
    );
  }

  DepositoBancario copyWith({List<DepositoFoto>? fotos}) {
    return DepositoBancario(
      id: id,
      numeroDeposito: numeroDeposito,
      valor: valor,
      fechaProcesamiento: fechaProcesamiento,
      fotoUrl: fotoUrl,
      idEstado: idEstado,
      denominacionEstado: denominacionEstado,
      colorEstado: colorEstado,
      idTipoExtraccion: idTipoExtraccion,
      denominacionTipoExtraccion: denominacionTipoExtraccion,
      colorTipoExtraccion: colorTipoExtraccion,
      idBanco: idBanco,
      nombreBanco: nombreBanco,
      idtienda: idtienda,
      createdAt: createdAt,
      fotos: fotos ?? this.fotos,
    );
  }
}

class RecargaSaldoDeposito {
  final int? id;
  final double monto;
  final DateTime fechaPago;
  final String? observacion;
  final int idBanco;
  final int idtienda;
  final DateTime createdAt;

  RecargaSaldoDeposito({
    this.id,
    required this.monto,
    required this.fechaPago,
    this.observacion,
    required this.idBanco,
    required this.idtienda,
    required this.createdAt,
  });

  factory RecargaSaldoDeposito.fromJson(Map<String, dynamic> json) {
    return RecargaSaldoDeposito(
      id: json['id'],
      monto: (json['monto'] ?? 0.0).toDouble(),
      fechaPago: DateTime.parse(
        json['fecha_pago'] ?? DateTime.now().toIso8601String(),
      ),
      observacion: json['observacion'],
      idBanco: json['id_banco'] ?? 0,
      idtienda: json['idtienda'] ?? 0,
      createdAt: DateTime.parse(
        json['created_at'] ?? DateTime.now().toIso8601String(),
      ),
    );
  }
}

class HistorialSaldoDeposito {
  final int? id;
  final double montoAnterior;
  final double montoNuevo;
  final double diferencia;
  final String
  tipoOperacion; // 'recarga', 'descuento_deposito', 'ajuste_deposito'
  final String? referencia;
  final String? observacion;
  final int? idRecarga;
  final int idBanco;
  final int idtienda;
  final DateTime createdAt;

  HistorialSaldoDeposito({
    this.id,
    required this.montoAnterior,
    required this.montoNuevo,
    required this.diferencia,
    required this.tipoOperacion,
    this.referencia,
    this.observacion,
    this.idRecarga,
    required this.idBanco,
    required this.idtienda,
    required this.createdAt,
  });

  bool get esRecarga => tipoOperacion == 'recarga';

  factory HistorialSaldoDeposito.fromJson(Map<String, dynamic> json) {
    final recargaJoin = json['recarga'] as Map<String, dynamic>?;
    return HistorialSaldoDeposito(
      id: json['id'],
      montoAnterior: (json['monto_anterior'] ?? 0.0).toDouble(),
      montoNuevo: (json['monto_nuevo'] ?? 0.0).toDouble(),
      diferencia: (json['diferencia'] ?? 0.0).toDouble(),
      tipoOperacion: json['tipo_operacion'] ?? '',
      referencia: json['referencia'],
      observacion: recargaJoin?['observacion'] as String?,
      idRecarga: json['id_recarga'] as int?,
      idBanco: json['id_banco'] ?? 0,
      idtienda: json['idtienda'] ?? 0,
      createdAt: DateTime.parse(
        json['created_at'] ?? DateTime.now().toIso8601String(),
      ),
    );
  }
}

class HistorialEstadoDeposito {
  final int? id;
  final int idDeposito;
  final int idEstadoAnterior;
  final int idEstadoNuevo;
  final String? denominacionAnterior;
  final String? denominacionNuevo;
  final String? observacion;
  final DateTime createdAt;

  HistorialEstadoDeposito({
    this.id,
    required this.idDeposito,
    required this.idEstadoAnterior,
    required this.idEstadoNuevo,
    this.denominacionAnterior,
    this.denominacionNuevo,
    this.observacion,
    required this.createdAt,
  });

  factory HistorialEstadoDeposito.fromJson(Map<String, dynamic> json) {
    return HistorialEstadoDeposito(
      id: json['id'],
      idDeposito: json['id_deposito'] ?? 0,
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
