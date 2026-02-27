class SavedAddressModel {
  final int id;
  final String userId;
  final String label;
  final String icon; // icon name hint: 'home', 'work', 'place', etc.
  final String direccion;
  final double latitud;
  final double longitud;
  final DateTime createdAt;

  const SavedAddressModel({
    required this.id,
    required this.userId,
    required this.label,
    required this.icon,
    required this.direccion,
    required this.latitud,
    required this.longitud,
    required this.createdAt,
  });

  factory SavedAddressModel.fromJson(Map<String, dynamic> json) {
    return SavedAddressModel(
      id: json['id'] as int,
      userId: json['user_id'] as String,
      label: json['label'] as String,
      icon: json['icon'] as String? ?? 'place',
      direccion: json['direccion'] as String,
      latitud: (json['latitud'] as num).toDouble(),
      longitud: (json['longitud'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'label': label,
        'icon': icon,
        'direccion': direccion,
        'latitud': latitud,
        'longitud': longitud,
      };

  SavedAddressModel copyWith({
    int? id,
    String? userId,
    String? label,
    String? icon,
    String? direccion,
    double? latitud,
    double? longitud,
    DateTime? createdAt,
  }) {
    return SavedAddressModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      label: label ?? this.label,
      icon: icon ?? this.icon,
      direccion: direccion ?? this.direccion,
      latitud: latitud ?? this.latitud,
      longitud: longitud ?? this.longitud,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
