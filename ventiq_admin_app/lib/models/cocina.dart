/// Modelos del módulo de cocinas (Fase 1 del plan restaurante/cocina).
///
/// Una cocina es un almacén propio de la tienda marcado con `es_cocina = true`:
/// ahí vive su materia prima y sus tandas terminadas. Un TPV se liga a una o
/// más cocinas y solo puede enrutar platos a esas.
library;

/// Modo de elaboración de un producto que va a cocina.
///
/// - [alPedido]: se cocina cuando se pide (bistec). Baja materia prima al pedir.
/// - [porTanda]: se produce en lotes (arroz moro) y se vende del stock
///   terminado. Si se acabó, está agotado aunque quede materia prima.
enum ModoElaboracion {
  alPedido('al_pedido', 'Al pedido'),
  porTanda('por_tanda', 'Por tanda');

  const ModoElaboracion(this.valor, this.etiqueta);

  /// Valor tal como se guarda en `app_dat_producto.modo_elaboracion`.
  final String valor;

  /// Texto para mostrar en la UI.
  final String etiqueta;

  static ModoElaboracion desdeValor(String? valor) {
    return ModoElaboracion.values.firstWhere(
      (m) => m.valor == valor,
      orElse: () => ModoElaboracion.alPedido,
    );
  }

  /// Descripción corta para ayudar al usuario a elegir.
  String get descripcion => switch (this) {
    ModoElaboracion.alPedido =>
      'Se prepara al momento de pedirlo. Descuenta ingredientes al pedir.',
    ModoElaboracion.porTanda =>
      'Se produce por lotes. Se vende del stock ya preparado.',
  };
}

/// TPV ligado a una cocina (forma reducida que devuelve `fn_listar_cocinas`).
class TpvLigado {
  const TpvLigado({required this.id, required this.denominacion});

  final int id;
  final String denominacion;

  factory TpvLigado.fromJson(Map<String, dynamic> json) {
    return TpvLigado(
      id: _asInt(json['id_tpv']) ?? 0,
      denominacion: json['denominacion']?.toString() ?? 'Sin nombre',
    );
  }
}

/// Una cocina con sus contadores, tal como la devuelve `fn_listar_cocinas`.
class Cocina {
  const Cocina({
    required this.id,
    required this.denominacion,
    required this.idAlmacen,
    required this.almacen,
    this.descripcion,
    this.impresora,
    this.orden = 0,
    this.activa = true,
    this.cantidadLayouts = 0,
    this.cantidadProductos = 0,
    this.productosPorTanda = 0,
    this.tpvs = const [],
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String denominacion;
  final int idAlmacen;
  final String almacen;
  final String? descripcion;
  final String? impresora;
  final int orden;
  final bool activa;

  final int cantidadLayouts;
  final int cantidadProductos;
  final int productosPorTanda;
  final List<TpvLigado> tpvs;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Una cocina sin TPV ligado no puede recibir comandas de nadie.
  bool get sinTpvs => tpvs.isEmpty;

  /// Sin layouts el almacén no puede recibir inventario.
  bool get sinLayouts => cantidadLayouts == 0;

  /// Cocina configurada pero que todavía no produce nada.
  bool get sinProductos => cantidadProductos == 0;

  /// Señales que el admin debería resolver para que la cocina opere.
  List<String> get advertencias => [
    if (!activa) 'Cocina desactivada: no recibe comandas',
    if (sinTpvs) 'Sin TPV ligado: ningún punto de venta puede enviarle platos',
    if (sinProductos) 'Sin platos asignados',
    if (sinLayouts) 'Sin ubicaciones: no puede recibir materia prima',
  ];

  bool get estaLista => advertencias.isEmpty;

  factory Cocina.fromJson(Map<String, dynamic> json) {
    final tpvsRaw = json['tpvs'];
    return Cocina(
      id: _asInt(json['id_cocina']) ?? 0,
      denominacion: json['denominacion']?.toString() ?? 'Sin nombre',
      idAlmacen: _asInt(json['id_almacen']) ?? 0,
      almacen: json['almacen']?.toString() ?? 'Sin almacén',
      descripcion: json['descripcion']?.toString(),
      impresora: json['impresora']?.toString(),
      orden: _asInt(json['orden']) ?? 0,
      activa: json['activa'] == true,
      cantidadLayouts: _asInt(json['cantidad_layouts']) ?? 0,
      cantidadProductos: _asInt(json['cantidad_productos']) ?? 0,
      productosPorTanda: _asInt(json['productos_por_tanda']) ?? 0,
      tpvs: tpvsRaw is List
          ? tpvsRaw
                .whereType<Map<String, dynamic>>()
                .map(TpvLigado.fromJson)
                .toList()
          : const [],
      createdAt: _asDate(json['created_at']),
      updatedAt: _asDate(json['updated_at']),
    );
  }
}

/// Resultado de `fn_disponibilidad_plato`.
///
/// El campo [tipo] indica por qué vía se calculó la disponibilidad, lo que
/// determina qué se le muestra al vendedor:
///   - `stock_propio`          producto de barra, stock del almacén del TPV
///   - `por_tanda`             porciones ya preparadas en la cocina
///   - `al_pedido`             límite según la materia prima de la cocina
///   - `elaborado_sin_cocina`  elaborado sin cocina asignada (comportamiento previo)
///   - `servicio`              sin control de disponibilidad
///   - `no_disponible`         no se puede vender desde este TPV
class DisponibilidadPlato {
  const DisponibilidadPlato({
    required this.idProducto,
    required this.producto,
    required this.tipo,
    this.disponible,
    this.ilimitado = false,
    this.vendibleAqui = true,
    this.idCocina,
    this.cocina,
    this.idAlmacen,
    this.modoElaboracion,
    this.tieneReceta,
    this.errorCode,
    this.mensaje,
    this.ingredientes = const [],
  });

  final int idProducto;
  final String producto;
  final String tipo;

  /// `null` cuando no aplica control de disponibilidad (servicios).
  final double? disponible;
  final bool ilimitado;

  /// `false` cuando el TPV no está ligado a la cocina del plato, o la cocina
  /// está desactivada.
  final bool vendibleAqui;

  final int? idCocina;
  final String? cocina;
  final int? idAlmacen;
  final ModoElaboracion? modoElaboracion;
  final bool? tieneReceta;

  /// `COCINA_NO_LIGADA`, `COCINA_INACTIVA`, `SIN_RECETA`, etc.
  final String? errorCode;
  final String? mensaje;

  final List<IngredienteDisponibilidad> ingredientes;

  bool get agotado => !ilimitado && (disponible ?? 0) <= 0;
  bool get vaACocina => idCocina != null;

  /// Texto corto para el chip de la tarjeta del producto.
  String get etiquetaCorta {
    if (!vendibleAqui) return 'No disponible aquí';
    if (ilimitado) return 'Servicio';
    final n = disponible ?? 0;
    if (n <= 0) return 'Agotado';
    if (modoElaboracion == ModoElaboracion.porTanda) {
      return '${_num(n)} porciones';
    }
    return 'Hasta ${_num(n)}';
  }

  factory DisponibilidadPlato.fromJson(Map<String, dynamic> json) {
    final ings = json['ingredientes'];
    return DisponibilidadPlato(
      idProducto: _asInt(json['id_producto']) ?? 0,
      producto: json['producto']?.toString() ?? '',
      tipo: json['tipo']?.toString() ?? 'desconocido',
      disponible: _asDouble(json['disponible']),
      ilimitado: json['ilimitado'] == true,
      vendibleAqui: json['vendible_aqui'] != false,
      idCocina: _asInt(json['id_cocina']),
      cocina: json['cocina']?.toString(),
      idAlmacen: _asInt(json['id_almacen']),
      modoElaboracion: json['modo_elaboracion'] == null
          ? null
          : ModoElaboracion.desdeValor(json['modo_elaboracion']?.toString()),
      tieneReceta: json['tiene_receta'] as bool?,
      errorCode: json['error_code']?.toString(),
      mensaje: json['message']?.toString(),
      ingredientes: ings is List
          ? ings
                .whereType<Map<String, dynamic>>()
                .map(IngredienteDisponibilidad.fromJson)
                .toList()
          : const [],
    );
  }
}

/// Línea del desglose por ingrediente de `fn_disponibilidad_plato`.
class IngredienteDisponibilidad {
  const IngredienteDisponibilidad({
    required this.idIngrediente,
    required this.ingrediente,
    required this.cantidadNecesaria,
    required this.stockDisponible,
    required this.unidadesPosibles,
    this.suficiente = true,
  });

  final int idIngrediente;
  final String ingrediente;
  final double cantidadNecesaria;
  final double stockDisponible;
  final double unidadesPosibles;
  final bool suficiente;

  /// El ingrediente que limita cuántas unidades se pueden preparar.
  bool get esCuelloDeBotella => unidadesPosibles <= 0;

  factory IngredienteDisponibilidad.fromJson(Map<String, dynamic> json) {
    final necesaria = _asDouble(json['cantidad_necesaria']) ?? 0;
    final stock = _asDouble(json['stock_disponible']) ?? 0;
    return IngredienteDisponibilidad(
      idIngrediente: _asInt(json['id_ingrediente']) ?? 0,
      ingrediente: json['ingrediente']?.toString() ?? 'Ingrediente',
      cantidadNecesaria: necesaria,
      stockDisponible: stock,
      unidadesPosibles: _asDouble(json['unidades_posibles']) ?? 0,
      suficiente: json['suficiente'] as bool? ?? (stock >= necesaria),
    );
  }
}

// ── Helpers de parseo ───────────────────────────────────────────────────────
// Las RPC devuelven numeric como String en algunos casos (jsonb), así que se
// parsea de forma tolerante en vez de castear directo.

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

DateTime? _asDate(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}

/// Formatea un número quitando el `.0` de los enteros.
String _num(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(2);
}
