import 'hr_salary_type.dart';

class HRSalaryReportEntry {
  final int trabajadorId;
  final String nombres;
  final String apellidos;
  final String? rolNombre;
  /// Modalidad de pago configurada actualmente para el trabajador.
  final TipoSalario tipoSalario;
  /// Tarifa por hora configurada (se conserva aunque cobre por día).
  final double salarioHoras;
  /// Tarifa por día configurada (se conserva aunque cobre por hora).
  final double salarioDia;
  /// Tarifa aplicable a su modalidad, ya resuelta por la base de datos.
  final double tarifa;
  /// Horas acumuladas — solo de jornadas pagadas por hora.
  final double totalHoras;
  final double totalSalarioBase;
  final double totalPPR;
  final double totalGeneral;
  /// Días acumulados. Modalidad día: días pagados. Modalidad hora: una
  /// jornada cerrada cuenta como un día. Nunca se derivan de horas/24.
  final double diasTrabajados;

  HRSalaryReportEntry({
    required this.trabajadorId,
    required this.nombres,
    required this.apellidos,
    this.rolNombre,
    this.tipoSalario = TipoSalario.hora,
    required this.salarioHoras,
    this.salarioDia = 0,
    required this.tarifa,
    required this.totalHoras,
    required this.totalSalarioBase,
    required this.totalPPR,
    required this.totalGeneral,
    required this.diasTrabajados,
  });

  String get nombreCompleto => '$nombres $apellidos';

  bool get esPorDia => tipoSalario.esPorDia;

  /// Tarifa formateada con su sufijo. Ej: '\$1500.00/d' o '\$120.00/h'.
  String get tarifaFormatted => tipoSalario.formatTarifa(tarifa);

  /// Horas para mostrar en tabla: '—' si cobra por día, porque sus horas
  /// reales no intervienen en el importe y mostrarlas induce a error.
  String get horasFormatted =>
      esPorDia ? '—' : '${totalHoras.toStringAsFixed(1)}h';

  /// Días para mostrar en tabla, sin decimales innecesarios.
  String get diasFormatted => diasTrabajados == diasTrabajados.roundToDouble()
      ? diasTrabajados.toStringAsFixed(0)
      : diasTrabajados.toStringAsFixed(2);

  factory HRSalaryReportEntry.fromJson(Map<String, dynamic> json) {
    final tipo = TipoSalario.fromDb(json['tipo_salario']);
    final salarioHoras = (json['salario_horas'] as num?)?.toDouble() ?? 0;
    final salarioDia = (json['salario_dia'] as num?)?.toDouble() ?? 0;

    return HRSalaryReportEntry(
      trabajadorId: json['trabajador_id'] as int,
      nombres: json['nombres'] as String? ?? '',
      apellidos: json['apellidos'] as String? ?? '',
      rolNombre: json['rol_nombre'] as String?,
      tipoSalario: tipo,
      salarioHoras: salarioHoras,
      salarioDia: salarioDia,
      // Si el backend aún no envía 'tarifa', se resuelve por modalidad.
      tarifa: (json['tarifa'] as num?)?.toDouble() ??
          (tipo.esPorDia ? salarioDia : salarioHoras),
      totalHoras: (json['total_horas'] as num?)?.toDouble() ?? 0,
      totalSalarioBase: (json['total_salario_base'] as num?)?.toDouble() ?? 0,
      totalPPR: (json['total_ppr'] as num?)?.toDouble() ?? 0,
      totalGeneral: (json['total_general'] as num?)?.toDouble() ?? 0,
      diasTrabajados: (json['dias_trabajados'] as num?)?.toDouble() ?? 0,
    );
  }
}
