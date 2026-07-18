// Modelos para recursos / tramos / turnos de un local_servicio.
// Reflejan las tablas flow.recurso, flow.tramo, flow.turno y flow.turno_tramo
// (ver migración 16_recursos_tramos_turnos.sql).
//
// Jerarquía:
//   Recurso (Carro 1) → Tramos (Ida, Vuelta) → Turnos (Ida y vuelta, Solo ida)
//   Un turno consume 1 plaza de CADA tramo en Turno.tramosIds.

/// Bucket de capacidad compartida dentro de un recurso (ej: Ida, Vuelta).
class Tramo {
  final int id;
  final String nombre;

  /// Capacidad del tramo por día. `null` = hereda [Recurso.capacidad].
  final int? capacidad;
  final int orden;
  final bool activo;

  Tramo({
    required this.id,
    required this.nombre,
    this.capacidad,
    this.orden = 0,
    this.activo = true,
  });

  factory Tramo.fromJson(Map<String, dynamic> json) => Tramo(
        id: (json['id'] as num).toInt(),
        nombre: json['nombre'] as String,
        capacidad: (json['capacidad'] as num?)?.toInt(),
        orden: (json['orden'] as num?)?.toInt() ?? 0,
        activo: (json['activo'] as bool?) ?? true,
      );
}

/// Opción reservable de un recurso; consume los tramos de [tramosIds].
class Turno {
  final int id;
  final String nombre;
  final int orden;
  final bool activo;

  /// Ids de los tramos que este turno consume (1 plaza de cada uno).
  final List<int> tramosIds;

  Turno({
    required this.id,
    required this.nombre,
    this.orden = 0,
    this.activo = true,
    List<int>? tramosIds,
  }) : tramosIds = tramosIds ?? [];

  factory Turno.fromJson(Map<String, dynamic> json) => Turno(
        id: (json['id'] as num).toInt(),
        nombre: json['nombre'] as String,
        orden: (json['orden'] as num?)?.toInt() ?? 0,
        activo: (json['activo'] as bool?) ?? true,
        tramosIds: (json['tramos'] as List?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            [],
      );
}

/// Unidad que presta el servicio (ej: Carro 1). Agrupa tramos y turnos.
class Recurso {
  final int id;
  final int idLocalServicio;
  final String nombre;

  /// Capacidad por defecto que heredan los tramos sin capacidad propia.
  final int capacidad;
  final int orden;
  final bool activo;
  final List<Tramo> tramos;
  final List<Turno> turnos;

  Recurso({
    required this.id,
    this.idLocalServicio = 0,
    required this.nombre,
    this.capacidad = 1,
    this.orden = 0,
    this.activo = true,
    List<Tramo>? tramos,
    List<Turno>? turnos,
  })  : tramos = tramos ?? [],
        turnos = turnos ?? [];

  factory Recurso.fromJson(Map<String, dynamic> json) => Recurso(
        id: (json['id'] as num).toInt(),
        idLocalServicio: (json['id_local_servicio'] as num?)?.toInt() ?? 0,
        nombre: json['nombre'] as String,
        capacidad: (json['capacidad'] as num?)?.toInt() ?? 1,
        orden: (json['orden'] as num?)?.toInt() ?? 0,
        activo: (json['activo'] as bool?) ?? true,
        tramos: (json['tramos'] as List?)
                ?.map((e) => Tramo.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        turnos: (json['turnos'] as List?)
                ?.map((e) => Turno.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  /// Capacidad efectiva de un tramo (la suya o, si es null, la del recurso).
  int capacidadDe(Tramo t) => t.capacidad ?? capacidad;
}
