import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'connectivity_service.dart';
import 'store_config_service.dart';
import 'user_preferences_service.dart';

/// Motivo por el que la licencia offline no es válida.
enum OfflineLicenseBlockReason {
  none,
  noLicense,
  invalidSignature,
  clockRollback,
  subscriptionExpired,
  validationWindowExpired,
  offlineNotAllowed,
}

/// Resultado de validar la licencia offline.
class OfflineLicenseStatus {
  final bool isValid;
  final OfflineLicenseBlockReason reason;
  final String message;
  final int? daysUntilForcedReconnect;
  final DateTime? fechaFin;
  final DateTime? emitidoEn;
  final int? diasMaxSinValidar;
  final bool permitirModoOfflineCompleto;

  const OfflineLicenseStatus({
    required this.isValid,
    required this.reason,
    required this.message,
    this.daysUntilForcedReconnect,
    this.fechaFin,
    this.emitidoEn,
    this.diasMaxSinValidar,
    this.permitirModoOfflineCompleto = false,
  });

  factory OfflineLicenseStatus.ok({
    DateTime? fechaFin,
    DateTime? emitidoEn,
    int? diasMaxSinValidar,
    int? daysUntilForcedReconnect,
    bool permitirModoOfflineCompleto = false,
  }) {
    return OfflineLicenseStatus(
      isValid: true,
      reason: OfflineLicenseBlockReason.none,
      message: 'Licencia offline válida',
      fechaFin: fechaFin,
      emitidoEn: emitidoEn,
      diasMaxSinValidar: diasMaxSinValidar,
      daysUntilForcedReconnect: daysUntilForcedReconnect,
      permitirModoOfflineCompleto: permitirModoOfflineCompleto,
    );
  }

  factory OfflineLicenseStatus.blocked({
    required OfflineLicenseBlockReason reason,
    required String message,
    DateTime? fechaFin,
    DateTime? emitidoEn,
    int? diasMaxSinValidar,
    int? daysUntilForcedReconnect,
    bool permitirModoOfflineCompleto = false,
  }) {
    return OfflineLicenseStatus(
      isValid: false,
      reason: reason,
      message: message,
      fechaFin: fechaFin,
      emitidoEn: emitidoEn,
      diasMaxSinValidar: diasMaxSinValidar,
      daysUntilForcedReconnect: daysUntilForcedReconnect,
      permitirModoOfflineCompleto: permitirModoOfflineCompleto,
    );
  }

  bool get requiresConnection =>
      !isValid &&
      (reason == OfflineLicenseBlockReason.validationWindowExpired ||
          reason == OfflineLicenseBlockReason.clockRollback ||
          reason == OfflineLicenseBlockReason.noLicense ||
          reason == OfflineLicenseBlockReason.invalidSignature ||
          reason == OfflineLicenseBlockReason.subscriptionExpired);
}

/// Servicio de licencia offline firmada (HMAC-SHA256).
///
/// Cadena canónica (misma que `fn_obtener_licencia_firmada`):
///   id_tienda|fecha_fin_epoch|emitido_en_epoch|dias_max|id_plan|permitir_offline
class OfflineLicenseService {
  static final OfflineLicenseService _instance =
      OfflineLicenseService._internal();
  factory OfflineLicenseService() => _instance;
  OfflineLicenseService._internal();

  /// Debe coincidir con `app_dat_licencia_offline_secreto.secreto`.
  /// Compilado en el binario para verificación local (HMAC simétrico).
  static const String _hmacSecret =
      'vq-offline-lic-2026-Xk9mR3xP7wQ2sT5vY8bN4cD6fH1jL0aZ';

  final UserPreferencesService _prefs = UserPreferencesService();
  final ConnectivityService _connectivity = ConnectivityService();
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Descarga la licencia firmada del servidor y la guarda localmente.
  Future<bool> fetchAndStoreSignedLicense(int storeId) async {
    try {
      print('🔐 Solicitando licencia firmada para tienda $storeId...');

      // Sesión local `offline_mode` no sirve para RPC; reautenticar si hace falta.
      final ready = await _ensureSupabaseSessionForLicenseFetch();
      if (!ready) {
        print(
          '❌ Sin sesión Supabase real: no se puede obtener licencia firmada',
        );
        return false;
      }

      final response = await _supabase.rpc(
        'fn_obtener_licencia_firmada',
        params: {'p_id_tienda': storeId},
      );

      if (response is! Map) {
        print('❌ Respuesta inesperada de fn_obtener_licencia_firmada: $response');
        return false;
      }

      final map = Map<String, dynamic>.from(response);
      if (map['success'] != true) {
        print('❌ Licencia firmada rechazada: ${map['message']}');
        return false;
      }

      final licenciaRaw = map['licencia'];
      final firma = map['firma']?.toString();
      if (licenciaRaw is! Map || firma == null || firma.isEmpty) {
        print('❌ Payload de licencia incompleto');
        return false;
      }

      final licencia = Map<String, dynamic>.from(licenciaRaw);
      if (!_verifySignature(licencia, firma)) {
        print('❌ Firma HMAC inválida al recibir licencia del servidor');
        return false;
      }

      await _prefs.saveSignedOfflineLicense(
        licencia: licencia,
        firma: firma,
      );
      await _prefs.updateLastSeenTimestamp();

      print('✅ Licencia firmada guardada localmente');
      return true;
    } catch (e) {
      print('❌ Error obteniendo licencia firmada: $e');
      return false;
    }
  }

  /// Garantiza un JWT real de Supabase antes del RPC de licencia.
  Future<bool> _ensureSupabaseSessionForLicenseFetch() async {
    final session = _supabase.auth.currentSession;
    if (session != null && !session.isExpired) {
      return true;
    }

    // Credenciales del usuario actual (remember me / offline_users / admin prep)
    String? email = await _prefs.getUserEmail();
    String? password;

    final saved = await _prefs.getSavedCredentials();
    if (email == null || email.isEmpty) {
      email = saved['email'];
    }
    password = saved['password'];

    if ((password == null || password.isEmpty) &&
        email != null &&
        email.isNotEmpty) {
      final offlineUsers = await _prefs.getOfflineUsers();
      for (final user in offlineUsers) {
        if (user['email']?.toString().toLowerCase() == email.toLowerCase()) {
          password = user['password']?.toString();
          break;
        }
      }
    }

    if ((password == null || password.isEmpty) ||
        email == null ||
        email.isEmpty) {
      final admin = await _prefs.getDeviceFullOfflineAdminCredentials();
      email = admin['email'];
      password = admin['password'];
    }

    if (email == null ||
        password == null ||
        email.isEmpty ||
        password.isEmpty) {
      print('⚠️ No hay credenciales para reautenticar y pedir licencia');
      return false;
    }

    try {
      print('🔑 Reautenticando en Supabase para obtener licencia ($email)...');
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (response.session == null) {
        print('❌ Reautenticación sin sesión');
        return false;
      }
      // No pisar el token offline_mode de la sesión local de la app:
      // solo necesitamos JWT en el client de Supabase para este RPC.
      print('✅ Sesión Supabase lista para licencia firmada');
      return true;
    } catch (e) {
      print('❌ Falló reautenticación para licencia: $e');
      return false;
    }
  }

  /// Valida la licencia local (firma + fechas + anti-rollback + ventana).
  Future<OfflineLicenseStatus> validateLocalLicense({int? storeId}) async {
    final resolvedStoreId =
        storeId ?? await _prefs.getIdTienda();
    if (resolvedStoreId == null) {
      return OfflineLicenseStatus.blocked(
        reason: OfflineLicenseBlockReason.noLicense,
        message: 'No hay tienda asociada a este dispositivo.',
      );
    }

    // Anti-manipulación de reloj
    final clockOk = await _prefs.touchAndValidateClock();
    if (!clockOk) {
      return OfflineLicenseStatus.blocked(
        reason: OfflineLicenseBlockReason.clockRollback,
        message:
            'Se detectó un cambio en la fecha del dispositivo. '
            'Conéctate a internet para revalidar la licencia.',
      );
    }

    final stored = await _prefs.getSignedOfflineLicense();
    if (stored == null) {
      // Fallback: si hay suscripción clásica y offline completo habilitado
      // por config cacheada, aún así exigimos token firmado.
      return OfflineLicenseStatus.blocked(
        reason: OfflineLicenseBlockReason.noLicense,
        message:
            'No hay licencia offline firmada en este dispositivo. '
            'Conéctate a internet para obtenerla.',
      );
    }

    final licencia = stored['licencia'] as Map<String, dynamic>;
    final firma = stored['firma'] as String;

    if (!_verifySignature(licencia, firma)) {
      await _prefs.clearSignedOfflineLicense();
      return OfflineLicenseStatus.blocked(
        reason: OfflineLicenseBlockReason.invalidSignature,
        message:
            'La licencia offline está corrupta o fue alterada. '
            'Conéctate a internet para renovarla.',
      );
    }

    final licenseStoreId = _asInt(licencia['id_tienda']);
    if (licenseStoreId != null && licenseStoreId != resolvedStoreId) {
      return OfflineLicenseStatus.blocked(
        reason: OfflineLicenseBlockReason.invalidSignature,
        message: 'La licencia no corresponde a esta tienda.',
      );
    }

    final permitirOffline =
        licencia['permitir_modo_offline_completo'] == true ||
        licencia['permitir_modo_offline_completo'] == 1 ||
        licencia['permitir_modo_offline_completo'] == '1';

    // Si la config local dice que offline completo está apagado, también bloquear
    // el camino offline (pero permitir online).
    final configAllows =
        await StoreConfigService.getPermitirModoOfflineCompleto(resolvedStoreId);
    final offlineAllowed = permitirOffline && configAllows;

    final fechaFinEpoch = _asInt(licencia['fecha_fin_epoch']) ?? 0;
    final emitidoEnEpoch = _asInt(licencia['emitido_en_epoch']) ?? 0;
    final diasMax = _asInt(licencia['dias_max_sin_validar']) ??
        await StoreConfigService.getDiasMaxSinValidarLicencia(resolvedStoreId);

    final fechaFin = fechaFinEpoch > 0
        ? DateTime.fromMillisecondsSinceEpoch(
            fechaFinEpoch * 1000,
            isUtc: true,
          ).toLocal()
        : null;
    final emitidoEn = emitidoEnEpoch > 0
        ? DateTime.fromMillisecondsSinceEpoch(
            emitidoEnEpoch * 1000,
            isUtc: true,
          ).toLocal()
        : null;

    final now = DateTime.now();

    if (fechaFin != null && !fechaFin.isAfter(now)) {
      return OfflineLicenseStatus.blocked(
        reason: OfflineLicenseBlockReason.subscriptionExpired,
        message:
            'La suscripción venció el ${_formatDate(fechaFin)}. '
            'Conéctate para renovar o revalidar.',
        fechaFin: fechaFin,
        emitidoEn: emitidoEn,
        diasMaxSinValidar: diasMax,
        permitirModoOfflineCompleto: offlineAllowed,
      );
    }

    // Ventana sin revalidar: desde emitido_en (o last_check de suscripción)
    final lastCheck = emitidoEn ??
        (await _prefs.getSubscriptionData())?['last_check'] as DateTime?;
    final anchor = lastCheck ?? now;
    final deadline = anchor.add(Duration(days: diasMax));
    final daysLeft = deadline.difference(now).inDays;

    if (now.isAfter(deadline)) {
      return OfflineLicenseStatus.blocked(
        reason: OfflineLicenseBlockReason.validationWindowExpired,
        message:
            'Debes conectarte a internet para revalidar la licencia '
            '(máximo $diasMax día${diasMax == 1 ? '' : 's'} sin validar).',
        fechaFin: fechaFin,
        emitidoEn: emitidoEn,
        diasMaxSinValidar: diasMax,
        daysUntilForcedReconnect: 0,
        permitirModoOfflineCompleto: offlineAllowed,
      );
    }

    if (!offlineAllowed && !_connectivity.isConnected) {
      return OfflineLicenseStatus.blocked(
        reason: OfflineLicenseBlockReason.offlineNotAllowed,
        message:
            'El modo offline completo no está habilitado para esta tienda. '
            'Se requiere conexión.',
        fechaFin: fechaFin,
        emitidoEn: emitidoEn,
        diasMaxSinValidar: diasMax,
        daysUntilForcedReconnect: daysLeft,
        permitirModoOfflineCompleto: false,
      );
    }

    return OfflineLicenseStatus.ok(
      fechaFin: fechaFin,
      emitidoEn: emitidoEn,
      diasMaxSinValidar: diasMax,
      daysUntilForcedReconnect: daysLeft,
      permitirModoOfflineCompleto: offlineAllowed,
    );
  }

  /// Revalida online si hay conexión; si no, valida localmente.
  Future<OfflineLicenseStatus> validate({
    int? storeId,
    bool forceOnlineRefresh = false,
  }) async {
    final resolvedStoreId = storeId ?? await _prefs.getIdTienda();
    if (resolvedStoreId == null) {
      return OfflineLicenseStatus.blocked(
        reason: OfflineLicenseBlockReason.noLicense,
        message: 'No hay tienda asociada a este dispositivo.',
      );
    }

    final online = _connectivity.isConnected;
    if (online && (forceOnlineRefresh || await _prefs.getSignedOfflineLicense() == null)) {
      final fetched = await fetchAndStoreSignedLicense(resolvedStoreId);
      if (!fetched && forceOnlineRefresh) {
        return OfflineLicenseStatus.blocked(
          reason: OfflineLicenseBlockReason.noLicense,
          message:
              'No se pudo revalidar la licencia con el servidor. '
              'Verifica la conexión e inténtalo de nuevo.',
        );
      }
    }

    return validateLocalLicense(storeId: resolvedStoreId);
  }

  bool _verifySignature(Map<String, dynamic> licencia, String firma) {
    final expected = _computeSignature(licencia);
    if (expected == null) return false;
    return _constantTimeEquals(expected, firma.toLowerCase());
  }

  String? _computeSignature(Map<String, dynamic> licencia) {
    final idTienda = _asInt(licencia['id_tienda']);
    final fechaFinEpoch = _asInt(licencia['fecha_fin_epoch']);
    final emitidoEnEpoch = _asInt(licencia['emitido_en_epoch']);
    final diasMax = _asInt(licencia['dias_max_sin_validar']);
    final idPlan = _asInt(licencia['id_plan']) ?? 0;
    if (idTienda == null ||
        fechaFinEpoch == null ||
        emitidoEnEpoch == null ||
        diasMax == null) {
      return null;
    }

    final permitir = licencia['permitir_modo_offline_completo'] == true ||
            licencia['permitir_modo_offline_completo'] == 1 ||
            licencia['permitir_modo_offline_completo'] == '1'
        ? '1'
        : '0';

    final canonico =
        '$idTienda|$fechaFinEpoch|$emitidoEnEpoch|$diasMax|$idPlan|$permitir';

    final hmac = Hmac(sha256, utf8.encode(_hmacSecret));
    return hmac.convert(utf8.encode(canonico)).toString();
  }

  static int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  static String _formatDate(DateTime d) {
    final local = d.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    return '${local.year}-$mm-$dd';
  }
}
