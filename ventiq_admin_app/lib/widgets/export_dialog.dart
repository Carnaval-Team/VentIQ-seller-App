import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/export_service.dart';

class ExportDialog extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onPdfSelected;
  final VoidCallback? onExcelSelected;

  const ExportDialog({
    super.key,
    required this.title,
    required this.subtitle,
    this.onPdfSelected,
    this.onExcelSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icono principal
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(50),
              ),
              child: const Icon(
                Icons.file_download_outlined,
                size: 32,
                color: AppColors.primary,
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Título
            Text(
              'Exportar Inventario',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 8),
            
            // Información del reporte
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.warehouse_outlined,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Texto de selección
            const Text(
              'Selecciona el formato de exportación:',
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 20),
            
            // Botones de formato
            Row(
              children: [
                // Botón PDF
                Expanded(
                  child: _ExportFormatButton(
                    icon: Icons.picture_as_pdf,
                    label: 'PDF',
                    description: 'Doc. portable',
                    color: Colors.red,
                    onTap: () {
                      Navigator.of(context).pop();
                      onPdfSelected?.call();
                    },
                  ),
                ),
                
                const SizedBox(width: 12),
                
                // Botón Excel
                Expanded(
                  child: _ExportFormatButton(
                    icon: Icons.table_chart,
                    label: 'Excel',
                    description: 'Hoja de cálculo',
                    color: Colors.green,
                    onTap: () {
                      Navigator.of(context).pop();
                      onExcelSelected?.call();
                    },
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Botón cancelar
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportFormatButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final VoidCallback onTap;

  const _ExportFormatButton({
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: color.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(12),
            color: color.withOpacity(0.05),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 24,
                  color: color,
                ),
              ),
              
              const SizedBox(height: 8),
              
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              
              const SizedBox(height: 4),
              
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: color.withOpacity(0.8),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Función helper para mostrar el diálogo de exportación
Future<void> showExportDialog({
  required BuildContext context,
  required String warehouseName,
  required String zoneName,
  required VoidCallback onPdfSelected,
  required VoidCallback onExcelSelected,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext context) {
      return ExportDialog(
        title: warehouseName,
        subtitle: zoneName,
        onPdfSelected: onPdfSelected,
        onExcelSelected: onExcelSelected,
      );
    },
  );
}
