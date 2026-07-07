import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/wapi_destinatario.dart';
import '../models/wapi_envio_log.dart';
import '../models/wapi_group.dart';
import '../models/wapi_programacion.dart';
import '../models/wapi_session.dart';
import '../utils/timezone_helper.dart';

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

  Future<void> sessionAction(int idSesion, String action) async {
    assert(['logout', 'restart', 'delete'].contains(action));
    await _invoke('wapi-session-action', {
      'id_sesion': idSesion,
      'action': action,
    });
  }

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
  Future<Map<String, dynamic>> sendProductsNow({
    required int idSesion,
    required List<int> productIds,
    required List<WapiDestinatario> destinations,
    String? template,
    int delayMinSeconds = 5,
    int delayMaxSeconds = 10,
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

  Future<WapiProgramacion> saveProgramacion({
    required int idTienda,
    required int idSesion,
    required TimeOfDay hora,
    required List<int> productIds,
    required List<int> destinatarioIds,
    required bool activa,
    int delayMinSeconds = 5,
    int delayMaxSeconds = 10,
    // Si no se pasa, detectamos la zona IANA del dispositivo automáticamente.
    // Pasar un valor explícito sólo si el cliente eligió otra zona manualmente.
    String? timezone,
    int? idExistente,
  }) async {
    final tz = timezone ?? await TimezoneHelper.getLocalTimezone();
    final horaStr =
        '${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}:00';
    final payload = {
      'id_tienda': idTienda,
      'id_sesion': idSesion,
      'hora_envio': horaStr,
      'timezone': tz,
      'activa': activa,
      'delay_min_seconds': delayMinSeconds,
      'delay_max_seconds': delayMaxSeconds,
    };

    Map<String, dynamic> prog;
    if (idExistente != null) {
      prog = await _sb
          .from('app_wapi_programacion')
          .update(payload)
          .eq('id', idExistente)
          .select()
          .single();
    } else {
      prog = await _sb
          .from('app_wapi_programacion')
          .insert(payload)
          .select()
          .single();
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
}
