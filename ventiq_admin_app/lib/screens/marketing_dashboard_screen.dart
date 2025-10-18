import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../utils/screen_protection_mixin.dart';
import '../utils/navigation_guard.dart';
import '../widgets/marketing_menu_widget.dart';
import '../widgets/store_selector_widget.dart';

class MarketingDashboardScreen extends StatefulWidget {
  const MarketingDashboardScreen({super.key});

  @override
  State<MarketingDashboardScreen> createState() =>
      _MarketingDashboardScreenState();
}

class _MarketingDashboardScreenState extends State<MarketingDashboardScreen>
    with ScreenProtectionMixin {
  @override
  String get protectedRoute => '/marketing-dashboard';
  @override
  Widget build(BuildContext context) {
    if (isCheckingPermissions) return buildPermissionLoadingWidget();
    if (!hasAccess) return buildAccessDeniedWidget();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Marketing Dashboard'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: const [
          AppBarStoreSelectorWidget(),
          MarketingMenuWidget(),
          SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWelcomeCard(),
            const SizedBox(height: 24),
            _buildQuickStats(),
            const SizedBox(height: 24),
            _buildModuleGrid(),
            const SizedBox(height: 24),
            _buildRecentActivity(),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeCard() {
    return Card(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withOpacity(0.1),
              AppColors.primary.withOpacity(0.05),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.campaign, size: 32, color: AppColors.primary),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Módulo de Marketing',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        'Gestiona promociones, campañas y fidelización de clientes',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStats() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Promociones Activas',
            '12',
            Icons.local_offer,
            Colors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Campañas en Curso',
            '3',
            Icons.campaign,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Clientes Activos',
            '1,245',
            Icons.people,
            Colors.orange,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModuleGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Módulos Disponibles',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: [
            _buildModuleCard(
              'Promociones',
              'Gestiona descuentos y ofertas especiales',
              Icons.local_offer,
              Colors.green,
              '/promotions',
            ),
            _buildModuleCard(
              'Campañas',
              'Crea y administra campañas de marketing',
              Icons.campaign,
              Colors.blue,
              '/campaigns',
            ),
            _buildModuleCard(
              'Comunicaciones',
              'Envía mensajes y notificaciones',
              Icons.email,
              Colors.purple,
              '/communications',
            ),
            _buildModuleCard(
              'Segmentos',
              'Segmenta y clasifica clientes',
              Icons.group,
              Colors.orange,
              '/segments',
            ),
            _buildModuleCard(
              'Fidelización',
              'Programa de puntos y recompensas',
              Icons.stars,
              Colors.amber,
              '/loyalty',
            ),
            _buildModuleCard(
              'Análisis',
              'Reportes y métricas de marketing',
              Icons.analytics,
              Colors.teal,
              '/marketing-analytics',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildModuleCard(
    String title,
    String description,
    IconData icon,
    Color color,
    String route,
  ) {
    return Card(
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, route),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: color),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentActivity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Actividad Reciente',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              _buildActivityItem(
                'Nueva promoción creada',
                'Descuento Verano 2024 - 15% de descuento',
                Icons.local_offer,
                Colors.green,
                '2 horas',
              ),
              const Divider(height: 1),
              _buildActivityItem(
                'Campaña enviada',
                'Newsletter semanal enviada a 1,200 clientes',
                Icons.email,
                Colors.blue,
                '1 día',
              ),
              const Divider(height: 1),
              _buildActivityItem(
                'Segmento actualizado',
                'Clientes VIP - 45 nuevos miembros',
                Icons.group,
                Colors.orange,
                '2 días',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActivityItem(
    String title,
    String description,
    IconData icon,
    Color color,
    String time,
  ) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.2),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(description),
      trailing: Text(
        time,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
    );
  }
}
