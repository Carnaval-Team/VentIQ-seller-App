import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/financial_service.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import 'expense_categories_management_screen.dart';
import 'cost_types_management_screen.dart';
import 'cost_centers_management_screen.dart';
import 'profit_margins_management_screen.dart';
import 'cost_assignments_management_screen.dart';
import 'financial_configuration_screen.dart';

class FinancialSetupScreen extends StatefulWidget {
  const FinancialSetupScreen({super.key});

  @override
  State<FinancialSetupScreen> createState() => _FinancialSetupScreenState();
}

class _FinancialSetupScreenState extends State<FinancialSetupScreen> {
  final FinancialService _financialService = FinancialService();
  bool _isLoading = false;
  bool _isInitialized = false;
  
  List<Map<String, dynamic>> _expenseCategories = [];
  List<Map<String, dynamic>> _costCenters = [];
  List<Map<String, dynamic>> _costTypes = [];
  Map<String, dynamic> _configStats = {};

  @override
  void initState() {
    super.initState();
    _checkInitializationStatus();
  }

  Future<void> _checkInitializationStatus() async {
    setState(() => _isLoading = true);
    
    try {
      // Verificar si ya existen configuraciones usando el nuevo método
      final isConfigured = await _financialService.isSystemConfigured();
      
      if (isConfigured) {
        // Obtener datos y estadísticas
        final categories = await _financialService.getExpenseCategories();
        final centers = await _financialService.getCostCenters();
        final types = await _financialService.getCostTypes();
        final stats = await _financialService.getConfigurationStats();
        
        setState(() {
          _expenseCategories = categories;
          _costCenters = centers;
          _costTypes = types;
          _configStats = stats;
          _isInitialized = true;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isInitialized = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackBar('Error verificando configuración: $e');
    }
  }

  Future<void> _initializeFinancialSystem() async {
    setState(() => _isLoading = true);
    
    try {
      await _financialService.initializeFinancialSystem();
      await _checkInitializationStatus();
      
      _showSuccessSnackBar('Sistema financiero inicializado correctamente');
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackBar('Error inicializando sistema: $e');
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 4),
      ),
    );
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
            onPressed: _checkInitializationStatus,
            tooltip: 'Actualizar',
          ),
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              tooltip: 'Menú',
            ),
          ),
        ],
      ),
      body: _isLoading ? _buildLoadingState() : _buildContent(),
      endDrawer: const AdminDrawer(),
      bottomNavigationBar: AdminBottomNavigation(
        currentIndex: 3,
        onTap: _onBottomNavTap,
      ),
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
            'Configurando sistema financiero...',
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
          _buildStatusCard(),
          const SizedBox(height: 20),
          if (!_isInitialized) _buildInitializationSection(),
          if (_isInitialized) ...[
            _buildConfigurationSections(),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _isInitialized ? AppColors.success.withOpacity(0.1) : AppColors.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isInitialized ? AppColors.success : AppColors.warning,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Icon(
            _isInitialized ? Icons.check_circle : Icons.warning,
            size: 48,
            color: _isInitialized ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(height: 12),
          Text(
            _isInitialized ? 'Sistema Financiero Configurado' : 'Sistema Financiero No Configurado',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _isInitialized ? AppColors.success : AppColors.warning,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isInitialized 
              ? 'El sistema financiero está listo para usar. Las operaciones se registrarán automáticamente como gastos.'
              : 'Necesitas inicializar el sistema financiero para comenzar a registrar gastos automáticamente.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitializationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Inicialización del Sistema',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'La inicialización creará automáticamente:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              _buildInitializationItem(
                Icons.category,
                'Categorías de Gastos Estándar',
                'Compras, Operativos, Administrativos, Servicios, etc.',
              ),
              _buildInitializationItem(
                Icons.account_balance,
                'Centros de Costo',
                'Basados en tus tiendas y almacenes actuales',
              ),
              _buildInitializationItem(
                Icons.analytics,
                'Tipos de Costo',
                'Directos, Indirectos, Administrativos, Financieros',
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _initializeFinancialSystem,
                  icon: const Icon(Icons.rocket_launch),
                  label: const Text('Inicializar Sistema Financiero'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInitializationItem(IconData icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigurationSections() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Dashboard de Configuración',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        
        // Estadísticas generales
        _buildStatsGrid(),
        const SizedBox(height: 20),
        
        // Accesos rápidos a CRUDs
        _buildQuickAccessGrid(),
        const SizedBox(height: 20),
        
        // Información detallada
        _buildDetailedInfo(),
      ],
    );
  }

  Widget _buildStatsGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Siempre 2 columnas, pero ajustar aspect ratio según el ancho
        final childAspectRatio = constraints.maxWidth > 600 ? 2.8 : 1.3;
        
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: constraints.maxWidth > 600 ? 12 : 8,
          mainAxisSpacing: constraints.maxWidth > 600 ? 12 : 8,
          childAspectRatio: childAspectRatio,
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
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
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
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAccessGrid() {
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
            // Siempre 2 columnas, pero ajustar aspect ratio según el ancho
            final childAspectRatio = constraints.maxWidth > 600 ? 2.8 : 2.2;
            
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: constraints.maxWidth > 600 ? 12 : 8,
              mainAxisSpacing: constraints.maxWidth > 600 ? 12 : 8,
              childAspectRatio: childAspectRatio,
              children: [
                _buildQuickAccessCard(
                  'Categorías de Gastos',
                  Icons.category,
                  AppColors.primary,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ExpenseCategoriesManagementScreen()),
                  ),
                ),
                _buildQuickAccessCard(
                  'Tipos de Costos',
                  Icons.analytics,
                  AppColors.info,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const CostTypesManagementScreen()),
                  ),
                ),
                _buildQuickAccessCard(
                  'Centros de Costo',
                  Icons.account_balance,
                  AppColors.success,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const CostCentersManagementScreen()),
                  ),
                ),
                _buildQuickAccessCard(
                  'Márgenes Comerciales',
                  Icons.trending_up,
                  Colors.orange,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ProfitMarginsManagementScreen()),
                  ),
                ),
                _buildQuickAccessCard(
                  'Asignaciones de Costos',
                  Icons.assignment,
                  AppColors.warning,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const CostAssignmentsManagementScreen()),
                  ),
                ),
                _buildQuickAccessCard(
                  'Configuración General',
                  Icons.settings,
                  Colors.grey,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const FinancialConfigurationScreen()),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildQuickAccessCard(String title, IconData icon, Color color, VoidCallback onTap) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
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
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailedInfo() {
    final avgMargin = _configStats['avg_margin'] ?? 0.0;
    final minMargin = _configStats['min_margin'] ?? 0.0;
    final maxMargin = _configStats['max_margin'] ?? 0.0;
    
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
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              _buildMarginInfo('Margen Promedio', '${avgMargin.toStringAsFixed(1)}%', Colors.blue),
              const SizedBox(height: 12),
              _buildMarginInfo('Margen Más Alto', '${maxMargin.toStringAsFixed(1)}%', Colors.green),
              const SizedBox(height: 12),
              _buildMarginInfo('Margen Más Bajo', '${minMargin.toStringAsFixed(1)}%', Colors.orange),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildIntegrationStatus(),
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

  Widget _buildIntegrationStatus() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.info.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.info),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.integration_instructions, color: AppColors.info, size: 24),
              const SizedBox(width: 12),
              const Text(
                'Integración Automática Activa',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '✅ Las recepciones de inventario se registran automáticamente como gastos\n'
            '✅ Los gastos se asignan automáticamente a centros de costo\n'
            '✅ Los costos se categorizan según el tipo de operación',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  void _onBottomNavTap(int index) {
    switch (index) {
      case 0: // Dashboard
        Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
        break;
      case 1: // Productos
        Navigator.pushNamed(context, '/products');
        break;
      case 2: // Inventario
        Navigator.pushNamed(context, '/inventory');
        break;
      case 3: // Configuración
        Navigator.pushNamed(context, '/settings');
        break;
    }
  }
}
