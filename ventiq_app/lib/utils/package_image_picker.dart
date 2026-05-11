// Punto de entrada unificado para elegir imágenes del paquete.
// En Flutter Web exporta la versión basada en dart:html; en mobile/desktop
// exporta el stub (que no debe llamarse: el caller usa image_picker allí).

export 'package_image_picker_stub.dart'
    if (dart.library.html) 'package_image_picker_web.dart';
