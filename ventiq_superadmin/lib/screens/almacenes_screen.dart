import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_colors.dart';
import '../widgets/app_drawer.dart';
import '../utils/platform_utils.dart';

class AlmacenesScreen extends StatefulWidget {
  const AlmacenesScreen({super.key});

  @override
  State<AlmacenesScreen> createState() => _AlmacenesScreenState();
}

class _AlmacenesScreenState extends State<AlmacenesScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _almacenes = [];
  List<Map<String, dynamic>> _filteredAlmacenes = [];
  List<Map<String, dynamic>> _tiendas = [];
  bool _isLoading = true;
  String _searchQuery = '';
  int? _selectedTienda;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      // Cargar tiendas
      final tiendasResponse = await _supabase
          .from('app_dat_tienda')
          .select('id, denominacion')
          .order('denominacion');
      
      // Cargar almacenes con información de tienda
      final almacenesResponse = await _supabase
          .from('app_dat_almacen')
          .select('''
            id,
            id_tienda,
            denominacion,
            direccion,
            ubicacion,
            created_at,
            app_dat_tienda!inner(
              denominacion
            )
          ''')
          .order('denominacion');
      
      // Obtener estadísticas de cada almacén
      final almacenesConStats = <Map<String, dynamic>>[];
      
      for (var almacen in almacenesResponse) {
        // Contar layouts (ubicaciones) del almacén
        final layoutsResponse = await _supabase
            .from('app_dat_layout_almacen')
            .select('id')
            .eq('id_almacen', almacen['id'])
            .count();
        
        // Contar productos en inventario del almacén
        final inventarioResponse = await _supabase
            .from('app_dat_inventario_productos')
            .select('id, cantidad_final')
            .eq('id_ubicacion', almacen['id']);
        
        int totalProductos = 0;
        double stockTotal = 0;
        
        if (inventarioResponse is List) {
          totalProductos = inventarioResponse.length;
          for (var item in inventarioResponse) {
            stockTotal += (item['cantidad_final'] ?? 0).toDouble();
          }
        }
        
        // Contar TPVs asociados al almacén
        final tpvsResponse = await _supabase
            .from('app_dat_tpv')
            .select('id')
            .eq('id_almacen', almacen['id'])
            .count();
        
        almacenesConStats.add({
          ...almacen,
          'total_layouts': layoutsResponse.count ?? 0,
          'total_productos': totalProductos,
          'stock_total': stockTotal,
          'total_tpvs': tpvsResponse.count ?? 0,
          'tienda_nombre': almacen['app_dat_tienda']?['denominacion'] ?? 'Sin tienda',
        });
      }
      
      if (mounted) {
        setState(() {
          _tiendas = List<Map<String, dynamic>>.from(tiendasResponse);
          _almacenes = almacenesConStats;
          _filteredAlmacenes = almacenesConStats;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando almacenes: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar almacenes: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _filterAlmacenes() {
    setState(() {
      _filteredAlmacenes = _almacenes.where((almacen) {
        final matchesSearch = 
            almacen['denominacion'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
            almacen['direccion'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
            almacen['ubicacion'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
        
        final matchesTienda = _selectedTienda == null ||
                            almacen['id_tienda'] == _selectedTienda;
        
        return matchesSearch && matchesTienda;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(screenSize.width);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Almacenes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Actualizar',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateAlmacenDialog(),
            tooltip: 'Nuevo Almacén',
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: const AppDrawer(),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(isDesktop),
      floatingActionButton: !isDesktop ? FloatingActionButton(
        onPressed: () => _showCreateAlmacenDialog(),
        child: const Icon(Icons.add),
      ) : null,
    );
  }

  Widget _buildBody(bool isDesktop) {
    return Padding(
      padding: EdgeInsets.all(PlatformUtils.getScreenPadding()),
      child: Column(
        children: [
          _buildFilters(),
          const SizedBox(height: 16),
          _buildStats(),
          const SizedBox(height: 16),
          Expanded(
            child: isDesktop 
                ? _buildDesktopTable()
                : _buildMobileList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Buscar almacén',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                  _filterAlmacenes();
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<int?>(
                value: _selectedTienda,
                decoration: const InputDecoration(
                  labelText: 'Tienda',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todas')),
                  ..._tiendas.map((tienda) => DropdownMenuItem(
                    value: tienda['id'] as int,
                    child: Text(tienda['denominacion']),
                  )),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedTienda = value;
                  });
                  _filterAlmacenes();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats() {
    final totalStock = _almacenes.fold<double>(
      0, (sum, almacen) => sum + (almacen['stock_total'] ?? 0)
    );
    final totalProductos = _almacenes.fold<int>(
      0, (sum, almacen) => sum + (almacen['total_productos'] as int? ?? 0)
    );
    final totalLayouts = _almacenes.fold<int>(
      0, (sum, almacen) => sum + (almacen['total_layouts'] as int? ?? 0)
    );
    
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Total Almacenes',
            _almacenes.length.toString(),
            Icons.warehouse,
            AppColors.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Productos',
            totalProductos.toString(),
            Icons.inventory_2,
            AppColors.success,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Stock Total',
            totalStock.toStringAsFixed(0),
            Icons.inventory,
            AppColors.info,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Ubicaciones',
            totalLayouts.toString(),
            Icons.location_on,
            AppColors.secondary,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopTable() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lista de Almacenes',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Almacén')),
                      DataColumn(label: Text('Tienda')),
                      DataColumn(label: Text('Dirección')),
                      DataColumn(label: Text('Ubicación')),
                      DataColumn(label: Text('TPVs')),
                      DataColumn(label: Text('Productos')),
                      DataColumn(label: Text('Stock')),
                      DataColumn(label: Text('Acciones')),
                    ],
                    rows: _filteredAlmacenes.map((almacen) {
                      return DataRow(
                        cells: [
                          DataCell(Text(almacen['denominacion'] ?? 'Sin nombre')),
                          DataCell(Text(almacen['tienda_nombre'])),
                          DataCell(Text(almacen['direccion'] ?? 'Sin dirección')),
                          DataCell(Text(almacen['ubicacion'] ?? 'Sin ubicación')),
                          DataCell(
                            _buildCountChip(
                              almacen['total_tpvs'].toString(),
                              Icons.point_of_sale,
                              AppColors.info,
                            ),
                          ),
                          DataCell(
                            _buildCountChip(
                              almacen['total_productos'].toString(),
                              Icons.inventory_2,
                              AppColors.success,
                            ),
                          ),
                          DataCell(
                            Text(
                              almacen['stock_total'].toStringAsFixed(0),
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.visibility),
                                  onPressed: () => _showAlmacenDetails(almacen),
                                  tooltip: 'Ver Detalles',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _showEditAlmacenDialog(almacen),
                                  tooltip: 'Editar',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: AppColors.error),
                                  onPressed: () => _showDeleteConfirmation(almacen),
                                  tooltip: 'Eliminar',
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileList() {
    return ListView.builder(
      itemCount: _filteredAlmacenes.length,
      itemBuilder: (context, index) {
        final almacen = _filteredAlmacenes[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withOpacity(0.1),
              child: const Icon(
                Icons.warehouse,
                color: AppColors.primary,
              ),
            ),
            title: Text(
              almacen['denominacion'] ?? 'Sin nombre',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(almacen['tienda_nombre']),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (almacen['direccion'] != null)
                      _buildInfoRow(Icons.location_on, 'Dirección', almacen['direccion']),
                    if (almacen['ubicacion'] != null)
                      _buildInfoRow(Icons.map, 'Ubicación', almacen['ubicacion']),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatChip('TPVs', almacen['total_tpvs'].toString(), AppColors.info),
                        _buildStatChip('Productos', almacen['total_productos'].toString(), AppColors.success),
                        _buildStatChip('Stock', almacen['stock_total'].toStringAsFixed(0), AppColors.primary),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.visibility),
                          label: const Text('Ver'),
                          onPressed: () => _showAlmacenDetails(almacen),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.edit),
                          label: const Text('Editar'),
                          onPressed: () => _showEditAlmacenDialog(almacen),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.delete, color: AppColors.error),
                          label: const Text('Eliminar', style: TextStyle(color: AppColors.error)),
                          onPressed: () => _showDeleteConfirmation(almacen),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildCountChip(String count, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            count,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateAlmacenDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuevo Almacén'),
        content: const Text('Funcionalidad de creación de almacén en desarrollo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showAlmacenDetails(Map<String, dynamic> almacen) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(almacen['denominacion'] ?? 'Sin nombre'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tienda: ${almacen['tienda_nombre']}'),
            if (almacen['direccion'] != null)
              Text('Dirección: ${almacen['direccion']}'),
            if (almacen['ubicacion'] != null)
              Text('Ubicación: ${almacen['ubicacion']}'),
            const Divider(),
            Text('TPVs asociados: ${almacen['total_tpvs']}'),
            Text('Productos: ${almacen['total_productos']}'),
            Text('Stock total: ${almacen['stock_total'].toStringAsFixed(2)}'),
            Text('Ubicaciones: ${almacen['total_layouts']}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showEditAlmacenDialog(Map<String, dynamic> almacen) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Editar ${almacen['denominacion']}'),
        content: const Text('Funcionalidad de edición en desarrollo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(Map<String, dynamic> almacen) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: Text('¿Estás seguro de que deseas eliminar el almacén "${almacen['denominacion']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              // TODO: Implementar eliminación
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Funcionalidad en desarrollo')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}
