import 'package:flutter/material.dart';
import '../../services/tpv_service.dart';
import '../../config/app_colors.dart';

/// Clase con métodos estáticos para diálogos de TPV
/// Responsabilidades:
/// - Diálogo de edición
/// - Diálogo de estadísticas
/// - Diálogo de confirmación de eliminación
class TpvDetailsDialog {
  /// Muestra diálogo para editar TPV
  static void showEditDialog({
    required BuildContext context,
    required Map<String, dynamic> tpv,
    required VoidCallback onSuccess,
  }) {
    final denominacionController = TextEditingController(text: tpv['denominacion']);
    final descripcionController = TextEditingController(text: tpv['descripcion']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.edit, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text('Editar TPV'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: denominacionController,
              decoration: const InputDecoration(
                labelText: 'Denominación *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.point_of_sale),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descripcionController,
              decoration: const InputDecoration(
                labelText: 'Descripción',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
              ),
              maxLines: 2,
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
              if (denominacionController.text.isNotEmpty) {
                final success = await TpvService.updateTpv(
                  id: tpv['id'] is int ? tpv['id'] : int.parse(tpv['id'].toString()),
                  denominacion: denominacionController.text,
                  descripcion:
                      descripcionController.text.isEmpty ? null : descripcionController.text,
                );
                Navigator.pop(context);
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('TPV actualizado exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  onSuccess();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Error al actualizar TPV'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  /// Muestra diálogo con estadísticas del TPV
  static void showStatsDialog({
    required BuildContext context,
    required Map<String, dynamic> tpv,
  }) async {
    // Mostrar loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        title: Text('Cargando estadísticas...'),
        content: Center(
          heightFactor: 1,
          child: CircularProgressIndicator(),
        ),
      ),
    );

    try {
      final stats = await TpvService.getTpvStatistics(
        tpv['id'] is int ? tpv['id'] : int.parse(tpv['id'].toString()),
      );

      Navigator.pop(context); // Cerrar loading

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.analytics, color: AppColors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Estadísticas - ${tpv['denominacion']}',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatRow(
                context,
                'Precios activos:',
                '${stats['active_prices']}',
                Icons.attach_money,
                AppColors.success,
              ),
              const SizedBox(height: 8),
              _buildStatRow(
                context,
                'Productos únicos:',
                '${stats['unique_products']}',
                Icons.inventory,
                AppColors.primary,
              ),
              const SizedBox(height: 8),
              _buildStatRow(
                context,
                'Última venta:',
                stats['last_sale'] != null
                    ? DateTime.parse(stats['last_sale']).toString().split(' ')[0]
                    : 'Sin ventas',
                Icons.calendar_today,
                AppColors.info,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (e) {
      Navigator.pop(context); // Cerrar loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cargando estadísticas: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Muestra diálogo de confirmación para eliminar TPV
  static void showDeleteConfirmation({
    required BuildContext context,
    required Map<String, dynamic> tpv,
    required VoidCallback onSuccess,
  }) async {
    try {
      final tpvId = tpv['id'];
      if (tpvId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: ID de TPV no válido'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Validar si se puede eliminar
      final validation = await TpvService.validateTpvDeletion(
        tpvId is int ? tpvId : int.parse(tpvId.toString()),
      );

      if (!validation['can_delete']) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.warning, color: Colors.orange),
                const SizedBox(width: 8),
                const Text('No se puede eliminar'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Este TPV no puede ser eliminado por las siguientes razones:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ...(validation['reasons'] as List<dynamic>? ?? [])
                    .map<Widget>(
                      (reason) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• ', style: TextStyle(fontSize: 16)),
                            Expanded(child: Text(reason.toString())),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
        return;
      }

      // Mostrar confirmación de eliminación
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
                '¿Está seguro de eliminar el TPV "${tpv['denominacion']}"?',
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
                        Text('Eliminando TPV...'),
                      ],
                    ),
                  ),
                );

                final success = await TpvService.deleteTpv(
                  tpvId is int ? tpvId : int.parse(tpvId.toString()),
                );
                
                Navigator.pop(context); // Cerrar loading

                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('TPV eliminado exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  onSuccess();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Error al eliminar TPV'),
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
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Widget auxiliar para mostrar una fila de estadística
  static Widget _buildStatRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}