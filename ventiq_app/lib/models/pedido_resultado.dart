/// Resultados y errores de las RPC de Fase 2 (`fn_pedir_item_cuenta`,
/// `fn_cancelar_item_pedido`).
///
/// Se modelan aparte del item de cuenta porque describen lo que PASÓ al pedir
/// (se movió stock, se creó comanda, qué cocina la recibió), no el estado
/// actual de la línea. La UI los usa para el feedback inmediato; el estado
/// persistente lo lee luego de `MesaCuentaItem`.
library;

/// Lo que devolvió `fn_pedir_item_cuenta` cuando el pedido salió bien.
class PedidoResultado {
  final int idItem;
  final int idCuenta;

  /// `barra`, `cocina_al_pedido`, `cocina_por_tanda` o `servicio`.
  final String origen;

  /// Vocabulario del plan: `tpv`, `tanda`, `al_pedido`, `servicio`.
  final String? origenStock;

  final int? idCocina;
  final String? cocinaNombre;

  /// `true` si el inventario ya salió al pedir. `false` cuando se forzó la
  /// venta sin stock disponible.
  final bool stockMovido;

  final int? idComanda;
  final int? idComandaItem;

  /// Número visible de la comanda para cantarla en cocina.
  final int? numeroComanda;

  final int? estadoServicio;

  /// Mensaje listo para mostrar: "Enviado a Cocina caliente", "Servido de …",
  /// o "Agregado a la cuenta".
  final String mensaje;

  /// Presente sólo si se pidió con `forzarSinStock` y el descuento falló.
  /// Contiene el error original del inventario para poder avisar.
  final Map<String, dynamic>? avisoStock;

  const PedidoResultado({
    required this.idItem,
    required this.idCuenta,
    required this.origen,
    this.origenStock,
    this.idCocina,
    this.cocinaNombre,
    required this.stockMovido,
    this.idComanda,
    this.idComandaItem,
    this.numeroComanda,
    this.estadoServicio,
    required this.mensaje,
    this.avisoStock,
  });

  /// Se creó una comanda: el plato está en manos de la cocina.
  bool get fueACocina => idComanda != null;

  /// Porción ya hecha entregada de inmediato desde la cocina.
  bool get servidoDeTanda => origen == 'cocina_por_tanda';

  /// Producto de barra o servicio: no pasa por cocina.
  bool get esDeBarra => origen == 'barra' || origen == 'servicio';

  /// Se agregó a la cuenta pero sin mover inventario: hay que avisar.
  bool get sinStockDescontado => avisoStock != null;

  factory PedidoResultado.fromJson(Map<String, dynamic> json) {
    int? entero(String clave) =>
        json[clave] is num ? (json[clave] as num).toInt() : null;

    return PedidoResultado(
      idItem: (json['id_item'] as num).toInt(),
      idCuenta: (json['id_cuenta'] as num).toInt(),
      origen: json['origen'] as String? ?? 'barra',
      origenStock: json['origen_stock'] as String?,
      idCocina: entero('id_cocina'),
      cocinaNombre: json['cocina'] as String?,
      stockMovido: json['stock_movido'] as bool? ?? false,
      idComanda: entero('id_comanda'),
      idComandaItem: entero('id_comanda_item'),
      numeroComanda: entero('numero_comanda'),
      estadoServicio: entero('estado_servicio'),
      mensaje: json['message'] as String? ?? 'Agregado a la cuenta',
      avisoStock: json['aviso_stock'] is Map
          ? Map<String, dynamic>.from(json['aviso_stock'] as Map)
          : null,
    );
  }
}

/// Lo que devolvió `fn_cancelar_item_pedido`.
class CancelacionResultado {
  final int idItem;

  /// El plato ya se había servido (o estaba listo en el pase).
  final bool yaServido;

  /// Se devolvió inventario. Sólo ocurre si NO se había servido.
  final bool stockDevuelto;

  /// Se retiró de la cuenta sin devolver inventario: la materia prima se gastó.
  final bool esMerma;

  final String? motivo;
  final bool comandaCancelada;
  final String mensaje;

  const CancelacionResultado({
    required this.idItem,
    required this.yaServido,
    required this.stockDevuelto,
    required this.esMerma,
    this.motivo,
    required this.comandaCancelada,
    required this.mensaje,
  });

  factory CancelacionResultado.fromJson(Map<String, dynamic> json) {
    return CancelacionResultado(
      idItem: (json['id_item'] as num).toInt(),
      yaServido: json['ya_servido'] as bool? ?? false,
      stockDevuelto: json['stock_devuelto'] as bool? ?? false,
      esMerma: json['es_merma'] as bool? ?? false,
      motivo: json['motivo'] as String?,
      comandaCancelada: json['comanda_cancelada'] as bool? ?? false,
      mensaje: json['message'] as String? ?? 'Item cancelado',
    );
  }
}

/// Error de negocio devuelto por las RPC de pedido.
///
/// Se distingue de una excepción de red porque trae [errorCode], que la UI usa
/// para decidir el mensaje y si ofrecer una acción (pedir motivo, avisar al
/// gerente de que falta ligar la cocina, etc.).
class PedidoException implements Exception {
  final String errorCode;
  final String mensaje;

  /// Presente en errores de stock: cuánto había y cuánto se pedía.
  final double? cantidadDisponible;
  final double? cantidadRequerida;

  final int? idCocina;
  final String? cocinaNombre;
  final String? producto;

  /// Ingredientes que bloquearon la preparación, si la RPC los detalló.
  final List<Map<String, dynamic>>? ingredientesFaltantes;

  const PedidoException({
    required this.errorCode,
    required this.mensaje,
    this.cantidadDisponible,
    this.cantidadRequerida,
    this.idCocina,
    this.cocinaNombre,
    this.producto,
    this.ingredientesFaltantes,
  });

  /// El TPV no está ligado a la cocina del plato: es un problema de
  /// configuración, no de stock. El vendedor no puede resolverlo solo.
  bool get esProblemaDeConfiguracion =>
      errorCode == 'COCINA_NO_LIGADA' ||
      errorCode == 'COCINA_NOT_FOUND' ||
      errorCode == 'SIN_RECETA' ||
      errorCode == 'CUENTA_SIN_TPV';

  /// La cocina cerró turno: se resuelve reabriéndola.
  bool get cocinaCerrada => errorCode == 'COCINA_INACTIVA';

  /// Falta materia prima o porciones. Es el caso donde tiene sentido ofrecer
  /// "pedir de todas formas" si la tienda lo permite.
  bool get esFaltaDeStock =>
      errorCode == 'INSUFFICIENT_STOCK' ||
      errorCode == 'INSUFFICIENT_PORTIONS' ||
      errorCode == 'INSUFFICIENT_STOCK_INGREDIENT';

  /// Se intentó cancelar un plato ya servido sin dar motivo.
  bool get requiereMotivo => errorCode == 'MOTIVO_REQUERIDO';

  /// Título corto para el diálogo o snackbar.
  String get titulo {
    if (cocinaCerrada) return 'Cocina cerrada';
    if (esProblemaDeConfiguracion) return 'No se puede enviar a cocina';
    if (esFaltaDeStock) {
      return errorCode == 'INSUFFICIENT_PORTIONS'
          ? 'Sin porciones preparadas'
          : 'Sin existencias';
    }
    if (requiereMotivo) return 'Hace falta un motivo';
    return 'No se pudo agregar';
  }

  factory PedidoException.fromJson(Map<String, dynamic> json) {
    double? decimal(String clave) {
      final v = json[clave];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    final bloqueando = json['productos_bloqueando'] ?? json['ingredientes'];

    return PedidoException(
      errorCode: json['error_code'] as String? ?? 'UNKNOWN',
      mensaje: json['message'] as String? ?? 'Ocurrió un error al pedir el item',
      cantidadDisponible: decimal('cantidad_disponible'),
      cantidadRequerida: decimal('cantidad_requerida'),
      idCocina: json['id_cocina'] is num
          ? (json['id_cocina'] as num).toInt()
          : null,
      cocinaNombre: json['cocina'] as String?,
      producto: json['producto'] as String?,
      ingredientesFaltantes: bloqueando is List
          ? bloqueando
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : null,
    );
  }

  @override
  String toString() => mensaje;
}
