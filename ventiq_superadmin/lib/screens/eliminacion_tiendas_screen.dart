import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/deletion_items.dart';
import '../services/deletion_service.dart';
import '../widgets/app_drawer.dart';

class EliminacionTiendasScreen extends StatefulWidget {
  const EliminacionTiendasScreen({super.key});

  @override
  State<EliminacionTiendasScreen> createState() =>
      _EliminacionTiendasScreenState();
}

class _EliminacionTiendasScreenState extends State<EliminacionTiendasScreen> {
  final TextEditingController _searchCarnavalCtrl = TextEditingController();
  final TextEditingController _searchInventtiaCtrl = TextEditingController();

  static const int _pageSize = 25;
  int _pageCarnaval = 0;
  int _pageInventtia = 0;

  List<CarnavalProviderDeletionItem> _carnaval = [];
  List<CarnavalProviderDeletionItem> _carnavalFiltered = [];
  List<InventtiaStoreDeletionItem> _inventtia = [];
  List<InventtiaStoreDeletionItem> _inventtiaFiltered = [];

  bool _loadingCarnaval = true;
  bool _loadingInventtia = true;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loadingCarnaval = true;
      _loadingInventtia = true;
    });
    final provs = await DeletionService.getCarnavalProviders(
      page: _pageCarnaval,
      pageSize: _pageSize,
    );
    final stores = await DeletionService.getInventtiaStores(
      page: _pageInventtia,
      pageSize: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _carnaval = provs;
      _carnavalFiltered = provs;
      _inventtia = stores;
      _inventtiaFiltered = stores;
      _loadingCarnaval = false;
      _loadingInventtia = false;
    });
  }

  void _filterCarnaval(String query) {
    setState(() {
      _carnavalFiltered =
          _carnaval
              .where((e) => e.name.toLowerCase().contains(query.toLowerCase()))
              .toList();
    });
  }

  void _filterInventtia(String query) {
    setState(() {
      _inventtiaFiltered =
          _inventtia
              .where((e) => e.name.toLowerCase().contains(query.toLowerCase()))
              .toList();
    });
  }

  Future<void> _deleteCarnaval(int id, String name) async {
    final confirm = await _showConfirm(
      'Eliminar proveedor',
      '¿Eliminar "$name"? Esta acción es irreversible.',
    );
    if (!confirm) return;
    setState(() => _deleting = true);
    try {
      await DeletionService.deleteCarnavalProvider(id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Proveedor eliminado')));
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo eliminar: la función está en uso. Detalle: $e',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _deleteInventtia(int id, String name) async {
    final confirm = await _showConfirm(
      'Eliminar tienda',
      '¿Eliminar tienda "$name"? Esta acción es irreversible.',
    );
    if (!confirm) return;
    setState(() => _deleting = true);
    try {
      await DeletionService.deleteInventtiaStore(id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Tienda eliminada')));
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo eliminar: la tienda está en uso. Detalle: $e',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<bool> _showConfirm(String title, String msg) async {
    return await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: Text(title),
                content: Text(msg),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                    ),
                    child: const Text('Eliminar'),
                  ),
                ],
              ),
        ) ??
        false;
  }

  Color _accessColor(DateTime? last) {
    if (last == null) return AppColors.textSecondary;
    final diff = DateTime.now().difference(last).inDays;
    if (diff > 30) return AppColors.error; // rojo
    if (diff > 7) return AppColors.warning; // amarillo
    return AppColors.success; // verde
  }

  String _accessLabel(DateTime? last) {
    if (last == null) return 'Sin acceso';
    final diff = DateTime.now().difference(last).inDays;
    if (diff == 0) return 'Hoy';
    if (diff == 1) return 'Ayer';
    return 'Hace $diff días';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Eliminación de Tiendas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _deleting ? null : _loadData,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child:
            _deleting
                ? const Center(child: CircularProgressIndicator())
                : Row(
                  children: [
                    Expanded(child: _buildCarnavalCard()),
                    const SizedBox(width: 12),
                    Expanded(child: _buildInventtiaCard()),
                  ],
                ),
      ),
    );
  }

  Widget _buildCarnavalCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storefront, color: Colors.deepPurple),
                const SizedBox(width: 8),
                Text(
                  'Proveedores Carnaval (${_carnavalFiltered.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                _buildPager(
                  onPrev:
                      _pageCarnaval > 0 && !_deleting
                          ? () {
                            setState(() => _pageCarnaval--);
                            _loadData();
                          }
                          : null,
                  onNext:
                      !_deleting
                          ? () {
                            setState(() => _pageCarnaval++);
                            _loadData();
                          }
                          : null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchCarnavalCtrl,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar proveedor...',
                border: OutlineInputBorder(),
              ),
              onChanged: _filterCarnaval,
            ),
            const SizedBox(height: 12),
            Expanded(
              child:
                  _loadingCarnaval
                      ? const Center(child: CircularProgressIndicator())
                      : SingleChildScrollView(
                        child: DataTable(
                          columnSpacing: 12,
                          headingRowHeight: 44,
                          dataRowHeight: 60,
                          columns: const [
                            DataColumn(label: Text('Proveedor')),
                            DataColumn(label: Text('Productos')),
                            DataColumn(label: Text('Último acceso')),
                            DataColumn(label: Text('Acciones')),
                          ],
                          rows:
                              _carnavalFiltered.map((item) {
                                final color = _accessColor(item.ultimoAcceso);
                                return DataRow(
                                  cells: [
                                    DataCell(
                                      Text(
                                        item.name,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    DataCell(
                                      Text(item.totalProductos.toString()),
                                    ),
                                    DataCell(
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.access_time,
                                            size: 16,
                                            color: color,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _accessLabel(item.ultimoAcceso),
                                            style: TextStyle(color: color),
                                          ),
                                        ],
                                      ),
                                    ),
                                    DataCell(
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete,
                                          color: Colors.red,
                                        ),
                                        tooltip: 'Eliminar proveedor',
                                        onPressed:
                                            _deleting
                                                ? null
                                                : () => _deleteCarnaval(
                                                  item.id,
                                                  item.name,
                                                ),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInventtiaCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.store, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Tiendas Inventtia (${_inventtiaFiltered.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                _buildPager(
                  onPrev:
                      _pageInventtia > 0 && !_deleting
                          ? () {
                            setState(() => _pageInventtia--);
                            _loadData();
                          }
                          : null,
                  onNext:
                      !_deleting
                          ? () {
                            setState(() => _pageInventtia++);
                            _loadData();
                          }
                          : null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchInventtiaCtrl,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar tienda...',
                border: OutlineInputBorder(),
              ),
              onChanged: _filterInventtia,
            ),
            const SizedBox(height: 12),
            Expanded(
              child:
                  _loadingInventtia
                      ? const Center(child: CircularProgressIndicator())
                      : SingleChildScrollView(
                        child: DataTable(
                          columnSpacing: 12,
                          headingRowHeight: 44,
                          dataRowHeight: 60,
                          columns: const [
                            DataColumn(label: Text('Tienda')),
                            DataColumn(label: Text('Productos')),
                            DataColumn(label: Text('Almacenes')),
                            DataColumn(label: Text('Último acceso Supervisor')),
                            DataColumn(label: Text('Acciones')),
                          ],
                          rows:
                              _inventtiaFiltered.map((item) {
                                final color = _accessColor(
                                  item.ultimoAccesoSupervisor,
                                );
                                return DataRow(
                                  cells: [
                                    DataCell(
                                      Text(
                                        item.name,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    DataCell(
                                      Text(item.totalProductos.toString()),
                                    ),
                                    DataCell(
                                      Text(item.totalAlmacenes.toString()),
                                    ),
                                    DataCell(
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.access_time,
                                            size: 16,
                                            color: color,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _accessLabel(
                                              item.ultimoAccesoSupervisor,
                                            ),
                                            style: TextStyle(color: color),
                                          ),
                                        ],
                                      ),
                                    ),
                                    DataCell(
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete,
                                          color: Colors.red,
                                        ),
                                        tooltip: 'Eliminar tienda',
                                        onPressed:
                                            _deleting
                                                ? null
                                                : () => _deleteInventtia(
                                                  item.id,
                                                  item.name,
                                                ),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPager({VoidCallback? onPrev, VoidCallback? onNext}) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: onPrev,
          tooltip: 'Página anterior',
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: onNext,
          tooltip: 'Página siguiente',
        ),
      ],
    );
  }
}
