/// Configuración recurrente de capacidades para un local_servicio.
/// Refleja flow.plan_config.
///
/// Dos formas según el servicio use o no recursos:
///
///  • SIN recursos (cupo único por día):
///      { "default": 30, "por_dia": { "1": 50, "4": 60 } }
///    día ISO 1=lunes..7=domingo. Valor 0 = ese día no se planifica.
///
///  • CON recursos (una capacidad por recurso):
///      `{ "por_recurso": {
///          "id_recurso": { "default": 15, "por_dia": { "1": 20, "7": 0 } },
///          ...
///      } }`
class PlanConfig {
  final int? id;
  final int idLocalServicio;

  /// Capacidad por defecto (días sin override). Solo servicios SIN recursos.
  final int porDefecto;

  /// Override por día ISO (1=lunes … 7=domingo). Vacío = usar [porDefecto].
  /// Valor 0 = ese día no se planifica. Solo servicios SIN recursos.
  final Map<int, int> porDia;

  /// Config por recurso (servicios CON recursos). Clave = id_recurso.
  final Map<int, RecursoPlanConfig> porRecurso;

  final bool activo;

  PlanConfig({
    this.id,
    required this.idLocalServicio,
    this.porDefecto = 0,
    Map<int, int>? porDia,
    Map<int, RecursoPlanConfig>? porRecurso,
    this.activo = true,
  })  : porDia = porDia ?? {},
        porRecurso = porRecurso ?? {};

  /// true si la config está en modo "por recurso".
  bool get esPorRecurso => porRecurso.isNotEmpty;

  factory PlanConfig.fromJson(Map<String, dynamic> json) {
    final config = (json['config'] as Map?)?.cast<String, dynamic>() ?? {};

    // ── por_recurso (servicios con recursos) ──
    final porRecursoRaw =
        (config['por_recurso'] as Map?)?.cast<String, dynamic>() ?? {};
    final porRecurso = <int, RecursoPlanConfig>{};
    porRecursoRaw.forEach((k, v) {
      final idRec = int.tryParse(k.toString());
      if (idRec != null && v is Map) {
        porRecurso[idRec] =
            RecursoPlanConfig.fromJson(v.cast<String, dynamic>());
      }
    });

    // ── por_dia (servicios sin recursos) ──
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
      porRecurso: porRecurso,
      activo: (json['activo'] as bool?) ?? true,
    );
  }

  /// El jsonb `config` listo para enviar a la RPC.
  Map<String, dynamic> toConfigJson() {
    if (esPorRecurso) {
      return {
        'por_recurso': {
          for (final e in porRecurso.entries)
            e.key.toString(): e.value.toJson(),
        },
      };
    }
    return {
      'default': porDefecto,
      'por_dia': {
        for (final e in porDia.entries) e.key.toString(): e.value,
      },
    };
  }
}

/// Config recurrente de UN recurso: capacidad por defecto + overrides por día.
class RecursoPlanConfig {
  /// Capacidad por defecto de este recurso (días sin override).
  final int porDefecto;

  /// Override por día ISO (1=lunes … 7=domingo). Valor 0 = ese día cerrado.
  final Map<int, int> porDia;

  RecursoPlanConfig({this.porDefecto = 0, Map<int, int>? porDia})
      : porDia = porDia ?? {};

  factory RecursoPlanConfig.fromJson(Map<String, dynamic> json) {
    final porDiaRaw =
        (json['por_dia'] as Map?)?.cast<String, dynamic>() ?? {};
    final porDia = <int, int>{};
    porDiaRaw.forEach((k, v) {
      final dia = int.tryParse(k.toString());
      final cap = (v as num?)?.toInt();
      if (dia != null && cap != null) porDia[dia] = cap;
    });
    return RecursoPlanConfig(
      porDefecto: (json['default'] as num?)?.toInt() ?? 0,
      porDia: porDia,
    );
  }

  Map<String, dynamic> toJson() => {
        'default': porDefecto,
        'por_dia': {
          for (final e in porDia.entries) e.key.toString(): e.value,
        },
      };
}
