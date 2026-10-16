import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/services/tutorial_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('TutorialService · cliente', () {
    test('se muestra la primera vez y no tras marcarlo visto', () async {
      const uuid = 'user-1';
      expect(await TutorialService.debeMostrarCliente(uuid), isTrue);
      expect(await TutorialService.estadoCliente(uuid), isNull);

      await TutorialService.marcarVistoCliente(uuid);

      expect(await TutorialService.debeMostrarCliente(uuid), isFalse);
      expect(await TutorialService.estadoCliente(uuid), TutorialService.valorVisto);
    });

    test('omitir también impide que se repita', () async {
      const uuid = 'user-2';
      await TutorialService.marcarOmitidoCliente(uuid);

      expect(await TutorialService.debeMostrarCliente(uuid), isFalse);
      expect(
        await TutorialService.estadoCliente(uuid),
        TutorialService.valorOmitido,
      );
    });

    test('reiniciar lo vuelve a habilitar', () async {
      const uuid = 'user-3';
      await TutorialService.marcarVistoCliente(uuid);
      expect(await TutorialService.debeMostrarCliente(uuid), isFalse);

      await TutorialService.reiniciarCliente(uuid);

      expect(await TutorialService.debeMostrarCliente(uuid), isTrue);
      expect(await TutorialService.estadoCliente(uuid), isNull);
    });

    test('sin uuid no se muestra', () async {
      expect(await TutorialService.debeMostrarCliente(''), isFalse);
    });
  });

  group('TutorialService · admin por entidad', () {
    test('es independiente por entidad y por usuario', () async {
      const uuid = 'owner-1';
      expect(await TutorialService.debeMostrarAdmin(uuid, 7), isTrue);

      await TutorialService.marcarVistoAdmin(uuid, 7);

      // La misma entidad ya no lo muestra; otra entidad sí (entidad nueva).
      expect(await TutorialService.debeMostrarAdmin(uuid, 7), isFalse);
      expect(await TutorialService.debeMostrarAdmin(uuid, 8), isTrue);
      // Otro usuario con la misma entidad tampoco lo ha visto.
      expect(await TutorialService.debeMostrarAdmin('owner-2', 7), isTrue);
    });

    test('reiniciar por entidad no afecta a las demás', () async {
      const uuid = 'owner-3';
      await TutorialService.marcarVistoAdmin(uuid, 1);
      await TutorialService.marcarVistoAdmin(uuid, 2);

      await TutorialService.reiniciarAdmin(uuid, 1);

      expect(await TutorialService.debeMostrarAdmin(uuid, 1), isTrue);
      expect(await TutorialService.debeMostrarAdmin(uuid, 2), isFalse);
    });
  });

  test('las claves incluyen versión, usuario y entidad', () {
    expect(
      TutorialService.claveCliente('abc'),
      'flow_tutorial_cliente_${TutorialService.version}_abc',
    );
    expect(
      TutorialService.claveAdmin('abc', 12),
      'flow_tutorial_admin_${TutorialService.version}_abc_12',
    );
    expect(
      TutorialService.claveCliente('abc'),
      isNot(TutorialService.claveAdmin('abc', 0)),
    );
  });
}
