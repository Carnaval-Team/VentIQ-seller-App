import 'package:flutter/material.dart';
import '../../models/supplier.dart';
import '../../services/supplier_service.dart';
import '../../widgets/supplier/supplier_card.dart';
import 'add_edit_supplier_screen.dart';
import 'supplier_detail_screen.dart';
import '../../utils/navigation_guard.dart';

class SuppliersListScreen extends StatefulWidget {
  const SuppliersListScreen({super.key});

  @override
  State<SuppliersListScreen> createState() => _SuppliersListScreenState();
}

class _SuppliersListScreenState extends State<SuppliersListScreen> {
  List<Supplier> _suppliers = [];
  List<Supplier> _filteredSuppliers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _errorMessage = '';
  bool _canCreateSupplier = false;
  bool _canEditSupplier = false;
  bool _canDeleteSupplier = false;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    _loadSuppliers();
  }

  Future<void> _loadPermissions() async {
    final permissions = await Future.wait([
      NavigationGuard.canPerformAction('supplier.create'),
      NavigationGuard.canPerformAction('supplier.edit'),
      NavigationGuard.canPerformAction('supplier.delete'),
    ]);

    if (!mounted) return;
    setState(() {
      _canCreateSupplier = permissions[0];
      _canEditSupplier = permissions[1];
      _canDeleteSupplier = permissions[2];
    });
  }

  Future<void> _loadSuppliers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final suppliers = await SupplierService.getAllSuppliers(
        includeMetrics: true,
      );
      setState(() {
        _suppliers = suppliers;
        _filteredSuppliers = suppliers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error al cargar proveedores: $e';
      });
    }
  }

  void _filterSuppliers(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredSuppliers = _suppliers;
      } else {
        _filteredSuppliers =
            _suppliers.where((supplier) {
              return supplier.denominacion.toLowerCase().contains(
                    query.toLowerCase(),
                  ) ||
                  supplier.skuCodigo.toLowerCase().contains(
                    query.toLowerCase(),
                  ) ||
                  (supplier.ubicacion?.toLowerCase().contains(
                        query.toLowerCase(),
                      ) ??
                      false);
            }).toList();
      }
    });
  }

  Future<void> _navigateToAddSupplier() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddEditSupplierScreen()),
    );

    if (result == true) {
      _loadSuppliers();
    }
  }

  Future<void> _navigateToEditSupplier(Supplier supplier) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddEditSupplierScreen(supplier: supplier),
      ),
    );

    if (result == true) {
      _loadSuppliers();
    }
  }

  Future<void> _navigateToSupplierDetail(Supplier supplier) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SupplierDetailScreen(supplier: supplier),
      ),
    );

    if (result == true) {
      _loadSuppliers();
    }
  }

  Future<void> _deleteSupplier(Supplier supplier) async {
    try {
      // Mostrar indicador de carga
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final result = await SupplierService.deleteSupplier(supplier.id);

      // Cerrar indicador de carga
      if (mounted) Navigator.of(context).pop();

      if (result['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Colors.green,
          ),
        );
        _loadSuppliers();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      // Cerrar indicador de carga si hay error
      if (mounted) Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al eliminar proveedor: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Proveedores'),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics),
            onPressed: () => Navigator.pushNamed(context, '/supplier-reports'),
            tooltip: 'Reportes',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSuppliers,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: Column(
        children: [
          // Barra de búsqueda y estadísticas
          _buildHeader(),

          // Lista de proveedores
          Expanded(child: _buildContent()),
        ],
      ),
      floatingActionButton: FutureBuilder<bool>(
        future: NavigationGuard.canPerformAction('supplier.create'),
        builder: (context, snapshot) {
          if (snapshot.data == true) {
            return FloatingActionButton(
              onPressed: _navigateToAddSupplier,
              tooltip: 'Agregar proveedor',
              child: const Icon(Icons.add),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey.shade50,
      child: Column(
        children: [
          // Barra de búsqueda
          TextField(
            decoration: InputDecoration(
              hintText: 'Buscar proveedores...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: _filterSuppliers,
          ),

          const SizedBox(height: 16),

          // Estadísticas rápidas
          if (!_isLoading && _suppliers.isNotEmpty) _buildQuickStats(),
        ],
      ),
    );
  }

  Widget _buildQuickStats() {
    final totalSuppliers = _suppliers.length;
    final suppliersWithMetrics = _suppliers.where((s) => s.hasMetrics).length;
    final averageLeadTime =
        _suppliers
            .where((s) => s.leadTime != null)
            .map((s) => s.leadTime!)
            .fold<double>(0, (sum, leadTime) => sum + leadTime) /
        _suppliers.where((s) => s.leadTime != null).length;

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Total',
            totalSuppliers.toString(),
            Icons.business,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Activos',
            suppliersWithMetrics.toString(),
            Icons.trending_up,
            Colors.green,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Lead Time',
            averageLeadTime.isNaN ? 'N/A' : '${averageLeadTime.round()}d',
            Icons.schedule,
            Colors.orange,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadSuppliers,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_filteredSuppliers.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadSuppliers,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 80), // Espacio para FAB
        itemCount: _filteredSuppliers.length,
        itemBuilder: (context, index) {
          final supplier = _filteredSuppliers[index];
          return SupplierCard(
            supplier: supplier,
            showMetrics: true,
            onTap: () => _navigateToSupplierDetail(supplier),
            onEdit:
                _canEditSupplier
                    ? () => _navigateToEditSupplier(supplier)
                    : null,
            onDelete:
                _canDeleteSupplier ? () => _deleteSupplier(supplier) : null,
            onViewDetails: () => _navigateToSupplierDetail(supplier),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.business, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty
                ? 'No hay proveedores registrados'
                : 'No se encontraron proveedores',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isEmpty
                ? 'Agrega tu primer proveedor para comenzar'
                : 'Intenta con otros términos de búsqueda',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
          if (_searchQuery.isEmpty) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _canCreateSupplier ? _navigateToAddSupplier : null,
              icon: const Icon(Icons.add),
              label: const Text('Agregar Proveedor'),
            ),
          ],
        ],
      ),
    );
  }
}
