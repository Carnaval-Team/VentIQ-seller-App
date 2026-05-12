// Punto de entrada unificado para descargar PDFs.
// En Flutter Web usa dart:html; en mobile/desktop usa el stub (que no debe llamarse).

export 'pdf_download_stub.dart'
    if (dart.library.html) 'pdf_download_web.dart';
