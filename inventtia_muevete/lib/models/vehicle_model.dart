class VehicleModel {
  final int? id;
  final DateTime? createdAt;
  final String? marca;
  final String? modelo;
  final String? chapa;
  final String? circulacion;
  final String? categoria;
  final String? capacidad;
  final String? image;
  final String? descripcion;
  final String? color;

  VehicleModel({
    this.id,
    this.createdAt,
    this.marca,
    this.modelo,
    this.chapa,
    this.circulacion,
    this.categoria,
    this.capacidad,
    this.image,
    this.descripcion,
    this.color,
  });

  factory VehicleModel.fromJson(Map<String, dynamic> json) {
    return VehicleModel(
      id: json['id'] as int?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      marca: json['marca'] as String?,
      modelo: json['modelo'] as String?,
      chapa: json['chapa'] as String?,
      circulacion: json['circulacion'] as String?,
      categoria: json['categoria'] as String?,
      capacidad: json['capacidad'] as String?,
      image: json['image'] as String?,
      descripcion: json['descripcion'] as String?,
      color: json['color'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'marca': marca,
      'modelo': modelo,
      'chapa': chapa,
      'circulacion': circulacion,
      'categoria': categoria,
      'capacidad': capacidad,
      'image': image,
      'descripcion': descripcion,
      'color': color,
    };
  }

  VehicleModel copyWith({
    int? id,
    DateTime? createdAt,
    String? marca,
    String? modelo,
    String? chapa,
    String? circulacion,
    String? categoria,
    String? capacidad,
    String? image,
    String? descripcion,
    String? color,
  }) {
    return VehicleModel(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      marca: marca ?? this.marca,
      modelo: modelo ?? this.modelo,
      chapa: chapa ?? this.chapa,
      circulacion: circulacion ?? this.circulacion,
      categoria: categoria ?? this.categoria,
      capacidad: capacidad ?? this.capacidad,
      image: image ?? this.image,
      descripcion: descripcion ?? this.descripcion,
      color: color ?? this.color,
    );
  }
}
