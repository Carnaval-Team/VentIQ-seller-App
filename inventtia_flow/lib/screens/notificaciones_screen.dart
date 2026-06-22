import 'package:flutter/material.dart';
import '../config/app_theme.dart';

class NotificacionesScreen extends StatefulWidget {
  const NotificacionesScreen({super.key});

  @override
  State<NotificacionesScreen> createState() => _NotificacionesScreenState();
}

class _NotificacionesScreenState extends State<NotificacionesScreen> {
  bool _notifListas = true;
  bool _notifTickets = true;
  bool _notifPromos = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Notificaciones')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Preferencias de Notificación',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Cambios en mis listas'),
                  subtitle: const Text(
                      'Cuando tu número esté próximo a ser atendido'),
                  value: _notifListas,
                  activeColor: AppTheme.primary,
                  onChanged: (v) => setState(() => _notifListas = v),
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.list_alt,
                        color: AppTheme.primary, size: 20),
                  ),
                ),
                const Divider(height: 1, indent: 72),
                SwitchListTile(
                  title: const Text('Actualizaciones de reservas'),
                  subtitle: const Text(
                      'Cuando el estado de tu ticket cambie'),
                  value: _notifTickets,
                  activeColor: AppTheme.primary,
                  onChanged: (v) => setState(() => _notifTickets = v),
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.confirmation_number,
                        color: AppTheme.accent, size: 20),
                  ),
                ),
                const Divider(height: 1, indent: 72),
                SwitchListTile(
                  title: const Text('Novedades y promociones'),
                  subtitle:
                      const Text('Nuevos servicios y anuncios del sistema'),
                  value: _notifPromos,
                  activeColor: AppTheme.primary,
                  onChanged: (v) => setState(() => _notifPromos = v),
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.campaign,
                        color: AppTheme.warning, size: 20),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Historial placeholder
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Historial',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Column(
                      children: [
                        Icon(Icons.notifications_none,
                            size: 48,
                            color: AppTheme.textSecondary.withOpacity(0.4)),
                        const SizedBox(height: 8),
                        const Text(
                          'No hay notificaciones recientes',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
