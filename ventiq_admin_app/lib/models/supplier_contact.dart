class SupplierContact {
  final int id;
  final int supplierId;
  final String nombre;
  final String? telefono;
  final String? email;
  final String? cargo;
  final bool isPrimary;
  final DateTime createdAt;
  final bool isActive;
  
  SupplierContact({
    required this.id,
    required this.supplierId,
    required this.nombre,
    this.telefono,
    this.email,
    this.cargo,
    this.isPrimary = false,
    required this.createdAt,
    this.isActive = true,
  });
  
  factory SupplierContact.fromJson(Map<String, dynamic> json) {
    return SupplierContact(
      id: json['id'] ?? 0,
      supplierId: json['supplier_id'] ?? json['id_proveedor'] ?? 0,
      nombre: json['nombre'] ?? '',
      telefono: json['telefono'],
      email: json['email'],
      cargo: json['cargo'],
      isPrimary: json['is_primary'] ?? json['es_principal'] ?? false,
      createdAt: DateTime.parse(
        json['created_at'] ?? DateTime.now().toIso8601String(),
      ),
      isActive: json['is_active'] ?? json['es_activo'] ?? true,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'supplier_id': supplierId,
      'nombre': nombre,
      'telefono': telefono,
      'email': email,
      'cargo': cargo,
      'is_primary': isPrimary,
      'created_at': createdAt.toIso8601String(),
      'is_active': isActive,
    };
  }
  
  Map<String, dynamic> toInsertJson() {
    return {
      'supplier_id': supplierId,
      'nombre': nombre,
      'telefono': telefono,
      'email': email,
      'cargo': cargo,
      'is_primary': isPrimary,
    };
  }
  
  // Helper methods
  String get displayName => nombre;
  
  String get fullContactInfo {
    final parts = <String>[];
    if (cargo != null && cargo!.isNotEmpty) parts.add(cargo!);
    if (telefono != null && telefono!.isNotEmpty) parts.add(telefono!);
    if (email != null && email!.isNotEmpty) parts.add(email!);
    return parts.join(' • ');
  }
  
  String get contactMethods {
    final methods = <String>[];
    if (telefono != null && telefono!.isNotEmpty) methods.add('Teléfono');
    if (email != null && email!.isNotEmpty) methods.add('Email');
    return methods.join(', ');
  }
  
  bool get hasPhone => telefono != null && telefono!.isNotEmpty;
  bool get hasEmail => email != null && email!.isNotEmpty;
  bool get hasPosition => cargo != null && cargo!.isNotEmpty;
  
  String get primaryLabel => isPrimary ? 'Contacto Principal' : 'Contacto';
  
  @override
  String toString() => 'SupplierContact(id: $id, nombre: $nombre)';
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupplierContact &&
          runtimeType == other.runtimeType &&
          id == other.id;
  
  @override
  int get hashCode => id.hashCode;
  
  // Copy with method for updates
  SupplierContact copyWith({
    int? id,
    int? supplierId,
    String? nombre,
    String? telefono,
    String? email,
    String? cargo,
    bool? isPrimary,
    DateTime? createdAt,
    bool? isActive,
  }) {
    return SupplierContact(
      id: id ?? this.id,
      supplierId: supplierId ?? this.supplierId,
      nombre: nombre ?? this.nombre,
      telefono: telefono ?? this.telefono,
      email: email ?? this.email,
      cargo: cargo ?? this.cargo,
      isPrimary: isPrimary ?? this.isPrimary,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
    );
  }
}
