import 'hr_salary_type.dart';

class HRAttendance {
  final int asistenciaId;
  final int trabajadorId;
  final String nombres;
  final String apellidos;
  final DateTime? horaEntrada;
  final DateTime? horaSalida;
  /// Tarifa aplicable a la jornada: \$/hora o \$/día según [tipoSalario].
  final double salarioHora;
  final double? horasTrabajadas;
  final double? salarioTotal;
  final double pagoPorResultado;
  final bool aplicaPagoResultado;
  final String? rolNombre;
  final double? horasTranscurridas;
  final String? observaciones;
  /// Modalidad de pago de esta jornada (snapshot tomado al fichar entrada).
  final TipoSalario tipoSalario;
  /// Días pagados en esta jornada. Solo aplica si [tipoSalario] es por día.
  final double? cantidadDias;

  HRAttendance({
    required this.asistenciaId,
    required this.trabajadorId,
    required this.nombres,
    required this.apellidos,
    this.horaEntrada,
    this.horaSalida,
    required this.salarioHora,
    this.horasTrabajadas,
    this.salarioTotal,
    this.pagoPorResultado = 0,
    this.aplicaPagoResultado = false,
    this.rolNombre,
    this.horasTranscurridas,
    this.observaciones,
    this.tipoSalario = TipoSalario.hora,
    this.cantidadDias,
  });

  String get nombreCompleto => '$nombres $apellidos';

  bool get isWorking => horaSalida == null;

  bool get esPorDia => tipoSalario.esPorDia;

  /// El PPR es un bono fijo por jornada en ambas modalidades: no se
  /// multiplica por horas ni por días.
  double get totalCompensation =>
      (salarioTotal ?? 0) + (aplicaPagoResultado ? pagoPorResultado : 0);

  /// Cantidad efectivamente pagada, en la unidad de la modalidad:
  /// días si es por día, horas trabajadas si es por hora.
  double get cantidadPagada => tipoSalario.esPorDia
      ? (cantidadDias ?? 1)
      : (horasTrabajadas ?? 0);

  /// Cantidad pagada ya formateada. Ej: '1.5 d' o '8h 30m'.
  String get cantidadPagadaFormatted =>
      tipoSalario.formatCantidad(cantidadPagada);

  /// Tarifa formateada con su sufijo. Ej: '\$1500.00/d' o '\$120.00/h'.
  String get tarifaFormatted => tipoSalario.formatTarifa(salarioHora);

  factory HRAttendance.fromJson(Map<String, dynamic> json) {
    return HRAttendance(
      asistenciaId: json['asistencia_id'] as int? ?? json['id'] as int? ?? 0,
      trabajadorId: (json['trabajador_id'] as num).toInt(),
      nombres: json['nombres'] as String? ?? '',
      apellidos: json['apellidos'] as String? ?? '',
      horaEntrada: json['hora_entrada'] != null
          ? DateTime.parse(json['hora_entrada'] as String).toLocal()
          : null,
      horaSalida: json['hora_salida'] != null
          ? DateTime.parse(json['hora_salida'] as String).toLocal()
          : null,
      salarioHora: (json['salario_hora'] as num?)?.toDouble()
          ?? (json['salario_horas'] as num?)?.toDouble()
          ?? 0,
      horasTrabajadas: (json['horas_trabajadas'] as num?)?.toDouble(),
      salarioTotal: (json['salario_total'] as num?)?.toDouble(),
      pagoPorResultado: (json['pago_por_resultado'] as num?)?.toDouble() ?? 0,
      aplicaPagoResultado: json['aplica_pago_resultado'] as bool? ?? false,
      rolNombre: json['rol_nombre'] as String?,
      horasTranscurridas: (json['horas_transcurridas'] as num?)?.toDouble(),
      observaciones: json['observaciones'] as String?,
      tipoSalario: TipoSalario.fromDb(json['tipo_salario']),
      cantidadDias: (json['cantidad_dias'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'asistencia_id': asistenciaId,
      'trabajador_id': trabajadorId,
      'nombres': nombres,
      'apellidos': apellidos,
      'hora_entrada': horaEntrada?.toIso8601String(),
      'hora_salida': horaSalida?.toIso8601String(),
      'salario_hora': salarioHora,
      'horas_trabajadas': horasTrabajadas,
      'salario_total': salarioTotal,
      'pago_por_resultado': pagoPorResultado,
      'aplica_pago_resultado': aplicaPagoResultado,
      'rol_nombre': rolNombre,
      'observaciones': observaciones,
      'tipo_salario': tipoSalario.dbValue,
      'cantidad_dias': cantidadDias,
    };
  }
}
