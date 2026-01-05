import 'package:flutter/material.dart';
import '../../services/vendedor_service.dart';
import '../../config/app_colors.dart';
import 'vendor_details.dart';
import '../../utils/navigation_guard.dart';

/// Widget principal para la lista de vendedores
/// Responsabilidades:
/// - Cargar y mostrar vendedores
/// - Filtrar por búsqueda
/// - Mostrar estadísticas
/// - Delegar acciones a VendorDetails
class VendorListWidget extends StatefulWidget {
  final String searchQuery;
  final VoidCallback onRefresh;

  const VendorListWidget({
    Key? key,
    required this.searchQuery,
    required this.onRefresh,
  }) : super(key: key);

  @override
  State<VendorListWidget> createState() => _VendorListWidgetState();
}

class _VendorListWidgetState extends State<VendorListWidget> {
  List<Map<String, dynamic>> _vendedores = [];
  bool _isLoading = true;

  bool _canAssignTpv = false;
  bool _canUnassignTpv = false;
  bool _canDeleteVendor = false;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    _loadVendedores();
  }

  Future<void> _loadPermissions() async {
    final permissions = await Future.wait([
      NavigationGuard.canPerformAction('vendor.assign_tpv'),
      NavigationGuard.canPerformAction('vendor.unassign_tpv'),
      NavigationGuard.canPerformAction('vendor.delete'),
    ]);

    if (!mounted) return;
    setState(() {
      _canAssignTpv = permissions[0];
      _canUnassignTpv = permissions[1];
      _canDeleteVendor = permissions[2];
    });
  }

  @override
  void didUpdateWidget(VendorListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      setState(() {}); // Refrescar filtrado
    }
  }

  Future<void> _loadVendedores() async {
    setState(() => _isLoading = true);
    try {
      final vendedores = await VendedorService.getVendedoresByStore();
      if (mounted) {
        setState(() {
          _vendedores = vendedores;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error cargando vendedores: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Map<String, dynamic>> get _filteredVendedores {
    if (widget.searchQuery.isEmpty) return _vendedores;
    return _vendedores.where((vendedor) {
      final trabajador = vendedor['trabajador'] as Map<String, dynamic>?;
      if (trabajador == null) return false;

      final nombre =
          '${trabajador['nombres'] ?? ''} ${trabajador['apellidos'] ?? ''}'
              .toLowerCase();
      final query = widget.searchQuery.toLowerCase();
      return nombre.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [_buildStatsCard(), Expanded(child: _buildVendedoresList())],
    );
  }

  Widget _buildStatsCard() {
    final totalVendedores = _vendedores.length;
    final vendedoresConTpv =
        _vendedores.where((v) => v['id_tpv'] != null).length;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.success, AppColors.success.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.success.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('Total', totalVendedores.toString(), Icons.people),
          _buildStatItem(
            'Con TPV',
            vendedoresConTpv.toString(),
            Icons.point_of_sale,
          ),
          _buildStatItem(
            'Sin TPV',
            (totalVendedores - vendedoresConTpv).toString(),
            Icons.person_off,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildVendedoresList() {
    final filteredVendedores = _filteredVendedores;

    if (filteredVendedores.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              widget.searchQuery.isEmpty
                  ? 'No hay vendedores registrados'
                  : 'No se encontraron vendedores',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: filteredVendedores.length,
      itemBuilder:
          (context, index) => _buildVendedorCard(filteredVendedores[index]),
    );
  }

  Widget _buildVendedorCard(Map<String, dynamic> vendedor) {
    final trabajador = vendedor['trabajador'] as Map<String, dynamic>?;
    final tpv = vendedor['tpv'] as Map<String, dynamic>?;
    final hasTpv = tpv != null;

    final nombre =
        trabajador != null
            ? '${trabajador['nombres'] ?? ''} ${trabajador['apellidos'] ?? ''}'
            : 'Sin nombre';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.person, color: AppColors.success),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (trabajador?['id_roll'] != null)
                        Text(
                          'ID Trabajador: ${trabajador!['id']}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) => _handleVendedorAction(value, vendedor),
                  itemBuilder:
                      (context) => [
                        if (hasTpv && _canAssignTpv)
                          const PopupMenuItem(
                            value: 'reassign',
                            child: Row(
                              children: [
                                Icon(Icons.swap_horiz, size: 20),
                                SizedBox(width: 8),
                                Text('Reasignar TPV'),
                              ],
                            ),
                          ),
                        if (hasTpv && _canUnassignTpv)
                          const PopupMenuItem(
                            value: 'unassign',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.remove_circle,
                                  size: 20,
                                  color: Colors.orange,
                                ),
                                SizedBox(width: 8),
                                Text('Desasignar TPV'),
                              ],
                            ),
                          ),
                        if (!hasTpv && _canAssignTpv)
                          const PopupMenuItem(
                            value: 'assign',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.add_circle,
                                  size: 20,
                                  color: Colors.green,
                                ),
                                SizedBox(width: 8),
                                Text('Asignar TPV'),
                              ],
                            ),
                          ),
                        if (_canDeleteVendor)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, size: 20, color: Colors.red),
                                SizedBox(width: 8),
                                Text(
                                  'Eliminar',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                      ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildInfoChip('ID: ${vendedor['id']}', Icons.tag),
                if (hasTpv)
                  _buildInfoChip(
                    'TPV: ${tpv['denominacion']}',
                    Icons.point_of_sale,
                    color: AppColors.success,
                  )
                else
                  _buildInfoChip(
                    'Sin TPV asignado',
                    Icons.warning,
                    color: Colors.orange,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, IconData icon, {Color? color}) {
    final chipColor = color ?? AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: chipColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: chipColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _handleVendedorAction(String action, Map<String, dynamic> vendedor) {
    switch (action) {
      case 'assign':
        if (!_canAssignTpv) {
          NavigationGuard.showActionDeniedMessage(context, 'Asignar TPV');
          return;
        }
        VendorDetailsDialog.showAssignTpvDialog(
          context: context,
          vendedor: vendedor,
          onSuccess: () {
            _loadVendedores();
            widget.onRefresh();
          },
        );
        break;
      case 'reassign':
        if (!_canAssignTpv) {
          NavigationGuard.showActionDeniedMessage(context, 'Reasignar TPV');
          return;
        }
        VendorDetailsDialog.showReassignTpvDialog(
          context: context,
          vendedor: vendedor,
          onSuccess: () {
            _loadVendedores();
            widget.onRefresh();
          },
        );
        break;
      case 'unassign':
        if (!_canUnassignTpv) {
          NavigationGuard.showActionDeniedMessage(context, 'Desasignar TPV');
          return;
        }
        VendorDetailsDialog.showUnassignConfirmation(
          context: context,
          vendedor: vendedor,
          onSuccess: () {
            _loadVendedores();
            widget.onRefresh();
          },
        );
        break;
      case 'delete':
        if (!_canDeleteVendor) {
          NavigationGuard.showActionDeniedMessage(context, 'Eliminar vendedor');
          return;
        }
        VendorDetailsDialog.showDeleteConfirmation(
          context: context,
          vendedor: vendedor,
          onSuccess: () {
            _loadVendedores();
            widget.onRefresh();
          },
        );
        break;
    }
  }
}
