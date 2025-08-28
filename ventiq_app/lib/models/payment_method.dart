class PaymentMethod {
  final int id;
  final String denominacion;
  final String? descripcion;
  final bool esDigital;
  final bool esEfectivo;
  final bool esActivo;

  PaymentMethod({
    required this.id,
    required this.denominacion,
    this.descripcion,
    required this.esDigital,
    required this.esEfectivo,
    required this.esActivo,
  });

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: json['id'] as int,
      denominacion: json['denominacion'] as String,
      descripcion: json['descripcion'] as String?,
      esDigital: json['es_digital'] as bool? ?? false,
      esEfectivo: json['es_efectivo'] as bool? ?? false,
      esActivo: json['es_activo'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'denominacion': denominacion,
      'descripcion': descripcion,
      'es_digital': esDigital,
      'es_efectivo': esEfectivo,
      'es_activo': esActivo,
    };
  }

  String get displayName => denominacion;
  
  String get typeIcon {
    if (esEfectivo) return '💵';
    if (esDigital) return '💳';
    return '💰';
  }
}
