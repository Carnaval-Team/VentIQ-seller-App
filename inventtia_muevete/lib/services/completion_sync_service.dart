import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persiste los cierres de viaje que quedaron pendientes por falta de conexión
/// y los sincroniza cuando vuelve la señal.
///
/// Cola en SharedPreferences, clave `pending_completions`.
///
/// Formatos admitidos (campo `v`):
///
/// - `v: 2` — flujo de precio fijo. Sólo lleva `viaje_id` (y la espera si se
///   conoce): el monto, la comisión y el neto los calcula el servidor en
///   `fn_completar_viaje`, que es **idempotente**, así que reintentar es
///   seguro.
/// - sin `v` — entradas `v1` del flujo viejo de negociación que ya pueden
///   estar guardadas en el teléfono de un chofer. No se migran: se envían por
///   su camino legacy y se descartan al terminar de enviarse.
class CompletionSyncService {
  static const String _key = 'pending_completions';

  /// Versión que escribe esta build.
  static const int _versionActual = 2;

  static final _supabase = Supabase.instance.client;

  // ── Queue operations ────────────────────────────────────────────────────

  /// Encola un cierre de viaje del flujo nuevo.
  ///
  /// [esperaMin] es opcional: sólo se usa si el viaje no trae una espera
  /// medida en servidor. No se encola ningún precio (nunca).
  static Future<void> enqueueCompletion({
    required int viajeId,
    int? esperaMin,
    String? role, // 'client' | 'driver' — informativo para el log
    DateTime? timestamp,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = _readList(prefs);
    list.add({
      'v': _versionActual,
      'viaje_id': viajeId,
      'espera_min': esperaMin,
      'role': role,
      'ts': (timestamp ?? DateTime.now()).toUtc().toIso8601String(),
    });
    await prefs.setString(_key, jsonEncode(list));
  }

  static Future<bool> get hasPendingCompletions async {
    final prefs = await SharedPreferences.getInstance();
    return _readList(prefs).isNotEmpty;
  }

  static Future<List<Map<String, dynamic>>> peekCompletions() async {
    final prefs = await SharedPreferences.getInstance();
    return _readList(prefs);
  }

  static Future<void> clearCompletions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  // ── Sync logic ────────────────────────────────────────────────────────────

  /// Intenta sincronizar todos los cierres pendientes. Llamar al:
  /// - arrancar la app, al volver del segundo plano y al recuperar conexión.
  static Future<void> syncPendingCompletions() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _readList(prefs);
    if (list.isEmpty) return;

    // Check connectivity
    if (!await _hasInternet()) return;

    final remaining = <Map<String, dynamic>>[];

    for (final entry in list) {
      try {
        await _syncOne(entry);
      } catch (e) {
        debugPrint('[CompletionSync] Failed to sync: $e');
        remaining.add(entry);
      }
    }

    if (remaining.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, jsonEncode(remaining));
    }
  }

  static Future<void> _syncOne(Map<String, dynamic> entry) async {
    final version = (entry['v'] as num?)?.toInt() ?? 1;
    if (version >= 2) {
      await _enviarV2(entry);
    } else {
      // Compatibilidad: drenar la cola vieja tal como se enviaba antes.
      await _enviarV1(entry);
    }
  }

  /// Flujo de precio fijo: el servidor recalcula todo. Idempotente, así que
  /// repetir la llamada nunca cobra dos veces.
  static Future<void> _enviarV2(Map<String, dynamic> entry) async {
    final viajeId = (entry['viaje_id'] as num?)?.toInt();
    if (viajeId == null) {
      throw Exception('Entrada v2 sin viaje_id');
    }
    final esperaMin = (entry['espera_min'] as num?)?.toInt();

    try {
      final res = await _supabase.schema('muevete').rpc(
        'fn_completar_viaje',
        params: {
          'p_viaje_id': viajeId,
          'p_espera_min': esperaMin,
        },
      );
      if (res is Map && res['success'] == false) {
        throw Exception(res['error'] ?? 'El servidor no confirmó el cierre');
      }
    } on PostgrestException catch (e) {
      // El viaje ya está cerrado (o no existe): la entrada cumplió su
      // objetivo, se descarta en vez de reintentar para siempre.
      final texto = '${e.code ?? ''} ${e.message}';
      if (texto.contains('P0032') ||
          texto.contains('viaje_ya_completado') ||
          texto.contains('estado_invalido') ||
          texto.contains('P0030') ||
          texto.contains('viaje_no_existe')) {
        debugPrint(
          '[CompletionSync] Viaje $viajeId ya cerrado en servidor; '
          'se descarta la entrada.',
        );
        return;
      }
      rethrow;
    }
  }

  /// Flujo viejo (v1): se conserva el envío tal cual lo hacía la build
  /// anterior para no perder cierres que queden en el teléfono.
  static Future<void> _enviarV1(Map<String, dynamic> entry) async {
    final role = entry['role'] as String;
    final viajeId = entry['viaje_id'] as int;
    final solicitudId = entry['solicitud_id'] as int;
    final metodoPago = entry['metodo_pago'] as String;

    if (role == 'client') {
      // If wallet payment, run the RPC first
      if (metodoPago == 'wallet') {
        final result = await _supabase.rpc(
          'complete_ride_payment',
          params: {
            'p_metodo_pago': metodoPago,
            'p_client_uuid': entry['user_id'],
            'p_driver_id': entry['driver_id'],
            'p_viaje_id': viajeId,
            'p_precio_final': entry['precio'],
            'p_precio_base': entry['precio_base'] ?? entry['precio'],
          },
        );
        final data = result as Map<String, dynamic>;
        if (data['success'] != true) {
          throw Exception(data['error'] ?? 'Error procesando pago');
        }
      }

      // Mark solicitud completada
      await _supabase
          .schema('muevete')
          .from('solicitudes_transporte')
          .update({'estado': 'completada'})
          .eq('id', solicitudId);

      // Also mark viaje as completed so driver's UI updates
      await _supabase
          .schema('muevete')
          .from('viajes')
          .update({'completado': true, 'estado': false})
          .eq('id', viajeId);
    } else {
      // Driver role
      // Mark viaje completado + estado false
      await _supabase
          .schema('muevete')
          .from('viajes')
          .update({'completado': true, 'estado': false})
          .eq('id', viajeId);

      // Also update solicitud
      await _supabase
          .schema('muevete')
          .from('solicitudes_transporte')
          .update({'estado': 'completada'})
          .eq('id', solicitudId);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static List<Map<String, dynamic>> _readList(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}