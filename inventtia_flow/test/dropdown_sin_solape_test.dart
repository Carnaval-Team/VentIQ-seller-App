import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/config/app_theme.dart';

/// Regresión del punto 2 del plan: en un formulario con valor ya puesto, el
/// **placeholder** y el valor se dibujaban uno encima del otro.
///
/// Causa: los dropdowns de admin usaban `InputDecorator` + `DropdownButton` con
/// un `contentPadding` inventado a mano (`vertical: 4`) y un `isEmpty` calculado
/// aparte. `InputDecorator` coloca la etiqueta flotante y el contenido según ese
/// padding, y `DropdownButton` decide el placeholder por su cuenta: cuando las
/// dos cosas no coinciden, el campo enseña etiqueta flotante y "Seleccionar…"
/// a la vez, en la misma banda.
///
/// La solución es `DropdownButtonFormField`, que toma el `inputDecorationTheme`
/// de la app (`vertical: 14`) y deriva `isEmpty` él solo. Estas pruebas fijan las
/// tres propiedades que sostienen el arreglo: no solapa, el placeholder
/// desaparece cuando hay valor, y el tema mantiene el padding holgado.
void main() {
  testWidgets('con valor, la etiqueta no pisa el valor y no hay placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              child: DropdownButtonFormField<String>(
                initialValue: 'Argentina',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'País',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
                hint: const Text('Seleccionar país'),
                items: const [
                  DropdownMenuItem(
                    value: 'Argentina',
                    child: Text('Argentina'),
                  ),
                  DropdownMenuItem(value: 'Chile', child: Text('Chile')),
                ],
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. El placeholder no se pinta: el campo tiene valor.
    expect(
      find.text('Seleccionar país'),
      findsNothing,
      reason: 'El placeholder no debe convivir con un valor ya seleccionado.',
    );

    // 2. Etiqueta y valor son los dos únicos textos, y no se solapan.
    final etiqueta = tester.getRect(find.text('País'));
    final valor = tester.getRect(find.text('Argentina'));
    expect(
      etiqueta.overlaps(valor),
      isFalse,
      reason:
          'La etiqueta "País" se solapa con el valor ($etiqueta vs $valor). '
          'Revisa el contentPadding del InputDecoration.',
    );
    // La etiqueta flota arriba; el valor va debajo.
    expect(etiqueta.bottom, lessThanOrEqualTo(valor.top + 1));
  });

  testWidgets('sin valor se ve el placeholder y la etiqueta, sin solaparse', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              child: DropdownButtonFormField<String>(
                initialValue: null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'País',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
                hint: const Text('Seleccionar país'),
                items: const [
                  DropdownMenuItem(
                    value: 'Argentina',
                    child: Text('Argentina'),
                  ),
                  DropdownMenuItem(value: 'Chile', child: Text('Chile')),
                ],
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final etiqueta = tester.getRect(find.text('País'));
    final placeholder = tester.getRect(find.text('Seleccionar país'));
    expect(
      etiqueta.overlaps(placeholder),
      isFalse,
      reason: 'Etiqueta y placeholder se solapan ($etiqueta vs $placeholder).',
    );
    expect(etiqueta.bottom, lessThanOrEqualTo(placeholder.top + 1));
  });

  testWidgets('`isDense` no basta para solapar: manda el padding del tema', (
    tester,
  ) async {
    // Muchos campos densos de admin usan `isDense: true` junto a `labelText`.
    // Como `isDense` no toca el `contentPadding`, la etiqueta sigue flotando
    // arriba con el padding del tema.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              child: DropdownButtonFormField<String>(
                initialValue: 'Argentina',
                isExpanded: true,
                isDense: true,
                decoration: const InputDecoration(labelText: 'País'),
                items: const [
                  DropdownMenuItem(
                    value: 'Argentina',
                    child: Text('Argentina'),
                  ),
                  DropdownMenuItem(value: 'Chile', child: Text('Chile')),
                ],
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final etiqueta = tester.getRect(find.text('País'));
    final valor = tester.getRect(find.text('Argentina'));
    expect(etiqueta.overlaps(valor), isFalse, reason: '$etiqueta vs $valor');
  });

  test('el tema mantiene el padding vertical holgado', () {
    // Si alguien "optimiza" el tema, el bug volvería por ahí en vez de por los
    // dropdowns, así que el valor también queda fijado.
    final padding = AppTheme.light.inputDecorationTheme.contentPadding;
    expect(padding, isA<EdgeInsets>());
    expect((padding as EdgeInsets).top, greaterThanOrEqualTo(10));
  });
}
