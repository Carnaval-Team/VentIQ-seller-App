/// Modelos del módulo Compras (tablas `fdi_dat_compra*`).
///
/// Las claves JSON son las del contrato de las RPC `fn_fdi_compra_*`
/// (snake_case); las propiedades Dart van en camelCase.
library;

/// Redondeo a dos decimales, el mismo que aplica el recálculo en PostgreSQL.
double _redondear2(double valor) =>
    valor.isFinite ? (valor * 100).round() / 100 : 0;

/// Contrato mínimo de los catálogos cerrados que viajan como texto en la BD.
abstract interface class _CodigoLegible {
  String get codigo;
  String get etiqueta;
}

T? _desdeCodigo<T extends _CodigoLegible>(List<T> valores, String? codigo) {
  if (codigo == null) return null;
  for (final valor in valores) {
    if (valor.codigo == codigo) return valor;
  }
  return null;
}

String _etiquetaDe<T extends _CodigoLegible>(List<T> valores, String? codigo) =>
    _desdeCodigo(valores, codigo)?.etiqueta ?? codigo ?? '';

/// Estados del ciclo de vida de una compra (columna `estado`).
enum CompraEstado implements _CodigoLegible {
  creada('creada', 'Creada'),
  reservada('reservada', 'Reservada'),
  pagada('pagada', 'Pagada'),
  entregaParcial('entrega_parcial', 'Entrega parcial'),
  completada('completada', 'Completada'),
  cancelada('cancelada', 'Cancelada'),
  anulada('anulada', 'Anulada');

  const CompraEstado(this.codigo, this.etiqueta);

  @override
  final String codigo;
  @override
  final String etiqueta;

  static CompraEstado? desde(String? codigo) => _desdeCodigo(values, codigo);

  static String etiquetaDe(String? codigo) => _etiquetaDe(values, codigo);
}

/// Quién paga un ajuste (columna `origen_pago`).
enum OrigenPagoAjuste implements _CodigoLegible {
  fondo('fondo', 'Fondo'),
  walletImportadora('wallet_importadora', 'Wallet importadora'),
  walletProveedor('wallet_proveedor', 'Wallet proveedor'),
  externo('externo', 'Externo');

  const OrigenPagoAjuste(this.codigo, this.etiqueta);

  @override
  final String codigo;
  @override
  final String etiqueta;

  static OrigenPagoAjuste? desde(String? codigo) =>
      _desdeCodigo(values, codigo);

  static String etiquetaDe(String? codigo) => _etiquetaDe(values, codigo);
}

/// Base de cálculo del valor de un ajuste (columna `base`).
enum CompraBaseAjuste implements _CodigoLegible {
  global('global', 'Global'),
  unidad('unidad', 'Por unidad'),
  porcentaje('porcentaje', 'Porcentaje');

  const CompraBaseAjuste(this.codigo, this.etiqueta);

  @override
  final String codigo;
  @override
  final String etiqueta;

  static CompraBaseAjuste? desde(String? codigo) =>
      _desdeCodigo(values, codigo);

  static String etiquetaDe(String? codigo) => _etiquetaDe(values, codigo);
}

/// Cómo se reparte un ajuste entre las líneas (columna `reparto`).
enum CompraRepartoAjuste implements _CodigoLegible {
  valor('valor', 'Por valor'),
  peso('peso', 'Por peso'),
  cantidad('cantidad', 'Por cantidad');

  const CompraRepartoAjuste(this.codigo, this.etiqueta);

  @override
  final String codigo;
  @override
  final String etiqueta;

  static CompraRepartoAjuste? desde(String? codigo) =>
      _desdeCodigo(values, codigo);

  static String etiquetaDe(String? codigo) => _etiquetaDe(values, codigo);
}

/// Modo de liquidación de la compra (columna `modo_liquidacion`).
enum CompraModoLiquidacion implements _CodigoLegible {
  fondo('fondo', 'Fondo'),
  inversores('inversores', 'Inversores');

  const CompraModoLiquidacion(this.codigo, this.etiqueta);

  @override
  final String codigo;
  @override
  final String etiqueta;

  static CompraModoLiquidacion? desde(String? codigo) =>
      _desdeCodigo(values, codigo);

  static String etiquetaDe(String? codigo) => _etiquetaDe(values, codigo);
}

/// Momento del pago al proveedor (columna `politica_pago`).
enum CompraPoliticaPago implements _CodigoLegible {
  alPagar('al_pagar', 'Al pagar'),
  porRecepcion('por_recepcion', 'Por recepción');

  const CompraPoliticaPago(this.codigo, this.etiqueta);

  @override
  final String codigo;
  @override
  final String etiqueta;

  static CompraPoliticaPago? desde(String? codigo) =>
      _desdeCodigo(values, codigo);

  static String etiquetaDe(String? codigo) => _etiquetaDe(values, codigo);
}

/// Una línea de la compra. `toJson` emite exactamente las claves que espera
/// `fn_fdi_compra_crear` / `fn_fdi_compra_editar` en `p_lineas`.
class CompraLinea {
  final int? id;
  final int idProducto;
  final int? idVariante;
  final int? idPresentacion;
  final double cantidad;
  final double costoUnitario;
  final int? idAlmacen;
  final int? idUbicacion;

  /// Denominación del producto tal como la devuelve el detalle (solo lectura).
  final String? producto;

  final double? _costoLinea;

  const CompraLinea({
    this.id,
    required this.idProducto,
    this.idVariante,
    this.idPresentacion,
    required this.cantidad,
    required this.costoUnitario,
    this.idAlmacen,
    this.idUbicacion,
    this.producto,
    double? costoLinea,
  }) : _costoLinea = costoLinea;

  /// Lo calcula PostgreSQL como columna generada; si el JSON no lo trae (línea
  /// recién armada en el formulario) se calcula aquí con el mismo redondeo.
  double get costoLinea => _costoLinea ?? _redondear2(cantidad * costoUnitario);

  factory CompraLinea.fromJson(Map<String, dynamic> j) {
    final cantidad = (j['cantidad'] as num?)?.toDouble() ?? 0;
    final costoUnitario = (j['costo_unitario'] as num?)?.toDouble() ?? 0;
    return CompraLinea(
      id: (j['id'] as num?)?.toInt(),
      idProducto: (j['id_producto'] as num).toInt(),
      idVariante: (j['id_variante'] as num?)?.toInt(),
      idPresentacion: (j['id_presentacion'] as num?)?.toInt(),
      cantidad: cantidad,
      costoUnitario: costoUnitario,
      idAlmacen: (j['id_almacen'] as num?)?.toInt(),
      idUbicacion: (j['id_ubicacion'] as num?)?.toInt(),
      producto: j['producto']?.toString(),
      costoLinea: (j['costo_linea'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id_producto': idProducto,
    'id_variante': idVariante,
    'id_presentacion': idPresentacion,
    'cantidad': cantidad,
    'costo_unitario': costoUnitario,
    'id_almacen': idAlmacen,
    'id_ubicacion': idUbicacion,
  };
}

/// Estado de una línea de compra frente a lo ya recibido, según
/// `fn_fdi_compra_recepcion_pendiente`.
///
/// [pendiente] lo calcula el servidor (`cantidad - recibido`, redondeado a 4):
/// es la fuente de verdad del "falta por llegar" y el tope que la recepción
/// precarga y deja editar.
class LineaPendiente {
  final int idLinea;
  final int idProducto;
  final String producto;
  final double cantidad;
  final double costoUnitario;
  final double recibido;
  final double pendiente;

  const LineaPendiente({
    required this.idLinea,
    required this.idProducto,
    this.producto = '',
    this.cantidad = 0,
    this.costoUnitario = 0,
    this.recibido = 0,
    this.pendiente = 0,
  });

  /// Solo las líneas con pendiente > 0 se pueden recepcionar.
  bool get tienePendiente => pendiente > 0;

  /// Valor del pendiente al costo de la compra (mismo redondeo a 2).
  double get valorPendiente => _redondear2(pendiente * costoUnitario);

  factory LineaPendiente.fromJson(Map<String, dynamic> j) {
    final cantidad = (j['cantidad'] as num?)?.toDouble() ?? 0;
    final recibido = (j['recibido'] as num?)?.toDouble() ?? 0;
    return LineaPendiente(
      idLinea: (j['id_linea'] as num?)?.toInt() ?? 0,
      idProducto: (j['id_producto'] as num?)?.toInt() ?? 0,
      producto: j['producto']?.toString() ?? '',
      cantidad: cantidad,
      costoUnitario: (j['costo_unitario'] as num?)?.toDouble() ?? 0,
      recibido: recibido,
      pendiente: (j['pendiente'] as num?)?.toDouble() ??
          _redondear2(cantidad - recibido),
    );
  }
}

/// Un ajuste de la compra (flete, aduana, servicio de importadora...).
/// `toJson` emite exactamente las claves de `p_ajustes`.
class CompraAjuste {
  final int? id;
  final int? idTipoCosto;
  final String base;
  final double valor;
  final String reparto;
  final double montoCapitalizado;
  final bool afectaInventario;
  final String origenPago;
  final String estado;

  const CompraAjuste({
    this.id,
    this.idTipoCosto,
    this.base = 'global',
    required this.valor,
    this.reparto = 'valor',
    this.montoCapitalizado = 0,
    this.afectaInventario = true,
    this.origenPago = 'fondo',
    this.estado = 'declarado',
  });

  String get baseLegible => CompraBaseAjuste.etiquetaDe(base);
  String get repartoLegible => CompraRepartoAjuste.etiquetaDe(reparto);
  String get origenPagoLegible => OrigenPagoAjuste.etiquetaDe(origenPago);

  factory CompraAjuste.fromJson(Map<String, dynamic> j) => CompraAjuste(
    id: (j['id'] as num?)?.toInt(),
    idTipoCosto: (j['id_tipo_costo'] as num?)?.toInt(),
    base: j['base']?.toString() ?? 'global',
    valor: (j['valor'] as num?)?.toDouble() ?? 0,
    reparto: j['reparto']?.toString() ?? 'valor',
    montoCapitalizado: (j['monto_capitalizado'] as num?)?.toDouble() ?? 0,
    afectaInventario: j['afecta_inventario'] != false,
    origenPago: j['origen_pago']?.toString() ?? 'fondo',
    estado: j['estado']?.toString() ?? 'declarado',
  );

  Map<String, dynamic> toJson() => {
    'id_tipo_costo': idTipoCosto,
    'base': base,
    'valor': valor,
    'reparto': reparto,
    'origen_pago': origenPago,
    'afecta_inventario': afectaInventario,
  };
}

/// Una fila del historial de estados (`fdi_hist_estado_compra`).
class CompraHistorico {
  final int? id;
  final String? estadoAnterior;
  final String estadoNuevo;
  final String origen;
  final String? motivo;
  final DateTime? createdAt;

  const CompraHistorico({
    this.id,
    this.estadoAnterior,
    required this.estadoNuevo,
    this.origen = 'manual',
    this.motivo,
    this.createdAt,
  });

  String? get estadoAnteriorLegible =>
      estadoAnterior == null ? null : CompraEstado.etiquetaDe(estadoAnterior);
  String get estadoNuevoLegible => CompraEstado.etiquetaDe(estadoNuevo);

  factory CompraHistorico.fromJson(Map<String, dynamic> j) => CompraHistorico(
    id: (j['id'] as num?)?.toInt(),
    estadoAnterior: j['estado_anterior']?.toString(),
    estadoNuevo: j['estado_nuevo']?.toString() ?? '',
    origen: j['origen']?.toString() ?? 'manual',
    motivo: j['motivo']?.toString(),
    createdAt: j['created_at'] != null
        ? DateTime.tryParse(j['created_at'].toString())
        : null,
  );
}

/// Proveedor embebido en el detalle (`{id, denominacion}`).
class CompraProveedor {
  final int id;
  final String denominacion;

  const CompraProveedor({required this.id, required this.denominacion});

  factory CompraProveedor.fromJson(Map<String, dynamic> j) => CompraProveedor(
    id: (j['id'] as num?)?.toInt() ?? 0,
    denominacion: j['denominacion']?.toString() ?? '',
  );
}

/// Cabecera completa de una compra (fila de `fdi_dat_compra`).
class Compra {
  final int id;
  final int idTienda;
  final int numeroCompra;
  final int idProveedor;
  final String? numeroFactura;
  final DateTime? fechaFactura;
  final String monedaTotal;
  final double tasaFactura;
  final double totalMercancia;
  final double totalAjustes;
  final double totalFinanciado;
  final double costoAterrizado;
  final String modoLiquidacion;
  final String politicaPago;
  final String estado;
  final String? observacion;
  final String? idempotencyKey;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Compra({
    required this.id,
    required this.idTienda,
    required this.numeroCompra,
    required this.idProveedor,
    this.numeroFactura,
    this.fechaFactura,
    required this.monedaTotal,
    this.tasaFactura = 1,
    this.totalMercancia = 0,
    this.totalAjustes = 0,
    this.totalFinanciado = 0,
    this.costoAterrizado = 0,
    this.modoLiquidacion = 'fondo',
    this.politicaPago = 'al_pagar',
    this.estado = 'creada',
    this.observacion,
    this.idempotencyKey,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  String get estadoLegible => CompraEstado.etiquetaDe(estado);
  String get modoLiquidacionLegible =>
      CompraModoLiquidacion.etiquetaDe(modoLiquidacion);
  String get politicaPagoLegible => CompraPoliticaPago.etiquetaDe(politicaPago);

  /// Solo una compra recién creada se puede editar
  /// (la RPC rechaza cualquier otro estado).
  bool get esEditable => estado == 'creada';

  /// Solo una compra en `creada` y sin recepciones se puede cancelar; el
  /// "sin recepciones" lo valida la RPC, que es la que manda.
  bool get esCancelable => estado == 'creada';

  factory Compra.fromJson(Map<String, dynamic> j) => Compra(
    id: (j['id'] as num).toInt(),
    idTienda: (j['id_tienda'] as num).toInt(),
    numeroCompra: (j['numero_compra'] as num).toInt(),
    idProveedor: (j['id_proveedor'] as num).toInt(),
    numeroFactura: j['numero_factura']?.toString(),
    fechaFactura: j['fecha_factura'] != null
        ? DateTime.tryParse(j['fecha_factura'].toString())
        : null,
    monedaTotal: j['moneda_total']?.toString() ?? '',
    tasaFactura: (j['tasa_factura'] as num?)?.toDouble() ?? 1,
    totalMercancia: (j['total_mercancia'] as num?)?.toDouble() ?? 0,
    totalAjustes: (j['total_ajustes'] as num?)?.toDouble() ?? 0,
    totalFinanciado: (j['total_financiado'] as num?)?.toDouble() ?? 0,
    costoAterrizado: (j['costo_aterrizado'] as num?)?.toDouble() ?? 0,
    modoLiquidacion: j['modo_liquidacion']?.toString() ?? 'fondo',
    politicaPago: j['politica_pago']?.toString() ?? 'al_pagar',
    estado: j['estado']?.toString() ?? 'creada',
    observacion: j['observacion']?.toString(),
    idempotencyKey: j['idempotency_key']?.toString(),
    createdBy: j['created_by']?.toString(),
    createdAt: j['created_at'] != null
        ? DateTime.tryParse(j['created_at'].toString())
        : null,
    updatedAt: j['updated_at'] != null
        ? DateTime.tryParse(j['updated_at'].toString())
        : null,
  );
}

/// Fila del listado (`fn_fdi_compra_listar`).
class CompraResumen {
  final int id;
  final int numeroCompra;
  final int idProveedor;
  final String proveedor;
  final String? numeroFactura;
  final DateTime? fechaFactura;
  final String monedaTotal;
  final double totalMercancia;
  final double totalAjustes;
  final double totalFinanciado;
  final double costoAterrizado;
  final String modoLiquidacion;
  final String politicaPago;
  final String estado;
  final String? observacion;
  final DateTime? createdAt;

  /// Cantidad de líneas de la compra.
  final int lineas;

  const CompraResumen({
    required this.id,
    required this.numeroCompra,
    required this.idProveedor,
    required this.proveedor,
    this.numeroFactura,
    this.fechaFactura,
    required this.monedaTotal,
    this.totalMercancia = 0,
    this.totalAjustes = 0,
    this.totalFinanciado = 0,
    this.costoAterrizado = 0,
    this.modoLiquidacion = 'fondo',
    this.politicaPago = 'al_pagar',
    this.estado = 'creada',
    this.observacion,
    this.createdAt,
    this.lineas = 0,
  });

  String get estadoLegible => CompraEstado.etiquetaDe(estado);
  String get modoLiquidacionLegible =>
      CompraModoLiquidacion.etiquetaDe(modoLiquidacion);
  String get politicaPagoLegible => CompraPoliticaPago.etiquetaDe(politicaPago);
  bool get esCancelable => estado == 'creada';

  factory CompraResumen.fromJson(Map<String, dynamic> j) => CompraResumen(
    id: (j['id'] as num).toInt(),
    numeroCompra: (j['numero_compra'] as num).toInt(),
    idProveedor: (j['id_proveedor'] as num).toInt(),
    proveedor: j['proveedor']?.toString() ?? '',
    numeroFactura: j['numero_factura']?.toString(),
    fechaFactura: j['fecha_factura'] != null
        ? DateTime.tryParse(j['fecha_factura'].toString())
        : null,
    monedaTotal: j['moneda_total']?.toString() ?? '',
    totalMercancia: (j['total_mercancia'] as num?)?.toDouble() ?? 0,
    totalAjustes: (j['total_ajustes'] as num?)?.toDouble() ?? 0,
    totalFinanciado: (j['total_financiado'] as num?)?.toDouble() ?? 0,
    costoAterrizado: (j['costo_aterrizado'] as num?)?.toDouble() ?? 0,
    modoLiquidacion: j['modo_liquidacion']?.toString() ?? 'fondo',
    politicaPago: j['politica_pago']?.toString() ?? 'al_pagar',
    estado: j['estado']?.toString() ?? 'creada',
    observacion: j['observacion']?.toString(),
    createdAt: j['created_at'] != null
        ? DateTime.tryParse(j['created_at'].toString())
        : null,
    lineas: (j['lineas'] as num?)?.toInt() ?? 0,
  );
}

/// Respuesta completa de `fn_fdi_compra_detalle`.
class CompraDetalle {
  final Compra compra;
  final CompraProveedor? proveedor;
  final List<CompraLinea> lineas;
  final List<CompraAjuste> ajustes;
  final List<CompraHistorico> historial;

  /// Filas de `fdi_dat_compra_recepcion` sin modelo propio: la fase de
  /// recepciones aún no define su contrato de lectura.
  final List<Map<String, dynamic>> recepciones;

  const CompraDetalle({
    required this.compra,
    this.proveedor,
    this.lineas = const [],
    this.ajustes = const [],
    this.historial = const [],
    this.recepciones = const [],
  });

  int get idCompra => compra.id;
  int get numeroCompra => compra.numeroCompra;
  String get proveedorNombre => proveedor?.denominacion ?? '';
  bool get tieneRecepciones => recepciones.isNotEmpty;

  factory CompraDetalle.fromJson(Map<String, dynamic> j) => CompraDetalle(
    compra: Compra.fromJson(Map<String, dynamic>.from(j['compra'] as Map)),
    proveedor: j['proveedor'] is Map
        ? CompraProveedor.fromJson(
            Map<String, dynamic>.from(j['proveedor'] as Map),
          )
        : null,
    lineas: ((j['lineas'] as List?) ?? [])
        .map((e) => CompraLinea.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    ajustes: ((j['ajustes'] as List?) ?? [])
        .map((e) => CompraAjuste.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    historial: ((j['historial'] as List?) ?? [])
        .map(
          (e) => CompraHistorico.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList(),
    recepciones: ((j['recepciones'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(),
  );
}

// ==========================================================================
// Liquidación (reserva y pago con el fondo)
// ==========================================================================

/// Una cuenta/medio con saldo para financiar la compra.
///
/// Es una fila de `fn_fdi_disponible(p_id_tienda)`, cuyo jsonb trae
/// `{id_cuenta, cuenta, id_medio_pago, medio_pago, moneda, saldo, reservado,
/// disponible}`. `reservado` es lo comprometido por reservas vivas y
/// `disponible` lo que la RPC acepta como máximo para esa cuenta.
class DisponibleFondo {
  final int idCuenta;
  final String cuenta;
  final int idMedioPago;
  final String medioPago;
  final String moneda;
  final double saldo;
  final double reservado;
  final double disponible;

  const DisponibleFondo({
    required this.idCuenta,
    required this.cuenta,
    required this.idMedioPago,
    required this.medioPago,
    required this.moneda,
    this.saldo = 0,
    this.reservado = 0,
    this.disponible = 0,
  });

  /// El método de pago con `disponible == 0` sigue en la lista para poder
  /// mostrarlo deshabilitado; quien pinta decide, aquí solo se informa.
  bool get tieneDisponible => disponible > 0;

  /// Texto para el selector: `cuenta · medio · moneda`.
  String get etiqueta => '$cuenta · $medioPago · $moneda';

  factory DisponibleFondo.fromJson(Map<String, dynamic> j) => DisponibleFondo(
    idCuenta: (j['id_cuenta'] as num?)?.toInt() ?? 0,
    cuenta: j['cuenta']?.toString() ?? '',
    idMedioPago: (j['id_medio_pago'] as num?)?.toInt() ?? 0,
    medioPago: j['medio_pago']?.toString() ?? '',
    moneda: j['moneda']?.toString() ?? '',
    saldo: (j['saldo'] as num?)?.toDouble() ?? 0,
    reservado: (j['reservado'] as num?)?.toDouble() ?? 0,
    disponible: (j['disponible'] as num?)?.toDouble() ?? 0,
  );
}

/// Una fuente de financiación enviada a `fn_fdi_compra_reservar` en
/// `p_fuentes`.
///
/// Ojo con las unidades: [monto] está en la moneda **nativa** de la cuenta
/// ([moneda]) y [tasaATotal] la lleva a la moneda del total de la compra. El
/// equivalente que compara la RPC —y el que suma [ResumenCobertura]— es
/// [montoEqTotal], ya redondeado a 2 decimales por fuente.
class FuenteReserva {
  final int idCuenta;
  final int idMedioPago;
  final String moneda;
  final double monto;
  final double tasaATotal;

  const FuenteReserva({
    required this.idCuenta,
    required this.idMedioPago,
    required this.moneda,
    required this.monto,
    this.tasaATotal = 1,
  });

  /// `round(monto * tasaATotal, 2)`; la RPC suma los equivalentes ya
  /// redondeados, no el total redondeado al final.
  double get montoEqTotal => _redondear2(monto * tasaATotal);

  factory FuenteReserva.fromJson(Map<String, dynamic> j) => FuenteReserva(
    idCuenta: (j['id_cuenta'] as num?)?.toInt() ?? 0,
    idMedioPago: (j['id_medio_pago'] as num?)?.toInt() ?? 0,
    moneda: j['moneda']?.toString() ?? '',
    monto: (j['monto'] as num?)?.toDouble() ?? 0,
    tasaATotal: (j['tasa_a_total'] as num?)?.toDouble() ?? 1,
  );

  /// Claves exactas que espera `p_fuentes`.
  Map<String, dynamic> toJson() => {
    'id_cuenta': idCuenta,
    'id_medio_pago': idMedioPago,
    'moneda': moneda,
    'monto': monto,
    'tasa_a_total': tasaATotal,
  };
}

/// Aritmética de cobertura en cliente: lo que decide, antes de llamar a la
/// RPC, si las fuentes propuestas cubren el total de la compra.
///
/// Se calcula en centavos enteros sobre el equivalente redondeado de cada
/// fuente ([FuenteReserva.montoEqTotal]), igual que valida el servidor; así
/// `0.1 + 0.2` no convierte una cobertura exacta en un falso faltante.
/// [total] es el total de la compra en su moneda (normalmente
/// `Compra.totalFinanciado`). Es pura y no toca la red.
class ResumenCobertura {
  final List<FuenteReserva> fuentes;
  final double total;

  const ResumenCobertura({this.fuentes = const [], this.total = 0});

  int get _centavosFinanciado => fuentes.fold<int>(
    0,
    (acc, f) => acc + (f.montoEqTotal * 100).round(),
  );

  int get _centavosTotal => (total * 100).round();

  /// Suma de los equivalentes en la moneda del total.
  double get totalFinanciado => _centavosFinanciado / 100;

  /// Lo que de verdad se aplica al total: el financiado sin el excedente.
  double get aportado {
    final f = _centavosFinanciado;
    final t = _centavosTotal;
    return (f < t ? f : t) / 100;
  }

  /// Cuánto falta para cubrir el total (0 si ya cubre o sobra).
  double get faltante {
    final f = _centavosFinanciado;
    final t = _centavosTotal;
    return (f >= t ? 0 : t - f) / 100;
  }

  /// Excedente financiado por encima del total (0 si falta o cubre exacto).
  double get sobra {
    final f = _centavosFinanciado;
    final t = _centavosTotal;
    return (f > t ? f - t : 0) / 100;
  }

  /// Cubre exacto, sin faltante **ni** excedente: es la única condición que
  /// acepta la reserva.
  bool get cubreExacto => _centavosFinanciado == _centavosTotal;

  /// Cubre al menos el total (incluye el caso con excedente).
  bool get cubre => _centavosFinanciado >= _centavosTotal;
}
