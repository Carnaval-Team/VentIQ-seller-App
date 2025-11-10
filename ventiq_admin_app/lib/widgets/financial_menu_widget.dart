import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../screens/production_costs_screen.dart';
import '../utils/navigation_guard.dart';
import '../screens/cost_assignments_screen.dart';
import '../screens/financial_configuration_screen.dart';

class FinancialMenuWidget extends StatelessWidget {
  const FinancialMenuWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(
        Icons.apps,
        color: Colors.white,
      ),
      tooltip: 'Módulo Financiero',
      onSelected: (value) => _navigateToModule(context, value),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'dashboard',
          child: Row(
            children: [
              Icon(Icons.dashboard, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Dashboard Financiero'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'setup',
          child: Row(
            children: [
              Icon(Icons.settings, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Configuración'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'reports',
          child: Row(
            children: [
              Icon(Icons.analytics, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Reportes Avanzados'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'expenses',
          child: Row(
            children: [
              Icon(Icons.receipt_long, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Gestión de Gastos'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'budgets',
          child: Row(
            children: [
              Icon(Icons.account_balance, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Presupuestos'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'projections',
          child: Row(
            children: [
              Icon(Icons.trending_up, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Proyecciones'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'cost_assignments',
          child: Row(
            children: [
              Icon(Icons.attach_money, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Asignación de Costos'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'configuration',
          child: Row(
            children: [
              Icon(Icons.settings, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Configuración del sistema'),
            ],
          ),
        ),
      ],
    );
  }

  void _navigateToModule(BuildContext context, String module) async {
    switch (module) {
      case 'dashboard':
        NavigationGuard.navigateWithPermission(context, '/financial-dashboard');
        break;
      case 'setup':
        NavigationGuard.navigateWithPermission(context, '/financial-setup');
        break;
      case 'reports':
        NavigationGuard.navigateWithPermission(context, '/financial-reports');
        break;
      case 'expenses':
        NavigationGuard.navigateWithPermission(context, '/financial-expenses');
        break;
      case 'budgets':
        // Navegar a la pestaña de presupuestos en reportes
        NavigationGuard.navigateWithPermission(context, '/financial-reports');
        break;
      case 'projections':
        // Navegar a la pestaña de proyecciones en reportes
        NavigationGuard.navigateWithPermission(context, '/financial-reports');
        break;
      case 'cost_assignments':
        final canNavigate = await NavigationGuard.canNavigate('/cost-assignments', context);
        if (canNavigate) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const CostAssignmentsScreen(),
            ),
          );
        }
        break;
      case 'configuration':
        final canNavigate = await NavigationGuard.canNavigate('/financial-configuration', context);
        if (canNavigate) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const FinancialConfigurationScreen(),
            ),
          );
        }
        break;
    }
  }
}
