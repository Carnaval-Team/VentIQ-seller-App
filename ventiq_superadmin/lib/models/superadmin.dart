import 'superadmin_role.dart';

class SuperAdmin {
  final int id;
  final String uuid;
  final String nombre;
  final String apellidos;
  final String email;
  final String? telefono;
  final bool activo;
  final int nivelAcceso;
  final int? idRol;
  final SuperAdminRole? rol;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? ultimoAcceso;

  SuperAdmin({
    required this.id,
    required this.uuid,
    required this.nombre,
    required this.apellidos,
    required this.email,
    this.telefono,
    required this.activo,
    required this.nivelAcceso,
    this.idRol,
    this.rol,
    required this.createdAt,
    required this.updatedAt,
    this.ultimoAcceso,
  });

  factory SuperAdmin.fromJson(Map<String, dynamic> json) {
    SuperAdminRole? rol;
    if (json['app_dat_superadmin_roles'] is Map) {
      rol = SuperAdminRole.fromJson(json['app_dat_superadmin_roles']);
    } else if (json['rol'] is Map) {
      rol = SuperAdminRole.fromJson(json['rol']);
    }

    return SuperAdmin(
      id: json['id'],
      uuid: json['uuid'],
      nombre: json['nombre'],
      apellidos: json['apellidos'],
      email: json['email'],
      telefono: json['telefono'],
      activo: json['activo'] ?? true,
      nivelAcceso: json['nivel_acceso'] ?? 1,
      idRol: json['id_rol'],
      rol: rol,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      ultimoAcceso: json['ultimo_acceso'] != null
          ? DateTime.parse(json['ultimo_acceso'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uuid': uuid,
      'nombre': nombre,
      'apellidos': apellidos,
      'email': email,
      'telefono': telefono,
      'activo': activo,
      'nivel_acceso': nivelAcceso,
      'id_rol': idRol,
      if (rol != null) 'app_dat_superadmin_roles': rol!.toJson(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'ultimo_acceso': ultimoAcceso?.toIso8601String(),
    };
  }

  String get nombreCompleto => '$nombre $apellidos';

  List<String> get permisosRutas {
    if (rol != null && rol!.permisos.isNotEmpty) {
      return rol!.permisos;
    }
    // Fallback legacy: nivel 1 = acceso a todo, niveles 2 y 3 tambien pueden navegar (los permisos de escritura se controlan aparte).
    return [];
  }

  String get nivelAccesoTexto {
    switch (nivelAcceso) {
      case 1:
        return 'Acceso Total';
      case 2:
        return 'Lectura/Escritura';
      case 3:
        return 'Solo Lectura';
      default:
        return 'Sin Acceso';
    }
  }
}
