import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'resena_service.dart';

/// Decide **a quién** hay que pedirle la reseña al entrar en la app.
///
/// POR QUE EXISTE
///   El servidor dice qué reservas completadas siguen sin reseña
///   (`cliente_resenas_pendientes`, migración 59), pero eso no basta: si el
///   cliente cierra el cartel sin escribir, no se le puede volver a preguntar
///   por lo mismo cada vez que abra la app. Aquí se recuerda lo que ya se pidió.
///
/// REGLAS
///   * Se pide **una vez por reserva**: en cuanto se le enseña el cartel (la
///     escriba o no), esa reserva no vuelve a preguntarse.
///   * Si la escribe, además desaparece sola de la lista del servidor.
///   * **Una sola vez por sesión**: si tiene varias pendientes, no se le
///     encadenan carteles; la siguiente sale en la próxima entrada.
///
/// Se guarda en `SharedPreferences` (como el tutorial: no hay tabla de
/// preferencias de usuario y no hace falta). Se guardan los ids ya pedidos, con
/// un tope de [_maxRecordadas] para que la clave no crezca sin freno.
class PreguntaResenaService {
  PreguntaResenaService._();

  static const String _clave = 'flow_resenas_pedidas';
  static const int _maxRecordadas = 60;

  /// Marca + estado en memoria de la sesión (no se persiste a propósito: al
  /// volver a abrir la app se puede preguntar por la siguiente pendiente).
  static bool _yaPreguntadoEnEstaSesion = false;

  /// `true` si en esta sesión ya se mostró un cartel de reseña.
  static bool get yaPreguntadoEnEstaSesion => _yaPreguntadoEnEstaSesion;

  /// Solo para tests: deja la sesión como recién abierta.
  @visibleForTesting
  static void reiniciarSesion() => _yaPreguntadoEnEstaSesion = false;

  /// La reserva por la que hay que preguntar ahora, o `null` si no toca.
  ///
  /// Nunca lanza: si algo falla (sin conexión, migración 59 sin aplicar) el
  /// cliente simplemente no ve el cartel.
  static Future<ResenaPendiente?> siguientePendiente() async {
    if (_yaPreguntadoEnEstaSesion) return null;
    try {
      final pendientes = await ResenaService.pendientes();
      if (pendientes.isEmpty) return null;
      final pedidas = await _leerPedidas();
      for (final pendiente in pendientes) {
        if (!pedidas.contains(pendiente.idAgenda)) return pendiente;
      }
      return null;
    } catch (e) {
      debugPrint('[flow] PreguntaResenaService.siguientePendiente ERROR: $e');
      return null;
    }
  }

  /// Marca la reserva como ya preguntada (y la sesión como usada).
  static Future<void> marcarPreguntada(int idAgenda) async {
    _yaPreguntadoEnEstaSesion = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final pedidas = prefs.getStringList(_clave) ?? <String>[];
      final ids = pedidas.map(int.tryParse).whereType<int>().toList();
      if (ids.contains(idAgenda)) return;
      ids.add(idAgenda);
      // Se conservan las últimas: una reserva vieja ya no va a aparecer como
      // pendiente, así que no hace falta recordarla para siempre.
      final recortadas = ids.length > _maxRecordadas
          ? ids.sublist(ids.length - _maxRecordadas)
          : ids;
      await prefs.setStringList(
        _clave,
        recortadas.map((id) => id.toString()).toList(),
      );
    } catch (e) {
      debugPrint('[flow] PreguntaResenaService.marcarPreguntada ERROR: $e');
    }
  }

  /// Solo para tests: borra el historial de preguntas.
  @visibleForTesting
  static Future<void> limpiar() async {
    _yaPreguntadoEnEstaSesion = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_clave);
    } catch (_) {}
  }

  static Future<Set<int>> _leerPedidas() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pedidas = prefs.getStringList(_clave) ?? <String>[];
      return pedidas.map(int.tryParse).whereType<int>().toSet();
    } catch (_) {
      return <int>{};
    }
  }
}
