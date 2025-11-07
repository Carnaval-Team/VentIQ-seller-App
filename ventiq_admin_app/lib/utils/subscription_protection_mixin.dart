import 'package:flutter/material.dart';
import '../services/subscription_guard_service.dart';

/// Mixin para proteger pantallas que requieren suscripción activa
mixin SubscriptionProtectionMixin<T extends StatefulWidget> on State<T> {
  final SubscriptionGuardService _subscriptionGuard = SubscriptionGuardService();
  bool _isCheckingSubscription = true;
  bool _hasValidSubscription = false;

  /// Ruta protegida - debe ser implementada por la clase que usa el mixin
  String get protectedRoute;

  @override
  void initState() {
    super.initState();
    _checkSubscriptionAccess();
  }

  /// Verifica si el usuario tiene acceso a esta pantalla
  Future<void> _checkSubscriptionAccess() async {
    try {
      final canAccess = await _subscriptionGuard.checkAndRedirectIfNeeded(
        context, 
        protectedRoute,
      );

      if (mounted) {
        setState(() {
          _hasValidSubscription = canAccess;
          _isCheckingSubscription = false;
        });
      }
    } catch (e) {
      print('❌ Error verificando acceso de suscripción: $e');
      if (mounted) {
        setState(() {
          _hasValidSubscription = false;
          _isCheckingSubscription = false;
        });
      }
    }
  }

  /// Widget que se muestra mientras se verifica la suscripción
  Widget buildSubscriptionCheckingWidget() {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Verificando suscripción...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Widget que se muestra cuando no hay suscripción válida
  Widget buildNoSubscriptionWidget() {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.block,
                size: 64,
                color: Colors.red[400],
              ),
              const SizedBox(height: 24),
              Text(
                'Acceso Restringido',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                _subscriptionGuard.getSubscriptionStatusMessage(),
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/subscription-detail',
                    (route) => false,
                  );
                },
                icon: const Icon(Icons.info_outline),
                label: const Text('Ver Detalles de Suscripción'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Método que debe ser llamado en el build de la pantalla protegida
  Widget buildProtectedContent(Widget content) {
    if (_isCheckingSubscription) {
      return buildSubscriptionCheckingWidget();
    }

    if (!_hasValidSubscription) {
      return buildNoSubscriptionWidget();
    }

    return content;
  }

  /// Fuerza una nueva verificación de suscripción
  Future<void> recheckSubscription() async {
    setState(() {
      _isCheckingSubscription = true;
    });
    await _checkSubscriptionAccess();
  }

  /// Verifica si tiene suscripción válida
  bool get hasValidSubscription => _hasValidSubscription;

  /// Verifica si está verificando suscripción
  bool get isCheckingSubscription => _isCheckingSubscription;
}
