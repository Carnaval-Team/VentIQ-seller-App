import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import '../models/store.dart';
import '../models/system_parameter.dart';
import '../models/integration.dart';
import '../services/mock_data_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  List<Store> _stores = [];
  List<SystemParameter> _parameters = [];
  List<Integration> _integrations = [];
  bool _isLoading = true;

  // Filtros y búsqueda
  String _searchQuery = '';
  String _selectedCategory = 'Todos';
  String _selectedType = 'Todos';
  String _selectedStatus = 'Todos';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _loadData() {
    setState(() => _isLoading = true);
    
    // Simular carga de datos
    Future.delayed(const Duration(milliseconds: 800), () {
      setState(() {
        _stores = MockDataService.getMockStores();
        _parameters = MockDataService.getMockSystemParameters();
        _integrations = MockDataService.getMockIntegrations();
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
          'Configuración',
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
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Tiendas', icon: Icon(Icons.store)),
            Tab(text: 'Parámetros', icon: Icon(Icons.settings)),
            Tab(text: 'Integraciones', icon: Icon(Icons.integration_instructions)),
          ],
        ),
      ),
      body: _isLoading
          ? _buildLoadingState()
          : TabBarView(
              controller: _tabController,
              children: [
                _buildStoresTab(),
                _buildParametersTab(),
                _buildIntegrationsTab(),
              ],
            ),
      endDrawer: const AdminDrawer(),
      bottomNavigationBar: AdminBottomNavigation(
        currentIndex: 3,
        onTap: _onBottomNavTap,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
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
          Text('Cargando configuración...', style: TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildStoresTab() {
    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _stores.length,
            itemBuilder: (context, index) {
              final store = _stores[index];
              return _buildStoreCard(store);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildParametersTab() {
    final filteredParams = _parameters.where((param) {
      final matchesSearch = _searchQuery.isEmpty ||
          param.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          param.description.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesCategory = _selectedCategory == 'Todos' || param.category == _selectedCategory.toLowerCase();
      return matchesSearch && matchesCategory;
    }).toList();

    return Column(
      children: [
        _buildParameterFilters(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filteredParams.length,
            itemBuilder: (context, index) {
              final param = filteredParams[index];
              return _buildParameterCard(param);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildIntegrationsTab() {
    final filteredIntegrations = _integrations.where((integration) {
      final matchesSearch = _searchQuery.isEmpty ||
          integration.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          integration.description.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesType = _selectedType == 'Todos' || integration.type == _selectedType.toLowerCase();
      final matchesStatus = _selectedStatus == 'Todos' || integration.status == _selectedStatus.toLowerCase();
      return matchesSearch && matchesType && matchesStatus;
    }).toList();

    return Column(
      children: [
        _buildIntegrationFilters(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filteredIntegrations.length,
            itemBuilder: (context, index) {
              final integration = filteredIntegrations[index];
              return _buildIntegrationCard(integration);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Buscar tiendas...',
          prefixIcon: const Icon(Icons.search, color: AppColors.primary),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onChanged: (value) => setState(() => _searchQuery = value),
      ),
    );
  }

  Widget _buildStoreCard(Store store) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: store.isActive ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
          child: Icon(
            Icons.store,
            color: store.isActive ? Colors.green : Colors.red,
          ),
        ),
        title: Text(store.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(store.address),
            Text('Manager: ${store.manager}', style: const TextStyle(fontSize: 12)),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: store.isActive ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                store.isActive ? 'Activa' : 'Inactiva',
                style: TextStyle(
                  color: store.isActive ? Colors.green : Colors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        onTap: () => _showStoreDetails(store),
      ),
    );
  }

  void _showStoreDetails(Store store) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(store.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Dirección: ${store.address}'),
              Text('Teléfono: ${store.phone}'),
              Text('Email: ${store.email}'),
              Text('Manager: ${store.manager}'),
              Text('Moneda: ${store.currency}'),
              Text('RUT: ${store.taxId}'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  void _showAddDialog() {
    final currentTab = _tabController.index;
    switch (currentTab) {
      case 0:
        _showAddStoreDialog();
        break;
      case 1:
        _showAddParameterDialog();
        break;
      case 2:
        _showAddIntegrationDialog();
        break;
    }
  }

  void _showAddStoreDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar Tienda'),
        content: const Text('Funcionalidad por implementar'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  void _showAddParameterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar Parámetro'),
        content: const Text('Funcionalidad por implementar'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  void _showAddIntegrationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar Integración'),
        content: const Text('Funcionalidad por implementar'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Widget _buildParameterFilters() {
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
              hintText: 'Buscar parámetros...',
              prefixIcon: const Icon(Icons.search, color: AppColors.primary),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedCategory,
            decoration: InputDecoration(
              labelText: 'Categoría',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            items: ['Todos', 'General', 'Fiscal', 'Inventario', 'Sistema', 'Seguridad'].map((cat) {
              return DropdownMenuItem(value: cat, child: Text(cat));
            }).toList(),
            onChanged: (value) => setState(() => _selectedCategory = value!),
          ),
        ],
      ),
    );
  }

  Widget _buildParameterCard(SystemParameter param) {
    Color categoryColor = _getCategoryColor(param.category);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: categoryColor.withOpacity(0.1),
          child: Icon(_getCategoryIcon(param.category), color: categoryColor),
        ),
        title: Text(param.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(param.description),
            Text('Valor: ${param.value}', style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: param.isEditable ? Colors.blue.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                param.isEditable ? 'Editable' : 'Solo lectura',
                style: TextStyle(
                  color: param.isEditable ? Colors.blue : Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        onTap: () => _showParameterDetails(param),
      ),
    );
  }

  Widget _buildIntegrationFilters() {
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
              hintText: 'Buscar integraciones...',
              prefixIcon: const Icon(Icons.search, color: AppColors.primary),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedType,
                  decoration: InputDecoration(
                    labelText: 'Tipo',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: ['Todos', 'Payment', 'Shipping', 'Accounting', 'CRM', 'Inventory'].map((type) {
                    return DropdownMenuItem(value: type, child: Text(type));
                  }).toList(),
                  onChanged: (value) => setState(() => _selectedType = value!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedStatus,
                  decoration: InputDecoration(
                    labelText: 'Estado',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: ['Todos', 'Connected', 'Disconnected', 'Error', 'Pending'].map((status) {
                    return DropdownMenuItem(value: status, child: Text(status));
                  }).toList(),
                  onChanged: (value) => setState(() => _selectedStatus = value!),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIntegrationCard(Integration integration) {
    Color statusColor = _getStatusColor(integration.status);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.1),
          child: Icon(_getIntegrationIcon(integration.type), color: statusColor),
        ),
        title: Text(integration.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(integration.description),
            Text('Provider: ${integration.provider}', style: const TextStyle(fontSize: 12)),
            if (integration.lastSync != null)
              Text('Última sync: ${_formatDate(integration.lastSync!)}', style: const TextStyle(fontSize: 12)),
          ],
        ),
        trailing: SizedBox(
          width: 100,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  integration.status.toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: integration.isActive,
                  onChanged: (value) => _toggleIntegration(integration, value),
                  activeColor: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
        onTap: () => _showIntegrationDetails(integration),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'general': return Colors.blue;
      case 'fiscal': return Colors.green;
      case 'inventory': return Colors.orange;
      case 'system': return Colors.purple;
      case 'security': return Colors.red;
      default: return Colors.grey;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'general': return Icons.settings;
      case 'fiscal': return Icons.receipt;
      case 'inventory': return Icons.inventory;
      case 'system': return Icons.computer;
      case 'security': return Icons.security;
      default: return Icons.settings;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'connected': return Colors.green;
      case 'disconnected': return Colors.grey;
      case 'error': return Colors.red;
      case 'pending': return Colors.orange;
      default: return Colors.grey;
    }
  }

  IconData _getIntegrationIcon(String type) {
    switch (type.toLowerCase()) {
      case 'payment': return Icons.payment;
      case 'shipping': return Icons.local_shipping;
      case 'accounting': return Icons.account_balance;
      case 'crm': return Icons.people;
      case 'inventory': return Icons.inventory_2;
      default: return Icons.integration_instructions;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inMinutes < 60) {
      return 'Hace ${difference.inMinutes} min';
    } else if (difference.inHours < 24) {
      return 'Hace ${difference.inHours} h';
    } else {
      return 'Hace ${difference.inDays} días';
    }
  }

  void _showParameterDetails(SystemParameter param) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(param.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Descripción: ${param.description}'),
              Text('Clave: ${param.key}'),
              Text('Valor actual: ${param.value}'),
              Text('Tipo: ${param.type}'),
              Text('Categoría: ${param.category}'),
              Text('Editable: ${param.isEditable ? "Sí" : "No"}'),
              Text('Requerido: ${param.isRequired ? "Sí" : "No"}'),
              if (param.validationRule != null)
                Text('Validación: ${param.validationRule}'),
            ],
          ),
        ),
        actions: [
          if (param.isEditable)
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Editar'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showIntegrationDetails(Integration integration) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(integration.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Descripción: ${integration.description}'),
              Text('Proveedor: ${integration.provider}'),
              Text('Tipo: ${integration.type}'),
              Text('Estado: ${integration.status}'),
              Text('Activa: ${integration.isActive ? "Sí" : "No"}'),
              Text('Configurada: ${integration.isConfigured ? "Sí" : "No"}'),
              if (integration.lastSync != null)
                Text('Última sincronización: ${integration.lastSync}'),
              if (integration.lastError != null)
                Text('Último error: ${integration.lastError}', 
                     style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Configurar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _toggleIntegration(Integration integration, bool value) {
    setState(() {
      // Aquí se actualizaría el estado en la base de datos
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${integration.name} ${value ? "activada" : "desactivada"}'),
        ),
      );
    });
  }

  void _onBottomNavTap(int index) {
    switch (index) {
      case 0:
        Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
        break;
      case 1:
        Navigator.pushNamed(context, '/products');
        break;
      case 2:
        Navigator.pushNamed(context, '/inventory');
        break;
      case 3:
        break;
    }
  }
}
