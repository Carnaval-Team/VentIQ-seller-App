class HRSalaryReportEntry {
  final int trabajadorId;
  final String nombres;
  final String apellidos;
  final String? rolNombre;
  final double salarioHoras;
  final double totalHoras;
  final double totalSalarioBase;
  final double totalPPR;
  final double totalGeneral;
  final int diasTrabajados;

  HRSalaryReportEntry({
    required this.trabajadorId,
    required this.nombres,
    required this.apellidos,
    this.rolNombre,
    required this.salarioHoras,
    required this.totalHoras,
    required this.totalSalarioBase,
    required this.totalPPR,
    required this.totalGeneral,
    required this.diasTrabajados,
  });

  String get nombreCompleto => '$nombres $apellidos';

  factory HRSalaryReportEntry.fromJson(Map<String, dynamic> json) {
    return HRSalaryReportEntry(
      trabajadorId: json['trabajador_id'] as int,
      nombres: json['nombres'] as String? ?? '',
      apellidos: json['apellidos'] as String? ?? '',
      rolNombre: json['rol_nombre'] as String?,
      salarioHoras: (json['salario_horas'] as num?)?.toDouble() ?? 0,
      totalHoras: (json['total_horas'] as num?)?.toDouble() ?? 0,
      totalSalarioBase: (json['total_salario_base'] as num?)?.toDouble() ?? 0,
      totalPPR: (json['total_ppr'] as num?)?.toDouble() ?? 0,
      totalGeneral: (json['total_general'] as num?)?.toDouble() ?? 0,
      diasTrabajados: json['dias_trabajados'] as int? ?? 0,
    );
  }
}
