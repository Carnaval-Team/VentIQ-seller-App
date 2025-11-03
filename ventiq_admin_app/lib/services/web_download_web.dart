// Implementación para web
import 'dart:html' as html;
import 'dart:typed_data';

void downloadFileWeb(Uint8List bytes, String fileName, String mimeType) {
  try {
    // Normalizar MIME type para PDFs
    final normalizedMimeType = mimeType == 'application/pdf' 
        ? 'application/pdf' 
        : mimeType;
    
    // Crear blob con MIME type correcto
    final blob = html.Blob([bytes], normalizedMimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    
    // Crear elemento anchor
    final anchor = html.AnchorElement()
      ..href = url
      ..download = fileName
      ..style.display = 'none';
    
    // Agregar temporalmente al DOM (requerido por algunos navegadores)
    html.document.body!.append(anchor);
    
    // Trigger download
    anchor.click();
    
    // Limpiar después de un delay para asegurar compatibilidad
    Future.delayed(const Duration(milliseconds: 100), () {
      anchor.remove();
      html.Url.revokeObjectUrl(url);
    });
    
  } catch (e) {
    print('Error en descarga web: $e');
    // Fallback: intentar abrir en nueva ventana
    _fallbackDownload(bytes, fileName, mimeType);
  }
}

/// Método de respaldo para navegadores problemáticos
void _fallbackDownload(Uint8List bytes, String fileName, String mimeType) {
  try {
    final blob = html.Blob([bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    
    // Abrir en nueva ventana como fallback
    html.window.open(url, '_blank');
    
    // Limpiar después de un delay más largo
    Future.delayed(const Duration(seconds: 2), () {
      html.Url.revokeObjectUrl(url);
    });
  } catch (e) {
    print('Error en fallback de descarga: $e');
    // Último recurso: mostrar URL de datos
    _dataUrlFallback(bytes, fileName, mimeType);
  }
}

/// Último recurso usando data URL
void _dataUrlFallback(Uint8List bytes, String fileName, String mimeType) {
  try {
    // Para archivos pequeños, usar data URL
    if (bytes.length < 10 * 1024 * 1024) { // Límite de 10MB
      final base64 = html.window.btoa(String.fromCharCodes(bytes));
      final dataUrl = 'data:$mimeType;base64,$base64';
      
      final anchor = html.AnchorElement()
        ..href = dataUrl
        ..download = fileName
        ..style.display = 'none';
      
      html.document.body!.append(anchor);
      anchor.click();
      anchor.remove();
    } else {
      print('Archivo demasiado grande para data URL fallback');
    }
  } catch (e) {
    print('Error en data URL fallback: $e');
  }
}
