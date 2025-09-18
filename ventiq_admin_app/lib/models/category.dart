class Category {
  final int id;
  final String name;
  final String description;
  final String? parentId;
  final String? parentName;
  final int level; // 1=principal, 2=subcategoria, 3=sub-subcategoria
  final String color;
  final String icon;
  final String? image; // URL de imagen desde Supabase
  final String skuCodigo;
  final bool isActive;
  final int productCount;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<String> tags;
  final double? commission; // Comisión por ventas en esta categoría
  final int sortOrder;
  final int? categoriaTiendaId;
  final DateTime? categoriaTiendaCreatedAt;

  Category({
    required this.id,
    required this.name,
    required this.description,
    this.parentId,
    this.parentName,
    this.level = 1,
    required this.color,
    required this.icon,
    this.image,
    required this.skuCodigo,
    this.isActive = true,
    this.productCount = 0,
    required this.createdAt,
    this.updatedAt,
    this.tags = const [],
    this.commission,
    this.sortOrder = 0,
    this.categoriaTiendaId,
    this.categoriaTiendaCreatedAt,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] ?? 0,
      name: json['denominacion'] ?? json['name'] ?? '',
      description: json['descripcion'] ?? json['description'] ?? '',
      parentId: json['parentId'],
      parentName: json['parentName'],
      level: json['level'] ?? 1,
      color: json['color'] ?? '#4A90E2',
      icon: json['icon'] ?? 'category',
      image: json['image'],
      skuCodigo: json['sku_codigo'] ?? json['skuCodigo'] ?? '',
      isActive: json['isActive'] ?? true,
      productCount: json['productCount'] ?? 0,
      createdAt: DateTime.parse(json['created_at'] ?? json['createdAt'] ?? DateTime.now().toIso8601String()),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
      tags: List<String>.from(json['tags'] ?? []),
      commission: json['commission']?.toDouble(),
      sortOrder: json['sortOrder'] ?? 0,
      categoriaTiendaId: json['categoria_tienda_id'],
      categoriaTiendaCreatedAt: json['categoria_tienda_created_at'] != null 
          ? DateTime.parse(json['categoria_tienda_created_at']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'denominacion': name,
      'descripcion': description,
      'parentId': parentId,
      'parentName': parentName,
      'level': level,
      'color': color,
      'icon': icon,
      'image': image,
      'sku_codigo': skuCodigo,
      'isActive': isActive,
      'productCount': productCount,
      'created_at': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'tags': tags,
      'commission': commission,
      'sortOrder': sortOrder,
      'categoria_tienda_id': categoriaTiendaId,
      'categoria_tienda_created_at': categoriaTiendaCreatedAt?.toIso8601String(),
    };
  }

  Category copyWith({
    int? id,
    String? name,
    String? description,
    String? parentId,
    String? parentName,
    int? level,
    String? color,
    String? icon,
    String? image,
    String? skuCodigo,
    bool? isActive,
    int? productCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? tags,
    double? commission,
    int? sortOrder,
    int? categoriaTiendaId,
    DateTime? categoriaTiendaCreatedAt,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      parentId: parentId ?? this.parentId,
      parentName: parentName ?? this.parentName,
      level: level ?? this.level,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      image: image ?? this.image,
      skuCodigo: skuCodigo ?? this.skuCodigo,
      isActive: isActive ?? this.isActive,
      productCount: productCount ?? this.productCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tags: tags ?? this.tags,
      commission: commission ?? this.commission,
      sortOrder: sortOrder ?? this.sortOrder,
      categoriaTiendaId: categoriaTiendaId ?? this.categoriaTiendaId,
      categoriaTiendaCreatedAt: categoriaTiendaCreatedAt ?? this.categoriaTiendaCreatedAt,
    );
  }
}
