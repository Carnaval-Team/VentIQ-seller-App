class Promotion {
  final String id;
  final String idTienda;
  final String idTipoPromocion;
  final String nombre;
  final String? descripcion;
  final String codigoPromocion;
  final double valorDescuento;
  final double? minCompra;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final bool estado;
  final bool aplicaTodo;
  final int? limiteUsos;
  final int? usosActuales;
  final DateTime createdAt;
  final PromotionType? tipoPromocion;
  final Store? tienda;
  final List<PromotionProduct> productos;
  final List<PromotionUsage> usos;

  Promotion({
    required this.id,
    required this.idTienda,
    required this.idTipoPromocion,
    required this.nombre,
    this.descripcion,
    required this.codigoPromocion,
    required this.valorDescuento,
    this.minCompra,
    required this.fechaInicio,
    required this.fechaFin,
    this.estado = true,
    this.aplicaTodo = false,
    this.limiteUsos,
    this.usosActuales = 0,
    required this.createdAt,
    this.tipoPromocion,
    this.tienda,
    this.productos = const [],
    this.usos = const [],
  });

  bool get isActive =>
      estado &&
      DateTime.now().isAfter(fechaInicio) &&
      DateTime.now().isBefore(fechaFin);

  bool get hasUsageLimit => limiteUsos != null;

  bool get isUsageLimitReached =>
      hasUsageLimit && (usosActuales ?? 0) >= (limiteUsos ?? 0);

  double get usagePercentage =>
      hasUsageLimit ? ((usosActuales ?? 0) / (limiteUsos ?? 1)) * 100 : 0.0;

  String get statusText {
    if (!estado) return 'Inactiva';
    if (DateTime.now().isBefore(fechaInicio)) return 'Programada';
    if (DateTime.now().isAfter(fechaFin)) return 'Vencida';
    if (isUsageLimitReached) return 'Límite alcanzado';
    return 'Activa';
  }

  factory Promotion.fromJson(Map<String, dynamic> json) {
    return Promotion(
      id: json['id']?.toString() ?? '',
      idTienda: json['id_tienda']?.toString() ?? '',
      idTipoPromocion: json['id_tipo_promocion']?.toString() ?? '',
      nombre: json['nombre'] ?? '',
      descripcion: json['descripcion'],
      codigoPromocion: json['codigo_promocion'] ?? '',
      valorDescuento: (json['valor_descuento'] ?? 0).toDouble(),
      minCompra: json['min_compra']?.toDouble(),
      fechaInicio:
          json['fecha_inicio'] != null
              ? DateTime.parse(json['fecha_inicio'])
              : DateTime.now(),
      fechaFin:
          json['fecha_fin'] != null
              ? DateTime.parse(json['fecha_fin'])
              : DateTime.now().add(const Duration(days: 30)),
      estado: json['estado'] ?? true,
      aplicaTodo: json['aplica_todo'] ?? false,
      limiteUsos: json['limite_usos'],
      usosActuales: json['usos_actuales'] ?? 0,
      createdAt:
          json['created_at'] != null
              ? DateTime.parse(json['created_at'])
              : DateTime.now(),
      tipoPromocion:
          json['tipo_promocion'] != null
              ? PromotionType.fromJson(json['tipo_promocion'])
              : null,
      tienda: json['tienda'] != null ? Store.fromJson(json['tienda']) : null,
      productos:
          (json['productos'] as List<dynamic>?)
              ?.map((p) => PromotionProduct.fromJson(p))
              .toList() ??
          [],
      usos:
          (json['usos'] as List<dynamic>?)
              ?.map((u) => PromotionUsage.fromJson(u))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'id_tienda': idTienda,
      'id_tipo_promocion': idTipoPromocion,
      'nombre': nombre,
      'descripcion': descripcion,
      'codigo_promocion': codigoPromocion,
      'valor_descuento': valorDescuento,
      'min_compra': minCompra,
      'fecha_inicio': fechaInicio.toIso8601String(),
      'fecha_fin': fechaFin.toIso8601String(),
      'estado': estado,
      'aplica_todo': aplicaTodo,
      'limite_usos': limiteUsos,
      'usos_actuales': usosActuales,
      'created_at': createdAt.toIso8601String(),
      'tipo_promocion': tipoPromocion?.toJson(),
      'tienda': tienda?.toJson(),
      'productos': productos.map((p) => p.toJson()).toList(),
      'usos': usos.map((u) => u.toJson()).toList(),
    };
  }

  Promotion copyWith({
    String? id,
    String? idTienda,
    String? idTipoPromocion,
    String? nombre,
    String? descripcion,
    String? codigoPromocion,
    double? valorDescuento,
    double? minCompra,
    DateTime? fechaInicio,
    DateTime? fechaFin,
    bool? estado,
    bool? aplicaTodo,
    int? limiteUsos,
    int? usosActuales,
    DateTime? createdAt,
    PromotionType? tipoPromocion,
    Store? tienda,
    List<PromotionProduct>? productos,
    List<PromotionUsage>? usos,
  }) {
    return Promotion(
      id: id ?? this.id,
      idTienda: idTienda ?? this.idTienda,
      idTipoPromocion: idTipoPromocion ?? this.idTipoPromocion,
      nombre: nombre ?? this.nombre,
      descripcion: descripcion ?? this.descripcion,
      codigoPromocion: codigoPromocion ?? this.codigoPromocion,
      valorDescuento: valorDescuento ?? this.valorDescuento,
      minCompra: minCompra ?? this.minCompra,
      fechaInicio: fechaInicio ?? this.fechaInicio,
      fechaFin: fechaFin ?? this.fechaFin,
      estado: estado ?? this.estado,
      aplicaTodo: aplicaTodo ?? this.aplicaTodo,
      limiteUsos: limiteUsos ?? this.limiteUsos,
      usosActuales: usosActuales ?? this.usosActuales,
      createdAt: createdAt ?? this.createdAt,
      tipoPromocion: tipoPromocion ?? this.tipoPromocion,
      tienda: tienda ?? this.tienda,
      productos: productos ?? this.productos,
      usos: usos ?? this.usos,
    );
  }
}

class PromotionType {
  final String id;
  final String denominacion;
  final String? descripcion;
  final String? icono;
  final DateTime createdAt;

  PromotionType({
    required this.id,
    required this.denominacion,
    this.descripcion,
    this.icono,
    required this.createdAt,
  });

  factory PromotionType.fromJson(Map<String, dynamic> json) {
    return PromotionType(
      id: json['id']?.toString() ?? '',
      denominacion: json['denominacion'] ?? '',
      descripcion: json['descripcion'],
      icono: json['icono'],
      createdAt:
          json['created_at'] != null
              ? DateTime.parse(json['created_at'])
              : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'denominacion': denominacion,
      'descripcion': descripcion,
      'icono': icono,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class PromotionProduct {
  final String id;
  final String idPromocion;
  final String? idProducto;
  final String? idCategoria;
  final String? idSubcategoria;
  final DateTime createdAt;
  final Product? producto;
  final Category? categoria;
  final Subcategory? subcategoria;

  PromotionProduct({
    required this.id,
    required this.idPromocion,
    this.idProducto,
    this.idCategoria,
    this.idSubcategoria,
    required this.createdAt,
    this.producto,
    this.categoria,
    this.subcategoria,
  });

  String get targetName {
    if (producto != null) return producto!.denominacion;
    if (categoria != null) return categoria!.denominacion;
    if (subcategoria != null) return subcategoria!.denominacion;
    return 'Sin especificar';
  }

  String get targetType {
    if (producto != null) return 'Producto';
    if (categoria != null) return 'Categoría';
    if (subcategoria != null) return 'Subcategoría';
    return 'General';
  }

  factory PromotionProduct.fromJson(Map<String, dynamic> json) {
    return PromotionProduct(
      id: json['id']?.toString() ?? '',
      idPromocion: json['id_promocion']?.toString() ?? '',
      idProducto: json['id_producto']?.toString(),
      idCategoria: json['id_categoria']?.toString(),
      idSubcategoria: json['id_subcategoria']?.toString(),
      createdAt:
          json['created_at'] != null
              ? DateTime.parse(json['created_at'])
              : DateTime.now(),
      producto:
          json['producto'] != null ? Product.fromJson(json['producto']) : null,
      categoria:
          json['categoria'] != null
              ? Category.fromJson(json['categoria'])
              : null,
      subcategoria:
          json['subcategoria'] != null
              ? Subcategory.fromJson(json['subcategoria'])
              : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'id_promocion': idPromocion,
      'id_producto': idProducto,
      'id_categoria': idCategoria,
      'id_subcategoria': idSubcategoria,
      'created_at': createdAt.toIso8601String(),
      'producto': producto?.toJson(),
      'categoria': categoria?.toJson(),
      'subcategoria': subcategoria?.toJson(),
    };
  }
}

class PromotionUsage {
  final String id;
  final String idPromocion;
  final String idOperacion;
  final String? idCliente;
  final double descuentoAplicado;
  final DateTime fechaUso;
  final Customer? cliente;

  PromotionUsage({
    required this.id,
    required this.idPromocion,
    required this.idOperacion,
    this.idCliente,
    required this.descuentoAplicado,
    required this.fechaUso,
    this.cliente,
  });

  factory PromotionUsage.fromJson(Map<String, dynamic> json) {
    return PromotionUsage(
      id: json['id']?.toString() ?? '',
      idPromocion: json['id_promocion']?.toString() ?? '',
      idOperacion: json['id_operacion']?.toString() ?? '',
      idCliente: json['id_cliente']?.toString(),
      descuentoAplicado: (json['descuento_aplicado'] ?? 0).toDouble(),
      fechaUso:
          json['fecha_uso'] != null
              ? DateTime.parse(json['fecha_uso'])
              : DateTime.now(),
      cliente:
          json['cliente'] != null ? Customer.fromJson(json['cliente']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'id_promocion': idPromocion,
      'id_operacion': idOperacion,
      'id_cliente': idCliente,
      'descuento_aplicado': descuentoAplicado,
      'fecha_uso': fechaUso.toIso8601String(),
      'cliente': cliente?.toJson(),
    };
  }
}

class PromotionValidationResult {
  final bool valida;
  final String? idPromocion;
  final String? nombre;
  final String? tipo;
  final int? productosValidos;
  final double? subtotal;
  final double? descuentoTotal;
  final double? totalConDescuento;
  final String mensaje;
  final String? tipoDescuento;
  final double? porcentaje;
  final double? monto;
  final double? puntosExtra;
  final double? minimoRequerido;
  final Promotion? promocion;
  final double? descuentoCalculado;

  PromotionValidationResult({
    required this.valida,
    this.idPromocion,
    this.nombre,
    this.tipo,
    this.productosValidos,
    this.subtotal,
    this.descuentoTotal,
    this.totalConDescuento,
    required this.mensaje,
    this.tipoDescuento,
    this.porcentaje,
    this.monto,
    this.puntosExtra,
    this.minimoRequerido,
    this.promocion,
    this.descuentoCalculado,
  });

  factory PromotionValidationResult.fromJson(Map<String, dynamic> json) {
    return PromotionValidationResult(
      valida: json['valida'] ?? false,
      idPromocion: json['id_promocion']?.toString(),
      nombre: json['nombre'],
      tipo: json['tipo'],
      productosValidos: json['productos_validos'],
      subtotal: json['subtotal']?.toDouble(),
      descuentoTotal: json['descuento_total']?.toDouble(),
      totalConDescuento: json['total_con_descuento']?.toDouble(),
      mensaje: json['mensaje'] ?? '',
      tipoDescuento: json['tipo_descuento'],
      porcentaje: json['porcentaje']?.toDouble(),
      monto: json['monto']?.toDouble(),
      puntosExtra: json['puntos_extra']?.toDouble(),
      minimoRequerido: json['minimo_requerido']?.toDouble(),
      promocion:
          json['promocion'] != null
              ? Promotion.fromJson(json['promocion'])
              : null,
      descuentoCalculado: json['descuento_calculado']?.toDouble(),
    );
  }

  PromotionValidationResult copyWith({
    bool? valida,
    String? idPromocion,
    String? nombre,
    String? tipo,
    int? productosValidos,
    double? subtotal,
    double? descuentoTotal,
    double? totalConDescuento,
    String? mensaje,
    String? tipoDescuento,
    double? porcentaje,
    double? monto,
    double? puntosExtra,
    double? minimoRequerido,
    Promotion? promocion,
    double? descuentoCalculado,
  }) {
    return PromotionValidationResult(
      valida: valida ?? this.valida,
      idPromocion: idPromocion ?? this.idPromocion,
      nombre: nombre ?? this.nombre,
      tipo: tipo ?? this.tipo,
      productosValidos: productosValidos ?? this.productosValidos,
      subtotal: subtotal ?? this.subtotal,
      descuentoTotal: descuentoTotal ?? this.descuentoTotal,
      totalConDescuento: totalConDescuento ?? this.totalConDescuento,
      mensaje: mensaje ?? this.mensaje,
      tipoDescuento: tipoDescuento ?? this.tipoDescuento,
      porcentaje: porcentaje ?? this.porcentaje,
      monto: monto ?? this.monto,
      puntosExtra: puntosExtra ?? this.puntosExtra,
      minimoRequerido: minimoRequerido ?? this.minimoRequerido,
      promocion: promocion ?? this.promocion,
      descuentoCalculado: descuentoCalculado ?? this.descuentoCalculado,
    );
  }
}

// Placeholder classes for related models
class Store {
  final String id;
  final String denominacion;

  Store({required this.id, required this.denominacion});

  factory Store.fromJson(Map<String, dynamic> json) {
    return Store(
      id: json['id']?.toString() ?? '',
      denominacion: json['denominacion'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'denominacion': denominacion};
}

class Product {
  final String id;
  final String denominacion;

  Product({required this.id, required this.denominacion});

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id']?.toString() ?? '',
      denominacion: json['denominacion'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'denominacion': denominacion};
}

class Category {
  final String id;
  final String denominacion;

  Category({required this.id, required this.denominacion});

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id']?.toString() ?? '',
      denominacion: json['denominacion'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'denominacion': denominacion};
}

class Subcategory {
  final String id;
  final String denominacion;

  Subcategory({required this.id, required this.denominacion});

  factory Subcategory.fromJson(Map<String, dynamic> json) {
    return Subcategory(
      id: json['id']?.toString() ?? '',
      denominacion: json['denominacion'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'denominacion': denominacion};
}

class Customer {
  final String id;
  final String nombreCompleto;

  Customer({required this.id, required this.nombreCompleto});

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id']?.toString() ?? '',
      nombreCompleto: json['nombre_completo'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'nombre_completo': nombreCompleto,
  };
}
