class Perfil {
  final int id;
  final String uuidUsuario;
  final String nombre;
  final String apellidos;
  final String ci;
  final String? telefono;
  final DateTime createdAt;
  final DateTime updatedAt;

  Perfil({
    required this.id,
    required this.uuidUsuario,
    required this.nombre,
    required this.apellidos,
    required this.ci,
    this.telefono,
    required this.createdAt,
    required this.updatedAt,
  });

  String get nombreCompleto => '$nombre $apellidos';

  factory Perfil.fromJson(Map<String, dynamic> json) => Perfil(
        id: json['id'] as int,
        uuidUsuario: json['uuid_usuario'] as String,
        nombre: json['nombre'] as String,
        apellidos: json['apellidos'] as String,
        ci: json['ci'] as String,
        telefono: json['telefono'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'uuid_usuario': uuidUsuario,
        'nombre': nombre,
        'apellidos': apellidos,
        'ci': ci,
        'telefono': telefono,
      };

  Perfil copyWith({
    String? nombre,
    String? apellidos,
    String? ci,
    String? telefono,
  }) =>
      Perfil(
        id: id,
        uuidUsuario: uuidUsuario,
        nombre: nombre ?? this.nombre,
        apellidos: apellidos ?? this.apellidos,
        ci: ci ?? this.ci,
        telefono: telefono ?? this.telefono,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}
