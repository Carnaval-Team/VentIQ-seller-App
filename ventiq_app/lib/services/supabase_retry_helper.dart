import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'network_request_queue.dart';
import 'smart_offline_manager.dart';
import 'user_preferences_service.dart';

/// Envuelve una llamada de red para:
/// - Encolarla si falla por error de red
/// - Notificar al SmartOfflineManager para mostrar el diálogo de confirmación
/// - Esperar a que el usuario decida (Reintentar / Modo Offline)
///
/// Si la app ya está en modo offline, el error se propaga inmediatamente
/// para que el caller pueda usar su lógica de fallback (cache).
Future<T> withNetworkRetry<T>(
  Future<T> Function() request, {
  required String description,
}) async {
  // Si ya estamos en modo offline, no interceptar — dejar que el caller
  // maneje el error como hoy (cache fallback, mensaje, etc.)
  final isOfflineModeEnabled =
      await UserPreferencesService().isOfflineModeEnabled();
  if (isOfflineModeEnabled) {
    return request();
  }

  try {
    return await request();
  } catch (e) {
    if (!_isNetworkError(e)) {
      rethrow;
    }

    print('🌐 withNetworkRetry: error de red en "$description": $e');

    final completer = Completer<T>();
    NetworkRequestQueue().enqueue<T>(
      task: request,
      completer: completer,
      description: description,
    );

    // Disparar el flujo de detección + diálogo (sin esperar el resultado)
    SmartOfflineManager().reportNetworkFailure(description, e);

    return completer.future;
  }
}

bool _isNetworkError(Object error) {
  if (error is SocketException) return true;
  if (error is TimeoutException) return true;
  if (error is http.ClientException) return true;
  final msg = error.toString().toLowerCase();
  return msg.contains('socketexception') ||
      msg.contains('timeoutexception') ||
      msg.contains('clientexception') ||
      msg.contains('failed host lookup') ||
      msg.contains('connection refused') ||
      msg.contains('connection closed') ||
      msg.contains('connection reset') ||
      msg.contains('network is unreachable');
}
