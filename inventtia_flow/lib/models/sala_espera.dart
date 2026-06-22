import 'servicio.dart';

class SalaEspera {
  final int id;
  final String uuidUsuario;
  final int idLocalServicio;
  final DateTime fechaRegla;
  final int numeroCola;
  final DateTime createdAt;
  final LocalServicio? localServicio;

  SalaEspera({
    required this.id,
    required this.uuidUsuario,
    required this.idLocalServicio,
    required this.fechaRegla,
    required this.numeroCola,
    required this.createdAt,
    this.localServicio,
  });

  factory SalaEspera.fromJson(Map<String, dynamic> json) => SalaEspera(
        id: json['id'] as int,
        uuidUsuario: json['uuid_usuario'] as String,
        idLocalServicio: json['id_local_servicio'] as int,
        fechaRegla: DateTime.parse(json['fecha_regla'] as String),
        numeroCola: json['numero_cola'] as int,
        createdAt: DateTime.parse(json['created_at'] as String),
        localServicio: json['local_servicio'] != null
            ? LocalServicio.fromJson(json['local_servicio'] as Map<String, dynamic>)
            : null,
      );
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
