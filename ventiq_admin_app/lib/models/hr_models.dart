// Modelos para el módulo de Recursos Humanos (Rec. Hum.)

/// Modelo para representar un turno con sus trabajadores
class ShiftWithWorkers {
  final int turnoId;
  final DateTime fechaApertura;
  final DateTime? fechaCierre;
  final String estadoNombre;
  final String tpvDenominacion;
  final String vendedorNombre;
  final double efectivoInicial;
  final double? efectivoReal;
  final double? diferencia;
  final List<ShiftWorkerHours> trabajadores;

  ShiftWithWorkers({
    required this.turnoId,
    required this.fechaApertura,
    this.fechaCierre,
    required this.estadoNombre,
    required this.tpvDenominacion,
    required this.vendedorNombre,
    required this.efectivoInicial,
    this.efectivoReal,
    this.diferencia,
    required this.trabajadores,
  });

  factory ShiftWithWorkers.fromJson(Map<String, dynamic> json) {
    return ShiftWithWorkers(
      turnoId: json['turno_id'] as int,
      fechaApertura: DateTime.parse(json['fecha_apertura'] as String),
      fechaCierre: json['fecha_cierre'] != null
          ? DateTime.parse(json['fecha_cierre'] as String)
          : null,
      estadoNombre: json['estado_nombre'] as String? ?? 'Desconocido',
      tpvDenominacion: json['tpv_denominacion'] as String? ?? 'N/A',
      vendedorNombre: json['vendedor_nombre'] as String? ?? 'N/A',
      efectivoInicial: (json['efectivo_inicial'] as num?)?.toDouble() ?? 0.0,
      efectivoReal: (json['efectivo_real'] as num?)?.toDouble(),
      diferencia: (json['diferencia'] as num?)?.toDouble(),
      trabajadores: (json['trabajadores'] as List<dynamic>?)
              ?.map((t) => ShiftWorkerHours.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  bool get isOpen => fechaCierre == null;
  
  String get duracionTurno {
    final end = fechaCierre ?? DateTime.now();
    final duration = end.difference(fechaApertura);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return '${hours}h ${minutes}m';
  }
}

/// Modelo para representar las horas trabajadas de un trabajador en un turno
class ShiftWorkerHours {
  final int id;
  final int idTurno;
  final int idTrabajador;
  final String trabajadorNombre;
  final String rolNombre;
  final DateTime horaEntrada;
  final DateTime? horaSalida;
  final double? horasTrabajadas;
  final double salarioHora;
  final double salarioTotal;
  final String? observaciones;

  ShiftWorkerHours({
    required this.id,
    required this.idTurno,
    required this.idTrabajador,
    required this.trabajadorNombre,
    required this.rolNombre,
    required this.horaEntrada,
    this.horaSalida,
    this.horasTrabajadas,
    required this.salarioHora,
    required this.salarioTotal,
    this.observaciones,
  });

  factory ShiftWorkerHours.fromJson(Map<String, dynamic> json) {
    final horasTrabajadas = (json['horas_trabajadas'] as num?)?.toDouble();
    final salarioHora = (json['salario_hora'] as num?)?.toDouble() ?? 0.0;
    final salarioTotal = horasTrabajadas != null ? horasTrabajadas * salarioHora : 0.0;

    return ShiftWorkerHours(
      id: json['id'] as int,
      idTurno: json['id_turno'] as int,
      idTrabajador: json['id_trabajador'] as int,
      trabajadorNombre: json['trabajador_nombre'] as String? ?? 'Desconocido',
      rolNombre: json['rol_nombre'] as String? ?? 'N/A',
      horaEntrada: DateTime.parse(json['hora_entrada'] as String),
      horaSalida: json['hora_salida'] != null
          ? DateTime.parse(json['hora_salida'] as String)
          : null,
      horasTrabajadas: horasTrabajadas,
      salarioHora: salarioHora,
      salarioTotal: salarioTotal,
      observaciones: json['observaciones'] as String?,
    );
  }

  bool get isWorking => horaSalida == null;

  String get horasTrabajadasFormatted {
    if (horasTrabajadas == null) return 'En turno';
    return '${horasTrabajadas!.toStringAsFixed(2)}h';
  }

  String get salarioTotalFormatted {
    return '\$${salarioTotal.toStringAsFixed(2)}';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'id_turno': idTurno,
      'id_trabajador': idTrabajador,
      'trabajador_nombre': trabajadorNombre,
      'rol_nombre': rolNombre,
      'hora_entrada': horaEntrada.toIso8601String(),
      'hora_salida': horaSalida?.toIso8601String(),
      'horas_trabajadas': horasTrabajadas,
      'salario_hora': salarioHora,
      'salario_total': salarioTotal,
      'observaciones': observaciones,
    };
  }
}

/// Modelo para resumen de horas y salarios por período
class HRSummary {
  final DateTime fechaDesde;
  final DateTime fechaHasta;
  final int totalTurnos;
  final int totalTrabajadores;
  final double totalHorasTrabajadas;
  final double totalSalarios;
  final Map<String, double> salariosPorRol;

  HRSummary({
    required this.fechaDesde,
    required this.fechaHasta,
    required this.totalTurnos,
    required this.totalTrabajadores,
    required this.totalHorasTrabajadas,
    required this.totalSalarios,
    required this.salariosPorRol,
  });

  factory HRSummary.fromJson(Map<String, dynamic> json) {
    return HRSummary(
      fechaDesde: DateTime.parse(json['fecha_desde'] as String),
      fechaHasta: DateTime.parse(json['fecha_hasta'] as String),
      totalTurnos: json['total_turnos'] as int? ?? 0,
      totalTrabajadores: json['total_trabajadores'] as int? ?? 0,
      totalHorasTrabajadas:
          (json['total_horas_trabajadas'] as num?)?.toDouble() ?? 0.0,
      totalSalarios: (json['total_salarios'] as num?)?.toDouble() ?? 0.0,
      salariosPorRol: Map<String, double>.from(
        json['salarios_por_rol'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  String get totalSalariosFormatted {
    return '\$${totalSalarios.toStringAsFixed(2)}';
  }

  String get promedioHorasPorTrabajador {
    if (totalTrabajadores == 0) return '0h';
    final promedio = totalHorasTrabajadas / totalTrabajadores;
    return '${promedio.toStringAsFixed(1)}h';
  }
}
