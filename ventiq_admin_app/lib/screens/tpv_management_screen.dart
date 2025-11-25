import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/tpv_managements/tpv.dart';
import '../widgets/tpv_managements/vendor.dart';
import '../widgets/tpv_managements/asignate_vendor.dart';
import '../services/tpv_service.dart';

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
      _showCreateTpvDialog();
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

  /// Muestra el diálogo para crear un nuevo TPV
  void _showCreateTpvDialog() {
    final denominacionController = TextEditingController();
    int? selectedAlmacenId;
    Map<String, dynamic>? selectedAlmacenData;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.point_of_sale, color: AppColors.primary),
              SizedBox(width: 8),
              Text('Crear Nuevo TPV'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: TpvService.getAlmacenesByStore(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error: ${snapshot.error}'),
                  );
                }

                final almacenes = snapshot.data ?? [];

                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Campo de denominación
                      const Text(
                        'Denominación del TPV *',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: denominacionController,
                        decoration: InputDecoration(
                          hintText: 'Ej: TPV Principal, TPV Caja 1',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          prefixIcon: const Icon(Icons.label),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Selector de almacén
                      const Text(
                        'Almacén *',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (almacenes.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.orange.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber,
                                  color: Colors.orange[700]),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'No hay almacenes disponibles',
                                  style: TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          width: double.maxFinite,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.grey.shade300,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: DropdownButton<int>(
                              value: selectedAlmacenId,
                              hint: const Text('Seleccione un almacén'),
                              isExpanded: true,
                              underline: const SizedBox(),
                              items: almacenes.map((almacen) {
                                return DropdownMenuItem<int>(
                                  value: almacen['id'],
                                  child: Text(
                                    almacen['denominacion'] ?? 'Sin nombre',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (id) {
                                if (id != null) {
                                  final almacen = almacenes
                                      .firstWhere((a) => a['id'] == id);
                                  setState(() {
                                    selectedAlmacenId = id;
                                    selectedAlmacenData = almacen;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              onPressed: denominacionController.text.isEmpty ||
                      selectedAlmacenId == null
                  ? null
                  : () async {
                      Navigator.pop(context);
                      await _createTpv(
                        denominacionController.text,
                        selectedAlmacenId!,
                      );
                    },
              icon: const Icon(Icons.add),
              label: const Text('Crear TPV'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Crea un nuevo TPV
  Future<void> _createTpv(String denominacion, int idAlmacen) async {
    try {
      final success = await TpvService.createTpv(
        denominacion: denominacion,
        idAlmacen: idAlmacen,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('TPV "$denominacion" creado exitosamente'),
              backgroundColor: Colors.green,
            ),
          );
          _refreshData();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error al crear el TPV'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      print('❌ Error creando TPV: $e');
    }
  }
}
