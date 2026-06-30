/// Configuración recurrente de capacidades por día de la semana para un
/// local_servicio. Refleja flow.plan_config.
///
/// El jsonb `config` tiene la forma:
///   { "default": 30, "por_dia": { "1": 50, "4": 60 } }   // día ISO 1=lunes..7=domingo
class PlanConfig {
  final int? id;
  final int idLocalServicio;

  /// Capacidad por defecto (días sin override).
  final int porDefecto;

  /// Override por día ISO (1=lunes … 7=domingo). Vacío = usar [porDefecto].
  /// Valor 0 = ese día no se planifica.
  final Map<int, int> porDia;

  final bool activo;

  PlanConfig({
    this.id,
    required this.idLocalServicio,
    required this.porDefecto,
    Map<int, int>? porDia,
    this.activo = true,
  }) : porDia = porDia ?? {};

  factory PlanConfig.fromJson(Map<String, dynamic> json) {
    final config = (json['config'] as Map?)?.cast<String, dynamic>() ?? {};
    final porDiaRaw =
        (config['por_dia'] as Map?)?.cast<String, dynamic>() ?? {};
    final porDia = <int, int>{};
    porDiaRaw.forEach((k, v) {
      final dia = int.tryParse(k.toString());
      final cap = (v as num?)?.toInt();
      if (dia != null && cap != null) porDia[dia] = cap;
    });
    return PlanConfig(
      id: (json['id'] as num?)?.toInt(),
      idLocalServicio: (json['id_local_servicio'] as num).toInt(),
      porDefecto: (config['default'] as num?)?.toInt() ?? 0,
      porDia: porDia,
      activo: (json['activo'] as bool?) ?? true,
    );
  }

  /// El jsonb `config` listo para enviar a la RPC.
  Map<String, dynamic> toConfigJson() => {
        'default': porDefecto,
        'por_dia': {
          for (final e in porDia.entries) e.key.toString(): e.value,
        },
      };
}
