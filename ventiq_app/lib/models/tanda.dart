/// Modelos de produccion por tandas (Fase 4).
///
/// Reflejan lo que devuelven `fn_listar_tandas_cocina`,
/// `fn_platos_por_tanda_cocina` y `fn_producir_tanda`.
library;

/// Estados de un lote de produccion. Coinciden con el CHECK de
/// `app_dat_produccion_tanda.estado`.
class EstadoTanda {
  static const int abierta = 1;
  static const int agotada = 2;
  static const int cerrada = 3;
  static const int anulada = 4;

  /// Lotes que siguen vivos en la cocina.
  static const List<int> vivos = [abierta, agotada];

  /// Historial.
  static const List<int> cerrados = [cerrada, anulada];
}

/// Un plato `por_tanda` del catalogo de la cocina, con lo que hay hecho y lo
/// que se podria producir.
class PlatoPorTanda {
  final int idProducto;
  final String producto;
  final String? sku;

  /// Porciones terminadas en el almacen de la cocina. Es lo que se puede vender
  /// ahora mismo; si es 0, el plato esta agotado aunque quede materia prima.
  final double porcionesHechas;

  /// Cuantas porciones mas se podrian cocinar con la MP que hay. Sale del
  /// minimo por ingrediente de floor(stock / cantidad_necesaria), con la parada
  /// de BOM aplicada.
  final double maxProducible;

  /// Ingrediente que limita la produccion. Es lo que el jefe necesita pedir al
  /// almacen. `null` si no hay limite calculable.
  final String? ingredienteLimite;
  final double? stockLimite;
  final double? porPorcionLimite;

  /// El plato tiene receta: sin ella no se puede calcular consumo ni producir.
  final bool tieneReceta;

  /// Lote abierto de este plato, si hay. Sirve para ofrecer "cerrar tanda".
  final int? tandaAbierta;

  const PlatoPorTanda({
    required this.idProducto,
    required this.producto,
    this.sku,
    required this.porcionesHechas,
    required this.maxProducible,
    this.ingredienteLimite,
    this.stockLimite,
    this.porPorcionLimite,
    required this.tieneReceta,
    this.tandaAbierta,
  });

  bool get agotado => porcionesHechas <= 0;
  bool get sePuedeProducir => tieneReceta && maxProducible > 0;
  bool get tieneLoteAbierto => tandaAbierta != null;

  /// Quedan pocas: hay que ir pensando en la proxima tanda. El umbral es
  /// deliberadamente bajo y fijo; afinarlo por plato es trabajo futuro.
  bool get quedanPocas => porcionesHechas > 0 && porcionesHechas <= 3;

  /// Texto para la tarjeta, en lenguaje de cocina.
  String get estadoTexto {
    if (!tieneReceta) return 'Sin receta';
    if (agotado) return 'Agotado';
    if (quedanPocas) return 'Quedan pocas';
    return 'Disponible';
  }

  String get porcionesTexto {
    final n = porcionesHechas;
    final txt = n % 1 == 0 ? n.toInt().toString() : n.toStringAsFixed(1);
    return n == 1 ? '1 porcion' : '$txt porciones';
  }

  factory PlatoPorTanda.fromJson(Map<String, dynamic> json) {
    double dec(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0;
      return 0;
    }

    final limite = json['ingrediente_limite'];
    final lim = limite is Map ? Map<String, dynamic>.from(limite) : null;

    return PlatoPorTanda(
      idProducto: (json['id_producto'] as num).toInt(),
      producto: json['producto'] as String? ?? 'Plato',
      sku: json['sku'] as String?,
      porcionesHechas: dec(json['porciones_hechas']),
      maxProducible: dec(json['max_producible']),
      ingredienteLimite: lim?['ingrediente'] as String?,
      stockLimite: lim == null ? null : dec(lim['stock']),
      porPorcionLimite: lim == null ? null : dec(lim['por_porcion']),
      tieneReceta: json['tiene_receta'] as bool? ?? false,
      tandaAbierta: json['tanda_abierta'] is num
          ? (json['tanda_abierta'] as num).toInt()
          : null,
    );
  }
}

/// Un lote producido.
class Tanda {
  final int id;
  final int idCocina;
  final String? cocina;
  final int idProducto;
  final String producto;
  final String? sku;

  final double producidas;
  final double descartadas;

  final int estado;
  final String estadoTexto;

  /// Stock del SKU terminado en el almacen de la cocina.
  ///
  /// OJO: es el stock del PRODUCTO, no el de este lote. Con dos tandas abiertas
  /// del mismo plato el valor se repite en ambas — no sumarlo.
  final double porcionesRestantes;

  final double? costoMp;
  final double? costoPorPorcion;

  final String? notas;
  final String? motivoDescarte;
  final String producidoPor;

  final DateTime createdAt;
  final DateTime? closedAt;
  final int minutosAbierta;

  const Tanda({
    required this.id,
    required this.idCocina,
    this.cocina,
    required this.idProducto,
    required this.producto,
    this.sku,
    required this.producidas,
    required this.descartadas,
    required this.estado,
    required this.estadoTexto,
    required this.porcionesRestantes,
    this.costoMp,
    this.costoPorPorcion,
    this.notas,
    this.motivoDescarte,
    required this.producidoPor,
    required this.createdAt,
    this.closedAt,
    required this.minutosAbierta,
  });

  bool get abierta => estado == EstadoTanda.abierta;
  bool get cerrada => estado == EstadoTanda.cerrada;
  bool get anulada => estado == EstadoTanda.anulada;
  bool get viva => EstadoTanda.vivos.contains(estado);

  /// Se sirvieron todas: el lote esta consumido aunque no se haya cerrado.
  bool get consumida => viva && porcionesRestantes <= 0;

  /// Porciones que salieron, estimadas contra lo producido.
  double get servidasEstimado =>
      (producidas - descartadas - porcionesRestantes).clamp(0, producidas);

  /// Costo real por porcion SERVIDA: incluye lo que se boto. Es el numero que
  /// dice si el tamano del lote es el adecuado.
  double? get costoPorServida {
    final servibles = producidas - descartadas;
    if (costoMp == null || servibles <= 0) return null;
    return costoMp! / servibles;
  }

  String num2(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);

  factory Tanda.fromJson(Map<String, dynamic> json) {
    double dec(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0;
      return 0;
    }

    double? decNull(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    DateTime? fecha(String k) => json[k] == null
        ? null
        : DateTime.tryParse(json[k] as String? ?? '');

    return Tanda(
      id: (json['id'] as num).toInt(),
      idCocina: (json['id_cocina'] as num).toInt(),
      cocina: json['cocina'] as String?,
      idProducto: (json['id_producto'] as num).toInt(),
      producto: json['producto'] as String? ?? 'Plato',
      sku: json['sku'] as String?,
      producidas: dec(json['producidas']),
      descartadas: dec(json['descartadas']),
      estado: json['estado'] is num
          ? (json['estado'] as num).toInt()
          : EstadoTanda.abierta,
      estadoTexto: json['estado_texto'] as String? ?? 'Abierta',
      porcionesRestantes: dec(json['porciones_restantes']),
      costoMp: decNull(json['costo_mp']),
      costoPorPorcion: decNull(json['costo_por_porcion']),
      notas: json['notas'] as String?,
      motivoDescarte: json['motivo_descarte'] as String?,
      producidoPor: json['producido_por'] as String? ?? 'Sin identificar',
      createdAt: fecha('created_at') ?? DateTime.now(),
      closedAt: fecha('closed_at'),
      minutosAbierta: json['minutos_abierta'] is num
          ? (json['minutos_abierta'] as num).toInt()
          : 0,
    );
  }
}

/// Resultado de `fn_producir_tanda`.
class ProduccionResultado {
  final int idTanda;
  final String producto;
  final String? cocina;
  final double porciones;
  final double stockPrevio;
  final double stockNuevo;
  final double? costoMp;
  final double? costoPorPorcion;

  /// Que se consumio y cuanto. `es_por_tanda` marca los componentes donde la
  /// explosion de receta se detuvo (se consumieron porciones hechas, no MP).
  final List<Map<String, dynamic>> consumo;

  final String mensaje;

  const ProduccionResultado({
    required this.idTanda,
    required this.producto,
    this.cocina,
    required this.porciones,
    required this.stockPrevio,
    required this.stockNuevo,
    this.costoMp,
    this.costoPorPorcion,
    this.consumo = const [],
    required this.mensaje,
  });

  factory ProduccionResultado.fromJson(Map<String, dynamic> json) {
    double dec(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0;
      return 0;
    }

    final c = json['consumo'];

    return ProduccionResultado(
      idTanda: (json['id_tanda'] as num).toInt(),
      producto: json['producto'] as String? ?? 'Plato',
      cocina: json['cocina'] as String?,
      porciones: dec(json['porciones']),
      stockPrevio: dec(json['stock_previo']),
      stockNuevo: dec(json['stock_nuevo']),
      costoMp: json['costo_mp'] == null ? null : dec(json['costo_mp']),
      costoPorPorcion:
          json['costo_por_porcion'] == null ? null : dec(json['costo_por_porcion']),
      consumo: c is List
          ? c.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : const [],
      mensaje: json['message'] as String? ?? 'Tanda producida',
    );
  }
}

/// Error de negocio de las RPC de tandas.
class TandaException implements Exception {
  final String errorCode;
  final String mensaje;

  /// Ingredientes que faltan, cuando el error es de stock. Cada entrada trae
  /// `ingrediente`, `necesario`, `disponible`, `falta`.
  final List<Map<String, dynamic>> faltantes;

  const TandaException(
    this.errorCode,
    this.mensaje, {
    this.faltantes = const [],
  });

  bool get esFaltaDeStock => errorCode == 'INSUFFICIENT_STOCK';

  /// El plato no esta configurado como `por_tanda`: lo arregla el gerente en la
  /// gestion de platos, no el cocinero.
  bool get esConfiguracion =>
      errorCode == 'NO_ES_POR_TANDA' ||
      errorCode == 'PLATO_OTRA_COCINA' ||
      errorCode == 'SIN_RECETA' ||
      errorCode == 'SIN_PRESENTACION';

  bool get requiereMotivo => errorCode == 'MOTIVO_REQUERIDO';

  /// Ya salieron porciones: hay que cerrar con merma en vez de anular.
  bool get yaConsumida => errorCode == 'TANDA_YA_CONSUMIDA';

  String get titulo {
    if (esFaltaDeStock) return 'Falta materia prima';
    if (esConfiguracion) return 'El plato no esta listo para tandas';
    if (yaConsumida) return 'Ya se sirvieron porciones';
    if (requiereMotivo) return 'Hace falta un motivo';
    return 'No se pudo completar';
  }

  factory TandaException.fromJson(Map<String, dynamic> json) {
    final f = json['faltantes'];
    return TandaException(
      json['error_code'] as String? ?? 'UNKNOWN',
      json['message'] as String? ?? 'Ocurrio un error',
      faltantes: f is List
          ? f.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : const [],
    );
  }

  @override
  String toString() => mensaje;
}
