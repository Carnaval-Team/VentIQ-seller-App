class WorkerRole {
  final int id;
  final String denominacion;
  final String? descripcion;
  final DateTime createdAt;

  WorkerRole({
    required this.id,
    required this.denominacion,
    this.descripcion,
    required this.createdAt,
  });

  factory WorkerRole.fromJson(Map<String, dynamic> json) {
    return WorkerRole(
      id: json['id'] as int,
      denominacion: json['denominacion'] as String,
      descripcion: json['descripcion'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'denominacion': denominacion,
      'descripcion': descripcion,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class WorkerData {
  final int trabajadorId;
  final String nombres;
  final String apellidos;
  final DateTime fechaCreacion;
  final int rolId;
  final String rolNombre;
  final String tipoRol;
  final Map<String, dynamic> datosEspecificos;
  final String? usuarioUuid;

  WorkerData({
    required this.trabajadorId,
    required this.nombres,
    required this.apellidos,
    required this.fechaCreacion,
    required this.rolId,
    required this.rolNombre,
    required this.tipoRol,
    required this.datosEspecificos,
    this.usuarioUuid,
  });

  factory WorkerData.fromJson(Map<String, dynamic> json) {
    return WorkerData(
      trabajadorId: json['trabajador_id'] as int,
      nombres: json['nombres'] as String,
      apellidos: json['apellidos'] as String,
      fechaCreacion: DateTime.parse(json['fecha_creacion'] as String),
      rolId: json['rol_id'] as int? ?? 0, // Si es null, usar 0
      rolNombre: json['rol_nombre'] as String? ?? 'Desconocido', // Si es null, usar 'Desconocido'
      tipoRol: json['tipo_rol'] as String,
      datosEspecificos: json['datos_especificos'] as Map<String, dynamic>? ?? {},
      usuarioUuid: json['usuario_uuid'] as String?,
    );
  }

  String get nombreCompleto => '$nombres $apellidos';

  // Getters para datos específicos según el rol
  String? get tpvDenominacion => datosEspecificos['tpv_denominacion'] as String?;
  int? get tpvId => datosEspecificos['tpv_id'] as int?;
  String? get numeroConfirmacion => datosEspecificos['numero_confirmacion'] as String?;
  
  String? get almacenDenominacion => datosEspecificos['almacen_denominacion'] as String?;
  int? get almacenId => datosEspecificos['almacen_id'] as int?;
  String? get almacenDireccion => datosEspecificos['almacen_direccion'] as String?;
  String? get almacenUbicacion => datosEspecificos['almacen_ubicacion'] as String?;

  Map<String, dynamic> toJson() {
    return {
      'trabajador_id': trabajadorId,
      'nombres': nombres,
      'apellidos': apellidos,
      'fecha_creacion': fechaCreacion.toIso8601String(),
      'rol_id': rolId,
      'rol_nombre': rolNombre,
      'tipo_rol': tipoRol,
      'datos_especificos': datosEspecificos,
      'usuario_uuid': usuarioUuid,
    };
  }
}

class TPVData {
  final int id;
  final String denominacion;
  final String? almacenDenominacion;
  final int? almacenId;

  TPVData({
    required this.id,
    required this.denominacion,
    this.almacenDenominacion,
    this.almacenId,
  });

  factory TPVData.fromJson(Map<String, dynamic> json) {
    return TPVData(
      id: json['id'] as int,
      denominacion: json['denominacion'] as String,
      almacenDenominacion: json['almacen_denominacion'] as String?,
      almacenId: json['almacen_id'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'denominacion': denominacion,
      'almacen_denominacion': almacenDenominacion,
      'almacen_id': almacenId,
    };
  }
}

class AlmacenData {
  final int id;
  final String denominacion;
  final String? direccion;
  final String? ubicacion;

  AlmacenData({
    required this.id,
    required this.denominacion,
    this.direccion,
    this.ubicacion,
  });

  factory AlmacenData.fromJson(Map<String, dynamic> json) {
    return AlmacenData(
      id: json['id'] as int,
      denominacion: json['denominacion'] as String,
      direccion: json['direccion'] as String?,
      ubicacion: json['ubicacion'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'denominacion': denominacion,
      'direccion': direccion,
      'ubicacion': ubicacion,
    };
  }
}

class WorkerStatistics {
  final int totalTrabajadores;
  final int totalGerentes;
  final int totalSupervisores;
  final int totalVendedores;
  final int totalAlmaceneros;
  final double porcentajeGerentes;
  final double porcentajeSupervisores;
  final double porcentajeVendedores;
  final double porcentajeAlmaceneros;

  WorkerStatistics({
    required this.totalTrabajadores,
    required this.totalGerentes,
    required this.totalSupervisores,
    required this.totalVendedores,
    required this.totalAlmaceneros,
    required this.porcentajeGerentes,
    required this.porcentajeSupervisores,
    required this.porcentajeVendedores,
    required this.porcentajeAlmaceneros,
  });

  factory WorkerStatistics.fromJson(Map<String, dynamic> json) {
    // Extraer datos de la estructura anidada del RPC
    final porRol = json['por_rol'] as Map<String, dynamic>? ?? {};
    final porcentajes = json['porcentajes'] as Map<String, dynamic>? ?? {};
    
    return WorkerStatistics(
      totalTrabajadores: json['total_trabajadores'] as int? ?? 0,
      totalGerentes: porRol['gerentes'] as int? ?? 0,
      totalSupervisores: porRol['supervisores'] as int? ?? 0,
      totalVendedores: porRol['vendedores'] as int? ?? 0,
      totalAlmaceneros: porRol['almaceneros'] as int? ?? 0,
      porcentajeGerentes: (porcentajes['gerentes'] as num?)?.toDouble() ?? 0.0,
      porcentajeSupervisores: (porcentajes['supervisores'] as num?)?.toDouble() ?? 0.0,
      porcentajeVendedores: (porcentajes['vendedores'] as num?)?.toDouble() ?? 0.0,
      porcentajeAlmaceneros: (porcentajes['almaceneros'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
