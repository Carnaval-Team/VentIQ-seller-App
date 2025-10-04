import 'package:flutter/material.dart';
import '../../config/app_colors.dart';

class CRMMenuWidget extends StatelessWidget {
  const CRMMenuWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(
        Icons.apps,
        color: Colors.white,
      ),
      tooltip: 'Módulo CRM',
      onSelected: (value) => _navigateToModule(context, value),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'dashboard',
          child: Row(
            children: [
              Icon(Icons.dashboard, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Dashboard CRM'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'customers',
          child: Row(
            children: [
              Icon(Icons.people, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Gestión de Clientes'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'suppliers',
          child: Row(
            children: [
              Icon(Icons.factory, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Gestión de Proveedores'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'relationships',
          child: Row(
            children: [
              Icon(Icons.handshake, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Relaciones Comerciales'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'interactions',
          child: Row(
            children: [
              Icon(Icons.chat, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Historial de Interacciones'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'opportunities',
          child: Row(
            children: [
              Icon(Icons.trending_up, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Oportunidades'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'analytics',
          child: Row(
            children: [
              Icon(Icons.analytics, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Analytics CRM'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'reports',
          child: Row(
            children: [
              Icon(Icons.assessment, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Reportes Avanzados'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'settings',
          child: Row(
            children: [
              Icon(Icons.settings, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Configuración CRM'),
            ],
          ),
        ),
      ],
    );
  }

  void _navigateToModule(BuildContext context, String module) {
    switch (module) {
      case 'dashboard':
        Navigator.pushNamed(context, '/crm-dashboard');
        break;
      case 'customers':
        Navigator.pushNamed(context, '/customers');
        break;
      case 'suppliers':
        Navigator.pushNamed(context, '/suppliers');
        break;
      case 'relationships':
        Navigator.pushNamed(context, '/relationships');
        break;
      case 'interactions':
        Navigator.pushNamed(context, '/crm-interactions');
        break;
      case 'opportunities':
        Navigator.pushNamed(context, '/crm-opportunities');
        break;
      case 'analytics':
        Navigator.pushNamed(context, '/crm-analytics');
        break;
      case 'reports':
        Navigator.pushNamed(context, '/crm-reports');
        break;
      case 'settings':
        Navigator.pushNamed(context, '/crm-settings');
        break;
      default:
        // Mostrar mensaje de funcionalidad próximamente
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$module - Próximamente'),
            backgroundColor: Colors.orange,
          ),
        );
    }
  }
}
