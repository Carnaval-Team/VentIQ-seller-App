class HomeBanner {
  final int? id;
  final String imageUrl;
  final String? link;
  final String? descripcion;
  final int orden;
  final bool activo;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const HomeBanner({
    this.id,
    required this.imageUrl,
    this.link,
    this.descripcion,
    this.orden = 0,
    this.activo = true,
    this.createdAt,
    this.updatedAt,
  });

  factory HomeBanner.fromJson(Map<String, dynamic> json) {
    return HomeBanner(
      id: json['id'] as int?,
      imageUrl: json['image_url'] as String? ?? '',
      link: json['link'] as String?,
      descripcion: json['descripcion'] as String?,
      orden: (json['orden'] as num?)?.toInt() ?? 0,
      activo: json['activo'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'image_url': imageUrl,
      'link': link,
      'descripcion': descripcion,
      'orden': orden,
      'activo': activo,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  HomeBanner copyWith({
    int? id,
    String? imageUrl,
    String? link,
    String? descripcion,
    int? orden,
    bool? activo,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return HomeBanner(
      id: id ?? this.id,
      imageUrl: imageUrl ?? this.imageUrl,
      link: link ?? this.link,
      descripcion: descripcion ?? this.descripcion,
      orden: orden ?? this.orden,
      activo: activo ?? this.activo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
