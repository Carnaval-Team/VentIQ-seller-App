class Variant {
  final int id;
  final int idSubCategoria;
  final int idAtributo;
  final String denominacion;
  final String label;
  final String? descripcion;
  final DateTime createdAt;
  final String? subCategoriaName; // For displaying subcategory info
  final String? atributoName; // For displaying attribute info - deprecated, use denominacion
  final List<VariantOption> options;

  Variant({
    required this.id,
    required this.idSubCategoria,
    required this.idAtributo,
    required this.denominacion,
    required this.label,
    this.descripcion,
    required this.createdAt,
    this.subCategoriaName,
    this.atributoName,
    this.options = const [],
  });

  factory Variant.fromJson(Map<String, dynamic> json) {
    return Variant(
      id: json['id'] as int,
      idSubCategoria: json['id_sub_categoria'] ?? 0, // Default for compatibility
      idAtributo: json['id_atributo'] ?? json['id'] ?? 0, // Use id as fallback
      denominacion: json['denominacion'] as String,
      label: json['label'] as String,
      descripcion: json['descripcion'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      subCategoriaName: json['subcategoria_name'] as String?,
      atributoName: json['atributo_name'] as String?, // Keep for backward compatibility
      options: (json['opciones'] as List<dynamic>?)
          ?.map((o) => VariantOption.fromJson(o))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'id_sub_categoria': idSubCategoria,
      'id_atributo': idAtributo,
      'denominacion': denominacion,
      'label': label,
      'descripcion': descripcion,
      'created_at': createdAt.toIso8601String(),
      if (subCategoriaName != null) 'subcategoria_name': subCategoriaName,
      if (atributoName != null) 'atributo_name': atributoName,
      'opciones': options.map((o) => o.toJson()).toList(),
    };
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'denominacion': denominacion,
      'label': label,
      'descripcion': descripcion,
      'id_sub_categoria': idSubCategoria,
      'id_atributo': idAtributo,
    };
  }

  @override
  String toString() => denominacion;
}

class VariantOption {
  final int id;
  final int idVariante;
  final String denominacion;
  final String? descripcion;
  final String? valor;
  final String? color;
  final String? imageUrl;
  final DateTime createdAt;

  VariantOption({
    required this.id,
    required this.idVariante,
    required this.denominacion,
    this.descripcion,
    this.valor,
    this.color,
    this.imageUrl,
    required this.createdAt,
  });

  factory VariantOption.fromJson(Map<String, dynamic> json) {
    return VariantOption(
      id: json['id'] as int,
      idVariante: json['id_variante'] as int,
      denominacion: json['denominacion'] as String,
      descripcion: json['descripcion'] as String?,
      valor: json['valor'] as String?,
      color: json['color'] as String?,
      imageUrl: json['image_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'id_variante': idVariante,
      'denominacion': denominacion,
      'descripcion': descripcion,
      'valor': valor,
      'color': color,
      'image_url': imageUrl,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'id_variante': idVariante,
      'denominacion': denominacion,
      'descripcion': descripcion,
      'valor': valor,
      'color': color,
      'image_url': imageUrl,
    };
  }

  @override
  String toString() => denominacion;
}
