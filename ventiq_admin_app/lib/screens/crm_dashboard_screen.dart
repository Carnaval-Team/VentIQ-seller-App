import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../utils/screen_protection_mixin.dart';
import '../utils/navigation_guard.dart';
import '../widgets/crm/crm_menu_widget.dart';
import '../widgets/crm/crm_kpi_cards.dart';
import '../widgets/store_selector_widget.dart';
import '../services/dashboard_service.dart';
import '../models/crm/crm_metrics.dart';

class CRMDashboardScreen extends StatefulWidget {
  const CRMDashboardScreen({super.key});

  @override
  State<CRMDashboardScreen> createState() => _CRMDashboardScreenState();
}

class _CRMDashboardScreenState extends State<CRMDashboardScreen>
    with ScreenProtectionMixin {
  @override
  String get protectedRoute => '/crm-dashboard';
  bool _isLoading = true;
  CRMMetrics _crmMetrics = const CRMMetrics();

  @override
  void initState() {
    super.initState();
    _loadCRMData();
  }

  Future<void> _loadCRMData() async {
    try {
      final metrics = await DashboardService.getCRMMetrics();
      setState(() {
        _crmMetrics = metrics;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading CRM data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CRM Empresarial'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: const [
          AppBarStoreSelectorWidget(),
          CRMMenuWidget(),
          SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadCRMData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWelcomeCard(),
              const SizedBox(height: 24),

              // KPIs CRM mejorados
              const Text(
                'Métricas CRM',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              CRMKPICards(metrics: _crmMetrics, isLoading: _isLoading),

              const SizedBox(height: 32),
              _buildModuleGrid(),
              const SizedBox(height: 24),
              _buildRecentActivity(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeCard() {
    return Card(
      elevation: 4,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
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
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.business_center,
                    size: 32,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CRM Empresarial',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Gestión integral de relaciones comerciales',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      if (!_isLoading)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_crmMetrics.totalContactsCalculated} contactos totales',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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

  Widget _buildModuleGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Módulos CRM',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.3,
          children: [
            _buildModuleCard(
              'Clientes',
              Icons.people,
              '/customers',
              Colors.blue,
              '${_crmMetrics.totalCustomers} registrados',
            ),
            _buildModuleCard(
              'Proveedores',
              Icons.factory,
              '/suppliers',
              Colors.orange,
              '${_crmMetrics.totalSuppliers} activos',
            ),
            _buildModuleCard(
              'Analytics',
              Icons.analytics,
              '/crm-analytics',
              Colors.green,
              'Reportes avanzados',
            ),
            _buildModuleCard(
              'Relaciones',
              Icons.handshake,
              '/relationships',
              Colors.purple,
              'Gestión comercial',
            ),
            _buildModuleCard(
              'Interacciones',
              Icons.star_rate,
              '/interacciones-clientes',
              Colors.amber,
              'Ratings y comentarios',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildModuleCard(
    String title,
    IconData icon,
    String route,
    Color color,
    String subtitle,
  ) {
    return Card(
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.pushNamed(context, route),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 2),
              Flexible(
                child: Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
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
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildActivityItem(
                  'Nuevo cliente VIP registrado',
                  '2 horas',
                  Icons.person_add,
                  Colors.green,
                ),
                const Divider(),
                _buildActivityItem(
                  'Recepción de proveedor completada',
                  '4 horas',
                  Icons.inventory,
                  Colors.blue,
                ),
                const Divider(),
                _buildActivityItem(
                  'Actualización de datos de contacto',
                  '1 día',
                  Icons.edit,
                  Colors.orange,
                ),
                const Divider(),
                _buildActivityItem(
                  'Análisis de métricas CRM generado',
                  '2 días',
                  Icons.analytics,
                  Colors.purple,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActivityItem(
    String title,
    String time,
    IconData icon,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                Text(
                  time,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
        ],
      ),
    );
  }
}
