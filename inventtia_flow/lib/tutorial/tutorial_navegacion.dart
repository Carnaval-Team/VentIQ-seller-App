import 'package:flutter/material.dart';

import '../models/entidad.dart';
import '../screens/admin/config_categorias_screen.dart';
import '../screens/admin/gestion_locales_screen.dart';
import '../screens/admin/gestion_servicios_screen.dart';
import '../screens/admin/planificacion_screen.dart';
import '../screens/admin/reservas_screen.dart';
import 'tutorial_destino.dart';

/// Traduce el destino de un paso del tutorial en navegación real.
///
/// Lo usan los dos sitios que lanzan el recorrido del admin (el shell, para el
/// primer uso, y la pantalla de «Gestión», para repetirlo): así «Siguiente»
/// lleva al usuario a la pantalla del paso en vez de dejarlo esperando.
///
/// Los destinos del cliente (Home, catálogo y detalle de un servicio) los
/// resuelve el shell, porque son sus pestañas.
class TutorialNavegacion {
  TutorialNavegacion._();

  /// Cierra todo lo que esté apilado sobre el shell (módulos, hojas, diálogos).
  ///
  /// El shell entra con `pushReplacementNamed('/home')`, así que es la primera
  /// ruta; se comprueba también por nombre para que siga funcionando si algún día
  /// se llega a él de otra forma.
  static void volverAlShell(BuildContext context) {
    Navigator.of(context, rootNavigator: true).popUntil(
      (ruta) => ruta.isFirst || ruta.settings.name == '/home',
    );
  }

  /// Abre la pantalla del módulo donde vive el paso.
  ///
  /// [entidad] es la entidad seleccionada: sin ella no hay módulos que abrir.
  static Future<void> irAAdmin(
    BuildContext context,
    Entidad? entidad,
    TutorialDestino destino,
  ) async {
    // Los destinos del cliente no se tocan desde aquí.
    if (destino == TutorialDestino.home ||
        destino == TutorialDestino.catalogo ||
        destino == TutorialDestino.servicio) {
      return;
    }

    // Se parte siempre del shell: evita apilar módulos unos encima de otros
    // cuando el usuario va y viene con «Siguiente» / «Atrás».
    volverAlShell(context);
    // «Gestión» es el propio shell: basta con haber cerrado lo apilado.
    if (destino == TutorialDestino.gestion) return;
    if (entidad == null) return;

    final Widget? pantalla = switch (destino) {
      TutorialDestino.locales => GestionLocalesScreen(entidad: entidad),
      TutorialDestino.servicios => GestionServiciosScreen(entidad: entidad),
      TutorialDestino.serviciosFormulario => GestionServiciosScreen(
        entidad: entidad,
        abrirNuevoAlEntrar: true,
      ),
      TutorialDestino.planificacion => PlanificacionScreen(entidad: entidad),
      TutorialDestino.reservas => ReservasScreen(entidad: entidad),
      TutorialDestino.categorias => ConfigCategoriasScreen(entidad: entidad),
      TutorialDestino.home ||
      TutorialDestino.catalogo ||
      TutorialDestino.servicio ||
      TutorialDestino.gestion =>
        null,
    };
    if (pantalla == null) return;

    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => pantalla),
    );
  }
}
