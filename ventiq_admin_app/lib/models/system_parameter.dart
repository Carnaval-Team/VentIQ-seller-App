class SystemParameter {
  final String id;
  final String key;
  final String name;
  final String description;
  final String value;
  final String type; // 'string', 'number', 'boolean', 'json'
  final String category;
  final bool isEditable;
  final bool isRequired;
  final String? validationRule;
  final DateTime createdAt;
  final DateTime? lastUpdated;

  SystemParameter({
    required this.id,
    required this.key,
    required this.name,
    required this.description,
    required this.value,
    required this.type,
    required this.category,
    this.isEditable = true,
    this.isRequired = false,
    this.validationRule,
    required this.createdAt,
    this.lastUpdated,
  });

  factory SystemParameter.fromJson(Map<String, dynamic> json) {
    return SystemParameter(
      id: json['id'] ?? '',
      key: json['key'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      value: json['value'] ?? '',
      type: json['type'] ?? 'string',
      category: json['category'] ?? 'general',
      isEditable: json['isEditable'] ?? true,
      isRequired: json['isRequired'] ?? false,
      validationRule: json['validationRule'],
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      lastUpdated: json['lastUpdated'] != null ? DateTime.parse(json['lastUpdated']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'key': key,
      'name': name,
      'description': description,
      'value': value,
      'type': type,
      'category': category,
      'isEditable': isEditable,
      'isRequired': isRequired,
      'validationRule': validationRule,
      'createdAt': createdAt.toIso8601String(),
      'lastUpdated': lastUpdated?.toIso8601String(),
    };
  }

  SystemParameter copyWith({
    String? id,
    String? key,
    String? name,
    String? description,
    String? value,
    String? type,
    String? category,
    bool? isEditable,
    bool? isRequired,
    String? validationRule,
    DateTime? createdAt,
    DateTime? lastUpdated,
  }) {
    return SystemParameter(
      id: id ?? this.id,
      key: key ?? this.key,
      name: name ?? this.name,
      description: description ?? this.description,
      value: value ?? this.value,
      type: type ?? this.type,
      category: category ?? this.category,
      isEditable: isEditable ?? this.isEditable,
      isRequired: isRequired ?? this.isRequired,
      validationRule: validationRule ?? this.validationRule,
      createdAt: createdAt ?? this.createdAt,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}
