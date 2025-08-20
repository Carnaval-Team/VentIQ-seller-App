import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import '../models/inventory.dart';
import '../models/warehouse.dart';
import '../services/mock_data_service.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<InventoryItem> _inventoryItems = [];
  List<Warehouse> _warehouses = [];
  bool _isLoading = true;
  String _selectedWarehouse = 'Todos';
  String _selectedClassification = 'Todas';
  String _stockFilter = 'Todos';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadInventoryData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _loadInventoryData() {
    setState(() {
      _isLoading = true;
    });
    
    Future.delayed(const Duration(milliseconds: 800), () {
      setState(() {
        _inventoryItems = MockDataService.getMockInventory();
        _warehouses = MockDataService.getMockWarehouses();
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
          'Control de Inventario',
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
            onPressed: _showAddInventoryDialog,
            tooltip: 'Agregar Item',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadInventoryData,
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
            Tab(text: 'Stock', icon: Icon(Icons.inventory_2, size: 18)),
            Tab(text: 'Almacenes', icon: Icon(Icons.warehouse, size: 18)),
            Tab(text: 'Movimientos', icon: Icon(Icons.swap_horiz, size: 18)),
            Tab(text: 'ABC', icon: Icon(Icons.analytics, size: 18)),
          ],
        ),
      ),
      body: _isLoading ? _buildLoadingState() : TabBarView(
        controller: _tabController,
        children: [
          _buildStockTab(),
          _buildWarehousesTab(),
          _buildMovementsTab(),
          _buildABCTab(),
        ],
      ),
      endDrawer: const AdminDrawer(),
      bottomNavigationBar: AdminBottomNavigation(
        currentIndex: 2,
        onTap: _onBottomNavTap,
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.primary),
    );
  }

  Widget _buildStockTab() {
    final filteredItems = _getFilteredInventoryItems();
    
    return Column(
      children: [
        _buildSearchAndFilters(),
        _buildStockSummary(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filteredItems.length,
            itemBuilder: (context, index) => _buildInventoryCard(filteredItems[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildWarehousesTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _warehouses.length,
      itemBuilder: (context, index) => _buildWarehouseCard(_warehouses[index]),
    );
  }

  Widget _buildMovementsTab() {
    return const Center(
      child: Text('Movimientos de Inventario\n(Próximamente)', 
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary)),
    );
  }

  Widget _buildABCTab() {
    return const Center(
      child: Text('Clasificación ABC\n(Próximamente)', 
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary)),
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar productos...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 1,
                child: DropdownButtonFormField<String>(
                  value: _selectedWarehouse,
                  decoration: const InputDecoration(
                    labelText: 'Almacén',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  isExpanded: true,
                  items: ['Todos', ..._warehouses.map((w) => w.name)].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value, 
                      child: Text(
                        value,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) => setState(() => _selectedWarehouse = value!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: DropdownButtonFormField<String>(
                  value: _stockFilter,
                  decoration: const InputDecoration(
                    labelText: 'Stock',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  isExpanded: true,
                  items: ['Todos', 'Sin Stock', 'Stock Bajo', 'Stock OK'].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value, 
                      child: Text(
                        value,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) => setState(() => _stockFilter = value!),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStockSummary() {
    final totalItems = _inventoryItems.length;
    final outOfStock = _inventoryItems.where((item) => item.currentStock <= 0).length;
    final lowStock = _inventoryItems.where((item) => item.currentStock > 0 && item.currentStock <= item.minStock).length;
    
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.background,
      child: Row(
        children: [
          _buildSummaryCard('Total Items', totalItems.toString(), AppColors.info),
          const SizedBox(width: 8),
          _buildSummaryCard('Sin Stock', outOfStock.toString(), AppColors.error),
          const SizedBox(width: 8),
          _buildSummaryCard('Stock Bajo', lowStock.toString(), AppColors.warning),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              child: Text(
                value, 
                style: TextStyle(
                  fontSize: 18, 
                  fontWeight: FontWeight.bold, 
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(
                title, 
                style: const TextStyle(
                  fontSize: 11, 
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryCard(InventoryItem item) {
    final stockStatus = _getStockStatus(item);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: stockStatus.color.withOpacity(0.1),
          child: Icon(Icons.inventory_2, color: stockStatus.color),
        ),
        title: Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SKU: ${item.sku}'),
            Text('Almacén: ${item.warehouseName}'),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${item.currentStock}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: stockStatus.color)),
            Text(stockStatus.label, style: TextStyle(fontSize: 12, color: stockStatus.color)),
          ],
        ),
        onTap: () => _showInventoryDetails(item),
      ),
    );
  }

  Widget _buildWarehouseCard(Warehouse warehouse) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: AppColors.primary,
          child: Icon(Icons.warehouse, color: Colors.white),
        ),
        title: Text(warehouse.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(warehouse.address),
            Text('${warehouse.zones.length} zonas'),
          ],
        ),
        trailing: Icon(warehouse.isActive ? Icons.check_circle : Icons.cancel, 
          color: warehouse.isActive ? AppColors.success : AppColors.error),
        onTap: () => _showWarehouseDetails(warehouse),
      ),
    );
  }

  List<InventoryItem> _getFilteredInventoryItems() {
    return _inventoryItems.where((item) {
      final matchesSearch = _searchQuery.isEmpty || 
        item.productName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        item.sku.toLowerCase().contains(_searchQuery.toLowerCase());
      
      final matchesWarehouse = _selectedWarehouse == 'Todos' || item.warehouseName == _selectedWarehouse;
      
      final matchesStock = _stockFilter == 'Todos' ||
        (_stockFilter == 'Sin Stock' && item.currentStock <= 0) ||
        (_stockFilter == 'Stock Bajo' && item.currentStock > 0 && item.currentStock <= item.minStock) ||
        (_stockFilter == 'Stock OK' && item.currentStock > item.minStock);
      
      return matchesSearch && matchesWarehouse && matchesStock;
    }).toList();
  }

  ({Color color, String label}) _getStockStatus(InventoryItem item) {
    if (item.currentStock <= 0) {
      return (color: AppColors.error, label: 'Sin Stock');
    } else if (item.currentStock <= item.minStock) {
      return (color: AppColors.warning, label: 'Stock Bajo');
    } else {
      return (color: AppColors.success, label: 'Stock OK');
    }
  }

  void _showAddInventoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar Item'),
        content: const Text('Funcionalidad de agregar item\n(Por implementar)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showInventoryDetails(InventoryItem item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.productName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SKU: ${item.sku}'),
            Text('Stock Actual: ${item.currentStock}'),
            Text('Stock Mínimo: ${item.minStock}'),
            Text('Almacén: ${item.warehouseName}'),
            Text('Ubicación: ${item.location}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showWarehouseDetails(Warehouse warehouse) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(warehouse.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dirección: ${warehouse.address}'),
            Text('Tipo: ${warehouse.type}'),
            Text('Zonas: ${warehouse.zones.length}'),
            Text('Estado: ${warehouse.isActive ? "Activo" : "Inactivo"}'),
          ],
        ),
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
      case 2: // Inventario (current)
        break;
      case 3: // Configuración
        Navigator.pushNamed(context, '/settings');
        break;
    }
  }
}
