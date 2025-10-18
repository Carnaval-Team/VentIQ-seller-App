import 'package:flutter/material.dart';
import '../services/permissions_service.dart';
import 'navigation_guard.dart';

/// Mixin para proteger pantallas según permisos del usuario
mixin ScreenProtectionMixin<T extends StatefulWidget> on State<T> {
  final PermissionsService _permissionsService = PermissionsService();
  
  bool _isCheckingPermissions = true;
  bool _hasAccess = false;
  UserRole? _userRole;

  /// Ruta de la pantalla a proteger (debe ser implementado por la clase)
  String get protectedRoute;

  /// Verificar permisos al iniciar
  @override
  void initState() {
    super.initState();
    _checkScreenPermissions();
  }

  /// Verificar si el usuario tiene acceso a esta pantalla
  Future<void> _checkScreenPermissions() async {
    try {
      final role = await _permissionsService.getUserRole();
      final canAccess = await _permissionsService.canAccessScreen(protectedRoute);

      if (mounted) {
        setState(() {
          _userRole = role;
          _hasAccess = canAccess;
          _isCheckingPermissions = false;
        });

        // Si no tiene acceso, regresar y mostrar mensaje
        if (!canAccess) {
          Navigator.pop(context);
          NavigationGuard.showActionDeniedMessage(
            context,
            'acceder a esta pantalla',
          );
        }
      }
    } catch (e) {
      print('❌ Error verificando permisos de pantalla: $e');
      if (mounted) {
        setState(() {
          _hasAccess = false;
          _isCheckingPermissions = false;
        });
        Navigator.pop(context);
      }
    }
  }

  /// Verificar si el usuario puede realizar una acción
  Future<bool> canPerformAction(String action) async {
    return await _permissionsService.canPerformAction(action);
  }

  /// Obtener el rol del usuario
  UserRole? get userRole => _userRole;

  /// Verificar si está cargando permisos
  bool get isCheckingPermissions => _isCheckingPermissions;

  /// Verificar si tiene acceso
  bool get hasAccess => _hasAccess;

  /// Widget de carga mientras se verifican permisos
  Widget buildPermissionLoadingWidget() {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Verificando permisos...'),
          ],
        ),
      ),
    );
  }

  /// Widget de acceso denegado
  Widget buildAccessDeniedWidget() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Acceso Denegado'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.block, size: 64, color: Colors.red.shade600),
            const SizedBox(height: 16),
            const Text(
              'No tienes permisos para acceder a esta pantalla',
              style: TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Regresar'),
            ),
          ],
        ),
      ),
    );
  }
}