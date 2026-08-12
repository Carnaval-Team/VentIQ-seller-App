// Punto de entrada con conditional import.
// En Web resuelve a web_reload_web.dart (dart:html); en el resto, al stub.
export 'web_reload_stub.dart' if (dart.library.html) 'web_reload_web.dart';
