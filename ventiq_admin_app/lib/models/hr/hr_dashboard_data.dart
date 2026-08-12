import 'hr_salary_type.dart';

class HRDashboardSummary {
  /// Horas acumuladas — solo de jornadas pagadas por hora.
  final double totalHoras;
  /// Días acumulados de TODAS las jornadas: los días pagados en modalidad
  /// día, y una jornada cerrada = un día en modalidad hora. Así el KPI es
  /// sumable con plantilla mixta.
  final double totalDias;
  final double totalSalarioBase;
  final double totalPPR;
  final double totalGeneral;
  final int totalRegistros;
  /// Cuántas jornadas del período se pagaron por hora / por día.
  /// Sirve para ocultar KPIs que no aplican a la plantilla actual.
  final int registrosHora;
  final int registrosDia;
  final List<HRDailyData> dailyData;

  HRDashboardSummary({
    required this.totalHoras,
    this.totalDias = 0,
    required this.totalSalarioBase,
    required this.totalPPR,
    required this.totalGeneral,
    required this.totalRegistros,
    this.registrosHora = 0,
    this.registrosDia = 0,
    required this.dailyData,
  });

  /// La tienda tiene trabajadores en ambas modalidades en este período.
  bool get esMixto => registrosHora > 0 && registrosDia > 0;

  /// Hay al menos una jornada pagada por día en el período.
  bool get tieneDias => registrosDia > 0;

  /// Hay al menos una jornada pagada por hora en el período.
  bool get tieneHoras => registrosHora > 0;

  factory HRDashboardSummary.fromJson(Map<String, dynamic> json) {
    final daily = json['daily_data'] as List<dynamic>? ?? [];
    return HRDashboardSummary(
      totalHoras: (json['total_horas'] as num?)?.toDouble() ?? 0,
      totalDias: (json['total_dias'] as num?)?.toDouble() ?? 0,
      totalSalarioBase: (json['total_salario_base'] as num?)?.toDouble() ?? 0,
      totalPPR: (json['total_ppr'] as num?)?.toDouble() ?? 0,
      totalGeneral: (json['total_general'] as num?)?.toDouble() ?? 0,
      totalRegistros: json['total_registros'] as int? ?? 0,
      registrosHora: json['registros_hora'] as int? ?? 0,
      registrosDia: json['registros_dia'] as int? ?? 0,
      dailyData: daily.map((d) => HRDailyData.fromJson(d as Map<String, dynamic>)).toList(),
    );
  }
}

class HRDailyData {
  final String fecha;
  final double horas;
  final double dias;
  final double salario;
  final double ppr;

  HRDailyData({
    required this.fecha,
    required this.horas,
    this.dias = 0,
    required this.salario,
    required this.ppr,
  });

  double get total => salario + ppr;

  factory HRDailyData.fromJson(Map<String, dynamic> json) {
    return HRDailyData(
      fecha: json['fecha'] as String? ?? '',
      horas: (json['horas'] as num?)?.toDouble() ?? 0,
      dias: (json['dias'] as num?)?.toDouble() ?? 0,
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
  final TipoSalario tipoSalario;
  /// Tarifa vigente para su modalidad (\$/hora o \$/día).
  final double tarifa;
  /// Horas acumuladas — solo de jornadas pagadas por hora.
  final double totalHoras;
  /// Días acumulados (pagados si es por día, jornadas si es por hora).
  final double totalDias;
  final double totalSalarioBase;
  final double totalPPR;
  final double totalGeneral;
  final bool tienePPR;

  HRTopWorker({
    required this.trabajadorId,
    required this.nombres,
    required this.apellidos,
    this.rolNombre,
    this.tipoSalario = TipoSalario.hora,
    this.tarifa = 0,
    required this.totalHoras,
    this.totalDias = 0,
    required this.totalSalarioBase,
    required this.totalPPR,
    required this.totalGeneral,
    this.tienePPR = false,
  });

  String get nombreCompleto => '$nombres $apellidos';

  bool get esPorDia => tipoSalario.esPorDia;

  /// Tarifa formateada con su sufijo. Ej: '\$1500.00/d' o '\$120.00/h'.
  String get tarifaFormatted => tipoSalario.formatTarifa(tarifa);

  /// Horas para tabla: '—' si cobra por día (sus horas no definen el pago).
  String get horasFormatted =>
      esPorDia ? '—' : '${totalHoras.toStringAsFixed(1)}h';

  String get diasFormatted => totalDias == totalDias.roundToDouble()
      ? totalDias.toStringAsFixed(0)
      : totalDias.toStringAsFixed(2);

  factory HRTopWorker.fromJson(Map<String, dynamic> json) {
    return HRTopWorker(
      trabajadorId: json['trabajador_id'] as int,
      nombres: json['nombres'] as String? ?? '',
      apellidos: json['apellidos'] as String? ?? '',
      rolNombre: json['rol_nombre'] as String?,
      tipoSalario: TipoSalario.fromDb(json['tipo_salario']),
      tarifa: (json['tarifa'] as num?)?.toDouble() ?? 0,
      totalHoras: (json['total_horas'] as num?)?.toDouble() ?? 0,
      totalDias: (json['total_dias'] as num?)?.toDouble() ?? 0,
      totalSalarioBase: (json['total_salario_base'] as num?)?.toDouble() ?? 0,
      totalPPR: (json['total_ppr'] as num?)?.toDouble() ?? 0,
      totalGeneral: (json['total_general'] as num?)?.toDouble() ?? 0,
      tienePPR: json['tiene_ppr'] as bool? ?? false,
    );
  }
}
