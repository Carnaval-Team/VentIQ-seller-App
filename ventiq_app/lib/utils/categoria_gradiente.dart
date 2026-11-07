import 'package:flutter/material.dart';

import '../theme/ventiq_home_theme.dart';

/// Degradado estable de una categoría a partir de su `id`.
///
/// "Estable" es el requisito de verdad: la misma categoría tiene que verse del
/// mismo color en la sesión de hoy y en la de dentro de un mes, y en el móvil
/// del vendedor y en el navegador del TPV. Por eso se deriva del `id` y no de
/// nada aleatorio ni de la posición en la lista.
///
/// Antes de esto, el Home coloreaba las tarjetas con un hash del **nombre**
/// (`CategoryService._generateCategoryColor`), así que dos categorías distintas
/// podían compartir color y una renombrada cambiaba de color sola. El `id` es
/// mejor clave: no cambia al renombrar.
List<Color> gradienteCategoria(int id) {
  final int indice = id.abs() % VentiqHomeTheme.cardGradients.length;
  return VentiqHomeTheme.cardGradients[indice];
}

/// Igual que [gradienteCategoria] pero para casos donde solo se tiene el
/// nombre (p. ej. una categoría creada offline que aún no tiene `id`).
///
/// Usa el mismo mecanismo que antes (hash del nombre) para no dejar la tarjeta
/// sin color, pero es un **fallback**: cuando hay `id`, úsalo.
List<Color> gradienteCategoriaPorNombre(String nombre) {
  if (nombre.isEmpty) return VentiqHomeTheme.cardGradients.first;
  final int indice = nombre.toLowerCase().hashCode.abs() %
      VentiqHomeTheme.cardGradients.length;
  return VentiqHomeTheme.cardGradients[indice];
}

/// Paleta completa, expuesta para los tests y para futuros usos (por ejemplo
/// el fondo de reserva de una tarjeta sin imagen).
List<List<Color>> get paletaGradientesCategoria =>
    VentiqHomeTheme.cardGradients;
