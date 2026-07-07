import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

/// Helper para resolver la zona horaria IANA del dispositivo.
///
/// Se usa principalmente en las programaciones WAPI (envío diario automático),
/// donde Postgres calcula `next_run_at` con `AT TIME ZONE timezone`. Si la zona
/// está mal el cron dispara a la hora equivocada para el cliente.
class TimezoneHelper {
  TimezoneHelper._();

  /// Cache en memoria — la zona del dispositivo no cambia entre saves.
  static String? _cached;

  /// Fallback usado solo si la plataforma no puede resolver la zona.
  /// Lo mantenemos en CUBA/Habana porque es donde está la mayor parte de
  /// la base de clientes; en última instancia el usuario puede editar la
  /// programación si su zona difiere.
  static const String fallback = 'America/Havana';

  /// Devuelve el IANA timezone name del dispositivo (ej. 'America/Havana',
  /// 'America/Mexico_City', 'Europe/Madrid'). Si falla, devuelve [fallback].
  static Future<String> getLocalTimezone() async {
    if (_cached != null) return _cached!;
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      // En v5+ devuelve un TimezoneInfo con campo `identifier`.
      // Soportamos también el caso (poco probable) de que la API exponga
      // directamente un String, sin romper en compilación.
      final id = _extractIdentifier(info);
      if (id != null && id.isNotEmpty) {
        _cached = id;
        return id;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[TimezoneHelper] No se pudo obtener la zona: $e');
      }
    }
    _cached = fallback;
    return fallback;
  }

  /// Limpia el cache (útil si en algún momento exponemos un selector manual).
  static void invalidate() => _cached = null;

  static String? _extractIdentifier(dynamic info) {
    if (info == null) return null;
    if (info is String) return info;
    try {
      // TimezoneInfo de flutter_timezone v5+
      final dyn = info as dynamic;
      final id = dyn.identifier;
      if (id is String) return id;
    } catch (_) {}
    return null;
  }
}
