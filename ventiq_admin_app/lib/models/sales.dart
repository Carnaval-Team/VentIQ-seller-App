class Sale {
  final String id;
  final String orderId;
  final String customerId;
  final String customerName;
  final String tpvId;
  final String tpvName;
  final String sellerId;
  final String sellerName;
  final DateTime saleDate;
  final String paymentMethod;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final String status; // completada, cancelada, devuelta
  final List<SaleItem> items;

  Sale({
    required this.id,
    required this.orderId,
    required this.customerId,
    required this.customerName,
    required this.tpvId,
    required this.tpvName,
    required this.sellerId,
    required this.sellerName,
    required this.saleDate,
    required this.paymentMethod,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.status,
    this.items = const [],
  });

  factory Sale.fromJson(Map<String, dynamic> json) {
    return Sale(
      id: json['id'] ?? '',
      orderId: json['orderId'] ?? '',
      customerId: json['customerId'] ?? '',
      customerName: json['customerName'] ?? '',
      tpvId: json['tpvId'] ?? '',
      tpvName: json['tpvName'] ?? '',
      sellerId: json['sellerId'] ?? '',
      sellerName: json['sellerName'] ?? '',
      saleDate: DateTime.parse(json['saleDate'] ?? DateTime.now().toIso8601String()),
      paymentMethod: json['paymentMethod'] ?? '',
      subtotal: (json['subtotal'] ?? 0.0).toDouble(),
      discount: (json['discount'] ?? 0.0).toDouble(),
      tax: (json['tax'] ?? 0.0).toDouble(),
      total: (json['total'] ?? 0.0).toDouble(),
      status: json['status'] ?? 'completada',
      items: (json['items'] as List<dynamic>?)
          ?.map((i) => SaleItem.fromJson(i))
          .toList() ?? [],
    );
  }
}

class SaleItem {
  final String id;
  final String saleId;
  final String productId;
  final String variantId;
  final String productName;
  final String variantName;
  final int quantity;
  final double unitPrice;
  final double totalPrice;

  SaleItem({
    required this.id,
    required this.saleId,
    required this.productId,
    required this.variantId,
    required this.productName,
    required this.variantName,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
  });

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    return SaleItem(
      id: json['id'] ?? '',
      saleId: json['saleId'] ?? '',
      productId: json['productId'] ?? '',
      variantId: json['variantId'] ?? '',
      productName: json['productName'] ?? '',
      variantName: json['variantName'] ?? '',
      quantity: json['quantity'] ?? 0,
      unitPrice: (json['unitPrice'] ?? 0.0).toDouble(),
      totalPrice: (json['totalPrice'] ?? 0.0).toDouble(),
    );
  }
}

class TPV {
  final String id;
  final String name;
  final String code;
  final String storeId;
  final String storeName;
  final String location;
  final bool isActive;
  final String status; // activo, inactivo, mantenimiento
  final DateTime lastActivity;
  final String? assignedUserId;
  final String? assignedUserName;

  TPV({
    required this.id,
    required this.name,
    required this.code,
    required this.storeId,
    required this.storeName,
    required this.location,
    this.isActive = true,
    required this.status,
    required this.lastActivity,
    this.assignedUserId,
    this.assignedUserName,
  });

  factory TPV.fromJson(Map<String, dynamic> json) {
    return TPV(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      code: json['code'] ?? '',
      storeId: json['storeId'] ?? '',
      storeName: json['storeName'] ?? '',
      location: json['location'] ?? '',
      isActive: json['isActive'] ?? true,
      status: json['status'] ?? 'activo',
      lastActivity: DateTime.parse(json['lastActivity'] ?? DateTime.now().toIso8601String()),
      assignedUserId: json['assignedUserId'],
      assignedUserName: json['assignedUserName'],
    );
  }
}

class CashDelivery {
  final int id;
  final double montoEntrega;
  final String motivoEntrega;
  final String nombreRecibe;
  final String nombreAutoriza;
  final DateTime fechaEntrega;
  final int estado;
  final int idTurno;
  final String creadoPor;

  CashDelivery({
    required this.id,
    required this.montoEntrega,
    required this.motivoEntrega,
    required this.nombreRecibe,
    required this.nombreAutoriza,
    required this.fechaEntrega,
    required this.estado,
    required this.idTurno,
    required this.creadoPor,
  });

  factory CashDelivery.fromJson(Map<String, dynamic> json) {
    return CashDelivery(
      id: json['id'] ?? 0,
      montoEntrega: (json['monto_entrega'] ?? 0.0).toDouble(),
      motivoEntrega: json['motivo_entrega'] ?? '',
      nombreRecibe: json['nombre_recibe'] ?? '',
      nombreAutoriza: json['nombre_autoriza'] ?? '',
      fechaEntrega: DateTime.parse(json['fecha_entrega'] ?? DateTime.now().toIso8601String()),
      estado: json['estado'] ?? 1,
      idTurno: json['id_turno'] ?? 0,
      creadoPor: json['creado_por'] ?? '',
    );
  }
}

class SalesVendorReport {
  final String uuidUsuario;
  final String nombres;
  final String apellidos;
  final String nombreCompleto;
  final int totalVentas;
  final double totalProductosVendidos;
  final double totalDineroEfectivo;
  final double totalDineroTransferencia;
  final double totalDineroGeneral;
  final double totalImporteVentas;
  final int productosDiferentesVendidos;
  final DateTime primeraVenta;
  final DateTime ultimaVenta;
  final double totalEgresos;

  SalesVendorReport({
    required this.uuidUsuario,
    required this.nombres,
    required this.apellidos,
    required this.nombreCompleto,
    required this.totalVentas,
    required this.totalProductosVendidos,
    required this.totalDineroEfectivo,
    required this.totalDineroTransferencia,
    required this.totalDineroGeneral,
    required this.totalImporteVentas,
    required this.productosDiferentesVendidos,
    required this.primeraVenta,
    required this.ultimaVenta,
    this.totalEgresos = 0.0,
  });

  factory SalesVendorReport.fromJson(Map<String, dynamic> json) {
    return SalesVendorReport(
      uuidUsuario: json['uuid_usuario'] ?? '',
      nombres: json['nombres'] ?? '',
      apellidos: json['apellidos'] ?? '',
      nombreCompleto: json['nombre_completo'] ?? '',
      totalVentas: json['total_ventas'] ?? 0,
      totalProductosVendidos: (json['total_productos_vendidos'] ?? 0.0).toDouble(),
      totalDineroEfectivo: (json['total_dinero_efectivo'] ?? 0.0).toDouble(),
      totalDineroTransferencia: (json['total_dinero_transferencia'] ?? 0.0).toDouble(),
      totalDineroGeneral: (json['total_dinero_general'] ?? 0.0).toDouble(),
      totalImporteVentas: (json['total_importe_ventas'] ?? 0.0).toDouble(),
      productosDiferentesVendidos: json['productos_diferentes_vendidos'] ?? 0,
      primeraVenta: DateTime.parse(json['primera_venta'] ?? DateTime.now().toIso8601String()),
      ultimaVenta: DateTime.parse(json['ultima_venta'] ?? DateTime.now().toIso8601String()),
      totalEgresos: (json['total_egresos'] ?? 0.0).toDouble(),
    );
  }

  // Helper method to create a copy with updated egresos
  SalesVendorReport copyWith({double? totalEgresos}) {
    return SalesVendorReport(
      uuidUsuario: uuidUsuario,
      nombres: nombres,
      apellidos: apellidos,
      nombreCompleto: nombreCompleto,
      totalVentas: totalVentas,
      totalProductosVendidos: totalProductosVendidos,
      totalDineroEfectivo: totalDineroEfectivo,
      totalDineroTransferencia: totalDineroTransferencia,
      totalDineroGeneral: totalDineroGeneral,
      totalImporteVentas: totalImporteVentas,
      productosDiferentesVendidos: productosDiferentesVendidos,
      primeraVenta: primeraVenta,
      ultimaVenta: ultimaVenta,
      totalEgresos: totalEgresos ?? this.totalEgresos,
    );
  }

  // Helper method to determine if vendor is active (has sales today)
  bool get isActiveToday {
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    return ultimaVenta.isAfter(todayStart);
  }

  // Helper method to get status based on activity
  String get status {
    if (isActiveToday) {
      return 'activo';
    } else if (ultimaVenta.isAfter(DateTime.now().subtract(const Duration(days: 7)))) {
      return 'reciente';
    } else {
      return 'inactivo';
    }
  }
}
