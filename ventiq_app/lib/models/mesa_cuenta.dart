/// Cuenta abierta de mesa: estado intermedio entre "mesa libre" y
/// "venta registrada". Refleja la fila de `app_dat_mesa_cuenta_abierta`
/// más los items relacionados.
///
/// Mientras la cuenta esté en estado [estado] == 1 (abierta), el vendedor
/// puede agregar/quitar productos sin tocar inventario. Al "Cerrar Nota"
/// se invoca el flujo normal de venta y la cuenta pasa a estado 2.

class MesaCuenta {
  final int id;
  final int idMesa;
  final String? mesaNumero;
  final String? mesaZona;
  final int? idTpv;
  final int? idVendedor;
  final int? numeroComensales;
  final String? notas;
  final int estado; // 1 abierta, 2 cerrada, 3 cancelada
  final double total;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<MesaCuentaItem> items;

  const MesaCuenta({
    required this.id,
    required this.idMesa,
    this.mesaNumero,
    this.mesaZona,
    this.idTpv,
    this.idVendedor,
    this.numeroComensales,
    this.notas,
    required this.estado,
    required this.total,
    required this.createdAt,
    required this.updatedAt,
    this.items = const [],
  });

  bool get abierta => estado == 1;
  int get cantidadItems => items.length;
  double get totalCalculado =>
      items.fold(0.0, (s, i) => s + i.cantidad * i.precioUnitario);

  factory MesaCuenta.fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items'];
    final items = <MesaCuentaItem>[];
    if (itemsRaw is List) {
      for (final raw in itemsRaw) {
        if (raw is Map) {
          items.add(MesaCuentaItem.fromJson(Map<String, dynamic>.from(raw)));
        }
      }
    }
    return MesaCuenta(
      id: (json['id'] as num).toInt(),
      idMesa: (json['id_mesa'] as num).toInt(),
      mesaNumero: json['mesa_numero'] as String?,
      mesaZona: json['mesa_zona'] as String?,
      idTpv: json['id_tpv'] is num ? (json['id_tpv'] as num).toInt() : null,
      idVendedor:
          json['id_vendedor'] is num ? (json['id_vendedor'] as num).toInt() : null,
      numeroComensales: json['numero_comensales'] is num
          ? (json['numero_comensales'] as num).toInt()
          : null,
      notas: json['notas'] as String?,
      estado: (json['estado'] as num).toInt(),
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
      items: items,
    );
  }
}

class MesaCuentaItem {
  final int id;
  final int idProducto;
  final String? productoNombre;
  final String? productoSku;
  final bool productoEsElaborado;
  final bool productoEsServicio;
  final int? idVariante;
  final int? idOpcionVariante;
  final String? varianteNombre;
  final int? idPresentacion;
  final String? presentacionNombre;
  final int? idUbicacion;
  final String? ubicacionNombre;
  final double cantidad;
  final double precioUnitario;
  final double? precioBase;
  final double subtotal;
  final int? idMetodoPago;
  final Map<String, dynamic>? promotionData;
  final Map<String, dynamic>? inventoryData;
  final String? notas;
  final String? skuProducto;
  final String? skuUbicacion;
  final DateTime createdAt;

  const MesaCuentaItem({
    required this.id,
    required this.idProducto,
    this.productoNombre,
    this.productoSku,
    this.productoEsElaborado = false,
    this.productoEsServicio = false,
    this.idVariante,
    this.idOpcionVariante,
    this.varianteNombre,
    this.idPresentacion,
    this.presentacionNombre,
    this.idUbicacion,
    this.ubicacionNombre,
    required this.cantidad,
    required this.precioUnitario,
    this.precioBase,
    required this.subtotal,
    this.idMetodoPago,
    this.promotionData,
    this.inventoryData,
    this.notas,
    this.skuProducto,
    this.skuUbicacion,
    required this.createdAt,
  });

  String get displayName {
    if (varianteNombre != null && varianteNombre!.isNotEmpty) {
      return '${productoNombre ?? 'Producto'} — $varianteNombre';
    }
    return productoNombre ?? 'Producto $idProducto';
  }

  factory MesaCuentaItem.fromJson(Map<String, dynamic> json) {
    return MesaCuentaItem(
      id: (json['id'] as num).toInt(),
      idProducto: (json['id_producto'] as num).toInt(),
      productoNombre: json['producto_nombre'] as String?,
      productoSku: json['producto_sku'] as String?,
      productoEsElaborado: json['producto_es_elaborado'] as bool? ?? false,
      productoEsServicio: json['producto_es_servicio'] as bool? ?? false,
      idVariante:
          json['id_variante'] is num ? (json['id_variante'] as num).toInt() : null,
      idOpcionVariante: json['id_opcion_variante'] is num
          ? (json['id_opcion_variante'] as num).toInt()
          : null,
      varianteNombre: json['variante_nombre'] as String?,
      idPresentacion: json['id_presentacion'] is num
          ? (json['id_presentacion'] as num).toInt()
          : null,
      presentacionNombre: json['presentacion_nombre'] as String?,
      idUbicacion: json['id_ubicacion'] is num
          ? (json['id_ubicacion'] as num).toInt()
          : null,
      ubicacionNombre: json['ubicacion_nombre'] as String?,
      cantidad: (json['cantidad'] as num).toDouble(),
      precioUnitario: (json['precio_unitario'] as num).toDouble(),
      precioBase: (json['precio_base'] as num?)?.toDouble(),
      subtotal: (json['subtotal'] as num?)?.toDouble() ??
          ((json['cantidad'] as num).toDouble() *
              (json['precio_unitario'] as num).toDouble()),
      idMetodoPago: json['id_metodo_pago'] is num
          ? (json['id_metodo_pago'] as num).toInt()
          : null,
      promotionData: json['promotion_data'] is Map
          ? Map<String, dynamic>.from(json['promotion_data'] as Map)
          : null,
      inventoryData: json['inventory_data'] is Map
          ? Map<String, dynamic>.from(json['inventory_data'] as Map)
          : null,
      notas: json['notas'] as String?,
      skuProducto: json['sku_producto'] as String?,
      skuUbicacion: json['sku_ubicacion'] as String?,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
