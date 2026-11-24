/// Tutorial guiado de la vista de compra.
///
/// El motor vive en [widgets/tutorial_guiado.dart]; este archivo solo conserva
/// los nombres del módulo Compras para no tocar el formulario ni su contrato de
/// pruebas. Cualquier pantalla nueva debería usar `PasoGuiado` /
/// `mostrarTutorialGuiado` directamente.
library;

import 'package:flutter/material.dart';

import '../../widgets/tutorial_guiado.dart';

export '../../widgets/tutorial_guiado.dart'
    show
        AvisoTutorial,
        PasoGuiado,
        insertarAvisoTutorial,
        mostrarTutorialGuiado;

/// Un paso del tutorial de compras. Alias de [PasoGuiado].
typedef PasoTutorialCompra = PasoGuiado;

/// Lanza el recorrido de compras. Alias de [mostrarTutorialGuiado].
Future<bool> mostrarTutorialCompra(
  BuildContext context, {
  required List<PasoTutorialCompra> pasos,
}) => mostrarTutorialGuiado(context, pasos: pasos);

/// Recorrido con velo, anillo de resalte y tarjeta explicativa.
///
/// Se mantiene el nombre por compatibilidad; el cuerpo es [TutorialGuiado].
class TutorialCompra extends StatelessWidget {
  const TutorialCompra({super.key, required this.pasos});

  final List<PasoTutorialCompra> pasos;

  @override
  Widget build(BuildContext context) => TutorialGuiado(pasos: pasos);
}
