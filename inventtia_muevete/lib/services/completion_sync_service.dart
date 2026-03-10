import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists pending trip completions offline and syncs them when connectivity
/// returns.
///
/// Queue key: `pending_completions` in SharedPreferences.
class CompletionSyncService {
  static const String _key = 'pending_completions';
  static final _supabase = Supabase.instance.client;

  // ── Queue operations ────────────────────────────────────────────────────

  static Future<void> enqueueCompletion({
    required int solicitudId,
    required int viajeId,
    required int driverId,
    required String userId,
    required double precio,
    required String metodoPago,
    required String role, // 'client' | 'driver'
    DateTime? timestamp,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = _readList(prefs);
    list.add({
      'solicitud_id': solicitudId,
      'viaje_id': viajeId,
      'driver_id': driverId,
      'user_id': userId,
      'precio': precio,
      'metodo_pago': metodoPago,
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

  /// Attempt to sync all pending completions. Call on:
  /// - App startup, app resume, connectivity change.
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
    final role = entry['role'] as String;
    final viajeId = entry['viaje_id'] as int;
    final solicitudId = entry['solicitud_id'] as int;
    final metodoPago = entry['metodo_pago'] as String;

    if (role == 'client') {
      // If wallet payment, run the RPC first
      if (metodoPago == 'wallet') {
        final result = await _supabase.rpc('complete_ride_payment', params: {
          'p_metodo_pago': metodoPago,
          'p_client_uuid': entry['user_id'],
          'p_driver_id': entry['driver_id'],
          'p_viaje_id': viajeId,
          'p_precio_final': entry['precio'],
        });
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
