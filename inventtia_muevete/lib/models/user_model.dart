class UserModel {
  final int? userId;
  final DateTime? createdAt;
  final String? name;
  final String? phone;
  final String? email;
  final String? image;
  final String? uuid;
  final String? ci;
  final String? latitud;
  final String? longitud;
  final String? province;
  final String? municipality;
  final String? direccion;
  final String? pais;
  // New: user type discriminator and shipper fields
  final String? tipoUsuario;
  final String? tipoCuenta;
  final String? empresaNombre;
  final String? empresaRut;
  final String? empresaDireccion;
  final List<String>? mercaderiasHabituales;

  UserModel({
    this.userId,
    this.createdAt,
    this.name,
    this.phone,
    this.email,
    this.image,
    this.uuid,
    this.ci,
    this.latitud,
    this.longitud,
    this.province,
    this.municipality,
    this.direccion,
    this.pais,
    this.tipoUsuario,
    this.tipoCuenta,
    this.empresaNombre,
    this.empresaRut,
    this.empresaDireccion,
    this.mercaderiasHabituales,
  });

  bool get isShipper => tipoUsuario == 'shipper';
  bool get isClientePasajero => tipoUsuario == 'cliente_pasajero' || tipoUsuario == null;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    List<String>? mercaderias;
    final raw = json['mercaderias_habituales'];
    if (raw is List) {
      mercaderias = raw.map((e) => e.toString()).toList();
    }
    return UserModel(
      userId: json['user_id'] as int?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      name: json['name'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      image: json['image'] as String?,
      uuid: json['uuid'] as String?,
      ci: json['ci'] as String?,
      latitud: json['latitud'] as String?,
      longitud: json['longitud'] as String?,
      province: json['province'] as String?,
      municipality: json['municipality'] as String?,
      direccion: json['direccion'] as String?,
      pais: json['pais'] as String?,
      tipoUsuario: json['tipo_usuario'] as String?,
      tipoCuenta: json['tipo_cuenta'] as String?,
      empresaNombre: json['empresa_nombre'] as String?,
      empresaRut: json['empresa_rut'] as String?,
      empresaDireccion: json['empresa_direccion'] as String?,
      mercaderiasHabituales: mercaderias,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'phone': phone,
      'email': email,
      'image': image,
      'uuid': uuid,
      'ci': ci,
      'latitud': latitud,
      'longitud': longitud,
      'province': province,
      'municipality': municipality,
      'direccion': direccion,
      'pais': pais,
      if (tipoUsuario != null) 'tipo_usuario': tipoUsuario,
      if (tipoCuenta != null) 'tipo_cuenta': tipoCuenta,
      if (empresaNombre != null) 'empresa_nombre': empresaNombre,
      if (empresaRut != null) 'empresa_rut': empresaRut,
      if (empresaDireccion != null) 'empresa_direccion': empresaDireccion,
      if (mercaderiasHabituales != null)
        'mercaderias_habituales': mercaderiasHabituales,
    };
  }

  UserModel copyWith({
    int? userId,
    DateTime? createdAt,
    String? name,
    String? phone,
    String? email,
    String? image,
    String? uuid,
    String? ci,
    String? latitud,
    String? longitud,
    String? province,
    String? municipality,
    String? direccion,
    String? pais,
    String? tipoUsuario,
    String? tipoCuenta,
    String? empresaNombre,
    String? empresaRut,
    String? empresaDireccion,
    List<String>? mercaderiasHabituales,
  }) {
    return UserModel(
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      image: image ?? this.image,
      uuid: uuid ?? this.uuid,
      ci: ci ?? this.ci,
      latitud: latitud ?? this.latitud,
      longitud: longitud ?? this.longitud,
      province: province ?? this.province,
      municipality: municipality ?? this.municipality,
      direccion: direccion ?? this.direccion,
      pais: pais ?? this.pais,
      tipoUsuario: tipoUsuario ?? this.tipoUsuario,
      tipoCuenta: tipoCuenta ?? this.tipoCuenta,
      empresaNombre: empresaNombre ?? this.empresaNombre,
      empresaRut: empresaRut ?? this.empresaRut,
      empresaDireccion: empresaDireccion ?? this.empresaDireccion,
      mercaderiasHabituales:
          mercaderiasHabituales ?? this.mercaderiasHabituales,
    );
  }
}
