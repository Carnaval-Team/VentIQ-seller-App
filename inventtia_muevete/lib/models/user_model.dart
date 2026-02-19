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
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
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
    );
  }
}
