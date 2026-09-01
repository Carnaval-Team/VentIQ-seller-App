import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/update_service.dart';

/// Helper reutilizable para mostrar los diálogos de actualización.
class UpdateDialogHelper {
  /// Diálogo que se muestra cuando hay una nueva versión disponible.
  static void showUpdateAvailableDialog(
    BuildContext context,
    Map<String, dynamic> updateInfo,
  ) {
    final bool isObligatory = updateInfo['obligatoria'] == true;
    final String newVersion =
        updateInfo['version_disponible']?.toString() ?? 'Desconocida';
    final String currentVersion =
        updateInfo['current_version']?.toString() ?? 'Desconocida';

    showDialog(
      context: context,
      barrierDismissible: !isObligatory,
      builder: (context) => WillPopScope(
        onWillPop: () async => !isObligatory,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(
                isObligatory ? Icons.warning : Icons.system_update,
                color: isObligatory ? Colors.orange : Colors.blue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isObligatory
                      ? 'Actualización Obligatoria'
                      : 'Nueva Versión Disponible',
                  style: const TextStyle(fontSize: 16),
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
              Text('Nueva versión disponible: $newVersion'),
              Text('Versión actual: $currentVersion'),
              const SizedBox(height: 16),
              if (isObligatory)
                const Text(
                  'Esta actualización es obligatoria y debe instalarse para continuar usando la aplicación.',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                )
              else
                const Text(
                  'Se recomienda actualizar para obtener las últimas mejoras y correcciones.',
                ),
            ],
          ),
          actions: [
            if (!isObligatory)
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Más tarde'),
              ),
            ElevatedButton(
              onPressed: () async {
                final bool ok = await UpdateService.openUpdate(updateInfo);
                if (!ok && context.mounted) {
                  Navigator.of(context).pop();
                  showManualDownloadDialog(context, updateInfo);
                  return;
                }
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('📱 Actualización iniciada'),
                      backgroundColor: Colors.blue,
                      duration: Duration(seconds: 4),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isObligatory ? Colors.orange : Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: Text(kIsWeb ? 'Actualizar ahora' : 'Descargar'),
            ),
          ],
        ),
      ),
    );
  }

  /// Diálogo informativo cuando no hay actualizaciones.
  static void showNoUpdateDialog(
    BuildContext context,
    Map<String, dynamic> updateInfo,
  ) {
    final String currentVersion =
        updateInfo['current_version']?.toString() ?? 'Desconocida';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Aplicación Actualizada',
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
            Text('Versión actual: $currentVersion'),
            const SizedBox(height: 8),
            const Text(
              'Tu aplicación está actualizada con la última versión disponible.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  /// Diálogo de error cuando falla la verificación.
  static void showUpdateErrorDialog(BuildContext context, [Object? _]) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error, color: Colors.red),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Error de Verificación',
                style: TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No se pudo verificar si hay actualizaciones disponibles. Inténtalo más tarde.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  /// Diálogo para copiar manualmente el enlace de descarga.
  static void showManualDownloadDialog(
    BuildContext context,
    Map<String, dynamic> updateInfo,
  ) {
    final String url = kIsWeb
        ? (updateInfo['download_url_web']?.toString() ?? '')
        : (updateInfo['download_url_apk']?.toString() ?? '');

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
            const Text(
              'No se pudo abrir automáticamente el enlace de actualización.',
            ),
            const SizedBox(height: 16),
            if (url.isEmpty)
              const Text(
                'No hay una URL de descarga configurada. Contacta al soporte técnico.',
              )
            else ...[
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
                  url,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
          if (url.isNotEmpty)
            ElevatedButton(
              onPressed: () async {
                try {
                  await Clipboard.setData(ClipboardData(text: url));
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
