import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/wapi_agotado_config.dart';
import '../models/wapi_agotado_log.dart';
import '../models/wapi_destinatario.dart';
import '../models/wapi_envio_log.dart';
import '../models/wapi_group.dart';
import '../models/wapi_programacion.dart';
import '../models/wapi_session.dart';
import '../utils/timezone_helper.dart';

/// ============================================================================
///  Avisos de agotado: la feature depende de tablas que se crean en una
///  migración aparte. Mientras esa migración no esté aplicada en el proyecto
///  Supabase, la app NO debe romperse: el servicio traduce el error de
///  Postgres y la UI muestra un aviso claro.
/// ============================================================================

/// Se lanza cuando las tablas/columna de avisos de agotado todavía no existen
/// en la base (migración pendiente de aplicar).
class WapiAgotadoNoDisponible implements Exception {
  final String? detalle;
  const WapiAgotadoNoDisponible([this.detalle]);

  /// Mensaje único para toda la UI: no duplicar el texto en cada pantalla.
  static const String mensaje =
      'Avisos de agotado no disponibles todavía: falta aplicar la migración.';

  @override
  String toString() => detalle == null ? mensaje : '$mensaje ($detalle)';
}

/// ¿El error es "la relación/columna no existe"? Cubre el código Postgres
/// `42P01` (undefined_table) y `42703` (undefined_column), además de los
/// `PGRST204`/`PGRST205` que devuelve PostgREST cuando el esquema del proyecto
/// todavía no tiene la migración aplicada.
bool esEsquemaFaltante(Object e, {String? columna}) {
  String? code;
  String texto = '';
  if (e is PostgrestException) {
    code = e.code;
    texto = '${e.message} ${e.details ?? ''} ${e.hint ?? ''}'.toLowerCase();
  } else {
    texto = '$e'.toLowerCase();
  }
  final col = columna?.toLowerCase();
  // Tabla inexistente: si falta la tabla, falta todo lo que hay dentro.
  if (code == '42P01' || code == 'PGRST205') return true;
  if (texto.contains('42p01') || texto.contains('pgrst205')) return true;
  // Columna inexistente (Postgres 42703 / PostgREST PGRST204): sólo cuenta si
  // el error nombra la columna que nos interesa. Un 42703 de OTRA columna no
  // se arregla reintentando sin la nuestra.
  if (code == '42703' || code == 'PGRST204') {
    return col == null || texto.contains(col);
  }
  if (texto.contains('42703') || texto.contains('pgrst204')) {
    return col == null || texto.contains(col);
  }
  final noExiste = texto.contains('does not exist') ||
      texto.contains('no existe') ||
      texto.contains('schema cache');
  if (!noExiste) return false;
  if (col == null) return true;
  return texto.contains(col);
}

/// Acciones que acepta `wapi-session-action`. Se listan aquí para que un
/// typo falle en desarrollo en vez de llegar al backend (que responde 400).
const _accionesSesion = <String>{
  'qr',
  'logout',
  'restart',
  'recover',
  'delete',
  'stop',
  'force-kill',
  'health',
  'register-webhook',
};

/// Servicio que centraliza todas las operaciones del módulo
/// "Notificación a Clientes" (difusión WhatsApp).
///
/// Reglas:
///   * Lecturas simples → directo a tabla (`app_wapi_*`) bajo RLS.
///   * Operaciones que tocan la API WAPI externa → siempre vía Edge Function.
class WapiNotificationService {
  WapiNotificationService._();
  static final WapiNotificationService instance = WapiNotificationService._();
  factory WapiNotificationService() => instance;

  final SupabaseClient _sb = Supabase.instance.client;

  /// ¿El backend soporta `app_wapi_programacion.solo_disponibles`?
  ///
  /// La app puede actualizarse ANTES de que se aplique la migración que crea
  /// esa columna. La primera vez que Postgres contesta "columna inexistente"
  /// se guarda aquí (en memoria, por sesión) para guardar sin el campo y no
  /// repetir el intento fallido en cada guardado.
  bool _soloDisponiblesSoportado = true;
  bool get soloDisponiblesSoportado => _soloDisponiblesSoportado;

  /// Mensaje NO bloqueante para la UI cuando el servidor aún no soporta el
  /// filtro. La programación se guarda igual; sólo falta aplicar la migración.
  static const String avisoSoloDisponiblesNoSoportado =
      'Programación guardada, pero tu base de datos todavía no soporta "solo '
      'disponibles": actualízala para habilitar ese filtro.';

  // =========================================================================
  // Edge Function invoker
  // =========================================================================

  Future<Map<String, dynamic>> _invoke(
    String fn,
    Map<String, dynamic> body,
  ) async {
    final res = await _sb.functions.invoke(fn, body: body);
    final data = res.data;
    if (data is Map<String, dynamic>) {
      if (data['success'] == true) {
        return (data['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      }
      final err = data['error'];
      final msg = (err is Map) ? (err['message'] ?? 'Error desconocido') : err?.toString() ?? 'Error desconocido';
      throw Exception('[$fn] $msg');
    }
    throw Exception('[$fn] Respuesta inválida: $data');
  }

  // =========================================================================
  // Sesiones / bots
  // =========================================================================

  Future<List<WapiSession>> listSessions(int idTienda) async {
    // Sincronizamos primero con WAPI vía Edge Function (best-effort)
    try {
      final data = await _invoke('wapi-list-sessions', {'id_tienda': idTienda});
      final list = (data['sesiones'] as List?) ?? const [];
      return list
          .map((e) => WapiSession.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Fallback: leer DB
      final rows = await _sb
          .from('app_wapi_sesion')
          .select()
          .eq('id_tienda', idTienda)
          .order('created_at', ascending: false);
      return (rows as List)
          .map((e) => WapiSession.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  Future<WapiSession> createSession({
    required int idTienda,
    required String nombre,
  }) async {
    final data = await _invoke('wapi-session-create', {
      'id_tienda': idTienda,
      'nombre': nombre,
    });
    final idSesion = (data['id_sesion'] as num).toInt();
    // Releer el row completo
    final row = await _sb
        .from('app_wapi_sesion')
        .select()
        .eq('id', idSesion)
        .single();
    return WapiSession.fromJson(row);
  }

  Future<WapiSessionStatus> getStatus(
    int idSesion, {
    bool includeQr = false,
  }) async {
    final data = await _invoke('wapi-session-status', {
      'id_sesion': idSesion,
      'include_qr': includeQr,
    });
    return WapiSessionStatus.fromJson(data);
  }

  /// Ejecuta una acción sobre la sesión y devuelve el status que reporta el
  /// backend tras ejecutarla (útil para saber si reconectar requiere QR).
  ///
  /// Usa [sessionActionRaw] si necesitas la respuesta completa: `restart`
  /// devuelve además `requiere_qr`, `requiere_confirmacion_manual`, los pasos
  /// ejecutados y `reintento_sugerido_en_segundos`.
  Future<WapiStatus> sessionAction(int idSesion, String action) async {
    final data = await sessionActionRaw(idSesion, action);
    return WapiStatus.fromString(data['status'] as String?);
  }

  /// Respuesta completa de `wapi-session-action`.
  Future<Map<String, dynamic>> sessionActionRaw(
    int idSesion,
    String action,
  ) async {
    assert(
      _accionesSesion.contains(action),
      'Acción de sesión no soportada: $action',
    );
    return _invoke('wapi-session-action', {
      'id_sesion': idSesion,
      'action': action,
    });
  }

  /// Estado del servidor OpenWA (health + versión).
  ///
  /// La `version` sólo viene si el backend tiene `WAPI_API_KEY`: sirve para
  /// saber si el gateway está atrasado respecto a los arreglos de reconexión.
  Future<Map<String, dynamic>> sessionHealth(int idSesion) =>
      sessionActionRaw(idSesion, 'health');

  /// Reconecta el bot con la escalera real (`_shared/session_recovery.ts`):
  /// sólo `/start` si el motor está apagado, `stop → start` si está colgado, y
  /// `force-kill → start` si la sesión quedó en FAILED.
  ///
  /// **No pide QR**: reusa las credenciales guardadas en el volumen de OpenWA.
  /// Devuelve la respuesta cruda para poder avisar si hay que confirmar algo en
  /// el teléfono (`requiere_confirmacion_manual`).
  ///
  /// Antes esto llamaba a `restart` (siempre `stop → start`, que tira el motor y
  /// con él el Chromium entero). `recover` decide según el estado REAL: si el
  /// motor ya estaba apagado se ahorra el `stop` y levanta antes.
  Future<Map<String, dynamic>> reconectar(int idSesion) =>
      sessionActionRaw(idSesion, 'recover');

  /// Espera a que el motor termine de levantar después de [reconectar].
  ///
  /// `recover` contesta en cuanto OpenWA acepta el arranque, pero el motor
  /// (Chromium + WhatsApp Web) tarda ~15-25 s en llegar a `ready`. La pantalla
  /// esperaba 3 s y acto seguido abría el diálogo del QR: el cliente creía que
  /// había que volver a escanear cuando en realidad sólo faltaba esperar.
  ///
  /// Sondea `wapi-session-status` (barato: una sesión) hasta que llega a
  /// `CONNECTED`, aparece un estado que ya no se resuelve esperando, o vence
  /// [timeout]. Devuelve la última foto (o `null` si no se pudo leer) y llama a
  /// [onTick] en cada vuelta para que la UI pueda ir contando.
  Future<WapiSessionStatus?> esperarConexion(
    int idSesion, {
    Duration timeout = const Duration(seconds: 90),
    Duration intervalo = const Duration(seconds: 4),
    void Function(WapiSessionStatus?)? onTick,
  }) async {
    final limite = DateTime.now().add(timeout);
    WapiSessionStatus? ultima;
    var ticks = 0;
    var estancado = 0;
    while (DateTime.now().isBefore(limite)) {
      await Future.delayed(intervalo);
      try {
        ultima = await getStatus(idSesion);
        onTick?.call(ultima);
      } catch (_) {
        // Un tick que falle no debe cortar la espera.
        continue;
      }
      ticks++;
      switch (ultima.status) {
        case WapiStatus.connected:
          return ultima;
        case WapiStatus.failed:
          // Estado terminal en OpenWA: esperar más no cambia nada.
          return ultima;
        case WapiStatus.scanQr:
          // Sin teléfono guardado el QR es el único camino: no esperamos más.
          final tel = ultima.phoneNumber?.trim();
          if (tel == null || tel.isEmpty) return ultima;
          estancado = 0;
        case WapiStatus.disconnected:
          // `recover` puede reportar `disconnected` un instante mientras el
          // motor arranca; sólo lo damos por perdido si se queda ahí.
          estancado++;
          if (ticks >= 3 && estancado >= 2) return ultima;
        case WapiStatus.initializing:
        case WapiStatus.connecting:
        case WapiStatus.unknown:
          estancado = 0; // sigue arrancando: otra vuelta
      }
    }
    return ultima;
  }

  /// Reintenta reconectar matando primero el motor del servidor. Es la segunda
  /// oportunidad cuando un `restart` normal no levanta el bot.
  Future<Map<String, dynamic>> forzarReinicio(int idSesion) =>
      sessionActionRaw(idSesion, 'force-kill');

  // =========================================================================
  // Grupos
  // =========================================================================

  Future<List<WapiGroup>> listGroups(int idSesion) async {
    final data = await _invoke('wapi-list-groups', {'id_sesion': idSesion});
    final list = (data['grupos'] as List?) ?? const [];
    return list
        .map((e) => WapiGroup.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // =========================================================================
  // Destinatarios (DB directo, RLS protege)
  // =========================================================================

  Future<List<WapiDestinatario>> getDestinatarios(int idTienda) async {
    final rows = await _sb
        .from('app_wapi_destinatario')
        .select()
        .eq('id_tienda', idTienda)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => WapiDestinatario.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<WapiDestinatario> upsertDestinatario({
    required int idTienda,
    int? idSesion,
    required WapiDestinatarioTipo tipo,
    required String chatId,
    String? etiqueta,
  }) async {
    final row = await _sb
        .from('app_wapi_destinatario')
        .upsert(
          {
            'id_tienda': idTienda,
            'id_sesion': idSesion,
            'tipo': tipo.apiValue,
            'chat_id': chatId,
            'etiqueta': etiqueta,
          },
          onConflict: 'id_tienda,chat_id',
        )
        .select()
        .single();
    return WapiDestinatario.fromJson(row);
  }

  Future<void> deleteDestinatario(int id) async {
    await _sb.from('app_wapi_destinatario').delete().eq('id', id);
  }

  // =========================================================================
  // Envío manual
  // =========================================================================

  /// Envía productos AHORA. Como el envío puede tardar varios minutos (delays
  /// anti-ban entre mensajes), el backend procesa en segundo plano y responde
  /// inmediatamente con:
  /// `{ queued: true, total_mensajes_estimados, tiempo_estimado_segundos,
  ///   delay_segundos: { min, max }, message }`.
  /// El progreso real se ve en el historial (`app_wapi_envio_log`).
  ///
  /// [soloDisponibles] lo decide el usuario en el selector de productos: si
  /// viene `true`, el backend descarta los productos agotados en el momento
  /// del envío (el stock puede cambiar entre que se elige y que se envía).
  /// Sólo se manda la clave cuando es `true`, así el envío manual normal sigue
  /// funcionando contra un backend que todavía no conozca el campo.
  Future<Map<String, dynamic>> sendProductsNow({
    required int idSesion,
    required List<int> productIds,
    required List<WapiDestinatario> destinations,
    String? template,
    int delayMinSeconds = 5,
    int delayMaxSeconds = 10,
    bool soloDisponibles = false,
  }) async {
    final destPayload = destinations
        .map((d) => {
              'tipo': d.tipo.apiValue,
              'chat_id': d.chatId,
              if (d.etiqueta != null) 'etiqueta': d.etiqueta,
            })
        .toList();
    return _invoke('wapi-send-products', {
      'id_sesion': idSesion,
      'product_ids': productIds,
      'destinations': destPayload,
      if (template != null && template.isNotEmpty)
        'message_template': template,
      'delay_min_seconds': delayMinSeconds,
      'delay_max_seconds': delayMaxSeconds,
      'tipo_envio': 'manual',
      if (soloDisponibles) 'solo_disponibles': true,
    });
  }

  /// Reanuda una tanda interrumpida: re-despacha SÓLO los mensajes que
  /// quedaron `pendiente` o `fallido`.
  ///
  /// El backend reutiliza esas mismas filas de `app_wapi_envio_log` (no
  /// inserta nuevas), así que la tanda original se completa en el historial
  /// en lugar de duplicarse.
  ///
  /// [summaryProductIds] son los productos de la tanda COMPLETA (no sólo los
  /// pendientes). Sin ellos, el resumen final listaría únicamente lo que se
  /// reanudó — el usuario vería "10 productos" tras un envío de 70.
  Future<Map<String, dynamic>> resumeTanda({
    required int idSesion,
    required List<int> logIds,
    List<int> summaryProductIds = const <int>[],
    int delayMinSeconds = 5,
    int delayMaxSeconds = 10,
  }) async {
    if (logIds.isEmpty) {
      throw Exception('No hay mensajes pendientes que reanudar.');
    }
    return _invoke('wapi-send-products', {
      'id_sesion': idSesion,
      'resume_log_ids': logIds,
      if (summaryProductIds.isNotEmpty)
        'summary_product_ids': summaryProductIds,
      // El backend los deriva de los logs; van vacíos para satisfacer el
      // contrato del endpoint.
      'product_ids': <int>[],
      'destinations': <Map<String, dynamic>>[],
      'delay_min_seconds': delayMinSeconds,
      'delay_max_seconds': delayMaxSeconds,
    });
  }

  // =========================================================================
  // Programación (Plan Avanzado)
  // =========================================================================

  Future<WapiProgramacion?> getProgramacion(int idTienda) async {
    final rows = await _sb
        .from('app_wapi_programacion')
        .select()
        .eq('id_tienda', idTienda)
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    final prog = rows.first;
    final idProg = (prog['id'] as num).toInt();

    final prods = await _sb
        .from('app_wapi_programacion_producto')
        .select('id_producto, orden')
        .eq('id_programacion', idProg)
        .order('orden');
    final dests = await _sb
        .from('app_wapi_programacion_destinatario')
        .select('id_destinatario')
        .eq('id_programacion', idProg);

    return WapiProgramacion.fromJson(
      prog,
      productIds: prods
          .map<int>((e) => ((e as Map)['id_producto'] as num).toInt())
          .toList(),
      destinatarioIds: dests
          .map<int>((e) => ((e as Map)['id_destinatario'] as num).toInt())
          .toList(),
    );
  }

  /// Guarda (crea o actualiza) la programación diaria.
  ///
  /// [soloDisponibles] se persiste en `app_wapi_programacion.solo_disponibles`
  /// y es lo que decide si el cron re-filtra los productos agotados. Se manda
  /// también cuando es `false`: omitirlo impediría volver a desactivarlo.
  ///
  /// COMPATIBILIDAD HACIA ATRÁS: la app puede actualizarse antes de que se
  /// aplique la migración de esa columna. Si el guardado falla por "columna
  /// inexistente", se reintenta SIN el campo (la programación se guarda igual,
  /// como antes), se recuerda en [soloDisponiblesSoportado] para no reintentar
  /// en cada guardado y la UI avisa de forma no bloqueante.
  Future<WapiProgramacion> saveProgramacion({
    required int idTienda,
    required int idSesion,
    required TimeOfDay hora,
    required List<int> productIds,
    required List<int> destinatarioIds,
    required bool activa,
    int delayMinSeconds = 5,
    int delayMaxSeconds = 10,
    bool soloDisponibles = false,
    // Si no se pasa, detectamos la zona IANA del dispositivo automáticamente.
    // Pasar un valor explícito sólo si el cliente eligió otra zona manualmente.
    String? timezone,
    int? idExistente,
  }) async {
    final tz = timezone ?? await TimezoneHelper.getLocalTimezone();
    final modelo = WapiProgramacion(
      id: idExistente ?? 0,
      idTienda: idTienda,
      idSesion: idSesion,
      nombre: 'Difusión diaria',
      horaEnvio: hora,
      timezone: tz,
      activa: activa,
      delayMinSeconds: delayMinSeconds,
      delayMaxSeconds: delayMaxSeconds,
      soloDisponibles: soloDisponibles,
    );

    Future<Map<String, dynamic>> escribir(Map<String, dynamic> payload) {
      if (idExistente != null) {
        return _sb
            .from('app_wapi_programacion')
            .update(payload)
            .eq('id', idExistente)
            .select()
            .single();
      }
      return _sb
          .from('app_wapi_programacion')
          .insert(payload)
          .select()
          .single();
    }

    final payload = modelo.toDbMap();
    // Ya sabemos que el servidor no tiene la columna: no la mandamos.
    if (!_soloDisponiblesSoportado) payload.remove('solo_disponibles');

    Map<String, dynamic> prog;
    try {
      prog = await escribir(payload);
    } on PostgrestException catch (e) {
      if (!esEsquemaFaltante(e, columna: 'solo_disponibles')) rethrow;
      // La migración todavía no está aplicada. Guardamos SIN el campo para no
      // romper un guardado que hoy funciona, y lo recordamos para la sesión.
      _soloDisponiblesSoportado = false;
      prog = await escribir(payload..remove('solo_disponibles'));
    }
    final idProg = (prog['id'] as num).toInt();

    // Reemplazar productos y destinos
    await _sb
        .from('app_wapi_programacion_producto')
        .delete()
        .eq('id_programacion', idProg);
    await _sb
        .from('app_wapi_programacion_destinatario')
        .delete()
        .eq('id_programacion', idProg);

    if (productIds.isNotEmpty) {
      final prodRows = <Map<String, dynamic>>[];
      for (var i = 0; i < productIds.length; i++) {
        prodRows.add({
          'id_programacion': idProg,
          'id_producto': productIds[i],
          'orden': i,
        });
      }
      await _sb.from('app_wapi_programacion_producto').insert(prodRows);
    }

    if (destinatarioIds.isNotEmpty) {
      await _sb.from('app_wapi_programacion_destinatario').insert(
            destinatarioIds
                .map((id) => {
                      'id_programacion': idProg,
                      'id_destinatario': id,
                    })
                .toList(),
          );
    }

    return WapiProgramacion.fromJson(
      prog,
      productIds: productIds,
      destinatarioIds: destinatarioIds,
    );
  }

  Future<void> setProgramacionActiva(int idProgramacion, bool activa) async {
    await _sb
        .from('app_wapi_programacion')
        .update({'activa': activa})
        .eq('id', idProgramacion);
  }

  // =========================================================================
  // Avisos de agotado (stock 0)
  //
  // Tablas del contrato WS3: `app_wapi_agotado_config`,
  // `app_wapi_agotado_destinatario` y `app_wapi_agotado_log` (config con
  // UNIQUE(id_tienda) → una fila por tienda). Mientras la migración no esté
  // aplicada, TODO lo de esta sección lanza [WapiAgotadoNoDisponible] y la UI
  // muestra el aviso de migración pendiente en vez de reventar.
  // =========================================================================

  static String _detalleError(Object e) =>
      e is PostgrestException ? (e.message) : '$e';

  /// Traduce el error: si es "no existe la tabla/columna" lo convierte en
  /// [WapiAgotadoNoDisponible]; si no, lo relanza intacto (con su stack).
  static Never _falloAgotado(Object e, StackTrace st) {
    if (esEsquemaFaltante(e)) {
      throw WapiAgotadoNoDisponible(_detalleError(e));
    }
    Error.throwWithStackTrace(e, st);
  }

  /// Configuración de avisos de agotado de la tienda, o `null` si aún no hay
  /// ninguna guardada. Lanza [WapiAgotadoNoDisponible] si falta la migración.
  Future<WapiAgotadoConfig?> getAgotadoConfig(int idTienda) async {
    try {
      final rows = await _sb
          .from('app_wapi_agotado_config')
          .select()
          .eq('id_tienda', idTienda)
          .limit(1);
      if (rows.isEmpty) return null;
      final cfg = rows.first;
      final idCfg = (cfg['id'] as num).toInt();
      final dests = await _sb
          .from('app_wapi_agotado_destinatario')
          .select('id_destinatario')
          .eq('id_config', idCfg);
      return WapiAgotadoConfig.fromJson(
        cfg,
        destinatarioIds: dests
            .map<int>((e) => ((e as Map)['id_destinatario'] as num).toInt())
            .toList(),
      );
    } catch (e, st) {
      _falloAgotado(e, st);
    }
  }

  /// Crea o actualiza la configuración y reemplaza sus destinatarios.
  ///
  /// Usa `upsert` sobre `id_tienda` (UNIQUE en el contrato): si la fila ya
  /// existe se actualiza, si no se crea. Idempotente y sin carrera con otro
  /// dispositivo de la misma tienda.
  Future<WapiAgotadoConfig> saveAgotadoConfig({
    required int idTienda,
    required int idSesion,
    required bool activo,
    required String plantilla,
    required int delayMinSeconds,
    required int delayMaxSeconds,
    required int cooldownMinutos,
    required List<int> destinatarioIds,
  }) async {
    final modelo = WapiAgotadoConfig(
      id: 0,
      idTienda: idTienda,
      idSesion: idSesion,
      activo: activo,
      plantilla: plantilla.trim().isEmpty
          ? WapiAgotadoConfig.plantillaDefault
          : plantilla.trim(),
      delayMinSeconds: delayMinSeconds,
      delayMaxSeconds: delayMaxSeconds,
      cooldownMinutos: cooldownMinutos,
      destinatarioIds: destinatarioIds,
    );
    try {
      final cfg = await _sb
          .from('app_wapi_agotado_config')
          .upsert(modelo.toDbMap(), onConflict: 'id_tienda')
          .select()
          .single();
      final idCfg = (cfg['id'] as num).toInt();

      await _sb
          .from('app_wapi_agotado_destinatario')
          .delete()
          .eq('id_config', idCfg);
      if (destinatarioIds.isNotEmpty) {
        await _sb.from('app_wapi_agotado_destinatario').insert(
              destinatarioIds
                  .map((id) => {
                        'id_config': idCfg,
                        'id_destinatario': id,
                      })
                  .toList(),
            );
      }
      return WapiAgotadoConfig.fromJson(cfg, destinatarioIds: destinatarioIds);
    } catch (e, st) {
      _falloAgotado(e, st);
    }
  }

  /// Enciende/apaga los avisos sin tocar el resto de la configuración.
  Future<void> setAgotadoActivo(int idConfig, bool activo) async {
    try {
      await _sb
          .from('app_wapi_agotado_config')
          .update({'activo': activo}).eq('id', idConfig);
    } catch (e, st) {
      _falloAgotado(e, st);
    }
  }

  /// Historial reciente de avisos (pendientes, enviados, fallidos u omitidos).
  Future<List<WapiAgotadoLog>> getAgotadoLogs(
    int idTienda, {
    int limit = 30,
  }) async {
    try {
      final rows = await _sb
          .from('app_wapi_agotado_log')
          .select()
          .eq('id_tienda', idTienda)
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .map((e) => WapiAgotadoLog.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      _falloAgotado(e, st);
    }
  }

  // =========================================================================
  // Debug del envío automático (cron + edge function dispatcher)
  // =========================================================================

  /// Devuelve un snapshot consolidado del estado del dispatcher para una
  /// tienda: vault secrets, cron job, programación, últimas respuestas HTTP
  /// y últimas corridas del cron. Útil para troubleshooting cuando el envío
  /// automático no se dispara.
  Future<Map<String, dynamic>> getDispatchDebug(int idTienda) async {
    final res = await _sb.rpc(
      'fn_wapi_dispatch_debug',
      params: {'p_id_tienda': idTienda},
    );
    if (res is Map) return Map<String, dynamic>.from(res);
    if (res is String) {
      // Algunos drivers devuelven el JSON como string
      final decoded = jsonDecode(res);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return <String, dynamic>{};
  }

  /// Fuerza un envío inmediato de una programación específica (ignora
  /// `next_run_at`). Devuelve el `request_id` que pg_net asignó a la
  /// llamada HTTP; tras unos segundos podemos verlo en
  /// [getDispatchDebug] dentro de `last_http_responses`.
  Future<Map<String, dynamic>> forceDispatch(int idProgramacion) async {
    final res = await _sb.rpc(
      'fn_wapi_force_dispatch',
      params: {'p_id_programacion': idProgramacion},
    );
    if (res is Map) return Map<String, dynamic>.from(res);
    return <String, dynamic>{'raw': res};
  }

  // =========================================================================
  // Historial
  // =========================================================================

  Future<List<WapiEnvioLog>> getRecentLogs(
    int idTienda, {
    int limit = 50,
  }) async {
    final rows = await _sb
        .from('app_wapi_envio_log')
        .select()
        .eq('id_tienda', idTienda)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((e) => WapiEnvioLog.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Mapa `chat_id → etiqueta` de los destinatarios de la tienda, para mostrar
  /// nombres de grupo en el historial en vez de ids `1203…@g.us`.
  Future<Map<String, String>> getEtiquetasDestinatarios(int idTienda) async {
    final rows = await _sb
        .from('app_wapi_destinatario')
        .select('chat_id, etiqueta')
        .eq('id_tienda', idTienda);
    final map = <String, String>{};
    for (final r in (rows as List)) {
      final chat = r['chat_id'] as String?;
      final etq = r['etiqueta'] as String?;
      if (chat != null && etq != null && etq.isNotEmpty) map[chat] = etq;
    }
    return map;
  }

  /// Denominaciones de productos por id. Se consulta sólo para los ids que
  /// aparecen en el historial visible.
  Future<Map<int, String>> getDenominacionesProductos(
    Iterable<int> idsProducto,
  ) async {
    final ids = idsProducto.toSet().toList();
    if (ids.isEmpty) return {};
    final rows = await _sb
        .from('app_dat_producto')
        .select('id, denominacion')
        .inFilter('id', ids);
    final map = <int, String>{};
    for (final r in (rows as List)) {
      final id = (r['id'] as num?)?.toInt();
      final den = r['denominacion'] as String?;
      if (id != null && den != null) map[id] = den;
    }
    return map;
  }
}
