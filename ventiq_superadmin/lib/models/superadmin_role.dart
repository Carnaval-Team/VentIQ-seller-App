class SuperAdminRole {
  final int? id;
  final String nombre;
  final String? descripcion;
  final List<String> permisos;
  final bool activo;
  final DateTime createdAt;
  final DateTime updatedAt;

  SuperAdminRole({
    this.id,
    required this.nombre,
    this.descripcion,
    this.permisos = const [],
    this.activo = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SuperAdminRole.fromJson(Map<String, dynamic> json) {
    final permisosRaw = json['permisos'];
    List<String> permisos = [];
    if (permisosRaw is List) {
      permisos = permisosRaw.map((e) => e.toString()).toList();
    } else if (permisosRaw is String && permisosRaw.isNotEmpty) {
      try {
        // Fallback por si viene como string JSON
        permisos = permisosRaw
            .replaceAll('[', '')
            .replaceAll(']', '')
            .replaceAll('"', '')
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      } catch (_) {}
    }

    return SuperAdminRole(
      id: json['id'],
      nombre: json['nombre'] ?? '',
      descripcion: json['descripcion'],
      permisos: permisos,
      activo: json['activo'] ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'nombre': nombre,
      'descripcion': descripcion,
      'permisos': permisos,
      'activo': activo,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  SuperAdminRole copyWith({
    int? id,
    String? nombre,
    String? descripcion,
    List<String>? permisos,
    bool? activo,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SuperAdminRole(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      descripcion: descripcion ?? this.descripcion,
      permisos: permisos ?? this.permisos,
      activo: activo ?? this.activo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
