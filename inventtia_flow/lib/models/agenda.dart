import 'servicio.dart';

class EstadoAgenda {
  final int id;
  final String nombre;
  final String? descripcion;

  EstadoAgenda({required this.id, required this.nombre, this.descripcion});

  factory EstadoAgenda.fromJson(Map<String, dynamic> json) => EstadoAgenda(
        id: json['id'] as int,
        nombre: json['nombre'] as String,
        descripcion: json['descripcion'] as String?,
      );

  bool get esReservado => nombre == 'reservado';
  bool get esCancelado => nombre == 'cancelado';
  bool get esCompletado => nombre == 'completado';
}

class Agenda {
  final int id;
  final String? uuidUsuario;
  final int idLocalServicio;
  final int? idEstado;
  final DateTime fechaHoraReserva;
  final DateTime? fechaHoraAtencion;
  final DateTime createdAt;
  final DateTime updatedAt;
  final EstadoAgenda? estado;
  final LocalServicio? localServicio;

  Agenda({
    required this.id,
    this.uuidUsuario,
    required this.idLocalServicio,
    this.idEstado,
    required this.fechaHoraReserva,
    this.fechaHoraAtencion,
    required this.createdAt,
    required this.updatedAt,
    this.estado,
    this.localServicio,
  });

  factory Agenda.fromJson(Map<String, dynamic> json) => Agenda(
        id: (json['id'] as num).toInt(),
        uuidUsuario: json['uuid_usuario'] as String?,
        idLocalServicio: (json['id_local_servicio'] as num).toInt(),
        idEstado: (json['id_estado'] as num?)?.toInt(),
        fechaHoraReserva: DateTime.parse(json['fecha_hora_reserva'] as String),
        fechaHoraAtencion: json['fecha_hora_atencion'] != null
            ? DateTime.parse(json['fecha_hora_atencion'] as String)
            : null,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        estado: (json['estado'] ?? json['nom_estado_agenda']) != null
            ? EstadoAgenda.fromJson((json['estado'] ?? json['nom_estado_agenda']) as Map<String, dynamic>)
            : null,
        localServicio: json['local_servicio'] != null
            ? LocalServicio.fromJson(json['local_servicio'] as Map<String, dynamic>)
            : (json['local'] != null || json['servicio'] != null)
                ? LocalServicio.fromJson(json)
                : null,
      );
}
