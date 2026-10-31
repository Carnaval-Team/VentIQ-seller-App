/// Modelos del **pago por adelantado del servicio** (migración 62 del schema
/// `flow`).
///
/// El circuito es el mismo que el de la suscripción —deep link de Transfermóvil
/// → «Ya he pagado» → verificación manual del admin— pero con los datos del
/// admin de la entidad: **su número de proveedor y su WhatsApp de verificación**.
/// Nada de lo que hay aquí acredita una reserva: el único que decide es
/// `flow.admin_verificar_pago_reserva` (o el reloj, vía
/// `flow.reserva_pago_expirar`).
///
/// Regla de tolerancia (igual que en `suscripcion.dart`): los `jsonb_build_object`
/// de la migración son la fuente, pero un campo que falte o venga de otro tipo
/// **no** puede tumbar la pantalla. Todo se lee con coerción y valores por
/// defecto prudentes: ante la duda, «no disponible» y «sin datos», nunca una
/// excepción.
library;

import '../utils/precio_reserva.dart';

/// Configuración del cobro por adelantado de **una entidad**
/// (`flow.cobro_config`; es una sola config para todos sus locales).
class CobroConfig {
  const CobroConfig({
    required this.idEntidad,
    this.activo = false,
    this.tieneFila = false,
    this.numeroProveedor = '',
    this.titulo = '',
    this.whatsappVerificacion,
    this.soporteWhatsapp,
    this.instrucciones,
    this.moneda = 'CUP',
    this.horasVigencia = 24,
    this.cancelarSiExpira = true,
  });

  final int idEntidad;

  /// Interruptor «Cobrar por adelantado».
  final bool activo;

  /// `true` si la entidad ya tiene fila en `flow.cobro_config`. Es informativo:
  /// sin fila, el RPC devuelve los valores por defecto.
  final bool tieneFila;

  /// Número de proveedor de Transfermóvil del admin (el que cobra).
  final String numeroProveedor;

  /// Título que se pinta en la app de Transfermóvil al abrir el deep link.
  final String titulo;

  /// WhatsApp **del admin** al que el cliente manda el comprobante. `null` u
  /// vacío ⇒ la hoja de pago no ofrece el botón de WhatsApp.
  final String? whatsappVerificacion;

  /// WhatsApp de soporte de la plataforma, si el admin configuró uno.
  final String? soporteWhatsapp;

  /// Instrucciones libres del admin («paga a este número y mándame el
  /// comprobante»). Se muestran tal cual en la hoja del cliente.
  final String? instrucciones;

  /// Moneda en la que se cobra. `CUP` por defecto.
  final String moneda;

  /// Horas que el intento está vivo antes de expirar (1-720).
  final int horasVigencia;

  /// Si al expirar el pago se cancela la reserva (lo hace el servidor).
  final bool cancelarSiExpira;

  /// La actividad se puede configurar: hay número de proveedor.
  bool get configurado => numeroProveedor.trim().isNotEmpty;

  /// ¿Está activo **y** se puede cobrar de verdad? La BD rechaza `activo` sin
  /// número de proveedor; esto es la misma invariante en la app.
  bool get cobrando => activo && configurado;

  CobroConfig copyWith({
    bool? activo,
    bool? tieneFila,
    String? numeroProveedor,
    String? titulo,
    String? whatsappVerificacion,
    String? soporteWhatsapp,
    String? instrucciones,
    String? moneda,
    int? horasVigencia,
    bool? cancelarSiExpira,
  }) {
    return CobroConfig(
      idEntidad: idEntidad,
      activo: activo ?? this.activo,
      tieneFila: tieneFila ?? this.tieneFila,
      numeroProveedor: numeroProveedor ?? this.numeroProveedor,
      titulo: titulo ?? this.titulo,
      whatsappVerificacion: whatsappVerificacion ?? this.whatsappVerificacion,
      soporteWhatsapp: soporteWhatsapp ?? this.soporteWhatsapp,
      instrucciones: instrucciones ?? this.instrucciones,
      moneda: moneda ?? this.moneda,
      horasVigencia: horasVigencia ?? this.horasVigencia,
      cancelarSiExpira: cancelarSiExpira ?? this.cancelarSiExpira,
    );
  }

  factory CobroConfig.fromJson(Map<String, dynamic> json) {
    final horas = _entero(json['intent_horas_vigencia']);
    return CobroConfig(
      idEntidad: _entero(json['id_entidad']) ?? 0,
      activo: json['activo'] == true,
      tieneFila: json['tiene_fila'] == true,
      numeroProveedor: _texto(json['transfermovil_numero_proveedor']) ?? '',
      titulo: _texto(json['transfermovil_titulo']) ?? '',
      whatsappVerificacion: _texto(json['whatsapp_verificacion']),
      soporteWhatsapp: _texto(json['soporte_whatsapp']),
      instrucciones: _texto(json['instrucciones']),
      moneda: _texto(json['moneda']) ?? 'CUP',
      // Un plazo fuera de rango no se corrige en silencio con un valor absurdo:
      // se cae a 24 h, que es el defecto de la tabla.
      horasVigencia: (horas != null && horas >= 1 && horas <= 720) ? horas : 24,
      cancelarSiExpira: json['cancelar_si_expira'] != false,
    );
  }
}

/// Lo que la app necesita saber **antes** de ofrecer «Pagar por adelantado»
/// (`flow.cliente_cobro_info`).
class CobroInfo {
  const CobroInfo({
    this.disponible = false,
    this.idEntidad,
    this.moneda = 'CUP',
    this.horasVigencia = 24,
    this.whatsappVerificacion,
    this.soporteWhatsapp,
    this.instrucciones,
    this.numeroProveedor = '',
    this.titulo = '',
  });

  /// `true` solo si la entidad tiene el cobro activo y con número de proveedor.
  /// Si viene `false`, la ficha no pinta nada del cobro.
  final bool disponible;

  final int? idEntidad;
  final String moneda;
  final int horasVigencia;
  final String? whatsappVerificacion;
  final String? soporteWhatsapp;
  final String? instrucciones;
  final String numeroProveedor;
  final String titulo;

  /// Texto corto para el banner de la ficha del servicio.
  String get resumenVigencia {
    if (horasVigencia <= 1) return 'Tienes 1 hora para pagar';
    if (horasVigencia < 48) return 'Tienes $horasVigencia horas para pagar';
    final dias = horasVigencia ~/ 24;
    return 'Tienes $dias días para pagar';
  }

  factory CobroInfo.fromJson(Map<String, dynamic> json) {
    final horas = _entero(json['horas_vigencia']);
    return CobroInfo(
      // Solo se apaga si el servidor lo dice: un campo ausente no debe ocultar
      // el cobro en una entidad que sí lo tiene activo.
      disponible: json['disponible'] == true,
      idEntidad: _entero(json['id_entidad']),
      moneda: _texto(json['moneda']) ?? 'CUP',
      horasVigencia: (horas != null && horas >= 1 && horas <= 720) ? horas : 24,
      whatsappVerificacion: _texto(json['whatsapp_verificacion']),
      soporteWhatsapp: _texto(json['soporte_whatsapp']),
      instrucciones: _texto(json['instrucciones']),
      numeroProveedor: _texto(json['numero_proveedor']) ?? '',
      titulo: _texto(json['titulo']) ?? '',
    );
  }
}

/// Un intento de pago por adelantado de **una reserva** (`flow.reserva_pago`).
///
/// `estado` ∈ `creado | reportado | verificado | rechazado | expirado | anulado`
/// y es el mismo valor que el servidor copia en `agenda.pago_estado` (allí se
/// llama `pendiente` al `creado`).
class PagoReserva {
  const PagoReserva({
    required this.id,
    required this.idAgenda,
    required this.monto,
    this.moneda = 'CUP',
    this.estado = 'creado',
    this.urlIntent = '',
    this.urlHttp,
    this.numeroProveedor = '',
    this.idTransaccion,
    this.codigoConfirmacion,
    this.comprobanteUrl,
    this.motivoRechazo,
    this.expiraAt,
    this.reportadoAt,
    this.verificadoAt,
    this.vencido,
    this.titulo,
    this.instrucciones,
    this.whatsappVerificacion,
  });

  final int id;
  final int idAgenda;
  final double monto;
  final String moneda;

  /// `creado` | `reportado` | `verificado` | `rechazado` | `expirado` | `anulado`.
  final String estado;

  /// Deep link `transfermovil://...`, el que se lanza.
  final String urlIntent;

  /// Respaldo `https://transfermovil.app/...` por si el esquema no está
  /// registrado en el dispositivo.
  final String? urlHttp;

  final String numeroProveedor;

  /// Referencia interna del intento (`FLW-PAGO-…`). **No** viaja en el link: es
  /// el dato que soporte usa para ubicar el pago.
  final String? idTransaccion;

  /// Código que muestra Transfermóvil, ya reportado por el cliente.
  final String? codigoConfirmacion;
  final String? comprobanteUrl;

  /// Motivo del rechazo (o las observaciones de la verificación).
  final String? motivoRechazo;

  final DateTime? expiraAt;
  final DateTime? reportadoAt;
  final DateTime? verificadoAt;

  /// Lo calcula el servidor: el plazo ya venció y el intento sigue vivo.
  final bool? vencido;

  /// Datos de la transferencia que solo devuelven `cliente_crear_pago_reserva`
  /// (y la config). Se guardan aquí para que la hoja funcione aunque no reciba
  /// un [CobroInfo].
  final String? titulo;
  final String? instrucciones;
  final String? whatsappVerificacion;

  /// «1500 CUP» / «$18».
  String get montoEtiqueta => PrecioReserva.formatear(monto, moneda);

  /// Importe tal como lo espera Transfermóvil: sin centavos de relleno en CUP.
  String get importeTransfermovil {
    if (monto == monto.roundToDouble()) return monto.toStringAsFixed(0);
    return monto.toStringAsFixed(2);
  }

  bool get esPendiente => estado == 'creado' || estado == 'reportado';
  bool get esReportado => estado == 'reportado';
  bool get verificado => estado == 'verificado';
  bool get rechazado => estado == 'rechazado';

  /// Caducado por estado, por la bandera del servidor o por fecha local. Las
  /// tres fuentes valen: la app no puede depender de que el cron ya haya
  /// marcado la fila.
  bool get expirado {
    if (estado == 'expirado') return true;
    if (vencido == true) return true;
    final e = expiraAt;
    return e != null && e.isBefore(DateTime.now());
  }

  /// Se puede volver a pulsar «Ya he pagado».
  bool get puedeReportar => esPendiente && !expirado;

  /// Tiempo que queda hasta `expira_at`. Nunca negativo.
  Duration get restante {
    final e = expiraAt;
    if (e == null) return Duration.zero;
    final d = e.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  /// «2 h 05 min» / «14 min 20 s» / «45 s», para la cuenta atrás de la hoja.
  String get restanteEtiqueta {
    final d = restante;
    if (d.inSeconds <= 0) return 'vencido';
    if (d.inHours >= 1) {
      final min = d.inMinutes % 60;
      return '${d.inHours} h ${min.toString().padLeft(2, '0')} min';
    }
    if (d.inMinutes >= 1) {
      final seg = d.inSeconds % 60;
      return '${d.inMinutes} min ${seg.toString().padLeft(2, '0')} s';
    }
    return '${d.inSeconds} s';
  }

  String get etiquetaEstado {
    switch (estado) {
      case 'creado':
        return 'Pago sin reportar';
      case 'reportado':
        return 'Pago reportado, esperando verificación';
      case 'verificado':
        return 'Verificado';
      case 'rechazado':
        return 'Rechazado';
      case 'expirado':
        return 'Caducado';
      case 'anulado':
        return 'Anulado';
      default:
        return estado;
    }
  }

  PagoReserva copyWith({
    String? estado,
    String? codigoConfirmacion,
    String? comprobanteUrl,
    String? motivoRechazo,
    DateTime? reportadoAt,
    DateTime? verificadoAt,
    bool? vencido,
  }) {
    return PagoReserva(
      id: id,
      idAgenda: idAgenda,
      monto: monto,
      moneda: moneda,
      estado: estado ?? this.estado,
      urlIntent: urlIntent,
      urlHttp: urlHttp,
      numeroProveedor: numeroProveedor,
      idTransaccion: idTransaccion,
      codigoConfirmacion: codigoConfirmacion ?? this.codigoConfirmacion,
      comprobanteUrl: comprobanteUrl ?? this.comprobanteUrl,
      motivoRechazo: motivoRechazo ?? this.motivoRechazo,
      expiraAt: expiraAt,
      reportadoAt: reportadoAt ?? this.reportadoAt,
      verificadoAt: verificadoAt ?? this.verificadoAt,
      vencido: vencido ?? this.vencido,
      titulo: titulo,
      instrucciones: instrucciones,
      whatsappVerificacion: whatsappVerificacion,
    );
  }

  factory PagoReserva.fromJson(Map<String, dynamic> json) {
    return PagoReserva(
      id: _entero(json['id']) ?? 0,
      idAgenda: _entero(json['id_agenda']) ?? 0,
      monto: _decimal(json['monto']) ?? 0,
      moneda: _texto(json['moneda']) ?? 'CUP',
      estado: _texto(json['estado']) ?? 'creado',
      urlIntent: _texto(json['url_intent']) ?? '',
      urlHttp: _texto(json['url_http']),
      numeroProveedor: _texto(json['numero_proveedor']) ?? '',
      idTransaccion: _texto(json['id_transaccion']),
      codigoConfirmacion: _texto(json['codigo_confirmacion']),
      comprobanteUrl: _texto(json['comprobante_url']),
      motivoRechazo: _texto(json['motivo_rechazo']),
      expiraAt: _fecha(json['expira_at']),
      reportadoAt: _fecha(json['reportado_at']),
      verificadoAt: _fecha(json['verificado_at']),
      vencido: _booleano(json['vencido']),
      titulo: _texto(json['titulo']),
      instrucciones: _texto(json['instrucciones']),
      whatsappVerificacion: _texto(json['whatsapp_verificacion']),
    );
  }
}

/// Una fila de la bandeja del admin (`flow.admin_listar_pagos_reserva`): el pago
/// **más** la reserva a la que pertenece, el cliente y el servicio/local.
class PagoAdminItem {
  const PagoAdminItem({
    required this.pago,
    required this.idAgenda,
    this.fechaHoraReserva,
    this.cantidad = 1,
    this.estadoReserva,
    this.motivoCancelacion,
    this.idLocalServicio,
    this.servicio,
    this.local,
    this.clienteNombre,
    this.clienteApellidos,
    this.clienteTelefono,
    this.clienteUuid,
  });

  final PagoReserva pago;
  final int idAgenda;
  final DateTime? fechaHoraReserva;
  final int cantidad;

  /// «Reservado», «Cancelado», «Completado»…
  final String? estadoReserva;

  /// Motivo, si la reserva se canceló (por ejemplo, al expirar el pago).
  final String? motivoCancelacion;

  final int? idLocalServicio;
  final String? servicio;
  final String? local;

  final String? clienteNombre;
  final String? clienteApellidos;
  final String? clienteTelefono;
  final String? clienteUuid;

  /// Nombre y apellidos, o un texto genérico si el perfil no viene.
  String get clienteEtiqueta {
    final nombre = [clienteNombre, clienteApellidos]
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join(' ');
    return nombre.isEmpty ? 'Cliente sin perfil' : nombre;
  }

  String get telefonoEtiqueta {
    final t = clienteTelefono?.trim();
    return (t == null || t.isEmpty) ? 'Sin teléfono' : t;
  }

  /// ¿Se puede ofrecer el botón de WhatsApp? Hace falta teléfono.
  bool get tieneTelefono => (clienteTelefono?.trim().isNotEmpty ?? false);

  String get servicioLocalEtiqueta {
    final s = servicio?.trim();
    final l = local?.trim();
    if (s == null || s.isEmpty) return l ?? 'Servicio';
    if (l == null || l.isEmpty) return s;
    return '$s · $l';
  }

  /// «14/03/2026 10:30», en hora local.
  String get fechaEtiqueta {
    final f = fechaHoraReserva;
    if (f == null) return 'Sin fecha';
    String dos(int v) => v < 10 ? '0$v' : '$v';
    return '${dos(f.day)}/${dos(f.month)}/${f.year} ${dos(f.hour)}:${dos(f.minute)}';
  }

  String get importeEtiqueta => pago.montoEtiqueta;

  factory PagoAdminItem.fromJson(Map<String, dynamic> json) {
    final cliente = _mapa(json['cliente']);
    return PagoAdminItem(
      // `admin_listar_pagos_reserva` devuelve la fila plana: el pago y la
      // reserva comparten nivel, así que el mismo mapa alimenta a los dos.
      pago: PagoReserva.fromJson(json),
      idAgenda: _entero(json['id_agenda']) ?? 0,
      fechaHoraReserva: _fecha(json['fecha_hora_reserva']),
      cantidad: _entero(json['cantidad']) ?? 1,
      estadoReserva: _texto(_mapa(json['estado_reserva'])['nombre']),
      motivoCancelacion: _texto(json['motivo_cancelacion']),
      idLocalServicio: _entero(json['id_local_servicio']),
      servicio: _texto(_mapa(json['servicio'])['nombre']),
      local: _texto(_mapa(json['local'])['nombre']),
      clienteNombre: _texto(cliente['nombre']),
      clienteApellidos: _texto(cliente['apellidos']),
      clienteTelefono: _texto(cliente['telefono']),
      clienteUuid: _texto(cliente['uuid_usuario']),
    );
  }
}

// ── Utilidades de parseo tolerante ─────────────────────────────────────────

/// `DateTime?` desde ISO-8601, tolerando `null` y basura. En hora local.
DateTime? _fecha(dynamic v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toLocal();
  return null;
}

/// Un `String?` «de verdad»: `null` para ausente, vacío o solo espacios.
String? _texto(dynamic v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

Map<String, dynamic> _mapa(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

/// Entero tolerante: `num`, o texto numérico (PostgREST devuelve `numeric` como
/// `num`, pero un `jsonb_build_object` puede colarlo como string).
int? _entero(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) {
    final t = v.trim();
    return int.tryParse(t) ?? double.tryParse(t)?.toInt();
  }
  return null;
}

/// Decimal tolerante, con la misma regla que [_entero].
double? _decimal(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

/// Booleano tolerante: solo un `bool` cuenta; cualquier otra cosa es «no sé».
bool? _booleano(dynamic v) => v is bool ? v : null;

List<T> _lista<T>(dynamic v, T Function(Map<String, dynamic>) parse) {
  if (v is! List) return const [];
  return v
      .whereType<Map>()
      .map((e) => parse(Map<String, dynamic>.from(e)))
      .toList(growable: false);
}

/// Lista de pagos ya parseada. Se expone por si otra pantalla necesita leer
/// directamente el `data` de `admin_listar_pagos_reserva`.
List<PagoAdminItem> pagosAdminDesde(dynamic data) =>
    _lista(data, PagoAdminItem.fromJson);
