import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/financial_menu_widget.dart';
import '../widgets/store_selector_widget.dart';
import '../services/financial_service.dart';
import 'financial_configuration_screen.dart';
import 'financial_expenses_screen.dart';
import 'financial_activity_history_screen.dart';
import 'cost_assignments_screen.dart';

class FinancialScreen extends StatefulWidget {
  const FinancialScreen({super.key});

  @override
  State<FinancialScreen> createState() => _FinancialScreenState();
}

class _FinancialScreenState extends State<FinancialScreen> {
  final FinancialService _financialService = FinancialService();
  bool _isInitializing = false;
  bool _isConfigured = false;
  bool _isLoading = true;
  int _pendingOperationsCount = 0;
  List<Map<String, dynamic>> _recentActivities = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await _checkConfigurationStatus();
    await _loadPendingOperationsCount();
    await _loadRecentActivities();
  }

  Future<void> _checkConfigurationStatus() async {
    try {
      final isConfigured = await _financialService.isSystemConfigured();
      setState(() {
        _isConfigured = isConfigured;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isConfigured = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadPendingOperationsCount() async {
    try {
      final count = await _financialService.getPendingOperationsCount();
      setState(() {
        _pendingOperationsCount = count;
      });
    } catch (e) {
      print('❌ Error cargando operaciones pendientes: $e');
      setState(() {
        _pendingOperationsCount = 0;
      });
    }
  }

  Future<void> _loadRecentActivities() async {
    try {
      final activities = await _financialService.getRecentActivities();
      setState(() {
        _recentActivities = activities;
      });
    } catch (e) {
      print('❌ Error cargando actividades recientes: $e');
      setState(() {
        _recentActivities = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Módulo Financiero'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: const [
          AppBarStoreSelectorWidget(),
          FinancialMenuWidget(),
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
            // Solo mostrar configuración si NO está configurado
            if (!_isConfigured && !_isLoading) ...[
              _buildConfigurationCard(),
              const SizedBox(height: 24),
            ],
            _buildQuickStats(),
            const SizedBox(height: 24),
            _buildModuleGrid(),
            const SizedBox(height: 24),
            _buildRecentActivity(),
            const SizedBox(height: 24),
            _buildPendingOperationsCard(),
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
                Icon(
                  Icons.account_balance_wallet,
                  size: 32,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sistema Financiero VentIQ',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        'Control integral de finanzas, costos y rentabilidad',
                        style: TextStyle(
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

  Widget _buildConfigurationCard() {
    if (_isLoading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              const Text('Verificando configuración...'),
            ],
          ),
        ),
      );
    }

    if (_isConfigured) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    color: AppColors.success,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Sistema Configurado',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'El sistema financiero está completamente configurado y listo para usar. Accede a la configuración detallada para gestionar categorías, centros de costo y márgenes comerciales.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pushNamed(context, '/financial-configuration'),
                  icon: const Icon(Icons.dashboard),
                  label: const Text('Ver Dashboard de Configuración'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.settings,
                  color: AppColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Configuración del Sistema',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Inicializa las configuraciones básicas del sistema financiero incluyendo categorías de gastos, tipos de costos, centros de costo y márgenes comerciales.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isInitializing ? null : _initializeFinancialSystem,
                icon: _isInitializing 
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(_isInitializing ? 'Configurando...' : 'Configurar Sistema Financiero'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _initializeFinancialSystem() async {
    setState(() => _isInitializing = true);
    
    try {
      await _financialService.initializeFinancialSystem();
      await _checkConfigurationStatus(); // Recheck status after initialization
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Sistema financiero configurado exitosamente'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error configurando sistema: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }

  Widget _buildQuickStats() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dashboard, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Resumen Rápido',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Contador de operaciones pendientes - destacado
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _pendingOperationsCount > 0 
                          ? Colors.orange.withOpacity(0.1)
                          : Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _pendingOperationsCount > 0 
                            ? Colors.orange
                            : Colors.green,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.pending_actions,
                          size: 32,
                          color: _pendingOperationsCount > 0 
                              ? Colors.orange
                              : Colors.green,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$_pendingOperationsCount',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: _pendingOperationsCount > 0 
                                ? Colors.orange
                                : Colors.green,
                          ),
                        ),
                        const Text(
                          'Operaciones\nPendientes',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (_pendingOperationsCount > 0) ...[
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const FinancialExpensesScreen(),
                                ),
                              ).then((_) => _loadData());
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            ),
                            child: const Text(
                              'Procesar',
                              style: TextStyle(fontSize: 12, color: Colors.white),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Actividades recientes
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.history, color: AppColors.primary),
                        const SizedBox(height: 8),
                        Text(
                          '${_recentActivities.length}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        const Text(
                          'Actividades\nRecientes',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
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
          'Módulos Financieros',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            // Responsive grid based on screen width
            int crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
            double childAspectRatio = constraints.maxWidth > 600 ? 1.2 : 1.1;
            
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: childAspectRatio,
              children: [
                _buildModuleCard(
                  'Dashboard',
                  'KPIs y métricas\nen tiempo real',
                  Icons.dashboard,
                  AppColors.primary,
                  () => Navigator.pushNamed(context, '/financial-dashboard'),
                ),
                _buildModuleCard(
                  'Reportes',
                  'Análisis y\nproyecciones',
                  Icons.analytics,
                  Colors.green,
                  () => Navigator.pushNamed(context, '/financial-reports'),
                ),
                _buildModuleCard(
                  'Gastos',
                  'Gestión de\ngastos operativos',
                  Icons.receipt_long,
                  Colors.orange,
                  () => Navigator.pushNamed(context, '/financial-expenses'),
                ),
                _buildModuleCard(
                  'Costos de Producción',
                  'Análisis de costos\nde platos elaborados',
                  Icons.restaurant_menu,
                  Colors.purple,
                  () => Navigator.pushNamed(context, '/restaurant-costs'),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildModuleCard(String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: color,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
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

  Widget _buildRecentActivity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Actividad Reciente',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: _recentActivities.map((activity) => _buildActivityItem(activity)).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildActivityItem(Map<String, dynamic> activity) {
    final tipoActividad = activity['tipo_actividad'] as String? ?? 'unknown';
    final descripcion = activity['descripcion'] as String? ?? 'Sin descripción';
    final fechaActividad = activity['fecha_actividad'] != null 
        ? DateTime.tryParse(activity['fecha_actividad']) ?? DateTime.now()
        : DateTime.now();
    final monto = activity['monto'];

    IconData icon;
    Color color;

    switch (tipoActividad) {
      case 'gasto_registrado':
        icon = Icons.add_circle;
        color = Colors.green;
        break;
      case 'gasto_eliminado':
        icon = Icons.remove_circle;
        color = Colors.red;
        break;
      case 'operacion_procesada':
        icon = Icons.check_circle;
        color = Colors.blue;
        break;
      default:
        icon = Icons.info;
        color = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  descripcion,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTimeAgo(fechaActividad),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          if (monto != null)
            Text(
              '\$${monto}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays} días';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} horas';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minutos';
    } else {
      return '${difference.inSeconds} segundos';
    }
  }

  Widget _buildPendingOperationsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.pending_actions,
                  color: AppColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Operaciones Pendientes',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Hay $_pendingOperationsCount operaciones pendientes de procesar.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/financial-pending-operations'),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Ver Operaciones Pendientes'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
