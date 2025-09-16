import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/financial_service.dart';
import 'expense_categories_management_screen.dart';
import 'cost_types_management_screen.dart';
import 'cost_centers_management_screen.dart';
import 'profit_margins_management_screen.dart';
import 'cost_assignments_management_screen.dart';

class FinancialConfigurationScreen extends StatefulWidget {
  const FinancialConfigurationScreen({Key? key}) : super(key: key);

  @override
  State<FinancialConfigurationScreen> createState() => _FinancialConfigurationScreenState();
}

class _FinancialConfigurationScreenState extends State<FinancialConfigurationScreen> {
  final FinancialService _financialService = FinancialService();
  Map<String, dynamic> _configStats = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConfigurationStats();
  }

  Future<void> _loadConfigurationStats() async {
    try {
      final stats = await _financialService.getConfigurationStats();
      setState(() {
        _configStats = stats;
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Configuración Financiera',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadConfigurationStats,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _isLoading ? _buildLoadingState() : _buildContent(),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: 16),
          Text(
            'Cargando configuración...',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWelcomeCard(),
          const SizedBox(height: 20),
          _buildStatsGrid(),
          const SizedBox(height: 20),
          _buildConfigurationGrid(),
          const SizedBox(height: 20),
          _buildMarginAnalysis(),
          const SizedBox(height: 20), // Extra bottom padding
        ],
      ),
    );
  }

  Widget _buildWelcomeCard() {
    return Card(
      elevation: 2,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
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
                Icon(
                  Icons.settings,
                  size: 28,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Dashboard de Configuración',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Gestiona la configuración completa del sistema financiero',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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

  Widget _buildStatsGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Resumen de Configuración',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: crossAxisCount == 4 ? 1.2 : 1.4,
              children: [
                _buildStatCard(
                  'Categorías de Gastos',
                  '${_configStats['categories_count'] ?? 0}',
                  Icons.category,
                  AppColors.primary,
                ),
                _buildStatCard(
                  'Centros de Costo',
                  '${_configStats['cost_centers_count'] ?? 0}',
                  Icons.account_balance,
                  AppColors.success,
                ),
                _buildStatCard(
                  'Tipos de Costo',
                  '${_configStats['cost_types_count'] ?? 0}',
                  Icons.analytics,
                  AppColors.info,
                ),
                _buildStatCard(
                  'Asignaciones',
                  '${_configStats['assignments_count'] ?? 0}',
                  Icons.assignment,
                  AppColors.warning,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigurationGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Gestión de Configuración',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: crossAxisCount == 3 ? 1.0 : 1.1,
              children: [
                _buildConfigCard(
                  'Categorías de Gastos',
                  'Gestionar categorías y subcategorías',
                  Icons.category,
                  AppColors.primary,
                  () => _navigateToScreen(const ExpenseCategoriesManagementScreen()),
                ),
                _buildConfigCard(
                  'Tipos de Costos',
                  'Administrar tipos de costos',
                  Icons.analytics,
                  AppColors.info,
                  () => _navigateToScreen(const CostTypesManagementScreen()),
                ),
                _buildConfigCard(
                  'Centros de Costo',
                  'Gestionar centros de costo',
                  Icons.account_balance,
                  AppColors.success,
                  () => _navigateToScreen(const CostCentersManagementScreen()),
                ),
                _buildConfigCard(
                  'Márgenes Comerciales',
                  'Configurar márgenes de productos',
                  Icons.trending_up,
                  Colors.orange,
                  () => _navigateToScreen(const ProfitMarginsManagementScreen()),
                ),
                _buildConfigCard(
                  'Asignaciones de Costos',
                  'Gestionar asignaciones automáticas',
                  Icons.assignment,
                  AppColors.warning,
                  () => _navigateToScreen(const CostAssignmentsManagementScreen()),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _navigateToScreen(Widget screen) async {
    print('🚀 Navegando a pantalla: ${screen.runtimeType}');
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => screen),
      );
      print('✅ Navegación completada exitosamente');
      // Refresh data when returning from configuration screens
      _loadConfigurationStats();
    } catch (e) {
      print('❌ Error en navegación: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al navegar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildConfigCard(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: () {
          print('🔘 Card presionado: $title');
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        splashColor: color.withOpacity(0.2),
        highlightColor: color.withOpacity(0.1),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 24,
                  color: color,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMarginAnalysis() {
    final avgMargin = _configStats['avg_margin'] ?? 0.0;
    final minMargin = _configStats['min_margin'] ?? 0.0;
    final maxMargin = _configStats['max_margin'] ?? 0.0;
    final marginsCount = _configStats['margins_count'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Análisis de Márgenes Comerciales',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (marginsCount > 0) ...[
                  _buildMarginInfo('Margen Promedio', '${avgMargin.toStringAsFixed(1)}%', Colors.blue),
                  const SizedBox(height: 8),
                  _buildMarginInfo('Margen Más Alto', '${maxMargin.toStringAsFixed(1)}%', Colors.green),
                  const SizedBox(height: 8),
                  _buildMarginInfo('Margen Más Bajo', '${minMargin.toStringAsFixed(1)}%', Colors.orange),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.info.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info, color: AppColors.info, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Se han configurado $marginsCount márgenes comerciales activos',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: AppColors.warning, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No hay márgenes comerciales configurados. Configura márgenes para tus productos.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMarginInfo(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textPrimary,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
