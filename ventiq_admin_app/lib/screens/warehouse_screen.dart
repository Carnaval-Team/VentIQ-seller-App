import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import '../models/warehouse.dart';
import '../services/warehouse_service.dart';
import 'warehouse_detail_screen.dart';

class WarehouseScreen extends StatefulWidget {
  const WarehouseScreen({super.key});

  @override
  State<WarehouseScreen> createState() => _WarehouseScreenState();
}

class _WarehouseScreenState extends State<WarehouseScreen> {
  final _service = WarehouseService();
  List<Warehouse> _warehouses = [];
  String _search = '';
  String _direccionFilter = '';
  bool _loading = true;
  DateTime? _lastSearchAt;
  
  // Pagination variables
  WarehousePagination? _pagination;
  int _currentPage = 1;
  final int _itemsPerPage = 10;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool isRefresh = true}) async {
    print('🔄 _loadData iniciado - isRefresh: $isRefresh');
    
    if (isRefresh) {
      setState(() {
        _loading = true;
        _currentPage = 1;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    
    try {
      print('📦 Cargando stores...');
      // Load stores for filter
      final stores = await _service.listStores();
      print('📦 Stores cargados: ${stores.length}');
      
      print('🏭 Cargando almacenes con paginación...');
      print('  - Filtro denominación: ${_search.isNotEmpty ? _search : 'null'}');
      print('  - Filtro dirección: ${_direccionFilter.isNotEmpty ? _direccionFilter : 'null'}');
      print('  - Filtro tienda: null (sin filtro)');
      print('  - Página: ${isRefresh ? 1 : _currentPage}');
      print('  - Por página: $_itemsPerPage');
      
      // Load warehouses with pagination
      final response = await _service.listWarehousesWithPagination(
        denominacionFilter: _search.isNotEmpty ? _search : null,
        direccionFilter: _direccionFilter.isNotEmpty ? _direccionFilter : null,
        tiendaFilter: null, // Sin filtro de tienda
        pagina: isRefresh ? 1 : _currentPage,
        porPagina: _itemsPerPage,
      );
      
      print('✅ Respuesta recibida:');
      print('  - Almacenes: ${response.almacenes.length}');
      print('  - Paginación: ${response.paginacion.paginaActual}/${response.paginacion.totalPaginas}');
      print('  - Total almacenes: ${response.paginacion.totalAlmacenes}');
      
      setState(() {
        // Ya no necesitamos stores para filtros
        
        if (isRefresh) {
          _warehouses = response.almacenes;
          _currentPage = 1;
          print('🔄 Lista de almacenes actualizada (refresh): ${_warehouses.length}');
        } else {
          _warehouses.addAll(response.almacenes);
          print('➕ Almacenes agregados: ${response.almacenes.length}, Total: ${_warehouses.length}');
        }
        
        _pagination = response.paginacion;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      print('❌ Error loading warehouses: $e');
      print('📍 Stack trace: ${StackTrace.current}');
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar almacenes: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _loadMoreData() async {
    if (_pagination != null && _pagination!.tieneSiguiente && !_loadingMore) {
      _currentPage++;
      await _loadData(isRefresh: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Gestión de Almacenes',
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
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _loadData(isRefresh: true),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFilters(),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Almacenes',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _onAddWarehouse,
                          icon: const Icon(Icons.add),
                          label: const Text('Agregar almacén'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _warehouses.isEmpty
                          ? const Center(
                              child: Text(
                                'No hay almacenes',
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            )
                          : Column(
                              children: [
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: _warehouses.length + (_pagination?.tieneSiguiente == true ? 1 : 0),
                                    itemBuilder: (context, index) {
                                      if (index == _warehouses.length) {
                                        // Load more button
                                        return Padding(
                                          padding: const EdgeInsets.all(16.0),
                                          child: _loadingMore
                                              ? const Center(child: CircularProgressIndicator())
                                              : ElevatedButton(
                                                  onPressed: _loadMoreData,
                                                  child: const Text('Cargar más'),
                                                ),
                                        );
                                      }
                                      
                                      final w = _warehouses[index];
                                      return _WarehouseCard(
                                        warehouse: w,
                                        onEdit: () => _onEditWarehouse(w),
                                        onView: () => _onViewWarehouse(w),
                                      );
                                    },
                                  ),
                                ),
                                if (_pagination != null) _buildPaginationInfo(),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
      endDrawer: const AdminDrawer(),
      bottomNavigationBar: AdminBottomNavigation(
        currentRoute: '/warehouse',
        onTap: _onBottomNavTap,
      ),
    );
  }

  void _onBottomNavTap(int index) {
    // El AdminBottomNavigation ya maneja la navegación automáticamente
    // Esta función se mantiene por compatibilidad pero no es necesaria
    // ya que AdminBottomNavigation usa _handleTap internamente
  }

  Widget _buildFilters() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Buscar por nombre',
              prefixIcon: Icon(Icons.search, color: AppColors.primary),
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: (v) async {
              _search = v;
              final now = DateTime.now();
              _lastSearchAt = now;
              await Future.delayed(const Duration(milliseconds: 500));
              if (_lastSearchAt == now) {
                await _loadData(isRefresh: true);
              }
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Buscar por dirección',
              prefixIcon: Icon(Icons.location_on, color: AppColors.primary),
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: (v) async {
              _direccionFilter = v;
              final now = DateTime.now();
              _lastSearchAt = now;
              await Future.delayed(const Duration(milliseconds: 500));
              if (_lastSearchAt == now) {
                await _loadData(isRefresh: true);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPaginationInfo() {
    if (_pagination == null) return const SizedBox.shrink();
    
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Página ${_pagination!.paginaActual} de ${_pagination!.totalPaginas}',
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            '${_pagination!.totalAlmacenes} almacenes total',
            style: const TextStyle(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  void _onAddWarehouse() async {
    final result = await Navigator.pushNamed(context, '/add-warehouse');
    if (result == true) {
      // Refresh the list if warehouse was created successfully
      await _loadData(isRefresh: true);
    }
  }

  void _onEditWarehouse(Warehouse w) {
    // Placeholder: in future, open edit modal
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Editar: ${w.name} (pendiente)')),
    );
  }

  Future<void> _onViewWarehouse(Warehouse w) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WarehouseDetailScreen(warehouseId: w.id),
      ),
    );
    _loadData();
  }
}

class _WarehouseCard extends StatelessWidget {
  final Warehouse warehouse;
  final VoidCallback onEdit;
  final VoidCallback onView;

  const _WarehouseCard({
    required this.warehouse,
    required this.onEdit,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onView,
        borderRadius: BorderRadius.circular(12),
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
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.warehouse,
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
                          warehouse.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                warehouse.address,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: onView,
                        icon: const Icon(Icons.visibility_outlined),
                        tooltip: 'Ver detalle',
                        color: AppColors.primary,
                        iconSize: 20,
                      ),
                      IconButton(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Editar',
                        color: AppColors.textSecondary,
                        iconSize: 20,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _compactBadge(Icons.layers_outlined, '${warehouse.zones.length}', 'Layouts'),
                  const SizedBox(width: 12),
                  _compactBadge(Icons.inventory_outlined, '${warehouse.limitesStockCount}', 'Límites'),
                  const SizedBox(width: 12),
                  _statusBadge(warehouse.type),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compactBadge(IconData icon, String count, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          count,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _statusBadge(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
