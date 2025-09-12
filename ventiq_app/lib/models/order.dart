import 'product.dart';
import 'payment_method.dart';
import '../utils/price_utils.dart';

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

    // Con promociones, calcular precios según tipo y método de pago
    final valorDescuento = promotionData!['valor_descuento'] as double?;
    final tipoDescuento = promotionData!['tipo_descuento'] as int?;

    final prices = PriceUtils.calculatePromotionPrices(
      precioBase ?? precioUnitario,
      valorDescuento,
      tipoDescuento,
    );

    // Para efectivo (id: 1), usar precio_oferta (el menor)
    // Para otros métodos, usar precio_venta (el mayor)
    if (paymentMethod?.id == 1) {
      return prices['precio_oferta']!;
    } else {
      return prices['precio_venta']!;
    }
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
    }
  }
}
