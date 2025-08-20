import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import '../models/financial.dart';
import '../services/mock_sales_service.dart';

class FinancialScreen extends StatefulWidget {
  const FinancialScreen({super.key});

  @override
  State<FinancialScreen> createState() => _FinancialScreenState();
}

class _FinancialScreenState extends State<FinancialScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  List<Expense> _expenses = [];
  List<CostCenter> _costCenters = [];
  bool _isLoading = true;
  String _selectedPeriod = 'Este Mes';
  String _selectedCostCenter = 'Todos';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadFinancialData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadFinancialData() {
    setState(() => _isLoading = true);
    
    Future.delayed(const Duration(milliseconds: 800), () {
      setState(() {
        _expenses = MockSalesService.getMockExpenses();
        _costCenters = MockSalesService.getMockCostCenters();
        _isLoading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Gestión Financiera',
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
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: _showAddExpenseDialog,
            tooltip: 'Agregar Gasto',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadFinancialData,
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
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Gastos', icon: Icon(Icons.receipt_long, size: 18)),
            Tab(text: 'Centros Costo', icon: Icon(Icons.account_balance, size: 18)),
            Tab(text: 'Reportes', icon: Icon(Icons.analytics, size: 18)),
          ],
        ),
      ),
      body: _isLoading ? _buildLoadingState() : TabBarView(
        controller: _tabController,
        children: [
          _buildExpensesTab(),
          _buildCostCentersTab(),
          _buildReportsTab(),
        ],
      ),
      endDrawer: const AdminDrawer(),
      bottomNavigationBar: AdminBottomNavigation(
        currentIndex: 3,
        onTap: _onBottomNavTap,
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.primary),
    );
  }

  Widget _buildExpensesTab() {
    return Column(
      children: [
        _buildExpenseFilters(),
        _buildExpenseSummary(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _expenses.length,
            itemBuilder: (context, index) => _buildExpenseCard(_expenses[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildCostCentersTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _costCenters.length,
      itemBuilder: (context, index) => _buildCostCenterCard(_costCenters[index]),
    );
  }

  Widget _buildReportsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildFinancialMetrics(),
          const SizedBox(height: 20),
          _buildExpenseChart(),
          const SizedBox(height: 20),
          _buildBudgetAnalysis(),
        ],
      ),
    );
  }

  Widget _buildExpenseFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _selectedPeriod,
              decoration: const InputDecoration(
                labelText: 'Período',
                border: OutlineInputBorder(),
              ),
              items: ['Este Mes', 'Últimos 3 Meses', 'Este Año'].map((String value) {
                return DropdownMenuItem<String>(value: value, child: Text(value));
              }).toList(),
              onChanged: (value) => setState(() => _selectedPeriod = value!),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _selectedCostCenter,
              decoration: const InputDecoration(
                labelText: 'Centro de Costo',
                border: OutlineInputBorder(),
              ),
              items: ['Todos', ..._costCenters.map((c) => c.name)].map((String value) {
                return DropdownMenuItem<String>(value: value, child: Text(value));
              }).toList(),
              onChanged: (value) => setState(() => _selectedCostCenter = value!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseSummary() {
    final totalExpenses = _expenses.fold(0.0, (sum, expense) => sum + expense.amount);
    final monthlyExpenses = _expenses.where((e) => e.expenseDate.month == DateTime.now().month)
        .fold(0.0, (sum, expense) => sum + expense.amount);
    
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.background,
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.error.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.trending_down, color: AppColors.error, size: 32),
                  const SizedBox(height: 8),
                  Text('\$${totalExpenses.toStringAsFixed(2)}', 
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.error)),
                  const Text('Total Gastos', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.calendar_month, color: AppColors.warning, size: 32),
                  const SizedBox(height: 8),
                  Text('\$${monthlyExpenses.toStringAsFixed(2)}', 
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.warning)),
                  const Text('Este Mes', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseCard(Expense expense) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.error.withOpacity(0.1),
          child: const Icon(Icons.receipt_long, color: AppColors.error),
        ),
        title: Text(expense.description, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${expense.category} • ${expense.costCenter}'),
            Text('${expense.expenseDate.day}/${expense.expenseDate.month}/${expense.expenseDate.year}'),
          ],
        ),
        trailing: Text('\$${expense.amount.toStringAsFixed(2)}', 
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.error)),
      ),
    );
  }

  Widget _buildCostCenterCard(CostCenter costCenter) {
    final centerExpenses = _expenses.where((e) => e.costCenter == costCenter.name)
        .fold(0.0, (sum, expense) => sum + expense.amount);
    final budgetUsed = centerExpenses / costCenter.budget * 100;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(costCenter.name, 
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: costCenter.isActive ? AppColors.success.withOpacity(0.1) : AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(costCenter.isActive ? 'Activo' : 'Inactivo',
                    style: TextStyle(fontSize: 12, color: costCenter.isActive ? AppColors.success : AppColors.error)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(costCenter.description, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Presupuesto: \$${costCenter.budget.toStringAsFixed(2)}'),
                      Text('Gastado: \$${centerExpenses.toStringAsFixed(2)}'),
                      Text('Usado: ${budgetUsed.toStringAsFixed(1)}%'),
                    ],
                  ),
                ),
                SizedBox(
                  width: 60,
                  height: 60,
                  child: CircularProgressIndicator(
                    value: budgetUsed / 100,
                    backgroundColor: AppColors.border,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      budgetUsed > 90 ? AppColors.error : 
                      budgetUsed > 70 ? AppColors.warning : AppColors.success,
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

  Widget _buildFinancialMetrics() {
    final totalBudget = _costCenters.fold(0.0, (sum, center) => sum + center.budget);
    final totalSpent = _expenses.fold(0.0, (sum, expense) => sum + expense.amount);
    final remaining = totalBudget - totalSpent;
    
    return Row(
      children: [
        Expanded(child: _buildMetricCard('Presupuesto Total', '\$${totalBudget.toStringAsFixed(2)}', AppColors.info)),
        const SizedBox(width: 8),
        Expanded(child: _buildMetricCard('Gastado', '\$${totalSpent.toStringAsFixed(2)}', AppColors.error)),
        const SizedBox(width: 8),
        Expanded(child: _buildMetricCard('Disponible', '\$${remaining.toStringAsFixed(2)}', AppColors.success)),
      ],
    );
  }

  Widget _buildMetricCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          Text(title, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildExpenseChart() {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Gastos por Categoría', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Expanded(
            child: PieChart(
              PieChartData(
                sections: [
                  PieChartSectionData(value: 40, color: AppColors.primary, title: 'Operaciones'),
                  PieChartSectionData(value: 25, color: AppColors.success, title: 'Marketing'),
                  PieChartSectionData(value: 20, color: AppColors.warning, title: 'Personal'),
                  PieChartSectionData(value: 15, color: AppColors.error, title: 'Otros'),
                ],
                centerSpaceRadius: 40,
                sectionsSpace: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetAnalysis() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Análisis Presupuestario', 
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          ...List.generate(4, (index) => ListTile(
            leading: CircleAvatar(
              backgroundColor: [AppColors.success, AppColors.warning, AppColors.error, AppColors.info][index].withOpacity(0.1),
              child: Icon([Icons.trending_up, Icons.trending_flat, Icons.trending_down, Icons.analytics][index], 
                color: [AppColors.success, AppColors.warning, AppColors.error, AppColors.info][index]),
            ),
            title: Text(['Centro ${index + 1}', 'Centro ${index + 2}', 'Centro ${index + 3}', 'Centro ${index + 4}'][index]),
            subtitle: Text('${90 - index * 15}% del presupuesto usado'),
            trailing: Text('${(index + 1) * 500}\$', style: const TextStyle(fontWeight: FontWeight.bold)),
          )),
        ],
      ),
    );
  }

  void _showAddExpenseDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar Gasto'),
        content: const Text('Funcionalidad de agregar gasto\n(Por implementar)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
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
