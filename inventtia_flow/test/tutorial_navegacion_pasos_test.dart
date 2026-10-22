import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/tutorial/tutorial_anchor.dart';
import 'package:inventtia_flow/tutorial/tutorial_controller.dart';
import 'package:inventtia_flow/tutorial/tutorial_destino.dart';
import 'package:inventtia_flow/tutorial/tutorial_paso.dart';
import 'package:inventtia_flow/tutorial/tutorial_registry.dart';

/// Navegación por pasos: el tutorial no se queda esperando a que el usuario
/// cambie de pantalla; al entrar en un paso le pide a la app que abra la suya.
///
/// Se montan anclas reales (el registro del tutorial se alimenta de widgets
/// montados) y un navegador de mentira que apunta lo que se le pide.
///
/// Ojo con el temporizador de seguridad de `TutorialController` (1,5 s): cuando
/// el ancla del paso no llega a aparecer hay que dejar que se cumpla, o
/// `testWidgets` se queja de que queda un `Timer` pendiente al acabar.
void main() {
  late TutorialController c;
  late List<TutorialDestino> pedidos;

  setUp(() {
    TutorialRegistry.instance.limpiar();
    c = TutorialController.aisladoParaPruebas();
    pedidos = <TutorialDestino>[];
  });

  tearDown(() {
    TutorialRegistry.instance.limpiar();
  });

  Future<void> navegador(TutorialDestino destino) async {
    pedidos.add(destino);
  }

  /// Cumple el temporizador de seguridad de la navegación.
  Future<void> dejarPasarLaEspera(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 1600));

  /// Monta una pantalla con las anclas indicadas. El registro va en post-frame,
  /// así que hace falta un `pump` para que cuenten como montadas.
  Future<void> montar(WidgetTester tester, List<String> ids) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              for (final id in ids) TutorialAnchor(id: id, child: Text(id)),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('al iniciar pide el destino del primer paso', (tester) async {
    // El ancla del primer paso no está montada: vive en otra pantalla.
    await montar(tester, const <String>['b']);

    c.iniciar(
      const <TutorialPaso>[
        TutorialPaso(
          id: 'a',
          titulo: 'A',
          mensaje: 'a',
          destino: TutorialDestino.catalogo,
        ),
        TutorialPaso(
          id: 'b',
          titulo: 'B',
          mensaje: 'b',
          destino: TutorialDestino.servicio,
        ),
      ],
      navegador: navegador,
    );
    await tester.pump();

    expect(pedidos, <TutorialDestino>[TutorialDestino.catalogo]);
    expect(c.navegando, isTrue);

    await dejarPasarLaEspera(tester);
    expect(c.navegando, isFalse);
  });

  testWidgets('no navega si el elemento del paso ya está a la vista',
      (tester) async {
    await montar(tester, const <String>['a']);

    c.iniciar(
      const <TutorialPaso>[
        TutorialPaso(
          id: 'a',
          titulo: 'A',
          mensaje: 'a',
          destino: TutorialDestino.home,
        ),
      ],
      navegador: navegador,
    );
    await tester.pump();

    expect(pedidos, isEmpty);
    expect(c.navegando, isFalse);
  });

  testWidgets('siguiente pide el destino del paso nuevo', (tester) async {
    await montar(tester, const <String>['a']);

    c.iniciar(
      const <TutorialPaso>[
        TutorialPaso(id: 'a', titulo: 'A', mensaje: 'a'),
        TutorialPaso(
          id: 'b',
          titulo: 'B',
          mensaje: 'b',
          destino: TutorialDestino.localDetalle,
        ),
      ],
      navegador: navegador,
    );
    await tester.pump();
    expect(pedidos, isEmpty);

    c.siguiente();
    await tester.pump();

    expect(pedidos, <TutorialDestino>[TutorialDestino.localDetalle]);

    await dejarPasarLaEspera(tester);
  });

  testWidgets('al volver atrás pide la pantalla del paso anterior',
      (tester) async {
    // Estamos en la pantalla del segundo paso: al retroceder hay que volver a la
    // del primero.
    await montar(tester, const <String>['b']);

    c.iniciar(
      const <TutorialPaso>[
        TutorialPaso(
          id: 'a',
          titulo: 'A',
          mensaje: 'a',
          destino: TutorialDestino.locales,
        ),
        TutorialPaso(
          id: 'b',
          titulo: 'B',
          mensaje: 'b',
          destino: TutorialDestino.servicios,
        ),
      ],
      navegador: navegador,
    );
    await tester.pump();
    expect(pedidos, <TutorialDestino>[TutorialDestino.locales]);

    c.siguiente();
    await tester.pump();
    // Su elemento ya está a la vista: no hay nada que pedir.
    expect(pedidos, <TutorialDestino>[TutorialDestino.locales]);

    c.anterior();
    await tester.pump();
    expect(pedidos, <TutorialDestino>[
      TutorialDestino.locales,
      TutorialDestino.locales,
    ]);

    await dejarPasarLaEspera(tester);
  });

  testWidgets('mientras navega no se le pide nada al usuario y se apaga al '
      'aparecer el elemento', (tester) async {
    await montar(tester, const <String>['a']);

    c.iniciar(
      const <TutorialPaso>[
        TutorialPaso(id: 'a', titulo: 'A', mensaje: 'a'),
        TutorialPaso(
          id: 'b',
          titulo: 'B',
          mensaje: 'b',
          destino: TutorialDestino.reservas,
        ),
      ],
      navegador: navegador,
    );
    await tester.pump();

    c.siguiente();
    expect(c.navegando, isTrue);

    // La navegación real monta el elemento del paso: el aviso se apaga.
    await montar(tester, const <String>['a', 'b']);
    await tester.pump();

    expect(pedidos, <TutorialDestino>[TutorialDestino.reservas]);
    expect(c.navegando, isFalse);
  });
}
