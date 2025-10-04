import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/crm/crm_menu_widget.dart';
import '../widgets/store_selector_widget.dart';
import '../services/dashboard_service.dart';
import '../models/crm/crm_metrics.dart';

class CRMDashboardScreen extends StatefulWidget {
  const CRMDashboardScreen({super.key});

  @override
  State<CRMDashboardScreen> createState() => _CRMDashboardScreenState();
}

class _CRMDashboardScreenState extends State<CRMDashboardScreen> {
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
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
                const Icon(
                  Icons.business_center,
                  size: 32,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 12),
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
                      Text(
                        'Gestión integral de clientes y proveedores - ${_crmMetrics.totalContactsCalculated} contactos',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
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

  Widget _buildQuickStats() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Clientes',
            '${_crmMetrics.totalCustomers}',
            Icons.people,
            Colors.blue,
            '${_crmMetrics.vipCustomers} VIP',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Proveedores',
            '${_crmMetrics.totalSuppliers}',
            Icons.factory,
            Colors.orange,
            '${_crmMetrics.activeSuppliers} activos',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Score Relaciones',
            '${_crmMetrics.relationshipScore.toStringAsFixed(1)}%',
            Icons.trending_up,
            Colors.green,
            'Excelente',
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, String subtitle) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(
              title,
              style: const TextStyle(color: Colors.grey),
            ),
            Text(
              subtitle,
              style: TextStyle(color: color, fontSize: 12),
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
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            _buildModuleCard('Clientes', Icons.people, '/customers', Colors.blue),
            _buildModuleCard('Proveedores', Icons.factory, '/suppliers', Colors.orange),
            _buildModuleCard('Analytics', Icons.analytics, '/crm-analytics', Colors.green),
            _buildModuleCard('Relaciones', Icons.handshake, '/relationships', Colors.purple),
          ],
        ),
      ],
    );
  }

  Widget _buildModuleCard(String title, IconData icon, String route, Color color) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.pushNamed(context, route),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600),
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
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildActivityItem('Nuevo cliente VIP registrado', '2 horas', Icons.person_add, Colors.green),
                _buildActivityItem('Recepción de proveedor completada', '4 horas', Icons.inventory, Colors.blue),
                _buildActivityItem('Actualización de datos de contacto', '1 día', Icons.edit, Colors.orange),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActivityItem(String title, String time, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
                Text(time, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
