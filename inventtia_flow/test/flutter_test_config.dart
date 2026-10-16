import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Configuración común a **todos** los archivos de `test/`.
///
/// POR QUE EXISTE
///   `AppTheme.light` arma el `TextTheme` con `GoogleFonts.interTextTheme()`, y
///   `google_fonts` descarga Inter en tiempo de ejecución. En un test esa
///   descarga no puede funcionar (el binding devuelve 400 a toda petición HTTP)
///   y `google_fonts` lanza un error **asíncrono**: el runner se lo adjudica al
///   test que esté corriendo cuando llega, que puede ser cualquiera.
///
///   Consecuencia: la suite era intermitente. `appbar_contraste_test` (y
///   `dropdown_sin_solape_test`, que también usan `AppTheme.light`) pasan
///   aislados y fallan dentro del conjunto según el orden con el que se crucen.
///   Se apaga la descarga y se filtra ese error concreto, que es ruido del
///   entorno de test y no un fallo del producto.
///
/// Lo que **no** hace: silenciar nada más. Cualquier otro error sigue llegando
/// al runner tal cual.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // El binding primero: es él quien instala su propio `FlutterError.onError`, así
  // que el filtro tiene que ir después o lo pisaría.
  TestWidgetsFlutterBinding.ensureInitialized();

  GoogleFonts.config.allowRuntimeFetching = false;

  final original = FlutterError.onError;
  FlutterError.onError = (detalles) {
    if (_esLaFuenteQueNoSePuedeCargar(detalles.exception)) {
      debugPrint(
        '[test] Inter no se puede descargar en un test; se ignora ese fallo.',
      );
      return;
    }
    original?.call(detalles);
  };

  await testMain();
}

/// Reconoce **solo** el fallo de `google_fonts` al no poder traer Inter.
bool _esLaFuenteQueNoSePuedeCargar(Object? error) {
  final texto = error.toString();
  if (!texto.contains('Inter')) return false;
  return texto.contains('unable to load font') ||
      texto.contains('allowRuntimeFetching');
}
