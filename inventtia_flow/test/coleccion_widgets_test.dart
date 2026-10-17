import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inventtia_flow/config/app_theme.dart';
import 'package:inventtia_flow/models/config_precio.dart';
import 'package:inventtia_flow/models/servicio.dart';
import 'package:inventtia_flow/screens/coleccion_detail_screen.dart';
import 'package:inventtia_flow/screens/reserva_multiple_screen.dart';
import 'package:inventtia_flow/services/coleccion_service.dart';
import 'package:inventtia_flow/services/home_catalog_service.dart';
import 'package:inventtia_flow/utils/horario_atencion.dart';
import 'package:inventtia_flow/widgets/tarjeta_coleccion.dart';

/// Pruebas de widget de la sección de colecciones y de la reserva múltiple.
///
/// No tocan Supabase: el catálogo se inyecta. Lo que se comprueba es lo que un
/// `flutter analyze` no ve — que las piezas se pinten sin desbordarse en el
/// ancho de un móvil real y que el recorrido de reserva esté donde debe.
///
/// Además, cada test deja una captura en `../.dsh/screenshots/` para poder
/// revisar el resultado a ojo (el renderizador de tests dibuja el texto como
/// bloques, así que la captura sirve para composición y color, no para tipografía).
const Key _kCaptura = Key('captura');

/// Deja una captura de la pantalla montada en `../.dsh/screenshots/`.
///
/// Es un extra de revisión, no una aserción: si el sistema de archivos no deja
/// escribir (CI en solo lectura, por ejemplo) el test **no** falla por esto. El
/// renderizador de tests dibuja el texto como bloques, así que la captura sirve
/// para revisar composición, color y espaciado, no tipografía.
Future<void> _capturar(WidgetTester tester, String nombre) async {
  try {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_kCaptura),
    );
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data;
    });
    if (bytes == null) return;
    final dir = Directory('../.dsh/screenshots');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    File(
      '${dir.path}/$nombre.png',
    ).writeAsBytesSync(bytes.buffer.asUint8List(), flush: true);
  } catch (e) {
    debugPrint('[test] sin captura $nombre: $e');
  }
}

HomeCatalogItem _item({
  required int id,
  required String titulo,
  String local = 'Spa Aurora',
  String? provincia = 'Villa Clara',
  double? precio = 25,
  String moneda = 'USD',
  bool permiteDirecta = true,
  bool conFoto = false,
  String? descripcion,
}) {
  return HomeCatalogItem(
    id: id,
    title: titulo,
    venue: local,
    category: const HomeCatalogCategory(
      id: 3,
      codigo: 'belleza',
      nombre: 'Belleza',
    ),
    subcategoria: const HomeCatalogCategory(
      id: 30,
      codigo: 'facial',
      nombre: 'Facial',
    ),
    price: precio,
    currency: moneda,
    provincia: provincia,
    direccion: 'Calle 12, #45',
    imageUrl: conFoto ? 'https://example.invalid/foto.jpg' : null,
    permiteReservaDirecta: permiteDirecta,
    cantidadMaxCapacidad: 2,
    rating: 4.7,
    totalResenas: 18,
    estadoHorario: EstadoHorario.abierto,
    localServicio: LocalServicio(
      id: id,
      idLocal: 1,
      idServicio: id,
      createdAt: DateTime(2026),
      permiteReservaDirecta: permiteDirecta,
      cantidadMaxCapacidad: 2,
      servicio: Servicio(
        id: id,
        nombre: titulo,
        descripcion: descripcion,
        createdAt: DateTime(2026),
        configPrecio: ConfigPrecio(preciosBase: {moneda: precio ?? 0}),
      ),
    ),
  );
}

Widget _app(Widget child) => MaterialApp(
  // Sin `AppTheme.light`: ese tema arma el `TextTheme` con GoogleFonts, que en
  // un test no puede descargar Inter (toda petición devuelve 400) y con la
  // descarga apagada exige el .ttf en assets. Ninguno de los dos casos aporta
  // nada a lo que se mide aquí; el resto del tema es el mismo.
  theme: ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppTheme.primary),
    scaffoldBackgroundColor: AppTheme.surface,
    extensions: const [AppSemanticColors.defaults],
  ),
  home: RepaintBoundary(key: _kCaptura, child: child),
);

void main() {
  // `AppTheme.light` arma el `TextTheme` con GoogleFonts, que en un test no
  // puede descargar Inter (toda petición devuelve 400) y lanzaría una excepción
  // de red en mitad del test. Con la descarga apagada el tema cae a la fuente
  // por defecto y lo que se mide es la composición, no la descarga.
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const coleccion = Coleccion(
    id: 7,
    titulo: 'Todo para la cara',
    subtitulo: 'Limpieza, hidratación y diseño de cejas',
    icono: '💧',
    colorInicio: '#70537C',
    colorFin: '#C98CA4',
    totalServicios: 4,
    servicios: [11, 12, 13, 14],
  );

  final servicios = [
    _item(
      id: 11,
      titulo: 'Limpieza facial profunda',
      descripcion: 'Con extracción y mascarilla.',
    ),
    _item(id: 12, titulo: 'Hidratación con ácido hialurónico', precio: 32),
    // Sin foto a propósito: una imagen de red deja la caché esperando y
    // `pumpAndSettle` no termina nunca. El hueco se cubre con el degradado real.
    _item(id: 13, titulo: 'Diseño de cejas', local: 'Studio Ceja', precio: 12),
    _item(id: 14, titulo: 'Masaje facial relajante', permiteDirecta: false),
  ];

  tearDown(() {
    // Las capturas son un extra de revisión: no deben condicionar el resultado.
  });

  testWidgets('el riel de colecciones se pinta entero en un móvil de 360', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        Scaffold(
          backgroundColor: AppTheme.surface,
          body: Center(
            child: SizedBox(
              height: 158,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 3,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => TarjetaColeccion(
                  coleccion: Coleccion(
                    id: i,
                    titulo: [
                      'Todo para la cara',
                      'Pack novia',
                      'Self-care Sunday',
                    ][i],
                    icono: ['💧', '💍', '🌿'][i],
                    colorInicio: ['#70537C', '#8C5B72', '#2D7573'][i],
                    colorFin: ['#C98CA4', '#C98CA4', '#71BCB4'][i],
                    totalServicios: [4, 12, 8][i],
                  ),
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Todo para la cara'), findsOneWidget);
    expect(find.text('Pack novia'), findsOneWidget);
    expect(find.text('4 servicios'), findsOneWidget);
    // El riel es perezoso: solo se construyen las tarjetas visibles.
    expect(find.text('COLECCIÓN'), findsWidgets);

    await _capturar(tester, '01_riel_colecciones');
  });

  testWidgets(
    'la tarjeta de una sola colección ocupa el ancho y gana subtítulo',
    (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(
          Scaffold(
            backgroundColor: AppTheme.surface,
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: TarjetaColeccion(
                coleccion: coleccion,
                expandida: true,
                alto: 176,
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Todo para la cara'), findsOneWidget);
      expect(
        find.text('Limpieza, hidratación y diseño de cejas'),
        findsOneWidget,
      );

      await _capturar(tester, '02_coleccion_expandida');
    },
  );

  testWidgets('la vista de la colección agrupa por local y no se desborda', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        ColeccionDetailScreen(
          coleccion: coleccion,
          serviciosIniciales: servicios,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('COLECCIÓN CURADA'), findsOneWidget);
    expect(find.text('Cómo reservar esta colección'), findsOneWidget);
    expect(find.text('Servicios de la colección'), findsOneWidget);
    expect(find.text('Spa Aurora'), findsOneWidget);
    expect(find.text('Studio Ceja'), findsOneWidget);
    expect(find.text('Reservar'), findsOneWidget);
    // Reserva directa fuera: el chip explica por dónde sí se reserva.
    expect(find.text('Solo lista de espera'), findsOneWidget);

    await _capturar(tester, '03_coleccion_detalle');
  });

  testWidgets('modo selección cuenta los servicios y deja elegir turnos', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        ColeccionDetailScreen(
          coleccion: coleccion,
          serviciosIniciales: servicios,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reservar'));
    await tester.pumpAndSettle();

    expect(find.text('ELIGE TUS SERVICIOS'), findsOneWidget);
    expect(
      find.text('Toca los servicios que quieras reservar'),
      findsOneWidget,
    );

    await tester.tap(find.text('Limpieza facial profunda'));
    await tester.tap(find.text('Hidratación con ácido hialurónico'));
    await tester.pumpAndSettle();

    // Dos servicios, dos establecimientos distintos según la selección.
    expect(find.textContaining('2 servicios'), findsWidgets);
    expect(find.text('Elegir turnos (2)'), findsOneWidget);

    await _capturar(tester, '04_coleccion_seleccion');

    await tester.tap(find.text('Elegir turnos (2)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // La pantalla de reserva múltiple se abre con los dos elegidos.
    expect(find.text('Día y turno'), findsOneWidget);
    expect(find.text('Confirmar 2 reservas'), findsOneWidget);
  });

  testWidgets('el asistente lista cada servicio con su estado', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        ReservaMultipleScreen(
          coleccion: coleccion,
          servicios: servicios.take(3).toList(),
        ),
      ),
    );
    // Sin Supabase las lecturas fallan: la pantalla debe seguir en pie (no
    // quedarse en blanco ni reventar), ofrecer reintentar y **no** decir a la
    // vez "no hay cupo" y "no pudimos leer", que serían dos motivos distintos.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Día y turno'), findsOneWidget);
    expect(find.textContaining('de 3 listos'), findsOneWidget);
    expect(find.text('Confirmar 3 reservas'), findsOneWidget);
    expect(find.text('Reintentar'), findsWidgets);
    expect(
      find.textContaining('Ahora mismo no hay días con cupo'),
      findsNothing,
    );
    expect(find.textContaining('No pudimos leer los turnos'), findsWidgets);

    await _capturar(tester, '05_reserva_multiple');
  });

  testWidgets('sin colecciones no se pinta nada de la sección', (tester) async {
    await tester.pumpWidget(
      _app(const Scaffold(body: Center(child: Text('Home sin colecciones')))),
    );
    await tester.pumpAndSettle();

    expect(sinColecciones, isA<SizedBox>());
    expect(find.text('Home sin colecciones'), findsOneWidget);
  });
}
