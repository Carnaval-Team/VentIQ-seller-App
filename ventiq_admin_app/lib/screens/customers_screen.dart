import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import '../models/customer.dart';
import '../services/customer_service.dart';
import '../utils/navigation_guard.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Customer> _customers = [];
  bool _isLoading = true;
  String _selectedSegment = 'Todos';
  String _sortBy = 'Nombre';
  List<Customer> _filteredCustomers = [];
  String _errorMessage = '';

  bool _canManageCustomers = false;
  @override
  void initState() {
    super.initState();
    _loadPermissions();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
        _applyFilters();
      });
    });
    _tabController = TabController(length: 3, vsync: this);
    _loadCustomersData();
  }

  Future<void> _loadPermissions() async {
    final permissions = await Future.wait([
      NavigationGuard.canPerformAction('customer.create'),
      NavigationGuard.canPerformAction('customer.edit'),
      NavigationGuard.canPerformAction('customer.delete'),
    ]);

    if (!mounted) return;
    setState(() {
      _canManageCustomers = permissions.any((p) => p);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomersData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final customers = await CustomerService.getAllCustomers(
        activeOnly: true,
        includeMetrics: true,
      );

      setState(() {
        _customers = customers;
        _filteredCustomers = customers;
        _isLoading = false;
      });
      _applyFilters();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error al cargar clientes: $e';
      });
    }
  }

  void _applyFilters() {
    List<Customer> filtered = List.from(_customers);

    // Filtrar por búsqueda
    if (_searchQuery.isNotEmpty) {
      filtered =
          filtered.where((customer) {
            return customer.nombreCompleto.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ) ||
                customer.codigoCliente.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ) ||
                (customer.email?.toLowerCase().contains(
                      _searchQuery.toLowerCase(),
                    ) ??
                    false);
          }).toList();
    }

    // Filtrar por segmento
    if (_selectedSegment != 'Todos') {
      filtered =
          filtered.where((customer) {
            switch (_selectedSegment) {
              case 'VIP':
                return customer.isVIP;
              case 'Corporativo':
                return customer.isCorporativo;
              case 'Regular':
                return customer.tipoCliente == 1;
              default:
                return true;
            }
          }).toList();
    }

    setState(() {
      _filteredCustomers = filtered;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'CRM Clientes',
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
          if (_canManageCustomers)
            IconButton(
              icon: const Icon(Icons.add, color: Colors.white),
              onPressed: _showAddCustomerDialog,
              tooltip: 'Agregar Cliente',
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadCustomersData,
            tooltip: 'Actualizar',
          ),
          Builder(
            builder:
                (context) => IconButton(
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
            Tab(text: 'Clientes', icon: Icon(Icons.people, size: 18)),
            Tab(
              text: 'Fidelización',
              icon: Icon(Icons.card_giftcard, size: 18),
            ),
            Tab(text: 'Segmentación', icon: Icon(Icons.analytics, size: 18)),
          ],
        ),
      ),
      body:
          _isLoading
              ? _buildLoadingState()
              : TabBarView(
                controller: _tabController,
                children: [
                  _buildCustomersTab(),
                  _buildLoyaltyTab(),
                  _buildSegmentationTab(),
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: 16),
          Text(
            'Cargando clientes...',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomersTab() {
    // Usar _filteredCustomers que ya se calcula en _applyFilters()
    if (_filteredCustomers.isEmpty &&
        _searchQuery.isEmpty &&
        _selectedSegment == 'Todos') {
      _applyFilters(); // Aplicar filtros iniciales si no se han aplicado
    }
    final filteredCustomers = _filteredCustomers;

    return Column(
      children: [
        _buildSearchAndFilters(),
        Expanded(
          child:
              filteredCustomers.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredCustomers.length,
                    itemBuilder: (context, index) {
                      final customer = filteredCustomers[index];
                      return _buildCustomerCard(customer);
                    },
                  ),
        ),
      ],
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar por nombre, email o teléfono...',
              prefixIcon: const Icon(Icons.search, color: AppColors.primary),
              suffixIcon:
                  _searchQuery.isNotEmpty
                      ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                      : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedSegment,
                  decoration: InputDecoration(
                    labelText: 'Segmento',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items:
                      ['Todos', 'VIP', 'Premium', 'Regular', 'Nuevo'].map((
                        segment,
                      ) {
                        return DropdownMenuItem(
                          value: segment,
                          child: Text(segment),
                        );
                      }).toList(),
                  onChanged:
                      (value) => setState(() => _selectedSegment = value!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _sortBy,
                  decoration: InputDecoration(
                    labelText: 'Ordenar por',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items:
                      ['Nombre', 'Fecha registro', 'Compras', 'Puntos'].map((
                        sort,
                      ) {
                        return DropdownMenuItem(value: sort, child: Text(sort));
                      }).toList(),
                  onChanged: (value) => setState(() => _sortBy = value!),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerCard(Customer customer) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showCustomerDetails(customer),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                child: Text(
                  customer.nombreCompleto.isNotEmpty
                      ? customer.nombreCompleto.substring(0, 1).toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.nombreCompleto,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (customer.email != null && customer.email!.isNotEmpty)
                      Text(
                        customer.email!,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.phone, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          customer.telefono ?? 'Sin teléfono',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.star, size: 14, color: Colors.orange[600]),
                        const SizedBox(width: 4),
                        Text(
                          '${customer.puntosAcumulados} puntos',
                          style: TextStyle(
                            color: Colors.orange[600],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '\$${customer.totalCompras.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getSegmentColor(
                        customer.tipoClienteDisplay,
                      ).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      customer.tipoClienteDisplay,
                      style: TextStyle(
                        color: _getSegmentColor(customer.tipoClienteDisplay),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    customer.nivelFidelidadDisplay,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: AppColors.textSecondary),
          SizedBox(height: 16),
          Text(
            'No se encontraron clientes',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          SizedBox(height: 8),
          Text(
            'Intenta ajustar los filtros de búsqueda',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Color _getSegmentColor(String segment) {
    switch (segment) {
      case 'VIP':
      case 'Corporativo':
        return Colors.purple;
      case 'Premium':
        return Colors.orange;
      case 'Regular':
        return AppColors.primary;
      case 'Nuevo':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  void _showCustomerDetails(Customer customer) {
    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.9,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: AppColors.primary.withOpacity(0.1),
                        child: Text(
                          customer.nombreCompleto.isNotEmpty
                              ? customer.nombreCompleto
                                  .substring(0, 1)
                                  .toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customer.nombreCompleto,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (customer.email != null &&
                                customer.email!.isNotEmpty)
                              Text(
                                customer.email!,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            if (customer.telefono != null &&
                                customer.telefono!.isNotEmpty)
                              Text(
                                customer.telefono!,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoCard(
                          'Puntos',
                          '${customer.puntosAcumulados}',
                          Icons.stars,
                          Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildInfoCard(
                          'Compras',
                          '\$${customer.totalCompras.toStringAsFixed(2)}',
                          Icons.shopping_bag,
                          AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoCard(
                          'Tipo',
                          customer.tipoClienteDisplay,
                          Icons.category,
                          _getSegmentColor(customer.tipoClienteDisplay),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildInfoCard(
                          'Registro',
                          '${customer.fechaRegistro.day}/${customer.fechaRegistro.month}/${customer.fechaRegistro.year}',
                          Icons.calendar_today,
                          Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoCard(
                          'Nivel',
                          customer.nivelFidelidadDisplay,
                          Icons.star,
                          Colors.amber,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildInfoCard(
                          'Código',
                          customer.codigoCliente,
                          Icons.qr_code,
                          Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (_canManageCustomers)
                        ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.edit),
                          label: const Text('Editar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                        label: const Text('Cerrar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildInfoCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  void _showAddCustomerDialog() {
    if (!_canManageCustomers) {
      NavigationGuard.showActionDeniedMessage(context, 'Agregar cliente');
      return;
    }
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Agregar Cliente'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre completo',
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono',
                    prefixIcon: Icon(Icons.phone),
                  ),
                  keyboardType: TextInputType.phone,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (nameController.text.isNotEmpty &&
                      emailController.text.isNotEmpty) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Cliente agregado exitosamente'),
                      ),
                    );
                  }
                },
                child: const Text('Agregar'),
              ),
            ],
          ),
    );
  }

  Widget _buildLoyaltyTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Programa de Fidelización',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildLoyaltyCard(
                  'Clientes VIP',
                  '${_customers.where((c) => c.isVIP).length}',
                  Icons.star,
                  Colors.purple,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildLoyaltyCard(
                  'Puntos Totales',
                  '${_customers.fold<int>(0, (sum, c) => sum + c.puntosAcumulados)}',
                  Icons.stars,
                  Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildLoyaltyCard(
                  'Canjes Mes',
                  '89', // Esto podría calcularse desde las ventas
                  Icons.redeem,
                  AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildLoyaltyCard(
                  'Nuevos Miembros',
                  '${_customers.where((c) => DateTime.now().difference(c.fechaRegistro).inDays <= 30).length}',
                  Icons.person_add,
                  Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Top Clientes por Puntos',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  ...(_customers.isNotEmpty
                      ? _customers
                          .take(5)
                          .map(
                            (customer) => ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primary.withOpacity(
                                  0.1,
                                ),
                                child: Text(
                                  customer.nombreCompleto.isNotEmpty
                                      ? customer.nombreCompleto.substring(0, 1)
                                      : '?',
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              title: Text(customer.nombreCompleto),
                              trailing: Text(
                                '${customer.puntosAcumulados} pts',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                          .toList()
                      : [const Text('No hay clientes disponibles')]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoyaltyCard(
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
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(
              title,
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentationTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Segmentación de Clientes',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildSegmentCard('VIP', '24', Colors.purple, '15%'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSegmentCard('Premium', '45', Colors.orange, '28%'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSegmentCard(
                  'Regular',
                  '78',
                  AppColors.primary,
                  '49%',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSegmentCard('Nuevo', '12', Colors.green, '8%'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Análisis de Comportamiento',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  _buildBehaviorItem(
                    'Frecuencia de Compra',
                    'Semanal: 32% | Mensual: 45% | Ocasional: 23%',
                  ),
                  _buildBehaviorItem(
                    'Ticket Promedio',
                    '\$45.50 (↑12% vs mes anterior)',
                  ),
                  _buildBehaviorItem(
                    'Productos Favoritos',
                    'Electrónicos: 35% | Ropa: 28% | Hogar: 22%',
                  ),
                  _buildBehaviorItem(
                    'Canal Preferido',
                    'Tienda física: 65% | Online: 35%',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentCard(
    String segment,
    String count,
    Color color,
    String percentage,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.people, color: color),
            ),
            const SizedBox(height: 8),
            Text(
              count,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(segment, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text(percentage, style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildBehaviorItem(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.analytics, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onBottomNavTap(int index) {
    switch (index) {
      case 0: // Dashboard
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/dashboard',
          (route) => false,
        );
        break;
      case 1: // Productos
        Navigator.pushNamed(context, '/products-dashboard');
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
