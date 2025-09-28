import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_colors.dart';
import '../widgets/app_drawer.dart';
import '../utils/platform_utils.dart';

class TpvsScreen extends StatefulWidget {
  const TpvsScreen({super.key});

  @override
  State<TpvsScreen> createState() => _TpvsScreenState();
}

class _TpvsScreenState extends State<TpvsScreen> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;
  
  List<Map<String, dynamic>> _tpvs = [];
  List<Map<String, dynamic>> _vendedores = [];
  List<Map<String, dynamic>> _filteredTpvs = [];
  List<Map<String, dynamic>> _filteredVendedores = [];
  List<Map<String, dynamic>> _tiendas = [];
  List<Map<String, dynamic>> _almacenes = [];
  
  bool _isLoading = true;
  String _searchQuery = '';
  int? _selectedTienda;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      // Cargar tiendas
      final tiendasResponse = await _supabase
          .from('app_dat_tienda')
          .select('id, denominacion')
          .order('denominacion');
      
      // Cargar almacenes
      final almacenesResponse = await _supabase
          .from('app_dat_almacen')
          .select('id, denominacion, id_tienda')
          .order('denominacion');
      
      // Cargar TPVs con información relacionada
      final tpvsResponse = await _supabase
          .from('app_dat_tpv')
          .select('''
            id,
            id_tienda,
            id_almacen,
            denominacion,
            created_at,
            app_dat_tienda!inner(
              denominacion
            ),
            app_dat_almacen!inner(
              denominacion
            )
          ''')
          .order('denominacion');
      
      // Cargar vendedores con información relacionada
      final vendedoresResponse = await _supabase
          .from('app_dat_vendedor')
          .select('''
            id,
            uuid,
            id_tienda,
            id_tpv,
            numero_confirmacion,
            created_at,
            app_dat_tienda!inner(
              denominacion
            ),
            app_dat_tpv!inner(
              denominacion
            ),
            app_dat_trabajadores!inner(
              id,
              nombres,
              apellidos
            )
          ''')
          .order('created_at', ascending: false);
      
      // Formatear datos de TPVs
      final tpvs = <Map<String, dynamic>>[];
      for (var tpv in tpvsResponse) {
        // Contar vendedores asignados a este TPV
        final vendedoresCount = await _supabase
            .from('app_dat_vendedor')
            .select('id')
            .eq('id_tpv', tpv['id'])
            .count();
        
        tpvs.add({
          ...tpv,
          'tienda_nombre': tpv['app_dat_tienda']?['denominacion'] ?? 'Sin tienda',
          'almacen_nombre': tpv['app_dat_almacen']?['denominacion'] ?? 'Sin almacén',
          'vendedores_count': vendedoresCount.count ?? 0,
        });
      }
      
      // Formatear datos de vendedores
      final vendedores = <Map<String, dynamic>>[];
      for (var vendedor in vendedoresResponse) {
        final trabajador = vendedor['app_dat_trabajadores'];
        
        vendedores.add({
          ...vendedor,
          'nombres': trabajador?['nombres'] ?? 'Sin nombre',
          'apellidos': trabajador?['apellidos'] ?? '',
          'tienda_nombre': vendedor['app_dat_tienda']?['denominacion'] ?? 'Sin tienda',
          'tpv_nombre': vendedor['app_dat_tpv']?['denominacion'] ?? 'Sin TPV',
        });
      }
      
      if (mounted) {
        setState(() {
          _tiendas = List<Map<String, dynamic>>.from(tiendasResponse);
          _almacenes = List<Map<String, dynamic>>.from(almacenesResponse);
          _tpvs = tpvs;
          _vendedores = vendedores;
          _filteredTpvs = tpvs;
          _filteredVendedores = vendedores;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando datos: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar datos: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _filterData() {
    setState(() {
      // Filtrar TPVs
      _filteredTpvs = _tpvs.where((tpv) {
        final matchesSearch = 
            tpv['denominacion'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
            tpv['tienda_nombre'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
            tpv['almacen_nombre'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
        
        final matchesTienda = _selectedTienda == null ||
                            tpv['id_tienda'] == _selectedTienda;
        
        return matchesSearch && matchesTienda;
      }).toList();
      
      // Filtrar vendedores
      _filteredVendedores = _vendedores.where((vendedor) {
        final nombreCompleto = '${vendedor['nombres']} ${vendedor['apellidos']}'.toLowerCase();
        final matchesSearch = 
            nombreCompleto.contains(_searchQuery.toLowerCase()) ||
            vendedor['tpv_nombre'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
            vendedor['numero_confirmacion'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
        
        final matchesTienda = _selectedTienda == null ||
                            vendedor['id_tienda'] == _selectedTienda;
        
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
        title: const Text('TPVs y Vendedores'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Puntos de Venta', icon: Icon(Icons.point_of_sale)),
            Tab(text: 'Vendedores', icon: Icon(Icons.people)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Actualizar',
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: const AppDrawer(),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTpvsTab(isDesktop),
                _buildVendedoresTab(isDesktop),
              ],
            ),
    );
  }

  Widget _buildTpvsTab(bool isDesktop) {
    return Padding(
      padding: EdgeInsets.all(PlatformUtils.getScreenPadding()),
      child: Column(
        children: [
          _buildFilters(),
          const SizedBox(height: 16),
          _buildTpvsStats(),
          const SizedBox(height: 16),
          Expanded(
            child: isDesktop 
                ? _buildTpvsDesktopTable()
                : _buildTpvsMobileList(),
          ),
        ],
      ),
    );
  }

  Widget _buildVendedoresTab(bool isDesktop) {
    return Padding(
      padding: EdgeInsets.all(PlatformUtils.getScreenPadding()),
      child: Column(
        children: [
          _buildFilters(),
          const SizedBox(height: 16),
          _buildVendedoresStats(),
          const SizedBox(height: 16),
          Expanded(
            child: isDesktop 
                ? _buildVendedoresDesktopTable()
                : _buildVendedoresMobileList(),
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
                  labelText: 'Buscar',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                  _filterData();
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
                  _filterData();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTpvsStats() {
    final tiendasConTpv = _tpvs.map((t) => t['id_tienda']).toSet().length;
    final almacenesConTpv = _tpvs.map((t) => t['id_almacen']).toSet().length;
    final totalVendedores = _tpvs.fold<int>(
      0, (sum, tpv) => sum + (tpv['vendedores_count'] as int)
    );
    
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Total TPVs',
            _tpvs.length.toString(),
            Icons.point_of_sale,
            AppColors.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Tiendas con TPV',
            tiendasConTpv.toString(),
            Icons.store,
            AppColors.success,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Almacenes',
            almacenesConTpv.toString(),
            Icons.warehouse,
            AppColors.info,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Vendedores',
            totalVendedores.toString(),
            Icons.people,
            AppColors.secondary,
          ),
        ),
      ],
    );
  }

  Widget _buildVendedoresStats() {
    final tiendasConVendedor = _vendedores.map((v) => v['id_tienda']).toSet().length;
    final tpvsConVendedor = _vendedores.map((v) => v['id_tpv']).toSet().length;
    final conConfirmacion = _vendedores.where((v) => v['numero_confirmacion'] != null).length;
    
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Total Vendedores',
            _vendedores.length.toString(),
            Icons.people,
            AppColors.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Tiendas',
            tiendasConVendedor.toString(),
            Icons.store,
            AppColors.success,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'TPVs Asignados',
            tpvsConVendedor.toString(),
            Icons.point_of_sale,
            AppColors.info,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Con Confirmación',
            conConfirmacion.toString(),
            Icons.verified_user,
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

  Widget _buildTpvsDesktopTable() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Puntos de Venta',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('TPV')),
                      DataColumn(label: Text('Tienda')),
                      DataColumn(label: Text('Almacén')),
                      DataColumn(label: Text('Vendedores')),
                      DataColumn(label: Text('Fecha Creación')),
                      DataColumn(label: Text('Acciones')),
                    ],
                    rows: _filteredTpvs.map((tpv) {
                      return DataRow(
                        cells: [
                          DataCell(Text(tpv['denominacion'] ?? 'Sin nombre')),
                          DataCell(Text(tpv['tienda_nombre'])),
                          DataCell(Text(tpv['almacen_nombre'])),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.info.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                tpv['vendedores_count'].toString(),
                                style: TextStyle(
                                  color: AppColors.info,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          DataCell(Text(_formatDate(tpv['created_at']))),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.visibility),
                                  onPressed: () => _showTpvDetails(tpv),
                                  tooltip: 'Ver Detalles',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _showEditDialog('TPV', tpv),
                                  tooltip: 'Editar',
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

  Widget _buildVendedoresDesktopTable() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vendedores',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Vendedor')),
                      DataColumn(label: Text('Tienda')),
                      DataColumn(label: Text('TPV Asignado')),
                      DataColumn(label: Text('N° Confirmación')),
                      DataColumn(label: Text('Fecha Registro')),
                      DataColumn(label: Text('Acciones')),
                    ],
                    rows: _filteredVendedores.map((vendedor) {
                      return DataRow(
                        cells: [
                          DataCell(Text('${vendedor['nombres']} ${vendedor['apellidos']}')),
                          DataCell(Text(vendedor['tienda_nombre'])),
                          DataCell(Text(vendedor['tpv_nombre'])),
                          DataCell(
                            vendedor['numero_confirmacion'] != null
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.success.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      vendedor['numero_confirmacion'],
                                      style: TextStyle(
                                        color: AppColors.success,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  )
                                : const Text('Sin confirmación', style: TextStyle(color: AppColors.textSecondary)),
                          ),
                          DataCell(Text(_formatDate(vendedor['created_at']))),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.visibility),
                                  onPressed: () => _showVendedorDetails(vendedor),
                                  tooltip: 'Ver Detalles',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _showEditDialog('Vendedor', vendedor),
                                  tooltip: 'Editar',
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

  Widget _buildTpvsMobileList() {
    return ListView.builder(
      itemCount: _filteredTpvs.length,
      itemBuilder: (context, index) {
        final tpv = _filteredTpvs[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withOpacity(0.1),
              child: const Icon(
                Icons.point_of_sale,
                color: AppColors.primary,
              ),
            ),
            title: Text(
              tpv['denominacion'] ?? 'Sin nombre',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tienda: ${tpv['tienda_nombre']}'),
                Text('Almacén: ${tpv['almacen_nombre']}'),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.people, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      '${tpv['vendedores_count']} vendedores',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => _showTpvDetails(tpv),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVendedoresMobileList() {
    return ListView.builder(
      itemCount: _filteredVendedores.length,
      itemBuilder: (context, index) {
        final vendedor = _filteredVendedores[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.info.withOpacity(0.1),
              child: const Icon(
                Icons.person,
                color: AppColors.info,
              ),
            ),
            title: Text(
              '${vendedor['nombres']} ${vendedor['apellidos']}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tienda: ${vendedor['tienda_nombre']}'),
                Text('TPV: ${vendedor['tpv_nombre']}'),
                if (vendedor['numero_confirmacion'] != null)
                  Text(
                    'Confirmación: ${vendedor['numero_confirmacion']}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => _showVendedorDetails(vendedor),
            ),
          ),
        );
      },
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  void _showTpvDetails(Map<String, dynamic> tpv) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tpv['denominacion'] ?? 'Sin nombre'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${tpv['id']}'),
            Text('Tienda: ${tpv['tienda_nombre']}'),
            Text('Almacén: ${tpv['almacen_nombre']}'),
            Text('Vendedores asignados: ${tpv['vendedores_count']}'),
            Text('Fecha de creación: ${_formatDate(tpv['created_at'])}'),
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

  void _showVendedorDetails(Map<String, dynamic> vendedor) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${vendedor['nombres']} ${vendedor['apellidos']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('UUID: ${vendedor['uuid']}'),
            Text('Tienda: ${vendedor['tienda_nombre']}'),
            Text('TPV: ${vendedor['tpv_nombre']}'),
            if (vendedor['numero_confirmacion'] != null)
              Text('N° Confirmación: ${vendedor['numero_confirmacion']}'),
            Text('Fecha de registro: ${_formatDate(vendedor['created_at'])}'),
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

  void _showEditDialog(String type, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Editar $type'),
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
}
