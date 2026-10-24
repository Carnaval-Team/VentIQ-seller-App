import 'package:flutter/material.dart';

/// Ruta que entra **desde la izquierda**, como un menú lateral.
///
/// POR QUE UNA RUTA Y NO UN `Scaffold.drawer`
///   El panel de categorías se lee como un cajón (entra de izquierda a derecha,
///   deja ver la pantalla de debajo con un velo y se cierra tocando fuera), pero
///   por dentro sigue siendo una ruta. Un `drawer` de verdad no lo es, y eso
///   rompería tres cosas que ya funcionan: el botón atrás del sistema, el
///   «volver al shell» del tutorial (`popUntil`) y el cambio de pestaña de la
///   barra inferior, que cierran lo apilado con el `Navigator`.
///
/// No es opaca: la pantalla de debajo se sigue viendo tras el velo que pinta el
/// propio panel, que es lo que da la sensación de cajón. El velo va DENTRO del
/// panel (y no en `barrierColor`) para que se pueda tocar y cerrar.
class RutaLateral<T> extends PageRouteBuilder<T> {
  RutaLateral({required WidgetBuilder builder})
    : super(
        pageBuilder: (context, _, _) => builder(context),
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 190),
        opaque: false,
        transitionsBuilder: (context, animacion, secundaria, hijo) {
          // Accesibilidad: con las animaciones desactivadas el panel aparece en
          // su sitio, sin deslizarse. (La duración de la transición sigue siendo
          // la misma, como en cualquier `MaterialPageRoute` de la app: lo que se
          // quita es el movimiento, que es lo que molesta.)
          if (MediaQuery.disableAnimationsOf(context)) return hijo;

          final curva = CurvedAnimation(
            parent: animacion,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curva,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(-1, 0),
                end: Offset.zero,
              ).animate(curva),
              child: hijo,
            ),
          );
        },
      );
}
