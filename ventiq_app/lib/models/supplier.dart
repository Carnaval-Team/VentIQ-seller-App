class Supplier {
  final int id;
  final String nombre;
  final int idTienda;

  Supplier({
    required this.id,
    required this.nombre,
    required this.idTienda,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) {
    return Supplier(
      id: json['id'] as int,
      nombre: json['denominacion'] as String? ?? '',
      idTienda: json['idtienda'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'denominacion': nombre,
      'idtienda': idTienda,
    };
  }

  @override
  String toString() => 'Supplier(id: $id, nombre: $nombre, idTienda: $idTienda)';
}
