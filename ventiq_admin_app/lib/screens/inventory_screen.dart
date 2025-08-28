import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import 'inventory_reception_screen.dart';
import 'inventory_operations_screen.dart';
import '../models/inventory.dart';
import '../models/warehouse.dart';
import '../services/inventory_service.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<InventoryProduct> _inventoryProducts = [];
  List<InventoryItem> _inventoryItems = [];
  List<Warehouse> _warehouses = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String _selectedWarehouse = 'Todos';
  int? _selectedWarehouseId;
  String _selectedClassification = 'Todas';
  String _stockFilter = 'Todos';
  String _errorMessage = '';

  // Pagination and summary data
  int _currentPage = 1;
  bool _hasNextPage = false;
  InventorySummary? _inventorySummary;
  PaginationInfo? _paginationInfo;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _scrollController.addListener(_scrollListener);
    _loadInventoryData();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadNextPage();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _loadInventoryData({bool reset = true}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
        _currentPage = 1;
        _inventoryProducts.clear();
        _inventoryItems.clear();
      });
    }

    try {
      // Load warehouses first (only on initial load)
      if (reset) {
        final warehouses = await InventoryService.getWarehouses();
        setState(() {
          _warehouses = warehouses;
        });
      }

      // Load inventory products with pagination
      final response = await InventoryService.getInventoryProducts(
        idAlmacen: _selectedWarehouseId,
        busqueda: _searchQuery.isEmpty ? null : _searchQuery,
        mostrarSinStock: _stockFilter != 'Sin Stock',
        conStockMinimo: _stockFilter == 'Stock Bajo' ? true : null,
        pagina: _currentPage,
      );

      setState(() {
        if (reset) {
          _inventoryProducts = response.products;
        } else {
          _inventoryProducts.addAll(response.products);
        }
        _inventoryItems =
            _inventoryProducts.map((p) => p.toInventoryItem()).toList();
        _inventorySummary = response.summary;
        _paginationInfo = response.pagination;
        _hasNextPage = response.pagination?.tieneSiguiente ?? false;
        _isLoading = false;
        _isLoadingMore = false;
      });

      print(
        '✅ Loaded ${response.products.length} products (page $_currentPage)',
      );
      print(
        '📊 Summary: ${_inventorySummary?.totalInventario} total, ${_inventorySummary?.totalSinStock} sin stock',
      );
    } catch (e) {
      print('❌ Error loading inventory data: $e');
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _errorMessage = 'Error al cargar inventario: $e';
      });
    }
  }

  void _loadNextPage() async {
    if (_isLoadingMore || !_hasNextPage) return;

    setState(() {
      _isLoadingMore = true;
      _currentPage++;
    });

    _loadInventoryData(reset: false);
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
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadInventoryData,
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
            Tab(text: 'Stock', icon: Icon(Icons.inventory_2, size: 18)),
            Tab(text: 'Almacenes', icon: Icon(Icons.warehouse, size: 18)),
            Tab(text: 'Movimientos', icon: Icon(Icons.swap_horiz, size: 18)),
            Tab(text: 'ABC', icon: Icon(Icons.analytics, size: 18)),
          ],
        ),
      ),
      body:
          _isLoading
              ? _buildLoadingState()
              : _errorMessage.isNotEmpty
              ? _buildErrorState()
              : TabBarView(
                controller: _tabController,
                children: [
                  _buildStockTab(),
                  _buildWarehousesTab(),
                  _buildMovementsTab(),
                  _buildABCTab(),
                ],
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showInventoryReceptionDialog,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
        tooltip: 'Agregar Recepción de Inventario',
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: 16),
          Text(
            'Cargando inventario...',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: AppColors.error),
          const SizedBox(height: 16),
          Text(
            _errorMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadInventoryData,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _buildStockTab() {
    final filteredItems = _getFilteredInventoryItems();

    return Column(
      children: [
        _buildSearchAndFilters(),
        _buildInventorySummary(),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: filteredItems.length + (_isLoadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == filteredItems.length) {
                return _buildLoadingMoreIndicator();
              }
              return _buildInventoryCard(filteredItems[index]);
            },
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
    return const InventoryOperationsScreen();
  }

  Widget _buildABCTab() {
    return const Center(
      child: Text(
        'Clasificación ABC\n(Próximamente)',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary),
      ),
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
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (value) {
              setState(() => _searchQuery = value);
              // Debounce search
              Future.delayed(const Duration(milliseconds: 500), () {
                if (_searchQuery == value) {
                  _loadInventoryData();
                }
              });
            },
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
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String>(
                      value: 'Todos',
                      child: Text('Todos', style: TextStyle(fontSize: 14)),
                    ),
                    ..._warehouses.map(
                      (w) => DropdownMenuItem<String>(
                        value: w.name,
                        child: Text(
                          w.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedWarehouse = value!;
                      if (value == 'Todos') {
                        _selectedWarehouseId = null;
                      } else {
                        final warehouse = _warehouses.firstWhere(
                          (w) => w.name == value,
                        );
                        _selectedWarehouseId = int.tryParse(warehouse.id);
                      }
                    });
                    _loadInventoryData(); // Reload with new filter
                  },
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
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  isExpanded: true,
                  items:
                      ['Todos', 'Sin Stock', 'Stock Bajo', 'Stock OK'].map((
                        String value,
                      ) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(
                            value,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                        );
                      }).toList(),
                  onChanged: (value) {
                    setState(() => _stockFilter = value!);
                    // No need to reload data, just update the UI
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInventorySummary() {
    if (_inventorySummary == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.background,
      child: Column(
        children: [
          Row(
            children: [
              _buildSummaryCard(
                'Total Inventario',
                _inventorySummary!.totalInventario.toString(),
                AppColors.info,
              ),
              const SizedBox(width: 8),
              _buildSummaryCard(
                'Sin Stock',
                _inventorySummary!.totalSinStock.toString(),
                AppColors.error,
              ),
              const SizedBox(width: 8),
              _buildSummaryCard(
                'Stock Bajo',
                _inventorySummary!.totalConCantidadBaja.toString(),
                AppColors.warning,
              ),
            ],
          ),
          if (_paginationInfo != null) ...[
            const SizedBox(height: 8),
            Text(
              'Página ${_paginationInfo!.paginaActual} de ${_paginationInfo!.totalPaginas} • ${_paginationInfo!.totalRegistros} productos total',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadingMoreIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildStockSummary() {
    final totalItems = _inventoryProducts.length;
    final outOfStock =
        _inventoryProducts.where((item) => item.cantidadFinal <= 0).length;
    final lowStock =
        _inventoryProducts
            .where((item) => item.cantidadFinal > 0 && item.cantidadFinal <= 10)
            .length;

    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.background,
      child: Row(
        children: [
          _buildSummaryCard(
            'Total Items',
            totalItems.toString(),
            AppColors.info,
          ),
          const SizedBox(width: 8),
          _buildSummaryCard(
            'Sin Stock',
            outOfStock.toString(),
            AppColors.error,
          ),
          const SizedBox(width: 8),
          _buildSummaryCard(
            'Stock Bajo',
            lowStock.toString(),
            AppColors.warning,
          ),
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

  Widget _buildInventoryCard(InventoryProduct item) {
    final stockStatus = _getStockStatus(item.stockDisponible.toInt());

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
        title: Text(
          item.nombreProducto,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${item.variante} ${item.opcionVariante}'),
            Text('Almacén: ${item.almacen}'),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${item.stockDisponible}'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: stockStatus.color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                stockStatus.label,
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ],
        ),
        onTap: () => _showInventoryProductDetails(item),
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
        title: Text(
          warehouse.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(warehouse.address),
            Text('${warehouse.zones.length} zonas'),
          ],
        ),
        trailing: Icon(
          warehouse.isActive ? Icons.check_circle : Icons.cancel,
          color: warehouse.isActive ? AppColors.success : AppColors.error,
        ),
        onTap: () => _showWarehouseDetails(warehouse),
      ),
    );
  }

  List<InventoryProduct> _getFilteredInventoryItems() {
    List<InventoryProduct> filtered = List.from(_inventoryProducts);

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered =
          filtered.where((item) {
            return item.nombreProducto.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ) ||
                item.skuProducto.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                );
          }).toList();
    }

    // Apply warehouse filter
    if (_selectedWarehouse != 'Todos') {
      filtered =
          filtered.where((item) => item.almacen == _selectedWarehouse).toList();
    }

    // Apply stock filter based on stock_disponible field
    switch (_stockFilter) {
      case 'Sin Stock':
        filtered = filtered.where((item) => item.stockDisponible <= 0).toList();
        break;
      case 'Stock Bajo':
        filtered =
            filtered
                .where(
                  (item) =>
                      item.stockDisponible > 0 && item.stockDisponible < 10,
                )
                .toList();
        break;
      case 'Stock OK':
        filtered =
            filtered.where((item) => item.stockDisponible >= 10).toList();
        break;
      case 'Todos':
      default:
        // No stock filtering needed
        break;
    }

    return filtered;
  }

  ({Color color, String label}) _getStockStatus(int stock) {
    if (stock <= 0) {
      return (color: AppColors.error, label: 'Sin Stock');
    } else if (stock < 10) {
      return (color: AppColors.warning, label: 'Stock Bajo');
    } else {
      return (color: AppColors.success, label: 'Stock OK');
    }
  }

  void _showInventoryProductDetails(InventoryProduct item) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(item.nombreProducto),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Variante: ${item.variante} ${item.opcionVariante}'),
                Text('Almacén: ${item.almacen}'),
                Text('Stock Disponible: ${item.stockDisponible}'),
                if (item.precioVenta != null)
                  Text('Precio: \$${item.precioVenta!.toStringAsFixed(2)}'),
                Text('Categoría: ${item.categoria}'),
                Text('Subcategoría: ${item.subcategoria}'),
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

  void _showInventoryReceptionDialog() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) => InventoryReceptionScreen(),
            fullscreenDialog: true,
          ),
        )
        .then((_) {
          // Refresh inventory after reception
          _loadInventoryData();
        });
  }

  void _showWarehouseDetails(Warehouse warehouse) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
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
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/dashboard',
          (route) => false,
        );
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
