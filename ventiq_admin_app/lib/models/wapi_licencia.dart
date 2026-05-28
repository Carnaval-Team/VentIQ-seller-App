/// Modelos del sistema de licencias específico del módulo WAPI
/// (Notificación a Clientes / Difusión WhatsApp).
///
/// Independiente de `app_suscripciones` — vive en las tablas
/// `app_wapi_licencia_plan` y `app_wapi_licencia`.

enum WapiLicenciaEstado {
  enVerificacion(1, 'En verificación'),
  activa(2, 'Activa'),
  rechazada(3, 'Rechazada'),
  vencida(4, 'Vencida'),
  cancelada(5, 'Cancelada');

  final int value;
  final String label;
  const WapiLicenciaEstado(this.value, this.label);

  static WapiLicenciaEstado fromInt(int v) {
    return WapiLicenciaEstado.values.firstWhere(
      (e) => e.value == v,
      orElse: () => WapiLicenciaEstado.cancelada,
    );
  }
}

/// Plan disponible para adquirir licencia WAPI.
class WapiLicenciaPlan {
  final int id;
  final String denominacion;
  final String? descripcion;
  final double precioMensual;
  final double? precioPromocional;
  final int duracionMesesDefault;
  final bool esActivo;

  WapiLicenciaPlan({
    required this.id,
    required this.denominacion,
    this.descripcion,
    required this.precioMensual,
    this.precioPromocional,
    required this.duracionMesesDefault,
    required this.esActivo,
  });

  /// Precio que se le aplicaría al usuario hoy.
  /// Si hay precio promocional definido (>= 0), prevalece sobre el mensual.
  double get precioVigente => precioPromocional ?? precioMensual;

  /// Indica si actualmente está en periodo de prueba gratuita.
  bool get esPruebaGratis => precioVigente == 0;

  factory WapiLicenciaPlan.fromJson(Map<String, dynamic> json) {
    double? toDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse('$v');
    }

    return WapiLicenciaPlan(
      id: (json['id'] as num).toInt(),
      denominacion: json['denominacion'] ?? '',
      descripcion: json['descripcion'],
      precioMensual: toDouble(json['precio_mensual']) ?? 0,
      precioPromocional: toDouble(json['precio_promocional']),
      duracionMesesDefault:
          (json['duracion_meses_default'] as num?)?.toInt() ?? 1,
      esActivo: json['es_activo'] == true,
    );
  }
}

/// Licencia adquirida por una tienda.
class WapiLicencia {
  final int id;
  final int idTienda;
  final int idPlan;
  final WapiLicenciaEstado estado;
  final DateTime fechaSolicitud;
  final DateTime? fechaInicio;
  final DateTime? fechaFin;
  final int duracionMeses;
  final double montoPagado;
  final String? referenciaPago;
  final String? notas;
  final String? solicitadoPor;
  final String? verificadoPor;
  final DateTime? verificadoAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Plan asociado (join). Opcional porque no siempre se carga.
  final WapiLicenciaPlan? plan;

  WapiLicencia({
    required this.id,
    required this.idTienda,
    required this.idPlan,
    required this.estado,
    required this.fechaSolicitud,
    this.fechaInicio,
    this.fechaFin,
    required this.duracionMeses,
    required this.montoPagado,
    this.referenciaPago,
    this.notas,
    this.solicitadoPor,
    this.verificadoPor,
    this.verificadoAt,
    required this.createdAt,
    required this.updatedAt,
    this.plan,
  });

  /// `true` si la licencia está en estado activo y aún no ha vencido.
  bool get isActive {
    if (estado != WapiLicenciaEstado.activa) return false;
    if (fechaFin == null) return true; // sin vencimiento → siempre activa
    return DateTime.now().isBefore(fechaFin!);
  }

  bool get isEnVerificacion => estado == WapiLicenciaEstado.enVerificacion;

  bool get isRechazada => estado == WapiLicenciaEstado.rechazada;

  /// `true` si está marcada como vencida o si la fecha fin ya pasó estando activa.
  bool get vencida {
    if (estado == WapiLicenciaEstado.vencida) return true;
    if (estado == WapiLicenciaEstado.activa &&
        fechaFin != null &&
        DateTime.now().isAfter(fechaFin!)) {
      return true;
    }
    return false;
  }

  /// Días restantes hasta el vencimiento. `null` si no aplica.
  int? get diasRestantes {
    if (fechaFin == null) return null;
    final diff = fechaFin!.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  factory WapiLicencia.fromJson(Map<String, dynamic> json) {
    double toDouble(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse('$v') ?? 0;
    }

    DateTime? tryDate(dynamic v) =>
        v == null ? null : DateTime.tryParse('$v');

    final planJson = json['app_wapi_licencia_plan'];
    return WapiLicencia(
      id: (json['id'] as num).toInt(),
      idTienda: (json['id_tienda'] as num).toInt(),
      idPlan: (json['id_plan'] as num).toInt(),
      estado: WapiLicenciaEstado.fromInt(
          (json['estado'] as num?)?.toInt() ?? 1),
      fechaSolicitud: tryDate(json['fecha_solicitud']) ?? DateTime.now(),
      fechaInicio: tryDate(json['fecha_inicio']),
      fechaFin: tryDate(json['fecha_fin']),
      duracionMeses: (json['duracion_meses'] as num?)?.toInt() ?? 1,
      montoPagado: toDouble(json['monto_pagado']),
      referenciaPago: json['referencia_pago'],
      notas: json['notas'],
      solicitadoPor: json['solicitado_por'],
      verificadoPor: json['verificado_por'],
      verificadoAt: tryDate(json['verificado_at']),
      createdAt: tryDate(json['created_at']) ?? DateTime.now(),
      updatedAt: tryDate(json['updated_at']) ?? DateTime.now(),
      plan: planJson is Map<String, dynamic>
          ? WapiLicenciaPlan.fromJson(planJson)
          : null,
    );
  }
}
