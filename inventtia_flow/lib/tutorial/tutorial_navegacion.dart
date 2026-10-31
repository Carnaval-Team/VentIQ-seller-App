import 'package:flutter/material.dart';

import '../models/entidad.dart';
import '../screens/admin/cobros_screen.dart';
import '../screens/admin/config_categorias_screen.dart';
import '../screens/admin/gestion_servicios_screen.dart';
import '../screens/admin/local_servicio_admin_screen.dart';
import '../screens/admin/locales_servicios_screen.dart';
import '../screens/admin/mi_suscripcion_screen.dart';
import '../screens/admin/reservas_screen.dart';
import '../services/catalogo_service.dart';
import '../services/exploracion_service.dart';
import '../utils/exploracion_navegacion.dart';
import 'tutorial_destino.dart';

/// Traduce el destino de un paso del tutorial en navegación real.
///
/// Lo usan los tres sitios que lanzan un recorrido: el shell para el primer uso
/// del cliente y del admin, la pantalla de «Gestión» para repetir el del admin, y
/// el perfil para repetir el del cliente. Así «Siguiente» lleva al usuario a la
/// pantalla del paso en vez de dejarlo esperando.
///
/// Los destinos que son **pestañas** del shell (Home, catálogo y detalle de un
/// servicio) los resuelve el propio shell, porque son suyas; los que son
/// **pantallas apiladas** se resuelven aquí.
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

  /// Abre la pantalla de «Exploración rápida» donde vive el paso del cliente.
  ///
  /// Usa `ExploracionNavegacion`, exactamente las mismas rutas que abren las
  /// tarjetas del Home: si el tutorial abriera por su cuenta otra pantalla, el
  /// paso resaltaría algo que el usuario no puede alcanzar tocando la tarjeta.
  ///
  /// Es «best effort»: si la lectura falla (o falta la migración 57), no navega y
  /// el paso se queda esperando con su burbuja, que es la degradación prevista
  /// —el usuario siempre puede pulsar «Siguiente» o «Saltar»—.
  static Future<void> irACliente(
    BuildContext context,
    TutorialDestino destino,
  ) async {
    // Se capta el navegador antes de cualquier espera: tras un `await` el
    // `context` puede haberse desmontado.
    volverAlShell(context);
    if (!context.mounted) return;

    switch (destino) {
      case TutorialDestino.listaCategorias:
        await ExploracionNavegacion.abrirCategorias(context);
      case TutorialDestino.listaEstablecimientos:
        await ExploracionNavegacion.abrirEstablecimientos(context);
      case TutorialDestino.fichaEstablecimiento:
        // El paso vive en la ficha de un establecimiento concreto: se abre la del
        // primero que tenga servicios publicados.
        try {
          final establecimientos = await ExploracionService.establecimientos();
          if (establecimientos.isEmpty || !context.mounted) return;
          await ExploracionNavegacion.abrirFicha(
            context,
            establecimiento: establecimientos.first,
          );
        } catch (_) {
          // Sin datos no hay ficha que abrir: el paso espera.
        }
      case TutorialDestino.topServicios:
        await ExploracionNavegacion.abrirTopServicios(context);
      case TutorialDestino.home ||
          TutorialDestino.catalogo ||
          TutorialDestino.servicio ||
          TutorialDestino.gestion ||
          TutorialDestino.locales ||
          TutorialDestino.localDetalle ||
          TutorialDestino.servicioLocal ||
          TutorialDestino.servicios ||
          TutorialDestino.serviciosFormulario ||
          TutorialDestino.reservas ||
          TutorialDestino.categorias ||
          TutorialDestino.cobros ||
          TutorialDestino.suscripcion:
        return;
    }
  }

  /// Abre la pantalla del módulo donde vive el paso.
  ///
  /// [entidad] es la entidad seleccionada: sin ella no hay módulos que abrir.
  static Future<void> irAAdmin(
    BuildContext context,
    Entidad? entidad,
    TutorialDestino destino,
  ) async {
    // Los destinos del cliente no se tocan desde aquí (los resuelve
    // `irACliente` y el shell).
    if (destino == TutorialDestino.home ||
        destino == TutorialDestino.catalogo ||
        destino == TutorialDestino.servicio ||
        destino == TutorialDestino.listaCategorias ||
        destino == TutorialDestino.listaEstablecimientos ||
        destino == TutorialDestino.fichaEstablecimiento ||
        destino == TutorialDestino.topServicios) {
      return;
    }

    // Se capta el navegador antes de cualquier espera: tras un `await` el
    // `context` puede haberse desmontado.
    final navegador = Navigator.of(context, rootNavigator: true);

    // Se parte siempre del shell: evita apilar módulos unos encima de otros
    // cuando el usuario va y viene con «Siguiente» / «Atrás».
    volverAlShell(context);
    // «Gestión» es el propio shell: basta con haber cerrado lo apilado.
    if (destino == TutorialDestino.gestion) return;
    if (entidad == null) return;

    final Widget? pantalla = switch (destino) {
      TutorialDestino.locales => LocalesServiciosScreen(entidad: entidad),
      TutorialDestino.localDetalle => await _primerLocal(entidad),
      TutorialDestino.servicioLocal => await _primerServicioLocal(entidad),
      TutorialDestino.servicios => GestionServiciosScreen(entidad: entidad),
      TutorialDestino.serviciosFormulario => GestionServiciosScreen(
        entidad: entidad,
        abrirNuevoAlEntrar: true,
      ),
      TutorialDestino.reservas => ReservasScreen(entidad: entidad),
      TutorialDestino.categorias => ConfigCategoriasScreen(entidad: entidad),
      TutorialDestino.cobros => CobrosScreen(entidad: entidad),
      TutorialDestino.suscripcion => const MiSuscripcionScreen(),
      TutorialDestino.home ||
      TutorialDestino.catalogo ||
      TutorialDestino.servicio ||
      TutorialDestino.gestion ||
      TutorialDestino.listaCategorias ||
      TutorialDestino.listaEstablecimientos ||
      TutorialDestino.fichaEstablecimiento ||
      TutorialDestino.topServicios =>
        null,
    };
    if (pantalla == null) return;

    navegador.push(MaterialPageRoute(builder: (_) => pantalla));
  }

  /// Módulo de locales con el primero ya abierto. Si aún no hay locales se
  /// queda en la lista, donde está el botón para crearlo.
  static Future<Widget> _primerLocal(Entidad entidad) async {
    try {
      final locales = await CatalogoService.getLocalesByEntidad(entidad.id);
      if (locales.isNotEmpty) {
        return LocalesServiciosScreen(
          entidad: entidad,
          idLocalInicial: locales.first.id,
        );
      }
    } catch (_) {
      // Navegar es "best effort": sin datos se abre la lista.
    }
    return LocalesServiciosScreen(entidad: entidad);
  }

  /// Configuración del primer servicio ofrecido en un local. Sin ninguno, el
  /// detalle del primer local, que es donde se añade.
  static Future<Widget> _primerServicioLocal(Entidad entidad) async {
    try {
      final pares = await CatalogoService.getLocalServicios(
        idEntidad: entidad.id,
        incluirInactivos: true,
      );
      if (pares.isNotEmpty) {
        // Se relee completo: el detalle necesita el tipo de actividad.
        final ls = await CatalogoService.getLocalServicio(pares.first.id);
        return LocalServicioAdminScreen(
          localServicio: ls,
          entidadId: entidad.id,
          pestanaInicial: PestanaLocalServicio.configuracion,
        );
      }
    } catch (_) {
      // Sin datos se cae al detalle del local.
    }
    return _primerLocal(entidad);
  }
}
