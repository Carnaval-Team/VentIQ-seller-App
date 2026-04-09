class HRDashboardSummary {
  final double totalHoras;
  final double totalSalarioBase;
  final double totalPPR;
  final double totalGeneral;
  final int totalRegistros;
  final List<HRDailyData> dailyData;

  HRDashboardSummary({
    required this.totalHoras,
    required this.totalSalarioBase,
    required this.totalPPR,
    required this.totalGeneral,
    required this.totalRegistros,
    required this.dailyData,
  });

  factory HRDashboardSummary.fromJson(Map<String, dynamic> json) {
    final daily = json['daily_data'] as List<dynamic>? ?? [];
    return HRDashboardSummary(
      totalHoras: (json['total_horas'] as num?)?.toDouble() ?? 0,
      totalSalarioBase: (json['total_salario_base'] as num?)?.toDouble() ?? 0,
      totalPPR: (json['total_ppr'] as num?)?.toDouble() ?? 0,
      totalGeneral: (json['total_general'] as num?)?.toDouble() ?? 0,
      totalRegistros: json['total_registros'] as int? ?? 0,
      dailyData: daily.map((d) => HRDailyData.fromJson(d as Map<String, dynamic>)).toList(),
    );
  }
}

class HRDailyData {
  final String fecha;
  final double horas;
  final double salario;
  final double ppr;

  HRDailyData({
    required this.fecha,
    required this.horas,
    required this.salario,
    required this.ppr,
  });

  double get total => salario + ppr;

  factory HRDailyData.fromJson(Map<String, dynamic> json) {
    return HRDailyData(
      fecha: json['fecha'] as String? ?? '',
      horas: (json['horas'] as num?)?.toDouble() ?? 0,
      salario: (json['salario'] as num?)?.toDouble() ?? 0,
      ppr: (json['ppr'] as num?)?.toDouble() ?? 0,
    );
  }
}

class HRTopWorker {
  final int trabajadorId;
  final String nombres;
  final String apellidos;
  final String? rolNombre;
  final double totalHoras;
  final double totalSalarioBase;
  final double totalPPR;
  final double totalGeneral;
  final bool tienePPR;

  HRTopWorker({
    required this.trabajadorId,
    required this.nombres,
    required this.apellidos,
    this.rolNombre,
    required this.totalHoras,
    required this.totalSalarioBase,
    required this.totalPPR,
    required this.totalGeneral,
    this.tienePPR = false,
  });

  String get nombreCompleto => '$nombres $apellidos';

  factory HRTopWorker.fromJson(Map<String, dynamic> json) {
    return HRTopWorker(
      trabajadorId: json['trabajador_id'] as int,
      nombres: json['nombres'] as String? ?? '',
      apellidos: json['apellidos'] as String? ?? '',
      rolNombre: json['rol_nombre'] as String?,
      totalHoras: (json['total_horas'] as num?)?.toDouble() ?? 0,
      totalSalarioBase: (json['total_salario_base'] as num?)?.toDouble() ?? 0,
      totalPPR: (json['total_ppr'] as num?)?.toDouble() ?? 0,
      totalGeneral: (json['total_general'] as num?)?.toDouble() ?? 0,
      tienePPR: json['tiene_ppr'] as bool? ?? false,
    );
  }
}
