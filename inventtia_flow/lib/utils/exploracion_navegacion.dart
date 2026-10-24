import 'package:flutter/material.dart';

import '../models/establecimiento_resumen.dart';
import '../models/ficha_local.dart';
import '../screens/categorias_screen.dart';
import '../screens/establecimientos_screen.dart';
import '../screens/ficha_local_screen.dart';
import '../screens/top_servicios_screen.dart';
import '../services/campana_service.dart';
import '../services/home_catalog_service.dart';
import 'ruta_lateral.dart';

/// Único mapa de «qué pantalla abre cada atajo de Exploración rápida».
///
/// Lo usan tres sitios distintos: la rejilla del Home, las propias pantallas
/// nuevas (una subcategoría del listado de categorías abre el listado de
/// establecimientos filtrado) y el tutorial del cliente, que navega solo. Si
/// cada uno construyera su `MaterialPageRoute`, el día que cambie un constructor
/// el tutorial abriría otra cosa que el toque del usuario.
class ExploracionNavegacion {
  ExploracionNavegacion._();

  /// Panel lateral de categorías (entra de izquierda a derecha, ver
  /// [RutaLateral]). Dentro: los rubros con su total de locales, «Ver todos» por
  /// rubro y las subcategorías al abrir la carpeta.
  static Future<void> abrirCategorias(BuildContext context) {
    return Navigator.push(
      context,
      RutaLateral<void>(builder: (_) => const CategoriasScreen()),
    );
  }

  /// Listado de establecimientos, opcionalmente filtrado.
  ///
  /// [categoria] incluye sus subcategorías (filtro de servidor); [subcategoria]
  /// manda sobre ella.
  static Future<void> abrirEstablecimientos(
    BuildContext context, {
    HomeCatalogCategory? categoria,
    HomeCatalogCategory? subcategoria,
    String? provincia,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => EstablecimientosScreen(
          categoria: categoria,
          subcategoria: subcategoria,
          provincia: provincia,
        ),
      ),
    );
  }

  /// Ficha del establecimiento: la MISMA vista del espacio patrocinado.
  ///
  /// Se puede pasar una [campana] cuando la ficha viene del espacio patrocinado,
  /// un [establecimiento] del listado agregado, o una [ficha] ya normalizada
  /// (el Home la arma desde su ítem del feed). El listado de establecimientos la
  /// abre sin campaña.
  static Future<void> abrirFicha(
    BuildContext context, {
    EstablecimientoResumen? establecimiento,
    CampanaPatrocinada? campana,
    FichaLocal? ficha,
  }) {
    final cabecera =
        ficha ??
        (establecimiento != null
            ? FichaLocal.desdeEstablecimiento(establecimiento)
            : (campana != null ? FichaLocal.desdeCampana(campana) : null));
    if (cabecera == null) {
      // No debería ocurrir: quien llama tiene uno de los tres.
      return Future<void>.value();
    }
    return Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => FichaLocalScreen(ficha: cabecera, campana: campana),
      ),
    );
  }

  /// Top 10 de servicios (más populares de la semana).
  static Future<void> abrirTopServicios(BuildContext context, {int limite = 10}) {
    return Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => TopServiciosScreen(limite: limite)),
    );
  }
}