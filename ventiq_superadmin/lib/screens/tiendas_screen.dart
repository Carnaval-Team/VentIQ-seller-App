import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/tienda.dart';
import '../widgets/app_drawer.dart';
import '../utils/platform_utils.dart';

class TiendasScreen extends StatefulWidget {
  const TiendasScreen({super.key});

  @override
  State<TiendasScreen> createState() => _TiendasScreenState();
}

class _TiendasScreenState extends State<TiendasScreen> {
  List<Tienda> _tiendas = [];
  List<Tienda> _filteredTiendas = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedFilter = 'todas';

  @override
  void initState() {
    super.initState();
    _loadTiendas();
  }

  Future<void> _loadTiendas() async {
    setState(() => _isLoading = true);
    
    // Simular carga de datos
    await Future.delayed(const Duration(seconds: 1));
    
    setState(() {
      _tiendas = Tienda.getMockData();
      _filteredTiendas = _tiendas;
      _isLoading = false;
    });
  }

  void _filterTiendas() {
    setState(() {
      _filteredTiendas = _tiendas.where((tienda) {
        final matchesSearch = tienda.nombre.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                            tienda.ubicacion.toLowerCase().contains(_searchQuery.toLowerCase());
        
        final matchesFilter = _selectedFilter == 'todas' ||
                            (_selectedFilter == 'activas' && tienda.estado == 'activa') ||
                            (_selectedFilter == 'inactivas' && tienda.estado != 'activa') ||
                            (_selectedFilter == 'renovacion' && tienda.necesitaRenovacion);
        
        return matchesSearch && matchesFilter;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(screenSize.width);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Tiendas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTiendas,
            tooltip: 'Actualizar',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateTiendaDialog(),
            tooltip: 'Nueva Tienda',
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: const AppDrawer(),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(isDesktop),
      floatingActionButton: !isDesktop ? FloatingActionButton(
        onPressed: () => _showCreateTiendaDialog(),
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
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Buscar tiendas...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      _searchQuery = value;
                      _filterTiendas();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: _selectedFilter,
                    decoration: const InputDecoration(
                      labelText: 'Filtrar por estado',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'todas', child: Text('Todas')),
                      DropdownMenuItem(value: 'activas', child: Text('Activas')),
                      DropdownMenuItem(value: 'inactivas', child: Text('Inactivas')),
                      DropdownMenuItem(value: 'renovacion', child: Text('Necesitan Renovación')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedFilter = value!;
                      });
                      _filterTiendas();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats() {
    final activas = _tiendas.where((t) => t.estado == 'activa').length;
    final inactivas = _tiendas.length - activas;
    final necesitanRenovacion = _tiendas.where((t) => t.necesitaRenovacion).length;

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Total Tiendas',
            _tiendas.length.toString(),
            Icons.store,
            AppColors.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Activas',
            activas.toString(),
            Icons.check_circle,
            AppColors.success,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Inactivas',
            inactivas.toString(),
            Icons.cancel,
            AppColors.error,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Renovación',
            necesitanRenovacion.toString(),
            Icons.schedule,
            AppColors.warning,
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
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            // Header de la tabla
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.store, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Lista de Tiendas (${_filteredTiendas.length})',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            // Tabla con scroll
            Expanded(
              child: SingleChildScrollView(
                child: SizedBox(
                  width: double.infinity,
                  child: DataTable(
                    columnSpacing: 16,
                    horizontalMargin: 16,
                    headingRowHeight: 56,
                    dataRowHeight: 72,
                    columns: const [
                      DataColumn(
                        label: Expanded(
                          child: Text(
                            'Tienda',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Expanded(
                          child: Text(
                            'Ubicación',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Expanded(
                          child: Text(
                            'Estado',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Expanded(
                          child: Text(
                            'Licencia',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Expanded(
                          child: Text(
                            'Vencimiento',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Expanded(
                          child: Text(
                            'Ventas/Mes',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Expanded(
                          child: Text(
                            'Acciones',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                    rows: _filteredTiendas.map((tienda) {
                      return DataRow(
                        cells: [
                          DataCell(
                            SizedBox(
                              width: double.infinity,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    tienda.nombre,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    tienda.direccion,
                                    style: Theme.of(context).textTheme.bodySmall,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: double.infinity,
                              child: Text(
                                tienda.ubicacion,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: double.infinity,
                              child: _buildStatusChip(tienda.estado),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: double.infinity,
                              child: _buildLicenseChip(tienda.tipoLicencia),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: double.infinity,
                              child: _buildExpirationInfo(tienda),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: double.infinity,
                              child: Text(
                                '\$${tienda.ventasMes.toStringAsFixed(0)}',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: double.infinity,
                              child: _buildActions(tienda),
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
      itemCount: _filteredTiendas.length,
      itemBuilder: (context, index) {
        final tienda = _filteredTiendas[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getStatusColor(tienda.estado).withOpacity(0.1),
              child: Icon(
                Icons.store,
                color: _getStatusColor(tienda.estado),
              ),
            ),
            title: Text(
              tienda.nombre,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tienda.ubicacion),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _buildStatusChip(tienda.estado),
                    const SizedBox(width: 8),
                    _buildLicenseChip(tienda.tipoLicencia),
                  ],
                ),
              ],
            ),
            trailing: PopupMenuButton(
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'view',
                  child: ListTile(
                    leading: Icon(Icons.visibility),
                    title: Text('Ver Detalles'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit),
                    title: Text('Editar'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete, color: Colors.red),
                    title: Text('Eliminar', style: TextStyle(color: Colors.red)),
                  ),
                ),
              ],
              onSelected: (value) => _handleAction(value.toString(), tienda),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusChip(String estado) {
    Color color;
    switch (estado) {
      case 'activa':
        color = AppColors.success;
        break;
      case 'suspendida':
        color = AppColors.warning;
        break;
      default:
        color = AppColors.error;
    }

    return Chip(
      label: Text(
        estado.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: color.withOpacity(0.1),
      side: BorderSide(color: color),
    );
  }

  Widget _buildLicenseChip(String tipoLicencia) {
    Color color;
    switch (tipoLicencia) {
      case 'enterprise':
        color = AppColors.primary;
        break;
      case 'premium':
        color = AppColors.secondary;
        break;
      default:
        color = AppColors.textSecondary;
    }

    return Chip(
      label: Text(
        tipoLicencia.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: color.withOpacity(0.1),
      side: BorderSide(color: color),
    );
  }

  Widget _buildExpirationInfo(Tienda tienda) {
    if (tienda.fechaVencimientoLicencia == null) {
      return const Text('Sin vencimiento');
    }

    final dias = tienda.diasParaVencimiento;
    Color color = AppColors.success;
    String text = '$dias días';

    if (dias < 0) {
      color = AppColors.error;
      text = 'Vencida';
    } else if (dias <= 30) {
      color = AppColors.warning;
    }

    return Text(
      text,
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildActions(Tienda tienda) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.visibility),
          onPressed: () => _handleAction('view', tienda),
          tooltip: 'Ver Detalles',
        ),
        IconButton(
          icon: const Icon(Icons.edit),
          onPressed: () => _handleAction('edit', tienda),
          tooltip: 'Editar',
        ),
        IconButton(
          icon: const Icon(Icons.delete, color: AppColors.error),
          onPressed: () => _handleAction('delete', tienda),
          tooltip: 'Eliminar',
        ),
      ],
    );
  }

  Color _getStatusColor(String estado) {
    switch (estado) {
      case 'activa':
        return AppColors.success;
      case 'suspendida':
        return AppColors.warning;
      default:
        return AppColors.error;
    }
  }

  void _handleAction(String action, Tienda tienda) {
    switch (action) {
      case 'view':
        _showTiendaDetails(tienda);
        break;
      case 'edit':
        _showEditTiendaDialog(tienda);
        break;
      case 'delete':
        _showDeleteConfirmation(tienda);
        break;
    }
  }

  void _showCreateTiendaDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva Tienda'),
        content: const Text('Funcionalidad de creación de tienda en desarrollo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showTiendaDetails(Tienda tienda) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tienda.nombre),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dirección: ${tienda.direccion}'),
            Text('Ubicación: ${tienda.ubicacion}'),
            Text('Estado: ${tienda.estado}'),
            Text('Tipo de Licencia: ${tienda.tipoLicencia}'),
            Text('Productos: ${tienda.totalProductos}'),
            Text('Empleados: ${tienda.totalEmpleados}'),
            Text('Ventas del Mes: \$${tienda.ventasMes.toStringAsFixed(2)}'),
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

  void _showEditTiendaDialog(Tienda tienda) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Editar ${tienda.nombre}'),
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

  void _showDeleteConfirmation(Tienda tienda) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: Text('¿Estás seguro de que deseas eliminar "${tienda.nombre}"?'),
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
