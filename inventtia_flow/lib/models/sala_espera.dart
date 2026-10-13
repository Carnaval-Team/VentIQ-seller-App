import 'servicio.dart';

class SalaEspera {
  final int id;
  final String? uuidUsuario;
  final int idLocalServicio;
  final DateTime fechaRegla;
  final int numeroCola;
  final DateTime createdAt;
  final LocalServicio? localServicio;
  // Campos extra del RPC
  final int ultimoOtorgado;
  final int personasDelante;
  final bool esSuTurno;

  /// Turno elegido al anotarse en la cola (`flow.sala_espera.id_turno`).
  ///
  /// Es `null` en las entradas anteriores a que la app pidiera el turno y en
  /// los servicios que no trabajan por turnos: en esos casos la cola vale para
  /// cualquier turno del día.
  final int? idTurno;

  /// Nombre del turno elegido, tal como lo devuelve
  /// `cliente_obtener_salas_espera` (`null` si la migración
  /// `38_sala_espera_turno.sql` todavía no está aplicada, o si la entrada no
  /// tiene turno).
  final String? turnoNombre;

  SalaEspera({
    required this.id,
    this.uuidUsuario,
    required this.idLocalServicio,
    required this.fechaRegla,
    required this.numeroCola,
    required this.createdAt,
    this.localServicio,
    this.ultimoOtorgado = 0,
    this.personasDelante = 0,
    this.esSuTurno = false,
    this.idTurno,
    this.turnoNombre,
  });

  factory SalaEspera.fromJson(Map<String, dynamic> json) {
    // Soporta formato RPC y formato PostgREST
    final lsRaw = json['local_servicio'];
    LocalServicio? ls;
    if (lsRaw != null) {
      ls = LocalServicio.fromJson(lsRaw as Map<String, dynamic>);
    } else if (json['local'] != null || json['servicio'] != null) {
      // RPC embeds local/servicio directamente en el objeto raíz
      ls = LocalServicio.fromJson(json);
    }

    final turnoRaw = json['turno'];
    final turnoNombre = turnoRaw is Map
        ? turnoRaw['nombre']?.toString()
        : turnoRaw?.toString();

    return SalaEspera(
      id: (json['id'] as num).toInt(),
      uuidUsuario: json['uuid_usuario'] as String?,
      idLocalServicio: (json['id_local_servicio'] as num).toInt(),
      fechaRegla: DateTime.parse(json['fecha_regla'] as String),
      numeroCola: (json['numero_cola'] as num).toInt(),
      createdAt: DateTime.parse(json['created_at'] as String),
      localServicio: ls,
      ultimoOtorgado: (json['ultimo_otorgado'] as num?)?.toInt() ?? 0,
      personasDelante: (json['personas_delante'] as num?)?.toInt() ?? 0,
      esSuTurno: json['es_su_turno'] as bool? ?? false,
      idTurno: (json['id_turno'] as num?)?.toInt(),
      turnoNombre: (turnoNombre ?? '').isEmpty ? null : turnoNombre,
    );
  }
}

class UltimoNumero {
  final int id;
  final int idLocalServicio;
  final int ultimoOtorgado;
  final DateTime updatedAt;

  UltimoNumero({
    required this.id,
    required this.idLocalServicio,
    required this.ultimoOtorgado,
    required this.updatedAt,
  });

  factory UltimoNumero.fromJson(Map<String, dynamic> json) => UltimoNumero(
    id: json['id'] as int,
    idLocalServicio: json['id_local_servicio'] as int,
    ultimoOtorgado: json['ultimo_otorgado'] as int,
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );
}
