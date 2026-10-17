import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/tutorial/tutorial_anchor.dart';
import 'package:inventtia_flow/tutorial/tutorial_controller.dart';
import 'package:inventtia_flow/tutorial/tutorial_overlay.dart';
import 'package:inventtia_flow/tutorial/tutorial_paso.dart';
import 'package:inventtia_flow/tutorial/tutorial_registry.dart';

/// Pruebas del comportamiento multi-pantalla del overlay.
///
/// Son las que cubren lo que no se puede testear con lógica pura: que el hueco
/// deje pasar el toque real al widget resaltado, que el recorrido salte solo al
/// llegar a la pantalla siguiente y que **no** salte cuando el elemento de otro
/// paso está montado pero oculto (pestañas del `IndexedStack`).

Widget _app(Widget home) => MaterialApp(
      builder: (context, child) => TutorialOverlayHost(child: child),
      home: home,
    );

const List<TutorialPaso> _pasosDos = <TutorialPaso>[
  TutorialPaso(id: 'a', titulo: 'Paso A', mensaje: 'mensaje a'),
  TutorialPaso(id: 'b', titulo: 'Paso B', mensaje: 'mensaje b'),
];

const List<TutorialPaso> _pasosPestanas = <TutorialPaso>[
  TutorialPaso(id: 'a', titulo: 'Paso A', mensaje: 'mensaje a'),
  TutorialPaso(id: 'c', titulo: 'Paso C', mensaje: 'mensaje c'),
];

/// 'a' y 'c' están siempre a la vista; 'b' solo cuando se pide.
const List<TutorialPaso> _pasosConHueco = <TutorialPaso>[
  TutorialPaso(id: 'a', titulo: 'Paso A', mensaje: 'mensaje a'),
  TutorialPaso(id: 'b', titulo: 'Paso B', mensaje: 'mensaje b'),
  TutorialPaso(id: 'c', titulo: 'Paso C', mensaje: 'mensaje c'),
];

class _ConPasoCondicional extends StatefulWidget {
  const _ConPasoCondicional({super.key});

  @override
  State<_ConPasoCondicional> createState() => _ConPasoCondicionalState();
}

class _ConPasoCondicionalState extends State<_ConPasoCondicional> {
  bool _mostrarB = false;

  void mostrarB() => setState(() => _mostrarB = true);

  void ocultarB() => setState(() => _mostrarB = false);

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [
            TutorialAnchor(id: 'a', child: const Text('ancla a')),
            if (_mostrarB)
              const TutorialAnchor(id: 'b', child: Text('ancla b')),
            const TutorialAnchor(id: 'c', child: Text('ancla c')),
          ],
        ),
      );
}

class _PantallaA extends StatelessWidget {
  const _PantallaA();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TutorialAnchor(
            id: 'a',
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const _PantallaB()),
              ),
              child: const Text('ir'),
            ),
          ),
        ),
      );
}

class _PantallaB extends StatelessWidget {
  const _PantallaB();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: TutorialAnchor(id: 'b', child: Text('destino'))),
      );
}

class _ConPestanas extends StatefulWidget {
  const _ConPestanas({super.key});

  @override
  State<_ConPestanas> createState() => _ConPestanasState();
}

class _ConPestanasState extends State<_ConPestanas> {
  int _i = 0;

  void cambiar(int i) => setState(() => _i = i);

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(
          index: _i,
          children: const <Widget>[
            TutorialAnchor(id: 'a', child: Center(child: Text('pestana a'))),
            TutorialAnchor(id: 'c', child: Center(child: Text('pestana c'))),
          ],
        ),
      );
}

/// Deja correr unos frames (hay una animación de pulso que nunca se detiene, así
/// que no se puede usar `pumpAndSettle`).
Future<void> _avanzarFrames(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  setUp(() {
    TutorialController.instance.resetParaPruebas();
    TutorialRegistry.instance.limpiar();
  });

  tearDown(() {
    TutorialController.instance.resetParaPruebas();
    TutorialRegistry.instance.limpiar();
  });

  testWidgets('sin tutorial activo el overlay no tapa nada', (tester) async {
    await tester.pumpWidget(_app(const _PantallaA()));
    await _avanzarFrames(tester);

    await tester.tap(find.text('ir'));
    await _avanzarFrames(tester);

    // La navegación llegó a su destino: el overlay no interceptó el toque.
    expect(find.text('destino'), findsOneWidget);
  });

  testWidgets('muestra la burbuja del paso actual sobre el elemento', (tester) async {
    await tester.pumpWidget(_app(const _PantallaA()));
    await _avanzarFrames(tester);

    TutorialController.instance.iniciar(_pasosDos);
    await _avanzarFrames(tester);

    expect(find.text('Paso A'), findsOneWidget);
    expect(find.text('Paso B'), findsNothing);
    expect(find.text('PASO 1 DE 2'), findsOneWidget);
  });

  testWidgets('el hueco deja pulsar el widget resaltado y el recorrido avanza solo',
      (tester) async {
    await tester.pumpWidget(_app(const _PantallaA()));
    await _avanzarFrames(tester);

    TutorialController.instance.iniciar(_pasosDos);
    await _avanzarFrames(tester);
    expect(find.text('Paso A'), findsOneWidget);

    // El botón está dentro del hueco: el toque llega de verdad a la app.
    await tester.tap(find.text('ir'));
    await _avanzarFrames(tester);
    await _avanzarFrames(tester);

    expect(find.text('destino'), findsOneWidget);
    expect(TutorialController.instance.indice, 1);
    expect(find.text('Paso B'), findsOneWidget);
  });

  testWidgets('cambiar de pestaña avanza al paso de la pestaña visible',
      (tester) async {
    final key = GlobalKey<_ConPestanasState>();
    await tester.pumpWidget(_app(_ConPestanas(key: key)));
    await _avanzarFrames(tester);

    TutorialController.instance.iniciar(_pasosPestanas);
    await _avanzarFrames(tester);
    // El ancla de la otra pestaña está montada (IndexedStack) pero oculta: el
    // tutorial NO debe saltar a ella sola.
    expect(find.text('Paso A'), findsOneWidget);
    expect(TutorialController.instance.indice, 0);

    key.currentState!.cambiar(1);
    await _avanzarFrames(tester);
    await _avanzarFrames(tester);

    expect(TutorialController.instance.indice, 1);
    expect(find.text('Paso C'), findsOneWidget);
  });

  testWidgets('omitir cierra el overlay y avisa', (tester) async {
    await tester.pumpWidget(_app(const _PantallaA()));
    await _avanzarFrames(tester);

    var omitido = 0;
    TutorialController.instance.iniciar(_pasosDos, alOmitir: () => omitido++);
    await _avanzarFrames(tester);
    expect(find.text('Paso A'), findsOneWidget);

    await tester.tap(find.text('Saltar'));
    await _avanzarFrames(tester);

    expect(omitido, 1);
    expect(TutorialController.instance.activo, isFalse);
    expect(find.text('Paso A'), findsNothing);
    expect(find.text('Paso B'), findsNothing);
  });

  testWidgets('el botón principal avanza y el último paso cierra', (tester) async {
    await tester.pumpWidget(_app(const _PantallaA()));
    await _avanzarFrames(tester);

    var completado = 0;
    TutorialController.instance.iniciar(
      _pasosDos,
      alCompletar: () => completado++,
    );
    await _avanzarFrames(tester);

    await tester.tap(find.text('Siguiente'));
    await _avanzarFrames(tester);

    expect(TutorialController.instance.indice, 1);
    expect(find.text('Paso B'), findsOneWidget);
    // El último paso se rotula "Entendido".
    expect(find.text('Entendido'), findsOneWidget);

    await tester.tap(find.text('Entendido'));
    await _avanzarFrames(tester);

    expect(completado, 1);
    expect(TutorialController.instance.activo, isFalse);
  });

  testWidgets(
      '"Siguiente" hacia un paso que aún no existe no se salta los intermedios',
      (tester) async {
    final key = GlobalKey<_ConPasoCondicionalState>();
    await tester.pumpWidget(_app(_ConPasoCondicional(key: key)));
    await _avanzarFrames(tester);

    TutorialController.instance.iniciar(_pasosConHueco);
    await _avanzarFrames(tester);
    expect(find.text('Paso A'), findsOneWidget);

    // El paso 3 ('c') ya está a la vista, pero el 2 ('b') todavía no se ha
    // montado: el recorrido debe esperar al 2, no saltar al 3.
    await tester.tap(find.text('Siguiente'));
    await _avanzarFrames(tester);
    await _avanzarFrames(tester);

    expect(TutorialController.instance.indice, 1);
    expect(find.text('Paso B'), findsOneWidget);
    expect(find.text('Paso C'), findsNothing);

    // Cuando el elemento del paso 2 aparece, el recorrido lo resalta (sigue en
    // el 2: para avanzar hay que volver a "hacer" el paso, no basta con verlo).
    key.currentState!.mostrarB();
    await _avanzarFrames(tester);
    await _avanzarFrames(tester);

    expect(TutorialController.instance.indice, 1);
    expect(TutorialRegistry.instance.estaVisible('b'), isTrue);
    expect(find.text('Paso B'), findsOneWidget);

    // Y en cuanto el paso 2 deja de estar a la vista, salta al 3.
    key.currentState!.ocultarB();
    await _avanzarFrames(tester);
    await _avanzarFrames(tester);

    expect(TutorialController.instance.indice, 2);
    expect(find.text('Paso C'), findsOneWidget);
  });
}