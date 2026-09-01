import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Maps technical/Supabase errors to short Spanish messages for the UI.
class AppError {
  AppError._();

  static const connection =
      'Hubo un problema de conexión, inténtalo más tarde';
  static const generic =
      'No se pudo completar la operación. Inténtalo de nuevo';
  static const unauthorized =
      'Tu sesión expiró. Vuelve a iniciar sesión';
  static const forbidden =
      'No tienes permiso para realizar esta acción';
  static const notFound =
      'No se encontró la información solicitada';
  static const conflict =
      'La operación no se pudo completar porque el registro ya existe o cambió';
  static const validation =
      'Revisa los datos ingresados e inténtalo de nuevo';
  static const server =
      'El servidor no responde correctamente. Inténtalo más tarde';

  /// Returns a user-safe message. Never exposes raw Supabase/PostgREST text.
  ///
  /// [action] optional context, e.g. "enviar la oferta" →
  /// "No se pudo enviar la oferta. Inténtalo de nuevo"
  static String message(Object? error, {String? action}) {
    if (error == null) {
      return _withAction(generic, action);
    }

    // Prefer our own already-friendly exceptions (not technical dumps).
    if (error is Exception) {
      final own = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      if (_looksUserFriendly(own)) return own;
    }

    if (_isConnectivity(error)) {
      return connection;
    }

    if (error is AuthException) {
      return _authMessage(error);
    }

    if (error is PostgrestException) {
      return _postgrestMessage(error, action: action);
    }

    if (error is StorageException) {
      return _withAction(
        'No se pudo subir o descargar el archivo. Inténtalo de nuevo',
        action,
      );
    }

    if (error is FunctionException) {
      return server;
    }

    if (error is TimeoutException) {
      return connection;
    }

    if (error is PlatformException) {
      final code = error.code.toLowerCase();
      final msg = (error.message ?? '').toLowerCase();
      if (code.contains('network') ||
          msg.contains('network') ||
          msg.contains('socket') ||
          msg.contains('connection')) {
        return connection;
      }
      return _withAction(generic, action);
    }

    final raw = error.toString().toLowerCase();
    if (_looksConnectivityText(raw)) return connection;
    if (raw.contains('jwt') ||
        raw.contains('session') ||
        raw.contains('not authenticated') ||
        raw.contains('unauthorized')) {
      return unauthorized;
    }
    if (raw.contains('permission') ||
        raw.contains('row-level security') ||
        raw.contains('rls') ||
        raw.contains('forbidden')) {
      return forbidden;
    }
    if (raw.contains('duplicate') ||
        raw.contains('unique') ||
        raw.contains('already exists')) {
      return conflict;
    }
    if (raw.contains('timeout') || raw.contains('timed out')) {
      return connection;
    }

    return _withAction(generic, action);
  }

  static String _withAction(String fallback, String? action) {
    if (action == null || action.trim().isEmpty) return fallback;
    if (fallback == generic) {
      return 'No se pudo $action. Inténtalo de nuevo';
    }
    if (fallback == connection) return connection;
    return fallback;
  }

  static bool _isConnectivity(Object error) {
    if (error is TimeoutException || error is ClientException) return true;
    // Avoid dart:io (breaks web). Detect native socket/http types by name.
    if (!kIsWeb) {
      final type = error.runtimeType.toString();
      if (type.contains('SocketException') ||
          type.contains('HandshakeException') ||
          type.contains('HttpException') ||
          type.contains('TlsException') ||
          type.contains('OSError')) {
        return true;
      }
    }
    return _looksConnectivityText(error.toString().toLowerCase());
  }

  static bool _looksConnectivityText(String raw) {
    return raw.contains('socketexception') ||
        raw.contains('failed host lookup') ||
        raw.contains('network is unreachable') ||
        raw.contains('connection refused') ||
        raw.contains('connection reset') ||
        raw.contains('connection closed') ||
        raw.contains('clientexception') ||
        raw.contains('xmlhttprequest') ||
        raw.contains('failed to fetch') ||
        raw.contains('network error') ||
        raw.contains('no internet') ||
        raw.contains('offline') ||
        raw.contains('timed out') ||
        raw.contains('timeout');
  }

  static bool _looksUserFriendly(String text) {
    if (text.isEmpty || text.length > 140) return false;
    final lower = text.toLowerCase();
    // Reject technical dumps
    if (lower.contains('postgrest') ||
        lower.contains('supabase') ||
        lower.contains('socketexception') ||
        lower.contains('postgres') ||
        lower.contains('pgrst') ||
        lower.contains('code:') ||
        lower.contains('statuscode') ||
        lower.contains('stack trace') ||
        lower.contains('http://') ||
        lower.contains('https://') ||
        RegExp(r'\b[0-9a-f]{8}-[0-9a-f]{4}-').hasMatch(lower)) {
      return false;
    }
    // Likely Spanish UX copy
    return RegExp(
      r'[áéíóúñÁÉÍÓÚÑ]|ya |no |debe |hubo |error |saldo |sesión',
      caseSensitive: false,
    ).hasMatch(text);
  }

  static String _authMessage(AuthException error) {
    final msg = error.message.toLowerCase();
    final status = error.statusCode;

    if (status == '400' ||
        msg.contains('invalid login') ||
        msg.contains('invalid credentials') ||
        msg.contains('wrong password') ||
        msg.contains('email not confirmed')) {
      if (msg.contains('email not confirmed')) {
        return 'Debes confirmar tu correo antes de iniciar sesión';
      }
      return 'Correo o contraseña incorrectos';
    }
    if (msg.contains('user already registered') ||
        msg.contains('already been registered')) {
      return 'Ya existe una cuenta con este correo';
    }
    if (msg.contains('rate limit') || msg.contains('too many')) {
      return 'Demasiados intentos. Espera un momento e inténtalo de nuevo';
    }
    if (status == '401' || msg.contains('session') || msg.contains('jwt')) {
      return unauthorized;
    }
    return _withAction(generic, 'iniciar sesión');
  }

  static String _postgrestMessage(
    PostgrestException error, {
    String? action,
  }) {
    final code = (error.code ?? '').toUpperCase();
    final msg = error.message.toLowerCase();
    final details = (error.details?.toString() ?? '').toLowerCase();
    final hint = (error.hint ?? '').toLowerCase();
    final blob = '$msg $details $hint';

    if (code == '401' || code == 'PGRST301') return unauthorized;
    if (code == '403' || blob.contains('row-level security')) return forbidden;
    if (code == '404' || code == 'PGRST116') return notFound;
    if (code == '409' ||
        code == '23505' ||
        blob.contains('duplicate') ||
        blob.contains('unique')) {
      return conflict;
    }
    if (code == '23503') {
      return 'No se pudo completar porque faltan datos relacionados';
    }
    if (code == '23514' || code == '22P02' || code.startsWith('23')) {
      return validation;
    }
    if (code == '57014' || blob.contains('timeout')) return connection;
    if (code == '503' || code == '502' || code == '500') return server;

    return _withAction(generic, action);
  }
}
