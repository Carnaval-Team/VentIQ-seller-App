import 'package:flutter/material.dart';
import 'connectivity_service.dart';
import 'offline_license_service.dart';
import 'store_config_service.dart';
import 'subscription_service.dart';
import 'user_preferences_service.dart';
import '../models/subscription.dart';

class SubscriptionGuardService {
  static final SubscriptionGuardService _instance =
      SubscriptionGuardService._internal();
  factory SubscriptionGuardService() => _instance;
  SubscriptionGuardService._internal();

  final SubscriptionService _subscriptionService = SubscriptionService();
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();
  final OfflineLicenseService _offlineLicenseService = OfflineLicenseService();
  final ConnectivityService _connectivityService = ConnectivityService();

  Subscription? _cachedSubscription;
  int? _cachedStoreId;
  DateTime? _lastCheck;
  OfflineLicenseStatus? _lastOfflineStatus;

  // Rutas que están permitidas sin suscripción/licencia activa
  static const List<String> _allowedRoutesWithoutSubscription = [
    '/subscription-detail',
    '/login',
    '/',
  ];

  OfflineLicenseStatus? get lastOfflineStatus => _lastOfflineStatus;

  /// Verifica si el usuario tiene una suscripción/licencia activa válida.
  ///
  /// - Con red: consulta servidor + renueva token firmado (también en full
  ///   offline: la red sirve para obtener/renovar licencia, no para sync).
  /// - Sin red + modo completo: valida token firmado local.
  /// - Sin red sin modo completo: falla (requiere conexión).
  Future<bool> hasActiveSubscription({bool forceRefresh = false}) async {
    try {
      final currentStoreId = await _userPreferencesService.getIdTienda();
      if (currentStoreId == null) {
        print('⚠️ No se pudo obtener ID de tienda para verificar suscripción');
        return false;
      }

      final hasNetwork = _connectivityService.isConnected;
      final stayFullyOffline =
          await _userPreferencesService.shouldStayFullyOffline();
      final offlineCompleto =
          await StoreConfigService.getPermitirModoOfflineCompleto(
            currentStoreId,
          );

      // Sin red: solo licencia local (full offline no inventa conectividad).
      if (!hasNetwork) {
        if (!offlineCompleto) {
          print('❌ Sin conexión y modo offline completo deshabilitado');
          _lastOfflineStatus = OfflineLicenseStatus.blocked(
            reason: OfflineLicenseBlockReason.offlineNotAllowed,
            message:
                'Se requiere conexión a internet. El modo offline completo '
                'no está habilitado para esta tienda.',
          );
          return false;
        }

        final status = await _offlineLicenseService.validateLocalLicense(
          storeId: currentStoreId,
        );
        _lastOfflineStatus = status;
        if (status.isValid) {
          print('✅ Licencia offline firmada válida');
          return true;
        }
        print('❌ Licencia offline inválida: ${status.message}');
        return false;
      }

      // Con red + full offline: priorizar licencia local; si falta/inválida,
      // descargarla del servidor (no bloquear por stayFullyOffline).
      if (stayFullyOffline && !forceRefresh) {
        var status = await _offlineLicenseService.validateLocalLicense(
          storeId: currentStoreId,
        );
        if (!status.isValid) {
          print(
            '🔐 Full offline con red pero sin licencia válida — '
            'intentando descargar...',
          );
          final fetched = await _offlineLicenseService
              .fetchAndStoreSignedLicense(currentStoreId);
          if (fetched) {
            status = await _offlineLicenseService.validateLocalLicense(
              storeId: currentStoreId,
            );
          }
        }
        _lastOfflineStatus = status;
        if (status.isValid) {
          print('✅ Licencia offline válida (full offline + red)');
          return true;
        }
        // Si no se pudo obtener licencia, seguir al flujo online clásico
        // para al menos validar suscripción activa.
        print(
          '⚠️ No se pudo validar licencia offline; '
          'continuando con verificación online de suscripción',
        );
      }

      // Online: caché corta si no se fuerza refresh
      if (!forceRefresh) {
        final shouldRefresh =
            await _userPreferencesService.shouldRefreshSubscription();
        if (!shouldRefresh) {
          // Preferir token firmado si existe
          final signed =
              await _userPreferencesService.getSignedOfflineLicense();
          if (signed != null) {
            final status = await _offlineLicenseService.validateLocalLicense(
              storeId: currentStoreId,
            );
            _lastOfflineStatus = status;
            if (status.isValid) {
              print('✅ Licencia firmada válida desde caché');
              return true;
            }
          }

          final hasStoredActive =
              await _userPreferencesService.hasActiveSubscriptionStored();
          if (hasStoredActive) {
            // Tienda con offline completo: asegurar token firmado aunque la
            // suscripción clásica esté en caché (evita el banner de bloqueo).
            if (offlineCompleto) {
              final ensured = await _ensureSignedLicense(currentStoreId);
              if (ensured) {
                print(
                  '✅ Suscripción en caché + licencia firmada asegurada',
                );
                return true;
              }
              // Seguir al refresh de servidor para reintentar licencia
            } else {
              print('✅ Suscripción válida desde preferencias (caché)');
              return true;
            }
          }
        }
      }

      // Obtener suscripción del servidor
      _cachedSubscription = await _subscriptionService.getActiveSubscription(
        currentStoreId,
      );
      _cachedStoreId = currentStoreId;
      _lastCheck = DateTime.now();

      if (_cachedSubscription == null) {
        print(
          '❌ No se encontró suscripción activa para tienda: $currentStoreId',
        );
        await _userPreferencesService.clearSubscriptionData();
        await _userPreferencesService.clearSignedOfflineLicense();
        _lastOfflineStatus = OfflineLicenseStatus.blocked(
          reason: OfflineLicenseBlockReason.subscriptionExpired,
          message: 'No se encontró suscripción activa para esta tienda.',
        );
        return false;
      }

      final isValid = _cachedSubscription!.isActive;
      print('🔍 Suscripción verificada: ${isValid ? 'VÁLIDA' : 'INVÁLIDA'}');

      if (isValid) {
        await _userPreferencesService.saveSubscriptionData(
          subscriptionId: _cachedSubscription!.id,
          state: _cachedSubscription!.estado,
          planId: _cachedSubscription!.idPlan,
          planName:
              _cachedSubscription!.planDenominacion ?? 'Plan desconocido',
          startDate: _cachedSubscription!.fechaInicio,
          endDate: _cachedSubscription!.fechaFin,
          features: _cachedSubscription!.planFuncionesHabilitadas,
        );
        await _userPreferencesService.updateLastSeenTimestamp();

        // Renovar token firmado (obligatorio para operar offline después)
        final ensured = await _ensureSignedLicense(currentStoreId);
        if (!ensured && offlineCompleto) {
          print(
            '⚠️ Suscripción activa pero no se pudo obtener licencia firmada',
          );
        }
      } else {
        print('  - Estado: ${_cachedSubscription!.estadoText}');
        print('  - Es activa: ${_cachedSubscription!.estado == 1}');
        print('  - Vencida: ${_cachedSubscription!.isExpired}');
        if (_cachedSubscription!.fechaFin != null) {
          print('  - Fecha fin: ${_cachedSubscription!.fechaFin}');
          print('  - Fecha actual: ${DateTime.now()}');
        }
        await _userPreferencesService.clearSubscriptionData();
        await _userPreferencesService.clearSignedOfflineLicense();
        _lastOfflineStatus = OfflineLicenseStatus.blocked(
          reason: OfflineLicenseBlockReason.subscriptionExpired,
          message: getSubscriptionStatusMessage(),
        );
      }

      return isValid;
    } catch (e) {
      print('❌ Error verificando suscripción activa: $e');

      // Si falló la red pero hay modo offline completo, intentar licencia local
      final storeId = await _userPreferencesService.getIdTienda();
      if (storeId != null) {
        final offlineCompleto =
            await StoreConfigService.getPermitirModoOfflineCompleto(storeId);
        if (offlineCompleto) {
          final status = await _offlineLicenseService.validateLocalLicense(
            storeId: storeId,
          );
          _lastOfflineStatus = status;
          return status.isValid;
        }
      }
      return false;
    }
  }

  /// Descarga/renueva la licencia firmada y actualiza [_lastOfflineStatus].
  Future<bool> _ensureSignedLicense(int storeId) async {
    final fetched =
        await _offlineLicenseService.fetchAndStoreSignedLicense(storeId);
    final status = await _offlineLicenseService.validateLocalLicense(
      storeId: storeId,
    );
    _lastOfflineStatus = status;
    return fetched && status.isValid;
  }

  /// Obtiene la suscripción actual (puede ser inactiva)
  Future<Subscription?> getCurrentSubscription({
    bool forceRefresh = false,
  }) async {
    await hasActiveSubscription(forceRefresh: forceRefresh);
    return _cachedSubscription;
  }

  /// Verifica si una ruta está permitida sin suscripción activa
  bool isRouteAllowedWithoutSubscription(String route) {
    return _allowedRoutesWithoutSubscription.contains(route);
  }

  /// Redirige al usuario a la vista de suscripción si no tiene suscripción activa.
  /// Bloqueo total de la app (decisión A del plan).
  Future<bool> checkAndRedirectIfNeeded(
    BuildContext context,
    String currentRoute,
  ) async {
    if (isRouteAllowedWithoutSubscription(currentRoute)) {
      return true;
    }

    final currentStoreId = await _userPreferencesService.getIdTienda();
    if (currentStoreId == null) {
      print('⚠️ No hay usuario logueado, permitiendo acceso a $currentRoute');
      return true;
    }

    final hasActive = await hasActiveSubscription();
    if (!hasActive) {
      print(
        '🚫 Acceso denegado a $currentRoute - Redirigiendo a detalles de suscripción',
      );

      if (context.mounted) {
        if (currentRoute != '/subscription-detail') {
          final msg =
              _lastOfflineStatus?.message ??
              'Tu suscripción/licencia no está activa. Redirigiendo...';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: Colors.orange,
              duration: const Duration(milliseconds: 2000),
            ),
          );
        }

        Navigator.pushNamedAndRemoveUntil(
          context,
          '/subscription-detail',
          (route) => false,
        );
      }
      return false;
    }

    return true;
  }

  /// Middleware para proteger rutas
  Future<bool> canAccessRoute(String route) async {
    if (isRouteAllowedWithoutSubscription(route)) {
      return true;
    }

    return await hasActiveSubscription();
  }

  /// Limpia el caché de suscripción y datos de preferencias
  Future<void> clearCache() async {
    _cachedSubscription = null;
    _cachedStoreId = null;
    _lastCheck = null;
    _lastOfflineStatus = null;
    await _userPreferencesService.clearSubscriptionData();
    await _userPreferencesService.clearSignedOfflineLicense();
    print('🧹 Caché de suscripción limpiado');
  }

  /// Fuerza una verificación de suscripción / revalidación de licencia.
  /// Con red, siempre intenta descargar la licencia firmada primero.
  Future<bool> forceCheck() async {
    final storeId = await _userPreferencesService.getIdTienda();
    if (storeId != null && _connectivityService.isConnected) {
      await _offlineLicenseService.fetchAndStoreSignedLicense(storeId);
    }
    return await hasActiveSubscription(forceRefresh: true);
  }

  /// Días restantes hasta forzar reconexión (null si no aplica).
  Future<int?> getDaysUntilForcedReconnect() async {
    final status =
        _lastOfflineStatus ??
        await _offlineLicenseService.validateLocalLicense();
    return status.daysUntilForcedReconnect;
  }

  /// Obtiene el mensaje apropiado según el estado de la suscripción
  String getSubscriptionStatusMessage() {
    if (_lastOfflineStatus != null && !_lastOfflineStatus!.isValid) {
      return _lastOfflineStatus!.message;
    }

    if (_cachedSubscription == null) {
      return 'No se encontró información de suscripción para esta tienda.';
    }

    if (_cachedSubscription!.isExpired) {
      return 'Tu suscripción ha vencido el ${_cachedSubscription!.fechaFin?.toString().split(' ')[0]}. Contacta al administrador para renovarla.';
    }

    if (!_cachedSubscription!.isActive) {
      return 'Tu suscripción está ${_cachedSubscription!.estadoText.toLowerCase()}. Contacta al administrador para activarla.';
    }

    if (_cachedSubscription!.diasRestantes > 0 &&
        _cachedSubscription!.diasRestantes <= 30) {
      return 'Tu suscripción vence en ${_cachedSubscription!.diasRestantes} días. Contacta al administrador para renovarla.';
    }

    return 'Tu suscripción está activa.';
  }

  /// Obtiene el color apropiado según el estado de la suscripción
  Color getSubscriptionStatusColor() {
    if (_lastOfflineStatus != null && !_lastOfflineStatus!.isValid) {
      return Colors.red;
    }

    if (_cachedSubscription == null ||
        !_cachedSubscription!.isActive ||
        _cachedSubscription!.isExpired) {
      return Colors.red;
    }

    if (_cachedSubscription!.diasRestantes > 0 &&
        _cachedSubscription!.diasRestantes <= 30) {
      return Colors.orange;
    }

    return Colors.green;
  }
}
