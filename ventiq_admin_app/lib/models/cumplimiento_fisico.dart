class PlanCumplimiento {
  final String status;
  final String? errorCode;
  final String mensaje;
  final int? idProducto;
  final int? idUbicacion;
  final int? idVariante;
  final int? idOpcionVariante;
  final int? idPresentacionSolicitada;
  final double? cantidadSolicitada;
  final double? equivalenteSolicitado;
  final double? equivalenteCumplido;
  final double? equivalenteDisponible;
  final double? maximoServible;
  final String? estrategia;
  final List<LineaFisica> lineasFisicas;
  final List<ConversionPresentacion> conversiones;
  final List<SaldoProyectado> saldosProyectados;

  const PlanCumplimiento({
    required this.status,
    this.errorCode,
    required this.mensaje,
    this.idProducto,
    this.idUbicacion,
    this.idVariante,
    this.idOpcionVariante,
    this.idPresentacionSolicitada,
    this.cantidadSolicitada,
    this.equivalenteSolicitado,
    this.equivalenteCumplido,
    this.equivalenteDisponible,
    this.maximoServible,
    this.estrategia,
    this.lineasFisicas = const [],
    this.conversiones = const [],
    this.saldosProyectados = const [],
  });

  bool get esExitoso => status == 'success';
  bool get requiereConversion => conversiones.isNotEmpty;

  factory PlanCumplimiento.fromJson(Map<String, dynamic> json) {
    return PlanCumplimiento(
      status: json['status']?.toString() ?? 'error',
      errorCode: _texto(json['error_code']),
      mensaje:
          _texto(json['mensaje_usuario']) ??
          _texto(json['message']) ??
          'No se pudo planificar el cumplimiento físico.',
      idProducto: _entero(json['id_producto']),
      idUbicacion: _entero(json['id_ubicacion']),
      idVariante: _entero(json['id_variante']),
      idOpcionVariante: _entero(json['id_opcion_variante']),
      idPresentacionSolicitada: _entero(json['id_presentacion_solicitada']),
      cantidadSolicitada: _decimal(json['cantidad_solicitada']),
      equivalenteSolicitado: _decimal(json['equivalente_solicitado']),
      equivalenteCumplido: _decimal(json['equivalente_cumplido']),
      equivalenteDisponible: _decimal(json['equivalente_disponible']),
      maximoServible: _decimal(json['maximo_servible']),
      estrategia: _texto(json['estrategia']),
      lineasFisicas: _listaMap(
        json['lineas_fisicas'],
      ).map(LineaFisica.fromJson).toList(growable: false),
      conversiones: _listaMap(
        json['conversiones'],
      ).map(ConversionPresentacion.fromJson).toList(growable: false),
      saldosProyectados: _listaMap(
        json['saldos_proyectados'],
      ).map(SaldoProyectado.fromJson).toList(growable: false),
    );
  }
}

class LineaFisica {
  final int idPresentacion;
  final String nombre;
  final double cantidad;
  final double factorEntero;
  final double equivalente;
  final String origen;

  const LineaFisica({
    required this.idPresentacion,
    required this.nombre,
    required this.cantidad,
    required this.factorEntero,
    required this.equivalente,
    required this.origen,
  });

  factory LineaFisica.fromJson(Map<String, dynamic> json) {
    return LineaFisica(
      idPresentacion: _entero(json['id_presentacion']) ?? 0,
      nombre: _texto(json['nombre']) ?? 'Presentación',
      cantidad: _decimal(json['cantidad']) ?? 0,
      factorEntero: _decimal(json['factor_entero']) ?? 0,
      equivalente: _decimal(json['equivalente']) ?? 0,
      origen: _texto(json['origen']) ?? 'propio',
    );
  }
}

class ConversionPresentacion {
  final String tipo;
  final int? idPresentacionOrigen;
  final int? idPresentacionDestino;
  final double? cantidadOrigen;
  final double? cantidadDestino;
  final List<PataConversionPresentacion> patas;

  const ConversionPresentacion({
    required this.tipo,
    this.idPresentacionOrigen,
    this.idPresentacionDestino,
    this.cantidadOrigen,
    this.cantidadDestino,
    this.patas = const [],
  });

  factory ConversionPresentacion.fromJson(Map<String, dynamic> json) {
    return ConversionPresentacion(
      tipo: _texto(json['tipo']) ?? 'conversion',
      idPresentacionOrigen: _entero(json['id_presentacion_origen']),
      idPresentacionDestino: _entero(json['id_presentacion_destino']),
      cantidadOrigen: _decimal(json['cantidad_origen']),
      cantidadDestino: _decimal(json['cantidad_destino']),
      patas: _listaMap(
        json['patas'],
      ).map(PataConversionPresentacion.fromJson).toList(growable: false),
    );
  }
}

class PataConversionPresentacion {
  final String tipo;
  final int idPresentacion;
  final double cantidad;
  final double factorEntero;
  final double equivalente;

  const PataConversionPresentacion({
    required this.tipo,
    required this.idPresentacion,
    required this.cantidad,
    required this.factorEntero,
    required this.equivalente,
  });

  factory PataConversionPresentacion.fromJson(Map<String, dynamic> json) {
    return PataConversionPresentacion(
      tipo: _texto(json['tipo']) ?? 'entrada',
      idPresentacion: _entero(json['id_presentacion']) ?? 0,
      cantidad: _decimal(json['cantidad']) ?? 0,
      factorEntero: _decimal(json['factor_entero']) ?? 0,
      equivalente: _decimal(json['equivalente']) ?? 0,
    );
  }
}

class SaldoProyectado {
  final int idPresentacion;
  final String nombre;
  final double cantidad;
  final double factorEntero;
  final double equivalente;

  const SaldoProyectado({
    required this.idPresentacion,
    required this.nombre,
    required this.cantidad,
    required this.factorEntero,
    required this.equivalente,
  });

  factory SaldoProyectado.fromJson(Map<String, dynamic> json) {
    return SaldoProyectado(
      idPresentacion: _entero(json['id_presentacion']) ?? 0,
      nombre: _texto(json['nombre']) ?? 'Presentación',
      cantidad: _decimal(json['cantidad']) ?? 0,
      factorEntero: _decimal(json['factor_entero']) ?? 0,
      equivalente: _decimal(json['equivalente']) ?? 0,
    );
  }
}

Iterable<Map<String, dynamic>> _listaMap(dynamic value) sync* {
  if (value is! List) return;
  for (final item in value) {
    if (item is Map) yield Map<String, dynamic>.from(item);
  }
}

String? _texto(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

double? _decimal(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

int? _entero(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
