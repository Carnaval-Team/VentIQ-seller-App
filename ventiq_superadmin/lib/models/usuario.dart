class Usuario {
  final String id;
  final String email;
  final String nombre;
  final String apellido;
  final String rol; // super_admin, admin_tienda, gerente, supervisor
  final List<int> tiendasAsignadas;
  final DateTime fechaCreacion;
  final DateTime? ultimoAcceso;
  final bool activo;

  Usuario({
    required this.id,
    required this.email,
    required this.nombre,
    required this.apellido,
    required this.rol,
    required this.tiendasAsignadas,
    required this.fechaCreacion,
    this.ultimoAcceso,
    required this.activo,
  });

  String get nombreCompleto => '$nombre $apellido';

  bool get esSuperAdmin => rol == 'super_admin';
  bool get esAdminTienda => rol == 'admin_tienda';

  factory Usuario.fromJson(Map<String, dynamic> json) {
    return Usuario(
      id: json['id'],
      email: json['email'],
      nombre: json['nombre'],
      apellido: json['apellido'],
      rol: json['rol'],
      tiendasAsignadas: List<int>.from(json['tiendas_asignadas'] ?? []),
      fechaCreacion: DateTime.parse(json['fecha_creacion']),
      ultimoAcceso: json['ultimo_acceso'] != null
          ? DateTime.parse(json['ultimo_acceso'])
          : null,
      activo: json['activo'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'nombre': nombre,
      'apellido': apellido,
      'rol': rol,
      'tiendas_asignadas': tiendasAsignadas,
      'fecha_creacion': fechaCreacion.toIso8601String(),
      'ultimo_acceso': ultimoAcceso?.toIso8601String(),
      'activo': activo,
    };
  }

  static List<Usuario> getMockData() {
    return [
      Usuario(
        id: 'super-1',
        email: 'admin@ventiq.com',
        nombre: 'Carlos',
        apellido: 'Rodríguez',
        rol: 'super_admin',
        tiendasAsignadas: [],
        fechaCreacion: DateTime.now().subtract(const Duration(days: 365)),
        ultimoAcceso: DateTime.now().subtract(const Duration(hours: 2)),
        activo: true,
      ),
      Usuario(
        id: 'admin-1',
        email: 'maria.gonzalez@supermercadocentral.com',
        nombre: 'María',
        apellido: 'González',
        rol: 'admin_tienda',
        tiendasAsignadas: [1],
        fechaCreacion: DateTime.now().subtract(const Duration(days: 180)),
        ultimoAcceso: DateTime.now().subtract(const Duration(hours: 6)),
        activo: true,
      ),
      Usuario(
        id: 'admin-2',
        email: 'juan.perez@minimarket.com',
        nombre: 'Juan',
        apellido: 'Pérez',
        rol: 'admin_tienda',
        tiendasAsignadas: [2],
        fechaCreacion: DateTime.now().subtract(const Duration(days: 90)),
        ultimoAcceso: DateTime.now().subtract(const Duration(days: 1)),
        activo: true,
      ),
      Usuario(
        id: 'gerente-1',
        email: 'ana.martinez@farmacia.com',
        nombre: 'Ana',
        apellido: 'Martínez',
        rol: 'gerente',
        tiendasAsignadas: [3],
        fechaCreacion: DateTime.now().subtract(const Duration(days: 365)),
        ultimoAcceso: DateTime.now().subtract(const Duration(hours: 12)),
        activo: true,
      ),
      Usuario(
        id: 'admin-3',
        email: 'pedro.santos@colmado.com',
        nombre: 'Pedro',
        apellido: 'Santos',
        rol: 'admin_tienda',
        tiendasAsignadas: [4],
        fechaCreacion: DateTime.now().subtract(const Duration(days: 60)),
        ultimoAcceso: DateTime.now().subtract(const Duration(days: 7)),
        activo: false,
      ),
    ];
  }
}
