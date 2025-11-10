import 'package:flutter/material.dart';
import 'subscription_service.dart';
import 'user_preferences_service.dart';
import '../models/subscription.dart';

class SubscriptionGuardService {
  static final SubscriptionGuardService _instance = SubscriptionGuardService._internal();
  factory SubscriptionGuardService() => _instance;
  SubscriptionGuardService._internal();

  final SubscriptionService _subscriptionService = SubscriptionService();
  final UserPreferencesService _userPreferencesService = UserPreferencesService();
  
  Subscription? _cachedSubscription;
  int? _cachedStoreId;
  DateTime? _lastCheck;
  
  // Rutas que están permitidas sin suscripción activa
  static const List<String> _allowedRoutesWithoutSubscription = [
    '/subscription-detail',
    '/login',
    '/',
  ];

  /// Verifica si el usuario tiene una suscripción activa válida
  Future<bool> hasActiveSubscription({bool forceRefresh = false}) async {
    try {
      final currentStoreId = await _userPreferencesService.getIdTienda();
      if (currentStoreId == null) {
        print('⚠️ No se pudo obtener ID de tienda para verificar suscripción');
        return false;
      }

      // Verificar primero en preferencias si no es refresh forzado
      if (!forceRefresh) {
        final shouldRefresh = await _userPreferencesService.shouldRefreshSubscription();
        if (!shouldRefresh) {
          final hasStoredActive = await _userPreferencesService.hasActiveSubscriptionStored();
          if (hasStoredActive) {
            print('✅ Suscripción válida desde preferencias (caché)');
            return true;
          }
        }
      }

      // Obtener suscripción del servidor
      _cachedSubscription = await _subscriptionService.getActiveSubscription(currentStoreId);
      _cachedStoreId = currentStoreId;
      _lastCheck = DateTime.now();

      if (_cachedSubscription == null) {
        print('❌ No se encontró suscripción activa para tienda: $currentStoreId');
        // Limpiar datos obsoletos de preferencias
        await _userPreferencesService.clearSubscriptionData();
        return false;
      }

      final isValid = _cachedSubscription!.isActive;
      print('🔍 Suscripción verificada: ${isValid ? 'VÁLIDA' : 'INVÁLIDA'}');
      
      if (isValid) {
        // Actualizar datos en preferencias
        await _userPreferencesService.saveSubscriptionData(
          subscriptionId: _cachedSubscription!.id,
          state: _cachedSubscription!.estado,
          planId: _cachedSubscription!.idPlan,
          planName: _cachedSubscription!.planDenominacion ?? 'Plan desconocido',
          startDate: _cachedSubscription!.fechaInicio,
          endDate: _cachedSubscription!.fechaFin,
          features: _cachedSubscription!.planFuncionesHabilitadas,
        );
      } else {
        print('  - Estado: ${_cachedSubscription!.estadoText}');
        print('  - Es activa: ${_cachedSubscription!.estado == 1}');
        print('  - Vencida: ${_cachedSubscription!.isExpired}');
        if (_cachedSubscription!.fechaFin != null) {
          print('  - Fecha fin: ${_cachedSubscription!.fechaFin}');
          print('  - Fecha actual: ${DateTime.now()}');
        }
        // Limpiar datos obsoletos de preferencias
        await _userPreferencesService.clearSubscriptionData();
      }

      return isValid;
    } catch (e) {
      print('❌ Error verificando suscripción activa: $e');
      return false;
    }
  }

  /// Obtiene la suscripción actual (puede ser inactiva)
  Future<Subscription?> getCurrentSubscription({bool forceRefresh = false}) async {
    await hasActiveSubscription(forceRefresh: forceRefresh);
    return _cachedSubscription;
  }

  /// Verifica si una ruta está permitida sin suscripción activa
  bool isRouteAllowedWithoutSubscription(String route) {
    return _allowedRoutesWithoutSubscription.contains(route);
  }

  /// Redirige al usuario a la vista de suscripción si no tiene suscripción activa
  Future<bool> checkAndRedirectIfNeeded(BuildContext context, String currentRoute) async {
    // Si ya está en una ruta permitida, no hacer nada
    if (isRouteAllowedWithoutSubscription(currentRoute)) {
      return true;
    }

    final hasActive = await hasActiveSubscription();
    if (!hasActive) {
      print('🚫 Acceso denegado a $currentRoute - Redirigiendo a detalles de suscripción');
      
      if (context.mounted) {
        // Mostrar mensaje informativo
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Tu suscripción no está activa. Contacta al administrador para activarla.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Ver Detalles',
              textColor: Colors.white,
              onPressed: () {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/subscription-detail',
                  (route) => false,
                );
              },
            ),
          ),
        );

        // Redirigir a detalles de suscripción
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

  /// Limpia el caché de suscripción
  void clearCache() {
    _cachedSubscription = null;
    _cachedStoreId = null;
    _lastCheck = null;
    print('🧹 Caché de suscripción limpiado');
  }

  /// Fuerza una verificación de suscripción
  Future<bool> forceCheck() async {
    return await hasActiveSubscription(forceRefresh: true);
  }

  /// Obtiene el mensaje apropiado según el estado de la suscripción
  String getSubscriptionStatusMessage() {
    if (_cachedSubscription == null) {
      return 'No se encontró información de suscripción para esta tienda.';
    }

    if (_cachedSubscription!.isExpired) {
      return 'Tu suscripción ha vencido el ${_cachedSubscription!.fechaFin?.toString().split(' ')[0]}. Contacta al administrador para renovarla.';
    }

    if (!_cachedSubscription!.isActive) {
      return 'Tu suscripción está ${_cachedSubscription!.estadoText.toLowerCase()}. Contacta al administrador para activarla.';
    }

    if (_cachedSubscription!.diasRestantes > 0 && _cachedSubscription!.diasRestantes <= 30) {
      return 'Tu suscripción vence en ${_cachedSubscription!.diasRestantes} días. Contacta al administrador para renovarla.';
    }

    return 'Tu suscripción está activa.';
  }

  /// Obtiene el color apropiado según el estado de la suscripción
  Color getSubscriptionStatusColor() {
    if (_cachedSubscription == null || !_cachedSubscription!.isActive || _cachedSubscription!.isExpired) {
      return Colors.red;
    }

    if (_cachedSubscription!.diasRestantes > 0 && _cachedSubscription!.diasRestantes <= 30) {
      return Colors.orange;
    }

    return Colors.green;
  }
}
