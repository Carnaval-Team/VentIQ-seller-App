import 'package:flutter/material.dart';

/// Puente entre una pantalla **apilada** y la barra inferior del shell.
///
/// Las cuatro vistas de «Exploración rápida» (categorías, establecimientos, ficha
/// del local y top 10) se empujan SOBRE el shell, así que la `NavigationBar` del
/// `HomeShell` se queda debajo y no se ve. Cada una pinta su propia copia de la
/// barra —la misma, `BarraNavegacionCliente`— y al tocar una pestaña hay que hacer
/// dos cosas: cerrar lo que está apilado y pedirle al shell que cambie de pestaña.
///
/// Ese «pedirle al shell» vive aquí. Lo registra `HomeShell` y las pantallas solo
/// necesitan `ShellNavegacion.irAPestana(context, indice)`; los índices son los del
/// shell del cliente (0 Inicio, 1 Servicios, 2 Mis Listas, 3 Reservas, 4 Perfil),
/// los mismos que usa `HomeShell._onTabSelected`.
///
/// Sin shell detrás (una pantalla montada sola en un test o en una vista previa)
/// `disponible` es `false` y las pantallas no pintan la barra: antes que una barra
/// que no lleva a ningún sitio, ninguna.
class ShellNavegacion {
  ShellNavegacion._();

  static void Function(int indice)? _cambiarPestana;

  // Índices del shell del cliente. Se nombran aquí para que las pantallas no
  // tengan que saberse la lista de pestañas de memoria.
  static const int inicio = 0;
  static const int servicios = 1;
  static const int misListas = 2;
  static const int reservas = 3;
  static const int perfil = 4;

  /// `true` cuando hay un shell escuchando (la pantalla se abrió desde la app).
  static bool get disponible => _cambiarPestana != null;

  static void registrar(void Function(int indice) cambiarPestana) {
    _cambiarPestana = cambiarPestana;
  }

  static void limpiar() {
    _cambiarPestana = null;
  }

  /// Vuelve al shell y cambia de pestaña.
  ///
  /// Primero cierra lo apilado —la ficha, el listado, hojas y diálogos—: si no,
  /// la pestaña nueva quedaría por debajo de la ruta actual y el toque parecería
  /// no hacer nada. Después avisa al shell, que es el único que puede cambiar de
  /// pestaña y refrescar su contenido.
  static void irAPestana(BuildContext context, int indice) {
    // El `Navigator` se captura antes de tocar la pila: el `context` de la
    // pantalla que llama queda desmontado en cuanto se cierra su ruta.
    final navegador = Navigator.of(context, rootNavigator: true);
    navegador.popUntil(
      (ruta) => ruta.isFirst || ruta.settings.name == '/home',
    );
    _cambiarPestana?.call(indice);
  }
}