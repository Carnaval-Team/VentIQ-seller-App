class SuperAdmin {
  final int id;
  final String uuid;
  final String nombre;
  final String apellidos;
  final String email;
  final String? telefono;
  final bool activo;
  final int nivelAcceso;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? ultimoAcceso;



  //nuevo a acutlizar 
  SuperAdmin({
    required this.id,
    required this.uuid,
    required this.nombre,
    required this.apellidos,
    required this.email,
    this.telefono,
    required this.activo,
    required this.nivelAcceso,
    required this.createdAt,
    required this.updatedAt,
    this.ultimoAcceso,
  });

  factory SuperAdmin.fromJson(Map<String, dynamic> json) {
    return SuperAdmin(
      id: json['id'],
      uuid: json['uuid'],
      nombre: json['nombre'],
      apellidos: json['apellidos'],
      email: json['email'],
      telefono: json['telefono'],
      activo: json['activo'] ?? true,
      nivelAcceso: json['nivel_acceso'] ?? 1,
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
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'ultimo_acceso': ultimoAcceso?.toIso8601String(),
    };
  }

  String get nombreCompleto => '$nombre $apellidos';
  
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
