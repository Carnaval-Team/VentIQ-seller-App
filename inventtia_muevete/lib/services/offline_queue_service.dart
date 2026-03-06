import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineQueueService {
  static const String _key = 'pending_positions';
  static const int _maxEntries = 2000;

  final SharedPreferences _prefs;

  OfflineQueueService(this._prefs);

  /// Add a position to the offline queue. FIFO eviction at [_maxEntries].
  void enqueue({
    required int driverId,
    required double latitude,
    required double longitude,
  }) {
    final list = _readList();
    list.add({
      'driver_id': driverId,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
    // FIFO eviction
    if (list.length > _maxEntries) {
      list.removeRange(0, list.length - _maxEntries);
    }
    _prefs.setString(_key, jsonEncode(list));
  }

  /// Read all pending entries without removing them.
  List<Map<String, dynamic>> peekAll() => _readList();

  /// Returns true if there are pending entries.
  bool get hasPending => _readList().isNotEmpty;

  /// Clear the queue (call only after successful flush).
  void clear() {
    _prefs.remove(_key);
  }

  /// Check internet connectivity with a DNS lookup (3s timeout).
  static Future<bool> hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  List<Map<String, dynamic>> _readList() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[OfflineQueue] Error decoding queue: $e');
      return [];
    }
  }
}
