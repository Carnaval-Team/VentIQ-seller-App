import '../utils/stock_mixto_formatter.dart';

class SaldoPresentacion {
  final int idPresentacion;
  final String nombre;
  final String? skuCodigo;
  final double cantidadFisica;
  final double factorRel;
  final double equivalenteBase;
  final bool esBase;
  final int? nivel;

  const SaldoPresentacion({
    required this.idPresentacion,
    required this.nombre,
    this.skuCodigo,
    required this.cantidadFisica,
    required this.factorRel,
    required this.equivalenteBase,
    required this.esBase,
    this.nivel,
  });

  factory SaldoPresentacion.fromJson(Map<dynamic, dynamic> json) {
    final cantidad = _double(json['cantidad_fisica'] ?? json['cantidad']);
    final factor = _double(json['factor_rel'], fallback: 1);
    return SaldoPresentacion(
      idPresentacion: _int(json['id_presentacion']),
      nombre: json['nombre']?.toString() ?? 'Presentación',
      skuCodigo: json['sku_codigo']?.toString(),
      cantidadFisica: cantidad,
      factorRel: factor,
      equivalenteBase: _double(
        json['equivalente_base'],
        fallback: cantidad * factor,
      ),
      esBase: _bool(json['es_base']),
      nivel: _nullableInt(json['nivel']),
    );
  }

  Map<String, dynamic> toFormatterMap() => {
    'nombre': nombre,
    'cantidad': cantidadFisica,
    if (skuCodigo != null) 'sku_codigo': skuCodigo,
  };
}

class StockMixto {
  final List<SaldoPresentacion> desglose;
  final String texto;
  final String textoCorto;
  final double equivalenteBase;
  final String nombrePresentacionBase;

  const StockMixto({
    required this.desglose,
    required this.texto,
    required this.textoCorto,
    required this.equivalenteBase,
    this.nombrePresentacionBase = 'Unidad',
  });

  static const vacio = StockMixto(
    desglose: [],
    texto: 'Sin stock',
    textoCorto: '—',
    equivalenteBase: 0,
  );

  factory StockMixto.fromJson(Map<dynamic, dynamic> json) {
    final rawDesglose = json['stock_desglose'] ?? json['desglose'];
    final desglose = <SaldoPresentacion>[];
    if (rawDesglose is List) {
      for (final raw in rawDesglose) {
        if (raw is Map) {
          desglose.add(SaldoPresentacion.fromJson(raw));
        }
      }
    }

    final formatterData = desglose
        .map((saldo) => saldo.toFormatterMap())
        .toList();
    final textoServidor = json['stock_texto'] ?? json['texto'];
    final textoCortoServidor = json['stock_texto_corto'] ?? json['texto_corto'];
    final nombreBase =
        json['nombre_presentacion_base']?.toString() ?? _nombreBase(desglose);
    final equivalente = _double(
      json['stock_equivalente_base'] ?? json['equivalente_base'],
      fallback: desglose.fold(
        0,
        (total, saldo) => total + saldo.equivalenteBase,
      ),
    );

    return StockMixto(
      desglose: List.unmodifiable(desglose),
      texto: _texto(textoServidor) ?? StockMixtoFormatter.mixto(formatterData),
      textoCorto:
          _texto(textoCortoServidor) ??
          StockMixtoFormatter.mixto(formatterData, abreviar: true, vacio: '—'),
      equivalenteBase: equivalente,
      nombrePresentacionBase: nombreBase,
    );
  }

  double saldoDe(int idPresentacion) {
    for (final saldo in desglose) {
      if (saldo.idPresentacion == idPresentacion) return saldo.cantidadFisica;
    }
    return 0;
  }

  bool get tieneStock => desglose.any((saldo) => saldo.cantidadFisica != 0);

  static String _nombreBase(List<SaldoPresentacion> saldos) {
    for (final saldo in saldos) {
      if (saldo.esBase) return saldo.nombre;
    }
    return 'Unidad';
  }
}

class StockMixtoException implements Exception {
  final String operacion;
  final Object? causa;

  const StockMixtoException(this.operacion, [this.causa]);

  @override
  String toString() => causa == null
      ? 'No se pudo $operacion.'
      : 'No se pudo $operacion: $causa';
}

double _double(dynamic value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

int _int(dynamic value) => _nullableInt(value) ?? 0;

int? _nullableInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

bool _bool(dynamic value) =>
    value == true || value == 1 || value?.toString().toLowerCase() == 'true';

String? _texto(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
