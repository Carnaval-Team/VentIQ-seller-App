/// Modelos del **resumen de reservas del admin** (punto 3 del plan).
///
/// Se parsean a mano, tolerantes a propósito, porque el payload lo arma una
/// función PL/pgSQL con `jsonb_build_object` y ya nos ha mordido antes
/// (`Agenda.fromJson` revienta con un `num` que llega como texto o con una
/// clave ausente):
///
/// - un entero puede llegar como `int`, `num` o `"7"`;
/// - un `date`/`timestamp` puede llegar como `String` ISO;
/// - `items`, `por_servicio` o el payload entero pueden llegar como `String`
///   (jsonb sin decodificar) o faltar;
/// - ninguna clave es obligatoria: si falta, se devuelve el neutro (`0`, `null`
///   o lista vacía) en vez de lanzar.
///
/// Ningún `fromJson` de este fichero lanza nunca. La pantalla decide qué hacer
/// con los ceros.
library;

import 'dart:convert';

// ── Lectura tolerante ────────────────────────────────────────────────────────

/// Convierte [valor] en `Map<String, dynamic>`; `{}` si no lo es.
///
/// Acepta un `String` porque un `jsonb` devuelto sin decodificar llega así.
Map<String, dynamic> _mapaJson(dynamic valor) {
  if (valor is Map) return Map<String, dynamic>.from(valor);
  if (valor is String && valor.trim().isNotEmpty) {
    final decodificado = _decodificar(valor);
    if (decodificado is Map) return Map<String, dynamic>.from(decodificado);
  }
  return const <String, dynamic>{};
}

/// Convierte [valor] en lista; `[]` si no lo es (o si es un `String` con JSON).
List<dynamic> _listaJson(dynamic valor) {
  if (valor is List) return valor;
  if (valor is String && valor.trim().isNotEmpty) {
    final decodificado = _decodificar(valor);
    if (decodificado is List) return decodificado;
  }
  return const <dynamic>[];
}

/// `jsonDecode` tolerante: si el texto no es JSON válido, se trata como
/// ausente (nunca propaga la excepción de `dart:convert`).
dynamic _decodificar(String texto) {
  try {
    return jsonDecode(texto);
  } catch (_) {
    return null;
  }
}

/// Entero tolerante: `num`, texto numérico o [defecto].
int _int(dynamic valor, {int defecto = 0}) {
  if (valor == null) return defecto;
  if (valor is int) return valor;
  if (valor is num) return valor.toInt();
  final texto = valor.toString().trim();
  if (texto.isEmpty) return defecto;
  final entero = int.tryParse(texto);
  if (entero != null) return entero;
  return double.tryParse(texto)?.toInt() ?? defecto;
}

/// `double?` tolerante: `num` o texto numérico.
double? _double(dynamic valor) {
  if (valor == null) return null;
  if (valor is double) return valor;
  if (valor is num) return valor.toDouble();
  final texto = valor.toString().trim();
  if (texto.isEmpty) return null;
  return double.tryParse(texto);
}

/// Texto tolerante: recorta y convierte el vacío en `null`.
String? _texto(dynamic valor) {
  if (valor == null) return null;
  final texto = valor.toString().trim();
  return texto.isEmpty ? null : texto;
}

/// `DateTime?` tolerante: `DateTime` o ISO-8601 (`yyyy-MM-dd` inclusive).
///
/// Un `date` (`2026-10-27`) se interpreta como medianoche **local**, que es el
/// mismo día que la RPC usa para agrupar (ella agrupa en hora de La Habana).
DateTime? _fecha(dynamic valor) {
  if (valor == null) return null;
  if (valor is DateTime) return valor;
  final texto = valor.toString().trim();
  if (texto.isEmpty) return null;
  return DateTime.tryParse(texto);
}

/// Bandera tolerante: `true`, `"true"`, `1` o `"1"`.
bool _bool(dynamic valor) {
  if (valor is bool) return valor;
  final texto = valor?.toString().trim().toLowerCase();
  return texto == 'true' || texto == '1';
}

/// Recorta un `DateTime` a su día (medianoche local).
DateTime _soloDia(DateTime f) => DateTime(f.year, f.month, f.day);

/// Día de hoy a medianoche, con el reloj local del dispositivo.
DateTime _hoyLocal() {
  final ahora = DateTime.now();
  return DateTime(ahora.year, ahora.month, ahora.day);
}

// ── Totales por servicio ─────────────────────────────────────────────────────

/// Fila de `resumen.por_servicio`.
class ServicioTotal {
  final String servicio;
  final int total;

  const ServicioTotal({required this.servicio, required this.total});

  factory ServicioTotal.fromJson(dynamic json) {
    final mapa = _mapaJson(json);
    return ServicioTotal(
      servicio: _texto(mapa['servicio']) ?? 'Sin servicio',
      total: _int(mapa['total']),
    );
  }

  @override
  String toString() => 'ServicioTotal($servicio, $total)';
}

/// `resumen` del payload: contadores del rango completo + ranking de servicios.
class TotalesResumen {
  final int total;
  final int reservadas;
  final int canceladas;
  final int completadas;
  final List<ServicioTotal> porServicio;

  const TotalesResumen({
    required this.total,
    required this.reservadas,
    required this.canceladas,
    required this.completadas,
    this.porServicio = const <ServicioTotal>[],
  });

  /// El neutro compartido: útil para pintar la tarjeta sin datos.
  static const TotalesResumen cero = TotalesResumen(
    total: 0,
    reservadas: 0,
    canceladas: 0,
    completadas: 0,
  );

  factory TotalesResumen.fromJson(dynamic json) {
    final mapa = _mapaJson(json);
    return TotalesResumen(
      total: _int(mapa['total']),
      reservadas: _int(mapa['reservadas']),
      canceladas: _int(mapa['canceladas']),
      completadas: _int(mapa['completadas']),
      porServicio: _listaJson(
        mapa['por_servicio'],
      ).whereType<Map>().map(ServicioTotal.fromJson).toList(growable: false),
    );
  }

  bool get estaVacio => total == 0;

  /// Los [cuantos] servicios con más reservas (el ranking ya viene ordenado).
  List<ServicioTotal> topServicios([int cuantos = 3]) {
    if (porServicio.length <= cuantos) return porServicio;
    return porServicio.sublist(0, cuantos);
  }
}

// ── Rango ────────────────────────────────────────────────────────────────────

/// `rango` del payload: el día del servidor, los extremos usados y el último
/// día que realmente tiene reservas.
class RangoReservas {
  final DateTime hoy;
  final DateTime desde;
  final DateTime hasta;

  /// `null` cuando la entidad no tiene ninguna reserva desde [desde].
  final DateTime? ultimoDiaConReserva;

  /// `true` si el servidor recortó el rango por el tope de seguridad.
  final bool truncado;

  const RangoReservas({
    required this.hoy,
    required this.desde,
    required this.hasta,
    this.ultimoDiaConReserva,
    this.truncado = false,
  });

  factory RangoReservas.fromJson(dynamic json) {
    final mapa = _mapaJson(json);
    final hoy = _soloDia(_fecha(mapa['hoy']) ?? _hoyLocal());
    final desdeBruto = _fecha(mapa['desde']);
    final desde = desdeBruto == null ? hoy : _soloDia(desdeBruto);
    final hastaBruto = _fecha(mapa['hasta']);
    final hastaSinNormalizar = hastaBruto == null
        ? desde
        : _soloDia(hastaBruto);
    final ultimo = _fecha(mapa['ultimo_dia_con_reserva']);

    return RangoReservas(
      hoy: hoy,
      desde: desde,
      // Un rango al revés no es un rango: se ancla en `desde`.
      hasta: hastaSinNormalizar.isBefore(desde) ? desde : hastaSinNormalizar,
      ultimoDiaConReserva: ultimo == null ? null : _soloDia(ultimo),
      truncado: _bool(mapa['truncado']),
    );
  }
}

// ── Reserva y día ────────────────────────────────────────────────────────────

/// Una reserva dentro de un día (los `items` del payload).
class ReservaResumen {
  final int id;
  final DateTime? fechaHoraReserva;
  final int cantidad;
  final int idEstado;

  /// Nombre del estado (`Reservado`, `Cancelado`, `Completado`…).
  final String estado;
  final String? servicio;
  final String? local;
  final String? cliente;
  final String? clienteTelefono;
  final String? turno;
  final String? motivoCancelacion;
  final String? canceladoPorRol;

  /// `pendiente`, `reportado`, `verificado`, `rechazado`, `expirado` o `null`.
  final String? pagoEstado;
  final double? precioTotal;
  final String? moneda;
  final int? idLocalServicio;

  const ReservaResumen({
    required this.id,
    this.fechaHoraReserva,
    this.cantidad = 1,
    this.idEstado = 0,
    this.estado = '',
    this.servicio,
    this.local,
    this.cliente,
    this.clienteTelefono,
    this.turno,
    this.motivoCancelacion,
    this.canceladoPorRol,
    this.pagoEstado,
    this.precioTotal,
    this.moneda,
    this.idLocalServicio,
  });

  factory ReservaResumen.fromJson(dynamic json) {
    final mapa = _mapaJson(json);
    return ReservaResumen(
      id: _int(mapa['id']),
      fechaHoraReserva: _fecha(mapa['fecha_hora_reserva']),
      cantidad: _int(mapa['cantidad'], defecto: 1),
      idEstado: _int(mapa['id_estado']),
      estado: _texto(mapa['estado']) ?? '',
      servicio: _texto(mapa['servicio']),
      local: _texto(mapa['local']),
      cliente: _texto(mapa['cliente']),
      clienteTelefono: _texto(mapa['cliente_telefono']),
      turno: _texto(mapa['turno']),
      motivoCancelacion: _texto(mapa['motivo_cancelacion']),
      canceladoPorRol: _texto(mapa['cancelado_por_rol']),
      pagoEstado: _texto(mapa['pago_estado']),
      precioTotal: _double(mapa['precio_total']),
      moneda: _texto(mapa['moneda']),
      idLocalServicio: mapa['id_local_servicio'] == null
          ? null
          : _int(mapa['id_local_servicio']),
    );
  }

  bool get esReservada => idEstado == 1;
  bool get esCancelada => idEstado == 2;
  bool get esCompletada => idEstado == 3;

  /// Mismo criterio que la RPC para `pagos_pendientes`: hay pago y no está
  /// verificado (incluye `reportado`, `rechazado` y `expirado`).
  bool get tienePagoPendiente =>
      pagoEstado != null && pagoEstado != 'verificado';

  /// Cantidad efectiva de personas (nunca menos de 1).
  int get personas => cantidad < 1 ? 1 : cantidad;
}

/// Un día del rango con sus contadores y —si se pidieron— sus reservas.
class DiaResumen {
  final DateTime fecha;
  final int total;
  final int reservadas;
  final int canceladas;
  final int completadas;
  final int personas;
  final int pagosPendientes;
  final List<ReservaResumen> items;

  const DiaResumen({
    required this.fecha,
    this.total = 0,
    this.reservadas = 0,
    this.canceladas = 0,
    this.completadas = 0,
    this.personas = 0,
    this.pagosPendientes = 0,
    this.items = const <ReservaResumen>[],
  });

  factory DiaResumen.fromJson(dynamic json) {
    final mapa = _mapaJson(json);
    final fecha = _fecha(mapa['fecha']);
    return DiaResumen(
      // Sin `fecha` legible el día no sirve para nada: se ancla en hoy para que
      // el objeto siga siendo válido y no arrastre al resto del parseo.
      fecha: fecha == null ? _hoyLocal() : _soloDia(fecha),
      total: _int(mapa['total']),
      reservadas: _int(mapa['reservadas']),
      canceladas: _int(mapa['canceladas']),
      completadas: _int(mapa['completadas']),
      personas: _int(mapa['personas']),
      pagosPendientes: _int(mapa['pagos_pendientes']),
      items: _listaJson(
        mapa['items'],
      ).whereType<Map>().map(ReservaResumen.fromJson).toList(growable: false),
    );
  }

  bool get tieneReservas => total > 0;

  /// Todas las reservas del día están canceladas (el marcador va en rojo).
  bool get soloCanceladas => total > 0 && canceladas == total;

  /// Reservas del día que siguen "vivas" (reservadas + completadas).
  int get activas => reservadas + completadas;

  /// Todas las reservas del día ya se completaron (el marcador va en azul).
  bool get todoCompletado => total > 0 && completadas == total;

  bool get hayPagosPendientes => pagosPendientes > 0;
}

/// Payload completo de `flow.admin_calendario_reservas`.
class ResumenReservas {
  final RangoReservas rango;
  final TotalesResumen resumen;
  final List<DiaResumen> dias;

  const ResumenReservas({
    required this.rango,
    this.resumen = TotalesResumen.cero,
    this.dias = const <DiaResumen>[],
  });

  factory ResumenReservas.fromJson(dynamic json) {
    final mapa = _mapaJson(json);
    return ResumenReservas(
      rango: RangoReservas.fromJson(mapa['rango']),
      resumen: TotalesResumen.fromJson(mapa['resumen']),
      dias: _listaJson(
        mapa['dias'],
      ).whereType<Map>().map(DiaResumen.fromJson).toList(growable: false),
    );
  }

  bool get estaVacio => resumen.total == 0;

  /// Solo los días con reservas, en orden cronológico.
  List<DiaResumen> get diasConReservas {
    final conReservas = dias.where((d) => d.tieneReservas).toList();
    conReservas.sort((a, b) => a.fecha.compareTo(b.fecha));
    return conReservas;
  }
}
