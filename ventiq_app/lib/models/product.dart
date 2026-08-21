class Product {
  final int id;
  final String denominacion;
  final String? descripcion;
  final String? sku;
  final String? foto;
  final double precio;
  final num cantidad;
  final bool esRefrigerado;
  final bool esFragil;
  final bool esPeligroso;
  final bool esVendible;
  final bool esComprable;
  final bool esInventariable;
  final bool esPorLotes;
  final bool esElaborado;
  final bool esServicio;
  final bool esPaquete;
  final String categoria;
  final List<ProductVariant> variantes;
  final Map<String, dynamic>?
  inventoryMetadata; // Store inventory data for products without variants
  final num reservadoCarnaval;

  // ── Cocina (Fase 1 restaurante/cocina) ─────────────────────────────────
  // Se llenan solo para los productos que vienen de fn_productos_cocina_tpv.
  // Un producto de barra los deja en null y se comporta igual que antes.

  /// Cocina a la que se enruta este plato, si va a alguna.
  final int? idCocina;

  /// Nombre de la cocina, para mostrarlo al vendedor ("Cocina caliente").
  final String? cocina;

  /// Almacén de esa cocina: de ahí sale su materia prima o sus tandas.
  final int? idAlmacenCocina;

  /// Impresora de la estación, si tiene una configurada.
  final String? impresoraCocina;

  /// 'al_pedido' (se cocina al pedirlo) o 'por_tanda' (se sirve de lo hecho).
  final String? modoElaboracion;

  /// True cuando no aplica control de disponibilidad (servicios).
  final bool ilimitado;

  /// Este plato se prepara en una cocina, no se toma de la barra.
  bool get vaACocina => idCocina != null;

  /// Se produce por lotes: la disponibilidad son porciones ya hechas.
  bool get esPorTanda => modoElaboracion == 'por_tanda';

  /// Se cocina en el momento: la disponibilidad la limita la materia prima.
  bool get esAlPedido => vaACocina && modoElaboracion != 'por_tanda';

  /// Texto corto para el chip de la tarjeta, en el lenguaje del vendedor.
  ///
  /// Un mesero entiende "3 porciones" o "Hasta 5", no "stock_disponible: 3".
  String get etiquetaDisponibilidad {
    if (ilimitado) return 'Disponible';
    final n = cantidadReal;
    if (n <= 0) return 'Agotado';
    if (!vaACocina) return _formatearCantidad(n);
    if (esPorTanda) {
      return n == 1 ? '1 porción' : '${_formatearCantidad(n)} porciones';
    }
    return 'Hasta ${_formatearCantidad(n)}';
  }

  static String _formatearCantidad(num n) {
    if (n is int || n == n.roundToDouble()) return n.toInt().toString();
    return n.toStringAsFixed(2);
  }

  /// Stock real descontando reservas de Carnaval
  num get cantidadReal => (cantidad - reservadoCarnaval).clamp(0, double.infinity);

  Product({
    required this.id,
    required this.denominacion,
    this.descripcion,
    this.sku,
    this.foto,
    required this.precio,
    required this.cantidad,
    required this.esRefrigerado,
    required this.esFragil,
    required this.esPeligroso,
    required this.esVendible,
    required this.esComprable,
    required this.esInventariable,
    required this.esPorLotes,
    required this.esElaborado,
    required this.esServicio,
    this.esPaquete = false,
    required this.categoria,
    this.variantes = const [],
    this.inventoryMetadata,
    this.reservadoCarnaval = 0,
    this.idCocina,
    this.cocina,
    this.idAlmacenCocina,
    this.impresoraCocina,
    this.modoElaboracion,
    this.ilimitado = false,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'],
      denominacion: json['denominacion'],
      descripcion: json['descripcion'],
      sku: json['sku'],
      foto: json['foto'],
      precio: json['precio']?.toDouble() ?? 0.0,
      cantidad: json['cantidad'] ?? 0,
      esRefrigerado: json['es_refrigerado'] ?? false,
      esFragil: json['es_fragil'] ?? false,
      esPeligroso: json['es_peligroso'] ?? false,
      esVendible: json['es_vendible'] ?? false,
      esComprable: json['es_comprable'] ?? false,
      esInventariable: json['es_inventariable'] ?? false,
      esPorLotes: json['es_por_lotes'] ?? false,
      esElaborado: json['es_elaborado'] ?? false,
      esServicio: json['es_servicio'] ?? false,
      esPaquete: json['es_paquete'] ?? false,
      categoria: json['categoria'] ?? '',
      variantes:
          (json['variantes'] as List<dynamic>?)
              ?.map((v) => ProductVariant.fromJson(v))
              .toList() ??
          [],
      reservadoCarnaval: json['reservado_carnaval'] ?? 0,
      idCocina: json['id_cocina'] as int?,
      cocina: json['cocina'] as String?,
      idAlmacenCocina: json['id_almacen_cocina'] as int?,
      impresoraCocina: json['impresora'] as String?,
      modoElaboracion: json['modo_elaboracion'] as String?,
      ilimitado: json['ilimitado'] ?? false,
    );
  }

  /// Convertir Product a JSON para persistencia
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'denominacion': denominacion,
      'descripcion': descripcion,
      'sku': sku,
      'foto': foto,
      'precio': precio,
      'cantidad': cantidad,
      'es_refrigerado': esRefrigerado,
      'es_fragil': esFragil,
      'es_peligroso': esPeligroso,
      'es_vendible': esVendible,
      'es_comprable': esComprable,
      'es_inventariable': esInventariable,
      'es_por_lotes': esPorLotes,
      'es_elaborado': esElaborado,
      'es_servicio': esServicio,
      'es_paquete': esPaquete,
      'categoria': categoria,
      'variantes': variantes.map((v) => v.toJson()).toList(),
      'inventoryMetadata': inventoryMetadata,
      'reservado_carnaval': reservadoCarnaval,
      // Cocina: se persisten para que el modo offline conserve el enrutamiento.
      'id_cocina': idCocina,
      'cocina': cocina,
      'id_almacen_cocina': idAlmacenCocina,
      'impresora': impresoraCocina,
      'modo_elaboracion': modoElaboracion,
      'ilimitado': ilimitado,
    };
  }
}

class ProductVariant {
  final int id;
  final String nombre;
  final double precio;
  final num cantidad;
  final String? descripcion;
  final Map<String, dynamic>?
  inventoryMetadata; // Store inventory data for this specific variant
  final num reservadoCarnaval;

  /// Stock real descontando reservas de Carnaval
  num get cantidadReal => (cantidad - reservadoCarnaval).clamp(0, double.infinity);

  ProductVariant({
    required this.id,
    required this.nombre,
    required this.precio,
    required this.cantidad,
    this.descripcion,
    this.inventoryMetadata,
    this.reservadoCarnaval = 0,
  });

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    return ProductVariant(
      id: json['id'],
      nombre: json['nombre'],
      precio: json['precio']?.toDouble() ?? 0.0,
      cantidad: json['cantidad'] ?? 0,
      descripcion: json['descripcion'],
      reservadoCarnaval: json['reservado_carnaval'] ?? 0,
    );
  }

  /// Convertir ProductVariant a JSON para persistencia
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'precio': precio,
      'cantidad': cantidad,
      'descripcion': descripcion,
      'inventoryMetadata': inventoryMetadata,
      'reservado_carnaval': reservadoCarnaval,
    };
  }
}

class Presentation {
  final int id;
  final String denominacion;
  final String? descripcion;
  final String skuCodigo;
  final bool esFraccionable;

  Presentation({
    required this.id,
    required this.denominacion,
    this.descripcion,
    required this.skuCodigo,
    this.esFraccionable = false,
  });

  factory Presentation.fromJson(Map<String, dynamic> json) {
    return Presentation(
      id: json['id'],
      denominacion: json['denominacion'],
      descripcion: json['descripcion'],
      skuCodigo: json['sku_codigo'],
      esFraccionable: json['es_fraccionable'] ?? false,
    );
  }
}

class ProductPresentation {
  final int id;
  final int idProducto;
  final int idPresentacion;
  final double cantidad;
  final bool esBase;
  final Presentation presentacion;

  ProductPresentation({
    required this.id,
    required this.idProducto,
    required this.idPresentacion,
    required this.cantidad,
    required this.esBase,
    required this.presentacion,
  });

  factory ProductPresentation.fromJson(Map<String, dynamic> json) {
    final presentacionRaw = json['presentacion'];
    final presentacion = presentacionRaw is Map
        ? Presentation.fromJson(Map<String, dynamic>.from(presentacionRaw))
        : Presentation(
            id: json['id_presentacion'] is num
                ? (json['id_presentacion'] as num).toInt()
                : 0,
            denominacion: 'Unidad',
            descripcion: null,
            skuCodigo: '',
          );

    return ProductPresentation(
      id: json['id'],
      idProducto: json['id_producto'],
      idPresentacion: json['id_presentacion'],
      cantidad: (json['cantidad'] as num?)?.toDouble() ?? 1.0,
      esBase: json['es_base'] ?? false,
      presentacion: presentacion,
    );
  }
}
