import 'product.dart';
import 'payment_method.dart';
import '../utils/price_utils.dart';
import '../utils/promotion_rules.dart';

class Order {
  final String id;
  final DateTime fechaCreacion;
  final List<OrderItem> items;
  final double total;
  final OrderStatus status;
  final String? notas;
  final String? buyerName;
  final String? buyerPhone;
  final String? extraContacts;
  final String? paymentMethod;
  final int? operationId;
  final List<dynamic>? pagos; // Lista de pagos de la orden
  final Map<String, dynamic>? descuento; // Descuento aplicado (si existe)
  bool isOfflineOrder; // Campo para marcar órdenes offline

  Order({
    required this.id,
    required this.fechaCreacion,
    required this.items,
    required this.total,
    required this.status,
    this.notas,
    this.buyerName,
    this.buyerPhone,
    this.extraContacts,
    this.paymentMethod,
    this.operationId,
    this.pagos,
    this.descuento,
    this.isOfflineOrder = false, // Por defecto false
  });

  double get subtotal {
    return items.fold(0.0, (sum, item) => sum + item.subtotal);
  }

  int get totalItems {
    return items.fold(0, (sum, item) => sum + item.cantidad);
  }

  Order copyWith({
    String? id,
    DateTime? fechaCreacion,
    List<OrderItem>? items,
    double? total,
    OrderStatus? status,
    String? notas,
    String? buyerName,
    String? buyerPhone,
    String? extraContacts,
    String? paymentMethod,
    int? operationId,
    List<dynamic>? pagos,
    Map<String, dynamic>? descuento,
    bool? isOfflineOrder,
  }) {
    return Order(
      id: id ?? this.id,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
      items: items ?? this.items,
      total: total ?? this.total,
      status: status ?? this.status,
      notas: notas ?? this.notas,
      buyerName: buyerName ?? this.buyerName,
      buyerPhone: buyerPhone ?? this.buyerPhone,
      extraContacts: extraContacts ?? this.extraContacts,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      operationId: operationId ?? this.operationId,
      pagos: pagos ?? this.pagos,
      descuento: descuento ?? this.descuento,
      isOfflineOrder: isOfflineOrder ?? this.isOfflineOrder,
    );
  }

  /// Convertir Order a JSON para persistencia
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fechaCreacion': fechaCreacion.toIso8601String(),
      'items': items.map((item) => item.toJson()).toList(),
      'total': total,
      'status': status.index,
      'notas': notas,
      'buyerName': buyerName,
      'buyerPhone': buyerPhone,
      'extraContacts': extraContacts,
      'paymentMethod': paymentMethod,
      'operationId': operationId,
      'pagos': pagos,
      'descuento': descuento,
      'isOfflineOrder': isOfflineOrder,
    };
  }

  /// Crear Order desde JSON para persistencia
  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['id'] as String,
      fechaCreacion: DateTime.parse(json['fechaCreacion'] as String),
      items:
          (json['items'] as List<dynamic>)
              .map(
                (itemJson) =>
                    OrderItem.fromJson(itemJson as Map<String, dynamic>),
              )
              .toList(),
      total: (json['total'] as num).toDouble(),
      status: OrderStatus.values[json['status'] as int],
      notas: json['notas'] as String?,
      buyerName: json['buyerName'] as String?,
      buyerPhone: json['buyerPhone'] as String?,
      extraContacts: json['extraContacts'] as String?,
      paymentMethod: json['paymentMethod'] as String?,
      operationId: json['operationId'] as int?,
      pagos: json['pagos'] as List<dynamic>?,
      descuento: json['descuento'] as Map<String, dynamic>?,
      isOfflineOrder: json['isOfflineOrder'] as bool? ?? false,
    );
  }
}

class OrderItem {
  final String id;
  final Product producto;
  final ProductVariant? variante;
  final int cantidad;
  final double precioUnitario;
  final double? precioBase;
  final String ubicacionAlmacen;
  final Map<String, dynamic>? inventoryData;
  final PaymentMethod? paymentMethod;
  final Map<String, dynamic>? promotionData;
  // Nuevos campos para inventario
  final double? cantidadInicial;
  final double? cantidadFinal;
  // Campo para entradas del producto
  final double? entradasProducto;
  // Campo para ingredientes de productos elaborados
  final List<dynamic>? ingredientes;

  OrderItem({
    required this.id,
    required this.producto,
    this.variante,
    required this.cantidad,
    required this.precioUnitario,
    this.precioBase,
    required this.ubicacionAlmacen,
    this.inventoryData,
    this.paymentMethod,
    this.promotionData,
    this.cantidadInicial,
    this.cantidadFinal,
    this.entradasProducto,
    this.ingredientes,
  });

  double get subtotal {
    return _getFinalPrice() * cantidad;
  }

  double get displayPrice {
    return _getFinalPrice();
  }

  double _getFinalPrice() {
    // Si no hay datos de promoción, usar lógica original
    if (promotionData == null) {
      if (paymentMethod?.id == 1) {
        return precioUnitario; // Precio con descuento para efectivo
      } else {
        return precioBase ?? precioUnitario; // Precio base para otros métodos
      }
    }

    if (!PromotionRules.isPaymentMethodCompatible(
      promotionData!,
      paymentMethod?.id,
    )) {
      if (paymentMethod?.id == 1) {
        return precioUnitario;
      }
      return precioBase ?? precioUnitario;
    }

    // Con promociones, calcular precios según tipo y método de pago
    final valorDescuento = promotionData!['valor_descuento'] as double?;
    final tipoDescuento = promotionData!['tipo_descuento'] as int?;

    final basePrice = PromotionRules.resolveBasePrice(
      unitPrice: precioUnitario,
      basePrice: precioBase,
      promotion: promotionData,
    );

    final prices = PriceUtils.calculatePromotionPrices(
      basePrice,
      valorDescuento,
      tipoDescuento,
    );

    // Para efectivo (id: 1), usar precio_oferta (el menor)
    // Para otros métodos, usar precio_venta (el mayor)
    return PromotionRules.selectPriceForPayment(
      prices: prices,
      paymentMethodId: paymentMethod?.id,
    );
  }

  String get nombre {
    if (variante != null) {
      return '${producto.denominacion} - ${variante!.nombre}';
    }
    return producto.denominacion;
  }

  OrderItem copyWith({
    String? id,
    Product? producto,
    ProductVariant? variante,
    int? cantidad,
    double? precioUnitario,
    double? precioBase,
    String? ubicacionAlmacen,
    Map<String, dynamic>? inventoryData,
    PaymentMethod? paymentMethod,
    Map<String, dynamic>? promotionData,
    double? cantidadInicial,
    double? cantidadFinal,
    double? entradasProducto,
    List<dynamic>? ingredientes,
  }) {
    return OrderItem(
      id: id ?? this.id,
      producto: producto ?? this.producto,
      variante: variante ?? this.variante,
      cantidad: cantidad ?? this.cantidad,
      precioUnitario: precioUnitario ?? this.precioUnitario,
      precioBase: precioBase ?? this.precioBase,
      ubicacionAlmacen: ubicacionAlmacen ?? this.ubicacionAlmacen,
      inventoryData: inventoryData ?? this.inventoryData,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      promotionData: promotionData ?? this.promotionData,
      cantidadInicial: cantidadInicial ?? this.cantidadInicial,
      cantidadFinal: cantidadFinal ?? this.cantidadFinal,
      entradasProducto: entradasProducto ?? this.entradasProducto,
      ingredientes: ingredientes ?? this.ingredientes,
    );
  }

  /// Convertir OrderItem a JSON para persistencia
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'producto': producto.toJson(),
      'variante': variante?.toJson(),
      'cantidad': cantidad,
      'precioUnitario': precioUnitario,
      'precioBase': precioBase,
      'ubicacionAlmacen': ubicacionAlmacen,
      'inventoryData': inventoryData,
      'paymentMethod': paymentMethod?.toJson(),
      'promotionData': promotionData,
      'cantidadInicial': cantidadInicial,
      'cantidadFinal': cantidadFinal,
      'entradasProducto': entradasProducto,
      'ingredientes': ingredientes,
    };
  }

  /// Crear OrderItem desde JSON para persistencia
  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      id: json['id'] as String,
      producto: Product.fromJson(json['producto'] as Map<String, dynamic>),
      variante:
          json['variante'] != null
              ? ProductVariant.fromJson(
                json['variante'] as Map<String, dynamic>,
              )
              : null,
      cantidad: json['cantidad'] as int,
      precioUnitario: (json['precioUnitario'] as num).toDouble(),
      precioBase:
          json['precioBase'] != null
              ? (json['precioBase'] as num).toDouble()
              : null,
      ubicacionAlmacen: json['ubicacionAlmacen'] as String,
      inventoryData: json['inventoryData'] as Map<String, dynamic>?,
      paymentMethod:
          json['paymentMethod'] != null
              ? PaymentMethod.fromJson(
                json['paymentMethod'] as Map<String, dynamic>,
              )
              : null,
      promotionData: json['promotionData'] as Map<String, dynamic>?,
      cantidadInicial:
          json['cantidadInicial'] != null
              ? (json['cantidadInicial'] as num).toDouble()
              : null,
      cantidadFinal:
          json['cantidadFinal'] != null
              ? (json['cantidadFinal'] as num).toDouble()
              : null,
      entradasProducto:
          json['entradasProducto'] != null
              ? (json['entradasProducto'] as num).toDouble()
              : null,
      ingredientes: json['ingredientes'] as List<dynamic>?,
    );
  }
}

enum OrderStatus {
  borrador,
  enviada,
  procesando,
  completada,
  cancelada,
  devuelta,
  pagoConfirmado,
  pendienteDeSincronizacion, // Para órdenes creadas offline
}

extension OrderStatusExtension on OrderStatus {
  String get displayName {
    switch (this) {
      case OrderStatus.borrador:
        return 'Borrador';
      case OrderStatus.enviada:
        return 'Pendiente';
      case OrderStatus.procesando:
        return 'Procesando';
      case OrderStatus.completada:
        return 'Completada';
      case OrderStatus.cancelada:
        return 'Cancelada';
      case OrderStatus.devuelta:
        return 'Devuelta';
      case OrderStatus.pagoConfirmado:
        return 'Pago Confirmado';
      case OrderStatus.pendienteDeSincronizacion:
        return 'Pendiente Sincronización';
    }
  }

  String get displayColor {
    switch (this) {
      case OrderStatus.borrador:
        return '#FFA500'; // Naranja
      case OrderStatus.enviada:
        return '#4A90E2'; // Azul
      case OrderStatus.procesando:
        return '#FFD700'; // Dorado
      case OrderStatus.completada:
        return '#28A745'; // Verde
      case OrderStatus.cancelada:
        return '#DC3545'; // Rojo
      case OrderStatus.devuelta:
        return '#FF6B35'; // Naranja rojizo
      case OrderStatus.pagoConfirmado:
        return '#10B981'; // Verde esmeralda
      case OrderStatus.pendienteDeSincronizacion:
        return '#FF8C00'; // Naranja oscuro para órdenes offline
    }
  }
}
