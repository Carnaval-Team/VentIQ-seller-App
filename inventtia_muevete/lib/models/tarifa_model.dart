import 'package:flutter/material.dart';

/// Modelos del flujo de taxi con precio fijo (sin negociación).
///
/// Fuente de verdad: `docs/plan-taxi-precio-fijo/13-contrato-app-rpc.md`.
/// La app NUNCA calcula ni envía el precio: sólo lee lo que devuelven
/// `fn_cotizar_viaje` y `fn_viajes_disponibles`.

// ── Helpers de lectura defensiva del jsonb ────────────────────────────────

double _toDouble(Object? value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

double? _toDoubleOrNull(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int _toInt(Object? value, [int fallback = 0]) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

int? _toIntOrNull(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

bool _toBool(Object? value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final v = value.toLowerCase();
    if (v == 'true' || v == 't' || v == '1') return true;
    if (v == 'false' || v == 'f' || v == '0') return false;
  }
  return fallback;
}

String? _toStr(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

Map<String, dynamic> _toMap(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

/// Icono del vehículo a partir del `tipo` del catálogo.
IconData iconoVehiculo(String? tipo) {
  switch ((tipo ?? '').toLowerCase()) {
    case 'moto':
      return Icons.two_wheeler;
    case 'auto':
      return Icons.directions_car;
    case 'microbus':
      return Icons.directions_bus;
    case 'camioneta':
      return Icons.airport_shuttle;
    case 'bicicleta':
      return Icons.pedal_bike;
    case 'tuktuk':
      return Icons.electric_rickshaw;
    case 'triciclo':
    case 'triciclo_electrico':
      return Icons.electric_rickshaw;
    case 'minivan':
      return Icons.directions_bus_filled;
    case 'camion':
      return Icons.local_shipping;
    default:
      return Icons.directions_car;
  }
}

// ── Catálogo de vehículos (muevete.v_catalogo_vehiculos) ──────────────────

/// Fila de `muevete.v_catalogo_vehiculos`.
///
/// `id` es lo que se manda como `p_id_tipo` en las RPC. `nombre` es la
/// etiqueta visible (incluye "Microbús" y "Triciclo Eléctrico").
class CatalogoVehiculo {
  final int id;
  final String tipo;
  final String nombre;
  final int orden;
  final int pasajerosMax;
  final String categoria;

  const CatalogoVehiculo({
    required this.id,
    required this.tipo,
    required this.nombre,
    this.orden = 0,
    this.pasajerosMax = 1,
    this.categoria = 'pasajero',
  });

  factory CatalogoVehiculo.fromJson(Map<String, dynamic> json) {
    final tipo = _toStr(json['tipo']) ?? 'auto';
    return CatalogoVehiculo(
      id: _toInt(json['id']),
      tipo: tipo,
      nombre: _toStr(json['nombre']) ?? tipo,
      orden: _toInt(json['orden']),
      pasajerosMax: _toInt(json['pasajeros_max'], 1),
      categoria: _toStr(json['categoria']) ?? 'pasajero',
    );
  }

  IconData get icon => iconoVehiculo(tipo);
}

// ── Cotización (fn_cotizar_viaje) ─────────────────────────────────────────

/// Resultado de `fn_cotizar_viaje`: el desglose que la app pinta en modo
/// sólo lectura.
class Cotizacion {
  /// Precio final al cliente (lo que se muestra grande).
  final double precioPlataforma;
  final double comisionPct;
  final double comisionMonto;

  /// Lo que le toca al chofer.
  final double precioChofer;

  /// `fijo` / `fijo_mas_km` / `por_km`.
  final String tarifaModo;
  final String? zonaNombre;
  final bool dentroDeZona;

  /// `fn_cotizar_viaje` devuelve `fallback_municipio` como BOOLEANO: true cuando
  /// no se encontró zona y se aplicó la tarifa del municipio.
  final bool fallbackMunicipio;

  /// Municipio al que se recurrió (clave `municipio_aplicado`), si aplica.
  final String? municipioAplicado;
  final double kmTotal;
  final double kmLineal;
  final bool esNocturno;
  final double recargoNocturno;

  /// `precio_corto_aplicado` es un BOOLEANO en la RPC (el flag), no un monto.
  final bool precioCortoAplicado;
  final double redondeoCup;
  final double precioAntesRedondeo;
  final String moneda;

  /// Desglose interno completo (no se muestra crudo).
  final Map<String, dynamic> detalle;

  const Cotizacion({
    required this.precioPlataforma,
    this.comisionPct = 0,
    this.comisionMonto = 0,
    this.precioChofer = 0,
    this.tarifaModo = 'fijo',
    this.zonaNombre,
    this.dentroDeZona = false,
    this.fallbackMunicipio = false,
    this.municipioAplicado,
    this.kmTotal = 0,
    this.kmLineal = 0,
    this.esNocturno = false,
    this.recargoNocturno = 0,
    this.precioCortoAplicado = false,
    this.redondeoCup = 0,
    this.precioAntesRedondeo = 0,
    this.moneda = 'CUP',
    this.detalle = const <String, dynamic>{},
  });

  factory Cotizacion.fromJson(Map<String, dynamic> json) {
    // OJO con la forma REAL de `fn_cotizar_viaje` (verificado contra la BD):
    //   raíz   → precio_plataforma, comision_pct, comision_monto, precio_chofer,
    //            zona_id, zona_nombre, tarifa_modo, km_total, km_fuente,
    //            es_nocturno, precio_corto (bool), moneda, multiplicador_tipo,
    //            calculado_at, precio_vigente_desde y `detalle`
    //   detalle→ dentro_de_zona, fallback_municipio, municipio_aplicado,
    //            km_lineal, recargo_nocturno, recargo_prima_distancia,
    //            precio_antes_redondeo, redondeo_cup, precio_corto_aplicado,
    //            base, modo, monto_fijo, precio_km, precio_minimo, zona_origen_*
    // Por eso se lee primero de la raíz y, si falta, de `detalle`.
    final d = _toMap(json['detalle']);
    Object? pick(String k) => json[k] ?? d[k];

    final precioPlataforma = _toDouble(pick('precio_plataforma'));
    final redondeo = _toDouble(pick('redondeo_cup'));
    final antes = _toDoubleOrNull(pick('precio_antes_redondeo')) ??
        (precioPlataforma - redondeo);

    return Cotizacion(
      precioPlataforma: precioPlataforma,
      comisionPct: _toDouble(pick('comision_pct')),
      comisionMonto: _toDouble(pick('comision_monto')),
      precioChofer: _toDouble(pick('precio_chofer')),
      tarifaModo: _toStr(pick('tarifa_modo')) ?? 'fijo',
      zonaNombre: _toStr(pick('zona_nombre')) ??
          _toStr(d['zona_origen_nombre']),
      dentroDeZona: _toBool(pick('dentro_de_zona')),
      fallbackMunicipio: _toBool(pick('fallback_municipio')),
      municipioAplicado: _toStr(pick('municipio_aplicado')),
      kmTotal: _toDouble(pick('km_total')),
      kmLineal: _toDouble(pick('km_lineal')),
      esNocturno: _toBool(pick('es_nocturno')),
      recargoNocturno: _toDouble(pick('recargo_nocturno')),
      // En la raíz la RPC publica `precio_corto`; dentro de detalle el flag se
      // llama `precio_corto_aplicado`. Ambos son booleanos.
      precioCortoAplicado:
          _toBool(json['precio_corto'] ?? d['precio_corto_aplicado']),
      redondeoCup: redondeo,
      precioAntesRedondeo: antes,
      moneda: _toStr(pick('moneda')) ?? 'CUP',
      detalle: d,
    );
  }

  bool get fueraDeZona => !dentroDeZona;

  bool get aplicaPrecioCorto => precioCortoAplicado;

  /// Etiqueta de la fila "Tarifa de la zona".
  ///
  /// Ojo: `dentro_de_zona` significa que **el destino cae en la misma zona que
  /// el origen**. Cuando el origen está en una zona pero el viaje sale de ella,
  /// `zona_nombre` trae la zona aplicada y `dentro_de_zona` es false; en ese caso
  /// se cobra el tramo por km de esa misma zona, así que no hay que decir
  /// "fuera de zona".
  String get zonaEtiqueta {
    if (dentroDeZona) {
      return zonaNombre != null ? 'Tarifa de $zonaNombre' : 'Tarifa de la zona';
    }
    if (zonaNombre != null && zonaNombre != 'Fuera de zona') {
      return 'Tarifa de $zonaNombre · destino fuera de la zona';
    }
    if (municipioAplicado != null) {
      return 'Tarifa municipal · $municipioAplicado';
    }
    if (fallbackMunicipio) {
      return 'Tarifa municipal';
    }
    return 'Fuera de zona · tarifa general';
  }

  String get tarifaModoEtiqueta {
    switch (tarifaModo) {
      case 'fijo_mas_km':
        return 'Tarifa fija + km';
      case 'por_km':
        return 'Por kilómetro';
      case 'fijo':
      default:
        return 'Tarifa fija por zona';
    }
  }
}

// ── Viaje disponible para el chofer (fn_viajes_disponibles) ───────────────

/// Fila de `fn_viajes_disponibles`, ya con el neto del chofer calculado por
/// la plataforma. La app no recalcula nada: sólo muestra.
class ViajeDisponible {
  final int solicitudId;

  /// "El cliente paga".
  final double precioPlataforma;

  /// "Comisión plataforma".
  final double comisionMonto;
  final double comisionPct;

  /// Neto contable (`precio_plataforma - comision_monto`).
  ///
  /// OJO: NO es "lo que cobra el chofer".
  /// · `efectivo` → el chofer recibe el total en mano y la comisión se le
  ///   DESCUENTA del wallet (queda como deuda hasta el tope configurado).
  /// · `wallet`   → al cliente se le retiene el total y al chofer se le ABONA
  ///   este neto en su wallet.
  /// La UI debe explicarlo según [metodoPago], no decir "te tocan X".
  final double precioChofer;

  /// `'efectivo'` | `'wallet'`: cómo paga el cliente. Determina el texto del dinero.
  final String metodoPago;

  final int pasajeros;
  final int capacidadVehiculo;
  final String? direccionOrigen;
  final String? direccionDestino;
  final double km;
  final double? distanciaAOrigenKm;
  final String? tipoVehiculo;
  final int? idTipoVehiculo;

  /// Cuenta atrás del TTL, en segundos, medida por el servidor.
  final int segundosRestantes;

  /// Habilita/deshabilita el botón "Tomar viaje".
  final bool puedeTomar;

  /// Texto del por qué NO puede tomarlo (ver §4 del contrato).
  final String? motivoBloqueo;

  final String? zonaNombre;
  final double deudaDisponible;
  final String moneda;
  final Map<String, dynamic> desglose;

  // Datos opcionales: no están garantizados por el contrato; se rellenan
  // desde `muevete.solicitudes_transporte` al tomar el viaje.
  final String? userId;
  final double? latOrigen;
  final double? lonOrigen;
  final double? latDestino;
  final double? lonDestino;

  const ViajeDisponible({
    required this.solicitudId,
    required this.precioPlataforma,
    this.comisionMonto = 0,
    this.comisionPct = 0,
    this.precioChofer = 0,
    this.metodoPago = 'efectivo',
    this.pasajeros = 1,
    this.capacidadVehiculo = 0,
    this.direccionOrigen,
    this.direccionDestino,
    this.km = 0,
    this.distanciaAOrigenKm,
    this.tipoVehiculo,
    this.idTipoVehiculo,
    this.segundosRestantes = 0,
    this.puedeTomar = false,
    this.motivoBloqueo,
    this.zonaNombre,
    this.deudaDisponible = 0,
    this.moneda = 'CUP',
    this.desglose = const <String, dynamic>{},
    this.userId,
    this.latOrigen,
    this.lonOrigen,
    this.latDestino,
    this.lonDestino,
  });

  factory ViajeDisponible.fromJson(Map<String, dynamic> json) {
    return ViajeDisponible(
      solicitudId: _toInt(json['solicitud_id']),
      precioPlataforma: _toDouble(json['precio_plataforma']),
      comisionMonto: _toDouble(json['comision_monto']),
      comisionPct: _toDouble(json['comision_pct']),
      precioChofer: _toDouble(json['precio_chofer']),
      metodoPago: (_toStr(json['metodo_pago']) ?? 'efectivo').toLowerCase(),
      pasajeros: _toInt(json['pasajeros'], 1),
      capacidadVehiculo: _toInt(json['capacidad_vehiculo']),
      direccionOrigen: _toStr(json['direccion_origen']),
      direccionDestino: _toStr(json['direccion_destino']),
      km: _toDouble(json['km']),
      distanciaAOrigenKm: _toDoubleOrNull(json['distancia_a_origen_km']),
      tipoVehiculo: _toStr(json['tipo_vehiculo']),
      idTipoVehiculo: _toIntOrNull(json['id_tipo_vehiculo']),
      segundosRestantes: _toInt(json['segundos_restantes']),
      puedeTomar: _toBool(json['puede_tomar']),
      motivoBloqueo: _toStr(json['motivo_bloqueo']),
      zonaNombre: _toStr(json['zona_nombre']),
      deudaDisponible: _toDouble(json['deuda_disponible']),
      moneda: _toStr(json['moneda']) ?? 'CUP',
      desglose: _toMap(json['desglose']),
      userId: _toStr(json['user_id']),
      latOrigen: _toDoubleOrNull(json['lat_origen']),
      lonOrigen: _toDoubleOrNull(json['lon_origen']),
      latDestino: _toDoubleOrNull(json['lat_destino']),
      lonDestino: _toDoubleOrNull(json['lon_destino']),
    );
  }

  /// Completa los datos de contacto/ruta con la fila de la solicitud.
  ViajeDisponible conSolicitud(Map<String, dynamic>? row) {
    if (row == null) return this;
    return ViajeDisponible(
      solicitudId: solicitudId,
      precioPlataforma: precioPlataforma,
      comisionMonto: comisionMonto,
      comisionPct: comisionPct,
      precioChofer: precioChofer,
      metodoPago: metodoPago,
      pasajeros: pasajeros,
      capacidadVehiculo: capacidadVehiculo,
      direccionOrigen: direccionOrigen ?? _toStr(row['direccion_origen']),
      direccionDestino: direccionDestino ?? _toStr(row['direccion_destino']),
      km: km,
      distanciaAOrigenKm: distanciaAOrigenKm,
      tipoVehiculo: tipoVehiculo ?? _toStr(row['tipo_vehiculo']),
      idTipoVehiculo: idTipoVehiculo ?? _toIntOrNull(row['id_tipo_vehiculo']),
      segundosRestantes: segundosRestantes,
      puedeTomar: puedeTomar,
      motivoBloqueo: motivoBloqueo,
      zonaNombre: zonaNombre,
      deudaDisponible: deudaDisponible,
      moneda: moneda,
      desglose: desglose,
      userId: userId ?? _toStr(row['user_id']),
      latOrigen: latOrigen ?? _toDoubleOrNull(row['lat_origen']),
      lonOrigen: lonOrigen ?? _toDoubleOrNull(row['lon_origen']),
      latDestino: latDestino ?? _toDoubleOrNull(row['lat_destino']),
      lonDestino: lonDestino ?? _toDoubleOrNull(row['lon_destino']),
    );
  }
}