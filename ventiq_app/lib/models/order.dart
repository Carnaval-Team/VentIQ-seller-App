import 'product.dart';

class Order {
  final String id;
  final DateTime fechaCreacion;
  final List<OrderItem> items;
  final double total;
  final OrderStatus status;
  final String? notas;

  Order({
    required this.id,
    required this.fechaCreacion,
    required this.items,
    required this.total,
    required this.status,
    this.notas,
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
  }) {
    return Order(
      id: id ?? this.id,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
      items: items ?? this.items,
      total: total ?? this.total,
      status: status ?? this.status,
      notas: notas ?? this.notas,
    );
  }
}

class OrderItem {
  final String id;
  final Product producto;
  final ProductVariant? variante;
  final int cantidad;
  final double precioUnitario;
  final String ubicacionAlmacen;

  OrderItem({
    required this.id,
    required this.producto,
    this.variante,
    required this.cantidad,
    required this.precioUnitario,
    required this.ubicacionAlmacen,
  });

  double get subtotal => precioUnitario * cantidad;

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
    String? ubicacionAlmacen,
  }) {
    return OrderItem(
      id: id ?? this.id,
      producto: producto ?? this.producto,
      variante: variante ?? this.variante,
      cantidad: cantidad ?? this.cantidad,
      precioUnitario: precioUnitario ?? this.precioUnitario,
      ubicacionAlmacen: ubicacionAlmacen ?? this.ubicacionAlmacen,
    );
  }
}

enum OrderStatus {
  borrador,
  enviada,
  procesando,
  completada,
  cancelada,
}

extension OrderStatusExtension on OrderStatus {
  String get displayName {
    switch (this) {
      case OrderStatus.borrador:
        return 'Borrador';
      case OrderStatus.enviada:
        return 'Enviada';
      case OrderStatus.procesando:
        return 'Procesando';
      case OrderStatus.completada:
        return 'Completada';
      case OrderStatus.cancelada:
        return 'Cancelada';
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
    }
  }
}
