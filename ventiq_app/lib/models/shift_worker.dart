/// Modelo para trabajadores asignados a turnos
class ShiftWorker {
  final int? id;
  final int idTurno;
  final int idTrabajador;
  final String nombresTrabajador;
  final String apellidosTrabajador;
  final String? rolTrabajador;
  final DateTime horaEntrada;
  final DateTime? horaSalida;
  final double? horasTrabajadas;
  final String? observaciones;
  final DateTime createdAt;
  final DateTime updatedAt;

  ShiftWorker({
    this.id,
    required this.idTurno,
    required this.idTrabajador,
    required this.nombresTrabajador,
    required this.apellidosTrabajador,
    this.rolTrabajador,
    required this.horaEntrada,
    this.horaSalida,
    this.horasTrabajadas,
    this.observaciones,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Crear desde JSON de Supabase
  factory ShiftWorker.fromJson(Map<String, dynamic> json) {
    // Manejar datos anidados del trabajador
    final trabajadorData = json['trabajador'] as Map<String, dynamic>?;
    final rolData = trabajadorData?['seg_roll'] as Map<String, dynamic>?;

    return ShiftWorker(
      id: json['id'] as int?,
      idTurno: json['id_turno'] as int,
      idTrabajador: json['id_trabajador'] as int,
      nombresTrabajador: trabajadorData?['nombres'] as String? ?? 'Sin nombre',
      apellidosTrabajador: trabajadorData?['apellidos'] as String? ?? '',
      rolTrabajador: rolData?['denominacion'] as String?,
      horaEntrada: DateTime.parse(json['hora_entrada'] as String),
      horaSalida: json['hora_salida'] != null
          ? DateTime.parse(json['hora_salida'] as String)
          : null,
      horasTrabajadas: json['horas_trabajadas'] != null
          ? (json['horas_trabajadas'] as num).toDouble()
          : null,
      observaciones: json['observaciones'] as String?,
      createdAt: DateTime.parse(
        json['created_at'] as String? ?? DateTime.now().toIso8601String(),
      ),
      updatedAt: DateTime.parse(
        json['updated_at'] as String? ?? DateTime.now().toIso8601String(),
      ),
    );
  }

  /// Convertir a JSON para Supabase
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'id_turno': idTurno,
      'id_trabajador': idTrabajador,
      'hora_entrada': horaEntrada.toIso8601String(),
      if (horaSalida != null) 'hora_salida': horaSalida!.toIso8601String(),
      if (observaciones != null) 'observaciones': observaciones,
    };
  }

  /// Convertir a JSON para almacenamiento offline
  Map<String, dynamic> toOfflineJson() {
    return {
      if (id != null) 'id': id,
      'id_turno': idTurno,
      'id_trabajador': idTrabajador,
      'nombres_trabajador': nombresTrabajador,
      'apellidos_trabajador': apellidosTrabajador,
      'rol_trabajador': rolTrabajador,
      'hora_entrada': horaEntrada.toIso8601String(),
      if (horaSalida != null) 'hora_salida': horaSalida!.toIso8601String(),
      if (horasTrabajadas != null) 'horas_trabajadas': horasTrabajadas,
      if (observaciones != null) 'observaciones': observaciones,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Crear desde JSON offline
  factory ShiftWorker.fromOfflineJson(Map<String, dynamic> json) {
    return ShiftWorker(
      id: json['id'] as int?,
      idTurno: json['id_turno'] as int,
      idTrabajador: json['id_trabajador'] as int,
      nombresTrabajador: json['nombres_trabajador'] as String? ?? 'Sin nombre',
      apellidosTrabajador: json['apellidos_trabajador'] as String? ?? '',
      rolTrabajador: json['rol_trabajador'] as String?,
      horaEntrada: DateTime.parse(json['hora_entrada'] as String),
      horaSalida: json['hora_salida'] != null
          ? DateTime.parse(json['hora_salida'] as String)
          : null,
      horasTrabajadas: json['horas_trabajadas'] != null
          ? (json['horas_trabajadas'] as num).toDouble()
          : null,
      observaciones: json['observaciones'] as String?,
      createdAt: DateTime.parse(
        json['created_at'] as String? ?? DateTime.now().toIso8601String(),
      ),
      updatedAt: DateTime.parse(
        json['updated_at'] as String? ?? DateTime.now().toIso8601String(),
      ),
    );
  }

  /// Verificar si el trabajador está activo (sin hora de salida)
  bool get isActive => horaSalida == null;

  /// Obtener nombre completo del trabajador
  String get nombreCompleto => '$nombresTrabajador $apellidosTrabajador'.trim();

  /// Copiar con modificaciones
  ShiftWorker copyWith({
    int? id,
    int? idTurno,
    int? idTrabajador,
    String? nombresTrabajador,
    String? apellidosTrabajador,
    String? rolTrabajador,
    DateTime? horaEntrada,
    DateTime? horaSalida,
    double? horasTrabajadas,
    String? observaciones,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ShiftWorker(
      id: id ?? this.id,
      idTurno: idTurno ?? this.idTurno,
      idTrabajador: idTrabajador ?? this.idTrabajador,
      nombresTrabajador: nombresTrabajador ?? this.nombresTrabajador,
      apellidosTrabajador: apellidosTrabajador ?? this.apellidosTrabajador,
      rolTrabajador: rolTrabajador ?? this.rolTrabajador,
      horaEntrada: horaEntrada ?? this.horaEntrada,
      horaSalida: horaSalida ?? this.horaSalida,
      horasTrabajadas: horasTrabajadas ?? this.horasTrabajadas,
      observaciones: observaciones ?? this.observaciones,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Modelo para trabajador disponible (para selección)
class AvailableWorker {
  final int id;
  final String nombres;
  final String apellidos;
  final String? rol;
  final int? idRol;

  AvailableWorker({
    required this.id,
    required this.nombres,
    required this.apellidos,
    this.rol,
    this.idRol,
  });

  factory AvailableWorker.fromJson(Map<String, dynamic> json) {
    final rolData = json['seg_roll'] as Map<String, dynamic>?;
    
    return AvailableWorker(
      id: json['id'] as int,
      nombres: json['nombres'] as String? ?? 'Sin nombre',
      apellidos: json['apellidos'] as String? ?? '',
      rol: rolData?['denominacion'] as String?,
      idRol: json['id_roll'] as int?,
    );
  }

  String get nombreCompleto => '$nombres $apellidos'.trim();
}
