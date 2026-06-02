class SuscripcionModel {
  final int id;
  final String usuarioUuid;
  final String planCodigo;
  // 'activa' | 'vencida' | 'cancelada' | 'pendiente_pago'
  final String estado;
  final DateTime inicio;
  final DateTime vencimiento;
  final bool renovacionAuto;
  final String? notas;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const SuscripcionModel({
    required this.id,
    required this.usuarioUuid,
    required this.planCodigo,
    required this.estado,
    required this.inicio,
    required this.vencimiento,
    required this.renovacionAuto,
    this.notas,
    required this.createdAt,
    this.updatedAt,
  });

  bool get estaActiva => estado == 'activa';

  bool get esGratis => planCodigo.endsWith('_gratis');

  /// Primer mes promocional: plan de pago activo sin cobro inicial.
  bool get enPeriodoPrueba =>
      !esGratis &&
      (notas?.toLowerCase().contains('primer mes') == true ||
          notas?.toLowerCase().contains('promoción') == true);

  int get diasRestantes {
    final hoy = DateTime.now();
    final diff = vencimiento.difference(DateTime(hoy.year, hoy.month, hoy.day));
    return diff.inDays;
  }

  bool get estaPorVencer => estaActiva && diasRestantes <= 7 && diasRestantes >= 0;

  bool get estaVencida => estado == 'vencida' || (estaActiva && diasRestantes < 0);

  factory SuscripcionModel.fromJson(Map<String, dynamic> json) {
    return SuscripcionModel(
      id: json['id'] as int,
      usuarioUuid: json['usuario_uuid'] as String,
      planCodigo: json['plan_codigo'] as String,
      estado: json['estado'] as String? ?? 'activa',
      inicio: DateTime.parse(json['inicio'] as String),
      vencimiento: DateTime.parse(json['vencimiento'] as String),
      renovacionAuto: json['renovacion_auto'] as bool? ?? true,
      notas: json['notas'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'usuario_uuid': usuarioUuid,
        'plan_codigo': planCodigo,
        'estado': estado,
        'inicio': inicio.toIso8601String().split('T').first,
        'vencimiento': vencimiento.toIso8601String().split('T').first,
        'renovacion_auto': renovacionAuto,
        if (notas != null) 'notas': notas,
        'created_at': createdAt.toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      };
}
