class Integration {
  final String id;
  final String name;
  final String type; // 'payment', 'shipping', 'accounting', 'crm', 'inventory'
  final String provider;
  final String description;
  final bool isActive;
  final bool isConfigured;
  final Map<String, dynamic> config;
  final Map<String, String> credentials;
  final String status; // 'connected', 'disconnected', 'error', 'pending'
  final DateTime? lastSync;
  final String? lastError;
  final DateTime createdAt;
  final DateTime? lastUpdated;

  Integration({
    required this.id,
    required this.name,
    required this.type,
    required this.provider,
    required this.description,
    this.isActive = false,
    this.isConfigured = false,
    required this.config,
    required this.credentials,
    this.status = 'disconnected',
    this.lastSync,
    this.lastError,
    required this.createdAt,
    this.lastUpdated,
  });

  factory Integration.fromJson(Map<String, dynamic> json) {
    return Integration(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      type: json['type'] ?? '',
      provider: json['provider'] ?? '',
      description: json['description'] ?? '',
      isActive: json['isActive'] ?? false,
      isConfigured: json['isConfigured'] ?? false,
      config: Map<String, dynamic>.from(json['config'] ?? {}),
      credentials: Map<String, String>.from(json['credentials'] ?? {}),
      status: json['status'] ?? 'disconnected',
      lastSync: json['lastSync'] != null ? DateTime.parse(json['lastSync']) : null,
      lastError: json['lastError'],
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      lastUpdated: json['lastUpdated'] != null ? DateTime.parse(json['lastUpdated']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'provider': provider,
      'description': description,
      'isActive': isActive,
      'isConfigured': isConfigured,
      'config': config,
      'credentials': credentials,
      'status': status,
      'lastSync': lastSync?.toIso8601String(),
      'lastError': lastError,
      'createdAt': createdAt.toIso8601String(),
      'lastUpdated': lastUpdated?.toIso8601String(),
    };
  }

  Integration copyWith({
    String? id,
    String? name,
    String? type,
    String? provider,
    String? description,
    bool? isActive,
    bool? isConfigured,
    Map<String, dynamic>? config,
    Map<String, String>? credentials,
    String? status,
    DateTime? lastSync,
    String? lastError,
    DateTime? createdAt,
    DateTime? lastUpdated,
  }) {
    return Integration(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      provider: provider ?? this.provider,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      isConfigured: isConfigured ?? this.isConfigured,
      config: config ?? this.config,
      credentials: credentials ?? this.credentials,
      status: status ?? this.status,
      lastSync: lastSync ?? this.lastSync,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}
