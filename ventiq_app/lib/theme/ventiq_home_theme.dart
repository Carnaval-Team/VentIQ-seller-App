import 'package:flutter/material.dart';

/// Tokens del Home tipo cliente del TPV.
///
/// Es una réplica de la escala visual del Home de `inventtia_flow` —radios,
/// sombras, pesos y tamaños medidos sobre `widgets/exploracion_rapida_grid.dart`
/// y `config/app_theme.dart` de esa app— pero con la paleta de marca de VentiQ
/// (`#194B8C`, el mismo del icono adaptativo y del tema de `main.dart`) en vez
/// del `#405F90` de GoReserva.
///
/// La intención es que el resultado se sienta de la misma familia que el Home
/// del cliente sin dejar de ser Inventtia Caja: mismos radios, mismos pesos,
/// mismo aire, mismos degradados; distinto azul.
///
/// Todo lo que sea "cuánto mide" o "de qué color es" vive aquí y no repartido
/// por los widgets, para que el rediseño se pueda ajustar en un solo sitio.
class VentiqHomeTheme {
  const VentiqHomeTheme._();

  // ── Marca ────────────────────────────────────────────────────────────────
  /// Azul de marca. Coincide con `adaptive_icon_background` del pubspec y con
  /// la semilla del `ColorScheme` de la app.
  static const Color primary = Color(0xFF194B8C);
  static const Color primaryDark = Color(0xFF123A6E);
  static const Color primaryLight = Color(0xFF2A63AC);

  /// Cian de las acciones de sección ("Ver tienda ›"). Es el `accent` que ya
  /// usa inventtia_flow.
  static const Color accent = Color(0xFF00BCD4);

  // ── Superficies y texto ──────────────────────────────────────────────────
  static const Color surface = Color(0xFFF5F7FA);
  static const Color card = Colors.white;
  static const Color textPrimary = Color(0xFF14224A);
  static const Color textSecondary = Color(0xFF5A6B85);
  static const Color border = Color(0xFFE0E6ED);

  // ── Estados ──────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF43A047);
  static const Color warning = Color(0xFFFB8C00);
  static const Color danger = Color(0xFFE53935);

  // ── Hero (banda superior) ────────────────────────────────────────────────
  /// Degradado vertical de la cabecera. Oscuro arriba para que el blanco del
  /// saludo y del buscador tenga contraste sobrado.
  static const List<Color> heroGradient = <Color>[
    Color(0xFF123A6E),
    Color(0xFF194B8C),
  ];

  /// Color plano de la banda que asoma por detrás del buscador. Tiene que ser
  /// igual al final de [heroGradient] o se ve la costura.
  static const Color heroBand = Color(0xFF194B8C);

  // ── Degradados de tarjeta ────────────────────────────────────────────────
  /// Ocho pares curados, `[inicio, fin]` de `topLeft` a `bottomRight`.
  ///
  /// Se asignan de forma determinista por `id` (ver `categoria_gradiente.dart`)
  /// para que una categoría conserve su color entre sesiones y dispositivos.
  /// Están elegidos para que el blanco de encima pase contraste AA en todo el
  /// recorrido del degradado.
  static const List<List<Color>> cardGradients = <List<Color>>[
    <Color>[Color(0xFF194B8C), Color(0xFF123A6E)], // marca
    <Color>[Color(0xFF4F5C8B), Color(0xFF3B4A7E)], // indigo
    <Color>[Color(0xFF1FA8B8), Color(0xFF1593A3)], // teal
    <Color>[Color(0xFF424A65), Color(0xFF2C3654)], // navy
    <Color>[Color(0xFFFF4E5F), Color(0xFFE8394C)], // coral
    <Color>[Color(0xFF2E9E6B), Color(0xFF1F7A52)], // verde
    <Color>[Color(0xFFD98324), Color(0xFFB36A1A)], // ámbar
    <Color>[Color(0xFF6B4E9E), Color(0xFF4F3A78)], // violeta
  ];

  // ── Radios ───────────────────────────────────────────────────────────────
  static const double radiusCard = 22;
  static const double radiusBlock = 20;
  static const double radiusField = 14;
  static const double radiusTile = 10;
  static const double radiusChip = 8;

  // ── Sombras ──────────────────────────────────────────────────────────────
  /// Sombra canónica de las tarjetas del Home (≈5 % de un azul-negro).
  static const List<BoxShadow> shadowCard = <BoxShadow>[
    BoxShadow(color: Color(0x0D2B3A67), blurRadius: 12, offset: Offset(0, 5)),
  ];

  /// Sombra del buscador: más alta y más difusa para que "flote" sobre la
  /// costura entre el hero y el lienzo.
  static const List<BoxShadow> shadowBuscador = <BoxShadow>[
    BoxShadow(color: Color(0x1A1B2B4D), blurRadius: 22, offset: Offset(0, 9)),
  ];

  /// Sombra de las tarjetas de riel horizontal (más discreta que la canónica).
  static const List<BoxShadow> shadowRiel = <BoxShadow>[
    BoxShadow(color: Color(0x0D2B3A67), blurRadius: 10, offset: Offset(0, 4)),
  ];

  // ── Tipografía ───────────────────────────────────────────────────────────
  /// Rótulo de bloque ("CATEGORÍAS", "EXPLORACIÓN RÁPIDA"): mayúsculas, muy
  /// espaciado. Es un rótulo, no un titular de contenido.
  static const TextStyle rotuloBloque = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.6,
    color: textPrimary,
  );

  /// Acción de sección ("Ver tienda ›").
  static const TextStyle accionSeccion = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w800,
    color: accent,
  );

  /// Titular de sección, cuando hace falta uno de verdad.
  static const TextStyle tituloSeccion = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.2,
    color: textPrimary,
  );

  /// Título dentro de la tarjeta. `height 1.1` y `letterSpacing -0.3` son los
  /// que hacen que 19 px no se vean toscos en una tarjeta de 122 pt.
  static const TextStyle tituloTarjeta = TextStyle(
    fontSize: 19,
    height: 1.1,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
    color: Colors.white,
  );

  static const TextStyle subtituloTarjeta = TextStyle(
    fontSize: 12,
    height: 1.15,
    fontWeight: FontWeight.w500,
    color: Color(0xCCFFFFFF),
  );

  /// Texto del chip superior de la tarjeta. 9 px **no** escala con el tema
  /// porque acompaña al chip, no al contenido; el escalado lo absorbe el
  /// `mainAxisExtent` de la rejilla.
  static const TextStyle chipTarjeta = TextStyle(
    fontSize: 9,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.7,
    color: Colors.white,
  );

  static const TextStyle pieTarjeta = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w800,
    color: Colors.white,
  );

  // ── Layout ───────────────────────────────────────────────────────────────
  /// Separación entre tarjetas de la rejilla (horizontal y vertical).
  static const double gridSpacing = 12;

  /// Padding horizontal estándar de las secciones del Home.
  static const double sectionPadding = 16;

  /// Altura base de una tarjeta de la rejilla.
  static const double cardExtentBase = 122;

  /// Altura de las tarjetas del drawer (llevan chip de contexto más largo).
  static const double cardExtentDrawer = 134;

  /// Alto de la banda del hero, sin contar el `safe area`.
  static const double heroHeight = 190;

  /// Cuánto del buscador se solapa con la banda del hero. Es lo que hace que
  /// la tarjeta blanca "flote" sobre la costura en vez de quedar debajo.
  static const double searchOverlap = 26;

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Alto de tarjeta que respeta el escalado de texto del sistema.
  ///
  /// El original de inventtia_flow documenta por qué se usa `mainAxisExtent` y
  /// no `childAspectRatio`: con texto al 130 % un ratio fijo desborda en
  /// pantallas de 320 pt, y aquí la altura mínima del contenido es conocida.
  static double cardExtent(BuildContext context, {double base = cardExtentBase}) {
    final double escala = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4);
    return base * escala;
  }

  /// El sistema pidió reducir el movimiento. Todas las animaciones del Home
  /// deben consultar esto y caer a `Duration.zero`.
  static bool reduceMotion(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);
}
