import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/auth_service.dart';

/// Bloquea el acceso a una pantalla si el superadmin logueado
/// no tiene permiso para la ruta indicada.
class RouteGuard extends StatelessWidget {
  final String route;
  final Widget child;

  const RouteGuard({
    super.key,
    required this.route,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (AuthService.canAccessRoute(route)) return child;

    return Scaffold(
      appBar: AppBar(title: const Text('Acceso denegado')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 64, color: AppColors.error),
              const SizedBox(height: 16),
              const Text(
                'No tienes permiso para acceder a esta sección',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Contacta a un administrador para que te asigne el rol correspondiente.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.pushReplacementNamed(context, '/dashboard'),
                icon: const Icon(Icons.dashboard),
                label: const Text('Ir al Dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
