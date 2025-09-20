import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_colors.dart';
import '../services/financial_service.dart';
import '../services/user_preferences_service.dart';
import '../widgets/expense_category_tree_widget.dart';

class FinancialExpensesScreen extends StatefulWidget {
  const FinancialExpensesScreen({super.key});

  @override
  State<FinancialExpensesScreen> createState() => _FinancialExpensesScreenState();
}

class _FinancialExpensesScreenState extends State<FinancialExpensesScreen>
    with SingleTickerProviderStateMixin {
  final FinancialService _financialService = FinancialService();
  
  late TabController _tabController;
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _pendingOperations = [];
  List<Map<String, dynamic>> _categoriesHierarchy = [];
  List<Map<String, dynamic>> _costCenters = [];
  List<Map<String, dynamic>> _costTypes = []; // Agregar lista de tipos de costo
  bool _isLoading = true;
  String _selectedPeriod = 'month';
  Set<String> _selectedCategoryIds = <String>{};
  int _pendingOperationsCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        _loadDataForCurrentTab();
      }
    });
    _loadExpensesData();
    // Eliminar _loadPendingOperationsCount() - se carga cuando sea necesario
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDataForCurrentTab() async {
    if (_tabController.index == 0) {
      await _loadExpensesData();
    } else {
      await _loadPendingOperations();
    }
  }

  Future<void> _loadExpensesData() async {
    setState(() => _isLoading = true);
    
    try {
      print(' Cargando datos de gastos...');
      final userPrefs = UserPreferencesService();
      final storeId = await userPrefs.getIdTienda() ?? 1;
      print('  - Tienda ID: $storeId');
      
      final futures = await Future.wait([
        _financialService.getExpenseCategoriesHierarchy(),
        _financialService.getCostCenters(storeId: storeId),
        _financialService.getCostTypes(), // Agregar carga de tipos de costo
        _getExpensesByPeriod(),
      ]);

      final categoriesHierarchy = futures[0] as List<Map<String, dynamic>>;
      final costCenters = futures[1] as List<Map<String, dynamic>>;
      final costTypes = futures[2] as List<Map<String, dynamic>>;
      final expenses = futures[3] as List<Map<String, dynamic>>;

      print(' Datos cargados:');
      print('  - Categorías: ${categoriesHierarchy.length}');
      print('  - Centros de costo: ${costCenters.length}');
      print('  - Tipos de costo: ${costTypes.length}');
      print('  - Gastos: ${expenses.length}');

      setState(() {
        _categoriesHierarchy = categoriesHierarchy;
        _costCenters = costCenters;
        _costTypes = costTypes;
        _expenses = expenses;
        _isLoading = false;
      });
      
      // Actualizar conteo después de cargar gastos
      _loadPendingOperationsCount();
    } catch (e) {
      print(' Error loading expenses data: $e');
      setState(() {
        _categoriesHierarchy = [];
        _costCenters = [];
        _costTypes = [];
        _expenses = [];
        _isLoading = false;
      });
    }
  }

  Future<void> _loadPendingOperations() async {
    setState(() => _isLoading = true);
    
    try {
      print(' Cargando operaciones pendientes...');
      print('  - Período: ${_getPeriodStartDate()} a ${_getPeriodEndDate()}');
      print('  - Categorías seleccionadas: ${_selectedCategoryIds.length}');
      
      final operations = await _financialService.getPendingExpenseOperations(
        startDate: _getPeriodStartDate(),
        endDate: _getPeriodEndDate(),
        categoryIds: _selectedCategoryIds.isNotEmpty ? _selectedCategoryIds.toList() : null,
      );

      print(' Operaciones pendientes cargadas: ${operations.length}');
      for (final op in operations.take(3)) {
        print('  - ${op['tipo_operacion']}: ${op['descripcion']} (\$${op['monto']})');
      }

      setState(() {
          _pendingOperations = operations;
          _pendingOperationsCount = operations.length; // AGREGAR ESTA LÍNEA
          _isLoading = false;
});
      
      // Ya no necesitamos llamar _loadPendingOperationsCount() aquí
    } catch (e) {
      print(' Error loading pending operations: $e');
      setState(() {
        _pendingOperations = [];
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
      print(' Conteo de operaciones pendientes: $count');
    } catch (e) {
      print(' Error loading pending operations count: $e');
      setState(() {
        _pendingOperationsCount = 0;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _getExpensesByPeriod() async {
    try {
      final userPrefs = UserPreferencesService();
      final storeId = await userPrefs.getIdTienda() ?? 1;
      
      // Usar el nuevo método del FinancialService
      return await _financialService.getExpensesByPeriod(
        storeId: storeId,
        startDate: _getPeriodStartDate(),
        endDate: _getPeriodEndDate(),
        categoryIds: _selectedCategoryIds.isNotEmpty ? _selectedCategoryIds.toList() : null,
      );
    } catch (e) {
      print('Error getting expenses: $e');
      return [];
    }
  }

  String _getPeriodStartDate() {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case 'today':
        return DateTime(now.year, now.month, now.day).toIso8601String().split('T')[0];
      case 'week':
        return now.subtract(Duration(days: now.weekday - 1)).toIso8601String().split('T')[0];
      case 'month':
        return DateTime(now.year, now.month, 1).toIso8601String().split('T')[0];
      case 'quarter':
        final quarterStart = ((now.month - 1) ~/ 3) * 3 + 1;
        return DateTime(now.year, quarterStart, 1).toIso8601String().split('T')[0];
      default:
        return DateTime(now.year, now.month, 1).toIso8601String().split('T')[0];
    }
  }

  String _getPeriodEndDate() {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case 'today':
        return DateTime(now.year, now.month, now.day, 23, 59, 59).toIso8601String().split('T')[0];
      case 'week':
        return now.add(Duration(days: 7 - now.weekday)).toIso8601String().split('T')[0];
      case 'month':
        return DateTime(now.year, now.month + 1, 0).toIso8601String().split('T')[0];
      case 'quarter':
        final quarterEnd = ((now.month - 1) ~/ 3 + 1) * 3;
        return DateTime(now.year, quarterEnd + 1, 0).toIso8601String().split('T')[0];
      default:
        return now.toIso8601String().split('T')[0];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Gastos'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDataForCurrentTab,
            tooltip: 'Actualizar',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddExpenseDialog,
            tooltip: 'Agregar Gasto',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.list), text: 'Gastos'),
            Tab(icon: Icon(Icons.pending), text: 'Operaciones Pendientes'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _isLoading ? _buildLoadingState() : _buildExpensesView(),
          _isLoading ? _buildLoadingState() : _buildPendingOperationsView(),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.primary),
    );
  }

  Widget _buildExpensesView() {
    return Column(
      children: [
        _buildFiltersCard(),
        _buildSummaryCard(),
        Expanded(child: _buildExpensesList()),
      ],
    );
  }

  Widget _buildPendingOperationsView() {
    return Column(
      children: [
        _buildFiltersCard(),
        _buildSummaryCard(),
        Expanded(child: _buildPendingOperationsList()),
      ],
    );
  }

  Widget _buildFiltersCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                value: _selectedPeriod,
                decoration: const InputDecoration(
                  labelText: 'Período',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: const [
                  DropdownMenuItem(value: 'today', child: Text('Hoy')),
                  DropdownMenuItem(value: 'week', child: Text('Esta Semana')),
                  DropdownMenuItem(value: 'month', child: Text('Este Mes')),
                  DropdownMenuItem(value: 'quarter', child: Text('Trimestre')),
                ],
                onChanged: (value) {
                  setState(() => _selectedPeriod = value!);
                  _loadDataForCurrentTab();
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 1,
              child: ElevatedButton.icon(
                onPressed: _showCategoryFilterDialog,
                icon: const Icon(Icons.filter_list),
                label: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Filtrar'),
                    if (_selectedCategoryIds.isNotEmpty)
                      Text(
                        '(${_selectedCategoryIds.length})',
                        style: const TextStyle(fontSize: 10),
                      ),
                  ],
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedCategoryIds.isNotEmpty 
                      ? AppColors.primary 
                      : Colors.grey[300],
                  foregroundColor: _selectedCategoryIds.isNotEmpty 
                      ? Colors.white 
                      : Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCategoryFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filtrar por Categorías'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ExpenseCategoryTreeWidget(
            categories: _categoriesHierarchy,
            selectedIds: _selectedCategoryIds,
            onSelectionChanged: (selectedIds) {
              setState(() => _selectedCategoryIds = selectedIds);
            },
            title: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _selectedCategoryIds.clear());
              Navigator.pop(context);
              _loadDataForCurrentTab();
            },
            child: const Text('Limpiar Filtros'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _loadDataForCurrentTab();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    final totalExpenses = _expenses.fold<double>(
      0.0, 
      (sum, expense) => sum + ((expense['monto'] as num?)?.toDouble() ?? 0.0)
    );
    final totalPendingOperations = _pendingOperations.fold<double>(
      0.0, 
      (sum, operation) => sum + ((operation['monto'] as num?)?.toDouble() ?? 0.0)
    );

    final isExpensesTab = _tabController.index == 0;
    final currentTotal = isExpensesTab ? totalExpenses : totalPendingOperations;
    final itemCount = isExpensesTab ? _expenses.length : _pendingOperations.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primary.withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                isExpensesTab ? Icons.receipt_long : Icons.pending_actions,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isExpensesTab ? 'Total de Gastos' : 'Operaciones Pendientes',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\$${currentTotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '$itemCount ${isExpensesTab ? 'gastos registrados' : 'operaciones pendientes'}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    'Operaciones pendientes: $_pendingOperationsCount',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpensesList() {
    if (_expenses.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No hay gastos registrados',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Los gastos aparecerán aquí una vez registrados',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _expenses.length,
      itemBuilder: (context, index) {
        final expense = _expenses[index];
        return _buildExpenseItem(expense);
      },
    );
  }

  Widget _buildPendingOperationsList() {
    if (_pendingOperations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No hay operaciones pendientes registradas',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Las operaciones pendientes aparecerán aquí una vez registradas',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingOperations.length,
      itemBuilder: (context, index) {
        final operation = _pendingOperations[index];
        return _buildPendingOperationCard(operation);
      },
    );
  }

  Widget _buildExpenseItem(Map<String, dynamic> expense) {
    final amount = expense['monto'] as num? ?? 0.0;
    final category = expense['app_nom_subcategoria_gasto']?['denominacion'] ?? 'Sin categoría';
    final costCenter = expense['app_cont_centro_costo']?['denominacion'] ?? 'Sin centro';
    final date = expense['fecha'] ?? '';
    final costType = expense['app_cont_tipo_costo']?['denominacion'] ?? 'Sin tipo de costo';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.receipt_long,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Color(0xFF2D3748),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.business_center,
                            size: 14,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              costCenter,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.price_change,
                            size: 14,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              costType,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '\$${amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 14,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 6),
                  Text(
                    date,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingOperationCard(Map<String, dynamic> operation) {
    final amount = (operation['monto'] as num).toDouble();
    final description = operation['descripcion'] ?? 'Sin descripción';
    final date = operation['fecha_operacion'] ?? '';
    final tipoOperacion = operation['tipo_operacion'] ?? '';
    final isRecepcion = tipoOperacion == 'recepcion';
    final isEntregaEfectivo = tipoOperacion == 'entrega_efectivo';

    // Información adicional según el tipo
    String additionalInfo = '';
    if (isRecepcion) {
      additionalInfo = operation['proveedor'] ?? 'Sin proveedor';
    } else if (isEntregaEfectivo) {
      additionalInfo = operation['usuario'] ?? 'Usuario desconocido';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isRecepcion ? Colors.blue.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isRecepcion ? Colors.blue.withOpacity(0.3) : Colors.green.withOpacity(0.3)
                    ),
                  ),
                  child: Text(
                    isRecepcion ? 'RECEPCIÓN' : 'EFECTIVO',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isRecepcion ? Colors.blue : Colors.green,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Text(
                    '\$${amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              description,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  date,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                if (additionalInfo.isNotEmpty) ...[
                  const SizedBox(width: 16),
                  Icon(
                    isRecepcion ? Icons.local_shipping : Icons.person,
                    size: 16,
                    color: Colors.grey[600]
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      additionalInfo,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
            
            // Mostrar detalles específicos según el tipo de operación
            // Remover carga automática de detalles - solo mostrar cuando el usuario procese
            // if (isRecepcion && operation['original_data'] != null) 
            //   _buildReceptionDetails(operation['original_data']),
            
            // if (isEntregaEfectivo && operation['original_data'] != null)
            //   _buildCashWithdrawalDetails(operation['original_data']),
            
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _registerExpenseFromOperation(operation),
                    icon: const Icon(Icons.add_circle, size: 18),
                    label: const Text('Registrar Gasto'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _skipOperationExpense(operation),
                  icon: const Icon(Icons.skip_next, size: 18),
                  label: const Text('Omitir'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[300],
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceptionDetails(Map<String, dynamic> receptionData) {
    final products = receptionData['app_dat_recepcion_productos'] as List<dynamic>? ?? [];
    final receptionInfo = receptionData['app_dat_operacion_recepcion'] as Map<String, dynamic>? ?? {};
    
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2, size: 16, color: Colors.blue[700]),
              const SizedBox(width: 6),
              Text(
                'Detalles de la Recepción',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Información general
          if (receptionInfo['entregado_por'] != null) ...[
            _buildDetailRow('Proveedor:', receptionInfo['entregado_por']),
          ],
          if (receptionInfo['recibido_por'] != null) ...[
            _buildDetailRow('Recibido por:', receptionInfo['recibido_por']),
          ],
          if (receptionInfo['observaciones_compra'] != null) ...[
            _buildDetailRow('Observaciones:', receptionInfo['observaciones_compra']),
          ],
          
          const SizedBox(height: 8),
          Text(
            'Productos (${products.length}):',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.blue[700],
            ),
          ),
          const SizedBox(height: 4),
          
          // Lista de productos
          ...products.take(5).map((product) {
            final productData = product as Map<String, dynamic>;
            final productName = productData['app_dat_producto']?['denominacion'] ?? 'Producto';
            final cantidad = productData['cantidad'] ?? 0;
            final precioUnitario = (productData['precio_unitario'] as num?)?.toDouble() ?? 0.0;
            final descuento = (productData['descuento_monto'] as num?)?.toDouble() ?? 0.0;
            final bonificacion = productData['bonificacion_cantidad'] ?? 0;
            final costoReal = (productData['costo_real'] as num?)?.toDouble() ?? 0.0;
            
            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    productName,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        'Cant: $cantidad',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'P.Unit: \$${precioUnitario.toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                      if (descuento > 0) ...[
                        const SizedBox(width: 12),
                        Text(
                          'Desc: \$${descuento.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 11, color: Colors.orange),
                        ),
                      ],
                    ],
                  ),
                  if (bonificacion > 0 || costoReal > 0) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (bonificacion > 0) ...[
                          Text(
                            'Bonif: $bonificacion',
                            style: const TextStyle(fontSize: 11, color: Colors.green),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Text(
                          'Costo Real: \$${costoReal.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 11, 
                            color: Colors.blue[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
          
          if (products.length > 5) ...[
            const SizedBox(height: 4),
            Text(
              '... y ${products.length - 5} productos más',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCashWithdrawalDetails(Map<String, dynamic> withdrawalData) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.money_off, size: 16, color: Colors.green[700]),
              const SizedBox(width: 6),
              Text(
                'Detalles del Egreso de Efectivo',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.green[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          _buildDetailRow('Motivo:', withdrawalData['motivo_entrega'] ?? 'Sin especificar'),
          _buildDetailRow('Recibe:', withdrawalData['nombre_recibe'] ?? 'Sin especificar'),
          _buildDetailRow('Autoriza:', withdrawalData['nombre_autoriza'] ?? 'Sin especificar'),
          _buildDetailRow('Monto:', '\$${((withdrawalData['monto_entrega'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}'),
          
          if (withdrawalData['id_turno'] != null) ...[
            _buildDetailRow('Turno ID:', withdrawalData['id_turno'].toString()),
          ],
          if (withdrawalData['id_medio_pago'] != null) ...[
            _buildDetailRow('Medio de Pago ID:', withdrawalData['id_medio_pago'].toString()),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _registerExpenseFromOperation(Map<String, dynamic> operation) {
  final descriptionController = TextEditingController(text: operation['descripcion']);
  final amountController = TextEditingController(text: operation['monto'].toString());
  
  // Inicializar como null para que el usuario seleccione
  String? selectedCategory = operation['id_subcategoria_gasto']?.toString();
  String? selectedCostCenter = operation['id_centro_costo']?.toString();
  String? selectedCostType = operation['id_tipo_costo']?.toString();
  
  // Validar que los valores existan en las listas disponibles
  if (selectedCategory != null && !_categoriesHierarchy.any((cat) => 
      cat['children']?.any((sub) => sub['subcategory_id'].toString() == selectedCategory) ?? false)) {
    selectedCategory = null; // Reset si no existe
  }
  if (selectedCostCenter != null && !_costCenters.any((cc) => cc['id'].toString() == selectedCostCenter)) {
    selectedCostCenter = null; // Reset si no existe
  }
  if (selectedCostType != null && !_costTypes.any((ct) => ct['id'].toString() == selectedCostType)) {
    selectedCostType = null; // Reset si no existe
  }
  
  // Variables para el preview de asignaciones
  Map<String, dynamic>? assignmentsPreview;
  bool isLoadingPreview = false;
  
  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text('Registrar Gasto: ${operation['tipo_operacion']}'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
            maxWidth: MediaQuery.of(context).size.width * 0.9,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Información de la operación
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Información de la Operación:', 
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[700])),
                      const SizedBox(height: 8),
                      Text('Tipo: ${operation['tipo_operacion']}'),
                      Text('Fecha: ${operation['fecha_operacion']}'),
                      if (operation['proveedor'] != null)
                        Text('Proveedor: ${operation['proveedor']}'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Preview de asignaciones de costos
                if (assignmentsPreview != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (assignmentsPreview!['is_fully_assigned'] ?? false)
                        ? Colors.green.withOpacity(0.1) 
                        : Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: (assignmentsPreview!['is_fully_assigned'] ?? false)
                          ? Colors.green.withOpacity(0.3) 
                          : Colors.orange.withOpacity(0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              (assignmentsPreview!['is_fully_assigned'] ?? false)
                                ? Icons.check_circle 
                                : Icons.warning,
                              color: (assignmentsPreview!['is_fully_assigned'] ?? false)
                                ? Colors.green[700] 
                                : Colors.orange[700],
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Preview de Asignaciones de Costos',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: (assignmentsPreview!['is_fully_assigned'] ?? false)
                                  ? Colors.green[700] 
                                  : Colors.orange[700],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Monto del Gasto: \$${(assignmentsPreview!['expense_amount'] ?? 0.0).toStringAsFixed(2)}'),
                        Text('Total Asignado: \$${(assignmentsPreview!['total_assigned'] ?? 0.0).toStringAsFixed(2)}'),
                        Text(
                          (assignmentsPreview!['is_fully_assigned'] ?? false)
                            ? '✅ Completamente asignado' 
                            : '⚠️ Asignación parcial',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: (assignmentsPreview!['is_fully_assigned'] ?? false)
                              ? Colors.green[700] 
                              : Colors.orange[700],
                          ),
                        ),
                        const SizedBox(height: 12),
                        
                        // Lista de asignaciones
                        const Text('Detalle de Asignaciones:', 
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 8),
                        ...((assignmentsPreview!['assignments'] as List<dynamic>? ?? []).map((assignment) => 
                          Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.grey.withOpacity(0.2)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        (assignment as Map<String, dynamic>)['centro_costo_nombre'] ?? 'Desconocido',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                    ),
                                    Text(
                                      '\$${((assignment as Map<String, dynamic>)['monto_asignado'] ?? 0.0).toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold, 
                                        color: AppColors.primary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text('${(assignment as Map<String, dynamic>)['porcentaje_asignacion'] ?? 0}% • ${(assignment as Map<String, dynamic>)['metodo_asignacion_nombre'] ?? 'Desconocido'}',
                                  style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                                if ((assignment as Map<String, dynamic>)['is_auto_created'] == true)
                                  Container(
                                    margin: const EdgeInsets.only(top: 2),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: const Text(
                                      'Auto-creada',
                                      style: TextStyle(fontSize: 9, color: Colors.blue),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Campos del formulario
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  decoration: const InputDecoration(
                    labelText: 'Monto',
                    border: OutlineInputBorder(),
                    prefixText: '\$',
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  enabled: false, // No permitir editar el monto
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Categoría',
                    border: OutlineInputBorder(),
                  ),
                  items: _categoriesHierarchy
                      .expand((cat) => [
                            DropdownMenuItem(
                              value: cat['id'].toString(),
                              child: Text(
                                cat['name'] ?? '',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            ...(cat['children'] as List<Map<String, dynamic>>? ?? [])
                                .map((sub) => DropdownMenuItem(
                                      value: sub['subcategory_id'].toString(),
                                      child: Text(
                                        '  • ${sub['name'] ?? ''}',
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    )),
                        ])
                      .toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedCategory = value;
                      assignmentsPreview = null; // Reset preview
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedCostCenter,
                  decoration: const InputDecoration(
                    labelText: 'Centro de Costo',
                    border: OutlineInputBorder(),
                  ),
                  items: _costCenters.map((cc) => DropdownMenuItem(
                    value: cc['id'].toString(),
                    child: Text(
                      cc['denominacion'] ?? '',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: const TextStyle(fontSize: 14),
                    ),
                  )).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedCostCenter = value;
                      assignmentsPreview = null; // Reset preview
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedCostType,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de Costo',
                    border: OutlineInputBorder(),
                  ),
                  items: _costTypes.map((ct) => DropdownMenuItem(
                    value: ct['id'].toString(),
                    child: Text(
                      ct['denominacion'] ?? '',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: const TextStyle(fontSize: 14),
                    ),
                  )).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedCostType = value;
                      assignmentsPreview = null; // Reset preview
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Botón para generar preview
                if (selectedCostType != null && selectedCostCenter != null && amountController.text.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: isLoadingPreview ? null : () async {
                        setDialogState(() => isLoadingPreview = true);
                        
                        try {
                          final tempOperation = Map<String, dynamic>.from(operation);
                          tempOperation['monto'] = double.tryParse(amountController.text) ?? 0.0;
                          tempOperation['descripcion'] = descriptionController.text;

                          final preview = await _financialService.previewExpenseAssignments(
                            tempOperation,
                            subcategoryId: selectedCategory != null ? int.parse(selectedCategory!) : null,
                            costCenterId: int.parse(selectedCostCenter!),
                            costTypeId: int.parse(selectedCostType!),
                          );

                          setDialogState(() {
                            assignmentsPreview = preview;
                            isLoadingPreview = false;
                          });
                        } catch (e) {
                          setDialogState(() => isLoadingPreview = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error generando preview: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                      icon: isLoadingPreview 
                        ? const SizedBox(
                            width: 16, 
                            height: 16, 
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                          )
                        : const Icon(Icons.preview),
                      label: Text(isLoadingPreview ? 'Calculando...' : 'Ver Asignaciones de Costos'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (descriptionController.text.trim().isEmpty ||
                  amountController.text.trim().isEmpty ||
                  selectedCategory == null ||
                  selectedCostCenter == null ||
                  selectedCostType == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Todos los campos son obligatorios'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }

              try {
                // Validar que los valores se puedan parsear
                final subcategoryId = selectedCategory != null ? int.parse(selectedCategory!) : null;
                final costCenterId = int.parse(selectedCostCenter!);
                final costTypeId = int.parse(selectedCostType!);
                
                final success = await _financialService.registerExpenseFromOperation(
                  operation,
                  subcategoryId: subcategoryId,
                  costCenterId: costCenterId,
                  costTypeId: costTypeId,
                  customDescription: descriptionController.text.trim(),
                );

                Navigator.pop(context);
                
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Gasto registrado exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  _loadDataForCurrentTab();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Error al registrar el gasto'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error al registrar gasto: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Registrar'),
          ),
        ],
      ),
    ),
  );
}

  void _skipOperationExpense(Map<String, dynamic> operation) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Omitir Registro de Gasto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Por qué deseas omitir el registro de esta operación como gasto?'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Motivo (opcional)',
                border: OutlineInputBorder(),
                hintText: 'Ej: Ya registrado manualmente, no es deducible, etc.',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final success = await _financialService.skipExpenseFromOperation(
                  operation,
                  reasonController.text.trim().isEmpty 
                      ? 'Sin motivo especificado' 
                      : reasonController.text.trim(),
                );

                Navigator.pop(context);
                
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Operación omitida exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  _loadDataForCurrentTab();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Error al omitir la operación'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error al omitir operación: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Omitir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _deleteExpense(Map<String, dynamic> expense) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: Text('¿Estás seguro de que deseas eliminar este gasto?\n\nMonto: \$${expense['monto']}\nFecha: ${expense['fecha']}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final success = await _financialService.deleteExpense(expense['id']);
                
                Navigator.pop(context);
                
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Gasto eliminado exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  _loadDataForCurrentTab();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Error al eliminar el gasto'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _editExpense(Map<String, dynamic> expense) {
    // TODO: Implement edit expense functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Función de edición en desarrollo'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _deletePendingOperation(Map<String, dynamic> operation) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: Text('¿Estás seguro de que deseas eliminar esta operación pendiente?\n\n"${operation['descripcion']}"'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await Supabase.instance.client
                    .from('app_cont_operaciones_pendientes')
                    .delete()
                    .eq('id', operation['id']);
                
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Operación pendiente eliminada exitosamente'),
                    backgroundColor: Colors.green,
                  ),
                );
                _loadDataForCurrentTab();
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error al eliminar operación pendiente: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _editPendingOperation(Map<String, dynamic> operation) {
    // TODO: Implement edit pending operation functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Función de edición en desarrollo'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _showAddExpenseDialog() {
    final descriptionController = TextEditingController();
    final amountController = TextEditingController();
    String? selectedCategory;
    String? selectedCostCenter;
    String? selectedCostType;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Agregar Gasto'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Descripción',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    decoration: const InputDecoration(
                      labelText: 'Monto',
                      border: OutlineInputBorder(),
                      prefixText: '\$',
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'Categoría',
                      border: OutlineInputBorder(),
                    ),
                    items: _categoriesHierarchy
                        .expand((cat) => [
                              DropdownMenuItem(
                                value: cat['id'].toString(),
                                child: Text(
                                  cat['name'] ?? '',
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              ...(cat['children'] as List<Map<String, dynamic>>? ?? [])
                                  .map((sub) => DropdownMenuItem(
                                        value: sub['subcategory_id'].toString(),
                                        child: Text(
                                          '  • ${sub['name'] ?? ''}',
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      )),
                          ])
                        .toList(),
                    onChanged: (value) => setDialogState(() => selectedCategory = value),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedCostCenter,
                    decoration: const InputDecoration(
                      labelText: 'Centro de Costo',
                      border: OutlineInputBorder(),
                    ),
                    items: _costCenters.map((cc) => DropdownMenuItem(
                      value: cc['id'].toString(),
                      child: Text(
                        cc['denominacion'] ?? '',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: const TextStyle(fontSize: 14),
                      ),
                    )).toList(),
                    onChanged: (value) => setDialogState(() => selectedCostCenter = value),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedCostType,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de Costo',
                      border: OutlineInputBorder(),
                    ),
                    items: _costTypes.map((ct) => DropdownMenuItem(
                      value: ct['id'].toString(),
                      child: Text(
                        ct['denominacion'] ?? '',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: const TextStyle(fontSize: 14),
                      ),
                    )).toList(),
                    onChanged: (value) => setDialogState(() => selectedCostType = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (descriptionController.text.trim().isEmpty ||
                    amountController.text.trim().isEmpty ||
                    selectedCategory == null ||
                    selectedCostCenter == null ||
                    selectedCostType == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Todos los campos son obligatorios'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                try {
                  final userPrefs = UserPreferencesService();
                  final storeId = await userPrefs.getIdTienda() ?? 1;
                  final userId = Supabase.instance.client.auth.currentUser?.id;
                  
                  await Supabase.instance.client.from('app_cont_gastos').insert({
                    'monto': double.parse(amountController.text.trim()),
                    'id_subcategoria_gasto': int.tryParse(selectedCategory!) ?? 1,
                    'id_centro_costo': int.tryParse(selectedCostCenter!) ?? 1,
                    'id_tipo_costo': int.tryParse(selectedCostType!) ?? 1,
                    'id_tienda': storeId,
                    'uuid': userId,
                    'fecha': DateTime.now().toIso8601String().split('T')[0],
                    // Campos de tracking para gastos manuales
                    'tipo_origen': 'manual',
                    'origen_operacion': null, // No hay operación origen para gastos manuales
                    'id_referencia_origen': null, // No hay referencia para gastos manuales
                  });

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Gasto agregado exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  _loadDataForCurrentTab();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error al agregar gasto: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshAllData() async {
    await _loadPendingOperationsCount();
    await _loadDataForCurrentTab();
  }

  Future<void> _onOperationProcessed() async {
    // Refrescar datos después de procesar una operación
    await _refreshAllData();
    
    // Mostrar mensaje de confirmación
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Operación procesada correctamente'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}
