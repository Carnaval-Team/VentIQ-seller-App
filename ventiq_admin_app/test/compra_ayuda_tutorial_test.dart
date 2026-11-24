// Contrato de la ayuda y del tutorial de la vista de compra.
//
// Cubre dos cosas que se rompen en silencio:
//   1. La frase que explica un ajuste: tiene que decir la cuenta que se hizo y
//      quién lo paga, con las unidades correctas (porcentaje, unidad, fijo).
//   2. El tutorial: los pasos que apuntan a campos que no están montados se
//      saltan en vez de dejar un globo huérfano, y sin pasos no se abre.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/screens/compras/compra_ayuda.dart';
import 'package:ventiq_admin_app/screens/compras/compra_tutorial.dart';

void main() {
  group('explicación de un ajuste', () {
    test('porcentaje: dice el % aplicado y muestra la cuenta', () {
      final texto = explicacionAjusteCompra(
        base: 'porcentaje',
        valor: 10,
        monto: 100,
        mercancia: 1000,
        cantidad: 100,
        moneda: 'USD',
        origenPago: 'fondo',
      );
      expect(texto, contains('10 %'));
      expect(texto, contains('1,000.00'));
      expect(texto, contains('100.00'));
      expect(texto, contains('USD'));
      expect(texto, contains('lo paga el fondo'));
    });

    test('por unidad: multiplica por las unidades de la compra', () {
      final texto = explicacionAjusteCompra(
        base: 'unidad',
        valor: 2,
        monto: 200,
        mercancia: 1000,
        cantidad: 100,
        moneda: 'USD',
        origenPago: 'wallet_importadora',
      );
      expect(texto, contains('2 × 100'));
      expect(texto, contains('unidades'));
      expect(texto, contains('200.00'));
      expect(texto, contains('wallet de importadora'));
      // Un ajuste de la importadora no entra en el financiado.
      expect(texto, isNot(contains('financiado')));
    });

    test('unidad con una sola unidad no dice «unidades»', () {
      final texto = explicacionAjusteCompra(
        base: 'unidad',
        valor: 5,
        monto: 5,
        mercancia: 100,
        cantidad: 1,
        moneda: 'CUP',
        origenPago: 'externo',
      );
      expect(texto, contains('1 unidad'));
      expect(texto, isNot(contains('unidades')));
      expect(texto, contains('por fuera del fondo'));
    });

    test('fijo: no inventa una multiplicación', () {
      final texto = explicacionAjusteCompra(
        base: 'global',
        valor: 150,
        monto: 150,
        mercancia: 1000,
        cantidad: 100,
        moneda: 'EUR',
        origenPago: 'fondo',
      );
      expect(texto, contains('importe fijo'));
      expect(texto, isNot(contains('%')));
      expect(texto, isNot(contains('×')));
      expect(texto, contains('EUR'));
    });

    test('el proveedor que asume el costo no se confunde con el fondo', () {
      expect(quienPagaAjuste('wallet_proveedor'), contains('proveedor'));
      expect(quienPagaAjuste('wallet_proveedor'), isNot(contains('fondo')));
    });
  });

  group('conceptos de ayuda', () {
    test('la tasa de la factura se explica como moneda por 1 USD', () {
      expect(ayudaTasaFactura.titulo, contains('tasa'));
      expect(ayudaTasaFactura.queEs, contains('1 USD'));
      expect(ayudaTasaFactura.ejemplo, isNotNull);
      // El ejemplo tiene que traer la cuenta hecha, no solo prosa.
      expect(ayudaTasaFactura.ejemplo, contains('CUP'));
    });

    test('cada concepto con ejemplo trae números, no un párrafo vacío', () {
      for (final c in [
        ayudaTasaFactura,
        ayudaAjustes,
        ayudaBaseAjuste,
        ayudaRepartoAjuste,
        ayudaOrigenPago,
        ayudaCifrasCompra,
        ayudaLineasCompra,
        ayudaModoLiquidacion,
        ayudaPoliticaPago,
        ayudaMonedaFactura,
      ]) {
        expect(c.titulo, isNotEmpty);
        expect(c.queEs, isNotEmpty);
        if (c.ejemplo != null) {
          expect(
            c.ejemplo!,
            matches(RegExp(r'\d')),
            reason: '«${c.titulo}» promete un ejemplo y no trae cifras',
          );
        }
      }
    });

    test('el reparto avisa del límite real del aterrizaje', () {
      // Hoy el reparto del aterrizaje es siempre por valor: si se calla, el
      // usuario cree que «por peso» se aplica y el costo sale distinto.
      expect(ayudaRepartoAjuste.aviso, isNotNull);
      expect(ayudaRepartoAjuste.aviso, contains('por valor'));
    });
  });

  group('tutorial', () {
    testWidgets('sin pasos no se abre', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () =>
                      mostrarTutorialCompra(context, pasos: const []),
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      // Un recorrido vacío no pinta tarjeta ni deja la pantalla bloqueada.
      expect(find.text('Siguiente'), findsNothing);
    });

    testWidgets('recorre los pasos y termina', (tester) async {
      final claveA = GlobalKey();
      final claveB = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(title: const Text('Compra')),
              body: Column(
                children: [
                  SizedBox(
                    key: claveA,
                    height: 60,
                    child: const TextField(
                      decoration: InputDecoration(labelText: 'Proveedor'),
                    ),
                  ),
                  SizedBox(
                    key: claveB,
                    height: 60,
                    child: const TextField(
                      decoration: InputDecoration(labelText: 'Tasa'),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => mostrarTutorialCompra(
                      context,
                      pasos: [
                        PasoTutorialCompra(
                          clave: claveA,
                          titulo: 'Proveedor',
                          texto: 'A quién le compras.',
                        ),
                        PasoTutorialCompra(
                          clave: claveB,
                          titulo: 'Tasa',
                          texto: 'Moneda de la factura por 1 USD.',
                        ),
                      ],
                    ),
                    child: const Text('Abrir'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      // Paso 1 con su progreso.
      expect(find.text('Proveedor'), findsWidgets);
      expect(find.text('A quién le compras.'), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      expect(find.text('Tasa'), findsWidgets);
      expect(find.text('Moneda de la factura por 1 USD.'), findsOneWidget);
      expect(find.text('2 / 2'), findsOneWidget);
      // En el último paso el botón cambia de nombre.
      expect(find.text('Terminar'), findsOneWidget);
      expect(find.text('Siguiente'), findsNothing);

      await tester.tap(find.text('Terminar'));
      await tester.pumpAndSettle();

      // El recorrido se cerró: la pantalla vuelve a ser la de siempre.
      expect(find.text('1 / 2'), findsNothing);
      expect(find.text('Terminar'), findsNothing);
    });

    testWidgets('un paso sin widget montado se salta', (tester) async {
      final claveMontada = GlobalKey();
      final claveFantasma = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  SizedBox(
                    key: claveMontada,
                    height: 60,
                    child: const TextField(
                      decoration: InputDecoration(labelText: 'Real'),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => mostrarTutorialCompra(
                      context,
                      pasos: [
                        // Este campo no está en el árbol.
                        PasoTutorialCompra(
                          clave: claveFantasma,
                          titulo: 'Fantasma',
                          texto: 'No se puede resaltar.',
                        ),
                        PasoTutorialCompra(
                          clave: claveMontada,
                          titulo: 'Real',
                          texto: 'Este sí se ve.',
                        ),
                      ],
                    ),
                    child: const Text('Abrir'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      // Varios frames: el salto se programa con `addPostFrameCallback`.
      await tester.pumpAndSettle();

      // Aterriza en el único paso resaltable, no en el huérfano.
      expect(find.text('Este sí se ve.'), findsOneWidget);
      expect(find.text('No se puede resaltar.'), findsNothing);
    });

    testWidgets('«Salir» cierra sin completar', (tester) async {
      final clave = GlobalKey();
      bool? resultado;
      bool abierto = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  SizedBox(
                    key: clave,
                    height: 60,
                    child: const TextField(
                      decoration: InputDecoration(labelText: 'Campo'),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      abierto = true;
                      resultado = await mostrarTutorialCompra(
                        context,
                        pasos: [
                          PasoTutorialCompra(
                            clave: clave,
                            titulo: 'Campo',
                            texto: 'Un campo cualquiera.',
                          ),
                        ],
                      );
                    },
                    child: const Text('Abrir'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(abierto, isTrue);

      await tester.tap(find.text('Salir'));
      await tester.pumpAndSettle();

      expect(resultado, isFalse, reason: 'salir no es completar');
      expect(find.text('Un campo cualquiera.'), findsNothing);
    });
  });

  // ===========================================================================
  // Burbuja de aviso: cerrarla dos veces no puede reventar
  // ===========================================================================
  //
  // Regresión real: en la app la burbuja la cerraba su propio widget (al tocar
  // fuera, la X, o «Ver tutorial») y además la pantalla al desmontarse. Las dos
  // rutas quitaban la misma `OverlayEntry` y Flutter abortaba con
  // «An OverlayEntry should be removed only once.»
  group('burbuja de aviso', () {
    /// Monta un AppBar con el ancla y devuelve un abridor que inserta la
    /// burbuja ya con el árbol asentado.
    /// Monta la pantalla con el ancla y ya deja insertada la burbuja.
    ///
    /// Es `async` a propósito: `pumpWidget` devuelve un `Future` que hay que
    /// esperar; si se llama sin `await` desde una función síncrona, el
    /// siguiente `pumpAndSettle` choca con el guardián de la zona de test
    /// («Guarded function conflict»).
    Future<AvisoTutorial?> preparar(
      WidgetTester tester, {
      required VoidCallback alCerrar,
      Future<void> Function()? alAceptar,
    }) async {
      final ancla = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(
                title: const Text('Pantalla'),
                actions: [
                  IconButton(
                    key: ancla,
                    icon: const Icon(Icons.school_outlined),
                    onPressed: () {},
                  ),
                ],
              ),
              body: const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final aviso = insertarAvisoTutorial(
        tester.element(find.byType(Scaffold)),
        ancla: ancla,
        alAceptar: alAceptar ?? () async {},
        alCerrar: alCerrar,
      );
      await tester.pumpAndSettle();
      return aviso;
    }

    testWidgets('cerrar dos veces seguidas no lanza', (tester) async {
      var vecesCerrado = 0;
      final aviso = await preparar(tester, alCerrar: () => vecesCerrado++);

      expect(aviso, isNotNull);
      expect(find.text('¿Tienes dudas?'), findsOneWidget);

      // El bug original: la pantalla cerraba una entrada que el widget ya
      // había quitado. Debe ser inocuo.
      aviso!.cerrar();
      aviso.cerrar();
      aviso.cerrar();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('¿Tienes dudas?'), findsNothing);
    });

    testWidgets('toque fuera cierra una vez y avisa al llamador', (
      tester,
    ) async {
      var vecesCerrado = 0;
      final aviso = await preparar(tester, alCerrar: () => vecesCerrado++);
      expect(aviso, isNotNull);

      // Un toque en el velo, lejos de la burbuja (que cuelga de la barra, a la
      // derecha). El lienzo de test es 800×600: hay que tocar dentro.
      await tester.tapAt(const Offset(10, 400));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('¿Tienes dudas?'), findsNothing);
      expect(vecesCerrado, 1);

      // Y ahora el cierre programático de la pantalla: no debe reventar ni
      // volver a avisar.
      aviso!.cerrar();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(vecesCerrado, 1, reason: 'cerrar no se notifica dos veces');
    });

    testWidgets('«Ver tutorial» cierra la burbuja y arranca el recorrido', (
      tester,
    ) async {
      var vecesCerrado = 0;
      var aceptado = 0;
      final aviso = await preparar(
        tester,
        alCerrar: () => vecesCerrado++,
        alAceptar: () async => aceptado++,
      );
      expect(aviso, isNotNull);

      await tester.tap(find.text('Ver tutorial'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('¿Tienes dudas?'), findsNothing);
      expect(aceptado, 1, reason: 'arranca el tutorial una sola vez');
      expect(vecesCerrado, 1);

      // El cierre posterior de la pantalla no reabre ni duplica nada.
      aviso!.cerrar();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(aceptado, 1);
    });

    testWidgets('sin ancla montada no inserta nada', (tester) async {
      final anclaSinMontar = GlobalKey();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );

      final aviso = insertarAvisoTutorial(
        tester.element(find.byType(Scaffold)),
        ancla: anclaSinMontar,
        alAceptar: () async {},
        alCerrar: () {},
      );

      expect(aviso, isNull);
      expect(tester.takeException(), isNull);
    });
  });
}
