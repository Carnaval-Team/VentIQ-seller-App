import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../providers/notificacion_provider.dart';

/// Campana de notificaciones con badge de no leidas, reutilizable en cualquier
/// AppBar/Hero. Al tocar navega a /notificaciones.
///
/// [color] = color del icono (blanco sobre hero, primary sobre AppBar claro).
/// [onSurface] = true cuando va sobre fondo claro (usa fondo de pastilla suave).
class NotificacionesBell extends StatelessWidget {
  final Color color;
  final bool onSurface;

  const NotificacionesBell({
    super.key,
    this.color = Colors.white,
    this.onSurface = false,
  });

  @override
  Widget build(BuildContext context) {
    final count = context.select<NotificacionProvider, int>(
      (p) => p.unreadCount,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: onSurface
              ? AppTheme.primary.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.pushNamed(context, '/notificaciones'),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                count > 0
                    ? Icons.notifications
                    : Icons.notifications_outlined,
                color: color,
                size: 26,
              ),
            ),
          ),
        ),
        if (count > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              decoration: BoxDecoration(
                color: AppTheme.error,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Center(
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
