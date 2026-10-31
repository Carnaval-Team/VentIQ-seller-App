/// Configuración de precios automáticos de una entidad (tabla
/// `flow.precio_config`, migración 60).
///
/// La lee y escribe `PrecioConfigService` con las RPC
/// `admin_precio_config_get/set`. La app la usa para saber:
///
///  * si el cálculo automático está activo ([autoActivo]),
///  * desde qué moneda se escribe el precio a mano ([monedaOrigen]),
///  * cuántos decimales se aplican a CUP ([redondeoCup]) y a las divisas
///    ([redondeoDivisa]).
///
/// Modelo puro: sin Flutter ni Supabase.
class PrecioConfig {
  /// Si es `false`, el formulario no calcula solo: el admin pulsa el botón.
  final bool autoActivo;

  /// Moneda desde la que se escribe el precio («calcular desde …»).
  final String monedaOrigen;

  /// Decimales de los precios en CUP (0–2). La tasa del toque es entera.
  final int redondeoCup;

  /// Decimales de los precios en divisas (0–2).
  final int redondeoDivisa;

  const PrecioConfig({
    this.autoActivo = true,
    this.monedaOrigen = 'USD',
    this.redondeoCup = 0,
    this.redondeoDivisa = 2,
  });

  /// Decimales que corresponden a [moneda]: [redondeoCup] para CUP y
  /// [redondeoDivisa] para el resto.
  int decimalesDe(String moneda) =>
      moneda.trim().toUpperCase() == 'CUP' ? redondeoCup : redondeoDivisa;

  /// Igual que [fromJson], pero nunca lanza y rellena con los valores por
  /// defecto de la base (`auto_activo=true`, `USD`, CUP 0, divisas 2).
  factory PrecioConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return const PrecioConfig();
    final auto = json['auto_activo'];
    final origen = (json['moneda_origen'] ?? '').toString().trim().toUpperCase();
    return PrecioConfig(
      autoActivo: auto is bool ? auto : true,
      monedaOrigen: origen.isEmpty ? 'USD' : origen,
      redondeoCup: _decimales(json['redondeo_cup'], 0),
      redondeoDivisa: _decimales(json['redondeo_divisa'], 2),
    );
  }

  Map<String, dynamic> toJson() => {
    'auto_activo': autoActivo,
    'moneda_origen': monedaOrigen,
    'redondeo_cup': redondeoCup,
    'redondeo_divisa': redondeoDivisa,
  };

  PrecioConfig copyWith({
    bool? autoActivo,
    String? monedaOrigen,
    int? redondeoCup,
    int? redondeoDivisa,
  }) => PrecioConfig(
    autoActivo: autoActivo ?? this.autoActivo,
    monedaOrigen: monedaOrigen ?? this.monedaOrigen,
    redondeoCup: redondeoCup ?? this.redondeoCup,
    redondeoDivisa: redondeoDivisa ?? this.redondeoDivisa,
  );

  @override
  bool operator ==(Object other) =>
      other is PrecioConfig &&
      other.autoActivo == autoActivo &&
      other.monedaOrigen == monedaOrigen &&
      other.redondeoCup == redondeoCup &&
      other.redondeoDivisa == redondeoDivisa;

  @override
  int get hashCode =>
      Object.hash(autoActivo, monedaOrigen, redondeoCup, redondeoDivisa);

  @override
  String toString() =>
      'PrecioConfig(auto: $autoActivo, origen: $monedaOrigen, '
      'cup: $redondeoCup, divisa: $redondeoDivisa)';
}

/// Normaliza un redondeo que llega de la red (num, texto o basura) al rango
/// 0–2 que valida la propia RPC.
int _decimales(Object? raw, int porDefecto) {
  int? valor;
  if (raw is num) {
    valor = raw.toInt();
  } else if (raw is String) {
    valor = int.tryParse(raw.trim());
  }
  if (valor == null || valor < 0 || valor > 2) return porDefecto;
  return valor;
}