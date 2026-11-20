class ProductCurrencyException implements Exception {
  final String code;
  ProductCurrencyException(this.code);
  @override
  String toString() => code;
}

/// Selección monetaria de una línea. Los importes viajan como texto decimal.
class ProductCurrencySeleccion {
  static const version = 'producto-v1';

  final String idLineaCliente;
  final String idProducto;
  final String cantidad;
  final String monedaVenta;
  final String tipoCobro;
  final int? idMedioPago;
  final String precioUnitarioNativo;
  final String descuentoManualUnitario;
  final Map<String, dynamic> snapshotPrecio;
  final Map<String, dynamic>? snapshotTasa;
  final List<Map<String, dynamic>> ajustesAutomaticos;

  const ProductCurrencySeleccion({
    required this.idLineaCliente,
    required this.idProducto,
    required this.cantidad,
    required this.monedaVenta,
    required this.tipoCobro,
    required this.idMedioPago,
    required this.precioUnitarioNativo,
    required this.descuentoManualUnitario,
    required this.snapshotPrecio,
    required this.snapshotTasa,
    required this.ajustesAutomaticos,
  });

  ProductCurrencySeleccion copyWith({
    String? monedaVenta,
    String? tipoCobro,
    int? idMedioPago,
    bool limpiarMedio = false,
  }) {
    return ProductCurrencySeleccion(
      idLineaCliente: idLineaCliente,
      idProducto: idProducto,
      cantidad: cantidad,
      monedaVenta: monedaVenta ?? this.monedaVenta,
      tipoCobro: tipoCobro ?? this.tipoCobro,
      idMedioPago: limpiarMedio ? null : (idMedioPago ?? this.idMedioPago),
      precioUnitarioNativo: precioUnitarioNativo,
      descuentoManualUnitario: descuentoManualUnitario,
      snapshotPrecio: snapshotPrecio,
      snapshotTasa: snapshotTasa,
      ajustesAutomaticos: ajustesAutomaticos,
    );
  }

  /// Misma selección con otra cantidad. El importe de la línea (`neto`, `cup`)
  /// se calcula desde `cantidad`: si el carrito cambia la cantidad del ítem y
  /// la selección conserva la anterior, el ticket y la sincronización cobran
  /// la cantidad vieja (5 x diesel salía como 1 x diesel).
  ProductCurrencySeleccion conCantidad(double nuevaCantidad) {
    var texto = nuevaCantidad.toStringAsFixed(3);
    texto = texto.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    return ProductCurrencySeleccion(
      idLineaCliente: idLineaCliente,
      idProducto: idProducto,
      cantidad: texto,
      monedaVenta: monedaVenta,
      tipoCobro: tipoCobro,
      idMedioPago: idMedioPago,
      precioUnitarioNativo: precioUnitarioNativo,
      descuentoManualUnitario: descuentoManualUnitario,
      snapshotPrecio: snapshotPrecio,
      snapshotTasa: snapshotTasa,
      ajustesAutomaticos: ajustesAutomaticos,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id_linea_cliente': idLineaCliente,
      'id_producto': idProducto,
      'cantidad': cantidad,
      'moneda_venta': monedaVenta,
      'seleccion_cobro': {
        'tipo': tipoCobro,
        'id_medio_pago': idMedioPago,
      },
      'precio_unitario_nativo': precioUnitarioNativo,
      'descuento_manual_unitario_nativo': descuentoManualUnitario,
      'snapshot_precio': snapshotPrecio,
      'snapshot_tasa': snapshotTasa,
      'snapshot_ajustes_automaticos': ajustesAutomaticos,
    };
  }

  factory ProductCurrencySeleccion.fromJson(Map<String, dynamic> json) {
    final precio = json['precio_unitario_nativo'];
    if (precio is num) {
      throw ProductCurrencyException('DECIMAL_STRING_REQUIRED');
    }
    if (precio is! String || precio.isEmpty) {
      throw ProductCurrencyException('NATIVE_PRICE_UNAVAILABLE');
    }
    if (precio == 'NaN' || precio.contains('e') || precio.contains('E')) {
      throw ProductCurrencyException('INVALID_DECIMAL');
    }
    final moneda = json['moneda_venta'];
    if (moneda is! String || (moneda != 'CUP' && moneda != 'USD')) {
      throw ProductCurrencyException('UNSUPPORTED_CURRENCY');
    }
    final cantidad = json['cantidad'];
    if (cantidad is! String || cantidad.isEmpty || cantidad.startsWith('-')) {
      throw ProductCurrencyException('INVALID_QUANTITY');
    }
    final cobro = json['seleccion_cobro'];
    if (cobro is! Map) {
      throw ProductCurrencyException('PAYMENT_SELECTION_MISMATCH');
    }
    final tipo = cobro['tipo']?.toString();
    final medio = cobro['id_medio_pago'];
    if (tipo == 'pendiente') {
      if (medio != null) {
        throw ProductCurrencyException('PAYMENT_SELECTION_MISMATCH');
      }
    } else if (tipo != 'medio_pago' || medio is! int) {
      throw ProductCurrencyException('PAYMENT_SELECTION_MISMATCH');
    }
    final idLinea = json['id_linea_cliente']?.toString() ?? '';
    if (!_uuid.hasMatch(idLinea)) {
      throw ProductCurrencyException('CONTRACT_VERSION_UNSUPPORTED');
    }
    final tasa = json['snapshot_tasa'];
    if (moneda == 'USD') {
      if (tasa is! Map || tasa['evidencia_publicacion'] == null) {
        throw ProductCurrencyException('SNAPSHOT_EVIDENCE_REQUIRED');
      }
    }
    final precioSnap = json['snapshot_precio'];
    if (precioSnap is! Map) {
      throw ProductCurrencyException('SNAPSHOT_INVALID');
    }
    final ajustes = json['snapshot_ajustes_automaticos'];
    return ProductCurrencySeleccion(
      idLineaCliente: idLinea,
      idProducto: json['id_producto']?.toString() ?? '',
      cantidad: cantidad,
      monedaVenta: moneda,
      tipoCobro: tipo!,
      idMedioPago: medio is int ? medio : null,
      precioUnitarioNativo: precio,
      descuentoManualUnitario:
          (json['descuento_manual_unitario_nativo'] ?? '0').toString(),
      snapshotPrecio: Map<String, dynamic>.from(precioSnap),
      snapshotTasa: tasa is Map ? Map<String, dynamic>.from(tasa) : null,
      ajustesAutomaticos:
          ajustes is List
              ? ajustes.map((e) => Map<String, dynamic>.from(e as Map)).toList()
              : const [],
    );
  }
}

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Lee una orden ya guardada sin convertirla de contrato.
class PendingSaleCodec {
  static void preparar(Map<String, dynamic> order) {
    final version = order['version_monetaria'];
    if (version == null) return;
    if (version != ProductCurrencySeleccion.version) {
      throw ProductCurrencyException('CONTRACT_VERSION_UNSUPPORTED');
    }
    final uuid = order['client_uuid']?.toString() ?? '';
    if (!_uuid.hasMatch(uuid)) {
      throw ProductCurrencyException('CONTRACT_VERSION_UNSUPPORTED');
    }
    final items = order['items'];
    if (items is! List || items.isEmpty) {
      throw ProductCurrencyException('NATIVE_PRICE_UNAVAILABLE');
    }
    for (final item in items) {
      if (item is! Map || item['seleccion'] is! Map) {
        throw ProductCurrencyException('SNAPSHOT_INVALID');
      }
      ProductCurrencySeleccion.fromJson(
        Map<String, dynamic>.from(item['seleccion'] as Map),
      );
    }
  }

  /// Devuelve la orden guardada. Una venta nueva no se reconstruye desde los pagos.
  static Map<String, dynamic> leer(Map<String, dynamic> order) {
    preparar(order);
    return order;
  }
}
