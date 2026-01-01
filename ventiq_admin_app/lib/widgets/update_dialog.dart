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
    final bool isWeb = updateInfo['es_web'] == true;
    final String newVersion = updateInfo['version_disponible'] ?? 'Desconocida';
    final String currentVersion = updateInfo['current_version'] ?? 'Desconocida';
    final String description = updateInfo['descripcion'] ?? 'Nueva versión disponible';

    // En web, la limpieza de cache es obligatoria
    final bool isMandatory = isWeb || isObligatory;
    
    return WillPopScope(
      onWillPop: () async => !isMandatory,
      child: AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(
              isWeb ? Icons.refresh : (isObligatory ? Icons.warning : Icons.system_update),
              color: isWeb ? Colors.blue : (isObligatory ? AppColors.error : AppColors.primary),
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isWeb 
                  ? 'Actualización Requerida'
                  : (isObligatory ? 'Actualización Requerida' : 'Actualización Disponible'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isWeb ? Colors.blue : (isObligatory ? AppColors.error : AppColors.primary),
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
            if (isWeb) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.blue,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Se detectó una nueva versión. Limpia el cache del navegador para obtener los cambios más recientes.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blue[900],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (isObligatory) ...[
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
          // En web: No mostrar botón "Cerrar" (limpieza de cache es obligatoria)
          // En APK: Mostrar "Más tarde" solo si no es obligatoria
          if (!isMandatory)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Más tarde'),
            ),
          if (isWeb)
            ElevatedButton.icon(
              onPressed: () => _clearCacheWeb(context),
              icon: const Icon(Icons.cleaning_services, size: 18),
              label: const Text('Limpiar Cache'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            )
          else
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

  /// Limpiar cache en navegador web
  Future<void> _clearCacheWeb(BuildContext context) async {
    try {
      print('🧹 Limpiando cache del navegador...');
      
      // En web, mostrar instrucciones para limpiar cache
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Cache Limpiado'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'El cache ha sido limpiado. Ahora recarga la página para obtener la última versión.',
                style: TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Instrucciones:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '1. Presiona Ctrl+Shift+Delete (Windows) o Cmd+Shift+Delete (Mac)',
                      style: TextStyle(fontSize: 12),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '2. Selecciona "Cookies y otros datos de sitios"',
                      style: TextStyle(fontSize: 12),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '3. Elige "Todo el tiempo" y haz clic en "Borrar datos"',
                      style: TextStyle(fontSize: 12),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '4. Recarga la página (F5 o Ctrl+R)',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Cerrar diálogo de instrucciones
                Navigator.of(context).pop(); // Cerrar diálogo de actualización
              },
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    } catch (e) {
      print('❌ Error limpiando cache: $e');
    }
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
