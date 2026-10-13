// Modelos para recursos / tramos / turnos de un local_servicio.
// Reflejan las tablas flow.recurso, flow.tramo, flow.turno y flow.turno_tramo
// (ver migración 16_recursos_tramos_turnos.sql).
//
// Jerarquía (léase con ejemplos de varios oficios, no sólo transporte):
//   Recurso (Carro 1 / Mesa 3 / Habitación 4 / Sillón de uñas)
//     → Tramo (Ida / Vuelta / Entrada / Salida / …)
//       → Turno (la opción que el cliente elige)
//   Un turno consume 1 plaza de CADA tramo en Turno.tramosIds.
//
// Un tramo sólo hace falta cuando un mismo turno gasta capacidad en VARIOS
// contadores a la vez (ida y vuelta de un ómnibus, entrada y salida de una
// habitación). Si el negocio no tiene ese caso, el local_servicio puede trabajar
// con `sin_tramos` / `solo_turnos` y la app le crea un tramo oculto por turno:
// el modelo no cambia, sólo deja de mostrarse.

/// Bucket de capacidad compartida dentro de un recurso (ej: Ida, Vuelta).
class Tramo {
  final int id;
  final String nombre;

  /// Capacidad del tramo por día. `null` = hereda [Recurso.capacidad].
  final int? capacidad;
  final String? tipoTrayecto;
  final int orden;
  final bool activo;

  Tramo({
    required this.id,
    required this.nombre,
    this.capacidad,
    this.tipoTrayecto,
    this.orden = 0,
    this.activo = true,
  });

  factory Tramo.fromJson(Map<String, dynamic> json) => Tramo(
    id: (json['id'] as num).toInt(),
    nombre: json['nombre'] as String,
    capacidad: (json['capacidad'] as num?)?.toInt(),
    tipoTrayecto: json['tipo_trayecto'] as String?,
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
  final Map<String, double> precios;

  /// Ids de los tramos que este turno consume (1 plaza de cada uno).
  final List<int> tramosIds;

  /// Hora de inicio del turno, `"HH:MM"`, o null. Sólo presentación: no altera
  /// cupo ni reserva (punto 7 del plan de mejoras).
  final String? horaInicio;

  /// Hora de fin del turno, `"HH:MM"`, o null.
  final String? horaFin;

  Turno({
    required this.id,
    required this.nombre,
    this.orden = 0,
    this.activo = true,
    Map<String, double>? precios,
    List<int>? tramosIds,
    this.horaInicio,
    this.horaFin,
  }) : precios = precios ?? {},
       tramosIds = tramosIds ?? [];

  /// `"09:00 – 11:00"`, `"09:00"` o null si no hay ninguna hora.
  String? get etiquetaHora => etiquetaHoraTurno(horaInicio, horaFin);

  factory Turno.fromJson(Map<String, dynamic> json) => Turno(
    id: (json['id'] as num).toInt(),
    nombre: json['nombre'] as String,
    orden: (json['orden'] as num?)?.toInt() ?? 0,
    activo: (json['activo'] as bool?) ?? true,
    precios:
        (json['precios'] as Map?)?.map(
          (key, value) => MapEntry(key.toString(), (value as num).toDouble()),
        ) ??
        {},
    tramosIds:
        (json['tramos'] as List?)?.map((e) => (e as num).toInt()).toList() ??
        [],
    // La BD manda `"09:00"` por `to_char(..., 'HH24:MI')`, pero se normaliza
    // igualmente por si llega `"09:00:00"` de una consulta directa a la tabla.
    horaInicio: _normalizarHora(json['hora_inicio']),
    horaFin: _normalizarHora(json['hora_fin']),
  );
}

/// Deja `"09:00"` y `"09:00:00"` en `"09:00"`. Cualquier otra cosa es null: una
/// hora ilegible no debe romper el parseo de todo el recurso.
String? _normalizarHora(Object? raw) {
  if (raw is! String) return null;
  final t = raw.trim();
  if (t.isEmpty) return null;
  final partes = t.split(':');
  if (partes.length < 2) return null;
  final h = int.tryParse(partes[0]);
  final m = int.tryParse(partes[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// Etiqueta legible de las horas de un turno.
///
/// Pura y sin dependencias para poder testearla: es la que usan el admin, la
/// ficha del cliente y la lista de turnos, y todas deben decir lo mismo.
String? etiquetaHoraTurno(String? inicio, String? fin) {
  final i = (inicio == null || inicio.trim().isEmpty) ? null : inicio.trim();
  final f = (fin == null || fin.trim().isEmpty) ? null : fin.trim();
  if (i == null && f == null) return null;
  if (i != null && f != null) return '$i – $f';
  return i ?? f;
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
  }) : tramos = tramos ?? [],
       turnos = turnos ?? [];

  factory Recurso.fromJson(Map<String, dynamic> json) => Recurso(
    id: (json['id'] as num).toInt(),
    idLocalServicio: (json['id_local_servicio'] as num?)?.toInt() ?? 0,
    nombre: json['nombre'] as String,
    capacidad: (json['capacidad'] as num?)?.toInt() ?? 1,
    orden: (json['orden'] as num?)?.toInt() ?? 0,
    activo: (json['activo'] as bool?) ?? true,
    tramos:
        (json['tramos'] as List?)
            ?.map((e) => Tramo.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    turnos:
        (json['turnos'] as List?)
            ?.map((e) => Turno.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
  );

  /// Capacidad efectiva de un tramo (la suya o, si es null, la del recurso).
  int capacidadDe(Tramo t) => t.capacidad ?? capacidad;

  /// Nombre con el que la migración 41 crea el recurso oculto de los modos
  /// simplificados ("solo turnos" / "no uso tramos").
  static const String nombreCupoInterno = 'Cupo';

  /// `true` si este recurso es el que crea el sistema por detrás en los modos
  /// simplificados. La UI lo etiqueta distinto ("Cupo del día") para que el
  /// admin no crea que lo creó él ni intente gestionarlo como a Mesa 3.
  bool get esCupoInterno =>
      nombre.trim().toLowerCase() == nombreCupoInterno.toLowerCase();
}
