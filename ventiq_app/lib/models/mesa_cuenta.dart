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
    this.itemsEnCocina = 0,
    this.itemsListos = 0,
  });

  bool get abierta => estado == 1;
  int get cantidadItems => items.length;
  double get totalCalculado =>
      items.fold(0.0, (s, i) => s + i.cantidad * i.precioUnitario);

  // ── Fase 2 · estado agregado de cocina ─────────────────────────────────
  /// Líneas con comanda pendiente o en preparación. Lo calcula la RPC para
  /// no tener que recorrer las comandas por separado.
  final int itemsEnCocina;

  /// Líneas listas en cocina pero aún no entregadas al comensal.
  final int itemsListos;

  /// Hay comandas sin servir: al cerrar la nota conviene avisar.
  bool get tieneComandasPendientes => itemsEnCocina > 0;

  /// Hay platos esperando que el mesero los recoja del pase.
  bool get tienePlatosListos => itemsListos > 0;

  /// Resumen para el encabezado de la cuenta. `null` si no hay nada en cocina.
  String? get resumenCocina {
    final partes = <String>[];
    if (itemsListos > 0) {
      partes.add(itemsListos == 1 ? '1 listo' : '$itemsListos listos');
    }
    if (itemsEnCocina > 0) {
      partes.add(itemsEnCocina == 1
          ? '1 en cocina'
          : '$itemsEnCocina en cocina');
    }
    return partes.isEmpty ? null : partes.join(' · ');
  }

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
      itemsEnCocina: json['items_en_cocina'] is num
          ? (json['items_en_cocina'] as num).toInt()
          : 0,
      itemsListos: json['items_listos'] is num
          ? (json['items_listos'] as num).toInt()
          : 0,
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

  // ── Fase 2 · cocina y servicio ─────────────────────────────────────────
  /// De dónde salió el stock al pedir: `tpv`, `tanda`, `al_pedido` o
  /// `servicio`. `null` en líneas creadas antes de la Fase 2 (legado).
  final String? origenStock;
  final int? idCocina;
  final String? cocinaNombre;

  /// Foto del estado en el momento de pedir. Para el estado VIVO usar
  /// [estadoServicioEfectivo], que prefiere el de la comanda.
  final int? estadoServicio;

  /// `true` si el inventario ya salió al pedir; el cobro no lo repite.
  final bool stockMovido;

  final int? idComandaItem;
  final int? comandaNumero;

  /// Estado actual de la comanda en cocina. Es el dato vivo: la cocina lo
  /// actualiza, mientras [estadoServicio] se queda como estaba al pedir.
  final int? comandaEstado;

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
    this.origenStock,
    this.idCocina,
    this.cocinaNombre,
    this.estadoServicio,
    this.stockMovido = false,
    this.idComandaItem,
    this.comandaNumero,
    this.comandaEstado,
  });

  String get displayName {
    if (varianteNombre != null && varianteNombre!.isNotEmpty) {
      return '${productoNombre ?? 'Producto'} — $varianteNombre';
    }
    return productoNombre ?? 'Producto $idProducto';
  }

  // ── Clasificación de la línea ──────────────────────────────────────────

  /// La línea se preparó (o se está preparando) en una cocina.
  bool get vaACocina => idCocina != null && origenStock != 'tpv';

  /// Porción ya hecha servida desde la cocina: no espera preparación.
  bool get esDeTanda => origenStock == 'tanda';

  /// Se cocina al momento: tiene comanda y pasa por los estados del KDS.
  bool get esAlPedido => origenStock == 'al_pedido';

  /// Estado vivo del servicio. La comanda es la fuente de verdad porque la
  /// cocina la va actualizando; `estado_servicio` de la línea es la foto del
  /// momento en que se pidió y se queda atrás.
  int? get estadoServicioEfectivo => comandaEstado ?? estadoServicio;

  bool get pendienteEnCocina => estadoServicioEfectivo == 1;
  bool get enPreparacion => estadoServicioEfectivo == 2;
  bool get listoParaServir => estadoServicioEfectivo == 3;
  bool get entregado => estadoServicioEfectivo == 4;
  bool get cancelado => estadoServicioEfectivo == 5;

  /// Sigue en manos de la cocina: bloquea o avisa al cerrar la nota.
  bool get sinServir =>
      estadoServicioEfectivo != null && estadoServicioEfectivo! <= 3;

  /// Texto corto para la línea de la nota, en lenguaje de oficio.
  /// Devuelve `null` cuando no hay nada que decir (producto de barra).
  String? get etiquetaServicio {
    if (esDeTanda) return 'Servido';
    switch (estadoServicioEfectivo) {
      case 1:
        return 'En cocina';
      case 2:
        return 'Preparando';
      case 3:
        return 'Listo';
      case 4:
        return 'Entregado';
      case 5:
        return 'Cancelado';
      default:
        return null;
    }
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
      // Fase 2. Todos tolerantes a ausencia: si el 18 no está aplicado,
      // llegan null y la UI se comporta como antes.
      origenStock: json['origen_stock'] as String?,
      idCocina:
          json['id_cocina'] is num ? (json['id_cocina'] as num).toInt() : null,
      cocinaNombre: json['cocina_nombre'] as String?,
      estadoServicio: json['estado_servicio'] is num
          ? (json['estado_servicio'] as num).toInt()
          : null,
      stockMovido: json['stock_movido'] as bool? ?? false,
      idComandaItem: json['id_comanda_item'] is num
          ? (json['id_comanda_item'] as num).toInt()
          : null,
      comandaNumero: json['comanda_numero'] is num
          ? (json['comanda_numero'] as num).toInt()
          : null,
      comandaEstado: json['comanda_estado'] is num
          ? (json['comanda_estado'] as num).toInt()
          : null,
    );
  }
}
