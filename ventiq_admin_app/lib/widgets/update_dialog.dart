import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_colors.dart';
import '../services/update_service.dart';

class UpdateDialog extends StatelessWidget {
  final Map<String, dynamic> updateInfo;

  const UpdateDialog({
    Key? key,
    required this.updateInfo,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool isObligatory = updateInfo['obligatoria'] == true;
    final String newVersion = updateInfo['version_disponible'] ?? 'Desconocida';
    final String currentVersion = updateInfo['current_version'] ?? 'Desconocida';
    final String description = updateInfo['descripcion'] ?? 'Nueva versión disponible';

    return WillPopScope(
      onWillPop: () async => !isObligatory,
      child: AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(
              isObligatory ? Icons.warning : Icons.system_update,
              color: isObligatory ? AppColors.error : AppColors.primary,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isObligatory ? 'Actualización Requerida' : 'Actualización Disponible',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isObligatory ? AppColors.error : AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Versión actual:',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      Text(
                        currentVersion,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Nueva versión:',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          newVersion,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.success,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              description,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
              ),
            ),
            if (isObligatory) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.error.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: AppColors.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Esta actualización es obligatoria para continuar usando la aplicación.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (!isObligatory)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Más tarde',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          ElevatedButton.icon(
            onPressed: () => _downloadUpdate(context),
            icon: const Icon(Icons.download, size: 18),
            label: Text(isObligatory ? 'Actualizar Ahora' : 'Descargar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isObligatory ? AppColors.error : AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  /// Descargar actualización
  Future<void> _downloadUpdate(BuildContext context) async {
    try {
      final Uri url = Uri.parse(UpdateService.downloadUrl);
      
      print('🔗 Intentando abrir URL: ${url.toString()}');
      
      // Intentar diferentes modos de lanzamiento
      bool launched = false;
      
      // Método 1: Intentar con navegador web
      try {
        launched = await launchUrl(
          url,
          mode: LaunchMode.externalApplication,
        );
        print('✅ Método 1 (externalApplication): $launched');
      } catch (e) {
        print('❌ Método 1 falló: $e');
      }
      
      // Método 2: Si falla, intentar con navegador interno
      if (!launched) {
        try {
          launched = await launchUrl(
            url,
            mode: LaunchMode.inAppWebView,
          );
          print('✅ Método 2 (inAppWebView): $launched');
        } catch (e) {
          print('❌ Método 2 falló: $e');
        }
      }
      
      // Método 3: Si falla, intentar modo plataforma
      if (!launched) {
        try {
          launched = await launchUrl(url);
          print('✅ Método 3 (default): $launched');
        } catch (e) {
          print('❌ Método 3 falló: $e');
        }
      }
      
      if (launched) {
        // Cerrar diálogo
        if (context.mounted) {
          Navigator.of(context).pop();
        }
        
        // Mostrar mensaje de confirmación
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📱 Descarga iniciada - Instala la nueva versión'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 4),
          ),
        );
      } else {
        // Si todos los métodos fallan, mostrar diálogo con URL para copiar
        _showManualDownloadDialog(context);
      }
      
    } catch (e) {
      print('❌ Error general abriendo enlace de descarga: $e');
      _showManualDownloadDialog(context);
    }
  }
  
  /// Mostrar diálogo para descarga manual
  void _showManualDownloadDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.download, color: Colors.blue),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Descarga Manual',
                style: TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('No se pudo abrir automáticamente el enlace de descarga.'),
            const SizedBox(height: 16),
            const Text('Copia este enlace y ábrelo en tu navegador:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: SelectableText(
                UpdateService.downloadUrl,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Cerrar diálogo manual
              Navigator.of(context).pop(); // Cerrar diálogo de actualización
            },
            child: const Text('Cerrar'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Intentar copiar al portapapeles
              try {
                await Clipboard.setData(ClipboardData(text: UpdateService.downloadUrl));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('📋 Enlace copiado al portapapeles'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                print('❌ Error copiando al portapapeles: $e');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Copiar Enlace'),
          ),
        ],
      ),
    );
  }
}
