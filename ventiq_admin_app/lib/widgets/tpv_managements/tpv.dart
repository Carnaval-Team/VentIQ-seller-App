import 'package:flutter/material.dart';
import '../../services/tpv_service.dart';
import '../../config/app_colors.dart';
import '../../screens/tpv_prices_screen.dart';
import 'tpv_details.dart';
import '../../utils/navigation_guard.dart';

/// Widget principal para la lista de TPVs
/// Responsabilidades:
/// - Cargar y mostrar TPVs
/// - Filtrar por búsqueda
/// - Mostrar estadísticas
/// - Delegar acciones a TpvDetails
class TpvListWidget extends StatefulWidget {
  final String searchQuery;
  final VoidCallback onRefresh;

  const TpvListWidget({
    Key? key,
    required this.searchQuery,
    required this.onRefresh,
  }) : super(key: key);

  @override
  State<TpvListWidget> createState() => _TpvListWidgetState();
}

class _TpvListWidgetState extends State<TpvListWidget> {
  List<Map<String, dynamic>> _tpvs = [];
  bool _isLoading = true;

  bool _canEditTpv = false;
  bool _canDeleteTpv = false;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    _loadTpvs();
  }

  Future<void> _loadPermissions() async {
    final permissions = await Future.wait([
      NavigationGuard.canPerformAction('tpv.edit'),
      NavigationGuard.canPerformAction('tpv.delete'),
    ]);

    if (!mounted) return;
    setState(() {
      _canEditTpv = permissions[0];
      _canDeleteTpv = permissions[1];
    });
  }

  @override
  void didUpdateWidget(TpvListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      setState(() {}); // Refrescar filtrado
    }
  }

  Future<void> _loadTpvs() async {
    setState(() => _isLoading = true);
    try {
      final tpvs = await TpvService.getTpvsByStore();
      if (mounted) {
        setState(() {
          _tpvs = tpvs;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error cargando TPVs: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Map<String, dynamic>> get _filteredTpvs {
    if (widget.searchQuery.isEmpty) return _tpvs;
    return _tpvs.where((tpv) {
      final denominacion = tpv['denominacion']?.toString().toLowerCase() ?? '';
      final query = widget.searchQuery.toLowerCase();
      return denominacion.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [_buildStatsCard(), Expanded(child: _buildTpvsList())],
    );
  }

  Widget _buildStatsCard() {
    final totalTpvs = _tpvs.length;
    final tpvsConVendedor =
        _tpvs.where((t) {
          try {
            final vendedores = t['vendedor'] as List<dynamic>?;
            return vendedores != null && vendedores.isNotEmpty;
          } catch (e) {
            return false;
          }
        }).length;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            'Total TPVs',
            totalTpvs.toString(),
            Icons.point_of_sale,
          ),
          _buildStatItem(
            'Con Vendedor',
            tpvsConVendedor.toString(),
            Icons.person,
          ),
          _buildStatItem(
            'Disponibles',
            (totalTpvs - tpvsConVendedor).toString(),
            Icons.check_circle,
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

  Widget _buildTpvsList() {
    final filteredTpvs = _filteredTpvs;

    if (filteredTpvs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.point_of_sale, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              widget.searchQuery.isEmpty
                  ? 'No hay TPVs registrados'
                  : 'No se encontraron TPVs',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: filteredTpvs.length,
      itemBuilder: (context, index) => _buildTpvCard(filteredTpvs[index]),
    );
  }

  Widget _buildTpvCard(Map<String, dynamic> tpv) {
    final vendedores = tpv['vendedor'] as List<dynamic>? ?? [];
    final hasVendedor = vendedores.isNotEmpty;

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
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.point_of_sale, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tpv['denominacion'] ?? 'Sin nombre',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (tpv['descripcion'] != null)
                        Text(
                          tpv['descripcion'],
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) => _handleTpvAction(value, tpv),
                  itemBuilder:
                      (context) => [
                        if (_canEditTpv)
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit, size: 20),
                                SizedBox(width: 8),
                                Text('Editar'),
                              ],
                            ),
                          ),
                        const PopupMenuItem(
                          value: 'prices',
                          child: Row(
                            children: [
                              Icon(Icons.attach_money, size: 20),
                              SizedBox(width: 8),
                              Text('Gestionar Precios'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'stats',
                          child: Row(
                            children: [
                              Icon(Icons.analytics, size: 20),
                              SizedBox(width: 8),
                              Text('Estadísticas'),
                            ],
                          ),
                        ),
                        if (_canDeleteTpv)
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
                _buildInfoChip('ID: ${tpv['id']}', Icons.tag),
                if (tpv['almacen'] != null)
                  _buildInfoChip(
                    'Almacén: ${tpv['almacen']['denominacion'] ?? 'Sin nombre'}',
                    Icons.warehouse,
                    color: AppColors.info,
                  ),
                _buildInfoChip(
                  hasVendedor
                      ? '${vendedores.length} Vendedor(es)'
                      : 'Sin vendedor',
                  hasVendedor ? Icons.person : Icons.person_off,
                  color: hasVendedor ? AppColors.success : Colors.orange,
                ),
              ],
            ),
            if (hasVendedor) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              ...vendedores.map((vendedor) {
                final trabajador =
                    vendedor['trabajador'] as Map<String, dynamic>?;
                if (trabajador != null) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(Icons.person, size: 16, color: AppColors.info),
                        const SizedBox(width: 8),
                        Text(
                          '${trabajador['nombres']} ${trabajador['apellidos'] ?? ''}',
                          style: TextStyle(color: AppColors.info, fontSize: 13),
                        ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              }).toList(),
            ],
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

  void _handleTpvAction(String action, Map<String, dynamic> tpv) {
    switch (action) {
      case 'edit':
        if (!_canEditTpv) {
          NavigationGuard.showActionDeniedMessage(context, 'Editar TPV');
          return;
        }
        TpvDetailsDialog.showEditDialog(
          context: context,
          tpv: tpv,
          onSuccess: () {
            _loadTpvs();
            widget.onRefresh();
          },
        );
        break;
      case 'prices':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) => TpvPricesScreen(
                  tpvId:
                      tpv['id'] is int
                          ? tpv['id']
                          : int.parse(tpv['id'].toString()),
                ),
          ),
        );
        break;
      case 'stats':
        TpvDetailsDialog.showStatsDialog(context: context, tpv: tpv);
        break;
      case 'delete':
        if (!_canDeleteTpv) {
          NavigationGuard.showActionDeniedMessage(context, 'Eliminar TPV');
          return;
        }
        TpvDetailsDialog.showDeleteConfirmation(
          context: context,
          tpv: tpv,
          onSuccess: () {
            _loadTpvs();
            widget.onRefresh();
          },
        );
        break;
    }
  }
}
