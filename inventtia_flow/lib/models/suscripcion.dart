/// Modelos del módulo de suscripciones (migraciones 43–46 del schema `flow`).
///
/// Regla de oro de este archivo: **el estado que pinta la UI lo deriva el
/// servidor de las FECHAS**, no del texto guardado en la tabla. El cron puede ir
/// con retraso y el aviso tiene que ser exacto igual. Aquí no se recalcula nada
/// de eso: se confía en lo que devuelve `flow.cliente_estado_suscripcion`.
library;

import '../utils/precio_reserva.dart';

/// Estados posibles de una suscripción, tal como los nombra el servidor.
///
/// `sin_suscripcion` es el caso de una entidad **anterior** al módulo: no tiene
/// fila en `flow.suscripcion`. Es *grandfathering*: sigue activa y **no** es un
/// impago, así que no dispara el aviso de "no has pagado". El superadmin le crea
/// la fila cuando corre `flow.admin_suscripcion_inicializar()`.
enum EstadoSuscripcion {
  trial,
  activa,
  enGracia,
  vencida,
  sinPlan,
  suspendida,
  cancelada,
  sinSuscripcion,
  desconocido;

  static EstadoSuscripcion desde(String? valor) {
    switch (valor) {
      case 'trial':
        return EstadoSuscripcion.trial;
      case 'activa':
        return EstadoSuscripcion.activa;
      case 'en_gracia':
        return EstadoSuscripcion.enGracia;
      case 'vencida':
        return EstadoSuscripcion.vencida;
      case 'sin_plan':
        return EstadoSuscripcion.sinPlan;
      case 'suspendida':
        return EstadoSuscripcion.suspendida;
      case 'cancelada':
        return EstadoSuscripcion.cancelada;
      case 'sin_suscripcion':
        return EstadoSuscripcion.sinSuscripcion;
      default:
        return EstadoSuscripcion.desconocido;
    }
  }

  /// Texto corto para la píldora de estado.
  String get etiqueta {
    switch (this) {
      case EstadoSuscripcion.trial:
        return 'Prueba';
      case EstadoSuscripcion.activa:
        return 'Activa';
      case EstadoSuscripcion.enGracia:
        return 'En gracia';
      case EstadoSuscripcion.vencida:
        return 'Vencida';
      case EstadoSuscripcion.sinPlan:
        return 'Sin plan';
      case EstadoSuscripcion.suspendida:
        return 'Suspendida';
      case EstadoSuscripcion.cancelada:
        return 'Cancelada';
      case EstadoSuscripcion.sinSuscripcion:
        return 'Sin registro';
      case EstadoSuscripcion.desconocido:
        return 'Desconocido';
    }
  }

  /// ¿Es un problema de pago? Es lo que decide si se pinta el aviso permanente
  /// de "no has pagado". `suspendida` entra porque el efecto es el mismo (la
  /// entidad no se muestra), aunque la causa sea una decisión del superadmin.
  bool get esImpago =>
      this == EstadoSuscripcion.vencida ||
      this == EstadoSuscripcion.sinPlan ||
      this == EstadoSuscripcion.cancelada ||
      this == EstadoSuscripcion.suspendida;

  /// ¿Todavía funciona? `sinSuscripcion` cuenta como activa (grandfathering).
  bool get operativa =>
      this == EstadoSuscripcion.trial ||
      this == EstadoSuscripcion.activa ||
      this == EstadoSuscripcion.enGracia ||
      this == EstadoSuscripcion.sinSuscripcion;
}

/// Estado de la suscripción de una entidad (`flow.cliente_estado_suscripcion`).
class EstadoSuscripcionEntidad {
  const EstadoSuscripcionEntidad({
    required this.idEntidad,
    required this.estado,
    required this.activa,
    this.estadoGuardado,
    this.esTrial = false,
    this.enGracia = false,
    this.planCodigo,
    this.planNombre,
    this.duracionDias,
    this.precio,
    this.moneda,
    this.fechaInicio,
    this.fechaVencimiento,
    this.fechaGraciaFin,
    this.diasRestantes,
    this.diasGracia,
    this.mensaje,
  });

  final int idEntidad;
  final EstadoSuscripcion estado;

  /// `true` si la entidad puede mostrarse y recibir reservas. Lo calcula
  /// `flow.entidad_activa`, que es el **único** predicado que decide esto.
  final bool activa;

  /// El estado tal como está guardado en la tabla. Puede ir por detrás del
  /// [estado] derivado de las fechas (el cron cada 15 minutos); es solo para el
  /// panel del superadmin.
  final String? estadoGuardado;

  final bool esTrial;
  final bool enGracia;
  final String? planCodigo;
  final String? planNombre;
  final int? duracionDias;
  final double? precio;
  final String? moneda;
  final DateTime? fechaInicio;
  final DateTime? fechaVencimiento;
  final DateTime? fechaGraciaFin;

  /// Días que quedan hasta el vencimiento. Negativo si ya pasó.
  final int? diasRestantes;

  /// Días que quedan del margen de gracia. Negativo si ya se agotó.
  final int? diasGracia;

  /// Frase ya redactada por el servidor, para no duplicar la lógica de textos.
  final String? mensaje;

  EstadoSuscripcionEntidad copyWith({EstadoSuscripcion? estado}) =>
      EstadoSuscripcionEntidad(
        idEntidad: idEntidad,
        estado: estado ?? this.estado,
        activa: activa,
        estadoGuardado: estadoGuardado,
        esTrial: esTrial,
        enGracia: enGracia,
        planCodigo: planCodigo,
        planNombre: planNombre,
        duracionDias: duracionDias,
        precio: precio,
        moneda: moneda,
        fechaInicio: fechaInicio,
        fechaVencimiento: fechaVencimiento,
        fechaGraciaFin: fechaGraciaFin,
        diasRestantes: diasRestantes,
        diasGracia: diasGracia,
        mensaje: mensaje,
      );

  /// `true` si hay que pintar el aviso permanente de impago.
  bool get mostrarAvisoImpago => estado.esImpago;

  /// Precio del plan formateado con el símbolo de la moneda. `null` si no hay.
  String? get precioEtiqueta =>
      precio == null ? null : PrecioReserva.formatear(precio!, moneda ?? 'CUP');

  factory EstadoSuscripcionEntidad.fromJson(Map<String, dynamic> json) {
    return EstadoSuscripcionEntidad(
      idEntidad: (json['id_entidad'] as num?)?.toInt() ?? 0,
      estado: EstadoSuscripcion.desde(json['estado'] as String?),
      // Solo es `false` si el servidor lo dice: una respuesta a la que le falte
      // el campo no debe apagar la entidad en la UI.
      activa: json['activa'] != false,
      estadoGuardado: json['estado_guardado'] as String?,
      esTrial: json['es_trial'] == true,
      enGracia: json['en_gracia'] == true,
      planCodigo: json['plan_codigo'] as String?,
      planNombre: json['plan_nombre'] as String?,
      duracionDias: (json['duracion_dias'] as num?)?.toInt(),
      precio: (json['precio'] as num?)?.toDouble(),
      moneda: json['moneda'] as String?,
      fechaInicio: fecha(json['fecha_inicio']),
      fechaVencimiento: fecha(json['fecha_vencimiento']),
      fechaGraciaFin: fecha(json['fecha_gracia_fin']),
      diasRestantes: (json['dias_restantes'] as num?)?.toInt(),
      diasGracia: (json['dias_gracia'] as num?)?.toInt(),
      mensaje: json['mensaje'] as String?,
    );
  }
}

/// Un plan que el cliente puede comprar (`flow.suscripcion_plan`).
///
/// Desde la migración 72 la tabla gana tres conceptos que cambian la tarjeta:
///
/// * `id_entidad` — un plan **privado** solo lo ve la entidad dueña. `null` es
///   un plan público.
/// * `modalidad` — `pago` (Transfermóvil, flujo de siempre) o `contacto` (se
///   contrata hablando con ventas por WhatsApp; no hay intent de pago).
/// * `etiqueta` — cinta comercial de la tarjeta ("Más popular", "Recomendado").
///
/// Todos los campos nuevos son opcionales y con valores por defecto: si el
/// servidor todavía no manda las columnas (migración pendiente) el modelo se
/// comporta como antes y la pantalla no cambia.
class PlanSuscripcion {
  const PlanSuscripcion({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.duracionDias,
    required this.precio,
    required this.moneda,
    this.descripcion,
    this.limites = const <String, dynamic>{},
    this.orden = 0,
    this.modalidad = 'pago',
    this.etiqueta,
    this.esPrivado = false,
    this.idEntidad,
    this.entidadDenominacion,
    this.contactoWhatsapp,
    this.precioCup,
  });

  final int id;
  final String codigo;
  final String nombre;
  final int duracionDias;
  final double precio;
  final String moneda;
  final String? descripcion;

  /// Límites funcionales del plan: `entidades`, `locales`,
  /// `servicios_por_local`, `servicios_catalogo`, `usuarios`.
  ///
  /// REGLA del contrato: un número **> 0** es un límite; la clave ausente,
  /// `null`, `0` o negativo significa **sin límite**. Por eso [limiteDe] no
  /// devuelve los valores no positivos.
  final Map<String, dynamic> limites;

  final int orden;

  /// `'pago'` (se paga con Transfermóvil) o `'contacto'` (se contrata con
  /// ventas). Un valor desconocido se trata como `'pago'`, que es el flujo de
  /// siempre.
  final String modalidad;

  /// Cinta de la tarjeta, p. ej. "Más popular". `null` = sin cinta.
  final String? etiqueta;

  /// Plan privado: visible solo para [idEntidad] (`id_entidad` NOT NULL).
  final bool esPrivado;

  /// Entidad dueña del plan privado. `null` en los planes públicos.
  final int? idEntidad;

  /// Denominación de la entidad dueña, ya resuelta por el servidor.
  final String? entidadDenominacion;

  /// WhatsApp de ventas para la modalidad `contacto`. El servidor lo saca de
  /// `flow.suscripcion_config`; si no llega, la UI cae al número de soporte.
  final String? contactoWhatsapp;

  /// Precio del plan **convertido a CUP por el servidor** con la tasa cacheada
  /// (migración 74), redondeado a pesos enteros.
  ///
  /// `null` si el servidor no manda el campo (migración pendiente) o si no hay
  /// tasa para esa moneda. La app **nunca** convierte: sin este dato no muestra
  /// ninguna cifra en CUP, para no inventarse un importe que no va a pagarse.
  final double? precioCup;

  /// `true` si toca pintar la equivalencia en CUP: el plan está tarifado en otra
  /// moneda y el servidor sí mandó la conversión.
  bool get mostrarPrecioCup =>
      moneda.toUpperCase() != 'CUP' && precioCup != null;

  /// "16900 CUP" con el formateador de la app, o `null` si no hay precio en CUP.
  ///
  /// Se usa [PrecioReserva.formatear] a propósito: el separador y la posición del
  /// símbolo tienen que ser los mismos que en el resto de la app.
  String? get precioCupEtiqueta =>
      precioCup == null ? null : PrecioReserva.formatear(precioCup!, 'CUP');

  /// `true` si el plan se contrata hablando con ventas, no con Transfermóvil.
  bool get esPorContacto => modalidad == 'contacto';

  /// Límite de un recurso, o `null` si el plan no lo limita.
  int? limiteDe(String recurso) {
    final valor = limites[recurso];
    if (valor is num && valor > 0) return valor.toInt();
    return null;
  }

  /// Características legibles para la tarjeta, derivadas de [limites]:
  /// "2 locales", "5 servicios por local", "3 usuarios"…
  ///
  /// Si el plan no limita nada, devuelve `["Sin límite"]`: decir "Sin límite" es
  /// más honesto que una lista vacía, que se leería como una tarjeta sin
  /// información.
  List<String> get caracteristicas {
    final lista = <String>[];

    void agregar(String recurso, String singular, String plural) {
      final n = limiteDe(recurso);
      if (n == null) return;
      lista.add(n == 1 ? '1 $singular' : '$n $plural');
    }

    agregar('entidades', 'entidad', 'entidades');
    agregar('locales', 'local', 'locales');
    agregar('servicios_por_local', 'servicio por local', 'servicios por local');
    agregar(
      'servicios_catalogo',
      'servicio en catálogo',
      'servicios en catálogo',
    );
    agregar('usuarios', 'usuario', 'usuarios');

    return lista.isEmpty ? const ['Sin límite'] : lista;
  }

  /// "1 mes", "3 meses", "12 meses" cuando la duración es exacta; si no, días.
  ///
  /// Las duraciones se definen en **días exactos** (30/90/365) y no en meses
  /// calendario, así que la etiqueta es una comodidad de presentación, no un
  /// cálculo.
  String get etiquetaDuracion {
    switch (duracionDias) {
      case 30:
        return '1 mes';
      case 90:
        return '3 meses';
      case 180:
        return '6 meses';
      case 365:
        return '1 año';
    }
    if (duracionDias % 30 == 0) return '${duracionDias ~/ 30} meses';
    return duracionDias == 1 ? '1 día' : '$duracionDias días';
  }

  String get precioEtiqueta => PrecioReserva.formatear(precio, moneda);

  /// Precio por mes, para comparar planes de un vistazo. `null` si el plan dura
  /// menos de un mes (comparar sale engañoso).
  String? get precioPorMesEtiqueta {
    if (duracionDias < 28) return null;
    final meses = duracionDias / 30.0;
    return PrecioReserva.formatear(precio / meses, moneda);
  }

  factory PlanSuscripcion.fromJson(Map<String, dynamic> json) {
    final limites = json['limites'];
    final modalidad = json['modalidad'] as String?;
    final etiqueta = json['etiqueta'] as String?;
    return PlanSuscripcion(
      id: (json['id'] as num?)?.toInt() ?? 0,
      codigo: json['codigo'] as String? ?? '',
      nombre: json['nombre'] as String? ?? '',
      duracionDias: (json['duracion_dias'] as num?)?.toInt() ?? 30,
      precio: (json['precio'] as num?)?.toDouble() ?? 0,
      moneda: json['moneda'] as String? ?? 'CUP',
      descripcion: json['descripcion'] as String?,
      limites: limites is Map
          ? Map<String, dynamic>.from(limites)
          : const <String, dynamic>{},
      orden: (json['orden'] as num?)?.toInt() ?? 0,
      // Un valor ausente o vacío cae a 'pago': es el flujo de siempre y así un
      // servidor sin la migración 72 no desactiva el botón de pagar de nadie.
      modalidad: modalidad == 'contacto' ? 'contacto' : 'pago',
      etiqueta: (etiqueta == null || etiqueta.trim().isEmpty)
          ? null
          : etiqueta.trim(),
      // Solo es privado si el servidor lo dice explícitamente.
      esPrivado: json['es_privado'] == true,
      idEntidad: (json['id_entidad'] as num?)?.toInt(),
      entidadDenominacion: json['entidad_denominacion'] as String?,
      contactoWhatsapp: json['contacto_whatsapp'] as String?,
      // Tolerante: sin la migración 74 la clave no llega y queda `null`, así que
      // la tarjeta no pinta ninguna equivalencia en CUP.
      precioCup: (json['precio_cup'] as num?)?.toDouble(),
    );
  }
}

/// Un intento de pago de Transfermóvil (`flow.suscripcion_intent`).
///
/// El `id_transaccion` es el que se le pasa a la app de Transfermóvil. Es
/// **único** por intento a propósito: si se repite, Transfermóvil reutiliza el
/// importe de la transacción anterior.
class IntentSuscripcion {
  const IntentSuscripcion({
    required this.id,
    required this.idPlan,
    required this.monto,
    required this.moneda,
    required this.idTransaccion,
    required this.urlIntent,
    required this.estado,
    this.planNombre,
    this.urlHttp,
    this.expiraAt,
    this.createdAt,
  });

  final int id;
  final int idPlan;
  final String? planNombre;
  final double monto;
  final String moneda;
  final String idTransaccion;

  /// Deep link `transfermovil://...`. Es el que se lanza.
  final String urlIntent;

  /// Respaldo `https://transfermovil.app/...`, por si el esquema no está
  /// registrado en el dispositivo.
  final String? urlHttp;

  /// `creado` | `abierto` | `reportado` | `verificado` | `rechazado` | `expirado`.
  final String estado;

  final DateTime? expiraAt;
  final DateTime? createdAt;

  /// Solo se puede pagar mientras no se haya reportado ni caducado.
  bool get vigente => estado == 'creado' || estado == 'abierto';

  bool get expirado {
    if (estado == 'expirado') return true;
    final e = expiraAt;
    return e != null && e.isBefore(DateTime.now());
  }

  String get montoEtiqueta => PrecioReserva.formatear(monto, moneda);

  /// Texto legible del estado, para el historial de la pantalla.
  String get etiquetaEstado {
    switch (estado) {
      case 'creado':
        return 'Sin abrir';
      case 'abierto':
        return 'Abierto en Transfermóvil';
      case 'reportado':
        return 'Pago reportado';
      case 'verificado':
        return 'Verificado';
      case 'rechazado':
        return 'Rechazado';
      case 'expirado':
        return 'Caducado';
      default:
        return estado;
    }
  }

  factory IntentSuscripcion.fromJson(Map<String, dynamic> json) {
    return IntentSuscripcion(
      id: (json['id'] as num?)?.toInt() ?? 0,
      idPlan: (json['id_plan'] as num?)?.toInt() ?? 0,
      planNombre: json['plan_nombre'] as String?,
      monto: (json['monto'] as num?)?.toDouble() ?? 0,
      moneda: json['moneda'] as String? ?? 'CUP',
      idTransaccion: json['id_transaccion'] as String? ?? '',
      urlIntent: json['url_intent'] as String? ?? '',
      urlHttp: json['url_http'] as String?,
      estado: json['estado'] as String? ?? 'creado',
      expiraAt: fecha(json['expira_at']),
      createdAt: fecha(json['created_at']),
    );
  }
}

/// Lo que devuelve `cliente_crear_intent_suscripcion`: el intent más los datos
/// de la transferencia que el cliente tiene que ver antes de salir a pagar.
///
/// Con la migración 74 el cobro es **siempre en CUP al cambio del día**: `monto`
/// y `moneda` del intent (y `importe`, el del deep link) vienen en CUP, y además
/// llegan `monto_plan`, `moneda_plan` y `tasa_cup` para poder explicar de dónde
/// sale esa cifra sin convertir nada en Dart.
class IntentPagoCreado {
  const IntentPagoCreado({
    required this.intent,
    required this.idTransaccion,
    required this.importe,
    required this.numeroProveedor,
    required this.titulo,
    required this.soporteWhatsapp,
    this.modoPrueba = false,
    this.montoPlan,
    this.monedaPlan,
    this.tasaCup,
  });

  final IntentSuscripcion intent;

  /// Importe tal como se le pasa a Transfermóvil, ya sin decimales de relleno
  /// ("1500" en vez de "1500.00"). Se muestra así porque es lo que el cliente
  /// verá en la app del banco. Desde la migración 74 está en CUP.
  final String importe;

  final String idTransaccion;
  final String numeroProveedor;
  final String titulo;
  final String soporteWhatsapp;

  /// Aviso para la UI: la configuración está en modo prueba. Se pinta un rótulo
  /// para que nadie cobre de verdad creyendo que prueba.
  final bool modoPrueba;

  /// Precio del plan en su moneda original (30 USD, 25 EUR…). `null` si el
  /// servidor todavía no manda la migración 74.
  final double? montoPlan;

  /// Moneda original del plan. `null` si no llega.
  final String? monedaPlan;

  /// Tasa aplicada por el servidor. Se guarda tal cual: la app no la usa para
  /// calcular, solo la expone por si una pantalla quiere explicarla.
  final double? tasaCup;

  /// `true` si el servidor ya devolvió el intent en CUP (migración 74).
  bool get cobraEnCup => intent.moneda.toUpperCase() == 'CUP';

  /// Importe que se transfiere, con su moneda, tal como lo manda el servidor.
  String get importeEtiqueta => '$importe ${intent.moneda}';

  /// `true` si se puede explicar la equivalencia: el plan estaba en otra moneda
  /// y el servidor mandó tanto el precio original como el cobro en CUP.
  bool get muestraEquivalenciaPlan =>
      montoPlan != null &&
      monedaPlan != null &&
      monedaPlan!.toUpperCase() != 'CUP' &&
      cobraEnCup;

  /// "Plan Plus · 30 USD ≈ 25350 CUP", todo con cifras del servidor.
  String? get equivalenciaPlanEtiqueta {
    if (!muestraEquivalenciaPlan) return null;
    final precioPlan = PrecioReserva.formatear(montoPlan!, monedaPlan!);
    final enCup = PrecioReserva.formatear(intent.monto, intent.moneda);
    final nombre = intent.planNombre?.trim();
    final plan = (nombre == null || nombre.isEmpty) ? 'Plan' : 'Plan $nombre';
    return '$plan · $precioPlan ≈ $enCup';
  }

  factory IntentPagoCreado.fromJson(Map<String, dynamic> json) {
    return IntentPagoCreado(
      intent: IntentSuscripcion.fromJson(json),
      idTransaccion: json['id_transaccion'] as String? ?? '',
      importe: json['importe'] as String? ?? '',
      numeroProveedor: json['numero_proveedor'] as String? ?? '',
      titulo: json['titulo'] as String? ?? '',
      soporteWhatsapp: json['soporte_whatsapp'] as String? ?? '5354590207',
      modoPrueba: json['modo_prueba'] == true,
      // Tolerante: sin la 74 estas claves no llegan y quedan en `null`, así que
      // el paso de pago se limita a mostrar el importe que sí vino.
      montoPlan: (json['monto_plan'] as num?)?.toDouble(),
      monedaPlan: json['moneda_plan'] as String?,
      tasaCup: (json['tasa_cup'] as num?)?.toDouble(),
    );
  }
}

/// Un pago reportado por el cliente (`flow.suscripcion_transaccion`).
class PagoSuscripcion {
  const PagoSuscripcion({
    required this.id,
    required this.monto,
    required this.moneda,
    required this.estado,
    this.idIntent,
    this.codigoConfirmacion,
    this.metodo,
    this.comprobanteUrl,
    this.observaciones,
    this.reportadoAt,
    this.verificadoAt,
  });

  final int id;
  final int? idIntent;

  /// Código que muestra Transfermóvil. Es **único**: un mismo código no puede
  /// acreditar dos pagos.
  final String? codigoConfirmacion;

  final double monto;
  final String moneda;
  final String? metodo;
  final String? comprobanteUrl;

  /// `reportado` | `verificado` | `rechazado`.
  final String estado;

  /// Motivo del rechazo cuando el superadmin no pudo verificarlo.
  final String? observaciones;

  final DateTime? reportadoAt;
  final DateTime? verificadoAt;

  String get montoEtiqueta => PrecioReserva.formatear(monto, moneda);

  String get etiquetaEstado {
    switch (estado) {
      case 'reportado':
        return 'Pendiente de verificación';
      case 'verificado':
        return 'Verificado';
      case 'rechazado':
        return 'Rechazado';
      default:
        return estado;
    }
  }

  factory PagoSuscripcion.fromJson(Map<String, dynamic> json) {
    return PagoSuscripcion(
      id: (json['id'] as num?)?.toInt() ?? 0,
      idIntent: (json['id_intent'] as num?)?.toInt(),
      codigoConfirmacion: json['codigo_confirmacion'] as String?,
      monto: (json['monto'] as num?)?.toDouble() ?? 0,
      moneda: json['moneda'] as String? ?? 'CUP',
      metodo: json['metodo'] as String?,
      comprobanteUrl: json['comprobante_url'] as String?,
      estado: json['estado'] as String? ?? 'reportado',
      observaciones: json['observaciones'] as String?,
      reportadoAt: fecha(json['reportado_at']),
      verificadoAt: fecha(json['verificado_at']),
    );
  }
}

/// Una línea del libro de movimientos de la suscripción. Es **append-only**: es
/// la auditoría de por qué la entidad tiene el tiempo que tiene.
class MovimientoSuscripcion {
  const MovimientoSuscripcion({
    required this.tipo,
    required this.dias,
    this.fechaDesde,
    this.fechaHasta,
    this.motivo,
    this.createdAt,
  });

  /// `trial` | `acreditacion` | `renovacion` | `ajuste` | `expiracion` |
  /// `suspension` | `reactivacion` | `inicializacion`.
  final String tipo;

  final int dias;
  final DateTime? fechaDesde;
  final DateTime? fechaHasta;
  final String? motivo;
  final DateTime? createdAt;

  String get etiquetaTipo {
    switch (tipo) {
      case 'trial':
        return 'Prueba';
      case 'acreditacion':
        return 'Pago acreditado';
      case 'renovacion':
        return 'Renovación';
      case 'ajuste':
        return 'Ajuste';
      case 'expiracion':
        return 'Vencimiento';
      case 'suspension':
        return 'Suspensión';
      case 'reactivacion':
        return 'Reactivación';
      case 'inicializacion':
        return 'Alta';
      default:
        return tipo;
    }
  }

  /// "+30 días" / "-0 días" → sin signo cuando es cero (vencimiento, suspensión).
  String get etiquetaDias {
    if (dias == 0) return '—';
    return dias > 0 ? '+$dias días' : '$dias días';
  }

  factory MovimientoSuscripcion.fromJson(Map<String, dynamic> json) {
    return MovimientoSuscripcion(
      tipo: json['tipo'] as String? ?? '',
      dias: (json['dias'] as num?)?.toInt() ?? 0,
      fechaDesde: fecha(json['fecha_desde']),
      fechaHasta: fecha(json['fecha_hasta']),
      motivo: json['motivo'] as String?,
      createdAt: fecha(json['created_at']),
    );
  }
}

/// Intents, pagos y movimientos de una entidad, en una sola llamada.
class MiSuscripcion {
  const MiSuscripcion({
    this.intents = const <IntentSuscripcion>[],
    this.pagos = const <PagoSuscripcion>[],
    this.movimientos = const <MovimientoSuscripcion>[],
  });

  final List<IntentSuscripcion> intents;
  final List<PagoSuscripcion> pagos;
  final List<MovimientoSuscripcion> movimientos;

  /// El último pago reportado y todavía sin verificar, si lo hay. Es lo que
  /// decide si la pantalla muestra "esperando verificación" en vez del botón de
  /// pagar.
  PagoSuscripcion? get pagoPendiente {
    for (final p in pagos) {
      if (p.estado == 'reportado') return p;
    }
    return null;
  }

  /// El intent más reciente que todavía sirve para pagar.
  IntentSuscripcion? get intentVigente {
    for (final i in intents) {
      if (i.vigente && !i.expirado) return i;
    }
    return null;
  }

  factory MiSuscripcion.fromJson(Map<String, dynamic> json) {
    return MiSuscripcion(
      intents: _lista(json['intents'], IntentSuscripcion.fromJson),
      pagos: _lista(json['pagos'], PagoSuscripcion.fromJson),
      movimientos: _lista(json['movimientos'], MovimientoSuscripcion.fromJson),
    );
  }
}

/// Lo que devuelve `cliente_reportar_pago_suscripcion`.
class ReportePago {
  const ReportePago({
    required this.idTransaccionPago,
    this.soporteWhatsapp = '5354590207',
    this.mensajeSoporte = '',
  });

  final int idTransaccionPago;

  /// Número de soporte al que se manda el aviso, ya resuelto por el servidor.
  final String soporteWhatsapp;

  /// Mensaje ya redactado por el servidor ("Yo Fulanito he pagado el plan...").
  /// Se usa tal cual: la app solo lo abre en WhatsApp, no lo reescribe.
  final String mensajeSoporte;

  factory ReportePago.fromJson(Map<String, dynamic> json) {
    return ReportePago(
      idTransaccionPago: (json['id_transaccion_pago'] as num?)?.toInt() ?? 0,
      soporteWhatsapp: json['soporte_whatsapp'] as String? ?? '5354590207',
      mensajeSoporte: json['mensaje_soporte'] as String? ?? '',
    );
  }
}

/// `DateTime?` desde ISO-8601, tolerando `null` y basura.
DateTime? fecha(dynamic v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toLocal();
  return null;
}

List<T> _lista<T>(dynamic v, T Function(Map<String, dynamic>) parse) {
  if (v is! List) return const [];
  return v
      .whereType<Map>()
      .map((e) => parse(Map<String, dynamic>.from(e)))
      .toList(growable: false);
}
