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
  bool _canEditPricePermission = false;
  final Set<int> _updatingPricePermission = {};

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
      NavigationGuard.canPerformAction('vendor.edit_price_permission'),
    ]);

    if (!mounted) return;
    setState(() {
      _canAssignTpv = permissions[0];
      _canUnassignTpv = permissions[1];
      _canDeleteVendor = permissions[2];
      _canEditPricePermission = permissions[3];
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
    final sinTpv = totalVendedores - vendedoresConTpv;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 600;
          if (isNarrow) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStatItem(
                  label: 'Total Vendedores',
                  value: totalVendedores.toString(),
                  icon: Icons.people_alt_outlined,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 10),
                _buildStatItem(
                  label: 'Con TPV',
                  value: vendedoresConTpv.toString(),
                  icon: Icons.point_of_sale_outlined,
                  color: AppColors.success,
                ),
                const SizedBox(height: 10),
                _buildStatItem(
                  label: 'Sin TPV',
                  value: sinTpv.toString(),
                  icon: Icons.person_off_outlined,
                  color: Colors.orange,
                ),
              ],
            );
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _buildStatItem(
                    label: 'Total Vendedores',
                    value: totalVendedores.toString(),
                    icon: Icons.people_alt_outlined,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatItem(
                    label: 'Con TPV',
                    value: vendedoresConTpv.toString(),
                    icon: Icons.point_of_sale_outlined,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatItem(
                    label: 'Sin TPV',
                    value: sinTpv.toString(),
                    icon: Icons.person_off_outlined,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatItem({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
              Icon(icon, color: color, size: 18),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              height: 1,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
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
            const SizedBox(height: 12),
            _buildPricePermissionToggle(vendedor),
          ],
        ),
      ),
    );
  }

  Widget _buildPricePermissionToggle(Map<String, dynamic> vendedor) {
    final vendedorId = vendedor['id'] as int?;
    if (vendedorId == null) return const SizedBox.shrink();

    final canCustomize = vendedor['permitir_customizar_precio_venta'] == true;
    final isUpdating = _updatingPricePermission.contains(vendedorId);
    final accent = canCustomize ? AppColors.success : AppColors.textSecondary;
    final canEdit = _canEditPricePermission && !isUpdating;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: canEdit
            ? () =>
                _togglePriceCustomizationPermission(vendedor, !canCustomize)
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: canCustomize
                ? AppColors.success.withOpacity(0.06)
                : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: canCustomize
                  ? AppColors.success.withOpacity(0.25)
                  : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.price_change_outlined,
                  size: 18,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Cambio de precio',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      canCustomize ? 'Habilitado' : 'Deshabilitado',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: accent,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isUpdating)
                SizedBox(
                  width: 36,
                  height: 20,
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accent,
                      ),
                    ),
                  ),
                )
              else
                _buildPillSwitch(
                  value: canCustomize,
                  onChanged: _canEditPricePermission
                      ? (value) =>
                          _togglePriceCustomizationPermission(vendedor, value)
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPillSwitch({
    required bool value,
    ValueChanged<bool>? onChanged,
  }) {
    final activeColor = AppColors.success;
    final disabled = onChanged == null;
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: disabled ? null : () => onChanged(!value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: 42,
            height: 22,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: value
                  ? activeColor
                  : AppColors.textSecondary.withOpacity(0.35),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Stack(
              children: [
                AnimatedAlign(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  alignment:
                      value ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Icon(
                      value ? Icons.check_rounded : Icons.close_rounded,
                      size: 12,
                      color: value
                          ? activeColor
                          : AppColors.textSecondary.withOpacity(0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
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

  Future<void> _togglePriceCustomizationPermission(
    Map<String, dynamic> vendedor,
    bool value,
  ) async {
    if (!_canEditPricePermission) {
      NavigationGuard.showActionDeniedMessage(
        context,
        'Editar permiso de precio',
      );
      return;
    }

    final vendedorId = vendedor['id'] as int?;
    if (vendedorId == null) return;

    final previousValue = vendedor['permitir_customizar_precio_venta'] == true;

    setState(() {
      _updatingPricePermission.add(vendedorId);
      _updateVendorPricePermission(vendedorId, value);
    });

    final success = await VendedorService.updatePriceCustomizationPermission(
      vendedorId: vendedorId,
      canCustomize: value,
    );

    if (!mounted) return;

    if (!success) {
      setState(() {
        _updateVendorPricePermission(vendedorId, previousValue);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo actualizar el permiso de precio'),
          backgroundColor: Colors.red,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Permiso para cambiar precio activado'
                : 'Permiso para cambiar precio desactivado',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    }

    setState(() {
      _updatingPricePermission.remove(vendedorId);
    });
  }

  void _updateVendorPricePermission(int vendedorId, bool value) {
    final index = _vendedores.indexWhere((v) => v['id'] == vendedorId);
    if (index == -1) return;

    final updated = Map<String, dynamic>.from(_vendedores[index]);
    updated['permitir_customizar_precio_venta'] = value;

    final updatedList = List<Map<String, dynamic>>.from(_vendedores);
    updatedList[index] = updated;
    _vendedores = updatedList;
  }
}
