import 'package:flutter/material.dart';
import '../services/permissions_service.dart';

/// Guard para proteger navegación según permisos del usuario
class NavigationGuard {
  static final PermissionsService _permissionsService = PermissionsService();

  /// Verificar si el usuario puede navegar a una ruta
  static Future<bool> canNavigate(
    String route,
    BuildContext context, {
    bool showDialog = true,
  }) async {
    try {
      final canAccess = await _permissionsService.canAccessScreen(route);

      if (!canAccess && showDialog && context.mounted) {
        _showAccessDeniedDialog(context, route);
      }

      return canAccess;
    } catch (e) {
      print('❌ Error verificando permisos de navegación: $e');
      return false;
    }
  }

  /// Navegar con verificación de permisos
  static Future<void> navigateWithPermission(
    BuildContext context,
    String route, {
    Object? arguments,
    bool replace = false,
  }) async {
    final canAccess = await canNavigate(route, context);

    if (canAccess && context.mounted) {
      if (replace) {
        Navigator.pushReplacementNamed(context, route, arguments: arguments);
      } else {
        Navigator.pushNamed(context, route, arguments: arguments);
      }
    }
  }

  /// Navegar y remover todas las rutas anteriores con verificación
  static Future<void> navigateAndRemoveUntil(
    BuildContext context,
    String route, {
    Object? arguments,
  }) async {
    final canAccess = await canNavigate(route, context);

    if (canAccess && context.mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        route,
        (route) => false,
        arguments: arguments,
      );
    }
  }

  /// Mostrar diálogo de acceso denegado
  static void _showAccessDeniedDialog(BuildContext context, String route) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.block, color: Colors.red.shade600),
            const SizedBox(width: 12),
            const Text('Acceso Denegado'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'No tienes permisos para acceder a esta sección.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Contacta con el gerente si necesitas acceso.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  /// Obtener el rol del usuario actual
  static Future<UserRole> getUserRole() async {
    return await _permissionsService.getUserRole();
  }

  /// Verificar si el usuario puede realizar una acción
  static Future<bool> canPerformAction(String action) async {
    return await _permissionsService.canPerformAction(action);
  }

  /// Mostrar mensaje de acción no permitida
  static void showActionDeniedMessage(
    BuildContext context,
    String actionName,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.block, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text('No tienes permisos para: $actionName'),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }
}