import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import '../widgets/admin_card.dart';
import '../models/warehouse.dart';
import '../models/store.dart';
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
  List<Store> _stores = [];
  String _selectedStore = 'all';
  String _search = '';
  bool _loading = true;
  DateTime? _lastSearchAt;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final stores = await _service.listStores();
    final data = await _service.listWarehouses(storeId: _selectedStore, search: _search);
    setState(() {
      _stores = [
        Store(
          id: 'all',
          name: 'Todas las tiendas',
          address: '',
          phone: '',
          email: '',
          manager: '',
          isActive: true,
          timezone: '',
          businessHours: const {},
          latitude: 0.0,
          longitude: 0.0,
          currency: 'CLP',
          taxId: '',
          createdAt: DateTime.now(),
        ),
        ...stores,
      ];
      _warehouses = data;
      _loading = false;
    });
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
              onRefresh: _loadData,
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
                          : ListView.builder(
                              itemCount: _warehouses.length,
                              itemBuilder: (context, index) {
                                final w = _warehouses[index];
                                return _WarehouseCard(
                                  warehouse: w,
                                  onEdit: () => _onEditWarehouse(w),
                                  onView: () => _onViewWarehouse(w),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
      endDrawer: const AdminDrawer(),
      bottomNavigationBar: AdminBottomNavigation(
        currentIndex: 2,
        onTap: _onBottomNavTap,
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

  Widget _buildFilters() {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<String>(
            value: _stores.any((s) => s.id == _selectedStore) ? _selectedStore : null,
            decoration: const InputDecoration(
              labelText: 'Tienda',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: (_stores.isEmpty
                    ? [
                        Store(
                          id: 'all',
                          name: 'Todas las tiendas',
                          address: '',
                          phone: '',
                          email: '',
                          manager: '',
                          isActive: true,
                          timezone: '',
                          businessHours: const {},
                          latitude: 0.0,
                          longitude: 0.0,
                          currency: 'CLP',
                          taxId: '',
                          createdAt: DateTime.now(),
                        )
                      ]
                    : _stores)
                .map((s) => DropdownMenuItem<String>(
                      value: s.id,
                      child: Text(s.name),
                    ))
                .toList(),
            onChanged: (v) async {
              setState(() => _selectedStore = v ?? 'all');
              await _loadData();
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Buscar almacén',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) async {
              _search = v;
              final now = DateTime.now();
              _lastSearchAt = now;
              await Future.delayed(const Duration(milliseconds: 250));
              if (_lastSearchAt == now) {
                await _loadData();
              }
            },
          ),
        ),
      ],
    );
  }

  void _onAddWarehouse() {
    // Placeholder: in future, open modal to create warehouse
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Acción: Agregar almacén (pendiente)')),
    );
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
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('📦', style: TextStyle(fontSize: 24)),
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
                    const SizedBox(height: 4),
                    Text(
                      warehouse.address,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _badge(Icons.layers, '${warehouse.zones.length} layouts'),
                        _badge(Icons.category, 'ABC mixto'),
                        _badge(Icons.check_circle, warehouse.type),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  TextButton(onPressed: onEdit, child: const Text('EDITAR')),
                  const SizedBox(height: 4),
                  ElevatedButton(onPressed: onView, child: const Text('VER DETALLE')),
                ],
              )
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
