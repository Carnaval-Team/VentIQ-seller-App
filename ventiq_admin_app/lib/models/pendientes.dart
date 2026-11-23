/// Modelos de la fase 9 de Compras: pendientes de recepción, detalle por
/// línea, histórico de recepciones y vista de facturas.
///
/// Contrato: `lib/sql/compra/09_pendientes.sql`. Las claves JSON son las que
/// devuelven las cuatro funciones (snake_case) y **no se inventa ninguna**:
///
///   · `fn_fdi_pendientes_panel(bigint, text)`
///   · `fn_fdi_pendientes_detalle(bigint, bigint)`
///   · `fn_fdi_recepciones_historial(bigint, date, date)`
///   · `fn_fdi_facturas(bigint, date, date)`
///
/// Regla que atraviesa todo el archivo: **ningún agregado suma monedas
/// distintas**. Los totales viven siempre en [TotalPendienteMoneda] y amigos,
/// uno por moneda; no existe —ni debe existir— un «total» escalar del panel.
library;

import 'compra.dart' show OrigenPagoAjuste;

// ===========================================================================
// Lectura tolerante del JSON (numeric puede llegar como número o como texto)
// ===========================================================================

double aDouble(dynamic valor) {
  if (valor == null) return 0;
  if (valor is num) return valor.isFinite ? valor.toDouble() : 0;
  return double.tryParse(valor.toString().trim()) ?? 0;
}

double? aDoubleONulo(dynamic valor) {
  if (valor == null) return null;
  if (valor is num) return valor.isFinite ? valor.toDouble() : null;
  return double.tryParse(valor.toString().trim());
}

int aEntero(dynamic valor, {int porDefecto = 0}) {
  if (valor == null) return porDefecto;
  if (valor is num) return valor.isFinite ? valor.toInt() : porDefecto;
  return int.tryParse(valor.toString().trim()) ?? porDefecto;
}

int? aEnteroONulo(dynamic valor) {
  if (valor == null) return null;
  if (valor is num) return valor.isFinite ? valor.toInt() : null;
  return int.tryParse(valor.toString().trim());
}

/// Acepta `date` (`YYYY-MM-DD`) y `timestamptz` (ISO 8601). Un valor ilegible
/// se devuelve como `null`: nunca se inventa una fecha.
DateTime? aFecha(dynamic valor) {
  if (valor == null) return null;
  final texto = valor.toString().trim();
  if (texto.isEmpty) return null;
  return DateTime.tryParse(texto);
}

String? aTexto(dynamic valor) {
  if (valor == null) return null;
  final texto = valor.toString().trim();
  return texto.isEmpty ? null : texto;
}

List<Map<String, dynamic>> aListaDeMapas(dynamic valor) {
  if (valor is! List) return const [];
  return valor
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList(growable: false);
}

// ===========================================================================
// Cálculos puros del contrato
// ===========================================================================

/// Umbral por defecto de antigüedad que la UI resalta en naranja.
///
/// No es un filtro: el panel no se filtra por umbral, solo se avisa.
const int umbralAntiguedadDias = 15;

/// `recibido_pct` del contrato: razón `Σ recibido / Σ pedido` acotada a [0, 1],
/// sin moneda y redondeada a 6 decimales como `round(x, 6)` de PostgreSQL.
///
/// Se usa solo cuando el JSON no trae la clave; el número del servidor manda.
double recibidoPctCalculado({required double pedido, required double recibido}) {
  if (pedido <= 0) return 0;
  final razon = recibido / pedido;
  if (!razon.isFinite) return 0;
  final redondeado = double.parse(razon.toStringAsFixed(6));
  if (redondeado < 0) return 0;
  return redondeado > 1 ? 1 : redondeado;
}

/// Porcentaje entero para la barra fina (0..100).
int porcentajeRecibido(double pct) => (pct.clamp(0, 1) * 100).round();

/// Antigüedad en prosa: `Hoy`, `1 día`, `16 días`.
String textoDias(int dias) {
  if (dias <= 0) return 'Hoy';
  return dias == 1 ? '1 día' : '$dias días';
}

/// Antigüedad corta para chips y tablas: `0 d`, `1 d`, `16 d`.
String textoDiasCorto(int dias) => '${dias < 0 ? 0 : dias} d';

/// Los días que superan el umbral se resaltan; no se filtran.
bool superaUmbralAntiguedad(
  int dias, {
  int umbral = umbralAntiguedadDias,
}) => dias > umbral;

/// «Última recepción 12/11 · 4 d sin movimiento» o «Sin recepciones · 21 d…».
String textoRecepcionYDias(DateTime? ultimaRecepcion, int diasSinMovimiento) {
  final dias = textoDiasCorto(diasSinMovimiento);
  if (ultimaRecepcion == null) return 'Sin recepciones · $dias sin movimiento';
  final dia = ultimaRecepcion.day.toString().padLeft(2, '0');
  final mes = ultimaRecepcion.month.toString().padLeft(2, '0');
  return 'Últ. recepción $dia/$mes · $dias sin movimiento';
}

// ===========================================================================
// Orden del panel
// ===========================================================================

/// Los dos únicos valores que acepta `p_orden`. Cualquier otro revienta con
/// 22023 en el servidor, así que el cliente no inventa un tercero.
enum PendientesOrden {
  antiguedad('antiguedad', 'Más antiguas'),
  monto('monto', 'Mayor pendiente');

  const PendientesOrden(this.codigo, this.etiqueta);

  final String codigo;
  final String etiqueta;

  static PendientesOrden desde(String? codigo) {
    final limpio = codigo?.trim().toLowerCase();
    return limpio == 'monto' ? PendientesOrden.monto : PendientesOrden.antiguedad;
  }
}

// ===========================================================================
// Estado de recepción de una factura (`estado_recepcion`)
// ===========================================================================

/// `sin recibir` | `parcial` | `completa`, tal como lo calcula
/// `fn_fdi_facturas`. El color sale de la misma paleta de estados de compra
/// (ver `compras_widgets.dart`), no de una paleta nueva.
enum EstadoRecepcion {
  sinRecibir('sin recibir', 'Sin recibir'),
  parcial('parcial', 'Parcial'),
  completa('completa', 'Completa');

  const EstadoRecepcion(this.codigo, this.etiqueta);

  final String codigo;
  final String etiqueta;

  static EstadoRecepcion desde(String? codigo) {
    switch (codigo?.trim().toLowerCase()) {
      case 'completa':
        return EstadoRecepcion.completa;
      case 'parcial':
        return EstadoRecepcion.parcial;
      default:
        return EstadoRecepcion.sinRecibir;
    }
  }

  static String etiquetaDe(String? codigo) => desde(codigo).etiqueta;
}

// ===========================================================================
// Panel de pendientes
// ===========================================================================

/// Una compra abierta del panel (`compras[]`).
class PendienteCompra {
  final int idCompra;
  final int numeroCompra;
  final String? numeroFactura;
  final String? proveedor;
  final DateTime? fechaFactura;
  final String estado;
  final String moneda;
  final int diasAntiguedad;
  final int lineas;
  final double pedido;
  final double recibido;
  final double recibidoPct;
  final double montoTotal;
  final double montoPendiente;
  final DateTime? ultimaRecepcion;
  final int diasSinMovimiento;

  const PendienteCompra({
    required this.idCompra,
    required this.numeroCompra,
    this.numeroFactura,
    this.proveedor,
    this.fechaFactura,
    this.estado = 'creada',
    this.moneda = '',
    this.diasAntiguedad = 0,
    this.lineas = 0,
    this.pedido = 0,
    this.recibido = 0,
    this.recibidoPct = 0,
    this.montoTotal = 0,
    this.montoPendiente = 0,
    this.ultimaRecepcion,
    this.diasSinMovimiento = 0,
  });

  /// Sin nada recibido: la fila se lee «Sin recepción».
  bool get sinRecepcion => recibido <= 0;

  /// «#1042» del panel; el número de compra es entero en la tabla.
  String get etiquetaCompra => '#$numeroCompra';

  /// «40 / 100» — cantidades, nunca importes.
  String get textoPedidoRecibido =>
      '${_cantidad(recibido)} / ${_cantidad(pedido)}';

  factory PendienteCompra.fromJson(Map<String, dynamic> j) {
    final pedido = aDouble(j['pedido']);
    final recibido = aDouble(j['recibido']);
    return PendienteCompra(
      idCompra: aEntero(j['id_compra']),
      numeroCompra: aEntero(j['numero_compra']),
      numeroFactura: aTexto(j['numero_factura']),
      proveedor: aTexto(j['proveedor']),
      fechaFactura: aFecha(j['fecha_factura']),
      estado: aTexto(j['estado']) ?? 'creada',
      moneda: aTexto(j['moneda']) ?? '',
      diasAntiguedad: aEntero(j['dias_antiguedad']),
      lineas: aEntero(j['lineas']),
      pedido: pedido,
      recibido: recibido,
      recibidoPct:
          aDoubleONulo(j['recibido_pct']) ??
          recibidoPctCalculado(pedido: pedido, recibido: recibido),
      montoTotal: aDouble(j['monto_total']),
      montoPendiente: aDouble(j['monto_pendiente']),
      ultimaRecepcion: aFecha(j['ultima_recepcion']),
      diasSinMovimiento: aEntero(j['dias_sin_movimiento']),
    );
  }
}

/// Un bloque de totales del panel, **por moneda**.
class TotalPendienteMoneda {
  final String moneda;
  final int compras;
  final double montoTotal;
  final double montoPendiente;

  const TotalPendienteMoneda({
    required this.moneda,
    this.compras = 0,
    this.montoTotal = 0,
    this.montoPendiente = 0,
  });

  factory TotalPendienteMoneda.fromJson(Map<String, dynamic> j) =>
      TotalPendienteMoneda(
        moneda: aTexto(j['moneda']) ?? '',
        compras: aEntero(j['compras']),
        montoTotal: aDouble(j['monto_total']),
        montoPendiente: aDouble(j['monto_pendiente']),
      );
}

/// Payload completo de `fn_fdi_pendientes_panel`.
class PendientesPanel {
  final int idTienda;
  final PendientesOrden orden;
  final DateTime? generadoAt;
  final List<PendienteCompra> compras;
  final List<TotalPendienteMoneda> totalesPorMoneda;

  const PendientesPanel({
    required this.idTienda,
    this.orden = PendientesOrden.antiguedad,
    this.generadoAt,
    this.compras = const [],
    this.totalesPorMoneda = const [],
  });

  bool get vacio => compras.isEmpty;

  int get comprasAbiertas => compras.length;

  /// Compras sin ninguna recepción (bloque «sin recepción» de la franja).
  int get sinRecepcion => compras.where((c) => c.sinRecepcion).length;

  /// La más antigua **según el orden que devolvió el servidor**: no se
  /// reordena en cliente.
  PendienteCompra? get masAntigua {
    if (compras.isEmpty) return null;
    var mayor = compras.first;
    for (final c in compras) {
      if (c.diasAntiguedad > mayor.diasAntiguedad) mayor = c;
    }
    return mayor;
  }

  /// Cuántas superan el umbral (solo para el pie; no filtra).
  int get sobreUmbral => compras
      .where((c) => superaUmbralAntiguedad(c.diasAntiguedad))
      .length;

  /// Compras por moneda: alimenta la franja cuando no hay permiso de importes,
  /// donde un monto se sustituye por conteos.
  Map<String, int> get comprasPorMoneda {
    final mapa = <String, int>{};
    for (final c in compras) {
      final moneda = c.moneda.trim().isEmpty ? '—' : c.moneda.trim();
      mapa[moneda] = (mapa[moneda] ?? 0) + 1;
    }
    return mapa;
  }

  factory PendientesPanel.fromJson(Map<String, dynamic> j) => PendientesPanel(
    idTienda: aEntero(j['id_tienda']),
    orden: PendientesOrden.desde(aTexto(j['orden'])),
    generadoAt: aFecha(j['generado_at']),
    compras: aListaDeMapas(j['compras'])
        .map(PendienteCompra.fromJson)
        .toList(growable: false),
    totalesPorMoneda: aListaDeMapas(
      j['totales_por_moneda'],
    ).map(TotalPendienteMoneda.fromJson).toList(growable: false),
  );
}

// ===========================================================================
// Detalle por línea de una compra
// ===========================================================================

/// Una línea de `lineas[]` en `fn_fdi_pendientes_detalle`.
class LineaPendienteCompra {
  final int idCompraLinea;
  final String producto;
  final String? variante;
  final String? presentacion;
  final int? idAlmacen;
  final int? idUbicacion;
  final double cantidad;
  final double recibido;
  final double pendiente;
  final double costoUnitario;
  final double montoPendiente;
  final DateTime? ultimaRecepcion;
  final int diasSinMovimiento;

  const LineaPendienteCompra({
    required this.idCompraLinea,
    this.producto = '',
    this.variante,
    this.presentacion,
    this.idAlmacen,
    this.idUbicacion,
    this.cantidad = 0,
    this.recibido = 0,
    this.pendiente = 0,
    this.costoUnitario = 0,
    this.montoPendiente = 0,
    this.ultimaRecepcion,
    this.diasSinMovimiento = 0,
  });

  /// `pendiente` viene acotado a 0 por línea, pero la fila se pinta con el
  /// mismo criterio por si llegara un valor raro.
  bool get tienePendiente => pendiente > 0;

  String get textoPresentacion {
    final partes = [
      if (presentacion != null && presentacion!.isNotEmpty) presentacion!,
      if (variante != null && variante!.isNotEmpty) variante!,
    ];
    return partes.isEmpty ? '—' : partes.join(' · ');
  }

  factory LineaPendienteCompra.fromJson(Map<String, dynamic> j) =>
      LineaPendienteCompra(
        idCompraLinea: aEntero(j['id_compra_linea']),
        producto: aTexto(j['producto']) ?? '',
        variante: aTexto(j['variante']),
        presentacion: aTexto(j['presentacion']),
        idAlmacen: aEnteroONulo(j['id_almacen']),
        idUbicacion: aEnteroONulo(j['id_ubicacion']),
        cantidad: aDouble(j['cantidad']),
        recibido: aDouble(j['recibido']),
        pendiente: aDouble(j['pendiente']),
        costoUnitario: aDouble(j['costo_unitario']),
        montoPendiente: aDouble(j['monto_pendiente']),
        ultimaRecepcion: aFecha(j['ultima_recepcion']),
        diasSinMovimiento: aEntero(j['dias_sin_movimiento']),
      );
}

/// Cabecera (`compra`) de `fn_fdi_pendientes_detalle`: los mismos agregados que
/// la fila del panel, para que pantalla y tabla cuadren.
class CompraPendienteCabecera {
  final int idCompra;
  final int numeroCompra;
  final String? numeroFactura;
  final String? proveedor;
  final DateTime? fechaFactura;
  final String estado;
  final String moneda;
  final double tasaFactura;
  final double totalMercancia;
  final double totalAjustes;
  final double totalFinanciado;
  final double costoAterrizado;
  final String? observacion;
  final DateTime? createdAt;
  final int diasAntiguedad;
  final int numLineas;
  final double pedido;
  final double recibido;
  final double recibidoPct;
  final double montoTotal;
  final double montoPendiente;
  final DateTime? ultimaRecepcion;
  final int diasSinMovimiento;

  const CompraPendienteCabecera({
    required this.idCompra,
    required this.numeroCompra,
    this.numeroFactura,
    this.proveedor,
    this.fechaFactura,
    this.estado = 'creada',
    this.moneda = '',
    this.tasaFactura = 1,
    this.totalMercancia = 0,
    this.totalAjustes = 0,
    this.totalFinanciado = 0,
    this.costoAterrizado = 0,
    this.observacion,
    this.createdAt,
    this.diasAntiguedad = 0,
    this.numLineas = 0,
    this.pedido = 0,
    this.recibido = 0,
    this.recibidoPct = 0,
    this.montoTotal = 0,
    this.montoPendiente = 0,
    this.ultimaRecepcion,
    this.diasSinMovimiento = 0,
  });

  String get etiquetaCompra => '#$numeroCompra';

  String get textoPedidoRecibido =>
      '${_cantidad(recibido)} de ${_cantidad(pedido)}';

  factory CompraPendienteCabecera.fromJson(Map<String, dynamic> j) {
    final pedido = aDouble(j['pedido']);
    final recibido = aDouble(j['recibido']);
    return CompraPendienteCabecera(
      idCompra: aEntero(j['id_compra']),
      numeroCompra: aEntero(j['numero_compra']),
      numeroFactura: aTexto(j['numero_factura']),
      proveedor: aTexto(j['proveedor']),
      fechaFactura: aFecha(j['fecha_factura']),
      estado: aTexto(j['estado']) ?? 'creada',
      moneda: aTexto(j['moneda']) ?? '',
      tasaFactura: aDouble(j['tasa_factura']) == 0
          ? 1
          : aDouble(j['tasa_factura']),
      totalMercancia: aDouble(j['total_mercancia']),
      totalAjustes: aDouble(j['total_ajustes']),
      totalFinanciado: aDouble(j['total_financiado']),
      costoAterrizado: aDouble(j['costo_aterrizado']),
      observacion: aTexto(j['observacion']),
      createdAt: aFecha(j['created_at']),
      diasAntiguedad: aEntero(j['dias_antiguedad']),
      numLineas: aEntero(j['lineas']),
      pedido: pedido,
      recibido: recibido,
      recibidoPct:
          aDoubleONulo(j['recibido_pct']) ??
          recibidoPctCalculado(pedido: pedido, recibido: recibido),
      montoTotal: aDouble(j['monto_total']),
      montoPendiente: aDouble(j['monto_pendiente']),
      ultimaRecepcion: aFecha(j['ultima_recepcion']),
      diasSinMovimiento: aEntero(j['dias_sin_movimiento']),
    );
  }
}

/// Totales del detalle, por moneda (`totales_por_moneda`).
class TotalDetalleMoneda {
  final String moneda;
  final int lineas;
  final double montoTotal;
  final double montoPendiente;

  const TotalDetalleMoneda({
    required this.moneda,
    this.lineas = 0,
    this.montoTotal = 0,
    this.montoPendiente = 0,
  });

  factory TotalDetalleMoneda.fromJson(Map<String, dynamic> j) =>
      TotalDetalleMoneda(
        moneda: aTexto(j['moneda']) ?? '',
        lineas: aEntero(j['lineas']),
        montoTotal: aDouble(j['monto_total']),
        montoPendiente: aDouble(j['monto_pendiente']),
      );
}

/// Payload completo de `fn_fdi_pendientes_detalle`.
class PendienteDetalle {
  final int idTienda;
  final CompraPendienteCabecera compra;
  final List<LineaPendienteCompra> lineas;
  final List<TotalDetalleMoneda> totalesPorMoneda;

  const PendienteDetalle({
    required this.idTienda,
    required this.compra,
    this.lineas = const [],
    this.totalesPorMoneda = const [],
  });

  bool get vacio => lineas.isEmpty;

  int get lineasConPendiente =>
      lineas.where((l) => l.tienePendiente).length;

  int get lineasSinRecepcion => lineas.where((l) => l.recibido <= 0).length;

  /// Σ `monto_pendiente` de las líneas. Se compara con el agregado del
  /// servidor en el test de contrato: aquí no se mezcla ninguna moneda.
  double get sumaLineasPendiente {
    var total = 0.0;
    for (final l in lineas) {
      total += l.montoPendiente;
    }
    return double.parse(total.toStringAsFixed(2));
  }

  factory PendienteDetalle.fromJson(Map<String, dynamic> j) => PendienteDetalle(
    idTienda: aEntero(j['id_tienda']),
    compra: CompraPendienteCabecera.fromJson(
      j['compra'] is Map
          ? Map<String, dynamic>.from(j['compra'] as Map)
          : const <String, dynamic>{},
    ),
    lineas: aListaDeMapas(j['lineas'])
        .map(LineaPendienteCompra.fromJson)
        .toList(growable: false),
    totalesPorMoneda: aListaDeMapas(
      j['totales_por_moneda'],
    ).map(TotalDetalleMoneda.fromJson).toList(growable: false),
  );
}

// ===========================================================================
// Histórico de recepciones
// ===========================================================================

/// Una fila de `recepciones[]` (`fn_fdi_recepciones_historial`): un vínculo
/// `fdi_dat_compra_recepcion` con su estado de operación.
class RecepcionHistorial {
  final int idRecepcion;
  final int? idOperacion;
  final DateTime? fecha;
  final int? numeroCompra;
  final String? numeroFactura;
  final String? proveedor;
  final double montoValorizado;
  final String moneda;
  final String? origenPago;
  final double pctImportadora;
  final double montoImportadora;
  final int? estadoOperacion;
  final String? estadoOperacionNombre;
  final int lineas;
  final double cantidadRecibida;
  final String? productos;
  final DateTime? fechaOperacion;

  const RecepcionHistorial({
    required this.idRecepcion,
    this.idOperacion,
    this.fecha,
    this.numeroCompra,
    this.numeroFactura,
    this.proveedor,
    this.montoValorizado = 0,
    this.moneda = '',
    this.origenPago,
    this.pctImportadora = 0,
    this.montoImportadora = 0,
    this.estadoOperacion,
    this.estadoOperacionNombre,
    this.lineas = 0,
    this.cantidadRecibida = 0,
    this.productos,
    this.fechaOperacion,
  });

  String get origenPagoLegible =>
      OrigenPagoAjuste.etiquetaDe(origenPago ?? '');

  /// El histórico **no** devuelve `id_compra`: se empareja por número de
  /// compra, que es el identificador legible que sí trae.
  bool esDeCompra(int numeroCompra) => this.numeroCompra == numeroCompra;

  factory RecepcionHistorial.fromJson(Map<String, dynamic> j) =>
      RecepcionHistorial(
        idRecepcion: aEntero(j['id_recepcion']),
        idOperacion: aEnteroONulo(j['id_operacion']),
        fecha: aFecha(j['fecha']),
        numeroCompra: aEnteroONulo(j['numero_compra']),
        numeroFactura: aTexto(j['numero_factura']),
        proveedor: aTexto(j['proveedor']),
        montoValorizado: aDouble(j['monto_valorizado']),
        moneda: aTexto(j['moneda']) ?? '',
        origenPago: aTexto(j['origen_pago']),
        pctImportadora: aDouble(j['pct_importadora']),
        montoImportadora: aDouble(j['monto_importadora']),
        estadoOperacion: aEnteroONulo(j['estado_operacion']),
        estadoOperacionNombre: aTexto(j['estado_operacion_nombre']),
        lineas: aEntero(j['lineas']),
        cantidadRecibida: aDouble(j['cantidad_recibida']),
        productos: aTexto(j['productos']),
        fechaOperacion: aFecha(j['fecha_operacion']),
      );
}

/// Totales del histórico, por moneda.
class TotalRecepcionMoneda {
  final String moneda;
  final int recepciones;
  final double montoValorizado;
  final double montoImportadora;
  final double cantidadRecibida;

  const TotalRecepcionMoneda({
    required this.moneda,
    this.recepciones = 0,
    this.montoValorizado = 0,
    this.montoImportadora = 0,
    this.cantidadRecibida = 0,
  });

  factory TotalRecepcionMoneda.fromJson(Map<String, dynamic> j) =>
      TotalRecepcionMoneda(
        moneda: aTexto(j['moneda']) ?? '',
        recepciones: aEntero(j['recepciones']),
        montoValorizado: aDouble(j['monto_valorizado']),
        montoImportadora: aDouble(j['monto_importadora']),
        cantidadRecibida: aDouble(j['cantidad_recibida']),
      );
}

/// Payload completo de `fn_fdi_recepciones_historial`.
class HistorialRecepciones {
  final int idTienda;
  final DateTime? desde;
  final DateTime? hasta;
  final DateTime? generadoAt;
  final List<RecepcionHistorial> recepciones;
  final List<TotalRecepcionMoneda> totalesPorMoneda;

  const HistorialRecepciones({
    required this.idTienda,
    this.desde,
    this.hasta,
    this.generadoAt,
    this.recepciones = const [],
    this.totalesPorMoneda = const [],
  });

  /// Las recepciones de una compra, filtradas en cliente por número de compra
  /// (el histórico no expone `id_compra`).
  List<RecepcionHistorial> deCompra(int numeroCompra) =>
      recepciones.where((r) => r.esDeCompra(numeroCompra)).toList(
        growable: false,
      );

  factory HistorialRecepciones.fromJson(Map<String, dynamic> j) =>
      HistorialRecepciones(
        idTienda: aEntero(j['id_tienda']),
        desde: aFecha(j['desde']),
        hasta: aFecha(j['hasta']),
        generadoAt: aFecha(j['generado_at']),
        recepciones: aListaDeMapas(
          j['recepciones'],
        ).map(RecepcionHistorial.fromJson).toList(growable: false),
        totalesPorMoneda: aListaDeMapas(
          j['totales_por_moneda'],
        ).map(TotalRecepcionMoneda.fromJson).toList(growable: false),
      );
}

// ===========================================================================
// Vista de facturas
// ===========================================================================

/// Una fila de `facturas[]` (`fn_fdi_facturas`), incluidas las cerradas.
class FacturaResumen {
  final int idCompra;
  final String? numeroFactura;
  final int numeroCompra;
  final String? proveedor;
  final DateTime? fechaFactura;
  final String estado;
  final String moneda;
  final double totalFactura;
  final double aterrizado;
  final double pagado;
  final int recepciones;
  final double recibidoPct;
  final EstadoRecepcion estadoRecepcion;
  final DateTime? ultimaRecepcion;

  const FacturaResumen({
    required this.idCompra,
    required this.numeroCompra,
    this.numeroFactura,
    this.proveedor,
    this.fechaFactura,
    this.estado = 'creada',
    this.moneda = '',
    this.totalFactura = 0,
    this.aterrizado = 0,
    this.pagado = 0,
    this.recepciones = 0,
    this.recibidoPct = 0,
    this.estadoRecepcion = EstadoRecepcion.sinRecibir,
    this.ultimaRecepcion,
  });

  bool get sinRecepcion => estadoRecepcion == EstadoRecepcion.sinRecibir;

  String get etiquetaCompra => '#$numeroCompra';

  factory FacturaResumen.fromJson(Map<String, dynamic> j) {
    final pedido = aDouble(j['pedido']);
    final recibido = aDouble(j['recibido']);
    return FacturaResumen(
      idCompra: aEntero(j['id_compra']),
      numeroFactura: aTexto(j['numero_factura']),
      numeroCompra: aEntero(j['numero_compra']),
      proveedor: aTexto(j['proveedor']),
      fechaFactura: aFecha(j['fecha_factura']),
      estado: aTexto(j['estado']) ?? 'creada',
      moneda: aTexto(j['moneda']) ?? '',
      totalFactura: aDouble(j['total_factura']),
      aterrizado: aDouble(j['aterrizado']),
      pagado: aDouble(j['pagado']),
      recepciones: aEntero(j['recepciones']),
      recibidoPct: aDoubleONulo(j['recibido_pct']) ??
          recibidoPctCalculado(pedido: pedido, recibido: recibido),
      estadoRecepcion: EstadoRecepcion.desde(aTexto(j['estado_recepcion'])),
      ultimaRecepcion: aFecha(j['ultima_recepcion']),
    );
  }
}

/// Totales de facturas, por moneda.
class TotalFacturaMoneda {
  final String moneda;
  final int compras;
  final double totalFactura;
  final double aterrizado;
  final double pagado;

  const TotalFacturaMoneda({
    required this.moneda,
    this.compras = 0,
    this.totalFactura = 0,
    this.aterrizado = 0,
    this.pagado = 0,
  });

  factory TotalFacturaMoneda.fromJson(Map<String, dynamic> j) =>
      TotalFacturaMoneda(
        moneda: aTexto(j['moneda']) ?? '',
        compras: aEntero(j['compras']),
        totalFactura: aDouble(j['total_factura']),
        aterrizado: aDouble(j['aterrizado']),
        pagado: aDouble(j['pagado']),
      );
}

/// Payload completo de `fn_fdi_facturas`.
class FacturasVista {
  final int idTienda;
  final DateTime? desde;
  final DateTime? hasta;
  final DateTime? generadoAt;
  final List<FacturaResumen> facturas;
  final List<TotalFacturaMoneda> totalesPorMoneda;

  const FacturasVista({
    required this.idTienda,
    this.desde,
    this.hasta,
    this.generadoAt,
    this.facturas = const [],
    this.totalesPorMoneda = const [],
  });

  bool get vacio => facturas.isEmpty;

  int get total => facturas.length;

  int get sinRecibir =>
      facturas.where((f) => f.estadoRecepcion == EstadoRecepcion.sinRecibir).length;

  int get parciales =>
      facturas.where((f) => f.estadoRecepcion == EstadoRecepcion.parcial).length;

  int get completas =>
      facturas.where((f) => f.estadoRecepcion == EstadoRecepcion.completa).length;

  factory FacturasVista.fromJson(Map<String, dynamic> j) => FacturasVista(
    idTienda: aEntero(j['id_tienda']),
    desde: aFecha(j['desde']),
    hasta: aFecha(j['hasta']),
    generadoAt: aFecha(j['generado_at']),
    facturas: aListaDeMapas(
      j['facturas'],
    ).map(FacturaResumen.fromJson).toList(growable: false),
    totalesPorMoneda: aListaDeMapas(
      j['totales_por_moneda'],
    ).map(TotalFacturaMoneda.fromJson).toList(growable: false),
  );
}

// ===========================================================================
// Formato de cantidades y moneda (compartido por las tres pantallas)
// ===========================================================================

/// Cantidad sin ceros de relleno: `40`, `12,5`, `0,25`.
///
/// No usa `intl` para que el modelo siga siendo Dart puro (y testeable sin
/// inicializar la app).
String _cantidad(double valor) {
  if (!valor.isFinite) return '0';
  final redondeado = double.parse(valor.abs().toStringAsFixed(4));
  final partes = redondeado
      .toStringAsFixed(4)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '')
      .split('.');
  final decimales = partes.length > 1 ? partes[1] : '';
  return '${valor < 0 ? '-' : ''}${_agruparMiles(partes.first)}'
      '${decimales.isEmpty ? '' : ',$decimales'}';
}

String _agruparMiles(String digitos) {
  final buffer = StringBuffer();
  for (var i = 0; i < digitos.length; i++) {
    if (i > 0 && (digitos.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digitos[i]);
  }
  return buffer.toString();
}

/// Cantidad con el formato de los modelos (público para las pantallas).
String formatearCantidadContrato(double valor) => _cantidad(valor);