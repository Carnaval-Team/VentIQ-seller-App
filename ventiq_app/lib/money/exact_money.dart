/// Importe exacto en unidades de 10^-6. No usa double como autoridad.
class ExactMoney {
  static const int _scale = 6;
  final BigInt _units;

  const ExactMoney._(this._units);

  static final ExactMoney cero = ExactMoney._(BigInt.zero);

  factory ExactMoney.parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      throw FormatException('Importe vacio');
    }
    final negative = text.startsWith('-');
    final body = negative ? text.substring(1) : text;
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(body)) {
      throw FormatException('Importe invalido');
    }
    final parts = body.split('.');
    final whole = parts[0];
    final frac = parts.length == 2 ? parts[1] : '';
    if (frac.length > _scale) {
      throw FormatException('Importe con mas de $_scale decimales');
    }
    final digits = whole + frac.padRight(_scale, '0');
    var units = BigInt.parse(digits);
    if (negative) units = -units;
    return ExactMoney._(units);
  }

  ExactMoney operator +(ExactMoney other) => ExactMoney._(_units + other._units);

  ExactMoney operator -(ExactMoney other) => ExactMoney._(_units - other._units);

  bool operator >(ExactMoney other) => _units > other._units;

  ExactMoney times(int factor) => ExactMoney._(_units * BigInt.from(factor));

  /// Producto de dos importes. El resultado vuelve a la escala 6 con half-up.
  ExactMoney timesMoney(ExactMoney other) {
    final product = _units * other._units;
    final scale = BigInt.from(10).pow(_scale);
    return ExactMoney._(_divideHalfUp(product, scale));
  }

  /// Resta [percent] por ciento. 10 sobre 1.05 deja 0.945.
  ExactMoney percentOff(int percent) {
    if (percent < 0 || percent > 100) {
      throw FormatException('Porcentaje invalido');
    }
    final next = _units * BigInt.from(100 - percent);
    return ExactMoney._(_divideHalfUp(next, BigInt.from(100)));
  }

  /// Suma [percent] por ciento. 10 sobre 1.05 deja 1.155.
  ExactMoney percentOn(int percent) {
    if (percent < 0 || percent > 100) {
      throw FormatException('Porcentaje invalido');
    }
    final next = _units * BigInt.from(100 + percent);
    return ExactMoney._(_divideHalfUp(next, BigInt.from(100)));
  }

  ExactMoney roundHalfUp(int places) {
    if (places < 0 || places > _scale) {
      throw FormatException('Escala invalida');
    }
    final factor = BigInt.from(10).pow(_scale - places);
    return ExactMoney._(_divideHalfUp(_units, factor) * factor);
  }

  /// Texto con [places] decimales, sin recortar ceros. 270 a 2 decimales es 270.00.
  String toFixed(int places) {
    final rounded = roundHalfUp(places);
    final negative = rounded._units.isNegative;
    final digits = rounded._units.abs().toString().padLeft(_scale + 1, '0');
    final whole = digits.substring(0, digits.length - _scale);
    if (places == 0) return negative ? '-$whole' : whole;
    final frac = digits.substring(digits.length - _scale, digits.length - _scale + places);
    final body = '$whole.$frac';
    return negative ? '-$body' : body;
  }

  static BigInt _divideHalfUp(BigInt value, BigInt factor) {
    final negative = value.isNegative;
    final abs = value.abs();
    final q = abs ~/ factor;
    final r = abs.remainder(factor);
    final half = factor ~/ BigInt.two;
    final rounded = r >= half ? q + BigInt.one : q;
    return negative ? -rounded : rounded;
  }

  @override
  String toString() {
    final negative = _units.isNegative;
    final digits = _units.abs().toString().padLeft(_scale + 1, '0');
    final whole = digits.substring(0, digits.length - _scale);
    var frac = digits.substring(digits.length - _scale);
    frac = frac.replaceFirst(RegExp(r'0+$'), '');
    final body = frac.isEmpty ? whole : '$whole.$frac';
    return negative ? '-$body' : body;
  }

  @override
  bool operator ==(Object other) => other is ExactMoney && other._units == _units;

  @override
  int get hashCode => _units.hashCode;
}
