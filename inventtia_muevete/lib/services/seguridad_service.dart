import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../utils/app_error.dart';
import 'offline_queue_service.dart';

/// Contacto de emergencia propio (`muevete.contactos_emergencia`).
class ContactoEmergencia {
  final int id;
  final String nombre;
  final String telefono;
  final String? parentesco;
  final int prioridad;
  final String canal;
  final String estado;
  final bool verificado;

  const ContactoEmergencia({
    required this.id,
    required this.nombre,
    required this.telefono,
    required this.prioridad,
    required this.canal,
    required this.estado,
    required this.verificado,
    this.parentesco,
  });

  factory ContactoEmergencia.fromJson(Map<String, dynamic> json) {
    return ContactoEmergencia(
      id: (json['id'] as num?)?.toInt() ?? 0,
      nombre: (json['nombre'] ?? '').toString(),
      telefono: (json['telefono'] ?? '').toString(),
      parentesco: json['parentesco']?.toString(),
      prioridad: (json['prioridad'] as num?)?.toInt() ?? 2,
      canal: (json['canal'] ?? 'sms').toString(),
      estado: (json['estado'] ?? 'pendiente').toString(),
      verificado: json['verificado'] == true,
    );
  }

  /// La lista nunca muestra el teléfono completo: el titular lo conoce.
  String get telefonoEnmascarado {
    final digitos = telefono.replaceAll(RegExp(r'\D'), '');
    if (digitos.length <= 3) return '•••';
    return '••••${digitos.substring(digitos.length - 3)}';
  }

  /// Estado tal como lo pide el plan: "sin verificar" mientras no haya SMS.
  String get estadoLegible {
    if (estado == 'rechazado') return 'Rechazado';
    if (estado == 'revocado') return 'Revocado';
    if (verificado) return 'Verificado';
    return 'Sin verificar';
  }
}

/// Datos de la contraparte que la RPC entrega antes de abordar.
///
/// Whitelist del servidor: nombre público, foto, chapa, tipo de vehículo y
/// CI parcial. Nunca teléfono, CI completa ni documentos.
class FichaContraparte {
  final bool ok;
  final String? motivo;
  final String rol;
  final String nombrePublico;
  final String? fotoUrl;
  final String? ciParcial;
  final String? marca;
  final String? modelo;
  final String? color;
  final String? chapa;
  final double rating;
  final int viajes;
  final bool verificado;

  const FichaContraparte({
    required this.ok,
    required this.rol,
    required this.nombrePublico,
    this.motivo,
    this.fotoUrl,
    this.ciParcial,
    this.marca,
    this.modelo,
    this.color,
    this.chapa,
    this.rating = 0,
    this.viajes = 0,
    this.verificado = false,
  });

  static const FichaContraparte noDisponible = FichaContraparte(
    ok: false,
    rol: '',
    nombrePublico: '',
  );

  factory FichaContraparte.fromJson(Map<String, dynamic> json) {
    final vehiculo = json['vehiculo'];
    final veh = vehiculo is Map ? vehiculo : const <String, dynamic>{};
    return FichaContraparte(
      ok: json['ok'] != false,
      motivo: json['motivo']?.toString(),
      rol: (json['rol'] ?? '').toString(),
      nombrePublico: (json['nombre_publico'] ?? '').toString(),
      fotoUrl: json['foto_url']?.toString(),
      ciParcial: json['ci_parcial']?.toString(),
      marca: veh['marca']?.toString(),
      modelo: veh['modelo']?.toString(),
      color: veh['color']?.toString(),
      chapa: veh['chapa']?.toString(),
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      viajes: (json['viajes'] as num?)?.toInt() ?? 0,
      verificado: json['verificado'] == true,
    );
  }

  String get vehiculoLegible {
    final partes = [
      marca,
      modelo,
    ].whereType<String>().where((p) => p.isNotEmpty);
    if (partes.isEmpty) return 'Vehículo sin datos';
    final base = partes.join(' ');
    if (color == null || color!.isEmpty) return base;
    return '$base · $color';
  }

  /// El chofer ve al pasajero: no hay chapa ni vehículo que mostrar.
  bool get muestraVehiculo => (chapa ?? '').trim().isNotEmpty;
}

/// Enlace de viaje compartido recién creado (`muevete.enlaces_viaje`).
class EnlaceViaje {
  final int? id;
  final String token;
  final String url;
  final DateTime? expiraAt;

  const EnlaceViaje({
    required this.token,
    required this.url,
    this.id,
    this.expiraAt,
  });

  factory EnlaceViaje.fromJson(Map<String, dynamic> json) {
    final token = (json['token'] ?? '').toString();
    final devuelto = (json['url'] ?? '').toString();
    final base = SupabaseConfig.supabaseUrl;
    final url = devuelto.startsWith('http')
        ? devuelto
        : '$base/functions/v1/seguridad-publica'
              '${devuelto.startsWith('/') ? devuelto : '/f/$token'}';
    return EnlaceViaje(
      id: (json['enlace_id'] as num?)?.toInt(),
      token: token,
      url: url,
      expiraAt: DateTime.tryParse((json['expira_at'] ?? '').toString()),
    );
  }
}

/// Resultado de intentar disparar el pánico.
class ResultadoPanico {
  final bool enviado;
  final bool enCola;
  final int? eventoId;

  const ResultadoPanico({
    required this.enviado,
    required this.enCola,
    this.eventoId,
  });

  static const ResultadoPanico offline = ResultadoPanico(
    enviado: false,
    enCola: true,
  );
}

/// Incidente propio reportado (`muevete.incidentes`).
class IncidentePropio {
  final int id;
  final String tipo;
  final String severidad;
  final String estado;
  final String descripcion;
  final DateTime? createdAt;
  final String? resolucion;

  const IncidentePropio({
    required this.id,
    required this.tipo,
    required this.severidad,
    required this.estado,
    required this.descripcion,
    this.createdAt,
    this.resolucion,
  });

  factory IncidentePropio.fromJson(Map<String, dynamic> json) {
    return IncidentePropio(
      id: (json['id'] as num?)?.toInt() ?? 0,
      tipo: (json['tipo'] ?? '').toString(),
      severidad: (json['severidad'] ?? '').toString(),
      estado: (json['estado'] ?? '').toString(),
      descripcion: (json['descripcion'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()),
      resolucion: json['resolucion']?.toString(),
    );
  }
}

/// Estado de seguridad de la contraparte (`muevete.fn_estado_contraparte`).
///
/// La RPC sólo responde si eres el chofer de ese viaje (o superadmin); si no,
/// lanza `no_autorizado`. Aquí no se inventa nada: sin datos no hay alarma.
class EstadoContraparte {
  /// Bloqueo vigente de cualquiera de las dos partes.
  final bool bloqueado;

  /// Incidentes confirmados de severidad alta o crítica en la ventana.
  final bool alertaSeguridad;

  /// La plataforma no permite emparejar a estas dos personas.
  final bool emparejamientoBloqueado;

  final String? recomendacion;

  const EstadoContraparte({
    required this.bloqueado,
    required this.alertaSeguridad,
    required this.emparejamientoBloqueado,
    this.recomendacion,
  });

  factory EstadoContraparte.fromJson(Map<String, dynamic> json) {
    return EstadoContraparte(
      bloqueado: json['bloqueado'] == true,
      alertaSeguridad: json['alerta_seguridad'] == true,
      emparejamientoBloqueado: json['emparejamiento_bloqueado'] == true,
      recomendacion: json['recomendacion']?.toString(),
    );
  }

  /// Hay algo que el chofer deba saber del pasajero que lleva.
  bool get tieneReportes => alertaSeguridad || bloqueado;
}

/// Error de seguridad con mensaje ya en español.
class SeguridadException implements Exception {
  final String mensaje;
  final String? clave;

  const SeguridadException(this.mensaje, {this.clave});

  @override
  String toString() => mensaje;
}

/// Acceso a las RPC de seguridad del viaje (H2).
///
/// Contrato real: `inventtia_muevete/docs/migrations/037_taxi_seguridad.sql`.
/// El pánico se puede disparar sin red: queda en una cola local persistente y
/// se reintenta con el mismo `client_event_id` (idempotente en el servidor).
class SeguridadService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Cola FIFO de pánicos pendientes de envío.
  static const String outboxKey = 'seguridad_outbox_v1';
  static const int maxOutbox = 50;

  // ── Contactos de emergencia ─────────────────────────────────────────────

  Future<List<ContactoEmergencia>> contactos() async {
    final uid = _uid;
    try {
      final rows = await _supabase
          .schema('muevete')
          .from('contactos_emergencia')
          .select()
          .eq('user_uuid', uid)
          .order('prioridad')
          .order('created_at');
      return List<Map<String, dynamic>>.from(
        rows,
      ).map(ContactoEmergencia.fromJson).toList();
    } on PostgrestException catch (e) {
      throw SeguridadException(
        AppError.message(e, action: 'cargar tus contactos'),
        clave: e.code,
      );
    } catch (e) {
      throw SeguridadException(
        AppError.message(e, action: 'cargar tus contactos'),
      );
    }
  }

  /// Alta directa a la tabla (la RLS permite INSERT del propio contacto).
  /// El trigger del servidor valida máximo de contactos y que no seas tú.
  Future<ContactoEmergencia> crearContacto({
    required String nombre,
    required String telefono,
    String? parentesco,
    int prioridad = 2,
  }) async {
    final normalizado = normalizarTelefono(telefono);
    if (normalizado == null) {
      throw const SeguridadException(
        'Escribe un teléfono válido. Si es cubano, basta con los 8 dígitos',
      );
    }

    try {
      final row = await _supabase
          .schema('muevete')
          .from('contactos_emergencia')
          .insert({
            'user_uuid': _uid,
            'nombre': nombre.trim(),
            'telefono': normalizado,
            'parentesco': (parentesco ?? '').trim().isEmpty
                ? null
                : parentesco!.trim(),
            'prioridad': prioridad,
            'canal': 'sms',
            'estado': 'pendiente',
          })
          .select()
          .single();
      return ContactoEmergencia.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      throw SeguridadException(_mensajeContacto(e), clave: e.code);
    } catch (e) {
      throw SeguridadException(
        AppError.message(e, action: 'guardar el contacto'),
      );
    }
  }

  Future<void> actualizarContacto(
    int id, {
    String? nombre,
    String? telefono,
    String? parentesco,
    int? prioridad,
  }) async {
    final cambios = <String, dynamic>{};
    if (nombre != null && nombre.trim().isNotEmpty) {
      cambios['nombre'] = nombre.trim();
    }
    if (telefono != null && telefono.trim().isNotEmpty) {
      final normalizado = normalizarTelefono(telefono);
      if (normalizado == null) {
        throw const SeguridadException('Escribe un teléfono válido');
      }
      cambios['telefono'] = normalizado;
    }
    if (parentesco != null) {
      cambios['parentesco'] = parentesco.trim().isEmpty
          ? null
          : parentesco.trim();
    }
    if (prioridad != null) cambios['prioridad'] = prioridad;
    if (cambios.isEmpty) return;

    try {
      await _supabase
          .schema('muevete')
          .from('contactos_emergencia')
          .update(cambios)
          .eq('id', id)
          .eq('user_uuid', _uid);
    } on PostgrestException catch (e) {
      throw SeguridadException(_mensajeContacto(e), clave: e.code);
    } catch (e) {
      throw SeguridadException(
        AppError.message(e, action: 'actualizar el contacto'),
      );
    }
  }

  Future<void> eliminarContacto(int id) async {
    try {
      await _supabase
          .schema('muevete')
          .from('contactos_emergencia')
          .delete()
          .eq('id', id)
          .eq('user_uuid', _uid);
    } on PostgrestException catch (e) {
      throw SeguridadException(_mensajeContacto(e), clave: e.code);
    } catch (e) {
      throw SeguridadException(
        AppError.message(e, action: 'eliminar el contacto'),
      );
    }
  }

  /// `fn_iniciar_validacion_contacto`. El OTP **nunca** se muestra en la UI,
  /// ni siquiera si el servidor lo devolviera en un entorno de desarrollo.
  Future<Map<String, dynamic>> iniciarValidacion(int contactoId) async {
    final res = await _rpc(
      'fn_iniciar_validacion_contacto',
      params: {'p_contacto_id': contactoId},
      accion: 'iniciar la verificación del contacto',
    );
    return _asMap(res);
  }

  /// `fn_confirmar_contacto`.
  Future<void> confirmarContacto(int contactoId, String codigo) async {
    await _rpc(
      'fn_confirmar_contacto',
      params: {'p_contacto_id': contactoId, 'p_codigo': codigo.trim()},
      accion: 'confirmar el código',
    );
  }

  // ── Pánico con cola local ───────────────────────────────────────────────

  /// `fn_disparar_panico`. Firma real:
  /// `(p_solicitud_id, p_client_event_id, p_lat, p_lon, p_precision_m,
  ///   p_modo, p_compartir, p_capturado_at)`.
  ///
  /// Si no hay red (o la llamada falla por conexión), el evento se guarda en
  /// [outboxKey] y se enviará al reconectar con el mismo `client_event_id`.
  Future<ResultadoPanico> dispararPanico({
    required int solicitudId,
    required double lat,
    required double lon,
    double? precisionM,
    String modo = 'discreto',
    bool compartir = true,
  }) async {
    final payload = <String, dynamic>{
      'client_event_id': _uuidV4(),
      'solicitud_id': solicitudId,
      'lat': lat,
      'lon': lon,
      'precision_m': precisionM,
      'modo': modo,
      'compartir': compartir,
      'capturado_at': DateTime.now().toUtc().toIso8601String(),
      'ts': DateTime.now().toUtc().toIso8601String(),
    };

    final hayRed = await OfflineQueueService.hasInternetConnection();
    if (!hayRed) {
      await _encolar(payload);
      return ResultadoPanico.offline;
    }

    try {
      final res = await _rpc(
        'fn_disparar_panico',
        params: {
          'p_solicitud_id': solicitudId,
          'p_client_event_id': payload['client_event_id'],
          'p_lat': lat,
          'p_lon': lon,
          'p_precision_m': precisionM,
          'p_modo': modo,
          'p_compartir': compartir,
          'p_capturado_at': payload['capturado_at'],
        },
        accion: 'enviar la alerta',
      );
      final map = _asMap(res);
      return ResultadoPanico(
        enviado: true,
        enCola: false,
        eventoId: (map['evento_id'] as num?)?.toInt(),
      );
    } on SeguridadException catch (e) {
      // Error de negocio (no eres participante, viaje cerrado…): reintentar no
      // sirve. Se informa y no se pierde: queda en la cola igualmente.
      final noReintentable = const {
        'solicitud_no_existe',
        'no_participante',
        'viaje_no_activo',
        'no_autenticado',
      }.contains(e.clave);
      await _encolar(payload);
      if (noReintentable) {
        throw SeguridadException(
          '${e.mensaje}. La alerta quedó guardada en el teléfono',
          clave: e.clave,
        );
      }
      return ResultadoPanico.offline;
    } catch (_) {
      await _encolar(payload);
      return ResultadoPanico.offline;
    }
  }

  /// Reintenta los pánicos guardados. Idempotente por `client_event_id`.
  static Future<int> sincronizarPanicosPendientes() async {
    final prefs = await SharedPreferences.getInstance();
    final lista = _leerCola(prefs);
    if (lista.isEmpty) return 0;
    if (!await OfflineQueueService.hasInternetConnection()) return 0;

    final supabase = Supabase.instance.client;
    final restantes = <Map<String, dynamic>>[];
    var enviados = 0;

    for (final entrada in lista) {
      try {
        await supabase
            .schema('muevete')
            .rpc(
              'fn_disparar_panico',
              params: {
                'p_solicitud_id': entrada['solicitud_id'],
                'p_client_event_id': entrada['client_event_id'],
                'p_lat': entrada['lat'],
                'p_lon': entrada['lon'],
                'p_precision_m': entrada['precision_m'],
                'p_modo': entrada['modo'] ?? 'discreto',
                'p_compartir': entrada['compartir'] ?? true,
                'p_capturado_at': entrada['capturado_at'],
              },
            );
        enviados++;
      } on PostgrestException catch (e) {
        final texto = '${e.code ?? ''} ${e.message}'.toLowerCase();
        // Duplicado (ya estaba en el servidor) o viaje ya cerrado: la alerta
        // deja de tener sentido, se descarta en vez de reintentar siempre.
        if (texto.contains('p0101') ||
            texto.contains('p0102') ||
            texto.contains('p0103') ||
            texto.contains('duplicado') ||
            texto.contains('solicitud_no_existe') ||
            texto.contains('no_participante') ||
            texto.contains('viaje_no_activo')) {
          debugPrint('[Seguridad] Pánico descartado de la cola: $texto');
        } else {
          restantes.add(entrada);
        }
      } catch (e) {
        debugPrint('[Seguridad] No se pudo enviar el pánico: $e');
        restantes.add(entrada);
      }
    }

    if (restantes.isEmpty) {
      await prefs.remove(outboxKey);
    } else {
      await prefs.setString(outboxKey, jsonEncode(restantes));
    }
    return enviados;
  }

  /// Cuántos pánicos esperan conexión.
  static Future<int> panicosPendientes() async {
    final prefs = await SharedPreferences.getInstance();
    return _leerCola(prefs).length;
  }

  static Timer? _reintentoTimer;

  /// Reintenta la cola cada 30 s mientras haya pendientes.
  ///
  /// Se arranca al abrir la app (ver `main.dart`). Sólo intenta enviar si hay
  /// eventos en cola y hay conexión, así que no gasta datos en vano.
  static void iniciarReintentoPeriodico({
    Duration intervalo = const Duration(seconds: 30),
  }) {
    _reintentoTimer?.cancel();
    _reintentoTimer = Timer.periodic(intervalo, (_) async {
      try {
        final pendientes = await panicosPendientes();
        if (pendientes == 0) return;
        await sincronizarPanicosPendientes();
      } catch (e) {
        debugPrint('[Seguridad] Reintento de pánico falló: $e');
      }
    });
  }

  static Future<void> _encolar(Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();
    final lista = _leerCola(prefs);
    lista.add(payload);

    // El plan prohíbe perder una alerta por saturación: se descarta el más
    // viejo sólo si tiene más de 7 días; si no, se avisa (ver pantalla).
    while (lista.length > maxOutbox) {
      final primero = lista.first;
      final ts = DateTime.tryParse((primero['ts'] ?? '').toString());
      final viejo = ts != null && DateTime.now().difference(ts).inDays > 7;
      if (viejo) {
        lista.removeAt(0);
      } else {
        break;
      }
    }
    await prefs.setString(outboxKey, jsonEncode(lista));
  }

  static List<Map<String, dynamic>> _leerCola(SharedPreferences prefs) {
    final raw = prefs.getString(outboxKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Configuración ───────────────────────────────────────────────────────

  /// Número de policía configurado en `muevete.configuracion_seguridad`.
  /// El número no se escribe en Dart: cae a `106` sólo si la tabla no responde.
  Future<String> numeroPolicia() async {
    try {
      final row = await _supabase
          .schema('muevete')
          .from('configuracion_seguridad')
          .select('numeros_emergencia')
          .eq('id', 1)
          .maybeSingle();
      final numeros = row?['numeros_emergencia'];
      if (numeros is Map) {
        final policia = numeros['policia']?.toString();
        if (policia != null && policia.trim().isNotEmpty) {
          return policia.trim();
        }
      }
    } catch (_) {
      // Sin tabla de configuración se usa el número público de Cuba.
    }
    return '106';
  }

  // ── Enlaces de viaje compartido ─────────────────────────────────────────

  /// `fn_crear_enlace_viaje(p_solicitud_id, p_alcance)`.
  Future<EnlaceViaje> crearEnlace(
    int solicitudId, {
    String alcance = 'completo',
  }) async {
    final res = await _rpc(
      'fn_crear_enlace_viaje',
      params: {'p_solicitud_id': solicitudId, 'p_alcance': alcance},
      accion: 'crear el enlace del viaje',
    );
    final map = _asMap(res);
    final token = (map['token'] ?? '').toString();
    if (token.isEmpty && map['url'] == null) {
      throw const SeguridadException(
        'El servidor no devolvió el enlace. Inténtalo de nuevo',
      );
    }
    return EnlaceViaje.fromJson(map);
  }

  Future<void> revocarEnlace(int enlaceId) async {
    await _rpc(
      'fn_revocar_enlace_viaje',
      params: {'p_enlace_id': enlaceId},
      accion: 'revocar el enlace',
    );
  }

  /// Enlaces vigentes de la solicitud (lectura directa, RLS propia).
  Future<List<Map<String, dynamic>>> enlacesVigentes(int solicitudId) async {
    try {
      final rows = await _supabase
          .schema('muevete')
          .from('enlaces_viaje')
          .select('id, rol, expira_at, revocado_at, accesos, created_at')
          .eq('solicitud_id', solicitudId)
          .isFilter('revocado_at', null)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      return const [];
    }
  }

  // ── Verificación mutua y abordaje ───────────────────────────────────────

  /// `fn_ficha_contraparte(p_solicitud_id)`.
  Future<FichaContraparte> fichaContraparte(int solicitudId) async {
    final res = await _rpc(
      'fn_ficha_contraparte',
      params: {'p_solicitud_id': solicitudId},
      accion: 'ver los datos de la otra persona',
    );
    final map = _asMap(res);
    if (map.isEmpty) return FichaContraparte.noDisponible;
    return FichaContraparte.fromJson(map);
  }

  /// `fn_confirmar_abordaje(p_viaje_id, p_chapa_confirmada, p_metodo)`.
  ///
  /// `p_metodo` sólo admite `ficha | cache | sin_verificacion`.
  Future<void> confirmarAbordaje(
    int viajeId, {
    bool chapaConfirmada = true,
    String metodo = 'ficha',
  }) async {
    await _rpc(
      'fn_confirmar_abordaje',
      params: {
        'p_viaje_id': viajeId,
        'p_chapa_confirmada': chapaConfirmada,
        'p_metodo': metodo,
      },
      accion: 'confirmar el abordaje',
    );
  }

  // ── Incidentes ──────────────────────────────────────────────────────────

  /// `fn_reportar_incidente(p_solicitud_id, p_tipo, p_descripcion,
  /// p_evidencia, p_no_emparejar)`. La severidad la calcula el servidor a
  /// partir del tipo; el cliente no la envía.
  Future<Map<String, dynamic>> reportarIncidente({
    required int solicitudId,
    required String tipo,
    required String descripcion,
    List<Map<String, dynamic>> evidencia = const [],
    bool noEmparejar = false,
  }) async {
    final res = await _rpc(
      'fn_reportar_incidente',
      params: {
        'p_solicitud_id': solicitudId,
        'p_tipo': tipo,
        'p_descripcion': descripcion.trim(),
        'p_evidencia': evidencia,
        'p_no_emparejar': noEmparejar,
      },
      accion: 'enviar el reporte',
    );
    return _asMap(res);
  }

  /// Historial de incidentes propios (lectura directa, RLS `select_own`).
  Future<List<IncidentePropio>> incidentesPropios() async {
    try {
      final rows = await _supabase
          .schema('muevete')
          .from('incidentes')
          .select(
            'id, tipo, severidad, estado, descripcion, resolucion, created_at',
          )
          .eq('reportado_por_uuid', _uid)
          .order('created_at', ascending: false)
          .limit(30);
      return List<Map<String, dynamic>>.from(
        rows,
      ).map(IncidentePropio.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Etiqueta legible de un tipo de incidente.
  static String etiquetaTipo(String tipo) {
    const mapa = <String, String>{
      'robo_con_violencia': 'Robo con violencia',
      'robo_sin_violencia': 'Robo sin violencia',
      'agresion_fisica': 'Agresión física',
      'amenaza': 'Amenaza',
      'acoso_sexual': 'Acoso sexual',
      'acoso_verbal': 'Acoso verbal',
      'suplantacion': 'Suplantación de identidad',
      'vehiculo_incorrecto': 'Vehículo incorrecto',
      'no_show_pasajero': 'Pasajero que no apareció',
      'cobro_abusivo': 'Cobro indebido',
      'extorsion': 'Extorsión',
      'otro': 'Otra cosa',
    };
    return mapa[tipo] ?? tipo.replaceAll('_', ' ');
  }

  static String etiquetaSeveridad(String severidad) {
    const mapa = <String, String>{
      'baja': 'Baja',
      'media': 'Media',
      'alta': 'Alta',
      'critica': 'Crítica',
    };
    return mapa[severidad] ?? severidad;
  }

  static String etiquetaEstadoIncidente(String estado) {
    const mapa = <String, String>{
      'reportado': 'Recibido',
      'en_revision': 'En revisión',
      'confirmado': 'Confirmado',
      'descartado': 'Descartado',
      'escalado': 'Escalado',
    };
    return mapa[estado] ?? estado.replaceAll('_', ' ');
  }

  // ── Estado de la contraparte (lista negra) ──────────────────────────────

  /// `fn_estado_contraparte(p_user_uuid, p_driver_id)`. Devuelve las claves
  /// `bloqueado`, `alerta_seguridad`, `emparejamiento_bloqueado` y
  /// `recomendacion`.
  ///
  /// Nunca lanza: si la RPC falla, no hay sesión de chofer o no hay datos,
  /// devuelve `null` y la pantalla no muestra ninguna alarma.
  Future<EstadoContraparte?> estadoContraparte({
    required String userUuid,
    required int driverId,
  }) async {
    try {
      final res = await _supabase.schema('muevete').rpc(
        'fn_estado_contraparte',
        params: {'p_user_uuid': userUuid, 'p_driver_id': driverId},
      );
      final map = _asMap(res);
      if (map.isEmpty) return null;
      return EstadoContraparte.fromJson(map);
    } catch (e) {
      debugPrint('[Seguridad] Estado de la contraparte no disponible: $e');
      return null;
    }
  }

  // ── Helpers públicos ────────────────────────────────────────────────────

  /// Normaliza a E.164 cubano (`+53` + 8 dígitos) como exige el CHECK de la
  /// tabla. Devuelve `null` si no parece un teléfono.
  static String? normalizarTelefono(String raw) {
    final limpio = raw.replaceAll(RegExp(r'[^\d+]'), '');
    if (limpio.isEmpty) return null;

    var digitos = limpio.startsWith('+') ? limpio.substring(1) : limpio;
    digitos = digitos.replaceAll('+', '');
    if (digitos.isEmpty) return null;

    if (digitos.startsWith('53')) {
      final resto = digitos.substring(2);
      if (resto.length >= 8 && resto.length <= 13) return '+53$resto';
      return null;
    }
    if (digitos.length == 8) return '+53$digitos';
    if (digitos.length > 8 && digitos.length <= 15) return '+$digitos';
    return null;
  }

  /// Enmascara un teléfono para `metadata` del consentimiento.
  static String enmascararTelefono(String telefono) {
    final digitos = telefono.replaceAll(RegExp(r'\D'), '');
    if (digitos.length <= 3) return '•••';
    return '••••${digitos.substring(digitos.length - 3)}';
  }

  // ── Interno ─────────────────────────────────────────────────────────────

  String get _uid {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      throw const SeguridadException(
        'Tu sesión expiró. Vuelve a iniciar sesión',
      );
    }
    return uid;
  }

  Future<dynamic> _rpc(
    String nombre, {
    required Map<String, dynamic> params,
    required String accion,
  }) async {
    try {
      return await _supabase.schema('muevete').rpc(nombre, params: params);
    } on PostgrestException catch (e) {
      throw SeguridadException(_mensajeRpc(e, accion), clave: _clave(e));
    } catch (e) {
      throw SeguridadException(AppError.message(e, action: accion));
    }
  }

  static String _mensajeRpc(PostgrestException e, String accion) {
    final clave = _clave(e);
    const mapa = <String, String>{
      'no_autenticado': 'Tu sesión expiró. Vuelve a iniciar sesión',
      'no_autorizado': 'No puedes hacer esta operación con tu cuenta',
      'no_participante': 'No participas en ese viaje',
      'solicitud_no_existe': 'La solicitud no existe',
      'viaje_no_activo': 'El viaje ya no está activo',
      'viaje_cerrado': 'El viaje ya terminó',
      'viaje_no_existe': 'El viaje no existe',
      'contacto_no_existe': 'El contacto no existe',
      'codigo_invalido': 'El código no es correcto o venció',
      'fuera_de_ventana': 'Pasó el tiempo para hacer esta operación',
      'chapa_no_confirmada':
          'Marca que la chapa coincide antes de iniciar el viaje',
      'metodo_invalido': 'Método de abordaje no válido',
      'no_se_pudo_generar_token':
          'No se pudo crear el enlace. Inténtalo de nuevo',
      'funcion_no_disponible':
          'Esta función todavía no está disponible en el servidor',
    };
    if (clave != null && mapa.containsKey(clave)) return mapa[clave]!;
    return AppError.message(e, action: accion);
  }

  static String? _clave(PostgrestException e) {
    final codigo = (e.code ?? '').toUpperCase();
    const porCodigo = <String, String>{
      'P0100': 'no_autenticado',
      'P0101': 'solicitud_no_existe',
      'P0102': 'no_participante',
      'P0103': 'viaje_no_activo',
      'P0104': 'evento_no_existe',
      'P0105': 'viaje_cerrado',
      'P0106': 'no_se_pudo_generar_token',
      'P0111': 'no_puedes_borrar_el_ultimo_contacto_aceptado',
      'P0112': 'contacto_invalido',
      'P0113': 'maximo_contactos_alcanzado',
      'P0114': 'contacto_no_existe',
      'P0115': 'codigo_invalido',
      'P0116': 'chapa_no_confirmada',
      'P0117': 'fuera_de_ventana',
      'P0030': 'viaje_no_existe',
      '42501': 'no_autorizado',
      '28000': 'no_autenticado',
      'PGRST202': 'funcion_no_disponible',
    };
    if (porCodigo.containsKey(codigo)) return porCodigo[codigo];

    final texto = '${e.message} ${e.details ?? ''}'.toLowerCase();
    for (final clave in porCodigo.values) {
      if (texto.contains(clave)) return clave;
    }
    if (texto.contains('could not find the function')) {
      return 'funcion_no_disponible';
    }
    return null;
  }

  static String _mensajeContacto(PostgrestException e) {
    final clave = _clave(e);
    switch (clave) {
      case 'maximo_contactos_alcanzado':
        return 'Ya tienes el máximo de contactos de emergencia (3)';
      case 'contacto_invalido':
        return 'Ese contacto no es válido: no puedes usar tu propio teléfono';
      case 'no_puedes_borrar_el_ultimo_contacto_aceptado':
        return 'Agrega otro contacto antes de borrar el último que tienes';
      case 'contacto_no_existe':
        return 'Ese contacto ya no existe';
      default:
        return AppError.message(e, action: 'guardar el contacto');
    }
  }

  static Map<String, dynamic> _asMap(dynamic res) {
    if (res is Map) return Map<String, dynamic>.from(res);
    if (res is List && res.isNotEmpty && res.first is Map) {
      return Map<String, dynamic>.from(res.first as Map);
    }
    return const <String, dynamic>{};
  }

  /// UUID v4 sin dependencias nuevas.
  static String _uuidV4() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
