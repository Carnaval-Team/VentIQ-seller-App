import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/tpv_managements/tpv.dart';
import '../widgets/tpv_managements/vendor.dart';
import '../widgets/tpv_managements/asignate_vendor.dart';

/// Pantalla principal de gestión de TPVs y Vendedores
/// Responsabilidad: Coordinar tabs, búsqueda y navegación
/// La lógica específica está delegada a widgets independientes
class TpvManagementScreen extends StatefulWidget {
  const TpvManagementScreen({Key? key}) : super(key: key);

  @override
  State<TpvManagementScreen> createState() => _TpvManagementScreenState();
}

class _TpvManagementScreenState extends State<TpvManagementScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';
  int _refreshKey = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refreshData() {
    setState(() => _refreshKey++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de TPVs'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.point_of_sale), text: 'TPVs'),
            Tab(icon: Icon(Icons.people), text: 'Vendedores'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                TpvListWidget(
                  key: ValueKey('tpv_$_refreshKey'),
                  searchQuery: _searchQuery,
                  onRefresh: _refreshData,
                ),
                VendorListWidget(
                  key: ValueKey('vendor_$_refreshKey'),
                  searchQuery: _searchQuery,
                  onRefresh: _refreshData,
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: TextField(
        decoration: InputDecoration(
          hintText:
              _tabController.index == 0
                  ? 'Buscar TPVs...'
                  : 'Buscar vendedores...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
        ),
        onChanged: (value) {
          setState(() => _searchQuery = value);
        },
      ),
    );
  }

  void _showAddDialog() {
    final isTPVTab = _tabController.index == 0;

    if (isTPVTab) {
      // TODO: Implementar diálogo de creación de TPV
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Funcionalidad de creación de TPV en desarrollo'),
          backgroundColor: AppColors.warning,
        ),
      );
    } else {
      // Mostrar diálogo de asignación de vendedor
      // Nota: Este diálogo requiere un TPV seleccionado
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Seleccione un TPV desde la lista para asignar un vendedor',
          ),
          backgroundColor: AppColors.info,
        ),
      );
    }
  }
}
