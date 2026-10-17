import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/tutorial/tutorial_controller.dart';
import 'package:inventtia_flow/tutorial/tutorial_destino.dart';
import 'package:inventtia_flow/tutorial/tutorial_paso.dart';

const List<TutorialPaso> _pasos = <TutorialPaso>[
  TutorialPaso(id: 'a', titulo: 'A', mensaje: 'paso a'),
  TutorialPaso(id: 'b', titulo: 'B', mensaje: 'paso b'),
  TutorialPaso(id: 'c', titulo: 'C', mensaje: 'paso c', opcional: true),
];

void main() {
  late TutorialController c;

  setUp(() {
    c = TutorialController.aisladoParaPruebas();
  });

  test('iniciar activa el recorrido en el primer paso', () {
    expect(c.activo, isFalse);

    c.iniciar(_pasos, flujoId: 'test');

    expect(c.activo, isTrue);
    expect(c.total, 3);
    expect(c.indice, 0);
    expect(c.flujoId, 'test');
    expect(c.pasoActual?.id, 'a');
  });

  test('iniciar con lista vacía no hace nada', () {
    c.iniciar(const <TutorialPaso>[], flujoId: 'test');
    expect(c.activo, isFalse);
    expect(c.pasoActual, isNull);
  });

  test('siguiente avanza y terminar dispara alCompletar', () {
    var completado = 0;
    c.iniciar(_pasos, alCompletar: () => completado++);

    c.siguiente();
    expect(c.indice, 1);
    expect(c.activo, isTrue);

    c.siguiente();
    expect(c.indice, 2);
    expect(completado, 0);

    c.siguiente(); // último → termina
    expect(c.activo, isFalse);
    expect(completado, 1);
  });

  test('anterior retrocede y no baja de cero', () {
    c.iniciar(_pasos);
    c.siguiente();
    expect(c.indice, 1);

    c.anterior();
    expect(c.indice, 0);

    c.anterior();
    expect(c.indice, 0);
  });

  test('omitir cierra y usa alOmitir', () {
    var omitido = 0;
    var completado = 0;
    c.iniciar(
      _pasos,
      alCompletar: () => completado++,
      alOmitir: () => omitido++,
    );

    c.omitir();

    expect(c.activo, isFalse);
    expect(omitido, 1);
    expect(completado, 0);
  });

  test('omitir sin alOmitir cae en alCompletar (no se repite igual)', () {
    var completado = 0;
    c.iniciar(_pasos, alCompletar: () => completado++);

    c.omitir();

    expect(completado, 1);
  });

  test('sin anclas montadas el recorrido se queda esperando', () {
    c.iniciar(_pasos);

    // Ningún ancla está en el árbol: no hay a dónde saltar y el tutorial sigue
    // vivo (no se da por terminado porque el último paso no se alcanzó).
    c.evaluarAvance();

    expect(c.activo, isTrue);
    expect(c.indice, 0);
  });

  test('repetir relanza el último recorrido conservando los callbacks', () {
    var completado = 0;
    c.iniciar(_pasos, flujoId: 'test', alCompletar: () => completado++);
    c.irA(2);
    c.terminar();
    expect(completado, 1);
    expect(c.activo, isFalse);

    c.repetir();

    expect(c.activo, isTrue);
    expect(c.indice, 0);
    expect(c.flujoId, 'test');

    c.irA(2);
    c.siguiente();
    expect(completado, 2);
  });

  test('notifica a los listeners en cada cambio', () {
    var avisos = 0;
    c.addListener(() => avisos++);

    c.iniciar(_pasos);
    c.siguiente();
    c.anterior();
    c.terminar();

    expect(avisos, 4);
  });

  test('repetir sin recorrido previo no hace nada', () {
    c.repetir();
    expect(c.activo, isFalse);
  });

  test('sin navegador el recorrido no navega ni se queda colgado', () async {
    c.iniciar(
      const <TutorialPaso>[
        TutorialPaso(
          id: 'a',
          titulo: 'A',
          mensaje: 'a',
          destino: TutorialDestino.home,
        ),
      ],
    );

    await Future<void>.delayed(Duration.zero);

    expect(c.navegando, isFalse);
    expect(c.activo, isTrue);
  });

  test('pide el destino del paso y deja de esperar si la navegación falla',
      () async {
    final pedidos = <TutorialDestino>[];
    c.iniciar(
      const <TutorialPaso>[
        TutorialPaso(
          id: 'a',
          titulo: 'A',
          mensaje: 'a',
          destino: TutorialDestino.gestion,
        ),
      ],
      navegador: (destino) async {
        pedidos.add(destino);
        throw StateError('sin permiso');
      },
    );

    await Future<void>.delayed(Duration.zero);

    expect(pedidos, <TutorialDestino>[TutorialDestino.gestion]);
    expect(c.navegando, isFalse);
  });

  test('repetir conserva el navegador', () async {
    final pedidos = <TutorialDestino>[];
    c.iniciar(
      const <TutorialPaso>[
        TutorialPaso(
          id: 'a',
          titulo: 'A',
          mensaje: 'a',
          destino: TutorialDestino.locales,
        ),
      ],
      navegador: (destino) async => pedidos.add(destino),
    );
    await Future<void>.delayed(Duration.zero);
    expect(pedidos, <TutorialDestino>[TutorialDestino.locales]);

    c.terminar();
    c.repetir();
    await Future<void>.delayed(Duration.zero);

    expect(pedidos, <TutorialDestino>[
      TutorialDestino.locales,
      TutorialDestino.locales,
    ]);
  });
}