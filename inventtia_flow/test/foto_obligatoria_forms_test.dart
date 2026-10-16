import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inventtia_flow/models/servicio.dart';
import 'package:inventtia_flow/screens/admin/gestion_locales_screen.dart';
import 'package:inventtia_flow/screens/admin/gestion_servicios_screen.dart';

/// La foto es **obligatoria** en el alta y en la edición, tanto del local como
/// del servicio.
///
/// Se montan los formularios de verdad (no una copia) sin Supabase: las lecturas
/// del nomenclador y de geonames fallan y el formulario sigue pintándose, que es
/// justo lo que hace falta para comprobar la validación. Lo que se mide es que
/// pulsar Guardar sin foto **no** deje pasar el guardado: el error sale en el
/// campo y el formulario sigue abierto.
Servicio _servicio({String? foto}) => Servicio(
  id: 7,
  nombre: 'Corte de pelo',
  foto: foto,
  createdAt: DateTime(2026),
);

Widget _app(Widget hoja) => MaterialApp(
  theme: ThemeData(useMaterial3: true),
  home: Scaffold(body: SingleChildScrollView(child: hoja)),
);

/// Deja que el formulario termine sus lecturas (que en test fallan) y deja el
/// botón de guardar a la vista antes de tocarlo.
Future<void> _preparar(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _tocarGuardar(WidgetTester tester, String etiqueta) async {
  await tester.ensureVisible(find.text(etiqueta));
  await tester.pump();
  await tester.tap(find.text(etiqueta));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  // El tema por defecto no usa GoogleFonts, pero se apaga la descarga por si el
  // widget la pidiese: en un test toda petición devuelve 400 y lanzaría.
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('servicio nuevo: sin foto no se guarda y el error se ve', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400 * 3, 3000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(ServicioFormSheet(idEntidad: 1, servicio: null)),
    );
    await _preparar(tester);

    // El campo avisa desde el principio de que la foto hace falta.
    expect(find.text('Foto del servicio *'), findsOneWidget);
    expect(find.text('Agregar imagen'), findsOneWidget);
    expect(find.text('La foto del servicio es obligatoria'), findsNothing);

    await _tocarGuardar(tester, 'Crear Servicio');

    expect(find.text('La foto del servicio es obligatoria'), findsOneWidget);
    // Sigue abierto: no se guardó nada.
    expect(find.text('Crear Servicio'), findsOneWidget);
  });

  testWidgets('servicio existente CON foto: no se exige volver a subirla', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400 * 3, 3000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        ServicioFormSheet(
          idEntidad: 1,
          servicio: _servicio(foto: 'https://x/servicios/7.jpg?v=1'),
        ),
      ),
    );
    await _preparar(tester);

    // Ya hay foto: el botón dice "Cambiar", no "Agregar".
    expect(find.text('Cambiar imagen'), findsOneWidget);
    expect(find.text('Agregar imagen'), findsNothing);

    await _tocarGuardar(tester, 'Guardar');

    expect(find.text('La foto del servicio es obligatoria'), findsNothing);
  });

  testWidgets('local nuevo: sin foto no se guarda y el error se ve', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400 * 3, 3000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(LocalFormSheet(idEntidad: 1, local: null)));
    await _preparar(tester);

    expect(find.text('Foto del local *'), findsOneWidget);
    expect(find.text('La foto del local es obligatoria'), findsNothing);

    await _tocarGuardar(tester, 'Crear Local');

    expect(find.text('La foto del local es obligatoria'), findsOneWidget);
    expect(find.text('Crear Local'), findsOneWidget);
  });

  testWidgets('local existente CON foto: no se exige volver a subirla', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400 * 3, 3000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        LocalFormSheet(
          idEntidad: 1,
          local: Local(
            id: 3,
            nombre: 'Sala Demo',
            foto: 'https://x/locales/3.jpg?v=1',
            createdAt: DateTime(2026),
          ),
        ),
      ),
    );
    await _preparar(tester);

    expect(find.text('Cambiar imagen'), findsOneWidget);

    await _tocarGuardar(tester, 'Guardar');

    expect(find.text('La foto del local es obligatoria'), findsNothing);
  });
}
