class Category {
  final String id;
  final String name;
  final String description;
  final String? parentId;
  final String? parentName;
  final int level; // 1=principal, 2=subcategoria, 3=sub-subcategoria
  final String color;
  final String icon;
  final bool isActive;
  final int productCount;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<String> tags;
  final double? commission; // Comisión por ventas en esta categoría
  final int sortOrder;

  Category({
    required this.id,
    required this.name,
    required this.description,
    this.parentId,
    this.parentName,
    this.level = 1,
    required this.color,
    required this.icon,
    this.isActive = true,
    this.productCount = 0,
    required this.createdAt,
    this.updatedAt,
    this.tags = const [],
    this.commission,
    this.sortOrder = 0,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      parentId: json['parentId'],
      parentName: json['parentName'],
      level: json['level'] ?? 1,
      color: json['color'] ?? '#4A90E2',
      icon: json['icon'] ?? 'category',
      isActive: json['isActive'] ?? true,
      productCount: json['productCount'] ?? 0,
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
      tags: List<String>.from(json['tags'] ?? []),
      commission: json['commission']?.toDouble(),
      sortOrder: json['sortOrder'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'parentId': parentId,
      'parentName': parentName,
      'level': level,
      'color': color,
      'icon': icon,
      'isActive': isActive,
      'productCount': productCount,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'tags': tags,
      'commission': commission,
      'sortOrder': sortOrder,
    };
  }

  Category copyWith({
    String? id,
    String? name,
    String? description,
    String? parentId,
    String? parentName,
    int? level,
    String? color,
    String? icon,
    bool? isActive,
    int? productCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? tags,
    double? commission,
    int? sortOrder,
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
      isActive: isActive ?? this.isActive,
      productCount: productCount ?? this.productCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tags: tags ?? this.tags,
      commission: commission ?? this.commission,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
