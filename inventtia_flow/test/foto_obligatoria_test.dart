import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/utils/foto_obligatoria.dart';

/// Regla de la foto obligatoria del local y del servicio.
///
/// Es la que decide si un formulario del panel puede guardar. Cubre los cuatro
/// casos reales: alta sin foto (bloquea), alta con foto elegida (deja pasar),
/// edición de algo que ya tenía foto (deja pasar sin volver a subirla) y edición
/// de un registro antiguo sin foto (bloquea hasta que se le ponga una).
void main() {
  group('tieneFoto', () {
    test('sin nada no hay foto', () {
      expect(tieneFoto(fotoGuardada: null, archivoElegido: false), isFalse);
    });

    test('una foto guardada cuenta como foto', () {
      expect(
        tieneFoto(
          fotoGuardada: 'https://x/locales/3.jpg',
          archivoElegido: false,
        ),
        isTrue,
      );
    });

    test(
      'un archivo recién elegido cuenta como foto, aunque no se haya subido',
      () {
        expect(tieneFoto(fotoGuardada: null, archivoElegido: true), isTrue);
      },
    );

    test('una URL en blanco no cuenta como foto', () {
      // Caso real: columnas antiguas con `''` en vez de `null`.
      expect(tieneFoto(fotoGuardada: '', archivoElegido: false), isFalse);
      expect(tieneFoto(fotoGuardada: '   ', archivoElegido: false), isFalse);
    });
  });

  group('errorFotoObligatoria', () {
    test('alta sin foto: mensaje con el nombre del campo', () {
      expect(
        errorFotoObligatoria(
          queEs: 'local',
          fotoGuardada: null,
          archivoElegido: false,
        ),
        'La foto del local es obligatoria',
      );
      expect(
        errorFotoObligatoria(
          queEs: 'servicio',
          fotoGuardada: null,
          archivoElegido: false,
        ),
        'La foto del servicio es obligatoria',
      );
    });

    test('no obliga a volver a subir una foto que ya está', () {
      expect(
        errorFotoObligatoria(
          queEs: 'servicio',
          fotoGuardada: 'https://x/servicios/7.jpg?v=1',
          archivoElegido: false,
        ),
        isNull,
      );
    });

    test('con archivo elegido no hay error', () {
      expect(
        errorFotoObligatoria(
          queEs: 'local',
          fotoGuardada: null,
          archivoElegido: true,
        ),
        isNull,
      );
    });

    test(
      'un registro antiguo sin foto no se puede guardar hasta ponérsela',
      () {
        expect(
          errorFotoObligatoria(
            queEs: 'local',
            fotoGuardada: '',
            archivoElegido: false,
          ),
          isNotNull,
        );
        expect(
          errorFotoObligatoria(
            queEs: 'local',
            fotoGuardada: '',
            archivoElegido: true,
          ),
          isNull,
        );
      },
    );
  });
}
