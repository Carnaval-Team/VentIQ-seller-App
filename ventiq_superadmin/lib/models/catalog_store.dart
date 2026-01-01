class CatalogStore {
  final int id;
  final String denominacion;
  final String? direccion;
  final String? ubicacion;
  final DateTime createdAt;
  final String? imagenUrl;
  final String? phone;
  final bool onlyCatalogo;
  final bool validada;
  final bool mostrarEnCatalogo;
  final String? nombrePais;
  final String? nombreEstado;
  final String? provincia;

  CatalogStore({
    required this.id,
    required this.denominacion,
    required this.direccion,
    required this.ubicacion,
    required this.createdAt,
    required this.imagenUrl,
    required this.phone,
    required this.onlyCatalogo,
    required this.validada,
    required this.mostrarEnCatalogo,
    required this.nombrePais,
    required this.nombreEstado,
    required this.provincia,
  });

  factory CatalogStore.fromJson(Map<String, dynamic> json) {
    return CatalogStore(
      id: json['id'],
      denominacion: (json['denominacion'] ?? '').toString(),
      direccion: json['direccion']?.toString(),
      ubicacion: json['ubicacion']?.toString(),
      createdAt: DateTime.parse(json['created_at']),
      imagenUrl: json['imagen_url']?.toString(),
      phone: json['phone']?.toString(),
      onlyCatalogo: (json['only_catalogo'] as bool?) ?? false,
      validada: (json['validada'] as bool?) ?? false,
      mostrarEnCatalogo: (json['mostrar_en_catalogo'] as bool?) ?? false,
      nombrePais: json['nombre_pais']?.toString(),
      nombreEstado: json['nombre_estado']?.toString(),
      provincia: json['provincia']?.toString(),
    );
  }

  CatalogStore copyWith({bool? validada, bool? mostrarEnCatalogo}) {
    return CatalogStore(
      id: id,
      denominacion: denominacion,
      direccion: direccion,
      ubicacion: ubicacion,
      createdAt: createdAt,
      imagenUrl: imagenUrl,
      phone: phone,
      onlyCatalogo: onlyCatalogo,
      validada: validada ?? this.validada,
      mostrarEnCatalogo: mostrarEnCatalogo ?? this.mostrarEnCatalogo,
      nombrePais: nombrePais,
      nombreEstado: nombreEstado,
      provincia: provincia,
    );
  }

  String get ubicacionCompleta {
    final parts = <String>[];

    if ((direccion ?? '').trim().isNotEmpty) parts.add(direccion!.trim());

    final location = (ubicacion ?? '').trim();
    if (location.isNotEmpty) parts.add(location);

    final provinciaLocal = (provincia ?? '').trim();
    if (provinciaLocal.isNotEmpty &&
        !parts.join(', ').contains(provinciaLocal)) {
      parts.add(provinciaLocal);
    }

    final estadoLocal = (nombreEstado ?? '').trim();
    if (estadoLocal.isNotEmpty && !parts.join(', ').contains(estadoLocal)) {
      parts.add(estadoLocal);
    }

    final paisLocal = (nombrePais ?? '').trim();
    if (paisLocal.isNotEmpty && !parts.join(', ').contains(paisLocal)) {
      parts.add(paisLocal);
    }

    if (parts.isEmpty) return 'Sin ubicación';

    return parts.join(', ');
  }
}
