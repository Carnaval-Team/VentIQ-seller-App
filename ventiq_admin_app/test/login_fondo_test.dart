// Contrato del fondo del login web.
//
// Dos cosas que se rompen en silencio:
//   1. El asset declarado en `pubspec.yaml` pero inexistente en disco (o al
//      revés): la app compila y la imagen simplemente no aparece.
//   2. La foto sin velo: el texto blanco cae sobre zonas claras y deja de
//      leerse, pero ningún test de layout lo detecta.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const rutaImagen = 'assets/images/login_bg.jpg';

  group('el fondo del login web existe y está declarado', () {
    test('el archivo está en disco', () {
      final fichero = File(rutaImagen);
      expect(
        fichero.existsSync(),
        isTrue,
        reason: 'falta $rutaImagen: sin él el panel se queda solo en azul',
      );
    });

    test('está declarado en pubspec', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains(rutaImagen));
    });

    test('pesa lo razonable para un fondo', () {
      final bytes = File(rutaImagen).lengthSync();
      // El PNG original pesaba 1,9 MB. Un fondo de login por encima de ~400 KB
      // se nota en el arranque, sobre todo en web.
      expect(
        bytes,
        lessThan(400 * 1024),
        reason:
            'el fondo pesa ${(bytes / 1024).round()} KB: conviene recomprimirlo',
      );
    });

    test('es un JPEG válido', () {
      final bytes = File(rutaImagen).readAsBytesSync();
      // Firma SOI de JPEG: FF D8 FF.
      expect(
        bytes.sublist(0, 3),
        [0xFF, 0xD8, 0xFF],
        reason: 'la extensión dice .jpg pero el contenido no lo es',
      );
    });
  });

  group('el panel de marca usa la foto con velo', () {
    test('la imagen se pinta como fondo del panel', () {
      final fuente = File('lib/screens/login_screen.dart').readAsStringSync();
      expect(fuente, contains('assets/images/login_bg.jpg'));
      expect(
        fuente,
        contains('errorBuilder'),
        reason:
            'si el asset falta, el panel debe seguir siendo azul y legible en '
            'vez de reventar',
      );
    });

    test('hay un velo encima de la foto', () {
      final fuente = File('lib/screens/login_screen.dart').readAsStringSync();
      // El velo es el degradado con alfa alto sobre el azul corporativo.
      expect(
        fuente,
        contains('Color(0xF2123A6B)'),
        reason:
            'sin el velo el texto blanco se pierde sobre las zonas claras de '
            'la foto',
      );
      expect(fuente, contains('StackFit.expand'));
    });
  });
}