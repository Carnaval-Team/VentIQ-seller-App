import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/config/app_theme.dart';
import 'package:inventtia_flow/models/entidad.dart';
import 'package:inventtia_flow/screens/admin/gestion_screen.dart';

/// El selector de entidad del Home del admin.
///
/// EL FALLO QUE FIJA
///   Con **más de una** entidad el título del AppBar deja de ser una columna y
///   pasa a ser un `DropdownButton`. Y `DropdownButton` pinta el botón **cerrado**
///   con el widget del item seleccionado, no con su `style`: internamente mete
///   los `items` en un `IndexedStack` (`dropdown.dart`, en `build`). Como los
///   items van en `AppTheme.textPrimary` —y tienen que ir así, porque el menú se
///   abre en blanco—, el nombre de la entidad salía **azul marino sobre el
///   degradado primario**: 2.05:1, por debajo del 4.5:1 que pide WCAG AA.
///
///   El `style: _tituloAppBar` (blanco) del `DropdownButton` no podía ganarle:
///   el `DefaultTextStyle` heredado solo rellena lo que el `Text` no fija, y el
///   item fija el color explícitamente.
///
/// LA CURA
///   `selectedItemBuilder`: el botón cerrado se pinta con él (blanco) y el menú
///   sigue usando `items` (oscuro sobre blanco).
///
/// Con una sola entidad la pantalla no usa el desplegable, así que las dos ramas
/// se prueban por separado.
void main() {
  Entidad entidad(int id, String nombre) => Entidad(
    id: id,
    denominacion: nombre,
    ownerUuid: 'uuid-$id',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  Future<void> montar(WidgetTester tester, List<Entidad> entidades) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            // El degradado real: lo que hay debajo del texto del título.
            flexibleSpace: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.primaryDark, AppTheme.primary],
                ),
              ),
            ),
            title: EntidadSelector(
              entidades: entidades,
              seleccionada: entidades.first,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('con varias entidades el nombre se pinta blanco, no azul', (
    tester,
  ) async {
    final entidades = [
      entidad(1, 'Wer'),
      entidad(2, 'Salon Cejas'),
      entidad(3, 'Salon A'),
    ];
    await montar(tester, entidades);

    // `selectedItemBuilder` construye los tres, pero `DropdownButton` los mete
    // en un `IndexedStack`: solo el seleccionado está "onstage". Se mira el
    // árbol entero (`skipOffstage: false`) porque cualquiera de los tres puede
    // pasar a ser el visible al cambiar de entidad.
    for (final e in entidades) {
      final textos = tester.widgetList<Text>(
        find.text(e.denominacion, skipOffstage: false),
      );
      expect(
        textos,
        isNotEmpty,
        reason: '«${e.denominacion}» no está en el selector',
      );
      for (final texto in textos) {
        expect(
          texto.style?.color,
          Colors.white,
          reason:
              '«${e.denominacion}» sale sobre el degradado: debe ir en blanco',
        );
        expect(
          texto.style?.color,
          isNot(AppTheme.textPrimary),
          reason: '«${e.denominacion}» se pintó con el azul del menú',
        );
      }
    }
  });

  testWidgets('el menú desplegable conserva el texto oscuro', (tester) async {
    await montar(tester, [entidad(1, 'Wer'), entidad(2, 'Salon Cejas')]);

    // Se abre el menú: los `items` viven ahora en un overlay blanco, así que
    // ahí el color correcto es `textPrimary` (13.2:1 sobre blanco).
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();

    final delMenu = tester
        .widgetList<Text>(find.text('Salon Cejas'))
        .where((t) => t.style?.color == AppTheme.textPrimary);
    expect(
      delMenu,
      isNotEmpty,
      reason: 'dentro del menú blanco el texto debe seguir siendo oscuro',
    );
  });

  testWidgets('con una sola entidad tampoco aparece el azul', (tester) async {
    await montar(tester, [entidad(1, 'Wer')]);

    final titulo = tester.widget<Text>(find.text('Gestión'));
    expect(titulo.style?.color, Colors.white);

    final nombre = tester.widget<Text>(find.text('Wer'));
    expect(nombre.style?.color, isNot(AppTheme.textPrimary));
  });
}
