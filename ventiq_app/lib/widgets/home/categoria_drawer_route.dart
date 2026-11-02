import 'package:flutter/material.dart';

import '../../theme/ventiq_home_theme.dart';

/// Ruta del drawer de categorías.
///
/// **No** es un `Drawer` de `Scaffold` ni un `showModalBottomSheet`, y las dos
/// decisiones tienen motivo:
///
///  * Un `Scaffold.drawer` se lleva por delante el botón atrás del sistema: con
///    el drawer abierto, "atrás" lo cierra en vez de subir un nivel, y el
///    `popUntil` de cualquier flujo revienta. Es exactamente lo que documenta
///    `inventtia_flow` en su `RutaLateral`, y por eso allí tampoco usan
///    `Drawer`.
///  * Un `showModalBottomSheet` no deja controlar el gesto de arrastre ni el
///    apilar de niveles con la precisión que hace falta aquí.
///
/// La ruta entra **desde abajo** (como una hoja) y ocupa toda la pantalla. Al
/// ser una ruta de verdad, el botón atrás del hardware llega al `PopScope` del
/// drawer, que decide si sube un nivel o cierra.
class CategoriaDrawerRoute<T> extends PageRouteBuilder<T> {
  CategoriaDrawerRoute({
    required WidgetBuilder builder,
    super.settings,
  }) : super(
          opaque: false,
          barrierDismissible: true,
          barrierColor: const Color(0x6B0B1226),
          barrierLabel: 'Cerrar categorías',
          transitionDuration: const Duration(milliseconds: 280),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (BuildContext context, _, __) => builder(context),
          transitionsBuilder: (
            BuildContext context,
            Animation<double> animacion,
            Animation<double> secundaria,
            Widget hijo,
          ) {
            // Con movimiento reducido, aparece y ya está.
            if (VentiqHomeTheme.reduceMotion(context)) return hijo;

            final CurvedAnimation curva = CurvedAnimation(
              parent: animacion,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );

            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(curva),
              child: FadeTransition(
                opacity: Tween<double>(begin: 0.6, end: 1).animate(curva),
                child: hijo,
              ),
            );
          },
        );
}

/// Abre el drawer y devuelve el resultado cuando se cierra.
Future<T?> abrirCategoriaDrawer<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return Navigator.of(context).push<T>(CategoriaDrawerRoute<T>(builder: builder));
}
