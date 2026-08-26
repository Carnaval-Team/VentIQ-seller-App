import 'hr_salary_type.dart';

/// Una jornada (día trabajado) de un trabajador, tal como la devuelve
/// `fn_hr_worker_salary_detail`.
///
/// Es la unidad que RR.HH. audita y corrige: cada fila es un día concreto
/// con su propia tarifa, su cantidad pagada y su PPR. La tarifa NO es la del
/// trabajador, es el snapshot guardado en esa jornada: si un día pasado se
/// corrigió, aquí se ve el valor corregido.
class HRSalaryDay {
  final int asistenciaId;
  final DateTime? horaEntrada;
  final DateTime? horaSalida;

  /// Modalidad con la que se pagó ESTA jornada.
  final TipoSalario tipoSalario;

  /// Tarifa aplicada a esta jornada (\$/hora o \$/día según [tipoSalario]).
  final double tarifa;

  /// Días pagados. Solo tiene valor en modalidad día.
  final double? cantidadDias;

  /// Horas reales entre entrada y salida (columna generada en la base).
  final double horasTrabajadas;

  /// Cantidad pagada en la unidad de la modalidad: días o horas.
  final double cantidadPagada;

  /// Salario base del día (cantidad pagada x tarifa).
  final double salarioTotal;

  /// Monto del PPR guardado en esta jornada.
  final double pagoPorResultado;

  /// Si el PPR de esta jornada se cobra o no.
  final bool aplicaPagoResultado;

  /// Salario base + PPR (si aplica).
  final double totalDia;

  /// Jornada sin hora de salida: todavía no tiene pago y no se puede editar.
  final bool abierta;

  final String? observaciones;

  HRSalaryDay({
    required this.asistenciaId,
    this.horaEntrada,
    this.horaSalida,
    this.tipoSalario = TipoSalario.hora,
    required this.tarifa,
    this.cantidadDias,
    required this.horasTrabajadas,
    required this.cantidadPagada,
    required this.salarioTotal,
    required this.pagoPorResultado,
    required this.aplicaPagoResultado,
    required this.totalDia,
    this.abierta = false,
    this.observaciones,
  });

  bool get esPorDia => tipoSalario.esPorDia;

  /// PPR que realmente suma al total del día.
  double get pprEfectivo => aplicaPagoResultado ? pagoPorResultado : 0;

  /// Cantidad pagada ya formateada. Ej: '1 d' o '8h 30m'.
  String get cantidadFormatted => tipoSalario.formatCantidad(cantidadPagada);

  /// Tarifa formateada con su sufijo. Ej: '\$500.00/d'.
  String get tarifaFormatted => tipoSalario.formatTarifa(tarifa);

  factory HRSalaryDay.fromJson(Map<String, dynamic> json) {
    return HRSalaryDay(
      asistenciaId: (json['asistencia_id'] as num).toInt(),
      horaEntrada: json['hora_entrada'] != null
          ? DateTime.parse(json['hora_entrada'] as String).toLocal()
          : null,
      horaSalida: json['hora_salida'] != null
          ? DateTime.parse(json['hora_salida'] as String).toLocal()
          : null,
      tipoSalario: TipoSalario.fromDb(json['tipo_salario']),
      tarifa: (json['tarifa'] as num?)?.toDouble() ?? 0,
      cantidadDias: (json['cantidad_dias'] as num?)?.toDouble(),
      horasTrabajadas: (json['horas_trabajadas'] as num?)?.toDouble() ?? 0,
      cantidadPagada: (json['cantidad_pagada'] as num?)?.toDouble() ?? 0,
      salarioTotal: (json['salario_total'] as num?)?.toDouble() ?? 0,
      pagoPorResultado: (json['pago_por_resultado'] as num?)?.toDouble() ?? 0,
      aplicaPagoResultado: json['aplica_pago_resultado'] as bool? ?? false,
      totalDia: (json['total_dia'] as num?)?.toDouble() ?? 0,
      abierta: json['abierta'] as bool? ?? false,
      observaciones: json['observaciones'] as String?,
    );
  }
}

/// Detalle completo devuelto por `fn_hr_worker_salary_detail`: la
/// configuración vigente del trabajador más sus jornadas del rango.
///
/// La configuración vigente puede diferir de lo pagado en días pasados; se
/// expone para poder sugerir valores al editar (por ejemplo el PPR
/// configurado cuando la jornada no tenía ninguno).
class HRWorkerSalaryDetail {
  final int trabajadorId;
  final String nombres;
  final String apellidos;
  final String? rolNombre;

  /// Modalidad configurada hoy al trabajador.
  final TipoSalario tipoSalario;
  final double salarioHoras;
  final double salarioDia;

  /// PPR configurado hoy al trabajador (valor sugerido al activar el PPR).
  final double pprConfigurado;

  final List<HRSalaryDay> dias;

  HRWorkerSalaryDetail({
    required this.trabajadorId,
    required this.nombres,
    required this.apellidos,
    this.rolNombre,
    this.tipoSalario = TipoSalario.hora,
    required this.salarioHoras,
    required this.salarioDia,
    required this.pprConfigurado,
    required this.dias,
  });

  String get nombreCompleto => '$nombres $apellidos';

  /// Jornadas cerradas: las únicas con pago y, por tanto, editables.
  List<HRSalaryDay> get diasCerrados =>
      dias.where((d) => !d.abierta).toList();

  double get totalBase =>
      diasCerrados.fold(0.0, (s, d) => s + d.salarioTotal);

  double get totalPPR =>
      diasCerrados.fold(0.0, (s, d) => s + d.pprEfectivo);

  double get totalGeneral => totalBase + totalPPR;

  factory HRWorkerSalaryDetail.fromJson(
    Map<String, dynamic> trabajador,
    List<dynamic> data,
  ) {
    return HRWorkerSalaryDetail(
      trabajadorId: (trabajador['trabajador_id'] as num).toInt(),
      nombres: trabajador['nombres'] as String? ?? '',
      apellidos: trabajador['apellidos'] as String? ?? '',
      rolNombre: trabajador['rol_nombre'] as String?,
      tipoSalario: TipoSalario.fromDb(trabajador['tipo_salario']),
      salarioHoras: (trabajador['salario_horas'] as num?)?.toDouble() ?? 0,
      salarioDia: (trabajador['salario_dia'] as num?)?.toDouble() ?? 0,
      pprConfigurado:
          (trabajador['ppr_configurado'] as num?)?.toDouble() ?? 0,
      dias: data
          .map((e) => HRSalaryDay.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
