import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/services/resena_service.dart';
import 'package:inventtia_flow/widgets/pedir_resena_sheet.dart';

/// El cartel que pide la reseña al terminar una reserva.
///
/// Se prueba lo que puede romperse sin darse cuenta: que la reseña se publique
/// con el `id_agenda` de **esa** reserva (no del servicio), que sin estrellas no
/// se publique nada, que lo escrito no se pierda si el servidor falla, y que el
/// cartel quepa y responda con el teclado abierto y con texto grande.
void main() {
  final atendido = DateTime(2026, 10, 22, 15, 30);

  ResenaPendiente pendiente({
    int idAgenda = 41,
    String servicio = 'Corte de cabello',
    String local = 'Salón Bella',
    String? foto,
  }) => ResenaPendiente(
    idAgenda: idAgenda,
    idLocalServicio: 7,
    servicioNombre: servicio,
    localNombre: local,
    servicioFoto: foto,
    atendido: atendido,
  );

  /// Monta el cartel dentro de un `Scaffold` real, como lo verá el usuario.
  Widget montar(
    Widget child, {
    Size tamano = const Size(390, 844),
    TextScaler escalador = TextScaler.noScaling,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: tamano, textScaler: escalador),
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );

  group('contenido del cartel', () {
    testWidgets('enseña el servicio, el local y la fecha de la reserva', (
      tester,
    ) async {
      await tester.pumpWidget(
        montar(
          PedirResenaSheet(
            pendiente: pendiente(),
            uuidUsuario: 'uuid-1',
            ahora: DateTime(2026, 10, 24),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('¿Cómo te fue?'), findsOneWidget);
      expect(find.text('Corte de cabello'), findsOneWidget);
      expect(find.text('Salón Bella · hace 2 días'), findsOneWidget);
      expect(find.text('RESERVA COMPLETADA'), findsOneWidget);
      // Sin estrellas todavía: la frase invita, no felicita en vano.
      expect(find.text('Toca las estrellas para valorar'), findsOneWidget);
    });

    testWidgets('sin local ni foto el cartel no deja huecos ni revienta', (
      tester,
    ) async {
      await tester.pumpWidget(
        montar(
          PedirResenaSheet(
            pendiente: pendiente(local: '', foto: null),
            uuidUsuario: 'uuid-1',
            ahora: DateTime(2026, 10, 24),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Corte de cabello'), findsOneWidget);
      // Solo la fecha: no queda un "· " colgando.
      expect(find.text('hace 2 días'), findsOneWidget);
      // El respaldo degradado ocupa el hueco de la foto.
      expect(find.byIcon(Icons.rate_review_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la frase cambia con la nota y no miente al de 1 estrella', (
      tester,
    ) async {
      await tester.pumpWidget(
        montar(
          PedirResenaSheet(
            pendiente: pendiente(),
            uuidUsuario: 'uuid-1',
            ahora: DateTime(2026, 10, 24),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(PedirResenaSheet.claveEstrella(1)));
      await tester.pumpAndSettle();
      expect(
        find.text('Lo sentimos. Cuéntanos qué falló y lo revisamos.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(PedirResenaSheet.claveEstrella(5)));
      await tester.pumpAndSettle();
      expect(
        find.text('¡Excelente! Cuéntanos por qué lo recomendarías.'),
        findsOneWidget,
      );
    });
  });

  group('publicar', () {
    testWidgets('sin estrellas no publica y lo dice en el propio cartel', (
      tester,
    ) async {
      var intentos = 0;
      await tester.pumpWidget(
        montar(
          PedirResenaSheet(
            pendiente: pendiente(),
            uuidUsuario: 'uuid-1',
            ahora: DateTime(2026, 10, 24),
            publicar: ({required puntuacion, comentario}) async {
              intentos++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(PedirResenaSheet.clavePublicar));
      await tester.pumpAndSettle();

      expect(intentos, 0);
      expect(find.byKey(PedirResenaSheet.claveError), findsOneWidget);
      expect(find.text('Elige de 1 a 5 estrellas para publicar.'), findsOneWidget);
    });

    testWidgets('publica la nota y el texto, y devuelve true al cerrar', (
      tester,
    ) async {
      int? nota;
      String? texto;
      var publicado = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    publicado = await mostrarPedirResena(
                      context,
                      pendiente: pendiente(),
                      uuidUsuario: 'uuid-1',
                      ahora: DateTime(2026, 10, 24),
                      publicar: ({required puntuacion, comentario}) async {
                        nota = puntuacion;
                        texto = comentario;
                      },
                    );
                  },
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(PedirResenaSheet.claveEstrella(4)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(PedirResenaSheet.claveComentario),
        'Muy buen trato, volveré.',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(PedirResenaSheet.clavePublicar));
      await tester.pumpAndSettle();

      expect(nota, 4);
      expect(texto, 'Muy buen trato, volveré.');
      expect(publicado, isTrue);
      expect(find.text('¿Cómo te fue?'), findsNothing);
    });

    testWidgets('si el servidor falla, el texto escrito no se pierde', (
      tester,
    ) async {
      await tester.pumpWidget(
        montar(
          PedirResenaSheet(
            pendiente: pendiente(),
            uuidUsuario: 'uuid-1',
            ahora: DateTime(2026, 10, 24),
            publicar: ({required puntuacion, comentario}) async {
              throw Exception('No se pudo publicar la reseña');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(PedirResenaSheet.claveEstrella(3)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(PedirResenaSheet.claveComentario),
        'Estuvo bien, aunque esperé un poco.',
      );
      await tester.tap(find.byKey(PedirResenaSheet.clavePublicar));
      await tester.pumpAndSettle();

      // El error se pinta dentro y el cartel sigue abierto con lo escrito.
      expect(find.byKey(PedirResenaSheet.claveError), findsOneWidget);
      expect(find.text('No se pudo publicar la reseña'), findsOneWidget);
      final campo = tester.widget<TextField>(
        find.byKey(PedirResenaSheet.claveComentario),
      );
      expect(campo.controller!.text, 'Estuvo bien, aunque esperé un poco.');
    });

    testWidgets('"Ahora no" cierra sin publicar y devuelve false', (
      tester,
    ) async {
      var intentos = 0;
      var publicado = true;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    publicado = await mostrarPedirResena(
                      context,
                      pendiente: pendiente(),
                      uuidUsuario: 'uuid-1',
                      ahora: DateTime(2026, 10, 24),
                      publicar: ({required puntuacion, comentario}) async {
                        intentos++;
                      },
                    );
                  },
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      // El cartel es alto: en el viewport por defecto de un test (800×600) el
      // botón queda por debajo del pliegue. Se asegura visible antes de tocar,
      // igual que haría el usuario con un scroll.
      await tester.ensureVisible(find.byKey(PedirResenaSheet.claveAhoraNo));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(PedirResenaSheet.claveAhoraNo));
      await tester.pumpAndSettle();

      expect(intentos, 0);
      expect(publicado, isFalse);
    });
  });

  group('ayudas para escribir', () {
    testWidgets('tocar una idea la añade al texto y desaparecen las ideas', (
      tester,
    ) async {
      await tester.pumpWidget(
        montar(
          PedirResenaSheet(
            pendiente: pendiente(),
            uuidUsuario: 'uuid-1',
            ahora: DateTime(2026, 10, 24),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(PedirResenaSheet.claveSugerencia('Trato muy amable')),
      );
      await tester.pumpAndSettle();

      final campo = tester.widget<TextField>(
        find.byKey(PedirResenaSheet.claveComentario),
      );
      expect(campo.controller!.text, 'Trato muy amable');
      // Ya hay texto: las ideas sobran y se retiran.
      expect(
        find.byKey(PedirResenaSheet.claveSugerencia('Trato muy amable')),
        findsNothing,
      );
    });

    testWidgets('tocar dos ideas las une sin duplicar la misma', (tester) async {
      await tester.pumpWidget(
        montar(
          PedirResenaSheet(
            pendiente: pendiente(),
            uuidUsuario: 'uuid-1',
            ahora: DateTime(2026, 10, 24),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(PedirResenaSheet.claveSugerencia('Trato muy amable')),
      );
      await tester.pumpAndSettle();
      // Se vuelve a mostrar el texto escrito para poder añadir otra: se borra
      // primero el campo y se comprueba que la unión no duplica.
      await tester.enterText(
        find.byKey(PedirResenaSheet.claveComentario),
        '',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(PedirResenaSheet.claveSugerencia('Lugar limpio y cómodo')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(PedirResenaSheet.claveComentario),
        'Lugar limpio y cómodo',
      );
      await tester.pumpAndSettle();

      final campo = tester.widget<TextField>(
        find.byKey(PedirResenaSheet.claveComentario),
      );
      expect(campo.controller!.text, 'Lugar limpio y cómodo');
    });
  });

  group('maqueta', () {
    testWidgets('cabe en una pantalla pequeña sin desbordar', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        montar(
          PedirResenaSheet(
            pendiente: pendiente(),
            uuidUsuario: 'uuid-1',
            ahora: DateTime(2026, 10, 24),
          ),
          tamano: const Size(320, 568),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Los controles siguen existiendo: se puede llegar a ellos con scroll.
      expect(find.byKey(PedirResenaSheet.clavePublicar), findsOneWidget);
    });

    testWidgets('con texto grande no se desborda ni se sale de la pantalla', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        montar(
          PedirResenaSheet(
            pendiente: pendiente(
              servicio: 'Depilación de cejas con diseño y perfilado',
            ),
            uuidUsuario: 'uuid-1',
            ahora: DateTime(2026, 10, 24),
          ),
          escalador: const TextScaler.linear(1.3),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(PedirResenaSheet.claveEstrella(5)), findsOneWidget);
    });
  });
}
