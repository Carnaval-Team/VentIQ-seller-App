import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/config/app_theme.dart';

/// Contraste del AppBar del dashboard admin (plan, fase F5).
///
/// **El fallo que se corrigió:** `_EntidadSelector`
/// (`lib/screens/admin/gestion_screen.dart`) pintaba el nombre de la entidad y
/// la flecha con `AppTheme.textPrimary` (#1A237E) directamente sobre el fondo
/// primario del AppBar (#405F90) → **2.05:1**, muy por debajo del 4.5:1 que
/// exige WCAG 2.x AA. Ahora el texto/icono que vive *sobre* la AppBar es blanco
/// (6.45:1 sobre el primario y 9.32:1 sobre el extremo oscuro del degradado) y
/// el `textPrimary` se reserva para *dentro* del desplegable, que se abre en
/// blanco (13.24:1). El mismo par está espejado en
/// `lib/screens/vendedor/vendedor_screen.dart`.
///
/// El test es Dart puro: no toca Supabase, ni red, ni widgets.
const double _umbralAA = 4.5;

/// Linealiza un canal sRGB (0..1) según WCAG 2.x.
double _lineal(double canal) => canal <= 0.03928
    ? canal / 12.92
    : math.pow((canal + 0.055) / 1.055, 2.4).toDouble();

/// Luminancia relativa (WCAG 2.x).
double _luminancia(Color color) =>
    0.2126 * _lineal(color.r) +
    0.7152 * _lineal(color.g) +
    0.0722 * _lineal(color.b);

/// Razón de contraste WCAG 2.x: `(L1 + 0.05) / (L2 + 0.05)`, con L1 la más
/// luminosa. Va de 1:1 (idénticos) a 21:1 (negro sobre blanco).
double razonContraste(Color a, Color b) {
  final la = _luminancia(a);
  final lb = _luminancia(b);
  final claro = math.max(la, lb);
  final oscuro = math.min(la, lb);
  return (claro + 0.05) / (oscuro + 0.05);
}

void main() {
  // `AppTheme.light` construye el `TextTheme` con GoogleFonts, que necesita el
  // binding inicializado (si no: "Binding has not yet been initialized").
  TestWidgetsFlutterBinding.ensureInitialized();

  test('blanco sobre el primario de marca cumple AA (título y acciones)', () {
    final razon = razonContraste(Colors.white, AppTheme.primary);
    expect(
      razon,
      greaterThanOrEqualTo(_umbralAA),
      reason:
          'El título/selector de la AppBar va blanco sobre #405F90; '
          'razón medida: ${razon.toStringAsFixed(2)}:1.',
    );
  });

  test('blanco sobre primaryDark cumple AA (extremo oscuro del degradado)', () {
    final razon = razonContraste(Colors.white, AppTheme.primaryDark);
    expect(
      razon,
      greaterThanOrEqualTo(_umbralAA),
      reason:
          'El flexibleSpace usa el degradado primaryDark → primary; el extremo '
          'oscuro también debe cumplir AA. Razón: ${razon.toStringAsFixed(2)}:1.',
    );
  });

  test('el subtítulo del título (blanco al 82 %) cumple AA', () {
    // `Color.alphaBlend` reproduce lo que hace el motor al pintar un blanco al
    // 82 % encima del fondo: se comprueba el color *resultante*, no el blanco
    // puro, que sería una medida engañosa.
    final subtitulo = Color.alphaBlend(
      Colors.white.withValues(alpha: 0.82),
      AppTheme.primary,
    );
    final razon = razonContraste(subtitulo, AppTheme.primary);
    expect(
      razon,
      greaterThanOrEqualTo(_umbralAA),
      reason:
          'El nombre de la entidad se pinta como subtítulo blanco al 82 %; '
          'razón efectiva: ${razon.toStringAsFixed(2)}:1.',
    );
  });

  test('textPrimary sobre el primario NO cumple AA (el fallo corregido)', () {
    final razon = razonContraste(AppTheme.textPrimary, AppTheme.primary);
    // Se fija el valor medido (~2.05:1) para que el test documente el fallo y
    // avise si alguna vez alguien vuelve a pintar `textPrimary` sobre la AppBar.
    expect(
      razon,
      lessThan(_umbralAA),
      reason:
          'Si esta razón ya cumple AA, actualiza el comentario de '
          'app_theme.dart y el de gestion_screen.dart.',
    );
    expect(razon, closeTo(2.05, 0.05));
  });

  test('textPrimary sobre blanco cumple AA (dentro del desplegable)', () {
    final razon = razonContraste(AppTheme.textPrimary, Colors.white);
    expect(
      razon,
      greaterThanOrEqualTo(_umbralAA),
      reason:
          'El desplegable de entidades se abre con `dropdownColor: '
          'Colors.white` y sus items en textPrimary; '
          'razón: ${razon.toStringAsFixed(2)}:1.',
    );
  });

  test('el tema fija el título del AppBar en blanco, w700 y 18', () {
    final theme = AppTheme.light;
    final appBarTheme = theme.appBarTheme;
    final style = appBarTheme.titleTextStyle;

    expect(style, isNotNull, reason: 'app_theme.dart debe definir titleTextStyle.');
    expect(style!.color, theme.colorScheme.onPrimary);
    expect(style.fontSize, 18);
    expect(style.fontWeight, FontWeight.w700);
    // El fondo del AppBar no cambia: sigue siendo el primario de la semilla.
    expect(appBarTheme.backgroundColor, theme.colorScheme.primary);
    expect(appBarTheme.foregroundColor, theme.colorScheme.onPrimary);
  });
}
