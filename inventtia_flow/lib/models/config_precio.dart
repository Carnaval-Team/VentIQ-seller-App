/// Monedas soportadas en la aplicación (configurables por servicio).
class MonedasApp {
  MonedasApp._();

  static const todas = ['USD', 'EUR', 'CUP', 'MLC'];

  static String etiqueta(String codigo) => switch (codigo) {
        'USD' => 'USD — Dólar',
        'EUR' => 'EUR — Euro',
        'CUP' => 'CUP — Peso cubano',
        'MLC' => 'MLC — Moneda libremente convertible',
        _ => codigo,
      };

  static String simbolo(String codigo) => switch (codigo) {
        'USD' => '\$',
        'EUR' => '€',
        'CUP' => 'CUP',
        'MLC' => 'MLC',
        _ => codigo,
      };
}

/// Precio por opción de un campo select: [siClave] + mapa opción → precios por moneda.
class ReglaPrecio {
  final String siClave;
  /// opción del select → { moneda → precio }
  final Map<String, Map<String, double>> preciosOpcion;

  ReglaPrecio({
    required this.siClave,
    Map<String, Map<String, double>>? preciosOpcion,
  }) : preciosOpcion = preciosOpcion ?? {};

  factory ReglaPrecio.fromJson(Map<String, dynamic> json) {
    final siClave = json['si_clave']?.toString() ?? '';
    final out = <String, Map<String, double>>{};

    final rawOpcion = json['precios_opcion'];
    if (rawOpcion is Map) {
      for (final e in rawOpcion.entries) {
        final precios = _parsePreciosMoneda(e.value);
        if (precios.isNotEmpty) out[e.key.toString()] = precios;
      }
    } else {
      // Formato anterior: opciones[] + precios{} compartidos → migrar en lectura.
      final opciones = (json['opciones'] as List?)?.map((e) => e.toString()).toList() ?? [];
      final precios = _parsePreciosMoneda(json['precios']);
      if (precios.isNotEmpty) {
        for (final o in opciones) {
          out[o] = Map<String, double>.from(precios);
        }
      }
    }

    return ReglaPrecio(siClave: siClave, preciosOpcion: out);
  }

  static Map<String, double> _parsePreciosMoneda(Object? raw) {
    final precios = <String, double>{};
    if (raw is Map) {
      for (final e in raw.entries) {
        final v = e.value;
        if (v is num) precios[e.key.toString()] = v.toDouble();
      }
    }
    return precios;
  }

  Map<String, dynamic> toJson() => {
        'si_clave': siClave,
        if (preciosOpcion.isNotEmpty)
          'precios_opcion': preciosOpcion.map(
            (opcion, precios) => MapEntry(opcion, precios.map((k, v) => MapEntry(k, v))),
          ),
      };

  ReglaPrecio copyWith({
    String? siClave,
    Map<String, Map<String, double>>? preciosOpcion,
  }) =>
      ReglaPrecio(
        siClave: siClave ?? this.siClave,
        preciosOpcion: preciosOpcion ?? this.preciosOpcion,
      );
}

/// Configuración de precio de un servicio (columna config_precio en BD).
class ConfigPrecio {
  final String monedaDefault;
  final List<String> monedas;
  final Map<String, double> preciosBase;
  final List<ReglaPrecio> reglas;

  /// Transporte: si true, el precio del turno "ida y vuelta" aplica a todo
  /// pasaje ida+vuelta (aunque las fechas sean distintas).
  /// Si false (default), ese precio solo aplica cuando ambas fechas son el
  /// mismo día; en fechas distintas se cobran ida + vuelta por separado.
  final bool aplicaPrecioIdaVueltaTodos;

  ConfigPrecio({
    this.monedaDefault = 'USD',
    List<String>? monedas,
    Map<String, double>? preciosBase,
    List<ReglaPrecio>? reglas,
    this.aplicaPrecioIdaVueltaTodos = false,
  })  : monedas = monedas ?? const ['USD'],
        preciosBase = preciosBase ?? const {},
        reglas = reglas ?? const [];

  bool get tienePrecio =>
      preciosBase.values.any((v) => v > 0) ||
      reglas.any((r) =>
          r.preciosOpcion.values.any((m) => m.values.any((v) => v > 0)));

  factory ConfigPrecio.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return ConfigPrecio();
    final baseRaw = json['precios_base'];
    final base = <String, double>{};
    if (baseRaw is Map) {
      for (final e in baseRaw.entries) {
        final v = e.value;
        if (v is num) base[e.key.toString()] = v.toDouble();
      }
    }
    return ConfigPrecio(
      monedaDefault: json['moneda_default']?.toString() ?? 'USD',
      monedas: (json['monedas'] as List?)?.map((e) => e.toString()).toList() ??
          ['USD'],
      preciosBase: base,
      reglas: (json['reglas'] as List?)
              ?.map((e) => ReglaPrecio.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      aplicaPrecioIdaVueltaTodos:
          json['aplica_precio_ida_vuelta_todos'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'moneda_default': monedaDefault,
        'monedas': monedas,
        if (preciosBase.isNotEmpty)
          'precios_base': preciosBase.map((k, v) => MapEntry(k, v)),
        if (reglas.isNotEmpty) 'reglas': reglas.map((r) => r.toJson()).toList(),
        'aplica_precio_ida_vuelta_todos': aplicaPrecioIdaVueltaTodos,
      };

  ConfigPrecio copyWith({
    String? monedaDefault,
    List<String>? monedas,
    Map<String, double>? preciosBase,
    List<ReglaPrecio>? reglas,
    bool? aplicaPrecioIdaVueltaTodos,
  }) =>
      ConfigPrecio(
        monedaDefault: monedaDefault ?? this.monedaDefault,
        monedas: monedas ?? this.monedas,
        preciosBase: preciosBase ?? this.preciosBase,
        reglas: reglas ?? this.reglas,
        aplicaPrecioIdaVueltaTodos:
            aplicaPrecioIdaVueltaTodos ?? this.aplicaPrecioIdaVueltaTodos,
      );
}
