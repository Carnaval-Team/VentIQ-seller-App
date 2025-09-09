import 'package:flutter/material.dart';
import '../config/app_colors.dart';

class MarketingMenuWidget extends StatelessWidget {
  const MarketingMenuWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(
        Icons.apps,
        color: Colors.white,
      ),
      tooltip: 'Módulo de Marketing',
      onSelected: (value) => _navigateToModule(context, value),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'dashboard',
          child: Row(
            children: [
              Icon(Icons.dashboard, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Dashboard Marketing'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'promotions',
          child: Row(
            children: [
              Icon(Icons.local_offer, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Promociones'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'campaigns',
          child: Row(
            children: [
              Icon(Icons.campaign, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Campañas'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'communications',
          child: Row(
            children: [
              Icon(Icons.email, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Comunicaciones'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'segments',
          child: Row(
            children: [
              Icon(Icons.group, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Segmentos de Clientes'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'loyalty',
          child: Row(
            children: [
              Icon(Icons.stars, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Fidelización'),
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
              Text('Análisis y Reportes'),
            ],
          ),
        ),
      ],
    );
  }

  void _navigateToModule(BuildContext context, String module) {
    switch (module) {
      case 'dashboard':
        Navigator.pushNamed(context, '/marketing-dashboard');
        break;
      case 'promotions':
        Navigator.pushNamed(context, '/promotions');
        break;
      case 'campaigns':
        Navigator.pushNamed(context, '/campaigns');
        break;
      case 'communications':
        Navigator.pushNamed(context, '/communications');
        break;
      case 'segments':
        Navigator.pushNamed(context, '/segments');
        break;
      case 'loyalty':
        Navigator.pushNamed(context, '/loyalty');
        break;
      case 'analytics':
        Navigator.pushNamed(context, '/analytics');
        break;
    }
  }
}
