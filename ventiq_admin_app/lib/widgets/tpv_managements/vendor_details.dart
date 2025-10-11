import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/vendedor_service.dart';
import '../../services/tpv_service.dart';
import '../../services/user_preferences_service.dart';
import '../../config/app_colors.dart';

/// Clase con métodos estáticos para diálogos de vendedores
/// Responsabilidades:
/// - Diálogo de asignar TPV
/// - Diálogo de reasignar TPV
/// - Diálogo de desasignar TPV
/// - Diálogo de eliminar vendedor
class VendorDetailsDialog {
  /// Muestra diálogo para asignar TPV a vendedor
  static void showAssignTpvDialog({
    required BuildContext context,
    required Map<String, dynamic> vendedor,
    required VoidCallback onSuccess,
  }) async {
    // Cargar TPVs disponibles
    final tpvsDisponibles = await TpvService.getTpvsDisponibles();

    if (tpvsDisponibles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay TPVs disponibles para asignar'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    Map<String, dynamic>? selectedTpv;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.add_circle, color: AppColors.success),
              const SizedBox(width: 8),
              const Text('Asignar TPV'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Selecciona un TPV para asignar al vendedor:',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<Map<String, dynamic>>(
                decoration: const InputDecoration(
                  labelText: 'TPV *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.point_of_sale),
                ),
                value: selectedTpv,
                items: tpvsDisponibles.map((tpv) {
                  return DropdownMenuItem(
                    value: tpv,
                    child: Text(tpv['denominacion']),
                  );
                }).toList(),
                onChanged: (value) => setState(() => selectedTpv = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: selectedTpv == null
                  ? null
                  : () async {
                      Navigator.pop(context);
                      final success = await VendedorService.asignarVendedorATpv(
                        vendedorId: vendedor['id'],
                        tpvId: selectedTpv!['id'],
                      );
                      if (success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('TPV asignado exitosamente'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        onSuccess();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Error al asignar TPV'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
              child: const Text('Asignar'),
            ),
          ],
        ),
      ),
    );
  }

  /// Muestra diálogo para reasignar vendedor a otro TPV
  static void showReassignTpvDialog({
    required BuildContext context,
    required Map<String, dynamic> vendedor,
    required VoidCallback onSuccess,
  }) async {
    final currentTpv = vendedor['tpv'] as Map<String, dynamic>?;
    final tpvsDisponibles = await TpvService.getTpvsDisponibles();

    // Filtrar el TPV actual
    final tpvsParaReasignar = tpvsDisponibles
        .where((tpv) => tpv['id'] != currentTpv?['id'])
        .toList();

    if (tpvsParaReasignar.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay otros TPVs disponibles para reasignar'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    Map<String, dynamic>? selectedTpv;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.swap_horiz, color: AppColors.warning),
              const SizedBox(width: 8),
              const Text('Reasignar Vendedor'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'TPV actual: ${currentTpv?['denominacion'] ?? 'Ninguno'}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<Map<String, dynamic>>(
                decoration: const InputDecoration(
                  labelText: 'Nuevo TPV *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.point_of_sale),
                ),
                value: selectedTpv,
                items: tpvsParaReasignar.map((tpv) {
                  return DropdownMenuItem(
                    value: tpv,
                    child: Text(tpv['denominacion']),
                  );
                }).toList(),
                onChanged: (value) => setState(() => selectedTpv = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: selectedTpv == null
                  ? null
                  : () async {
                      Navigator.pop(context);
                      final success = await VendedorService.asignarVendedorATpv(
                        vendedorId: vendedor['id'],
                        tpvId: selectedTpv!['id'],
                      );
                      if (success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Vendedor reasignado exitosamente'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        onSuccess();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Error al reasignar vendedor'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
              child: const Text('Reasignar'),
            ),
          ],
        ),
      ),
    );
  }

  /// Muestra diálogo de confirmación para desasignar vendedor de TPV
  static void showUnassignConfirmation({
    required BuildContext context,
    required Map<String, dynamic> vendedor,
    required VoidCallback onSuccess,
  }) {
    final trabajador = vendedor['trabajador'] as Map<String, dynamic>?;
    final nombre = '${trabajador?['nombres'] ?? ''} ${trabajador?['apellidos'] ?? ''}'.trim();
    final tpv = vendedor['tpv'] as Map<String, dynamic>?;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: AppColors.warning),
            const SizedBox(width: 8),
            const Text('Confirmar Desasignación'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¿Estás seguro de que deseas desasignar a $nombre del TPV "${tpv?['denominacion']}"?',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange[700]),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Esta acción eliminará la asignación pero mantendrá el historial',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final success = await VendedorService.desasignarVendedorDeTpv(
                  vendedor['id'],
                );
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Vendedor desasignado exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  onSuccess();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Error al desasignar vendedor'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
            child: const Text('Desasignar'),
          ),
        ],
      ),
    );
  }

  /// Muestra diálogo de confirmación para eliminar vendedor
  static void showDeleteConfirmation({
    required BuildContext context,
    required Map<String, dynamic> vendedor,
    required VoidCallback onSuccess,
  }) {
    final trabajador = vendedor['trabajador'] as Map<String, dynamic>?;
    final nombre = '${trabajador?['nombres'] ?? ''} ${trabajador?['apellidos'] ?? ''}'.trim();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: AppColors.error),
            const SizedBox(width: 8),
            const Text('Confirmar Eliminación'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¿Está seguro de eliminar al vendedor "$nombre"?',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.red[700]),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Esta acción no se puede deshacer',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              
              // Mostrar loading
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const AlertDialog(
                  content: Row(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 16),
                      Text('Eliminando vendedor...'),
                    ],
                  ),
                ),
              );

              try {
                final success = await VendedorService.deleteVendedor(
                  vendedor['id'],
                );
                
                Navigator.pop(context); // Cerrar loading

                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Vendedor eliminado exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  onSuccess();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Error al eliminar vendedor'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } catch (e) {
                Navigator.pop(context); // Cerrar loading
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}