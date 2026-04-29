class ValoracionModel {
  final int id;
  final int viajeId;
  final int driverId;
  final String userId;
  final int rating;
  final String? comentario;
  final DateTime createdAt;
  final String? userName;

  ValoracionModel({
    required this.id,
    required this.viajeId,
    required this.driverId,
    required this.userId,
    required this.rating,
    this.comentario,
    required this.createdAt,
    this.userName,
  });

  factory ValoracionModel.fromJson(Map<String, dynamic> json) {
    return ValoracionModel(
      id: json['id'] as int,
      viajeId: json['viaje_id'] as int,
      driverId: json['driver_id'] as int,
      userId: json['user_id'] as String,
      rating: json['rating'] as int,
      comentario: json['comentario'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      userName: json['user_name'] as String?,
    );
  }
}
